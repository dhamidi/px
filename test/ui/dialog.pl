/* test/ui/dialog.pl (adr/0026): render-test proof for prolog/ui/dialog.pl
   -- the Dialog port. A plain swipl script, no server, no networking
   (test/ui/tabs.pl's / test/ui/accordion.pl's pattern):
   render_to_string/2 over the templates and assert the exact ARIA/data
   contract documented in docs/radix-port-analysis.md's "Dialog" entry
   and prolog/ui/dialog.pl's own module header, for:

     - dialog_trigger/2   aria-haspopup="dialog", aria-expanded,
                           aria-controls, data-state, class merge
     - dialog_content/2   the literal <dialog> tag (NOT the El(Attrs,
                           Children) whitelist path), NO explicit
                           role="dialog" by default, role(R) override
                           (AlertDialog hook), aria-labelledby/
                           aria-describedby only when supplied,
                           data-state, data-modal only when false,
                           native `open` only when open(true)
     - dialog_title/2     <h2>, id/class pass-through
     - dialog_description/2  <p>, id/class pass-through
     - dialog_close/2     <button data-dialog-close>, always marked
     - dialog/2           the full id-wiring (aria-controls/id,
                           aria-labelledby/id, aria-describedby/id),
                           optional trigger/title/description, default
                           accessible Close, close(none) suppression,
                           gensym'd id when omitted, open(_)/modal(_)
                           forwarding
     - the kitchen-sink demo registration (px_ui:demo/3) rendering end
       to end exactly as prolog/px_ui.pl's ui_show_view embeds it
       (`\Goal` as a div's Children, not the bare atom -- adr/0019's
       arity-0 dispatch rule)
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/dialog.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Harness (test/ui/tabs.pl's / test/ui/accordion.pl's pattern).
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

extract_attr_value(Haystack, Attr, Value) :-
    format(string(Prefix), "~w=\"", [Attr]),
    once(sub_string(Haystack, Before, Len, _, Prefix)),
    Start is Before + Len,
    sub_string(Haystack, Start, _, 0, Tail),
    once(sub_string(Tail, ValLen, _, _, "\"")),
    sub_string(Tail, 0, ValLen, _, Value).

main :-
    tests,
    failed_count(N),
    (   N =:= 0
    ->  format("~nAll ui/dialog checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Trigger: aria-haspopup="dialog", aria-expanded, aria-controls,
    % data-state, class merge.
    % ===================================================================

    render_to_string(dialog_trigger([], "Open"), TriggerDefault),
    check(trigger_haspopup_dialog,
          contains(TriggerDefault, "aria-haspopup=\"dialog\"")),
    check(trigger_default_closed,
          ( contains(TriggerDefault, "aria-expanded=\"false\""),
            contains(TriggerDefault, "data-state=\"closed\"") )),
    check(trigger_no_controls_by_default,
          not_contains(TriggerDefault, "aria-controls")),
    check(trigger_default_class,
          contains(TriggerDefault, "class=\"px-dialog-trigger\"")),
    check(trigger_default_exact,
          TriggerDefault ==
              "<button type=\"button\" aria-haspopup=\"dialog\" aria-expanded=\"false\" data-state=\"closed\" class=\"px-dialog-trigger\">Open</button>"),

    render_to_string(dialog_trigger([open(true), controls("c1")], "Open"), TriggerOpen),
    check(trigger_open_expanded_true,
          contains(TriggerOpen, "aria-expanded=\"true\"")),
    check(trigger_open_data_state,
          contains(TriggerOpen, "data-state=\"open\"")),
    check(trigger_controls,
          contains(TriggerOpen, "aria-controls=\"c1\"")),

    render_to_string(
        dialog_trigger([id("t1"), class("wide"), aria_label("Open the thing")], "Open"),
        TriggerOptsPassthrough),
    check(trigger_id_passed_through,
          contains(TriggerOptsPassthrough, "id=\"t1\"")),
    check(trigger_aria_label_passed_through,
          contains(TriggerOptsPassthrough, "aria-label=\"Open the thing\"")),
    check(trigger_class_merged_after_default,
          contains(TriggerOptsPassthrough, "class=\"px-dialog-trigger wide\"")),

    % ===================================================================
    % Content: literal <dialog> tag, no explicit role by default, role(R)
    % override, aria-labelledby/describedby only when supplied,
    % data-state, data-modal only when false, native `open` only when
    % open(true).
    % ===================================================================

    render_to_string(dialog_content([], "Body"), ContentDefault),
    check(content_is_dialog_tag,
          ( sub_string(ContentDefault, 0, 7, _, "<dialog"),
            sub_string(ContentDefault, _, _, 0, "</dialog>") )),
    check(content_no_explicit_role_by_default,
          not_contains(ContentDefault, "role=")),
    check(content_default_closed,
          contains(ContentDefault, "data-state=\"closed\"")),
    check(content_no_open_attr_by_default,
          not_contains(ContentDefault, " open")),
    check(content_no_labelledby_by_default,
          not_contains(ContentDefault, "aria-labelledby")),
    check(content_no_describedby_by_default,
          not_contains(ContentDefault, "aria-describedby")),
    check(content_no_data_modal_by_default,
          not_contains(ContentDefault, "data-modal")),
    check(content_default_class,
          contains(ContentDefault, "class=\"px-dialog-content\"")),
    check(content_default_exact,
          ContentDefault ==
              "<dialog data-state=\"closed\" class=\"px-dialog-content\">Body</dialog>"),

    render_to_string(
        dialog_content([labelledby("t"), describedby("d"), open(true)], "Body"),
        ContentOpen),
    check(content_labelledby,
          contains(ContentOpen, "aria-labelledby=\"t\"")),
    check(content_describedby,
          contains(ContentOpen, "aria-describedby=\"d\"")),
    check(content_open_data_state,
          contains(ContentOpen, "data-state=\"open\"")),
    check(content_open_attr_present,
          contains(ContentOpen, " open")),

    % role(R) override -- the AlertDialog hook.
    render_to_string(dialog_content([role(alertdialog)], "Body"), ContentAlert),
    check(content_role_override,
          contains(ContentAlert, "role=\"alertdialog\"")),

    % modal(false) -- data-modal="false" only when non-default.
    render_to_string(dialog_content([modal(false)], "Body"), ContentNonModal),
    check(content_data_modal_false,
          contains(ContentNonModal, "data-modal=\"false\"")),
    render_to_string(dialog_content([modal(true)], "Body"), ContentModalTrue),
    check(content_data_modal_true_omitted,
          not_contains(ContentModalTrue, "data-modal")),

    % id + class pass-through/merge.
    render_to_string(dialog_content([id("c1"), class("wide")], "Body"), ContentOpts),
    check(content_id_passed_through,
          contains(ContentOpts, "id=\"c1\"")),
    check(content_class_merged,
          contains(ContentOpts, "class=\"px-dialog-content wide\"")),

    % ===================================================================
    % Title: <h2>, id/class pass-through.
    % ===================================================================

    render_to_string(dialog_title([id("ti1")], "Delete file?"), Title),
    check(title_is_h2_tag,
          ( sub_string(Title, 0, 3, _, "<h2"),
            sub_string(Title, _, _, 0, "</h2>") )),
    check(title_id,
          contains(Title, "id=\"ti1\"")),
    check(title_default_class,
          contains(Title, "class=\"px-dialog-title\"")),
    check(title_text,
          contains(Title, "Delete file?")),

    % ===================================================================
    % Description: <p>, id/class pass-through.
    % ===================================================================

    render_to_string(dialog_description([id("d1")], "This can't be undone."), Description),
    check(description_is_p_tag,
          ( sub_string(Description, 0, 2, _, "<p"),
            sub_string(Description, _, _, 0, "</p>") )),
    check(description_id,
          contains(Description, "id=\"d1\"")),
    check(description_default_class,
          contains(Description, "class=\"px-dialog-description\"")),

    % ===================================================================
    % Close: <button data-dialog-close>, always marked, class merge.
    % ===================================================================

    render_to_string(dialog_close([], "Cancel"), Close),
    check(close_is_button_tag,
          ( sub_string(Close, 0, 7, _, "<button"),
            sub_string(Close, _, _, 0, "</button>") )),
    check(close_marker_always_present,
          contains(Close, "data-dialog-close=\"\"")),
    check(close_default_class,
          contains(Close, "class=\"px-dialog-close\"")),
    check(close_exact,
          Close ==
              "<button type=\"button\" data-dialog-close=\"\" class=\"px-dialog-close\">Cancel</button>"),

    % ===================================================================
    % Root: wrapper is <px-dialog>.
    % ===================================================================

    render_to_string(dialog_root([], []), RootEmpty),
    check(root_wrapper_is_px_dialog,
          ( sub_string(RootEmpty, 0, _, _, "<px-dialog>"),
            sub_string(RootEmpty, _, _, 0, "</px-dialog>") )),
    check(root_default_class,
          contains(RootEmpty, "class=\"px-dialog\"")),

    % ===================================================================
    % Convenience `dialog/2`: full id-wiring, optional trigger/title/
    % description, default accessible Close, close(none) suppression,
    % gensym'd id when omitted, open(_)/modal(_) forwarding.
    % ===================================================================

    render_to_string(
        dialog([id("d1"), trigger("Open"), title("Title"), description("Desc")],
               ["Body content"]),
        Full),

    check(full_wrapper_is_px_dialog,
          ( sub_string(Full, 0, _, _, "<px-dialog>"),
            sub_string(Full, _, _, 0, "</px-dialog>") )),
    check(full_has_trigger,
          contains(Full, "aria-haspopup=\"dialog\"")),
    check(full_trigger_controls_content,
          contains(Full, "aria-controls=\"d1-content\"")),
    check(full_content_id,
          contains(Full, "id=\"d1-content\"")),
    check(full_content_labelledby_title,
          contains(Full, "aria-labelledby=\"d1-title\"")),
    check(full_content_describedby_description,
          contains(Full, "aria-describedby=\"d1-description\"")),
    check(full_title_id,
          contains(Full, "id=\"d1-title\"")),
    check(full_title_text,
          contains(Full, "Title")),
    check(full_description_id,
          contains(Full, "id=\"d1-description\"")),
    check(full_description_text,
          contains(Full, "Desc")),
    check(full_default_close_present,
          contains(Full, "data-dialog-close=\"\"")),
    check(full_default_close_accessible_name,
          contains(Full, "px-visually-hidden")),
    check(full_body_content_present,
          contains(Full, "Body content")),
    check(full_default_closed,
          ( contains(Full, "data-state=\"closed\""),
            not_contains(Full, "data-modal") )),

    % No trigger/title/description supplied: none of the three render,
    % and Content carries neither aria-labelledby nor aria-describedby.
    render_to_string(dialog([id("d2")], ["Just body"]), NoParts),
    check(no_parts_no_trigger,
          not_contains(NoParts, "aria-haspopup")),
    check(no_parts_no_title,
          not_contains(NoParts, "<h2")),
    check(no_parts_no_labelledby,
          not_contains(NoParts, "aria-labelledby")),
    check(no_parts_no_description,
          not_contains(NoParts, "<p class=\"px-dialog-description\"")),
    check(no_parts_no_describedby,
          not_contains(NoParts, "aria-describedby")),
    check(no_parts_close_still_default,
          contains(NoParts, "data-dialog-close")),
    check(no_parts_body_present,
          contains(NoParts, "Just body")),

    % close(none) suppresses the Close button entirely.
    render_to_string(dialog([id("d3"), close(none)], ["Body"]), NoClose),
    check(no_close_suppressed,
          not_contains(NoClose, "data-dialog-close")),

    % close(Kids) overrides the default content.
    render_to_string(dialog([id("d4"), close("Dismiss")], ["Body"]), CustomClose),
    check(custom_close_text,
          sub_string(CustomClose, _, _, _,
                     "data-dialog-close=\"\" class=\"px-dialog-close\">Dismiss</button>")),

    % open(true)/modal(false) forwarding: Trigger AND Content both see
    % open(true); only Content sees modal(false).
    render_to_string(
        dialog([id("d5"), trigger("Open"), open(true), modal(false)], ["Body"]),
        OpenNonModal),
    check(open_forwarded_trigger,
          contains(OpenNonModal, "aria-expanded=\"true\"")),
    check(open_forwarded_content,
          contains(OpenNonModal, "data-state=\"open\"")),
    check(modal_false_forwarded_content_only,
          count_occurrences(OpenNonModal, "data-modal=\"false\"", 1)),

    % Gensym'd id when omitted -- still produces a consistent,
    % non-empty wiring.
    render_to_string(dialog([trigger("Open")], ["Body"]), GensymId),
    check(gensym_id_wiring_consistent,
          ( sub_string(GensymId, _, _, _, "aria-controls=\"px-dialog-"),
            sub_string(GensymId, _, _, _, "id=\"px-dialog-") )),

    % class/extra opts forwarded to Root's div.
    render_to_string(dialog([id("d6"), class("wide")], ["Body"]), RootClass),
    check(root_class_merged,
          contains(RootClass, "class=\"px-dialog wide\"")),

    % Direct id-wiring cross-check: extract and compare attribute
    % values rather than substring guessing.
    render_to_string(
        dialog([id("d7"), trigger("Open"), title("T"), description("D")], ["B"]),
        Wired),
    extract_attr_value(Wired, "aria-controls", ControlsVal),
    extract_attr_value(Wired, "aria-labelledby", LabelledbyVal),
    extract_attr_value(Wired, "aria-describedby", DescribedbyVal),
    check(wiring_controls_matches_content_id,
          ( ControlsVal == "d7-content",
            sub_string(Wired, _, _, _, "id=\"d7-content\"") )),
    check(wiring_labelledby_matches_title_id,
          ( LabelledbyVal == "d7-title",
            sub_string(Wired, _, _, _, "id=\"d7-title\"") )),
    check(wiring_describedby_matches_description_id,
          ( DescribedbyVal == "d7-description",
            sub_string(Wired, _, _, _, "id=\"d7-description\"") )),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it: `\Call` as a div's sole
    % Children argument.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(dialog, _Order, \dialog_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(dialog, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \dialog_demo), Demo),
    check(demo_has_two_dialogs,
          count_occurrences(Demo, "<px-dialog>", 2)),
    check(demo_has_two_triggers,
          count_occurrences(Demo, "aria-haspopup=\"dialog\"", 2)),
    check(demo_has_two_dialog_tags,
          count_occurrences(Demo, "<dialog ", 2)),
    check(demo_has_a_form,
          contains(Demo, "<form>")),
    check(demo_has_nested_list,
          contains(Demo, "<ul>")),
    check(demo_first_has_description,
          contains(Demo, "Make changes to your profile")),
    check(demo_second_has_no_description_but_has_title,
          contains(Demo, "What's new")),

    % show some real output for the record
    format("~n--- rendered dialog_demo ---~n~w~n-----------------------------~n",
           [Demo]).
