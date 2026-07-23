:- module(bridge, [register_worker/2, register_server/2, shutdown_all_workers/0]).

/** <module> Control-plane bridge. See adr/0005 and adr/0006.

This module is exactly the "control-plane" half of what those ADRs call
`bridge.c`/`bridge.h`: startup coordination and fanning a graceful-shutdown
signal out to every worker's loop. It is never a per-request data plane --
no request-handling data of any kind crosses between workers through this
module or the registry it keeps.

Each worker owns one OS thread, one uv_loop_t and one attached Prolog
engine, permanently co-located (adr/0005). uv_stop/1 must therefore only
ever be called ON a worker's own thread, over its own loop -- calling it
cross-thread would violate the single safety rule libuv itself gives for
handles/loops not otherwise documented as thread-safe. The one primitive
libuv *does* document as safe to call from any thread is uv_async_send/1,
which wakes the owning loop and runs its callback on the loop's own
thread. So the fan-out here works in two hops:

  1. register_worker/2 (called by each worker, on its own thread, right
     after uv_loop_new/1) creates a uv_async_t on that worker's loop whose
     callback -- on_shutdown_async/2 below -- performs the graceful stop,
     and records WorkerId-Loop-Async in a small shared registry.
     register_server/2 (called a moment later, once uv_listen/3 has
     actually produced a listening socket) records that socket alongside
     it, so the callback has something to close.
  2. shutdown_all_workers/0 (called from whatever thread decides to shut
     the service down, e.g. the thread handling SIGTERM -- see
     worker:install_shutdown_handler/0 and adr/0031) reads that registry
     and calls uv_async_send/1 on every worker's async handle -- never
     touches a worker's loop or handles directly. Each worker's own
     thread then wakes up inside its own uv_run/2 and runs its own async
     callback, same-thread, same-loop.

  As of adr/0031 that callback does NOT call uv_stop/1 (that would cut
  off connections already in flight). Instead it closes the worker's
  listening socket and its own async handle -- see on_shutdown_async/2's
  own comment for why that is enough to make uv_run/2 return by itself,
  once in-flight connections finish closing the ordinary way.

Known limitation (deliberately not engineered around, per the ADRs' own
"experiment-grade control plane" scope): workers are started asynchronously
via thread_create/3 in worker:start_workers/3, so there is a startup race
between a worker registering itself and shutdown_all_workers/0 running. If
shutdown_all_workers/0 runs before a worker has reached register_worker/2,
that worker simply is not in the registry yet and will not receive the
wakeup -- it keeps running. shutdown_all_workers/0 does its best against
whatever is registered at the moment it runs; no startup barrier/rendezvous
is implemented, since that is not needed for this framework's actual
use (shutdown is normally requested long after workers are up and serving,
not in the same instant they are being spawned).
*/

:- use_module(uv_swi).

%!  worker_registry(?WorkerId, ?Loop, ?Async) is nondet.
%
%   WorkerId -> (Loop, Async) registry, one row per live worker. Small
%   and fixed-size (one entry per worker) -- not a hot path -- so plain
%   dynamic facts guarded by a mutex are simpler than library(assoc)
%   here and equally correct.
:- dynamic worker_registry/3.

%!  worker_server(?WorkerId, ?Server) is nondet.
%
%   WorkerId -> its listening uv_tcp_t handle. Set once, by
%   register_server/2, right after worker:worker_loop/2's uv_listen/3
%   succeeds -- the listener does not exist yet when register_worker/2
%   runs (that happens straight after uv_loop_new/1), so it cannot be
%   recorded there. Closing this handle during shutdown is what actually
%   stops a worker from accepting *new* connections -- see
%   on_shutdown_async/2.
:- dynamic worker_server/2.

%!  register_worker(+WorkerId, +Loop) is det.
%
%   Called by a worker, on its own thread, right after uv_loop_new/1 and
%   before entering uv_run/2 (see worker:worker_loop/2). Creates a
%   uv_async_t on Loop whose callback -- run on Loop's own owning
%   thread whenever uv_async_send/1 fires it -- performs the graceful
%   stop (on_shutdown_async/2), then records the worker in the shared
%   registry under a mutex.
%
%   The async callback closure is explicitly module-qualified
%   (bridge:on_shutdown_async/2) rather than left bare: it is recorded
%   by the C layer via PL_record/1 and later invoked through
%   uv_dispatch:uv_invoke/2, whose strip_module/3 call resolves an
%   unqualified callable against uv_dispatch's own context module, not
%   the module that built the term -- exactly the pitfall worker.pl's
%   on_connection registration already works around the same way.
register_worker(WorkerId, Loop) :-
    uv_async_init(Loop, bridge:on_shutdown_async(WorkerId, Loop), Async),
    with_mutex(bridge_registry,
               assertz(worker_registry(WorkerId, Loop, Async))).

