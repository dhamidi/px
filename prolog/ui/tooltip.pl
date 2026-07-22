:- module(ui_tooltip, []).

%   No predicates are exported: tooltip_root/2, tooltip_trigger/2,
%   tooltip_content/2, tooltip_arrow/1 and tooltip/2 are never called
%   module-qualified -- they are term SHAPES that px_template's
%   bare-call dispatch resolves via the multifile
%   px_template:render_helper/2 table (registered below), the same
%   pattern prolog/ui/popover.pl uses.

/** <module> Tooltip (adr/0026): short, hover/focus-triggered text hint
anchored to its Trigger by `assets/js/lib/popper.js` -- popper's
second consumer after prolog/ui/popover.pl.

Ported from Radix UI's Tooltip primitive (docs/radix-port-analysis.md,
"Tooltip" entry). Anatomy upstream: `Provider`, `Root`, `Trigger`,
`Portal`, `Content`, `Arrow`. The analysis doc's own verdict: "the most
algorithmically involved primitive in the overlay family... the
delay/skip-delay/single-open/grace-area system is the entirety of what
needs porting -- there is no focus trap and no modal behavior at all."

**Scope (documented reduction, adr/0026 rule 2/3).** This port ships
the delay/skip-delay coordination faithfully (delayDuration 700ms,
skipDelayDuration 300ms -- Radix's own defaults) and the three-way
`data-state` contract, but deliberately does NOT port the convex-hull
grace-area polygon (moving the pointer from Trigger to Content along a
protected diagonal without closing) -- the analysis doc's own "Port
difficulty: L" callout names this as the single most involved piece,
and this port's Content is short hint text, not `disableHoverableContent
=false` rich interactive content the polygon exists to protect; a
future revision porting hoverable/interactive tooltip content should
add it then. Losing it only regresses the interactive-content case:
plain hover/focus/leave/Escape and the delay/skip-delay system --
"the entirety of what needs porting" for the common case -- are all
here.

**No `Provider` template (documented deviation).** Upstream's Provider
is a React context wrapper whose only job is holding the document-wide
`isOpenDelayed`/last-close-timestamp state every Tooltip.Root reads.
Server-rendered markup has no equivalent concept to emit (there is no
DOM node Provider contributes), and the coordination itself lives
where it belongs for a vanilla-JS DOM world: a single module-level
variable in `assets/js/components/tooltip.js`, shared automatically by
every `<px-tooltip>` on the page with no wrapping element required --
see that file's header for the exact mechanism. This is a strict
simplification over upstream (no `<Tooltip.Provider>` to remember to
wrap the app in) with the same effective behavior.

**No `Portal` template** -- same rationale as popover.pl's own
omission: "not needed as an abstraction server-side... `popover`/
top-layer... handles the stacking-context escape natively", exactly
what Content's native `popover` attribute (below) gives for free.

**Platform choice (adr/0026 rule 3) -- native `popover="manual"` +
popper.js positioning.** Popover's own port used `popover="auto"`
because Trigger's native `popovertarget` click-toggles it and light-
dismiss (Escape/click-outside) is exactly what a click-triggered panel
wants. Tooltip is hover/focus-driven, not click-driven, and needs
precise custom control over WHEN it opens (delay timer, skip-delay
fast path) and closes (immediate on leave/blur/Escape, no light-dismiss
click-outside concept at all since there is nothing to click) -- both
squarely `<px-tooltip>`'s job, not the UA's. `popover="auto"` would
actively fight this: auto popovers close each other and light-dismiss
on outside pointerdown, neither of which maps onto hover semantics.
`popover="manual"` is the right primitive here instead: it still
promotes Content to the top layer (escaping ancestor `overflow`/
`z-index`, ARROW/POSITIONING'S whole reason for existing) and still
fires `beforetoggle`/`toggle` when `showPopover()`/`hidePopover()` are
called, but does NOT auto-close on outside interaction and does NOT
close other open popovers -- exactly what a hover-driven, JS-fully-
controlled show/hide wants. Because manual popovers are only ever
shown/hidden by `<px-tooltip>` calling `showPopover()`/`hidePopover()`
itself (there is no `popovertarget` button toggling Content the way
Popover's Trigger does), `assets/js/components/tooltip.js` drives state
synchronously in the same function that calls show/hide, rather than
popover.js's beforetoggle/toggle event-driven split (there is no
external toggle source to react to here) -- see that file's header.

**DOM/ARIA contract emitted** (docs/radix-port-analysis.md's "Tooltip"
entry, adr/0026 rule 2 -- sacred except where noted above):

    Trigger (`<button>`): NO `type="button"` (deliberate, matches
                          upstream -- "tooltip triggers are often
                          anchors, and type on an anchor means MIME
                          type, not button type"; a caller embedding a
                          Trigger inside a `<form>` must add
                          `type(button)` itself via pass-through Opts
                          if submit-on-click is not wanted), NO
                          aria-haspopup/aria-expanded (Tooltip is not a
                          disclosure widget upstream either -- the only
                          formal ARIA relationship is describedby),
                          aria-describedby (Content's id, when
                          describedby(_) supplied), data-state.
    Content (`<div>`):   role="tooltip" (the aria-label-override
                          variant that moves role to a separate
                          visually-hidden sibling is NOT ported --
                          documented gap, no caller in this port's demo
                          needs it), PLUS native popover="manual"
                          (additive, see "Platform choice" above), id,
                          data-state (three-way: closed | delayed-open
                          | instant-open), data-side, data-align (the
                          popper.js styling contract, same
                          [data-side=...]/[data-align=...] API Popover
                          already ships), data-side-offset,
                          data-align-offset (additive markup-level
                          handoff to `<px-tooltip>`, same convention as
                          popover.pl's own Content).
    Arrow (`<div>`):     aria-hidden="true" only -- pure CSS-positioned
                          nub keyed off Content's own [data-side], same
                          as popover.pl's Arrow.

Options (plain lists, adr/0026 rule 1):

  `tooltip_root/2` Opts:
    class(C)        merged with the default class, default first
                    ("px-tooltip C").
    anything else   passed through verbatim, appended AFTER the
                    computed attributes.

  `tooltip_trigger/2` Opts:
    state(closed|delayed_open|instant_open)  default `closed`. Drives
                    `data-state` (rendered as the hyphenated
                    "delayed-open"/"instant-open" wire values Radix's
                    own contract uses; Prolog-side the atom uses `_`,
                    same reason every other multi-word Prolog atom in
                    this codebase does -- `-` is not a valid unquoted
                    atom-continuation character). An unrecognised value
                    falls back to `closed`.
    describedby(Id) Content's own id -- REQUIRED for `aria-describedby`
                    wiring to mean anything; gensym'd by `tooltip/2`
                    when assembling the common case, but a standalone
                    call must supply one. Without it the Trigger still
                    renders (a plain, inert button) rather than
                    throwing -- same graceful-degradation posture as
                    popover.pl's own `controls(Id)`.
    class(C), anything else  pass-through, as usual.

  `tooltip_content/2` Opts:
    state(closed|delayed_open|instant_open)  default `closed`, same
                    coercion as Trigger's.
    id(Id)          this Content's own id -- REQUIRED for the
                    Trigger's `aria-describedby` to mean anything;
                    gensym'd by `tooltip/2`, standalone callers must
                    supply one.
    side(top|right|bottom|left)  default `top` -- Radix's own Tooltip
                    Content default (NOT Popover's `bottom` default;
                    the two components genuinely differ here, confirmed
                    against Radix's own Content API reference).
                    Drives `data-side`, read by `<px-tooltip>` as
                    popper.js's `side` option.
    align(start|center|end)  default `center` (Radix's own default).
                    Drives `data-align`, read the same way.
    side_offset(N)  default `0` (Radix's own default). Drives
                    `data-side-offset`.
    align_offset(N)  default `0` (Radix's own default). Drives
                    `data-align-offset`.
    class(C), anything else  pass-through, as usual.

  `tooltip_arrow/1` Opts:
    class(C), anything else  pass-through onto the `<div>`. No other
                    options -- pure markup, positioned entirely by CSS
                    keyed off the parent Content's `[data-side]`.

  `tooltip/2` Opts: everything `tooltip_root/2` takes, PLUS
    state(_)        default `closed`. Forwarded to both Trigger and
                    Content.
    side(_), align(_), side_offset(_), align_offset(_)  forwarded to
                    Content, same defaults as `tooltip_content/2`.
    id(Id)          optional; base every generated part's id is built
                    from (`<Id>-content`); gensym'd (`px-tooltip-N`)
                    when absent, same convention as popover.pl's
                    `content_id/2`.

  `tooltip/2` second argument: `[TriggerChildren, ContentChildren]`
                    (mirrors popover.pl's `popover/2` Parts shape
                    exactly) -- Content is wrapped with an Arrow
                    automatically (`tooltip_arrow([])`, appended after
                    ContentChildren) so the common case gets an arrow
                    for free.
*/

