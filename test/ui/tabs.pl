/* test/ui/tabs.pl (adr/0026): render-test proof for prolog/ui/tabs.pl
   -- the Tabs port, this library's second roving-focus consumer. A
   plain swipl script, no server, no networking
   (test/ui/toggle_group.pl's own pattern): render_to_string/2 over the
   templates and assert the exact ARIA/data contract documented in
   docs/radix-port-analysis.md's "Tabs" entry, for:

     - tabs_root/2      data-orientation, class merge/pass-through
     - tabs_list/2      role="tablist", aria-orientation, data-loop
     - tabs_trigger/1,2 role="tab", aria-selected, data-state,
                        aria-controls, tabindex 0/-1, disabled
     - tabs_content/1,2 role="tabpanel", aria-labelledby, data-state,
                        data-orientation, hidden on inactive, tabindex
                        always "0"
     - tabs/2           the full id-wiring between a Trigger and its
                        Content (aria-controls/id and
                        aria-labelledby/id each matching), value(_)
                        matching to pick the selected item, disabled
                        item forwarding, orientation forwarding to
                        List/Content, loop(true) default, vertical
                        variant
     - the kitchen-sink demo registration (px_ui:demo/3) rendering end
       to end exactly as prolog/px_ui.pl's ui_show_view embeds it
       (`\Goal` as a div's Children, not the bare atom -- adr/0019's
       arity-0 dispatch rule)

   plus the two required-option guards (`value` on both `tabs/2` and
   its per-item `tabs_item/3`).
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/tabs.pl').

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
    ->  format("~nAll ui/tabs checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Root: data-orientation default horizontal, class merge.
    % ===================================================================

    render_to_string(tabs_root([], []), RootDefault),

    check(root_wrapper_is_px_tabs,
          ( sub_string(RootDefault, 0, _, _, "<px-tabs>"),
            sub_string(RootDefault, _, _, 0, "</px-tabs>") )),
    check(root_orientation_default_horizontal,
          contains(RootDefault, "data-orientation=\"horizontal\"")),
    check(root_default_class,
          contains(RootDefault, "class=\"px-tabs\"")),
    check(root_exact,
          RootDefault ==
              "<px-tabs><div data-orientation=\"horizontal\" class=\"px-tabs\"></div></px-tabs>"),

    render_to_string(
        tabs_root([orientation(vertical), id("t1"), class("wide")], []),
        RootOpts),
    check(root_orientation_vertical,
          contains(RootOpts, "data-orientation=\"vertical\"")),
    check(root_id_passed_through,
          contains(RootOpts, "id=\"t1\"")),
    check(root_class_merged_after_default,
          contains(RootOpts, "class=\"px-tabs wide\"")),

    render_to_string(tabs_root([orientation(sideways)], []), RootBadOrientation),
    check(root_invalid_orientation_falls_back,
          contains(RootBadOrientation, "data-orientation=\"horizontal\"")),

    % ===================================================================
    % List: role="tablist", aria-orientation, data-loop.
    % ===================================================================

    render_to_string(tabs_list([], []), ListDefault),
    check(list_role_tablist,
          contains(ListDefault, "role=\"tablist\"")),
    check(list_aria_orientation_default_horizontal,
          contains(ListDefault, "aria-orientation=\"horizontal\"")),
    check(list_loop_default_true,
          contains(ListDefault, "data-loop=\"\"")),
    check(list_default_class,
          contains(ListDefault, "class=\"px-tabs-list\"")),

    render_to_string(tabs_list([loop(false)], []), ListNoLoop),
    check(list_loop_false_omitted,
          not_contains(ListNoLoop, "data-loop")),

    render_to_string(tabs_list([orientation(vertical)], []), ListVertical),
    check(list_aria_orientation_vertical,
          contains(ListVertical, "aria-orientation=\"vertical\"")),

    % ===================================================================
    % Trigger: role="tab", aria-selected, data-state, aria-controls,
    % tabindex 0/-1, disabled.
    % ===================================================================

    render_to_string(
        tabs_trigger([selected(true), controls("panel1")], "Account"),
        TriggerSelected),
    check(trigger_role_tab,
          contains(TriggerSelected, "role=\"tab\"")),
    check(trigger_aria_selected_true,
          contains(TriggerSelected, "aria-selected=\"true\"")),
    check(trigger_data_state_active,
          contains(TriggerSelected, "data-state=\"active\"")),
    check(trigger_aria_controls,
          contains(TriggerSelected, "aria-controls=\"panel1\"")),
    check(trigger_tabindex_0,
          contains(TriggerSelected, "tabindex=\"0\"")),
    check(trigger_selected_exact,
          TriggerSelected ==
              "<button type=\"button\" role=\"tab\" aria-selected=\"true\" aria-controls=\"panel1\" data-state=\"active\" tabindex=\"0\" class=\"px-tabs-trigger\">Account</button>"),

    render_to_string(tabs_trigger([], "Billing"), TriggerDefault),
    check(trigger_default_unselected,
          ( contains(TriggerDefault, "aria-selected=\"false\""),
            contains(TriggerDefault, "data-state=\"inactive\""),
            contains(TriggerDefault, "tabindex=\"-1\""),
            not_contains(TriggerDefault, "aria-controls") )),

    render_to_string(tabs_trigger([disabled(true)], "Billing"), TriggerDisabled),
    check(trigger_disabled_exact,
          TriggerDisabled ==
              "<button type=\"button\" role=\"tab\" aria-selected=\"false\" data-state=\"inactive\" tabindex=\"-1\" class=\"px-tabs-trigger\" data-disabled=\"\" disabled>Billing</button>"),

    % `tabs_trigger/1` (no-label shorthand) delegates to `/2`.
    render_to_string(tabs_trigger([]), TriggerNoLabel),
    check(trigger_no_label_no_content,
          contains(TriggerNoLabel, "></button>")),

    % id / aria_label pass-through, class merge.
    render_to_string(
        tabs_trigger([id("tr1"), class("wide"), aria_label("Account tab")],
                     "Account"),
        TriggerOptsPassthrough),
    check(trigger_id_passed_through,
          contains(TriggerOptsPassthrough, "id=\"tr1\"")),
    check(trigger_aria_label_passed_through,
          contains(TriggerOptsPassthrough, "aria-label=\"Account tab\"")),
    check(trigger_class_merged_after_default,
          contains(TriggerOptsPassthrough, "class=\"px-tabs-trigger wide\"")),

    % ===================================================================
    % Content: role="tabpanel", aria-labelledby, data-state,
    % data-orientation, hidden on inactive, tabindex always "0".
    % ===================================================================

    render_to_string(
        tabs_content([selected(true), labelledby("trigger1")], "Hello"),
        ContentSelected),
    check(content_role_tabpanel,
          contains(ContentSelected, "role=\"tabpanel\"")),
    check(content_aria_labelledby,
          contains(ContentSelected, "aria-labelledby=\"trigger1\"")),
    check(content_data_state_active,
          contains(ContentSelected, "data-state=\"active\"")),
    check(content_data_orientation_default_horizontal,
          contains(ContentSelected, "data-orientation=\"horizontal\"")),
    check(content_tabindex_0,
          contains(ContentSelected, "tabindex=\"0\"")),
    check(content_selected_not_hidden,
          not_contains(ContentSelected, "hidden")),
    check(content_selected_exact,
          ContentSelected ==
              "<div role=\"tabpanel\" aria-labelledby=\"trigger1\" data-state=\"active\" data-orientation=\"horizontal\" tabindex=\"0\" class=\"px-tabs-content\">Hello</div>"),

    render_to_string(tabs_content([], "Hidden panel"), ContentDefault),
    check(content_default_inactive_hidden,
          ( contains(ContentDefault, "data-state=\"inactive\""),
            contains(ContentDefault, "hidden"),
            contains(ContentDefault, "tabindex=\"0\""),
            not_contains(ContentDefault, "aria-labelledby") )),

    render_to_string(tabs_content([orientation(vertical)], "V"), ContentVertical),
    check(content_data_orientation_vertical,
          contains(ContentVertical, "data-orientation=\"vertical\"")),

    % `tabs_content/1` (no-children shorthand) delegates to `/2`.
    render_to_string(tabs_content([]), ContentNoChildren),
    check(content_no_children_no_content,
          contains(ContentNoChildren, "></div>")),

    % ===================================================================
    % Convenience `tabs/2`: value(_) required, per-item value(_)
    % required, selected computed by matching, full id-wiring, disabled
    % forwarding, orientation forwarding, loop(true) default.
    % ===================================================================

    check(tabs_missing_value_throws,
          catch((render_to_string(tabs([], []), _), fail),
                error(existence_error(option, value), _),
                true)),

    check(tabs_item_missing_value_throws,
          catch((render_to_string(
                     tabs([value(a)], [tabs_item([], "A", ["panelA"])]),
                     _),
                 fail),
                error(existence_error(option, value), _),
                true)),

    render_to_string(
        tabs([id("g1"), value(a)],
             [ tabs_item([value(a)], "A", ["panelA"]),
               tabs_item([value(b), disabled(true)], "B", ["panelB"]),
               tabs_item([value(c)], "C", ["panelC"])
             ]),
        GroupA),

    check(group_wrapper_is_px_tabs,
          ( sub_string(GroupA, 0, _, _, "<px-tabs>"),
            sub_string(GroupA, _, _, 0, "</px-tabs>") )),
    check(group_role_tablist_present,
          contains(GroupA, "role=\"tablist\"")),
    check(group_three_tabs,
          count_occurrences(GroupA, "role=\"tab\"", 3)),
    check(group_three_tabpanels,
          count_occurrences(GroupA, "role=\"tabpanel\"", 3)),
    check(group_one_selected,
          count_occurrences(GroupA, "aria-selected=\"true\"", 1)),
    check(group_one_active_trigger,
          count_occurrences(GroupA, "data-state=\"active\"", 2)),  % A's trigger + A's panel
    check(group_matched_item_selected,
          sub_string(GroupA, _, _, _,
                     "aria-selected=\"true\" aria-controls=\"g1-a-content\" data-state=\"active\" tabindex=\"0\" class=\"px-tabs-trigger\" id=\"g1-a-trigger\"")),
    % Content always carries tabindex="0" unconditionally (the doc's own
    % contract), so the "exactly one roving tab stop" invariant is
    % checked scoped to Triggers only, via the substring that only a
    % selected Trigger's own attribute run produces.
    check(group_exactly_one_trigger_tabindex_0,
          count_occurrences(GroupA, "tabindex=\"0\" class=\"px-tabs-trigger\"", 1)),
    check(group_disabled_item_stays_unselected_and_marked,
          sub_string(GroupA, _, _, _,
                     "class=\"px-tabs-trigger\" data-disabled=\"\" disabled id=\"g1-b-trigger\"")),
    check(group_two_panels_hidden,
          count_occurrences(GroupA, "hidden", 2)),

    % The Trigger<->Content id-wiring: A's trigger's aria-controls
    % equals A's content's id; A's content's aria-labelledby equals A's
    % trigger's id -- both directions, for all three items.
    check(group_wiring_a,
          ( sub_string(GroupA, _, _, _, "aria-controls=\"g1-a-content\""),
            sub_string(GroupA, _, _, _, "id=\"g1-a-content\""),
            sub_string(GroupA, _, _, _, "aria-labelledby=\"g1-a-trigger\""),
            sub_string(GroupA, _, _, _, "id=\"g1-a-trigger\"") )),
    check(group_wiring_b,
          ( sub_string(GroupA, _, _, _, "aria-controls=\"g1-b-content\""),
            sub_string(GroupA, _, _, _, "id=\"g1-b-content\""),
            sub_string(GroupA, _, _, _, "aria-labelledby=\"g1-b-trigger\""),
            sub_string(GroupA, _, _, _, "id=\"g1-b-trigger\"") )),
    check(group_wiring_c,
          ( sub_string(GroupA, _, _, _, "aria-controls=\"g1-c-content\""),
            sub_string(GroupA, _, _, _, "id=\"g1-c-content\""),
            sub_string(GroupA, _, _, _, "aria-labelledby=\"g1-c-trigger\""),
            sub_string(GroupA, _, _, _, "id=\"g1-c-trigger\"") )),

    % Panel content itself made it through.
    check(group_panel_content_present,
          ( contains(GroupA, "panelA"),
            contains(GroupA, "panelB"),
            contains(GroupA, "panelC") )),

    % value(_) matching is type-tolerant (atom vs string compare equal).
    render_to_string(
        tabs([id("g2"), value("b")],
             [ tabs_item([value(a)], "A", ["pa"]),
               tabs_item([value(b)], "B", ["pb"])
             ]),
        GroupStringValue),
    check(group_string_value_matches_atom_item,
          sub_string(GroupStringValue, _, _, _,
                     "aria-selected=\"true\" aria-controls=\"g2-b-content\"")),

    % No item matches Opts' value(_): nothing selected, every panel
    % hidden, no tabindex="0" anywhere (roving-focus's own install-time
    % fallback -- first non-disabled item -- takes over client-side).
    render_to_string(
        tabs([id("g3"), value(nonexistent)],
             [ tabs_item([value(a)], "A", ["pa"]),
               tabs_item([value(b)], "B", ["pb"])
             ]),
        GroupNoMatch),
    check(group_no_match_none_selected,
          not_contains(GroupNoMatch, "aria-selected=\"true\"")),
    check(group_no_match_none_trigger_tabindex_0,
          not_contains(GroupNoMatch, "tabindex=\"0\" class=\"px-tabs-trigger\"")),
    check(group_no_match_both_hidden,
          count_occurrences(GroupNoMatch, "hidden", 2)),

    % orientation(vertical) forwarded to Root, List, and every Content.
    render_to_string(
        tabs([id("g4"), value(a), orientation(vertical)],
             [ tabs_item([value(a)], "A", ["pa"]),
               tabs_item([value(b)], "B", ["pb"])
             ]),
        GroupVertical),
    check(group_vertical_root,
          contains(GroupVertical, "data-orientation=\"vertical\"")),
    check(group_vertical_list,
          contains(GroupVertical, "aria-orientation=\"vertical\"")),
    check(group_vertical_content_count,
          count_occurrences(GroupVertical, "data-orientation=\"vertical\"", 3)),  % Root + 2 Content

    % loop(false) override forwarded to List (default is true).
    render_to_string(
        tabs([id("g5"), value(a), loop(false)],
             [ tabs_item([value(a)], "A", ["pa"]) ]),
        GroupNoLoop),
    check(group_loop_false_omits_data_loop,
          not_contains(GroupNoLoop, "data-loop")),

    render_to_string(
        tabs([id("g6"), value(a)],
             [ tabs_item([value(a)], "A", ["pa"]) ]),
        GroupLoopDefault),
    check(group_loop_default_true,
          contains(GroupLoopDefault, "data-loop=\"\"")),

    % Auto-gensym'd root base when id(_) is omitted -- still produces a
    % consistent, non-empty trigger/content id pair.
    render_to_string(
        tabs([value(a)],
             [ tabs_item([value(a)], "A", ["pa"]) ]),
        GroupGensym),
    check(group_gensym_id_wiring_consistent,
          ( sub_string(GroupGensym, _, _, _, "aria-controls=\"px-tabs-"),
            sub_string(GroupGensym, _, _, _, "id=\"px-tabs-") )),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Call` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(tabs, _Order, \tabs_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(tabs, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \tabs_demo), Demo),
    check(demo_has_two_tabs_groups,
          count_occurrences(Demo, "<px-tabs>", 2)),
    check(demo_has_six_triggers,
          count_occurrences(Demo, "role=\"tab\"", 6)),
    check(demo_has_six_panels,
          count_occurrences(Demo, "role=\"tabpanel\"", 6)),
    check(demo_has_one_disabled_trigger,
          count_occurrences(Demo, "data-disabled=\"\" disabled", 1)),
    check(demo_has_vertical_variant,
          contains(Demo, "data-orientation=\"vertical\"")),
    check(demo_has_active_and_inactive_states,
          ( contains(Demo, "data-state=\"active\""),
            contains(Demo, "data-state=\"inactive\"") )),

    % show some real output for the record
    format("~n--- rendered tabs_demo ---~n~w~n-----------------------------------~n",
           [Demo]).
