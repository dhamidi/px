:- module(px_page,
          [ serve_get/3,            % +PageModule, +Env0, -Env
            serve_msg/3,            % +PageModule, +Env0, -Env
            ensure_layout/0
          ]).

/** <module> TEA pages (adr/0027): `:- page(Path)` and its runtime.

A page is a module under app/pages/ implementing the Elm Architecture
as ordinary predicates:

    model(+Env, -Model)              init: failure is 404
    view(+Model, -Html)              pure: template term out
    update(+Msg, +Model0, -Model, -Effects)   messages only
    msg(+Env, -Msg)                  optional custom decoder

`:- page(Path)` expands (like route/resources, adr/0018) into route
registrations for GET (model -> view) and POST/PATCH/PUT/DELETE
(model -> update -> effects), a reversible path helper named
`<module>_path` carrying the path's parameters in order, and
end-of-load checks that model/2 and view/2 exist.

Message decoding (adr/0027 decision 3): M:msg/2 when defined; else
the `_msg` param (emitted by form_for as a hidden input) -- or the
page's single declared form -- names the message; a matching
`:- form(Name, ...)` in the page module validates first, so update
sees `Name(ok(Values))` / `Name(invalid(Values, Errors))`; a formless
message arrives as `Name(Params)`.

Effects (adr/0027 decision 4): redirect(PathTerm), turbo(Streams),
status(Code). turbo with redirect is turbo_or_redirect/4 (adr/0024);
turbo alone responds with the stream actions outright; no redirect
means render view(Model), status(Code) defaulting to 200. An unknown
effect term is a domain error -- typos fail loudly, not silently.

ensure_layout/0 (adr/0027 decision 5): called at boot after the app
tree has loaded; when no `layout(Title, Content)` template exists it
installs the framework default -- a mobile-first document shell with
a viewport meta tag, one stylesheet_tag per top-level stylesheet
under css/ in the asset manifest, and the importmap tags.
*/

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(error)).

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/px_template'], TemplateSpec),
   atomic_list_concat([Dir, '/px_env'],      EnvSpec),
   atomic_list_concat([Dir, '/px_form'],     FormSpec),
   atomic_list_concat([Dir, '/px_turbo'],    TurboSpec),
   atomic_list_concat([Dir, '/px_assets'],   AssetsSpec),
   atomic_list_concat([Dir, '/px_router'],   RouterSpec),
   atomic_list_concat([Dir, '/router'],      V1RouterSpec),
   use_module(TemplateSpec),
   use_module(EnvSpec, [respond/3, respond/4, redirect/3, not_found/2]),
   use_module(FormSpec, [form_result/3]),
   use_module(TurboSpec, [turbo_or_redirect/4, turbo_stream/3]),
   use_module(AssetsSpec, []),
   use_module(RouterSpec, []),
   use_module(V1RouterSpec, []).


		 /*******************************
		 *     :- page/1 EXPANSION      *
		 *******************************/

:- multifile user:term_expansion/2.

user:term_expansion((:- page(Path)), Expansion) :-
    px_page:expand_page(Path, Expansion).

%!  expand_page(+Path, -Expansion) is det.
%
%   `:- page("/adr/:id")` in module adr becomes: the GET route (name =
%   module, so path_for(adr, ...) works), one message route per verb,
%   the adr_path/1 helper (parameters in path order), and end-of-load
%   contract checks. Registrations run `now` -- source order is route
%   order, exactly as adr/0018.

expand_page(Path, Expansion) :-
    prolog_load_context(module, M),
    must_be(text, Path),
    path_param_names(Path, ParamNames),
    atom_concat(M, '_path', Helper),
    length(ParamNames, TermArity),
    helper_clause(Helper, ParamNames, M, HelperClause),
    msg_registrations(M, Path, MsgRegs),
    append([ [ (:- initialization(px_page:register_page(M, Path), now)) ],
             MsgRegs,
             [ (:- initialization(px_router:register_path_helper(Helper, TermArity, M), now)),
               HelperClause,
               (:- initialization(px_page:check_page(M)))
             ]
           ], Expansion).

%   ":name" segments, in order -- these are the helper's arguments.
path_param_names(Path, Names) :-
    atomic_list_concat(Segments, '/', Path),
    findall(Name,
            ( member(S, Segments),
              atom_concat(':', Name, S)
            ),
            Names).

%   guestbook_path(P) :- router:path_for(guestbook, [], P).
%   adr_path(Id, P)   :- router:path_for(adr, [id=Id], P).
helper_clause(Helper, ParamNames, M,
              (Head :- router:path_for(M, Pairs, P))) :-
    length(ParamNames, N),
    length(Vars, N),
    maplist([K, V, K=V]>>true, ParamNames, Vars, Pairs),
    append(Vars, [P], Args),
    Head =.. [Helper|Args].

msg_registrations(M, Path, Regs) :-
    findall((:- initialization(px_page:register_msg_route(M, Verb, Path), now)),
            member(Verb, [post, patch, put, delete]),
            Regs).

