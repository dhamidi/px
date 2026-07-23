:- module(px_cli, [cli/0, main/1]).

/** <module> The px command line (adr/0032).

bin/px execs `swipl -g px_cli:cli prolog/px_cli.pl -- ARGS`. cli/0
reads argv and dispatches main/1:

    px new APP                        scaffold a new application
    px generate feature NAME [F:W..]  scaffold a working CRUD feature
    px routes                         print the app's route table
    px server                         boot the app (load + serve)
    px console                        interactive toplevel, app loaded
    px build [-o FILE]                one executable (adr/0033, px_build)
    px version | help

Commands that need an app (routes/server/console/build) locate the
app root by walking up from cwd to the nearest directory holding
config/app.pl -- so px works from anywhere inside an app, like git.

Scaffolds are SELF-DOCUMENTING WORKING EXAMPLES: `px generate
feature posts` emits a complete list/show/new/create/edit/update/
destroy resource that serves correctly with zero edits, and its
comments teach every convention in user language. Generated files
never reference ADRs or other framework-internal documents -- a
user must never need to read framework source or its decision log
to work on their app.

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

main([new, App|_])                    :- !, cmd_new(App), halt(0).
main([generate, feature, Name|Fs])    :- !, cmd_generate_feature(Name, Fs), halt(0).
main([g, feature, Name|Fs])           :- !, cmd_generate_feature(Name, Fs), halt(0).
%   Framework generators dispatch directly: px generate px:auth.
main([generate, Name|Fs])             :- sub_atom(Name, 0, 3, _, 'px:'), !,
                                         cmd_generate_feature(Name, Fs), halt(0).
main([g, Name|Fs])                    :- sub_atom(Name, 0, 3, _, 'px:'), !,
                                         cmd_generate_feature(Name, Fs), halt(0).
main([routes|_])                      :- !, in_app_root(cmd_routes), halt(0).
main([server|_])                      :- !, in_app_root(prologex:prologex_run).
main([console|_])                     :- !, in_app_root(cmd_console).
main([build|Rest])                    :- !, in_app_root(cmd_build(Rest)), halt(0).
main([version|_])                     :- !, cmd_version, halt(0).
main([help|_])                        :- !, usage, halt(0).
main([])                              :- !, usage, halt(0).
main(Argv) :-
    format(user_error, "px: unknown command ~w~n~n", [Argv]),
    usage,
    halt(1).

usage :-
    format("px -- the prologex command line~n~n"),
    format("  px install [DIR]           put px on your PATH (default ~~/.local/bin)~n"),
    format("  px new APP                 scaffold a new application~n"),
    format("  px generate feature NAME [field:widget ...]~n"),
    format("                             scaffold a working CRUD feature (alias: g)~n"),
    format("                             widgets: text textarea email number checkbox~n"),
    format("                             default fields: title:text body:textarea~n"),
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
segment_str(splat(N), S) :- !, atom_concat('*', N, S).
segment_str(S, S).


		 /*******************************
		 *          px console          *
		 *******************************/

cmd_console :-
    prologex:prologex_load,
    format("px console -- app loaded; feature commands are a module away:~n"),
    format("  ?- some_feature_commands:predicate(...).~n"),
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

%   px_ui ships with the framework; a new app gets its stylesheet and
%   the shared JS machinery so components work on day one. Plain file
%   copies -- the app owns them from here.
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

%   `px generate feature posts [title:text body:textarea ...]`
%   scaffolds a COMPLETE, WORKING resource: list, show, new/create
%   with validation and 422 re-render, edit/update, destroy. It
%   serves correctly with zero edits; the comments in the generated
%   files teach the conventions, so they double as the docs.
%
%   `px generate px:NAME` runs a generator that SHIPS with the
%   framework but writes ordinary code into the app (adr/0035) --
%   px:auth is the first: a full users/sessions authentication
%   system. Framework generators live in prolog/px_gen_NAME.pl,
%   loaded on demand, exposing generate/0 run in the app root.

cmd_generate_feature(Name0, _FieldArgs) :-
    atom_string(NameA, Name0),
    atom_concat('px:', GenName, NameA),
    !,
    (   \+ exists_directory(app)
    ->  format(user_error, "px: no app/ here -- run inside an application~n", []),
        halt(1)
    ;   true
    ),
    px_home(Home),
    atomic_list_concat([Home, '/prolog/px_gen_', GenName], Spec),
    (   exists_source(Spec)
    ->  use_module(Spec),
        atom_concat(px_gen_, GenName, Module),
        Module:generate
    ;   format(user_error, "px: no framework generator named px:~w~n", [GenName]),
        halt(1)
    ).
cmd_generate_feature(Name0, FieldArgs) :-
    atom_string(Name, Name0),
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
    parse_fields(FieldArgs, Fields),
    singular(Name, Sing),
    make_directory_path(Dir),
    forall(feature_file(Rel, TemplateGoal),
           ( call(TemplateGoal, Name, Sing, Fields, Content),
             directory_file_path(Dir, Rel, Path),
             setup_call_cleanup(open(Path, write, S),
                                write(S, Content),
                                close(S)),
             format("  create app/~w/~w~n", [Name, Rel])
           )),
    format("Feature ~w scaffolded and ready: boot with bin/px server, visit /~w~n",
           [Name, Name]).

