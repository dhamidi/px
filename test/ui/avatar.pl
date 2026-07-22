/* test/ui/avatar.pl (adr/0026): render-test proof for prolog/ui/avatar.pl
   -- the Avatar port. A plain swipl script, no server, no networking
   (test/ui/progress.pl's pattern): render_to_string/2 over the
   templates and assert the exact contract documented in
   prolog/ui/avatar.pl's module header / docs/radix-port-analysis.md's
   "Avatar" entry:

     - no role/aria-* anywhere (upstream ships none)
     - Root is a <px-avatar> custom element (not a whitelisted HTML5
       element -- rendered via px_template:render_tag/4), carrying
       data-state="loading|loaded|error" (this port's own addition,
       sanctioned by the analysis doc's "Interactivity class" section,
       NOT a literal Radix attribute)
     - Image is a void <img>, Fallback a <span>, both always rendered
     - class merge (default-first, additive) on all three parts
     - delay_ms(N) -> data-delay-ms="N" on Fallback only, when N is a
       non-negative integer; omitted (and never leaked as a raw
       attribute) otherwise
     - avatar/4's DOM order is Fallback THEN Image (deliberate deviation
       from the anatomy listing order, documented in the module header)
     - the kitchen-sink demo (px_ui:demo/3) registration and its four
       scenarios: working image, broken src, broken src + delay_ms,
       fallback-only (no avatar_image/1 at all)

   Run:  swipl test/ui/avatar.pl
*/

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../../prolog/px_template'], TemplateSpec),
   atomic_list_concat([Dir, '/../../prolog/px_ui'],       PxUiSpec),
   use_module(TemplateSpec),
   use_module(PxUiSpec).

:- initialization(main, main).

                 /*******************************
                 *            HARNESS           *
                 *******************************/

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

% True iff Needle1 occurs strictly before Needle2 in Haystack.
before(Haystack, Needle1, Needle2) :-
    sub_string(Haystack, B1, _, _, Needle1),
    sub_string(Haystack, B2, _, _, Needle2),
    B1 < B2.

