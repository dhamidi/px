:- module(bridge, [register_worker/2, shutdown_all_workers/0]).

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
     callback calls uv_stop/1 on that same loop, and records
     WorkerId-Loop-Async in a small shared registry.
  2. shutdown_all_workers/0 (called from whatever thread decides to shut
     the service down, e.g. the thread handling SIGINT) reads that
     registry and calls uv_async_send/1 on every worker's async handle --
     never uv_stop/1 directly. Each worker's own thread then wakes up
     inside its own uv_run/2, its own async callback runs, and IT calls
     uv_stop/1 on itself. uv_run/2 then returns once that iteration of
     the loop completes (libuv does not require pending handles to be
     closed first for uv_run/2 to return -- see libuv's uv_stop/1 docs).

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

%!  register_worker(+WorkerId, +Loop) is det.
%
%   Called by a worker, on its own thread, right after uv_loop_new/1 and
%   before entering uv_run/2 (see worker:worker_loop/2). Creates a
%   uv_async_t on Loop whose callback -- run on Loop's own owning
%   thread whenever uv_async_send/1 fires it -- calls uv_stop(Loop),
%   then records the worker in the shared registry under a mutex.
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

on_shutdown_async(WorkerId, Loop) :-
    format(user_error, "worker ~w: shutting down~n", [WorkerId]),
    uv_stop(Loop).

%!  shutdown_all_workers is det.
%
%   Signal every currently-registered worker to stop. Safe to call from
%   any thread (e.g. a signal handler thread): it never touches a
%   worker's loop directly, it only calls uv_async_send/1 on each
%   worker's async handle, which is libuv's cross-thread-safe wakeup
%   primitive. Each worker's own uv_run/2 then returns once its own
%   thread processes the wakeup and calls uv_stop/1 on itself.
%
%   Registry access is mutex-guarded because workers may still be
%   concurrently registering themselves (via thread_create/3-started
%   startup) while this reads the registry -- see the startup-race note
%   above for what that means for workers not yet registered.
shutdown_all_workers :-
    with_mutex(bridge_registry,
               findall(Async, worker_registry(_, _, Async), Asyncs)),
    forall(member(Async, Asyncs), uv_async_send(Async)).
