/* Milestone 11: the Rack-style env layer (px_env.pl, adr/0017) and
   the config subsystem (px_config.pl + config/app.pl, adr/0022),
   standalone -- no sockets. A fake v1 request compound (the exact
   shape http_stream.pl builds: http_request(Method, Url, Headers,
   Body), adr/0037) goes through px_env:handle_request/3 against an
   in-memory output stream, and the written bytes are asserted on.

   Covers:
     - config: base facts, env('PORT', Default) resolution with typing
       (numeric strings -> numbers), production overlay + base
       fallback, facts with bodies, require_config/2 throwing on a
       missing key, current_env/1 default
     - env: make_env/4 key shapes, params merging (query over form,
       urlencoded body parsed only under the right content-type),
       env_merge_params/3 (path params win)
     - pipeline: a logger middleware that adds a key, a fake router
       that respond/3-s for "/hi", 404 conversion when every element
       declines, exception -> 500, redirect/3 -> 303 + location for a
       literal path string, declined (failing) middleware skipped
     - the wire: status line, connection: close, no content-length,
       default content-type, rendered body

   Rendering: uses the real px_template:render/2 (adr/0019) when
   prolog/px_template.pl exists; otherwise a clearly-marked local
   STUB render (strings written verbatim) is asserted so the edge can
   still be exercised.

   Run:  swipl test/milestone11_env.pl
*/

:- prolog_load_context(directory, Dir),
   asserta(test_dir(Dir)),
   atomic_list_concat([Dir, '/../prolog/px_env'], PxEnvLib),
   atomic_list_concat([Dir, '/../prolog/px_config'], PxConfigLib),
   use_module(PxEnvLib),
   use_module(PxConfigLib).

:- discontiguous test/1.

:- initialization(main, main).

main :-
    ensure_render_backend,
    load_repo_config,
    Tests = [ config_defaults,
              config_env_var_typing,
              config_production_overlay,
              config_rule_body,
              require_config_missing,
              env_shape,
              env_params_merging,
              env_merge_params_path_wins,
              pipeline_hit,
              pipeline_declined_all_is_404,
              pipeline_exception_is_500,
              pipeline_redirect
            ],
    run_tests(Tests, 0, Failed),
    length(Tests, N),
    (   Failed =:= 0
    ->  format("milestone11_env: all ~w tests passed~n", [N]),
        halt(0)
    ;   format(user_error, "milestone11_env: ~w of ~w test(s) FAILED~n",
               [Failed, N]),
        halt(1)
    ).

run_tests([], Failed, Failed).
run_tests([T|Ts], Failed0, Failed) :-
    (   catch(test(T), Error,
              ( print_message(error, Error), fail ))
    ->  format("  ok: ~w~n", [T]),
        Failed1 = Failed0
    ;   format(user_error, "  FAILED: ~w~n", [T]),
        Failed1 is Failed0 + 1
    ),
    run_tests(Ts, Failed1, Failed).

%   Use the real template renderer when it exists; otherwise stub it,
%   loudly. The interface is fixed: px_template:render(Stream, Term).
ensure_render_backend :-
    (   current_predicate(px_template:render/2)
    ->  format(user_error,
               "milestone11: rendering via the REAL px_template~n", [])
    ;   format(user_error,
               "milestone11: prolog/px_template.pl not found -- using a local STUB render (strings verbatim)~n",
               []),
        assertz((px_template:render(Stream, Term) :-
                    (   string(Term) -> write(Stream, Term)
                    ;   atom(Term)   -> write(Stream, Term)
                    ;   print(Stream, Term)
                    )))
    ).

load_repo_config :-
    repo_config_path(Path),
    px_config:load_config(Path).

repo_config_path(Path) :-
    test_dir(Dir),
    atomic_list_concat([Dir, '/../config/app.pl'], Path).


		 /*******************************
		 *        CONFIG TESTS         *
		 *******************************/

