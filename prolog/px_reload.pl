:- module(px_reload,
          [ maybe_reload/2,      % +Stream, -Handled
            record_boot_state/0
          ]).

/** <module> Hot reload for app code in development (adr/0036).

Before each request, in development only, px_request/3 (prologex.pl)
calls maybe_reload/2: scan the mtimes of every loaded file under
app/ (and config/app.pl -- tracked_file/1 below) and reload any that
changed since last seen, via load_files(F, [if(true)]), BEFORE the
request is dispatched. Outside development this predicate is a no-op
(Handled = false, nothing scanned) -- a production boot never pays
for or executes any of this.

Route registration (:- initialization(register_route(...), now),
adr/0018) already retracts any existing route/4 fact of the same
Name before asserting (router:add_route/4), so a reload re-running
those directives replaces the route rather than duplicating it --
no change needed there for this ADR.

THE HAZARD this module exists to handle: a syntax error in the file
being edited. Empirically (verified by hand while building this),
SWI's reload of an already-loaded file clears ALL of that file's
owned clauses up front, before re-reading it -- so a bare
catch/3 around load_files/2 is not enough: even with the
syntax_errors(error) option (which turns the syntax error into a
catchable exception instead of load_files' default
print-and-skip-that-clause behaviour), by the time the exception is
thrown the file's predicates are already gone. So every changed file
is handled as: (1) attempt the real reload from disk, catching any
exception; (2) on success, cache the new source text as the file's
"last known good" content and move on; (3) on failure, reload the
file's OWN PATH again but this time from the cached last-good text
via load_files/2's stream(Stream) option -- same nominal File, so
SWI's per-file ownership bookkeeping (source_file/1 et al) and this
module's own mtime tracking both stay consistent -- restoring the
predicates the failed attempt wiped, and report the error for the
request that discovered it. The worker never crashes and a request
never gets a silent 500: reload failures come back as a plain-text
500 naming the file and the error (a rich dev error page is future
work, per the ADR).

Tracking is mostly thread_local: each worker thread reloads
independently on its own thread (workers > 1 is fine, adr/0005) with
no lock and no shared mutable state for the steady-state edit loop --
exactly the "no watcher thread, no new threads" design adr/0036 calls
for. The one piece of shared (ordinary dynamic, not thread_local)
state is px_reload_boot/3, written once by record_boot_state/0 right
after prologex_load/0 finishes loading the app (prologex.pl):
snapshot mtime + source text of every tracked file as it stood at the
end of boot. A worker thread's first-ever look at a file compares the
CURRENT disk mtime against that boot snapshot, not just "whatever I
see the first time I look" -- otherwise a file edited between boot
finishing and a given worker's first request would have its edit
silently missed by that worker until a LATER edit (caught by hand
while building this: the file's disk mtime already differs from what
is loaded the very first time that worker looks at it, so "first
sighting = just record a baseline, no reload" would adopt the EDITED
mtime as baseline without ever having reloaded the edit). Comparing
against the boot snapshot instead means: mtime unchanged since boot
-> genuinely nothing to do; mtime changed since boot -> handle it
exactly like any other detected change, reloading it before this
first request runs.
*/

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(px_config, [current_env/1]).
:- use_module(response,  [reply_error/3]).

%   px_reload_mtime(File, Mtime): last mtime this worker thread has
%   either (a) seen at first sighting, or (b) finished handling
%   (successfully or not) a change for.
:- thread_local px_reload_mtime/2.
%   px_reload_good(File, Content): the last successfully-loaded
%   source text for File, as a string -- the restore target on a
%   failed reload.
:- thread_local px_reload_good/2.
%   px_reload_boot(File, Mtime, Content): NOT thread_local -- written
%   once, by record_boot_state/0, from the boot (main) thread right
%   after prologex_load/0 finishes. The ground truth every worker
%   thread's first-ever look at a file is checked against (see the
%   module doc above).
:- dynamic px_reload_boot/3.

%!  record_boot_state is det.
%
%   Snapshot mtime + source text of every tracked file as it stands
%   right now. Called once, from prologex.pl's prologex_load/0, after
%   the app tree has finished loading -- so "now" is exactly "what is
%   actually loaded in the shared predicate database", the reference
%   point every worker thread's first sighting of a file is compared
%   against.
record_boot_state :-
    retractall(px_reload_boot(_, _, _)),
    tracked_files(Files),
    forall(member(F, Files), record_boot_file(F)).

