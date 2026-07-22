/* ui/accessible_icon (adr/0026): the render-contract test required by
   rule 7a. A plain swipl script -- no server, no networking -- loading
   px_template.pl and prolog/ui/accessible_icon.pl directly (which in
   turn loads prolog/ui/visually_hidden.pl, its one declared dependency
   -- NOT through px_ui.pl's directory scan, so this test's outcome
   depends only on this component and the one module it actually
   depends on, not on whatever else happens to be under prolog/ui/ at
   the moment it runs), exercising render_to_string/2 over the
   templates and the registered demo, same harness shape as
   test/milestone10_templates.pl / test/ui/aspect_ratio.pl.

   Covers:
     - accessible_icon_root/3 emits exactly TWO sibling nodes -- no
       wrapping container of its own, matching Radix's own Fragment
       output (icon + hidden label, not <div><icon/><label/></div>):
         1. the icon term wrapped in <span aria-hidden="true">
         2. a visually-hidden <span class="px-visually-hidden"> with
            the label TEXT (the accessible name comes from text
            content, not aria-label, per the analysis doc's contract)
     - Opts (extra attrs) land on the icon wrapper span, since there is
       no separate Root container to put them on
     - the icon term can be any renderable body term (an element, or a
       raw/1 SVG string)
     - accessible_icon/3 (top-level convenience) renders identically to
       accessible_icon_root/3 for the same args
     - the component registers px_ui:demo(accessible_icon, _, \Goal)
       -- the explicit \Goal escape, not a bare atom (see
       test/ui/visually_hidden.pl's header for why that distinction
       matters) -- and that demo renders the same icon-button pattern
       as the visually_hidden demo, built via one accessible_icon/3
       call instead of by hand

   Run:  swipl test/ui/accessible_icon.pl
*/

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../../prolog/px_template'],        TemplateSpec),
   atomic_list_concat([Dir, '/../../prolog/ui/accessible_icon'], AiSpec),
   use_module(TemplateSpec),
   use_module(AiSpec).

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
    ->  format("~nAll ui/accessible_icon checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

		 /*******************************
		 *             TESTS            *
		 *******************************/

tests :-
    % -- exact markup: two siblings, no wrapping container --------------
    check(root_exact_markup,
          ( render_to_string(accessible_icon_root([], span("X"), "Close"), S1),
            S1 == "<span aria-hidden=\"true\"><span>X</span></span><span class=\"px-visually-hidden\">Close</span>" )),

    % -- the label is TEXT content, never aria-label ---------------------
    check(label_is_text_content_not_aria_label,
          ( render_to_string(accessible_icon_root([], span("X"), "Close"), S2),
            contains(S2, ">Close<"),
            \+ contains(S2, "aria-label") )),

    % -- Opts land on the icon wrapper span (no separate Root node) -----
    check(opts_land_on_icon_wrapper,
          ( render_to_string(accessible_icon_root([id(ic1), class(spin)], span("X"), "Close"), S3),
            contains(S3, "<span aria-hidden=\"true\" id=\"ic1\" class=\"spin\">"),
            contains(S3, "<span class=\"px-visually-hidden\">Close</span>") )),

    % -- the icon term can be arbitrary renderable content: raw/1 SVG ---
    check(icon_term_can_be_raw_svg,
          ( render_to_string(
                accessible_icon_root([], raw("<svg><path d=\"M0 0\"/></svg>"), "Save"),
                S4),
            S4 == "<span aria-hidden=\"true\"><svg><path d=\"M0 0\"/></svg></span><span class=\"px-visually-hidden\">Save</span>" )),

    % -- top-level convenience == the Root part for the same args -------
    check(convenience_matches_root,
          ( render_to_string(accessible_icon([id(a)], span("X"), "Close"), SA),
            render_to_string(accessible_icon_root([id(a)], span("X"), "Close"), SB),
            SA == SB )),

    % -- label text is escaped like any other text node ------------------
    check(label_escaped,
          ( render_to_string(accessible_icon_root([], span("X"), "a & b"), S5),
            contains(S5, "a &amp; b") )),

    % -- demo registration uses the \Goal escape, not a bare atom -------
    check(demo_registered_as_explicit_escape,
          ( px_ui:demo(accessible_icon, _Order, Call),
            Call = \_Goal )),

    % -- demo actually renders through (catches the bare-atom-registration
    %    pitfall: a bare atom Call would render as literal text instead) -
    check(demo_renders_icon_button_pattern,
          ( px_ui:demo(accessible_icon, _Order2, Call2),
            render_to_string(Call2, SDemo),
            contains(SDemo, "aria-hidden=\"true\""),
            contains(SDemo, "class=\"px-visually-hidden\""),
            contains(SDemo, "Mark task as complete"),
            contains(SDemo, "class=\"px-icon-button\""),
            contains(SDemo, "<svg "),
            contains(SDemo, "focusable=\"false\"") )),

    % show some real output for the record
    px_ui:demo(accessible_icon, _Order3, Call3),
    render_to_string(Call3, Full),
    format("~n--- rendered accessible_icon_demo ---~n~w~n---------------------------------------~n", [Full]).
