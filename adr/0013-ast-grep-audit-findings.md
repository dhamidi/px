# 0013. ast-grep audit of the C sources

Status: Accepted

## Context

`c/uv_swi.c`, `c/llhttp_swi.c`, and `c/http_stream_swi.c` are hand-written
C, and per adr/0002 they're deliberately kept small and mechanical
specifically so they're easy to audit. Once the FFI core was working and
proven (worker model, TCP echo, `SO_REUSEPORT` multi-worker, llhttp
parsing, fs/timer/async bindings, the response `IOSTREAM`), it was worth
actually running that audit rather than assuming "small and mechanical"
implied "correct."

## Decision

Used `ast-grep` (a structural search tool, not text/regex-based) against
all three C files for two classes of pattern:

- Unsafe string functions (`strcpy`, `strcat`, `sprintf`, `gets`) --
  none found.
- Every `malloc`/`calloc` call site, checked for a null-pointer guard
  before the returned pointer is dereferenced.

The second sweep found seven real gaps, all sharing the same shape: a
pointer from `malloc`/`calloc` was dereferenced (to set a struct field,
or via `memcpy`) with no check that the allocation actually succeeded --
an allocation failure would have been a null-pointer dereference, not a
clean error back to Prolog. Fixed all seven:

- The `conn_ctx_t` allocation shared by the TCP, timer, and async
  handle-creation paths (three call sites, one per handle kind).
- The write-request allocation in `uv_write/3` (both the request struct
  and the copied-data buffer).
- All three fs request allocations (`uv_fs_open/5`, `uv_fs_read/5`,
  `uv_fs_close/3`), including the read buffer itself.

Each fix follows the pattern already used elsewhere in the file for
allocation failures: free whatever was already allocated on this path
and return `PL_resource_error("memory")`, so an allocation failure
surfaces as an ordinary Prolog resource-error exception instead of
crashing the worker.

## Consequences

Rebuilt and reran the full milestone test suite (1, 3, 4, 6) after the
fixes -- all pass, confirming the fixes didn't change any success-path
behavior, only the previously-missing failure path. Allocation failure
under normal operation is extremely unlikely (these are small, fixed-size
structs), so this audit mostly buys defense-in-depth rather than fixing
an observed crash -- worth doing anyway, since the whole point of keeping
this layer small was to make exactly this kind of check cheap to run and
trust.

One related, deliberately *not* fixed gap surfaced during earlier
work on the worker shutdown path (adr/0005/0006): a handle's Prolog
blob can be garbage collected without its underlying libuv handle ever
having been `uv_close`'d, since blob release only frees memory and
never calls `uv_close`. That's a handle-lifecycle question (when is a
handle allowed to close, not whether a pointer is null), out of scope
for this audit and left as a known limitation for a future pass.