record_boot_file(F) :-
    catch(time_file(F, Mtime), _, fail),
    !,
    catch(read_file_to_string(F, Content, []), _, Content = ""),
    assertz(px_reload_boot(F, Mtime, Content)).
record_boot_file(_).


                 /*******************************
                 *            ENTRY             *
                 *******************************/

%!  maybe_reload(+Stream, -Handled) is det.
%
%   Outside development: Handled = false immediately, nothing else
%   runs. In development: scan every tracked file; changed ones are
%   reloaded. If every reload attempt (if any) succeeded, Handled =
%   false and the caller proceeds to dispatch the request normally.
%   If any reload failed, a plain-text 500 explaining why has already
%   been written to Stream (response:reply_error/3) and Handled =
%   true -- the caller must not dispatch the request further.
maybe_reload(Stream, Handled) :-
    (   current_env(development)
    ->  tracked_files(Files),
        check_files(Files, Errors),
        (   Errors == []
        ->  Handled = false
        ;   respond_reload_errors(Stream, Errors),
            Handled = true
        )
    ;   Handled = false
    ).


                 /*******************************
                 *      TRACKED FILE SET        *
                 *******************************/

%!  tracked_files(-Files) is det.
%
%   Every currently-loaded file (source_file/1) that lives under the
%   app/ tree or is config/app.pl -- exactly adr/0036's "every loaded
%   file under app/ (and config/app.pl)". Resolved fresh on every
%   call (cheap: two absolute_file_name/2-ish lookups plus a linear
%   scan of source_file/1) so an app started once and never
%   restarted still tracks correctly regardless of thread.
tracked_files(Files) :-
    findall(F, tracked_file(F), Files0),
    sort(Files0, Files).

%   No cut here: source_file/1 is the thing findall/3 (tracked_files/1)
%   needs to backtrack over to visit every loaded file. A cut in this
%   clause -- even one meant only to stop the app_dir/config_app_file
%   disjunction from yielding two solutions for the same F -- would
%   also cut away that backtracking and silently truncate the file
%   list to one entry (caught by hand while building this: sort/2 in
%   tracked_files/1 already dedupes, so no cut is needed at all).
tracked_file(F) :-
    source_file(F),
    (   app_dir(AppDir),
        under_dir(F, AppDir)
    ;   config_app_file(F)
    ).

app_dir(Dir) :-
    user:file_search_path(app, Dir),
    !.

under_dir(F, Dir) :-
    atom_concat(Dir, '/', DirSlash),
    sub_atom(F, 0, _, _, DirSlash).

config_app_file(F) :-
    exists_file('config/app.pl'),
    absolute_file_name('config/app.pl', F).


                 /*******************************
                 *      CHECK / RELOAD LOOP      *
                 *******************************/

%!  check_files(+Files, -Errors) is det.
%
%   Errors is a list of File-Error pairs, one per file whose reload
%   attempt failed this pass (usually empty).
check_files([], []).
check_files([F|Fs], Errors) :-
    check_file(F, Errors0),
    check_files(Fs, Errors1),
    append(Errors0, Errors1, Errors).

check_file(F, Errors) :-
    catch(time_file(F, Mtime), _, fail),
    !,
    (   px_reload_mtime(F, Seen)
    ->  (   Mtime =:= Seen
        ->  Errors = []
        ;   handle_change(F, Mtime, Errors)
        )
    ;   first_sighting(F, Mtime, Errors)
    ).
check_file(_, []).     % file vanished since last seen -- ignore it

