/* test/ui/scroll_area.pl (adr/0026): render-test proof for
   prolog/ui/scroll_area.pl -- the Scroll Area port. A plain swipl
   script, no server, no networking (test/ui/hover_card.pl's pattern):
   render_to_string/2 over the templates and assert the exact
   ARIA/data contract documented in docs/radix-port-analysis.md's
   "Scroll Area" entry, for:

     - scroll_area_root/2       <px-scroll-area> wrapper, class merge/
                                  pass-through, data-type (default
                                  "auto", overridable),
                                  data-scroll-hide-delay (default 600,
                                  overridable)
     - scroll_area_viewport/2   NO role/aria/tabindex anywhere, class
                                  merge
     - scroll_area_scrollbar/2  data-orientation (default vertical),
                                  data-state (visible for auto/always,
                                  hidden for scroll/hover, by default;
                                  visible(Bool) overrides), NO role/
                                  aria-hidden/aria-orientation
     - scroll_area_thumb/1      no role/aria, class merge, no children
     - scroll_area_corner/1     no role/aria, class merge, no children
     - scroll_area/2            Root wraps Viewport+Scrollbar(s)(+Corner
                                  for orientation(both)), type/
                                  scroll_hide_delay forwarded to Root
                                  AND to every Scrollbar, orientation
                                  never leaks onto Root as a raw
                                  attribute

   plus the kitchen-sink demo registration (px_ui:demo/3) rendering end
   to end exactly as prolog/px_ui.pl's ui_show_view embeds it (`\Goal`
   as a div's Children, not the bare atom -- adr/0019's arity-0
   dispatch rule), and the css_coverage-relevant class names every
   ui.css selector for this component must find.
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/scroll_area.pl').

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
    ->  format("~nAll ui/scroll_area checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Root: <px-scroll-area> wrapper, class merge, type/scroll-hide-delay
    % defaults and overrides.
    % ===================================================================

    render_to_string(scroll_area_root([], []), RootDefault),
    check(root_wrapper_is_px_scroll_area,
          ( sub_string(RootDefault, 0, _, _, "<px-scroll-area>"),
            sub_string(RootDefault, _, _, 0, "</px-scroll-area>") )),
    check(root_default_class,
          contains(RootDefault, "class=\"px-scroll-area\"")),
    check(root_default_type_auto,
          contains(RootDefault, "data-type=\"auto\"")),
    check(root_default_scroll_hide_delay_600,
          contains(RootDefault, "data-scroll-hide-delay=\"600\"")),
    check(root_no_role_or_aria,
          ( not_contains(RootDefault, "role"),
            not_contains(RootDefault, "aria-") )),

    render_to_string(
        scroll_area_root([class("wide"), id("g1"), type(hover), scroll_hide_delay(250)], []),
        RootOpts),
    check(root_class_merged_after_default,
          contains(RootOpts, "class=\"px-scroll-area wide\"")),
    check(root_id_passed_through,
          contains(RootOpts, "id=\"g1\"")),
    check(root_type_hover,
          contains(RootOpts, "data-type=\"hover\"")),
    check(root_scroll_hide_delay_overridden,
          contains(RootOpts, "data-scroll-hide-delay=\"250\"")),

    render_to_string(scroll_area_root([type(sideways)], []), RootBadType),
    check(root_invalid_type_falls_back_to_auto,
          contains(RootBadType, "data-type=\"auto\"")),

    % ===================================================================
    % Viewport: no role/aria/tabindex anywhere, class merge.
    % ===================================================================

    render_to_string(scroll_area_viewport([], "content"), ViewportDefault),
    check(viewport_exact,
          ViewportDefault ==
              "<div class=\"px-scroll-area-viewport\">content</div>"),
    check(viewport_no_role_aria_tabindex,
          ( not_contains(ViewportDefault, "role"),
            not_contains(ViewportDefault, "aria-"),
            not_contains(ViewportDefault, "tabindex") )),

    render_to_string(scroll_area_viewport([class("tall")], "x"), ViewportClass),
    check(viewport_class_merged,
          contains(ViewportClass, "class=\"px-scroll-area-viewport tall\"")),

    % ===================================================================
    % Scrollbar: data-orientation (default vertical), data-state (visible
    % for auto/always, hidden for scroll/hover by default; visible(Bool)
    % overrides), no role/aria anywhere.
    % ===================================================================

    render_to_string(scroll_area_scrollbar([], []), ScrollbarDefault),
    check(scrollbar_default_orientation_vertical,
          contains(ScrollbarDefault, "data-orientation=\"vertical\"")),
    check(scrollbar_default_state_visible,   % type(_) defaults to auto
          contains(ScrollbarDefault, "data-state=\"visible\"")),
    check(scrollbar_no_role_or_aria,
          ( not_contains(ScrollbarDefault, "role"),
            not_contains(ScrollbarDefault, "aria-hidden"),
            not_contains(ScrollbarDefault, "aria-orientation") )),

    render_to_string(scroll_area_scrollbar([orientation(horizontal)], []), ScrollbarHoriz),
    check(scrollbar_orientation_horizontal,
          contains(ScrollbarHoriz, "data-orientation=\"horizontal\"")),

    render_to_string(scroll_area_scrollbar([type(always)], []), ScrollbarAlways),
    check(scrollbar_type_always_visible,
          contains(ScrollbarAlways, "data-state=\"visible\"")),

    render_to_string(scroll_area_scrollbar([type(hover)], []), ScrollbarHover),
    check(scrollbar_type_hover_hidden_by_default,
          contains(ScrollbarHover, "data-state=\"hidden\"")),

    render_to_string(scroll_area_scrollbar([type(scroll)], []), ScrollbarScroll),
    check(scrollbar_type_scroll_hidden_by_default,
          contains(ScrollbarScroll, "data-state=\"hidden\"")),

    render_to_string(scroll_area_scrollbar([type(hover), visible(true)], []), ScrollbarHoverForced),
    check(scrollbar_visible_override_wins_over_type,
          contains(ScrollbarHoverForced, "data-state=\"visible\"")),

    render_to_string(scroll_area_scrollbar([orientation(sideways)], []), ScrollbarBadOrientation),
    check(scrollbar_invalid_orientation_falls_back,
          contains(ScrollbarBadOrientation, "data-orientation=\"vertical\"")),

    % ===================================================================
    % Thumb: class merge, no children, no role/aria.
    % ===================================================================

    render_to_string(scroll_area_thumb([]), ThumbDefault),
    check(thumb_exact,
          ThumbDefault == "<div class=\"px-scroll-area-thumb\"></div>"),

    render_to_string(scroll_area_thumb([class("big")]), ThumbClass),
    check(thumb_class_merged,
          contains(ThumbClass, "class=\"px-scroll-area-thumb big\"")),

    % ===================================================================
    % Corner: class merge, no children, no role/aria.
    % ===================================================================

    render_to_string(scroll_area_corner([]), CornerDefault),
    check(corner_exact,
          CornerDefault == "<div class=\"px-scroll-area-corner\"></div>"),

    % ===================================================================
    % Convenience `scroll_area/2`: Root wraps Viewport+Scrollbar(s)(+
    % Corner for orientation(both)); type/scroll_hide_delay forwarded to
    % Root AND to every Scrollbar; orientation never leaks onto Root.
    % ===================================================================

    render_to_string(scroll_area([id("s1")], "body"), Vertical),
    check(vertical_wrapper_is_px_scroll_area,
          ( sub_string(Vertical, 0, _, _, "<px-scroll-area>"),
            sub_string(Vertical, _, _, 0, "</px-scroll-area>") )),
    check(vertical_has_one_scrollbar,
          count_occurrences(Vertical, "px-scroll-area-scrollbar", 1)),
    check(vertical_scrollbar_is_vertical,
          contains(Vertical, "data-orientation=\"vertical\"")),
    check(vertical_no_corner,
          not_contains(Vertical, "px-scroll-area-corner")),
    check(vertical_content_present,
          contains(Vertical, "body")),
    check(vertical_root_no_raw_orientation_attr,
          not_contains(Vertical, " orientation=")),

    render_to_string(scroll_area([orientation(horizontal)], "row"), Horizontal),
    check(horizontal_has_one_scrollbar,
          count_occurrences(Horizontal, "px-scroll-area-scrollbar", 1)),
    check(horizontal_scrollbar_is_horizontal,
          contains(Horizontal, "data-orientation=\"horizontal\"")),
    check(horizontal_no_corner,
          not_contains(Horizontal, "px-scroll-area-corner")),

    render_to_string(scroll_area([orientation(both), type(always)], "grid"), Both),
    check(both_has_two_scrollbars,
          count_occurrences(Both, "px-scroll-area-scrollbar", 2)),
    check(both_has_vertical_and_horizontal,
          ( contains(Both, "data-orientation=\"vertical\""),
            contains(Both, "data-orientation=\"horizontal\"") )),
    check(both_has_corner,
          contains(Both, "px-scroll-area-corner")),
    check(both_type_forwarded_to_root,
          contains(Both, "data-type=\"always\"")),
    check(both_type_forwarded_to_every_scrollbar,
          count_occurrences(Both, "data-state=\"visible\"", 2)),

    render_to_string(scroll_area([type(hover), scroll_hide_delay(300)], "x"), HoverGroup),
    check(hover_group_scroll_hide_delay_on_root,
          contains(HoverGroup, "data-scroll-hide-delay=\"300\"")),
    check(hover_group_scrollbar_hidden_by_default,
          contains(HoverGroup, "data-state=\"hidden\"")),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Goal` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(scroll_area, _Order, \scroll_area_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(scroll_area, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \scroll_area_demo), Demo),
    check(demo_has_six_scroll_areas,
          count_occurrences(Demo, "<px-scroll-area>", 6)),
    check(demo_has_viewport_every_time,
          count_occurrences(Demo, "px-scroll-area-viewport", 6)),
    check(demo_has_corner_for_both_orientation,
          contains(Demo, "px-scroll-area-corner")),
    check(demo_has_type_always,
          contains(Demo, "data-type=\"always\"")),
    check(demo_has_type_hover,
          contains(Demo, "data-type=\"hover\"")),
    check(demo_has_type_scroll,
          contains(Demo, "data-type=\"scroll\"")),
    check(demo_has_type_auto,
          contains(Demo, "data-type=\"auto\"")),
    check(demo_has_horizontal_orientation,
          contains(Demo, "data-orientation=\"horizontal\"")),
    check(demo_has_tag_list_items,
          contains(Demo, "Tag v1.")),
    check(demo_has_chip_row,
          contains(Demo, "px-scroll-area-chip")),
    check(demo_has_no_role_anywhere,
          not_contains(Demo, "role")),
    check(demo_has_no_aria_anywhere,
          not_contains(Demo, "aria-")),

    % show some real output for the record
    format("~n--- rendered scroll_area_demo (truncated) ---~n"),
    ( string_length(Demo, DemoLen), DemoLen > 2000
    -> sub_string(Demo, 0, 2000, _, DemoHead),
       format("~w...(~w chars total)~n", [DemoHead, DemoLen])
    ;  format("~w~n", [Demo])
    ),
    format("-----------------------------------~n").