test(config_defaults) :-
    clear_env('PORT'),
    clear_env('PROLOGEX_ENV'),
    px_config:current_env(development),
    px_config:config(port, 8090),          % env('PORT', 8090), PORT unset
    px_config:config(workers, 2),
    px_config:config(database, DB),
    DB == "data/prologex.db".

test(config_env_var_typing) :-
    setenv('PORT', '8091'),
    px_config:config(port, Port),
    clear_env('PORT'),
    Port == 8091.                          % a number, not '8091' text

test(config_production_overlay) :-
    %   The production overlay for `database` is env-driven
    %   (env('DATABASE_PATH', "data/prologex.db")): a real deploy sets
    %   DATABASE_PATH, this sandbox keeps the writable local default
    %   (adr/0022, config/app.pl).  Set it here to prove the overlay
    %   is active under production and resolves the env value.
    setenv('PROLOGEX_ENV', production),
    setenv('DATABASE_PATH', '/srv/app/prod.db'),
    px_config:current_env(production),
    px_config:config(database, DB),
    px_config:config(port, Port),          % no production overlay: base
    clear_env('DATABASE_PATH'),
    clear_env('PROLOGEX_ENV'),
    atom_string(DB, "/srv/app/prod.db"),   % production overlay + env resolution
                                           % (a set env var resolves to an atom)
    Port == 8090,
    px_config:config(database, DevDB),     % back in development
    DevDB == "data/prologex.db".

test(config_rule_body) :-
    tmp_file_stream(text, TmpPath, TmpOut),
    format(TmpOut, "config(port, 1234).~n", []),
    format(TmpOut, "config(cpus, N) :- current_prolog_flag(cpu_count, N).~n", []),
    close(TmpOut),
    px_config:load_config(TmpPath),
    px_config:config(port, 1234),
    px_config:config(cpus, Cpus),
    integer(Cpus), Cpus >= 1,
    delete_file(TmpPath),
    load_repo_config.                      % restore for later tests

test(require_config_missing) :-
    px_config:require_config(port, 8090),  % present: behaves as config/2
    catch(( px_config:require_config(definitely_absent_key, _),
            fail
          ),
          error(existence_error(prologex_config, definitely_absent_key),
                context(_, Message)),
          true),
    contains(Message, "definitely_absent_key"),
    contains(Message, "config/app.pl").


		 /*******************************
		 *          ENV TESTS          *
		 *******************************/

fake_request(Method, Url, Headers, Body,
             http_request(Method, Url, Headers, Body)).

capture(Request, WorkerId, Out) :-
    with_output_to(string(Out),
                   ( current_output(Stream),
                     px_env:handle_request(Request, Stream, WorkerId) )).

contains(Text, Sub) :-
    (   sub_string(Text, _, _, _, Sub)
    ->  true
    ;   format(user_error, "    expected ~q in:~n~q~n", [Sub, Text]),
        fail
    ).

lacks(Text, Sub) :-
    (   sub_string(Text, _, _, _, Sub)
    ->  format(user_error, "    did NOT expect ~q in:~n~q~n", [Sub, Text]),
        fail
    ;   true
    ).

test(env_shape) :-
    fake_request('GET', "/posts/7?utm=news",
                 ["Host"-"example.org", "Accept"-"text/html"],
                 "", Request),
    px_env:make_env(Request, user_output, 2, Env),
    is_list(Env),
    env_get(Env, method, get),
    env_get(Env, path, "/posts/7"),
    env_get(Env, raw_path, "/posts/7?utm=news"),
    env_get(Env, headers, ["host"-"example.org", "accept"-"text/html"]),
    param(Env, utm, "news"),
    env_get(Env, body, ""),
    env_get(Env, worker, 2),
    env_get(Env, config, px_config),       % accessor marker, no snapshot
    env_get(Env, response, response(200, [], none)).

