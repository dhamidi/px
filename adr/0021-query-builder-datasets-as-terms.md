# 0021. Query builder: datasets as terms

Status: Accepted

## Context

The north star (adr/0016, rule 4) commands: "Terms are the DSL;
DCG/term-rewriting compiles them. SQL, HTML, and routes are Prolog
terms compiled by the framework — never strings concatenated by user
code." Its worked example already uses the query syntax this ADR must
deliver:

```prolog
index(Env0, Env) :-
    findall(P, row(q(posts, [order_by(desc(created_at))]), P), Posts),
    respond(Env0, view(post_index(Posts)), Env).

show(Env0, Env) :-
    Id = Env0.params.id,
    once(row(q(posts, [where(id == Id)]), Post)),
    respond(Env0, view(post_show(Post)), Env).
```

That is the contract. This ADR specifies the term language behind it,
how it composes, how it compiles, and how it executes on top of the
SQLite connection layer (adr/0020: one connection per worker,
`db_row/4` streaming rows from `sqlite3_step`).

The design inspiration is Sequel, Jeremy Evans' Ruby database toolkit.
Sequel's central idea is the *dataset*: an immutable value representing
an SQL query, built up by chaining methods that each return a new
dataset, and compiled to SQL only when results are demanded:

```ruby
DB[:posts].where(author: 'd').order(:created_at).limit(5)
```

