/* test/ui/password_toggle_field.pl (adr/0026): render-test proof for
   prolog/ui/password_toggle_field.pl -- the Password Toggle Field
   port. A plain swipl script, no server, no networking (test/ui/
   switch.pl's / test/ui/checkbox.pl's pattern): render_to_string/2
   over the templates and assert the exact ARIA/data contract
   documented in docs/radix-port-analysis.md's "Password Toggle
   Field" entry (as adapted by prolog/ui/password_toggle_field.pl's
   own module-header deviations #1-#3), for:

     - default (hidden)   type="password", eye icon default-shown,
                           hidden label "Show password", Toggle
                           pre-hydration-inert (aria-hidden="true"
                           tabindex="-1")
     - visible(true)       type="text", data-visible="true", hidden
                           label "Hide password"
     - disabled             mirrored onto BOTH input and toggle
     - required + name/value/placeholder (form participation options)
     - id defaults (gensym) vs. caller-supplied (lands on the INPUT,
       not Root -- deviation #1's flip side)

   plus the convenience `password_toggle_field/1` wrapper, class
   merging, option pass-through, the individual parts called directly
   (password_toggle_field_input/1, _toggle/1, _icon/1), and the
   kitchen-sink demo registration (px_ui:demo/3) rendering end to end
   exactly as prolog/px_ui.pl's ui_show_view embeds it
   (`\password_toggle_field_demo` as a div's Children, not the bare
   atom -- adr/0019's arity-0 dispatch rule).
*/

