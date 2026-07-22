:- module(ui_alert_dialog, []).

%   No predicates are exported: alert_dialog_root/2, alert_dialog_trigger/2,
%   alert_dialog_content/2, alert_dialog_title/2, alert_dialog_description/2,
%   alert_dialog_action/2, alert_dialog_cancel/2 and alert_dialog/2 are
%   never called module-qualified -- they are term SHAPES that
%   px_template's bare-call dispatch resolves via the multifile tmpl/2 /
%   render_helper/2 tables (adr/0019), the same pattern every other
%   prolog/ui/*.pl module in this port follows.

/** <module> Alert Dialog (adr/0026): an interruptive modal requiring an
explicit response (confirm/cancel) -- e.g. destructive-action
confirmation ("Delete account?").

Ported from Radix UI's Alert Dialog primitive (docs/radix-port-analysis.md,
"Alert Dialog" entry). Upstream anatomy is `Root`, `Trigger`, `Portal`,
`Overlay`, `Content`, `Action`, `Cancel` (both `Action` and `Cancel` are
literally `Dialog.Close` under a different name upstream -- there is no
separate `Close` export), `Title`, `Description`.

**A thin config wrapper over Dialog, not a reimplementation (the
analysis doc's own verdict).** This module composes `prolog/ui/dialog.pl`'s
parts directly rather than re-deriving any markup: `alert_dialog_root/2`,
`alert_dialog_trigger/2`, `alert_dialog_title/2`, `alert_dialog_description/2`
are pure `~>` pass-throughs to `dialog_root/2`/`dialog_trigger/2`/
`dialog_title/2`/`dialog_description/2` (identical output, only the
template *name* differs, so this module's own anatomy vocabulary matches
upstream's); `alert_dialog_content/2` composes `dialog_content/2` with
three forced deviations (below); `alert_dialog_action/2` and
`alert_dialog_cancel/2` both compose `dialog_close/2` -- same
`data-dialog-close` marker `assets/js/components/dialog.js` already
delegates click-to-close for generically (no new JS query target, no new
custom element: `<px-dialog>` itself is reused verbatim as the Root
wrapper).

**The three deviations from Dialog, precisely (per the analysis doc):**

  1. `modal` is forced `true`, not exposed as a prop -- alert dialogs
     cannot be non-modal. `alert_dialog_content/2` drops any caller-
     supplied `modal(_)` opt and always renders modal (no
     `data-modal="false"` ever, no `data_modal` opt on this module's
     public surface at all).
  2. Content sets `role="alertdialog"` instead of the native `<dialog>`
     element's own implicit `role="dialog"` -- `dialog_content/2` was
     built with exactly this hook (its module header: "an Alert Dialog
     port MUST pass `role(alertdialog)` explicitly"). `alert_dialog_content/2`
     drops any caller-supplied `role(_)` opt and always passes
     `role(alertdialog)` through.
  3. **Outside click never dismisses an Alert Dialog** (the ARIA
     alertdialog pattern: must be dismissed via an explicit action).
     Escape is NOT overridden -- Escape still closes it, same as Dialog.
     This is THE ONE GAP `dialog.js` did not already close: it wires
     backdrop-click light-dismiss unconditionally for every modal
     `<dialog>`. The fix (see that file's header for the exact diff) is
     a new opt-out marker, `data-no-outside-dismiss`, read once in
     `connectedCallback` -- when present on the `<dialog>` element, the
     backdrop-click listener is simply never attached. `alert_dialog_content/2`
     always emits this marker (an additive, boolean-style `data-*`
     attribute, same "presence alone carries the meaning" convention as
     `dialog_close/2`'s own `data-dialog-close`).

**Cancel is autofocused by default -- the platform way, no script
needed.** The analysis doc: "`onOpenAutoFocus` is overridden to focus
the Cancel button specifically, not the first tabbable element (focus
starts on the least-destructive action)... Cancel-button auto-focus
still needs a small script" (true of upstream's React implementation).
This port needs no script at all: native `<dialog>`'s own `showModal()`
already honours a plain HTML `autofocus` attribute on any descendant --
`alert_dialog_cancel/2` renders it unconditionally, so the platform's
own initial-focus algorithm lands on Cancel with zero JS. (If a Content
happens to render no Cancel at all -- an unusual, caller-driven choice
-- `showModal()` simply falls back to its normal "first focusable
descendant" default, same as Dialog.)

**Anatomy (this module's public template surface, seven parts):**
`Root` (`alert_dialog_root/2`, delegates to `dialog_root/2` verbatim),
`Trigger` (`alert_dialog_trigger/2`, delegates to `dialog_trigger/2`
verbatim), `Content` (`alert_dialog_content/2`, composes `dialog_content/2`
with the three forced deviations above), `Title` (`alert_dialog_title/2`,
delegates to `dialog_title/2` verbatim), `Description`
(`alert_dialog_description/2`, delegates to `dialog_description/2`
verbatim), `Action` (`alert_dialog_action/2`, composes `dialog_close/2`
with an additive `.px-alert-dialog-action` class -- destructive-red per
Radix's own hero demo), `Cancel` (`alert_dialog_cancel/2`, composes
`dialog_close/2` with an additive `.px-alert-dialog-cancel` class --
neutral -- plus the unconditional `autofocus` attribute above).
`alert_dialog/2` is the rule-1 top-level convenience assembling the
common case (the classic "delete account?" confirm), with the same
Trigger<->Content `aria-controls`/`id` and Content<->Title/Description
`aria-labelledby`/`aria-describedby`/`id` wiring `dialog/2` already does
(gensym pattern lifted straight from that module), plus a Cancel/Action
footer row.

**DOM/ARIA contract emitted** (docs/radix-port-analysis.md's "Alert
Dialog" entry, adr/0026 rule 2 -- sacred except where the analysis doc
itself documents Alert Dialog's deviations from Dialog, above):

    Trigger  <button type="button" aria-haspopup="dialog"
                      aria-expanded="true|false" aria-controls="{contentId}"
                      data-state="open|closed">     (identical to Dialog's
                          Trigger -- no anatomy difference documented)
    Content  <dialog role="alertdialog"             (ALWAYS explicit --
                          never the bare native-implicit `dialog` role)
                      id aria-labelledby="{titleId}" (only if a Title is
                          mounted) aria-describedby="{descId}" (only if a
                          Description is mounted)
                      data-state="open|closed"
                      data-no-outside-dismiss="">    (ALWAYS -- see
                          deviation 3 above; NEVER data-modal, since
                          modal is forced and never exposed)
    Title       <h2 id="{titleId}">                 (identical to Dialog)
    Description <p id="{descId}">                   (identical to Dialog)
    Cancel      <button type="button" data-dialog-close autofocus
                         class="px-dialog-close px-alert-dialog-cancel">
    Action      <button type="button" data-dialog-close
                         class="px-dialog-close px-alert-dialog-action">

Options (a plain list, adr/0026 rule 1) -- every part's Opts list is
identical to the corresponding Dialog part's own (see `prolog/ui/dialog.pl`'s
module header for the full per-option reference), with these
additions/removals:

  `alert_dialog_content/2` Opts: identical to `dialog_content/2`'s,
                    EXCEPT `role(_)` and `modal(_)` are accepted but
                    silently DISCARDED (not forwarded) -- this module's
                    whole point is that both are fixed, not configurable
                    (matches upstream: `modal` "is forced true and not
                    exposed as a prop" and Content "sets role=alertdialog
                    instead of role=dialog" with no override path).

  `alert_dialog_action/2` / `alert_dialog_cancel/2` Opts: identical to
                    `dialog_close/2`'s (`class(C)`, anything else,
                    merged/passed through) -- `alert_dialog_cancel/2`
                    additionally always emits `autofocus`, unconditionally
                    (not an opt-out -- see "Cancel is autofocused" above).

  `alert_dialog/2` Opts: identical to `dialog/2`'s `trigger(Kids)`/
                    `title(Kids)`/`description(Kids)`/`id(Id)`/`open(Bool)`/
                    `class(C)` (see that module's header), EXCEPT:
                      - no `modal(Bool)` (forced, never exposed, as above)
                      - no `close(Kids)` (Alert Dialog has no separate
                        Close export/default "x" icon button at all --
                        Radix's own anatomy omits it)
                      - `cancel(Kids)` optional: when supplied, an
                        `alert_dialog_cancel/2` is rendered (autofocused);
                        absent renders no Cancel button at all.
                      - `action(Kids)` optional: when supplied, an
                        `alert_dialog_action/2` is rendered; absent
                        renders no Action button at all.
                      - When either `cancel(Kids)` or `action(Kids)` (or
                        both) is supplied, they are wrapped together in a
                        `<div class="px-alert-dialog-footer">` (a
                        right-aligned button row, matching Radix's own
                        hero-demo `Flex justify="end"` footer) rendered
                        immediately after BodyChildren, Cancel before
                        Action (Radix's own demo order: least-destructive
                        action reads first, left-to-right). When BOTH are
                        absent, no footer `<div>` is rendered at all.

  `alert_dialog/2` second argument: BodyChildren -- same free-form
                    template-children slot as `dialog/2`'s, rendered
                    inside Content after Title/Description and before
                    the Cancel/Action footer (Alert Dialog has no Close
                    button at all, so there is no "Close renders first"
                    ordering rule to inherit from `dialog/2` here).

Both every part and `alert_dialog/2` are registered as
`px_template:render_helper/2` hooks (adr/0019) where genuine computation
happens (Content's forced role/modal/no-outside-dismiss, Action/Cancel's
class merge and Cancel's autofocus, the convenience's id-wiring); Root/
Trigger/Title/Description are plain `~>` template-term rewrites (no
computation of their own -- `toolbar.pl`'s `toolbar_toggle_group/2 ~>
toggle_group/2` is the precedent for this "same output, different
anatomy name" pattern).
*/

