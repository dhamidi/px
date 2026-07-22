# 0018. Router v2: resources and path helpers

Status: Accepted

## Context

The v1 router (adr/0009, `prolog/router.pl`) got the hard part right:
route path templates are parsed once, at registration time, by a DCG
into a list of segment terms (`[posts, param(id)]`); matching an
incoming path against a template is plain unification; and because
`match_path/3` is written as a genuine relation — no cuts, no
mode-assuming built-ins — the same clauses run both directions.
`match_route/4` decomposes a concrete path into params; `path_for/3`
generates a concrete path from a route name and params. One relation,
two calling modes, no second code path to keep in sync.

What v1 lacks is a pleasant surface. Registering a route means calling
`add_route/4` imperatively with an explicitly module-qualified handler:

```prolog
:- initialization(add_route(adr_show, get, "/adr/:id", adr_browser:show_adr)).
```

Seven such calls per resource, by hand, with hand-invented route names.
And nothing generates paths in app code: `path_for/3` exists, but the
demo app writes `"/adr/1"` string literals anyway, because calling
`path_for(adr_show, [id=Id], P)` inline in a `format/3` template is
clumsier than the string.

The north star (adr/0016) fixes the surface and binds this ADR to it:

- Rule 3 — declarations are directives: `:- route(...)`,
  `:- resources(...)`; lookups are relations that run both ways.
- Rule 4 — terms are the DSL: routes are Prolog terms compiled by the
  framework, and `post_path(Id)` is a *term* app code writes where a
  path is expected, never a string literal.
- Rule 7 — no module ceremony: directives capture the defining module
  at expansion time; app code never writes `mymodule:handler`.

The worked example in adr/0016 uses exactly this surface:

```prolog
:- route(get, "/", home_page).
:- resources(posts).
```

and, inside templates and redirects:

```prolog
\link_to(Post.title, post_path(Post.id))
turbo_or_redirect(Env0, post_path(Id), [...], Env)
```

This ADR specifies how that surface works and how it lowers onto the
unchanged v1 engine.

## Decision

### The v1 core is kept, unchanged

Everything adr/0009 decided stands:

- Templates are parsed **once**, by the DCG `path_template//1`, into
  segment terms (`atom` literals and `param(Name)`), at registration
  time — never per request.
- Matching is plain unification via `match_path/3`, which remains one
  cut-free relation reviewed and tested in both calling modes.
- Routes are stored as `route/4` facts with pre-parsed segments.
- `path_for(Name, Params, Path)` remains the reverse-routing entry
  point, and `add_route/4` remains the low-level registration API.

Router v2 is a **term-expansion layer on top of this engine**. The
directives below are sugar that expands into `add_route/4` calls and
ordinary generated predicates. There is no second matcher, no second
path builder, no new route store.

### 1. The `route/3` directive

```prolog
:- route(get, "/", home_page).
:- route(get, "/about", about_page).
```

`Handler` is an **unqualified** predicate name. Per north-star rule 7,
the expansion — not the author — supplies the module, by asking the
load context which module is currently being compiled. The route name
is the handler atom, so `path_for(home_page, [], P)` works with no
extra naming step.

Expansion sketch (simplified; lives in `library(prologex)`):

```prolog
user:term_expansion((:- route(Method, Path, Handler)), Expansion) :-
    prolog_load_context(module, M),          % rule 7: capture, don't ask
    Expansion =
      [ (:- initialization(
              router:register_route(Handler, Method, Path, M:Handler),
              now))
      ].

% register_route/4 = check + add_route/4, nothing more:
register_route(Name, Method, Path, M:Handler) :-
    check_handler(M, Handler),               % see "Load-time checking"
    add_route(Name, Method, Path, M:Handler).
```

The directive is rewritten at compile time; the actual registration is
one `add_route/4` call, exactly as in v1. A reader who prints the
expansion sees the v1 API — the sugar is transparent.

Handlers follow adr/0017's convention: `home_page(Env0, Env)`, a
relation between environment dicts. The router stores and looks up the
goal; it does not care about the convention beyond arity 2.

### 2. The `resources/1` and `resources/2` directives

```prolog
:- resources(posts).
```

expands to the seven REST routes, exactly as Rails defines them:

