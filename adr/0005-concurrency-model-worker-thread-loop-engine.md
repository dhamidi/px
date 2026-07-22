# 0005. Concurrency model: worker = thread + loop + engine

Status: Accepted

## Context

SWI-Prolog threads, created with `thread_create/3`, are real operating
system threads — a 1:1 mapping onto pthreads, each with its own fully
attached Prolog engine. They are not green or cooperative threads
multiplexed onto a small number of kernel threads, the way goroutines
or Erlang processes are. This matters directly for a server design: it
rules out "spawn a Prolog thread per accepted connection" as a scaling
strategy, because the real OS thread count would then scale linearly
with concurrent connection count.

Separately, libuv's event loop (`uv_run`) needs to run on some
dedicated thread to do non-blocking I/O multiplexing at all. The
question this ADR answers is how the loop thread and Prolog engine
threads relate to each other.

The design went through three iterations before converging on the one
below.

The first idea was a single non-Prolog "reactor" thread running one
global `uv_loop`, handing work off to a Prolog thread spawned per
accepted connection via a queue. This was rejected on two grounds: it
reintroduces the thread-per-connection blow-up on the Prolog side, and
direct verification against SWI-Prolog's C API documentation showed
there is no C-level API to post into a Prolog `message_queue` from a
thread with no attached engine. Attaching an engine to the reactor
thread "just for this" was considered and rejected too — an attached
engine on that thread risks it getting caught in SWI-Prolog's
stop-the-world garbage collector rendezvous across all attached
engines, which would stall the event loop for the duration of every
such rendezvous.

The second idea fixed the thread-per-connection blow-up with a bounded
thread pool: a small fixed pool of reactor threads, each running its
own loop and its own `SO_REUSEPORT` listener, plus a separate bounded
pool of Prolog worker threads pulling ready connection events off a
shared queue. This works. But it adds an entire extra queue and
hand-off layer between "the thread that owns the loop" and "the thread
that owns the engine," and that layer exists purely because the two
were assumed to need to be different threads.

The third and final idea is that they do not need to be different
threads at all. Put the loop and the engine on the same thread. Since
that thread already has an attached Prolog engine — it is a genuine
`thread_create/3` Prolog thread — C callbacks firing during that
thread's own `uv_run` call can call `PL_call` directly and
synchronously, with no cross-thread hand-off needed for the common
request path. This is a direct copy of how Node.js itself works: one
thread, one event loop, callbacks run directly on it. Node's own
scaling story is exactly "run more independent copies of that unit"
(the `cluster` module, `worker_threads`), never "add a thread pool
behind a shared loop."

## Decision

The core concurrency unit is a **worker**: one OS thread, running one
`uv_loop_t`, with one attached SWI-Prolog engine, permanently
co-located for the worker's entire lifetime. The loop and the engine
never separate from the thread or from each other.

The default configuration is exactly one worker at startup, matching
Node's single-threaded-by-default behavior exactly. Scaling is running
more workers — a configurable count, with a reasonable default
suggestion of the CPU core count — where each worker independently
binds the listen socket via `SO_REUSEPORT` so the kernel load-balances
new connections across workers with zero coordination required between
them. This is the direct analogue of Node's `cluster`/`worker_threads`
scaling model.

Workers share no mutable state by default, the same shared-nothing
posture Node workers have. Each worker independently opens its own
`uv_fs_*` handles, owns its own connections end to end, and never
reaches into another worker's data.

The `c/bridge.c` / `c/bridge.h` code that exists alongside the workers
is control-plane only: startup coordination, and fanning a shutdown
signal out to every worker's loop via `uv_async_send`. It is never a
per-request data plane, and no request-handling data crosses between
workers through it or any other channel.

## Consequences

This is a real simplification over both earlier designs, not merely a
rename — it deletes an entire queue and hand-off layer that the second
design needed. It also means the request/response streaming design
can use a real, straightforwardly blocking-looking `IOSTREAM`
implementation where `Sread` and `Swrite` are only ever called from
the worker's own thread. That is safe by construction: there is no
cross-thread contention on a connection's stream, because the loop
that reads and writes it and the engine that runs handler code over it
never leave the same thread.

The trade-off this design creates — a worker's single thread is both
the event loop and the Prolog execution context, so blocking one
blocks the other — is not addressed here. It is covered in full in
ADR-0006.
