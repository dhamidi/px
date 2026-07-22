/* Non-HTTP unit test: proves router:path_for/3 round-trips against
   router:match_route/4, per adr/0009 -- match a concrete path to get
   Params out, then feed those same Params back into path_for/3 and
   confirm the original path comes back out. No network, no workers;
   pure in-process unification.

   Run with:  swipl -q -g main -t halt test/router_path_for_roundtrip.pl
*/

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../prolog/router'], RouterLib),
   use_module(RouterLib).

:- initialization(main, main).

main :-
    router:clear_routes,
    router:add_route(adr_show, get, "/adr/:id", app:show_adr),
    router:add_route(adr_section, get, "/adr/:id/section/:name", app:show_section),
    router:add_route(adr_index, get, "/adr", app:index_adr),
    router:add_route(home, get, "/", app:home),

    test_case("single param",   get, "/adr/9",              adr_show,    "/adr/9"),
    test_case("two params",     get, "/adr/9/section/decision", adr_section, "/adr/9/section/decision"),
    test_case("no params",      get, "/adr",                 adr_index,   "/adr"),
    test_case("root path",      get, "/",                    home,        "/"),

    test_no_match,

    format("~nALL PATH_FOR ROUND-TRIP TESTS PASSED~n"),
    halt(0).
main :-
    format(user_error, "~nPATH_FOR ROUND-TRIP TESTS FAILED~n", []),
    halt(1).

test_case(Label, Method, Path, ExpectedName, ExpectedPath) :-
    format("~n[~w] forward: match_route(~q, ~q, H, Params)~n", [Label, Method, Path]),
    ( router:match_route(Method, Path, Handler, Params)
    -> format("  matched handler=~q params=~q~n", [Handler, Params])
    ;  format("  FAIL: no route matched~n", []), fail
    ),
    format("[~w] reverse: path_for(~q, ~q, PathBack)~n", [Label, ExpectedName, Params]),
    ( router:path_for(ExpectedName, Params, PathBack)
    -> format("  path_for produced ~q~n", [PathBack])
    ;  format("  FAIL: path_for/3 did not produce a path~n", []), fail
    ),
    ( atom_string(ExpectedPathAtom, ExpectedPath), atom_string(PathBackAtom, PathBack),
      ExpectedPathAtom == PathBackAtom
    -> format("  OK: round-trip matches original path ~q~n", [ExpectedPath])
    ;  format("  FAIL: expected ~q, got ~q~n", [ExpectedPath, PathBack]), fail
    ).

test_no_match :-
    format("~n[no match] match_route(get, \"/nope\", _, _) should fail~n", []),
    ( router:match_route(get, "/nope", _, _)
    -> format("  FAIL: unexpectedly matched~n", []), fail
    ;  format("  OK: correctly did not match~n", [])
    ).
