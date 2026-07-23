/* Milestone 17: the controller layer (prolog/px_controller.pl,
   adr/0027 cycle + adr/0029 actions), standalone --
   no server, no sockets, no database. `:- page(Action, Path, Opts)` is user:
   term_expansion, so it can only be exercised by loading a real page
   MODULE (adr/0027 decision 2: a page is a module); this file writes
   one such fixture module, "widget_page", to a fixed /tmp path at
   startup and loads it with use_module/1 -- exactly the shape a real
   page module under app/pages/ is loaded in, just from /tmp instead.

   The fixture page owns "/widgets/:id", a `rename` form, and three
   formless/effect messages (poke, go, boom) that exercise status,
   redirect and the unknown-effect error without ever touching
   px_query -- widget_page keeps its one row of state in a plain
   dynamic fact, not the database.

   Covers:
     - :- page/2,3 expansion: GET route -> px_controller:serve_get(widget_page, main),
       POST/PATCH/PUT/DELETE routes -> px_controller:serve_msg(widget_page, main),
       the widget_page_path/2 helper resolving through
       px_router:resolve_path_term/2
     - ensure_layout/0: installs the framework default layout when no
       app layout/2 template exists yet (run FIRST, before any test
       renders a page -- every view here calls layout/2, and nothing
       in this file or the facade's own module tree defines it, per
       adr/0027 decision 5)
     - the GET cycle: model -> view -> respond, asserting the
       rendered body carries the model's data
     - a failing model IS a 404 (adr/0027 decision 2)
     - message decoding + forms (adr/0027 decision 3): a `_msg=rename`
       POST validates through the declared form, update sees
       rename(ok(Values)) / rename(invalid(Values,Errors)); a POST
       with no `_msg` at all still decodes to the page's one declared
       form; a `_msg` naming no form decodes to Name(ParamsDict)
     - effects (adr/0027 decision 4): status(Code), redirect(PathTerm)
       -> 303 + location, and an unknown effect term -> domain_error

   Run:  swipl test/milestone17_pages.pl
*/

:- prolog_load_context(directory, Dir),
   asserta(test_dir(Dir)),
   atomic_list_concat([Dir, '/../prolog/prologex'], PrologexLib),
   use_module(PrologexLib).            % also wires the library(...) search path

%   Regression note: px_controller:ensure_layout/0 asserts into
%   px_template:tmpl/2 at runtime, which requires that predicate to be
%   dynamic as well as multifile. Writing this test caught it declared
%   multifile-only -- making the assertz throw permission_error(modify,
%   static_procedure, ...) on any boot where the app defines no layout
%   -- and px_template.pl now declares `:- dynamic tmpl/2.` alongside.
%   The ensure_layout test below is the guard against that regressing.

:- discontiguous test/1.


		 /*******************************
		 *   THE FIXTURE PAGE MODULE   *
		 *******************************/

%   widget_page.pl is written to a fixed /tmp path (never inside the
%   repo) and loaded with use_module/1, so `:- page/3` and `:- form/2`
%   -- both user:term_expansion -- run for real, in their own module,
%   exactly as app/pages/widgets.pl would load.

