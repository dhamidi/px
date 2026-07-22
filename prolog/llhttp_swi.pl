:- module(llhttp_swi,
          [ llhttp_parser_new/1,
            llhttp_on_url/2,
            llhttp_on_header_field/2,
            llhttp_on_header_value/2,
            llhttp_on_headers_complete/2,
            llhttp_on_body/2,
            llhttp_on_message_complete/2,
            llhttp_execute/3,
            llhttp_pause/1,
            llhttp_resume/1,
            llhttp_method_name/2
          ]).

/** <module> Loader for c/llhttp_swi.so, the 1:1 llhttp FFI (adr/0002, adr/0003).

Foreign predicates registered by a shared library land in whatever
module is "current" when use_foreign_library/1 runs -- which, without
this dedicated loader module, would silently be whichever module
happens to load the library first. Giving the library its own module
with an explicit export list means every predicate below is reliably
importable from any module via use_module/1, regardless of load order.

## Registering callbacks: module-qualify them, and load uv_dispatch

llhttp_on_url/2, llhttp_on_header_field/2, llhttp_on_header_value/2,
llhttp_on_headers_complete/2, llhttp_on_body/2 and
llhttp_on_message_complete/2 each record a Prolog closure that the C
side fires later, synchronously, from inside llhttp_execute/3, via
uv_dispatch:uv_invoke/2 -- the exact same trampoline c/uv_swi.c uses
for libuv callbacks. This module does not load prolog/uv_dispatch.pl
itself (uv_swi.pl doesn't either, for the same reason): the caller is
expected to `use_module(uv_dispatch)` before any callback actually
fires, same as worker.pl does. Without it, the first callback firing
raises existence_error(procedure, uv_dispatch:uv_invoke/2), reported
(and swallowed, per call_closure/3 in llhttp_swi.c) to stderr rather
than propagated -- so a missing use_module/1 here shows up as
callbacks silently not doing anything, not a load-time error.

uv_invoke/2 does
`strip_module(Closure, M, Plain), ..., call(M:Goal)`: an *unqualified*
atom or compound registered from module X will silently resolve in
whatever module happens to be current at the point llhttp_execute/3 is
later called, not module X, which typically means an
existence_error(procedure, ...) at the worst possible moment. Always
register callbacks module-qualified, e.g. `worker:on_body`, exactly as
worker.pl does for uv_swi.pl's callbacks.

## Parsing model

llhttp_parser_new/1 always initializes an HTTP_REQUEST parser: this
framework is a server, so it only ever needs to parse requests, never
responses (see adr/0003).

## Backpressure (adr/0008)

llhttp_pause/1 and llhttp_resume/1 must only be called between
llhttp_execute/3 calls, never from inside a registered callback --
llhttp itself documents this restriction. The callback trampolines in
c/llhttp_swi.c therefore never translate a callback's outcome into
HPE_PAUSED on your behalf; a worker that wants to apply backpressure
calls llhttp_pause/1 itself once llhttp_execute/3 returns, based on how
far behind its own consumer has fallen.
*/

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../c/llhttp_swi'], LibBase),
   use_foreign_library(LibBase).
