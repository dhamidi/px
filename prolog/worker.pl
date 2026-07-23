:- module(worker, [start_workers/3, worker_loop/2, install_shutdown_handler/0]).

/** <module> Worker lifecycle. See adr/0005.

A worker is one OS thread, running one uv_loop_t, with one attached
SWI-Prolog engine -- started via thread_create/3, which gives the thread
its own attached engine for free. Default deployments run a single
worker (mirrors Node's single-threaded-by-default behaviour); running
more is exactly running more of these, each independently bound to the
same port via SO_REUSEPORT so the kernel spreads new connections across
them with no coordination between workers required.

install_shutdown_handler/0 (adr/0031) is the other half of the worker
lifecycle: it wires SIGTERM/SIGINT to bridge.pl's graceful fan-out and
then waits, bounded, for every worker thread this module started to
actually finish, before halting the process.
*/

:- use_module(uv_dispatch).
:- use_module(uv_swi).
:- use_module(bridge).
:- reexport(uv_swi).

%   Remembers the Count last passed to start_workers/3, so
%   install_shutdown_handler/0 knows which worker_<N> thread aliases to
%   wait on without needing its own separate bookkeeping -- IDs are
%   always the contiguous 1..Count start_workers/3 itself hands out.
:- dynamic worker_count/1.

%!  start_workers(+Port, +Count, :ConnectionGoal) is det.
%
%   Start Count workers, each listening on Port via SO_REUSEPORT.
%   ConnectionGoal is called as call(ConnectionGoal, WorkerId, Loop,
%   ClientHandle) for every accepted connection, on the worker's own
%   thread/engine -- see adr/0007 for how a connection is normally
%   turned into request/response streams from there.
start_workers(Port, Count, ConnectionGoal) :-
    must_be(positive_integer, Count),
    retractall(worker_count(_)),
    assertz(worker_count(Count)),
    numlist(1, Count, Ids),
    forall(member(Id, Ids),
           ( worker_alias(Id, Alias),
             thread_create(worker_loop(Id, cfg(Port, ConnectionGoal)), _,
                            [ alias(Alias),
                              detached(true)
                            ])
           )).

worker_loop(Id, cfg(Port, ConnectionGoal)) :-
    uv_loop_new(Loop),
    register_worker(Id, Loop),
    uv_tcp_init(Loop, Server),
    uv_tcp_bind_reuseport(Server, '0.0.0.0', Port),
    % 4096 matches this VM's kernel somaxconn ceiling (net.core.somaxconn) --
    % passing a larger backlog wouldn't buy anything, the kernel caps it
    % there anyway. See adr/0015-load-test-10k-connections.md.
    uv_listen(Server, 4096, worker:on_connection(Id, Loop, ConnectionGoal)),
    bridge:register_server(Id, Server),
    format(user_error, "worker ~w: listening on port ~w~n", [Id, Port]),
    uv_run(Loop, default),
    format(user_error, "worker ~w: stopped~n", [Id]).

on_connection(Id, Loop, ConnectionGoal, Server, _Status) :-
    uv_tcp_init(Loop, Client),
    uv_accept(Server, Client),
    call(ConnectionGoal, Id, Loop, Client).

worker_alias(Id, Alias) :- format(atom(Alias), 'worker_~w', [Id]).


                 /*******************************
                 *      GRACEFUL SHUTDOWN       *
                 *******************************/

%!  install_shutdown_handler is det.
%
%   Installs SIGTERM and SIGINT handlers (adr/0031) that shut the
%   service down cleanly and promptly instead of relying on systemd's
%   SIGKILL escalation:
%
%     1. bridge:shutdown_all_workers -- fans a graceful stop out to
%        every worker (stop accepting new connections, let whatever is
%        already in flight finish, then let that worker's uv_run/2
%        return on its own -- see bridge.pl's on_shutdown_async/2).
%     2. Waits, with a bounded grace period, for every worker_<N>
%        thread's OS thread to actually finish (thread_property/2
%        polling -- workers are detached(true), so thread_join/2 isn't
%        available; a finished detached thread is reaped immediately
%        and thread_property/2 for its alias starts throwing
%        existence_error(thread, Alias), which is exactly what this
%        polls for. The same technique test/milestone5_shutdown.pl
%        already proved out for the older, non-graceful uv_stop/1
%        path).
%     3. halt(0).
%
%   Per SWI's on_signal/3, the handler goal below runs synchronously on
%   whichever thread actually receives the signal -- empirically (and,
%   for this project, always) the main thread, since it is the one
%   blocked in prologex_run/0's thread_get_message(_) when the signal
%   arrives; SWI delivers the signal by interrupting that blocking call
%   and running the handler goal on that same thread before considering
%   resuming it. halt/1 terminates the whole process immediately, from
%   whatever thread calls it, so there is no need for the interrupted
%   thread_get_message(_) call to ever actually return.
install_shutdown_handler :-
    on_signal(term, _, worker:handle_shutdown_signal),
    on_signal(int,  _, worker:handle_shutdown_signal).

