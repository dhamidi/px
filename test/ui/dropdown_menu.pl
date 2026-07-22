/* test/ui/dropdown_menu.pl (adr/0026): render-test proof for
   prolog/ui/dropdown_menu.pl -- the Dropdown Menu port, this library's
   first Menu-family wrapper and assets/js/lib/menu.js's proving
   consumer. A plain swipl script, no server, no networking
   (test/ui/toggle_group.pl's / test/ui/popover.pl's pattern):
   render_to_string/2 over the templates and assert the exact
   ARIA/data contract documented in prolog/ui/dropdown_menu.pl's own
   module header, for:

     - dropdown_menu_root   wraps in <px-dropdown-menu>
     - dropdown_menu_trigger  aria-haspopup="menu", aria-expanded,
                       aria-controls, data-state, native popovertarget
     - dropdown_menu_content  role="menu" (delegates to menu_content/2),
                       popover="auto", default side=bottom/align=start
     - dropdown_menu/2  id-wiring both directions (Trigger's
                       aria-controls/popovertarget -> Content's id;
                       Content's aria-labelledby -> Trigger's id)
     - the kitchen-sink demo (px_ui:demo/3): registered exactly once,
       renders end to end with every anatomy part the demo brief
       requires -- items with shortcuts, a separator, a checkbox item,
       a radio group, a submenu, a disabled item.
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/separator.pl').
:- use_module('../../prolog/ui/_menu.pl').
:- use_module('../../prolog/ui/dropdown_menu.pl').

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
    ->  format("~nAll ui/dropdown_menu checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % dropdown_menu_root/2 -- wraps in <px-dropdown-menu>.
    % ===================================================================

    render_to_string(dropdown_menu_root([], []), Root),
    check(root_wrapper_is_px_dropdown_menu,
          ( sub_string(Root, 0, _, _, "<px-dropdown-menu>"),
            sub_string(Root, _, _, 0, "</px-dropdown-menu>") )),
    check(root_default_class, contains(Root, "class=\"px-dropdown-menu\"")),

    % ===================================================================
    % dropdown_menu_trigger/2 -- aria-haspopup="menu", data-state,
    % native popovertarget, aria-controls.
    % ===================================================================

    render_to_string(dropdown_menu_trigger([], "Open menu"), Trigger),
    check(trigger_haspopup_menu, contains(Trigger, "aria-haspopup=\"menu\"")),
    check(trigger_default_closed,
          ( contains(Trigger, "aria-expanded=\"false\""),
            contains(Trigger, "data-state=\"closed\"") )),
    check(trigger_no_wiring_without_controls, not_contains(Trigger, "popovertarget")),
    check(trigger_class, contains(Trigger, "class=\"px-dropdown-menu-trigger\"")),

    render_to_string(dropdown_menu_trigger([open(true), controls("m-content")], "Open menu"),
                      TriggerWired),
    check(trigger_wired_aria_controls, contains(TriggerWired, "aria-controls=\"m-content\"")),
    check(trigger_wired_popovertarget, contains(TriggerWired, "popovertarget=\"m-content\"")),
    check(trigger_open_state,
          ( contains(TriggerWired, "aria-expanded=\"true\""),
            contains(TriggerWired, "data-state=\"open\"") )),

    % ===================================================================
    % dropdown_menu_content/2 -- thin rename over menu_content/2,
    % default side=bottom/align=start (Dropdown Menu's own default).
    % ===================================================================

    render_to_string(dropdown_menu_content([id("m-content")], []), Content),
    check(content_role_menu, contains(Content, "role=\"menu\"")),
    check(content_popover_auto, contains(Content, "popover=\"auto\"")),
    check(content_default_side_bottom, contains(Content, "data-side=\"bottom\"")),
    check(content_default_align_start, contains(Content, "data-align=\"start\"")),
    check(content_class, contains(Content, "class=\"px-menu-content\"")),

    % ===================================================================
    % dropdown_menu/2 -- convenience, both-directions id wiring.
    % ===================================================================

    render_to_string(
        dropdown_menu([id("ddm1")],
          [ "Open", [menu_item([], "A"), menu_item([], "B")] ]),
        Full),
    check(full_trigger_id, contains(Full, "id=\"ddm1-trigger\"")),
    check(full_content_id, contains(Full, "id=\"ddm1-content\"")),
    check(full_trigger_controls_content,
          ( contains(Full, "aria-controls=\"ddm1-content\""),
            contains(Full, "popovertarget=\"ddm1-content\"") )),
    check(full_content_labelledby_trigger,
          contains(Full, "aria-labelledby=\"ddm1-trigger\"")),
    check(full_two_items, count_occurrences(Full, "role=\"menuitem\"", 2)),

    render_to_string(
        dropdown_menu([id("ddm2"), side(right), align(end), side_offset(4)],
          [ "Open", [] ]),
        FullOpts),
    check(full_side_forwarded, contains(FullOpts, "data-side=\"right\"")),
    check(full_align_forwarded, contains(FullOpts, "data-align=\"end\"")),
    check(full_side_offset_forwarded, contains(FullOpts, "data-side-offset=\"4\"")),
    check(full_no_leaked_side_on_root,
          % side(_)/align(_)/etc. are Trigger/Content-only concepts --
          % must not leak onto Root's own <div> as literal attributes.
          not_contains(FullOpts, "<div class=\"px-dropdown-menu\" id=\"ddm2\" side=")),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Call` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(dropdown_menu, _Order, \dropdown_menu_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(dropdown_menu, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \dropdown_menu_demo), Demo),
    check(demo_has_dropdown_menu, contains(Demo, "<px-dropdown-menu>")),
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

    format("~n--- rendered dropdown_menu/2 (basic) ---~n~w~n-----------------------------------~n",
           [Full]).
