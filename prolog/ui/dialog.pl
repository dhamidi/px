:- module(ui_dialog, []).

%   No predicates are exported: dialog/2, dialog_root/2, dialog_trigger/2,
%   dialog_content/2, dialog_title/2, dialog_description/2 and
%   dialog_close/2 are never called module-qualified -- they are term
%   SHAPES that px_template's bare-call dispatch resolves via the
%   multifile tmpl/2 / render_helper/2 tables (adr/0019), the same
%   pattern prolog/ui/tabs.pl and prolog/ui/accordion.pl use.

/** <module> Dialog (adr/0026): a centered modal (default) or non-modal
window overlay, opened from a Trigger, dismissible via a Close button,
Escape, or (modal only) an outside click.

Ported from Radix UI's Dialog primitive (docs/radix-port-analysis.md,
"Dialog" entry). Upstream anatomy is `Root`, `Trigger`, `Portal`,
`Overlay` (modal only), `Content`, `Title`, `Description`, `Close`.

**Portal/Overlay collapse (platform simplification, documented per
adr/0026 rule 2/3).** This port does NOT expose `dialog_portal/2` or
`dialog_overlay/2` templates -- the analysis doc's own verdict: "the top
layer IS the portal, ::backdrop IS the overlay". Native `<dialog>` +
`showModal()` promotes the element to the browser's top layer with zero
markup of its own (Portal existed only to physically relocate JSX to
`document.body` to escape ancestor `overflow`/`z-index` stacking
contexts -- a pure React-reconciliation concern, moot server-side, see
the analysis doc's "Shared machinery" section), and the UA-generated
`::backdrop` pseudo-element that comes with top-layer promotion IS the
Overlay -- there is no `data-state`-bearing DOM node for it to carry
(Radix's Overlay renders `data-state` on a real element; here that
styling hook is exposed instead as a `::backdrop` CSS rule scoped to
`dialog[data-state="open"]::backdrop` in assets/css/ui.css, the
documented equivalent hook -- see "Styling hook" below).

**Anatomy (this module's public template surface, six parts):**
`Root` (`dialog_root/2`, the `<px-dialog>` custom-element wrapper,
adr/0026 rule 4), `Trigger` (`dialog_trigger/2`, a `<button>`),
`Content` (`dialog_content/2`, the NATIVE `<dialog>` element itself --
see "Platform choice" below), `Title` (`dialog_title/2`, an `<h2>`),
`Description` (`dialog_description/2`, a `<p>`), `Close`
(`dialog_close/2`, a `<button>`). `dialog/2` is the rule-1 top-level
convenience assembling the common case, with the Trigger<->Content
`aria-controls`/`id` wiring and Content<->Title/Description
`aria-labelledby`/`aria-describedby`/`id` wiring computed automatically
(gensym pattern lifted straight from `prolog/ui/tabs.pl`'s
`take_root_base/3`).

**Platform choice (adr/0026 rule 3) -- native `<dialog>` +
`showModal()`.** The analysis doc's own verdict: "CUSTOM-ELEMENT,
substantially platform-assisted... covering the simple modal case
well." `dialog_content/2` renders a literal `<dialog>` tag via
`px_template:render_tag/4` (NOT the `El(Attrs,Children)` whitelist
path -- `dialog` is deliberately NOT added to px_template's
`html_element/1` whitelist, because this module's own top-level
convenience is itself named `dialog/2`, and `~>` rejects any template
whose functor is a whitelisted element name, adr/0019's
`expand_template/3` guard, "bare calls resolve element-first, so it
could never be called". `render_tag/4` -- the exact mechanism
`tabs_root/2`/`accordion_root/2` already use for their own non-whitelisted
`<px-tabs>`/`<px-accordion>` wrapper tags -- sidesteps the whitelist
entirely and writes any literal tag name, so `<dialog>` ships with zero
changes to px_template.pl). `showModal()` gives, for free, with no JS
written in this module: top-layer stacking (no z-index bookkeeping),
`::backdrop` (Overlay, above), Escape-to-close (dispatches a `cancel`
then `close` event), and a baseline focus trap with default
focus-return to the trigger on close. What it does NOT give, per the
analysis doc, and what `assets/js/components/dialog.js` supplies (see
that file's own header for the exact mechanism of each):

  1. Body scroll-lock -- `showModal()` does not touch `<body>` scroll.
  2. Outside-click (backdrop-click) light-dismiss -- `<dialog>` has no
     built-in equivalent; added via `event.target === dialogEl` plus a
     `getBoundingClientRect()` bounds check on click.
  3. Keeping the Trigger's `aria-expanded`/`data-state` in sync with
     Content's own `data-state` across open/close (native `<dialog>`
     only owns its own attributes, not a sibling Trigger's).

Deliberately NOT ported (documented gaps, future work, not this
module's job per adr/0026 rule 3's "irreducible behavior only" bar):
the non-modal branch-registry system (a portalled Popover nested
logically-but-not-DOM-inside a modal Dialog -- no native "one top-layer
element is inside another" concept exists) and the full hand-rolled
non-modal interact-outside bookkeeping Radix does (`modal(false)` here
is a deliberately thin `show()` swap -- see `assets/js/components/
dialog.js`'s header for exactly what that variant does and does not
get).

**No `aria-modal` (upstream's own choice, kept as-is).** Radix
explicitly never sets `aria-modal` on Content -- source comment: "a
better-supported equivalent to `aria-modal`" is `hideOthers()` marking
sibling subtrees `aria-hidden`. This port has no client-side
`hideOthers` equivalent (out of scope, same "irreducible behavior only"
bar) and, matching upstream, does not emit `aria-modal` either --
native `showModal()`'s own top-layer promotion already removes the rest
of the page from the accessibility tree while open in every engine that
implements it, which is the actual behavior `hideOthers()` was
polyfilling.

**Role handling -- built for AlertDialog reuse.** The analysis doc:
Content carries "role=dialog id aria-labelledby ... aria-describedby
... data-state" -- and separately notes Alert Dialog "wraps Dialog
wholesale", differing only in `Content sets role="alertdialog" instead
of role="dialog"`. The native `<dialog>` element's OWN implicit ARIA
role is already `dialog` -- so `dialog_content/2` deliberately does
**not** render an explicit `role="dialog"` attribute (a documented,
zero-regression platform simplification: the computed role assistive
tech sees is identical either way). What it DOES expose is a `role(R)`
Opts key: absent (the common Dialog case) emits nothing and lets the
implicit role stand; `role(alertdialog)` (or any other value) emits it
explicitly, because `alertdialog` has NO native `<dialog>`-implicit
equivalent -- an Alert Dialog port MUST pass `role(alertdialog)`
explicitly. This is the one hook a follow-on `ui/alert_dialog.pl` port
needs from this module beyond composing `dialog_root/2`/`dialog_content/2`
directly with a different default config, exactly mirroring how
upstream Alert Dialog is "a thin config wrapper, not a reimplementation".

**Styling hook (Overlay collapse, above).** `assets/css/ui.css`'s
Dialog section keys backdrop dimming off `dialog.px-dialog-content::backdrop`
(scoped to this component's own class, not a bare `dialog::backdrop`,
so it never leaks onto some unrelated native `<dialog>` an app might
render outside px_ui) plus `[data-state="open"]`/`[data-state="closed"]`
for the open/close transition -- the closest CSS equivalent to Radix's
`data-state`-keyed Overlay styling despite there being no Overlay
element to attach it to.

**DOM/ARIA contract emitted** (docs/radix-port-analysis.md's "Dialog"
entry, adr/0026 rule 2 -- sacred except where noted above):

    Trigger  <button type="button" aria-haspopup="dialog"
                      aria-expanded="true|false" aria-controls="{contentId}"
                      data-state="open|closed">
    Content  <dialog id aria-labelledby="{titleId}"    (only if a Title
                          is mounted -- dialog/2 wires this automatically)
                      aria-describedby="{descId}"       (only if a
                          Description is mounted)
                      data-state="open|closed">          (role="dialog" is
                          the element's own IMPLICIT role -- see above;
                          role(R) overrides explicitly when supplied)
    Title       <h2 id="{titleId}">
    Description <p id="{descId}">
    Close       <button type="button" data-dialog-close>  (data-dialog-close
                          is an additive JS-hook marker, not a Radix
                          attribute -- assets/js/components/dialog.js's
                          click-to-close query target, same "DOM-level
                          encoding" rationale as tabs.pl's own
                          `data-loop`)

Two additional additive-only extensions (rule 2):

  1. `data-modal="false"` on Content, ONLY when `modal(false)` -- the
     analysis doc's own default is modal, so the common case emits
     nothing (mirrors tabs.pl's `data-loop` / accordion.pl's
     `data-collapsible` convention of "marker present only when
     non-default"). `assets/js/components/dialog.js` reads it to
     decide `show()` vs `showModal()`.
  2. Content's `open(true)` renders the bare native `open` attribute --
     a statically-open, NON-modal `<dialog>` at first paint (no
     backdrop, no focus trap, no Escape-close: exactly what `<dialog
     open>` without a `showModal()` call natively is). This is the
     no-JS degrade path for a dialog a caller wants server-rendered
     already visible; the common "closed until JS opens it" case is
     `open(false)` (the default), under which the dialog is fully
     absent from view (the UA stylesheet's own `dialog:not([open])
     {display:none}`) until `<px-dialog>` calls `showModal()`/`show()`.

Options (a plain list, adr/0026 rule 1):

  `dialog_trigger/2` Opts:
    open(Bool)      default `false`. Drives `aria-expanded` and
                    `data-state` (open|closed).
    controls(Id)    the Content id this Trigger discloses; emitted as
                    `aria-controls`. Not a Radix prop the way it reads
                    here (Radix's Trigger reads it off context) --
                    `dialog/2` supplies it when assembling the common
                    case, same role as collapsible.pl's own
                    `controls(Id)`.
    class(C), anything else  merged/passed through, same convention as
                    every other part in this library.

  `dialog_content/2` Opts:
    open(Bool)      default `false`. Drives `data-state` and the bare
                    native `open` attribute (see extension 2 above).
    labelledby(Id)  emits `aria-labelledby`, only when supplied.
    describedby(Id) emits `aria-describedby`, only when supplied.
    role(R)         emits an explicit `role="R"` attribute, only when
                    supplied (see "Role handling" above; absent =
                    implicit native `dialog` role stands).
    modal(Bool)     default `true`. Emits `data-modal="false"` only
                    when `false` (extension 1 above).
    class(C), anything else  merged/passed through, as usual. `id(Id)`
                    is never specially "taken" here -- pass it through
                    like any other part's `id`.

  `dialog_title/2` / `dialog_description/2` Opts:
    class(C), anything else (id(...), ...)  merged/passed through --
                    no other computed attributes; these two parts carry
                    no ARIA/data-state of their own in the analysis
                    doc, only an `id` a caller (or `dialog/2`) wires
                    into Content's `aria-labelledby`/`aria-describedby`.

  `dialog_close/2` Opts:
    class(C), anything else  merged/passed through. `data-dialog-close`
                    (extension, see contract above) is ALWAYS emitted --
                    it carries no state, purely a query-target marker.

  `dialog/2` Opts:
    trigger(Kids)   optional. When supplied, a `dialog_trigger/2` is
                    rendered and wired to Content via `aria-controls`;
                    when absent, no Trigger is rendered at all (a
                    caller-driven-open dialog, e.g. opened from a
                    `<px-toolbar>` button elsewhere on the page that
                    reaches in and calls `.showModal()` directly).
    title(Kids)     optional. When supplied, a `dialog_title/2` is
                    rendered (gensym'd id) and Content's
                    `aria-labelledby` wired to it; absent skips both.
    description(Kids)  optional, same wiring story for `aria-describedby`.
    close(Kids)     optional. Default: an "x" glyph plus a
                    `visually_hidden([], "Close")` accessible name
                    (prolog/ui/visually_hidden.pl, adr/0026) -- so the
                    default close affordance is never an unlabelled
                    icon button. `close(none)` suppresses the Close
                    button entirely; any other `Kids` overrides its
                    content (the caller is then responsible for its own
                    accessible name if it is icon-only).
    id(Id)          optional base every derived id (`<Id>-content`,
                    `<Id>-title`, `<Id>-description`) is built from;
                    defaults to a fresh gensym'd `px-dialog-N` (mirrors
                    `tabs/2`'s own `take_root_base/3`).
    open(Bool)      default `false`. Forwarded to both Trigger and
                    Content.
    modal(Bool)     default `true`. Forwarded to Content only (extension
                    1 above).
    class(C), anything else  forwarded to Root's wrapper `<div>`, same
                    last-wins spread order as every other convenience
                    template in this library.

  `dialog/2` second argument: BodyChildren -- arbitrary template
                    children (a form, prose, nested markup -- anything
                    `render/2` accepts) rendered inside Content AFTER
                    Title/Description. Close is rendered FIRST inside
                    Content (CSS positions `.px-dialog-close` absolute
                    top-right regardless of DOM order -- a deliberate,
                    documented ordering choice, not upstream Radix's
                    "author decides" freedom, which the flat
                    `[TriggerKids, TitleKids, ...]`-shaped convenience
                    cannot offer without becoming its own template
                    language; callers wanting a different order compose
                    `dialog_root/2`/`dialog_content/2`/parts directly).

Both every part and `dialog/2` are registered as
`px_template:render_helper/2` hooks (adr/0019) -- the Opts-list
defaults/merge/id-wiring logic below is genuine computation, the same
reason tabs.pl/accordion.pl/collapsible.pl register theirs the same
way.
*/