feature_file('controller.pl', tpl_feature_controller).
feature_file('messages.pl',   tpl_feature_messages).
feature_file('model.pl',      tpl_feature_model).
feature_file('commands.pl',   tpl_feature_commands).
feature_file('views.pl',      tpl_feature_views).

%   "title:text" -> title-text. Default: a title and a body.
parse_fields([], [title-text, body-textarea]) :- !.
parse_fields(Args, Fields) :-
    maplist(parse_field, Args, Fields).

parse_field(Arg, F-W) :-
    (   split_string(Arg, ":", "", [FS, WS]),
        atom_string(F, FS),
        atom_string(W, WS),
        memberchk(W, [text, textarea, email, number, checkbox, hidden])
    ->  true
    ;   format(user_error,
               "px: bad field ~w -- expected name:widget with widget one of text, textarea, email, number, checkbox, hidden~n",
               [Arg]),
        halt(1)
    ).

%   posts -> post; a name with no trailing s is its own singular.
singular(Name, Sing) :-
    (   atom_concat(S, s, Name), S \== ''
    ->  Sing = S
    ;   Sing = Name
    ).

%   Per-field text fragments the templates splice in.

fields_form_decl(Fields, Text) :-
    findall(Line,
            ( member(F-W, Fields),
              format(atom(Line), "       field(~w, ~w, [required])", [F, W])
            ),
            Lines),
    atomic_list_concat(Lines, ',\n', Text).

fields_schema(Fields, Text) :-
    findall(Line,
            ( member(F-W, Fields),
              sql_type(W, T),
              format(atom(Line), "             ~w ~w not null,", [F, T])
            ),
            Lines),
    atomic_list_concat(Lines, '\n', Text).

sql_type(number, integer) :- !.
sql_type(_, text).

%   field_var(title, 'Title'): the plain Prolog variable name a
%   generated clause binds a field's value to -- field/3 always reads
%   INTO one of these, never into a dict slot.
field_var(F, Var) :-
    sub_atom(F, 0, 1, After, First),
    sub_atom(F, 1, After, 0, Rest),
    upcase_atom(First, FirstUp),
    atom_concat(FirstUp, Rest, Var).

%   "Title, Body" -- the field vars alone, in field order.
fields_vars(Fields, Text) :-
    findall(Var,
            ( member(F-_, Fields), field_var(F, Var) ),
            Vars),
    atomic_list_concat(Vars, ', ', Text).

%   "Id, Title, Body" -- what a record term's arguments look like:
%   the :id first, then one variable per field, in field order.
fields_record_pattern(Fields, Text) :-
    fields_vars(Fields, Vars),
    (   Vars == ''
    ->  Text = 'Id'
    ;   format(atom(Text), 'Id, ~w', [Vars])
    ).

%   "_, _" -- one wildcard per field, same count as fields_vars/2, for
%   patterns that only care about the record's :id.
fields_wild(Fields, Text) :-
    findall('_', member(_, Fields), Wilds),
    atomic_list_concat(Wilds, ', ', Text).

%   The field/3 extraction a model/3 clause runs against an already-
%   fetched Row, one field per line: "field(Row, title, Title),".
fields_extract(Fields, Text) :-
    findall(Line,
            ( member(F-_, Fields),
              field_var(F, Var),
              format(atom(Line), "    field(Row, ~w, ~w),", [F, Var])
            ),
            Lines),
    atomic_list_concat(Lines, '\n', Text).

%   The show page's field-by-field display, one line per field, all
%   plain variables -- model/3 already extracted them with field/3, so
%   there is nothing left for the template to reach into.
fields_show_lines(Fields, Text) :-
    findall(Line,
            ( member(F-_, Fields),
              field_var(F, Var),
              format(atom(Line), "        p([strong(\"~w: \"), text(~w)]),",
                     [F, Var])
            ),
            Lines),
    atomic_list_concat(Lines, '\n', Text).

first_field([F-_|_], F).

first_field_var(Fields, Var) :-
    first_field(Fields, F),
    field_var(F, Var).


		 /*******************************
		 *       NEW-APP TEMPLATES      *
		 *******************************/

