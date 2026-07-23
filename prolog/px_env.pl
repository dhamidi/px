:- module(px_env,
          [ make_env/4,           % +Request, +Stream, +WorkerId, -Env
            % Env accessors (adr/0037): the env is a plain Key-Value
            % pairs list, reached ONLY through these relations -- never
            % destructured directly, so its representation can change
            % without touching a line of app code.
            env_get/3,            % +Env, +Key, -Value        (semidet)
            put_env/4,            % +Env0, +Key, +Value, -Env  (det)
            param/3,              % +Env, +Key, -Value         (semidet)
            params/2,             % +Env, -Pairs               (det)
            header/3,             % +Env, +Name, -Value        (semidet)
            path_id/3,            % +Env, +Key, -IntegerId     (semidet, never throws)
            cookie/3,             % +Env, +Name, -Value        (semidet)
            env_merge_params/3,   % +Env0, +Pairs, -Env
            respond/3,            % +Env0, +Template, -Env
            respond/4,            % +Env0, +Template, +Opts, -Env
            redirect/3,           % +Env0, +PathTerm, -Env
            redirect/4,           % +Env0, +PathTerm, +Opts, -Env
            not_found/2,          % +Env0, -Env
            set_pipeline/1,       % +Goals
            dispatch_env/2,       % +Env0, -Env
            handle_request/3,     % +Request, +Stream, +WorkerId
            write_response/2,     % +Stream, +Env
            eval_path_term/2      % multifile hook: +PathTerm, -PathString
          ]).

/** <module> The Rack-style env layer, per adr/0017 (shapes fixed by
    adr/0016, dict-free per adr/0037).

Every request is one env value, threaded relationally: handlers and
middleware are relations Goal(Env0, Env). The env is a plain list of
`Key-Value` pairs (adr/0037) -- NOT an SWI dict -- reached only through
env_get/3, put_env/4 and the named accessors (param/3, params/2,
header/3, path_id/3, cookie/3). It prints readably (which the
development error console consumes) and pattern-matches. No I/O happens
in the pipeline: the helpers here (respond, redirect, not_found) are
pure put_env/4s, and the only code that writes bytes is the transport
edge, write_response/2, after the pipeline finishes.

The transport (http_stream.pl) hands a request compound
    http_request(Method, Url, Headers, Body)
where Headers is a Name-Value pairs list and Body is the accumulated
body string.

Standardized env keys (adr/0017): method (lowercase atom), path
(string, query stripped, percent-decoded), raw_path (string, as
received), headers (Name-Value string pairs, names lowercased), params
(a Key-Value pairs list: query-string params merged over form-body
params; path params are merged LATER by the router via
env_merge_params/3 and win), body (raw body string), worker (worker
id), config (the atom `px_config`, an accessor marker), response (a
`response(Status, HeaderPairs, Body)` compound, body a template term,
never bytes).
*/

:- use_module(library(uri)).
:- use_module(library(apply)).
:- use_module(library(lists)).

%   eval_path_term(+PathTerm, -PathString) is the reversible-router
%   hook (adr/0018): the router registers clauses that evaluate path
%   helper terms like post_path(7) to their path strings. redirect/3
%   consults it; a plain string/atom path passes through as-is.
:- multifile eval_path_term/2.
:- dynamic eval_path_term/2.

:- (   exists_source(px_template)
   ->  use_module(px_template)
   ;   true
   ).


		 /*******************************
		 *        ENV ACCESSORS         *
		 *******************************/

%!  env_get(+Env, +Key, -Value) is semidet.
%!  put_env(+Env0, +Key, +Value, -Env) is det.
%
%   The two primitives every other accessor is built on. env_get reads
%   the first pair for a ground Key (fails if absent -- never throws);
%   put_env replaces any existing pair for Key and prepends the new
%   one, immutably.

env_get(Env, Key, Value) :-
    memberchk(Key-Value, Env).

put_env(Env0, Key, Value, [Key-Value|Env1]) :-
    (   selectchk(Key-_, Env0, Env1)
    ->  true
    ;   Env1 = Env0
    ).

%!  param(+Env, +Key, -Value) is semidet.
%!  params(+Env, -Pairs) is det.
%!  header(+Env, +Name, -Value) is semidet.

param(Env, Key, Value) :-
    env_get(Env, params, Pairs),
    memberchk(Key-Value, Pairs).

params(Env, Pairs) :-
    env_get(Env, params, Pairs).

header(Env, Name, Value) :-
    env_get(Env, headers, Headers),
    memberchk(Name-Value, Headers).

%!  path_id(+Env, +Key, -Id) is semidet.
%
%   The blessed integer-id reader for path params: the value of Key as
%   an integer, FAILING (never throwing) when the segment is absent or
%   not a number -- so a model/3 clause using it turns
%   /things/notanumber into the 404 its failure contract promises
%   (adr/0027), with no catch/3 boilerplate.

path_id(Env, Key, Id) :-
    param(Env, Key, V),
    (   integer(V)
    ->  Id = V
    ;   catch(number_string(Id, V), _, fail),
        integer(Id)
    ).