:- use_module(library(lists)).
:- use_module(library(gensym)).
:- use_module('../px_template').
:- use_module(visually_hidden, []).

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

		 /*******************************
		 *        OPTION HELPERS        *
		 *******************************/

%!  take_bool(+Name, +Default, +Opts0, -Value, -Rest) is det.
%
%   Same shape as tabs.pl's own take_bool/5: pulls Name(Value) out of
%   Opts0, defaulting to Default when absent.
take_bool(Name, Default, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Rest)
    ->  ( V0 == true -> Value = true ; Value = false )
    ;   Value = Default, Rest = Opts0
    ).

%!  merge_class(+Opts0, +Default, -ClassVal, -Rest) is det.
%
%   Same helper as every other port in this library.
merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

state_atom(true,  open)   :- !.
state_atom(false, closed).

		 /*******************************
		 *             ROOT             *
		 *******************************/

%!  dialog_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `dialog_root([], [Trigger, Content])`.
%   Renders the `<px-dialog>` custom-element wrapper (adr/0026 rule 4)
%   around a plain `<div>` -- exactly tabs_root/2's/accordion_root/2's
%   own pattern. Without JS upgrade: the Trigger is a real, focusable
%   `<button>`; the Content `<dialog>` simply never opens (no
%   `showModal()`/`show()` caller exists) -- the documented no-JS story
%   (adr/0026 rule 4's progressive-enhancement bar): nothing breaks,
%   the dialog is just unreachable, same class of gap as Select's
%   "native element variant is the no-JS fallback" for a component that
%   has no lesser native form at all.
px_template:render_helper(dialog_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_dialog, [], [div(Attrs, Children)]).

root_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-dialog", ClassVal, Opts1),
    append([ [class(ClassVal)], Opts1 ], Attrs).

		 /*******************************
		 *            TRIGGER           *
		 *******************************/

%!  dialog_trigger(+Opts, +Children) is det.
%
%   Bare-call template surface: `dialog_trigger([open(false),
%   controls(Id)], "Open")`.
px_template:render_helper(dialog_trigger(Opts, Children), S) :-
    trigger_attrs(Opts, Attrs),
    px_template:render(S, button(Attrs, Children)).

trigger_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_bool(open, false, Opts0, Open, Opts1),
    take_controls(Opts1, ControlsOpt, Opts2),
    merge_class(Opts2, "px-dialog-trigger", ClassVal, Opts3),
    state_atom(Open, State),
    controls_attrs(ControlsOpt, ControlsAttrs),
    append([ [type(button), aria_haspopup(dialog), aria_expanded(Open)],
             ControlsAttrs,
             [data_state(State), class(ClassVal)],
             Opts3
           ], Attrs).

take_controls(Opts0, ControlsOpt, Rest) :-
    (   selectchk(controls(Id), Opts0, Rest)
    ->  ControlsOpt = controls(Id)
    ;   ControlsOpt = none, Rest = Opts0
    ).

controls_attrs(controls(Id), [aria_controls(Id)]) :- !.
controls_attrs(none, []).

		 /*******************************
		 *            CONTENT           *
		 *******************************/

%!  dialog_content(+Opts, +Children) is det.
%
%   Bare-call template surface: `dialog_content([labelledby(Tid),
%   describedby(Did)], [...])`. Renders the literal `<dialog>` tag via
%   render_tag/4 -- see the module header's "Platform choice" section
%   for why this deliberately bypasses the El(Attrs,Children) element
%   whitelist instead of adding `dialog` to it.
px_template:render_helper(dialog_content(Opts, Children), S) :-
    content_attrs(Opts, Attrs),
    px_template:render_tag(S, dialog, Attrs, Children).

content_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_bool(open, false, Opts0, Open, Opts1),
    take_bool(modal, true, Opts1, Modal, Opts2),
    take_labelledby(Opts2, LOpt, Opts3),
    take_describedby(Opts3, DOpt, Opts4),
    take_role(Opts4, ROpt, Opts5),
    merge_class(Opts5, "px-dialog-content", ClassVal, Opts6),
    state_atom(Open, State),
    role_attrs(ROpt, RoleAttrs),
    labelledby_attrs(LOpt, LabelledbyAttrs),
    describedby_attrs(DOpt, DescribedbyAttrs),
    modal_attrs(Modal, ModalAttrs),
    ( Open == true -> OpenAttrs = [open] ; OpenAttrs = [] ),
    append([ RoleAttrs, LabelledbyAttrs, DescribedbyAttrs,
             [data_state(State)], ModalAttrs, [class(ClassVal)],
             OpenAttrs, Opts6
           ], Attrs).

take_labelledby(Opts0, LOpt, Rest) :-
    (   selectchk(labelledby(Id), Opts0, Rest)
    ->  LOpt = labelledby(Id)
    ;   LOpt = none, Rest = Opts0
    ).

labelledby_attrs(labelledby(Id), [aria_labelledby(Id)]) :- !.
labelledby_attrs(none, []).

take_describedby(Opts0, DOpt, Rest) :-
    (   selectchk(describedby(Id), Opts0, Rest)
    ->  DOpt = describedby(Id)
    ;   DOpt = none, Rest = Opts0
    ).

describedby_attrs(describedby(Id), [aria_describedby(Id)]) :- !.
describedby_attrs(none, []).

take_role(Opts0, ROpt, Rest) :-
    (   selectchk(role(R), Opts0, Rest)
    ->  ROpt = role(R)
    ;   ROpt = none, Rest = Opts0
    ).

%   Deliberately NOT role="dialog" by default -- the native <dialog>
%   element's own implicit role already is `dialog` (see the module
%   header's "Role handling" section). Only an explicit override (e.g.
%   role(alertdialog), for a future ui/alert_dialog.pl) ever emits one.
role_attrs(role(R), [role(R)]) :- !.
role_attrs(none, []).

