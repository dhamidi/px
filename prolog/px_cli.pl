:- module(px_cli, [cli/0, main/1]).

/** <module> The px command line (adr/0032).

bin/px execs `swipl -g px_cli:cli prolog/px_cli.pl -- ARGS`. cli/0
reads argv and dispatches main/1:

    px new APP                  scaffold a new application
    px generate feature NAME    scaffold app/NAME/ (alias: g)
    px routes                   print the app's route table
    px server                   boot the app (load + serve)
    px console                  interactive toplevel, app loaded
    px build [-o FILE]          one executable (adr/0033, px_build)
    px version | help

Commands that need an app (routes/server/console/build) locate the
app root by walking up from cwd to the nearest directory holding
config/app.pl -- so px works from anywhere inside an app, like git.
Scaffolds emit the adr/0029 feature shapes with the guestbook ADR's
worked example as commented guidance; the generated app boots and
serves immediately.

The framework home is this file's own tree (adr/0030: location, not
mechanics), overridable with PX_HOME; `px new` bakes the discovered
home into the generated bin/ shims, visible and editable.
*/

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(filesex)).
:- use_module(library(readutil)).

%   The framework home: parent of this file's directory.
:- dynamic px_home/1.
:- prolog_load_context(directory, Dir),
   file_directory_name(Dir, Home),
   assertz(px_home(Home)).


		 /*******************************
		 *           DISPATCH           *
		 *******************************/

cli :-
    current_prolog_flag(argv, Argv),
    (   catch(main(Argv), E,
              ( print_message(error, E), halt(1) ))
    ->  true
    ;   halt(1)
    ).

main([new, App|_])                 :- !, cmd_new(App), halt(0).
main([generate, feature, Name|_])  :- !, cmd_generate_feature(Name), halt(0).
main([g, feature, Name|_])         :- !, cmd_generate_feature(Name), halt(0).
main([routes|_])                   :- !, in_app_root(cmd_routes), halt(0).
main([server|_])                   :- !, in_app_root(prologex:prologex_run).
main([console|_])                  :- !, in_app_root(cmd_console).
main([build|Rest])                 :- !, in_app_root(cmd_build(Rest)), halt(0).
main([version|_])                  :- !, cmd_version, halt(0).
main([help|_])                     :- !, usage, halt(0).
main([])                           :- !, usage, halt(0).
main(Argv) :-
    format(user_error, "px: unknown command ~w~n~n", [Argv]),
    usage,
    halt(1).

usage :-
    format("px -- the prologex command line (adr/0032)~n~n"),
    format("  px install [DIR]           put px on your PATH (default ~~/.local/bin)~n"),
    format("  px new APP                 scaffold a new application~n"),
    format("  px generate feature NAME   scaffold app/NAME/ (alias: g)~n"),
    format("  px routes                  print the route table~n"),
    format("  px server                  boot the app~n"),
    format("  px console                 toplevel with the app loaded~n"),
    format("  px build [-o FILE]         compile the app to one executable~n"),
    format("  px version | help~n").

cmd_version :-
    px_home(Home),
    format("px (prologex) at ~w~n", [Home]).

%   Walk up from cwd to the nearest config/app.pl, cd there, run
%   Goal. Commands that need an app fail early and clearly without
%   one.
in_app_root(Goal) :-
    working_directory(CWD, CWD),
    (   find_app_root(CWD, Root)
    ->  working_directory(_, Root),
        load_framework,
        call(Goal)
    ;   format(user_error,
               "px: not inside an application (no config/app.pl above ~w)~n",
               [CWD]),
        halt(1)
    ).

find_app_root(Dir, Root) :-
    directory_file_path(Dir, 'config/app.pl', Probe),
    (   exists_file(Probe)
    ->  Root = Dir
    ;   file_directory_name(Dir, Parent),
        Parent \== Dir,
        find_app_root(Parent, Root)
    ).

load_framework :-
    px_home(Home),
    directory_file_path(Home, 'prolog/prologex', Spec),
    use_module(Spec).


		 /*******************************
		 *          px routes           *
		 *******************************/

%   The reversible router made visible (adr/0032 decision 3): load
%   the app, print router:route/4 in registration order -- which is
%   match order.
cmd_routes :-
    prologex:prologex_load,
    format("~w~t~10|~w~t~40|~w~t~62|~w~n",
           ['METHOD', 'PATH', 'NAME', 'HANDLER']),
    forall(router:route(Name, Method, Segments, Handler),
           ( segments_path(Segments, Path),
             format("~w~t~10|~w~t~40|~w~t~62|~q~n",
                    [Method, Path, Name, Handler])
           )).

