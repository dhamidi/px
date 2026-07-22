:- module(px_db,
          [ db_open/2,                  % +Path, -DB
            db_close/1,                 % +DB
            db_row/4,                   % +DB, +SQL, +Params, -Row
            db_exec/3,                  % +DB, +SQL, +Params
            db_transaction/2,           % +DB, :Goal
            db_last_insert_rowid/2,     % +DB, -Id
            db_changes/2                % +DB, -N
          ]).

/** <module> Database convenience layer over the 1:1 SQLite FFI (adr/0020).

The flagship predicate is db_row/4: nondeterminism is iteration
(adr/0016 rule 6). A database row is a solution -- rows yield on
backtracking, streamed from sqlite's step, never collected into a
list first. once/1 is early termination, forall/2 streams, and a list
is an explicit choice made by the caller with findall/3.
*/

:- use_module(sqlite3_swi).
:- use_module(library(pairs)).

:- meta_predicate db_transaction(+, 0).

%!  db_open(+Path, -DB) is det.
%
%   Open the SQLite database at Path (":memory:" works) and apply the
%   framework's connection pragmas (adr/0020 section 4): WAL so many
%   workers' readers proceed concurrently with a single writer, a
%   5-second busy_timeout so contending writers queue instead of
%   erroring with SQLITE_BUSY, and foreign key enforcement.

db_open(Path, DB) :-
    sqlite3_open(Path, DB),
    db_exec(DB, "PRAGMA journal_mode = WAL", []),
    db_exec(DB, "PRAGMA busy_timeout = 5000", []),
    db_exec(DB, "PRAGMA foreign_keys = ON", []).

%!  db_close(+DB) is det.
%
%   Close the connection. Throws (SQLITE_BUSY) if statements are still
%   live -- a bug we want loud. Idempotent: closing twice succeeds.

db_close(DB) :-
    sqlite3_close(DB).

%!  db_row(+DB, +SQL, +Params, -Row) is nondet.
%
%   True when Row is a row produced by running SQL with Params on DB.
%   Each solution is one sqlite3_step; backtracking steps again; `done`
%   fails the enumeration -- the natural Prolog way to say "no more
%   rows". Whatever way execution leaves -- exhaustion, a cut, once/1,
%   or an exception -- setup_call_cleanup/3 finalizes the statement.
%   Row is a dict tagged `row`, keyed by column-name atoms:
%   row{id: 7, title: "..."}.
%
%   Binding happens inside the Call argument (not the Setup, as
%   adr/0020's sketch has it) so that a bind error -- e.g. a type error
%   on a parameter -- still runs the cleanup and finalizes the
%   just-prepared statement instead of leaking it.

db_row(DB, SQL, Params, Row) :-
    setup_call_cleanup(
        sqlite3_prepare(DB, SQL, Stmt),
        ( bind_all(Params, 1, Stmt),
          stmt_row(Stmt, Row)
        ),
        sqlite3_finalize(Stmt)).

bind_all([], _, _).
bind_all([P|Ps], I, Stmt) :-
    sqlite3_bind(Stmt, I, P),
    I1 is I + 1,
    bind_all(Ps, I1, Stmt).

% The repeat/step loop is the classic Prolog idiom for driving an
% external cursor; column names are fetched once, before the first
% step, and reused for every row dict.
stmt_row(Stmt, Row) :-
    sqlite3_column_count(Stmt, N),
    column_names(Stmt, 0, N, Names),
    repeat,
    sqlite3_step(Stmt, Result),
    (   Result == row
    ->  columns(Stmt, 0, N, Values),
        pairs_keys_values(Pairs, Names, Values),
        dict_pairs(Row, row, Pairs)
    ;   !, fail                        % done: cut the repeat, end enumeration
    ).

column_names(_, N, N, []) :- !.
column_names(Stmt, I, N, [Name|Names]) :-
    sqlite3_column_name(Stmt, I, Name),
    I1 is I + 1,
    column_names(Stmt, I1, N, Names).

columns(_, N, N, []) :- !.
columns(Stmt, I, N, [V|Vs]) :-
    sqlite3_column(Stmt, I, V),
    I1 is I + 1,
    columns(Stmt, I1, N, Vs).

%!  db_exec(+DB, +SQL, +Params) is det.
%
%   Run SQL for effect. Prepares, binds, steps to done, finalizes
%   (setup_call_cleanup, as db_row/4). Any rows the statement happens
%   to produce are discarded (e.g. `PRAGMA journal_mode = WAL` answers
%   one row). Deterministic: succeeds once or throws.

db_exec(DB, SQL, Params) :-
    setup_call_cleanup(
        sqlite3_prepare(DB, SQL, Stmt),
        ( bind_all(Params, 1, Stmt),
          exec_steps(Stmt)
        ),
        sqlite3_finalize(Stmt)).

exec_steps(Stmt) :-
    sqlite3_step(Stmt, Result),
    (   Result == done
    ->  true
    ;   exec_steps(Stmt)
    ).

%!  db_transaction(+DB, :Goal) is semidet.
%
%   BEGIN IMMEDIATE; call Goal once; COMMIT if it succeeds. ROLLBACK if
%   Goal throws (the exception is re-thrown) OR if Goal fails
%   (db_transaction/2 then fails: failure inside a transaction means
%   "this did not logically happen", and the database agrees). Goal is
%   not re-entered on backtracking; a transaction runs its goal with
%   once-semantics. Every exit path -- success, failure, exception --
%   issues exactly one COMMIT or ROLLBACK.
%
%   BEGIN IMMEDIATE (rather than deferred BEGIN) takes the write lock
%   up front, so cross-worker lock contention surfaces at BEGIN --
%   where busy_timeout handles it by waiting -- instead of as a
%   mid-transaction SQLITE_BUSY upgrade failure.

db_transaction(DB, Goal) :-
    db_exec(DB, "BEGIN IMMEDIATE", []),
    (   catch(Goal, Error, true)
    ->  (   var(Error)
        ->  db_exec(DB, "COMMIT", [])
        ;   db_exec(DB, "ROLLBACK", []),
            throw(Error)
        )
    ;   db_exec(DB, "ROLLBACK", []),
        fail
    ).

%!  db_last_insert_rowid(+DB, -Id) is det.

db_last_insert_rowid(DB, Id) :-
    sqlite3_last_insert_rowid(DB, Id).

%!  db_changes(+DB, -N) is det.

db_changes(DB, N) :-
    sqlite3_changes(DB, N).
