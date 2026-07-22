/* test/ui/navigation_menu.pl (adr/0026): render-test proof for
   prolog/ui/navigation_menu.pl -- the Navigation Menu port. A plain
   swipl script, no server, no networking (test/ui/hover_card.pl's
   pattern): render_to_string/2 over the templates and assert the
   exact ARIA/data contract documented in
   docs/radix-port-analysis.md's "Navigation Menu" entry, for:

     - navigation_menu_root/2      <px-navigation-menu> wrapper, <nav>,
                                    aria-label (default "Main"),
                                    data-orientation (default
                                    horizontal), class merge
     - navigation_menu_list/2      <ul>, data-orientation
     - navigation_menu_item/2      <li>, class merge, no state
     - navigation_menu_trigger/2   <button type=button>, aria-expanded,
                                    aria-controls (when wired),
                                    data-state, NO aria-haspopup
                                    (unlike Dropdown Menu's Trigger --
                                    this is not a menu)
     - navigation_menu_content/2   aria-labelledby (when wired),
                                    data-state, data-motion (ONLY when
                                    motion(_) \== none -- absent
                                    otherwise, the contract's own
                                    "|null")
     - navigation_menu_link/2      <a>, data-active, href passthrough
     - navigation_menu_trigger_item/2  auto id-wires one Trigger+
                                    Content pair inside an Item
     - navigation_menu_link_item/2 an Item wrapping a bare Link
     - navigation_menu/2           Root wraps List wraps Items,
                                    orientation/aria_label forwarded to
                                    both Root and List

   plus the kitchen-sink demo registration (px_ui:demo/3) rendering end
   to end exactly as prolog/px_ui.pl's ui_show_view embeds it (`\Goal`
   as a div's Children, not the bare atom -- adr/0019's arity-0
   dispatch rule).
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/navigation_menu.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Harness (test/ui/hover_card.pl's pattern).
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
    ->  format("~nAll ui/navigation_menu checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Root: <px-navigation-menu> wrapper, <nav>, aria-label default,
    % data-orientation default, class merge.
    % ===================================================================

    render_to_string(navigation_menu_root([], []), RootDefault),
    check(root_wrapper_is_px_navigation_menu,
          ( sub_string(RootDefault, 0, _, _, "<px-navigation-menu>"),
            sub_string(RootDefault, _, _, 0, "</px-navigation-menu>") )),
    check(root_is_nav,
          ( contains(RootDefault, "<nav "), contains(RootDefault, "</nav>") )),
    check(root_default_aria_label_main,
          contains(RootDefault, "aria-label=\"Main\"")),
    check(root_default_orientation_horizontal,
          contains(RootDefault, "data-orientation=\"horizontal\"")),
    check(root_default_class,
          contains(RootDefault, "class=\"px-navigation-menu\"")),

    render_to_string(
        navigation_menu_root([class("wide"), id("nm1"), orientation(vertical), aria_label("Site")], []),
        RootOpts),
    check(root_class_merged_after_default,
          contains(RootOpts, "class=\"px-navigation-menu wide\"")),
    check(root_id_passed_through,
          contains(RootOpts, "id=\"nm1\"")),
    check(root_orientation_vertical,
          contains(RootOpts, "data-orientation=\"vertical\"")),
    check(root_aria_label_overridden,
          contains(RootOpts, "aria-label=\"Site\"")),

    render_to_string(navigation_menu_root([orientation(diagonal)], []), RootBadOrientation),
    check(root_invalid_orientation_falls_back,
          contains(RootBadOrientation, "data-orientation=\"horizontal\"")),

    % ===================================================================
    % List: <ul>, data-orientation, class merge.
    % ===================================================================

    render_to_string(navigation_menu_list([], []), ListDefault),
    check(list_is_ul,
          ( sub_string(ListDefault, 0, _, _, "<ul "),
            sub_string(ListDefault, _, _, 0, "</ul>") )),
    check(list_default_orientation_horizontal,
          contains(ListDefault, "data-orientation=\"horizontal\"")),
    check(list_default_class,
          contains(ListDefault, "class=\"px-navigation-menu-list\"")),

    render_to_string(navigation_menu_list([orientation(vertical)], []), ListVertical),
    check(list_orientation_vertical,
          contains(ListVertical, "data-orientation=\"vertical\"")),

    % ===================================================================
    % Item: <li>, class merge, no state of its own.
    % ===================================================================

    render_to_string(navigation_menu_item([], "x"), ItemDefault),
    check(item_exact,
          ItemDefault == "<li class=\"px-navigation-menu-item\">x</li>"),

    render_to_string(navigation_menu_item([class("big")], "x"), ItemClass),
    check(item_class_merged,
          contains(ItemClass, "class=\"px-navigation-menu-item big\"")),

    % ===================================================================
    % Trigger: <button type=button>, aria-expanded, aria-controls (when
    % wired), data-state, NO aria-haspopup.
    % ===================================================================

    render_to_string(navigation_menu_trigger([], "Learn"), TriggerDefault),
    check(trigger_is_button,
          ( sub_string(TriggerDefault, 0, _, _, "<button "),
            sub_string(TriggerDefault, _, _, 0, "</button>") )),
    check(trigger_type_button,
          contains(TriggerDefault, "type=\"button\"")),
    check(trigger_default_aria_expanded_false,
          contains(TriggerDefault, "aria-expanded=\"false\"")),
    check(trigger_default_state_closed,
          contains(TriggerDefault, "data-state=\"closed\"")),
    check(trigger_no_aria_controls_when_absent,
          not_contains(TriggerDefault, "aria-controls")),
    check(trigger_no_aria_haspopup,
          not_contains(TriggerDefault, "aria-haspopup")),

    render_to_string(
        navigation_menu_trigger([open(true), controls("c1")], "Learn"),
        TriggerOpen),
    check(trigger_aria_expanded_true,
          contains(TriggerOpen, "aria-expanded=\"true\"")),
    check(trigger_state_open,
          contains(TriggerOpen, "data-state=\"open\"")),
    check(trigger_aria_controls_wired,
          contains(TriggerOpen, "aria-controls=\"c1\"")),

    % ===================================================================
    % Content: aria-labelledby (when wired), data-state, data-motion
    % (only when motion(_) \== none).
    % ===================================================================

    render_to_string(navigation_menu_content([], "Body"), ContentDefault),
    check(content_default_state_closed,
          contains(ContentDefault, "data-state=\"closed\"")),
    check(content_no_aria_labelledby_when_absent,
          not_contains(ContentDefault, "aria-labelledby")),
    check(content_no_data_motion_by_default,
          not_contains(ContentDefault, "data-motion")),

    render_to_string(
        navigation_menu_content([open(true), labelledby("t1"), motion(from_start)], "Body"),
        ContentOpts),
    check(content_state_open,
          contains(ContentOpts, "data-state=\"open\"")),
    check(content_aria_labelledby_wired,
          contains(ContentOpts, "aria-labelledby=\"t1\"")),
    check(content_data_motion_from_start,
          contains(ContentOpts, "data-motion=\"from-start\"")),

    render_to_string(navigation_menu_content([motion(from_end)], "B"), ContentFromEnd),
    check(content_data_motion_from_end,
          contains(ContentFromEnd, "data-motion=\"from-end\"")),
    render_to_string(navigation_menu_content([motion(to_start)], "B"), ContentToStart),
    check(content_data_motion_to_start,
          contains(ContentToStart, "data-motion=\"to-start\"")),
    render_to_string(navigation_menu_content([motion(to_end)], "B"), ContentToEnd),
    check(content_data_motion_to_end,
          contains(ContentToEnd, "data-motion=\"to-end\"")),
    render_to_string(navigation_menu_content([motion(none)], "B"), ContentNoMotion),
    check(content_data_motion_none_omitted,
          not_contains(ContentNoMotion, "data-motion")),

    % ===================================================================
    % Link: <a>, data-active, href passthrough.
    % ===================================================================

    render_to_string(navigation_menu_link([], "GitHub"), LinkDefault),
    check(link_is_anchor,
          ( sub_string(LinkDefault, 0, _, _, "<a "),
            sub_string(LinkDefault, _, _, 0, "</a>") )),
    check(link_default_data_active_false,
          contains(LinkDefault, "data-active=\"false\"")),

    render_to_string(
        navigation_menu_link([active(true), href("/docs")], "Docs"),
        LinkActive),
    check(link_data_active_true,
          contains(LinkActive, "data-active=\"true\"")),
    check(link_href_passthrough,
          contains(LinkActive, "href=\"/docs\"")),

    % ===================================================================
    % navigation_menu_trigger_item/2: auto id-wires Trigger+Content.
    % ===================================================================

    render_to_string(
        navigation_menu_trigger_item([id("nm-t1"), open(true)],
            ["Learn", "Panel body"]),
        TriggerItem),
    check(trigger_item_is_li,
          ( sub_string(TriggerItem, 0, _, _, "<li "),
            sub_string(TriggerItem, _, _, 0, "</li>") )),
    check(trigger_item_trigger_id,
          contains(TriggerItem, "id=\"nm-t1-trigger\"")),
    check(trigger_item_content_id,
          contains(TriggerItem, "id=\"nm-t1-content\"")),
    check(trigger_item_aria_controls_wired,
          contains(TriggerItem, "aria-controls=\"nm-t1-content\"")),
    check(trigger_item_aria_labelledby_wired,
          contains(TriggerItem, "aria-labelledby=\"nm-t1-trigger\"")),
    check(trigger_item_open_threaded_to_both,
          count_occurrences(TriggerItem, "data-state=\"open\"", 2)),
    check(trigger_item_label_present,
          contains(TriggerItem, "Learn")),
    check(trigger_item_content_present,
          contains(TriggerItem, "Panel body")),

    render_to_string(
        navigation_menu_trigger_item([], ["Overview", "Body"]),
        TriggerItemGensym),
    check(trigger_item_gensym_id_when_absent,
          contains(TriggerItemGensym, "id=\"px_navigation_menu_")),

    % ===================================================================
    % navigation_menu_link_item/2: an Item wrapping a bare Link.
    % ===================================================================

    render_to_string(
        navigation_menu_link_item([href("https://github.com"), active(false)], "GitHub"),
        LinkItem),
    check(link_item_is_li,
          ( sub_string(LinkItem, 0, _, _, "<li "),
            sub_string(LinkItem, _, _, 0, "</li>") )),
    check(link_item_no_trigger,
          not_contains(LinkItem, "<button")),
    check(link_item_href,
          contains(LinkItem, "href=\"https://github.com\"")),
    check(link_item_text,
          contains(LinkItem, "GitHub")),

    % ===================================================================
    % navigation_menu/2: Root wraps List wraps Items, orientation/
    % aria_label forwarded to both Root and List.
    % ===================================================================

    render_to_string(
        navigation_menu([orientation(vertical), aria_label("Sidebar")],
            [ navigation_menu_link_item([href("#a")], "A"),
              navigation_menu_link_item([href("#b")], "B")
            ]),
        Group1),
    check(group_wrapper_is_px_navigation_menu,
          ( sub_string(Group1, 0, _, _, "<px-navigation-menu>"),
            sub_string(Group1, _, _, 0, "</px-navigation-menu>") )),
    check(group_orientation_on_root,
          contains(Group1, "<nav aria-label=\"Sidebar\" data-orientation=\"vertical\"")),
    check(group_orientation_on_list,
          count_occurrences(Group1, "data-orientation=\"vertical\"", 2)),
    check(group_items_present,
          ( contains(Group1, "href=\"#a\""), contains(Group1, "href=\"#b\"") )),

    render_to_string(navigation_menu([], []), Group2),
    check(group_default_orientation_horizontal,
          contains(Group2, "data-orientation=\"horizontal\"")),
    check(group_default_aria_label_main,
          contains(Group2, "aria-label=\"Main\"")),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Goal` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(navigation_menu, _Order, \navigation_menu_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(navigation_menu, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \navigation_menu_demo), Demo),
    check(demo_has_two_navigation_menus,
          count_occurrences(Demo, "<px-navigation-menu>", 2)),
    check(demo_has_learn_trigger,
          contains(Demo, ">Learn<")),
    check(demo_has_overview_trigger,
          contains(Demo, ">Overview<")),
    check(demo_has_github_link,
          contains(Demo, "github.com")),
    check(demo_has_featured_card,
          contains(Demo, "px-navigation-menu-featured")),
    check(demo_has_link_cards,
          contains(Demo, "px-navigation-menu-card")),
    check(demo_has_vertical_orientation_section,
          contains(Demo, "data-orientation=\"vertical\"")),
    check(demo_has_active_link,
          contains(Demo, "data-active=\"true\"")),
    check(demo_no_role_menu_anywhere,
          not_contains(Demo, "role=\"menu\"")),
    check(demo_no_aria_haspopup_anywhere,
          not_contains(Demo, "aria-haspopup")),

    % show some real output for the record
    format("~n--- rendered navigation_menu_demo (truncated) ---~n"),
    ( string_length(Demo, DemoLen), DemoLen > 2000
    -> sub_string(Demo, 0, 2000, _, DemoHead), format("~w...~n", [DemoHead])
    ;  format("~w~n", [Demo])
    ),
    format("-----------------------------------~n").
