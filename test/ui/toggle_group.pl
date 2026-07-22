/* test/ui/toggle_group.pl (adr/0026): render-test proof for
   prolog/ui/toggle_group.pl -- the Toggle Group port, this library's
   first roving-focus consumer. A plain swipl script, no server, no
   networking (milestone10_templates.pl's / test/ui/toggle.pl's
   pattern): render_to_string/2 over the templates and assert the
   exact ARIA/data contract documented in docs/radix-port-analysis.md's
   "Toggle Group" entry, for:

     - type(single)    role="radiogroup", role="radio" + aria-checked
                        per Item, at most one pressed
     - type(multiple)  role="toolbar", aria-pressed + data-state per
                        Item, independent
     - disabled Item    data-disabled="" + native disabled, excluded
                        from the auto-picked active/tab-stop Item
     - disabled Root    data-disabled="" on Root only, no propagation
     - orientation(vertical)  data-orientation="vertical"
     - loop(true)       data-loop=""
     - tabindex 0/-1    exactly one non-disabled Item gets tabindex="0"
                        per group (auto-picked: first pressed
                        non-disabled Item, else first non-disabled)
     - active(true) caller override short-circuits the auto-pick

   plus the convenience `toggle_group/2` wrapper (type-injection,
   class merging, option pass-through), the two required-option guards
   (`type` on both Root and Item), and the kitchen-sink demo
   registration (px_ui:demo/3) rendering end to end exactly as
   prolog/px_ui.pl's ui_show_view embeds it (`\Goal` as a div's
   Children, not the bare atom -- adr/0019's arity-0 dispatch rule).
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/toggle_group.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Harness (milestone10_templates.pl's / test/ui/toggle.pl's pattern).
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
    ->  format("~nAll ui/toggle_group checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Root: type(single) -- role="radiogroup", data-orientation default
    % horizontal, no data-loop/data-disabled by default.
    % ===================================================================

    render_to_string(toggle_group_root([type(single)], []), RootSingle),

    check(root_single_wrapper_is_px_toggle_group,
          ( sub_string(RootSingle, 0, _, _, "<px-toggle-group>"),
            sub_string(RootSingle, _, _, 0, "</px-toggle-group>") )),
    check(root_single_role_radiogroup,
          contains(RootSingle, "role=\"radiogroup\"")),
    check(root_single_orientation_default_horizontal,
          contains(RootSingle, "data-orientation=\"horizontal\"")),
    check(root_single_default_class,
          contains(RootSingle, "class=\"px-toggle-group\"")),
    check(root_single_no_loop,
          not_contains(RootSingle, "data-loop")),
    check(root_single_no_disabled,
          not_contains(RootSingle, "data-disabled")),
    check(root_single_exact,
          RootSingle ==
              "<px-toggle-group><div role=\"radiogroup\" data-orientation=\"horizontal\" class=\"px-toggle-group\"></div></px-toggle-group>"),

    % ===================================================================
    % Root: type(multiple) -- role="toolbar".
    % ===================================================================

    render_to_string(toggle_group_root([type(multiple)], []), RootMultiple),
    check(root_multiple_role_toolbar,
          contains(RootMultiple, "role=\"toolbar\"")),

    % ===================================================================
    % Root: missing type(_) is a hard error -- no sane default between
    % mutually-exclusive-select and independent-select.
    % ===================================================================

    check(root_missing_type_throws,
          catch((render_to_string(toggle_group_root([], []), _), fail),
                error(existence_error(option, type), _),
                true)),

    % ===================================================================
    % Root: orientation(vertical), loop(true), disabled(true) -- each
    % independently, plus id/class pass-through and merging.
    % ===================================================================

    render_to_string(
        toggle_group_root([type(single), orientation(vertical), loop(true),
                            disabled(true), id("tg1"), class("wide")],
                           []),
        RootOpts),

    check(root_orientation_vertical,
          contains(RootOpts, "data-orientation=\"vertical\"")),
    check(root_loop_true,
          contains(RootOpts, "data-loop=\"\"")),
    check(root_disabled_true,
          contains(RootOpts, "data-disabled=\"\"")),
    check(root_id_passed_through,
          contains(RootOpts, "id=\"tg1\"")),
    check(root_class_merged_after_default,
          contains(RootOpts, "class=\"px-toggle-group wide\"")),

    % orientation(vertical) is threaded, but an unrecognised value
    % falls back to the default -- same guard as separator.pl/
    % radio_group.pl's own orientation_opt/2.
    render_to_string(toggle_group_root([type(single), orientation(sideways)], []),
                      RootBadOrientation),
    check(root_invalid_orientation_falls_back,
          contains(RootBadOrientation, "data-orientation=\"horizontal\"")),

    % ===================================================================
    % Item: type(single) -- role="radio" + aria-checked, no aria-pressed.
    % ===================================================================

    render_to_string(toggle_group_item([type(single), pressed(true), active(true)],
                                        "Left"),
                      ItemSingleOn),

    check(item_single_role_radio,
          contains(ItemSingleOn, "role=\"radio\"")),
    check(item_single_aria_checked_true,
          contains(ItemSingleOn, "aria-checked=\"true\"")),
    check(item_single_no_aria_pressed,
          not_contains(ItemSingleOn, "aria-pressed")),
    check(item_single_data_state_on,
          contains(ItemSingleOn, "data-state=\"on\"")),
    check(item_single_tabindex_0,
          contains(ItemSingleOn, "tabindex=\"0\"")),
    check(item_single_exact,
          ItemSingleOn ==
              "<button type=\"button\" role=\"radio\" aria-checked=\"true\" data-state=\"on\" tabindex=\"0\" class=\"px-toggle-group-item\">Left</button>"),

    render_to_string(toggle_group_item([type(single)], "Right"), ItemSingleOff),
    check(item_single_default_pressed_false,
          ( contains(ItemSingleOff, "aria-checked=\"false\""),
            contains(ItemSingleOff, "data-state=\"off\""),
            contains(ItemSingleOff, "tabindex=\"-1\"") )),

    % ===================================================================
    % Item: type(multiple) -- aria-pressed + data-state, no role/
    % aria-checked.
    % ===================================================================

    render_to_string(toggle_group_item([type(multiple), pressed(true)], "Bold"),
                      ItemMultipleOn),

    check(item_multiple_aria_pressed_true,
          contains(ItemMultipleOn, "aria-pressed=\"true\"")),
    check(item_multiple_no_role,
          not_contains(ItemMultipleOn, "role=")),
    check(item_multiple_no_aria_checked,
          not_contains(ItemMultipleOn, "aria-checked")),
    check(item_multiple_data_state_on,
          contains(ItemMultipleOn, "data-state=\"on\"")),

    render_to_string(toggle_group_item([type(multiple)], "X"), ItemMultipleOff),
    check(item_multiple_exact,
          ItemMultipleOff ==
              "<button type=\"button\" aria-pressed=\"false\" data-state=\"off\" tabindex=\"-1\" class=\"px-toggle-group-item\">X</button>"),

    % ===================================================================
    % Item: missing type(_) is a hard error.
    % ===================================================================

    check(item_missing_type_throws,
          catch((render_to_string(toggle_group_item([], "X"), _), fail),
                error(existence_error(option, type), _),
                true)),

    % ===================================================================
    % Item: disabled(true) -- data-disabled="" plus native disabled,
    % independent of pressed/type.
    % ===================================================================

    render_to_string(toggle_group_item([type(multiple), disabled(true)], "X"),
                      ItemDisabled),
    check(item_disabled_exact,
          ItemDisabled ==
              "<button type=\"button\" aria-pressed=\"false\" data-state=\"off\" tabindex=\"-1\" class=\"px-toggle-group-item\" data-disabled=\"\" disabled>X</button>"),

    % Item: class merge + pass-through (id, aria_label).
    render_to_string(
        toggle_group_item([type(multiple), id("it1"), class("wide"),
                            aria_label("Bold")], "B"),
        ItemOpts),
    check(item_id_passed_through, contains(ItemOpts, "id=\"it1\"")),
    check(item_aria_label_passed_through,
          contains(ItemOpts, "aria-label=\"Bold\"")),
    check(item_class_merged_after_default,
          contains(ItemOpts, "class=\"px-toggle-group-item wide\"")),

    % `toggle_group_item/1` (no-label shorthand) delegates to `/2`.
    render_to_string(toggle_group_item([type(multiple)]), ItemNoLabel),
    check(item_no_label_no_content,
          contains(ItemNoLabel, "></button>")),

    % ===================================================================
    % Convenience `toggle_group/2`: type threaded onto every Item
    % (overriding any per-Item value), auto-picked active Item.
    % ===================================================================

    render_to_string(
        toggle_group([id("g1"), type(single)],
                     [ toggle_group_item([pressed(true)], "A"),
                       toggle_group_item([], "B"),
                       toggle_group_item([disabled(true)], "C")
                     ]),
        GroupSingle),

    check(group_single_root_role,
          contains(GroupSingle, "role=\"radiogroup\"")),
    check(group_single_items_get_role_radio,
          count_occurrences(GroupSingle, "role=\"radio\"", 3)),
    check(group_single_one_pressed,
          count_occurrences(GroupSingle, "aria-checked=\"true\"", 1)),
    check(group_single_pressed_item_is_active,
          % The pressed, non-disabled Item ("A") is the auto-picked
          % tab stop: aria-checked="true" and tabindex="0" both land
          % on the same (first, "A") button.
          sub_string(GroupSingle, _, _, _,
                     "aria-checked=\"true\" data-state=\"on\" tabindex=\"0\"")),
    check(group_single_exactly_one_tabindex_0,
          count_occurrences(GroupSingle, "tabindex=\"0\"", 1)),
    check(group_single_disabled_item_stays_tabindex_minus1,
          sub_string(GroupSingle, _, _, _,
                     "tabindex=\"-1\" class=\"px-toggle-group-item\" data-disabled=\"\" disabled>C")),

    % No Item is pressed -> the first non-disabled Item ("A") is
    % auto-picked active instead.
    render_to_string(
        toggle_group([id("g2"), type(multiple)],
                     [ toggle_group_item([], "A"),
                       toggle_group_item([], "B")
                     ]),
        GroupNoPressed),
    check(group_no_pressed_first_item_active,
          sub_string(GroupNoPressed, _, _, _,
                     "tabindex=\"0\" class=\"px-toggle-group-item\">A")),
    check(group_no_pressed_second_item_inactive,
          sub_string(GroupNoPressed, _, _, _,
                     "tabindex=\"-1\" class=\"px-toggle-group-item\">B")),

    % First Item disabled -> the auto-pick skips it, lands on the next
    % non-disabled Item instead.
    render_to_string(
        toggle_group([id("g3"), type(multiple)],
                     [ toggle_group_item([disabled(true)], "A"),
                       toggle_group_item([], "B")
                     ]),
        GroupFirstDisabled),
    check(group_first_disabled_skipped,
          ( sub_string(GroupFirstDisabled, _, _, _,
                       "tabindex=\"-1\" class=\"px-toggle-group-item\" data-disabled=\"\" disabled>A"),
            sub_string(GroupFirstDisabled, _, _, _,
                       "tabindex=\"0\" class=\"px-toggle-group-item\">B") )),

    % Every Item disabled -> no auto-pick at all, every tabindex stays -1.
    render_to_string(
        toggle_group([id("g4"), type(multiple)],
                     [ toggle_group_item([disabled(true)], "A"),
                       toggle_group_item([disabled(true)], "B")
                     ]),
        GroupAllDisabled),
    check(group_all_disabled_no_tabindex_0,
          not_contains(GroupAllDisabled, "tabindex=\"0\"")),
    check(group_all_disabled_both_minus1,
          count_occurrences(GroupAllDisabled, "tabindex=\"-1\"", 2)),

    % Explicit `active(true)` on a specific Item short-circuits the
    % auto-pick entirely, even overriding a pressed Item elsewhere.
    render_to_string(
        toggle_group([id("g5"), type(single)],
                     [ toggle_group_item([pressed(true)], "A"),
                       toggle_group_item([active(true)], "B")
                     ]),
        GroupExplicitActive),
    check(group_explicit_active_wins,
          ( sub_string(GroupExplicitActive, _, _, _,
                       "tabindex=\"-1\" class=\"px-toggle-group-item\">A"),
            sub_string(GroupExplicitActive, _, _, _,
                       "tabindex=\"0\" class=\"px-toggle-group-item\">B") )),

    % `type` on an Item is always overridden by the group's own type,
    % never left to whatever the caller happened to pass locally.
    render_to_string(
        toggle_group([id("g6"), type(multiple)],
                     [ toggle_group_item([type(single), pressed(true)], "A") ]),
        GroupTypeOverride),
    check(group_type_always_overridden,
          ( contains(GroupTypeOverride, "aria-pressed=\"true\""),
            not_contains(GroupTypeOverride, "role=\"radio\"") )),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Call` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(toggle_group, _Order, \toggle_group_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(toggle_group, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \toggle_group_demo), Demo),
    check(demo_has_four_groups,
          count_occurrences(Demo, "<px-toggle-group>", 4)),
    check(demo_has_radiogroup_and_toolbar,
          ( contains(Demo, "role=\"radiogroup\""),
            contains(Demo, "role=\"toolbar\"") )),
    check(demo_has_vertical_orientation,
          contains(Demo, "data-orientation=\"vertical\"")),
    check(demo_has_disabled_item,
          contains(Demo, "data-disabled=\"\" disabled")),
    check(demo_has_pressed_and_unpressed,
          ( contains(Demo, "data-state=\"on\""),
            contains(Demo, "data-state=\"off\"") )),

    % show some real output for the record
    format("~n--- rendered toggle_group_demo ---~n~w~n-----------------------------------~n",
           [Demo]).
