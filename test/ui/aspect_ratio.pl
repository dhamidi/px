/* ui/aspect_ratio (adr/0026): the render-contract test required by
   rule 7a. A plain swipl script -- no server, no networking -- loading
   px_template.pl and px_ui.pl (which, per its directory scan, loads
   every module under prolog/ui/ -- currently just aspect_ratio.pl)
   and exercising render_to_string/2 over the templates and the
   registered demo, same harness shape as
   test/milestone10_templates.pl.

   Covers:
     - aspect_ratio_root/2 emits ONE div carrying
       data-radix-aspect-ratio-wrapper="" and a computed
       `aspect-ratio: W / H;` inline style (the platform choice noted
       in the module header: no padding-bottom hack, no absolutely
       positioned inner div)
     - ratio(16/9) / ratio(1/1) both compute correctly
     - ratio/1 omitted defaults to 1/1 (Radix's own default)
     - pass-through attrs (id, class) survive untouched
     - a caller-supplied style(...) is appended after the computed
       aspect-ratio declaration, not overwritten
     - a malformed ratio/1 term throws domain_error(px_aspect_ratio, _)
     - aspect_ratio/2 (the top-level convenience) renders identically
       to aspect_ratio_root/2 for the same Opts/Content
     - the component registers px_ui:demo(aspect_ratio, _, _), and
       that demo call renders both a 16/9 image and a 1/1 swatch

   Run:  swipl test/ui/aspect_ratio.pl
*/

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../../prolog/px_template'], TemplateSpec),
   atomic_list_concat([Dir, '/../../prolog/px_ui'],       PxUiSpec),
   use_module(TemplateSpec),
   use_module(PxUiSpec).

:- initialization(main, main).

		 /*******************************
		 *            HARNESS           *
		 *******************************/

:- dynamic failed_count/1.
failed_count(0).

bump :-
    retract(failed_count(N)),
    N1 is N + 1,
    assertz(failed_count(N1)).

check(Name, Goal) :-
    (   catch(Goal, E,
              ( format("      unexpected error: ~q~n", [E]), fail ))
    ->  format("PASS  ~w~n", [Name])
    ;   format("FAIL  ~w~n", [Name]),
        bump
    ).

contains(Haystack, Needle) :-
    sub_string(Haystack, _, _, _, Needle).

main :-
    tests,
    failed_count(N),
    (   N =:= 0
    ->  format("~nAll ui/aspect_ratio checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

		 /*******************************
		 *             TESTS            *
		 *******************************/

tests :-
    % NB: every check below uses its OWN string variable (S1, S2, ...)
    % rather than a shared "S" -- this whole predicate is ONE clause
    % body, so a reused variable name is the SAME variable throughout
    % it (Prolog scopes variables to the clause, not the goal); reusing
    % "S" would bind it in the first check and then every later
    % render_to_string(..., S) would just fail to unify against that
    % stale value (same trap milestone10_templates.pl's S1..S11 avoid).

    % -- one div, the query hook, computed aspect-ratio ----------------
    check(root_16_9_exact_markup,
          ( render_to_string(aspect_ratio_root([ratio(16/9)], "x"), S1),
            S1 == "<div data-radix-aspect-ratio-wrapper=\"\" style=\"aspect-ratio: 16 / 9;\">x</div>" )),

    check(root_1_1_exact_markup,
          ( render_to_string(aspect_ratio_root([ratio(1/1)], "sq"), S2),
            S2 == "<div data-radix-aspect-ratio-wrapper=\"\" style=\"aspect-ratio: 1 / 1;\">sq</div>" )),

    % -- ratio/1 omitted defaults to 1/1 (Radix's own default) ---------
    check(default_ratio_is_square,
          ( render_to_string(aspect_ratio_root([], "d"), S3),
            contains(S3, "style=\"aspect-ratio: 1 / 1;\"") )),

    % -- no leftover Radix padding-hack style ever emitted --------------
    check(no_padding_hack,
          ( render_to_string(aspect_ratio_root([ratio(4/3)], "p"), S4),
            \+ contains(S4, "padding-bottom"),
            \+ contains(S4, "position:"),
            \+ contains(S4, "position=") )),

    % -- pass-through attrs survive, in addition to the computed ones --
    check(passthrough_id_and_class,
          ( render_to_string(aspect_ratio_root([ratio(16/9), id(hero), class(box)], "c"), S5),
            contains(S5, "data-radix-aspect-ratio-wrapper=\"\""),
            contains(S5, "style=\"aspect-ratio: 16 / 9;\""),
            contains(S5, "id=\"hero\""),
            contains(S5, "class=\"box\"") )),

    % -- caller style(...) appended after the computed declaration -----
    check(caller_style_appended,
          ( render_to_string(aspect_ratio_root([ratio(16/9), style("border-radius:8px;")], "c"), S6),
            S6 == "<div data-radix-aspect-ratio-wrapper=\"\" style=\"aspect-ratio: 16 / 9; border-radius:8px;\">c</div>" )),

    % -- malformed ratio/1 is a caller error, not silently coerced -----
    check(malformed_ratio_throws,
          catch(( render_to_string(aspect_ratio_root([ratio(sixteen_nine)], "x"), _), fail ),
                error(domain_error(px_aspect_ratio, sixteen_nine), _),
                true)),

    % -- top-level convenience == the Root part for the same args ------
    check(convenience_matches_root,
          ( render_to_string(aspect_ratio([ratio(16/9), id(a)], "x"), SA),
            render_to_string(aspect_ratio_root([ratio(16/9), id(a)], "x"), SB),
            SA == SB )),

    % -- content can be an element, not just text -----------------------
    check(image_content_renders_inside,
          ( render_to_string(
                aspect_ratio([ratio(16/9)],
                             img([src("/pic.png"), alt("a pic")])),
                S7),
            S7 == "<div data-radix-aspect-ratio-wrapper=\"\" style=\"aspect-ratio: 16 / 9;\"><img src=\"/pic.png\" alt=\"a pic\"></div>" )),

    % -- demo registration + render (adr/0026 rule 7b) ------------------
    check(demo_registered,
          px_ui:demo(aspect_ratio, _Order, \aspect_ratio_demo)),

    check(demo_renders_16_9_and_1_1,
          ( render_to_string(\aspect_ratio_demo, SDemo),
            contains(SDemo, "aspect-ratio: 16 / 9;"),
            contains(SDemo, "aspect-ratio: 1 / 1;"),
            contains(SDemo, "<img "),
            contains(SDemo, "class=\"aspect-ratio-swatch\""),
            contains(SDemo, "data-radix-aspect-ratio-wrapper=\"\"") )),

    % show some real output for the record
    render_to_string(\aspect_ratio_demo, Full),
    format("~n--- rendered aspect_ratio_demo ---~n~w~n-----------------------------------~n", [Full]).