:- use_module(library(lists)).
:- use_module('../px_template').
:- use_module(dialog, []).

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

		 /*******************************
		 *        OPTION HELPERS        *
		 *******************************/

%   Same small helpers as dialog.pl's own (private copies, not shared
%   via export -- the established convention across this library; see
%   e.g. tabs.pl's/collapsible.pl's own duplicated take_bool/merge_class).

take_bool(Name, Default, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Rest)
    ->  ( V0 == true -> Value = true ; Value = false )
    ;   Value = Default, Rest = Opts0
    ).

merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  drop_opt(+Probe, +Opts0, -Rest) is det.
%
%   Removes a Probe(_) term from Opts0 if present; leaves Opts0
%   untouched otherwise. Used to silently discard a caller-supplied
%   role(_)/modal(_) on alert_dialog_content/2 -- both are forced, per
%   the module header's "three deviations".
drop_opt(Probe, Opts0, Rest) :-
    (   selectchk(Probe, Opts0, Rest)
    ->  true
    ;   Rest = Opts0
    ).

%!  take_kids(+Name, +Opts0, -Opt, -Rest) is det.
%
%   Same generic helper as dialog.pl's own -- Opt = Name(Kids), or
%   `none` if Name(_) is absent from Opts0.
take_kids(Name, Opts0, Opt, Rest) :-
    Probe =.. [Name, Kids],
    (   selectchk(Probe, Opts0, Rest)
    ->  Opt =.. [Name, Kids]
    ;   Opt = none, Rest = Opts0
    ).

