# 0031. Graceful shutdown on SIGTERM

Status: Accepted

## Context

`swipl` installs no SIGTERM handler by default, so `systemctl --user
stop prologex` had nothing to ask the process to shut down with:
systemd's default stop sequence sends SIGTERM, gets no response at all
(the process just keeps running, oblivious), waits out the full
`TimeoutStopSec` (systemd's own default is 90s), and only then escalates
to SIGKILL. Every `stop`/`restart` during development was paying that
90-second stall.

`deploy/prologex.service` had been shipping a workaround for exactly
this, called out in its own comment:

```
# swipl installs no SIGTERM handler, so the default stop sequence stalls
# for the full 90s TimeoutStopSec before systemd escalates. Until graceful
# shutdown is wired (bridge:shutdown_all_workers exists but is unbound to
# any signal), kill outright: the app is stateless between requests and
# sqlite recovers via its journal.
KillSignal=SIGKILL
TimeoutStopSec=5
```

That comment also names exactly what was missing: `bridge.pl` already
had `shutdown_all_workers/0` (added alongside the worker model itself,
adr/0005/adr/0006, and proved by `test/milestone5_shutdown.pl`) -- a
correct, thread-safe fan-out that wakes every worker's `uv_loop_t` via
`uv_async_send/1` and lets each worker's own thread call `uv_stop/1` on
its own loop, same-thread, per libuv's rules. It was just never bound to
a signal, and even if it had been, milestone5's own header comment
already documented the gap: `uv_stop/1` stops loop iteration without
closing any handles, so the old fan-out did not actually stop a worker
from accepting new connections, and gave whatever was already in flight
no chance to finish -- it just abandoned it mid-response the instant
`uv_stop` fired.

## Decision

Two independent, additive pieces, both scoped to `prolog/bridge.pl` and
`prolog/worker.pl` (no C changes needed -- every libuv primitive this
uses, `uv_close/2`, `uv_timer_*` unused in the end, `uv_stop/1`,
`uv_async_*`, was already a 1:1-bound predicate per adr/0002):

**1. `bridge.pl`'s fan-out now stops gracefully, not abruptly.**
`worker.pl`'s `worker_loop/2` registers its listening socket with a new
`bridge:register_server/2` (mirroring the existing `register_worker/2`,
just one step later -- the listener does not exist yet when
`register_worker/2` runs). `on_shutdown_async/2` -- the callback that
runs, worker-thread-local, when `shutdown_all_workers/0` wakes a
worker -- no longer calls `uv_stop/1` at all. Instead it closes that
worker's listening socket (no more *new* connections) and its own
async handle (an async handle counts as "active" for as long as it
exists, so leaving it open would keep `uv_run/2` blocking forever even
after every connection finished). Nothing else is touched: connections
already accepted keep running exactly as before, each closing itself
the ordinary way once its response is fully written
(`http_stream.pl`'s one-response-per-connection, close-after-write
model, adr/0007). Once the listener, the async handle, and every
in-flight connection have all closed, `uv_run/2` has zero active
handles left and returns by itself -- `UV_RUN_DEFAULT`'s documented
behaviour, not a forced stop -- and the worker's OS thread exits
normally.

**2. `worker:install_shutdown_handler/0`** wires SIGTERM and SIGINT
(`on_signal/3`) to a handler that calls `shutdown_all_workers`, then
waits, bounded, for every worker thread to actually finish (polling
`thread_property/2` until it throws `existence_error` -- workers are
`detached(true)`, so `thread_join/2` isn't available; a finished
detached thread is reaped immediately and starts throwing that error,
the same technique `test/milestone5_shutdown.pl` already used), then
calls `halt(0)`. The grace period is fixed at 5 seconds
(`shutdown_grace_seconds/1`): long enough for an in-flight response to
finish, short enough that a genuinely stuck worker (adr/0006: a
blocking handler stalls its whole worker) cannot make `systemctl stop`
hang the way the SIGKILL workaround was built to route around in the
first place -- if a worker is still not done by then, this just halts
anyway. Confirmed empirically (not assumed) that `on_signal/3`'s
handler goal runs synchronously on whichever thread receives the
signal -- for this project, the main thread, since it's the one parked
in `prologex_run/0`'s `thread_get_message(_)` when SIGTERM arrives;
SWI delivers the signal by interrupting that blocking call and running
the handler there before considering resuming it. Calling `halt/1` from
inside the handler ends the process immediately, so the interrupted
`thread_get_message(_)` never needs to actually return.

`prolog/prologex.pl` is being edited in parallel by other work and was
intentionally left untouched here. Wiring this in for real is one line,
right before `prologex_run/0`'s closing `thread_get_message(_)`:

```prolog
worker:start_workers(Port, Workers, prologex:px_conn),
worker:install_shutdown_handler,
thread_get_message(_).
```

Proved independently of `prologex_run/0` by
`test/milestone18_graceful_shutdown.sh`, which boots its own 2-worker
server directly on `worker:start_workers/3` +
`worker:install_shutdown_handler/0` (no `app/`, no
`prolog/prologex.pl`), on a side port (8131, never 8090 / the real
systemd unit), and checks against the exact `swipl` PID it started:
the server serves before shutdown; SIGTERM makes it exit within 10s
with status 0; the port is released afterwards; and a slow,
already-in-flight request (`curl --limit-rate` against a multi-megabyte
body built from this repo's own `adr/*.md` files, repeated past this
VM's ~4MB TCP send-buffer autotune ceiling so the response genuinely
cannot be handed to the kernel in one shot -- real backpressure, not
something that would pass by accident) still completes byte-for-byte
despite the SIGTERM landing mid-transfer.

`deploy/prologex.service`'s workaround block is removed --
`KillSignal=SIGKILL` and its `TimeoutStopSec=5` are gone, replaced by a
comment pointing at this ADR and a `TimeoutStopSec=15` safety net (not
relied on in normal operation: the handler's own 5s grace period plus
halt overhead should always finish well inside that, `TimeoutStopSec=15`
just bounds what happens if the mechanism itself ever regresses,
without going back to systemd's 90s default).

## Consequences

`systemctl --user stop prologex` (once the one-line
`install_shutdown_handler` call above lands in `prologex_run/0` and this
service file is reinstalled) now stops in low single-digit seconds
instead of stalling for up to 90s, and does so via the application's own
clean exit (status 0) rather than an external SIGKILL. In-flight
requests are no longer silently abandoned mid-response the instant
shutdown is requested -- they get to finish, bounded by a grace period
that itself now has a real, tested number attached to it rather than
being an untested assumption. The old SIGKILL workaround is safe to
remove precisely because it stops being a safety-relevant workaround:
the process now responds to SIGTERM correctly, so systemd's normal
signal escalation path is the one actually exercised, with
`TimeoutStopSec=15` sitting behind it purely as a regression backstop.
No C code changed -- this was achievable entirely with libuv primitives
`prolog/bridge.pl` and `prolog/worker.pl` already had 1:1 access to
(adr/0002); the one thing that had to be earned empirically rather than
assumed was which thread `on_signal/3`'s handler actually runs on, since
getting that wrong (e.g. assuming a fresh, unrelated thread with no
usable Prolog context) would have made calling `halt/1` from inside it
questionable.
