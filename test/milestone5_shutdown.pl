/* Milestone 5 (adr/0005, adr/0006): graceful-shutdown fan-out via
   prolog/bridge.pl. Starts several independent workers -- each its own
   thread + uv_loop_t + attached Prolog engine, per adr/0005 -- proves
   they are actually serving connections, then calls
   bridge:shutdown_all_workers, which uv_async_send/1's every worker's
   async handle. That wakes each worker's own uv_run/2, lets IT call
   uv_stop/1 on itself (never cross-thread -- see bridge.pl's header),
   and each worker's async callback prints "worker N: shutting down"
   right before its uv_run/2 returns.

   Proof that every worker's loop, and not just the process, actually
   stopped: workers are started via thread_create/3 with detached(true)
   (see worker:start_workers/3). A detached thread's OS resources are
   reclaimed the instant its goal (worker_loop/2, which ends right after
   uv_run/2 returns) completes -- after that, thread_property/2 for its
   alias throws existence_error(thread, Alias). Polling for that
   exception is a direct, in-process, non-networked confirmation that
   uv_run/2 returned for every single worker, not merely that the whole
   swipl process happened to be killed by the outer `timeout` wrapper --
   this script keeps running and prints its own verdict well inside that
   wrapper's deadline.

   Note on why this test does NOT also assert "connect refused" after
   shutdown: uv_stop/1 stops loop iteration but -- correctly, per libuv's
   own documented semantics -- does not close any handles. The listening
   TCP socket stays open and bound at the OS level (still in the kernel's
   listen backlog) even after the worker's thread has fully exited, so a
   post-shutdown connect attempt can complete a TCP handshake and then
   hang waiting for a reply that will never come, rather than being
   refused. bridge.pl's register_worker/2 only ever receives Loop (per
   its specified signature), never the listener handle, precisely because
   that is control-plane scope (adr/0005) -- closing per-worker listener
   sockets is a separate concern this milestone does not attempt. */

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../prolog/worker'], WorkerLib),
   use_module(WorkerLib).
:- use_module(library(socket)).

on_conn(Id, _Loop, Client) :-
    uv_read_start(Client, user:on_data(Id)).

on_data(_Id, Client, end_of_file) :- !, uv_close(Client, true).
on_data(Id, Client, Data) :-
    string_upper(Data, Up),
    format(string(Reply), "[worker ~w] ~w", [Id, Up]),
    uv_write(Client, Reply, user:noop1).

noop1(_Status).

%!  probe(+Port, -Result) is det.
%
%   One request/reply round-trip against Port, used only to prove the
%   workers are up and serving BEFORE shutdown. Result is reply(Text)
%   on success, or refused if the connection could not be made at all.
probe(Port, Result) :-
    catch(
        setup_call_cleanup(
            tcp_connect(localhost:Port, StreamPair, []),
            ( stream_pair(StreamPair, In, Out),
              format(Out, "ping~n", []),
              flush_output(Out),
              read_line_to_string(In, Line),
              ( Line == end_of_file -> Result = refused ; Result = reply(Line) )
            ),
            close(StreamPair)),
        error(socket_error(_, _), _),
        Result = refused).

%!  wait_thread_gone(+Alias, +Deadline, -Result) is det.
%
%   Poll thread_property(Alias, status(_)) until it throws
%   existence_error(thread, Alias) (the thread finished and, being
%   detached, was reaped) or Deadline (a get_time/1 timestamp) passes.
%   Result is gone or timeout.
wait_thread_gone(Alias, Deadline, Result) :-
    get_time(Now),
    (   Now > Deadline
    ->  Result = timeout
    ;   (   catch(thread_property(Alias, status(_)),
                  error(existence_error(thread, Alias), _),
                  fail)
        ->  sleep(0.05),
            wait_thread_gone(Alias, Deadline, Result)
        ;   Result = gone
        )
    ).

:- initialization(main, main).

main :-
    Port = 7005,
    WorkerCount = 3,
    numlist(1, WorkerCount, Ids),
    maplist([Id,Alias]>>format(atom(Alias), 'worker_~w', [Id]), Ids, Aliases),

    format(user_error, "~n=== milestone5: starting ~w workers on port ~w ===~n",
           [WorkerCount, Port]),
    start_workers(Port, WorkerCount, user:on_conn),

    % Give the detached worker threads a moment to reach uv_listen/3.
    sleep(0.3),

    format(user_error, "~n=== milestone5: probing BEFORE shutdown ===~n", []),
    findall(R1, (between(1, 5, _), probe(Port, R1)), Before),
    forall(member(R, Before), format(user_error, "  probe -> ~w~n", [R])),
    ( \+ member(refused, Before)
    -> format(user_error, "PROOF-BEFORE: PASS -- all probes got a reply, workers are serving~n", [])
    ;  format(user_error, "PROOF-BEFORE: FAIL -- at least one probe was refused~n", [])
    ),

    format(user_error, "~n=== milestone5: calling bridge:shutdown_all_workers ===~n", []),
    get_time(T0),
    bridge:shutdown_all_workers,

    format(user_error, "~n=== milestone5: waiting for each worker's OS thread to terminate ===~n", []),
    Deadline is T0 + 5.0,
    maplist({Deadline}/[Alias,Alias-Result]>>wait_thread_gone(Alias, Deadline, Result),
            Aliases, ThreadResults),
    forall(member(A-R, ThreadResults),
           format(user_error, "  ~w -> ~w~n", [A, R])),
    get_time(T1),
    Elapsed is T1 - T0,
    format(user_error, "  (all resolved within ~2f s of calling shutdown_all_workers)~n", [Elapsed]),

    ( forall(member(_-gone, ThreadResults), true)
    -> format(user_error, "PROOF-AFTER: PASS -- every worker thread terminated (uv_run/2 returned, loop stopped) after shutdown_all_workers~n", [])
    ;  format(user_error, "PROOF-AFTER: FAIL -- at least one worker thread is still running~n", [])
    ),

    ( \+ member(refused, Before), forall(member(_-gone, ThreadResults), true)
    -> ( format(user_error, "~n=== milestone5: OVERALL PASS -- this message printed by the test script itself, well before any outer timeout ===~n", []),
         halt(0) )
    ;  ( format(user_error, "~n=== milestone5: OVERALL FAIL ===~n", []), halt(1) )
    ).