:- use_module(library(lists)).
:- use_module(library(gensym)).
:- use_module('../px_template').

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

		 /*******************************
		 *        OPTION HELPERS        *
		 *******************************/

valid_side(top).
valid_side(right).
valid_side(bottom).
valid_side(left).

valid_align(start).
valid_align(center).
valid_align(end).

valid_state(closed).
valid_state(delayed_open).
valid_state(instant_open).

%!  take_state(+Opts0, -State, -Rest) is det.
%
%   Default `closed`; an unrecognised value falls back to `closed`
%   too -- same guard shape as popover.pl's take_open/3.
take_state(Opts0, State, Rest) :-
    (   selectchk(state(S0), Opts0, Rest)
    ->  ( valid_state(S0) -> State = S0 ; State = closed )
    ;   State = closed, Rest = Opts0
    ).

%!  state_value(?State, ?Value) is det.
%
%   Prolog-side atom (underscore, a valid unquoted-atom separator) to
%   the wire value (hyphenated, Radix's own three-way contract).
state_value(closed,       closed).
state_value(delayed_open, 'delayed-open').
state_value(instant_open, 'instant-open').

%!  take_describedby(+Opts0, -DOpt, -Rest) is det.
take_describedby(Opts0, DOpt, Rest) :-
    (   selectchk(describedby(Id), Opts0, Rest)
    ->  DOpt = describedby(Id)
    ;   DOpt = none, Rest = Opts0
    ).

describedby_attrs(describedby(Id), [aria_describedby(Id)]) :- !.
describedby_attrs(none, []).

%!  take_side(+Opts0, -Side, -Rest) is det.
%
%   Default `top` -- Radix's own Tooltip Content default (differs from
%   popover.pl's `bottom` default -- see the module header).
take_side(Opts0, Side, Rest) :-
    (   selectchk(side(S0), Opts0, Rest)
    ->  ( valid_side(S0) -> Side = S0 ; Side = top )
    ;   Side = top, Rest = Opts0
    ).

%!  take_align(+Opts0, -Align, -Rest) is det.
take_align(Opts0, Align, Rest) :-
    (   selectchk(align(A0), Opts0, Rest)
    ->  ( valid_align(A0) -> Align = A0 ; Align = center )
    ;   Align = center, Rest = Opts0
    ).

%!  take_offset(+Name, +Opts0, -Value, -Rest) is det.
take_offset(Name, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Rest)
    ->  Value = V0
    ;   Value = 0, Rest = Opts0
    ).

