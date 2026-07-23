:- module(px_query,
          [ sql/3,                      % +Q, -SQL, -Params
            use_db/1,                   % +DB
            row/2,                      % +Q, -Row
            row/3,                      % +DB, +Q, -Row
            field/3,                    % +Row, +Column, -Value
            insert/3,                   % +Table, +Pairs, -Id
            insert/4,                   % +DB, +Table, +Pairs, -Id
            update/3,                   % +Table, +Pairs, +WhereExpr
            update/4,                   % +DB, +Table, +Pairs, +WhereExpr
            delete/2,                   % +Table, +WhereExpr
            delete/3,                   % +DB, +Table, +WhereExpr
            q_exec/2,                   % +SQL, +Params
            q_exec/3                    % +DB, +SQL, +Params
          ]).

/** <module> Query builder: datasets as terms (adr/0021).

A dataset is the term q(Table, Clauses) -- inert data until executed.
sql/3 compiles it to an SQL string plus parameter list via a pure,
deterministic DCG; row/2 and row/3 execute it on px_db's db_row/4,
so nondeterminism-is-iteration (adr/0016 rule 6, adr/0020) flows
through unchanged: one solution per row, backtracking steps the
cursor, once/1 stops it early.

Clause vocabulary: select/1, where/1, join/2, left_join/2,
group_by/1, order_by/1, limit/1, offset/1. Expression vocabulary
inside where/1: ==, \==, <, >, =<, >=, like/2, in/2, is_null/1,
and/2, or/2, \+ /1, and a list meaning conjunction. Inside a join's
on/1, both sides of == are field references; in where/1 a field
reference on the right is written field(F).

== SQL injection posture (adr/0021, load-bearing) ==

  1. Values are NEVER interpolated into SQL text. Every value
     position -- comparison operands, like/2 patterns, every element
     of an in/2 list, limit/offset counts, every column value in
     insert/update -- compiles to a `?` placeholder and travels in
     the parameter list, bound via sqlite3_bind_* (adr/0020). No
     code path in this module converts a value to SQL text.
  2. Identifiers are whitelisted at compile time. Table names, field
     names, and both parts of a Table/Field reference must be atoms
     matching [a-z_][a-z0-9_]*. A non-atom throws
     type_error(identifier, X); an atom outside the pattern throws
     domain_error(sql_identifier, X) -- in both cases before any SQL
     text exists. There is no quoted-identifier support and no way
     to smuggle text into an identifier position.

  The SQL produced here is therefore composed exclusively of
  compiler-owned keywords, whitelisted identifiers, and `?`
  placeholders.

== Composition is list manipulation ==

Because a dataset is a term, scopes are relations between datasets;
no database is needed to build or test them:

  ==
  %% published(+Q0, -Q): narrow any posts dataset to published rows.
  published(q(posts, C0), q(posts, [where(published == true)|C0])).

  %% paginate(+Q0, +Page, +PerPage, -Q)
  paginate(q(T, C0), Page, PerPage, q(T, C)) :-
      Offset is (Page - 1) * PerPage,
      append(C0, [limit(PerPage), offset(Offset)], C).
  ==

== Escape hatch ==

For queries the vocabulary cannot express, a raw sql(Text, Params)
term is accepted anywhere a dataset is (row/2, row/3, sql/3), and
q_exec/2 runs raw SQL for effect. Hand-written SQL text, but
parameters are still ?-bound -- the escape hatch relaxes the
vocabulary, never the injection posture.
*/

:- use_module(px_db).

%   One connection per worker (adr/0020 section 4): each worker thread
%   calls use_db/1 once at startup; the fact is thread-local, so
%   workers never see each other's connections.
:- thread_local current_db/1.

%!  use_db(+DB) is det.
%
%   Make DB the calling thread's implicit connection for row/2,
%   insert/3, update/3, delete/2, and q_exec/2.

use_db(DB) :-
    retractall(current_db(_)),
    assertz(current_db(DB)).

this_db(DB) :-
    (   current_db(DB)
    ->  true
    ;   throw(error(existence_error(px_query_connection, current_db),
                    context(px_query:this_db/1,
                            'no connection for this thread; call use_db/1 first')))
    ).


		 /*******************************
		 *   COMPILATION: sql/3 (DCG)   *
		 *******************************/

