/* test/ui/accordion.pl (adr/0026): render-test proof for
   prolog/ui/accordion.pl -- the Accordion port. A plain swipl script,
   no server, no networking (test/ui/toggle_group.pl's /
   test/ui/collapsible.pl's pattern): render_to_string/2 over the
   templates and assert the exact ARIA/data contract documented in
   docs/radix-port-analysis.md's "Accordion" entry, for:

     - Root       data-orientation (default vertical), data-type,
                  data-collapsible (only when true), required `type`
     - Item       data-orientation, data-state, native `open`, native
                  `name` (low-level opt) -- and crucially NO
                  data-disabled (contract note, unlike Collapsible)
     - Trigger    everything Collapsible's trigger sets (aria-controls
                  only while open, aria-expanded always, data-state,
                  data-disabled) PLUS aria-disabled on the
                  currently-open trigger when type=single and NOT
                  collapsible
     - Header     folded INSIDE Trigger's <summary> as a nested <h3>
                  (data-orientation, data-state, data-disabled)
     - Content    role="region", aria-labelledby (unconditional), plus
                  everything Collapsible's content sets, never `hidden`

   plus the `accordion/2` convenience (type/collapsible/orientation
   injection, shared `name` grouping for type=single, Trigger<->Content
   id wiring, disabled routing to Trigger+Header+Content only), the
   required-`type` guard on both Root and the convenience, and the
   kitchen-sink demo registration (px_ui:demo/3).
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/accordion.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Harness (test/ui/toggle_group.pl's / test/ui/collapsible.pl's pattern).
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

% Extracts the FIRST `<TagName ...>` opening tag (attributes included)
% from Haystack, e.g. extract_open_tag(S, "details", "<details ...>").
extract_open_tag(Haystack, TagName, TagStr) :-
    format(string(Prefix), "<~w", [TagName]),
    once(sub_string(Haystack, Start, _, _, Prefix)),
    sub_string(Haystack, Start, _, 0, Tail),
    once(sub_string(Tail, CloseLen0, _, _, ">")),
    CloseLen is CloseLen0 + 1,
    sub_string(Tail, 0, CloseLen, _, TagStr).

main :-
    tests,
    failed_count(N),
    (   N =:= 0
    ->  format("~nAll ui/accordion checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Root: type(single) -- wrapper, data-type, data-orientation default
    % vertical, no data-collapsible by default.
    % ===================================================================

    render_to_string(accordion_root([type(single)], []), RootSingle),

    check(root_wrapper_is_px_accordion,
          ( sub_string(RootSingle, 0, _, _, "<px-accordion>"),
            sub_string(RootSingle, _, _, 0, "</px-accordion>") )),
    check(root_data_type_single,
          contains(RootSingle, "data-type=\"single\"")),
    check(root_orientation_default_vertical,
          contains(RootSingle, "data-orientation=\"vertical\"")),
    check(root_default_class,
          contains(RootSingle, "class=\"px-accordion\"")),
    check(root_no_collapsible_by_default,
          not_contains(RootSingle, "data-collapsible")),
    check(root_single_exact,
          RootSingle ==
              "<px-accordion><div data-orientation=\"vertical\" data-type=\"single\" class=\"px-accordion\"></div></px-accordion>"),

    render_to_string(accordion_root([type(multiple)], []), RootMultiple),
    check(root_data_type_multiple,
          contains(RootMultiple, "data-type=\"multiple\"")),

    % Missing type(_) is a hard error -- no sane default.
    check(root_missing_type_throws,
          catch((render_to_string(accordion_root([], []), _), fail),
                error(existence_error(option, type), _),
                true)),

    % collapsible(true), orientation(horizontal) -- each independently,
    % plus id/class pass-through and merging. Invalid orientation falls
    % back to the default.
    render_to_string(
        accordion_root([type(single), collapsible(true), orientation(horizontal),
                         id("acc1"), class("wide")], []),
        RootOpts),
    check(root_collapsible_true,
          contains(RootOpts, "data-collapsible=\"\"")),
    check(root_orientation_horizontal,
          contains(RootOpts, "data-orientation=\"horizontal\"")),
    check(root_id_passed_through,
          contains(RootOpts, "id=\"acc1\"")),
    check(root_class_merged_after_default,
          contains(RootOpts, "class=\"px-accordion wide\"")),

    render_to_string(accordion_root([type(single), orientation(sideways)], []),
                      RootBadOrientation),
    check(root_invalid_orientation_falls_back,
          contains(RootBadOrientation, "data-orientation=\"vertical\"")),

    % ===================================================================
    % Item: <details>, data-orientation, data-state, native open/name --
    % and crucially NO data-disabled (contract note, unlike Collapsible).
    % ===================================================================

    render_to_string(accordion_item([], "x"), ClosedItem),
    check(closed_item_is_details_tag,
          ( sub_string(ClosedItem, 0, 8, _, "<details"),
            sub_string(ClosedItem, _, _, 0, "</details>") )),
    check(closed_item_data_state,
          contains(ClosedItem, "data-state=\"closed\"")),
    check(closed_item_orientation_default_vertical,
          contains(ClosedItem, "data-orientation=\"vertical\"")),
    check(closed_item_no_open_attr,
          not_contains(ClosedItem, " open")),
    check(closed_item_no_name,
          not_contains(ClosedItem, "name=")),
    check(closed_item_never_data_disabled,
          not_contains(ClosedItem, "data-disabled")),
    check(closed_item_default_class,
          contains(ClosedItem, "class=\"px-accordion-item\"")),

    render_to_string(accordion_item([open(true)], "x"), OpenItem),
    check(open_item_data_state,
          contains(OpenItem, "data-state=\"open\"")),
    check(open_item_has_open_attr,
          contains(OpenItem, " open")),

    render_to_string(accordion_item([orientation(horizontal)], "x"), HorizItem),
    check(item_orientation_horizontal,
          contains(HorizItem, "data-orientation=\"horizontal\"")),

    render_to_string(accordion_item([name(grp1)], "x"), NamedItem),
    check(item_name_rendered,
          contains(NamedItem, "name=\"grp1\"")),

    render_to_string(accordion_item([class("accent")], "x"), ClassedItem),
    check(item_class_merged,
          contains(ClassedItem, "class=\"px-accordion-item accent\"")),

    % ===================================================================
    % Trigger: everything Collapsible's trigger sets, plus a nested
    % Header <h3> (Header placement deviation, see module header).
    % ===================================================================

    render_to_string(accordion_trigger([], "Title"), ClosedTrigger),
    check(closed_trigger_is_summary_tag,
          ( sub_string(ClosedTrigger, 0, 8, _, "<summary"),
            sub_string(ClosedTrigger, _, _, 0, "</summary>") )),
    check(closed_trigger_aria_expanded_false,
          contains(ClosedTrigger, "aria-expanded=\"false\"")),
    check(closed_trigger_data_state,
          contains(ClosedTrigger, "data-state=\"closed\"")),
    check(closed_trigger_no_aria_controls,
          not_contains(ClosedTrigger, "aria-controls")),
    check(closed_trigger_no_aria_disabled,
          not_contains(ClosedTrigger, "aria-disabled")),
    check(closed_trigger_has_nested_h3,
          ( sub_string(ClosedTrigger, _, _, _, "<h3 "),
            sub_string(ClosedTrigger, _, _, _, "</h3></summary>") )),
    check(closed_trigger_header_class,
          contains(ClosedTrigger, "class=\"px-accordion-header\"")),
    check(closed_trigger_header_text,
          contains(ClosedTrigger, "Title")),
    check(closed_trigger_header_orientation_default_vertical,
          contains(ClosedTrigger, "<h3 data-orientation=\"vertical\"")),
    check(closed_trigger_header_data_state,
          sub_string(ClosedTrigger, _, _, _, "<h3 data-orientation=\"vertical\" data-state=\"closed\"")),

    render_to_string(accordion_trigger([open(true), controls(cid)], "Title"), OpenTrigger),
    check(open_trigger_has_aria_controls,
          contains(OpenTrigger, "aria-controls=\"cid\"")),
    check(open_trigger_aria_expanded_true,
          contains(OpenTrigger, "aria-expanded=\"true\"")),
    check(open_trigger_header_data_state_open,
          contains(OpenTrigger, "data-state=\"open\"")),

    render_to_string(accordion_trigger([open(false), controls(cid)], "Title"), ClosedTriggerControls),
    check(closed_trigger_controls_omitted_even_when_supplied,
          not_contains(ClosedTriggerControls, "aria-controls")),

    % Trigger: disabled -- data-disabled AND tabindex="-1" on the
    % summary, data-disabled also mirrored onto the nested Header.
    render_to_string(accordion_trigger([disabled(true)], "Title"), DisabledTrigger),
    check(disabled_trigger_data_disabled,
          count_occurrences(DisabledTrigger, "data-disabled=\"\"", 2)),
    check(disabled_trigger_tabindex,
          contains(DisabledTrigger, "tabindex=\"-1\"")),

    render_to_string(accordion_trigger([disabled(false)], "Title"), EnabledTrigger),
    check(enabled_trigger_no_tabindex,
          not_contains(EnabledTrigger, "tabindex")),

    % Trigger: aria-disabled -- ONLY type=single, NOT collapsible, AND
    % open. Every other combination omits it entirely.
    render_to_string(
        accordion_trigger([type(single), collapsible(false), open(true)], "T"),
        MandatoryOpenTrigger),
    check(mandatory_open_aria_disabled,
          contains(MandatoryOpenTrigger, "aria-disabled=\"true\"")),

    render_to_string(
        accordion_trigger([type(single), collapsible(true), open(true)], "T"),
        CollapsibleOpenTrigger),
    check(collapsible_true_no_aria_disabled,
          not_contains(CollapsibleOpenTrigger, "aria-disabled")),

    render_to_string(
        accordion_trigger([type(multiple), collapsible(false), open(true)], "T"),
        MultipleOpenTrigger),
    check(type_multiple_no_aria_disabled,
          not_contains(MultipleOpenTrigger, "aria-disabled")),

    render_to_string(
        accordion_trigger([type(single), collapsible(false), open(false)], "T"),
        MandatoryClosedTrigger),
    check(mandatory_but_closed_no_aria_disabled,
          not_contains(MandatoryClosedTrigger, "aria-disabled")),

    % type(_) entirely omitted defaults to `multiple` -- never
    % aria-disabled, even when open.
    render_to_string(
        accordion_trigger([collapsible(false), open(true)], "T"),
        NoTypeTrigger),
    check(no_type_defaults_multiple_no_aria_disabled,
          not_contains(NoTypeTrigger, "aria-disabled")),

    % Trigger/Header class merge.
    render_to_string(accordion_trigger([class("accent")], "T"), ClassedTrigger),
    check(trigger_class_merged,
          contains(ClassedTrigger, "class=\"px-accordion-trigger accent\"")),

    % ===================================================================
    % Content: role="region", aria-labelledby (unconditional), everything
    % Collapsible's content sets, never `hidden`.
    % ===================================================================

    render_to_string(accordion_content([open(true), id(cid), labelledby(tid)], "Body"),
                      OpenContent),
    check(open_content_is_div_tag,
          ( sub_string(OpenContent, 0, 4, _, "<div"),
            sub_string(OpenContent, _, _, 0, "</div>") )),
    check(open_content_role_region,
          contains(OpenContent, "role=\"region\"")),
    check(open_content_aria_labelledby,
          contains(OpenContent, "aria-labelledby=\"tid\"")),
    check(open_content_data_state,
          contains(OpenContent, "data-state=\"open\"")),
    check(open_content_id,
          contains(OpenContent, "id=\"cid\"")),
    check(open_content_never_hidden,
          not_contains(OpenContent, "hidden")),

    render_to_string(accordion_content([open(false), labelledby(tid)], "Body"), ClosedContent),
    check(closed_content_data_state,
          contains(ClosedContent, "data-state=\"closed\"")),
    check(closed_content_aria_labelledby_unconditional,
          contains(ClosedContent, "aria-labelledby=\"tid\"")),

    render_to_string(accordion_content([disabled(true)], "Body"), DisabledContent),
    check(disabled_content_data_disabled,
          contains(DisabledContent, "data-disabled=\"\"")),

    render_to_string(accordion_content([], "Body"), NoLabelledbyContent),
    check(no_labelledby_when_absent,
          not_contains(NoLabelledbyContent, "aria-labelledby")),

    render_to_string(accordion_content([class("pad")], "Body"), ClassedContent),
    check(content_class_merged,
          contains(ClassedContent, "class=\"px-accordion-content pad\"")),

    % ===================================================================
    % Convenience `accordion/2`: type/collapsible/orientation threaded,
    % Trigger<->Content id wiring, shared `name` grouping for type=single.
    % ===================================================================

    % Missing type(_) on the convenience is a hard error too.
    check(convenience_missing_type_throws,
          catch((render_to_string(accordion([], []), _), fail),
                error(existence_error(option, type), _),
                true)),

    % Single item: Trigger<->Content id wiring. The Item's own id is
    % explicit ("item1") so the derived Trigger/Content ids are
    % predictable; the top-level accordion Opts deliberately carries no
    % id(_) of its own, so the FIRST `id="..."` in the render really is
    % the Item's.
    render_to_string(
        accordion([type(single), collapsible(true)],
                  [ accordion_item([open(true), id("item1")], ["Q", "A"]) ]),
        ConvOneItem),
    check(conv_one_details,
          count_occurrences(ConvOneItem, "<details", 1)),
    check(conv_one_summary,
          count_occurrences(ConvOneItem, "<summary", 1)),
    check(conv_trigger_text,
          contains(ConvOneItem, "Q")),
    check(conv_content_text,
          contains(ConvOneItem, "A")),
    check(conv_id_wiring,
          ( extract_attr_value(ConvOneItem, "id", ItemId),
            ItemId == "item1",
            extract_attr_value(ConvOneItem, "aria-controls", ControlsId),
            ControlsId == "item1-content"
          )),
    check(conv_labelledby_matches_trigger_id,
          ( extract_attr_value(ConvOneItem, "aria-labelledby", LabelledbyId),
            LabelledbyId == "item1-trigger"
          )),

    % Three items, type(single): all share ONE `name` group -- the
    % "modern platform exclusive accordions" story, zero JS required.
    render_to_string(
        accordion([id("acc-single"), type(single)],
                  [ accordion_item([open(true)], ["One", "Body one"]),
                    accordion_item([], ["Two", "Body two"]),
                    accordion_item([], ["Three", "Body three"])
                  ]),
        ConvSingleGroup),
    check(conv_single_three_details,
          count_occurrences(ConvSingleGroup, "<details", 3)),
    check(conv_single_shared_name,
          ( extract_attr_value(ConvSingleGroup, "name", GroupName),
            format(string(NamePattern), "name=\"~w\"", [GroupName]),
            count_occurrences(ConvSingleGroup, NamePattern, 3)
          )),

    % type(multiple): no `name` attribute anywhere.
    render_to_string(
        accordion([id("acc-multi"), type(multiple)],
                  [ accordion_item([open(true)], ["One", "Body one"]),
                    accordion_item([open(true)], ["Two", "Body two"])
                  ]),
        ConvMultiGroup),
    check(conv_multi_no_name,
          not_contains(ConvMultiGroup, "name=")),
    check(conv_multi_both_open,
          count_occurrences(ConvMultiGroup, "data-state=\"open\"", 8)),
                              % 4 data-state emitters (Item, Header, Trigger, Content) x 2 open items

    % type(single), collapsible(false): the open item's Trigger carries
    % aria-disabled="true", exactly once.
    render_to_string(
        accordion([id("acc-mandatory"), type(single), collapsible(false)],
                  [ accordion_item([open(true)], ["One", "Body one"]),
                    accordion_item([], ["Two", "Body two"])
                  ]),
        ConvMandatory),
    check(conv_mandatory_aria_disabled_once,
          count_occurrences(ConvMandatory, "aria-disabled=\"true\"", 1)),
    check(conv_mandatory_root_no_data_collapsible,
          not_contains(ConvMandatory, "data-collapsible")),

    render_to_string(
        accordion([id("acc-collapsible"), type(single), collapsible(true)],
                  [ accordion_item([open(true)], ["One", "Body one"]),
                    accordion_item([], ["Two", "Body two"])
                  ]),
        ConvCollapsibleTrue),
    check(conv_collapsible_true_no_aria_disabled,
          not_contains(ConvCollapsibleTrue, "aria-disabled")),
    check(conv_collapsible_true_root_flag,
          contains(ConvCollapsibleTrue, "data-collapsible=\"\"")),

    % disabled(true) at the ItemOpts level routes to Trigger + Header +
    % Content only -- never to the Item's own <details> tag.
    render_to_string(
        accordion([id("acc-disabled"), type(multiple)],
                  [ accordion_item([disabled(true)], ["One", "Body one"]) ]),
        ConvDisabledItem),
    check(conv_disabled_item_three_occurrences,
          % Trigger (summary) + Header (h3) + Content (div) each get
          % data-disabled="" -- the Item (<details>) itself never does.
          count_occurrences(ConvDisabledItem, "data-disabled=\"\"", 3)),
    check(conv_disabled_details_tag_has_no_data_disabled,
          ( extract_open_tag(ConvDisabledItem, "details", DetailsTag),
            not_contains(DetailsTag, "data-disabled")
          )),

    % Raw markup interleaved in Items passes through unmodified.
    render_to_string(
        accordion([id("acc-raw"), type(multiple)],
                  [ accordion_item([], ["One", "Body one"]),
                    p(class("note"), "A plain paragraph, not an Item")
                  ]),
        ConvRaw),
    check(conv_raw_passthrough,
          contains(ConvRaw, "<p class=\"note\">A plain paragraph, not an Item</p>")),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Call` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(accordion, _Order, \accordion_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(accordion, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \accordion_demo), Demo),
    check(demo_has_four_accordions,
          count_occurrences(Demo, "<px-accordion>", 4)),
    check(demo_has_single_and_multiple_types,
          ( contains(Demo, "data-type=\"single\""),
            contains(Demo, "data-type=\"multiple\"") )),
    check(demo_has_name_grouping,
          contains(Demo, "name=")),
    check(demo_has_mandatory_open_aria_disabled,
          contains(Demo, "aria-disabled=\"true\"")),
    check(demo_has_disabled_item,
          contains(Demo, "data-disabled=\"\"")),
    check(demo_has_open_and_closed_states,
          ( contains(Demo, "data-state=\"open\""),
            contains(Demo, "data-state=\"closed\"") )),

    % show some real output for the record
    format("~n--- rendered accordion_demo ---~n~w~n-------------------------------~n",
           [Demo]).
