/* test/ui/_menu.pl (adr/0026): render-test proof for
   prolog/ui/_menu.pl -- the shared Menu part templates every menu
   wrapper (Dropdown Menu first) composes. A plain swipl script, no
   server, no networking (test/ui/toggle_group.pl's pattern):
   render_to_string/2 over the templates and assert the exact
   ARIA/data contract documented in prolog/ui/_menu.pl's own module
   header (itself transcribing docs/radix-port-analysis.md's "Menu"
   entry), for:

     - menu_content / menu_sub_content  role="menu", popover="auto",
       tabindex="-1", data-state, data-side/data-align defaults
       (bottom/start for Content, right/start for SubContent), the
       shared "px-menu-content" class both carry (SubContent adds
       "px-menu-sub-content" additionally, never instead)
     - menu_item      role="menuitem", disabled -> data-disabled +
                       aria-disabled, textvalue -> data-text-value,
                       close_on_select(_) -> data-close-on-select
                       (omitted entirely when not given)
     - menu_checkbox_item  role="menuitemcheckbox", aria-checked,
                       data-state, an always-rendered Indicator whose
                       own data-state mirrors the item's, default
                       close_on_select(false) (rendered explicitly)
     - menu_radio_group / menu_radio_item  role="group" /
                       role="menuitemradio", data-value
     - menu_label      no role
     - menu_separator  delegates to separator_root/2 -- role="separator",
                       both classes present
     - menu_sub / menu_sub_trigger / menu_sub_content  wrapper
                       data-state, aria-haspopup="menu", aria-expanded,
                       aria-controls wired to SubContent's id
     - menu_item_indicator  aria-hidden, data-state
     - menu_arrow      aria-hidden, pure markup

   plus the "no px_ui:demo/3 registered here" contract (adr/0026 rule 1
   -- _menu.pl is shared vocabulary, not itself a kitchen-sink
   component).
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/separator.pl').
:- use_module('../../prolog/ui/_menu.pl').

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
    ->  format("~nAll ui/_menu checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % menu_content/2 -- root level defaults: side=bottom, align=start.
    % ===================================================================

    render_to_string(menu_content([id("c1")], []), Content),
    check(content_role_menu, contains(Content, "role=\"menu\"")),
    check(content_popover_auto, contains(Content, "popover=\"auto\"")),
    check(content_tabindex, contains(Content, "tabindex=\"-1\"")),
    check(content_id, contains(Content, "id=\"c1\"")),
    check(content_default_closed, contains(Content, "data-state=\"closed\"")),
    check(content_default_side_bottom, contains(Content, "data-side=\"bottom\"")),
    check(content_default_align_start, contains(Content, "data-align=\"start\"")),
    check(content_orientation_vertical, contains(Content, "data-orientation=\"vertical\"")),
    check(content_class, contains(Content, "class=\"px-menu-content\"")),
    check(content_no_sub_class, not_contains(Content, "px-menu-sub-content")),

    render_to_string(menu_content([open(true), labelledby("trig1")], []), ContentOpen),
    check(content_open_state, contains(ContentOpen, "data-state=\"open\"")),
    check(content_labelledby, contains(ContentOpen, "aria-labelledby=\"trig1\"")),

    % ===================================================================
    % menu_sub_content/2 -- default side=right, align=start; shares the
    % "px-menu-content" class AND adds "px-menu-sub-content".
    % ===================================================================

    render_to_string(menu_sub_content([id("s1")], []), SubContent),
    check(sub_content_role_menu, contains(SubContent, "role=\"menu\"")),
    check(sub_content_default_side_right, contains(SubContent, "data-side=\"right\"")),
    check(sub_content_default_align_start, contains(SubContent, "data-align=\"start\"")),
    check(sub_content_both_classes,
          contains(SubContent, "class=\"px-menu-content px-menu-sub-content\"")),

    % ===================================================================
    % menu_item/1,2 -- role, tabindex, disabled, textvalue,
    % close_on_select.
    % ===================================================================

    render_to_string(menu_item([], "Copy"), Item),
    check(item_role_menuitem, contains(Item, "role=\"menuitem\"")),
    check(item_tabindex, contains(Item, "tabindex=\"-1\"")),
    check(item_no_disabled, not_contains(Item, "data-disabled")),
    check(item_no_close_on_select, not_contains(Item, "data-close-on-select")),
    check(item_class, contains(Item, "class=\"px-menu-item\"")),
    check(item_exact,
          Item == "<div role=\"menuitem\" tabindex=\"-1\" class=\"px-menu-item\">Copy</div>"),

    render_to_string(menu_item([disabled(true)], "Delete"), ItemDisabled),
    check(item_disabled_data_attr, contains(ItemDisabled, "data-disabled=\"\"")),
    check(item_disabled_aria_attr, contains(ItemDisabled, "aria-disabled=\"true\"")),

    render_to_string(menu_item([textvalue("zzz")], [span("Weird Label")]), ItemTextValue),
    check(item_textvalue, contains(ItemTextValue, "data-text-value=\"zzz\"")),

    render_to_string(menu_item([close_on_select(false)], "Stay open"), ItemStaysOpen),
    check(item_close_on_select_false, contains(ItemStaysOpen, "data-close-on-select=\"false\"")),

    render_to_string(menu_item([]), ItemNoLabel),
    check(item_no_label_shorthand, contains(ItemNoLabel, "></div>")),

    % ===================================================================
    % menu_checkbox_item/2 -- aria-checked, data-state, always-rendered
    % Indicator, default close_on_select(false).
    % ===================================================================

    render_to_string(menu_checkbox_item([checked(true)], "Show hidden files"), CheckOn),
    check(checkbox_role, contains(CheckOn, "role=\"menuitemcheckbox\"")),
    check(checkbox_aria_checked_true, contains(CheckOn, "aria-checked=\"true\"")),
    check(checkbox_data_state_checked, contains(CheckOn, "data-state=\"checked\"")),
    check(checkbox_default_close_on_select_false,
          contains(CheckOn, "data-close-on-select=\"false\"")),
    check(checkbox_indicator_present,
          contains(CheckOn, "class=\"px-menu-item-indicator\"")),
    check(checkbox_indicator_state_matches,
          contains(CheckOn, "data-state=\"checked\" class=\"px-menu-item-indicator\"")),
    check(checkbox_two_classes,
          contains(CheckOn, "class=\"px-menu-item px-menu-checkbox-item\"")),

    render_to_string(menu_checkbox_item([], "Off"), CheckOff),
    check(checkbox_default_unchecked,
          ( contains(CheckOff, "aria-checked=\"false\""),
            contains(CheckOff, "data-state=\"unchecked\"") )),

    render_to_string(menu_checkbox_item([close_on_select(true)], "Closes"), CheckCloses),
    check(checkbox_close_on_select_override,
          contains(CheckCloses, "data-close-on-select=\"true\"")),

    render_to_string(menu_checkbox_item([disabled(true)], "Disabled"), CheckDisabled),
    check(checkbox_disabled, contains(CheckDisabled, "data-disabled=\"\"")),

    % ===================================================================
    % menu_radio_group/2, menu_radio_item/2.
    % ===================================================================

    render_to_string(menu_radio_group([aria_label("Zoom")], []), RadioGroup),
    check(radio_group_role, contains(RadioGroup, "role=\"group\"")),
    check(radio_group_aria_label, contains(RadioGroup, "aria-label=\"Zoom\"")),
    check(radio_group_class, contains(RadioGroup, "class=\"px-menu-radio-group\"")),

    render_to_string(menu_radio_item([checked(true), value("md")], "Medium"), RadioOn),
    check(radio_role, contains(RadioOn, "role=\"menuitemradio\"")),
    check(radio_aria_checked_true, contains(RadioOn, "aria-checked=\"true\"")),
    check(radio_data_value, contains(RadioOn, "data-value=\"md\"")),
    check(radio_two_classes,
          contains(RadioOn, "class=\"px-menu-item px-menu-radio-item\"")),
    check(radio_default_close_on_select_false,
          contains(RadioOn, "data-close-on-select=\"false\"")),

    % ===================================================================
    % menu_label/2 -- no role.
    % ===================================================================

    render_to_string(menu_label([], "Appearance"), Label),
    check(label_no_role, not_contains(Label, "role=")),
    check(label_class, contains(Label, "class=\"px-menu-label\"")),
    check(label_exact,
          Label == "<div class=\"px-menu-label\">Appearance</div>"),

    % ===================================================================
    % menu_separator/1 -- delegates to separator_root/2.
    % ===================================================================

    render_to_string(menu_separator([]), Separator),
    check(separator_role, contains(Separator, "role=\"separator\"")),
    check(separator_orientation, contains(Separator, "data-orientation=\"horizontal\"")),
    check(separator_both_classes,
          contains(Separator, "class=\"px-separator px-menu-separator\"")),

    % ===================================================================
    % menu_sub/2 -- wrapper + SubTrigger + SubContent wiring.
    % ===================================================================

    render_to_string(
        menu_sub([id("share")], ["Share", [menu_item([], "Email")]]),
        Sub),
    check(sub_wrapper_class, contains(Sub, "class=\"px-menu-sub\"")),
    check(sub_wrapper_data_state, contains(Sub, "data-state=\"closed\"")),
    check(sub_trigger_haspopup, contains(Sub, "aria-haspopup=\"menu\"")),
    check(sub_trigger_aria_expanded_false, contains(Sub, "aria-expanded=\"false\"")),
    check(sub_trigger_controls_matches_content_id,
          ( contains(Sub, "aria-controls=\"share-content\""),
            contains(Sub, "id=\"share-content\"") )),
    check(sub_content_default_side_right, contains(Sub, "data-side=\"right\"")),

    render_to_string(
        menu_sub([open(true), disabled(true)], ["More", []]),
        SubOpen),
    check(sub_open_state, contains(SubOpen, "data-state=\"open\"")),
    check(sub_trigger_disabled, contains(SubOpen, "data-disabled=\"\"")),

    % ===================================================================
    % menu_sub_trigger/2 standalone.
    % ===================================================================

    render_to_string(menu_sub_trigger([controls("x-content")], "More Tools"), SubTrigger),
    check(sub_trigger_role, contains(SubTrigger, "role=\"menuitem\"")),
    check(sub_trigger_controls, contains(SubTrigger, "aria-controls=\"x-content\"")),
    check(sub_trigger_class,
          contains(SubTrigger, "class=\"px-menu-item px-menu-sub-trigger\"")),

    % ===================================================================
    % menu_item_indicator/2 -- standalone, default state(unchecked).
    % ===================================================================

    render_to_string(menu_item_indicator([], "✓"), Indicator),
    check(indicator_aria_hidden, contains(Indicator, "aria-hidden=\"true\"")),
    check(indicator_default_state, contains(Indicator, "data-state=\"unchecked\"")),

    render_to_string(menu_item_indicator([state(checked)], "✓"), IndicatorChecked),
    check(indicator_explicit_state, contains(IndicatorChecked, "data-state=\"checked\"")),

    % ===================================================================
    % menu_arrow/1.
    % ===================================================================

    render_to_string(menu_arrow([]), Arrow),
    check(arrow_aria_hidden, contains(Arrow, "aria-hidden=\"true\"")),
    check(arrow_class, contains(Arrow, "class=\"px-menu-arrow\"")),
    check(arrow_exact,
          Arrow == "<div aria-hidden=\"true\" class=\"px-menu-arrow\"></div>"),

    % ===================================================================
    % No px_ui:demo/3 registered by this module (adr/0026 rule 1 --
    % shared vocabulary, not a kitchen-sink component).
    % ===================================================================

    check(no_demo_registered,
          \+ catch(px_ui:demo(menu, _, _), _, fail)),

    format("~n--- rendered menu_checkbox_item (checked) ---~n~w~n-----------------------------------~n",
           [CheckOn]).