No objects standing in for rows, no identity map, no lazy-loaded
association graph — a dataset is a description of a query, and
descriptions compose. That idea translates to Prolog better than to
Ruby, because Prolog's native data structure *is* the description: a
term. Where Sequel needs frozen objects and careful API discipline to
make datasets behave like values, in Prolog a query that is a term is
a value by construction. Composition is list manipulation, compilation
is a DCG (the pattern v1's router proved, adr/0009), and execution is
nondeterminism (adr/0016, rule 6: "a database row is a solution").

## Decision

### A dataset is a term: `q(Table, Clauses)`

A dataset is the term `q(Table, Clauses)` where `Table` is an atom and
`Clauses` is a list of clause terms. The clause vocabulary:

- `select(Fields)` — `Fields` is a list of field references (or a
  single field reference). Default when absent: `*`.
- `where(Expr)` — a condition in the expression language below.
  `where(List)` means the conjunction of the list's elements
  (Sequel's hash-argument behavior). Multiple `where/1` clauses in
  one dataset are ANDed together.
- `join(Table2, on(F1 == F2))` — inner join.
- `left_join(Table2, on(F1 == F2))` — left outer join.
- `group_by(Field)` or `group_by([Field, ...])`.
- `order_by(Field)`, `order_by(desc(Field))`, `order_by(asc(Field))`,
  or `order_by([...])` mixing the above.
- `limit(N)`.
- `offset(N)`.

The clause list is order-independent wherever SQL allows: the compiler
always emits the canonical SQL clause order (`SELECT` … `FROM` …
joins … `WHERE` … `GROUP BY` … `ORDER BY` … `LIMIT` … `OFFSET`)
regardless of where clauses sit in the list. Order matters only where
SQL itself is ordered: multiple joins keep their relative list order,
and so do sort keys within and across `order_by` clauses. These three
datasets compile identically:

```prolog
q(posts, [where(published == true), order_by(desc(created_at)), limit(10)])
q(posts, [limit(10), order_by(desc(created_at)), where(published == true)])
q(posts, [order_by(desc(created_at)), where(published == true), limit(10)])
```

A *field reference* is an atom (`title`) or `Table/Field`
(`posts/title`, compiled to `posts.title`). Qualified references are
how join conditions and joined-table columns are written; `.` is not
used because SWI-Prolog reserves functional dot-notation for dicts.

### The expression language

Conditions inside `where/1` and `on/1` are built from:

- `F == V`, `F \== V` — equality, inequality (`=` / `<>`)
- `F < V`, `F > V`, `F =< V`, `F >= V` — comparisons (`=<` compiles
  to SQL `<=`)
- `like(F, Pattern)` — `F LIKE ?`, the pattern bound as a parameter
- `in(F, List)` — `F IN (?, ?, …)`, one parameter per element; the
  empty list compiles to the always-false condition `1 = 0` (SQLite
  rejects `IN ()`), exactly as Sequel does
- `is_null(F)` — `F IS NULL`
- `and(E1, E2)`, `or(E1, E2)` — parenthesized conjunction and
  disjunction
- `[E1, E2, …]` — a list of expressions means their conjunction, so
  `where([a == 1, b > 2])` is `where(and(a == 1, b > 2))`

The left side of each operator is a field reference; the right side is
a value — or, inside `on/1`, another field reference, which is what
distinguishes a join condition (`posts/author_id == users/id`) from a
filter. In a join's `on/1`, both sides compile as identifiers; in
`where/1`, `==` against a field reference on the right is written
`F1 == field(F2)` to keep the value position unambiguous.

Values may be integers, floats, strings, and atoms (bound as text;
the booleans `true`/`false` bind as `1`/`0` per adr/0020's binding
rules).

### SQL injection posture

Stated explicitly, because this is the load-bearing property:

1. **Values are never interpolated into SQL text. Ever.** Every value
   position — comparison operands, `like` patterns, every element of
   an `in` list, every `limit`/`offset` count, every column value in
   `insert` and `update` — compiles to a `?` placeholder and travels
   in the parameter list, bound via `sqlite3_bind_*` (adr/0020).
   There is no code path in the compiler that converts a value to SQL
   text.
2. **Identifiers are whitelisted at compile time.** Table names,
   field names, and both parts of a `Table/Field` reference must be
   atoms matching `[a-z][a-zA-Z0-9_]*`. `sql/3` throws
   (`type_error(identifier, X)` for a non-atom,
   `domain_error(sql_identifier, X)` for an atom outside the
   pattern) before any SQL text exists. There is no quoted-identifier
   support and no way to smuggle arbitrary text into an identifier
   position — an identifier that needs quoting is, by this decision,
   not a supported identifier.

The consequence: the SQL string produced by `sql/3` is composed
exclusively of compiler-owned keywords, whitelisted identifiers, and
`?` placeholders. No user-supplied string can reach the SQL text
through the dataset language, including strings that arrived in an
HTTP request five milliseconds ago.

### Composition is list manipulation

Because a dataset is data, composing queries is consing and appending
— the Prolog analog of Sequel's method chaining, where every chained
call returns a new frozen dataset. A reusable scope is a relation
between datasets:

```prolog
%% published(+Q0, -Q): narrow any posts dataset to published rows.
published(q(posts, C0), q(posts, [where(published == true)|C0])).

%% by_author(+Author, +Q0, -Q)
by_author(Author, q(T, C0), q(T, [where(author == Author)|C0])).

%% paginate(+Q0, +Page, +PerPage, -Q)
paginate(q(T, C0), Page, PerPage, q(T, C)) :-
    Offset is (Page - 1) * PerPage,
    append(C0, [limit(PerPage), offset(Offset)], C).
```

Scopes chain the way any relations chain:

```prolog
recent_by(Author, Page, Q) :-
    published(q(posts, [order_by(desc(created_at))]), Q0),
    by_author(Author, Q0, Q1),
    paginate(Q1, Page, 20, Q).
```

All of this is pure: no database, no connection, no side effects.
Query construction is unit-testable with nothing but `plunit`:

```prolog
:- begin_tests(dataset_composition).

test(published_prepends_where) :-
    published(q(posts, [limit(3)]), Q),
    Q == q(posts, [where(published == true), limit(3)]).

test(paginate_page_2) :-
    paginate(q(posts, []), 2, 20, Q),
    Q == q(posts, [limit(20), offset(20)]).

:- end_tests(dataset_composition).
```

This is Sequel's deepest lesson applied: keep query *description*
separate from query *execution*, and the description layer needs no
database to be correct.

### Compilation is a DCG: `sql(Q, SQL, Params)`

`sql/3` compiles a dataset to an SQL string plus a parameter list, via
a DCG over code lists:

```prolog
sql(Q, SQL, Params) :-
    phrase(query(Q, Params), Codes),
    string_codes(SQL, Codes).
```

The compiler is deterministic (exactly one solution, no choice
points), pure (no side effects, no connection needed), and total over
valid datasets (invalid ones throw before emitting text, per the
whitelist above). This is the same shape as v1's router DCG
(adr/0009): a term language compiled by `phrase/2`, testable in
complete isolation from the I/O it ultimately drives.

Worked compilations — these are executable specifications, and the
test suite asserts them verbatim:

```prolog
?- sql(q(posts, [where(author == "d"), limit(3)]), SQL, Params).
SQL = "SELECT * FROM posts WHERE author = ? LIMIT ?",
Params = ["d", 3].

?- sql(q(posts, [ where([published == true, in(status, [live, featured])]),
                  order_by([desc(created_at), title]) ]),
       SQL, Params).
SQL = "SELECT * FROM posts WHERE published = ? AND status IN (?, ?) ORDER BY created_at DESC, title",
Params = [true, live, featured].

?- sql(q(posts, [ join(users, on(posts/author_id == users/id)),
                  where(users/name == "d"),
                  select([posts/title, users/name]) ]),
       SQL, Params).
SQL = "SELECT posts.title, users.name FROM posts INNER JOIN users ON posts.author_id = users.id WHERE users.name = ?",
Params = ["d"].

?- sql(q(comments, [ select([post_id, count(id)]),
                     where(\+ is_null(approved_at)),
                     group_by(post_id) ]),
       SQL, Params).
SQL = "SELECT post_id, count(id) FROM comments WHERE approved_at IS NOT NULL GROUP BY post_id",
Params = [].
```

(Two details visible above, decided here: `limit`/`offset` counts are
bound parameters like every other value — adr/0016's inline example
already listed `3` in `Params`, and its SQL comment showing a literal
`LIMIT 3` is corrected by this ADR to `LIMIT ?`. And `\+ Expr` is
negation, used for `IS NOT NULL` and `NOT IN` via `\+ is_null(F)` and
`\+ in(F, L)`. Aggregate calls in `select` are limited to `count/1`,
`sum/1`, `avg/1`, `min/1`, `max/1` over field references.)

### Execution streams: `row/2`, `row/3`, and the write predicates

Execution follows adr/0016 rule 6 — nondeterminism is iteration — and
sits directly on adr/0020's `db_row/4`, which streams one solution per
`sqlite3_step` without ever collecting a result list:

- `row(Q, Row)` — compiles `Q` with `sql/3` and streams rows on the
  current worker's implicit connection (adr/0020: one connection per
  worker thread, so no pool, no checkout, no argument to thread).
- `row(DB, Q, Row)` — the explicit-connection form, for scripts,
  tests, and tools running outside a worker.

`Row` is a dict tagged with the primary table name, keys are the
selected columns: `posts{id: 7, title: "Hello", ...}` — so templates
and handlers read `Row.title` with ordinary dict access. One solution
per row; backtracking steps the statement; `findall/3` collects when
a list is genuinely wanted; `once/1` takes the first row:

```prolog
index(Env0, Env) :-
    findall(P, row(q(posts, [order_by(desc(created_at))]), P), Posts),
    respond(Env0, view(post_index(Posts)), Env).

show(Env0, Env) :-
    Id = Env0.params.id,
    once(row(q(posts, [where(id == Id)]), Post)),
    respond(Env0, view(post_show(Post)), Env).
```

Writes are three predicates, all built on the same compile-then-bind
path, all values bound as `?` parameters, dict keys validated as
identifiers:

- `insert(Table, Dict, Id)` — `INSERT INTO Table (k1, k2, …) VALUES
  (?, ?, …)`; `Id` unifies with `last_insert_rowid()`.
- `update(Table, Dict, WhereExpr)` — `UPDATE Table SET k1 = ?, … WHERE
  …`; `WhereExpr` is the same expression language as `where/1`.
- `delete(Table, WhereExpr)` — `DELETE FROM Table WHERE …`.

The north star's `create` handler, unchanged, showing `insert/3` in
context:

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

For the query the vocabulary cannot express, the escape hatch is a raw
`sql(Text, Params)` term accepted anywhere a dataset is:

```prolog
row(sql("SELECT p.*, count(c.id) AS n_comments
         FROM posts p LEFT JOIN comments c ON c.post_id = p.id
         GROUP BY p.id HAVING n_comments > ?", [5]),
    Row)
```

Hand-written SQL text, but the parameters are still `?`-bound — the
escape hatch relaxes the vocabulary, never the injection posture.

### What this is not

This is a query builder, in Sequel's sense of the word — Sequel bills
itself as "the database toolkit for Ruby", and this layer is the
database toolkit for prologex. It is deliberately **not**:

- **Not an ORM.** No model classes, no objects. Rows are dicts;
  behavior lives in ordinary predicates that take dicts.
- **No identity map.** Two queries returning the same row return two
  dicts. Terms have value semantics; caching is the application's
  business if it has one.
- **No associations.** `post.comments` machinery is replaced by what
  it always secretly was: a join or a second query. Write the
  relation: `comment_of(Post, C) :- row(q(comments, [where(post_id ==
  Post.id)]), C).`
- **No lazy-loading magic.** `q/2` terms are inert data until handed
  to `row/2`; nothing executes behind your back, and nothing N+1s
  behind your back either.
- **No schema migrations.** Future work, noted honestly: a migration
  story (plausibly `:- migration(...)` directives compiled the same
  way) is deferred to a later ADR and nothing here depends on it.

The reasoning follows Sequel's: the valuable part of a database layer
is a composable, injection-safe query description language and a
predictable execution surface — not an object graph pretending the
database is memory. And Prolog needs an ORM even less than Ruby does.
What an ORM fakes with proxies and reflection — mapping records to a
richer structure, navigating relationships, querying by example —
Prolog does natively: pattern matching destructures a row in a clause
head, a "model method" is a predicate over a dict, and a
"relationship" is literally a relation. `row/2` makes a database table
behave like a Prolog predicate: one fact per solution, on
backtracking. Wrapping that in objects would be a downgrade.

## Consequences

Application code contains zero SQL strings in the normal path. Every
query in the north-star example is a term; the only SQL text in an
application is inside an explicit `sql(Text, Params)` escape-hatch
term, greppable and reviewable as the exception it is. `sql/3` remains
available at the toplevel as the inspection surface — paste any
dataset in and read the SQL it would run, an affordance Sequel users
know as `dataset.sql`.

Query construction and compilation are pure and testable without a
database. Scope predicates are tested with `==` on terms; the
compiler is tested with `sql/3` assertions like the worked examples
above; only `row/2` and the write predicates need a database, and
adr/0020's explicit-connection `row/3` lets those tests run on a
throwaway in-memory SQLite handle.

The injection posture is structural, not disciplinary: values cannot
reach SQL text because no compiler code path puts them there, and
identifiers cannot carry payloads because non-whitelisted atoms throw
at compile time. The cost is a closed vocabulary — no quoted
identifiers, no arbitrary SQL functions, no subqueries in v1. That is
accepted: the escape hatch covers the long tail, and extending the
clause/expression vocabulary is additive (new clause terms, new
expression functors) without breaking existing datasets.

The compiler inherits adr/0009's discipline: it must stay a pure,
deterministic DCG, and review treats side effects or extra choice
points in `sql/3` as defects. Multiple joins and sort keys are the
only order-sensitive parts of the clause list, and that is documented
behavior, not an accident.

Finally, flagged honestly as future work, not promised: because a
dataset is a term and adr/0009 proved that one relation can run both
directions, `q/2` is a candidate *reversibility surface*. A
`row(Q, Row)` called with `Row` bound and the row absent could, in
principle, generate the insert that would make the query true — the
database as an assertable predicate. Nothing in this ADR builds that,
and nothing here should be read as claiming SQL execution is cleanly
invertible (aggregates, joins, and deletes are not). But the design
keeps the door open by making the query a term rather than a string,
and a future ADR can walk through it or decline to.
