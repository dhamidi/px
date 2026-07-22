/* test/ui/form.pl (adr/0026): render-test proof for prolog/ui/form.pl
   -- the Form port. A plain swipl script, no server, no networking
   (test/ui/checkbox.pl's / test/ui/radio_group.pl's pattern):
   render_to_string/2 over the templates and assert the exact
   ARIA/data contract documented in docs/radix-port-analysis.md's
   "Form" entry AND prolog/ui/form.pl's own module header (novalidate,
   the aria-invalid-is-server-only rule, the hidden/data-forced
   Message contract, aria-describedby wiring), for:

     - form_root       <px-form><form novalidate class="px-form" ...>
     - form_field       id/name-required, invalid tri-state
                         (none/true/false), Children-rewriting
                         (for/id/name/invalid/describedby injection),
                         message-id synthesis
     - form_label       delegates to label_root/2 (prolog/ui/label.pl)
                         -- "px-label px-form-label" class, data-valid/
                         invalid tri-state
     - form_control     as(input|textarea|select), type default,
                         title="" default, aria-invalid ONLY on
                         invalid(true), aria-describedby merge/dedup
     - form_message     match(_) -> data-match kebab-case, forced(true)
                         -> visible + data-forced, default -> hidden
     - form_submit      <button type="submit">

   plus the individual parts called directly (bare, no form_field --
   the "usable to hand-write forms" half of the module's brief), and
   the kitchen-sink demo registration (px_ui:demo/3) rendering end to
   end exactly as prolog/px_ui.pl's ui_show_view embeds it (`\form_demo`
   as a div's Children, not the bare atom -- adr/0019's arity-0
   dispatch rule).

   Run:  swipl test/ui/form.pl
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/label.pl').
:- use_module('../../prolog/ui/form.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Harness (test/ui/checkbox.pl's pattern).
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
    ->  format("~nAll ui/form checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % form_root: always <px-form> wrapping <form novalidate class="px-form">.
    % ===================================================================

    render_to_string(form_root([id("f1")], []), Root),
    check(root_wrapper, ( sub_string(Root, 0, _, _, "<px-form>"),
                           sub_string(Root, _, _, 0, "</px-form>") )),
    check(root_novalidate, contains(Root, "novalidate")),
    check(root_class, contains(Root, "class=\"px-form\"")),
    check(root_id, contains(Root, "id=\"f1\"")),
    check(root_exact,
          Root == "<px-form><form class=\"px-form\" novalidate id=\"f1\"></form></px-form>"),

    % class(_) opt merges, does not replace.
    render_to_string(form_root([class("wide")], []), RootClass),
    check(root_class_merge, contains(RootClass, "class=\"px-form wide\"")),

    % ===================================================================
    % form_field: name(_) required; id defaults to "px-form-field-<name>";
    % invalid tri-state (none/true/false) drives data-valid/data-invalid
    % identically to what form_label/form_control get.
    % ===================================================================

    catch(
        ( render_to_string(form_field([], []), _), FieldNoName = false ),
        error(existence_error(option, name), _),
        FieldNoName = true
    ),
    check(field_name_required, FieldNoName == true),

    render_to_string(form_field([name(email)], []), FieldNone),
    check(field_no_invalid_attrs_by_default,
          ( not_contains(FieldNone, "data-invalid"),
            not_contains(FieldNone, "data-valid") )),
    check(field_class, contains(FieldNone, "class=\"px-form-field\"")),
    % form_field renders a <div>, not a <form> -- id lives on the div here.
    check(field_is_div,
          ( sub_string(FieldNone, 0, _, _, "<div"),
            sub_string(FieldNone, _, _, 0, "</div>") )),

    % Field itself carries no id of its own (Radix's Field is a
    % context provider, not necessarily an id-bearing DOM node) -- the
    % default "px-form-field-<name>" id is what gets INJECTED into a
    % child Control/Label, verified here via a bare Control child.
    render_to_string(form_field([name(email)], [form_control([])]), FieldDefaultId),
    check(field_default_id, contains(FieldDefaultId, "id=\"px-form-field-email\"")),

    render_to_string(form_field([name(email), invalid(true)], []), FieldTrue),
    check(field_invalid_true, contains(FieldTrue, "data-invalid=\"\"")),
    check(field_invalid_true_no_valid, not_contains(FieldTrue, "data-valid")),

    render_to_string(form_field([name(email), invalid(false)], []), FieldFalse),
    check(field_invalid_false, contains(FieldFalse, "data-valid=\"\"")),
    check(field_invalid_false_no_invalid, not_contains(FieldFalse, "data-invalid")),

    % explicit id(_) overrides the default -- the px_form-composition
    % escape hatch (module header) -- again observed via an injected
    % child Control.
    render_to_string(
        form_field([name(title), id('post_form_title')], [form_control([])]),
        FieldCustomId),
    check(field_custom_id, contains(FieldCustomId, "id=\"post_form_title\"")),

    % ===================================================================
    % form_field Children-rewriting: form_label gets for(Id); form_control
    % gets id/name/invalid/describedby; form_message gets id -- ALL only
    % when not already explicit; anything else passes through untouched.
    % ===================================================================

    render_to_string(
        form_field([name(email), invalid(true)],
          [ form_label([], "Email"),
            form_control([type(email), required]),
            form_message([match(value_missing)], "Required"),
            form_message([match(type_mismatch)], "Bad format"),
            p("interleaved plain markup")
          ]),
        Wired),

    check(wired_label_for, contains(Wired, "for=\"px-form-field-email\"")),
    check(wired_label_invalid, contains(Wired, "<label class=\"px-label px-form-label\" data-invalid=\"\" for=\"px-form-field-email\">")),
    check(wired_control_id, contains(Wired, "id=\"px-form-field-email\"")),
    check(wired_control_name, contains(Wired, "name=\"email\"")),
    check(wired_control_aria_invalid, contains(Wired, "aria-invalid=\"true\"")),
    check(wired_control_data_invalid,
          % Field, Label, Control -- all three mirror data-invalid identically.
          count_occurrences(Wired, "data-invalid=\"\"", 3)),
    check(wired_describedby,
          contains(Wired, "aria-describedby=\"px-form-field-email-message-1 px-form-field-email-message-2\"")),
    check(wired_message_1_id, contains(Wired, "id=\"px-form-field-email-message-1\"")),
    check(wired_message_2_id, contains(Wired, "id=\"px-form-field-email-message-2\"")),
    check(wired_message_1_match, contains(Wired, "data-match=\"value-missing\"")),
    check(wired_message_2_match, contains(Wired, "data-match=\"type-mismatch\"")),
    check(wired_plain_markup_passthrough, contains(Wired, "<p>interleaved plain markup</p>")),

    % Explicit options on a child win over Field's injected ones.
    render_to_string(
        form_field([name(email)],
          [ form_label([for(custom_for)], "Email"),
            form_control([id(custom_id), name(custom_name)])
          ]),
        WiredExplicit),
    check(explicit_for_wins, contains(WiredExplicit, "for=\"custom_for\"")),
    check(explicit_for_no_default, not_contains(WiredExplicit, "px-form-field-email\">")),
    check(explicit_id_wins, contains(WiredExplicit, "id=\"custom_id\"")),
    check(explicit_name_wins, contains(WiredExplicit, "name=\"custom_name\"")),

    % ===================================================================
    % form_label: bare call (hand-written forms, no Field). Delegates to
    % ui/label.pl's label_root/2 -- "px-label px-form-label" class.
    % ===================================================================

    render_to_string(form_label([for("x")], "Email"), Label),
    check(label_class, contains(Label, "class=\"px-label px-form-label\"")),
    check(label_for, contains(Label, "for=\"x\"")),
    check(label_no_state_by_default,
          ( not_contains(Label, "data-valid"), not_contains(Label, "data-invalid") )),
    check(label_exact,
          Label == "<label class=\"px-label px-form-label\" for=\"x\">Email</label>"),

    render_to_string(form_label([for("x"), invalid(true)], "Email"), LabelInvalid),
    check(label_invalid, contains(LabelInvalid, "data-invalid=\"\"")),

    % caller class(_) is additive, on top of BOTH merges.
    render_to_string(form_label([class("extra")], "Email"), LabelClass),
    check(label_class_merge, contains(LabelClass, "class=\"px-label px-form-label extra\"")),

    % ===================================================================
    % form_control: bare call. as(input) default, type default "text",
    % title="" default, no aria-invalid unless invalid(true).
    % ===================================================================

    render_to_string(form_control([]), ControlDefault),
    check(control_default_type, contains(ControlDefault, "type=\"text\"")),
    check(control_default_title, contains(ControlDefault, "title=\"\"")),
    check(control_default_class, contains(ControlDefault, "class=\"px-form-control\"")),
    check(control_no_aria_invalid_by_default, not_contains(ControlDefault, "aria-invalid")),
    check(control_no_describedby_by_default, not_contains(ControlDefault, "aria-describedby")),
    check(control_is_input,
          ( sub_string(ControlDefault, 0, _, _, "<input"),
            not_contains(ControlDefault, "</input>") )),

    render_to_string(form_control([type(email)]), ControlEmail),
    check(control_type_email, contains(ControlEmail, "type=\"email\"")),

    render_to_string(form_control([invalid(true)]), ControlInvalid),
    check(control_invalid_aria, contains(ControlInvalid, "aria-invalid=\"true\"")),
    check(control_invalid_data, contains(ControlInvalid, "data-invalid=\"\"")),

    render_to_string(form_control([invalid(false)]), ControlValid),
    check(control_valid_no_aria, not_contains(ControlValid, "aria-invalid")),
    check(control_valid_data, contains(ControlValid, "data-valid=\"\"")),

    % caller-supplied title(_) overrides the "" default.
    render_to_string(form_control([title("hint")]), ControlTitle),
    check(control_title_override, contains(ControlTitle, "title=\"hint\"")),
    check(control_title_override_once, count_occurrences(ControlTitle, "title=", 1)),

    % describedby(_) opt, and dedup against an author-supplied
    % aria_describedby(_).
    render_to_string(
        form_control([describedby([m1, m2]), aria_describedby("m2 extra")]),
        ControlDescribed),
    check(control_describedby_union,
          contains(ControlDescribed, "aria-describedby=\"m1 m2 extra\"")),
    check(control_describedby_once, count_occurrences(ControlDescribed, "aria-describedby=", 1)),

    % as(textarea) / as(select): no type attribute, Children used.
    render_to_string(form_control([as(textarea), required], []), ControlTextarea),
    check(control_textarea_tag,
          ( sub_string(ControlTextarea, 0, _, _, "<textarea"),
            sub_string(ControlTextarea, _, _, 0, "</textarea>") )),
    check(control_textarea_no_type, not_contains(ControlTextarea, "type=")),
    check(control_textarea_required, contains(ControlTextarea, " required")),

    render_to_string(form_control([as(select)], [option([value(a)], "A")]), ControlSelect),
    check(control_select_tag,
          ( sub_string(ControlSelect, 0, _, _, "<select"),
            sub_string(ControlSelect, _, _, 0, "</select>") )),
    check(control_select_no_type, not_contains(ControlSelect, "type=")),
    check(control_select_option, contains(ControlSelect, "<option value=\"a\">A</option>")),

    % arity-1 shorthand == arity-2 with empty Children.
    render_to_string(form_control([type(email)]), ControlArity1),
    render_to_string(form_control([type(email)], []), ControlArity2),
    check(control_arity_shorthand, ControlArity1 == ControlArity2),

    % ===================================================================
    % form_message: match(_) -> kebab-case data-match; forced(_) ->
    % visible + data-forced; default hidden, no data-match.
    % ===================================================================

    render_to_string(form_message([], "Any error"), MessageDefault),
    check(message_default_hidden, contains(MessageDefault, " hidden")),
    check(message_default_no_match, not_contains(MessageDefault, "data-match")),
    check(message_default_no_forced, not_contains(MessageDefault, "data-forced")),
    check(message_default_class, contains(MessageDefault, "class=\"px-form-message\"")),
    check(message_default_exact,
          MessageDefault == "<span class=\"px-form-message\" hidden>Any error</span>"),

    render_to_string(form_message([match(value_missing)], "Required"), MessageValueMissing),
    check(message_value_missing, contains(MessageValueMissing, "data-match=\"value-missing\"")),
    check(message_value_missing_hidden, contains(MessageValueMissing, " hidden")),

    findall(Kebab,
            ( member(M-Kebab,
                     [ value_missing-"value-missing", type_mismatch-"type-mismatch",
                       pattern_mismatch-"pattern-mismatch", too_long-"too-long",
                       too_short-"too-short", range_underflow-"range-underflow",
                       range_overflow-"range-overflow", step_mismatch-"step-mismatch",
                       bad_input-"bad-input"
                     ]),
              render_to_string(form_message([match(M)], "x"), Rendered),
              contains(Rendered, Kebab)
            ),
            AllMatchKeys),
    length(AllMatchKeys, NAllMatchKeys),
    check(all_nine_matchers, NAllMatchKeys == 9),

    catch(
        ( render_to_string(form_message([match(bogus)], "x"), _), MatchBogus = false ),
        error(domain_error(px_form_message_match, bogus), _),
        MatchBogus = true
    ),
    check(message_bad_match_throws, MatchBogus == true),

    render_to_string(form_message([forced(true)], "Server says no"), MessageForced),
    check(message_forced_visible, not_contains(MessageForced, "hidden")),
    check(message_forced_marker, contains(MessageForced, "data-forced=\"\"")),
    check(message_forced_exact,
          MessageForced == "<span class=\"px-form-message\" data-forced=\"\">Server says no</span>"),

    % ===================================================================
    % form_submit: plain submit button.
    % ===================================================================

    render_to_string(form_submit([], "Submit"), Submit),
    check(submit_exact,
          Submit == "<button type=\"submit\" class=\"px-form-submit\">Submit</button>"),

    render_to_string(form_submit([disabled], "Submit"), SubmitDisabled),
    check(submit_disabled, contains(SubmitDisabled, " disabled")),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Call` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(form, _Order, \form_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(form, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \form_demo), Demo),
    check(demo_has_px_form_wrapper, contains(Demo, "<px-form>")),
    check(demo_has_novalidate, contains(Demo, "novalidate")),
    check(demo_has_email_field, contains(Demo, "type=\"email\"")),
    check(demo_has_value_missing, contains(Demo, "data-match=\"value-missing\"")),
    check(demo_has_type_mismatch, contains(Demo, "data-match=\"type-mismatch\"")),
    check(demo_has_textarea, contains(Demo, "<textarea")),
    check(demo_has_forced_message,
          ( contains(Demo, "data-forced=\"\""),
            contains(Demo, "This username is already taken.") )),
    check(demo_forced_field_invalid, contains(Demo, "aria-invalid=\"true\"")),
    check(demo_has_submit, count_occurrences(Demo, "type=\"submit\"", 2)),

    % show some real output for the record
    format("~n--- rendered form_demo ---~n~w~n------------------------------~n",
           [Demo]).
