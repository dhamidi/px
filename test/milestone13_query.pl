/* Milestone 13 (adr/0021): the query builder -- datasets as terms.

   A dataset is q(Table, Clauses), inert data compiled to SQL + params
   by the pure DCG sql/3 and executed on px_db's db_row/4 via row/2/3.

   This is a plain swipl script, in two sections:

   PURE COMPILATION (no database at all): asserts exact SQL strings and
   parameter lists, including adr/0021's worked compilations verbatim --
   join with qualified fields, in/2 (and the empty in/2 -> 1 = 0),
   descending order, limit/offset as bound parameters, where(List)
   meaning conjunction, aggregates, \+ is_null, left_join, and the
   injection posture: a malicious identifier (the ATOM 'x; DROP')
   throws domain_error(sql_identifier, _) before any SQL text exists.

   LIVE (temp db via px_db): create a table, insert/3 (rowid comes
   back), row/2 enumeration through use_db/1 with where/order/limit
   (rows are dicts tagged with the table name), update/3 + verify,
   delete/3 + verify, and the q_exec/2 escape hatch.
*/

:- use_module('../prolog/px_db.pl').
:- use_module('../prolog/px_query.pl').

:- initialization(main, main).

check(Name, Goal) :-
    (   catch(Goal, E, (format("FAIL: ~w (exception ~q)~n", [Name, E]), fail))
    ->  format("PASS: ~w~n", [Name])
    ;   format("FAIL: ~w~n", [Name]),
        fail
    ).

main(_Argv) :-
    (   catch(run_all, E, (format("FAIL: uncaught exception ~q~n", [E]), fail))
    ->  format("~n=== milestone13: OVERALL PASS ===~n"),
        halt(0)
    ;   format("~n=== milestone13: OVERALL FAIL ===~n"),
        halt(1)
    ).

run_all :-
    format("--- pure compilation (no db) ---~n"),
    pure_section,
    format("~n--- live (temp db) ---~n"),
    live_section.

		 /*******************************
		 *      PURE COMPILATION        *
		 *******************************/

pure_section :-
    % (1) adr/0021 worked example: where + limit; limit is a bound param.
    check('(1) where + limit-as-param',
          ( sql(q(posts, [where(author == "d"), limit(3)]), S1, P1),
            S1 == "SELECT * FROM posts WHERE author = ? LIMIT ?",
            P1 == ["d", 3] )),

    % (2) adr/0021 worked example: list-means-AND, in/2, mixed order_by
    %     with desc.
    check('(2) list-means-AND + in/2 + order_by [desc(_), _]',
          ( sql(q(posts, [ where([published == true, in(status, [live, featured])]),
                           order_by([desc(created_at), title]) ]),
                S2, P2),
            S2 == "SELECT * FROM posts WHERE published = ? AND status IN (?, ?) ORDER BY created_at DESC, title",
            P2 == [true, live, featured] )),

    % (3) adr/0021 worked example: inner join, qualified fields, select.
    check('(3) join + Table/Field qualification + select',
          ( sql(q(posts, [ join(users, on(posts/author_id == users/id)),
                           where(users/name == "d"),
                           select([posts/title, users/name]) ]),
                S3, P3),
            S3 == "SELECT posts.title, users.name FROM posts INNER JOIN users ON posts.author_id = users.id WHERE users.name = ?",
            P3 == ["d"] )),

    % (4) adr/0021 worked example: aggregate in select, \+ is_null,
    %     group_by.
    check('(4) aggregate + \\+ is_null + group_by',
          ( sql(q(comments, [ select([post_id, count(id)]),
                              where(\+ is_null(approved_at)),
                              group_by(post_id) ]),
                S4, P4),
            S4 == "SELECT post_id, count(id) FROM comments WHERE approved_at IS NOT NULL GROUP BY post_id",
            P4 == [] )),

    % (5) empty in/2 compiles to the always-false 1 = 0, no params.
    check('(5) in(F, []) -> 1 = 0',
          ( sql(q(posts, [where(in(status, []))]), S5, P5),
            S5 == "SELECT * FROM posts WHERE 1 = 0",
            P5 == [] )),

    % (6) canonical clause order regardless of list order; multiple
    %     where/1 clauses AND together; offset is a param too;
    %     left_join; desc order.
    check('(6) clause order-independence + multi-where + left_join + offset',
          ( sql(q(posts, [ offset(20), limit(10),
                           where(published == true),
                           left_join(users, on(posts/author_id == users/id)),
                           order_by(desc(created_at)),
                           where(users/karma >= 5) ]),
                S6, P6),
            S6 == "SELECT * FROM posts LEFT JOIN users ON posts.author_id = users.id WHERE published = ? AND users.karma >= ? ORDER BY created_at DESC LIMIT ? OFFSET ?",
            P6 == [true, 5, 10, 20] )),

    % (7) injection posture: a malicious identifier is rejected at
    %     compile time with domain_error(sql_identifier, _), before any
    %     SQL text exists. 'x; DROP' is an ATOM -- the type is right,
    %     the spelling is outside [a-z_][a-z0-9_]*.
    check('(7a) malicious field atom throws domain_error(sql_identifier, _)',
          catch(( sql(q(posts, [where('x; DROP' == 1)]), _, _), fail ),
                error(domain_error(sql_identifier, 'x; DROP'), _),
                true)),
    check('(7b) malicious table atom throws domain_error(sql_identifier, _)',
          catch(( sql(q('x; DROP TABLE posts', []), _, _), fail ),
                error(domain_error(sql_identifier, 'x; DROP TABLE posts'), _),
                true)),
    check('(7c) non-atom identifier throws type_error(identifier, _)',
          catch(( sql(q(posts, [where("title" == 1)]), _, _), fail ),
                error(type_error(identifier, "title"), _),
                true)),

    % (8) expression coverage: or/2 parenthesizes, like/2 binds the
    %     pattern, is_null emits no param.
    check('(8) or/like/is_null',
          ( sql(q(posts, [where(or(like(title, "%pro%"), is_null(body)))]), S8, P8),
            S8 == "SELECT * FROM posts WHERE (title LIKE ? OR body IS NULL)",
            P8 == ["%pro%"] )),

    % (9) sql(Text, Params) escape hatch passes through.
    check('(9) sql(Text, Params) escape hatch',
          ( sql(sql("SELECT 1 WHERE 1 = ?", [1]), S9, P9),
            S9 == "SELECT 1 WHERE 1 = ?",
            P9 == [1] )).

		 /*******************************
		 *            LIVE              *
		 *******************************/

