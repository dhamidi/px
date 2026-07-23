# 0032. The px CLI

Status: Accepted

## Context

The framework has conventions (adr/0027, adr/0029) but no tooling:
creating an app means hand-copying directory shapes, adding a
feature means remembering five file skeletons, and inspecting the
route table means reading source. Rails answers this with `rails
new/generate/routes/console/server`; Django with `django-admin` +
`manage.py`. A convention-over-configuration framework without a
generator is a convention you have to memorize.

## Decision

One executable, `bin/px`, a thin shell exec into
`prolog/px_cli.pl`'s `main/1`. Commands:

    px new APP           scaffold a new application directory
    px generate feature NAME    scaffold app/NAME/ (alias: px g)
    px routes            print the route table of the app in cwd
    px server            boot the app in cwd (what bin/server does)
    px console           interactive toplevel with the app loaded
    px build [-o FILE]   compile the app into one executable (adr/0033)
    px version | help

Principles:

1. **Scaffolds are self-documenting working examples** (rule
   hardened after the blog dogfooding run): `px generate feature
   posts [field:widget ...]` emits a COMPLETE resource —
   list/show/new/create/edit/update/destroy, validation, 422
   re-render, safe id parsing — that serves correctly with zero
   edits, and whose comments teach every convention in user
   language: the request cycle, failure-is-404, forms validated
   before update, form-posts-to-the-page-that-renders-it, route
   declaration order, the no-if-then-else template idiom, global
   template/path-helper resolution, and why the domain fold is
   called module-qualified. **Generated files never reference ADRs
   or any framework-internal document** — a user must never need
   the framework source or its decision log to work on their app.
   `px new` follows the same rules for `config/app.pl`, the layout
   (viewport tag), the middleware pipeline, and a `welcome` feature;
   the generated app boots and serves immediately.

2. **Framework discovery is by location, overridable by
   environment** (adr/0030's principle applied to the CLI): `px`
   resolves the framework tree relative to its own script path;
   `PX_HOME` overrides. `px new` writes the discovered location into
   the generated `bin/px` and `bin/server` shims, so a scaffolded
   app is tied to a framework checkout explicitly and visibly.

3. **`px routes` is the reversible router made visible**: it runs
   the boot's load phase (no workers), then prints one line per
   `router:route/4` fact — method, path template (regenerated from
   the stored segments through the same `path_template//1` DCG that
   parsed it), route name, and handler — in registration order,
   which is match order.

4. **`px console` is the Rails console**: the app loaded (config,
   features, routes, db lazily on first query), an ordinary SWI
   toplevel. `guestbook_commands:load_comments(Cs).` just works.

5. **Boot splits into load and serve.** `prologex_run/0` becomes
   `prologex_load/0` (config, paths, assets mount, app tree,
   pipeline, layout, compile assets) then `prologex_serve/0`
   (db dir, workers, signal handler, block). routes/console stop
   after load; build (adr/0033) saves the state after load and makes
   `prologex_serve/0` the binary's entry.

## Consequences

The README's "Running it" becomes `bin/px server`. The five-file
feature shape stops being something to remember: it is what `px g
feature` types for you, with the ADR's own worked example inline as
guidance. The CLI lives in the framework repo and serves both roles
the repo plays (framework checkout and demo app). Not built now,
deliberately: `px test` (no app-level test convention exists yet)
and `px generate` beyond features (model/migration generators need a
migration story first).
