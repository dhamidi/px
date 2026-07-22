# 0025. Asset pipeline: Propshaft + importmap, no bundler

Status: Accepted

## Context

adr/0024 vendored Turbo as `apps/static/turbo.js` and adr/0016's demo
app served it — and `style.css` — through two hand-written routes:

```prolog
:- route(get, "/static/style.css", static_css).
:- route(get, "/static/turbo.js", static_js).

static_css(Env0, Env) :-
    static_file('style.css', Text),
    respond(Env0, raw(Text),
            [header("content-type", "text/css; charset=utf-8")], Env).
```

This works, but it has exactly the problems Rails had before
Propshaft and importmap-rails replaced Sprockets: every asset is
served under a fixed URL, so a browser (or an intermediate cache) that
already has `/static/style.css` cached keeps serving the OLD stylesheet
after a deploy until the cache entry expires — there is no way to say
"cache this forever" without also saying "and never notice when it
changes." The fix Rails 8 shipped is not a bundler; it is two much
smaller ideas working together:

- **Propshaft**: don't transform assets (no Sass, no bundling, no
  source maps to keep in sync) — just fingerprint them. Compute a
  content hash, copy the file to `<name>-<hash>.<ext>`, and serve THAT
  URL with a cache header that never expires, because the URL can only
  ever mean one exact set of bytes.
- **importmap-rails**: don't bundle JavaScript either. Ship an [import
  map](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/script/type/importmap)
  — a small JSON document, `{"imports": {"turbo": "/assets/turbo-...js"}}`
  — so the browser's own native ES module loader resolves bare
  specifiers (`import "turbo"`) to fingerprinted URLs. No webpack, no
  esbuild, no `node_modules`.

adr/0003's vendoring philosophy ("a point-in-time snapshot committed
to the repository, no package manager and no network at build or run
time") already ruled out a JS bundler for this framework; this ADR is
what fills the resulting gap with the Rails-8-shaped answer, in
keeping with adr/0016's "the 80% of Rails that makes it productive."

## Decision

### 1. Source layout

```
assets/
  css/
    app.css        (moved from apps/static/style.css)
  js/
    app.js          (new: the import-map entrypoint, `import "turbo";`)
    turbo.js         (moved from apps/static/turbo.js -- see section 5)
  img/
```

Plain files, nothing generated: `assets/js/*.js` are ordinary ES
modules — no JSX, no TypeScript, no `.vue`. `apps/static/` is gone;
`prolog/px_assets.pl` (module `px_assets`) is the whole pipeline.

### 2. `compile_assets/0`: hash, copy, gzip, manifest

```prolog
?- compile_assets.
true.
```

walks `assets/` recursively and, for every regular file:

