/* test/ui/progress.pl (adr/0026): render-test proof for
   prolog/ui/progress.pl -- the Progress port. A plain swipl script, no
   server, no networking (milestone10_templates.pl's pattern):
   render_to_string/2 over the templates and assert the exact ARIA/
   data contract documented in docs/radix-port-analysis.md's
   "Progress" entry, for all three states:

     - determinate/loading   (value 30 of max 100)
     - determinate/complete  (value 100 of max 100)
     - indeterminate         (value absent)

   plus the convenience `progress/1` wrapper, class merging, and the
   kitchen-sink demo registration (px_ui:demo/3) rendering end to end
   exactly as prolog/px_ui.pl's ui_show_view embeds it (`\progress_demo`
   as a div's Children, not the bare atom -- adr/0019's arity-0
   dispatch rule).
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/progress.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Harness (milestone10_templates.pl's pattern).
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

% True if nothing between the end of the first match of Needle in
% Haystack and the end of the string contains Excluded -- used to
% confirm the Indicator (found via a unique class-name landmark)
% carries no role/aria-* attributes of its own.
after_needle(Haystack, Needle, After) :-
    sub_string(Haystack, B, L, _, Needle),
    !,
    Pos is B + L,
    sub_string(Haystack, Pos, _, 0, After).

main :-
    tests,
    failed_count(N),
    (   N =:= 0
    ->  format("~nAll ui/progress checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Determinate / loading: value(30), max(100).
    % ===================================================================

    render_to_string(progress_root([value(30), max(100)],
                                    progress_indicator([value(30), max(100)])),
                      Loading),

    check(loading_role_progressbar,
          contains(Loading, "role=\"progressbar\"")),
    check(loading_aria_valuemax,
          contains(Loading, "aria-valuemax=\"100\"")),
    check(loading_aria_valuemin,
          contains(Loading, "aria-valuemin=\"0\"")),
    check(loading_aria_valuenow,
          contains(Loading, "aria-valuenow=\"30\"")),
    check(loading_aria_valuetext,
          contains(Loading, "aria-valuetext=\"30%\"")),
    check(loading_data_state,
          contains(Loading, "data-state=\"loading\"")),
    check(loading_root_data_value,
          contains(Loading, "data-value=\"30\"")),
    check(loading_root_data_max,
          contains(Loading, "data-max=\"100\"")),
    check(loading_root_default_class,
          contains(Loading, "class=\"px-progress\"")),

    % Indicator mirrors the data-state/data-value/data-max triplet,
    % carries no role/aria-* of its own, and its width is the inline
    % style computed server-side from value/max.
    check(loading_indicator_present,
          contains(Loading, "<div data-state=\"loading\" class=\"px-progress-indicator\" data-value=\"30\" data-max=\"100\" style=\"width: 30%;\"></div>")),
    check(loading_indicator_no_role,
          ( after_needle(Loading, "px-progress-indicator", After),
            not_contains(After, "role=") )),

    % ===================================================================
    % Determinate / complete: value(100), max(100).
    % ===================================================================

    render_to_string(progress([value(100), max(100)]), Complete),

    check(complete_data_state,
          contains(Complete, "data-state=\"complete\"")),
    check(complete_aria_valuenow,
          contains(Complete, "aria-valuenow=\"100\"")),
    check(complete_aria_valuetext,
          contains(Complete, "aria-valuetext=\"100%\"")),
    check(complete_root_data_value,
          contains(Complete, "data-value=\"100\"")),
    check(complete_indicator_full_width,
          contains(Complete, "style=\"width: 100%;\"")),
    % convenience wrapper nests exactly Root > Indicator, one of each
    check(complete_one_root,
          count_occurrences(Complete, "role=\"progressbar\"", 1)),

    % ===================================================================
    % Indeterminate: no value(_) at all.
    % ===================================================================

    render_to_string(progress([]), Indeterminate),

    check(indeterminate_data_state,
          contains(Indeterminate, "data-state=\"indeterminate\"")),
    check(indeterminate_default_max,
          contains(Indeterminate, "aria-valuemax=\"100\"")),
    check(indeterminate_data_max,
          contains(Indeterminate, "data-max=\"100\"")),
    check(indeterminate_no_aria_valuenow,
          not_contains(Indeterminate, "aria-valuenow")),
    check(indeterminate_no_aria_valuetext,
          not_contains(Indeterminate, "aria-valuetext")),
    check(indeterminate_no_data_value,
          not_contains(Indeterminate, "data-value")),
    check(indeterminate_indicator_no_style,
          not_contains(Indeterminate, "style=")),
    check(indeterminate_exact,
          Indeterminate ==
              "<div role=\"progressbar\" aria-valuemax=\"100\" aria-valuemin=\"0\" data-state=\"indeterminate\" class=\"px-progress\" data-max=\"100\"><div data-state=\"indeterminate\" class=\"px-progress-indicator\" data-max=\"100\"></div></div>"),

    % An out-of-range value degrades to indeterminate too (Radix's
    % isValidValueNumber guard), same contract as no value at all.
    render_to_string(progress([value(150), max(100)]), OutOfRange),
    check(out_of_range_value_is_indeterminate,
          contains(OutOfRange, "data-state=\"indeterminate\"")),
    check(out_of_range_no_data_value,
          not_contains(OutOfRange, "data-value")),

    % ===================================================================
    % Options: id/class pass-through, class merging, indicator does not
    % inherit Root's id (adr/0026's "trivially replaced by passing the
    % same values to both part templates" -- value/max only).
    % ===================================================================

    render_to_string(progress([value(30), max(100), id("bar"),
                                class("wide")]),
                      WithOpts),
    check(id_passed_to_root,
          contains(WithOpts, "id=\"bar\"")),
    check(id_not_duplicated_on_indicator,
          ( findall(1, sub_string(WithOpts, _, _, _, "id=\"bar\""), Ids),
            length(Ids, 1) )),
    check(class_merged_after_default,
          contains(WithOpts, "class=\"px-progress wide\"")),
    check(indicator_keeps_default_class,
          contains(WithOpts, "class=\"px-progress-indicator\"")),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Call` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(progress, _Order, \progress_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(progress, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \progress_demo), Demo),
    check(demo_renders_all_three_states,
          ( contains(Demo, "data-state=\"loading\""),
            contains(Demo, "data-state=\"complete\""),
            contains(Demo, "data-state=\"indeterminate\"") )),
    check(demo_has_three_progressbars,
          count_occurrences(Demo, "role=\"progressbar\"", 3)),
    check(demo_labels,
          ( contains(Demo, "30%"),
            contains(Demo, "100% (complete)"),
            contains(Demo, "indeterminate (no value)") )),

    % show some real output for the record
    format("~n--- rendered progress_demo ---~n~w~n------------------------------~n",
           [Demo]).
