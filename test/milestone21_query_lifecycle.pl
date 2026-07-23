/* Milestone 21: query-builder statement lifecycle (px_query.pl,
   px_db.pl), standalone -- no server, no sockets.

   Regression guard for a suspected "delete-then-insert breaks the
   connection" bug that was investigated after intermittent 404s on
   the auth-gated blog demo. The investigation's verdict: there is NO
   such bug in the single-connection data path. Every write goes
   through db_exec/3, which prepares, steps to `done`, and finalizes
   under setup_call_cleanup/3 (px_db.pl); db_row/4 finalizes its
   SELECT cursor the same way, including on early exit (once/1). The
   intermittent live failures were operational: orphaned swipl
   processes (swipl ignores SIGTERM, so `timeout N swipl ...` leaves
   the process alive) held the WAL-mode database open alongside the
   live worker.

   This test hammers the exact pattern that was suspected -- many
   rounds of insert-several / delete-each-in-a-loop / insert-again --
   on one connection and asserts every write lands, plus a row/2
   early-exit-then-write case (proving the SELECT cursor is finalized
   so the following write is not blocked). It uses a unique temp db
   and halts explicitly.

   Run:  swipl test/milestone21_query_lifecycle.pl
*/

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../prolog/px_db'],    PxDbLib),
   atomic_list_concat([Dir, '/../prolog/px_query'], PxQueryLib),
   use_module(PxDbLib),
   use_module(PxQueryLib).

:- initialization(main, main).

main :-
    tmp_db(DB),
    ( exists_file(DB) -> delete_file(DB) ; true ),
    px_db:db_open(DB, H),
    px_query:use_db(H),
    px_db:db_exec(H,
        "create table t (id integer primary key, v text not null)", []),
    Tests = [ delete_loop_then_insert,
              row_early_exit_then_insert,
              heavy_cycles
            ],
    run_tests(Tests, 0, Failed),
    ignore(( exists_file(DB) -> delete_file(DB) ; true )),
    length(Tests, N),
    (   Failed =:= 0
    ->  format("milestone21_query_lifecycle: all ~w tests passed~n", [N]),
        halt(0)
    ;   format(user_error,
               "milestone21_query_lifecycle: ~w of ~w test(s) FAILED~n",
               [Failed, N]),
        halt(1)
    ).

tmp_db('/tmp/px_milestone21_lifecycle.db').

run_tests([], F, F).
run_tests([T|Ts], F0, F) :-
    (   catch(test(T), E,
              ( format(user_error, "    exception: ~q~n", [E]), fail ))
    ->  format("  ok: ~w~n", [T]), F1 = F0
    ;   format(user_error, "  FAILED: ~w~n", [T]), F1 is F0 + 1
    ),
    run_tests(Ts, F1, F).

%   Insert five rows, delete each by id with a separate delete/2, then
%   insert again -- the write after the delete loop must succeed and
%   be readable back.
test(delete_loop_then_insert) :-
    forall(between(1, 5, K),
           ( atom_concat(a, K, V), insert(t, _{v: V}, _) )),
    findall(Id, ( row(q(t, []), R), Id = R.id ), Ids),
    forall(member(Id, Ids), delete(t, id == Id)),
    insert(t, _{v: "after_delete_loop"}, NewId),
    once(row(q(t, [where(id == NewId)]), Row)),
    Row.v == "after_delete_loop",
    delete(t, id == NewId).

%   Take the first solution of a multi-row query and stop (once/1),
%   then immediately write -- the SELECT cursor from the abandoned
%   nondeterministic row/2 must already be finalized, or the write
%   would block/fail.
test(row_early_exit_then_insert) :-
    forall(between(1, 10, K),
           ( atom_concat(b, K, V), insert(t, _{v: V}, _) )),
    once(row(q(t, [order_by(asc(id))]), _)),   % grab one, drop the rest
    insert(t, _{v: "after_early_exit"}, NewId),
    once(row(q(t, [where(id == NewId)]), Row)),
    Row.v == "after_early_exit",
    delete(t, []).                              % clear the table

%   Sustained pressure: 200 rounds of insert-5 / delete-each / and a
%   final write that must still land.
test(heavy_cycles) :-
    forall(between(1, 200, _), one_cycle),
    insert(t, _{v: "final"}, FId),
    once(row(q(t, [where(id == FId)]), Row)),
    Row.v == "final".

one_cycle :-
    forall(between(1, 5, K),
           ( atom_concat(c, K, V), insert(t, _{v: V}, _) )),
    findall(Id, ( row(q(t, []), R), Id = R.id ), Ids),
    forall(member(Id, Ids), delete(t, id == Id)).
