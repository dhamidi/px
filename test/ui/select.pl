/* test/ui/select.pl (adr/0026): render-test proof for
   prolog/ui/select.pl -- the Select port, the porting series' finale
   (33/33). A plain swipl script, no server, no networking (test/ui/
   popover.pl's/dropdown_menu.pl's pattern): render_to_string/2 over the
   templates and assert the exact ARIA/data contract this task's brief
   and prolog/ui/select.pl's own header document, for:

     - select_root/2          the native-<select> fallback + upgrade
                               wiring: real <select> with a synthesized
                               placeholder <option>, flattened
                               <option>/<optgroup> tree matching Items,
                               `selected` on the right native option;
                               the custom Trigger (aria-haspopup=listbox,
                               aria-expanded, aria-controls, data-state,
                               data-placeholder)+Value+Icon+Content
                               (role=listbox, popover=auto, data-side=
                               bottom, aria-labelledby) wired to the
                               SAME Items, id-generation, class merge
     - select_item/1,2         role=option, aria-selected, data-state
                               (checked|unchecked), data-value,
                               data-text-value, disabled degrade,
                               required value(_), textvalue(_)
                               requirement when Children isn't plain
                               text
     - select_item_text/2, select_item_indicator/2  the two Item
                               sub-parts
     - select_group/2          role=group, aria-labelledby auto-wired to
                               a leading select_label/2's id
     - select_label/2          no role, id pass-through
     - select_separator/1      delegates to separator_root/2
     - the kitchen-sink demo registration (px_ui:demo/3) rendering end
       to end exactly as prolog/px_ui.pl's ui_show_view embeds it
       (`\Goal` as a div's Children, not the bare atom -- adr/0019's
       arity-0 dispatch rule), including groups/labels/separator/a
       disabled item/a preselected variant/a placeholder variant/a
       surrounding <form>.
*/

:- use_module(library(pcre)).
:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/select.pl').

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

throws(Goal) :-
    catch((Goal, fail), _, true).