%   data-modal="false" only when non-default -- same "marker present
%   only when deviating from default" convention as tabs.pl's data-loop
%   / accordion.pl's data-collapsible.
modal_attrs(false, [data_modal("false")]) :- !.
modal_attrs(true,  []).

		 /*******************************
		 *             TITLE            *
		 *******************************/

%!  dialog_title(+Opts, +Children) is det.
%
%   Bare-call template surface: `dialog_title([id(Tid)], "Delete file?")`.
px_template:render_helper(dialog_title(Opts, Children), S) :-
    merge_class(Opts, "px-dialog-title", ClassVal, Opts1),
    append([class(ClassVal)], Opts1, Attrs),
    px_template:render(S, h2(Attrs, Children)).

		 /*******************************
		 *          DESCRIPTION         *
		 *******************************/

%!  dialog_description(+Opts, +Children) is det.
%
%   Bare-call template surface:
%   `dialog_description([id(Did)], "This can't be undone.")`.
px_template:render_helper(dialog_description(Opts, Children), S) :-
    merge_class(Opts, "px-dialog-description", ClassVal, Opts1),
    append([class(ClassVal)], Opts1, Attrs),
    px_template:render(S, p(Attrs, Children)).

		 /*******************************
		 *             CLOSE             *
		 *******************************/

