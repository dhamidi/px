/* test/ui/toggle.pl (adr/0026): render-test proof for
   prolog/ui/toggle.pl -- the Toggle port. A plain swipl script, no
   server, no networking (milestone10_templates.pl's pattern):
   render_to_string/2 over the templates and assert the exact ARIA/
   data contract documented in docs/radix-port-analysis.md's "Toggle"
   entry, for all three states:

     - off       (pressed absent -> default false)
     - on        (pressed(true))
     - disabled  (disabled(true), either pressed value)

   plus the convenience `toggle/2` wrapper, class merging, option
   pass-through, and the kitchen-sink demo registration (px_ui:demo/3)
   rendering end to end exactly as prolog/px_ui.pl's ui_show_view
   embeds it (`\toggle_demo` as a div's Children, not the bare atom --
   adr/0019's arity-0 dispatch rule).
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/toggle.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Harness (milestone10_templates.pl's / test/ui/progress.pl's pattern).
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
    ->  format("~nAll ui/toggle checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Off (default): no pressed(_) option at all.
    % ===================================================================

    render_to_string(toggle_root([], "Off"), Off),

    check(off_wrapper_is_px_toggle,
          ( sub_string(Off, 0, _, _, "<px-toggle>"),
            sub_string(Off, _, _, 0, "</px-toggle>") )),
    check(off_button_type,
          contains(Off, "<button type=\"button\"")),
    check(off_aria_pressed_false,
          contains(Off, "aria-pressed=\"false\"")),
    check(off_data_state_off,
          contains(Off, "data-state=\"off\"")),
    check(off_default_class,
          contains(Off, "class=\"px-toggle\"")),
    check(off_no_data_disabled,
          not_contains(Off, "data-disabled")),
    check(off_no_native_disabled,
          not_contains(Off, " disabled")),
    check(off_content,
          contains(Off, ">Off</button>")),
    check(off_exact,
          Off ==
              "<px-toggle><button type=\"button\" aria-pressed=\"false\" data-state=\"off\" class=\"px-toggle\">Off</button></px-toggle>"),

    % pressed(false) explicitly is the same as omitting it.
    render_to_string(toggle_root([pressed(false)], "Off"), OffExplicit),
    check(off_explicit_same_as_default, OffExplicit == Off),

    % ===================================================================
    % On: pressed(true).
    % ===================================================================

    render_to_string(toggle_root([pressed(true)], "On"), On),

    check(on_aria_pressed_true,
          contains(On, "aria-pressed=\"true\"")),
    check(on_data_state_on,
          contains(On, "data-state=\"on\"")),
    check(on_no_data_disabled,
          not_contains(On, "data-disabled")),
    check(on_exact,
          On ==
              "<px-toggle><button type=\"button\" aria-pressed=\"true\" data-state=\"on\" class=\"px-toggle\">On</button></px-toggle>"),

    % ===================================================================
    % Disabled: disabled(true), pressed(false) -- data-disabled="" plus
    % the native `disabled` attribute (adr/0026's "harmless without
    % JS": a disabled <button> is inert with zero JS involved).
    % ===================================================================

    render_to_string(toggle_root([disabled(true)], "Disabled"), Disabled),

    check(disabled_data_disabled_empty,
          contains(Disabled, "data-disabled=\"\"")),
    check(disabled_native_attr,
          contains(Disabled, " disabled>")),
    check(disabled_aria_pressed_false,
          contains(Disabled, "aria-pressed=\"false\"")),
    check(disabled_exact,
          Disabled ==
              "<px-toggle><button type=\"button\" aria-pressed=\"false\" data-state=\"off\" class=\"px-toggle\" data-disabled=\"\" disabled>Disabled</button></px-toggle>"),

    % disabled AND pressed together -- both contracts hold independently.
    render_to_string(toggle_root([pressed(true), disabled(true)], "X"),
                      DisabledOn),
    check(disabled_on_both_attrs,
          ( contains(DisabledOn, "aria-pressed=\"true\""),
            contains(DisabledOn, "data-state=\"on\""),
            contains(DisabledOn, "data-disabled=\"\""),
            contains(DisabledOn, " disabled>") )),

    % ===================================================================
    % Options: id/class pass-through, class merging, computed attrs
    % come before caller pass-through (last-wins spread order).
    % ===================================================================

    render_to_string(toggle_root([id("bold-toggle"), class("wide"),
                                   aria_label("Bold")],
                                  "B"),
                      WithOpts),
    check(id_passed_through,
          contains(WithOpts, "id=\"bold-toggle\"")),
    check(aria_label_passed_through,
          contains(WithOpts, "aria-label=\"Bold\"")),
    check(class_merged_after_default,
          contains(WithOpts, "class=\"px-toggle wide\"")),
    check(id_appears_once,
          count_occurrences(WithOpts, "id=\"bold-toggle\"", 1)),

    % ===================================================================
    % Convenience wrapper `toggle/2` delegates to Root exactly.
    % ===================================================================

    render_to_string(toggle([pressed(true)], "On"), ConvOn),
    check(convenience_matches_root, ConvOn == On),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Call` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(toggle, _Order, \toggle_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(toggle, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \toggle_demo), Demo),
    check(demo_renders_all_three_states,
          ( contains(Demo, "data-state=\"off\""),
            contains(Demo, "data-state=\"on\""),
            contains(Demo, "data-disabled=\"\"") )),
    check(demo_has_three_toggles,
          count_occurrences(Demo, "<px-toggle>", 3)),

    % show some real output for the record
    format("~n--- rendered toggle_demo ---~n~w~n----------------------------~n",
           [Demo]).