%!  register_server(+WorkerId, +Server) is det.
%
%   Called by a worker, on its own thread, right after uv_listen/3
%   succeeds (see worker:worker_loop/2). Records the listening handle so
%   on_shutdown_async/2 can close it later. Same thread-affinity rule as
%   every other handle here: Server is only ever touched (closed) back
%   on this same worker's own thread, from inside its own async
%   callback -- never cross-thread.
register_server(WorkerId, Server) :-
    with_mutex(bridge_registry,
               assertz(worker_server(WorkerId, Server))).

%!  on_shutdown_async(+WorkerId, +Loop) is det.
%
%   Runs on the worker's own thread, as every uv_async_t callback does,
%   fired via uv_async_send/1 from shutdown_all_workers/0. Performs a
%   *graceful* stop (adr/0031), not the abrupt uv_stop/1 this used to
%   call directly:
%
%     1. Close this worker's listening socket, if one has been
%        registered yet (worker_server/2) -- from this point on, no new
%        connections are accepted. uv_close/2 is itself asynchronous;
%        its completion fires on a later turn of this very loop.
%     2. Close this worker's own shutdown-async handle (looked back up
%        out of worker_registry/3). An async handle counts as "active"
%        for as long as it exists -- it could be uv_async_send/1'd again
%        at any moment -- so leaving it open would keep uv_run/2 blocking
%        forever even after every connection has finished. Closing a
%        handle from inside its own firing callback is an ordinary,
%        supported libuv pattern -- the same thing http_stream.pl does
%        when it closes a client connection as the last step of its own
%        message-complete callback.
%
%   Deliberately does NOT call uv_stop/1: connections already in flight
%   (accepted before the listener closed) are left running. Each closes
%   itself the normal way once its response is fully written --
%   http_stream.pl's one-response-per-connection, close-after-write
%   model (adr/0007) -- at which point it stops counting as an active
%   handle. Once the listener, this async handle, and every in-flight
%   connection have all closed, uv_run/2 has zero active handles left
%   and returns by itself (UV_RUN_DEFAULT's documented behaviour):
%   worker:worker_loop/2 then returns and the worker's OS thread exits.
%
%   There is deliberately no per-worker timeout in here: the *bounded*
%   half of "bounded grace period" is enforced one level up, by whoever
%   waits on these worker threads (worker:install_shutdown_handler/0)
%   giving up after a fixed deadline and halting anyway, regardless of
%   whether every worker has actually finished draining -- see adr/0031.
on_shutdown_async(WorkerId, Loop) :-
    format(user_error, "worker ~w: shutting down (no longer accepting connections)~n", [WorkerId]),
    ( with_mutex(bridge_registry, retract(worker_server(WorkerId, Server)))
    -> uv_close(Server, bridge:noop_close)
    ;  true
    ),
    ( worker_registry(WorkerId, Loop, Async)
    -> uv_close(Async, bridge:noop_close)
    ;  true
    ).

%!  noop_close is det.
%
%   uv_close/2's completion callback; nothing to do once a listener or
%   this worker's own async handle finishes closing -- worker_loop/2's
%   uv_run/2 noticing there are no active handles left is the only
%   signal anything downstream needs.
noop_close.

%!  shutdown_all_workers is det.
%
%   Signal every currently-registered worker to stop gracefully. Safe to
%   call from any thread (e.g. a signal handler thread, see
%   worker:install_shutdown_handler/0): it never touches a worker's loop
%   or handles directly, it only calls uv_async_send/1 on each worker's
%   async handle, which is libuv's cross-thread-safe wakeup primitive.
%   Each worker's own on_shutdown_async/2 then runs, same-thread,
%   same-loop, and each worker's own uv_run/2 returns once that worker
%   has stopped accepting connections and drained whatever was already
%   in flight (see on_shutdown_async/2).
%
%   Registry access is mutex-guarded because workers may still be
%   concurrently registering themselves (via thread_create/3-started
%   startup) while this reads the registry -- see the startup-race note
%   above for what that means for workers not yet registered.
shutdown_all_workers :-
    with_mutex(bridge_registry,
               findall(Async, worker_registry(_, _, Async), Asyncs)),
    forall(member(Async, Asyncs), uv_async_send(Async)).
