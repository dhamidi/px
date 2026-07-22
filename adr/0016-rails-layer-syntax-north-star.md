# 0016. The Rails layer: one syntax to rule the framework

Status: Accepted

## Context

Version 1 of prologex proved the transport stack (adr/0001 through
adr/0015). But the application-facing code it produced is spaghetti:
handlers take four positional arguments (`Request, Stream, PathParams,
QueryParams`), every callback must be manually module-qualified, HTML is
built with `format/3` string templates, paths are string literals, and
responses are hand-assembled status lines. It works; it is not pleasant.

The next iteration adds the 80% of Ruby on Rails that makes it
productive: a richer reversible router, streaming templates, a
Rack-style environment, SQLite with a Sequel-style query builder,
config management, modeled forms, and Hotwire/Turbo support. Before any
of that is built, this ADR fixes the *syntax* — every subsequent ADR
(0017–0024) must conform to the shapes established here. The goal is
"Rails-like elegance, but in Prolog": lean on unification, dicts,
nondeterminism, and term rewriting — never imitate Ruby's object
syntax with Prolog's.

## Decision: seven rules

1. **One env, threaded relationally.** Every handler and middleware is
   a relation `Goal(Env0, Env)` between an environment dict before and
   after. No positional argument soup, no hidden globals. (adr/0017)
2. **Exactly one new operator.** `~>` ("renders as") defines templates.
   Everything else is plain terms, directives, and predicates. A reader
   who knows standard Prolog can read a prologex app after learning one
   operator.
3. **Declarations are directives; lookups are relations.** Routes,
   forms, and config are declared with `:- route(...)`,
   `:- resources(...)`, `:- form(...)`, plain `config/2` facts — and
   queried with ordinary predicates that run forwards and backwards
   where that is meaningful (paths, queries).
4. **Terms are the DSL; DCG/term-rewriting compiles them.** SQL, HTML,
   and routes are Prolog terms compiled by the framework — never
   strings concatenated by user code.
5. **Bytes stream; terms may nest.** Template rendering writes to the
   response stream as it walks the term — element open-tags are on the
   wire before their children are computed. No output byte buffer,
   ever (adr/0007's rule, now extended to HTML and SQLite rows).
6. **Nondeterminism is iteration.** A database row is a solution:
   `row(DB, Query, Row)` yields rows on backtracking, streamed from
   sqlite's `step`, not collected into a list first. (adr/0020, 0021)
7. **No new module ceremony.** Directives capture the defining module
   at expansion time, so app code never writes `mymodule:handler`
   again.

## The worked example

A minimal blog exercising every subsystem. This is the target; the
per-subsystem ADRs specify how each piece works internally.

```prolog
:- use_module(library(prologex)).

%% config/app.pl (loaded automatically; adr/0022)
% config(port, 8090).
% config(database, "blog.db").
% config(production, database, "/var/lib/blog.db").   % env overlay

%% Routes (adr/0018).  resources/1 expands to the seven REST routes
%% and defines path helpers: posts_path/1, post_path/2, new_post_path/1, ...
:- route(get, "/", home_page).
:- resources(posts).

%% Handlers: Env0 -> Env relations (adr/0017)
home_page(Env0, Env) :-
    respond(Env0, home, Env).

index(Env0, Env) :-
    findall(P, row(q(posts, [order_by(desc(created_at))]), P), Posts),
    respond(Env0, post_index(Posts), Env).

show(Env0, Env) :-
    Id = Env0.params.id,
    once(row(q(posts, [where(id == Id)]), Post)),
    respond(Env0, post_show(Post), Env).

create(Env0, Env) :-
    form_result(post_form, Env0, Result),
    (   Result = ok(Values)
    ->  insert(posts, Values, Id),
        turbo_or_redirect(Env0, post_path(Id),
            [ prepend(posts, post_card(Values.put(id, Id))) ], Env)
    ;   Result = invalid(Values, Errors)
    ->  respond(Env0, post_form_view(Values, Errors),
                [status(422)], Env)
    ).

%% Templates (adr/0019): the one operator.  Body is a term; rendering
%% streams it — no HTML string ever exists in memory.
post_index(Posts) ~>
    layout("Posts",
      [ h1("All posts"),
        div(id(posts), each(Posts, post_card)),
        link_to("New post", new_post_path)
      ]).

post_card(Post) ~>
    article(class(card),
      [ h2(link_to(Post.title, post_path(Post.id))),
        p(Post.summary)
      ]).

post_show(Post) ~>
    layout(Post.title,
      turbo_frame(post(Post.id),
        [ h1(Post.title),
          markdown(Post.body)           % v1 markdown engine, reused
        ])).

%% Forms (adr/0023): declared once, validated and re-rendered from
%% the same declaration.
:- form(post_form,
     [ field(title, text,     [required, max_length(120)]),
       field(body,  textarea, [required])
     ]).

post_form_view(Values, Errors) ~>
    form_for(post_form, posts_path, Values, Errors).

%% Query builder (adr/0021): a query is a term; row/2 streams
%% solutions; sql/3 shows its compilation.
%%
%% ?- sql(q(posts, [where(author == "d"), limit(3)]), SQL, Params).
%% SQL = "SELECT * FROM posts WHERE author = ? LIMIT ?",
%% Params = ["d", 3].

:- initialization(prologex_run).
```

Things deliberately absent from the example: module qualification of
any handler or template, `format/3`, hand-written status lines, path
string literals (only `post_path(Id)` terms), and any variable named
`Stream` in app code.

## Syntax inventory

- `Goal(Env0, Env)` — handlers and middleware (adr/0017)
- `:- route(Method, Path, Handler)`, `:- resources(Name)`,
  `name_path(...)` helpers, reversible (adr/0018)
- `Head ~> Body` — templates; bare compound terms in a body resolve
  element-first, then template, then helper (`\Goal` remains as an
  explicit escape); plain strings auto-escape (adr/0019)
- `q(Table, Clauses)`, `row/2`–`row/3`, `insert/3`, `update/3`,
  `sql/3` (adr/0020, adr/0021)
- `config(Key, Value)` facts + `config/2` lookup with environment
  overlays (adr/0022)
- `:- form(Name, Fields)`, `form_result/3`, `form_for(...)`
  (adr/0023)
- `turbo_frame(Id, Content)`, `turbo_or_redirect/4`, stream actions
  `append/prepend/replace/remove` (adr/0024)

## Consequences

Every ADR from 0017 to 0024 is bound by this document; where a
subsystem ADR needs syntax not shown here, it must extend these shapes
(terms, directives, env-relations), not invent parallel ones. The v1
modules (`router.pl`, `middleware.pl`, `response.pl`, `app.pl`) will be
reworked to this surface; the transport core (worker model, llhttp,
IOSTREAMs) is untouched. The demo ADR-browser app gets rewritten in
this style as the proof, and the old four-argument handler convention
is retired.
