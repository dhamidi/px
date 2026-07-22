# 0004. libuv binding scope: TCP, fs, timers, async

Status: Accepted

## Context

libuv is a large library. Beyond TCP it covers UDP, named pipes, TTY
handles, a filesystem API, timers, child process spawning, DNS
resolution helpers, signal handling, and more. Binding all of it 1:1
into Prolog, as ADR-0002 requires for anything that is bound at all,
would mean a lot of C surface area to write, wrap, and keep correct —
most of it in service of capabilities this project has no use for.

The demo application only needs libuv to do three things: accept TCP
connections and read and write HTTP bytes on them, read files off disk
per request (`adr/*.md` for the ADR log, `apps/static/*` for static
assets), and time out connections that go idle or stall mid-request.

## Decision

Bind only the subset of libuv that the framework actually uses:

- `uv_loop_*` — loop creation and the run loop itself.
- `uv_tcp_init`, `uv_tcp_bind`, `uv_tcp_listen`, `uv_tcp_accept` —
  accepting inbound connections.
- `uv_read_start`, `uv_read_stop` — reading bytes off a connection.
- `uv_write` — writing bytes to a connection.
- `uv_close` — tearing down handles.
- `uv_async_init`, `uv_async_send` — cross-worker control signals; see
  ADR-0005 for what sends and receives them and why.
- `uv_fs_open`, `uv_fs_read`, `uv_fs_close` — reading files off disk.
- `uv_timer_init`, `uv_timer_start`, `uv_timer_stop`, `uv_timer_close`
  — idle and slow-connection timeouts.

Everything else in libuv is explicitly out of scope: UDP, pipes, TTY
handles, child process spawning, the DNS resolution helpers, and signal
handling beyond libuv's own defaults. None of it is wrapped, and none
of it is reachable from Prolog.

`uv_fs_*` deserves a specific note. libuv does not run filesystem calls
on the loop thread — it dispatches them to its own internal threadpool
and always delivers the completion callback back on the calling loop's
thread. That property matters here specifically: it means file reads
compose for free with the worker model described in ADR-0005, with no
extra bridging code needed to keep a file read off the loop thread. A
request handler that reads a file under `adr/` or `apps/static/` never
performs a blocking synchronous read that would stall its worker; the
threadpool dispatch that keeps the loop thread free is libuv's job,
not something `c/uv_swi.c` or the Prolog layer has to arrange.

## Consequences

The binding stays small and matches exactly what the demo app does:
serve HTTP over TCP, read files, and enforce timeouts. Nothing in
`c/uv_swi.c` exists to satisfy a hypothetical future need.

Extending to more of libuv later — UDP, child processes, or anything
else — is possible but not free. It means writing more 1:1 wrappers
under the same strict rule from ADR-0002, and thinking through how each
new capability interacts with the per-worker ownership model before any
Prolog code can use it.

There is no partial or dynamic FFI escape hatch. Anything not bound in
`c/uv_swi.c` is simply not usable from Prolog, full stop — not
reachable through a generic "call arbitrary libuv function" path, not
available by dropping to a lower-level interface. If the framework ever
needs a libuv capability outside this list, the only way to get it is
to bind it properly and revisit this decision.