main :-
    tests,
    failed_count(N),
    (   N =:= 0
    ->  format("~nAll ui/select checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % select_root/2: wrapper, native <select> fallback, Trigger/Value/
    % Icon/Content wiring -- nothing selected (placeholder state).
    % ===================================================================

    render_to_string(
        select_root([id("s1"), name(fruit), placeholder("Pick a fruit")],
          [ select_item([value(apple)], "Apple"),
            select_item([value(banana)], "Banana")
          ]),
        R1),

    check(root_wrapper_is_px_select,
          ( sub_string(R1, 0, _, _, "<px-select>"),
            sub_string(R1, _, _, 0, "</px-select>") )),
    check(root_wrapper_div_class,
          contains(R1, "class=\"px-select\"")),
    check(root_wrapper_div_id,
          contains(R1, "id=\"s1\"")),

    % -- Native <select> fallback: real, form-submittable, placeholder
    %    option selected, both items present, none marked selected. ----
    check(native_select_present,
          contains(R1, "<select id=\"s1-native\" class=\"px-select-native\" name=\"fruit\">")),
    check(native_placeholder_option_selected_when_nothing_chosen,
          contains(R1, "<option value=\"\" disabled hidden selected>Pick a fruit</option>")),
    check(native_options_present,
          ( contains(R1, "<option value=\"apple\">Apple</option>"),
            contains(R1, "<option value=\"banana\">Banana</option>") )),

    % -- Trigger: aria-haspopup=listbox, aria-expanded, aria-controls,
    %    data-state, data-placeholder (nothing selected). ---------------
    check(trigger_present,
          contains(R1, "<button type=\"button\" id=\"s1-trigger\" aria-haspopup=\"listbox\" aria-controls=\"s1-content\" aria-expanded=\"false\" data-placeholder=\"\" data-state=\"closed\" class=\"px-select-trigger\">")),

    % -- Value: shows the placeholder text, data-placeholder present. ---
    check(value_shows_placeholder_text,
          contains(R1, "class=\"px-select-value\">Pick a fruit</span>")),
    check(value_data_placeholder_present,
          contains(R1, "<span data-placeholder=\"\" class=\"px-select-value\"")),

    % -- Icon: aria-hidden, default chevron glyph. -----------------------
    check(icon_aria_hidden,
          contains(R1, "<span aria-hidden=\"true\" class=\"px-select-icon\">▾</span>")),

    % -- Content: role=listbox, native popover=auto, tabindex=-1,
    %    data-state, data-side=bottom (popper mode only -- module
    %    header), aria-labelledby Trigger's id. --------------------------
    check(content_role_listbox,
          contains(R1, "role=\"listbox\"")),
    check(content_native_popover_auto,
          contains(R1, "popover=\"auto\"")),
    check(content_tabindex,
          contains(R1, "id=\"s1-content\" popover=\"auto\" tabindex=\"-1\"")),
    check(content_data_state_closed,
          contains(R1, "data-state=\"closed\" data-side=\"bottom\"")),
    check(content_aria_labelledby_trigger,
          contains(R1, "aria-labelledby=\"s1-trigger\"")),

    % ===================================================================
    % select_root/2: one Item marked selected(true) -- no placeholder
    % anywhere, native <option selected> on the right one, Value shows
    % its text.
    % ===================================================================

    render_to_string(
        select_root([id("s2"), name(fruit2)],
          [ select_item([value(apple)], "Apple"),
            select_item([value(banana), selected(true)], "Banana")
          ]),
        R2),

    check(selected_native_option_marked,
          contains(R2, "<option value=\"banana\" selected>Banana</option>")),
    check(selected_placeholder_option_not_selected,
          not_contains(R2, "<option value=\"\" disabled hidden selected>")),
    check(selected_placeholder_option_still_present_unselected,
          contains(R2, "<option value=\"\" disabled hidden>Select an option…</option>")),
    check(selected_trigger_no_data_placeholder,
          not_contains(R2, "data-placeholder")),
    check(selected_value_shows_item_text,
          contains(R2, "class=\"px-select-value\">Banana</span>")),
    check(selected_item_aria_selected_true,
          contains(R2, "aria-selected=\"true\"")),
    check(selected_item_data_state_checked,
          contains(R2, "data-value=\"banana\" data-text-value=\"Banana\" class=\"px-select-item\"")),

    % ===================================================================
    % select_root/2: disabled/required forwarded to the native <select>
    % only; disabled Trigger too.
    % ===================================================================

    render_to_string(
        select_root([id("s3"), disabled(true), required(true)],
          [select_item([value(x)], "X")]),
        R3),
    check(disabled_native_select,
          contains(R3, "<select id=\"s3-native\" class=\"px-select-native\" disabled required>")),
    check(disabled_trigger_attr,
          contains(R3, "disabled data-disabled=\"\" data-state=\"closed\"")),

    % ===================================================================
    % select_root/2: gensym'd id when omitted.
    % ===================================================================

    render_to_string(select_root([], [select_item([value(x)], "X")]), R4),
    check(gensym_id_used_consistently,
          ( sub_string(R4, _, _, _, "<px-select><div id=\""),
            sub_string(R4, B, _, _, "-trigger\""),
            sub_string(R4, B2, _, _, "-content\""),
            B > 0, B2 > 0 )),

    % ===================================================================
    % select_item/1,2: role=option, aria-selected, data-state, disabled
    % degrade, value(_) required, textvalue(_) requirement.
    % ===================================================================

    render_to_string(select_item([value(apple)], "Apple"), Item1),
    check(item_role_option,
          contains(Item1, "role=\"option\"")),
    check(item_tabindex,
          contains(Item1, "tabindex=\"-1\"")),
    check(item_aria_selected_false_default,
          contains(Item1, "aria-selected=\"false\"")),
    check(item_data_state_unchecked_default,
          contains(Item1, "data-state=\"unchecked\"")),
    check(item_data_value,
          contains(Item1, "data-value=\"apple\"")),
    check(item_data_text_value_from_children,
          contains(Item1, "data-text-value=\"Apple\"")),
    check(item_indicator_present,
          contains(Item1, "class=\"px-select-item-indicator\"")),
    check(item_text_present,
          contains(Item1, "class=\"px-select-item-text\">Apple</span>")),

    render_to_string(select_item([value(x), selected(true)], "X"), Item2),
    check(item_selected_aria_true,
          contains(Item2, "aria-selected=\"true\"")),
    check(item_selected_state_checked,
          contains(Item2, "data-state=\"checked\"")),

    render_to_string(select_item([value(x), disabled(true)], "X"), Item3),
    check(item_disabled_attrs,
          ( contains(Item3, "data-disabled=\"\""),
            contains(Item3, "aria-disabled=\"true\"") )),

    render_to_string(select_item([value(x)]), Item4),
    check(item_no_label_shorthand,
          contains(Item4, "role=\"option\"")),

    check(item_missing_value_throws,
          throws(render_to_string(select_item([], "X"), _))),

    render_to_string(
        select_item([value(x), textvalue("Rich Label")], [span([], "icon"), "Rich"]),
        Item5),
    check(item_textvalue_used_for_data_text_value,
          contains(Item5, "data-text-value=\"Rich Label\"")),

    check(item_rich_children_without_textvalue_throws,
          throws(render_to_string(select_item([value(x)], [span([], "icon")]), _))),

    % ===================================================================
    % select_item_text/2, select_item_indicator/2.
    % ===================================================================

    render_to_string(select_item_text([], "Apple"), TextEl),
    check(item_text_exact,
          TextEl == "<span class=\"px-select-item-text\">Apple</span>"),

    render_to_string(select_item_indicator([state(checked)], "✓"), IndicatorEl),
    check(indicator_aria_hidden,
          contains(IndicatorEl, "aria-hidden=\"true\"")),
    check(indicator_state_checked,
          contains(IndicatorEl, "data-state=\"checked\"")),

    % ===================================================================
    % select_group/2: role=group, aria-labelledby auto-wired to a
    % leading select_label/2's id (gensym'd if it has none).
    % ===================================================================

    render_to_string(
        select_group([], [select_label([], "Fruits"), select_item([value(apple)], "Apple")]),
        Group1),
    check(group_role,
          contains(Group1, "role=\"group\"")),
    check(group_labelledby_matches_label_id,
          ( re_matchsub("aria-labelledby=\"([^\"]+)\"", Group1, M1, []),
            re_matchsub("<div class=\"px-select-label\" id=\"([^\"]+)\"", Group1, M2, []),
            get_dict(1, M1, LabelledBy),
            get_dict(1, M2, LabelId),
            LabelledBy == LabelId )),

    render_to_string(
        select_group([], [select_label([id("g1-label")], "Fruits"), select_item([value(apple)], "Apple")]),
        Group2),
    check(group_labelledby_respects_explicit_label_id,
          contains(Group2, "aria-labelledby=\"g1-label\"")),

    render_to_string(select_group([], [select_item([value(apple)], "Apple")]), Group3),
    check(group_no_label_no_labelledby,
          not_contains(Group3, "aria-labelledby")),

    % ===================================================================
    % select_label/2: no role.
    % ===================================================================

    render_to_string(select_label([], "Fruits"), LabelEl),
    check(label_no_role,
          not_contains(LabelEl, "role=")),
    check(label_class,
          contains(LabelEl, "class=\"px-select-label\"")),

    % ===================================================================
    % select_separator/1: delegates to separator_root/2.
    % ===================================================================

    render_to_string(select_separator([]), SepEl),
    check(separator_role,
          contains(SepEl, "role=\"separator\"")),
    check(separator_class_merged,
          contains(SepEl, "px-select-separator")),

    % ===================================================================
    % Groups + separator inside select_root/2: full composition, native
    % <optgroup> present, separator contributes nothing to the native
    % <select>.
    % ===================================================================

    render_to_string(
        select_root([id("s5"), name(fruit)],
          [ select_group([], [select_label([], "Fruits"), select_item([value(apple)], "Apple")]),
            select_separator([]),
            select_group([], [select_label([], "Vegetables"), select_item([value(carrot)], "Carrot")])
          ]),
        R5),
    check(native_optgroup_present,
          ( contains(R5, "<optgroup label=\"Fruits\">"),
            contains(R5, "<optgroup label=\"Vegetables\">") )),
    check(native_optgroup_wraps_options,
          contains(R5, "<optgroup label=\"Fruits\"><option value=\"apple\">Apple</option></optgroup>")),
    check(custom_group_role_present,
          count_occurrences(R5, "role=\"group\"", 2)),
    check(custom_separator_present,
          contains(R5, "px-select-separator")),

    % ===================================================================
    % Kitchen-sink demo registration + full render (adr/0026 rule 7b),
    % exactly as prolog/px_ui.pl's ui_show_view embeds it.
    % ===================================================================

    render_to_string(div(class("ui-demo"), \select_demo), Demo),
    check(demo_registered,
          px_ui:demo(select, _, _)),
    check(demo_has_groups_and_labels,
          ( contains(Demo, "Fruits"), contains(Demo, "Vegetables") )),
    check(demo_has_separator,
          contains(Demo, "px-select-separator")),
    check(demo_has_disabled_item,
          contains(Demo, "Blueberry")),
    check(demo_disabled_item_marked,
          ( sub_string(Demo, B3, _, _, "Blueberry"),
            sub_string(Demo, _, _, _, "data-value=\"blueberry\""),
            B3 > 0 )),
    check(demo_has_preselected_variant,
          ( contains(Demo, "select-demo-preselected"),
            contains(Demo, "Preselected") )),
    check(demo_has_placeholder_variant,
          ( contains(Demo, "Pick a color"),
            contains(Demo, "Placeholder variant") )),
    check(demo_wrapped_in_form,
          ( sub_string(Demo, _, _, _, "<form action=\"\" method=\"get\""),
            sub_string(Demo, _, _, _, "type=\"submit\"") )),
    check(demo_native_select_present,
          contains(Demo, "class=\"px-select-native\"")),

    format("~n--- select.pl render tests complete ---~n").
