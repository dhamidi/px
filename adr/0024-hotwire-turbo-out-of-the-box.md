# 0024. Hotwire Turbo out of the box

Status: Accepted

## Context

adr/0016 promised "the 80% of Rails that makes it productive", and one
of the largest pieces of that 80% is not on the server at all:
[Hotwire Turbo](https://turbo.hotwired.dev/), the Rails-blessed way to
get single-page-application feel without writing client-side
JavaScript. Turbo is three techniques layered on one small JS library:

- **Turbo Drive** intercepts link clicks and form submissions, fetches
  the new page over `fetch`, and swaps the `<body>` (merging the
  `<head>`) in place. Navigation stops feeling like full page loads;
  the server keeps serving ordinary full HTML pages.
- **Turbo Frames** decompose a page into `<turbo-frame id="...">`
  regions. A link or form inside a frame only replaces that frame:
  Turbo sends the request with a `Turbo-Frame` header, and on the
  response it extracts the matching frame and discards the rest.
  Frames can also be lazy — an empty frame with a `src` attribute is
  fetched automatically when it becomes visible.
- **Turbo Streams** are server-sent DOM mutations: a response with
  MIME type `text/vnd.turbo-stream.html` containing one or more
  `<turbo-stream action="..." target="...">` elements, each carrying a
  `<template>` of HTML. Turbo applies each action — `append`,
  `prepend`, `replace`, `update`, `remove`, `before`, `after` — to the
  element with the matching DOM id. A form submission can thus update
  three parts of a page in one response, no redirect and no client
  code.

The crucial property, and the reason Turbo fits this framework so
well, is that the server's job barely changes. Turbo consumes ordinary
HTML, keyed by ordinary status codes and headers. What it rewards is
exactly the discipline the surrounding ADRs already impose: correct
303 redirects after POST (adr/0017's `redirect/3`, adr/0023), honest
422s for invalid forms (adr/0023), responses that are terms until the
edge renders them (adr/0017), and templates that stream (adr/0019,
adr/0007).

adr/0016's worked example already uses `turbo_frame/2` and
`turbo_or_redirect/4` as if they existed. This ADR is where they are
specified.

## Decision

Turbo support ships in four pieces: Drive by default, frames as a
template term plus a pruning middleware, a stream responder, and the
`turbo_or_redirect/4` content-negotiation helper. Everything below
conforms to adr/0016's shapes: env-relations, terms compiled by the
framework, and adr/0019's template surface (`~>`, element terms, bare
template/helper calls) — this ADR adds vocabulary to that surface, it
does not extend the syntax.

### 1. Turbo Drive for free

The Turbo JavaScript is vendored, not fetched. Following adr/0003's
philosophy — a point-in-time snapshot committed to the repository, no
package manager and no network at build or run time — the compiled
`@hotwired/turbo` distribution file is copied into
`apps/static/turbo.js` at a pinned version. The vendored file carries a
header comment recording exactly what it is:

```js
/*!
 * @hotwired/turbo 8.0.13 (dist/turbo.es2017-umd.js)
 * Vendored per adr/0024; snapshot, never edited in place.
 * Upgrade = replace this file from a newer tagged release and
 * update this header. https://turbo.hotwired.dev/
 */
```

No CDN dependency: a prologex app is fully functional on a machine
with no outbound network, and a Turbo upgrade is a reviewable diff of
one file, exactly like re-vendoring llhttp.

The framework's default `layout` template includes it, in outline:

```prolog
layout(Title, Body) ~>
    html(
      [ head(
          [ title(Title),
            stylesheet(app),
            script([src("/static/turbo.js"), defer], [])
          ]),
        body(Body)
      ]).
```

That is the entire integration for Turbo Drive. Because every page in
every prologex app renders through `layout`, every app is
Drive-enabled out of the box: link clicks and form submissions become
`fetch` + body-swap, and navigation gets the SPA feel with zero
app-side JavaScript. The server needs nothing special beyond what
adr/0017 and adr/0023 already mandate — in particular, `redirect/3`
emits **303 See Other**, which is what makes redirect-after-POST
behave under Drive (the follow-up request is a GET, not a replayed
POST). Apps that want to opt a link out (`data-turbo="false"`) or
disable Drive entirely simply say so in their own templates; the
framework imposes nothing beyond the script tag.

### 2. Frames are a template term

`turbo_frame(IdTerm, Content)` is a helper on adr/0019's template
surface, called bare like any other template or helper. It renders a
`<turbo-frame>` element whose DOM id is the serialization of
`IdTerm`.

**Frame-id serialization rule.** DOM ids are strings; prologex ids are
terms, because terms are the DSL (adr/0016 rule 4). The rule:

- an atom serializes as itself: `posts` → `posts`;
- a compound serializes as its functor name, then `'_'`, then its
  arguments each serialized by the same rule, joined with `'_'`:
  `post(7)` → `post_7`, `comment(7, 3)` → `comment_7_3`,
  `comment(post(7), 3)` → `comment_post_7_3`;
- numbers and strings serialize as their canonical text.

The rule is deterministic and total over the terms handlers actually
build (route-helper-style compounds over atomics); it makes no claim
of reversibility — nothing ever parses a DOM id back into a term. The
same rule is used everywhere an element id is denoted by a term: frame
ids here, and stream-action targets in the next section, so
`turbo_frame(post(7), ...)` in one template and `replace(post(7), ...)`
in a stream action are guaranteed to name the same element.

The north star's `post_show` uses it directly:

```prolog
post_show(Post) ~>
    layout(Post.title,
      turbo_frame(post(Post.id),
        [ h1(Post.title),
          markdown(Post.body)
        ])).
```

which renders (for post 7) as:

```html
<turbo-frame id="post_7">
  <h1>...</h1>
  ...
</turbo-frame>
```

**Frame requests: the handler does not know.** When Turbo navigates
within a frame it sends a `Turbo-Frame: post_7` request header and
expects a response containing that frame. Rails answers this with
per-controller layout switching; prologex answers it with a
middleware, and this is the composition payoff adr/0017 promised when
it said a middleware could "strip [the body] back down to a bare
`turbo_frame` for a Turbo request".

Because `response.body` is still a term when the pipeline's last steps
see it, a `turbo_frames` middleware — sitting after `apply_layout` in
the pipeline —

```prolog
:- pipeline([request_logger, session, router,
             apply_layout, turbo_frames]).
```

does, in outline:

```prolog
turbo_frames(Env0, Env) :-
    memberchk("turbo-frame"-FrameId, Env0.headers),
    Body0 = Env0.response.body,
    frame_subtree(Body0, FrameId, Frame),    % find matching subtree
    Env = Env0.put(response/body, Frame)
             .put(response/headers,
                  ["vary"-"Turbo-Frame" | Env0.response.headers]).
```

`frame_subtree/3` walks the body term looking for a
`turbo_frame(IdTerm, _)` whose serialized `IdTerm` equals the header
value, and the whole response body is replaced by that subtree. No
matching header, or no matching frame? The middleware fails, i.e.
declines (adr/0017), the full page goes out unchanged, and Turbo
itself deals with a missing frame client-side. The `Vary: Turbo-Frame`
header keeps any HTTP cache from serving a pruned response to a
full-page request.

The consequence worth stating twice: **handler code is identical for
full-page and frame requests.** The `show` handler from adr/0016 —

```prolog
show(Env0, Env) :-
    Id = Env0.params.id,
    once(row(q(posts, [where(id == Id)]), Post)),
    respond(Env0, view(post_show(Post)), Env).
```

— serves both. A direct visit to `/posts/7` renders the full
`layout(...)` page. A click on the same link from inside a
`turbo_frame(post(7), ...)` elsewhere sends `Turbo-Frame: post_7`; the
same handler runs, builds the same term, and the middleware prunes the
term to the frame before a single byte is rendered. Zero re-rendering,
zero buffering, zero branches in application code. In v1 (bytes
written by the handler) this middleware was structurally impossible;
here it is a term walk and a dict put. This middleware is the
strongest concrete argument for adr/0017's body-as-term design.

**Lazy frames.** A frame whose content should load on demand is
declared with a `src/1` term instead of content:

```prolog
dashboard ~>
    layout("Dashboard",
      [ h1("Dashboard"),
        turbo_frame(recent_comments, src(comments_path))
      ]).
```

rendering as:

```html
<turbo-frame id="recent_comments" src="/comments" loading="lazy"></turbo-frame>
```

`src(PathTerm)` takes a route-helper term (adr/0018), never a path
string — the reversible router evaluates it, same as `redirect/3`.
Turbo fetches the frame when it scrolls into view; the handler behind
`comments_path` is, again, a perfectly ordinary handler whose response
happens to contain a `turbo_frame(recent_comments, ...)` — which the
`turbo_frames` middleware will duly prune for it.

### 3. Turbo Streams: a responder and an action vocabulary

`turbo_stream(Env0, Actions, Env)` is a responder helper alongside
adr/0017's `respond/3` and `redirect/3` — a pure dict put like the
others, no I/O. It sets the response's content type to
`text/vnd.turbo-stream.html` and its body to a term the edge knows how
to render:

```prolog
turbo_stream(Env0, Actions, Env) :-
    respond(Env0, turbo_stream(Actions),
            [ header("content-type", "text/vnd.turbo-stream.html") ],
            Env).
```

`Actions` is a list drawn from a closed vocabulary mirroring Turbo's
seven actions. In every case `TargetId` is a term serialized by the
frame-id rule of section 2, and `Template` is any adr/0019 template
term:

| Action term                  | Turbo action | Effect on `target`                 |
|------------------------------|--------------|------------------------------------|
| `append(TargetId, Template)` | `append`     | insert as last child               |
| `prepend(TargetId, Template)`| `prepend`    | insert as first child              |
| `replace(TargetId, Template)`| `replace`    | replace the element itself         |
| `update(TargetId, Template)` | `update`     | replace the element's children     |
| `remove(TargetId)`           | `remove`     | remove the element                 |
| `before(TargetId, Template)` | `before`     | insert before the element          |
| `after(TargetId, Template)`  | `after`      | insert after the element           |

Rendering happens at the transport edge like every other response
(adr/0017, adr/0019): the body is the term `turbo_stream(Actions)`
until then, and rendering streams. For each action the wrapper's open
tags go on the wire, then the action's template is walked and streamed
exactly as it would be in a page — element open-tags on the wire
before their children are computed, adr/0016 rule 5 — then the
wrapper closes, then the next action begins. There is no per-action
buffer and no whole-response buffer; a stream response with a large
`append` payload starts arriving at the client while the framework is
still walking the template, on adr/0007's chunked response machinery.

The generated markup for one action —
`prepend(posts, post_card(Post))` from the north star's `create` —
is:

```html
<turbo-stream action="prepend" target="posts">
  <template>
    <article class="card">
      <h2><a href="/posts/8">New post title</a></h2>
      <p>Summary...</p>
    </article>
  </template>
</turbo-stream>
```

`remove/1` carries no template and renders an empty element:

```html
<turbo-stream action="remove" target="post_7"></turbo-stream>
```

Note what is being reused: `post_card` is the same template the index
page uses. A stream action is just a targeted delivery of an ordinary
template — there is no separate "partial" concept to learn, because
adr/0019 templates already are partials.

### 4. `turbo_or_redirect/4`: progressive enhancement in one predicate

This is the ergonomic centerpiece, and the reason adr/0016 put it in
the north-star example. When Turbo Drive submits a form it advertises
stream support by including `text/vnd.turbo-stream.html` in the
`Accept` header. A client without JavaScript — or with Turbo disabled,
or a curl script, or a search crawler — does not. One predicate
content-negotiates between them:

```prolog
%!  turbo_or_redirect(+Env0, +PathTerm, +Actions, -Env) is det.
%
%   If the request accepts text/vnd.turbo-stream.html, respond
%   with the Turbo Stream Actions (section 3). Otherwise, 303 to
%   PathTerm (adr/0017's redirect/3). Same handler, both worlds.

turbo_or_redirect(Env0, PathTerm, Actions, Env) :-
    (   accepts_turbo_stream(Env0)
    ->  turbo_stream(Env0, Actions, Env)
    ;   redirect(Env0, PathTerm, Env)
    ).

accepts_turbo_stream(Env) :-
    memberchk("accept"-Accept, Env.headers),
    sub_string(Accept, _, _, _, "text/vnd.turbo-stream.html").
```

Walk through the north star's `create` handler:

```prolog
create(Env0, Env) :-
    form_result(post_form, Env0, Result),
    (   Result = ok(Values)
    ->  insert(posts, Values, Id),
        turbo_or_redirect(Env0, post_path(Id),
            [ prepend(posts, post_card(Values.put(id, Id))) ], Env)
    ;   Result = invalid(Values, Errors)
    ->  respond(Env0, view(post_form_view(Values, Errors)),
                [status(422)], Env)
    ).
```

**JS-on (Turbo submitting the form).** The POST arrives with
`Accept: text/vnd.turbo-stream.html, text/html, ...`. The insert
succeeds; `turbo_or_redirect/4` takes the stream branch and responds
`200` with content type `text/vnd.turbo-stream.html` and the one
`prepend` action of section 3. Turbo receives it and prepends the new
card into `<div id="posts">` — the element the index template declared
as `div(id(posts), each(Posts, post_card))`. The new post appears at
the top of the list without a navigation, and the only bytes that
crossed the wire are the card's own markup.

**JS-off (a bare browser form).** The same POST arrives without the
stream MIME type in `Accept`. The same clause runs, the same insert
happens, and `turbo_or_redirect/4` takes the redirect branch: `303 See
Other` to `post_path(Id)`. The browser GETs `/posts/8` and receives
the full `post_show` page. Classic POST-redirect-GET, fully
functional, no JavaScript required.

One handler, one clause, both behaviors. The application degrades
progressively by construction, and the difference between "SPA-feel"
and "plain HTML" is a single `Accept` header the framework negotiates
on the application's behalf.

### 5. Form errors: the 422 discipline pays off here

The `invalid` branch above does nothing Turbo-specific, and that is
the point. adr/0023 requires invalid form submissions to re-render the
form with **status 422 Unprocessable Content** — not a 200 with an
error page in it. Turbo Drive and Turbo Frames treat a 4xx response to
a form submission as "render this in place of the form" (within the
enclosing frame, if any): the user sees the re-rendered form with
inline errors, their scroll position and surrounding page intact.

So form errors work under Turbo automatically, with nothing extra in
this ADR — no error-handling actions, no special responder. This is
stated explicitly because it is *why* adr/0023's status-code
discipline matters: a framework that let handlers return sloppy 200s
for invalid forms would break silently the moment Turbo was enabled
(Turbo would try to navigate to the "successful" response and error
out). Correct status codes are not pedantry here; they are the
protocol Turbo keys on, exactly as the 303 is for redirects.

### 6. Out of scope, stated honestly

**Turbo Stream broadcast over WebSocket or SSE** — Rails'
`broadcast_append_to`, riding ActionCable — is genuinely valuable:
it is what turns Turbo Streams from "rich form responses" into "live
pages pushed from the server". It is deliberately not in this ADR
because it needs a persistent-connection story on the worker model
first: adr/0005/0006 workers own their connections and run
request-scoped handlers, and a broadcast subscription is a
long-lived, cross-request, cross-worker channel — a real design
problem, not a helper. When it is designed, SSE is the natural first
transport: an SSE response is just a response that never ends,
which adr/0007's chunked streaming responses already express — the
missing piece is pub/sub between workers, not anything at the HTTP
layer. The `turbo_stream(Actions)` term and its renderer are already
transport-neutral, so a future broadcast facility renders the exact
same action terms down a different pipe. Flagged as future work.

**Stimulus**, Hotwire's companion controller library, is not bundled.
Turbo is bundled because the framework itself keys behavior on it
(303s, 422s, frame pruning, stream negotiation); Stimulus is purely
app-side sprinkle-JS with no server contract, so bundling it would be
vendoring for someone else's code. Nothing prevents an app from
dropping `stimulus.js` into its own `apps/static/` and using it —
Turbo and Stimulus are designed to coexist.

## Consequences

The demo ADR-browser app (adr/0016) gets SPA-feel navigation — Drive
swaps, frame-scoped updates, stream-updated lists — with zero
app-side JavaScript: its only client asset is the vendored
`apps/static/turbo.js`, whose header comment records the pinned
upstream version and is the single place to look when auditing or
upgrading it (upgrade by file replacement and diff, per adr/0003's
model).

The `turbo_frames` pruning middleware becomes the strongest concrete
argument for adr/0017's body-as-term design: a feature that is a
per-controller layout mechanism in Rails, and structurally impossible
in prologex v1, falls out here as one declining middleware doing a
term walk — with the handler none the wiser. Any future feature that
wants to reshape responses (fragment caching, content security
policies injected into `head`, AMP-style variants) inherits the same
pattern.

Costs accepted knowingly. First, ~100KB of vendored third-party
JavaScript now ships with every app and must be re-vendored on Turbo's
release cadence, with no local ability to patch it (never edited in
place, same rule as llhttp). Second, the `turbo_frames` middleware
walks the body term on every request that carries a `Turbo-Frame`
header — cheap, since it is structure traversal without rendering,
but not free. Third, `turbo_or_redirect/4`'s `Accept` sniff is a
substring check, not a full content-negotiation parser; that matches
what Turbo actually sends and what Rails actually checks, and a
richer negotiator can replace `accepts_turbo_stream/1` later without
touching any handler. Finally, the action vocabulary is closed —
Turbo's custom-action extension point is not exposed — until a real
app demonstrates the need.
