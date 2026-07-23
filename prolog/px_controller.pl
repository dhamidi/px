:- module(px_controller,
          [ serve_get/4,            % +Controller, +Action, +Env0, -Env
            serve_msg/4,            % +Controller, +Action, +Env0, -Env
            ensure_layout/0
          ]).

/** <module> The controller layer (adr/0029): `:- page(Action, Path)`
and its runtime.

A controller is a feature's boundary module (app/<feature>/
controller.pl) declaring named actions on paths and implementing the
adr/0027 TEA cycle per action:

    model(+Action, +Env, -Model)     load: failure is 404
    view(+Action, +Model, -Html)     pure: template term out
    update(+Msg, +Model0, -Model, -Effects)   messages self-name,
                                              so no action key
    msg(+Env, -Msg)                  optional custom decoder

The controller is the imperative shell: model/3 and update/4 run the
feature's commands (side effects) and compose DOMAIN messages that
the pure model module (app/<feature>/model.pl) folds; view/3
delegates to the feature's views module. px_controller neither knows
nor enforces that split -- the filesystem convention does (adr/0029
decision 1); what it runs is exactly adr/0027's cycle.

`:- page(Action, Path)` / `:- page(Action, Path, [as(Name)])`
expands (like route/resources, adr/0018) into a GET route running
model -> view, message routes for POST/PATCH/PUT/DELETE running
model -> update -> effects, and a reversible path helper. Naming:
as(Name) wins; else the feature (module name minus `_controller`)
for the index action, `<feature>_<action>` otherwise. The helper is
`<name>_path` with the path's parameters in order.

Message decoding (adr/0027 decision 3, extended by adr/0029): the
`_msg` param -- emitted by form_for as a hidden input -- or the
feature's single declared form names the message; `:- form`
declarations are looked up in the controller AND in
`<feature>_messages` (the forms live with the message vocabulary).
A matching form validates first, so update sees Name(ok(Values)) /
Name(invalid(Values, Errors)); a formless message arrives as
Name(Params).

Effects (adr/0027 decision 4, unchanged): redirect(PathTerm),
turbo(Streams), status(Code); unknown effect terms are a domain
error.

ensure_layout/0 (adr/0027 decision 5, unchanged): installs the
framework's mobile-first default document shell at boot when the app
defined no layout/2 template.
*/

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(error)).

%   Sibling imports per adr/0030: the spec is the location.
:- use_module(px_template).
:- use_module(px_env, [respond/3, respond/4, redirect/3, redirect/4,
                       not_found/2, param/3, params/2,
                       env_get/3, put_env/4]).
:- use_module(px_form, [form_result/3]).
:- use_module(px_turbo, [turbo_or_redirect/4, turbo_stream/3]).
:- use_module(px_assets, []).
:- use_module(px_router, []).
:- use_module(router, []).


		 /*******************************
		 *    :- page/2,3 EXPANSION     *
		 *******************************/

:- multifile user:term_expansion/2.

user:term_expansion((:- page(Action, Path)), Expansion) :-
    px_controller:expand_page(Action, Path, [], Expansion).
user:term_expansion((:- page(Action, Path, Opts)), Expansion) :-
    px_controller:expand_page(Action, Path, Opts, Expansion).

%!  expand_page(+Action, +Path, +Opts, -Expansion) is det.
%
%   `:- page(show, "/adr/:id", [as(adr)])` in adrs_controller
%   becomes: the GET route named adr (so path_for(adr, ...) works),
%   one message route per verb (adr_post, ...), the adr_path/1 helper
%   (parameters in path order), and the end-of-load contract checks.
%   Registrations run `now` -- source order is route order (adr/0018).

expand_page(Action, Path, Opts, Expansion) :-
    prolog_load_context(module, M),
    must_be(atom, Action),
    must_be(text, Path),
    must_be(list, Opts),
    page_name(M, Action, Opts, Name),
    path_param_names(Path, ParamNames),
    atom_concat(Name, '_path', Helper),
    length(ParamNames, TermArity),
    helper_clause(Helper, ParamNames, Name, HelperClause),
    msg_registrations(M, Action, Name, Path, MsgRegs),
    append([ [ (:- initialization(px_controller:register_page(M, Action, Name, Path), now)) ],
             MsgRegs,
             [ (:- initialization(px_router:register_path_helper(Helper, TermArity, M), now)),
               HelperClause,
               (:- initialization(px_controller:check_controller(M)))
             ]
           ], Expansion).

%!  page_name(+Module, +Action, +Opts, -Name) is det.
%
%   as(Name) wins; index maps to the bare feature name; anything else
%   is feature_action.

page_name(_, _, Opts, Name) :-
    memberchk(as(Name0), Opts),
    !,
    must_be(atom, Name0),
    Name = Name0.
page_name(M, index, _, Name) :-
    !,
    feature_of(M, Name).
page_name(M, Action, _, Name) :-
    feature_of(M, F),
    atomic_list_concat([F, '_', Action], Name).

%!  feature_of(+Module, -Feature) is det.
%
%   guestbook_controller -> guestbook; a module not following the
%   naming convention is its own feature.