% Reentrancy guard: a second SIGTERM/SIGINT arriving while the first is
% still waiting out its grace period would otherwise interrupt that wait
% and re-run this whole predicate from the top (on_signal/3's handler
% goal can itself be interrupted by another signal, same as any other
% Prolog goal). Once shutdown is already under way there is nothing a
% second signal usefully adds, so it is just ignored -- control then
% resumes the first (outer) invocation's interrupted call, and shutdown
% proceeds exactly as if the second signal had not arrived.
:- dynamic shutting_down/0.

handle_shutdown_signal(Signal) :-
    (   shutting_down
    ->  true
    ;   assertz(shutting_down),
        graceful_shutdown(Signal)
    ).

%   The "bounded grace period" per adr/0031: long enough for an
%   in-flight response to finish writing, short enough that a stuck
%   worker (adr/0006: a blocking handler stalls its whole worker)
%   cannot make `systemctl stop` hang the way the old SIGKILL
%   workaround was built to route around. 5s sits well under the
%   unit's TimeoutStopSec=15 (adr/0012); a response that genuinely
%   cannot finish within the window is truncated, by design (the
%   grace is BOUNDED) -- a client wanting a multi-MB stream to survive
%   a restart is outside what a bounded drain promises.
shutdown_grace_seconds(5.0).

graceful_shutdown(Signal) :-
    format(user_error, "prologex: caught ~w, shutting down gracefully~n", [Signal]),
    ( worker_count(Count) -> true ; Count = 0 ),
    numlist(1, Count, Ids),
    maplist(worker_alias, Ids, Aliases),
    get_time(T0),
    bridge:shutdown_all_workers,
    shutdown_grace_seconds(Grace),
    Deadline is T0 + Grace,
    wait_workers_gone(Aliases, Deadline, Results),
    get_time(T1),
    forall(member(Alias-Result, Results),
           format(user_error, "prologex: ~w -> ~w~n", [Alias, Result])),
    Elapsed is T1 - T0,
    format(user_error,
           "prologex: shutdown settled in ~2f s, halting~n", [Elapsed]),
    halt(0).

%!  wait_workers_gone(+Aliases, +Deadline, -Results) is det.
%
%   Results is a list of Alias-gone or Alias-timeout, one per Alias,
%   for whichever comes first: the detached thread finishing (and being
%   reaped -- see wait_worker_gone/3) or Deadline (a get_time/1
%   timestamp) passing. Every alias is waited on even after an earlier
%   one times out -- a slow worker should not shrink the grace period
%   given to the others.
wait_workers_gone([], _, []).
wait_workers_gone([Alias|As], Deadline, [Alias-Result|Rs]) :-
    wait_worker_gone(Alias, Deadline, Result),
    wait_workers_gone(As, Deadline, Rs).

%!  wait_worker_gone(+Alias, +Deadline, -Result) is det.
%
%   Poll thread_property(Alias, status(_)) until it throws
%   existence_error(thread, Alias) (the detached thread finished and was
%   reaped -- Result = gone) or Deadline passes (Result = timeout). Same
%   technique as test/milestone5_shutdown.pl's wait_thread_gone/3.
wait_worker_gone(Alias, Deadline, Result) :-
    get_time(Now),
    (   Now > Deadline
    ->  Result = timeout
    ;   catch(thread_property(Alias, status(_)),
              error(existence_error(thread, Alias), _),
              fail)
    ->  sleep(0.05),
        wait_worker_gone(Alias, Deadline, Result)
    ;   Result = gone
    ).
