# 0027. App structure: the Elm Architecture, by convention

Status: Accepted

## Context

The demo app is one 168-line file mixing routes, handlers, templates,
forms, schema, and file-system access. That was fine for proving the
Rails layer; it is not a structure another person could grow an
application in. Rails answers this with MVC plus a fixed directory
layout ("convention over configuration"). But MVC's controller is an
awkward fit here: our handlers are already relations over an env, not
objects with actions, and "controller" adds a name for something that
in Prolog is just glue.

The Elm Architecture (TEA) fits the backend — and Prolog — better:

  - **Model** — a term holding everything one page needs. In Elm it is
    built by `init`; here, by a relation from the request env.
  - **Msg** — every state change is a named data term, not an
    anonymous POST body.
  - **update** — a relation `Msg × Model → Model' × Effects`, with
    effects as *data* interpreted by the runtime (Elm's `Cmd`).
  - **view** — a function from Model to markup, pure: it can see only
    the Model, never the env.

Each HTTP request is one full TEA cycle, stateless: build the model,
(for a message request) update it, render the view or run the
effects. Nothing here fights the framework we have — model/update are
ordinary relations, the view produces an adr/0019 template term, and
effects reuse redirect/turbo/status machinery that already exists.

## Decision 1: the standard directory layout

An application is a directory. `prologex_run/0` (adr/0016) boots
whatever directory it is started in — there is no application "main"
file at all; the layout *is* the wiring:

    app/
      pages/       one TEA page per file (model/update/view + its forms)
      views/       shared templates: layout.pl, partials
      lib/         plain modules: domain relations, no HTTP anywhere
    assets/        css/, js/ — asset-pipeline sources (adr/0025)
    bin/server     boots the app (dev and production, same entry)
    config/
      app.pl       config facts (adr/0022)
    data/          runtime state (the sqlite database lives here)
    public/        compiled, hashed assets (generated; gitignored)
    test/

Boot loads `config/app.pl`, then every module under `app/lib/`,
`app/views/`, `app/pages/` (in that order), mounts `/assets/:file`
itself, compiles assets, and starts the workers. The framework also
registers file-search paths so app code imports read like Elm's
`import Data.Adr`:

```prolog
:- use_module(library(prologex)).   % the facade, from anywhere
:- use_module(lib(adrs)).           % app/lib/adrs.pl
```

There is no `config/routes.pl`. Routes belong to the pages that serve
them (Decision 2); `:- route/3` and `:- resources/1,2` (adr/0018)
remain available anywhere for things that are not pages.

## Decision 2: a page is a module implementing TEA

`app/pages/<name>.pl` declares the path it owns; the module name is
the page name:

```prolog
:- module(guestbook, []).
:- use_module(library(prologex)).

:- page("/comments").
```

`:- page(Path)` expands (like route/resources, adr/0018) into:

  - a GET route running the page's *model → view* cycle,
  - POST/PATCH/PUT/DELETE routes running *model → update → effects*,
  - a reversible path helper named after the page — `guestbook_path`,
    or with the path's parameters in order: `:- page("/adr/:id")` in
    `adr.pl` gives `adr_path(Id)` — usable in every template and
    redirect exactly like a resources helper,
  - end-of-load checks that `model/2` and `view/2` exist.

The page contract, all ordinary module predicates (so two pages never
collide, unlike global template names):

```prolog
%% model(+Env, -Model) — Elm's init. Build everything the page needs
%% from the request. FAILURE IS 404: an unknown :id simply fails here.
model(_Env, m{comments: Comments, values: _{}, errors: []}) :-
    findall(C, row(q(comments, [order_by(desc(id))]), C), Comments).

%% view(+Model, -Html) — pure: Model in, template term out. It never
%% sees the env. Html is an ordinary adr/0019 term, so it composes
%% with layout, partials, px_ui components, turbo_frame — everything.
view(M, layout("Guestbook",
  [ h1("Guestbook"),
    turbo_frame(comments, each(M.comments, comment_card)),
    form_for(sign, guestbook_path, M.values, M.errors)
  ])).

%% update(+Msg, +Model0, -Model, -Effects) — only pages that accept
%% messages define it. Effects are data (Elm's Cmd), interpreted by
%% the runtime after update succeeds.
update(sign(ok(V)), M, M,
       [ redirect(guestbook_path),
         turbo([prepend(comments, comment_card(C))]) ]) :-
    insert(comments, V, Id),
    once(row(q(comments, [where(id == Id)]), C)).
update(sign(invalid(V, E)), M0, M, [status(422)]) :-
    M = M0.put(_{values: V, errors: E}).

%% Page-local partials use ~> as always (template names are global;
%% the convention is to prefix anything generic with the page name).
comment_card(C) ~>
    article(class(card),
      [ p(strong(C.author)), p(C.body), p(small(C.created_at)) ]).
```

A read-only page is just the first two:

```prolog
:- module(adr, []).
:- use_module(library(prologex)).
:- use_module(lib(adrs)).

:- page("/adr/:id").

model(Env, m{slug: Slug, markdown: Md}) :-
    Slug = Env.params.id,
    adr_markdown(Slug, Md).        % unknown slug -> fail -> 404

view(M, layout(M.slug,
  [ p(class(back), link_to("← all decisions", home_path)),
    markdown(M.markdown)
  ])).
```

## Decision 3: messages

Every non-GET request to a page is a message. The default decoder is
conventional:

  - The params' `_msg` field names the message. `form_for/4` emits it
    automatically as a hidden input (the form's name *is* the message
    name); a page with exactly one declared form needs no `_msg` at
    all.
  - If the named message matches a `:- form(Name, Fields)` declared
    in the page module, the params are validated (adr/0023) and the
    message is `Name(ok(Values))` or `Name(invalid(Values, Errors))`
    — validation happens *before* update, so update clauses pattern-
    match on the outcome, as in the guestbook above.
  - A message with no form arrives as `Name(Params)`.

A page needing something richer defines its own decoder and the
default stands aside entirely:

```prolog
%% msg(+Env, -Msg) — Elm's decoder, when convention isn't enough.
msg(Env, archive(Id)) :-
    get_dict(archive, Env.params, Id0), atom_string(Id, Id0).
```

No decodable message, or no matching update clause: 404, same as a
failing model.

## Decision 4: effects

`update/4`'s last argument is a list of effect terms — the response
side of Elm's `Cmd`, interpreted by the runtime in one place:

    redirect(PathTerm)   303 to a resolved path term (adr/0018).
    turbo(Streams)       with redirect: turbo_or_redirect/4 semantics
                         (adr/0024) — stream actions for Turbo
                         requests, the redirect for plain ones.
    status(Code)         no redirect: render view(Model) with Code
                         (422 re-render is `[status(422)]`).
    []                   render view(Model), 200.

Database writes are *not* effect terms: `insert/3` and friends are
already relations (adr/0021) and update calls them directly. On a
server, the response is the Cmd; pretending the database is one would
add ceremony with no purity to show for it.

## Decision 5: layouts are a convention, with a framework default

`app/views/layout.pl` conventionally defines the `layout(Title,
Content)` template every page and px_ui's own demo pages render
through. When no app layout exists after boot, the framework installs
its default: a mobile-first document shell — charset, **a viewport
meta tag**, title, one `stylesheet_tag` per top-level stylesheet in
the asset manifest, and the importmap tags. An app that defines
`layout ~>` owns the document from the first byte; one that doesn't
still gets a page that renders correctly on a phone.

## Consequences

`apps/adr_site.pl` is deleted and the demo app becomes the reference
layout: three content pages (`home`, `adr`, `guestbook`), two px_ui
wrappers (`ui`, `ui_show` — each a two-line model/view over the
framework's demo registry), one shared `views/layout.pl`, one
`lib/adrs.pl`. Nothing in the transport or Rails layers changes;
`:- page` lowers onto the same route store as everything else, and a
TEA page and a raw `:- route` handler can coexist in one app. The
px_ui facade module is now loaded by `library(prologex)` itself — the
component library is framework surface, not app code. What a page may
do is narrower than a raw handler (no direct respond/redirect) — that
narrowness is the point; the escape hatch is simply to write a route.
