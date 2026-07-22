# 0015. Load-tested to 10,000 concurrent connections

Status: Accepted

## Context

Everything up to this point had been proven correct at low volume --
milestone tests hit the server with a handful of sequential requests,
and the demo app was manually verified with a dozen or so curl calls.
None of that exercises real concurrency. Asked directly: does this
actually hold up at 10,000 concurrent connections, the kind of load the
worker model (adr/0005) was designed around? The honest answer required
actually generating that load and watching what happened, not reasoning
about it from the design docs.

Installed `hey` (a Go-based HTTP load generator, `go install
github.com/rakyll/hey@latest` -- no `wrk`/`ab`/`siege` available via apt
on this VM) and ran graduated tests against the live service: c=10
(baseline), c=1000, then c=10000 with n=20000.

## What broke, and what didn't

**Two infrastructure limits, fixed before the interesting testing could
even start:**

- The systemd user unit's default soft `LimitNOFILE` is 1024 -- nowhere
  near enough for thousands of concurrent open sockets. Set
  `LimitNOFILE=65536` explicitly in both `deploy/prologex.service` and
  `deploy/prologex-system.service`.
- `uv_listen`'s backlog was hardcoded to 128 (a milestone-testing
  leftover, never revisited). Raised to 4096, matching this VM's kernel
  `net.core.somaxconn` ceiling -- passing anything higher wouldn't do
  anything, the kernel caps it there regardless.

**A real, serious bug found under load that never showed up at low
volume:** at c=10000 the server reliably segfaulted within seconds,
always inside `on_connection_cb` while accepting a new connection, with
a stack trace showing clear signs of heap corruption (mismatched/bogus
symbol names from a crash site that isn't the actual bug site -- classic
use-after-free fingerprint). Root cause, found by rebuilding with `-g`
and reproducing under `gdb`: adr/0014's fix only pinned a handle's blob
atom alive from the moment `uv_close` was called onward. It did nothing
for the much larger window *before* that -- from handle creation
through the entire time a connection is only reachable via async
callbacks, with no live Prolog-level term referencing it (a listening
socket, in particular, is never referenced again by any Prolog goal
once `uv_run` starts blocking forever; a client connection is
unreferenced between one I/O event and the next). Nothing stopped
SWI's atom GC from reclaiming that blob -- and therefore `free()`-ing
the handle struct -- while libuv still held a live pointer to it. This
was always possible, in principle, from the very first connection; it
just needed enough GC pressure to actually trigger, which sequential
testing never produced and 10,000 concurrent connections did, reliably.

Fixed properly this time: pin every handle's blob atom (`PL_record`)
at *creation* time (`pl_uv_tcp_init`, `pl_uv_timer_init`,
`pl_uv_async_init`), not just at close time -- covering the handle's
entire lifetime in one consistent mechanism. `pl_uv_close`'s
now-redundant close-time pinning was removed (keeping both would leak
the first record). `release_ctx` still erases the pin exactly once,
when `on_close_cb` confirms libuv is actually done with the memory.

**After that fix**, three consecutive c=10000/n=20000 runs against the
live service: zero crashes, zero restarts, and (once running 2 workers
-- see below) zero connection resets and zero refused connections.
Checked `/proc/<pid>/fd` after the runs: 4 open sockets remaining (the
2 workers' listeners plus housekeeping) -- no descriptor leak from the
tens of thousands of connections opened and closed during testing.

**One remaining, real finding, not hidden:** with a single worker (the
demo app's previous default), c=10000 ran without crashing but with
~5% of requests failing with "connection reset by peer" -- the single
accept loop couldn't drain 10,000 near-simultaneous connection attempts
fast enough, and the kernel started resetting the overflow. Switching
the demo app to `workers(2)` (matching this VM's 2 CPU cores, exactly
what adr/0005 says to do to add headroom) took that to zero resets
across repeated runs -- a real, measured confirmation that the
documented scaling story actually works, not just a claim. With a
default (~20s) client timeout, a small number of requests (4-5%) still
timed out client-side under the heaviest concurrency; rerunning with a
longer client timeout (`hey -t 60`) got 20000/20000 to `200 OK` with
zero errors of any kind -- confirming this is a latency/queueing
characteristic (each worker's single thread still serializes its share
of requests, per adr/0006's documented "don't block the event loop"
trade-off, so very high concurrency means queueing, not failure), not
a capacity failure.

## Decision

Ship with `workers(2)` in `apps/adr_site.pl` (was `workers(1)`) and the
raised `LimitNOFILE`/backlog as the deployed configuration. The
handle-pinning fix is not optional -- without it the service cannot
survive real concurrent load at all, regardless of worker count.

## Consequences

The server now demonstrably handles 10,000 concurrent connections:
every request eventually completes correctly, with no crash, no
descriptor leak, and (at 2 workers) no connection resets. The
remaining latency under extreme concurrency is a direct, expected
consequence of adr/0006's design, not a defect -- and now has a real
number attached to it instead of just a description. Worker count is a
tuning knob, not a fixed constant; a busier deployment would want more
than 2, bounded by core count as adr/0005 already says. The
handle-pinning bug is a strong argument for load-testing as a standard
part of finishing any feature built on this FFI layer -- sequential
testing, however thorough, did not and could not have found it.