live_section :-
    tmp_file_stream(text, Path, TmpStream),
    close(TmpStream),
    format("temp db: ~w~n", [Path]),
    (   catch(live_checks(Path), E,
              (format("FAIL: live section exception ~q~n", [E]), fail))
    ->  Ok = true
    ;   Ok = false
    ),
    catch(delete_file(Path), _, true),
    atom_concat(Path, '-wal', Wal), catch(delete_file(Wal), _, true),
    atom_concat(Path, '-shm', Shm), catch(delete_file(Shm), _, true),
    Ok == true.

live_checks(Path) :-
    db_open(Path, DB),
    use_db(DB),

    q_exec("CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT, author TEXT, score INTEGER)",
           []),

    % insert/3: columns from dict keys, Id from last_insert_rowid.
    insert(posts, _{title: "first",  author: "d", score: 1}, Id1),
    check('(L1) first insert returns rowid 1', Id1 == 1),
    insert(posts, _{title: "second", author: "d", score: 5}, Id2),
    insert(posts, _{title: "third",  author: "e", score: 9}, Id3),
    check('(L1) rowids increment', (Id2 == 2, Id3 == 3)),

    % row/2 enumeration on the use_db/1 connection, with
    % where/order/limit -- rows are dicts tagged with the table name.
    findall(R, row(q(posts, [ where(author == "d"),
                              order_by(desc(score)),
                              limit(2) ]), R),
            Rows),
    format("rows: ~q~n", [Rows]),
    check('(L2) row/2 streams 2 matching rows', (length(Rows, 2))),
    Rows = [RA, RB],
    check('(L2) rows are dicts tagged posts', (is_dict(RA, posts), is_dict(RB, posts))),
    check('(L2) ordered desc by score', (RA.score == 5, RB.score == 1)),
    check('(L2) once/1 takes the first row only',
          ( once(row(q(posts, [order_by(title)]), First)),
            get_dict(title, First, FT), FT == "first" )),

    % row/3 explicit-connection variant.
    check('(L3) row/3 explicit-DB variant agrees',
          ( findall(T3, ( row(DB, q(posts, [select(title), order_by(title)]), TR3),
                          get_dict(title, TR3, T3) ),
                    Titles),
            Titles == ["first", "second", "third"] )),

    % update/3 + verify.
    update(posts, _{score: 100}, author == "d"),
    findall(S, ( row(q(posts, [where(author == "d")]), UR),
                 get_dict(score, UR, S) ),
            Scores),
    check('(L4) update/3 changed both matching rows', Scores == [100, 100]),
    check('(L4) update left the other author alone',
          ( once(row(q(posts, [where(author == "e")]), ER)),
            get_dict(score, ER, 9) )),

    % delete/3 (module delete/2 with current db) + verify.
    delete(posts, score == 100),
    findall(I, ( row(q(posts, []), DR), get_dict(id, DR, I) ),
            RemainingIds),
    check('(L5) delete/2 removed the updated rows', RemainingIds == [3]),

    % explicit-DB write variants + q_exec escape hatch.
    insert(DB, posts, _{title: "fourth", author: "f", score: 2}, Id4),
    check('(L6) insert/4 explicit-DB works', Id4 == 4),
    delete(DB, posts, id == Id4),
    q_exec(DB, "INSERT INTO posts (title, author, score) VALUES (?, ?, ?)",
           ["fifth", "g", 7]),
    check('(L6) q_exec/3 escape hatch inserts (params still ?-bound)',
          ( once(row(q(posts, [where(author == "g")]), QR)),
            get_dict(title, QR, "fifth") )),

    db_close(DB).
