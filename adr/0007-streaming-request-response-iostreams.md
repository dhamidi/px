# 0007. Streaming request and response bodies via IOSTREAM

Status: Accepted

## Context

A hard requirement for this project is that HTTP bodies are streams,
never byte buffers. A request handler must never be handed "the whole
body as one pre-built atom or string" as its *only* option, because
that would mean buffering an arbitrary amount of client data in memory
before any processing could start. It would also be dishonest about
what is actually happening underneath: llhttp is a genuinely
incremental, chunk-at-a-time parser. `llhttp_execute` is designed to be
called repeatedly with small chunks as they arrive off the socket, not
handed a complete message body in one call. An API that hid this behind
a single materialized buffer would be throwing away the one property
that makes llhttp worth binding in the first place.

The same reasoning applies symmetrically to responses. A handler
generating a large or slow response — proxied content, a generated
report, a long file — should be able to write it out incrementally as
it becomes available, not be forced to assemble the entire response
body before the first byte reaches the socket.

At the same time, most handlers do not care about squeezing out
maximal per-worker concurrency. A handler that reads a small JSON body
and replies with a small JSON body loses very little by treating the
body as "just a string I can parse" — as long as that convenience is
built on top of real streaming rather than replacing it.

## Decision

The request/response API has two layers.

The low-level layer is event-driven. As the owning worker's engine
drives `llhttp_execute` on newly-read socket bytes, llhttp's C
callbacks invoke Prolog predicates directly and synchronously:
`on_headers/2`, `on_body/2`, `on_end/1`. This is the genuinely
streaming layer — nothing pre-buffers the body independently of these
calls. A handler working at this level sees exactly the chunks as
llhttp produces them, in the order llhttp produces them, and can act on
each one immediately (for example, writing it straight to a file
without ever holding the full body in memory).

On top of that, a convenience layer offers an optional helper, for
example `read_body_to_string/2`, that a handler can call when it does
not need maximal per-worker concurrency and just wants the body
materialized. This mirrors the trade-off Node's own `body-parser`
middleware makes — buffering the body before calling the route
handler — which is a recognized, accepted pattern in real Node apps,
not a violation of the "never byte buffers" rule. The data is still
arriving and being handed off chunk-by-chunk under the hood regardless
of which layer a given handler chooses to use; the convenience layer
just accumulates those chunks on the handler's behalf instead of
requiring the handler to do it manually.

The convenience layer is implemented as a real SWI-Prolog `IOSTREAM`
object, built via `Snew`/`IOFUNCTIONS` (`prolog/http_stream.pl` plus C
support). `Sread` blocks, in the ordinary Prolog-thread sense, until
more body bytes have arrived or the body is complete. This is only ever
called from the owning worker's own thread and engine, which is safe
by construction: a worker never has cross-thread contention on its own
connections (see ADR-0005 for what a worker is).

Response writing mirrors this on the way out. `Swrite` on the response
`IOSTREAM` triggers `uv_write` directly — legal here specifically
because it runs on the same thread that owns the loop. Responses are
chunked-transfer-encoded when the response length is not known
upfront, and content-length-framed when it is.

## Consequences

Handler authors choose their altitude. Raw event callbacks give true
streaming — for example, proxying a large upload straight to disk
without ever holding it all in memory. The ordinary-feeling
blocking-read convenience API covers everything else, without the
framework ever silently doing the expensive thing — full buffering —
as its only option.

The cost is two APIs to maintain and document instead of one. This is
kept deliberately thin: the convenience layer is built strictly on top
of the event layer, not as a separate parallel implementation, so bugs
in chunk delivery only need to be fixed once.
