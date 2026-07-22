# 0020. SQLite: vendored amalgamation, strict 1:1 bindings, rows as solutions

Status: Accepted

## Context

The Rails layer needs a database. adr/0016 already committed to SQLite
with a Sequel-style query builder (adr/0021), and bound this ADR to two
of its rules in particular:

- Rule 4: **terms are the DSL** — SQL strings are compiled by the
  framework, never concatenated by user code.
- Rule 6: **nondeterminism is iteration** — "a database row is a
  solution: rows yield on backtracking, streamed from sqlite's `step`,
  not collected into a list first."

This ADR specifies everything below the query builder: how SQLite's C
sources get into the tree, what the C binding layer looks like, and the
core Prolog predicate — `db_row/4` — that turns SQLite's stepping
cursor into Prolog backtracking. adr/0021 sits entirely on top of the
surface defined here.

Three earlier decisions are not merely precedents but templates this
ADR follows exactly:

- **adr/0003** established how third-party C enters this repository:
  vendor the upstream amalgamation, never edit it, upgrade by
  re-vendoring. SQLite is the single most amalgamation-friendly project
  in existence — the two-file `sqlite3.c`/`sqlite3.h` bundle from
  sqlite.org is the officially recommended way to consume it.
- **adr/0002** established that FFI files are dumb, literal, 1:1
  wrappers; all ergonomics live in `prolog/`. The nondeterministic
  `db_row/4` is precisely the kind of ergonomics that rule keeps out of
  C: the C layer exposes `step` as a boring deterministic call, and
  Prolog turns stepping into backtracking.
- **adr/0014 and adr/0015** taught, twice and the hard way, what
  happens when a C-side pointer's lifetime is left to SWI-Prolog's atom
  garbage collector: a use-after-free that sequential testing cannot
  find and 10,000 concurrent connections finds reliably. The final fix
  there — pin every handle blob at creation, release the pin only on
  confirmed close — is applied to every SQLite blob *from day one* in
  this ADR, not retrofitted after the next segfault.

Finally, adr/0005's worker model shapes ownership: a worker is one OS
thread with one uv loop and one Prolog engine, shared-nothing. Database
connections follow the same shape — one connection per worker, never
shared.

## Decision

### 1. Vendor the official amalgamation into `vendor/sqlite3/`

SQLite's maintainers publish a single-file amalgamation
(`sqlite3.c` plus `sqlite3.h`) on sqlite.org for every release; it is
their recommended distribution form and compiles anywhere a C compiler
exists. Vendor exactly those two files:

```
vendor/sqlite3/
    sqlite3.c      # the amalgamation, ~9 MB of generated C
    sqlite3.h
    VERSION        # one line: the upstream release, e.g. "3.50.2"
```

The same rules as `vendor/llhttp/` (adr/0003) apply verbatim:

- These files are **third-party and never edited in place**. All
  SWI-Prolog glue lives in `c/sqlite3_swi.c`. Re-vendoring stays a
  clean file replacement, never a merge.
- The snapshot is point-in-time, not a submodule or a build-time
  fetch. Upgrading means downloading a newer amalgamation from
  sqlite.org, replacing the files, updating `VERSION`, and diffing.
- Unlike llhttp there is no `LICENSE-MIT` to carry: SQLite is
  **public domain** (its source header says so explicitly), so no
  license file is vendored. The `VERSION` file exists precisely
  because there is no other project-level record of which snapshot we
  took — the `SQLITE_VERSION` macro inside the vendored header is the
  authoritative cross-check.

### 2. Strict 1:1 C layer: `c/sqlite3_swi.c` + `prolog/sqlite3_swi.pl`

