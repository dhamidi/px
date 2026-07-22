/* test/ui/toast.pl (adr/0026): render-test proof for prolog/ui/toast.pl
   -- the Toast port. A plain swipl script, no server, no networking
   (test/ui/dialog.pl's pattern): render_to_string/2 over the templates
   and assert the exact ARIA/data contract documented in
   docs/radix-port-analysis.md's "Toast" entry and prolog/ui/toast.pl's
   own module header, for:

     - toast_viewport/2   role="region", aria-live="polite",
                          aria-label="{label} (F8)", tabindex="-1",
                          default well-known id "toast_viewport", class
                          merge
     - toast_root/2       <li>, role="status" (always -- never "alert",
                          matching the analysis doc), tabindex="0",
                          data-state, data-swipe-direction (static
                          default "right"), data-type (default
                          "foreground", no aria-live effect -- see
                          module header deviation 2), data-duration
                          (default 5000), gensym'd id when omitted
     - toast_title/2      <div>, id/class pass-through
     - toast_description/2  <div>, id/class pass-through
     - toast_action/2     <button data-alt-text>, alt_text/1 REQUIRED
                          (existence_error when absent)
     - toast_close/2      <button data-toast-close>, always marked
     - toast/2            optional title/description/action, default
                          accessible Close, close(none) suppression,
                          action(AltText-Kids) pair wiring, open/
                          duration/type/swipe_direction forwarding
     - the kitchen-sink demo registration (px_ui:demo/3) rendering end
       to end exactly as prolog/px_ui.pl's ui_show_view embeds it
       (`\Goal` as a div's Children, adr/0019's arity-0 dispatch rule)
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/toast.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Harness (test/ui/dialog.pl's pattern).
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

check_throws(Name, Goal, ExpectedError) :-
    (   catch(( Goal, Outcome = no_throw ), E, Outcome = threw(E))
    ->  (   Outcome = threw(ExpectedError)
        ->  format("PASS  ~w~n", [Name])
        ;   format("FAIL  ~w (got ~q)~n", [Name, Outcome]),
            bump
        )
    ;   format("FAIL  ~w (goal failed outright)~n", [Name]),
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
    ->  format("~nAll ui/toast checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Viewport: role=region, aria-live=polite, aria-label="{label} (F8)",
    % tabindex=-1, default well-known id, class merge.
    % ===================================================================

    render_to_string(toast_viewport([], "Body"), ViewportDefault),
    check(viewport_is_ol_tag,
          ( sub_string(ViewportDefault, _, 3, _, "<ol"),
            sub_string(ViewportDefault, _, _, _, "</ol>") )),
    check(viewport_default_id,
          contains(ViewportDefault, "id=\"toast_viewport\"")),
    check(viewport_role_region,
          contains(ViewportDefault, "role=\"region\"")),
    check(viewport_aria_live_polite,
          contains(ViewportDefault, "aria-live=\"polite\"")),
    check(viewport_aria_label_hotkey,
          contains(ViewportDefault, "aria-label=\"Notifications (F8)\"")),
    check(viewport_tabindex,
          contains(ViewportDefault, "tabindex=\"-1\"")),
    check(viewport_default_class,
          contains(ViewportDefault, "class=\"px-toast-viewport\"")),
    check(viewport_wraps_px_toast_viewport,
          ( sub_string(ViewportDefault, 0, _, _, "<px-toast-viewport>"),
            sub_string(ViewportDefault, _, _, 0, "</px-toast-viewport>") )),

    render_to_string(
        toast_viewport([id("custom-vp"), label("Alerts"), class("wide")], "Body"),
        ViewportOpts),
    check(viewport_custom_id,
          contains(ViewportOpts, "id=\"custom-vp\"")),
    check(viewport_custom_label,
          contains(ViewportOpts, "aria-label=\"Alerts (F8)\"")),
    check(viewport_class_merged,
          contains(ViewportOpts, "class=\"px-toast-viewport wide\"")),

    % ===================================================================
    % Root: <li>, role=status (always), tabindex=0, data-state,
    % data-swipe-direction, data-type, data-duration, gensym'd id.
    % ===================================================================

    render_to_string(toast_root([], "Body"), RootDefault),
    check(root_is_li_tag,
          ( sub_string(RootDefault, _, 3, _, "<li"),
            sub_string(RootDefault, _, _, _, "</li>") )),
    check(root_role_status,
          contains(RootDefault, "role=\"status\"")),
    check(root_never_role_alert,
          not_contains(RootDefault, "role=\"alert\"")),
    check(root_tabindex_zero,
          contains(RootDefault, "tabindex=\"0\"")),
    check(root_default_open,
          contains(RootDefault, "data-state=\"open\"")),
    check(root_default_swipe_direction,
          contains(RootDefault, "data-swipe-direction=\"right\"")),
    check(root_default_type,
          contains(RootDefault, "data-type=\"foreground\"")),
    check(root_default_duration,
          contains(RootDefault, "data-duration=\"5000\"")),
    check(root_default_class,
          contains(RootDefault, "class=\"px-toast\"")),
    check(root_gensym_id,
          contains(RootDefault, "id=\"px-toast-")),
    check(root_wraps_px_toast,
          ( sub_string(RootDefault, 0, _, _, "<px-toast>"),
            sub_string(RootDefault, _, _, 0, "</px-toast>") )),

    render_to_string(
        toast_root([id("t1"), open(false), duration(0), type(background),
                    swipe_direction(left), class("wide")], "Body"),
        RootOpts),
    check(root_custom_id,
          contains(RootOpts, "id=\"t1\"")),
    check(root_closed_state,
          contains(RootOpts, "data-state=\"closed\"")),
    check(root_duration_zero,
          contains(RootOpts, "data-duration=\"0\"")),
    check(root_type_background,
          contains(RootOpts, "data-type=\"background\"")),
    check(root_swipe_left,
          contains(RootOpts, "data-swipe-direction=\"left\"")),
    check(root_class_merged,
          contains(RootOpts, "class=\"px-toast wide\"")),

    % Invalid type/swipe_direction values raise a domain_error.
    check_throws(root_invalid_type_throws,
                 render_to_string(toast_root([type(bogus)], "x"), _),
                 error(domain_error(toast_type, bogus), _)),
    check_throws(root_invalid_swipe_direction_throws,
                 render_to_string(toast_root([swipe_direction(bogus)], "x"), _),
                 error(domain_error(toast_swipe_direction, bogus), _)),

    % ===================================================================
    % Title / Description: <div>, id/class pass-through.
    % ===================================================================

    render_to_string(toast_title([id("ti1")], "Saved"), Title),
    check(title_is_div_tag,
          ( sub_string(Title, 0, 4, _, "<div"),
            sub_string(Title, _, _, 0, "</div>") )),
    check(title_id, contains(Title, "id=\"ti1\"")),
    check(title_default_class, contains(Title, "class=\"px-toast-title\"")),
    check(title_text, contains(Title, "Saved")),

    render_to_string(toast_description([id("d1")], "Your changes were saved."), Description),
    check(description_is_div_tag,
          ( sub_string(Description, 0, 4, _, "<div"),
            sub_string(Description, _, _, 0, "</div>") )),
    check(description_id, contains(Description, "id=\"d1\"")),
    check(description_default_class,
          contains(Description, "class=\"px-toast-description\"")),

    % ===================================================================
    % Action: <button data-alt-text>, alt_text/1 REQUIRED.
    % ===================================================================

    render_to_string(toast_action([alt_text("Undo the change")], "Undo"), Action),
    check(action_is_button_tag,
          ( sub_string(Action, 0, 7, _, "<button"),
            sub_string(Action, _, _, 0, "</button>") )),
    check(action_alt_text,
          contains(Action, "data-alt-text=\"Undo the change\"")),
    check(action_default_class,
          contains(Action, "class=\"px-toast-action\"")),
    check(action_text, contains(Action, "Undo")),

    check_throws(action_missing_alt_text_throws,
                 render_to_string(toast_action([], "Undo"), _),
                 error(existence_error(option, alt_text), _)),

    % ===================================================================
    % Close: <button data-toast-close>, always marked, class merge.
    % ===================================================================

    render_to_string(toast_close([], "Dismiss"), Close),
    check(close_is_button_tag,
          ( sub_string(Close, 0, 7, _, "<button"),
            sub_string(Close, _, _, 0, "</button>") )),
    check(close_marker_always_present,
          contains(Close, "data-toast-close=\"\"")),
    check(close_default_class,
          contains(Close, "class=\"px-toast-close\"")),

    % ===================================================================
    % Convenience toast/2: optional title/description/action, default
    % accessible Close, close(none) suppression, action(AltText-Kids)
    % wiring, open/duration/type/swipe_direction forwarding.
    % ===================================================================

    render_to_string(
        toast([id("tst1"), title("Saved"), description("Your changes were saved."),
               action("Undo the change" - "Undo")],
              []),
        Full),
    check(full_wraps_px_toast,
          ( sub_string(Full, 0, _, _, "<px-toast>"),
            sub_string(Full, _, _, 0, "</px-toast>") )),
    check(full_id, contains(Full, "id=\"tst1\"")),
    check(full_title_present,
          contains(Full, "class=\"px-toast-title\">Saved</div>")),
    check(full_description_present,
          contains(Full, "Your changes were saved.")),
    check(full_action_present,
          contains(Full, "data-alt-text=\"Undo the change\"")),
    check(full_action_text, contains(Full, ">Undo</button>")),
    check(full_default_close_present,
          contains(Full, "data-toast-close=\"\"")),
    check(full_default_close_accessible_name,
          contains(Full, "px-visually-hidden")),
    check(full_default_open,
          contains(Full, "data-state=\"open\"")),

    % No title/description/action supplied: none of the three render.
    render_to_string(toast([id("tst2")], ["Just body"]), NoParts),
    check(no_parts_no_title,
          not_contains(NoParts, "px-toast-title")),
    check(no_parts_no_description,
          not_contains(NoParts, "px-toast-description")),
    check(no_parts_no_action,
          not_contains(NoParts, "px-toast-action")),
    check(no_parts_close_still_default,
          contains(NoParts, "data-toast-close")),
    check(no_parts_body_present,
          contains(NoParts, "Just body")),

    % close(none) suppresses the Close button entirely.
    render_to_string(toast([id("tst3"), close(none)], ["Body"]), NoClose),
    check(no_close_suppressed,
          not_contains(NoClose, "data-toast-close")),

    % close(Kids) overrides the default content.
    render_to_string(toast([id("tst4"), close("X")], ["Body"]), CustomClose),
    check(custom_close_text,
          contains(CustomClose, "data-toast-close=\"\" class=\"px-toast-close\">X</button>")),

    % open(false)/duration/type/swipe_direction all forward straight to
    % toast_root/2.
    render_to_string(
        toast([id("tst5"), open(false), duration(0), type(background),
               swipe_direction(up)],
              ["Body"]),
        Forwarded),
    check(forwarded_closed, contains(Forwarded, "data-state=\"closed\"")),
    check(forwarded_duration_zero, contains(Forwarded, "data-duration=\"0\"")),
    check(forwarded_type, contains(Forwarded, "data-type=\"background\"")),
    check(forwarded_swipe, contains(Forwarded, "data-swipe-direction=\"up\"")),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(toast, _Order, \toast_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(toast, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \toast_demo), Demo),
    check(demo_has_viewport,
          contains(Demo, "<px-toast-viewport>")),
    % 2 server-rendered baseline toasts plus 1 inert copy inside the
    % client-side-trigger <template> (never itself part of the live
    % DOM until cloned) -- 3 total.
    check(demo_has_toasts,
          count_occurrences(Demo, "<px-toast>", 3)),
    check(demo_has_action,
          contains(Demo, "px-toast-action")),
    check(demo_has_close,
          contains(Demo, "data-toast-close")),
    check(demo_has_trigger_button,
          contains(Demo, "px-toast-demo-trigger")),
    check(demo_has_template,
          ( sub_string(Demo, _, _, _, "<template id=\"toast-demo-template\">"),
            sub_string(Demo, _, _, _, "</template>") )),
    check(demo_has_inline_script,
          contains(Demo, "toast-demo-template")),
    check(demo_has_turbo_stream_snippet,
          contains(Demo, "turbo_stream(Env0,")),
    check(demo_snippet_mentions_prepend_toast_viewport,
          contains(Demo, "prepend(toast_viewport,")),

    % show some real output for the record
    format("~n--- rendered toast_demo ---~n~w~n-----------------------------~n",
           [Demo]).
