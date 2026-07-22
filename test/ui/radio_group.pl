/* test/ui/radio_group.pl (adr/0026): render-test proof for
   prolog/ui/radio_group.pl -- the Radio Group port. A plain swipl
   script, no server, no networking (milestone10_templates.pl's /
   test/ui/progress.pl's / test/ui/toggle.pl's pattern): render_to_string/2
   over the templates and assert the exact ARIA/data contract documented
   in docs/radix-port-analysis.md's "Radio Group" entry, for the NATIVE-
   capable port:

     - Root:  role=radiogroup, aria-required (always true/false),
              aria-orientation (only when given), data-disabled (only
              when disabled(true))
     - Item:  native <input type="radio"> (implicit role=radio/
              aria-checked, none authored explicitly), wrapper <label>
              carrying data-state/data-disabled
     - the `name` grouping contract, threaded by the radio_group/2
       convenience (explicit or gensym default)
     - the kitchen-sink demo registration (px_ui:demo/3) rendering end
       to end exactly as prolog/px_ui.pl's ui_show_view embeds it
       (`\radio_group_demo` as a div's Children, not the bare atom --
       adr/0019's arity-0 dispatch rule).
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/radio_group.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Harness (test/ui/progress.pl's / test/ui/toggle.pl's pattern).
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

% All values of attribute Attr="..." found in Haystack, left to right --
% used to confirm several <input>s share the exact same `name`.
all_attr_values(Haystack, Attr, Values) :-
    format(string(Needle), "~w=\"", [Attr]),
    string_length(Needle, NLen),
    findall(Value,
            ( sub_string(Haystack, B, _, _, Needle),
              Start is B + NLen,
              sub_string(Haystack, Start, _, 0, Tail),
              once(sub_string(Tail, E, _, _, "\"")),
              sub_string(Tail, 0, E, _, Value)
            ),
            Values).

% True iff Goal throws error(existence_error(option, Key), _) -- and
% does NOT simply succeed or fail silently.
throws_missing_option(Goal, Key) :-
    catch((Goal, fail), error(existence_error(option, Key), _), true).

main :-
    tests,
    failed_count(N),
    (   N =:= 0
    ->  format("~nAll ui/radio_group checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Root: no options at all.
    % ===================================================================

    render_to_string(radio_group_root([], []), Empty),
    check(root_exact_no_opts,
          Empty ==
              "<div role=\"radiogroup\" aria-required=\"false\" class=\"px-radio-group\"></div>"),

    % ===================================================================
    % Root: required(true), orientation(horizontal), disabled(true),
    % id pass-through.
    % ===================================================================

    render_to_string(
        radio_group_root([required(true), orientation(horizontal),
                           disabled(true), id("prefs")], []),
        RootFull),

    check(root_role,
          contains(RootFull, "role=\"radiogroup\"")),
    check(root_aria_required_true,
          contains(RootFull, "aria-required=\"true\"")),
    check(root_aria_orientation,
          contains(RootFull, "aria-orientation=\"horizontal\"")),
    check(root_data_disabled_empty,
          contains(RootFull, "data-disabled=\"\"")),
    check(root_id_passthrough,
          contains(RootFull, "id=\"prefs\"")),
    check(root_full_exact,
          RootFull ==
              "<div role=\"radiogroup\" aria-required=\"true\" aria-orientation=\"horizontal\" class=\"px-radio-group\" data-disabled=\"\" id=\"prefs\"></div>"),

    % orientation absent -> no aria-orientation at all (mirrors Radix:
    % an undefined prop renders no attribute).
    check(root_no_orientation_by_default,
          not_contains(Empty, "aria-orientation")),

    % An invalid orientation value is silently dropped, same spirit as
    % ui/separator.pl's own orientation guard.
    render_to_string(radio_group_root([orientation(diagonal)], []),
                      RootBadOrientation),
    check(root_invalid_orientation_omitted,
          not_contains(RootBadOrientation, "aria-orientation")),

    % ===================================================================
    % Root: class merging.
    % ===================================================================

    render_to_string(radio_group_root([class("wide")], []), RootClass),
    check(root_class_merged,
          contains(RootClass, "class=\"px-radio-group wide\"")),

    % ===================================================================
    % Item: checked.
    % ===================================================================

    render_to_string(
        radio_group_item([name("g"), value("v1"), checked(true)],
                          "Label1"),
        Checked),

    check(checked_exact,
          Checked ==
              "<label class=\"px-radio-group-item\" data-state=\"checked\"><input type=\"radio\" name=\"g\" value=\"v1\" checked><span class=\"px-radio-group-label\">Label1</span></label>"),
    % No explicit role/aria-checked authored on the input -- the native
    % semantics already give role=radio/aria-checked (module header,
    % deviation 1); confirm neither string appears anywhere.
    check(checked_no_explicit_role,
          not_contains(Checked, "role=")),
    check(checked_no_explicit_aria_checked,
          not_contains(Checked, "aria-checked")),

    % ===================================================================
    % Item: unchecked (default) + disabled.
    % ===================================================================

    render_to_string(
        radio_group_item([name("g"), value("v2"), disabled(true)],
                          "Label2"),
        UncheckedDisabled),

    check(unchecked_disabled_exact,
          UncheckedDisabled ==
              "<label class=\"px-radio-group-item\" data-state=\"unchecked\" data-disabled=\"\"><input type=\"radio\" name=\"g\" value=\"v2\" disabled><span class=\"px-radio-group-label\">Label2</span></label>"),

    % ===================================================================
    % Item: plain unchecked, no disabled -- data-state default, no
    % data-disabled/native-disabled at all.
    % ===================================================================

    render_to_string(radio_group_item([name("g"), value("v3")], "Label3"),
                      Plain),
    check(plain_data_state_unchecked,
          contains(Plain, "data-state=\"unchecked\"")),
    check(plain_no_checked_attr,
          not_contains(Plain, "checked>")),
    check(plain_no_data_disabled,
          not_contains(Plain, "data-disabled")),
    check(plain_no_native_disabled,
          not_contains(Plain, "disabled>")),

    % ===================================================================
    % Item /1 (no children) -- empty label span.
    % ===================================================================

    render_to_string(radio_group_item([name("g"), value("v4")]), NoLabel),
    check(no_label_exact,
          NoLabel ==
              "<label class=\"px-radio-group-item\" data-state=\"unchecked\"><input type=\"radio\" name=\"g\" value=\"v4\"><span class=\"px-radio-group-label\"></span></label>"),

    % ===================================================================
    % Item: class merge, pass-through lands on the <input>, not the
    % wrapper.
    % ===================================================================

    render_to_string(
        radio_group_item([name("g"), value("v5"), class("hi"),
                           aria_describedby("hint")],
                          "Label5"),
        WithOpts),
    check(item_class_merged_on_wrapper,
          contains(WithOpts, "class=\"px-radio-group-item hi\"")),
    check(item_passthrough_on_input,
          ( sub_string(WithOpts, B, _, _, "aria-describedby=\"hint\""),
            sub_string(WithOpts, IB, _, _, "<input"),
            IB < B )),

    % ===================================================================
    % Item: value(_) and name(_) are required -- calling without either
    % throws a clear existence_error rather than silently emitting a
    % broken/ungrouped radio.
    % ===================================================================

    check(missing_value_throws,
          throws_missing_option(
              render_to_string(radio_group_item([name("g")], "X"), _),
              value)),
    check(missing_name_throws,
          throws_missing_option(
              render_to_string(radio_group_item([value("v")], "X"), _),
              name)),

    % ===================================================================
    % Convenience `radio_group/2`: explicit name threaded onto every
    % Item that doesn't set its own.
    % ===================================================================

    render_to_string(
        radio_group([id("sizes"), name("size")],
          [ radio_group_item([value("s"), checked(true)], "Small"),
            radio_group_item([value("m")], "Medium")
          ]),
        Sizes),

    check(sizes_root_role,
          contains(Sizes, "role=\"radiogroup\"")),
    check(sizes_root_id,
          contains(Sizes, "id=\"sizes\"")),
    check(sizes_no_name_on_root_div,
          % the div itself must not carry a name="..." attribute --
          % only the two <input>s should.
          ( all_attr_values(Sizes, "name", Names),
            length(Names, 2) )),
    check(sizes_both_inputs_share_name,
          ( all_attr_values(Sizes, "name", ["size", "size"]) )),
    check(sizes_two_radio_inputs,
          count_occurrences(Sizes, "type=\"radio\"", 2)),
    check(sizes_one_checked,
          count_occurrences(Sizes, "checked>", 1)),

    % An Item that already sets its own name(_) keeps it (explicit wins
    % over the group default).
    render_to_string(
        radio_group([name("group-a")],
          [ radio_group_item([value("x"), name("group-b")], "X"),
            radio_group_item([value("y")], "Y")
          ]),
        MixedNames),
    check(explicit_item_name_wins,
          ( all_attr_values(MixedNames, "name", ["group-b", "group-a"]) )),

    % ===================================================================
    % Convenience `radio_group/2`: name(_) omitted entirely -- a fresh
    % gensym default is generated and shared by every Item.
    % ===================================================================

    render_to_string(
        radio_group([],
          [ radio_group_item([value("a")], "A"),
            radio_group_item([value("b")], "B"),
            radio_group_item([value("c")], "C")
          ]),
        Gensym),
    check(gensym_three_inputs_same_name,
          ( all_attr_values(Gensym, "name", [N, N, N]),
            string(N),
            sub_string(N, 0, _, _, "px-radio-group-") )),

    % ===================================================================
    % Root-level disabled(true) dims the group container but does NOT
    % auto-propagate to Items (documented deviation from Radix's
    % context-based inheritance -- module header).
    % ===================================================================

    render_to_string(
        radio_group([name("d"), disabled(true)],
          [radio_group_item([value("only")], "Only")]),
        RootDisabled),
    check(root_disabled_attr_present,
          contains(RootDisabled, "data-disabled=\"\"")),
    check(item_not_auto_disabled,
          not_contains(RootDisabled, "disabled>")),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Call` as a div's sole
    % Children argument. Three options, one checked, one disabled.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(radio_group, _Order, \radio_group_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(radio_group, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \radio_group_demo), Demo),

    check(demo_one_radiogroup,
          count_occurrences(Demo, "role=\"radiogroup\"", 1)),
    check(demo_three_radio_inputs,
          count_occurrences(Demo, "type=\"radio\"", 3)),
    check(demo_all_inputs_share_name,
          ( all_attr_values(Demo, "name", [N1, N2, N3]),
            N1 == N2, N2 == N3 )),
    check(demo_one_checked,
          count_occurrences(Demo, "checked>", 1)),
    check(demo_one_disabled_item,
          count_occurrences(Demo, "disabled>", 1)),
    check(demo_required_true,
          contains(Demo, "aria-required=\"true\"")),
    check(demo_labels,
          ( contains(Demo, "Default"),
            contains(Demo, "Comfortable"),
            contains(Demo, "Compact (disabled)") )),

    % show some real output for the record
    format("~n--- rendered radio_group_demo ---~n~w~n----------------------------------~n",
           [Demo]).