%!  sql(+Q, -SQL, -Params) is det.
%
%   Compile the dataset Q -- q(Table, Clauses) or the raw
%   sql(Text, Params) escape hatch -- to an SQL string and a flat
%   parameter list. Pure and deterministic: exactly one solution, no
%   side effects, no connection needed; invalid datasets throw before
%   any SQL text exists.

sql(sql(Text, Params), SQL, Params) :-
    !,
    must_be(list, Params),
    to_sql_string(Text, SQL).
sql(q(Table, Clauses), SQL, Params) :-
    !,
    must_be(list, Clauses),
    phrase(query(Table, Clauses, Params, []), Codes),
    string_codes(SQL, Codes).
sql(Q, _, _) :-
    throw(error(domain_error(dataset, Q), context(px_query:sql/3, _))).

to_sql_string(S, S) :- string(S), !.
to_sql_string(A, S) :- atom(A), !, atom_string(A, S).
to_sql_string(X, _) :-
    throw(error(type_error(sql_text, X), context(px_query:sql/3, _))).

%   The compiler always emits the canonical SQL clause order
%   regardless of where clauses sit in the list. Order is preserved
%   only where SQL itself is ordered: multiple joins keep their
%   relative list order, and so do sort keys within and across
%   order_by clauses. Multiple where/1 clauses AND together.
%   Params thread through the grammar as a difference list.

query(Table, Clauses, P0, P) -->
    { classify(Clauses, Sel, Joins, Wheres, Groups, Orders, Limit, Offset) },
    "SELECT ", select_list(Sel),
    " FROM ", ident(Table),
    joins(Joins),
    where_part(Wheres, P0, P1),
    group_part(Groups),
    order_part(Orders),
    limit_part(Limit, Offset, P1, P).

%   classify(+Clauses, -Sel, -Joins, -Wheres, -Groups, -Orders, -Limit, -Offset)
%   Sel/Limit/Offset are none or some(X); the rest are lists in
%   clause-list order. An unrecognized clause throws.

classify(Clauses, Sel, Joins, Wheres, Groups, Orders, Limit, Offset) :-
    maplist(known_clause, Clauses),
    (   memberchk(select(Sel0), Clauses) -> Sel = some(Sel0) ; Sel = none ),
    findall(j(K, T, On), ( member(C, Clauses), join_of(C, K, T, On) ), Joins),
    findall(E, member(where(E), Clauses), Wheres),
    findall(G, ( member(group_by(G0), Clauses), listify(G0, Gs), member(G, Gs) ),
            Groups),
    findall(O, ( member(order_by(O0), Clauses), listify(O0, Os), member(O, Os) ),
            Orders),
    (   memberchk(limit(L), Clauses)  -> Limit  = some(L) ; Limit  = none ),
    (   memberchk(offset(O), Clauses) -> Offset = some(O) ; Offset = none ).

join_of(join(T, On), inner, T, On).
join_of(left_join(T, On), left, T, On).

known_clause(C) :-
    (   nonvar(C),
        memberchk(C, [ select(_), where(_), join(_, _), left_join(_, _),
                       group_by(_), order_by(_), limit(_), offset(_) ])
    ->  true
    ;   throw(error(domain_error(query_clause, C), context(px_query:sql/3, _)))
    ).

listify(X, X)   :- is_list(X), !.
listify(X, [X]).

% --- SELECT ---------------------------------------------------------

select_list(none) --> !, "*".
select_list(some(Fs)) -->
    { listify(Fs, List) },
    select_fields(List).

select_fields([F]) --> !, select_field(F).
select_fields([F|Fs]) --> select_field(F), ", ", select_fields(Fs).
select_fields([]) -->
    { throw(error(domain_error(select_fields, []), context(px_query:sql/3, _))) }.

%   Aggregates are limited to count/sum/avg/min/max over a field
%   reference, in select position only.
select_field(Agg) -->
    { nonvar(Agg), Agg =.. [Name, F], aggregate_name(Name) },
    !,
    atom_codes_out(Name), "(", field_ref(F), ")".
select_field(F) --> field_ref(F).

aggregate_name(count).
aggregate_name(sum).
aggregate_name(avg).
aggregate_name(min).
aggregate_name(max).

% --- JOINs ----------------------------------------------------------

joins([]) --> [].
joins([j(Kind, Table, On)|Js]) -->
    join_kw(Kind), ident(Table), " ON ", on_condition(On),
    joins(Js).

join_kw(inner) --> " INNER JOIN ".
join_kw(left)  --> " LEFT JOIN ".