main :-
    tests,
    failed_count(N),
    (   N =:= 0
    ->  format("~nAll ui/avatar checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % avatar_root/1,2 -- Root, the <px-avatar> custom element.
    % ===================================================================

    render_to_string(avatar_root([], "x"), Root0),
    check(root_is_px_avatar_tag,
          contains(Root0, "<px-avatar ")),
    check(root_closes_px_avatar_tag,
          contains(Root0, "</px-avatar>")),
    check(root_default_class,
          contains(Root0, "class=\"px-avatar\"")),
    check(root_default_state_loading,
          contains(Root0, "data-state=\"loading\"")),
    check(root_no_role,
          not_contains(Root0, "role=")),
    check(root_no_aria,
          not_contains(Root0, "aria-")),
    check(root_renders_children,
          contains(Root0, ">x</px-avatar>")),
    check(root_exact,
          Root0 == "<px-avatar class=\"px-avatar\" data-state=\"loading\">x</px-avatar>"),

    % avatar_root/1 (no Children arg) == avatar_root/2 with [].
    render_to_string(avatar_root([]), Root1a),
    render_to_string(avatar_root([], []), Root1b),
    check(root_arity1_equals_arity2_empty, Root1a == Root1b),

    % state(loaded) / state(error) override the default.
    render_to_string(avatar_root([state(loaded)], []), RootLoaded),
    check(root_state_loaded,
          contains(RootLoaded, "data-state=\"loaded\"")),
    render_to_string(avatar_root([state(error)], []), RootError),
    check(root_state_error,
          contains(RootError, "data-state=\"error\"")),

    % An invalid state(_) value falls back to the "loading" default.
    render_to_string(avatar_root([state(bogus)], []), RootBogus),
    check(root_invalid_state_falls_back,
          contains(RootBogus, "data-state=\"loading\"")),

    % class(...) merges additively (default first), id(...)/other opts
    % pass straight through, exactly once.
    render_to_string(avatar_root([class("ring"), id("root-1")], []), RootOpts),
    check(root_class_merged,
          contains(RootOpts, "class=\"px-avatar ring\"")),
    check(root_id_passthrough,
          contains(RootOpts, "id=\"root-1\"")),
    check(root_id_appears_once,
          ( count_occurrences(RootOpts, "id=\"root-1\"", 1) )),

    % ===================================================================
    % avatar_image/1 -- Image, a void <img>.
    % ===================================================================

    render_to_string(avatar_image([src("/pic.png"), alt("A portrait")]), Image0),
    check(image_exact,
          Image0 == "<img class=\"px-avatar-image\" src=\"/pic.png\" alt=\"A portrait\">"),
    check(image_no_closing_tag,
          not_contains(Image0, "</img>")),
    check(image_no_role_or_aria,
          ( not_contains(Image0, "role="), not_contains(Image0, "aria-") )),

    render_to_string(avatar_image([class("square"), src("/x.png")]), ImageClass),
    check(image_class_merged,
          contains(ImageClass, "class=\"px-avatar-image square\"")),

    % ===================================================================
    % avatar_fallback/1,2 -- Fallback, a <span>.
    % ===================================================================

    render_to_string(avatar_fallback([], "AB"), Fallback0),
    check(fallback_exact,
          Fallback0 == "<span class=\"px-avatar-fallback\">AB</span>"),

    render_to_string(avatar_fallback([]), Fallback1),
    check(fallback_arity1_no_children,
          Fallback1 == "<span class=\"px-avatar-fallback\"></span>"),

    % delay_ms(N), N a non-negative integer -> data-delay-ms="N".
    render_to_string(avatar_fallback([delay_ms(600)], "AB"), FallbackDelay),
    check(fallback_delay_ms,
          contains(FallbackDelay, "data-delay-ms=\"600\"")),
    check(fallback_delay_ms_no_raw_underscore_attr,
          not_contains(FallbackDelay, "delay_ms=")),

    render_to_string(avatar_fallback([delay_ms(0)], "AB"), FallbackDelayZero),
    check(fallback_delay_ms_zero_allowed,
          contains(FallbackDelayZero, "data-delay-ms=\"0\"")),

    % Invalid delay_ms(_) (negative, or non-integer) is dropped
    % entirely -- never leaked as a raw `delay_ms` attribute either.
    render_to_string(avatar_fallback([delay_ms(-5)], "AB"), FallbackDelayNeg),
    check(fallback_delay_ms_negative_dropped,
          ( not_contains(FallbackDelayNeg, "data-delay-ms"),
            not_contains(FallbackDelayNeg, "delay_ms"),
            not_contains(FallbackDelayNeg, "delay-ms=\"-5\"") )),

    render_to_string(avatar_fallback([delay_ms(soon)], "AB"), FallbackDelayBad),
    check(fallback_delay_ms_non_integer_dropped,
          not_contains(FallbackDelayBad, "data-delay-ms")),

    % class(...) merges additively.
    render_to_string(avatar_fallback([class("initials")], "AB"), FallbackClass),
    check(fallback_class_merged,
          contains(FallbackClass, "class=\"px-avatar-fallback initials\"")),

    % ===================================================================
    % avatar/4 -- the rule-1 top-level convenience: Root wraps Fallback
    % THEN Image, in that DOM order (module header's documented
    % deviation from the anatomy listing order).
    % ===================================================================

    render_to_string(
        avatar([id("av-1")], [src("/pic.png"), alt("A")], [], "AB"),
        Combo),
    check(combo_one_root,
          count_occurrences(Combo, "<px-avatar ", 1)),
    check(combo_has_image,
          contains(Combo, "<img class=\"px-avatar-image\" src=\"/pic.png\" alt=\"A\">")),
    check(combo_has_fallback,
          contains(Combo, "<span class=\"px-avatar-fallback\">AB</span>")),
    check(combo_fallback_before_image,
          before(Combo, "px-avatar-fallback", "px-avatar-image")),
    check(combo_id_on_root_only,
          ( count_occurrences(Combo, "id=\"av-1\"", 1) )),

    % FallbackOpts (e.g. delay_ms) land on Fallback, never on Image/Root.
    render_to_string(
        avatar([], [src("/pic.png")], [delay_ms(300)], "CD"),
        ComboDelay),
    check(combo_delay_on_fallback_only,
          ( contains(ComboDelay, "data-delay-ms=\"300\""),
            count_occurrences(ComboDelay, "data-delay-ms", 1) )),

    % ===================================================================
    % Fallback-only composition (no avatar_image/1 at all) -- manual
    % avatar_root/2 + avatar_fallback/2, not the avatar/4 convenience.
    % ===================================================================

    render_to_string(
        avatar_root([id("fb-only")], avatar_fallback([], "FB")),
        FallbackOnly),
    check(fallback_only_no_image,
          not_contains(FallbackOnly, "<img")),
    check(fallback_only_has_fallback,
          contains(FallbackOnly, "<span class=\"px-avatar-fallback\">FB</span>")),
    check(fallback_only_exact,
          FallbackOnly ==
              "<px-avatar class=\"px-avatar\" data-state=\"loading\" id=\"fb-only\"><span class=\"px-avatar-fallback\">FB</span></px-avatar>"),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Call` as a div's sole
    % Children argument (adr/0019's arity-0 dispatch rule).
    % ===================================================================

    check(demo_registered,
          px_ui:demo(avatar, _Order, \avatar_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(avatar, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \avatar_demo), Demo),

    check(demo_has_four_avatars,
          count_occurrences(Demo, "<px-avatar ", 4)),
    check(demo_working_image_src,
          contains(Demo, "data:image/png;base64,")),
    check(demo_broken_src,
          contains(Demo, "/assets/does-not-exist.png")),
    check(demo_delay_ms,
          contains(Demo, "data-delay-ms=\"600\"")),
    check(demo_fallback_only_no_image_in_its_row,
          ( sub_string(Demo, B, _, _, "avatar-demo-fallback-only"),
            sub_string(Demo, B, _, 0, After),
            not_contains(After, "<img") )),
    check(demo_labels,
          ( contains(Demo, "Working image"),
            contains(Demo, "Broken src"),
            contains(Demo, "Fallback-only") )),

    % show some real output for the record
    format("~n--- rendered avatar_demo ---~n~w~n----------------------------~n",
           [Demo]).
