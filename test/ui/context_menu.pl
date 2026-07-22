/* test/ui/context_menu.pl (adr/0026): render-test proof for
   prolog/ui/context_menu.pl -- the Context Menu port, this library's
   second Menu-family wrapper (after Dropdown Menu). A plain swipl
   script, no server, no networking (test/ui/dropdown_menu.pl's
   pattern): render_to_string/2 over the templates and assert the
   exact ARIA/data contract documented in prolog/ui/context_menu.pl's
   own module header, for:

     - context_menu_root      wraps in <px-context-menu>
     - context_menu_trigger   data-state ONLY (open|closed), PLUS
                       data-disabled when disabled(true); NO
                       aria-haspopup/aria-expanded/aria-controls/
                       popovertarget at all -- the documented CONTRAST
                       with dropdown_menu_trigger/2's contract.
     - context_menu_content   role="menu" (delegates to menu_content/2),
                       popover="auto", CONTEXT MENU'S OWN defaults
                       side=right/align=start/side-offset=2 (contrast
                       with Dropdown Menu's bottom/start/0), and that
                       an explicit caller-supplied side/align/offset is
                       NOT overridden by those defaults.
     - context_menu/2  id-wiring (Trigger/Content ids derived from a
                       shared base) WITHOUT any aria-controls/
                       aria-labelledby wiring (Context Menu has no
                       persistent trigger element to relate Content to
                       -- unlike dropdown_menu/2).
     - the kitchen-sink demo (px_ui:demo/3): registered exactly once,
       renders end to end with every anatomy part the demo brief
       requires -- a dashed right-click-here trigger area, items, a
       checkbox item, a radio group, a submenu, a disabled item.
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/separator.pl').
:- use_module('../../prolog/ui/_menu.pl').
:- use_module('../../prolog/ui/context_menu.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Harness (test/ui/dropdown_menu.pl's pattern).
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
    ->  format("~nAll ui/context_menu checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % context_menu_root/2 -- wraps in <px-context-menu>.
    % ===================================================================

    render_to_string(context_menu_root([], []), Root),
    check(root_wrapper_is_px_context_menu,
          ( sub_string(Root, 0, _, _, "<px-context-menu>"),
            sub_string(Root, _, _, 0, "</px-context-menu>") )),
    check(root_default_class, contains(Root, "class=\"px-context-menu\"")),

    % ===================================================================
    % context_menu_trigger/2 -- data-state ONLY, plus data-disabled;
    % NO aria-haspopup/aria-expanded/aria-controls/popovertarget.
    % ===================================================================

    render_to_string(context_menu_trigger([], "Right-click area"), Trigger),
    check(trigger_is_span,
          ( sub_string(Trigger, 0, _, _, "<span "),
            sub_string(Trigger, _, _, 0, "</span>") )),
    check(trigger_default_closed, contains(Trigger, "data-state=\"closed\"")),
    check(trigger_no_haspopup, not_contains(Trigger, "aria-haspopup")),
    check(trigger_no_expanded, not_contains(Trigger, "aria-expanded")),
    check(trigger_no_controls, not_contains(Trigger, "aria-controls")),
    check(trigger_no_popovertarget, not_contains(Trigger, "popovertarget")),
    check(trigger_no_disabled_by_default, not_contains(Trigger, "data-disabled")),
    check(trigger_class, contains(Trigger, "class=\"px-context-menu-trigger\"")),

    render_to_string(context_menu_trigger([open(true), disabled(true)], "Area"), TriggerOpen),
    check(trigger_open_state, contains(TriggerOpen, "data-state=\"open\"")),
    check(trigger_disabled_attr, contains(TriggerOpen, "data-disabled=\"\"")),
    check(trigger_disabled_no_aria, not_contains(TriggerOpen, "aria-disabled")),

    % ===================================================================
    % context_menu_content/2 -- thin wrapper over menu_content/2 with
    % Context Menu's OWN defaults: side=right, align=start,
    % side_offset=2 (contrast: Dropdown Menu's own bottom/start/0).
    % ===================================================================

    render_to_string(context_menu_content([id("cm-content")], []), Content),
    check(content_role_menu, contains(Content, "role=\"menu\"")),
    check(content_popover_auto, contains(Content, "popover=\"auto\"")),
    check(content_default_side_right, contains(Content, "data-side=\"right\"")),
    check(content_default_align_start, contains(Content, "data-align=\"start\"")),
    check(content_default_side_offset_2, contains(Content, "data-side-offset=\"2\"")),
    check(content_class, contains(Content, "class=\"px-menu-content\"")),

    render_to_string(context_menu_content([id("cm-content2"), side(left), align(end), side_offset(9)], []),
                      ContentOverridden),
    check(content_side_override_respected, contains(ContentOverridden, "data-side=\"left\"")),
    check(content_align_override_respected, contains(ContentOverridden, "data-align=\"end\"")),
    check(content_side_offset_override_respected, contains(ContentOverridden, "data-side-offset=\"9\"")),

    % ===================================================================
    % context_menu/2 -- convenience, id-wiring WITHOUT any
    % aria-controls/aria-labelledby (no persistent trigger to relate).
    % ===================================================================

    render_to_string(
        context_menu([id("cm1")],
          [ "Right-click here", [menu_item([], "A"), menu_item([], "B")] ]),
        Full),
    check(full_trigger_id, contains(Full, "id=\"cm1-trigger\"")),
    check(full_content_id, contains(Full, "id=\"cm1-content\"")),
    check(full_no_aria_controls, not_contains(Full, "aria-controls")),
    check(full_no_aria_labelledby, not_contains(Full, "aria-labelledby")),
    check(full_no_popovertarget, not_contains(Full, "popovertarget")),
    check(full_content_default_side_right, contains(Full, "data-side=\"right\"")),
    check(full_two_items, count_occurrences(Full, "role=\"menuitem\"", 2)),

    render_to_string(
        context_menu([id("cm2"), disabled(true), side(top), align(center), side_offset(5)],
          [ "Area", [] ]),
        FullOpts),
    check(full_disabled_forwarded_to_trigger, contains(FullOpts, "data-disabled=\"\"")),
    check(full_side_forwarded, contains(FullOpts, "data-side=\"top\"")),
    check(full_align_forwarded, contains(FullOpts, "data-align=\"center\"")),
    check(full_side_offset_forwarded, contains(FullOpts, "data-side-offset=\"5\"")),
    check(full_no_leaked_side_on_root,
          % side(_)/align(_)/etc. are Trigger/Content-only concepts --
          % must not leak onto Root's own <div> as literal attributes.
          not_contains(FullOpts, "<div class=\"px-context-menu\" id=\"cm2\" side=")),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Call` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(context_menu, _Order, \context_menu_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(context_menu, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \context_menu_demo), Demo),
    check(demo_has_context_menu, contains(Demo, "<px-context-menu>")),
    check(demo_has_trigger_area, contains(Demo, "px-context-menu-area")),
    check(demo_has_trigger_area_text, contains(Demo, "Right-click here")),
    check(demo_has_plain_items, contains(Demo, "px-menu-shortcut")),
    check(demo_has_separator, contains(Demo, "px-menu-separator")),
    check(demo_has_checkbox_item, contains(Demo, "role=\"menuitemcheckbox\"")),
    check(demo_has_radio_group,
          ( contains(Demo, "role=\"group\""),
            contains(Demo, "role=\"menuitemradio\"") )),
    check(demo_has_submenu,
          ( contains(Demo, "px-menu-sub"),
            contains(Demo, "aria-haspopup=\"menu\"") )),
    check(demo_has_disabled_item, contains(Demo, "data-disabled=\"\" aria-disabled=\"true\"")),
    check(demo_has_label, contains(Demo, "px-menu-label")),
    check(demo_content_default_side_right, contains(Demo, "data-side=\"right\"")),

    format("~n--- rendered context_menu/2 (basic) ---~n~w~n-----------------------------------~n",
           [Full]).
