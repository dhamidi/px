:- module(px_router,
          [ route_dispatch/2,     % +Env0, -Env   (pipeline element)
            method_override/2,    % +Env0, -Env   (pipeline element)
            path_helper/3,        % ?Functor, ?TermArity, ?Module
            resolve_path_term/2   % +PathTerm, -PathString
          ]).

/** <module> Router v2: route/3 + resources/1,2 directives and path
    helpers, per adr/0018 (surface fixed by adr/0016, env shapes by
    adr/0017).

This module is a term-expansion layer over the UNCHANGED v1 engine
(prolog/router.pl, adr/0009): the directives below are sugar that
lowers onto router:add_route/4, and every generated path helper is a
one-line veneer over router:path_for/3.  There is no second matcher,
no second path builder, no new route store.

Directives (expanded via user:term_expansion/2; both capture the
defining module M with prolog_load_context(module, M) -- adr/0016
rule 7, app code never writes `mymodule:handler`):

    :- route(Method, Path, Handler).
        One route.  Handler is an unqualified atom naming an
        Env0->Env relation (adr/0017) defined in the declaring
        module; the route name is the handler atom, so
        path_for(Handler, [], P) works with no extra naming step.

    :- resources(Name).
    :- resources(Name, Opts).
        The seven Rails REST routes for a plural resource Name:

          GET       /posts           index    posts_index
          GET       /posts/new       new      posts_new
          POST      /posts           create   posts_create
          GET       /posts/:id       show     posts_show
          GET       /posts/:id/edit  edit     posts_edit
          PATCH/PUT /posts/:id       update   posts_update (+ alias
                                              posts_update_put)
          DELETE    /posts/:id       destroy  posts_destroy

        /posts/new is registered before /posts/:id (Rails ordering),
        so "/posts/new" reaches new/2, not show/2 with id=new.
        Opts: only(Actions) | except(Actions) (mutually exclusive;
        actions outside the seven are a load-time error) and
        singular(Atom) overriding the dumb s-stripping inflection
        (posts -> post).

Path helpers are generated as real predicates in the declaring
module (index -> posts_path/1, show -> post_path/2, new ->
new_post_path/1, edit -> edit_post_path/2), each a veneer over
router:path_for/3, and recorded in the path_helper/3 table.  Wherever
the framework expects a path -- redirect/3 (px_env, hook
px_env:eval_path_term/2) and attribute values in templates
(px_template, hook px_template:eval_attr_value/2) -- a term whose
functor F and arity N match a registered helper F/N+1 is called with
one extra, final output argument in the recorded module.  A
path_for(Name, Params) term is also accepted and evaluated through
router:path_for/3 directly.

Pipeline elements (adr/0017 env relations, for use in
px_env:set_pipeline/1):

    method_override/2 -- Rails' _method convention: a POST whose
        params carry _method in {patch, put, delete} is rewritten to
        that method (original preserved at Env.request.raw_method).
        Runs BEFORE route_dispatch.

    route_dispatch/2 -- match Env.method + Env.path against the
        route store via v1's match_route/4, merge the matched path
        params over Env.params (path params win --
        px_env:env_merge_params/3), and call the handler as an
        Env0->Env relation.  No route matches: FAIL, i.e. decline;
        px_env's pipeline converts a fully-declined request to 404.

Load-time checking: for every registered route, the handler
predicate M:Handler/2 is checked when the declaring file finishes
loading (initialization/1 -- so directive-before-definition source
order is fine) and a missing handler prints a warning naming the
exact predicate to define.  Helper-name collisions with existing
predicates are an error at registration time.
*/

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(error)).

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/router'], RouterSpec),
   atomic_list_concat([Dir, '/px_env'], EnvSpec),
   use_module(RouterSpec),
   use_module(EnvSpec).

%   path_helper(Functor, TermArity, Module): the framework-level
%   helper table of adr/0018.  TermArity is the arity of the TERM app
%   code writes (post_path(7) -> 1); the predicate has one more
%   argument, the output path.
:- dynamic path_helper/3.


		 /*******************************
		 *      DIRECTIVE EXPANSION     *
		 *******************************/

:- multifile user:term_expansion/2.

user:term_expansion((:- route(Method, Path, Handler)), Expansion) :-
    px_router:expand_route(Method, Path, Handler, Expansion).
user:term_expansion((:- resources(Res)), Expansion) :-
    px_router:expand_resources(Res, [], Expansion).
