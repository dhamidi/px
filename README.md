# prologex

An experiment: bind [llhttp](https://github.com/nodejs/llhttp) (HTTP
parsing) and [libuv](https://libuv.org/) (event loop) into
[SWI-Prolog](https://www.swi-prolog.org/) via its C foreign-function
interface, then build an Express-like HTTP framework on top in pure
Prolog — leaning on unification and DCGs where they genuinely buy
something (reversible routing, streaming parsers) rather than porting
JavaScript idioms directly.

On top of that transport core sits a Rails-flavoured layer (adr/0016
through adr/0024): a Rack-style env threaded through handlers as
`Goal(Env0, Env)` relations, `:- resources(...)` REST routing with
reversible path helpers, Phlex-style streaming templates behind a
single new operator (`Head ~> Body` — bytes hit the wire as the term
is walked, never buffered), vendored SQLite with a Sequel-style
query builder where a row is a nondeterministic solution, declared
forms that validate and re-render themselves, config as a Prolog
file, and Hotwire/Turbo (frames, streams, progressive enhancement)
out of the box.

Applications are structured by convention on the Elm Architecture
rather than MVC (adr/0027): each page is a module giving `model/2`
(build everything the page needs; failure is the 404), `view/2`
(pure, Model in, template term out) and — for pages that accept
messages — `update/4`, a relation from a decoded message and model
to a new model plus *effects as data* (redirect, turbo streams,
status), Elm's `Cmd` on the response side. A `:- page(Path)`
directive wires routes, message dispatch, and a reversible path
helper; there is no application "main" file at all — `bin/server`
boots whatever `app/` and `config/` contain.

The proof of the framework is a real app: `app/` serves this
project's own [architecture decision log](adr/) — markdown files
parsed by a hand-written DCG markdown engine, rendered to HTML, and
served over the framework's own router — plus a sqlite-backed
guestbook exercising forms, the query builder, and Turbo streams.
Start reading at `adr/0016-rails-layer-syntax-north-star.md` and
`adr/0027-app-structure-elm-architecture.md` for the application
surface, or `app/pages/guestbook.pl` to see it used.

## Why it's built the way it is

Every non-obvious decision is written down as it was made, one file per
decision, in [`adr/`](adr/) — including the ones that were revised after
getting feedback mid-build (the concurrency model went through three
iterations before landing on `adr/0005`; a real use-after-free bug found
while bringing up the demo app is `adr/0014`). Start at
[`adr/0001-project-goals-and-layout.md`](adr/0001-project-goals-and-layout.md)
for the map of the rest.

## Layout

```
adr/              one markdown file per decision (also the content the demo app serves)
vendor/           vendored amalgamated llhttp + sqlite C sources (adr/0003, adr/0020)
c/                1:1 C FFI: llhttp_swi.c, uv_swi.c, http_stream_swi.c, sqlite3_swi.c
prolog/           the framework: the transport core, the Rails layer (px_*.pl),
                   the TEA page runtime (px_page.pl), px_ui + prolog/ui/, markdown/
app/              the demo app, in the adr/0027 standard layout:
  pages/           one Elm-Architecture page per file (model/update/view)
  views/           shared templates (layout.pl)
  lib/             plain domain relations (adrs.pl)
assets/           css/ + js/ sources for the pipeline (adr/0025)
config/           app.pl — port, workers, database (adr/0022)
bin/server        boots the app by convention; deploy/ wraps it for systemd
test/             milestone proofs for each layer, run for real, not just written
```

## Running it

```sh
cd c && make
cd .. && bin/server
```

Or as a systemd user service — see `deploy/prologex.service` for the
install commands.

## px_ui — the component library

A full port of [Radix UI's primitives](https://www.radix-ui.com/) to
server-rendered Prolog templates: 32 components living in `prolog/ui/`,
browsable live at `/ui` on the demo site. The porting recipe is
`adr/0026`; the per-component analysis that drove it is
`docs/radix-port-analysis.md`. Highlights of the approach: the exact
Radix data-state/ARIA styling contract, platform-first implementations
(native `<dialog>`, the `popover` attribute, `<details name=...>`
exclusivity, styled native inputs) with small custom elements only for
irreducible behavior (roving tabindex, typeahead, hover delays), shared
machinery as plain ES modules (`lib/roving-focus`, `lib/popper`,
`lib/menu`) served through the import map, and progressive enhancement
throughout — Select renders a real native `<select>` that both works
without JS and remains the form-submitted value store after upgrade.
Every component shipped with contract tests, a CSS-coverage guard, and
headless-Chrome verification of real interactions against
radix-ui.com's own demos.

## Tests

Each `test/milestoneN_*.pl` is a standalone proof that one layer of the
stack actually works (not just compiles) — e.g. `milestone2_multiworker.pl`
proves the kernel is really load-balancing connections across
independent workers via `SO_REUSEPORT`, and `milestone8_markdown.pl`
proves the markdown engine against real ADR content. `test/smoke.sh`
checks a running instance end to end.
