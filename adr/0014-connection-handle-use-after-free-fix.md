# 0014. Fixed a use-after-free on every closed connection

Status: Accepted

## Context

While bringing up the demo app (adr/0013 was the last audit pass on the
C sources, done before this bug was exercised), the server segfaulted
reliably after 2-3 real HTTP requests, always inside `on_connection_cb`
while accepting a *new*, unrelated connection -- a strong signal of
heap corruption from something earlier, not a bug in accept itself.

The root cause: `uv_close/2`'s Prolog-visible handle term is normally
dropped by the caller the moment `uv_close` is called (see
`http_stream.pl`'s `on_message_complete/4`, which calls `uv_close(Client,
...)` as its last step and then simply returns). Once nothing in Prolog
references that term anymore, SWI's atom garbage collector is free to
reclaim the handle's blob atom at any later point -- including *before*
libuv has actually finished closing the handle, since `uv_close` is
asynchronous and only truly finishes when its completion callback
(`on_close_cb`) fires on a later loop iteration. The blob's `release`
callback does a bare `free()` of the underlying `uv_swi_handle_t` (by
design, per adr/0002 -- see `c/uv_swi.c`'s `release_uv_swi_handle`).
If that `free()` happens while libuv still holds a live pointer to the
same memory, libuv later touches freed memory: a classic
use-after-free, surfacing as a crash somewhere else entirely once the
corrupted heap is next touched -- exactly what was observed.

This generalizes a narrower risk already flagged as a known limitation
during the worker-shutdown work: a listener socket outliving its
`uv_close` was called out there as a *theoretical* gap specific to
shutdown. It turned out to be a much more general bug, hit on the
ordinary request path, not just shutdown.

## Decision

Added a `self_ref` field to the per-handle context struct
(`conn_ctx_t` in `c/uv_swi.c`), populated with `PL_record(handle_t)`
inside `pl_uv_close` at the moment `uv_close` is called. A recorded
term keeps any atoms it references alive regardless of what Prolog code
does with its own local variables -- the same mechanism this file
already used for callback closures, just applied to the handle itself.
The record is erased inside `release_ctx`, called from `on_close_cb`
once libuv confirms the close has actually completed -- only then is
the blob genuinely safe to eventually free.

## Consequences

Verified with a real stress test: 11 sequential HTTP requests against
the live demo app (previously crashing by request 3) all completed
correctly with no crash. This fix is generic to any handle closed via
`uv_close/2`, not just TCP client connections, so it also covers the
timer/async-handle case originally flagged. Every `uv_close/2` call now
costs one extra `PL_record`/`PL_erase` pair per handle close -- cheap,
and correctness-critical, not a hot-path concern worth optimizing away.