segments_path([], "/") :- !.
segments_path(Segments, Path) :-
    maplist(segment_str, Segments, Parts),
    atomic_list_concat([''|Parts], '/', Path).

segment_str(param(N), S) :- !, atom_concat(':', N, S).
segment_str(S, S).


		 /*******************************
		 *          px console          *
		 *******************************/

cmd_console :-
    prologex:prologex_load,
    format("px console -- app loaded; try guestbook_commands:load_comments(Cs).~n"),
    prolog.


		 /*******************************
		 *           px build           *
		 *******************************/

cmd_build(Rest) :-
    build_out(Rest, Opts),
    px_home(Home),
    directory_file_path(Home, 'prolog/px_build', Spec),
    use_module(Spec),
    px_build:build(Opts).

build_out(['-o', File|_], [out(File)]) :- !.
build_out(_, []).


		 /*******************************
		 *            px new            *
		 *******************************/

cmd_new(App) :-
    (   exists_directory(App)
    ->  format(user_error, "px: ~w already exists~n", [App]),
        halt(1)
    ;   true
    ),
    px_home(Home),
    forall(member(Dir, ['app/shared', 'app/welcome', 'assets/css',
                        'assets/js', 'bin', 'config', 'data']),
           ( directory_file_path(App, Dir, D),
             make_directory_path(D)
           )),
    forall(new_file(Rel, TemplateGoal),
           ( call(TemplateGoal, App, Home, Content),
             write_app_file(App, Rel, Content)
           )),
    copy_framework_assets(Home, App),
    make_executable(App, 'bin/px'),
    make_executable(App, 'bin/server'),
    format("Created ~w/ -- next:~n  cd ~w && bin/px server~n", [App, App]).

write_app_file(App, Rel, Content) :-
    directory_file_path(App, Rel, Path),
    setup_call_cleanup(open(Path, write, S),
                       write(S, Content),
                       close(S)),
    format("  create ~w~n", [Rel]).

make_executable(App, Rel) :-
    directory_file_path(App, Rel, Path),
    catch(process_create(path(chmod), ['+x', Path], []), _, true).

%   px_ui ships with the framework (adr/0026); a new app gets its
%   stylesheet and the shared JS machinery so components work on day
%   one. Plain file copies -- the app owns them from here.
copy_framework_assets(Home, App) :-
    directory_file_path(Home, 'assets/css/ui.css', UiCss),
    (   exists_file(UiCss)
    ->  directory_file_path(App, 'assets/css/ui.css', Dest),
        copy_file(UiCss, Dest),
        format("  create assets/css/ui.css (from framework)~n")
    ;   true
    ),
    directory_file_path(Home, 'assets/js', JsSrc),
    (   exists_directory(JsSrc)
    ->  directory_file_path(App, 'assets/js', JsDest),
        copy_directory(JsSrc, JsDest),
        format("  create assets/js/ (from framework)~n")
    ;   true
    ).

new_file('config/app.pl',           tpl_config).
new_file('app/shared/layout.pl',    tpl_layout).
new_file('app/shared/middleware.pl',tpl_middleware).
new_file('app/welcome/controller.pl', tpl_welcome).
new_file('assets/css/app.css',      tpl_app_css).
new_file('assets/js/app.js',        tpl_app_js).
new_file('bin/px',                  tpl_bin_px).
new_file('bin/server',              tpl_bin_server).
new_file('.gitignore',              tpl_gitignore).
new_file('README.md',               tpl_readme).


		 /*******************************
		 *      px generate feature     *
		 *******************************/

cmd_generate_feature(Name) :-
    (   \+ exists_directory(app)
    ->  format(user_error, "px: no app/ here -- run inside an application~n", []),
        halt(1)
    ;   true
    ),
    directory_file_path(app, Name, Dir),
    (   exists_directory(Dir)
    ->  format(user_error, "px: app/~w already exists~n", [Name]),
        halt(1)
    ;   true
    ),
    make_directory_path(Dir),
    forall(feature_file(Rel, TemplateGoal),
           ( call(TemplateGoal, Name, Content),
             directory_file_path(Dir, Rel, Path),
             setup_call_cleanup(open(Path, write, S),
                                write(S, Content),
                                close(S)),
             format("  create app/~w/~w~n", [Name, Rel])
           )),
    format("Feature ~w scaffolded -- declare pages in app/~w/controller.pl~n",
           [Name, Name]).

