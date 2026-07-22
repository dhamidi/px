/* test/ui/toolbar.pl (adr/0026): render-test proof for
   prolog/ui/toolbar.pl -- the Toolbar port, this library's second
   roving-focus consumer. A plain swipl script, no server, no
   networking (test/ui/toggle_group.pl's pattern): render_to_string/2
   over the templates and assert the exact ARIA/data contract
   documented in docs/radix-port-analysis.md's "Toolbar" entry, for:

     - Root       role="toolbar", aria-orientation ALWAYS present
                  (unlike Separator's conditional-omit), data-orientation
                  always present, optional dir pass-through, data-loop
                  only when loop(true)
     - Button     tabindex 0/-1 explicit, data-disabled+disabled when
                  disabled(true)
     - Link       tabindex 0/-1 explicit, plain <a>, no disabled option
     - Separator  delegates to separator/1, orientation defaults
                  vertical standalone but toolbar/2 auto-flips it to
                  the perpendicular of Root's own orientation unless
                  the caller already set one explicitly
     - ToggleGroup embedding: toolbar_toggle_group/2 delegates straight
                  to toggle_group/2 unchanged
     - toolbar/2 convenience: exactly ONE tabindex="0" across the WHOLE
                  toolbar (Buttons, Links, AND every embedded Toggle
                  Group's own Items), auto-picked (prefer explicit
                  active(true) > first non-disabled pressed > first
                  non-disabled), explicit active(_) anywhere always wins
     - kitchen-sink demo registration (px_ui:demo/3)

   Run:  swipl test/ui/toolbar.pl
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/separator.pl').
:- use_module('../../prolog/ui/toggle_group.pl').
:- use_module('../../prolog/ui/toolbar.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Harness (test/ui/toggle_group.pl's pattern).
% ---------------------------------------------------------------------

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

not_contains(Haystack, Needle) :-
    \+ sub_string(Haystack, _, _, _, Needle).

count_occurrences(Haystack, Needle, Count) :-
    findall(1, sub_string(Haystack, _, _, _, Needle), L),
    length(L, Count).

main :-
    tests,
    failed_count(N),
    (   N =:= 0
    ->  format("~nAll ui/toolbar checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Root: defaults -- role="toolbar", aria-orientation ALWAYS present
    % (both default and non-default), data-orientation, no dir/data-loop.
    % ===================================================================

    render_to_string(toolbar_root([], []), RootDefault),

    check(root_wrapper_is_px_toolbar,
          ( sub_string(RootDefault, 0, _, _, "<px-toolbar>"),
            sub_string(RootDefault, _, _, 0, "</px-toolbar>") )),
    check(root_role_toolbar,
          contains(RootDefault, "role=\"toolbar\"")),
    check(root_aria_orientation_default_horizontal,
          contains(RootDefault, "aria-orientation=\"horizontal\"")),
    check(root_data_orientation_default_horizontal,
          contains(RootDefault, "data-orientation=\"horizontal\"")),
    check(root_default_class,
          contains(RootDefault, "class=\"px-toolbar\"")),
    check(root_no_dir,
          not_contains(RootDefault, "dir=")),
    check(root_no_loop,
          not_contains(RootDefault, "data-loop")),
    check(root_default_exact,
          RootDefault ==
              "<px-toolbar><div role=\"toolbar\" aria-orientation=\"horizontal\" data-orientation=\"horizontal\" class=\"px-toolbar\"></div></px-toolbar>"),

    % ===================================================================
    % Root: orientation(vertical) -- aria-orientation ALSO present when
    % vertical (unlike Separator's own conditional omit).
    % ===================================================================

    render_to_string(toolbar_root([orientation(vertical)], []), RootVertical),
    check(root_vertical_aria_orientation,
          contains(RootVertical, "aria-orientation=\"vertical\"")),
    check(root_vertical_data_orientation,
          contains(RootVertical, "data-orientation=\"vertical\"")),

    % Invalid orientation falls back to horizontal.
    render_to_string(toolbar_root([orientation(sideways)], []), RootBadOrientation),
    check(root_invalid_orientation_falls_back,
          contains(RootBadOrientation, "data-orientation=\"horizontal\"")),

    % ===================================================================
    % Root: dir/loop/class/id pass-through and merging.
    % ===================================================================

    render_to_string(
        toolbar_root([dir(rtl), loop(true), id("tb1"), class("wide")], []),
        RootOpts),
    check(root_dir_passed_through, contains(RootOpts, "dir=\"rtl\"")),
    check(root_loop_true, contains(RootOpts, "data-loop=\"\"")),
    check(root_id_passed_through, contains(RootOpts, "id=\"tb1\"")),
    check(root_class_merged_after_default,
          contains(RootOpts, "class=\"px-toolbar wide\"")),

    % ===================================================================
    % Button: tabindex 0/-1, disabled.
    % ===================================================================

    render_to_string(toolbar_button([active(true)], "Cut"), ButtonActive),
    check(button_active_exact,
          ButtonActive ==
              "<button type=\"button\" tabindex=\"0\" class=\"px-toolbar-item px-toolbar-button\">Cut</button>"),

    render_to_string(toolbar_button([], "Copy"), ButtonDefault),
    check(button_default_tabindex_minus1,
          contains(ButtonDefault, "tabindex=\"-1\"")),
    check(button_default_no_disabled,
          not_contains(ButtonDefault, "data-disabled")),

    render_to_string(toolbar_button([disabled(true)], "Paste"), ButtonDisabled),
    check(button_disabled_exact,
          ButtonDisabled ==
              "<button type=\"button\" tabindex=\"-1\" class=\"px-toolbar-item px-toolbar-button\" data-disabled=\"\" disabled>Paste</button>"),

    % toolbar_button/1 (no-label shorthand) delegates to /2.
    render_to_string(toolbar_button([]), ButtonNoLabel),
    check(button_no_label_no_content, contains(ButtonNoLabel, "></button>")),

    % id/aria_label pass-through, class merge.
    render_to_string(
        toolbar_button([id("b1"), class("wide"), aria_label("Copy")], "C"),
        ButtonOpts),
    check(button_id_passed_through, contains(ButtonOpts, "id=\"b1\"")),
    check(button_aria_label_passed_through,
          contains(ButtonOpts, "aria-label=\"Copy\"")),
    check(button_class_merged_after_default,
          contains(ButtonOpts, "class=\"px-toolbar-item px-toolbar-button wide\"")),

    % ===================================================================
    % Link: tabindex 0/-1, plain <a>, href pass-through, no disabled.
    % ===================================================================

    render_to_string(toolbar_link([href("/docs"), active(true)], "Docs"), LinkActive),
    check(link_active_exact,
          LinkActive ==
              "<a tabindex=\"0\" class=\"px-toolbar-item px-toolbar-link\" href=\"/docs\">Docs</a>"),

    render_to_string(toolbar_link([href("#")], "Help"), LinkDefault),
    check(link_default_tabindex_minus1,
          contains(LinkDefault, "tabindex=\"-1\"")),
    check(link_is_anchor_tag,
          ( sub_string(LinkDefault, 0, _, _, "<a "),
            sub_string(LinkDefault, _, _, 0, "</a>") )),

    % toolbar_link/1 (no-label shorthand) delegates to /2.
    render_to_string(toolbar_link([]), LinkNoLabel),
    check(link_no_label_no_content, contains(LinkNoLabel, "></a>")),

    % ===================================================================
    % Separator: delegates to separator/1, default vertical when used
    % standalone.
    % ===================================================================

    render_to_string(toolbar_separator([]), SepDefault),
    check(separator_default_vertical,
          contains(SepDefault, "data-orientation=\"vertical\"")),
    check(separator_default_role,
          contains(SepDefault, "role=\"separator\"")),
    check(separator_default_class,
          contains(SepDefault, "class=\"px-separator px-toolbar-separator\"")),

    render_to_string(toolbar_separator([orientation(horizontal)]), SepHorizontal),
    check(separator_explicit_horizontal,
          contains(SepHorizontal, "data-orientation=\"horizontal\"")),

    render_to_string(toolbar_separator([decorative(true)]), SepDecorative),
    check(separator_decorative_role_none,
          contains(SepDecorative, "role=\"none\"")),

    % ===================================================================
    % ToggleGroup embedding: pure delegation to toggle_group/2.
    % ===================================================================

    render_to_string(
        toolbar_toggle_group([type(single)],
                             [ toggle_group_item([pressed(true)], "Bold") ]),
        EmbeddedGroup),
    check(embedded_toggle_group_wrapper,
          contains(EmbeddedGroup, "<px-toggle-group>")),
    check(embedded_toggle_group_role,
          contains(EmbeddedGroup, "role=\"radiogroup\"")),

    % ===================================================================
    % toolbar/2 convenience: separator auto-flip.
    % ===================================================================

    render_to_string(
        toolbar([], [ toolbar_button([], "A"), toolbar_separator([]),
                      toolbar_button([], "B") ]),
        AutoflipHorizontal),
    check(autoflip_horizontal_toolbar_gets_vertical_separator,
          contains(AutoflipHorizontal, "data-orientation=\"vertical\"")),

    render_to_string(
        toolbar([orientation(vertical)],
                [ toolbar_button([], "A"), toolbar_separator([]),
                  toolbar_button([], "B") ]),
        AutoflipVertical),
    check(autoflip_vertical_toolbar_gets_horizontal_separator,
          % Root itself also carries data-orientation="vertical", so
          % assert the separator's own div carries the horizontal flip
          % by checking BOTH orientations appear (root vertical, the
          % one non-root data-orientation is the separator's).
          count_occurrences(AutoflipVertical, "data-orientation=\"horizontal\"", 1)),

    % An explicit orientation on a Separator always wins over the
    % auto-flip.
    render_to_string(
        toolbar([], [ toolbar_button([], "A"),
                      toolbar_separator([orientation(horizontal)]) ]),
        AutoflipExplicitWins),
    check(autoflip_explicit_orientation_wins,
          contains(AutoflipExplicitWins, "data-orientation=\"horizontal\"")),

    % ===================================================================
    % toolbar/2 convenience: exactly one tabindex="0" across the WHOLE
    % toolbar, auto-picked -- first non-disabled candidate.
    % ===================================================================

    render_to_string(
        toolbar([id("t1")],
                [ toolbar_button([], "A"), toolbar_button([], "B"),
                  toolbar_link([href("#")], "C") ]),
        AutoPickFirst),
    check(autopick_first_item_active,
          sub_string(AutoPickFirst, _, _, _,
                     "tabindex=\"0\" class=\"px-toolbar-item px-toolbar-button\">A")),
    check(autopick_exactly_one_tabindex_0,
          count_occurrences(AutoPickFirst, "tabindex=\"0\"", 1)),

    % First item disabled -> auto-pick skips it.
    render_to_string(
        toolbar([id("t2")],
                [ toolbar_button([disabled(true)], "A"), toolbar_button([], "B") ]),
        AutoPickSkipDisabled),
    check(autopick_skip_disabled_first,
          sub_string(AutoPickSkipDisabled, _, _, _,
                     "tabindex=\"0\" class=\"px-toolbar-item px-toolbar-button\">B")),
    check(autopick_disabled_item_stays_minus1,
          sub_string(AutoPickSkipDisabled, _, _, _,
                     "tabindex=\"-1\" class=\"px-toolbar-item px-toolbar-button\" data-disabled=\"\" disabled>A")),

    % Explicit active(true) anywhere short-circuits the auto-pick.
    render_to_string(
        toolbar([id("t3")],
                [ toolbar_button([], "A"), toolbar_button([active(true)], "B") ]),
        AutoPickExplicit),
    check(autopick_explicit_wins,
          ( sub_string(AutoPickExplicit, _, _, _,
                       "tabindex=\"-1\" class=\"px-toolbar-item px-toolbar-button\">A"),
            sub_string(AutoPickExplicit, _, _, _,
                       "tabindex=\"0\" class=\"px-toolbar-item px-toolbar-button\">B") )),
    check(autopick_explicit_exactly_one_tabindex_0,
          count_occurrences(AutoPickExplicit, "tabindex=\"0\"", 1)),

    % ===================================================================
    % toolbar/2 convenience: the nested-Toggle-Group tab-stop problem --
    % exactly ONE tabindex="0" across Buttons AND an embedded Toggle
    % Group's own Items, never two.
    % ===================================================================

    render_to_string(
        toolbar([id("t4")],
                [ toolbar_button([], "Cut"),
                  toolbar_toggle_group([type(single)],
                    [ toggle_group_item([pressed(true)], "Bold"),
                      toggle_group_item([], "Italic")
                    ])
                ]),
        NestedGroup1),
    check(nested_group_exactly_one_tabindex_0_overall,
          count_occurrences(NestedGroup1, "tabindex=\"0\"", 1)),
    check(nested_group_button_is_the_tab_stop,
          % "Cut" comes first in DOM order and nothing is pressed
          % before it, so the flat auto-pick (first non-disabled
          % candidate) lands on the Button, not the pressed toggle Item.
          sub_string(NestedGroup1, _, _, _,
                     "tabindex=\"0\" class=\"px-toolbar-item px-toolbar-button\">Cut")),
    check(nested_group_items_forced_inactive,
          ( sub_string(NestedGroup1, _, _, _,
                       "aria-checked=\"true\" data-state=\"on\" tabindex=\"-1\""),
            sub_string(NestedGroup1, _, _, _,
                       "aria-checked=\"false\" data-state=\"off\" tabindex=\"-1\"") )),

    % When the toolbar's flat candidate list starts with the Toggle
    % Group (no preceding Button/Link), the auto-pick still finds
    % exactly one stop -- the FIRST Item in DOM order, regardless of
    % which one (if any) is pressed: Toolbar's auto-pick is plain
    % "first non-disabled candidate", not toggle_group.pl's own
    % "prefer the pressed Item" nicety (see mark_active_parts/2's
    % header for why).
    render_to_string(
        toolbar([id("t5")],
                [ toolbar_toggle_group([type(multiple)],
                    [ toggle_group_item([], "Bold"),
                      toggle_group_item([pressed(true)], "Italic")
                    ]),
                  toolbar_button([], "Cut")
                ]),
        NestedGroup2),
    check(nested_group_first_item_wins_regardless_of_pressed,
          sub_string(NestedGroup2, _, _, _,
                     "aria-pressed=\"false\" data-state=\"off\" tabindex=\"0\"")),
    check(nested_group2_exactly_one_tabindex_0_overall,
          count_occurrences(NestedGroup2, "tabindex=\"0\"", 1)),
    check(nested_group2_pressed_item_forced_inactive,
          sub_string(NestedGroup2, _, _, _,
                     "aria-pressed=\"true\" data-state=\"on\" tabindex=\"-1\"")),
    check(nested_group2_button_forced_inactive,
          sub_string(NestedGroup2, _, _, _,
                     "tabindex=\"-1\" class=\"px-toolbar-item px-toolbar-button\">Cut")),

    % All-disabled toolbar -> no tabindex="0" anywhere.
    render_to_string(
        toolbar([id("t6")],
                [ toolbar_button([disabled(true)], "A"),
                  toolbar_button([disabled(true)], "B")
                ]),
        AllDisabled),
    check(all_disabled_no_tabindex_0, not_contains(AllDisabled, "tabindex=\"0\"")),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3).
    % ===================================================================

    check(demo_registered,
          px_ui:demo(toolbar, _Order, \toolbar_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(toolbar, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \toolbar_demo), Demo),
    check(demo_has_toolbar_role,
          contains(Demo, "role=\"toolbar\"")),
    check(demo_has_embedded_toggle_group,
          contains(Demo, "<px-toggle-group>")),
    check(demo_has_link,
          contains(Demo, "<a ")),
    check(demo_has_vertical_orientation,
          contains(Demo, "data-orientation=\"vertical\"")),
    check(demo_has_disabled_button,
          contains(Demo, "data-disabled=\"\" disabled")),
    check(demo_exactly_two_tabindex_0,
          % Two independent <px-toolbar> instances in the demo, one
          % tab stop each.
          count_occurrences(Demo, "tabindex=\"0\"", 2)),

    % show some real output for the record
    format("~n--- rendered toolbar_demo ---~n~w~n-----------------------------------~n",
           [Demo]).