test(env_params_merging) :-
    % Query params win over form params; form body parsed only when
    % the request is urlencoded.
    fake_request('POST', "/params?a=1&b=two",
                 ["Host"-"x",
                  "Content-Type"-"application/x-www-form-urlencoded"],
                 "b=formb&c=three", Request),
    px_env:make_env(Request, user_output, 1, Env),
    param(Env, a, "1"),
    param(Env, b, "two"),                  % query beats form
    param(Env, c, "three"),                % form-only key present
    % Same body, but not form-encoded: body must NOT be parsed.
    fake_request('POST', "/params", ["Content-Type"-"text/plain"],
                 "b=formb&c=three", Request2),
    px_env:make_env(Request2, user_output, 1, Env2),
    \+ param(Env2, c, _),
    env_get(Env2, body, "b=formb&c=three").

test(env_merge_params_path_wins) :-
    fake_request('GET', "/posts/7?id=999&utm=news", [], "", Request),
    px_env:make_env(Request, user_output, 1, Env0),
    param(Env0, id, "999"),
    px_env:env_merge_params(Env0, [id-"7"], Env),  % the router's call
    param(Env, id, "7"),                   % path param wins
    param(Env, utm, "news").               % others ride along


		 /*******************************
		 *       PIPELINE TESTS        *
		 *******************************/

%   A tiny pipeline: a logger middleware that adds a key, a middleware
%   that always declines (fails), and a fake router that
%   pattern-matches the path. All are Env0->Env relations; the fake
%   router uses only the public helpers.

logger(Env0, Env) :-
    put_env(Env0, logged, true, Env).

always_declines(_Env0, _Env) :-
    fail.

fake_router(Env0, Env) :-
    env_get(Env0, path, Path),
    (   Path == "/hi"
    ->  px_env:respond(Env0, "hello world", Env)
    ;   Path == "/go"
    ->  px_env:redirect(Env0, "/hi", Env)
    ;   Path == "/boom"
    ->  throw(error(deliberate_boom,
                    context(fake_router/2, "always throws, on purpose")))
    ;   fail                               % declined: no route matched
    ).

set_test_pipeline :-
    px_env:set_pipeline([ user:logger,
                          user:always_declines,
                          user:fake_router
                        ]).

test(pipeline_hit) :-
    set_test_pipeline,
    fake_request('GET', "/hi?x=1", ["Host"-"example.org"], "", Request),
    % Relational check: middleware-added key survives the whole fold.
    px_env:make_env(Request, user_output, 3, Env0),
    px_env:dispatch_env(Env0, Env),
    env_get(Env, logged, true),
    env_get(Env, response, response(200, _, _)),
    % Wire check.
    capture(Request, 3, Out),
    contains(Out, "HTTP/1.1 200 OK\r\n"),
    contains(Out, "connection: close\r\n"),
    contains(Out, "content-type: text/html; charset=utf-8\r\n"),
    contains(Out, "hello world"),
    lacks(Out, "content-length").          % close-delimited, adr/0007

test(pipeline_declined_all_is_404) :-
    set_test_pipeline,
    fake_request('GET', "/nope", [], "", Request),
    capture(Request, 1, Out),
    contains(Out, "HTTP/1.1 404 Not Found\r\n"),
    contains(Out, "connection: close\r\n"),
    contains(Out, "404 Not Found").

test(pipeline_exception_is_500) :-
    set_test_pipeline,
    fake_request('GET', "/boom", [], "", Request),
    capture(Request, 1, Out),
    contains(Out, "HTTP/1.1 500 Internal Server Error\r\n"),
    contains(Out, "connection: close\r\n"),
    contains(Out, "500 Internal Server Error").

test(pipeline_redirect) :-
    set_test_pipeline,
    fake_request('POST', "/go", [], "", Request),
    capture(Request, 1, Out),
    contains(Out, "HTTP/1.1 303 See Other\r\n"),
    contains(Out, "location: /hi\r\n"),
    contains(Out, "connection: close\r\n"),
    % body is none: nothing after the header/body separator.
    sub_string(Out, Sep, 4, After, "\r\n\r\n"), !,
    After == 0,
    Sep > 0.

clear_env(Name) :-
    (   getenv(Name, _) -> unsetenv(Name) ; true ).
