:- module(prologex,
          [ prologex_run/0,
            px_conn/3,                  % +WorkerId, +Loop, +Client
            px_request/3,               % +WorkerId, +Request, +Stream
            op(1100, xfx, ~>)
          ]).

/** <module> The prologex facade (adr/0016).

The single module an application loads:

    :- use_module('../prolog/prologex').   % by path

It reexports the whole Rails-layer surface -- env responders
(adr/0017), the query builder (adr/0021), forms (adr/0023), Turbo
(adr/0024), config (adr/0022), templates' `~>` operator (adr/0019) --
and loads the router (adr/0018) whose route/resources directives are
global term_expansion. On top of that it provides:

    :- pipeline([Goal, ...]).
        Directive sugar over px_env:set_pipeline/1. Elements naming
        framework middleware (method_override, route_dispatch,
        turbo_frames) are qualified to their home modules; already
        qualified goals pass through; anything else is qualified to
        the declaring module -- adr/0016 rule 7, app code never
        writes `mymodule:goal`.

    :- schema(SQL).
        Declare a statement (canonically CREATE TABLE IF NOT EXISTS
        ...) to run once per worker connection, right after the
        database opens -- the app's schema rides with the app.

    prologex_run/0
        The whole boot (adr/0016, adr/0027, adr/0029). Started in an
        app directory (bin/server cds there) it needs no app "main"
        file: load config/app.pl, register the `app` search-path
        alias, mount /assets/:file, load app/shared/ then every
        feature directory under app/ (`:- page` directives register
        their routes as controllers load), install the
        default pipeline when the app declared none, install the
        default mobile-first layout when the app defined no layout/2
        template (px_page:ensure_layout/0), compile the asset
        pipeline (px_assets:compile_assets/0, adr/0025 -- idempotent
        and cheap, so it is safe to run on every start), ensure the
        database directory exists, start the workers, block forever.

Default pipeline (when the app has no `:- pipeline(...)`):

    [px_router:method_override, px_router:route_dispatch,
     px_turbo:turbo_frames]

Ordering is load-bearing: turbo_frames prunes the RESPONSE body term,
so it must run after route_dispatch has produced it; px_env's fold
semantics (a declined element leaves the env unchanged) make the
no-frame-header case free.

Per-worker database wiring (adr/0020 section 4, one connection per
worker): px_request/3 lazily opens the configured database on the
first request each worker thread serves, runs the declared schema
statements, and installs the connection via px_query:use_db/1
(thread-local), then hands the request to px_env:handle_request/3.
*/

:- use_module(library(apply)).
:- use_module(library(error)).
:- use_module(library(lists)).
:- use_module(library(filesex)).

%   Make `:- use_module(library(prologex))` -- the adr/0016 example's
%   own first line -- work for app code (adr/0027): the framework's
%   prolog/ directory joins the library search path.
:- prolog_load_context(directory, Dir),
   (   user:file_search_path(library, Dir)
   ->  true
   ;   assertz(user:file_search_path(library, Dir))
   ).

%   Sibling references per adr/0030: the spec is the location.
:- reexport(px_env,      [respond/3, respond/4, redirect/3, not_found/2]).
:- reexport(px_query,    [row/2, insert/3, update/3, delete/2, sql/3]).
:- reexport(px_form,     [form_result/3, form_validate/3]).
:- reexport(px_turbo,    [turbo_or_redirect/4, turbo_stream/3, dom_id/2]).
:- reexport(px_config,   [config/2, require_config/2]).
:- reexport(px_template, [render_to_string/2]).
:- reexport(px_assets,   [asset_path/2, serve_asset/2]).
:- use_module(px_router,     []).   % directives are global term_expansion
:- use_module(px_db,         []).
:- use_module(px_controller, []).   % :- page directive (adr/0027, adr/0029)
:- use_module(px_ui,         []).   % component library is framework surface
:- use_module(worker,        []).
:- use_module(http_stream,   []).


		 /*******************************
		 *   :- pipeline / :- schema    *
		 *******************************/

:- multifile user:term_expansion/2.

user:term_expansion((:- pipeline(Goals)),
                    (:- initialization(px_env:set_pipeline(QGoals), now))) :-
    is_list(Goals),
    prolog_load_context(module, M),
    maplist(prologex:qualify_pipeline_goal(M), Goals, QGoals).

user:term_expansion((:- schema(SQL)),
                    (:- initialization(prologex:add_schema(SQL), now))) :-
    (   string(SQL)
    ->  true
    ;   atom(SQL)
    ).

%!  qualify_pipeline_goal(+DeclaringModule, +Goal0, -Goal) is det.
%
%   Framework middleware resolves to its home module; explicit
%   qualifications pass through; anything else belongs to the
%   declaring module (adr/0016 rule 7).

qualify_pipeline_goal(_, Mod:G, Mod:G) :- !.
qualify_pipeline_goal(_, G, px_router:G) :-
    atom(G), framework_element(px_router, G), !.
qualify_pipeline_goal(_, G, px_turbo:G) :-
    atom(G), framework_element(px_turbo, G), !.
qualify_pipeline_goal(M, G, M:G).

framework_element(px_router, method_override).
framework_element(px_router, route_dispatch).
framework_element(px_turbo,  turbo_frames).

%   schema_sql/1: statements declared with :- schema(SQL), run once
%   per worker connection in declaration order.
:- dynamic schema_sql/1.