%!  take_base_id(+Opts0, -Base, -Rest) is det.
%
%   Same fallback shape as dialog.pl's own take_base_id/3.
take_base_id(Opts0, Base, Rest) :-
    (   selectchk(id(Id), Opts0, Rest)
    ->  Base = Id
    ;   Rest = Opts0, gensym('px-alert-dialog-', Base)
    ).

		 /*******************************
		 *      ROOT / TRIGGER / TITLE  *
		 *      / DESCRIPTION (pure      *
		 *      pass-throughs)           *
		 *******************************/

%!  alert_dialog_root(+Opts, +Children) is det.
%
%   Identical output to dialog_root/2 -- the `<px-dialog>` custom
%   element (assets/js/components/dialog.js) is reused verbatim; no new
%   custom element exists or is needed for Alert Dialog.
alert_dialog_root(Opts, Children) ~> dialog_root(Opts, Children).

%!  alert_dialog_trigger(+Opts, +Children) is det.
%
%   Identical output to dialog_trigger/2 -- no anatomy difference
%   documented for Trigger between Dialog and Alert Dialog.
alert_dialog_trigger(Opts, Children) ~> dialog_trigger(Opts, Children).

%!  alert_dialog_title(+Opts, +Children) is det.
alert_dialog_title(Opts, Children) ~> dialog_title(Opts, Children).