feature_of(M, Feature) :-
    (   atom_concat(Feature0, '_controller', M)
    ->  Feature = Feature0
    ;   Feature = M
    ).

%   ":name" segments, in order -- these are the helper's arguments.
path_param_names(Path, Names) :-
    atomic_list_concat(Segments, '/', Path),
    findall(Name,
            ( member(S, Segments),
              atom_concat(':', Name, S)
            ),
            Names).

%   home_path(P)    :- router:path_for(home, [], P).
%   adr_path(Id, P) :- router:path_for(adr, [id=Id], P).
helper_clause(Helper, ParamNames, RouteName,
              (Head :- router:path_for(RouteName, Pairs, P))) :-
    length(ParamNames, N),
    length(Vars, N),
    maplist([K, V, K=V]>>true, ParamNames, Vars, Pairs),
    append(Vars, [P], Args),
    Head =.. [Helper|Args].

msg_registrations(M, Action, Name, Path, Regs) :-
    findall((:- initialization(px_controller:register_msg_route(M, Action, Name, Verb, Path), now)),
            member(Verb, [post, patch, put, delete]),
            Regs).

%!  register_page(+M, +Action, +Name, +Path) is det.
%!  register_msg_route(+M, +Action, +Name, +Verb, +Path) is det.
%
%   Lowering targets: exactly one v1 add_route/4 call each.

register_page(M, Action, Name, Path) :-
    router:add_route(Name, get, Path, px_controller:serve_get(M, Action)).

register_msg_route(M, Action, Name, Verb, Path) :-
    atomic_list_concat([Name, '_', Verb], RouteName),
    router:add_route(RouteName, Verb, Path, px_controller:serve_msg(M, Action)).

%!  check_controller(+M) is det.
%
%   After the controller file loads: model/3 and view/3 are the
%   contract; missing ones get a warning naming the exact predicate.

check_controller(M) :-
    forall(member(PI, [model/3, view/3]),
           (   PI = F/A,
               current_predicate(M:F/A)
           ->  true
           ;   print_message(warning, px_controller(missing(M, PI)))
           )).

:- multifile prolog:message//1.
prolog:message(px_controller(missing(M, PI))) -->
    [ 'px_controller: controller ~w does not define ~w; define it before the first request'-[M, PI] ].


		 /*******************************
		 *          THE RUNTIME         *
		 *******************************/

%!  serve_get(+M, +Action, +Env0, -Env) is det.
%
%   One read-only cycle: model -> view -> respond. A failing model IS
%   the 404 (adr/0027 decision 2).

serve_get(M, Action, Env0, Env) :-
    (   authorized(M, Action, Env0)
    ->  (   M:model(Action, Env0, Model)
        ->  M:view(Action, Model, Html),
            respond(Env0, Html, Env)
        ;   not_found(Env0, Env)
        )
    ;   deny(Env0, Env)
    ).

%!  serve_msg(+M, +Action, +Env0, -Env) is det.
%
%   One message cycle: decode -> model -> update -> effects. Any
%   stage failing (no decodable message, no model, no matching update
%   clause) is a 404, same as a failing model on GET.

serve_msg(M, Action, Env0, Env) :-
    (   current_predicate(M:update/4),
        decode_msg(M, Env0, Msg)
    ->  (   authorized(M, Msg, Env0)
        ->  (   M:model(Action, Env0, Model0),
                M:update(Msg, Model0, Model, Effects)
            ->  run_effects(Effects, M, Action, Model, Env0, Env)
            ;   not_found(Env0, Env)
            )
        ;   deny(Env0, Env)
        )
    ;   not_found(Env0, Env)
    ).

%!  authorized(+M, +ActionOrMsg, +Env) is semidet.
%!  deny(+Env0, -Env) is det.
%
%   The authorize hook (adr/0035 decision 1): a controller MAY define
%   authorize/2; when it does, failure means "not you" and deny/2
%   answers -- through the multifile denied/2 hook when any clause
%   exists (generated auth code redirects to its sign-in page there),
%   else a plain 403. No authorize/2 = everything is public.
%
%   GET pages authorize on the ACTION (an atom); messages authorize
%   on the decoded MESSAGE TERM (a compound) -- one predicate, clause
%   shape selects. This matters: write messages post to the paths of
%   pages that are often public (destroy posts to show), so guarding
%   by action alone would wave a forged write through a public page.
%   A catch-all `authorize(_, Env) :- require_user(Env).` therefore
%   guards both dimensions at once; a public message is opened by
%   shape: `authorize(create_comment(_), _).`

:- multifile denied/2.
:- dynamic denied/2.

authorized(M, Action, Env) :-
    (   current_predicate(M:authorize/2)
    ->  M:authorize(Action, Env)
    ;   true
    ).

deny(Env0, Env) :-
    (   denied(Env0, Env)
    ->  true
    ;   respond(Env0, "403 Forbidden", [status(403)], Env)
    ).

%!  decode_msg(+M, +Env, -Msg) is semidet.

