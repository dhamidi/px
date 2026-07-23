:- module(px_build,
          [ build/1              % +Options
          ]).

/** <module> `px build`: the app as one executable (adr/0033).

build/1 runs the boot's load phase -- prologex_load/0, exactly what a
server boot does short of opening a port: config, app tree, routes,
forms, pipeline, layout, compiled and hashed assets, and whatever
load-time directives an app declared (the adrs feature's adr_doc/2
facts are the worked example) -- then bakes public/assets/ into
asset_blob/2 facts (px_assets:bake_asset_blobs/0) and hands the whole
resulting Prolog database to qsave_program/2: `stand_alone(true)` +
`foreign(save)` produce one ELF that carries its own zip-archived
state and its loaded foreign libraries (adr/0033 discovery 1 -- ONLY
libraries loaded through the `foreign(...)` alias are savable this
way; the four loader modules register and use that alias already),
with `goal(prologex:prologex_serve)` as the binary's entry point: it
opens the port and blocks, none of the load phase runs again.

prologex_load/0 is idempotent (config reload replaces its clauses;
route/pipeline/layout registration all check-before-install; asset
compilation re-hashes to the same names) so build/1 does not bother
guarding against a caller that already loaded the app -- it just
calls it.
*/

:- use_module(library(qsave)).
:- use_module(library(option)).
:- use_module(library(filesex)).

%   Sibling imports per adr/0030: the spec is the location.
:- use_module(prologex, [prologex_load/0, prologex_serve/0]).
:- use_module(px_assets, [bake_asset_blobs/0]).

%!  build(+Options) is det.
%
%   Options is a list; supported: out(File) -- the output path,
%   defaulting to the current directory's base name (e.g. an app
%   checked out at .../myapp builds "myapp"). Throws whatever
%   prologex_load/0 throws when the app in cwd fails to load (adr/
%   0033: "the build is also a smoke test"), and re-throws a clear
%   error naming a foreign library loaded outside the `foreign(...)`
%   alias when qsave_program/2 fails.
build(Options) :-
    out_file(Options, File),
    format(user_error, "px build: loading application...~n", []),
    prologex:prologex_load,
    format(user_error, "px build: baking asset blobs...~n", []),
    px_assets:bake_asset_blobs,
    format(user_error, "px build: saving state to ~w...~n", [File]),
    save_state(File),
    report_built(File).

out_file(Options, File) :-
    (   option(out(File0), Options)
    ->  File = File0
    ;   default_out_file(File)
    ).

%   The current directory's base name -- cwd is the app directory
%   (bin/server's own convention: cd there, then load by convention).
default_out_file(File) :-
    working_directory(CWD, CWD),
    ( sub_atom(CWD, _, 1, 0, '/') -> sub_atom(CWD, 0, _, 1, CWD1) ; CWD1 = CWD ),
    file_base_name(CWD1, File).

%!  save_state(+File) is det.
%
%   1GB stack -- generous headroom for a long-running server, cheap
%   (virtual, not resident, until actually used). `autoload(false)`:
%   qsave's own default (true) does a global scan for every predicate
%   still-undefined-but-autoloadable ANYWHERE in the loaded database,
%   including inside SWI system libraries this app merely transitively
%   imports, not just what prologex_load/0's own code path reaches --
%   tested against this app that scan chases a stale reference into
%   library(http/http_wrapper), which does its own use_module(http_
%   stream) and collides with this framework's OWN module of that
%   name (prolog/http_stream.pl), printing a load-time warning that
%   has nothing to do with anything this binary actually serves.
%   autoload(false) skips that speculative scan; it does not drop
%   anything real, because every predicate the app can actually reach
%   at runtime -- library(pcre)'s re_match/2 included, imported by
%   px_form.pl whether or not the loaded app's own forms happen to
%   declare a format/1 constraint that calls it -- was already loaded
%   for real (not left as an autoload stub) by the ordinary
%   use_module/1 directives that ran during prologex_load/0, well
%   before qsave_program/2 sees the database.
save_state(File) :-
    (   qsave_program(File,
                       [ stand_alone(true),
                         foreign(save),
                         goal(prologex:prologex_serve),
                         stack_limit(1_073_741_824),
                         autoload(false)
                       ])
    ->  true
    ;   report_qsave_failure,
        throw(error(px_build(qsave_failed),
                    context(px_build:build/1,
                            'qsave_program/2 returned false -- see stderr for the unsavable foreign library it just listed')))
    ).

%   qsave_program/2 fails silently (adr/0033 discovery 1) when some
%   loaded foreign library was found by an absolute path rather than
%   through the `foreign(...)` search-path alias. current_foreign_
%   library/2 lists every loaded foreign object and the file spec it
%   was loaded through; anything not of the shape foreign(_) is the
%   culprit qsave could not embed.
report_qsave_failure :-
    format(user_error,
           "px build: qsave_program/2 failed -- currently loaded foreign libraries:~n", []),
    forall(current_foreign_library(Path, Specs),
           format(user_error, "  ~w  (loaded via ~q)~n", [Path, Specs])).

report_built(File) :-
    absolute_file_name(File, Abs),
    size_file(Abs, Bytes),
    KB is Bytes / 1024,
    MB is Bytes / (1024*1024),
    format(user_error, "px build: wrote ~w (~1f MB / ~0f KB)~n", [Abs, MB, KB]).