| # | Method      | Path              | Handler   | Route name          |
|---|-------------|-------------------|-----------|---------------------|
| 1 | GET         | `/posts`          | `index`   | `posts_index`       |
| 2 | GET         | `/posts/new`      | `new`     | `posts_new`         |
| 3 | POST        | `/posts`          | `create`  | `posts_create`      |
| 4 | GET         | `/posts/:id`      | `show`    | `posts_show`        |
| 5 | GET         | `/posts/:id/edit` | `edit`    | `posts_edit`        |
| 6 | PATCH / PUT | `/posts/:id`      | `update`  | `posts_update`      |
| 7 | DELETE      | `/posts/:id`      | `destroy` | `posts_destroy`     |

Ordering note carried over from Rails: `/posts/new` is registered
before `/posts/:id`, so a request for `/posts/new` reaches `new`, not
`show` with `id=new`. Registration order is the table order.

Handlers are predicates named `index/2`, `show/2`, `new/2`, `create/2`,
`edit/2`, `update/2`, `destroy/2` **in the declaring module** — the
module captured at expansion time, same as `route/3`. No qualification,
no registration boilerplate: declaring `:- resources(posts)` and
defining `show(Env0, Env)` in the same file is the whole job.

Row 6 registers two `route/4` facts (one for `patch`, one for `put`),
both dispatching to `update/2`. The canonical route name
`posts_update` belongs to the PATCH fact; the PUT fact is registered
under the alias `posts_update_put` so both facts have distinct names,
but reverse routing (`path_for`, the helpers, `form_for`) always uses
the canonical name. Rails does the same thing for the same reason.

`only` and `except` options select a subset of the seven:

```prolog
:- resources(posts, [only([index, show, create])]).
:- resources(comments, [except([destroy])]).
```

`only(List)` keeps exactly the listed actions; `except(List)` keeps
the other actions. Giving both, or naming an action outside the seven,
is a load-time error. Helpers (below) are only generated for actions
that survive the filter — `only([index])` generates `posts_path/1` and
nothing else, so a stray `edit_post_path(Id)` in a template fails at
helper-resolution time rather than generating a dead link.

Expansion sketch:

```prolog
user:term_expansion((:- resources(Res)), Expansion) :-
    user:term_expansion((:- resources(Res, [])), Expansion).
user:term_expansion((:- resources(Res, Opts)), Expansion) :-
    prolog_load_context(module, M),
    selected_actions(Opts, Actions),          % apply only/except to the 7
    phrase(resource_expansion(Res, M, Actions), Expansion).
```

where `resource_expansion//3` emits, per action, the
`register_route/4` initialization (lowering to `add_route/4`, as in
`route/3`) plus the helper clauses of the next section.

#### Naming convention

The convention is deliberately dumb and fully mechanical. Given the
declared resource name — a **plural** atom, `posts`:

- The plural atom names the URL prefix (`/posts`), the route-name
  prefix (`posts_index`, `posts_show`, ...), and by convention the
  database table the query builder addresses (adr/0021), so
  `q(posts, ...)` and `:- resources(posts)` speak the same name.
- The **singular** is derived by stripping a trailing `s`:
  `posts` → `post`. That is the entire inflection engine. For
  irregular nouns where stripping `s` is wrong (`people`, `status`),
  the `singular(Atom)` option states it explicitly —
  `:- resources(people, [singular(person)])` — rather than the
  framework growing an English pluralization table.
- The member parameter is always `:id`, surfacing in handlers as
  `Env.params.id` (adr/0017).
- Collection-level helpers use the plural (`posts_path`); member-level
  helpers use the singular (`post_path`, `edit_post_path`); the two
  page-form helpers prefix the singular with the action
  (`new_post_path`, `edit_post_path`).

### 3. Path helpers are generated as real predicates

The `resources` expansion emits ordinary clauses into the declaring
module — not a lookup table consulted by a meta-interpreter, but
predicates you can call, trace, and list. For `:- resources(posts)`:

```prolog
posts_path(P)         :- path_for(posts_index, [],      P).
post_path(Id, P)      :- path_for(posts_show,  [id=Id], P).
new_post_path(P)      :- path_for(posts_new,   [],      P).
edit_post_path(Id, P) :- path_for(posts_edit,  [id=Id], P).
```

Each helper is a thin veneer over `path_for/3`; the segment terms
stored in `route/4` remain the single source of truth for what the
path looks like. Change the route, and every helper follows, because
there is nothing in the helper to update.

