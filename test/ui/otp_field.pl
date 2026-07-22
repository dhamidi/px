/* test/ui/otp_field.pl (adr/0026): render-test proof for
   prolog/ui/otp_field.pl -- the One-Time Password Field port. A plain
   swipl script, no server, no networking (test/ui/toggle_group.pl's /
   test/ui/radio_group.pl's pattern): render_to_string/2 over the
   templates and assert the exact ARIA/data contract documented in
   docs/radix-port-analysis.md's "One-Time Password Field" entry, for:

     - Root:    <px-otp-field><div role="group" ...>, data-numeric
                (default true), data-auto-submit (only when true),
                data-disabled (Root only, no propagation)
     - Input:   aria-label="Character {i} of {N}", maxlength/
                autocomplete placement (first cell only gets
                autocomplete="one-time-code" + full maxlength; every
                other cell gets autocomplete="off" plus the four
                password-manager-suppression data-* attributes),
                data-filled only when an initial value is given,
                inputmode/pattern per `numeric`
     - HiddenInput: type=hidden, readonly, name, value (omitted when
                blank)
     - the `otp_field/1,2` convenience: length(N) default 6, name(_)
       default gensym, value(_) sliced across the first cells,
       disabled/numeric threaded onto every generated part
     - the kitchen-sink demo registration (px_ui:demo/3) rendering end
       to end exactly as prolog/px_ui.pl's ui_show_view embeds it
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/otp_field.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Harness (test/ui/toggle_group.pl's / test/ui/radio_group.pl's pattern).
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
    ->  format("~nAll ui/otp_field checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Root: bare call, no options -- role=group, data-numeric (default
    % true), no data-auto-submit/data-disabled by default.
    % ===================================================================

    render_to_string(otp_field_root([], []), RootDefault),

    check(root_wrapper_is_px_otp_field,
          ( sub_string(RootDefault, 0, _, _, "<px-otp-field>"),
            sub_string(RootDefault, _, _, 0, "</px-otp-field>") )),
    check(root_role_group,
          contains(RootDefault, "role=\"group\"")),
    check(root_default_aria_label,
          contains(RootDefault, "aria-label=\"One-time password\"")),
    check(root_default_class,
          contains(RootDefault, "class=\"px-otp-field\"")),
    check(root_default_numeric,
          contains(RootDefault, "data-numeric=\"\"")),
    check(root_default_no_auto_submit,
          not_contains(RootDefault, "data-auto-submit")),
    check(root_default_no_disabled,
          not_contains(RootDefault, "data-disabled")),

    % ===================================================================
    % Root: numeric(false), auto_submit(true), disabled(true), plus
    % id/class/aria_label pass-through and merging.
    % ===================================================================

    render_to_string(
        otp_field_root([numeric(false), auto_submit(true), disabled(true),
                         id("otp1"), class("wide"), aria_label("Code")],
                        []),
        RootOpts),

    check(root_numeric_false_omits_attr,
          not_contains(RootOpts, "data-numeric")),
    check(root_auto_submit_true,
          contains(RootOpts, "data-auto-submit=\"\"")),
    check(root_disabled_true,
          contains(RootOpts, "data-disabled=\"\"")),
    check(root_id_passed_through,
          contains(RootOpts, "id=\"otp1\"")),
    check(root_class_merged_after_default,
          contains(RootOpts, "class=\"px-otp-field wide\"")),
    check(root_aria_label_override,
          contains(RootOpts, "aria-label=\"Code\"")),

    % ===================================================================
    % Input: first cell -- autocomplete="one-time-code", maxlength = N,
    % no password-manager-suppression attributes.
    % ===================================================================

    render_to_string(otp_field_input([index(1), total(6)]), InputFirst),

    check(input_first_aria_label,
          contains(InputFirst, "aria-label=\"Character 1 of 6\"")),
    check(input_first_autocomplete_otc,
          contains(InputFirst, "autocomplete=\"one-time-code\"")),
    check(input_first_maxlength_full,
          contains(InputFirst, "maxlength=\"6\"")),
    check(input_first_no_password_manager_attrs,
          ( not_contains(InputFirst, "data-1p-ignore"),
            not_contains(InputFirst, "data-lpignore"),
            not_contains(InputFirst, "data-bwignore"),
            not_contains(InputFirst, "data-form-type") )),
    check(input_first_class,
          contains(InputFirst, "class=\"px-otp-field-input\"")),
    check(input_first_inputmode_numeric,
          contains(InputFirst, "inputmode=\"numeric\"")),
    check(input_first_no_filled,
          not_contains(InputFirst, "data-filled")),
    check(input_first_no_value_attr,
          not_contains(InputFirst, "value=")),

    % ===================================================================
    % Input: non-first cell -- autocomplete="off", maxlength=1, plus
    % the four password-manager-suppression data-* attributes.
    % ===================================================================

    render_to_string(otp_field_input([index(2), total(6)]), InputOther),

    check(input_other_aria_label,
          contains(InputOther, "aria-label=\"Character 2 of 6\"")),
    check(input_other_autocomplete_off,
          contains(InputOther, "autocomplete=\"off\"")),
    check(input_other_maxlength_one,
          contains(InputOther, "maxlength=\"1\"")),
    check(input_other_1p_ignore,
          contains(InputOther, "data-1p-ignore")),
    check(input_other_lpignore,
          contains(InputOther, "data-lpignore=\"true\"")),
    check(input_other_bwignore,
          contains(InputOther, "data-bwignore=\"true\"")),
    check(input_other_form_type,
          contains(InputOther, "data-form-type=\"other\"")),

    % ===================================================================
    % Input: missing index/total is a hard error.
    % ===================================================================

    check(input_missing_index_throws,
          catch((render_to_string(otp_field_input([total(6)]), _), fail),
                error(existence_error(option, index), _),
                true)),
    check(input_missing_total_throws,
          catch((render_to_string(otp_field_input([index(1)]), _), fail),
                error(existence_error(option, total), _),
                true)),

    % ===================================================================
    % Input: value(Ch) -- value attribute + data-filled; numeric(false)
    % -- inputmode=text, no pattern; disabled(true).
    % ===================================================================

    render_to_string(otp_field_input([index(3), total(6), value("7")]),
                      InputValue),
    check(input_value_attr,
          contains(InputValue, "value=\"7\"")),
    check(input_value_filled,
          contains(InputValue, "data-filled=\"\"")),

    render_to_string(
        otp_field_input([index(2), total(6), numeric(false)]),
        InputTextMode),
    check(input_numeric_false_inputmode_text,
          contains(InputTextMode, "inputmode=\"text\"")),
    check(input_numeric_false_no_pattern,
          not_contains(InputTextMode, "pattern")),

    render_to_string(
        otp_field_input([index(2), total(6), disabled(true)]),
        InputDisabled),
    check(input_disabled_attrs,
          ( contains(InputDisabled, "data-disabled=\"\""),
            contains(InputDisabled, "disabled") )),

    % ===================================================================
    % HiddenInput: name required, readonly, type=hidden; value omitted
    % when blank, present when given; disabled optional.
    % ===================================================================

    render_to_string(otp_field_hidden_input([name(otp)]), HiddenBlank),
    check(hidden_type,
          contains(HiddenBlank, "type=\"hidden\"")),
    check(hidden_name,
          contains(HiddenBlank, "name=\"otp\"")),
    check(hidden_readonly,
          contains(HiddenBlank, "readonly")),
    check(hidden_class,
          contains(HiddenBlank, "class=\"px-otp-field-hidden-input\"")),
    check(hidden_blank_no_value_attr,
          not_contains(HiddenBlank, "value=")),

    render_to_string(
        otp_field_hidden_input([name(otp), value("123456")]),
        HiddenValue),
    check(hidden_value_attr,
          contains(HiddenValue, "value=\"123456\"")),

    check(hidden_missing_name_throws,
          catch((render_to_string(otp_field_hidden_input([]), _), fail),
                error(existence_error(option, name), _),
                true)),

    % ===================================================================
    % Convenience `otp_field/1`: default length(6), gensym name, six
    % cells with the correct index/total, exactly one hidden input.
    % ===================================================================

    render_to_string(otp_field([id("f1")]), FieldDefault),

    check(field_default_six_cells,
          count_occurrences(FieldDefault, "class=\"px-otp-field-input\"", 6)),
    check(field_default_one_hidden_input,
          count_occurrences(FieldDefault, "class=\"px-otp-field-hidden-input\"", 1)),
    check(field_default_last_cell_total_six,
          contains(FieldDefault, "aria-label=\"Character 6 of 6\"")),
    check(field_default_gensym_name,
          contains(FieldDefault, "name=\"px-otp-field-")),
    check(field_default_hidden_no_value,
          % No value(_) given -> every cell AND the hidden input start
          % blank -> value_attr/2's blank rule omits the attribute
          % everywhere in this render.
          not_contains(FieldDefault, "value=")),

    % ===================================================================
    % Convenience: explicit length/name/value, sliced across cells,
    % hidden input pre-filled with the same prefix.
    % ===================================================================

    render_to_string(
        otp_field([length(4), name("code"), value("12")]),
        FieldPrefilled),

    check(field_prefilled_four_cells,
          count_occurrences(FieldPrefilled, "class=\"px-otp-field-input\"", 4)),
    check(field_prefilled_name,
          contains(FieldPrefilled, "name=\"code\"")),
    check(field_prefilled_hidden_value,
          contains(FieldPrefilled, "value=\"12\"")),
    check(field_prefilled_two_filled_cells,
          count_occurrences(FieldPrefilled, "data-filled=\"\"", 2)),
    check(field_prefilled_first_cell_value,
          contains(FieldPrefilled, "value=\"1\"")),
    check(field_prefilled_second_cell_value,
          contains(FieldPrefilled, "value=\"2\"")),

    % value(_) longer than length(_) is truncated to the cell count.
    render_to_string(
        otp_field([length(3), name("code2"), value("123456")]),
        FieldTruncated),
    check(field_value_truncated_to_length,
          contains(FieldTruncated, "value=\"123\"")),
    check(field_value_truncated_three_cells,
          count_occurrences(FieldTruncated, "class=\"px-otp-field-input\"", 3)),

    % ===================================================================
    % Convenience: disabled/numeric threaded onto Root AND every
    % generated Input (and disabled onto the HiddenInput too).
    % ===================================================================

    render_to_string(
        otp_field([length(3), name("code3"), disabled(true), numeric(false)]),
        FieldDisabled),

    check(field_disabled_root,
          contains(FieldDisabled, "role=\"group\"")),
    check(field_disabled_root_flag,
          sub_string(FieldDisabled, _, _, _, "role=\"group\" aria-label=\"One-time password\" class=\"px-otp-field\" data-disabled=\"\"")),
    check(field_disabled_every_cell,
          count_occurrences(FieldDisabled, "data-disabled=\"\" disabled", 3)),
    check(field_disabled_hidden_input,
          sub_string(FieldDisabled, _, _, _, "class=\"px-otp-field-hidden-input\" disabled")),
    check(field_disabled_numeric_false_everywhere,
          not_contains(FieldDisabled, "data-numeric")),
    check(field_disabled_inputmode_text,
          count_occurrences(FieldDisabled, "inputmode=\"text\"", 3)),

    % `otp_field/2` appends extra content after the generated parts.
    render_to_string(
        otp_field([length(2), name("code4")], [span(class("hint"), "hint")]),
        FieldExtra),
    check(field_extra_children_appended,
          contains(FieldExtra, "<span class=\"hint\">hint</span>")),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Call` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(otp_field, _Order, \otp_field_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(otp_field, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \otp_field_demo), Demo),
    check(demo_has_two_fields,
          count_occurrences(Demo, "<px-otp-field>", 2)),
    check(demo_has_form,
          contains(Demo, "<form")),
    check(demo_has_hidden_readout,
          contains(Demo, "id=\"otp-demo-readout\"")),
    check(demo_has_disabled_field,
          contains(Demo, "data-disabled=\"\"")),
    check(demo_has_prefilled_cells,
          contains(Demo, "data-filled=\"\"")),

    % show some real output for the record
    format("~n--- rendered otp_field_demo ---~n~w~n-----------------------------------~n",
           [Demo]).
