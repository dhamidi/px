# 0034. px is a script over swipl, and bootstraps itself

Status: Accepted

## Context

A fresh `git clone` of the framework cannot run: the C bindings
(`c/*.so`) are build products, correctly gitignored, and the
Makefile's bare `-luv` never finds Homebrew's libuv on macOS (which
lives under `/opt/homebrew` on Apple Silicon, off every default
search path). The question was whether the fix is a compiled `px`
binary or a bootstrap step.

## Decision

**px stays an executable-over-swipl, deliberately.** A compiled px
could not do its job: applications load the framework *source* at
runtime (adr/0027 boot, adr/0030 references), so the checkout must
exist regardless — a px binary would be a launcher for files it
cannot carry. (`px build`, adr/0033, is the opposite case: an *app*
snapshot that carries everything precisely because loading is over.)

Instead, the clone bootstraps itself:

1. `bin/px` checks for swipl up front and, when missing, prints the
   one install line for the detected OS (`brew install swi-prolog
   libuv` / `apt install swi-prolog-nox libuv1-dev build-essential`).
2. Commands that run the framework (`server`, `routes`, `console`,
   `build`) build `c/` automatically when any shared object is
   missing — announced, once, needing only cc, make and libuv.
   `px new`, `help` and `version` work with swipl alone.
3. The Makefile finds libuv through pkg-config when available
   (Homebrew ships a `libuv.pc`), falling back to `-luv` where the
   default paths suffice (Debian). Compilation and linking go
   through `swipl-ld`, which owns the platform specifics.

So the whole getting-started is:

    git clone https://github.com/dhamidi/px && px/bin/px new myapp
    cd myapp && bin/px server        # C bindings build here, once

## Consequences

There is no install step to document beyond two packages, and no
version skew between a px binary and the framework tree — the script
IS the tree. The macOS path is designed (pkg-config, swipl-ld, and
SWI's use of the `.so` extension for foreign objects on Darwin) but
was not run on real macOS hardware when written; the first Mac clone
is the test, and whatever it surfaces lands as fixes to this
decision's mechanics, not its shape.