%!  alert_dialog_description(+Opts, +Children) is det.
alert_dialog_description(Opts, Children) ~> dialog_description(Opts, Children).

		 /*******************************
		 *             CONTENT          *
		 *******************************/

%!  alert_dialog_content(+Opts, +Children) is det.
%
%   Composes dialog_content/2 with the three forced deviations (module
%   header): role(alertdialog) always, modal(true) always (both
%   overriding/discarding any caller-supplied role(_)/modal(_)), and
%   the data-no-outside-dismiss marker THE ONE GAP dialog.js closes
%   (see that file's own header for the exact mechanism).
px_template:render_helper(alert_dialog_content(Opts0, Children), S) :-
    must_be(list, Opts0),
    drop_opt(role(_), Opts0, Opts1),
    drop_opt(modal(_), Opts1, Opts2),
    append([ [role(alertdialog), modal(true), data_no_outside_dismiss("")],
             Opts2
           ], ContentOpts),
    px_template:render(S, dialog_content(ContentOpts, Children)).

		 /*******************************
		 *          ACTION / CANCEL     *
		 *******************************/

%!  alert_dialog_action(+Opts, +Children) is det.
%
%   Composes dialog_close/2 -- same data-dialog-close click-delegation
%   target as Dialog's own Close button -- with an additive
%   `.px-alert-dialog-action` class (assets/css/ui.css: destructive red,
%   per Radix's own hero demo's "Yes, delete account" button).
px_template:render_helper(alert_dialog_action(Opts0, Children), S) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-alert-dialog-action", ClassVal, Opts1),
    append([[class(ClassVal)], Opts1], CloseOpts),
    px_template:render(S, dialog_close(CloseOpts, Children)).

%!  alert_dialog_cancel(+Opts, +Children) is det.
%
%   Composes dialog_close/2 with an additive `.px-alert-dialog-cancel`
%   class (neutral styling) plus an unconditional `autofocus` attribute
%   -- the platform's own initial-focus mechanism, no script needed
%   (module header's "Cancel is autofocused by default").
px_template:render_helper(alert_dialog_cancel(Opts0, Children), S) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-alert-dialog-cancel", ClassVal, Opts1),
    append([[class(ClassVal), autofocus], Opts1], CloseOpts),
    px_template:render(S, dialog_close(CloseOpts, Children)).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  alert_dialog(+Opts, +BodyChildren) is det.
%
%   The common case: a Root wrapping an optional Trigger and a Content
%   assembled from an optional Title/Description/BodyChildren plus an
%   optional Cancel/Action footer, with every id
%   (`aria-controls`/`aria-labelledby`/`aria-describedby`) wired
%   automatically -- see the module header for the full Opts list.
alert_dialog(Opts, BodyChildren) ~> \alert_dialog_render(Opts, BodyChildren).

px_template:render_helper(alert_dialog_render(Opts0, BodyChildren), S) :-
    must_be(list, Opts0),
    take_bool(open, false, Opts0, Open, Opts1),
    take_base_id(Opts1, Base, Opts2),
    take_kids(trigger, Opts2, TriggerOpt, Opts3),
    take_kids(title, Opts3, TitleOpt, Opts4),
    take_kids(description, Opts4, DescriptionOpt, Opts5),
    take_kids(cancel, Opts5, CancelOpt, Opts6),
    take_kids(action, Opts6, ActionOpt, RootOpts),

    format(atom(ContentId), '~w-content', [Base]),
    format(atom(TitleId), '~w-title', [Base]),
    format(atom(DescId), '~w-description', [Base]),

    ( TriggerOpt = trigger(TriggerKids)
    ->  TriggerCall = [alert_dialog_trigger([open(Open), controls(ContentId)], TriggerKids)]
    ;   TriggerCall = []
    ),
    ( TitleOpt = title(TitleKids)
    ->  TitleCall = [alert_dialog_title([id(TitleId)], TitleKids)],
        LabelledbyOpts = [labelledby(TitleId)]
    ;   TitleCall = [], LabelledbyOpts = []
    ),
    ( DescriptionOpt = description(DescKids)
    ->  DescCall = [alert_dialog_description([id(DescId)], DescKids)],
        DescribedbyOpts = [describedby(DescId)]
    ;   DescCall = [], DescribedbyOpts = []
    ),
    ( CancelOpt = cancel(CancelKids)
    ->  CancelCall = [alert_dialog_cancel([], CancelKids)]
    ;   CancelCall = []
    ),
    ( ActionOpt = action(ActionKids)
    ->  ActionCall = [alert_dialog_action([], ActionKids)]
    ;   ActionCall = []
    ),
    ( (CancelCall == [], ActionCall == [])
    ->  FooterCall = []
    ;   FooterCall = [div([class("px-alert-dialog-footer")], [CancelCall, ActionCall])]
    ),

    append([ [open(Open), id(ContentId)], LabelledbyOpts, DescribedbyOpts ],
           ContentOpts),
    ContentChildren = [TitleCall, DescCall, BodyChildren, FooterCall],
    RootChildren = [TriggerCall, alert_dialog_content(ContentOpts, ContentChildren)],

    px_template:render(S, alert_dialog_root(RootOpts, RootChildren)).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Order 16: the next free slot after dialog.pl's/popover.pl's Order
%   15 -- adr/0026 rule 8's porting order places Alert Dialog right
%   after Dialog in the "dialogs" phase, which this port depends on
%   directly (composes dialog.pl's parts wholesale).
px_ui:demo(alert_dialog, 16, \alert_dialog_demo).

%   `\alert_dialog_demo`, not the bare atom -- same explicit `\Goal`
%   escape every other component's demo template needs (adr/0019: a
%   bare atom is always a text node in render/2's dispatch). The
%   classic Radix hero-demo confirm dialog: "Delete account?" with a
%   neutral autofocused Cancel and a destructive-red Action, plus a
%   second row calling out the outside-click-does-not-dismiss behavior
%   (Escape still does) for anyone driving the demo by hand.
alert_dialog_demo ~>
    div(class("px-alert-dialog-demo"),
      [ h3("Delete account -- the classic destructive-action confirm"),
        p("Click to open. Escape closes it; clicking the backdrop does NOT (data-no-outside-dismiss, assets/js/components/dialog.js) -- an Alert Dialog must be dismissed via an explicit action, matching the ARIA alertdialog pattern. Focus lands on Cancel, the least-destructive action, automatically (a plain autofocus attribute -- no script)."),
        alert_dialog(
          [ id("alert-dialog-demo"),
            trigger("Delete account"),
            title("Are you absolutely sure?"),
            description("This action cannot be undone. This will permanently delete your account and remove your data from our servers."),
            cancel("Cancel"),
            action("Yes, delete account")
          ],
          [])
      ]).
