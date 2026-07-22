/* test/ui/slider.pl (adr/0026): render-test proof for
   prolog/ui/slider.pl -- the Slider port (single-thumb, NATIVE
   variant only; multi-thumb is deferred, see that module's header).
   A plain swipl script, no server, no networking (test/ui/switch.pl's
   / test/ui/progress.pl's pattern): render_to_string/2 over the
   templates and assert the exact DOM/data contract documented in
   prolog/ui/slider.pl's own module header (docs/radix-port-analysis.md's
   "Slider" entry, adapted to a native <input type=range>), for:

     - default value (midpoint of the implicit 0..100 range)
     - explicit value/min/max/step
     - disabled
     - vertical orientation (+ aria-orientation)
     - name (form participation) / aria_label pass-through
     - class merging, id/opt pass-through
     - individual parts callable directly (slider_root/slider_track/
       slider_range/slider_thumb)
     - the kitchen-sink demo registration (px_ui:demo/3) rendering end
       to end exactly as prolog/px_ui.pl's ui_show_view embeds it
       (`\slider_demo` as a div's Children, not the bare atom --
       adr/0019's arity-0 dispatch rule).
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/slider.pl').

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
    ->  format("~nAll ui/slider checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Default: no value/min/max/step/orientation given at all.
    % ===================================================================

    render_to_string(slider([id("sl1")]), Default),

    check(default_wrapper_is_px_slider,
          ( sub_string(Default, 0, _, _, "<px-slider>"),
            sub_string(Default, _, _, 0, "</px-slider>") )),
    check(default_root_class,
          contains(Default, "class=\"px-slider\"")),
    check(default_root_data_orientation,
          contains(Default, "data-orientation=\"horizontal\"")),
    check(default_root_slider_value_var,
          contains(Default, "--slider-value: 50.00;")),
    check(default_track_present,
          contains(Default, "class=\"px-slider-track\" data-orientation=\"horizontal\"")),
    check(default_range_present,
          contains(Default, "class=\"px-slider-range\" data-orientation=\"horizontal\"")),
    check(default_thumb_is_native_range_input,
          contains(Default, "<input type=\"range\" min=\"0\" max=\"100\" step=\"1\" value=\"50\"")),
    check(default_thumb_class,
          contains(Default, "class=\"px-slider-thumb\"")),
    check(default_no_aria_orientation,
          not_contains(Default, "aria-orientation")),
    check(default_no_role_or_aria_valuenow,
          ( not_contains(Default, "role=\"slider\""),
            not_contains(Default, "aria-valuenow"),
            not_contains(Default, "aria-valuemin"),
            not_contains(Default, "aria-valuemax") )),
    check(default_no_data_disabled,
          not_contains(Default, "data-disabled")),
    check(default_no_native_disabled,
          not_contains(Default, " disabled")),
    check(default_no_name,
          not_contains(Default, "name=")),
    check(default_exact,
          Default ==
              "<px-slider><div class=\"px-slider\" data-orientation=\"horizontal\" style=\"--slider-value: 50.00;\" id=\"sl1\"><div class=\"px-slider-track\" data-orientation=\"horizontal\"><div class=\"px-slider-range\" data-orientation=\"horizontal\"></div></div><input type=\"range\" min=\"0\" max=\"100\" step=\"1\" value=\"50\" data-orientation=\"horizontal\" class=\"px-slider-thumb\"></div></px-slider>"),

    % ===================================================================
    % Explicit value/min/max/step.
    % ===================================================================

    render_to_string(slider([id("sl2"), value(30), min(10), max(50), step(5)]),
                      Explicit),

    check(explicit_thumb_attrs,
          contains(Explicit, "<input type=\"range\" min=\"10\" max=\"50\" step=\"5\" value=\"30\"")),
    check(explicit_slider_value_var,
          % (30-10)/(50-10)*100 = 50.00
          contains(Explicit, "--slider-value: 50.00;")),

    % Out-of-range value clamps into [min,max].
    render_to_string(slider([id("sl2b"), value(999), min(0), max(10)]), Clamped),
    check(clamped_value_attr, contains(Clamped, "value=\"10\"")),
    check(clamped_slider_value_var, contains(Clamped, "--slider-value: 100.00;")),

    render_to_string(slider([id("sl2c"), value(-5), min(0), max(10)]), ClampedLow),
    check(clamped_low_value_attr, contains(ClampedLow, "value=\"0\"")),
    check(clamped_low_slider_value_var, contains(ClampedLow, "--slider-value: 0.00;")),

    % ===================================================================
    % Disabled: disabled(true) -- data-disabled="" mirrored on Root and
    % Thumb, plus the native `disabled` attribute (Track/Range do NOT
    % get their own data-disabled -- see the module header for why).
    % ===================================================================

    render_to_string(slider([id("sl3"), disabled(true)]), Disabled),

    check(disabled_data_disabled_count,
          % Root + Thumb only -- Track/Range are not mirrored.
          count_occurrences(Disabled, "data-disabled=\"\"", 2)),
    check(disabled_native_attr,
          contains(Disabled, "class=\"px-slider-thumb\" disabled")),
    check(disabled_track_has_no_data_disabled,
          not_contains(Disabled, "px-slider-track\" data-orientation=\"horizontal\" data-disabled")),

    % ===================================================================
    % Vertical orientation: data-orientation everywhere, PLUS
    % aria-orientation on the Thumb (the one explicit ARIA attribute
    % this port writes -- see the module header).
    % ===================================================================

    render_to_string(slider([id("sl4"), orientation(vertical), value(60)]),
                      Vertical),

    check(vertical_root_data_orientation,
          contains(Vertical, "<div class=\"px-slider\" data-orientation=\"vertical\"")),
    check(vertical_track_data_orientation,
          contains(Vertical, "class=\"px-slider-track\" data-orientation=\"vertical\"")),
    check(vertical_range_data_orientation,
          contains(Vertical, "class=\"px-slider-range\" data-orientation=\"vertical\"")),
    check(vertical_thumb_aria_orientation,
          contains(Vertical, "aria-orientation=\"vertical\"")),
    check(vertical_thumb_data_orientation,
          contains(Vertical, "data-orientation=\"vertical\" class=\"px-slider-thumb\"")),
    check(vertical_data_orientation_count,
          % Root, Track, Range, Thumb -- all four mirror data-orientation.
          count_occurrences(Vertical, "data-orientation=\"vertical\"", 4)),

    % Invalid orientation value falls back to the default (horizontal),
    % same guard shape as separator.pl's own orientation option.
    render_to_string(slider([id("sl4b"), orientation(diagonal)]), BadOrient),
    check(invalid_orientation_falls_back,
          contains(BadOrient, "data-orientation=\"horizontal\"")),

    % ===================================================================
    % Form participation: name(_) on the Thumb (native input) only.
    % ===================================================================

    render_to_string(slider([id("sl5"), name("volume"), value(70)]), Named),
    check(name_on_thumb,
          contains(Named, "class=\"px-slider-thumb\" name=\"volume\"")),
    check(name_appears_once,
          count_occurrences(Named, "name=\"volume\"", 1)),

    render_to_string(slider([id("sl5b")]), NoName),
    check(no_name_by_default, not_contains(NoName, "name=")),

    % ===================================================================
    % aria_label(_) pass-through -- routed to Thumb, not Root (the
    % analysis doc's own single-thumb "else omitted" default means
    % there is nothing auto-computed; a consumer opts in explicitly).
    % ===================================================================

    render_to_string(slider([id("sl6"), aria_label("Volume")]), AriaLabeled),
    check(aria_label_on_thumb,
          contains(AriaLabeled, "aria-label=\"Volume\"")),
    check(aria_label_not_on_root,
          % Root's own opening <div ...> tag (up to its first '>')
          % must not contain aria-label.
          ( sub_string(AriaLabeled, Before, Len, _, "<div class=\"px-slider\""),
            End is Before + Len,
            sub_string(AriaLabeled, End, _, 0, RootTagRest),
            sub_string(RootTagRest, B, 1, _, ">"),
            sub_string(RootTagRest, 0, B, _, RootOpenTag),
            \+ sub_string(RootOpenTag, _, _, _, "aria-label") )),

    % ===================================================================
    % Options: id/class pass-through (Root only), class merging.
    % ===================================================================

    render_to_string(slider([id("airplane-vol"), class("wide")]), WithOpts),
    check(id_passed_to_root,
          contains(WithOpts, "id=\"airplane-vol\"")),
    check(id_appears_once,
          count_occurrences(WithOpts, "id=\"airplane-vol\"", 1)),
    check(class_merged_after_default,
          contains(WithOpts, "class=\"px-slider wide\"")),
    check(track_keeps_fixed_class,
          contains(WithOpts, "class=\"px-slider-track\"")),
    check(range_keeps_fixed_class,
          contains(WithOpts, "class=\"px-slider-range\"")),
    check(thumb_keeps_fixed_class,
          contains(WithOpts, "class=\"px-slider-thumb\"")),

    % ===================================================================
    % Individual parts callable directly, same as switch.pl's/
    % progress.pl's part predicates.
    % ===================================================================

    render_to_string(slider_thumb([value(42)]), ThumbOnly),
    check(thumb_only_no_wrapper,
          ( not_contains(ThumbOnly, "px-slider>"),
            not_contains(ThumbOnly, "<div") )),
    check(thumb_only_value,
          contains(ThumbOnly, "value=\"42\"")),

    render_to_string(slider_track([], [slider_range([])]), TrackOnly),
    check(track_only_exact,
          TrackOnly ==
              "<div class=\"px-slider-track\" data-orientation=\"horizontal\"><div class=\"px-slider-range\" data-orientation=\"horizontal\"></div></div>"),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Call` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(slider, _Order, \slider_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(slider, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \slider_demo), Demo),
    check(demo_renders_all_states,
          ( contains(Demo, "data-orientation=\"horizontal\""),
            contains(Demo, "data-orientation=\"vertical\""),
            contains(Demo, "data-disabled=\"\"") )),
    check(demo_has_four_sliders,
          count_occurrences(Demo, "<px-slider>", 4)),

    % show some real output for the record
    format("~n--- rendered slider_demo ---~n~w~n----------------------------~n",
           [Demo]).