add_schema(SQL) :-
    (   schema_sql(SQL)
    ->  true                            % reload of the same declaration
    ;   assertz(schema_sql(SQL))
    ).


		 /*******************************
		 *          RUNNING             *
		 *******************************/

%!  prologex_run is det.
%
%   Load config, default the pipeline, start the workers, block.

prologex_run :-
    load_app_config,
    ensure_app_paths,
    mount_assets_route,
    load_app_tree,
    ensure_pipeline,
    px_controller:ensure_layout,
    px_assets:compile_assets,
    app_port(Port),
    app_workers(Workers),
    database_path(DBPath),
    ensure_parent_dir(DBPath),
    format(user_error,
           "prologex: ~w worker(s) on port ~w, database ~w~n",
           [Workers, Port, DBPath]),
    worker:start_workers(Port, Workers, prologex:px_conn),
    thread_get_message(_).

load_app_config :-
    (   exists_file('config/app.pl')
    ->  px_config:load_config('config/app.pl')
    ;   true
    ).

%   The adr/0029 conventions. ensure_app_paths registers the `app`
%   alias so `:- use_module(app(guestbook/model))` resolves inside
%   app modules (adr/0030); load_app_tree loads app/shared/ first
%   (layout, middleware), then every feature directory --
%   use_module/1 deduplicates, so a controller pulling in its
%   feature's files early is fine; mount_assets_route serves the
%   pipeline without the app writing a route for it. All are no-ops
%   for whatever the app directory does not contain.

ensure_app_paths :-
    (   exists_directory(app)
    ->  absolute_file_name(app, Abs),
        (   user:file_search_path(app, Abs)
        ->  true
        ;   assertz(user:file_search_path(app, Abs))
        )
    ;   true
    ).

load_app_tree :-
    load_dir_modules('app/shared'),
    (   exists_directory(app)
    ->  directory_files(app, Entries),
        msort(Entries, Sorted),
        forall(( member(E, Sorted),
                 \+ memberchk(E, ['.', '..', shared]),
                 directory_file_path(app, E, FeatureDir),
                 exists_directory(FeatureDir)
               ),
               load_dir_modules(FeatureDir))
    ;   true
    ).

%   load_files/2, not use_module/1: the boot loader LOADS app
%   modules, it does not import their exports anywhere -- two
%   features both exporting update/3 (a domain fold, adr/0029) must
%   not collide in the loader's namespace.
load_dir_modules(Dir) :-
    (   exists_directory(Dir)
    ->  directory_files(Dir, Files),
        msort(Files, Sorted),
        forall(( member(F, Sorted), file_name_extension(_, pl, F) ),
               ( directory_file_path(Dir, F, Path),
                 load_files(user:Path, [must_be_module(true), if(not_loaded)])
               ))
    ;   true
    ).

mount_assets_route :-
    router:add_route(px_assets_file, get, "/assets/:file",
                     px_assets:serve_asset).

app_port(Port) :-
    (   px_config:config(port, P) -> Port = P ; Port = 8090 ).

app_workers(Workers) :-
    (   px_config:config(workers, W) -> Workers = W ; Workers = 1 ).

database_path(Path) :-
    (   px_config:config(database, P) -> Path = P ; Path = "data/prologex.db" ).

ensure_parent_dir(Path) :-
    file_directory_name(Path, Dir),
    (   Dir == '.'
    ->  true
    ;   make_directory_path(Dir)
    ).

%!  ensure_pipeline is det.
%
%   Install the default pipeline unless the app declared one via
%   `:- pipeline([...])`. turbo_frames sits AFTER route_dispatch: it
%   prunes the response body the handler produced; when it declines
%   (no turbo-frame header / no matching frame) the env flows on
%   unchanged (px_env's fold semantics).

ensure_pipeline :-
    (   px_env:pipeline_goals(_)
    ->  true
    ;   px_env:set_pipeline([ px_router:method_override,
                              px_router:route_dispatch,
                              px_turbo:turbo_frames
                            ])
    ).


		 /*******************************
		 *      THE TRANSPORT WIRING    *
		 *******************************/

%!  px_conn(+WorkerId, +Loop, +Client) is det.
%
%   The ConnectionGoal handed to worker:start_workers/3 (called as
%   Goal(WorkerId, Loop, Client) per accepted connection).
%   http_stream:handle_connection(RequestGoal, WorkerId, Loop, Client)
%   parses the request and calls RequestGoal(Request, ResponseStream).

px_conn(WorkerId, Loop, Client) :-
    http_stream:handle_connection(prologex:px_request(WorkerId),
                                  WorkerId, Loop, Client).

%!  px_request(+WorkerId, +Request, +Stream) is det.
%
%   Per-request entry: lazily wire this worker thread's database
%   connection, then run the adr/0017 edge.

px_request(WorkerId, Request, Stream) :-
    ensure_db,
    px_env:handle_request(Request, Stream, WorkerId).

%   One connection per worker thread (adr/0020 section 4). The flag is
%   thread-local, so each worker opens its own connection on its first
%   request; schema statements run right after the open.
:- thread_local db_ready/0.

ensure_db :-
    (   db_ready
    ->  true
    ;   database_path(Path),
        px_db:db_open(Path, DB),
        forall(schema_sql(SQL), px_db:db_exec(DB, SQL, [])),
        px_query:use_db(DB),
        assertz(db_ready)
    ).