%!  merge_class(+Opts0, +Default, -ClassVal, -Rest) is det.
merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

		 /*******************************
		 *             ROOT             *
		 *******************************/

%!  tooltip_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `tooltip_root([], [Trigger, Content])`.
%   Renders the `<px-tooltip>` custom-element wrapper (adr/0026 rule 4)
%   around a server-rendered `<div>` -- without JS upgrade, Content
%   stays hidden (manual popovers, like auto ones, start hidden by the
%   UA stylesheet and there is no `popovertarget` here to open it --
%   see the module header's "Platform choice"): the documented no-JS
%   gap, same class as popover.pl's own `open(true)` story, except here
%   there is no JS-free open path at all because there is no click to
%   hang a `popovertarget` off -- hover/focus opening is irreducibly
%   `<px-tooltip>`'s job.
px_template:render_helper(tooltip_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_tooltip, [], [div(Attrs, Children)]).

root_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-tooltip", ClassVal, Opts1),
    append([ [class(ClassVal)], Opts1 ], Attrs).

		 /*******************************
		 *            TRIGGER           *
		 *******************************/

%!  tooltip_trigger(+Opts, +Children) is det.
%
%   Bare-call template surface: `tooltip_trigger([state(delayed_open),
%   describedby(Id)], "Hover me")`. Deliberately NO `type(button)` --
%   see the module header's DOM/ARIA contract note.
px_template:render_helper(tooltip_trigger(Opts, Children), S) :-
    trigger_attrs(Opts, Attrs),
    px_template:render(S, button(Attrs, Children)).

trigger_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_state(Opts0, State, Opts1),
    take_describedby(Opts1, DOpt, Opts2),
    merge_class(Opts2, "px-tooltip-trigger", ClassVal, Opts3),
    state_value(State, StateVal),
    describedby_attrs(DOpt, DAttrs),
    append([ DAttrs, [data_state(StateVal), class(ClassVal)], Opts3 ], Attrs).

		 /*******************************
		 *            CONTENT           *
		 *******************************/

%!  tooltip_content(+Opts, +Children) is det.
%
%   Bare-call template surface: `tooltip_content([id("t1"),
%   state(instant_open), side(bottom)], "Hint text")`. Renders the
%   native `popover="manual"` + `role="tooltip"` bubble `<px-tooltip>`
%   positions -- see the module header for the full platform split.
px_template:render_helper(tooltip_content(Opts, Children), S) :-
    content_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, Children)).