%   In on/1 both sides compile as identifiers (that is what makes it a
%   join condition, not a filter).
on_condition(on(F1 == F2)) -->
    !,
    field_ref(F1), " = ", field_ref(F2).
on_condition(On) -->
    { throw(error(domain_error(join_condition, On), context(px_query:sql/3, _))) }.

% --- WHERE ----------------------------------------------------------

%   A where(List) means the conjunction of its elements; multiple
%   where/1 clauses AND together. At top level conjuncts join with
%   bare AND (matching adr/0021's worked compilations); nested
%   and/2, or/2, and lists inside expressions parenthesize.

where_part(Wheres, P0, P) -->
    { foldl(where_conjuncts, Wheres, Conjs, []) },
    where_conj(Conjs, P0, P).

where_conjuncts(E, C0, C) :-
    (   is_list(E)
    ->  append(E, C, C0)
    ;   C0 = [E|C]
    ).

where_conj([], P, P) --> !.
where_conj(Conjs, P0, P) --> " WHERE ", conj(Conjs, P0, P).

conj([E], P0, P) --> !, expr(E, P0, P).
conj([E|Es], P0, P) --> expr(E, P0, P1), " AND ", conj(Es, P1, P).

%   expr(+E, ?P0, ?P)// -- compile one condition; parameters are
%   emitted into the P0..P difference list in textual order.

expr(F == V,  P0, P) --> !, field_ref(F), " = ",  rhs(V, P0, P).
expr(F \== V, P0, P) --> !, field_ref(F), " <> ", rhs(V, P0, P).
expr(F < V,   P0, P) --> !, field_ref(F), " < ",  rhs(V, P0, P).
expr(F > V,   P0, P) --> !, field_ref(F), " > ",  rhs(V, P0, P).
expr(F =< V,  P0, P) --> !, field_ref(F), " <= ", rhs(V, P0, P).
expr(F >= V,  P0, P) --> !, field_ref(F), " >= ", rhs(V, P0, P).
expr(like(F, Pat), P0, P) --> !, field_ref(F), " LIKE ?", { P0 = [Pat|P] }.
%   Empty in/2 compiles to the always-false 1 = 0 (SQLite rejects
%   `IN ()`), exactly as Sequel does.
expr(in(_, []), P, P) --> !, "1 = 0".
expr(in(F, Vs), P0, P) -->
    { is_list(Vs) },
    !,
    field_ref(F), " IN (", placeholders(Vs, P0, P), ")".
expr(is_null(F), P, P) --> !, field_ref(F), " IS NULL".
expr(\+ is_null(F), P, P) --> !, field_ref(F), " IS NOT NULL".
expr(\+ in(_, []), P, P) --> !, "1 = 1".
expr(\+ in(F, Vs), P0, P) -->
    { is_list(Vs) },
    !,
    field_ref(F), " NOT IN (", placeholders(Vs, P0, P), ")".
expr(\+ E, P0, P) --> !, "NOT (", expr(E, P0, P), ")".
expr(and(A, B), P0, P) --> !, "(", expr(A, P0, P1), " AND ", expr(B, P1, P), ")".
expr(or(A, B),  P0, P) --> !, "(", expr(A, P0, P1), " OR ",  expr(B, P1, P), ")".
expr(List, P0, P) -->
    { is_list(List), List \== [] },
    !,
    "(", conj(List, P0, P), ")".
expr(E, _, _) -->
    { throw(error(domain_error(query_expression, E), context(px_query:sql/3, _))) }.

%   Right-hand side of a comparison: a value becomes a ? placeholder;
%   field(F) marks an explicit field reference (column-to-column
%   comparison inside where/1).
rhs(field(F), P, P) --> !, field_ref(F).
rhs(V, P0, P) --> "?", { P0 = [V|P] }.

placeholders([V], P0, P) --> !, "?", { P0 = [V|P] }.
placeholders([V|Vs], P0, P) --> "?, ", { P0 = [V|P1] }, placeholders(Vs, P1, P).

% --- GROUP BY / ORDER BY -------------------------------------------

group_part([]) --> !.
group_part(Gs) --> " GROUP BY ", field_list(Gs).

field_list([F]) --> !, field_ref(F).
field_list([F|Fs]) --> field_ref(F), ", ", field_list(Fs).

order_part([]) --> !.
order_part(Os) --> " ORDER BY ", order_keys(Os).

order_keys([O]) --> !, order_key(O).
order_keys([O|Os]) --> order_key(O), ", ", order_keys(Os).

order_key(desc(F)) --> !, field_ref(F), " DESC".
order_key(asc(F))  --> !, field_ref(F), " ASC".
order_key(F) --> field_ref(F).

% --- LIMIT / OFFSET -------------------------------------------------

%   Limit and offset counts are bound parameters like every other
%   value. OFFSET without LIMIT uses SQLite's `LIMIT -1` (no limit);
%   the -1 is a compiler-owned literal, not a user value.

limit_part(none, none, P, P) --> !.
limit_part(some(L), none, P0, P) --> !, " LIMIT ?", { P0 = [L|P] }.
limit_part(some(L), some(O), P0, P) --> !, " LIMIT ? OFFSET ?", { P0 = [L, O|P] }.
limit_part(none, some(O), P0, P) --> " LIMIT -1 OFFSET ?", { P0 = [O|P] }.

% --- Field references and identifiers ------------------------------

%   A field reference is an atom (title) or Table/Field
%   (posts/title -> posts.title). Both parts are validated. Named
%   field_ref//1 (not field//1) so the DCG expansion (which adds two
%   difference-list args, making this predicate field_ref/3) does not
%   collide with the public row accessor field/3 (adr/0037 decision 4).

