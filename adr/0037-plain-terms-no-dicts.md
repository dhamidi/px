# 0037. Plain terms everywhere: excise SWI dicts

Status: Accepted

## Context

The framework threads SWI dicts through everything — the env
(`Env.params.id`), the response (`_{status, headers, body}`), the
app model (`m{comments: Cs}`), form values, and query rows
(`Row.title`). Dicts read like Ruby's `post.title`, which is why they
were chosen. But they are a bolt-on to Prolog with real costs the
ergonomics review surfaced:

  - **The `.` is overloaded and time-sensitive.** `Post.title` is
    goal-expanded dict access that works in a template body but
    evaluates differently in a clause head — a genuine
    least-surprise violation people (me included) trip on.
  - **They don't pattern-match.** The whole framework leans on clause
    selection (`article_list([]) ~>` / `article_list(As) ~>`), yet
    the data flowing through it is opaque dicts you must reach into
    rather than destructure.
  - **They print as `_G123{...}`** — useless in an error dump, which
    the development console (a coming feature) needs to read.
  - **They are un-Prolog.** The stated value of this project is to
    lean on Prolog's strengths, not import another language's data
    model. A dict is that import.

Decision: no SWI dict appears anywhere in the framework or in
generated application code. Data is plain Prolog terms, accessed
through relations. Where a shape is fixed, it is a compound; where it
is an open string→value map, it is a list of `Key-Value` pairs.

## Decision 1: the env is opaque, reached only through relations

Internally the env is a list of `Key-Value` pairs (latest wins),
which prints readably in an error dump and pattern-matches. App and
framework code never destructure it directly; they use relations:

    method(Env, Method)             path(Env, Path)
    param(Env, Key, Value)          params(Env, Pairs)     % semidet
    header(Env, Name, Value)        body(Env, Body)
    path_id(Env, Key, Id)           % integer :id, fails on garbage
    current_user(Env, User)         signed_in(Env)         % from px:auth

and is extended immutably by `put_env(Env0, Key, Value, Env)` (what
middleware and the runtime use). This is *more* encapsulated than
dicts: app code stops reaching into `Env.params.id` and asks
`path_id(Env, id, Id)`. The internal representation can change
without touching a line of app code.

Before / after (a controller model clause):

    % before
    model(show, Env, m{article: A, comments: Cs}) :-
        Id = Env.params.id, ...

    % after
    model(show, Env, page(A, Cs)) :-
        path_id(Env, id, Id), ...

## Decision 2: the response and other fixed shapes are compounds

The response is `response(Status, Headers, Body)` (Headers a pairs
list, Body a template term). Form results stay
`ok(Values) / invalid(Values, Errors)` but `Values` is a pairs list
`[title-"Hi", body-"..."]` (typed) and `Errors` is the existing
`error(Field, Msg)` list. `form_for(Form, Action, Values, Errors)`
refills from the pairs list; `field_value(Values, Field, V)` reads
one for app code.

## Decision 3: the app model is whatever term the app chooses

The framework imposes NO model shape — this is the point of the Elm
architecture and where Prolog earns its keep. `model/3` returns any
term; `view/3` pattern-matches it; the pieces the view needs arrive
as named variables, not dict lookups. The scaffold's convention is a
small tagged compound, e.g. `page(Rows, Values, Errors)`, destructured
in the view head:

    view(index, page(Rows, _, _), posts_index(Rows)).

No `M.put(...)`, no `M0`/`M1`/`M` threading through a dict — the
domain fold in the pure model builds the next term by construction:

    update(loaded(Rows), page(_, V, E), page(Rows, V, E)).
    update(rejected(V, E), page(Rows, _, _), page(Rows, V, E)).

## Decision 4: query rows are pairs lists; the model names their parts

This is where dicts were most convenient (`A.title` in a template),
so it gets the most deliberate replacement. `row(q(posts, [...]), Row)`
yields `Row = [id-1, title-"Hi", body-"...", created_at-"..."]`. The
idiom is that the **model destructures the row into named parts**, so
the view receives plain variables and never reaches into a row:

    % model
    model(show, Env, article(Id, Title, Body)) :-
        path_id(Env, id, Id),
        once(row(q(posts, [where(id == Id)]), R)),
        field(R, title, Title),
        field(R, body, Body).

    % view -- all plain variables, zero accessors
    view(show, article(_, Title, Body),
         layout(Title, [ h1(Title), p(Body) ])).

`field(Row, Key, Value)` is the one accessor (deterministic, throws on
a missing column — a typo'd column is loud, not a silent fail). For
the list case, a card template takes the row and pulls what it needs
with `field/3`, or the model pre-projects. Conscious trade: we give
up `A.title`'s brevity inside templates for uniform plain-term data
and pattern matching everywhere — exactly the project's stated value.
`q(Table, Clauses)` may also gain an explicit projection later
(`select([id, title])`) but that is not required by this ADR.

## Decision 5: config, turbo, assets internals

`config/2` is already relation-accessed; only its internal storage (if
any dict) changes. `dom_id`, turbo stream terms, and the asset
manifest convert their internal dicts to pairs/compounds; their
public relations are unchanged.

## Migration

1. Land the new `px_env` term API as the reference (env as pairs +
   the accessor relations + `put_env/4`), keeping the pipeline and
   `handle_request/3` green — this is the keystone; do it carefully,
   not as a sweep.
2. Fan out per-module Sonnet sweeps against the reference: px_router,
   px_controller, px_form, px_query (rows), px_turbo, px_config,
   px_gen_auth, and the px_cli scaffold templates (the generated app
   code must be dict-free too — adr/0032).
3. Migrate the demo app (`app/`) and the blog, then the tests.
4. `field/3` and the row change touch every template that did
   `Row.col`; the scaffold and both demos are the proving grounds.

## Consequences

Every value flowing through the framework prints readably, pattern-
matches, and is uniform — which the development error console
(coming) turns directly into a legible env dump, and which removes
the dict-dot timing gotcha entirely. The cost is real: query rows in
templates lose dot-brevity, and this is a framework-wide rewrite of
the data model touching ~15 files, the scaffold, the generator, both
demos, and the tests. It is sequenced behind hot reload (adr/0036, a
contained win) and ahead of the development console (which consumes
the new plain-term env). The public *relations* an app calls change
very little — `path_id/3`, `respond/3`, `redirect/3`, `row/2`,
`form_for/4` keep their names — so the app-facing churn is mostly
`Env.params.id` → `path_id(Env, id, Id)` and `Row.col` → `field(Row,
col, V)`, both mechanical.