%   The fixture's model is a plain tagged compound (adr/0037 decision
%   3): page(Id, Name). field_value/3 is reached qualified as
%   px_form:field_value/3 because library(prologex) does not reexport
%   it (only path_id/3 from px_env) -- exactly the mechanical
%   Env.params.id -> path_id/3 / Row.col -> field/3 style migration
%   the ADR calls for, here for a form's Values pairs list.
widget_page_source(Dir, "
:- module(widget_page, []).

:- use_module(library(prologex)).

:- page(main, \"/widgets/:id\", [as(widget_page)]).

:- form(rename, [field(name, text, [required])]).

:- dynamic widget_name/2.
widget_name(7, \"Widget Seven\").

model(main, Env, page(Id, Name)) :-
    path_id(Env, id, Id),
    widget_name(Id, Name).

view(main, page(Id, Name), layout(\"Widget\",
       [ h1([\"Widget #\", Id]),
         p(Name)
       ])).

update(rename(ok(V)), page(Id, _), page(Id, Name), [status(201)]) :-
    px_form:field_value(V, name, Name),
    retractall(widget_name(Id, _)),
    assertz(widget_name(Id, Name)).
update(rename(invalid(V, _Errors)), page(Id, _), page(Id, Name), [status(422)]) :-
    px_form:field_value(V, name, Name).
update(poke(_Params), M, M, [status(204)]).
update(go(_Params), page(Id, Name), page(Id, Name),
       [redirect(widget_page_path(Id))]).
update(boom(_Params), M, M, [nonsense(x)]).
") :- atom(Dir).

fixture_path('/tmp/prologex_milestone17_widget_page.pl').

write_fixture :-
    test_dir(Dir),
    widget_page_source(Dir, Source),
    fixture_path(Path),
    ( exists_file(Path) -> delete_file(Path) ; true ),
    setup_call_cleanup(
        open(Path, write, Out),
        write(Out, Source),
        close(Out)).

:- write_fixture.
:- fixture_path(Path), use_module(Path).


		 /*******************************
		 *            HARNESS           *
		 *******************************/

:- initialization(main, main).

main :-
    Tests = [ page_registers_routes_and_helper,
              ensure_layout_installs_default,
              get_cycle_renders_model,
              model_failure_is_404,
              message_rename_ok_status_201,
              message_rename_invalid_status_422,
              single_form_fallback,
              formless_message_decodes_to_params,
              redirect_effect,
              unknown_effect_is_domain_error
            ],
    run_tests(Tests, 0, Failed),
    length(Tests, N),
    cleanup_fixture,
    (   Failed =:= 0
    ->  format("milestone17_pages: all ~w tests passed~n", [N]),
        halt(0)
    ;   format(user_error, "milestone17_pages: ~w of ~w test(s) FAILED~n",
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

cleanup_fixture :-
    fixture_path(Path),
    ignore(( exists_file(Path), delete_file(Path) )).

contains(Text, Sub) :-
    (   sub_string(Text, _, _, _, Sub)
    ->  true
    ;   format(user_error, "    expected ~q in:~n~q~n", [Sub, Text]),
        fail
    ).


		 /*******************************
		 *          ENV BUILDERS        *
		 *******************************/

%   The adr/0017/0037 request shape px_env:make_env/4 expects (same as
%   milestone11): a bare http_request/4 compound. Query params always
%   parse regardless of method, so a POST's message params ride the
%   URL here rather than the body -- env_merge_params/3 afterwards
%   mimics the router's path-param merge (path params win, as a pairs
%   list), same as route_dispatch/2 would do for real.

fake_request(Method, Url, http_request(Method, Url, [], "")).

widget_env(Method, PathWithQuery, IdParam, Env) :-
    fake_request(Method, PathWithQuery, Request),
    px_env:make_env(Request, user_output, 1, Env0),
    px_env:env_merge_params(Env0, [id-IdParam], Env).

get_env(Path, IdParam, Env)  :- widget_env('GET',  Path, IdParam, Env).
post_env(Path, IdParam, Env) :- widget_env('POST', Path, IdParam, Env).

%   The wire, same idiom as milestone11's capture/3: write_response/2
%   on an in-memory stream over the Env the page produced.
capture_response(Env, Out) :-
    with_output_to(string(Out),
                   ( current_output(S), px_env:write_response(S, Env) )).


		 /*******************************
		 *       :- page/1 EXPANSION    *
		 *******************************/

test(page_registers_routes_and_helper) :-
    router:match_route(get, "/widgets/7", GetHandler, _GetParams),
    GetHandler == px_controller:serve_get(widget_page, main),
    forall(member(Verb, [post, patch, put, delete]),
           (   router:match_route(Verb, "/widgets/7", MsgHandler, _),
               MsgHandler == px_controller:serve_msg(widget_page, main)
           )),
    px_router:resolve_path_term(widget_page_path(7), Path),
    Path == "/widgets/7".


		 /*******************************
		 *         ensure_layout/0      *
		 *******************************/

%   Run BEFORE any test below renders a view: widget_page's view/2
%   calls layout/2 but never defines it, and neither does anything the
%   facade loaded (px_ui calls layout/2 in its own demo pages too, but
%   does not define it either) -- so this is the only thing standing
%   between "no layout/2 template exists yet" and every other test's
%   rendering.
test(ensure_layout_installs_default) :-
    \+ clause(px_template:tmpl(layout(_, _), _), _),
    px_controller:ensure_layout,
    clause(px_template:tmpl(layout(_, _), _), _),
    px_template:render_to_string(layout("T", p("x")), Html),
    contains(Html, "<meta charset"),
    contains(Html, "viewport"),
    contains(Html, "<title>T</title>").


		 /*******************************
		 *          THE GET CYCLE       *
		 *******************************/

test(get_cycle_renders_model) :-
    get_env("/widgets/7", "7", Env0),
    px_controller:serve_get(widget_page, main, Env0, Env),
    px_env:env_get(Env, response, response(200, _, _)),
    capture_response(Env, Out),
    contains(Out, "HTTP/1.1 200 OK"),
    contains(Out, "Widget #7"),
    contains(Out, "Widget Seven").

test(model_failure_is_404) :-
    get_env("/widgets/999", "999", Env0),
    px_controller:serve_get(widget_page, main, Env0, Env),
    px_env:env_get(Env, response, response(404, _, _)),
    capture_response(Env, Out),
    contains(Out, "HTTP/1.1 404 Not Found"),
    contains(Out, "404 Not Found").


		 /*******************************
		 *     MESSAGES + FORMS + EFFECTS *
		 *******************************/

test(message_rename_ok_status_201) :-
    post_env("/widgets/7?_msg=rename&name=Bob", "7", Env0),
    px_controller:serve_msg(widget_page, main, Env0, Env),
    px_env:env_get(Env, response, response(201, _, _)),
    capture_response(Env, Out),
    contains(Out, "HTTP/1.1 201"),
    contains(Out, "Bob"),
    widget_page:widget_name(7, "Bob").             % update really wrote it

test(message_rename_invalid_status_422) :-
    post_env("/widgets/7?_msg=rename&name=", "7", Env0),
    px_controller:serve_msg(widget_page, main, Env0, Env),
    px_env:env_get(Env, response, response(422, _, _)),
    capture_response(Env, Out),
    contains(Out, "HTTP/1.1 422").

%   A page with exactly one declared form needs no `_msg` at all
%   (adr/0027 decision 3).
test(single_form_fallback) :-
    post_env("/widgets/7?name=Carol", "7", Env0),
    \+ px_env:param(Env0, '_msg', _),
    px_controller:serve_msg(widget_page, main, Env0, Env),
    px_env:env_get(Env, response, response(201, _, _)),
    capture_response(Env, Out),
    contains(Out, "Carol"),
    widget_page:widget_name(7, "Carol").

%   `_msg=poke` names no declared form: decode_msg/3 falls to
%   Name(Params) with the raw params pairs list, and update/4's clause
%   for poke/1 has no matching :- form(poke, ...) at all.
test(formless_message_decodes_to_params) :-
    post_env("/widgets/7?_msg=poke&foo=bar", "7", Env0),
    px_controller:decode_msg(widget_page, Env0, Msg),
    Msg = poke(Params),
    is_list(Params),
    memberchk('_msg'-"poke", Params),
    memberchk(foo-"bar", Params),
    px_controller:serve_msg(widget_page, main, Env0, Env),
    px_env:env_get(Env, response, response(204, _, _)),
    capture_response(Env, Out),
    contains(Out, "HTTP/1.1 204").

%   redirect(PathTerm) resolves through the same px_router hook the
%   generated helper uses -- 303 + location, no body rendered.
test(redirect_effect) :-
    post_env("/widgets/7?_msg=go", "7", Env0),
    px_controller:serve_msg(widget_page, main, Env0, Env),
    px_env:env_get(Env, response, response(303, _, _)),
    capture_response(Env, Out),
    contains(Out, "HTTP/1.1 303 See Other"),
    contains(Out, "location: /widgets/7").

%   An effect term outside {redirect/1, turbo/1, status/1} is a
%   domain_error -- typos fail loudly, not silently (adr/0027 decision 4).
test(unknown_effect_is_domain_error) :-
    post_env("/widgets/7?_msg=boom", "7", Env0),
    catch(( px_controller:serve_msg(widget_page, main, Env0, _Env),
            fail
          ),
          error(domain_error(px_controller_effect, nonsense(x)), _),
          true).