user:term_expansion((:- resources(Res, Opts)), Expansion) :-
    px_router:expand_resources(Res, Opts, Expansion).

%!  expand_route(+Method, +Path, +Handler, -Expansion) is det.
%
%   `:- route(get, "/about", about)` in module M becomes one
%   add_route/4 registration (route name = handler atom) plus the
%   end-of-load handler-existence check.  The registration runs `now`
%   -- at directive-processing time -- so routes exist in source
%   order, which is what makes resources' new-before-show ordering
%   (and any app-level ordering) hold in the route store.
expand_route(Method, Path, Handler,
             [ (:- initialization(px_router:register_route(Handler, Method, Path, M:Handler), now)),
               (:- initialization(px_router:check_handler(M, Handler)))
             ]) :-
    prolog_load_context(module, M),
    must_be(atom, Method),
    must_be(atom, Handler).

%!  expand_resources(+Res, +Opts, -Expansion) is det.
expand_resources(Res, Opts, Expansion) :-
    prolog_load_context(module, M),
    must_be(atom, Res),
    check_options(Opts),
    selected_actions(Opts, Actions),
    singular_name(Res, Opts, Sing),
    phrase(resource_expansion(Actions, Res, Sing, M), Expansion).

resource_expansion(Actions, Res, Sing, M) -->
    registrations(Actions, Res, M),
    helper_definitions(Actions, Res, Sing, M),
    handler_checks(Actions, M).

%   Registrations, in Actions order (the table order of adr/0018, as
%   filtered by only/except): each is a `now` initialization lowering
%   onto router:add_route/4.  update registers two facts -- the
%   canonical posts_update (patch) and the alias posts_update_put --
%   because v1's add_route/4 keeps one fact per name.
registrations([], _, _) --> [].
registrations([A|As], Res, M) -->
    registration(A, Res, M),
    registrations(As, Res, M).

registration(update, Res, M) -->
    !,
    { route_name(Res, update, Name),
      atom_concat(Name, '_put', PutName),
      member_path(Res, Path)
    },
    [ (:- initialization(px_router:register_route(Name, patch, Path, M:update), now)),
      (:- initialization(px_router:register_route(PutName, put, Path, M:update), now))
    ].
registration(Action, Res, M) -->
    { route_name(Res, Action, Name),
      action_method_path(Action, Res, Method, Path)
    },
    [ (:- initialization(px_router:register_route(Name, Method, Path, M:Action), now)) ].

%   action_method_path(?Action, +Res, -Method, -Path)
action_method_path(index,   Res, get,    Path) :- collection_path(Res, Path).
action_method_path(new,     Res, get,    Path) :-
    collection_path(Res, P0), string_concat(P0, "/new", Path).
action_method_path(create,  Res, post,   Path) :- collection_path(Res, Path).
action_method_path(show,    Res, get,    Path) :- member_path(Res, Path).
action_method_path(edit,    Res, get,    Path) :-
    member_path(Res, P0), string_concat(P0, "/edit", Path).
action_method_path(destroy, Res, delete, Path) :- member_path(Res, Path).

collection_path(Res, Path) :- format(string(Path), "/~w", [Res]).
member_path(Res, Path)     :- format(string(Path), "/~w/:id", [Res]).

route_name(Res, Action, Name) :-
    atomic_list_concat([Res, '_', Action], Name).

%   Helper generation: only the four adr/0018 helpers, and only when
%   the action they are a veneer over survived only/except -- so
%   only([index]) generates posts_path/1 and nothing else, and a
%   stray edit_post_path(Id) fails at helper-resolution time.
%
%   Each helper is emitted as (a) a `now` registration into the
%   path_helper/3 table -- which also performs the collision check,
%   BEFORE the clause below is loaded -- and (b) an ordinary clause
%   in the declaring module wrapping router:path_for/3.
helper_definitions([], _, _, _) --> [].
helper_definitions([A|As], Res, Sing, M) -->
    helper_definition(A, Res, Sing, M),
    helper_definitions(As, Res, Sing, M).

helper_definition(Action, Res, Sing, M) -->
    { action_helper(Action, Res, Sing, F, N),
      !,
      route_name(Res, Action, RouteName),
      helper_clause(F, N, RouteName, Clause)
    },
    [ (:- initialization(px_router:register_path_helper(F, N, M), now)),
      Clause
    ].
helper_definition(_, _, _, _) --> [].

