/* ui/visually_hidden (adr/0026): the render-contract test required by
   rule 7a. A plain swipl script -- no server, no networking -- loading
   px_template.pl and prolog/ui/visually_hidden.pl directly (NOT through
   px_ui.pl's directory scan, so this test's outcome depends only on
   this component's own file, not on whatever else happens to be under
   prolog/ui/ at the moment it runs) and exercising render_to_string/2
   over the templates and the registered demo, same harness shape as
   test/milestone10_templates.pl / test/ui/aspect_ratio.pl.

   Covers:
     - visually_hidden_root/2 emits exactly one <span
       class="px-visually-hidden"> wrapping its children -- no role,
       no aria-*, per the analysis doc's "DOM/ARIA: none" contract
     - Opts (extra attrs: id, data_*, ...) survive, rendered alongside
       the fixed class
     - children can be an element, not just text
     - visually_hidden/2 (top-level convenience) renders identically to
       visually_hidden_root/2 for the same Opts/Children
     - the component registers px_ui:demo(visually_hidden, _, \Goal)
       -- the explicit \Goal escape, NOT a bare atom (a bare atom is a
       TEXT NODE in px_template's dispatch -- render_to_string(bare_atom,
       S) would literally render the atom's name as text instead of
       calling the template; this test asserts the registered Call
       actually renders through, catching that class of registration
       bug) -- and that demo renders the icon-button pattern: the
       hidden label text, the .px-visually-hidden class, and the
       decorative checkmark icon marked aria-hidden/focusable=false

   Run:  swipl test/ui/visually_hidden.pl
*/

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../../prolog/px_template'],       TemplateSpec),
   atomic_list_concat([Dir, '/../../prolog/ui/visually_hidden'], VhSpec),
   use_module(TemplateSpec),
   use_module(VhSpec).

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
    ->  format("~nAll ui/visually_hidden checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

		 /*******************************
		 *             TESTS            *
		 *******************************/

tests :-
    % -- exact markup: one span, the fixed class, no role/aria-* -------
    check(root_exact_markup,
          ( render_to_string(visually_hidden_root([], "secret text"), S1),
            S1 == "<span class=\"px-visually-hidden\">secret text</span>" )),

    % -- no stray role/aria-* ever emitted (DOM/ARIA: none) -------------
    check(no_role_or_aria,
          ( render_to_string(visually_hidden_root([], "x"), S2),
            \+ contains(S2, "role="),
            \+ contains(S2, "aria-") )),

    % -- Opts (extra attrs) survive, alongside the fixed class ----------
    check(passthrough_id_and_data_attr,
          ( render_to_string(visually_hidden_root([id(vh1), data_test(one)], "y"), S3),
            contains(S3, "class=\"px-visually-hidden\""),
            contains(S3, "id=\"vh1\""),
            contains(S3, "data-test=\"one\"") )),

    % -- children can be an element, not just text ----------------------
    check(element_children_render_inside,
          ( render_to_string(visually_hidden_root([], em("Loading")), S4),
            S4 == "<span class=\"px-visually-hidden\"><em>Loading</em></span>" )),

    % -- top-level convenience == the Root part for the same args ------
    check(convenience_matches_root,
          ( render_to_string(visually_hidden([id(a)], "z"), SA),
            render_to_string(visually_hidden_root([id(a)], "z"), SB),
            SA == SB )),

    % -- text is escaped like any other text node -----------------------
    check(text_escaped,
          ( render_to_string(visually_hidden_root([], "a & b < c"), S5),
            contains(S5, "a &amp; b &lt; c") )),

    % -- demo registration uses the \Goal escape, not a bare atom -------
    check(demo_registered_as_explicit_escape,
          ( px_ui:demo(visually_hidden, _Order, Call),
            Call = \_Goal )),

    % -- demo actually renders through (catches the bare-atom-registration
    %    pitfall: a bare atom Call would render as literal text instead) -
    check(demo_renders_icon_button_pattern,
          ( px_ui:demo(visually_hidden, _Order2, Call2),
            render_to_string(Call2, SDemo),
            contains(SDemo, "class=\"px-visually-hidden\""),
            contains(SDemo, "Mark task as complete"),
            contains(SDemo, "class=\"px-icon-button\""),
            contains(SDemo, "<svg "),
            contains(SDemo, "aria-hidden=\"true\""),
            contains(SDemo, "focusable=\"false\"") )),

    % show some real output for the record
    px_ui:demo(visually_hidden, _Order3, Call3),
    render_to_string(Call3, Full),
    format("~n--- rendered visually_hidden_demo ---~n~w~n--------------------------------------~n", [Full]).
