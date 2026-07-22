/* test/ui/hover_card.pl (adr/0026): render-test proof for
   prolog/ui/hover_card.pl -- the Hover Card port. A plain swipl
   script, no server, no networking (test/ui/popover.pl's pattern):
   render_to_string/2 over the templates and assert the exact
   ARIA/data contract documented in docs/radix-port-analysis.md's
   "Hover Card" entry, for:

     - hover_card_root/2      <px-hover-card> wrapper, class merge/
                                pass-through, data-open-delay/
                                data-close-delay (default 700/300,
                                overridable)
     - hover_card_trigger/2   data-state ONLY (deliberately NO
                                aria-haspopup/aria-expanded/
                                aria-controls -- unlike Popover's
                                Trigger), renders an <a>, href is
                                ordinary pass-through
     - hover_card_content/2   NO role anywhere, native popover="auto",
                                data-state, data-side (default bottom),
                                data-align (default center),
                                data-side-offset/data-align-offset
                                (default 0)
     - hover_card_arrow/1     aria-hidden="true", class merge
     - hover_card/2           Root wraps Trigger+Content, open(_)
                                threaded to both, href forwarded to
                                Trigger only (never leaked onto Root),
                                side/align/offset forwarded to Content,
                                open_delay/close_delay forwarded to
                                Root, an Arrow appended to Content
                                automatically

   plus the kitchen-sink demo registration (px_ui:demo/3) rendering end
   to end exactly as prolog/px_ui.pl's ui_show_view embeds it (`\Goal`
   as a div's Children, not the bare atom -- adr/0019's arity-0
   dispatch rule).
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/hover_card.pl').

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
    ->  format("~nAll ui/hover_card checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Root: <px-hover-card> wrapper, class merge, open/close delay
    % defaults and overrides.
    % ===================================================================

    render_to_string(hover_card_root([], []), RootDefault),
    check(root_wrapper_is_px_hover_card,
          ( sub_string(RootDefault, 0, _, _, "<px-hover-card>"),
            sub_string(RootDefault, _, _, 0, "</px-hover-card>") )),
    check(root_default_class,
          contains(RootDefault, "class=\"px-hover-card\"")),
    check(root_default_open_delay_700,
          contains(RootDefault, "data-open-delay=\"700\"")),
    check(root_default_close_delay_300,
          contains(RootDefault, "data-close-delay=\"300\"")),

    render_to_string(
        hover_card_root([class("wide"), id("g1"), open_delay(200), close_delay(50)], []),
        RootOpts),
    check(root_class_merged_after_default,
          contains(RootOpts, "class=\"px-hover-card wide\"")),
    check(root_id_passed_through,
          contains(RootOpts, "id=\"g1\"")),
    check(root_open_delay_overridden,
          contains(RootOpts, "data-open-delay=\"200\"")),
    check(root_close_delay_overridden,
          contains(RootOpts, "data-close-delay=\"50\"")),

    % ===================================================================
    % Trigger: data-state ONLY -- no aria-haspopup/aria-expanded/
    % aria-controls (unlike Popover's Trigger). An <a>, href is
    % ordinary pass-through.
    % ===================================================================

    render_to_string(
        hover_card_trigger([open(true), href("/u/ada")], "@ada"),
        TriggerOpen),
    check(trigger_is_anchor,
          ( sub_string(TriggerOpen, 0, _, _, "<a "),
            sub_string(TriggerOpen, _, _, 0, "</a>") )),
    check(trigger_data_state_open,
          contains(TriggerOpen, "data-state=\"open\"")),
    check(trigger_href_passthrough,
          contains(TriggerOpen, "href=\"/u/ada\"")),
    check(trigger_no_aria_haspopup,
          not_contains(TriggerOpen, "aria-haspopup")),
    check(trigger_no_aria_expanded,
          not_contains(TriggerOpen, "aria-expanded")),
    check(trigger_no_aria_controls,
          not_contains(TriggerOpen, "aria-controls")),
    check(trigger_exact,
          TriggerOpen ==
              "<a data-state=\"open\" class=\"px-hover-card-trigger\" href=\"/u/ada\">@ada</a>"),

    render_to_string(hover_card_trigger([], "@ada"), TriggerDefault),
    check(trigger_default_closed,
          contains(TriggerDefault, "data-state=\"closed\"")),
    check(trigger_no_href_degrades_gracefully,
          not_contains(TriggerDefault, "href")),

    % ===================================================================
    % Content: NO role anywhere, native popover="auto", data-state,
    % data-side (default bottom), data-align (default center),
    % data-side-offset/data-align-offset (default 0).
    % ===================================================================

    render_to_string(hover_card_content([], "Hello"), ContentDefault),
    check(content_no_role,
          not_contains(ContentDefault, "role")),
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

    render_to_string(
        hover_card_content(
            [ open(true), side(top), align(start),
              side_offset(8), align_offset(4)
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

    render_to_string(hover_card_content([side(sideways)], "X"), ContentBadSide),
    check(content_invalid_side_falls_back,
          contains(ContentBadSide, "data-side=\"bottom\"")),

    render_to_string(hover_card_content([align(nowhere)], "X"), ContentBadAlign),
    check(content_invalid_align_falls_back,
          contains(ContentBadAlign, "data-align=\"center\"")),

    % ===================================================================
    % Arrow: aria-hidden="true", class merge.
    % ===================================================================

    render_to_string(hover_card_arrow([]), ArrowDefault),
    check(arrow_exact,
          ArrowDefault ==
              "<div aria-hidden=\"true\" class=\"px-hover-card-arrow\"></div>"),

    render_to_string(hover_card_arrow([class("big")]), ArrowClass),
    check(arrow_class_merged,
          contains(ArrowClass, "class=\"px-hover-card-arrow big\"")),

    % ===================================================================
    % Convenience `hover_card/2`: Root wraps Trigger+Content, open(_)
    % threaded to both, href forwarded to Trigger ONLY, side/align/
    % offset forwarded to Content, open_delay/close_delay forwarded to
    % Root, an Arrow appended automatically.
    % ===================================================================

    render_to_string(
        hover_card(
            [ id("demo1"), open(true), href("/u/ada"),
              side(top), align(start), side_offset(6),
              open_delay(400), close_delay(120)
            ],
            ["@ada", "Profile body"]),
        Group1),

    check(group_wrapper_is_px_hover_card,
          ( sub_string(Group1, 0, _, _, "<px-hover-card>"),
            sub_string(Group1, _, _, 0, "</px-hover-card>") )),
    check(group_trigger_and_content_present,
          ( contains(Group1, "<a "), contains(Group1, "popover=\"auto\"") )),
    check(group_href_on_trigger,
          contains(Group1, "href=\"/u/ada\"")),
    check(group_open_threaded_to_both,
          count_occurrences(Group1, "data-state=\"open\"", 2)),
    check(group_side_align_offset_forwarded,
          ( contains(Group1, "data-side=\"top\""),
            contains(Group1, "data-align=\"start\""),
            contains(Group1, "data-side-offset=\"6\"") )),
    check(group_open_delay_forwarded,
          contains(Group1, "data-open-delay=\"400\"")),
    check(group_close_delay_forwarded,
          contains(Group1, "data-close-delay=\"120\"")),
    check(group_arrow_appended,
          contains(Group1, "px-hover-card-arrow")),
    check(group_content_present,
          contains(Group1, "Profile body")),
    check(group_no_role_anywhere,
          not_contains(Group1, "role")),
    check(group_no_aria_haspopup,
          not_contains(Group1, "aria-haspopup")),
    check(group_no_aria_controls,
          not_contains(Group1, "aria-controls")),
    % Regression: open(_)/side(_)/align(_)/side_offset(_)/align_offset(_)/
    % href(_) must NOT leak onto the Root <div> as raw, meaningless HTML
    % attributes -- only Trigger/Content should carry their computed
    % forms.
    check(group_root_no_raw_open_attr,
          not_contains(Group1, " open=\"true\"")),
    check(group_root_no_raw_side_attr,
          not_contains(Group1, " side=\"top\"")),
    % href appears exactly once in the whole render -- on Trigger only,
    % never leaked onto Root's <div>.
    check(group_href_appears_once_on_trigger_only,
          count_occurrences(Group1, "href=", 1)),

    render_to_string(hover_card([], ["@x", "Body"]), Group2),
    check(group_default_delays,
          ( contains(Group2, "data-open-delay=\"700\""),
            contains(Group2, "data-close-delay=\"300\"") )),
    check(group_default_closed,
          count_occurrences(Group2, "data-state=\"closed\"", 2)),
    check(group_no_href_when_omitted,
          not_contains(Group2, "href")),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Goal` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(hover_card, _Order, \hover_card_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(hover_card, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \hover_card_demo), Demo),
    check(demo_has_five_hover_cards,
          count_occurrences(Demo, "<px-hover-card>", 5)),
    check(demo_has_five_triggers,
          count_occurrences(Demo, "px-hover-card-trigger", 5)),
    check(demo_has_five_contents,
          count_occurrences(Demo, "popover=\"auto\"", 5)),
    check(demo_has_no_role_anywhere,
          not_contains(Demo, "role")),
    check(demo_has_every_side,
          ( contains(Demo, "data-side=\"top\""),
            contains(Demo, "data-side=\"right\""),
            contains(Demo, "data-side=\"bottom\""),
            contains(Demo, "data-side=\"left\"") )),
    check(demo_has_profile_card_markup,
          ( contains(Demo, "px-hover-card-avatar"),
            contains(Demo, "px-hover-card-stats") )),

    % show some real output for the record
    format("~n--- rendered hover_card_demo ---~n~w~n-----------------------------------~n",
           [Demo]).