%   action_helper(?Action, +Res, +Sing, -HelperFunctor, -TermArity)
action_helper(index, Res, _Sing, F, 0) :- atom_concat(Res, '_path', F).
action_helper(show,  _Res, Sing, F, 1) :- atom_concat(Sing, '_path', F).
action_helper(new,   _Res, Sing, F, 0) :-
    atomic_list_concat([new, '_', Sing, '_path'], F).
action_helper(edit,  _Res, Sing, F, 1) :-
    atomic_list_concat([edit, '_', Sing, '_path'], F).

helper_clause(F, 0, RouteName, (Head :- router:path_for(RouteName, [], P))) :-
    Head =.. [F, P].
helper_clause(F, 1, RouteName, (Head :- router:path_for(RouteName, [id=Id], P))) :-
    Head =.. [F, Id, P].

%   The end-of-load handler checks, one per surviving action.
handler_checks([], _) --> [].
handler_checks([A|As], M) -->
    [ (:- initialization(px_router:check_handler(M, A))) ],
    handler_checks(As, M).


		 /*******************************
		 *     OPTIONS AND NAMING       *
		 *******************************/

rest_actions([index, new, create, show, edit, update, destroy]).

check_options(Opts) :-
    must_be(list, Opts),
    forall(member(O, Opts),
           (   valid_option(O)
           ->  true
           ;   throw(error(domain_error(resources_option, O),
                           context(px_router:resources/2,
                                   'options are only(Actions), except(Actions), singular(Atom)')))
           )).

valid_option(only(L))     :- is_list(L).
valid_option(except(L))   :- is_list(L).
valid_option(singular(A)) :- atom(A).

selected_actions(Opts, Actions) :-
    rest_actions(All),
    (   memberchk(only(_), Opts),
        memberchk(except(_), Opts)
    ->  throw(error(domain_error(resources_options, Opts),
                    context(px_router:resources/2,
                            'give only/1 or except/1, not both')))
    ;   memberchk(only(Only), Opts)
    ->  check_actions(Only, All),
        include([A]>>memberchk(A, Only), All, Actions)
    ;   memberchk(except(Except), Opts)
    ->  check_actions(Except, All),
        exclude([A]>>memberchk(A, Except), All, Actions)
    ;   Actions = All
    ).

check_actions(List, All) :-
    forall(member(A, List),
           (   memberchk(A, All)
           ->  true
           ;   throw(error(domain_error(rest_action, A),
                           context(px_router:resources/2,
                                   'not one of the seven REST actions')))
           )).

%   The entire inflection engine (adr/0018): singular(Atom) option,
%   else strip one trailing 's', else the name is used as-is.
singular_name(_Res, Opts, Sing) :-
    memberchk(singular(Sing0), Opts),
    !,
    Sing = Sing0.
singular_name(Res, _Opts, Sing) :-
    (   atom_concat(Sing0, s, Res)
    ->  Sing = Sing0
    ;   Sing = Res
    ).


		 /*******************************
		 *     LOAD-TIME MACHINERY      *
		 *******************************/

%!  register_route(+Name, +Method, +Path, :Handler) is det.
%
%   Lowering target of both directives: exactly one v1 add_route/4
%   call.  A reader who prints the expansion sees the v1 API.
register_route(Name, Method, Path, Handler) :-
    router:add_route(Name, Method, Path, Handler).

%!  register_path_helper(+F, +TermArity, +M) is det.
%
%   Record a generated helper in the path_helper/3 table, first
%   checking for name collisions: if the helper predicate F/TermArity+1
%   already exists in M and was not put there by a previous load of
%   the same declaration, this is a load-time error (adr/0018), not a
%   silent extra clause.
register_path_helper(F, N, M) :-
    (   path_helper(F, N, M)
    ->  true                            % reload of the same declaration
    ;   A is N + 1,
        current_predicate(M:F/A)
    ->  throw(error(permission_error(generate, path_helper, M:F/A),
                    context(px_router:resources/2,
                            'helper name collides with an existing predicate')))
    ;   assertz(path_helper(F, N, M))
    ).

%!  check_handler(+M, +Handler) is det.
%
%   Runs after the declaring file has finished loading
%   (initialization/1): warn -- loudly, naming the exact predicate to
%   define -- when a registered route's handler M:Handler/2 does not
%   exist.  A check before the first request, per adr/0018, so a
%   typo'd action name is caught at load time and not by the first
%   user to click the link.
check_handler(M, Handler) :-
    (   current_predicate(M:Handler/2)
    ->  true
    ;   print_message(warning, px_router(missing_handler(M, Handler/2)))
    ).