Per adr/0002, `c/sqlite3_swi.c` is a third dumb FFI file alongside
`llhttp_swi.c` and `uv_swi.c`: every exported predicate is one
underlying SQLite C call, no policy, no ergonomics. It gets the same
dedicated loader module as libuv (`prolog/uv_swi.pl`'s pattern), so
foreign predicates land in a known module with an explicit export list
regardless of load order:

```prolog
:- module(sqlite3_swi,
          [ sqlite3_open/2,             % sqlite3_open_v2
            sqlite3_close/1,            % sqlite3_close
            sqlite3_prepare/3,          % sqlite3_prepare_v2
            sqlite3_bind/3,             % sqlite3_bind_{int64,double,text,null}
            sqlite3_step/2,             % sqlite3_step
            sqlite3_column/3,           % sqlite3_column_type + accessor
            sqlite3_column_count/2,     % sqlite3_column_count
            sqlite3_column_name/3,      % sqlite3_column_name
            sqlite3_finalize/1,         % sqlite3_finalize
            sqlite3_reset/1,            % sqlite3_reset
            sqlite3_last_insert_rowid/2,% sqlite3_last_insert_rowid
            sqlite3_changes/2,          % sqlite3_changes
            sqlite3_errmsg/2            % sqlite3_errmsg
          ]).

/** <module> Loader for c/sqlite3_swi.so, the 1:1 SQLite FFI (adr/0002, adr/0020). */

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../c/sqlite3_swi'], LibBase),
   use_foreign_library(LibBase).
```

#### The predicates

| Predicate | Underlying C call | Notes |
|---|---|---|
| `sqlite3_open(+File, -DB)` | `sqlite3_open_v2` | `File` a string/atom path (`":memory:"` works); `DB` a blob. |
| `sqlite3_close(+DB)` | `sqlite3_close` | Fails with an exception if statements are still live — a bug we want loud. |
| `sqlite3_prepare(+DB, +SQL, -Stmt)` | `sqlite3_prepare_v2` | `SQL` a string; `Stmt` a blob. One statement per call; trailing SQL is an error. |
| `sqlite3_bind(+Stmt, +Index, +Value)` | one of `sqlite3_bind_int64` / `_double` / `_text` / `_null` | 1-based index, matching SQLite. Type dispatch below. |
| `sqlite3_step(+Stmt, -Result)` | `sqlite3_step` | Unifies `Result` with the atom `row` or `done`. Every other return code throws. |
| `sqlite3_column(+Stmt, +Index, -Value)` | `sqlite3_column_type` + matching accessor | 0-based index, matching SQLite. Type mapping below. |
| `sqlite3_column_count(+Stmt, -N)` | `sqlite3_column_count` | |
| `sqlite3_column_name(+Stmt, +Index, -Name)` | `sqlite3_column_name` | `Name` an atom; needed so rows can be dicts keyed by column name. |
| `sqlite3_finalize(+Stmt)` | `sqlite3_finalize` | Releases the statement blob's pin (below). |
| `sqlite3_reset(+Stmt)` | `sqlite3_reset` | Re-run a prepared statement without re-preparing. |
| `sqlite3_last_insert_rowid(+DB, -Id)` | `sqlite3_last_insert_rowid` | |
| `sqlite3_changes(+DB, -N)` | `sqlite3_changes` | |
| `sqlite3_errmsg(+DB, -Msg)` | `sqlite3_errmsg` | Rarely called from Prolog directly; the C layer calls it when throwing. |

Two entries deserve an honest note against adr/0002's "one C call"
rule. `sqlite3_bind/3` and `sqlite3_column/3` each make a type
decision (which bind function; `column_type` then the matching
accessor). This is exactly the carve-out adr/0002 already grants:
"no data-structure translation *beyond what is strictly required to
cross the FFI boundary*". Prolog terms are dynamically typed and
SQLite's bind/column API is type-split; a minimal type dispatch at the
boundary is the crossing itself, not smuggled policy. Nothing else in
the file branches.

#### Type mapping

Binding (Prolog value → SQLite):

| Prolog | SQLite bind |
|---|---|
| integer | `sqlite3_bind_int64` |
| float | `sqlite3_bind_double` |
| string | `sqlite3_bind_text` (UTF-8, `SQLITE_TRANSIENT`) |
| atom (other than `null`) | `sqlite3_bind_text` (UTF-8, `SQLITE_TRANSIENT`) |
| the atom `null` | `sqlite3_bind_null` |
| anything else | `type_error` exception |

Columns (SQLite → Prolog value):

| SQLite column type | Prolog |
|---|---|
| `SQLITE_INTEGER` | integer (`sqlite3_column_int64`) |
| `SQLITE_FLOAT` | float (`sqlite3_column_double`) |
| `SQLITE_TEXT` | string (UTF-8) |
| `SQLITE_NULL` | the atom `null` |
| `SQLITE_BLOB` | string of the raw bytes (`sqlite3_column_blob` + `_bytes`) |

The mapping deliberately round-trips: what you bind as an integer you
read back as an integer; `null` is a real atom you can match on, never
a magic string. Binding blobs is not supported in v1 — nothing in the
Rails layer needs it yet, and adding a bind case later is one more arm
in the existing dispatch.

#### Errors are exceptions carrying `errmsg`

Any SQLite return code other than `SQLITE_OK` / `SQLITE_ROW` /
`SQLITE_DONE` becomes a Prolog exception thrown from C, carrying the
numeric code and the human message fetched via `sqlite3_errmsg` at the
moment of failure:

```prolog
?- sqlite3_prepare(DB, "SELEC * FROM posts", Stmt).
ERROR: sqlite3 error 1: near "SELEC": syntax error
```

thrown as the ISO-shaped term:

```prolog
error(sqlite3_error(Code, Errmsg), context(sqlite3_prepare/3, _))
```

No SQLite failure is ever a silent Prolog failure at the 1:1 layer;
plain failure is reserved for genuine logical "no" (which only
`db_row/4`, below, produces — at end of results).

#### Blob lifetime: the adr/0014/0015 lesson, applied from day one

`DB` and `Stmt` are SWI-Prolog blobs wrapping `sqlite3*` and
`sqlite3_stmt*`, the same wrapping pattern as `uv_swi.c`'s handles.
adr/0015 proved that leaving a blob's lifetime to atom-GC is a
use-after-free waiting for enough GC pressure: the collector may
reclaim the blob — and run its `release` hook over live C state — at
any moment the term happens to be unreferenced from Prolog. For SQLite
the orderings are nastier still, because statements hold interior
pointers into their connection: atom-GC choosing to reclaim a `DB`
blob before its `Stmt` blobs would tear down state the statements
still point at.

So every blob is pinned at creation and unpinned only on confirmed
teardown, exactly the mechanism adr/0015 converged on:

```c
typedef struct db_blob {
    sqlite3  *db;
    record_t  self_ref;    /* PL_record of the blob term; pins the
                              blob atom against atom-GC (adr/0015) */
} db_blob_t;

typedef struct stmt_blob {
    sqlite3_stmt *stmt;
    record_t      self_ref;   /* same pin, same rule */
} stmt_blob_t;
```

- `pl_sqlite3_open` and `pl_sqlite3_prepare` call `PL_record` on the
  freshly-unified blob term before returning.
- `pl_sqlite3_close` and `pl_sqlite3_finalize` call the underlying C
  function first, and only on success `PL_erase` the pin and NULL the
  pointer.
- The blob `release` hook therefore only ever sees an
  already-torn-down wrapper; it never calls `sqlite3_close` or
  `sqlite3_finalize` itself. A leaked (never-finalized) statement is a
  visible resource leak, not a latent heap corruption — the correct
  side of that trade, as two ADRs of segfault archaeology attest.

Lifetimes are thus explicit and deterministic: a connection or
statement lives exactly until the code that owns it says
`close`/`finalize`, never "until whenever atom-GC runs." The Prolog
layer's `setup_call_cleanup/3` use (next section) makes saying
`finalize` unavoidable.

### 3. The flagship: `db_row/4` — nondeterminism is iteration

This is north-star rule 6 made concrete. The Prolog-side database
module (`prolog/db.pl`) exports one central relation:

```prolog
%!  db_row(+DB, +SQL, +Params, -Row) is nondet.
%
%   True when Row is a row produced by running SQL with Params on DB.
%   Each solution is one sqlite3_step; backtracking steps again.
%   Row is a dict keyed by column names: row{id: 7, title: "..."}.
```

`db_row/4` is **nondeterministic**: it prepares, binds, and then each
`sqlite3_step/2` that answers `row` produces one solution.
Backtracking into `db_row/4` steps again. When `step` answers `done`,
the enumeration **fails** — the natural Prolog way to say "no more
rows." Whatever way execution leaves — exhaustion, a cut, an early
exit via `once/1`, or an exception — the statement is finalized,
because the whole thing is wrapped in `setup_call_cleanup/3`:

```prolog
db_row(DB, SQL, Params, Row) :-
    setup_call_cleanup(
        ( sqlite3_prepare(DB, SQL, Stmt),
          bind_all(Params, 1, Stmt)
        ),
        stmt_row(Stmt, Row),
        sqlite3_finalize(Stmt)).

bind_all([], _, _).
bind_all([P|Ps], I, Stmt) :-
    sqlite3_bind(Stmt, I, P),
    I1 is I + 1,
    bind_all(Ps, I1, Stmt).

stmt_row(Stmt, Row) :-
    sqlite3_column_count(Stmt, N),
    column_names(Stmt, 0, N, Names),      % sqlite3_column_name/3, once
    repeat,
    sqlite3_step(Stmt, Result),
    (   Result == row
    ->  columns(Stmt, 0, N, Values),      % sqlite3_column/3 per column
        pairs_keys_values(Pairs, Names, Values),
        dict_pairs(Row, row, Pairs)
    ;   !, fail                            % done: cut the repeat, end enumeration
    ).
```

(The `repeat`/`step` loop is the classic Prolog idiom for driving an
external cursor; column names are fetched once, before the first step,
and reused for every row dict.)

`Row` is a dict tagged `row`, keyed by column-name atoms, with values
already typed by the C layer's column mapping:

```prolog
?- db_row(DB, "SELECT id, title, created_at FROM posts WHERE author = ?",
          ["dario"], Row).
Row = row{id: 1, title: "Hello", created_at: 1753142400} ;
Row = row{id: 4, title: "Second post", created_at: 1753228800} ;
false.
```

#### The beautiful consequences

Because a row is a solution, all of Prolog's control constructs become
query execution strategies — with real, physical effects on how much
work SQLite does:

**`once/1` is early termination, not decoration.** This steps the
statement exactly once, gets one row, and the cleanup finalizes the
statement — SQLite never computes row two. It is `LIMIT 1` expressed
in the host language, and it genuinely stops stepping:

```prolog
show(Env0, Env) :-
    Id = Env0.params.id,
    once(db_row(Env0.db, "SELECT * FROM posts WHERE id = ?", [Id], Post)),
    respond(Env0, view(post_show(Post)), Env).
```

**`forall/2` streams.** This walks 10,000 rows one at a time — each
row exists only for the duration of its iteration, is rendered
straight to the response stream (adr/0007, adr/0016 rule 5), and is
gone before the next `step`:

```prolog
export_csv(Env0, Env) :-
    respond_stream(Env0, "text/csv", Out, Env),
    forall(db_row(Env0.db, "SELECT id, title, created_at FROM posts", [], Row),
           write_csv_row(Out, Row)).
```

At no point do 10,000 rows exist as a list. Peak memory is one row,
regardless of result-set size.

**A list is an explicit choice, made by the caller.** When a handler
really wants all rows materialized — say, to count and paginate — it
says so with `findall/3`, and the cost is visible at the call site:

```prolog
index(Env0, Env) :-
    findall(P,
            db_row(Env0.db,
                   "SELECT * FROM posts ORDER BY created_at DESC", [], P),
            Posts),
    respond(Env0, view(post_index(Posts)), Env).
```

This is the exact row-level analog of adr/0007's rule for HTTP bodies:
the truthful, streaming interface is the primitive; materialization is
an opt-in convenience layered on top, never the only option. SQLite's
`step` is a genuinely incremental cursor, just as llhttp is a genuinely
incremental parser — and in both cases the binding preserves that
property instead of hiding it behind a buffer.

adr/0021's `row(Q, Row)` / `row(DB, Q, Row)` (the term-based query
builder from adr/0016's syntax inventory) compiles its `q(Table,
Clauses)` term to a SQL string plus parameter list via `sql/3` and
then calls straight into `db_row/4`. The nondeterminism — and every
consequence above — flows through unchanged.

### 4. Concurrency and ownership: one connection per worker

Connections follow adr/0005's shared-nothing worker model:

- **One connection per worker.** At worker startup the framework reads
  `config(database, Path)` (adr/0022) and opens one connection on the
  worker's own thread. The connection lives in the worker's state,
  is reachable from handlers as `Env.db`, and is closed when the
  worker shuts down. It never crosses a worker boundary — same rule
  as connections, handles, and streams.
- **Serialized mode as belt and braces.** The amalgamation is compiled
  with `-DSQLITE_THREADSAFE=1` (serialized), SQLite's default and
  safest mode. Ownership discipline means no connection is ever
  actually used from two threads, so the internal mutexes are
  uncontended and effectively free — but a future bug that violates
  ownership degrades to a correctness-preserving slowdown instead of
  data corruption.
- **WAL mode for cross-worker readers.** Multiple workers each hold
  their own connection to the same database file. In SQLite's default
  rollback-journal mode, a writer blocks all readers; in WAL mode,
  readers proceed concurrently with a single writer — exactly the
  many-workers-one-file shape we have. So the framework's open
  sequence issues the pragmas immediately after `sqlite3_open/2`:

  ```prolog
  db_open(Path, DB) :-
      sqlite3_open(Path, DB),
      db_exec(DB, "PRAGMA journal_mode = WAL", []),
      db_exec(DB, "PRAGMA busy_timeout = 5000", []),
      db_exec(DB, "PRAGMA foreign_keys = ON", []).
  ```

- **`busy_timeout` on open.** WAL still permits only one writer at a
  time across all workers. With `busy_timeout` set, a worker that
  wants to write while another worker's transaction holds the write
  lock waits (up to 5 seconds) instead of failing instantly with
  `SQLITE_BUSY`. Writers queue; they do not error. (A worker blocked
  here blocks its own event loop — that is adr/0006's known,
  documented trade-off applying to the database exactly as it applies
  to any other blocking call, and 5 s is the ceiling, not the norm:
  SQLite write transactions on the same VM are typically
  sub-millisecond.)

  Note the pragmas go through `db_exec/3` — no extra C predicates for
  `sqlite3_busy_timeout` or WAL are needed, keeping the 1:1 surface at
  exactly the fourteen predicates listed.

### 5. Convenience layer: `db_exec/3` and `db_transaction/2`

Two more predicates in `prolog/db.pl` complete the surface adr/0021
builds on:

```prolog
%!  db_exec(+DB, +SQL, +Params) is det.
%
%   Run SQL for effect. Prepares, binds, steps to done, finalizes
%   (setup_call_cleanup, as db_row/4). Any rows the statement happens
%   to produce are discarded. Deterministic: succeeds once or throws.

