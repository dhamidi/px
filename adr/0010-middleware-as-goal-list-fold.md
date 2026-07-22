# 0010. Middleware as a goal list folded over request/response state

Status: Accepted

## Context

Express's middleware model is a chain of functions `(req, res, next) =>
...`. Each middleware either handles the request outright, calls `next()`
to pass control to the next middleware in the chain, or calls `next(err)`
to jump straight to error handling. That three-way shape exists because
JavaScript has no other lightweight way to express "try this, and if it
declines, try the next thing" — it is continuation-passing style bolted
onto the language by necessity, with `next` standing in for the rest of
the computation.

Prolog already has native control flow that covers the same three cases.
Failure means "this didn't apply, try something else." A cut or
successful return means "this handled it, stop." An exception means
"abandon the normal flow and jump to a handler." None of that needs to be
reinvented as an explicit callback argument.

## Decision

Middleware in this framework is an ordinary Prolog list of goals, threaded
over the request/response state with a fold in the vein of `foldl/4` from
`library(apply)` — one of the modern libraries that ship with SWI-Prolog
that this project leans on rather than reinventing. A middleware chain is
just:

```prolog
run_chain([], Req, Req).
run_chain([Goal|Goals], Req0, Req) :-
    call(Goal, Req0, Req1),
    run_chain(Goals, Req1, Req).
```

"Decline and pass control to the next middleware" is ordinary Prolog
failure: if `Goal` fails, the fold does not proceed to `Goals` on its
own the way `next()` would — instead the framework wraps each step so
that a failed middleware is simply skipped and the next goal in the list
is tried against the same state. Concretely this means each step is
attempted via a small wrapper predicate rather than a bare `call/3`, so
that failure of one middleware falls through to the next list element
instead of failing the whole chain. "Abort the chain with an error" is
an ordinary Prolog exception, thrown with `throw/1` from anywhere inside
a middleware goal and caught once, at the top of the chain, by whatever
installed it — typically the request dispatcher described in ADR-0009.

There is no `next` parameter. A middleware predicate's signature is just
`goal(Req0, Req)` (or `goal(Req0, Req, Extra...)` for parameterized
middleware built with closures via `library(yall)` or explicit partial
application) — the same shape as any other state-transforming Prolog
predicate in this codebase, request and response threaded through
exactly the way `library(apply)` already expects.

## Consequences

Middleware authors write plain Prolog predicates with an obvious
success/failure/exception contract instead of learning a
framework-specific calling convention. There is no `next` to remember to
call, forget to call, or call twice — classes of bug that are common in
Express codebases and structurally impossible here, because "continue to
the next middleware" is not a function you invoke but simply what
happens when a goal does not otherwise succeed or throw.

The trade-off is that anything genuinely asynchronous-feeling in the JS
sense does not have a direct equivalent. In Express it is common for a
middleware to kick off some work, call `next()`, and then run more code
*after* a later middleware in the chain has finished — code written
after the `next()` call but logically executed once control returns.
Prolog's fold has no such callback-return point: `run_chain/3` is a
plain recursive predicate, not a chain of callbacks that hand control
back to their caller. Anything that needs to happen "after the rest of
the chain has run" has to be written as its own explicit goal, placed
later in the list, rather than as code following a call to `next`. This
is a deliberate simplification rather than an oversight, and it is
recorded here so that if a real use case exposes a gap in it — a
middleware that genuinely needs to wrap the rest of the chain, such as
timing or transaction-scoping middleware — that gap can be evaluated
against this decision instead of quietly worked around.