decode_msg(M, Env, Msg) :-
    current_predicate(M:msg/2),
    !,
    M:msg(Env, Msg).
decode_msg(M, Env, Msg) :-
    msg_name(M, Env, Name),
    (   feature_form(M, Name)
    ->  form_result(Name, Env, Result),
        Msg =.. [Name, Result]
    ;   params(Env, Params),
        Msg =.. [Name, Params]
    ).

%   The `_msg` param names the message; a feature with exactly one
%   declared form (controller + messages module together) needs no
%   `_msg` at all.
msg_name(M, Env, Name) :-
    (   param(Env, '_msg', V)
    ->  to_atom(V, Name)
    ;   findall(N, feature_form(M, N), [Name])
    ).

%!  feature_form(+Controller, ?FormName) is nondet.
%
%   A form belongs to the feature when declared in the controller
%   itself or in the feature's messages module (adr/0029 decision 2).

feature_form(M, Name) :-
    feature_of(M, F),
    atom_concat(F, '_messages', MsgsModule),
    (   Mod = M
    ;   Mod = MsgsModule, Mod \== M
    ),
    px_form:form_definition(Name, Mod, _).

to_atom(V, A) :- atom(V), !, A = V.
to_atom(V, A) :- string(V), !, atom_string(A, V).

%!  run_effects(+Effects, +M, +Action, +Model, +Env0, -Env) is det.

run_effects(Effects, M, Action, Model, Env0, Env) :-
    must_be(list, Effects),
    forall(member(E, Effects), check_effect(E)),
    findall(header(N, V), member(header(N, V), Effects), HeaderOpts),
    (   memberchk(redirect(PathTerm), Effects)
    ->  (   memberchk(turbo(Streams), Effects)
        ->  turbo_or_redirect(Env0, PathTerm, Streams, Env1),
            add_headers(Env1, HeaderOpts, Env)
        ;   redirect(Env0, PathTerm, HeaderOpts, Env)
        )
    ;   memberchk(turbo(Streams), Effects)
    ->  turbo_stream(Env0, Streams, Env1),
        add_headers(Env1, HeaderOpts, Env)
    ;   M:view(Action, Model, Html),
        (   memberchk(status(S), Effects)
        ->  StatusOpts = [status(S)]
        ;   StatusOpts = []
        ),
        append(StatusOpts, HeaderOpts, Opts),
        respond(Env0, Html, Opts, Env)
    ).

%   Fold header effects into an already-built response (the turbo
%   paths construct their own response compounds).
add_headers(Env, [], Env) :- !.
add_headers(Env0, HeaderOpts, Env) :-
    findall(N-V, member(header(N, V), HeaderOpts), Extra),
    env_get(Env0, response, response(S, Hs0, B)),
    append(Hs0, Extra, Hs),
    put_env(Env0, response, response(S, Hs, B), Env).

check_effect(redirect(_)) :- !.
check_effect(turbo(Streams)) :- !, must_be(list, Streams).
check_effect(status(S)) :- !, must_be(integer, S).
check_effect(header(N, V)) :- !, must_be(text, N), must_be(text, V).
check_effect(E) :-
    throw(error(domain_error(px_controller_effect, E),
                context(px_controller:update/4,
                        'effects are redirect(PathTerm), turbo(Streams), status(Code), header(Name, Value)'))).


		 /*******************************
		 *      THE DEFAULT LAYOUT      *
		 *******************************/

%!  ensure_layout is det.
%
%   Boot hook (adr/0027 decision 5): when the loaded app defines no
%   layout/2 template, install the framework default so every page --
%   including px_ui's own demos -- renders a complete, mobile-first
%   document. The clause asserted has exactly the shape `~>` expands
%   to (px_template:tmpl/2, declared dynamic for this).

ensure_layout :-
    (   clause(px_template:tmpl(layout(_, _), _), _)
    ->  true
    ;   assertz((px_template:tmpl(layout(Title, Content), T) :-
                    T = px_default_layout(Title, Content)))
    ).

px_default_layout(Title, Content) ~>
    [ raw("<!DOCTYPE html>\n"),
      html(
        [ head(
            [ meta(charset("utf-8")),
              meta([name(viewport), content("width=device-width, initial-scale=1")]),
              title(Title),
              \px_page_stylesheets,
              \javascript_importmap_tags
            ]),
          body(div(class(page), Content))
        ])
    ].

%   One stylesheet_tag per top-level stylesheet under css/ in the
%   manifest, in name order -- app.css before ui.css, nested
%   directories excluded.
:- multifile px_template:render_helper/2.

px_template:render_helper(px_page_stylesheets, S) :-
    px_controller:write_stylesheets(S).

write_stylesheets(S) :-
    findall(L,
            ( px_assets:manifest_entry(L, _),
              string_concat("css/", Rest, L),
              \+ sub_string(Rest, _, _, _, "/"),
              string_concat(_, ".css", Rest)
            ),
            Ls0),
    sort(Ls0, Ls),
    forall(member(L, Ls), px_assets:stylesheet_tag(L, S)).
