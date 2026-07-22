/* test/ui/collapsible.pl (adr/0026): render-test proof for
   prolog/ui/collapsible.pl -- the Collapsible port. A plain swipl
   script, no server, no networking (test/ui/progress.pl's pattern):
   render_to_string/2 over the templates and assert the exact ARIA/
   data contract documented in docs/radix-port-analysis.md's
   "Collapsible" entry, for both states (open/closed), disabled, the
   documented `hidden` omission, and the `collapsible/2` convenience's
   Trigger<->Content id wiring, plus the kitchen-sink demo
   registration.
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/collapsible.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Harness (test/ui/progress.pl's pattern).
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

% Extracts the value of the FIRST `Attr="..."` occurrence in Haystack.
extract_attr_value(Haystack, Attr, Value) :-
    format(string(Prefix), "~w=\"", [Attr]),
    once(sub_string(Haystack, Before, Len, _, Prefix)),
    Start is Before + Len,
    sub_string(Haystack, Start, _, 0, Tail),
    once(sub_string(Tail, ValLen, _, _, "\"")),
    sub_string(Tail, 0, ValLen, _, Value).

main :-
    tests,
    failed_count(N),
    (   N =:= 0
    ->  format("~nAll ui/collapsible checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Root (`<details>`): closed (default) vs open.
    % ===================================================================

    render_to_string(collapsible_root([], "x"), ClosedRoot),
    check(closed_root_data_state,
          contains(ClosedRoot, "data-state=\"closed\"")),
    check(closed_root_no_open_attr,
          not_contains(ClosedRoot, " open")),
    check(closed_root_default_class,
          contains(ClosedRoot, "class=\"px-collapsible\"")),
    check(closed_root_is_details_tag,
          ( sub_string(ClosedRoot, 0, 8, _, "<details"),
            sub_string(ClosedRoot, _, _, 0, "</details>") )),
    check(closed_root_no_data_disabled,
          not_contains(ClosedRoot, "data-disabled")),

    render_to_string(collapsible_root([open(true)], "x"), OpenRoot),
    check(open_root_data_state,
          contains(OpenRoot, "data-state=\"open\"")),
    check(open_root_has_open_attr,
          contains(OpenRoot, "<details data-state=\"open\" class=\"px-collapsible\" open>")),

    % ===================================================================
    % Root: disabled -> data-disabled="" (empty-string, not "true").
    % ===================================================================

    render_to_string(collapsible_root([disabled(true)], "x"), DisabledRoot),
    check(disabled_root_data_disabled_empty,
          contains(DisabledRoot, "data-disabled=\"\"")),
    check(disabled_root_no_true_string,
          not_contains(DisabledRoot, "data-disabled=\"true\"")),

    % ===================================================================
    % Trigger (`<summary>`): aria-controls ONLY set while open (a
    % literal upstream quirk, kept as documented in the module header).
    % ===================================================================

    render_to_string(collapsible_trigger([open(false), controls(cid)], "Toggle"), ClosedTrigger),
    check(closed_trigger_no_aria_controls,
          not_contains(ClosedTrigger, "aria-controls")),
    check(closed_trigger_aria_expanded_false,
          contains(ClosedTrigger, "aria-expanded=\"false\"")),
    check(closed_trigger_data_state,
          contains(ClosedTrigger, "data-state=\"closed\"")),
    check(closed_trigger_is_summary_tag,
          ( sub_string(ClosedTrigger, 0, 8, _, "<summary"),
            sub_string(ClosedTrigger, _, _, 0, "</summary>") )),

    render_to_string(collapsible_trigger([open(true), controls(cid)], "Toggle"), OpenTrigger),
    check(open_trigger_has_aria_controls,
          contains(OpenTrigger, "aria-controls=\"cid\"")),
    check(open_trigger_aria_expanded_true,
          contains(OpenTrigger, "aria-expanded=\"true\"")),
    check(open_trigger_data_state,
          contains(OpenTrigger, "data-state=\"open\"")),

    % No controls(_) supplied at all -> never emits aria-controls, even
    % while open (nothing to point it at).
    render_to_string(collapsible_trigger([open(true)], "Toggle"), NoControlsTrigger),
    check(open_trigger_without_controls_opt_has_no_aria_controls,
          not_contains(NoControlsTrigger, "aria-controls")),

    % ===================================================================
    % Trigger: disabled -> data-disabled="" AND tabindex="-1" (this
    % port's documented, JS-free best-effort mitigation -- <summary>
    % has no native `disabled` attribute).
    % ===================================================================

    render_to_string(collapsible_trigger([disabled(true)], "Toggle"), DisabledTrigger),
    check(disabled_trigger_data_disabled_empty,
          contains(DisabledTrigger, "data-disabled=\"\"")),
    check(disabled_trigger_tabindex,
          contains(DisabledTrigger, "tabindex=\"-1\"")),

    render_to_string(collapsible_trigger([disabled(false)], "Toggle"), EnabledTrigger),
    check(enabled_trigger_no_tabindex,
          not_contains(EnabledTrigger, "tabindex")),

    % ===================================================================
    % Content (`<div>`): id, data-state, data-disabled -- and, per the
    % module header's documented contract deviation, NEVER a `hidden`
    % attribute (native <details> already owns show/hide; a static
    % hidden would desync after the user natively re-opens it).
    % ===================================================================

    render_to_string(collapsible_content([open(true), id(cid)], "Body"), OpenContent),
    check(open_content_data_state,
          contains(OpenContent, "data-state=\"open\"")),
    check(open_content_id,
          contains(OpenContent, "id=\"cid\"")),
    check(open_content_never_hidden,
          not_contains(OpenContent, "hidden")),
    check(open_content_is_div_tag,
          ( sub_string(OpenContent, 0, 4, _, "<div"),
            sub_string(OpenContent, _, _, 0, "</div>") )),

    render_to_string(collapsible_content([open(false), id(cid)], "Body"), ClosedContent),
    check(closed_content_data_state,
          contains(ClosedContent, "data-state=\"closed\"")),
    check(closed_content_never_hidden,
          not_contains(ClosedContent, "hidden")),

    % ===================================================================
    % class(...) merges after the default, on all three parts.
    % ===================================================================

    render_to_string(collapsible_root([class("wide")], "x"), ClassedRoot),
    check(root_class_merged,
          contains(ClassedRoot, "class=\"px-collapsible wide\"")),
    render_to_string(collapsible_trigger([class("accent")], "x"), ClassedTrigger),
    check(trigger_class_merged,
          contains(ClassedTrigger, "class=\"px-collapsible-trigger accent\"")),
    render_to_string(collapsible_content([class("pad")], "x"), ClassedContent),
    check(content_class_merged,
          contains(ClassedContent, "class=\"px-collapsible-content pad\"")),

    % ===================================================================
    % collapsible/2 convenience: assembles Root > Trigger + Content,
    % Trigger's aria-controls wired to Content's id automatically.
    % ===================================================================

    render_to_string(
        collapsible([id("demo1")], ["Question", "Answer"]),
        ConvClosed),
    check(convenience_one_details,
          count_occurrences(ConvClosed, "<details", 1)),
    check(convenience_one_summary,
          count_occurrences(ConvClosed, "<summary", 1)),
    check(convenience_root_id,
          contains(ConvClosed, "id=\"demo1\"")),
    check(convenience_content_id_derived,
          contains(ConvClosed, "id=\"demo1-content\"")),
    check(convenience_no_aria_controls_when_closed,
          not_contains(ConvClosed, "aria-controls")),
    check(convenience_trigger_text,
          contains(ConvClosed, "Question")),
    check(convenience_content_text,
          contains(ConvClosed, "Answer")),
    check(convenience_never_hidden,
          not_contains(ConvClosed, "hidden")),

    render_to_string(
        collapsible([id("demo2"), open(true)], ["Q", "A"]),
        ConvOpen),
    check(convenience_open_root_has_open_attr,
          contains(ConvOpen, " open")),
    check(convenience_open_aria_controls_matches_content_id,
          contains(ConvOpen, "aria-controls=\"demo2-content\"")),
    check(convenience_open_content_id_matches,
          contains(ConvOpen, "id=\"demo2-content\"")),
    check(convenience_open_data_state_open_thrice,
          count_occurrences(ConvOpen, "data-state=\"open\"", 3)),

    % Without an explicit id(...), a gensym'd id still wires Trigger to
    % Content consistently (uniqueness across renders is gensym's job,
    % not asserted here -- just that root<->content agree). Needs
    % open(true) so the trigger actually emits aria-controls at all
    % (only set while open, per the contract).
    render_to_string(collapsible([open(true)], ["Q", "A"]), ConvNoId),
    check(convenience_gensym_id_wires_up,
          ( extract_attr_value(ConvNoId, "id", ContentId),
            extract_attr_value(ConvNoId, "aria-controls", ControlsId),
            ContentId == ControlsId
          )),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Call` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(collapsible, _Order, \collapsible_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(collapsible, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \collapsible_demo), Demo),
    check(demo_has_closed_and_open_instances,
          ( contains(Demo, "data-state=\"closed\""),
            contains(Demo, "data-state=\"open\"") )),
    check(demo_has_two_details,
          count_occurrences(Demo, "<details", 2)),
    check(demo_open_instance_has_native_open_attr,
          contains(Demo, "open id=\"collapsible-demo-open\"")),
    check(demo_ids,
          ( contains(Demo, "collapsible-demo-closed"),
            contains(Demo, "collapsible-demo-open") )),

    % show some real output for the record
    format("~n--- rendered collapsible_demo ---~n~w~n---------------------------------~n",
           [Demo]).