%!  cookie(+Env, +Name, -Value) is semidet.
%
%   Value of the named cookie from the request's cookie header
%   (adr/0035): Name an atom, Value a string. Fails when there is no
%   cookie header or no such cookie -- never throws.
cookie(Env, Name, Value) :-
    header(Env, "cookie", Raw),
    split_string(Raw, ";", " \t", Pairs),
    member(Pair, Pairs),
    cookie_pair(Pair, Name, Value),
    !.

cookie_pair(Pair, Name, Value) :-
    once(sub_string(Pair, Before, 1, After, "=")),
    sub_string(Pair, 0, Before, _, NameS),
    atom_string(NameA, NameS),
    NameA == Name,
    sub_string(Pair, _, After, 0, Value).

%!  env_merge_params(+Env0, +Pairs, -Env) is det.
%
%   Merge Pairs into the env's params, Pairs winning on collision. The
%   router calls this with the path params of a matched route, giving
%   path params highest precedence (adr/0017).
env_merge_params(Env0, Pairs, Env) :-
    params(Env0, Ps0),
    foldl(override_param, Pairs, Ps0, Ps),
    put_env(Env0, params, Ps, Env).

override_param(K-V, Ps0, [K-V|Ps1]) :-
    (   selectchk(K-_, Ps0, Ps1)
    ->  true
    ;   Ps1 = Ps0
    ).


		 /*******************************
		 *          BUILDING            *
		 *******************************/

%!  make_env(+Request, +Stream, +WorkerId, -Env) is det.
%
%   Build the initial env from the transport's http_request/4 compound.
%   Stream is accepted for signature stability with the transport edge
%   but not stored: the body arrives as an accumulated string and all
%   writing goes through write_response/2.
make_env(http_request(Method0, Url, Headers0, Body), _Stream, WorkerId, Env) :-
    downcase_atom(Method0, Method),
    to_string(Url, RawPath),
    split_request_target(Url, Path, QueryPairs),
    maplist(lowercase_header, Headers0, Headers),
    form_pairs(Headers, Body, FormPairs),
    params_pairs(FormPairs, QueryPairs, Params),
    Env = [ method-Method,
            path-Path,
            raw_path-RawPath,
            headers-Headers,
            params-Params,
            body-Body,
            worker-WorkerId,
            config-px_config,
            response-response(200, [], none)
          ].

%   Split "/posts/7?utm=news" into the decoded path "/posts/7" and the
%   decoded query pairs [utm=news].
split_request_target(Url, Path, QueryPairs) :-
    uri_components(Url, uri_components(_Scheme, _Auth, Path0, Search, _Frag)),
    (   var(Path0) -> Path1 = '/' ; Path1 = Path0 ),
    uri_encoded(path, Decoded, Path1),
    to_string(Decoded, Path),
    (   nonvar(Search)
    ->  catch(uri_query_components(Search, QueryPairs), _, QueryPairs = [])
    ;   QueryPairs = []
    ).

lowercase_header(Name0-Value0, Name-Value) :-
    to_string(Name0, NameS),
    string_lower(NameS, Name),
    to_string(Value0, Value).

form_pairs(Headers, Body, Pairs) :-
    (   memberchk("content-type"-ContentType, Headers),
        sub_string(ContentType, 0, _, _, "application/x-www-form-urlencoded"),
        string(Body),
        Body \== ""
    ->  catch(uri_query_components(Body, Pairs), _, Pairs = [])
    ;   Pairs = []
    ).

%   One params pairs list, query winning over form on collision (path
%   params win over both -- merged later via env_merge_params/3). Keys
%   are atoms, values strings (adr/0017).
params_pairs(FormPairs, QueryPairs, Params) :-
    foldl(add_param, FormPairs, [], P0),
    foldl(add_param, QueryPairs, P0, Params).

add_param(Name0=Value0, Ps0, [Name-Value|Ps1]) :-
    to_atom(Name0, Name),
    to_string(Value0, Value),
    (   selectchk(Name-_, Ps0, Ps1)
    ->  true
    ;   Ps1 = Ps0
    ).


		 /*******************************
		 *          HELPERS            *
		 *******************************/

%!  respond(+Env0, +Template, -Env) is det.
%!  respond(+Env0, +Template, +Opts, -Env) is det.
%
%   Set the response body to Template (a template term per adr/0019 --
%   never bytes). Opts: status(Code) (default 200), header(N, V) (may
%   repeat).
respond(Env0, Template, Env) :-
    respond(Env0, Template, [], Env).

respond(Env0, Template, Opts, Env) :-
    (   memberchk(status(Code), Opts) -> true ; Code = 200 ),
    findall(N-V, member(header(N, V), Opts), Headers),
    put_env(Env0, response, response(Code, Headers, Template), Env).

%!  redirect(+Env0, +PathTerm, -Env) is det.
%!  redirect(+Env0, +PathTerm, +Opts, -Env) is det.
%
%   303 See Other to PathTerm (evaluated through the eval_path_term/2
%   hook; a plain string/atom passes through). 303 so redirects after
%   non-GET forms behave under Turbo (adr/0024). Opts: header(N, V),
%   may repeat -- sign-in/out carry their set-cookie here (adr/0035).
redirect(Env0, PathTerm, Env) :-
    redirect(Env0, PathTerm, [], Env).

