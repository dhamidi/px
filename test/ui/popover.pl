/* test/ui/popover.pl (adr/0026): render-test proof for
   prolog/ui/popover.pl -- the Popover port, lib/popper.js's proving
   consumer. A plain swipl script, no server, no networking (test/ui/
   accordion.pl's / tabs.pl's pattern): render_to_string/2 over the
   templates and assert the exact ARIA/data contract documented in
   docs/radix-port-analysis.md's "Popover" entry, for:

     - popover_root/2      <px-popover> wrapper, class merge/pass-through
     - popover_trigger/2   aria-haspopup="dialog", aria-expanded,
                            data-state, aria-controls + native
                            popovertarget (both wired off controls(_)),
                            graceful no-controls degrade
     - popover_content/2   role="dialog", native popover="auto",
                            data-state, data-side (default bottom),
                            data-align (default center),
                            data-side-offset/data-align-offset (default
                            0), optional aria-labelledby/aria-describedby
     - popover_arrow/1     aria-hidden="true", class merge
     - popover_close/1,2   native popovertarget +
                            popovertargetaction="hide", no-label
                            shorthand
     - popover/2           the full id-wiring between Trigger and
                            Content (aria-controls/popovertarget vs id
                            all matching), open(_) threaded to both,
                            side/align/offset forwarding, an Arrow
                            appended to Content automatically, auto-
                            gensym'd id when omitted

   plus the kitchen-sink demo registration (px_ui:demo/3) rendering end
   to end exactly as prolog/px_ui.pl's ui_show_view embeds it (`\Goal`
   as a div's Children, not the bare atom -- adr/0019's arity-0
   dispatch rule).
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/popover.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Harness (test/ui/accordion.pl's / tabs.pl's pattern).
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
    ->  format("~nAll ui/popover checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Root: <px-popover> wrapper, class merge.
    % ===================================================================

    render_to_string(popover_root([], []), RootDefault),
    check(root_wrapper_is_px_popover,
          ( sub_string(RootDefault, 0, _, _, "<px-popover>"),
            sub_string(RootDefault, _, _, 0, "</px-popover>") )),
    check(root_default_class,
          contains(RootDefault, "class=\"px-popover\"")),
    check(root_exact,
          RootDefault ==
              "<px-popover><div class=\"px-popover\"></div></px-popover>"),

    render_to_string(popover_root([class("wide"), id("g1")], []), RootOpts),
    check(root_class_merged_after_default,
          contains(RootOpts, "class=\"px-popover wide\"")),
    check(root_id_passed_through,
          contains(RootOpts, "id=\"g1\"")),

    % ===================================================================
    % Trigger: aria-haspopup, aria-expanded, data-state, aria-controls +
    % native popovertarget, graceful no-controls degrade.
    % ===================================================================

    render_to_string(
        popover_trigger([open(true), controls("p1")], "Open"),
        TriggerOpen),
    check(trigger_aria_haspopup_dialog,
          contains(TriggerOpen, "aria-haspopup=\"dialog\"")),
    check(trigger_aria_expanded_true,
          contains(TriggerOpen, "aria-expanded=\"true\"")),
    check(trigger_data_state_open,
          contains(TriggerOpen, "data-state=\"open\"")),
    check(trigger_aria_controls,
          contains(TriggerOpen, "aria-controls=\"p1\"")),
    check(trigger_native_popovertarget,
          contains(TriggerOpen, "popovertarget=\"p1\"")),
    check(trigger_exact,
          TriggerOpen ==
              "<button type=\"button\" aria-haspopup=\"dialog\" aria-controls=\"p1\" popovertarget=\"p1\" aria-expanded=\"true\" data-state=\"open\" class=\"px-popover-trigger\">Open</button>"),

    render_to_string(popover_trigger([], "Open"), TriggerDefault),
    check(trigger_default_closed,
          ( contains(TriggerDefault, "aria-expanded=\"false\""),
            contains(TriggerDefault, "data-state=\"closed\"") )),
    check(trigger_no_controls_degrades_gracefully,
          ( not_contains(TriggerDefault, "aria-controls"),
            not_contains(TriggerDefault, "popovertarget") )),

    % ===================================================================
    % Content: role="dialog", native popover="auto", data-state,
    % data-side (default bottom), data-align (default center),
    % data-side-offset/data-align-offset (default 0), optional
    % aria-labelledby/aria-describedby.
    % ===================================================================

    render_to_string(popover_content([id("p1")], "Hello"), ContentDefault),
    check(content_role_dialog,
          contains(ContentDefault, "role=\"dialog\"")),
    check(content_native_popover_auto,
          contains(ContentDefault, "popover=\"auto\"")),
    check(content_data_state_closed,
          contains(ContentDefault, "data-state=\"closed\"")),
    check(content_data_side_default_bottom,
          contains(ContentDefault, "data-side=\"bottom\"")),
    check(content_data_align_default_center,
          contains(ContentDefault, "data-align=\"center\"")),
    check(content_data_side_offset_default_0,
          contains(ContentDefault, "data-side-offset=\"0\"")),
    check(content_data_align_offset_default_0,
          contains(ContentDefault, "data-align-offset=\"0\"")),
    check(content_id_passed_through,
          contains(ContentDefault, "id=\"p1\"")),
    check(content_no_labelledby_by_default,
          not_contains(ContentDefault, "aria-labelledby")),

    render_to_string(
        popover_content(
            [ id("p2"), open(true), side(top), align(start),
              side_offset(8), align_offset(4),
              labelledby("t1"), describedby("d1")
            ],
            "Hello"),
        ContentOpts),
    check(content_data_state_open,
          contains(ContentOpts, "data-state=\"open\"")),
    check(content_data_side_top,
          contains(ContentOpts, "data-side=\"top\"")),
    check(content_data_align_start,
          contains(ContentOpts, "data-align=\"start\"")),
    check(content_data_side_offset_8,
          contains(ContentOpts, "data-side-offset=\"8\"")),
    check(content_data_align_offset_4,
          contains(ContentOpts, "data-align-offset=\"4\"")),
    check(content_aria_labelledby,
          contains(ContentOpts, "aria-labelledby=\"t1\"")),
    check(content_aria_describedby,
          contains(ContentOpts, "aria-describedby=\"d1\"")),

    render_to_string(popover_content([id("p3"), side(sideways)], "X"), ContentBadSide),
    check(content_invalid_side_falls_back,
          contains(ContentBadSide, "data-side=\"bottom\"")),

    render_to_string(popover_content([id("p4"), align(nowhere)], "X"), ContentBadAlign),
    check(content_invalid_align_falls_back,
          contains(ContentBadAlign, "data-align=\"center\"")),

    % ===================================================================
    % Arrow: aria-hidden="true", class merge.
    % ===================================================================

    render_to_string(popover_arrow([]), ArrowDefault),
    check(arrow_exact,
          ArrowDefault ==
              "<div aria-hidden=\"true\" class=\"px-popover-arrow\"></div>"),

    render_to_string(popover_arrow([class("big")]), ArrowClass),
    check(arrow_class_merged,
          contains(ArrowClass, "class=\"px-popover-arrow big\"")),

    % ===================================================================
    % Close: native popovertarget + popovertargetaction="hide", no-label
    % shorthand.
    % ===================================================================

    render_to_string(popover_close([controls("p1")], "Close"), CloseWithLabel),
    check(close_native_popovertarget,
          contains(CloseWithLabel, "popovertarget=\"p1\"")),
    check(close_popovertargetaction_hide,
          contains(CloseWithLabel, "popovertargetaction=\"hide\"")),
    check(close_aria_label,
          contains(CloseWithLabel, "aria-label=\"Close\"")),

    render_to_string(popover_close([controls("p1")]), CloseNoLabel),
    check(close_no_label_shorthand_uses_x,
          contains(CloseNoLabel, "×")),

    render_to_string(popover_close([]), CloseNoControls),
    check(close_no_controls_degrades_gracefully,
          not_contains(CloseNoControls, "popovertarget")),

    % ===================================================================
    % Convenience `popover/2`: Trigger<->Content wiring, open(_)
    % threading, side/align/offset forwarding, auto Arrow, auto-gensym'd
    % id.
    % ===================================================================

    render_to_string(
        popover([id("demo1"), open(true), side(top), align(start), side_offset(6)],
                ["Open", "Panel body"]),
        Group1),

    check(group_wrapper_is_px_popover,
          ( sub_string(Group1, 0, _, _, "<px-popover>"),
            sub_string(Group1, _, _, 0, "</px-popover>") )),
    check(group_trigger_and_content_present,
          ( contains(Group1, "aria-haspopup=\"dialog\""),
            contains(Group1, "role=\"dialog\"") )),
    check(group_wiring_controls_matches_content_id,
          ( sub_string(Group1, _, _, _, "aria-controls=\"demo1-content\""),
            sub_string(Group1, _, _, _, "popovertarget=\"demo1-content\""),
            sub_string(Group1, _, _, _, "id=\"demo1-content\"") )),
    check(group_open_threaded_to_both,
          count_occurrences(Group1, "data-state=\"open\"", 2)),
    check(group_side_align_offset_forwarded,
          ( contains(Group1, "data-side=\"top\""),
            contains(Group1, "data-align=\"start\""),
            contains(Group1, "data-side-offset=\"6\"") )),
    check(group_arrow_appended,
          contains(Group1, "px-popover-arrow")),
    check(group_content_present,
          contains(Group1, "Panel body")),
    % Regression: open(_)/side(_)/align(_)/side_offset(_)/align_offset(_)
    % must NOT leak onto the Root <div> as raw, meaningless HTML
    % attributes -- only Trigger/Content should carry their computed
    % forms (aria-expanded/data-state, data-side, data-align, ...).
    check(group_root_no_raw_open_attr,
          not_contains(Group1, "open=\"true\"")),
    check(group_root_no_raw_side_attr,
          not_contains(Group1, " side=\"top\"")),
    check(group_root_no_raw_align_attr,
          not_contains(Group1, " align=\"start\"")),
    check(group_root_no_raw_side_offset_attr,
          not_contains(Group1, " side_offset=\"6\"")),

    render_to_string(popover([], ["Open", "Body"]), Group2),
    check(group_gensym_id_wiring_consistent,
          ( sub_string(Group2, _, _, _, "aria-controls=\"px_popover_"),
            sub_string(Group2, _, _, _, "popovertarget=\"px_popover_") )),
    check(group_default_closed,
          count_occurrences(Group2, "data-state=\"closed\"", 2)),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Goal` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(popover, _Order, \popover_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(popover, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \popover_demo), Demo),
    check(demo_has_five_popovers,
          count_occurrences(Demo, "<px-popover>", 5)),
    check(demo_has_five_triggers,
          count_occurrences(Demo, "aria-haspopup=\"dialog\"", 5)),
    check(demo_has_five_contents,
          count_occurrences(Demo, "role=\"dialog\"", 5)),
    check(demo_has_close_button,
          contains(Demo, "popovertargetaction=\"hide\"")),
    check(demo_has_every_side,
          ( contains(Demo, "data-side=\"top\""),
            contains(Demo, "data-side=\"right\""),
            contains(Demo, "data-side=\"bottom\""),
            contains(Demo, "data-side=\"left\"") )),

    % show some real output for the record
    format("~n--- rendered popover_demo ---~n~w~n-----------------------------------~n",
           [Demo]).
