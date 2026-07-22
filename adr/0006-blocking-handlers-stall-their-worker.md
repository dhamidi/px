# 0006. Blocking handlers stall their worker

Status: Accepted

## Context

ADR-0005 establishes the worker as one OS thread running one `uv_loop_t`
with one attached Prolog engine, permanently co-located. A direct and
unavoidable consequence follows from that: the same single thread is
both the thing running the event loop and the thing running Prolog
handler code. If a handler genuinely blocks — a slow synchronous
computation, or blocking on I/O outside the framework's own async
primitives — it stalls that worker's other connections for exactly as
long as the block lasts. No other connection on that worker makes
progress: no bytes are read, no bytes are written, no timer fires,
until the handler returns control to the loop.

This is not a bug to be found and fixed later. It is a structural
property of putting the loop and the engine on the same thread, which
ADR-0005 chose deliberately for the simplicity and safety it buys
elsewhere.

## Decision

Do not engineer around this for the initial version of prologex.
Document it and accept it as a known, well-understood trade-off. It is
exactly the same "don't block the event loop" rule Node.js has always
had — Node has the identical failure mode for the identical reason,
because one thread is both its loop and its JavaScript execution
context.

The mitigation is the same one Node relies on: run more than one
worker in production, so a stalled worker does not take down the whole
service, and write handler code that is non-blocking and fast by
construction.

The demo application in this repository, `apps/adr_site.pl`, only does
small local file reads and in-memory markdown rendering per request.
Both are cheap and short-lived. A single default worker is therefore
provably fine for this experiment, and the demo does not need to be
run with multiple workers to make its point.

## Consequences

This is flagged explicitly as future work, not attempted now: an SWI-Prolog
engine is a distinct primitive from an OS thread — in principle an
engine can be created and attached to or detached from a thread
independently of any specific thread. A later iteration could explore
cooperatively multiplexing several logical connections' engines onto a
single worker's thread, for true intra-worker concurrency closer to
how goroutines behave. That is a substantial design in its own right
and is not part of this decision.

For now, the whole story is: one worker, don't block it, run more
workers if more headroom is needed. Any handler code that must do real
blocking work — heavy computation, a blocking library call, a
synchronous filesystem or network operation outside libuv's own
non-blocking primitives — is out of scope for what this version of the
framework can protect a worker's other connections from. That
responsibility sits with whoever writes the handler, exactly as it
does in Node.