content_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_state(Opts0, State, Opts1),
    take_side(Opts1, Side, Opts2),
    take_align(Opts2, Align, Opts3),
    take_offset(side_offset, Opts3, SideOffset, Opts4),
    take_offset(align_offset, Opts4, AlignOffset, Opts5),
    merge_class(Opts5, "px-tooltip-content", ClassVal, Opts6),
    state_value(State, StateVal),
    append([ [role(tooltip), popover(manual)],
             [data_state(StateVal), data_side(Side), data_align(Align),
              data_side_offset(SideOffset), data_align_offset(AlignOffset),
              class(ClassVal)
             ],
             Opts6
           ], Attrs).

		 /*******************************
		 *             ARROW            *
		 *******************************/

%!  tooltip_arrow(+Opts) is det.
%
%   Bare-call template surface: `tooltip_arrow([])`. Pure markup, same
%   "plain div, CSS rotate" choice as popover.pl's own Arrow.
px_template:render_helper(tooltip_arrow(Opts), S) :-
    arrow_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, [])).

arrow_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-tooltip-arrow", ClassVal, Opts1),
    append([ [aria_hidden(true), class(ClassVal)], Opts1 ], Attrs).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  tooltip(+Opts, +Parts) is det.
%
%   Parts = [TriggerChildren, ContentChildren]. The common case: a Root
%   wrapping one Trigger and one Content (with an Arrow appended
%   automatically), `state(_)` threaded to both, Trigger's
%   `aria-describedby` wired to Content's `id` automatically -- same
%   division of labour as popover.pl's `popover/2`.
tooltip(Opts, Parts) ~> \tooltip_render(Opts, Parts).

px_template:render_helper(tooltip_render(Opts, [TriggerKids, ContentKids]), S) :-
    must_be(list, Opts),
    take_state(Opts, State, _),
    take_side(Opts, Side, _),
    take_align(Opts, Align, _),
    take_offset(side_offset, Opts, SideOffset, _),
    take_offset(align_offset, Opts, AlignOffset, _),
    content_id(Opts, ContentId),
    exclude(convenience_only_opt, Opts, RootOpts),
    TriggerOpts = [state(State), describedby(ContentId)],
    ContentOpts = [ state(State), id(ContentId), side(Side), align(Align),
                     side_offset(SideOffset), align_offset(AlignOffset)
                   ],
    px_template:render(S,
        tooltip_root(RootOpts,
          [ tooltip_trigger(TriggerOpts, TriggerKids),
            tooltip_content(ContentOpts, [ContentKids, tooltip_arrow([])])
          ])).

%!  convenience_only_opt(+Opt) is semidet.
%
%   Same rationale as popover.pl's own: Trigger/Content-only concepts
%   that must NOT leak onto Root's `<div>` as literal, meaningless HTML
%   attributes.
convenience_only_opt(state(_)).
convenience_only_opt(side(_)).
convenience_only_opt(align(_)).
convenience_only_opt(side_offset(_)).
convenience_only_opt(align_offset(_)).

