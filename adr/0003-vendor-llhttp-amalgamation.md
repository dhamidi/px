# 0003. Vendor the llhttp amalgamation instead of building from source

Status: Accepted

## Context

The framework's HTTP parsing sits on top of llhttp, the parser extracted
from Node.js. There is no apt or distro package for llhttp on this Ubuntu
24.04 VM, so it has to come from somewhere else.

llhttp's canonical source is not C. It is written in TypeScript as a state
machine grammar and compiled down to C by a separate tool, `llparse`.
Building llhttp from its canonical source therefore means running a
Node.js toolchain to regenerate the C files before a single line of the
framework can be compiled. This VM has no Node or npm installed, and
pulling in an entire JavaScript build chain just to produce roughly 300KB
of generated C felt like the wrong dependency for a Prolog experiment to
carry, especially for a build step that only ever needs to run once, on
llhttp's own release cadence, not on every developer's machine.

## Decision

llhttp's maintainers publish the pre-generated, ready-to-compile amalgamated
C sources directly on each tagged release branch upstream — no `llparse`
run and no Node required to use them as-is.

Vendor `include/llhttp.h`, `src/api.c`, `src/http.c`, and `src/llhttp.c`,
along with `LICENSE-MIT`, from the `release/v9.4.2` branch of
`github.com/nodejs/llhttp`, into `vendor/llhttp/` in this repository as a
flat drop-in. These files are compiled straight into the build alongside
`c/llhttp_swi.c` via the project Makefile, with no generation step of our
own.

## Consequences

No Node.js dependency exists anywhere in this project, at build time or
otherwise. The cost is that the parser's grammar cannot be regenerated or
customized locally: any such change would require pulling in `llparse` and
Node after all. That trade-off is acceptable because this project only
needs to consume llhttp's compiled C API — parsing HTTP requests via its
callbacks — not modify how it parses.

The vendored files are a point-in-time snapshot of `release/v9.4.2`, not a
submodule or a pinned package fetched at build time. Upgrading llhttp
later means repeating the same manual steps against a newer release
branch and diffing the result, not running a version bump command.

`llhttp.h`, `api.c`, `http.c`, and `llhttp.c` are treated as third-party
and are never edited in place, so that future re-vendoring stays a clean
file replacement rather than a merge. Any wrapping, adaptation, or
SWI-Prolog-specific glue lives entirely in `c/llhttp_swi.c` instead.