redirect(Env0, PathTerm, Opts, Env) :-
    resolve_path_term(PathTerm, Path),
    findall(N-V, member(header(N, V), Opts), Extra),
    put_env(Env0, response,
            response(303, ["location"-Path|Extra], none), Env).

resolve_path_term(PathTerm, Path) :-
    (   eval_path_term(PathTerm, Path0)
    ->  Path = Path0
    ;   ( atom(PathTerm) ; string(PathTerm) )
    ->  Path = PathTerm
    ;   throw(error(type_error(path_term, PathTerm),
                    context(px_env:redirect/3, 'no eval_path_term/2 clause applies and the term is not a literal path')))
    ).

%!  not_found(+Env0, -Env) is det.
not_found(Env0, Env) :-
    respond(Env0, "404 Not Found", [status(404)], Env).


		 /*******************************
		 *          PIPELINE           *
		 *******************************/

:- dynamic pipeline_goals/1.

%!  set_pipeline(+Goals) is det.
set_pipeline(Goals) :-
    must_be(list, Goals),
    retractall(pipeline_goals(_)),
    assertz(pipeline_goals(Goals)).

%!  dispatch_env(+Env0, -Env) is det.
%
%   Run the stored pipeline over Env0 as a fold of env-relations: a
%   step that FAILS has declined (env flows on unchanged); every
%   element runs. If after the pipeline the response body is still
%   `none` with status 200, nothing handled it -> 404. An exception
%   becomes a 500.
dispatch_env(Env0, Env) :-
    (   pipeline_goals(Goals) -> true ; Goals = [] ),
    catch(run_pipeline(Goals, Env0, Env1),
          Error,
          error_env(Env0, Error, Env1)),
    finalize_env(Env1, Env).

run_pipeline([], Env, Env).
run_pipeline([Step|Steps], Env0, Env) :-
    (   call(Step, Env0, Env1)
    ->  true
    ;   Env1 = Env0
    ),
    run_pipeline(Steps, Env1, Env).

error_env(Env0, Error, Env) :-
    message_to_string(Error, Message),
    format(user_error, "px_env: pipeline error: ~w~n", [Message]),
    format(string(Body), "500 Internal Server Error: ~w", [Message]),
    put_env(Env0, response, response(500, [], Body), Env).

finalize_env(Env0, Env) :-
    env_get(Env0, response, response(Status, _, Body)),
    (   Body == none,
        Status =:= 200
    ->  not_found(Env0, Env)
    ;   Env = Env0
    ).


		 /*******************************
		 *      THE TRANSPORT EDGE     *
		 *******************************/

%!  handle_request(+Request, +Stream, +WorkerId) is det.
handle_request(Request, Stream, WorkerId) :-
    make_env(Request, Stream, WorkerId, Env0),
    dispatch_env(Env0, Env),
    write_response(Stream, Env).

%!  write_response(+Stream, +Env) is det.
%
%   Write status line + headers, then render the body term. Always adds
%   `connection: close` (close-delimited transport) and no
%   content-length. Content-Type defaults to text/html; charset=utf-8
%   unless a header set it. `none` writes nothing;
%   `raw_bytes(Binary)` is the binary escape door (adr/0025 assets):
%   the stream is switched to octet first so iso_latin_1 bytes go out
%   unchanged.
write_response(Stream, Env) :-
    env_get(Env, response, response(Status, Headers, Body)),
    reason_phrase(Status, Reason),
    format(Stream, "HTTP/1.1 ~w ~w\r\n", [Status, Reason]),
    forall(member(Name-Value, Headers),
           format(Stream, "~w: ~w\r\n", [Name, Value])),
    (   Body == none
    ->  true
    ;   has_content_type(Headers)
    ->  true
    ;   format(Stream, "content-type: text/html; charset=utf-8\r\n", [])
    ),
    format(Stream, "connection: close\r\n\r\n", []),
    (   Body == none
    ->  true
    ;   Body = raw_bytes(Binary)
    ->  set_stream(Stream, encoding(octet)),
        write(Stream, Binary)
    ;   px_template:render(Stream, Body)
    ),
    flush_output(Stream).

has_content_type(Headers) :-
    member(Name-_, Headers),
    to_string(Name, NameS),
    string_lower(NameS, "content-type"),
    !.

reason_phrase(Status, Reason) :-
    (   known_reason(Status, Reason0)
    ->  Reason = Reason0
    ;   Reason = "Status"
    ).

known_reason(200, "OK").
known_reason(303, "See Other").
known_reason(403, "Forbidden").
known_reason(404, "Not Found").
known_reason(422, "Unprocessable Content").
known_reason(500, "Internal Server Error").


		 /*******************************
		 *          SMALL BITS         *
		 *******************************/

to_string(Text, String) :-
    text_to_string(Text, String).

to_atom(Text, Atom) :-
    (   atom(Text) -> Atom = Text ; atom_string(Atom, Text) ).
