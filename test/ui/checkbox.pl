/* test/ui/checkbox.pl (adr/0026): render-test proof for
   prolog/ui/checkbox.pl -- the Checkbox port. A plain swipl script, no
   server, no networking (test/ui/switch.pl's / test/ui/progress.pl's
   pattern): render_to_string/2 over the templates and assert the exact
   ARIA/data contract documented in docs/radix-port-analysis.md's
   "Checkbox" entry, for:

     - unchecked      (checked absent -> default false, no <px-checkbox>
                        wrapper, Indicator Presence-gated out of the DOM)
     - checked         (checked(true), Indicator present, no wrapper)
     - indeterminate   (checked(indeterminate), wrapped in <px-checkbox>,
                        aria-checked="mixed", Indicator present)
     - disabled        (disabled(true), either checked value)
     - required + name/value (form participation options)

   plus the convenience `checkbox/1` wrapper, class merging, option
   pass-through, the individual parts called directly
   (checkbox_input/1, checkbox_indicator/1 -- same as
   progress_root/progress_indicator, switch_trigger/switch_thumb), and
   the kitchen-sink demo registration (px_ui:demo/3) rendering end to
   end exactly as prolog/px_ui.pl's ui_show_view embeds it (`\checkbox_demo`
   as a div's Children, not the bare atom -- adr/0019's arity-0
   dispatch rule).
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/checkbox.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Harness (test/ui/switch.pl's / test/ui/progress.pl's pattern).
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
    ->  format("~nAll ui/checkbox checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Unchecked (default): no checked(_) option at all. No <px-checkbox>
    % wrapper (NATIVE, zero JS); Indicator Presence-gated out entirely.
    % ===================================================================

    render_to_string(checkbox([id("s1")]), Unchecked),

    check(unchecked_no_wrapper,
          not_contains(Unchecked, "px-checkbox>")),
    check(unchecked_label_wraps,
          ( sub_string(Unchecked, 0, _, _, "<label"),
            sub_string(Unchecked, _, _, 0, "</label>") )),
    check(unchecked_root_class,
          contains(Unchecked, "class=\"px-checkbox\"")),
    check(unchecked_root_data_state,
          contains(Unchecked, "data-state=\"unchecked\"")),
    check(unchecked_input_type_role,
          contains(Unchecked, "<input type=\"checkbox\" role=\"checkbox\"")),
    check(unchecked_aria_checked_false,
          contains(Unchecked, "aria-checked=\"false\"")),
    check(unchecked_aria_required_false,
          contains(Unchecked, "aria-required=\"false\"")),
    check(unchecked_input_data_state,
          contains(Unchecked, "data-state=\"unchecked\"")),
    check(unchecked_input_class,
          contains(Unchecked, "class=\"px-checkbox-input\"")),
    check(unchecked_no_native_checked,
          not_contains(Unchecked, "checked>")),
    check(unchecked_no_data_disabled,
          not_contains(Unchecked, "data-disabled")),
    check(unchecked_no_native_disabled,
          not_contains(Unchecked, " disabled")),
    check(unchecked_default_value,
          contains(Unchecked, "value=\"on\"")),
    check(unchecked_no_indicator,
          not_contains(Unchecked, "px-checkbox-indicator")),
    check(unchecked_exact,
          Unchecked ==
              "<label class=\"px-checkbox\" data-state=\"unchecked\" id=\"s1\"><input type=\"checkbox\" role=\"checkbox\" aria-checked=\"false\" aria-required=\"false\" data-state=\"unchecked\" class=\"px-checkbox-input\" value=\"on\"></label>"),

    % checked(false) explicitly is the same as omitting it.
    render_to_string(checkbox([id("s1"), checked(false)]), UncheckedExplicit),
    check(unchecked_explicit_same_as_default, UncheckedExplicit == Unchecked),

    % An invalid checked(_) value falls back to false too.
    render_to_string(checkbox([id("s1"), checked(bogus)]), UncheckedBogus),
    check(unchecked_bogus_same_as_default, UncheckedBogus == Unchecked),

    % ===================================================================
    % Checked: checked(true). Indicator present, still no wrapper.
    % ===================================================================

    render_to_string(checkbox([id("s2"), checked(true)]), Checked),

    check(checked_no_wrapper,
          not_contains(Checked, "px-checkbox>")),
    check(checked_root_data_state,
          contains(Checked, "data-state=\"checked\"")),
    check(checked_aria_checked_true,
          contains(Checked, "aria-checked=\"true\"")),
    check(checked_native_checked,
          contains(Checked, " checked value=\"on\"")),
    check(checked_indicator_present,
          contains(Checked, "<span data-state=\"checked\" class=\"px-checkbox-indicator\"></span>")),
    check(checked_data_state_count,
          % Root, Trigger, Indicator -- all three mirror data-state="checked".
          count_occurrences(Checked, "data-state=\"checked\"", 3)),

    % ===================================================================
    % Indeterminate: checked(indeterminate). Wrapped in <px-checkbox>,
    % aria-checked="mixed", no native `checked` attribute, Indicator
    % present.
    % ===================================================================

    render_to_string(checkbox([id("s3"), checked(indeterminate)]), Indeterminate),

    check(indeterminate_wrapper,
          ( sub_string(Indeterminate, 0, _, _, "<px-checkbox>"),
            sub_string(Indeterminate, _, _, 0, "</px-checkbox>") )),
    check(indeterminate_aria_checked_mixed,
          contains(Indeterminate, "aria-checked=\"mixed\"")),
    check(indeterminate_data_state,
          contains(Indeterminate, "data-state=\"indeterminate\"")),
    check(indeterminate_data_state_count,
          % Root, Trigger, Indicator -- all three mirror it.
          count_occurrences(Indeterminate, "data-state=\"indeterminate\"", 3)),
    check(indeterminate_no_native_checked,
          not_contains(Indeterminate, "checked>")),
    check(indeterminate_indicator_present,
          contains(Indeterminate, "<span data-state=\"indeterminate\" class=\"px-checkbox-indicator\"></span>")),
    check(indeterminate_exact,
          Indeterminate ==
              "<px-checkbox><label class=\"px-checkbox\" data-state=\"indeterminate\" id=\"s3\"><input type=\"checkbox\" role=\"checkbox\" aria-checked=\"mixed\" aria-required=\"false\" data-state=\"indeterminate\" class=\"px-checkbox-input\" value=\"on\"><span data-state=\"indeterminate\" class=\"px-checkbox-indicator\"></span></label></px-checkbox>"),

    % ===================================================================
    % Disabled: disabled(true) -- data-disabled="" plus the native
    % `disabled` attribute, mirrored on Root/Trigger (and Indicator when
    % it is present at all).
    % ===================================================================

    render_to_string(checkbox([id("s4"), disabled(true)]), Disabled),

    check(disabled_unchecked_no_indicator,
          not_contains(Disabled, "px-checkbox-indicator")),
    check(disabled_data_disabled_count,
          % Root, Trigger -- Indicator is absent (unchecked -> Presence-gated out).
          count_occurrences(Disabled, "data-disabled=\"\"", 2)),
    check(disabled_native_attr,
          contains(Disabled, " disabled value=\"on\"")),
    check(disabled_aria_checked_false,
          contains(Disabled, "aria-checked=\"false\"")),

    % disabled AND checked together -- both contracts hold independently,
    % and now the Indicator IS present (checked -> not Presence-gated
    % out), so all three mirror data-disabled.
    render_to_string(checkbox([id("s5"), checked(true), disabled(true)]),
                      DisabledOn),
    check(disabled_on_both_attrs,
          ( contains(DisabledOn, "aria-checked=\"true\""),
            contains(DisabledOn, "data-state=\"checked\""),
            contains(DisabledOn, " checked disabled value=\"on\"") )),
    check(disabled_on_data_disabled_count,
          count_occurrences(DisabledOn, "data-disabled=\"\"", 3)),

    % ===================================================================
    % Required + name/value: form-participation options, all on Trigger.
    % ===================================================================

    render_to_string(checkbox([id("s6"), name("terms"), required(true),
                                value("yes")]),
                      Form),

    check(form_aria_required_true,
          contains(Form, "aria-required=\"true\"")),
    check(form_native_required,
          contains(Form, " required name=\"terms\"")),
    check(form_name,
          contains(Form, "name=\"terms\"")),
    check(form_value,
          contains(Form, "value=\"yes\"")),
    check(form_no_name_on_root,
          count_occurrences(Form, "name=\"terms\"", 1)),

    % No name(_) given at all -- the input stays unnamed (does not
    % submit), same as a plain <input type=checkbox> with no name.
    render_to_string(checkbox([]), NoName),
    check(no_name_by_default,
          not_contains(NoName, "name=")),

    % ===================================================================
    % Options: id/class pass-through (Root only), class merging, Trigger/
    % Indicator keep their own fixed classes.
    % ===================================================================

    render_to_string(checkbox([id("airplane-mode"), class("wide"),
                                checked(true)]),
                      WithOpts),
    check(id_passed_to_root,
          contains(WithOpts, "id=\"airplane-mode\"")),
    check(id_appears_once,
          count_occurrences(WithOpts, "id=\"airplane-mode\"", 1)),
    check(class_merged_after_default,
          contains(WithOpts, "class=\"px-checkbox wide\"")),
    check(input_keeps_fixed_class,
          contains(WithOpts, "class=\"px-checkbox-input\"")),
    check(indicator_keeps_fixed_class,
          contains(WithOpts, "class=\"px-checkbox-indicator\"")),

    % ===================================================================
    % Individual parts (checkbox_root/checkbox_input/checkbox_indicator)
    % can be called directly, same as progress_root/progress_indicator
    % and switch_trigger/switch_thumb.
    % ===================================================================

    render_to_string(checkbox_input([checked(true)]), InputOnly),
    check(input_only_no_label,
          not_contains(InputOnly, "<label")),
    check(input_only_no_wrapper,
          not_contains(InputOnly, "px-checkbox>")),
    check(input_only_checked,
          contains(InputOnly, " checked value=\"on\"")),

    % checkbox_indicator/1 called directly always mounts (upstream's
    % forceMount escape hatch), even for an unchecked state.
    render_to_string(checkbox_indicator([disabled(true)]), IndicatorOnly),
    check(indicator_only_exact,
          IndicatorOnly ==
              "<span data-state=\"unchecked\" class=\"px-checkbox-indicator\" data-disabled=\"\"></span>"),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Call` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(checkbox, _Order, \checkbox_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(checkbox, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \checkbox_demo), Demo),
    check(demo_renders_all_states,
          ( contains(Demo, "data-state=\"unchecked\""),
            contains(Demo, "data-state=\"checked\""),
            contains(Demo, "data-state=\"indeterminate\""),
            contains(Demo, "data-disabled=\"\"") )),
    check(demo_has_seven_inputs,
          count_occurrences(Demo, "<input type=\"checkbox\" role=\"checkbox\"", 7)),
    check(demo_has_one_wrapper,
          count_occurrences(Demo, "<px-checkbox>", 1)),
    check(demo_has_form,
          ( contains(Demo, "<form method=\"get\" action=\"/ui/checkbox\">"),
            contains(Demo, "</form>") )),

    % show some real output for the record
    format("~n--- rendered checkbox_demo ---~n~w~n------------------------------~n",
           [Demo]).