%!  register_page(+M, +Path) is det.
%!  register_msg_route(+M, +Verb, +Path) is det.
%
%   Lowering targets: exactly one v1 add_route/4 call each, same as
%   px_router:register_route/4.

register_page(M, Path) :-
    router:add_route(M, get, Path, px_page:serve_get(M)).

register_msg_route(M, Verb, Path) :-
    atomic_list_concat([M, '_', Verb], Name),
    router:add_route(Name, Verb, Path, px_page:serve_msg(M)).

%!  check_page(+M) is det.
%
%   After the page file loads: model/2 and view/2 are the contract;
%   missing ones get a warning naming the exact predicate (the
%   check_handler/2 pattern of adr/0018).

check_page(M) :-
    forall(member(PI, [model/2, view/2]),
           (   PI = F/A,
               current_predicate(M:F/A)
           ->  true
           ;   print_message(warning, px_page(missing(M, PI)))
           )).

:- multifile prolog:message//1.
prolog:message(px_page(missing(M, PI))) -->
    [ 'px_page: page ~w does not define ~w; define it before the first request'-[M, PI] ].


		 /*******************************
		 *          THE RUNTIME         *
		 *******************************/

%!  serve_get(+M, +Env0, -Env) is det.
%
%   One read-only TEA cycle: model -> view -> respond. A failing
%   model IS the 404 (adr/0027 decision 2).

serve_get(M, Env0, Env) :-
    (   M:model(Env0, Model)
    ->  M:view(Model, Html),
        respond(Env0, Html, Env)
    ;   not_found(Env0, Env)
    ).

%!  serve_msg(+M, +Env0, -Env) is det.
%
%   One message cycle: decode -> model -> update -> effects. Any
%   stage failing (no decodable message, no model, no matching update
%   clause) is a 404, same as a failing model on GET.

serve_msg(M, Env0, Env) :-
    (   current_predicate(M:update/4),
        decode_msg(M, Env0, Msg),
        M:model(Env0, Model0),
        M:update(Msg, Model0, Model, Effects)
    ->  run_effects(Effects, M, Model, Env0, Env)
    ;   not_found(Env0, Env)
    ).

%!  decode_msg(+M, +Env, -Msg) is semidet.

decode_msg(M, Env, Msg) :-
    current_predicate(M:msg/2),
    !,
    M:msg(Env, Msg).
decode_msg(M, Env, Msg) :-
    msg_name(M, Env, Name),
    (   px_form:form_definition(Name, M, _)
    ->  form_result(Name, Env, Result),
        Msg =.. [Name, Result]
    ;   get_dict(params, Env, Params),
        Msg =.. [Name, Params]
    ).

%   The `_msg` param names the message; a page with exactly one
%   declared form needs no `_msg` at all.
msg_name(M, Env, Name) :-
    get_dict(params, Env, Params),
    (   get_dict('_msg', Params, V)
    ->  to_atom(V, Name)
    ;   findall(N, px_form:form_definition(N, M, _), [Name])
    ).

to_atom(V, A) :- atom(V), !, A = V.
to_atom(V, A) :- string(V), !, atom_string(A, V).

%!  run_effects(+Effects, +M, +Model, +Env0, -Env) is det.

run_effects(Effects, M, Model, Env0, Env) :-
    must_be(list, Effects),
    forall(member(E, Effects), check_effect(E)),
    (   memberchk(redirect(PathTerm), Effects)
    ->  (   memberchk(turbo(Streams), Effects)
        ->  turbo_or_redirect(Env0, PathTerm, Streams, Env)
        ;   redirect(Env0, PathTerm, Env)
        )
    ;   memberchk(turbo(Streams), Effects)
    ->  turbo_stream(Env0, Streams, Env)
    ;   M:view(Model, Html),
        (   memberchk(status(S), Effects)
        ->  respond(Env0, Html, [status(S)], Env)
        ;   respond(Env0, Html, Env)
        )
    ).

check_effect(redirect(_)) :- !.
check_effect(turbo(Streams)) :- !, must_be(list, Streams).
check_effect(status(S)) :- !, must_be(integer, S).
check_effect(E) :-
    throw(error(domain_error(px_page_effect, E),
                context(px_page:update/4,
                        'effects are redirect(PathTerm), turbo(Streams), status(Code)'))).


		 /*******************************
		 *      THE DEFAULT LAYOUT      *
		 *******************************/

%!  ensure_layout is det.
%
%   Boot hook (adr/0027 decision 5): when the loaded app defines no
%   layout/2 template, install the framework default so every page --
%   including px_ui's own demos -- renders a complete, mobile-first
%   document. The clause asserted has exactly the shape `~>` expands
%   to (px_template:tmpl/2 with a T = Body body).

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
%   manifest, in name order -- app.css before ui.css, nested directories
%   (component sources compiled individually, if any) excluded.
:- multifile px_template:render_helper/2.

px_template:render_helper(px_page_stylesheets, S) :-
    px_page:write_stylesheets(S).

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