```prolog
?- post_path(7, P).
P = "/posts/7".
```

The expansion also records each generated helper in a framework-level
table:

```prolog
%  path_helper(Functor, Arity, Module)   -- Arity is the TERM arity,
%                                           i.e. helper arity minus 1
path_helper(posts_path,     0, blog).
path_helper(post_path,      1, blog).
path_helper(new_post_path,  0, blog).
path_helper(edit_post_path, 1, blog).
```

This table exists for one reason: **the term form**. In templates
(adr/0019) and in `redirect/3` / `turbo_or_redirect/4` (adr/0017),
wherever the framework expects a path, app code writes the helper as a
term and the framework evaluates it. From the north star:

```prolog
post_card(Post) ~>
    article(class(card),
      [ h2(\link_to(Post.title, post_path(Post.id))),
        p(Post.summary)
      ]).

create(Env0, Env) :-
    ...,
    turbo_or_redirect(Env0, post_path(Id), [...], Env).
```

The evaluation rule: **a term whose functor and arity match a
registered helper (functor `F`, term arity `N`, helper `F/N+1`) is
called with one extra, final output argument**, in the module the
table records. Concretely, when the template renderer or the redirect
machinery reaches `post_path(7)`, it finds `path_helper(post_path, 1,
blog)`, calls `blog:post_path(7, Path)`, and uses the resulting
`"/posts/7"`. A zero-argument helper is written as a bare atom —
`\link_to("New post", new_post_path)` and `\form_for(post_form,
posts_path, ...)` in the north star both rely on this: the atom
`new_post_path` is functor/0, matched against helper
`new_post_path/1`.

A term that does *not* match a registered helper is not a path
expression, and passing one where a path is expected is an error at
render/redirect time — there is no fallback to "stringify the term".
Path string literals in app code are exactly what this rule retires.

`route/3` routes participate too: `:- route(get, "/", home_page)` is
addressable as `path_for(home_page, [], P)`; the general directive
does not generate a named helper predicate (only `resources` does),
but the term-evaluation table gains nothing from it either — for
non-resource routes, templates use `path_for/3` through a helper the
app defines itself if it wants one, and that helper is just Prolog.

### 4. Reversibility is still the payoff — and still one relation

Nothing in this ADR touches `match_path/3`. The helpers and the term
form are veneer; underneath, one route fact and one relation serve
both directions. With `:- resources(posts)` loaded in module `blog`,
the fact behind rows 4–7's path is:

```prolog
route(posts_show, get, [posts, param(id)], blog:show).
```

Forward — a request comes in, the router decomposes it:

```prolog
?- match_route(get, "/posts/7", Handler, Params).
Handler = blog:show,
Params = [id='7'].
```

Reverse — the same fact, the same `match_path/3` clauses, with
`PathSegments` unbound instead of `Params`:

```prolog
?- path_for(posts_show, [id=7], Path).
Path = "/posts/7".

?- post_path(7, Path).          % the generated veneer over the above
Path = "/posts/7".
```

The round-trip property from adr/0009 — `match_route` then `path_for`
with the extracted params reproduces the original path — now holds for
every route a `resources` directive emits, and stays covered by the
same style of test. The discipline adr/0009 imposes (no cuts, no
mode-assuming built-ins anywhere on the match path, both modes
reviewed) is inherited verbatim; the expansion layer adds no code to
the match path at all.

### 5. Method override

HTML forms can only submit GET and POST, but rows 6 and 7 of the
resource table need PATCH/PUT and DELETE. Rails' convention is
adopted: a form POSTs with a hidden `_method` field, and the framework
treats the request as the named method.

```html
<form method="post" action="/posts/7">
  <input type="hidden" name="_method" value="patch">
  ...
</form>
```

(`\form_for(...)` — adr/0023 — emits the hidden field automatically
when the target route's method is not GET or POST; hand-written forms
may include it themselves.)

The override is applied by router middleware, in the standard
middleware fold (adr/0010, restated as env-relations in adr/0017),
**before** route matching — on the request's worker, like all
middleware (adr/0005). The rule:

- Only a **POST** request may be overridden. `_method` on a GET, or on
  anything else, is ignored.
