/* test/ui/tooltip.pl (adr/0026): render-test proof for
   prolog/ui/tooltip.pl -- the Tooltip port, lib/popper.js's second
   consumer after Popover. A plain swipl script, no server, no
   networking (test/ui/popover.pl's pattern): render_to_string/2 over
   the templates and assert the exact ARIA/data contract documented in
   docs/radix-port-analysis.md's "Tooltip" entry, for:

     - tooltip_root/2      <px-tooltip> wrapper, class merge/pass-through
     - tooltip_trigger/2   NO type="button" (deliberate, matches
                            upstream), aria-describedby (wired off
                            describedby(_)), three-way data-state
                            (closed default, delayed-open, instant-open),
                            graceful no-describedby degrade
     - tooltip_content/2   role="tooltip", native popover="manual",
                            data-state, data-side (default top --
                            NOT Popover's bottom), data-align (default
                            center), data-side-offset/data-align-offset
                            (default 0)
     - tooltip_arrow/1     aria-hidden="true", class merge
     - tooltip/2           the full id-wiring between Trigger and
                            Content (aria-describedby vs id matching),
                            state(_) threaded to both, side/align/offset
                            forwarding, an Arrow appended to Content
                            automatically, auto-gensym'd id when omitted

   plus the kitchen-sink demo registration (px_ui:demo/3) rendering end
   to end exactly as prolog/px_ui.pl's ui_show_view embeds it (`\Goal`
   as a div's Children, not the bare atom -- adr/0019's arity-0
   dispatch rule).
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/tooltip.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Harness (test/ui/popover.pl's pattern).
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
    ->  format("~nAll ui/tooltip checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Root: <px-tooltip> wrapper, class merge.
    % ===================================================================

    render_to_string(tooltip_root([], []), RootDefault),
    check(root_wrapper_is_px_tooltip,
          ( sub_string(RootDefault, 0, _, _, "<px-tooltip>"),
            sub_string(RootDefault, _, _, 0, "</px-tooltip>") )),
    check(root_default_class,
          contains(RootDefault, "class=\"px-tooltip\"")),
    check(root_exact,
          RootDefault ==
              "<px-tooltip><div class=\"px-tooltip\"></div></px-tooltip>"),

    render_to_string(tooltip_root([class("wide"), id("g1")], []), RootOpts),
    check(root_class_merged_after_default,
          contains(RootOpts, "class=\"px-tooltip wide\"")),
    check(root_id_passed_through,
          contains(RootOpts, "id=\"g1\"")),

    % ===================================================================
    % Trigger: NO type="button", aria-describedby, three-way data-state,
    % graceful no-describedby degrade.
    % ===================================================================

    render_to_string(
        tooltip_trigger([state(delayed_open), describedby("t1")], "Hover me"),
        TriggerDelayed),
    check(trigger_no_type_attribute,
          not_contains(TriggerDelayed, "type=")),
    check(trigger_aria_describedby,
          contains(TriggerDelayed, "aria-describedby=\"t1\"")),
    check(trigger_data_state_delayed_open,
          contains(TriggerDelayed, "data-state=\"delayed-open\"")),
    check(trigger_exact,
          TriggerDelayed ==
              "<button aria-describedby=\"t1\" data-state=\"delayed-open\" class=\"px-tooltip-trigger\">Hover me</button>"),

    render_to_string(
        tooltip_trigger([state(instant_open), describedby("t1")], "Hover me"),
        TriggerInstant),
    check(trigger_data_state_instant_open,
          contains(TriggerInstant, "data-state=\"instant-open\"")),

    render_to_string(tooltip_trigger([], "Hover me"), TriggerDefault),
    check(trigger_default_closed,
          contains(TriggerDefault, "data-state=\"closed\"")),
    check(trigger_no_describedby_degrades_gracefully,
          not_contains(TriggerDefault, "aria-describedby")),
    check(trigger_no_haspopup,
          not_contains(TriggerDefault, "aria-haspopup")),
    check(trigger_no_expanded,
          not_contains(TriggerDefault, "aria-expanded")),

    render_to_string(tooltip_trigger([state(bogus)], "X"), TriggerBadState),
    check(trigger_invalid_state_falls_back,
          contains(TriggerBadState, "data-state=\"closed\"")),

    % ===================================================================
    % Content: role="tooltip", native popover="manual", data-state,
    % data-side (default top), data-align (default center),
    % data-side-offset/data-align-offset (default 0).
    % ===================================================================

    render_to_string(tooltip_content([id("t1")], "Hint text"), ContentDefault),
    check(content_role_tooltip,
          contains(ContentDefault, "role=\"tooltip\"")),
    check(content_native_popover_manual,
          contains(ContentDefault, "popover=\"manual\"")),
    check(content_data_state_closed,
          contains(ContentDefault, "data-state=\"closed\"")),
    check(content_data_side_default_top,
          contains(ContentDefault, "data-side=\"top\"")),
    check(content_data_align_default_center,
          contains(ContentDefault, "data-align=\"center\"")),
    check(content_data_side_offset_default_0,
          contains(ContentDefault, "data-side-offset=\"0\"")),
    check(content_data_align_offset_default_0,
          contains(ContentDefault, "data-align-offset=\"0\"")),
    check(content_id_passed_through,
          contains(ContentDefault, "id=\"t1\"")),

    render_to_string(
        tooltip_content(
            [ id("t2"), state(instant_open), side(bottom), align(start),
              side_offset(8), align_offset(4)
            ],
            "Hint text"),
        ContentOpts),
    check(content_data_state_instant_open,
          contains(ContentOpts, "data-state=\"instant-open\"")),
    check(content_data_side_bottom,
          contains(ContentOpts, "data-side=\"bottom\"")),
    check(content_data_align_start,
          contains(ContentOpts, "data-align=\"start\"")),
    check(content_data_side_offset_8,
          contains(ContentOpts, "data-side-offset=\"8\"")),
    check(content_data_align_offset_4,
          contains(ContentOpts, "data-align-offset=\"4\"")),

    render_to_string(tooltip_content([id("t3"), side(sideways)], "X"), ContentBadSide),
    check(content_invalid_side_falls_back,
          contains(ContentBadSide, "data-side=\"top\"")),

    render_to_string(tooltip_content([id("t4"), align(nowhere)], "X"), ContentBadAlign),
    check(content_invalid_align_falls_back,
          contains(ContentBadAlign, "data-align=\"center\"")),

    % ===================================================================
    % Arrow: aria-hidden="true", class merge.
    % ===================================================================

    render_to_string(tooltip_arrow([]), ArrowDefault),
    check(arrow_exact,
          ArrowDefault ==
              "<div aria-hidden=\"true\" class=\"px-tooltip-arrow\"></div>"),

    render_to_string(tooltip_arrow([class("big")]), ArrowClass),
    check(arrow_class_merged,
          contains(ArrowClass, "class=\"px-tooltip-arrow big\"")),

    % ===================================================================
    % Convenience `tooltip/2`: Trigger<->Content wiring, state(_)
    % threading, side/align/offset forwarding, auto Arrow, auto-gensym'd
    % id.
    % ===================================================================

    render_to_string(
        tooltip([id("demo1"), state(delayed_open), side(bottom), align(start), side_offset(6)],
                ["Hover", "Hint body"]),
        Group1),

    check(group_wrapper_is_px_tooltip,
          ( sub_string(Group1, 0, _, _, "<px-tooltip>"),
            sub_string(Group1, _, _, 0, "</px-tooltip>") )),
    check(group_trigger_and_content_present,
          ( contains(Group1, "px-tooltip-trigger"),
            contains(Group1, "role=\"tooltip\"") )),
    check(group_wiring_describedby_matches_content_id,
          ( sub_string(Group1, _, _, _, "aria-describedby=\"demo1-content\""),
            sub_string(Group1, _, _, _, "id=\"demo1-content\"") )),
    check(group_state_threaded_to_both,
          count_occurrences(Group1, "data-state=\"delayed-open\"", 2)),
    check(group_side_align_offset_forwarded,
          ( contains(Group1, "data-side=\"bottom\""),
            contains(Group1, "data-align=\"start\""),
            contains(Group1, "data-side-offset=\"6\"") )),
    check(group_arrow_appended,
          contains(Group1, "px-tooltip-arrow")),
    check(group_content_present,
          contains(Group1, "Hint body")),
    % Regression: state(_)/side(_)/align(_)/side_offset(_)/align_offset(_)
    % must NOT leak onto the Root <div> as raw, meaningless HTML
    % attributes.
    check(group_root_no_raw_state_attr,
          not_contains(Group1, " state=\"delayed_open\"")),
    check(group_root_no_raw_side_attr,
          not_contains(Group1, " side=\"bottom\"")),
    check(group_root_no_raw_align_attr,
          not_contains(Group1, " align=\"start\"")),
    check(group_root_no_raw_side_offset_attr,
          not_contains(Group1, " side_offset=\"6\"")),

    render_to_string(tooltip([], ["Hover", "Body"]), Group2),
    check(group_gensym_id_wiring_consistent,
          sub_string(Group2, _, _, _, "aria-describedby=\"px_tooltip_")),
    check(group_default_closed,
          count_occurrences(Group2, "data-state=\"closed\"", 2)),
    check(group_default_side_top,
          contains(Group2, "data-side=\"top\"")),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(tooltip, _Order, \tooltip_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(tooltip, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \tooltip_demo), Demo),
    check(demo_has_six_tooltips,
          count_occurrences(Demo, "<px-tooltip>", 6)),
    check(demo_has_six_describedby_wirings,
          count_occurrences(Demo, "aria-describedby=", 6)),
    check(demo_has_six_contents,
          count_occurrences(Demo, "role=\"tooltip\"", 6)),
    check(demo_has_icon_button_aria_label,
          contains(Demo, "aria-label=\"Add to library\"")),
    check(demo_has_every_side,
          ( contains(Demo, "data-side=\"top\""),
            contains(Demo, "data-side=\"right\""),
            contains(Demo, "data-side=\"bottom\""),
            contains(Demo, "data-side=\"left\"") )),
    check(demo_no_type_button_anywhere,
          not_contains(Demo, "type=\"button\"")),

    % show some real output for the record
    format("~n--- rendered tooltip_demo ---~n~w~n-----------------------------------~n",
           [Demo]).