:- use_module(library(pcre)).
:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/password_toggle_field.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Harness (test/ui/switch.pl's / test/ui/checkbox.pl's pattern).
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
    ->  format("~nAll ui/password_toggle_field checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Default (hidden): no visible(_) option at all.
    % ===================================================================

    render_to_string(password_toggle_field([id("s1")]), Hidden),

    check(hidden_wrapper_is_px_password_toggle_field,
          ( sub_string(Hidden, 0, _, _, "<px-password-toggle-field>"),
            sub_string(Hidden, _, _, 0, "</px-password-toggle-field>") )),
    check(hidden_root_div_class,
          contains(Hidden, "<div class=\"px-password-toggle-field\">")),
    check(hidden_input_type_password,
          contains(Hidden, "<input type=\"password\" id=\"s1\"")),
    check(hidden_input_autocomplete_default,
          contains(Hidden, "autocomplete=\"current-password\"")),
    check(hidden_input_autocapitalize_off,
          contains(Hidden, "autocapitalize=\"off\"")),
    check(hidden_input_spellcheck_false,
          contains(Hidden, "spellcheck=\"false\"")),
    check(hidden_input_class,
          contains(Hidden, "class=\"px-password-toggle-field-input\"")),
    check(hidden_toggle_type_button,
          contains(Hidden, "<button type=\"button\" aria-controls=\"s1\"")),
    check(hidden_toggle_pre_hydration_inert,
          ( contains(Hidden, "aria-hidden=\"true\""),
            contains(Hidden, "tabindex=\"-1\"") )),
    check(hidden_toggle_data_visible_false,
          contains(Hidden, "data-visible=\"false\"")),
    check(hidden_toggle_class,
          contains(Hidden, "class=\"px-password-toggle-field-toggle\"")),
    check(hidden_no_aria_pressed,
          not_contains(Hidden, "aria-pressed")),
    check(hidden_no_aria_label,
          not_contains(Hidden, "aria-label")),
    check(hidden_icon_wrapper_aria_hidden,
          contains(Hidden, "<span aria-hidden=\"true\">")),
    check(hidden_icon_show_span,
          contains(Hidden, "class=\"px-password-toggle-field-icon px-password-toggle-field-icon-show\"")),
    check(hidden_icon_hide_span,
          contains(Hidden, "class=\"px-password-toggle-field-icon px-password-toggle-field-icon-hide\"")),
    check(hidden_hidden_label_text,
          contains(Hidden, "<span class=\"px-visually-hidden\">Show password</span>")),

    % checked(false)-equivalent: visible(false) explicitly is the same
    % as omitting it.
    render_to_string(password_toggle_field([id("s1"), visible(false)]),
                      HiddenExplicit),
    check(hidden_explicit_same_as_default, HiddenExplicit == Hidden),

    % ===================================================================
    % Visible: visible(true), plus a real value.
    % ===================================================================

    render_to_string(password_toggle_field([id("s2"), visible(true),
                                             value("hunter2")]),
                      Visible),

    check(visible_input_type_text,
          contains(Visible, "<input type=\"text\" id=\"s2\"")),
    check(visible_input_value,
          contains(Visible, "value=\"hunter2\"")),
    check(visible_toggle_data_visible_true,
          contains(Visible, "data-visible=\"true\"")),
    check(visible_hidden_label_text,
          contains(Visible, "<span class=\"px-visually-hidden\">Hide password</span>")),
    check(visible_still_pre_hydration_inert,
          % Pre-hydration inertness is unconditional -- it does not
          % depend on the initial visible/hidden state, only on
          % whether client JS has upgraded the element yet.
          ( contains(Visible, "aria-hidden=\"true\""),
            contains(Visible, "tabindex=\"-1\"") )),

    % ===================================================================
    % Disabled: mirrored onto BOTH input and toggle (additive --
    % module header explains why).
    % ===================================================================

    render_to_string(password_toggle_field([id("s3"), disabled(true)]),
                      Disabled),

    check(disabled_input_attr,
          contains(Disabled, "<input type=\"password\" id=\"s3\" autocomplete=\"current-password\" autocapitalize=\"off\" spellcheck=\"false\" class=\"px-password-toggle-field-input\" disabled")),
    check(disabled_toggle_attr,
          contains(Disabled, "class=\"px-password-toggle-field-toggle\" disabled")),

    % ===================================================================
    % Required + name/value/placeholder: form-participation options,
    % all on the Input only (Toggle has no `required` concept).
    % ===================================================================

    render_to_string(password_toggle_field([id("s4"), name("password"),
                                             required(true),
                                             placeholder("Enter password"),
                                             value("secret")]),
                      Form),

    check(form_name, contains(Form, "name=\"password\"")),
    check(form_required, contains(Form, "required")),
    check(form_placeholder, contains(Form, "placeholder=\"Enter password\"")),
    check(form_value, contains(Form, "value=\"secret\"")),
    check(form_name_appears_once, count_occurrences(Form, "name=\"password\"", 1)),
    check(form_required_appears_once,
          % `required` shows up exactly once -- on the Input only; the
          % Toggle <button> has no `required`-shaped concept (module
          % header's own note).
          count_occurrences(Form, "required", 1)),

    % No name(_) given at all -- the input stays unnamed (does not
    % submit), same as a plain <input> with no name.
    render_to_string(password_toggle_field([]), NoName),
    check(no_name_by_default, not_contains(NoName, "name=")),

    % ===================================================================
    % id: caller-supplied lands on the INPUT (and is what aria-controls
    % references), NOT on Root -- deviation #1's flip side. Absent, a
    % fresh gensym'd id is used instead, still consistent between
    % Input and Toggle's aria-controls.
    % ===================================================================

    check(id_on_input_not_root,
          ( contains(Hidden, "<input type=\"password\" id=\"s1\""),
            not_contains(Hidden, "<div class=\"px-password-toggle-field\" id=") )),

    render_to_string(password_toggle_field([]), Gensym),
    check(gensym_id_used,
          contains(Gensym, "id=\"px_password_toggle_field_")),
    check(gensym_id_consistent_with_aria_controls,
          ( re_matchsub("id=\"(px_password_toggle_field_[0-9]+)\"", Gensym,
                         InputMatch, []),
            get_dict(1, InputMatch, IdValue),
            re_matchsub("aria-controls=\"(px_password_toggle_field_[0-9]+)\"",
                        Gensym, ControlsMatch, []),
            get_dict(1, ControlsMatch, IdValue) )),

    % ===================================================================
    % Options: class merging (Root only), fixed classes on Input/
    % Toggle/Icon spans are never overridden by a caller class(_).
    % ===================================================================

    render_to_string(password_toggle_field([id("s5"), class("wide")]),
                      WithOpts),
    check(class_merged_after_default,
          contains(WithOpts, "<div class=\"px-password-toggle-field wide\">")),
    check(input_keeps_fixed_class,
          contains(WithOpts, "class=\"px-password-toggle-field-input\"")),
    check(toggle_keeps_fixed_class,
          contains(WithOpts, "class=\"px-password-toggle-field-toggle\"")),

    % Arbitrary pass-through (data_*/aria_*) lands on Root, appended
    % after the computed attributes.
    render_to_string(password_toggle_field([id("s6"), data_testid("pwtf")]),
                      WithData),
    check(data_passthrough_on_root,
          contains(WithData, "<div class=\"px-password-toggle-field\" data-testid=\"pwtf\">")),

    % ===================================================================
    % Individual parts (password_toggle_field_input/1, _toggle/1,
    % _icon/1) can be called directly, same as switch_trigger/
    % switch_thumb, checkbox_input/checkbox_indicator.
    % ===================================================================

    render_to_string(password_toggle_field_input([visible(true)]), InputOnly),
    check(input_only_no_root_div, not_contains(InputOnly, "<div")),
    check(input_only_no_wrapper, not_contains(InputOnly, "px-password-toggle-field>")),
    check(input_only_type_text, contains(InputOnly, "type=\"text\"")),

    render_to_string(password_toggle_field_toggle([id("t1")]), ToggleOnly),
    check(toggle_only_no_root_div, not_contains(ToggleOnly, "<div")),
    check(toggle_only_aria_controls, contains(ToggleOnly, "aria-controls=\"t1\"")),

    render_to_string(password_toggle_field_icon([]), IconOnly),
    check(icon_only_has_both_glyphs,
          ( contains(IconOnly, "px-password-toggle-field-icon-show"),
            contains(IconOnly, "px-password-toggle-field-icon-hide") )),
    check(icon_only_svgs_present,
          ( contains(IconOnly, "<svg"),
            count_occurrences(IconOnly, "<svg", 2) )),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Call` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(password_toggle_field, _Order, \password_toggle_field_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(password_toggle_field, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \password_toggle_field_demo), Demo),
    check(demo_renders_all_states,
          ( contains(Demo, "data-visible=\"false\""),
            contains(Demo, "data-visible=\"true\""),
            contains(Demo, " disabled") )),
    check(demo_has_four_fields,
          count_occurrences(Demo, "<px-password-toggle-field>", 4)),
    check(demo_has_form,
          ( contains(Demo, "<form method=\"get\" action=\"/ui/password_toggle_field\">"),
            contains(Demo, "</form>") )),
    check(demo_form_field_required,
          contains(Demo, "required")),

    % show some real output for the record
    format("~n--- rendered password_toggle_field_demo ---~n~w~n--------------------------------------------~n",
           [Demo]).