1. Computes its sha256 (`library(crypto)`'s `crypto_file_hash/3`) and
   takes the first 12 hex characters.
2. Copies it, byte for byte, to
   `public/assets/<basename>-<hash12>.<ext>` — e.g.
   `assets/css/app.css` → `public/assets/app-9f12070d41cf.css`.
3. Writes a gzip sibling next to it: `app-9f12070d41cf.css.gz`
   (`library(zlib)`'s `gzopen/4`).
4. Records `"css/app.css": "app-9f12070d41cf.css"` — the path
   relative to `assets/`, forward-slash separated, mapped to the
   hashed basename — in `public/assets/.manifest.json`.

```json
{
  "css/app.css":"app-9f12070d41cf.css",
  "js/app.js":"app-72916b74ea34.js",
  "js/turbo.js":"turbo-ec1e72f6f2d2.js"
}
```

**Idempotent.** The hash is a pure function of the content, so
compiling twice with nothing changed produces byte-identical output —
nothing is rewritten, nothing is deleted. This is what makes it safe
to call on every process start (section 6) rather than only in a
separate "build" step.

**Stale-file cleanup.** Before writing the new manifest,
`compile_assets/0` reads the OLD one (if any) and remembers every
hashed filename it names. After computing the new manifest it deletes
any old hashed file (and its `.gz`) that is not a value in the new
one — the case where a source file's content changed (old hash orphaned)
or a source file was deleted outright. `public/assets/` therefore
never accumulates garbage across repeated compiles, the way a
`rm -rf public/assets && compile_assets` would achieve destructively,
without the destructive step.

`public/assets/.manifest.json` is loaded once into an in-memory table
(`load_manifest/0`) and can be reloaded on demand; `compile_assets/0`
keeps the table current itself, so nothing needs to call
`load_manifest/0` after compiling in the same process.

### 3. `asset_path/2`: logical name to hashed URL

```prolog
?- asset_path("css/app.css", Path).
Path = "/assets/app-9f12070d41cf.css".

?- asset_path("css/does-not-exist.css", Path).
ERROR: Unknown asset "css/does-not-exist.css"
% error(existence_error(asset, "css/does-not-exist.css"), _)
```

Naming the missing logical path in the thrown error (rather than a
generic "not found") is deliberate: this is a load-time-ish
programmer error (a typo'd path, or an asset that was never added
under `assets/`), and the message should say exactly what string to
go looking for.

### 4. Serving: `get "/assets/:file"`, whitelist, gzip, immutable cache

```prolog
:- route(get, "/assets/:file", serve_asset).
```

`serve_asset/2` is an ordinary env-relation handler (adr/0017). Its
whitelist is **the manifest's values, and only the manifest's
values** — a requested `:file` that is not itself a hashed filename
currently in the manifest is refused (404) before the filesystem is
even consulted:

```prolog
serve_asset(Env0, Env) :-
    File = Env0.params.file,
    (   manifest_entry(_, File)
    ->  ... serve it ...
    ;   not_found(Env0, Env)
    ).
```

This is what makes `/assets/:file` safe despite taking an arbitrary
path segment from the client: there is no path-traversal question to
even ask, because `File` is checked against a closed, framework-
controlled set of strings, never opened as `assets/<whatever the
client sent>`.

**Content-Type** comes from the extension (`.css`, `.js`, `.svg`,
`.png`, `.woff2`, ... — `application/octet-stream` for anything
unlisted, so an unrecognised-but-legitimate asset still serves).

**Cache-Control is `public, max-age=31536000, immutable`** — one year,
and a promise never to revalidate. This is the entire point of
content-hashing the filename: `/assets/app-9f12070d41cf.css` can, by
construction, only ever mean the exact bytes it means right now — the
day `app.css`'s content changes, `compile_assets/0` produces a NEW
URL (a new hash), and every template that calls
`asset_path("css/app.css", _)` starts pointing at it. The old URL is
simply never reused, so there is nothing to invalidate and no cache-
busting query string needed. Compare this to the old
`/static/style.css` route: identical bytes could be requested under
that URL forever, so it could never be marked immutable without
risking a stale stylesheet stuck in some browser's cache after a
deploy.

**Gzip negotiation.** When the request's `accept-encoding` header
contains `gzip` and a `.gz` sibling exists for the resolved file,
`serve_asset/2` serves the compressed bytes instead, with
`content-encoding: gzip` and `vary: accept-encoding` (so an
intermediate cache never hands the compressed bytes to a client that
didn't ask for them, or vice versa):

```
$ curl -sD - http://localhost:8090/assets/app-9f12070d41cf.css -o /dev/null
HTTP/1.1 200 OK
content-type: text/css; charset=utf-8
cache-control: public, max-age=31536000, immutable

$ curl -sD - -H 'Accept-Encoding: gzip' \
    http://localhost:8090/assets/app-9f12070d41cf.css -o /dev/null
HTTP/1.1 200 OK
content-type: text/css; charset=utf-8
cache-control: public, max-age=31536000, immutable
content-encoding: gzip
vary: accept-encoding
```

**Binary safety.** Both plain and gzip-compressed bytes are read with
`read_file_to_string/3` and `encoding(iso_latin_1)` — a lossless
byte-to-code-point mapping (unlike `utf8`, which would try to
interpret arbitrary binary as UTF-8 and can even reject it). The
result is handed to the response as `raw_bytes(Binary)`, a small
addition to `px_env:write_response/2` alongside px_template's existing
`raw/1`:

```prolog
(   Body = raw_bytes(Binary)
->  set_stream(Stream, encoding(octet)),
    write(Stream, Binary)
;   px_template:render(Stream, Body)
),
```

This matters because the response `IOSTREAM` defaults to UTF-8
encoding (`c/http_stream_swi.c`): writing an `iso_latin_1` string
containing byte values above 127 to a UTF-8-encoded stream would
re-encode each of those codes into a multi-byte UTF-8 sequence,
corrupting gzip's compressed bytes (or a PNG's, or a woff2 font's) on
the wire. Switching the stream to `octet` encoding first — safe here
because adr/0012's transport is one request per connection, closed
right after — makes the write byte-for-byte instead. Verified by
round-tripping a `.gz` file through `serve_asset/2` and gunzipping the
served bytes back to the original source (test/milestone16_assets.pl
and the E2E check in section 6 below both do this).

### 5. Template helpers

Three `px_template:render_helper/2` registrations (adr/0019's
extension hook):

```prolog
stylesheet_tag("css/app.css")
%% => <link rel="stylesheet" href="/assets/app-9f12070d41cf.css">

image_tag("img/logo.png", [class(logo)])
%% => <img src="/assets/logo-....png" class="logo">

\javascript_importmap_tags
%% => <script type="importmap">{"imports": {...}}</script>
%%    <script type="module">import "app";</script>
```

`javascript_importmap_tags` is called with the `\Goal` escape because
it is zero-arity: adr/0019's dispatch treats a bare ATOM in body
position as a text node (only compound terms resolve against
`tmpl/2`/`render_helper/2`) — `\Goal` is precisely the door adr/0019
built for a helper call shaped like this one.

It renders two script tags:

1. An **import map** — one entry per compiled JS asset, keyed by its
   bare module name (the logical name under `assets/js/`, minus the
   `.js` extension: `"js/turbo.js"` → `"turbo"`, a hypothetical
   `"js/components/foo.js"` → `"components/foo"`), valued by its
   hashed `/assets/...` URL:

   ```html
   <script type="importmap">{"imports": {"app": "/assets/app-....js", "turbo": "/assets/turbo-....js"}}</script>
   ```

2. A **module entrypoint** — `<script type="module">import "app";</script>`
   — emitted only when `assets/js/app.js` exists (and therefore
   `"js/app.js"` is in the manifest). An app with no `app.js` gets
   only the import map, e.g. for pages that import a bare module
   directly in an inline `<script type="module">`.

This is the mechanism that lets `assets/js/app.js` write

```js
import "turbo";
```

with **zero build step**: the browser's native module loader resolves
the bare specifier `"turbo"` through the import map to
`/assets/turbo-ec1e72f6f2d2.js`, exactly the way importmap-rails wires
`@hotwired/turbo` into a Rails 8 app.

The layout template (`apps/adr_site.pl`) now reads:

```prolog
layout(Title, Content) ~>
    [ raw("<!DOCTYPE html>\n"),
      html(
        [ head(
            [ meta(charset("utf-8")),
              title(Title),
              stylesheet_tag("css/app.css"),
              \javascript_importmap_tags
            ]),
          body(div(class(page), Content))
        ])
    ].
```

replacing the two hand-written `link(...)`/`script(...)` tags and the
`static_css`/`static_js` routes and handlers, which are deleted.

### 6. UMD vs. ESM: the Turbo file had to be re-vendored

adr/0024 vendored `dist/turbo.es2017-umd.js` — a
[UMD](https://github.com/umdjs/umd) bundle with no `export` statement,
because it was loaded with a plain `<script src="...">` tag. An import
map only helps `import` statements; `import "turbo"` requires the
target file to actually BE an ES module. The UMD build cannot be
imported (there is nothing to import — it attaches a global instead),
so it was swapped for the **ESM build**,
`dist/turbo.es2017-esm.js`, fetched once from the pinned release and
committed exactly like the UMD file was (adr/0003's vendoring
discipline: a reviewable diff of one file, no network at build or run
time going forward):

```
curl -sL https://unpkg.com/@hotwired/turbo@8.0.13/dist/turbo.es2017-esm.js \
    -o assets/js/turbo.js
```

The file's header comment records the swap:

```
/*!
 * @hotwired/turbo 8.0.13 (dist/turbo.es2017-esm.js)
 * Vendored per adr/0024, ESM build swapped in per adr/0025: ...
 */
```

Same version (8.0.13), same MIT-licensed content, different build
target — the only change importmap-rails' model requires.

### 7. `prologex_run/0` integration

```prolog
prologex_run :-
    load_app_config,
    ensure_pipeline,
    px_assets:compile_assets,
    app_port(Port),
    ...
```

`compile_assets/0` runs once at process start, before the workers bind
their listening sockets — cheap (a handful of files, sha256 and gzip
over kilobytes) and idempotent (section 2), so there is no reason to
make it a separate deploy step the way Rails' `assets:precompile` is.
A `systemctl --user restart prologex.service` recompiles assets as
part of every restart, same as it re-reads `config/app.pl`.

## Consequences

- `apps/static/` is gone; `assets/{css,js,img}/` is the only place
  static source files live, and `public/assets/` (gitignored,
  regenerated by every `compile_assets/0`) is the only place compiled,
  served copies live.
- Every asset URL an app template emits is content-hashed and
  cacheable forever, with no cache-invalidation mechanism needed
  because there is nothing to invalidate.
- Adding a JS module is: drop a file under `assets/js/`, `import` it
  by its bare logical name (module name = path minus `.js`) from
  `assets/js/app.js` or another already-importable module — no build
  step, no `package.json`, no bundler config.
- `px_env:write_response/2` gained one new case, `raw_bytes/1`,
  alongside the existing `raw/1` — a second escape door, this one for
  genuinely binary bodies. It is additive: every existing template and
  handler that never produces a `raw_bytes(_)` body is unaffected.
- The next asset-heavy feature (adr/0026's component library, landing
  in parallel) rides the same pipeline for free: any CSS or JS it adds
  under `assets/` is picked up by `compile_assets/0`'s directory walk
  with no changes to this module.