%!  dialog_close(+Opts, +Children) is det.
%
%   Bare-call template surface: `dialog_close([], "Cancel")`.
%   `data-dialog-close` (always emitted) is assets/js/components/
%   dialog.js's click-to-close query target -- an additive JS-hook
%   marker, not a Radix attribute (see the module header's contract).
px_template:render_helper(dialog_close(Opts, Children), S) :-
    must_be(list, Opts),
    merge_class(Opts, "px-dialog-close", ClassVal, Opts1),
    append([ [type(button), data_dialog_close(""), class(ClassVal)], Opts1 ], Attrs),
    px_template:render(S, button(Attrs, Children)).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  dialog(+Opts, +BodyChildren) is det.
%
%   The common case: a Root wrapping an optional Trigger and a Content
%   assembled from an optional Title/Description/Close plus
%   BodyChildren, with every id (`aria-controls`/`aria-labelledby`/
%   `aria-describedby`) wired automatically -- gensym pattern lifted
%   from tabs.pl's take_root_base/3. See the module header for the
%   full Opts list and the fixed Close-first/Title/Description/Body
%   render order.
dialog(Opts, BodyChildren) ~> \dialog_render(Opts, BodyChildren).

px_template:render_helper(dialog_render(Opts0, BodyChildren), S) :-
    must_be(list, Opts0),
    take_bool(open, false, Opts0, Open, Opts1),
    take_bool(modal, true, Opts1, Modal, Opts2),
    take_base_id(Opts2, Base, Opts3),
    take_kids(trigger, Opts3, TriggerOpt, Opts4),
    take_kids(title, Opts4, TitleOpt, Opts5),
    take_kids(description, Opts5, DescriptionOpt, Opts6),
    take_close_kids(Opts6, CloseOpt, RootOpts),

    format(atom(ContentId), '~w-content', [Base]),
    format(atom(TitleId), '~w-title', [Base]),
    format(atom(DescId), '~w-description', [Base]),

    ( TriggerOpt = trigger(TriggerKids)
    ->  TriggerCall = [dialog_trigger([open(Open), controls(ContentId)], TriggerKids)]
    ;   TriggerCall = []
    ),
    ( TitleOpt = title(TitleKids)
    ->  TitleCall = [dialog_title([id(TitleId)], TitleKids)],
        LabelledbyOpts = [labelledby(TitleId)]
    ;   TitleCall = [], LabelledbyOpts = []
    ),
    ( DescriptionOpt = description(DescKids)
    ->  DescCall = [dialog_description([id(DescId)], DescKids)],
        DescribedbyOpts = [describedby(DescId)]
    ;   DescCall = [], DescribedbyOpts = []
    ),
    ( CloseOpt = close(CloseKids)
    ->  CloseCall = [dialog_close([], CloseKids)]
    ;   CloseCall = []
    ),

    append([ [open(Open), modal(Modal), id(ContentId)],
             LabelledbyOpts, DescribedbyOpts
           ], ContentOpts),
    % Nested lists are fine as Children -- render/2 walks [X|Xs] (and any
    % X that is itself a list) recursively, so there is no need to flatten
    % CloseCall/TitleCall/DescCall (each already `[]` or a singleton) and
    % BodyChildren (whatever shape the caller passed, list or bare term)
    % into one flat list the way attribute lists must be (attrs are
    % walked element-by-element by render_attrs/2, which does require a
    % flat list -- hence the `append/2` above for ContentOpts).
    ContentChildren = [CloseCall, TitleCall, DescCall, BodyChildren],
    RootChildren = [TriggerCall, dialog_content(ContentOpts, ContentChildren)],

    px_template:render(S, dialog_root(RootOpts, RootChildren)).

%!  take_base_id(+Opts0, -Base, -Rest) is det.
%
%   `id(Base)` from Opts0 if the caller supplied one (removed from
%   Rest so it does not double up when RootOpts is later spread onto
%   Root's `<div>`); otherwise a fresh gensym'd `px-dialog-N` -- same
%   fallback shape as tabs.pl's take_root_base/3 / collapsible.pl's
%   content_id/2.
take_base_id(Opts0, Base, Rest) :-
    (   selectchk(id(Id), Opts0, Rest)
    ->  Base = Id
    ;   Rest = Opts0, gensym('px-dialog-', Base)
    ).

%!  take_kids(+Name, +Opts0, -Opt, -Rest) is det.
%
%   Opt = Name(Kids), or `none` if Name(_) is absent from Opts0.
%   Generic over `trigger`/`title`/`description` -- all three follow
%   the identical "optional, presence alone decides whether the part
%   renders" rule.
take_kids(Name, Opts0, Opt, Rest) :-
    Probe =.. [Name, Kids],
    (   selectchk(Probe, Opts0, Rest)
    ->  Opt =.. [Name, Kids]
    ;   Opt = none, Rest = Opts0
    ).

%!  take_close_kids(+Opts0, -CloseOpt, -Rest) is det.
%
%   `close(Kids)` from Opts0: `close(none)` (or any explicit `Kids`)
%   is honoured verbatim; ABSENT defaults to the accessible "x" glyph +
%   visually_hidden([], "Close") pair (module header's documented
%   default) rather than `none` -- the one part of `dialog/2` that is
%   opt-OUT, not opt-IN, so a Dialog assembled via the convenience
%   never accidentally ships an unclosable modal.
take_close_kids(Opts0, CloseOpt, Rest) :-
    (   selectchk(close(Kids), Opts0, Rest)
    ->  ( Kids == none -> CloseOpt = none ; CloseOpt = close(Kids) )
    ;   Rest = Opts0,
        CloseOpt = close([ span([aria_hidden(true)], "×"),
                            visually_hidden([], "Close")
                          ])
    ).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Order 15: the next free slot after accordion.pl's Order 14 --
%   adr/0026 rule 8's porting order places Dialog in the "dialogs"
%   phase, right after the roving-focus consumers (Toggle Group, Tabs,
%   Toolbar, Accordion) this port depends on nothing from but which
%   landed first in this codebase.
px_ui:demo(dialog, 15, \dialog_demo).

%   `\dialog_demo`, not the bare atom -- same explicit `\Goal` escape
%   every other component's demo template needs (adr/0019: a bare atom
%   is always a text node in render/2's dispatch). Two examples: a
%   Title+Description+form dialog (showing Trigger/Title/Description/
%   Close/BodyChildren all compose), and a second dialog whose Content
%   nests richer markup (a list inside a section) to demonstrate that
%   BodyChildren is genuinely arbitrary template content, not a form
%   only -- see the module header's "second arg" note.
dialog_demo ~>
    div(class("px-dialog-demo"),
      [ h3("Modal with a form -- Title/Description/Close/body all compose"),
        p("Click to open; Escape, the backdrop, or Cancel all close it (assets/js/components/dialog.js); without JavaScript the trigger is a plain, focusable button that never opens anything -- the documented no-JS story."),
        dialog(
          [ id("dialog-demo-form"),
            trigger("Edit profile"),
            title("Edit profile"),
            description("Make changes to your profile. Click save when you're done.")
          ],
          [ form(
              [ p([ label([for("dialog-demo-name")], "Name"),
                    input([type(text), id("dialog-demo-name"), value("Ada Lovelace")])
                  ]),
                p([ label([for("dialog-demo-handle")], "Handle"),
                    input([type(text), id("dialog-demo-handle"), value("@ada")])
                  ]),
                button([type(submit), class("px-dialog-save")], "Save changes")
              ])
          ]),

        h3("Nested content -- Content is arbitrary markup, not just a form"),
        p("Same anatomy, no description this time (aria-describedby is simply omitted -- Content's own aria-labelledby still wires to the Title); the body here is a section with a nested list."),
        dialog(
          [ id("dialog-demo-nested"), trigger("View changelog"),
            title("What's new") ],
          [ section(
              [ h4("0026 -- Dialog"),
                ul([ li("Native <dialog> + showModal() for top layer, ::backdrop and Escape."),
                     li("Outside-click and scroll-lock added in ~40 lines of JS."),
                     li("Zero-JS degrade: the trigger just never opens anything.")
                   ])
              ])
          ])
      ]).