field_ref(T/F) --> !, ident(T), ".", ident(F).
field_ref(F) --> ident(F).

%   The identifier whitelist: atoms matching [a-z_][a-z0-9_]*.
%   Everything else throws before any SQL text exists (see the module
%   header for the full injection posture).

ident(X) -->
    { valid_identifier(X), atom_codes(X, Codes) },
    atom_codes_out_(Codes).

atom_codes_out(A) --> { atom_codes(A, Codes) }, atom_codes_out_(Codes).

atom_codes_out_([]) --> [].
atom_codes_out_([C|Cs]) --> [C], atom_codes_out_(Cs).

%!  valid_identifier(+X) is det.
%
%   Succeed iff X is an atom matching [a-z_][a-z0-9_]*; otherwise
%   throw type_error(identifier, X) (non-atom) or
%   domain_error(sql_identifier, X) (atom outside the pattern).

valid_identifier(X) :-
    (   atom(X)
    ->  (   atom_codes(X, [C0|Cs]),
            ident_start(C0),
            all_ident_chars(Cs)
        ->  true
        ;   throw(error(domain_error(sql_identifier, X),
                        context(px_query:valid_identifier/1, _)))
        )
    ;   throw(error(type_error(identifier, X),
                    context(px_query:valid_identifier/1, _)))
    ).

