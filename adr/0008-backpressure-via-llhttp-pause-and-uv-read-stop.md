# 0008. Backpressure via llhttp pause and uv_read_stop

Status: Accepted

## Context

The streaming design for request and response bodies (see the ADR on
streaming `IOSTREAM`s over connections) means body bytes can arrive
off the socket faster than a request handler consumes them. A handler
doing slow per-chunk processing — writing each chunk to disk, say, or
running it through some transform — while the client uploads at full
network speed is an entirely ordinary case, not a pathological one.

Without some way to tell the producer to slow down, the only way to
cope with that mismatch is to keep buffering the unconsumed bytes in
memory until the handler catches up. That is exactly the
unbounded-buffering outcome the streaming design exists to avoid: an
`IOSTREAM` that hands chunks to the handler as they arrive is only an
improvement over "read the whole body into memory first" if the gap
between "arrived" and "consumed" is itself kept bounded.

## Decision

llhttp exposes `llhttp_pause` and `llhttp_resume` — a parser can be
paused mid-stream, and a callback can also return `HPE_PAUSED` to
pause it directly from inside the callback that noticed the consumer
is behind. libuv separately exposes `uv_read_stop` and
`uv_read_start` on a TCP handle, which stop and restart the kernel
delivering any more raw bytes on that socket at all.

These compose into a two-stage valve. When a consumer — whether it is
reading via the low-level event callbacks or via the convenience
blocking-read helper — falls sufficiently behind the bytes already
delivered to it, the worker pauses the llhttp parser with
`llhttp_pause`. Parsing stops there; no further HTTP-level events fire
until the consumer catches up. If the socket keeps producing more raw
bytes than even the paused parser can hold, the worker escalates to
the second stage and calls `uv_read_stop`, which stops the kernel from
delivering any more data on that connection at all. Both stages are
reversed once the consumer catches up: `llhttp_resume` restarts
parsing, and `uv_read_start` restarts kernel delivery.

The trigger for both stages is how far behind the consumer has
fallen, not a fixed buffer-size cutoff. There is no single "N bytes
and then pause" constant baked into the worker. This is deliberate:
different requests are read in different ways — some handlers drain
the low-level events as fast as they're delivered, others block on the
convenience read helper and only pull one chunk at a time — and a
fixed-size cutoff would either be too tight for the fast path or too
loose for the slow one. Measuring the actual gap adapts to whichever
way a given request happens to be read.

## Consequences

Memory use per connection is now bounded by how far behind the
slowest active consumer is allowed to fall, rather than by how much of
the body has arrived off the wire so far. That is the whole point of
doing this at all — it turns an unbounded quantity (bytes sent by a
client who can push data faster than the handler processes it) into a
bounded one (bytes in flight beyond the pause threshold).

The cost is real state to track per connection: how many bytes have
been delivered to the consumer versus how many it has actually
consumed, plus the current pause/resume status of both the llhttp
parser and the libuv read side, since the two stages can be
independently engaged or disengaged. Getting this bookkeeping wrong —
pausing without ever resuming, or resuming a read side that was never
actually stopped — produces stalled or leaking connections that are
easy to miss in a quick manual test. That makes this logic a natural
target for the ast-grep-based audit of the C bridge code, and it needs
direct testing (see the streaming-proof smoke test) that asserts
chunks genuinely arrive incrementally, and that a deliberately slow
consumer causes visible pause/resume cycles, rather than either
buffering everything up front or silently dropping bytes.
