/* Milestone 9 (adr/0020): the SQLite subsystem -- vendored amalgamation,
   strict 1:1 bindings (c/sqlite3_swi.c via prolog/sqlite3_swi.pl), and the
   px_db convenience layer whose flagship is the nondeterministic db_row/4:
   a database row is a solution, streamed from sqlite3_step on
   backtracking, never collected into a list first.

   This is a plain swipl script -- no server, no workers. It creates a
   temporary on-disk database file (on disk rather than :memory: so the
   WAL/busy_timeout pragmas in db_open/2 run for real) and proves:

   (a) db_row/4 enumerates all inserted rows as Key-Value pairs lists
       on backtracking;
   (b) once(db_row(...)) terminates the cursor early AND the statement is
       finalized by setup_call_cleanup -- proven by db_close/1 succeeding
       right after (sqlite3_close throws SQLITE_BUSY if any statement is
       still live, so a leaked statement cannot hide);
   (c) db_transaction/2 rolls back on exception (and rethrows);
   (d) db_transaction/2 rolls back on FAILURE too (and itself fails);
   (e) parameter binding round-trips typed: integer -> integer,
       float -> float, string -> string, null -> the atom null.
*/

:- use_module('../prolog/px_db.pl').

:- initialization(main, main).

check(Name, Goal) :-
    (   catch(Goal, E, (format("FAIL: ~w (exception ~q)~n", [Name, E]), fail))
    ->  format("PASS: ~w~n", [Name])
    ;   format("FAIL: ~w~n", [Name]),
        fail
    ).

count_posts(DB, N) :-
    once(db_row(DB, "SELECT COUNT(*) AS n FROM posts", [], Row)),
    memberchk(n-N, Row).

main(_Argv) :-
    tmp_file_stream(text, Path, TmpStream),
    close(TmpStream),
    format("temp db: ~w~n~n", [Path]),
    (   catch(run_all(Path), E, (format("FAIL: uncaught exception ~q~n", [E]), fail))
    ->  format("~n=== milestone9: OVERALL PASS ===~n"),
        Halt = 0
    ;   format("~n=== milestone9: OVERALL FAIL ===~n"),
        Halt = 1
    ),
    catch(delete_file(Path), _, true),
    atom_concat(Path, '-wal', Wal),  catch(delete_file(Wal), _, true),
    atom_concat(Path, '-shm', Shm),  catch(delete_file(Shm), _, true),
    halt(Halt).

run_all(Path) :-
    db_open(Path, DB),
    format("opened (WAL, busy_timeout, foreign_keys pragmas applied)~n"),

    db_exec(DB,
            "CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT, score REAL, note TEXT)",
            []),
    db_exec(DB, "INSERT INTO posts (title, score, note) VALUES (?, ?, ?)",
            ["first",  1.5, "a"]),
    db_last_insert_rowid(DB, Id1),
    check('db_last_insert_rowid after first insert = 1', Id1 == 1),
    db_exec(DB, "INSERT INTO posts (title, score, note) VALUES (?, ?, ?)",
            ["second", 2.5, "b"]),
    db_exec(DB, "INSERT INTO posts (title, score, note) VALUES (?, ?, ?)",
            ["third",  3.5, null]),
    db_changes(DB, Changes),
    check('db_changes after single-row insert = 1', Changes == 1),

    % (a) db_row/4 enumerates all rows as Key-Value pairs lists on
    % backtracking.
    findall(Row, db_row(DB, "SELECT id, title, score FROM posts ORDER BY id", [], Row),
            Rows),
    format("rows: ~q~n", [Rows]),
    length(Rows, NRows),
    check('(a) db_row yields 3 solutions on backtracking', NRows == 3),
    Rows = [R1, R2, R3],
    check('(a) rows are Key-Value pairs lists', (is_list(R1), is_list(R2), is_list(R3))),
    check('(a) field values via memberchk',
          (memberchk(title-"first", R1), memberchk(id-2, R2), memberchk(score-3.5, R3))),

    % (b) once/1 = early termination; cleanup finalized the statement.
    check('(b) once(db_row(...)) succeeds with the first row only',
          ( once(db_row(DB, "SELECT title FROM posts ORDER BY id", [], First)),
            memberchk(title-FT, First), FT == "first" )),
    % sqlite3_close throws SQLITE_BUSY if any statement is still live, so
    % closing (then reopening for the remaining checks) proves the once/1
    % above did not leak its statement.
    check('(b) db_close succeeds after once/1 (statement was finalized)',
          db_close(DB)),
    check('(b) db_close is idempotent (second close is a no-op)',
          db_close(DB)),
    db_open(Path, DB2),

    % (c) transaction rollback on exception.
    count_posts(DB2, Before),
    check('(c) rollback-on-exception rethrows the exception',
          catch(( db_transaction(DB2,
                      ( db_exec(DB2, "INSERT INTO posts (title) VALUES (?)", ["doomed"]),
                        throw(boom) )),
                  fail ),
                boom, true)),
    count_posts(DB2, AfterEx),
    check('(c) row count unchanged after exception rollback', Before == AfterEx),

    % (d) transaction rollback on failure.
    check('(d) db_transaction fails when its goal fails',
          \+ db_transaction(DB2,
                 ( db_exec(DB2, "INSERT INTO posts (title) VALUES (?)", ["also doomed"]),
                   fail ))),
    count_posts(DB2, AfterFail),
    check('(d) row count unchanged after failure rollback', Before == AfterFail),
    check('(d) transaction is really over (a fresh one commits fine)',
          ( db_transaction(DB2, db_exec(DB2,
                "INSERT INTO posts (title, score, note) VALUES (?, ?, ?)",
                ["committed", 9.0, null])),
            count_posts(DB2, AfterCommit),
            AfterCommit =:= Before + 1 )),

    % (e) typed round-trips: integer/float/string/null in, same types out.
    db_exec(DB2, "CREATE TABLE typed (i INTEGER, f REAL, s TEXT, n TEXT)", []),
    db_exec(DB2, "INSERT INTO typed (i, f, s, n) VALUES (?, ?, ?, ?)",
            [42, 3.25, "hello", null]),
    once(db_row(DB2, "SELECT i, f, s, n FROM typed", [], T)),
    format("typed row: ~q~n", [T]),
    check('(e) integer round-trips as integer',
          (memberchk(i-TI, T), integer(TI), TI == 42)),
    check('(e) float round-trips as float',
          (memberchk(f-TF, T), float(TF), TF == 3.25)),
    check('(e) string round-trips as string',
          (memberchk(s-TS, T), string(TS), TS == "hello")),
    check('(e) null round-trips as the atom null',
          (memberchk(n-TN, T), TN == null)),
    check('(e) null is bound via WHERE n IS NULL',
          ( once(db_row(DB2, "SELECT i FROM typed WHERE n IS NULL", [], NR)),
            memberchk(i-NI, NR), NI == 42 )),

    db_close(DB2).
