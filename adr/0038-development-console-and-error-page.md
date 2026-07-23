# 0038. The development console and rich error page

Status: Accepted

## Context

The ergonomics review named the framework's worst trait: silent
failure. A typo'd column, a missing clause, a `path_id` that fails —
all collapse into an indistinguishable blank `404 Not Found` (or a
terse `500`) with nothing in the log. Rails' whole development
experience is the opposite: a rich error page pinpointing the failing
line, with a REPL at the crash frame (better_errors + web-console).
We want that — and the dict excision (adr/0037) just made it feasible,
because the env is now a legible plain term (`[method-get,
path-"/comments", params-[...]]`) instead of an opaque `_G123{...}`.

The REPL half is dangerous. Rails' web-console has shipped real CVEs
whose root cause was always the same: the console endpoint reachable
in production. An endpoint that evaluates arbitrary code is remote
code execution the instant it is reachable by an attacker. The design
below treats "unreachable in production" as the primary requirement,
ahead of any feature.

## Decision 1: development-only, gated at boot, absent in production

Everything here is gated on a single boot-time fact `dev_console`,
set once when `px_config:current_env(development)` — the exact pattern
adr/0036 established for `dev_assets`, and for the exact same reason:
a per-request `current_env/1` check is unreliable inside a `px build`
binary (whose runtime `PROLOGEX_ENV` is whatever the deploying shell
happens to have), whereas the boot-time fact is snapshotted correctly
by `qsave_program/2`, and `px build` forces `PROLOGEX_ENV=production`
while loading, so a built binary's `dev_console` fact is *false* — the
console is not merely disabled, it is not compiled in.

The console/REPL endpoint is **not registered as a route** in
production. A request to it in production gets an ordinary 404 — no
"forbidden" page, no hint the feature exists, no attack surface. The
rich error page rendering is likewise skipped in production, which
serves the same terse `404`/`500` bodies as today, byte-identical.

## Decision 2: the rich error page (development)

When a request would produce a 404 or 500 in development, render an
HTML diagnostic page instead of the terse body:

  - **Classify the failure**, the feature that answers the silent-404
    complaint directly. Development records breadcrumbs (Decision 4)
    so the page can say which stage failed: *no route matched
    `GET /articles/5`* vs *route `article` matched, but `model(show)`
    failed* vs *an exception was thrown* vs *a template referenced a
    missing part*. "Route matched but the model failed" is the single
    most useful line this project can print.
  - **The env, as a legible term** — the pairs list, formatted, so you
    see method, path, params, headers, the resolved user at a glance.
  - **For a 500**: the exception term, its `message_to_string/2`
    rendering, and the `context(...)` (predicate + hint) SWI attached.
  - **The route table** on a 404, so "no route matched" is obvious
    from seeing what routes exist.
  - **The REPL** (Decision 3), inline.

## Decision 3: the inline REPL

The REPL is reachable two ways in development, both at the fixed dev
path `/__px/console`: `POST` evaluates a goal (used by the error page
and the console page alike), and `GET` renders a standalone,
browsable **console page** — the same token-guarded REPL, the env
dumped as a legible term, and the route table, without an error to
attach to. The example app links to it from its home page in
development only (`current_env(development)`); production never
advertises a route it does not serve. Both routes are registered
only by `enable_dev_console/0`, so in production a `GET` or `POST` to
`/__px/console` is an ordinary 404.

The REPL is a `<px-console>` custom element — a terminal-style
scrollback with command history (`↑`/`↓`), multi-line input
(`Shift+Enter`), and `clear` — self-contained in the console page (no
build step, no app asset pipeline). It POSTs a goal and renders the
JSON reply: bindings as `Name = Value`, then `true.`/`false.`, output
before the result, errors in red. The eval endpoint reads a goal
string, evaluates it once **in module `user`** (so unqualified goals
resolve against user's imports and app predicates are called
qualified), and returns that JSON — output, the first solution's
bindings, and whether it solved. Evaluation is `read_term_from_atom` + `call` in a chosen
app module, output captured with `with_output_to`, errors caught and
shown. The power of this is the whole point and the whole danger, so
beyond the boot gate:

  - **A per-boot random token.** At boot the console generates a
    128-bit random token. The endpoint requires it; the token appears
    only in the dev error page (rendered same-origin). A blind
    cross-site `POST` to the endpoint therefore cannot carry it — this
    is the defense for the case that most concerns us here, a dev
    server exposed through the exe.dev proxy. The token is not a
    production control (there is no endpoint in production); it is
    drive-by protection for an exposed dev server.
  - **Documented boundary**: the console is for local development; a
    development-mode server should not be deliberately exposed to the
    public. Production — the deployed posture (`PROLOGEX_ENV=
    production`, what the systemd units set) — has the whole feature
    off. This is the same contract Rails draws around web-console.

## Decision 4: development breadcrumbs

Classification needs to know what happened during the request. In
development only, a thread-local trace accumulates breadcrumbs the
router and controller append to — *matched route N*, *calling
handler H*, *model(Action) failed*, *exception E*. In production the
breadcrumb calls are not made at all (guarded by `dev_console`), so
there is zero overhead and zero behavior change. The trace is reset
per request.

## Consequences

The framework's headline weakness — losing the information a developer
needs into a blank 404 — is answered: development now says exactly
which stage failed and lets you poke the live app at the failure. The
cost is a genuinely dangerous capability (arbitrary evaluation) whose
safety rests entirely on the boot-time gate and route-registration
being correct; that boundary is therefore tested explicitly — a
production boot must 404 the console endpoint and serve terse error
bodies, and a `px build` binary must contain no console route at all.
The rich page consumes the plain-term env directly, which is the
concrete payoff of adr/0037 arriving right when this feature needs it.