- Only `patch`, `put`, and `delete` are legal override targets. Any
  other value is ignored — a form cannot smuggle itself into being a
  GET, and cannot invent methods.
- The middleware rewrites `Env.method` (and preserves the original
  under `Env.request.raw_method` for logging); `match_route/4` then
  runs against the overridden method and never knows the difference.

Sketch:

```prolog
method_override(Env0, Env) :-
    (   Env0.method == post,
        Override = Env0.form_params.get('_method'),
        memberchk(Override, [patch, put, delete])
    ->  Env = Env0.put(method, Override)
                  .put(request/raw_method, post)
    ;   Env = Env0
    ).
```

### Out of scope: nested and scoped routes

Rails also offers `resources :posts do resources :comments end`
(nested member paths like `/posts/:post_id/comments/:id`) and
`scope "/admin" do ... end` / `namespace`. These are **explicitly not
specified here**. The v1 engine can already express such paths — a
template like `/posts/:post_id/comments/:id` is just more segment
terms — but the directive syntax, helper-naming scheme
(`post_comment_path/3`?), and param-naming rules for nesting deserve
their own decision rather than a half-specified appendix to this one.
Until that ADR exists, nested paths are declared with plain `route/3`
directives, which lose nothing except the generated helpers.

### Load-time checking

The expansion of both directives emits a check alongside each
registration: the handler predicate must exist, with arity 2, in the
declaring module.

```prolog
check_handler(M, Handler) :-
    (   current_predicate(M:Handler/2)
    ->  true
    ;   print_message(error, prologex(missing_handler(M, Handler/2))),
        throw(error(existence_error(handler, M:Handler/2), _))
    ).
```

The check runs via `initialization/2` after the declaring file is
loaded (so directive-before-definition source order is fine), and a
failure **aborts the load**. A typo'd action name or a forgotten
`destroy/2` is a load-time error naming the module and predicate — not
a 500 discovered by the first user to click Delete. For `resources`,
each action that survives `only`/`except` filtering is checked;
filtered-out actions are not required to exist, which is the other
half of what `only([...])` is for.

Similarly checked at expansion time: helper-name collisions. If
`resources(posts)` would generate `post_path/2` and that predicate (or
another resource's helper of the same name) already exists in the
module, the expansion raises a load-time error instead of silently
adding clauses to it.

## Consequences

**Directives are sugar, not a new engine.** `add_route/4` with an
explicit module-qualified handler survives as the low-level API — it
is precisely what both directives expand into, it remains the right
tool for programmatic registration (tests, generated routes), and
`match_path/3`, `path_for/3`, `route/4`, and the DCG are untouched.
What dies is its use *in application code*: the v1 style of
`:- initialization(add_route(...))` with hand-qualified handlers and
hand-invented route names is retired along with the four-argument
handler convention (adr/0016), and path string literals in app code
are retired in favor of helper terms. The demo app's routing is
rewritten to `route/3` + `resources/1` as part of the adr/0016 proof.

**Handlers must exist in the declaring module, checked at load time.**
This is a real constraint: you cannot declare `:- resources(posts)` in
one module and define `show/2` in another (that would be module
ceremony returning through the back door), and you cannot ship a route
whose handler is missing. The payoff is that the error surface moves
from request time to load time, with a message naming the exact
predicate to define.

**The action names are common words.** `resources` claims `index/2`,
`show/2`, `new/2`, `create/2`, `edit/2`, `update/2`, `destroy/2` in
the declaring module. Two `resources` directives therefore cannot
share a module — each resource lives in its own module, which is the
Rails one-controller-per-resource shape anyway and costs nothing under
rule 7, since no module name is ever written at a call site.

**The reversibility discipline now protects more surface.** Every
helper and every term-form path in a template bottoms out in
`match_path/3` running backwards. A cut or one-directional built-in
introduced into the match path no longer just breaks `path_for/3` —
it breaks every link and redirect in every app. adr/0009's review rule
(a cut or mode-assuming built-in in `router.pl`'s match path is a
defect unless justified) stays in force and extends to the generated
helper bodies, which is easy because they contain nothing but a
`path_for/3` call.

**Still no parameter typing.** As in v1, `param(id)` unifies with any
segment; `post_path(7)` and `post_path(banana)` both produce paths.
Constraint options on routes (the reserved options term in `route/4`)
remain the natural future home for this; nothing in this ADR spends
that budget.