%!  first_sighting(+File, +Mtime, -Errors) is det.
%
%   This worker thread has never looked at File before. Compare
%   against the boot-time snapshot (record_boot_state/0): if File's
%   mtime has not moved since boot, what is loaded right now already
%   matches disk -- just adopt the boot content as this thread's
%   baseline, no reload. If it HAS moved (edited between boot
%   finishing and this thread's first request), seed the baseline
%   from the boot content (so a failed reload still has something
%   correct to restore to) and handle it exactly like any other
%   detected change.
first_sighting(F, Mtime, Errors) :-
    (   px_reload_boot(F, BootMtime, BootContent)
    ->  (   Mtime =:= BootMtime
        ->  asserta(px_reload_mtime(F, Mtime)),
            asserta(px_reload_good(F, BootContent)),
            Errors = []
        ;   asserta(px_reload_good(F, BootContent)),
            handle_change(F, Mtime, Errors)
        )
    ;   % Not present at boot (e.g. record_boot_state/0 never ran) --
        % fall back to establishing a baseline from disk right now,
        % same as before this refinement.
        catch(read_file_to_string(F, Content, []), _, Content = ""),
        asserta(px_reload_mtime(F, Mtime)),
        asserta(px_reload_good(F, Content)),
        Errors = []
    ).

%!  handle_change(+File, +NewMtime, -Errors) is det.
%
%   File's mtime changed since last seen. The tracked mtime is
%   updated to NewMtime up front, success or failure, so a file that
%   fails to reload is not retried every single request -- only when
%   it changes again (fixed, or edited further).
handle_change(F, NewMtime, Errors) :-
    retractall(px_reload_mtime(F, _)),
    asserta(px_reload_mtime(F, NewMtime)),
    catch(load_files(F, [if(true), syntax_errors(error)]), Error, true),
    (   var(Error)
    ->  catch(read_file_to_string(F, NewContent, []), _, true),
        (   nonvar(NewContent)
        ->  retractall(px_reload_good(F, _)),
            asserta(px_reload_good(F, NewContent))
        ;   true
        ),
        Errors = []
    ;   restore_last_good(F),
        Errors = [F-Error]
    ).

%!  restore_last_good(+File) is det.
%
%   Reload File's OWN PATH again, this time reading the cached
%   last-known-good source text via load_files/2's stream(Stream)
%   option instead of the (currently broken) file on disk -- this is
%   what actually undoes the clause-wipe the failed attempt above
%   left behind, restoring the predicates File owns to what they were
%   before this reload cycle. Best-effort: if even this fails (should
%   not happen -- it is the same content that loaded cleanly before),
%   it is logged, not thrown, so a restore failure still cannot crash
%   the worker.
restore_last_good(F) :-
    (   px_reload_good(F, GoodContent)
    ->  catch(
            setup_call_cleanup(
                open_string(GoodContent, RS),
                load_files(F, [if(true), stream(RS)]),
                close(RS)),
            RestoreError,
            print_message(error, px_reload(restore_failed(F, RestoreError))))
    ;   true
    ).

:- multifile prolog:message//1.
prolog:message(px_reload(restore_failed(File, Error))) -->
    [ 'px_reload: failed to restore last-good version of ~w after a reload error: ~q'
      -[File, Error] ].


                 /*******************************
                 *           RESPONSE           *
                 *******************************/

%!  respond_reload_errors(+Stream, +Errors) is det.
%
%   Writes a plain-text 500 naming every file that failed to reload
%   this pass and why. The dev-mode error is visible in the response
%   body rather than a silent 500 -- a rich in-browser error page
%   (adr/0036 says this is future work) can replace this later
%   without changing maybe_reload/2's contract.
respond_reload_errors(Stream, Errors) :-
    maplist(format_reload_error, Errors, Lines),
    atomic_list_concat(Lines, "\n\n", Body0),
    format(string(Body),
           "prologex hot reload: failed to reload changed file(s) in development:\n\n~w\n",
           [Body0]),
    reply_error(Stream, 500, Body),
    %   px_env:write_response/2 (the normal response path) ends with
    %   this same flush_output/1 -- ResponseStream is a genuine
    %   buffered IOSTREAM over the raw connection (adr/0007), and
    %   http_stream.pl's on_message_complete/4 calls uv_close/2 on the
    %   underlying connection right after this predicate returns, with
    %   no close/1 on Stream itself to flush implicitly. Without this,
    %   the reload-error body was written into the stream's buffer and
    %   then discarded when the socket closed -- caught by hand: curl
    %   saw a bare connection reset (000), not the 500 body.
    flush_output(Stream).

format_reload_error(File-Error, Line) :-
    reload_error_text(Error, Msg),
    format(string(Line), "~w:\n~w", [File, Msg]).

reload_error_text(error(syntax_error(Kind), file(Path, LineNo, Col, _)), Msg) :-
    !,
    format(string(Msg), "Syntax error: ~w at ~w:~w:~w", [Kind, Path, LineNo, Col]).
reload_error_text(error(Formal, _Context), Msg) :-
    !,
    format(string(Msg), "~q", [Formal]).
reload_error_text(Error, Msg) :-
    format(string(Msg), "~q", [Error]).