%!  content_id(+Opts, -ContentId) is det.
%
%   `id(Base)` from Opts, suffixed "-content", if the caller supplied
%   one; otherwise a fresh gensym'd id (`px-tooltip-N-content`) --
%   same convention as popover.pl's own `content_id/2`.
content_id(Opts, ContentId) :-
    (   memberchk(id(Base), Opts)
    ->  true
    ;   gensym(px_tooltip_, Base)
    ),
    format(atom(ContentId), '~w-content', [Base]).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Order 16: the next free slot after dialog.pl's/popover.pl's Order
%   15 (adr/0026 rule 8: Tooltip is popper.js's second consumer,
%   scheduled right after Popover, its proving consumer, per the
%   analysis doc's own dependency-ordered "popper" consumer list).
px_ui:demo(tooltip, 16, \tooltip_demo).

%   `\tooltip_demo`, not the bare atom -- adr/0019's arity-0 dispatch
%   escape, same as every other component's demo template.
tooltip_demo ~>
    div(class("px-tooltip-demo"),
      [ section(class("ui-demo-block"),
          [ h3("Basic -- hover or focus the trigger"),
            p("delayDuration defaults to 700ms (Radix's own default): hover and wait -- data-state goes closed -> delayed-open. Move the pointer straight to another tooltip's trigger within 300ms of this one closing (skipDelayDuration) and it opens INSTANTLY -- data-state goes straight to instant-open, no wait. Escape, blur, or moving the pointer off the trigger closes it immediately."),
            tooltip([],
              [ "Hover or focus me",
                "Helpful hint text"
              ])
          ]),

        section(class("ui-demo-block"),
          [ h3("Icon button"),
            p("The trigger can be any focusable control -- an icon-only button needs its OWN accessible name (aria-label here); the tooltip's aria-describedby supplies supplementary hint text on top of that name, not a replacement for it."),
            \tooltip_icon_demo
          ]),

        h3("Every side, align(center)"),
        p("side(top|right|bottom|left) -- data-side drives both the arrow's CSS direction and, via lib/popper.js, which edge of the trigger the bubble is placed against; top is Tooltip's own Radix default (Popover's is bottom)."),
        div(class("px-tooltip-sides-row"),
          [ tooltip_side_demo(top, "Top"),
            tooltip_side_demo(right, "Right"),
            tooltip_side_demo(bottom, "Bottom"),
            tooltip_side_demo(left, "Left")
          ])
      ]).

%!  tooltip_icon_demo// is det.
%
%   An icon-only trigger -- `aria-label` gives it an accessible name
%   (the button itself has no visible text), `tooltip_content/2`'s
%   `aria-describedby` wiring layers the hint text on top as a
%   SUPPLEMENTARY description, not a replacement -- `tooltip/2`'s
%   convenience form has no hook to add `aria_label(_)` onto Trigger
%   specifically (same limitation `popover/2` has), so this demo
%   composes `tooltip_root/2`/`tooltip_trigger/2`/`tooltip_content/2`
%   directly instead, exactly popover.pl's own "Basic" demo's reason
%   for doing the same.
px_template:render_helper(tooltip_icon_demo, S) :-
    px_template:render(S,
        tooltip_root([],
          [ tooltip_trigger(
                [ describedby("tooltip-demo-icon"), aria_label("Add to library") ],
                raw("<svg viewBox=\"0 0 24 24\" width=\"16\" height=\"16\" aria-hidden=\"true\" focusable=\"false\"><path fill=\"currentColor\" d=\"M12 2a1 1 0 0 1 1 1v8h8a1 1 0 1 1 0 2h-8v8a1 1 0 1 1-2 0v-8H3a1 1 0 1 1 0-2h8V3a1 1 0 0 1 1-1z\"/></svg>")),
            tooltip_content([id("tooltip-demo-icon")],
              [ "Add to library", tooltip_arrow([]) ])
          ])).

%!  tooltip_side_demo(+Side, +Label) is det.
%
%   One tooltip per side, `side_offset(6)` for a visible gap off the
%   trigger.
tooltip_side_demo(Side, Label) ~>
    div(class("px-tooltip-side-demo-item"), \tooltip_side_demo_render(Side, Label)).

px_template:render_helper(tooltip_side_demo_render(Side, Label), S) :-
    px_template:render(S,
        tooltip([side(Side), side_offset(6)],
          [ Label, ["Positioned ", Label, "."] ])).
