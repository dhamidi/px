# 0001. Project goals and layout

Status: Accepted

## Context

Prologex is an experiment: what does an HTTP server framework look like if
you lean into Prolog's strengths instead of porting the idioms of Express
and friends? Unification-based routing can be reversible. DCGs are a
natural fit for parsing. Dispatch can fall out of pattern matching rather
than an imperative chain of callbacks.

To answer that question honestly the framework needs real I/O, not a toy.
That means binding two C libraries through SWI-Prolog's foreign-function
interface: llhttp for HTTP request parsing and libuv for the event loop.
Pure Prolog is then layered on top of those bindings to provide the
ergonomics — routing, middleware, request/response objects, streaming.

The proof that the framework works is a deployed application, not a test
suite in isolation. That application is this project's own ADR log: a
site that reads the markdown files in `adr/`, renders them to HTML, and
serves the result over HTTP using the framework it documents.

## Decision

Lay out the repository by concern, one top-level directory each:

- `adr/` — this ADR log. Numbered markdown files, accepted or superseded,
  and also the content the demo app renders and serves.
- `vendor/llhttp/` — the vendored, pre-built amalgamated llhttp C sources,
  taken from an upstream GitHub release rather than built from the
  original ragel grammar. See ADR-0003.
- `c/` — the C side of the FFI. Two 1:1 bindings, `llhttp_swi.c` and
  `uv_swi.c`, plus a small control-plane bridge, `bridge.c`/`bridge.h`,
  that lets libuv callbacks hand work back to a Prolog engine. Built with
  `swipl-ld` into loadable `.so` files. See ADR-0002.
- `prolog/` — the framework itself, in pure Prolog:
  - `worker.pl` — worker lifecycle (ADR-0005)
  - `http_stream.pl` — streaming IOSTREAMs over the connection (ADR-0007)
  - `router.pl` — route matching and dispatch (ADR-0009)
  - `middleware.pl` — middleware chaining (ADR-0010)
  - `request.pl` / `response.pl` — request and response representations
  - `app.pl` — the `listen/2` entrypoint applications call
  - `markdown/parser.pl` and `markdown/html.pl` — the markdown-to-HTML
    pipeline used to render the ADR log (ADR-0011)
- `apps/` — `adr_site.pl`, the demo application, plus its `static/`
  assets.
- `deploy/` — the systemd unit and run script used to run the demo app
  in production (ADR-0012).
- `test/` — smoke tests.

The concurrency unit the framework is built around — one OS thread
running one libuv event loop with one attached SWI-Prolog engine,
co-located as a single unit — is called a worker throughout the codebase
and these ADRs. Its design is covered in full in ADR-0005 and ADR-0006
and is not repeated here.

## Consequences

The `c/` and `prolog/` split enforces a hard rule elaborated in ADR-0002:
the C side stays a literal, uncreative 1:1 binding of llhttp and libuv,
and every Prolog-specific idea — reversible routing, DCG-based parsing,
anything resembling framework ergonomics — lives in `prolog/` instead.
This makes the C code auditable for memory safety and correctness on its
own terms, without having to reason about Prolog semantics at the same
time, and it keeps the door open to rewriting the Prolog layer without
touching the FFI.

Because the demo app serves this ADR log, the markdown in `adr/` is not
just documentation: it is input to `prolog/markdown/parser.pl` and
`prolog/markdown/html.pl` at runtime. Malformed markdown or a parser gap
shows up as a broken page on the running site, not just an ugly file in
git. ADR formatting and CommonMark compliance therefore matter
functionally, and the markdown pipeline is effectively dogfooded on every
ADR from 0001 onward.