?- db_exec(DB, "INSERT INTO posts (title, body) VALUES (?, ?)",
           ["Hello", "First post."]),
   sqlite3_last_insert_rowid(DB, Id).
Id = 7.
```

```prolog
%!  db_transaction(+DB, :Goal) is semidet.
%
%   BEGIN IMMEDIATE; call Goal once; COMMIT if it succeeds.
%   ROLLBACK if Goal throws (the exception is re-thrown) OR if Goal
%   fails (db_transaction/2 then fails). Goal is not re-entered on
%   backtracking; a transaction runs its goal with once-semantics.

db_transaction(DB, Goal) :-
    db_exec(DB, "BEGIN IMMEDIATE", []),
    (   catch(Goal, Error, true)
    ->  (   var(Error)
        ->  db_exec(DB, "COMMIT", [])
        ;   db_exec(DB, "ROLLBACK", []),
            throw(Error)
        )
    ;   db_exec(DB, "ROLLBACK", []),
        fail
    ).
```

The failure semantics are stated explicitly because they are the
Prolog-specific case Rails never faces: **a failing goal rolls the
transaction back and `db_transaction/2` itself fails.** Failure inside
a transaction means "this did not logically happen," and the database
agrees. There is no way to leave `db_transaction/2` with a dangling
open transaction: every exit path — success, failure, exception — has
issued exactly one `COMMIT` or `ROLLBACK`.

`BEGIN IMMEDIATE` (rather than plain deferred `BEGIN`) takes the write
lock up front, so lock contention between workers surfaces at `BEGIN`
— where `busy_timeout` handles it by waiting — instead of as a
mid-transaction `SQLITE_BUSY` upgrade failure after work has been
done.

```prolog
create(Env0, Env) :-
    form_result(post_form, Env0, ok(Values)),
    db_transaction(Env0.db,
        ( db_exec(Env0.db,
                  "INSERT INTO posts (title, body) VALUES (?, ?)",
                  [Values.title, Values.body]),
          sqlite3_last_insert_rowid(Env0.db, Id),
          db_exec(Env0.db,
                  "INSERT INTO activity (post_id, kind) VALUES (?, 'created')",
                  [Id])
        )),
    redirect(Env0, post_path(Id), Env).
