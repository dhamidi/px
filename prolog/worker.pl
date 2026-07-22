:- module(worker, [start_workers/3, worker_loop/2]).

/** <module> Worker lifecycle. See adr/0005.

A worker is one OS thread, running one uv_loop_t, with one attached
SWI-Prolog engine -- started via thread_create/3, which gives the thread
its own attached engine for free. Default deployments run a single
worker (mirrors Node's single-threaded-by-default behaviour); running
more is exactly running more of these, each independently bound to the
same port via SO_REUSEPORT so the kernel spreads new connections across
them with no coordination between workers required.
*/

:- use_module(uv_dispatch).
:- use_module(uv_swi).
:- use_module(bridge).
:- reexport(uv_swi).

%!  start_workers(+Port, +Count, :ConnectionGoal) is det.
%
%   Start Count workers, each listening on Port via SO_REUSEPORT.
%   ConnectionGoal is called as call(ConnectionGoal, WorkerId, Loop,
%   ClientHandle) for every accepted connection, on the worker's own
%   thread/engine -- see adr/0007 for how a connection is normally
%   turned into request/response streams from there.
start_workers(Port, Count, ConnectionGoal) :-
    must_be(positive_integer, Count),
    numlist(1, Count, Ids),
    forall(member(Id, Ids),
           ( format(atom(Alias), 'worker_~w', [Id]),
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
    format(user_error, "worker ~w: listening on port ~w~n", [Id, Port]),
    uv_run(Loop, default).

on_connection(Id, Loop, ConnectionGoal, Server, _Status) :-
    uv_tcp_init(Loop, Client),
    uv_accept(Server, Client),
    call(ConnectionGoal, Id, Loop, Client).
