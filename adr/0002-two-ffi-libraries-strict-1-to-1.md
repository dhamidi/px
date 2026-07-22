# 0002. Two FFI libraries, strict 1:1

Status: Accepted

## Context

Prologex binds two C libraries into SWI-Prolog through its C foreign-function
interface: llhttp for HTTP parsing and libuv for the event loop and
non-blocking I/O. There are two broad ways to write these bindings.

One option is "smart" bindings: bake Prolog ergonomics directly into the C
layer, so the foreign functions themselves return dicts, drive DCGs, throw
Prolog exceptions with structured context, or otherwise make decisions about
how the data should look to application code.

The other option is dumb, literal wrappers: each exported predicate is a
thin, mechanical pass-through to one underlying C function, and every bit of
ergonomics is layered on top in Prolog.

The C layer is the part of this codebase least amenable to Prolog's own
tooling — no unit-clause testing, no easy REPL exploration, no `ast-grep`
queries over Prolog source. Anything that goes wrong in C is more expensive
to find and fix than the equivalent bug in Prolog. At the same time, the
project's stated premise is that the ergonomics — dict-based requests, DCG
routing, reversible path generation, markdown parsing — are exactly the kind
of thing Prolog is good at and C is not.

## Decision

We use strict 1:1 FFI. The bindings are split into two C files:

- `c/llhttp_swi.c` wraps `llhttp_init`, `llhttp_execute`, `llhttp_pause`,
  `llhttp_resume`, and the `llhttp_settings_t` callback slots.
- `c/uv_swi.c` wraps the libuv subset the framework needs: loop, TCP
  init/bind/listen/accept, `read_start`/`read_stop`, write, close, async,
  `fs_open`/`fs_read`/`fs_close`, timer init/start/stop/close, and run.

Every exported Prolog predicate maps to exactly one underlying C function
call. No branching logic, no data-structure translation beyond what is
strictly required to cross the FFI boundary (C structs to and from Prolog
terms), and no policy decisions live in these two files.

A third file, `c/bridge.c` / `c/bridge.h`, is the one deliberate exception,
and it is scoped narrowly: it handles cross-worker control-plane concerns —
startup coordination and shutdown fan-out across workers (see ADR-0005 and
ADR-0006 for what a worker is and how workers are coordinated) — never
per-request data. It does not wrap llhttp or libuv calls and is not part of
the 1:1 surface.

All ergonomics — dict-based requests, DCG-based routing, reversible path
generation, middleware chaining, markdown parsing — live exclusively in
`prolog/`, built on top of the 1:1 layer. None of it lives in C.

## Consequences

The C code stays small and mechanically checkable: each function in
`llhttp_swi.c` and `uv_swi.c` can be checked against the upstream llhttp and
libuv API documentation one call at a time, and the uniform 1:1 shape makes
the files a good audit surface for `ast-grep` (see the audit ADR for the
tooling this enables).

The cost lands on the Prolog side. C callbacks hand back raw terms and atoms,
and `prolog/` has to do the work of assembling those into dicts, running them
through DCGs, and otherwise making them ergonomic. This is the intended
trade: the framework's premise is that leveraging Prolog means putting
ergonomics in Prolog, not in C, and this decision is what keeps that premise
honest instead of letting convenience creep back into the C layer over time.

A practical benefit follows from this split: once the 1:1 layer is solid,
bugs in policy — routing behavior, streaming semantics, request/response
shaping — should never require touching C. They are Prolog bugs, fixable and
testable as Prolog code.
