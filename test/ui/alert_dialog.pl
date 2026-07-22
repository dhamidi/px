/* test/ui/alert_dialog.pl (adr/0026): render-test proof for
   prolog/ui/alert_dialog.pl -- the Alert Dialog port. A plain swipl
   script, no server, no networking (test/ui/dialog.pl's pattern):
   render_to_string/2 over the templates and assert the exact ARIA/data
   contract documented in docs/radix-port-analysis.md's "Alert Dialog"
   entry and prolog/ui/alert_dialog.pl's own module header, for:

     - alert_dialog_trigger/2   identical to dialog_trigger/2's contract
     - alert_dialog_content/2   role="alertdialog" ALWAYS (even when a
                                 caller tries role(dialog)), data-modal
                                 NEVER emitted (even when a caller tries
                                 modal(false)), data-no-outside-dismiss
                                 ALWAYS, aria-labelledby/describedby only
                                 when supplied, data-state, native `open`
                                 only when open(true)
     - alert_dialog_title/2 / alert_dialog_description/2   identical to
                                 dialog_title/2's / dialog_description/2's
     - alert_dialog_cancel/2    <button data-dialog-close autofocus
                                 class="px-dialog-close px-alert-dialog-cancel">
     - alert_dialog_action/2    <button data-dialog-close (NO autofocus)
                                 class="px-dialog-close px-alert-dialog-action">
     - alert_dialog_root/2      identical to dialog_root/2's (same
                                 <px-dialog> custom element, reused)
     - alert_dialog/2           the full id-wiring, optional trigger/
                                 title/description/cancel/action, footer
                                 wrapping cancel+action (cancel first),
                                 no footer when neither supplied, no
                                 default "x" close (unlike dialog/2),
                                 gensym'd id when omitted
     - the kitchen-sink demo registration (px_ui:demo/3) rendering end
       to end exactly as prolog/px_ui.pl's ui_show_view embeds it
*/

:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/ui/dialog.pl').
:- use_module('../../prolog/ui/alert_dialog.pl').

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
    ->  format("~nAll ui/alert_dialog checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-

    % ===================================================================
    % Trigger: identical contract to dialog_trigger/2.
    % ===================================================================

    render_to_string(alert_dialog_trigger([], "Delete account"), TriggerDefault),
    check(trigger_haspopup_dialog,
          contains(TriggerDefault, "aria-haspopup=\"dialog\"")),
    check(trigger_default_closed,
          ( contains(TriggerDefault, "aria-expanded=\"false\""),
            contains(TriggerDefault, "data-state=\"closed\"") )),
    check(trigger_default_class,
          contains(TriggerDefault, "class=\"px-dialog-trigger\"")),

    render_to_string(alert_dialog_trigger([open(true), controls("c1")], "Delete account"), TriggerOpen),
    check(trigger_open_expanded_true,
          contains(TriggerOpen, "aria-expanded=\"true\"")),
    check(trigger_controls,
          contains(TriggerOpen, "aria-controls=\"c1\"")),

    % ===================================================================
    % Content: role="alertdialog" ALWAYS (forced), data-modal NEVER
    % (forced true, not exposed), data-no-outside-dismiss ALWAYS.
    % ===================================================================

    render_to_string(alert_dialog_content([], "Body"), ContentDefault),
    check(content_is_dialog_tag,
          ( sub_string(ContentDefault, 0, 7, _, "<dialog"),
            sub_string(ContentDefault, _, _, 0, "</dialog>") )),
    check(content_role_alertdialog,
          contains(ContentDefault, "role=\"alertdialog\"")),
    check(content_no_data_modal,
          not_contains(ContentDefault, "data-modal")),
    check(content_no_outside_dismiss_marker,
          contains(ContentDefault, "data-no-outside-dismiss=\"\"")),
    check(content_default_closed,
          contains(ContentDefault, "data-state=\"closed\"")),
    check(content_no_open_attr_by_default,
          not_contains(ContentDefault, " open")),
    check(content_default_class,
          contains(ContentDefault, "class=\"px-dialog-content\"")),

    % role(_)/modal(_) supplied by a caller are silently discarded --
    % Alert Dialog's role and modality are not configurable.
    render_to_string(alert_dialog_content([role(dialog)], "Body"), ContentRoleOverride),
    check(content_role_cannot_be_overridden,
          ( contains(ContentRoleOverride, "role=\"alertdialog\""),
            not_contains(ContentRoleOverride, "role=\"dialog\"") )),

    render_to_string(alert_dialog_content([modal(false)], "Body"), ContentModalOverride),
    check(content_modal_cannot_be_overridden,
          not_contains(ContentModalOverride, "data-modal")),

    render_to_string(
        alert_dialog_content([labelledby("t"), describedby("d"), open(true)], "Body"),
        ContentOpen),
    check(content_labelledby,
          contains(ContentOpen, "aria-labelledby=\"t\"")),
    check(content_describedby,
          contains(ContentOpen, "aria-describedby=\"d\"")),
    check(content_open_data_state,
          contains(ContentOpen, "data-state=\"open\"")),
    check(content_open_attr_present,
          contains(ContentOpen, " open")),

    % ===================================================================
    % Title / Description: identical to dialog_title/2's / dialog_
    % description/2's contract (pure pass-throughs).
    % ===================================================================

    render_to_string(alert_dialog_title([id("ti1")], "Are you absolutely sure?"), Title),
    check(title_is_h2_tag,
          ( sub_string(Title, 0, 3, _, "<h2"),
            sub_string(Title, _, _, 0, "</h2>") )),
    check(title_default_class,
          contains(Title, "class=\"px-dialog-title\"")),

    render_to_string(alert_dialog_description([id("d1")], "This cannot be undone."), Description),
    check(description_is_p_tag,
          ( sub_string(Description, 0, 2, _, "<p"),
            sub_string(Description, _, _, 0, "</p>") )),
    check(description_default_class,
          contains(Description, "class=\"px-dialog-description\"")),

    % ===================================================================
    % Cancel: data-dialog-close, autofocus ALWAYS, neutral class.
    % ===================================================================

    render_to_string(alert_dialog_cancel([], "Cancel"), Cancel),
    check(cancel_is_button_tag,
          ( sub_string(Cancel, 0, 7, _, "<button"),
            sub_string(Cancel, _, _, 0, "</button>") )),
    check(cancel_marker_present,
          contains(Cancel, "data-dialog-close=\"\"")),
    check(cancel_autofocus_present,
          contains(Cancel, " autofocus")),
    check(cancel_class,
          contains(Cancel, "class=\"px-dialog-close px-alert-dialog-cancel\"")),

    % ===================================================================
    % Action: data-dialog-close, NO autofocus, destructive class.
    % ===================================================================

    render_to_string(alert_dialog_action([], "Yes, delete account"), Action),
    check(action_is_button_tag,
          ( sub_string(Action, 0, 7, _, "<button"),
            sub_string(Action, _, _, 0, "</button>") )),
    check(action_marker_present,
          contains(Action, "data-dialog-close=\"\"")),
    check(action_no_autofocus,
          not_contains(Action, "autofocus")),
    check(action_class,
          contains(Action, "class=\"px-dialog-close px-alert-dialog-action\"")),

    % ===================================================================
    % Root: identical to dialog_root/2's (same <px-dialog> element).
    % ===================================================================

    render_to_string(alert_dialog_root([], []), RootEmpty),
    check(root_wrapper_is_px_dialog,
          ( sub_string(RootEmpty, 0, _, _, "<px-dialog>"),
            sub_string(RootEmpty, _, _, 0, "</px-dialog>") )),
    check(root_default_class,
          contains(RootEmpty, "class=\"px-dialog\"")),

    % ===================================================================
    % Convenience `alert_dialog/2`: full id-wiring, optional trigger/
    % title/description/cancel/action, footer wrapping cancel+action
    % (cancel first), no default close, gensym'd id when omitted.
    % ===================================================================

    render_to_string(
        alert_dialog(
            [ id("ad1"), trigger("Delete account"), title("Are you sure?"),
              description("This cannot be undone."), cancel("Cancel"),
              action("Yes, delete account") ],
            ["Extra body"]),
        Full),

    check(full_wrapper_is_px_dialog,
          ( sub_string(Full, 0, _, _, "<px-dialog>"),
            sub_string(Full, _, _, 0, "</px-dialog>") )),
    check(full_role_alertdialog,
          contains(Full, "role=\"alertdialog\"")),
    check(full_no_outside_dismiss,
          contains(Full, "data-no-outside-dismiss=\"\"")),
    check(full_trigger_controls_content,
          contains(Full, "aria-controls=\"ad1-content\"")),
    check(full_content_id,
          contains(Full, "id=\"ad1-content\"")),
    check(full_content_labelledby_title,
          contains(Full, "aria-labelledby=\"ad1-title\"")),
    check(full_content_describedby_description,
          contains(Full, "aria-describedby=\"ad1-description\"")),
    check(full_title_id,
          contains(Full, "id=\"ad1-title\"")),
    check(full_description_id,
          contains(Full, "id=\"ad1-description\"")),
    check(full_body_content_present,
          contains(Full, "Extra body")),
    check(full_footer_present,
          contains(Full, "class=\"px-alert-dialog-footer\"")),
    check(full_cancel_before_action,
          ( sub_string(Full, CancelPos, _, _, "px-alert-dialog-cancel"),
            sub_string(Full, ActionPos, _, _, "px-alert-dialog-action"),
            CancelPos < ActionPos )),
    check(full_cancel_autofocused,
          contains(Full, "autofocus")),
    check(full_default_closed,
          ( contains(Full, "data-state=\"closed\""),
            not_contains(Full, "data-modal") )),
    check(full_no_stray_data_modal,
          not_contains(Full, "data-modal")),

    % No trigger/title/description/cancel/action supplied: none render;
    % no footer div at all when both cancel and action are absent.
    render_to_string(alert_dialog([id("ad2")], ["Just body"]), NoParts),
    check(no_parts_no_trigger,
          not_contains(NoParts, "aria-haspopup")),
    check(no_parts_no_title,
          not_contains(NoParts, "<h2")),
    check(no_parts_no_labelledby,
          not_contains(NoParts, "aria-labelledby")),
    check(no_parts_no_describedby,
          not_contains(NoParts, "aria-describedby")),
    check(no_parts_no_footer,
          not_contains(NoParts, "px-alert-dialog-footer")),
    check(no_parts_no_close_marker_at_all,
          not_contains(NoParts, "data-dialog-close")),
    check(no_parts_still_role_alertdialog,
          contains(NoParts, "role=\"alertdialog\"")),
    check(no_parts_still_no_outside_dismiss,
          contains(NoParts, "data-no-outside-dismiss")),
    check(no_parts_body_present,
          contains(NoParts, "Just body")),

    % cancel(Kids) alone still produces a footer (Action absent).
    render_to_string(alert_dialog([id("ad3"), cancel("Nevermind")], ["Body"]), CancelOnly),
    check(cancel_only_footer_present,
          contains(CancelOnly, "px-alert-dialog-footer")),
    check(cancel_only_no_action,
          not_contains(CancelOnly, "px-alert-dialog-action")),

    % Gensym'd id when omitted.
    render_to_string(alert_dialog([trigger("Delete")], ["Body"]), GensymId),
    check(gensym_id_wiring_consistent,
          ( sub_string(GensymId, _, _, _, "aria-controls=\"px-alert-dialog-"),
            sub_string(GensymId, _, _, _, "id=\"px-alert-dialog-") )),

    % class/extra opts forwarded to Root's div.
    render_to_string(alert_dialog([id("ad4"), class("wide")], ["Body"]), RootClass),
    check(root_class_merged,
          contains(RootClass, "class=\"px-dialog wide\"")),

    % Direct id-wiring cross-check.
    render_to_string(
        alert_dialog([id("ad5"), trigger("Open"), title("T"), description("D")], ["B"]),
        Wired),
    extract_attr_value(Wired, "aria-controls", ControlsVal),
    extract_attr_value(Wired, "aria-labelledby", LabelledbyVal),
    extract_attr_value(Wired, "aria-describedby", DescribedbyVal),
    check(wiring_controls_matches_content_id,
          ControlsVal == "ad5-content"),
    check(wiring_labelledby_matches_title_id,
          LabelledbyVal == "ad5-title"),
    check(wiring_describedby_matches_description_id,
          DescribedbyVal == "ad5-description"),

    % open(_) forwarding: Trigger AND Content both see open(true);
    % there is no modal(_) opt on alert_dialog/2's public surface at
    % all (forced, never exposed).
    render_to_string(
        alert_dialog([id("ad6"), trigger("Open"), open(true)], ["Body"]),
        Opened),
    check(open_forwarded_trigger,
          contains(Opened, "aria-expanded=\"true\"")),
    check(open_forwarded_content,
          contains(Opened, "data-state=\"open\"")),

    % ===================================================================
    % Kitchen-sink demo (px_ui:demo/3), rendered exactly the way
    % prolog/px_ui.pl's ui_show_view embeds it.
    % ===================================================================

    check(demo_registered,
          px_ui:demo(alert_dialog, _Order, \alert_dialog_demo)),
    check(demo_registered_exactly_once,
          ( findall(Order, px_ui:demo(alert_dialog, Order, _), Orders),
            length(Orders, 1) )),

    render_to_string(div(class("ui-demo"), \alert_dialog_demo), Demo),
    check(demo_has_one_dialog,
          count_occurrences(Demo, "<px-dialog>", 1)),
    check(demo_has_trigger,
          contains(Demo, "aria-haspopup=\"dialog\"")),
    check(demo_has_role_alertdialog,
          contains(Demo, "role=\"alertdialog\"")),
    check(demo_has_no_outside_dismiss,
          contains(Demo, "data-no-outside-dismiss")),
    check(demo_has_footer,
          contains(Demo, "px-alert-dialog-footer")),
    check(demo_has_cancel_class,
          contains(Demo, "px-alert-dialog-cancel")),
    check(demo_has_action_class,
          contains(Demo, "px-alert-dialog-action")),
    check(demo_has_autofocus,
          contains(Demo, "autofocus")),
    check(demo_has_title_text,
          contains(Demo, "Are you absolutely sure?")),
    check(demo_has_description_text,
          contains(Demo, "permanently delete your account")),
    check(demo_has_demo_wrapper_class,
          contains(Demo, "px-alert-dialog-demo")),

    % show some real output for the record
    format("~n--- rendered alert_dialog_demo ---~n~w~n-----------------------------~n",
           [Demo]).