:- multifile prolog:message//1.
prolog:message(px_router(missing_handler(M, PI))) -->
    [ 'px_router: route handler ~w:~w is not defined; define it before the first request'-[M, PI] ].


		 /*******************************
		 *      PATH-TERM RESOLUTION    *
		 *******************************/

%!  resolve_path_term(+PathTerm, -Path) is semidet.
%
%   The adr/0018 evaluation rule: a term (or bare atom) whose functor
%   F and arity N match a registered helper F/N+1 is called with one
%   extra, final output argument, in the module the path_helper/3
%   table records.  A path_for(Name, Params) term evaluates through
%   router:path_for/3 directly, covering route/3 routes that have no
%   generated helper.  Fails (rather than throws) on anything else so
%   the hooks below decline cleanly and their callers fall through.
resolve_path_term(PathTerm, Path) :-
    callable(PathTerm),
    (   PathTerm = path_for(Name, Params)
    ->  atom(Name),
        router:path_for(Name, Params, Path)
    ;   functor(PathTerm, F, N),
        path_helper(F, N, M),
        PathTerm =.. [F|Args],
        append(Args, [Path0], FullArgs),
        Goal =.. [F|FullArgs],
        call(M:Goal),
        Path = Path0
    ).

%   Both framework hooks route here: redirect/3 and friends
%   (px_env:eval_path_term/2, adr/0017) and compound attribute values
%   in templates (px_template:eval_attr_value/2, adr/0019) -- so
%   href(post_path(7)) and redirect(Env0, post_path(Id), Env) both
%   resolve through the same table and the same path_for/3.
:- multifile px_env:eval_path_term/2.
:- dynamic px_env:eval_path_term/2.
px_env:eval_path_term(PathTerm, Path) :-
    px_router:resolve_path_term(PathTerm, Path).

:- multifile px_template:eval_attr_value/2.
:- dynamic px_template:eval_attr_value/2.
px_template:eval_attr_value(PathTerm, Path) :-
    px_router:resolve_path_term(PathTerm, Path).


		 /*******************************
		 *      PIPELINE ELEMENTS       *
		 *******************************/

%!  method_override(+Env0, -Env) is det.
%
%   adr/0018 section 5, Rails' _method convention.  Only a POST may
%   be overridden; only patch, put and delete are legal targets --
%   a form cannot smuggle itself into being a GET or invent methods.
%   On override, Env.method is rewritten and the original preserved
%   at Env.request.raw_method; everything downstream (route matching
%   included) sees the overridden method and never knows the
%   difference.  Not applicable: the env passes through unchanged.
method_override(Env0, Env) :-
    (   get_dict(method, Env0, post),
        get_dict(params, Env0, Params),
        get_dict('_method', Params, Override0),
        method_atom(Override0, Override),
        memberchk(Override, [patch, put, delete])
    ->  Env = Env0.put(method, Override).put(request/raw_method, post)
    ;   Env = Env0
    ).

method_atom(V, A) :-
    (   atom(V)   -> A0 = V
    ;   string(V) -> atom_string(A0, V)
    ),
    downcase_atom(A0, A).

%!  route_dispatch(+Env0, -Env) is nondet.
%
%   The router as a pipeline element.  Matching reuses v1's
%   match_route/4 (and therefore the one cut-free match_path/3
%   relation, adr/0009) against Env.method + Env.path; on a match the
%   route's path params are merged over Env.params via
%   px_env:env_merge_params/3 -- path params win (adr/0017) -- and
%   the handler is called as an Env0->Env relation in its captured
%   module.  Routes are tried in registration order (so
%   /widgets/new beats /widgets/:id); when no route matches, this
%   predicate FAILS -- the pipeline treats that as declined and
%   px_env's finalizer produces the 404.
route_dispatch(Env0, Env) :-
    get_dict(method, Env0, Method),
    get_dict(path, Env0, Path),
    router:match_route(Method, Path, Handler, Params),
    path_params_dict(Params, ParamsDict),
    px_env:env_merge_params(Env0, ParamsDict, Env1),
    call(Handler, Env1, Env).

%   match_route/4 yields params as Name=Value pairs with atom values
%   (path segments); env params are a dict of atom keys to STRING
%   values (adr/0017), so convert on the way in.
path_params_dict(Pairs, Dict) :-
    foldl(put_path_param, Pairs, _{}, Dict).

put_path_param(Name=Value0, Dict0, Dict) :-
    atom_string(Value0, Value),
    put_dict(Name, Dict0, Value, Dict).
