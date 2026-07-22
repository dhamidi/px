/* ui/separator (adr/0026): the render-contract test required by rule
   7a. A plain swipl script -- no server, no networking -- loading
   px_template.pl and px_ui.pl (which, per its directory scan, loads
   every module under prolog/ui/) and exercising render_to_string/2
   over the templates and the registered demo, same harness shape as
   test/milestone10_templates.pl and test/ui/aspect_ratio.pl.

   Covers the contract from prolog/ui/separator.pl's module header
   (docs/radix-port-analysis.md "Separator"):
     - data-orientation is ALWAYS present, horizontal or vertical
     - default Opts ([]) is horizontal, non-decorative:
       role="separator", NO aria-orientation (horizontal is the ARIA
       default, so it is omitted)
     - orientation(vertical), non-decorative: role="separator" PLUS
       aria-orientation="vertical"
     - decorative(true): role="none" ONLY -- no aria-orientation at
       all, even when vertical
     - an invalid orientation/1 value falls back to the horizontal
       default (upstream's isValidOrientation guard)
     - pass-through attrs (id, data_testid) survive untouched; a
       caller class(...) is merged with, not replacing, the default
       px-separator styling hook
     - separator_root/1 (no Children) == separator_root/2 with []
     - separator/1,2 (the top-level convenience) render identically to
       separator_root/1,2 for the same Opts/Children
     - the component registers px_ui:demo(separator, _, _), and that
       demo renders the horizontal, vertical and decorative variants

   Run:  swipl test/ui/separator.pl
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
    ->  format("~nAll ui/separator checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

		 /*******************************
		 *             TESTS            *
		 *******************************/

tests :-
    % -- default Opts ([]): horizontal, role=separator, no aria-orientation
    check(default_horizontal_exact_markup,
          ( render_to_string(separator_root([]), S0),
            S0 == "<div class=\"px-separator\" data-orientation=\"horizontal\" role=\"separator\"></div>" )),

    % -- vertical, non-decorative: role=separator + aria-orientation --
    check(vertical_has_aria_orientation,
          ( render_to_string(separator_root([orientation(vertical)]), S1),
            S1 == "<div class=\"px-separator\" data-orientation=\"vertical\" role=\"separator\" aria-orientation=\"vertical\"></div>" )),

    % -- horizontal is the ARIA default: aria-orientation NEVER appears
    check(horizontal_omits_aria_orientation,
          ( render_to_string(separator_root([orientation(horizontal)]), S2),
            \+ contains(S2, "aria-orientation") )),

    % -- decorative: role="none" ONLY, no aria-orientation even vertical
    check(decorative_vertical_role_none_no_aria,
          ( render_to_string(separator_root([orientation(vertical), decorative(true)]), S3),
            S3 == "<div class=\"px-separator\" data-orientation=\"vertical\" role=\"none\"></div>",
            \+ contains(S3, "aria-orientation") )),

    check(decorative_horizontal_role_none,
          ( render_to_string(separator_root([decorative(true)]), S4),
            S4 == "<div class=\"px-separator\" data-orientation=\"horizontal\" role=\"none\"></div>" )),

    % -- data-orientation is ALWAYS present, decorative or not ---------
    check(data_orientation_always_present,
          ( render_to_string(separator_root([]), S5a), contains(S5a, "data-orientation=\"horizontal\""),
            render_to_string(separator_root([decorative(true)]), S5b), contains(S5b, "data-orientation=\"horizontal\""),
            render_to_string(separator_root([orientation(vertical), decorative(true)]), S5c), contains(S5c, "data-orientation=\"vertical\"") )),

    % -- explicit decorative(false) behaves like the default -----------
    check(explicit_decorative_false_same_as_default,
          ( render_to_string(separator_root([decorative(false)]), S6a),
            render_to_string(separator_root([]), S6b),
            S6a == S6b )),

    % -- invalid orientation/1 falls back to the horizontal default ----
    check(invalid_orientation_falls_back,
          ( render_to_string(separator_root([orientation(diagonal)]), S7),
            contains(S7, "data-orientation=\"horizontal\"") )),

    % -- pass-through attrs survive; class(...) merges with the default
    check(passthrough_id_and_data_attr,
          ( render_to_string(separator_root([id(sep1), data_testid(divider)]), S8),
            contains(S8, "id=\"sep1\""),
            contains(S8, "data-testid=\"divider\"") )),

    check(class_merged_not_replaced,
          ( render_to_string(separator_root([class('my-divider')]), S9),
            contains(S9, "class=\"px-separator my-divider\"") )),

    % -- separator_root/1 (implicit []) == separator_root/2 with [] ----
    check(root_1_matches_root_2_empty,
          ( render_to_string(separator_root([orientation(vertical)]), S10a),
            render_to_string(separator_root([orientation(vertical)], []), S10b),
            S10a == S10b )),

    % -- children pass through (rare, but the anatomy allows it) -------
    check(children_render_inside,
          ( render_to_string(separator_root([], span("|")), S11),
            S11 == "<div class=\"px-separator\" data-orientation=\"horizontal\" role=\"separator\"><span>|</span></div>" )),

    % -- top-level convenience == the Root part for the same args ------
    check(convenience_matches_root_arity_1,
          ( render_to_string(separator([orientation(vertical), decorative(true)]), S12a),
            render_to_string(separator_root([orientation(vertical), decorative(true)]), S12b),
            S12a == S12b )),

    check(convenience_matches_root_arity_2,
          ( render_to_string(separator([id(x)], "mid"), S13a),
            render_to_string(separator_root([id(x)], "mid"), S13b),
            S13a == S13b )),

    % -- demo registration + render (adr/0026 rule 7b) ------------------
    check(demo_registered,
          px_ui:demo(separator, _Order, \separator_demo)),

    check(demo_renders_all_three_variants,
          ( render_to_string(\separator_demo, SDemo),
            contains(SDemo, "Horizontal (default)"),
            contains(SDemo, "Vertical"),
            contains(SDemo, "Decorative"),
            contains(SDemo, "data-orientation=\"horizontal\" role=\"separator\""),
            contains(SDemo, "data-orientation=\"vertical\" role=\"separator\" aria-orientation=\"vertical\""),
            contains(SDemo, "data-orientation=\"vertical\" role=\"none\"") )),

    % show some real output for the record
    render_to_string(\separator_demo, Full),
    format("~n--- rendered separator_demo ---~n~w~n-----------------------------------~n", [Full]).
