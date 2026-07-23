/* Milestone 12: router v2 (px_router.pl, adr/0018), standalone -- no
   HTTP server, no sockets.  This file itself plays the app: it
   declares `:- resources(widgets)` and a custom
   `:- route(get, "/about", about)` at load time (both expanded by
   px_router's user:term_expansion/2, module captured = user), defines
   the handlers as Env0->Env relations using px_env:respond/3, and
   then drives fake env dicts through the pipeline elements.

   Covers:
     - dispatch: GET /widgets -> index, GET /widgets/7 -> show with
       params.id == "7" (path param merged, string value), the custom
       route GET /about -> about
     - ordering: GET /widgets/new -> new, NOT show with id=new
     - method override: POST /widgets/7 with params._method=delete is
       rewritten to delete (raw method preserved) and dispatches to
       destroy; a GET with _method is NOT overridden
     - helpers: widget_path(7, P) == "/widgets/7", plus widgets_path,
       new_widget_path, edit_widget_path
     - hooks: px_env:eval_path_term/2 and px_template:eval_attr_value/2
       resolve widget_path(7), the bare atom new_widget_path, and
       path_for(Name, Params) terms; px_env:redirect/3 accepts a
       helper term
     - reverse routing: router:path_for/3 still works on the generated
       routes, and match_route -> path_for round-trips
     - decline: no matching route -> route_dispatch/2 fails

   Run:  swipl test/milestone12_router.pl
*/

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../prolog/px_router'], PxRouterLib),
   use_module(PxRouterLib).

:- discontiguous test/1.

		 /*******************************
		 *       THE "APP" UNDER TEST   *
		 *******************************/

:- route(get, "/about", about).
:- resources(widgets).

about(Env0, Env) :-
    px_env:put_env(Env0, handled, about, Env1),
    px_env:respond(Env1, "about page", Env).

index(Env0, Env) :-
    px_env:put_env(Env0, handled, index, Env1),
    px_env:respond(Env1, "widget index", Env).

new(Env0, Env) :-
    px_env:put_env(Env0, handled, new, Env1),
    px_env:respond(Env1, "new widget form", Env).

create(Env0, Env) :-
    px_env:put_env(Env0, handled, create, Env1),
    px_env:respond(Env1, "created", Env).

show(Env0, Env) :-
    px_env:param(Env0, id, Id),
    px_env:put_env(Env0, handled, show, Env1),
    px_env:respond(Env1, show_page(Id), Env).

edit(Env0, Env) :-
    px_env:put_env(Env0, handled, edit, Env1),
    px_env:respond(Env1, "edit widget form", Env).

update(Env0, Env) :-
    px_env:put_env(Env0, handled, update, Env1),
    px_env:respond(Env1, "updated", Env).

destroy(Env0, Env) :-
    px_env:put_env(Env0, handled, destroy, Env1),
    px_env:respond(Env1, "destroyed", Env).

		 /*******************************
		 *          HARNESS            *
		 *******************************/

:- initialization(main, main).

