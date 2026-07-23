# 0036. Hot reload in development

Status: Accepted

## Context

The single worst thing about developing a prologex app is the feedback
loop: templates, controllers and CSS all load at boot, so *every*
change — even a color — needs a full `bin/px server` restart. Rails
reloads changed files on each request in development and serves assets
unhashed from source; the edit-refresh loop is seconds. We want that.

## Decision

Two mechanisms, both gated on `px_config:current_env(development)`
(the default when `PROLOGEX_ENV` is unset, adr/0022) and inert in
production — a production boot must behave exactly as today.

1. **Reload-on-request for app code.** Before dispatching each request
   in development, check the mtimes of every loaded file under `app/`
   (and `config/app.pl`); if any changed since last seen, reload them
   before the request runs. This is Rails' development model and fits
   the worker architecture (the check runs on the worker's own thread;
   no watcher thread, no inotify binding).

   Reloading is `load_files(Changed, [if(true)])`. SWI tracks per-file
   clause ownership, so reloading a file *replaces* the clauses it
   owns — including the multifile clauses it contributed to other
   modules: a view's `~>` templates (`px_template:tmpl/2`) and a
   messages file's `form_definition/3` are file-owned and replace
   cleanly. Module-local predicates (model/3, view/3, update/4,
   commands) replace as ordinary clause reload.

   The one hazard is facts asserted at load time by `:- initialization(
   ..., now)` directives rather than loaded as clauses: **routes**.
   `register_route/4` currently always `assertz`es, so a re-run on
   reload duplicates the route. The fix is to make route registration
   **idempotent by name**: replacing any existing `route/4` of the same
   name before asserting. Route names are unique per route, so this is
   correct for both first load and reload. `register_path_helper/3` and
   `add_schema/1` already check-before-assert; `form_definition/3` is a
   loaded clause; so route idempotency is the whole fix.

   A reload that raises (a syntax error in the file being edited) must
   not crash the worker: catch it, keep the previously loaded version
   live, and surface the error to the response (the development error
   page, adr to follow) rather than 500-ing silently.

2. **Assets served from source in development.** In development,
   `serve_asset/2` serves files straight from `assets/` by their
   logical name (`/assets/css/app.css`), unhashed, with no-cache
   headers and no compile step — so a CSS edit is visible on the next
   request with zero rebuild. `stylesheet_tag`/`javascript_importmap_tags`
   emit the unhashed logical paths in development. Production is
   unchanged: hashed, fingerprinted, immutable-cached, compiled at boot
   (adr/0025). The manifest/hashing path is production-only.

## Consequences

The dev loop becomes edit-save-refresh, seconds not a restart. The cost
is a per-request mtime scan of the app tree in development only —
cheap, and never present in production or in a `px build` binary (which
is production by construction). Route registration becoming
idempotent-by-name is a small semantic tightening that is also just
more correct: registering the same route name twice was never
meaningful. The mechanism is deliberately reload-on-request, not a
background watcher: it needs no new threads, can never reload
mid-request, and reloads exactly when it matters — right before code
runs.