```

(App code will normally not even write this much SQL — see
Consequences — but the transaction shape is the same either way.)

## Consequences

**Build wiring.** `c/Makefile` grows a `sqlite3_swi.so` target
following the exact shape of `llhttp_swi.so`, with one refinement: the
amalgamation is compiled to an object file once, separately, because a
~9 MB generated C file takes a noticeable while (tens of seconds) to
compile — a one-time cost paid per re-vendoring or `make clean`, not
per edit of `sqlite3_swi.c`:

```make
CFLAGS_SQLITE = -DSQLITE_THREADSAFE=1 -DSQLITE_OMIT_LOAD_EXTENSION \
                -I../vendor/sqlite3

sqlite3.o: ../vendor/sqlite3/sqlite3.c
	$(CC) -c -fPIC -O2 $(CFLAGS_SQLITE) -o $@ $<

sqlite3_swi.so: sqlite3_swi.c sqlite3.o
	$(SWIPL_LD) -shared -o $@ $(CFLAGS) $(CFLAGS_SQLITE) $^
```

`-DSQLITE_THREADSAFE=1` selects serialized mode per section 4.
`-DSQLITE_OMIT_LOAD_EXTENSION` removes the runtime extension loader we
have no use for, which also drops the `-ldl` link requirement and
shrinks the attack surface of a network-facing process.

**The C surface is small, uniform, and auditable.** Fourteen
predicates, each a mechanical wrapper, in one file that follows the
same blob-with-`self_ref` shape as `uv_swi.c` — so adr/0013's
`ast-grep` audit patterns extend to it directly, and the adr/0015
class of bug is excluded by construction rather than discovered under
load. Bugs in query semantics, row shaping, or transaction behavior
are Prolog bugs, testable against an in-memory database
(`sqlite3_open(":memory:", DB)`) with plain unit clauses — no server,
no fixtures on disk.

**adr/0021 has its foundation.** The query builder compiles
`q(Table, Clauses)` terms to `(SQL, Params)` via `sql/3` and executes
exclusively through `db_row/4` and `db_exec/3` — it adds no C, no new
execution paths, and inherits streaming-by-backtracking for free.
Consequently **app code normally never writes a SQL string**: handlers
say `row(q(posts, [where(author == A)]), Row)` and `insert(posts,
Values, Id)`, and the strings in this ADR's examples are what the
framework generates, visible to applications only through `sql/3` when
they ask. That closes the loop on adr/0016 rule 4: SQL joins HTML and
routes as a term language compiled by the framework, with the raw
string layer remaining available — honestly, and one level down — for
the cases the builder does not cover.

**Costs, stated plainly.** Re-vendoring is manual (download, replace,
diff — same as llhttp). One connection per worker means per-worker
page caches, slightly raising memory with worker count. And a slow
query blocks its whole worker (adr/0006) — the mitigation is the same
as for any blocking handler work: keep queries indexed and small, and
scale worker count.
