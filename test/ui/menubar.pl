/* test/ui/menubar.pl (adr/0026): render-test proof for
   prolog/ui/menubar.pl -- the Menubar port, this library's second
   Menu-family wrapper (after Dropdown Menu) and second top-level-
   roving-focus port (after Toolbar). A plain swipl script, no server,
   no networking (test/ui/dropdown_menu.pl's / test/ui/toolbar.pl's
   pattern): render_to_string/2 over the templates and assert the
   exact ARIA/data contract documented in prolog/ui/menubar.pl's own
   module header, for:

     - menubar_root       wraps in <px-menubar>, role="menubar",
                       data-orientation="horizontal" always
     - menubar_trigger     role="menuitem" (overriding the implicit
                       button role), aria-haspopup="menu",
                       aria-expanded, data-state, tabindex 0/-1,
                       native popovertarget, disabled
     - menubar_content     thin rename over menu_content/2, default
                       side=bottom/align=start
     - menubar_menu/2  id-wiring both directions (Trigger's
                       aria-controls/popovertarget -> Content's id;
                       Content's aria-labelledby -> Trigger's id),
                       wrapper data-state
     - menubar/2       exactly ONE tabindex="0" across the WHOLE bar,
                       auto-picked (first explicit active(true) >
                       first non-disabled > none), explicit active(_)
                       anywhere always wins, disabled Menus skipped
     - the kitchen-sink demo (px_ui:demo/3): registered exactly once,
       renders end to end with every anatomy part the demo brief
       requires -- File/Edit/View, items with shortcuts, separators,
       a submenu, checkbox items, a radio group, a disabled item.

   Run:  swipl test/ui/menubar.pl
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/separator.pl').
:- use_module('../../prolog/ui/_menu.pl').
:- use_module('../../prolog/ui/menubar.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Harness (test/ui/dropdown_menu.pl's / test/ui/toolbar.pl's pattern).
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
    ->  format("~nAll ui/menubar checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % menubar_root/2 -- wraps in <px-menubar>, role="menubar",
    % data-orientation always present (Menubar has no orientation
    % option -- always horizontal).
    % ===================================================================

    render_to_string(menubar_root([], []), RootDefault),
    check(root_wrapper_is_px_menubar,
          ( sub_string(RootDefault, 0, _, _, "<px-menubar>"),
            sub_string(RootDefault, _, _, 0, "</px-menubar>") )),
    check(root_role_menubar, contains(RootDefault, "role=\"menubar\"")),
    check(root_data_orientation_horizontal,
          contains(RootDefault, "data-orientation=\"horizontal\"")),
    check(root_default_class, contains(RootDefault, "class=\"px-menubar\"")),
    check(root_default_exact,
          RootDefault ==
              "<px-menubar><div role=\"menubar\" data-orientation=\"horizontal\" class=\"px-menubar\"></div></px-menubar>"),

    render_to_string(menubar_root([id("mb1"), class("wide")], []), RootOpts),
    check(root_id_passed_through, contains(RootOpts, "id=\"mb1\"")),
    check(root_class_merged_after_default,
          contains(RootOpts, "class=\"px-menubar wide\"")),

    % ===================================================================
    % menubar_trigger/2 -- role="menuitem" (NOT "button"),
    % aria-haspopup="menu", data-state, native popovertarget,
    % aria-controls, tabindex 0/-1, disabled.
    % ===================================================================

    render_to_string(menubar_trigger([], "File"), TriggerDefault),
    check(trigger_role_menuitem, contains(TriggerDefault, "role=\"menuitem\"")),
    check(trigger_not_role_button, not_contains(TriggerDefault, "role=\"button\"")),
    check(trigger_haspopup_menu, contains(TriggerDefault, "aria-haspopup=\"menu\"")),
    check(trigger_default_closed,
          ( contains(TriggerDefault, "aria-expanded=\"false\""),
            contains(TriggerDefault, "data-state=\"closed\"") )),
    check(trigger_default_tabindex_minus1, contains(TriggerDefault, "tabindex=\"-1\"")),
    check(trigger_no_wiring_without_controls, not_contains(TriggerDefault, "popovertarget")),
    check(trigger_class, contains(TriggerDefault, "class=\"px-menubar-trigger\"")),
    check(trigger_is_real_button,
          ( sub_string(TriggerDefault, 0, _, _, "<button "),
            sub_string(TriggerDefault, _, _, 0, "</button>") )),

    render_to_string(menubar_trigger([open(true), active(true), controls("m-content")], "File"),
                      TriggerWired),
    check(trigger_wired_aria_controls, contains(TriggerWired, "aria-controls=\"m-content\"")),
    check(trigger_wired_popovertarget, contains(TriggerWired, "popovertarget=\"m-content\"")),
    check(trigger_open_state,
          ( contains(TriggerWired, "aria-expanded=\"true\""),
            contains(TriggerWired, "data-state=\"open\"") )),
    check(trigger_active_tabindex_0, contains(TriggerWired, "tabindex=\"0\"")),

    render_to_string(menubar_trigger([disabled(true)], "File"), TriggerDisabled),
    check(trigger_disabled_attrs,
          ( contains(TriggerDisabled, "data-disabled=\"\""),
            contains(TriggerDisabled, "disabled") )),

    % ===================================================================
    % menubar_content/2 -- thin rename over menu_content/2, default
    % side=bottom/align=start.
    % ===================================================================

    render_to_string(menubar_content([id("m-content")], []), Content),
    check(content_role_menu, contains(Content, "role=\"menu\"")),
    check(content_popover_auto, contains(Content, "popover=\"auto\"")),
    check(content_default_side_bottom, contains(Content, "data-side=\"bottom\"")),
    check(content_default_align_start, contains(Content, "data-align=\"start\"")),
    check(content_class, contains(Content, "class=\"px-menu-content\"")),

    % ===================================================================
    % menubar_menu/2 -- convenience, both-directions id wiring, wrapper
    % data-state.
    % ===================================================================

    render_to_string(
        menubar_menu([id("mb-file")],
          [ "File", [menu_item([], "A"), menu_item([], "B")] ]),
        Full),
    check(full_wrapper_class, contains(Full, "class=\"px-menubar-menu\"")),
    check(full_wrapper_state_closed, contains(Full, "data-state=\"closed\"")),
    check(full_trigger_id, contains(Full, "id=\"mb-file-trigger\"")),
    check(full_content_id, contains(Full, "id=\"mb-file-content\"")),
    check(full_trigger_controls_content,
          ( contains(Full, "aria-controls=\"mb-file-content\""),
            contains(Full, "popovertarget=\"mb-file-content\"") )),
    check(full_content_labelledby_trigger,
          contains(Full, "aria-labelledby=\"mb-file-trigger\"")),
    check(full_two_items, count_occurrences(Full, "role=\"menuitem\"", 3)),
        % 3 = the Trigger itself + the two menu_item/2 rows (both also
        % role="menuitem" per _menu.pl's own Item contract).

    render_to_string(
        menubar_menu([id("mb-open"), open(true)], ["Edit", []]),
        FullOpen),
    check(full_open_threaded_to_both,
          ( contains(FullOpen, "aria-expanded=\"true\""),
            contains(FullOpen, "data-state=\"open\"") )),
    check(full_open_wrapper_state,
          sub_string(FullOpen, _, _, _, "data-state=\"open\" class=\"px-menubar-menu\"")),

    render_to_string(
        menubar_menu([id("mb-dis"), disabled(true)], ["View", []]),
        FullDisabled),
    check(full_disabled_forwarded_to_trigger_only,
          contains(FullDisabled, "data-disabled=\"\" disabled")),

    % No leaked convenience-only opts on the wrapper <div> itself.
    check(full_no_leaked_open_on_wrapper,
          not_contains(Full, "<div data-state=\"closed\" class=\"px-menubar-menu\" open=")),

    % ===================================================================
    % menubar/2 -- exactly ONE tabindex="0" across the WHOLE bar.
    % ===================================================================

    render_to_string(
        menubar([id("mb1")],
          [ menubar_menu([id("f")], ["File", []]),
            menubar_menu([id("e")], ["Edit", []]),
            menubar_menu([id("v")], ["View", []])
          ]),
        AutoPickFirst),
    check(autopick_first_menu_active,
          sub_string(AutoPickFirst, _, _, _, "tabindex=\"0\"")),
    check(autopick_exactly_one_tabindex_0,
          count_occurrences(AutoPickFirst, "tabindex=\"0\"", 1)),
    check(autopick_first_trigger_is_the_one,
          sub_string(AutoPickFirst, _, _, _,
                     "tabindex=\"0\" aria-expanded=\"false\" data-state=\"closed\" class=\"px-menubar-trigger\" id=\"f-trigger\">File")),

    % First Menu disabled -> auto-pick skips it.
    render_to_string(
        menubar([id("mb2")],
          [ menubar_menu([id("f"), disabled(true)], ["File", []]),
            menubar_menu([id("e")], ["Edit", []])
          ]),
        AutoPickSkipDisabled),
    check(autopick_skip_disabled_first,
          sub_string(AutoPickSkipDisabled, _, _, _, "id=\"e-trigger\">Edit")),
    check(autopick_skip_disabled_exactly_one_tabindex_0,
          count_occurrences(AutoPickSkipDisabled, "tabindex=\"0\"", 1)),

    % Explicit active(true) anywhere short-circuits the auto-pick.
    render_to_string(
        menubar([id("mb3")],
          [ menubar_menu([id("f")], ["File", []]),
            menubar_menu([id("e"), active(true)], ["Edit", []])
          ]),
        AutoPickExplicit),
    check(autopick_explicit_wins,
          sub_string(AutoPickExplicit, _, _, _, "tabindex=\"0\" aria-expanded=\"false\" data-state=\"closed\" class=\"px-menubar-trigger\" id=\"e-trigger\">Edit")),
    check(autopick_explicit_exactly_one_tabindex_0,
          count_occurrences(AutoPickExplicit, "tabindex=\"0\"", 1)),

    % All-disabled menubar -> no tabindex="0" anywhere.
    render_to_string(
        menubar([id("mb4")],
          [ menubar_menu([id("f"), disabled(true)], ["File", []]),
            menubar_menu([id("e"), disabled(true)], ["Edit", []])
          ]),
        AllDisabled),
    check(all_disabled_no_tabindex_0, not_contains(AllDisabled, "tabindex=\"0\"")),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Call` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(menubar, _Order, \menubar_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(menubar, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \menubar_demo), Demo),
    check(demo_has_menubar, contains(Demo, "<px-menubar>")),
    check(demo_has_role_menubar, contains(Demo, "role=\"menubar\"")),
    check(demo_has_three_menus, count_occurrences(Demo, "px-menubar-menu", 3)),
    check(demo_has_file_edit_view,
          ( contains(Demo, ">File<"),
            contains(Demo, ">Edit<"),
            contains(Demo, ">View<") )),
    check(demo_has_shortcuts, contains(Demo, "px-menu-shortcut")),
    check(demo_has_separator, contains(Demo, "px-menu-separator")),
    check(demo_has_submenu,
          ( contains(Demo, "px-menu-sub"),
            contains(Demo, "aria-haspopup=\"menu\"") )),
    check(demo_has_checkbox_item, contains(Demo, "role=\"menuitemcheckbox\"")),
    check(demo_has_radio_group,
          ( contains(Demo, "role=\"group\""),
            contains(Demo, "role=\"menuitemradio\"") )),
    check(demo_has_disabled_item, contains(Demo, "data-disabled=\"\" aria-disabled=\"true\"")),
    check(demo_has_label, contains(Demo, "px-menu-label")),
    check(demo_exactly_one_tabindex_0,
          count_occurrences(Demo, "tabindex=\"0\"", 1)),

    format("~n--- rendered menubar_menu/2 (basic) ---~n~w~n-----------------------------------~n",
           [Full]).