feature_file('controller.pl', tpl_feature_controller).
feature_file('messages.pl',   tpl_feature_messages).
feature_file('model.pl',      tpl_feature_model).
feature_file('commands.pl',   tpl_feature_commands).
feature_file('views.pl',      tpl_feature_views).


		 /*******************************
		 *       NEW-APP TEMPLATES      *
		 *******************************/

tpl_config(App, _, C) :-
    format(atom(C),
"%% config/app.pl -- ~w configuration (adr/0022).
%%
%%   config(Key, Value).         base fact, every environment
%%   config(Env, Key, Value).    overlay, when PROLOGEX_ENV=Env
%%
%% env('NAME', Default) values resolve against the OS environment at
%% lookup time -- deploy-time flexible even inside a px build binary.

config(port, env('PORT', 8090)).
config(workers, 1).
config(database, \"data/~w.db\").
", [App, App]).

tpl_layout(App, _, C) :-
    format(atom(C),
":- module(layout, []).

/** <module> The application layout (adr/0027 decision 5). Owning
this file owns the whole document -- keep the viewport meta tag; it
is what makes pages usable on phones (adr/0028).
*/

:- use_module(library(prologex)).

layout(Title, Content) ~~>
    [ raw(\"<!DOCTYPE html>\\n\"),
      html(
        [ head(
            [ meta(charset(\"utf-8\")),
              meta([name(viewport), content(\"width=device-width, initial-scale=1\")]),
              title(Title),
              stylesheet_tag(\"css/app.css\"),
              stylesheet_tag(\"css/ui.css\"),
              \\javascript_importmap_tags
            ]),
          body(div(class(page), Content))
        ])
    ].
% ~w
", [App]).

tpl_middleware(_, _, C) :-
    C = ":- module(app_middleware, []).

/** <module> Cross-feature concerns (adr/0029 decision 3): plain env
relations (adr/0017). Add auth, rate limiting, request ids here --
an env relation plus one line in the pipeline; a failing element
declines the request.
*/

:- use_module(library(prologex)).

:- pipeline([ log_requests,
              method_override,
              route_dispatch,
              turbo_frames
            ]).

log_requests(Env, Env) :-
    format(user_error, \"~w ~w~n\", [Env.method, Env.path]).
".

tpl_welcome(App, _, C) :-
    format(atom(C),
":- module(welcome_controller, []).

/** <module> The welcome feature. Replace me: `px generate feature
NAME` scaffolds the full adr/0029 shape (controller, messages, pure
model, commands, views).
*/

:- use_module(library(prologex)).

:- page(index, \"/\", [as(home)]).

model(index, _Env, m{app: \"~w\"}).

view(index, M, layout(M.app,
  [ h1([\"Welcome to \", M.app]),
    p(\"This page is app/welcome/controller.pl -- one action, no
       messages yet. The component library is browsable machinery:
       px_ui ships with the framework (adr/0026).\"),
    p([ \"Add a feature: \", code(\"bin/px generate feature guestbook\") ])
  ])).
", [App]).

tpl_app_css(_, _, C) :-
    C = ":root {
  --bg: #0f1115;
  --panel: #161a21;
  --text: #e6e8eb;
  --muted: #9aa4b2;
  --accent: #3E63DD;
  --accent-contrast: #ffffff;
  --accent-hover: #5472e4;
  --accent-text: #849dff;
  --border: #262b34;
  --code-bg: #1c2129;
  --danger: #f87171;
}

* { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; text-size-adjust: 100%; }

body {
  margin: 0;
  background: var(--bg);
  color: var(--text);
  font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", Helvetica, Arial, sans-serif;
  line-height: 1.6;
  color-scheme: dark;
}

/* Mobile-first (adr/0028): narrow is the default; widen upward. */
.page { max-width: 760px; margin: 0 auto; padding: 1.5rem 1rem 3rem; }
@media (min-width: 640px) { .page { padding: 2.5rem 1.5rem 4rem; } }

h1 { font-size: clamp(1.45rem, 4.5vw, 1.8rem); }
a { color: var(--accent-text); text-decoration: none; }
a:hover { text-decoration: underline; }
code {
  background: var(--code-bg);
  padding: 0.15em 0.4em;
  border-radius: 4px;
  font-family: \"SF Mono\", Consolas, Menlo, monospace;
}
".

tpl_app_js(_, _, C) :-
    C = "// assets/js/app.js -- served through the importmap (adr/0025).
// Import px_ui component elements here as you use them, e.g.:
//   import \"components/switch\";
".

tpl_bin_px(_, Home, C) :-
    format(atom(C),
"#!/usr/bin/env bash
# The px CLI (adr/0032), tied to the framework checkout below.
set -euo pipefail
export PX_HOME=\"${PX_HOME:-~w}\"
exec \"$PX_HOME/bin/px\" \"$@\"
", [Home]).

tpl_bin_server(_, _, C) :-
    C = "#!/usr/bin/env bash
# Boot this app (adr/0027): dev and production, same entry.
set -euo pipefail
cd \"$(dirname \"${BASH_SOURCE[0]}\")/..\"
exec bin/px server
".

tpl_gitignore(_, _, C) :-
    C = "public/assets/
data/
".

tpl_readme(App, _, C) :-
    format(atom(C),
"# ~w

A [prologex](https://github.com/dhamidi/px) application.

    bin/px server              # boot (config/app.pl owns port/workers)
    bin/px routes              # the route table
    bin/px console             # toplevel with the app loaded
    bin/px generate feature X  # scaffold app/X/ (adr/0029 shape)
    bin/px build               # one deployable executable (adr/0033)
", [App]).


		 /*******************************
		 *      FEATURE TEMPLATES       *
		 *******************************/

tpl_feature_controller(Name, C) :-
    format(atom(C),
":- module(~w_controller, []).

/** <module> The ~w boundary (adr/0029): declares pages, runs
commands (side effects), composes domain messages the pure model
folds over. Response effects are data: redirect(PathTerm),
turbo(Streams), status(Code).
*/

:- use_module(library(prologex)).
:- use_module(app(~w/messages), []).    % forms register on load
:- use_module(app(~w/model), [empty/1]).
:- use_module(app(~w/commands)).
:- use_module(app(~w/views), []).       % templates register on load

:- page(index, \"/~w\").                 % helper: ~w_path

model(index, _Env, M) :-
    empty(M).

view(index, M, ~w_view(M)).

%% Messages arrive validated (adr/0027 decision 3): a form named F
%% delivers F(ok(Values)) or F(invalid(Values, Errors)). Compose a
%% domain message, let the pure model fold it, answer with effects:
%%
%% update(sign(ok(Values)), M0, M,
%%        [ redirect(~w_path) ]) :-
%%     save_thing(Values, Thing),                 %% command
%%     ~w_model:update(saved(Thing), M0, M).      %% pure fold
%% update(sign(invalid(Values, Errors)), M0, M, [status(422)]) :-
%%     ~w_model:update(rejected(Values, Errors), M0, M).
", [Name, Name, Name, Name, Name, Name, Name, Name, Name, Name, Name, Name]).

tpl_feature_messages(Name, C) :-
    format(atom(C),
":- module(~w_messages, []).

/** <module> ~w's HTTP intent vocabulary (adr/0029): form
declarations validated at the edge, before update/4 ever runs.
*/

:- use_module(library(prologex)).

%% :- form(sign,
%%      [ field(title, text,     [required, max_length(120)]),
%%        field(body,  textarea, [required])
%%      ]).
", [Name, Name]).

tpl_feature_model(Name, C) :-
    format(atom(C),
":- module(~w_model,
          [ empty/1,                % -Model
            update/3                % +DomainMsg, +Model0, -Model
          ]).

/** <module> ~w's pure core (adr/0029): domain messages fold over
the model. No prologex import, no database, no env -- keep this
loadable with nothing but SWI.
*/

empty(m{}).

%% update(saved(Thing), M0, M) :- ...
%% update(rejected(Values, Errors), M0, M) :- ...
update(_, M, M).
", [Name, Name]).

tpl_feature_commands(Name, C) :-
    format(atom(C),
":- module(~w_commands, []).

/** <module> Every ~w side effect, reads and writes, named as verbs
(adr/0029). The only file in the feature that touches the database;
its schema rides here.
*/

:- use_module(library(prologex)).

%% :- schema(\"create table if not exists ~w (
%%              id integer primary key)\").
%%
%% load_things(Things) :-
%%     findall(T, row(q(~w, [order_by(desc(id))]), T), Things).
%%
%% save_thing(Values, Thing) :-
%%     insert(~w, Values, Id),
%%     once(row(q(~w, [where(id == Id)]), Thing)).
", [Name, Name, Name, Name, Name, Name]).

tpl_feature_views(Name, C) :-
    format(atom(C),
":- module(~w_views, []).

/** <module> ~w templates (adr/0029): pure, model in, markup out;
they never see the env. Template names are global -- prefix
anything generic with the feature name.
*/

:- use_module(library(prologex)).

~w_view(_M) ~~>
    layout(\"~w\",
      [ h1(\"~w\"),
        p(\"Scaffolded by px generate feature (adr/0032).\")
      ]).
", [Name, Name, Name, Name, Name]).