ident_start(C) :- C >= 0'a, C =< 0'z, !.
ident_start(0'_).

ident_char(C) :- ident_start(C), !.
ident_char(C) :- C >= 0'0, C =< 0'9.

all_ident_chars([]).
all_ident_chars([C|Cs]) :- ident_char(C), all_ident_chars(Cs).


		 /*******************************
		 *     EXECUTION: row/2,3       *
		 *******************************/

%!  row(+Q, -Row) is nondet.
%!  row(+DB, +Q, -Row) is nondet.
%
%   True when Row is a row produced by the dataset Q. row/2 runs on
%   the calling worker's connection (use_db/1); row/3 takes an
%   explicit connection, for scripts, tests, and tools. Each solution
%   is one sqlite3_step (adr/0020's db_row/4): backtracking streams,
%   once/1 stops early, findall/3 is the explicit way to get a list.
%   Row is a Key-Value pairs list keyed by the selected column names:
%   [id-7, title-"Hello"] (adr/0037 decision 4). Use field/3 to read
%   one column; the model is expected to destructure the row into
%   named parts rather than carry it further.

row(Q, Row) :-
    this_db(DB),
    row(DB, Q, Row).

row(DB, Q, Row) :-
    sql(Q, SQL, Params),                 % validates before any I/O
    db_row(DB, SQL, Params, Row).

%!  field(+Row, +Column, -Value) is det.
%
%   True when Value is the value of Column in Row (a row produced by
%   row/2 or row/3). Column is an atom. Deterministic; throws
%   existence_error(column, Column) if Row has no such column -- a
%   typo'd column name must fail loudly, not silently (adr/0037
%   decision 4, the whole point vs. dicts).

field(Row, Column, Value) :-
    must_be(atom, Column),
    (   memberchk(Column-Value0, Row)
    ->  Value = Value0
    ;   throw(error(existence_error(column, Column),
                    context(px_query:field/3, _)))
    ).


		 /*******************************
		 *           WRITES             *
		 *******************************/

%!  insert(+Table, +Pairs, -Id) is det.
%!  insert(+DB, +Table, +Pairs, -Id) is det.
%
%   INSERT INTO Table (k1, ...) VALUES (?, ...); Id unifies with
%   last_insert_rowid(). Pairs is a Key-Value pairs list
%   [col-val, ...] (adr/0037 decision 4); columns come from its keys,
%   each validated as an identifier, values are all ?-bound.

insert(Table, Pairs, Id) :-
    this_db(DB),
    insert(DB, Table, Pairs, Id).

insert(DB, Table, Pairs, Id) :-
    valid_identifier(Table),
    must_be(list, Pairs),
    (   Pairs == []
    ->  throw(error(domain_error(nonempty_pairs, Pairs),
                    context(px_query:insert/4, _)))
    ;   true
    ),
    pairs_keys_values(Pairs, Keys, Values),
    maplist(valid_identifier, Keys),
    atomic_list_concat(Keys, ', ', Cols),
    length(Keys, N),
    n_placeholders(N, Marks),
    atomic_list_concat(Marks, ', ', Qs),
    format(string(SQL), "INSERT INTO ~w (~w) VALUES (~w)", [Table, Cols, Qs]),
    db_exec(DB, SQL, Values),
    db_last_insert_rowid(DB, Id).

n_placeholders(0, []) :- !.
n_placeholders(N, ['?'|Marks]) :-
    N1 is N - 1,
    n_placeholders(N1, Marks).

%!  update(+Table, +Pairs, +WhereExpr) is det.
%!  update(+DB, +Table, +Pairs, +WhereExpr) is det.
%
%   UPDATE Table SET k1 = ?, ... WHERE ...; WhereExpr is the same
%   expression language as where/1 (a list means conjunction; the
%   empty list means no WHERE clause -- all rows). Pairs is a
%   Key-Value pairs list [col-val, ...] (adr/0037 decision 4).

update(Table, Pairs, WhereExpr) :-
    this_db(DB),
    update(DB, Table, Pairs, WhereExpr).

update(DB, Table, Pairs, WhereExpr) :-
    valid_identifier(Table),
    must_be(list, Pairs),
    (   Pairs == []
    ->  throw(error(domain_error(nonempty_pairs, Pairs),
                    context(px_query:update/4, _)))
    ;   true
    ),
    pairs_keys_values(Pairs, Keys, Values),
    maplist(valid_identifier, Keys),
    findall(S, ( member(K, Keys), atomic_list_concat([K, ' = ?'], S) ), Sets),
    atomic_list_concat(Sets, ', ', SetSQL),
    where_sql(WhereExpr, WhereSQL, WhereParams),
    format(string(SQL), "UPDATE ~w SET ~w~w", [Table, SetSQL, WhereSQL]),
    append(Values, WhereParams, Params),
    db_exec(DB, SQL, Params).

%!  delete(+Table, +WhereExpr) is det.
%!  delete(+DB, +Table, +WhereExpr) is det.
%
%   DELETE FROM Table WHERE ...; the empty list means no WHERE
%   clause -- all rows.

delete(Table, WhereExpr) :-
    this_db(DB),
    delete(DB, Table, WhereExpr).

delete(DB, Table, WhereExpr) :-
    valid_identifier(Table),
    where_sql(WhereExpr, WhereSQL, Params),
    format(string(SQL), "DELETE FROM ~w~w", [Table, WhereSQL]),
    db_exec(DB, SQL, Params).

%   where_sql(+Expr, -WhereSQL, -Params): compile a bare expression
%   through the same DCG as where/1 -- one code path, one posture.

where_sql(Expr, WhereSQL, Params) :-
    phrase(where_part([Expr], Params, []), Codes),
    string_codes(WhereSQL, Codes).

%!  q_exec(+SQL, +Params) is det.
%!  q_exec(+DB, +SQL, +Params) is det.
%
%   Escape hatch: run raw SQL for effect on the current (or given)
%   connection. Parameters are still ?-bound.

q_exec(SQL, Params) :-
    this_db(DB),
    q_exec(DB, SQL, Params).

q_exec(DB, SQL, Params) :-
    db_exec(DB, SQL, Params).