tpl_config(App, _, C) :-
    format(atom(C),
"%% config/app.pl -- ~w configuration.
%%
%%   config(Key, Value).         base fact, every environment
%%   config(Env, Key, Value).    overlay, active when PROLOGEX_ENV=Env
%%
%% env('NAME', Default) values resolve against the OS environment at
%% lookup time, so PORT=3000 bin/px server just works -- even inside
%% a compiled px build binary.

config(port, env('PORT', 8090)).
config(workers, 1).
config(database, \"data/~w.db\").
", [App, App]).

tpl_layout(_, _, C) :-
    C = ":- module(layout, []).

/** <module> The application layout. Every page renders through
layout(Title, Content); owning this file means owning the whole
document. Keep the viewport meta tag -- it is what makes pages
render at phone width instead of as a scaled-down desktop page.
*/

:- use_module(library(prologex)).

layout(Title, Content) ~>
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
".

tpl_middleware(_, _, C) :-
    C = ":- module(app_middleware, []).

/** <module> Cross-feature concerns. A middleware is a plain relation
from one request env to the next; the pipeline below runs them in
order for every request. Add auth, rate limiting, request ids the
same way: define an env relation here, add one line to the pipeline.
A middleware that FAILS declines the request -- which is exactly the
right primitive for auth.
*/

:- use_module(library(prologex)).

:- pipeline([ log_requests,
              method_override,      % lets forms send PATCH/PUT/DELETE
              route_dispatch,       % the router; your pages run here
              turbo_frames          % trims responses for Turbo Frames
            ]).

log_requests(Env, Env) :-
    format(user_error, \"~w ~w~n\", [Env.method, Env.path]).
".

tpl_welcome(App, _, C) :-
    format(atom(C),
":- module(welcome_controller, []).

/** <module> The welcome page. Every page is served by a controller
like this one: model/3 gathers what the page needs, view/3 turns it
into markup. Generate a full create/read/update/delete feature to
replace this with something real:

    bin/px generate feature posts

*/

:- use_module(library(prologex)).

:- page(index, \"/\", [as(home)]).

model(index, _Env, m{app: \"~w\"}).

view(index, M, layout(M.app,
  [ h1([\"Welcome to \", M.app]),
    p(\"This page is app/welcome/controller.pl. Scaffold a working
       feature next to it:\"),
    p(code(\"bin/px generate feature posts\")),
    p(\"then restart the server and visit /posts.\")
  ])).
", [App]).

tpl_app_css(_, _, C) :-
    C = ":root {
  --bg: #0f1115;
  --panel: #161a21;
  --text: #e6e8eb;
  --muted: #9aa4b2;
  /* Radix Themes' own computed indicator color (rgb(62, 99, 221)),
    .
     be a pale sky-blue (#7dd3fc) that was readable with dark (#0f1115)
     text on top of it; #3E63DD is darker/more saturated and FAILS that
     same dark-on-accent pairing, hence the three companion vars below. */
  --accent: #3E63DD;
  /* On-accent foreground: use for any text/glyph painted on top of an
     --accent-filled background (buttons, checked switch/checkbox/toggle
     fills, ...). White clears WCAG AA comfortably against #3E63DD. */
  --accent-contrast: #ffffff;
  /* Hover/active variant of --accent -- a touch lighter, for filled
     accent surfaces (buttons, checked-state controls) on :hover. */
  --accent-hover: #5472e4;
  /* Lighter indigo for TEXT usage (links, inline accents) directly on
     the dark page background -- plain --accent reads too dark/low-
     contrast for body-copy-sized link text on #0f1115; matches Radix's
     own lighter indigo link tint on dark themes. */
  --accent-text: #849dff;
  --border: #262b34;
  --code-bg: #1c2129;
  --danger: #f87171;
}

* { box-sizing: border-box; }

html {
  /* Mobile browsers otherwise inflate text after rotation. */
  -webkit-text-size-adjust: 100%;
  text-size-adjust: 100%;
}

body {
  margin: 0;
  background: var(--bg);
  color: var(--text);
  font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", Helvetica, Arial, sans-serif;
  line-height: 1.6;
  color-scheme: dark;
}

/* Mobile-first: the narrow screen is the default; widths
   and paddings grow under min-width queries, never the reverse. */
.page {
  max-width: 760px;
  margin: 0 auto;
  padding: 1.5rem 1rem 3rem;
}

@media (min-width: 640px) {
  .page {
    padding: 2.5rem 1.5rem 4rem;
  }
}

h1, h2, h3, h4, h5, h6 {
  line-height: 1.25;
  color: var(--text);
  overflow-wrap: anywhere;
}

h1 { font-size: clamp(1.45rem, 4.5vw, 1.8rem); margin-bottom: 0.5rem; }
h2 { font-size: clamp(1.15rem, 3.5vw, 1.35rem); margin-top: 2rem; border-bottom: 1px solid var(--border); padding-bottom: 0.3rem; }
h3 { font-size: clamp(1rem, 3vw, 1.1rem); margin-top: 1.75rem; margin-bottom: 0.75rem; }

p { color: var(--text); }

a { color: var(--accent-text); text-decoration: none; }
a:hover { text-decoration: underline; }

/* Link + button(_to) rows -- edit/delete next to each other, etc.
   flex-wrap so a long label never forces horizontal scroll at 390px. */
.actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 1rem;
  margin: 1.25rem 0;
}

.back { margin-bottom: 1.5rem; }

code {
  background: var(--code-bg);
  padding: 0.15em 0.4em;
  border-radius: 4px;
  font-family: \"SF Mono\", Consolas, Menlo, monospace;
  font-size: 0.9em;
}

hr {
  border: none;
  border-top: 1px solid var(--border);
  margin: 2rem 0;
}

/* ---------------------------------------------------------------- */
/* Forms.       */
/* ---------------------------------------------------------------- */

form {
  max-width: 28rem;
  margin: 1.5rem 0 3rem;
  padding: 1.25rem;
  background: var(--panel);
  border: 1px solid var(--border);
  border-radius: 12px;
  /* A hairline top highlight plus a soft drop shadow read as a very
     slightly raised panel -- the flat-panel-on-flat-page look we kept hitting is otherwise indistinguishable from the
     page background at a glance. */
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.03);
}

@media (min-width: 640px) {
  form {
    padding: 1.75rem 2rem;
  }
}

.field {
  display: flex;
  flex-direction: column;
  margin-bottom: 1.6rem;
}

/* The submit button owns its own top margin (below) as the form's
   one clear \"done, now act\" pause -- so the last field doesn't also
   add a second, smaller gap on top of it. */
.field:last-of-type {
  margin-bottom: 0;
}

.field label {
  /* Sentence case, not shouty tiny-caps: humanize/2 already renders
     \"Title\", \"Commenter\", ... -- text-transform: uppercase fought
     that casing AND made 0.78rem read as illegibly cramped. Bumped
     size + a real margin below fixes both at once. */
  font-size: 0.875rem;
  font-weight: 600;
  color: var(--muted);
  margin-bottom: 0.5rem;
}

input[type=\"text\"],
input[type=\"email\"],
input[type=\"password\"],
input[type=\"number\"],
textarea,
select {
  width: 100%;
  max-width: 28rem;
  min-height: 2.75rem;
  background: var(--bg);
  color: var(--text);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 0.6rem 0.85rem;
  font-size: 0.95rem;
  font-family: inherit;
  line-height: 1.4;
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}

textarea {
  min-height: 8rem;
  resize: vertical;
}

::placeholder {
  color: var(--muted);
  opacity: 1;
}

input[type=\"text\"]:focus,
input[type=\"email\"]:focus,
input[type=\"password\"]:focus,
input[type=\"number\"]:focus,
textarea:focus,
select:focus {
  outline: none;
  border-color: var(--accent);
  box-shadow: 0 0 0 3px rgba(62, 99, 221, 0.25);
}

/* A left accent bar groups label + input + error under one visual
   cue, on top of the input's own red border, so an errored field
   still reads at a glance even scanning fast down a long form. */
.field-error {
  border-left: 3px solid var(--danger);
  padding-left: 0.75rem;
}

.field-error input[type=\"text\"],
.field-error input[type=\"email\"],
.field-error input[type=\"password\"],
.field-error input[type=\"number\"],
.field-error textarea,
.field-error select {
  border-color: var(--danger);
}

.field-error input[type=\"text\"]:focus,
.field-error input[type=\"email\"]:focus,
.field-error input[type=\"password\"]:focus,
.field-error input[type=\"number\"]:focus,
.field-error textarea:focus,
.field-error select:focus {
  box-shadow: 0 0 0 3px rgba(248, 113, 113, 0.25);
}

p.error {
  color: var(--danger);
  font-size: 0.82rem;
  /* Tight to the input above it (attached), looser from whatever
     follows (the next field's label) -- .field's own margin-bottom
     already supplies that trailing space. */
  margin: 0.45rem 0 0;
}

form button,
form input[type=\"submit\"],
button[type=\"submit\"],
input[type=\"submit\"] {
  display: inline-block;
  /* The one clear \"you're done with the fields\" pause before the
     submit row (button_to overrides this back to 0 below -- it is
     not a fielded form). */
  margin-top: 2rem;
  background: var(--accent);
  /* was #0f1115 (dark) -- readable on the old pale #7dd3fc, fails on
     the new saturated #3E63DD indigo; --accent-contrast is white. */
  color: var(--accent-contrast);
  border: none;
  border-radius: 8px;
  padding: 0.7rem 1.75rem;
  font-size: 0.95rem;
  font-weight: 600;
  cursor: pointer;
  transition: background 0.15s ease;
}

form button:hover,
form input[type=\"submit\"]:hover,
button[type=\"submit\"]:hover,
input[type=\"submit\"]:hover {
  background: var(--accent-hover);
}

/* Full-width, comfortably tappable submit on narrow screens. */
@media (max-width: 480px) {
  form:not(.button-to) button,
  form:not(.button-to) input[type=\"submit\"] {
    width: 100%;
    padding: 0.8rem 1.5rem;
  }
}

/* button_to: a single button that IS a form -- no panel, no
   spacing; it sits inline next to links. */
form.button-to {
  display: inline;
  max-width: none;
  margin: 0;
  padding: 0;
  background: none;
  border: none;
}

form.button-to button {
  margin-top: 0;
  background: none;
  border: 1px solid var(--border);
  border-radius: 6px;
  color: var(--danger);
  font-weight: 500;
  font-size: 0.875rem;
  padding: 0.4rem 0.9rem;
}

/* A danger-tinted wash, not var(--panel) -- these buttons often sit
   ON a panel background themselves (comment cards), where a
   panel-colored hover would have been invisible. */
form.button-to button:hover {
  background: rgba(248, 113, 113, 0.1);
  border-color: var(--danger);
}

form button:focus-visible,
form input[type=\"submit\"]:focus-visible {
  outline: none;
  box-shadow: 0 0 0 3px rgba(62, 99, 221, 0.35);
}

/* ---------------------------------------------------------------- */
/* Cards (comment_card / article.card).                             */
/* ---------------------------------------------------------------- */

article.card {
  background: var(--panel);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 1.1rem 1.35rem;
  margin-bottom: 1rem;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.3);
}

article.card p {
  margin: 0.4rem 0;
}

article.card p:first-child {
  margin-top: 0;
}

article.card strong {
  /* var(--accent) is tuned for filled surfaces (adr'd at the top of
     this file); a commenter's name is body-copy-sized TEXT, exactly
     the case --accent-text exists for -- plain --accent under-
     contrasts here the same way it would in a paragraph link. */
  color: var(--accent-text);
  font-size: 1.02rem;
}

article.card small {
  color: var(--muted);
  font-size: 0.82rem;
}

/* button_to with no .actions wrapper (comment_card's own Delete) --
   a little breathing room from the timestamp line above it. */
article.card > form.button-to {
  display: inline-block;
  margin-top: 0.6rem;
}
".

tpl_app_js(_, _, C) :-
    C = "// assets/js/app.js -- served through the import map; plain ES
// modules, no build step. Import component elements as you use
// them, e.g.:
//   import \"components/switch\";
".

tpl_bin_px(_, Home, C) :-
    format(atom(C),
"#!/usr/bin/env bash
# The px CLI, tied to the framework checkout below.
set -euo pipefail
export PX_HOME=\"${PX_HOME:-~w}\"
exec \"$PX_HOME/bin/px\" \"$@\"
", [Home]).

tpl_bin_server(_, _, C) :-
    C = "#!/usr/bin/env bash
# Boot this app: dev and production, same entry. Port, worker count
# and database path live in config/app.pl.
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
    bin/px generate feature X  # scaffold a working CRUD feature
    bin/px build               # one deployable executable
", [App]).


		 /*******************************
		 *      FEATURE TEMPLATES       *
		 *******************************/

:- use_module(library(apply), [foldl/4]).

%   Placeholder substitution beats positional format args for
%   templates this size: {{feature}}, {{sing}} etc. are replaced
%   everywhere they occur.
render_tpl(Template, Pairs, Out) :-
    foldl(subst_one, Pairs, Template, Out).

subst_one(Key-Value, In, Out) :-
    atomic_list_concat(Parts, Key, In),
    atomic_list_concat(Parts, Value, Out).

feature_pairs(Name, Sing, Fields,
              [ '{{feature}}'-Name,
                '{{sing}}'-Sing,
                '{{form_fields}}'-FormDecl,
                '{{schema}}'-Schema,
                '{{show_lines}}'-ShowLines,
                '{{first_field}}'-First,
                '{{first_field_var}}'-FirstVar,
                '{{record_vars}}'-RecordVars,
                '{{record_pattern}}'-RecordPattern,
                '{{record_wild}}'-RecordWild,
                '{{field_extract}}'-FieldExtract
              ]) :-
    fields_form_decl(Fields, FormDecl),
    fields_schema(Fields, Schema),
    fields_show_lines(Fields, ShowLines),
    first_field(Fields, First),
    first_field_var(Fields, FirstVar),
    fields_vars(Fields, RecordVars),
    fields_record_pattern(Fields, RecordPattern),
    fields_wild(Fields, RecordWild),
    fields_extract(Fields, FieldExtract).

tpl_feature_controller(Name, Sing, Fields, C) :-
    feature_pairs(Name, Sing, Fields, Pairs),
    T = ':- module({{feature}}_controller, []).

/** <module> {{feature}}: routes, actions, and the request cycle.

How a request flows through this file:

    GET      model(Action, Env, Model) then view(Action, Model, Html)
    non-GET  model(Action, Env, M0)   then update(Msg, M0, M, Effects)

Rules you can rely on:

  - model/3 FAILING is the 404. There is no explicit not-found
    handling anywhere in this file, and none is needed.
  - Forms are validated before update/4 ever runs: a form named F
    (declared in messages.pl) arrives as F(ok(Values)) or
    F(invalid(Values, Errors)).
  - Effects are data, not actions: redirect(PathTerm), status(Code),
    turbo(Streams). No redirect means "render this action\'s view".
  - A form posts to the SAME page that renders it, so an invalid
    submission re-renders that page with the errors filled in. That
    is why the create form posts to /{{feature}}/new and the update
    form to /{{feature}}/:id/edit -- look at views.pl.
  - A database row is a Key-Value pairs list, never a dict: field/3
    reads one column (and throws on a typo\'d one, loudly, rather
    than failing silently). model/3 below reads every column a page
    needs into a plain, named variable BEFORE the view ever runs --
    the view works with those variables, never with a row.
*/

:- use_module(library(prologex)).
:- use_module(library(apply), [maplist/3]).        % summarize_{{sing}}/2 over the row list
:- use_module(app({{feature}}/messages), []).      % the form declarations
:- use_module(app({{feature}}/model), [empty/1]).  % the pure core; its update/3
                                          % is called qualified below, because
                                          % library(prologex) already provides
                                          % an update/3 (the SQL UPDATE)
:- use_module(app({{feature}}/commands)).          % every database read/write
:- use_module(app({{feature}}/views), []).         % the templates

%   Declaration order is match order: /{{feature}}/new must come
%   before /{{feature}}/:id, or the word "new" would be captured as
%   an :id. Each page gets a path helper usable anywhere a path is
%   expected -- links, redirects, form actions.

:- page(index, "/{{feature}}").                            %% {{feature}}_path
:- page(new,   "/{{feature}}/new",      [as(new_{{sing}})]).   %% new_{{sing}}_path
:- page(show,  "/{{feature}}/:id",      [as({{sing}})]).       %% {{sing}}_path(Id)
:- page(edit,  "/{{feature}}/:id/edit", [as(edit_{{sing}})]).  %% edit_{{sing}}_path(Id)

%   Everything below is PUBLIC until you say otherwise. Once you
%   have authentication (bin/px generate px:auth), uncomment this
%   block to keep reading public and writing signed-in-only --
%   authorize/2 failing sends the visitor to the sign-in page.
%   Pages authorize by ACTION (an atom); messages authorize by the
%   decoded MESSAGE TERM (a compound) -- writes post to the paths of
%   public pages, so the catch-all guarding both shapes is what
%   actually protects them. Open a message to everyone by shape:
%   authorize(some_msg(_), _Env).
%
%   :- use_module(app(shared/auth), [require_user/1]).
%
%   authorize(index, _Env).                        %% anyone
%   authorize(show,  _Env).                        %% anyone
%   authorize(_,     Env) :- require_user(Env).    %% new/edit + every write
%
%   To also HIDE the admin links from signed-out readers, add a flag
%   argument to the page(...) model term below, set it from
%   signed_in(Env) in model/3, and give the actions row two template
%   clauses in views.pl -- one matching a true flag that renders
%   them, one matching false that renders nothing.

%   The model is one small tagged term shared by every action in this
%   file, page(Rows, Record, Values, Errors):
%
%     Rows     a list of {{sing}}_summary(Id, First, Created) terms,
%              used by the index page.
%     Record   a {{sing}}(Id, ...) term, one argument per field, or
%              the atom `none`; used by the show and edit pages.
%     Values   the current form values as a Key-Value pairs list; []
%              until a form is involved.
%     Errors   the current form\'s error(Field, Message) list, or [].
%
%   Every action leaves the fields it does not need at their empty/1
%   defaults -- the view for that action only ever looks at the parts
%   it uses (see below), the same way a template only matches the
%   shape it expects.

%   model(Action, Env, Model): gather everything the page needs.
%   path_id/3 reads an integer :id from the URL and FAILS on
%   anything else -- and a failing model is the 404, so
%   /{{feature}}/notanumber never reaches your code.

model(index, _Env, M) :-
    all_{{feature}}(Rows),
    maplist(summarize_{{sing}}, Rows, Summaries),
    empty(M0),
    {{feature}}_model:update(loaded(Summaries), M0, M).
model(new, _Env, M) :-
    empty(M).
model(show, Env, M) :-
    path_id(Env, id, Id),
    find_{{sing}}(Id, Row),
{{field_extract}}
    empty(M0),
    {{feature}}_model:update(found({{sing}}({{record_pattern}})), M0, M).
model(edit, Env, M) :-
    path_id(Env, id, Id),
    find_{{sing}}(Id, Row),
{{field_extract}}
    empty(M0),
    {{feature}}_model:update(editing({{sing}}({{record_pattern}}), Row), M0, M).

%   A row -> its index-card summary: the :id, the one field the card
%   shows, and when it was created -- the only parts {{sing}}_card
%   (views.pl) needs, read out with field/3 once, here, so the view
%   never has to.
summarize_{{sing}}(Row, {{sing}}_summary(Id, First, Created)) :-
    field(Row, id, Id),
    field(Row, {{first_field}}, First),
    field(Row, created_at, Created).

%   view(Action, Model, Html): pure -- model in, template term out.
%   Each clause destructures Model down to the plain variables its
%   own page needs; the templates in views.pl never see a row or the
%   page(...) term itself.

view(index, page(Rows, _, _, _), {{sing}}_index(Rows)).
view(new,   page(_, _, Values, Errors), {{sing}}_new(Values, Errors)).
view(show,  page(_, {{sing}}({{record_pattern}}), _, _), {{sing}}_show({{record_pattern}})).
view(edit,  page(_, {{sing}}(Id, {{record_wild}}), Values, Errors), {{sing}}_edit(Id, Values, Errors)).

%   update(Msg, Model0, Model, Effects): run the side effect through
%   commands.pl, fold the outcome into the model, answer with
%   effects. Model0 comes from whichever page\'s model/3 the form
%   posted to -- on show/edit pages, Model0\'s Record already carries
%   the :id that update/destroy need, no re-parsing required.

update(create_{{sing}}(ok(Values)), _M0, M, [redirect({{sing}}_path(Id))]) :-
    save_{{sing}}(Values, Row),
{{field_extract}}
    field(Row, id, Id),
    empty(M1),
    {{feature}}_model:update(found({{sing}}({{record_pattern}})), M1, M).
update(create_{{sing}}(invalid(Values, Errors)), M0, M, [status(422)]) :-
    {{feature}}_model:update(rejected(Values, Errors), M0, M).

update(update_{{sing}}(ok(Values)), M0, M, [redirect({{sing}}_path(Id))]) :-
    M0 = page(_, {{sing}}(Id, {{record_wild}}), _, _),
    revise_{{sing}}(Id, Values, Row),
{{field_extract}}
    empty(M1),
    {{feature}}_model:update(found({{sing}}({{record_pattern}})), M1, M).
update(update_{{sing}}(invalid(Values, Errors)), M0, M, [status(422)]) :-
    {{feature}}_model:update(rejected(Values, Errors), M0, M).

update(destroy_{{sing}}(ok(_)), M0, M0, [redirect({{feature}}_path)]) :-
    M0 = page(_, {{sing}}(Id, {{record_wild}}), _, _),
    remove_{{sing}}(Id).
',
    render_tpl(T, Pairs, C).

tpl_feature_messages(Name, Sing, Fields, C) :-
    feature_pairs(Name, Sing, Fields, Pairs),
    T = ':- module({{feature}}_messages, []).

/** <module> {{feature}}\'s messages: what the outside world may ask
of it.

A form declaration is both the validator and the renderer:
form_for/4 in a view renders these exact fields, and a submission is
validated against them BEFORE the controller\'s update/4 runs -- so
update only ever sees create_{{sing}}(ok(Values)) or
create_{{sing}}(invalid(Values, Errors)). The form\'s name is the
message name; form_for adds it to the submission automatically as a
hidden input.

Constraint vocabulary: required, max_length(N), min_length(N),
numeric, range(Lo, Hi), format(Regex), in(List), check(Pred).
Widgets: text, textarea, email, password, number, checkbox,
select(Options), hidden.
*/

:- use_module(library(prologex)).

:- form(create_{{sing}},
     [
{{form_fields}}
     ]).

:- form(update_{{sing}},
     [
{{form_fields}}
     ]).

%   Destroy carries no data -- the form exists so the intent arrives
%   as a named message like every other write.
:- form(destroy_{{sing}}, []).
',
    render_tpl(T, Pairs, C).

tpl_feature_model(Name, Sing, Fields, C) :-
    feature_pairs(Name, Sing, Fields, Pairs),
    T = ':- module({{feature}}_model,
          [ empty/1,                % -Model
            update/3                % +DomainMsg, +Model0, -Model
          ]).

/** <module> {{feature}}\'s pure core: what the feature KNOWS, with
no notion of HTTP or storage. Domain messages fold over the model --
each update/3 clause is one fact about the domain. Import nothing
from the framework here; this module must load and test with plain
SWI-Prolog.

The model is one small tagged term, page(Rows, Record, Values,
Errors):

  - Rows    a list of {{sing}}_summary(Id, First, Created) terms, used
            by the index page.
  - Record  a {{sing}}(Id, ...) term with one argument per field, or
            the atom `none`; used by the show and edit pages.
  - Values  the current form values as a Key-Value pairs list (read
            with field_value/3), or [] when no form is in play.
  - Errors  the current form\'s error(Field, Message) list, or [].

Every field of the tuple is present on every action, even the ones a
given page ignores -- the controller\'s view/3 clauses pick out only
the parts each page needs by matching the shape they expect (see
controller.pl), the same way the templates in views.pl do.

Note the style: no if-then-else, one clause per message. Templates
work the same way (see views.pl).
*/

empty(page([], none, [], [])).

update(loaded(Rows), page(_, R, V, E), page(Rows, R, V, E)).
update(found(Record), page(Rs, _, V, E), page(Rs, Record, V, E)).
update(editing(Record, Values), page(Rs, _, _, _), page(Rs, Record, Values, [])).
update(rejected(Values, Errors), page(Rs, R, _, _), page(Rs, R, Values, Errors)).
',
    render_tpl(T, Pairs, C).

tpl_feature_commands(Name, Sing, Fields, C) :-
    feature_pairs(Name, Sing, Fields, Pairs),
    T = ':- module({{feature}}_commands,
          [ all_{{feature}}/1,      % -Rows, newest first
            find_{{sing}}/2,        % +Id, -Row (fails if absent)
            save_{{sing}}/2,        % +Values, -Row
            revise_{{sing}}/3,      % +Id, +Values, -Row
            remove_{{sing}}/1       % +Id
          ]).

/** <module> Every {{feature}} side effect, reads and writes, named
as verbs. This is the only file in the feature that touches the
database; the table\'s schema rides with it and is applied
automatically when the database opens.

A query is a term: q(Table, Clauses) with where/order_by/limit
clauses; row/2 yields one row per solution, as a Key-Value pairs
list -- field/3 reads one column, and throws (loudly, not silently)
on a typo\'d one. insert/3, update/3 and delete/2 are the write
side, taking a Key-Value pairs list of the columns to write.
*/

:- use_module(library(prologex)).

:- schema("create table if not exists {{feature}} (
             id integer primary key,
{{schema}}
             created_at text not null default current_timestamp)").

all_{{feature}}(Rows) :-
    findall(R, row(q({{feature}}, [order_by(desc(id))]), R), Rows).

%   Fails (no exception) when the id is absent: the calling model/3
%   fails with it, and that failure is the 404.
find_{{sing}}(Id, Row) :-
    once(row(q({{feature}}, [where(id == Id)]), Row)).

save_{{sing}}(Values, Row) :-
    insert({{feature}}, Values, Id),
    find_{{sing}}(Id, Row).

revise_{{sing}}(Id, Values, Row) :-
    update({{feature}}, Values, id == Id),
    find_{{sing}}(Id, Row).

remove_{{sing}}(Id) :-
    delete({{feature}}, id == Id).
',
    render_tpl(T, Pairs, C).

tpl_feature_views(Name, Sing, Fields, C) :-
    feature_pairs(Name, Sing, Fields, Pairs),
    T = ':- module({{feature}}_views, []).

/** <module> {{feature}}\'s templates: pure, model in, markup out --
they never see the request. Elements are plain terms (h1(...),
div(...)); strings escape automatically; attribute values that look
like path helpers ({{sing}}_path(Id)) resolve to real URLs anywhere
they appear.

Every template here takes PLAIN VARIABLES, never a row and never the
page(...) model term itself: controller.pl\'s model/3 and view/3
already picked each field out by name (field/3, or a plain pattern
match on an already-built record term) before a template ever runs,
so there is nothing left here to reach into -- exactly the point of
{{sing}}_card below, which destructures its one argument in its own
clause head rather than calling an accessor in its body.

Template names and path helpers are global across the app: any
feature\'s views may use another\'s, with no imports. Prefix generic
template names with the feature name so they never collide.

IMPORTANT: a template body is data, not code -- there is no
if-then-else inside one. To branch, write one clause per case and
let matching choose (see {{sing}}_list below: one clause for the
empty list, one for everything else). The framework rejects
(Cond -> A ; B) inside a template at load time for exactly this
reason.
*/

:- use_module(library(prologex)).

{{sing}}_index(Rows) ~>
    layout("{{feature}}",
      [ h1("{{feature}}"),
        p(class(actions), link_to("New {{sing}}", new_{{sing}}_path)),
        {{sing}}_list(Rows)
      ]).

{{sing}}_list([]) ~>
    p(class(empty), "No {{feature}} yet -- create the first one.").
{{sing}}_list(Rows) ~>
    each(Rows, {{sing}}_card).

%   {{sing}}_summary(...) is the exact term controller.pl\'s
%   summarize_{{sing}}/2 builds for each row -- matching it here, in
%   the clause head, IS how this template destructures a row, with no
%   accessor call anywhere in its body.
{{sing}}_card({{sing}}_summary(Id, First, Created)) ~>
    article(class(card),
      [ h2(link_to(First, {{sing}}_path(Id))),
        p(small(["created ", Created]))
      ]).

{{sing}}_show(Id, {{record_vars}}) ~>
    layout({{first_field_var}},
      [ p(link_to("← all {{feature}}", {{feature}}_path)),
        h1({{first_field_var}}),
{{show_lines}}
        div(class(actions),
          [ link_to("Edit", edit_{{sing}}_path(Id)),
            button_to("Delete {{sing}}", destroy_{{sing}},
                      delete({{sing}}_path(Id)))
          ])
      ]).

%   The create form posts to THIS page\'s own path (new_{{sing}}_path),
%   so an invalid submission re-renders this page: 422, errors
%   inline, values refilled -- all automatic.
{{sing}}_new(Values, Errors) ~>
    layout("New {{sing}}",
      [ p(link_to("← all {{feature}}", {{feature}}_path)),
        h1("New {{sing}}"),
        form_for(create_{{sing}}, new_{{sing}}_path, Values, Errors)
      ]).

%   Same principle: the update form posts back to the edit page.
%   patch(...) makes the form submit as a PATCH.
{{sing}}_edit(Id, Values, Errors) ~>
    layout("Edit",
      [ p(link_to("← back", {{sing}}_path(Id))),
        h1("Edit"),
        form_for(update_{{sing}}, patch(edit_{{sing}}_path(Id)), Values, Errors)
      ]).
',
    render_tpl(T, Pairs, C).
