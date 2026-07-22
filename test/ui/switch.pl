/* test/ui/switch.pl (adr/0026): render-test proof for
   prolog/ui/switch.pl -- the Switch port. A plain swipl script, no
   server, no networking (milestone10_templates.pl's / test/ui/
   progress.pl's pattern): render_to_string/2 over the templates and
   assert the exact ARIA/data contract documented in
   docs/radix-port-analysis.md's "Switch" entry, for:

     - unchecked  (checked absent -> default false)
     - checked    (checked(true))
     - disabled   (disabled(true), either checked value)
     - required + name (form participation options)

   plus the convenience `switch/1` wrapper, class merging, option
   pass-through, and the kitchen-sink demo registration (px_ui:demo/3)
   rendering end to end exactly as prolog/px_ui.pl's ui_show_view
   embeds it (`\switch_demo` as a div's Children, not the bare atom --
   adr/0019's arity-0 dispatch rule).
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/switch.pl').

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
    ->  format("~nAll ui/switch checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Unchecked (default): no checked(_) option at all.
    % ===================================================================

    render_to_string(switch([id("s1")]), Unchecked),

    check(unchecked_wrapper_is_px_switch,
          ( sub_string(Unchecked, 0, _, _, "<px-switch>"),
            sub_string(Unchecked, _, _, 0, "</px-switch>") )),
    check(unchecked_label_wraps,
          ( sub_string(Unchecked, _, _, _, "<label"),
            sub_string(Unchecked, _, _, _, "</label>") )),
    check(unchecked_root_class,
          contains(Unchecked, "class=\"px-switch\"")),
    check(unchecked_root_data_state,
          contains(Unchecked, "data-state=\"unchecked\"")),
    check(unchecked_trigger_type,
          contains(Unchecked, "<input type=\"checkbox\" role=\"switch\"")),
    check(unchecked_aria_checked_false,
          contains(Unchecked, "aria-checked=\"false\"")),
    check(unchecked_aria_required_false,
          contains(Unchecked, "aria-required=\"false\"")),
    check(unchecked_trigger_data_state,
          contains(Unchecked, "data-state=\"unchecked\"")),
    check(unchecked_trigger_class,
          contains(Unchecked, "class=\"px-switch-trigger\"")),
    check(unchecked_no_native_checked,
          not_contains(Unchecked, "checked>")),
    check(unchecked_no_data_disabled,
          not_contains(Unchecked, "data-disabled")),
    check(unchecked_no_native_disabled,
          not_contains(Unchecked, " disabled")),
    check(unchecked_default_value,
          contains(Unchecked, "value=\"on\"")),
    check(unchecked_thumb_present,
          contains(Unchecked, "<span data-state=\"unchecked\" class=\"px-switch-thumb\"></span>")),
    check(unchecked_exact,
          Unchecked ==
              "<px-switch><label class=\"px-switch\" data-state=\"unchecked\" id=\"s1\"><input type=\"checkbox\" role=\"switch\" aria-checked=\"false\" aria-required=\"false\" data-state=\"unchecked\" class=\"px-switch-trigger\" value=\"on\"><span data-state=\"unchecked\" class=\"px-switch-thumb\"></span></label></px-switch>"),

    % checked(false) explicitly is the same as omitting it.
    render_to_string(switch([id("s1"), checked(false)]), UncheckedExplicit),
    check(unchecked_explicit_same_as_default, UncheckedExplicit == Unchecked),

    % ===================================================================
    % Checked: checked(true).
    % ===================================================================

    render_to_string(switch([id("s2"), checked(true)]), Checked),

    check(checked_root_data_state,
          contains(Checked, "data-state=\"checked\"")),
    check(checked_aria_checked_true,
          contains(Checked, "aria-checked=\"true\"")),
    check(checked_native_checked,
          contains(Checked, " checked value=\"on\"")),
    check(checked_thumb_data_state,
          contains(Checked, "<span data-state=\"checked\" class=\"px-switch-thumb\"></span>")),
    check(checked_data_state_count,
          % Root, Trigger, Thumb -- all three mirror data-state="checked".
          count_occurrences(Checked, "data-state=\"checked\"", 3)),

    % ===================================================================
    % Disabled: disabled(true) -- data-disabled="" plus the native
    % `disabled` attribute, mirrored on Root/Trigger/Thumb (adr/0026's
    % "harmless without JS": a disabled <input> is inert with zero JS
    % involved, and the enclosing <label> still carries the visual hook).
    % ===================================================================

    render_to_string(switch([id("s3"), disabled(true)]), Disabled),

    check(disabled_data_disabled_count,
          % Root, Trigger, Thumb -- all three mirror data-disabled="".
          count_occurrences(Disabled, "data-disabled=\"\"", 3)),
    check(disabled_native_attr,
          contains(Disabled, " disabled value=\"on\"")),
    check(disabled_aria_checked_false,
          contains(Disabled, "aria-checked=\"false\"")),

    % disabled AND checked together -- both contracts hold independently.
    render_to_string(switch([id("s4"), checked(true), disabled(true)]),
                      DisabledOn),
    check(disabled_on_both_attrs,
          ( contains(DisabledOn, "aria-checked=\"true\""),
            contains(DisabledOn, "data-state=\"checked\""),
            contains(DisabledOn, "data-disabled=\"\""),
            contains(DisabledOn, " checked disabled value=\"on\"") )),

    % ===================================================================
    % Required + name/value: form-participation options, all on Trigger.
    % ===================================================================

    render_to_string(switch([id("s5"), name("subscribe"), required(true),
                              value("yes")]),
                      Form),

    check(form_aria_required_true,
          contains(Form, "aria-required=\"true\"")),
    check(form_native_required,
          contains(Form, " required name=\"subscribe\"")),
    check(form_name,
          contains(Form, "name=\"subscribe\"")),
    check(form_value,
          contains(Form, "value=\"yes\"")),
    check(form_no_name_on_root_or_thumb,
          count_occurrences(Form, "name=\"subscribe\"", 1)),

    % No name(_) given at all -- the input stays unnamed (does not
    % submit), same as a plain <input type=checkbox> with no name.
    render_to_string(switch([]), NoName),
    check(no_name_by_default,
          not_contains(NoName, "name=")),

    % ===================================================================
    % Options: id/class pass-through (Root only), class merging, native
    % checked/disabled/required attrs come before the value attribute
    % (computed-attrs-then-pass-through spread order).
    % ===================================================================

    render_to_string(switch([id("airplane-mode"), class("wide")]),
                      WithOpts),
    check(id_passed_to_root,
          contains(WithOpts, "id=\"airplane-mode\"")),
    check(id_appears_once,
          count_occurrences(WithOpts, "id=\"airplane-mode\"", 1)),
    check(class_merged_after_default,
          contains(WithOpts, "class=\"px-switch wide\"")),
    check(trigger_keeps_fixed_class,
          contains(WithOpts, "class=\"px-switch-trigger\"")),
    check(thumb_keeps_fixed_class,
          contains(WithOpts, "class=\"px-switch-thumb\"")),

    % ===================================================================
    % Individual parts (switch_root/switch_trigger/switch_thumb) can be
    % called directly, same as progress_root/progress_indicator.
    % ===================================================================

    render_to_string(switch_trigger([checked(true)]), TriggerOnly),
    check(trigger_only_no_label,
          not_contains(TriggerOnly, "<label")),
    check(trigger_only_no_wrapper,
          not_contains(TriggerOnly, "px-switch>")),
    check(trigger_only_checked,
          contains(TriggerOnly, " checked value=\"on\"")),

    render_to_string(switch_thumb([disabled(true)]), ThumbOnly),
    check(thumb_only_exact,
          ThumbOnly ==
              "<span data-state=\"unchecked\" class=\"px-switch-thumb\" data-disabled=\"\"></span>"),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Call` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(switch, _Order, \switch_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(switch, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \switch_demo), Demo),
    check(demo_renders_all_states,
          ( contains(Demo, "data-state=\"unchecked\""),
            contains(Demo, "data-state=\"checked\""),
            contains(Demo, "data-disabled=\"\"") )),
    check(demo_has_four_switches,
          count_occurrences(Demo, "<px-switch>", 4)),

    % show some real output for the record
    format("~n--- rendered switch_demo ---~n~w~n----------------------------~n",
           [Demo]).