main :-
    Tests = [ dispatch_index,
              dispatch_show_merges_path_params,
              dispatch_custom_route,
              new_routes_before_show,
              method_override_rewrites_post,
              method_override_dispatches_to_destroy,
              method_override_ignores_get,
              method_override_ignores_bogus_target,
              helper_predicates,
              eval_path_term_hook,
              eval_attr_value_hook,
              redirect_accepts_helper_term,
              reverse_path_for_and_roundtrip,
              no_match_declines,
              link_to_bare_atom_helper_resolves,
              link_to_bare_atom_non_helper_stays_literal
            ],
    run_tests(Tests, 0, Failed),
    length(Tests, N),
    (   Failed =:= 0
    ->  format("milestone12_router: all ~w tests passed~n", [N]),
        halt(0)
    ;   format(user_error, "milestone12_router: ~w of ~w test(s) FAILED~n",
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

%   A fake env, the adr/0017/0037 shape px_env:make_env/4 builds -- a
%   plain Key-Value pairs list, built by hand here because this test
%   exercises the router layer alone, with no transport and no HTTP
%   parsing. Params is itself a pairs list.
fake_env(Method, Path, Params,
         [ method-Method,
           path-Path,
           raw_path-Path,
           headers-[],
           params-Params,
           body-"",
           worker-1,
           config-px_config,
           response-response(200, [], none)
         ]).

		 /*******************************
		 *           TESTS             *
		 *******************************/

test(dispatch_index) :-
    fake_env(get, "/widgets", [], Env0),
    route_dispatch(Env0, Env),
    px_env:env_get(Env, handled, index),
    px_env:env_get(Env, response, response(200, _, "widget index")).

test(dispatch_show_merges_path_params) :-
    % Query param id=999 is present; the path param must win, and the
    % merged value is a string (adr/0017).
    fake_env(get, "/widgets/7", [id-"999", utm-"news"], Env0),
    route_dispatch(Env0, Env),
    px_env:env_get(Env, handled, show),
    px_env:param(Env, id, "7"),           % path param beat the query param
    px_env:param(Env, utm, "news"),       % other params ride along
    px_env:env_get(Env, response, response(_, _, show_page("7"))).

test(dispatch_custom_route) :-
    fake_env(get, "/about", [], Env0),
    route_dispatch(Env0, Env),
    px_env:env_get(Env, handled, about).

test(new_routes_before_show) :-
    % Rails ordering: /widgets/new is registered before /widgets/:id,
    % so it reaches new/2, not show/2 with id=new.
    fake_env(get, "/widgets/new", [], Env0),
    route_dispatch(Env0, Env),
    px_env:env_get(Env, handled, new),
    \+ px_env:param(Env, id, _).

test(method_override_rewrites_post) :-
    fake_env(post, "/widgets/7", ['_method'-"delete"], Env0),
    method_override(Env0, Env),
    px_env:env_get(Env, method, delete),
    px_env:env_get(Env, raw_method, post).

test(method_override_dispatches_to_destroy) :-
    % The full two-element chain: override, then dispatch.
    fake_env(post, "/widgets/7", ['_method'-"delete"], Env0),
    method_override(Env0, Env1),
    route_dispatch(Env1, Env),
    px_env:env_get(Env, handled, destroy),
    px_env:param(Env, id, "7").

test(method_override_ignores_get) :-
    % _method on anything but POST is ignored.
    fake_env(get, "/widgets/7", ['_method'-"delete"], Env0),
    method_override(Env0, Env),
    px_env:env_get(Env, method, get),
    \+ px_env:env_get(Env, raw_method, _).

test(method_override_ignores_bogus_target) :-
    % A form cannot smuggle itself into being a GET or invent methods.
    fake_env(post, "/widgets/7", ['_method'-"get"], Env0),
    method_override(Env0, Env),
    px_env:env_get(Env, method, post),
    fake_env(post, "/widgets/7", ['_method'-"teapot"], Env1),
    method_override(Env1, Env2),
    px_env:env_get(Env2, method, post).

test(helper_predicates) :-
    % The four generated helpers, callable as ordinary predicates in
    % this (the declaring) module.
    widgets_path(P1),          P1 == "/widgets",
    widget_path(7, P2),        P2 == "/widgets/7",
    new_widget_path(P3),       P3 == "/widgets/new",
    edit_widget_path(3, P4),   P4 == "/widgets/3/edit",
    % ... and recorded in the framework table (term arity = helper
    % arity minus one), in this module.
    px_router:path_helper(widget_path, 1, user),
    px_router:path_helper(widgets_path, 0, user).

test(eval_path_term_hook) :-
    px_env:eval_path_term(widget_path(7), P1),      P1 == "/widgets/7",
    px_env:eval_path_term(new_widget_path, P2),     P2 == "/widgets/new",  % bare-atom 0-arity form
    px_env:eval_path_term(path_for(widgets_show, [id=9]), P3),
    P3 == "/widgets/9",
    px_env:eval_path_term(path_for(about, []), P4), P4 == "/about",
    % A term matching no helper is NOT a path expression: the hook
    % declines (fails) rather than stringifying.
    \+ px_env:eval_path_term(bogus_path(7), _).

test(eval_attr_value_hook) :-
    px_template:eval_attr_value(widget_path(7), P1),  P1 == "/widgets/7",
    px_template:eval_attr_value(edit_widget_path(3), P2),
    P2 == "/widgets/3/edit",
    px_template:eval_attr_value(path_for(widgets_index, []), P3),
    P3 == "/widgets",
    \+ px_template:eval_attr_value(id(post-7), _).    % non-path attrs decline

test(redirect_accepts_helper_term) :-
    % redirect/3 goes through the eval_path_term hook (adr/0017).
    fake_env(post, "/widgets", [], Env0),
    px_env:redirect(Env0, widget_path(5), Env),
    px_env:env_get(Env, response, response(303, Headers, _)),
    memberchk("location"-"/widgets/5", Headers).

test(reverse_path_for_and_roundtrip) :-
    % v1 reverse routing still works on the generated routes...
    router:path_for(widgets_show, [id='7'], P1),  P1 == "/widgets/7",
    router:path_for(widgets_index, [], P2),       P2 == "/widgets",
    router:path_for(widgets_edit, [id=abc], P3),  P3 == "/widgets/abc/edit",
    router:path_for(about, [], P4),               P4 == "/about",
    % ... including the PATCH/PUT pair for update (canonical name on
    % the PATCH fact, alias on the PUT fact)...
    router:path_for(widgets_update, [id=1], "/widgets/1"),
    router:path_for(widgets_update_put, [id=1], "/widgets/1"),
    % ... and the adr/0009 round-trip: match, then rebuild from the
    % extracted params.
    router:match_route(get, "/widgets/42", Handler, Params),
    Handler == user:show,
    router:path_for(widgets_show, Params, P5),
    P5 == "/widgets/42".

test(no_match_declines) :-
    fake_env(get, "/nope", [], EnvA),
    \+ route_dispatch(EnvA, _),
    fake_env(patch, "/widgets", [], EnvB),        % wrong method for /widgets
    \+ route_dispatch(EnvB, _),
    fake_env(get, "/widgets/7/edit/x", [], EnvC),
    \+ route_dispatch(EnvC, _).

%   Regression (the "Sign the guestbook" bug): link_to's PathTerm arg
%   is a bare ATOM when the app writes a zero-arity path helper with
%   no parens (comments_path, not comments_path()) -- px_template's
%   write_attr_value/2 used to route only COMPOUND attribute values
%   through eval_attr_value/2, so the atom was never offered to the
%   router's hook and came out as a literal href="widgets_path".  An
%   atom naming a REGISTERED helper (widgets_path/0, generated by the
%   `:- resources(widgets)` directive at the top of this file) must
%   now resolve exactly like the compound form does.
test(link_to_bare_atom_helper_resolves) :-
    px_template:render_to_string(link_to("Sign the guestbook", widgets_path), S),
    S == "<a href=\"/widgets\">Sign the guestbook</a>".

%   An atom that does NOT name a registered helper is not a path
%   expression -- it must still fall back and render literally, same
%   as before this fix (and same as an unresolved compound falls back
%   to operator notation).
test(link_to_bare_atom_non_helper_stays_literal) :-
    px_template:render_to_string(link_to("x", not_a_helper_atom), S),
    S == "<a href=\"not_a_helper_atom\">x</a>".
