:- module(ui_popover, []).

%   No predicates are exported: popover/2, popover_root/2,
%   popover_trigger/2, popover_content/2, popover_arrow/1 and
%   popover_close/1,2 are never called module-qualified -- they are
%   term SHAPES that px_template's bare-call dispatch resolves via the
%   multifile px_template:render_helper/2 table (registered below),
%   the same pattern prolog/ui/collapsible.pl and prolog/ui/tabs.pl
%   use.

/** <module> Popover (adr/0026): anchored, click-triggered, non-modal
overlay for rich content, positioned relative to its Trigger by
`assets/js/lib/popper.js` -- this port is that shared module's proving
consumer.

Ported from Radix UI's Popover primitive (docs/radix-port-analysis.md,
"Popover" entry). Anatomy (this module's public template surface, per
the analysis doc's own list, minus the parts noted below):
`Root` (`popover_root/2`), `Trigger` (`popover_trigger/2`), `Content`
(`popover_content/2`), `Arrow` (`popover_arrow/1`), `Close`
(`popover_close/1,2`). `popover/2` is the rule-1 top-level convenience:
a Root wrapping one Trigger and one Content, id-wiring
(`aria-controls`/`popovertarget`/`id`) and `open(_)` threaded
automatically, the same division of labour as collapsible.pl's
`collapsible/2`.

**Anatomy omissions (contract deviations, noted per adr/0026 rule 2):**
no `Anchor` -- Trigger doubles as the anchor point popper.js positions
against by default (Radix's own Anchor exists only for the rarer case
where the visual anchor differs from Trigger, not needed by this
port); no `Portal` -- per the analysis doc, "not needed as an
abstraction server-side... `popover`/top-layer... handles the
stacking-context escape natively", exactly what Content's native
`popover` attribute (below) already gives for free; no `Title`/
`Description` -- upstream's are thin `id`-only wrappers whose sole job
is handing an id to Content's `aria-labelledby`/`aria-describedby`;
this port exposes that same wiring directly as `labelledby(Id)`/
`describedby(Id)` options on `popover_content/2` instead of adding two
more single-purpose templates (a caller supplies its own heading/text
element's id).

**Platform choice (adr/0026 rule 3) -- native `popover` + `popovertarget`
carries dismissal and toggling; popper.js carries positioning, per the
analysis doc's own recommended split.** The analysis doc's verdict on
Popover: "`popover=\"auto\"` gives native top-layer + light-dismiss for
the non-modal (default) case... Gaps: (1) `popover` doesn't position
anything -- CSS anchor positioning or a JS positioner is still needed
for side/align/collision/arrow... CSS anchor positioning covers flip/
fallback but not the available-width/height reporting... given uneven
2026 cross-browser anchor-positioning support." This port takes exactly
that split:

  - Content renders the native `popover="auto"` attribute (below) --
    Escape-to-dismiss, click-outside-to-dismiss, and top-layer stacking
    (escaping any ancestor `overflow`/`z-index`) are entirely the
    browser's job, zero JS.
  - Trigger renders the native `popovertarget` attribute pointing at
    Content's id -- clicking it opens/closes Content with **zero JS**;
    Close renders the same attribute with `popovertargetaction="hide"`.
    A page with `assets/js/components/popover.js` never loaded still
    gets a fully working, if unpositioned (see below), open/close
    popover.
  - `assets/js/components/popover.js`'s `<px-popover>` is the
    irreducible sliver the platform genuinely cannot give for free:
    calling `lib/popper.js`'s `position/3` (with `autoUpdate/3` while
    open) to place Content relative to Trigger by `side`/`align`/
    offsets/flip -- exactly the analysis doc's gap (1) above -- and
    mirroring `data-state`/`aria-expanded` off the native `toggle`
    event so they never drift from what the browser actually did.

**Gap (documented, not shipped as JS): `modal(true)` has no native
counterpart.** The analysis doc: "`popover` has no modal mode -- a
`modal=true` Popover has no clean native counterpart and would need to
fall back to `<dialog>`, an awkward two-element story," and lists
Popover's dependencies as including dismissable-layer/focus-guards/
focus-scope -- none of which are ported yet (Dialog, their first
consumer per adr/0026 rule 8's phase ordering, has not landed). This
port therefore ships **only Radix's own default, `modal=false`**: no
`modal(_)` option exists on any part here. Adding a modal variant is
future work gated on Dialog's focus-trap machinery landing first,
consistent with rule 8 ("a component agent must not begin a component
whose listed dependencies aren't merged") -- `modal=false` alone needed
none of dismissable-layer/focus-guards/focus-scope (the native
`popover` attribute already covers its whole job for the non-modal
case), which is what makes shipping this subset now possible at all.

**Gap (documented): `open(true)` needs JS to visually manifest.**
Unlike `<dialog open>`, there is no static HTML attribute that starts a
`[popover]` element already showing -- the UA stylesheet hides every
`[popover]` element until `showPopover()` runs or a `popovertarget`
button is activated. `popover_content/2`'s `open(true)` still renders
the CORRECT `data-state="open"` (and every other attribute a
JS-free reader -- a screen reader's accessibility tree walk, a test
asserting the contract -- can see), but the panel itself stays hidden
until `<px-popover>` reconciles it: on `connectedCallback`, if Content's
`data-state` is already `"open"`, it calls `.showPopover()` once,
which fires this element's own `toggle` handler and continues down the
exact same code path a user click would (see
assets/js/components/popover.js's header). Without JS: `open(true)`
degrades to `open(false)`'s visible behaviour (closed until the Trigger
is activated) -- documented, acceptable regression under adr/0026 rule
4's progressive-enhancement bar, same shape as accordion.pl's own
`collapsible=false` no-JS gap.

**DOM/ARIA contract emitted** (docs/radix-port-analysis.md's "Popover"
entry, adr/0026 rule 2 -- sacred except where noted above):

    Trigger (`<button>`): aria-haspopup="dialog", aria-expanded,
                          aria-controls (Content's id), data-state,
                          PLUS native popovertarget (Content's id,
                          additive -- see "Platform choice" above).
    Content (`<div>`):   role="dialog", id, data-state, data-side,
                          data-align (the popper.js styling contract --
                          same [data-side=...]/[data-align=...] API
                          Radix ships), aria-labelledby/
                          aria-describedby (only when the caller
                          supplies labelledby(_)/describedby(_)),
                          PLUS native popover="auto" (additive -- see
                          above) and data-side-offset/data-align-offset
                          (additive: the markup-level handoff
                          `<px-popover>` reads to drive popper.js's
                          `sideOffset`/`alignOffset`, since there is no
                          upstream-rendered attribute for either --
                          same "DOM-level encoding" justification
                          toggle_group.pl's own extensions use).
    Arrow (`<div>`):     aria-hidden="true" only -- pure CSS-positioned
                          nub keyed off Content's own `[data-side]`
                          (docs/radix-port-analysis.md's own "pure
                          markup, no JS" verdict for Arrow).
    Close (`<button>`):  native popovertarget (Content's id) +
                          popovertargetaction="hide" -- closes with
                          zero JS, same as Trigger's toggle wiring.

Options (plain lists, adr/0026 rule 1):

  `popover_root/2` Opts:
    class(C)        merged with the default class, default first
                    ("px-popover C").
    anything else   passed through verbatim, appended AFTER the
                    computed attributes.

  `popover_trigger/2` Opts:
    open(Bool)      default `false`. Drives `aria-expanded`,
                    `data-state` (open|closed).
    controls(Id)    REQUIRED for a standalone call to actually wire
                    anything (Content's id) -- emitted as BOTH
                    `aria-controls` and the native `popovertarget`.
                    Without it the Trigger still renders (a plain,
                    inert button) rather than throwing -- same
                    graceful-degradation posture as collapsible.pl's
                    own `controls(Id)`.
    class(C), anything else  pass-through, as usual.

  `popover_content/2` Opts:
    open(Bool)      default `false`. Drives `data-state` -- see the
                    "open(true) needs JS" gap above for what this
                    does and does not do without `<px-popover>`.
    id(Id)          this Content's own id -- REQUIRED for
                    `popovertarget` wiring to mean anything; gensym'd
                    by `popover/2` when assembling the common case,
                    but a standalone call must supply one.
    side(top|right|bottom|left)  default `bottom` (Radix's own
                    default). Drives `data-side`, read by
                    `<px-popover>` as popper.js's `side` option.
    align(start|center|end)  default `center` (Radix's own default).
                    Drives `data-align`, read the same way.
    side_offset(N)  default `0` (Radix's own default). Drives
                    `data-side-offset`.
    align_offset(N)  default `0` (Radix's own default). Drives
                    `data-align-offset`.
    labelledby(Id)  emits `aria-labelledby`, when supplied.
    describedby(Id)  emits `aria-describedby`, when supplied.
    class(C), anything else  pass-through, as usual.

  `popover_arrow/1` Opts:
    class(C), anything else  pass-through onto the `<div>`. No other
                    options -- pure markup, positioned entirely by CSS
                    keyed off the parent Content's `[data-side]`.

  `popover_close/1,2` Opts:
    controls(Id)    REQUIRED for a standalone call to actually wire
                    anything (Content's id) -- emitted as the native
                    `popovertarget`, with `popovertargetaction="hide"`.
    class(C), anything else  pass-through, as usual.
                    `popover_close/1` is the no-label shorthand
                    (Children = "×"), `popover_close/2` takes explicit
                    Children.

  `popover/2` Opts: everything `popover_root/2` takes, PLUS
    open(Bool)      default `false`. Forwarded to both Trigger and
                    Content.
    side(_), align(_), side_offset(_), align_offset(_)  forwarded to
                    Content, same defaults as `popover_content/2`.
    id(Id)          optional; base every generated part's id is built
                    from (`<Id>-trigger`/`-content`); gensym'd
                    (`px-popover-N`) when absent, same convention as
                    collapsible.pl's `content_id/2`.

  `popover/2` second argument: `[TriggerChildren, ContentChildren]`
                    (mirrors collapsible.pl's `collapsible/2` Parts
                    shape exactly) -- Content is wrapped with an Arrow
                    automatically (`popover_arrow([])`, appended after
                    ContentChildren) so the common case gets an arrow
                    for free; a caller wanting no arrow, or a Close
                    button inside Content, composes `popover_content/2`
                    directly instead.
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

%!  take_open(+Opts0, -Open, -Rest) is det.
%
%   Same coercing helper as collapsible.pl's/accordion.pl's: anything
%   other than the atom `true` degrades to `false`.
take_open(Opts0, Open, Rest) :-
    (   selectchk(open(O0), Opts0, Rest)
    ->  ( O0 == true -> Open = true ; Open = false )
    ;   Open = false, Rest = Opts0
    ).

%!  take_controls(+Opts0, -ControlsOpt, -Rest) is det.
take_controls(Opts0, ControlsOpt, Rest) :-
    (   selectchk(controls(Id), Opts0, Rest)
    ->  ControlsOpt = controls(Id)
    ;   ControlsOpt = none, Rest = Opts0
    ).

%!  take_labelledby(+Opts0, -LOpt, -Rest) is det.
take_labelledby(Opts0, LOpt, Rest) :-
    (   selectchk(labelledby(Id), Opts0, Rest)
    ->  LOpt = labelledby(Id)
    ;   LOpt = none, Rest = Opts0
    ).

%!  take_describedby(+Opts0, -DOpt, -Rest) is det.
take_describedby(Opts0, DOpt, Rest) :-
    (   selectchk(describedby(Id), Opts0, Rest)
    ->  DOpt = describedby(Id)
    ;   DOpt = none, Rest = Opts0
    ).

%!  take_side(+Opts0, -Side, -Rest) is det.
%
%   Default `bottom` -- Radix's own Popover Content default; an
%   unrecognised value falls back to the default (same guard shape as
%   tabs.pl's take_orientation/3).
take_side(Opts0, Side, Rest) :-
    (   selectchk(side(S0), Opts0, Rest)
    ->  ( valid_side(S0) -> Side = S0 ; Side = bottom )
    ;   Side = bottom, Rest = Opts0
    ).

%!  take_align(+Opts0, -Align, -Rest) is det.
%
%   Default `center` -- Radix's own default.
take_align(Opts0, Align, Rest) :-
    (   selectchk(align(A0), Opts0, Rest)
    ->  ( valid_align(A0) -> Align = A0 ; Align = center )
    ;   Align = center, Rest = Opts0
    ).

%!  take_offset(+Name, +Opts0, -Value, -Rest) is det.
%
%   Generalised over `side_offset`/`align_offset` -- both default `0`
%   (Radix's own defaults for both).
take_offset(Name, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Rest)
    ->  Value = V0
    ;   Value = 0, Rest = Opts0
    ).

%!  state_atom(+Open, -State) is det.
state_atom(true,  open)   :- !.
state_atom(false, closed).

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

%!  popover_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `popover_root([], [Trigger, Content])`.
%   Renders the `<px-popover>` custom-element wrapper (adr/0026 rule 4)
%   around a server-rendered `<div>` -- without JS upgrade, Trigger's
%   native `popovertarget` still fully opens/closes Content (native
%   `popover="auto"` handles dismissal), just unpositioned (Content
%   renders wherever the top layer's UA default places it, no
%   side/align/collision -- see the module header's "Platform choice").
px_template:render_helper(popover_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_popover, [], [div(Attrs, Children)]).

root_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-popover", ClassVal, Opts1),
    append([ [class(ClassVal)], Opts1 ], Attrs).

		 /*******************************
		 *            TRIGGER           *
		 *******************************/

%!  popover_trigger(+Opts, +Children) is det.
%
%   Bare-call template surface: `popover_trigger([open(true),
%   controls(Id)], "Open")`.
px_template:render_helper(popover_trigger(Opts, Children), S) :-
    trigger_attrs(Opts, Attrs),
    px_template:render(S, button(Attrs, Children)).

trigger_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_open(Opts0, Open, Opts1),
    take_controls(Opts1, ControlsOpt, Opts2),
    merge_class(Opts2, "px-popover-trigger", ClassVal, Opts3),
    state_atom(Open, State),
    (   ControlsOpt = controls(Id)
    ->  WireAttrs = [aria_controls(Id), popovertarget(Id)]
    ;   WireAttrs = []
    ),
    append([ [type(button), aria_haspopup(dialog)],
             WireAttrs,
             [aria_expanded(Open), data_state(State), class(ClassVal)],
             Opts3
           ], Attrs).

		 /*******************************
		 *            CONTENT           *
		 *******************************/

%!  popover_content(+Opts, +Children) is det.
%
%   Bare-call template surface: `popover_content([id("p1"), open(true),
%   side(top)], "Hello")`. Renders the native `popover="auto"` +
%   `role="dialog"` panel `<px-popover>` positions -- see the module
%   header for the full split.
px_template:render_helper(popover_content(Opts, Children), S) :-
    content_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, Children)).

content_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_open(Opts0, Open, Opts1),
    take_side(Opts1, Side, Opts2),
    take_align(Opts2, Align, Opts3),
    take_offset(side_offset, Opts3, SideOffset, Opts4),
    take_offset(align_offset, Opts4, AlignOffset, Opts5),
    take_labelledby(Opts5, LOpt, Opts6),
    take_describedby(Opts6, DOpt, Opts7),
    merge_class(Opts7, "px-popover-content", ClassVal, Opts8),
    state_atom(Open, State),
    labelledby_attrs(LOpt, LAttrs),
    describedby_attrs(DOpt, DAttrs),
    append([ [role(dialog), popover(auto)],
             LAttrs, DAttrs,
             [data_state(State), data_side(Side), data_align(Align),
              data_side_offset(SideOffset), data_align_offset(AlignOffset),
              class(ClassVal)
             ],
             Opts8
           ], Attrs).

labelledby_attrs(labelledby(Id), [aria_labelledby(Id)]) :- !.
labelledby_attrs(none, []).

describedby_attrs(describedby(Id), [aria_describedby(Id)]) :- !.
describedby_attrs(none, []).

		 /*******************************
		 *             ARROW            *
		 *******************************/

%!  popover_arrow(+Opts) is det.
%
%   Bare-call template surface: `popover_arrow([])`. Pure markup --
%   positioned entirely by CSS keyed off the parent Content's own
%   `[data-side]` (docs/radix-port-analysis.md's "arrow" entry: "Pure
%   markup; a server-rendered SVG partial, no JS" -- a plain div is
%   used here rather than an SVG partial, same visual result via
%   CSS `transform: rotate(45deg)`, one less asset to vendor).
px_template:render_helper(popover_arrow(Opts), S) :-
    arrow_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, [])).

arrow_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-popover-arrow", ClassVal, Opts1),
    append([ [aria_hidden(true), class(ClassVal)], Opts1 ], Attrs).

		 /*******************************
		 *             CLOSE            *
		 *******************************/

%!  popover_close(+Opts) is det.
%!  popover_close(+Opts, +Children) is det.
%
%   Bare-call template surface: `popover_close([controls(Id)], "Close")`.
%   `popover_close/1` is the no-label shorthand (Children = "×", same
%   `/1` delegates to `/2` shape as tabs.pl's `tabs_trigger/1,2`).
px_template:render_helper(popover_close(Opts), S) :-
    px_template:render_helper(popover_close(Opts, "×"), S).
px_template:render_helper(popover_close(Opts, Children), S) :-
    close_attrs(Opts, Attrs),
    px_template:render(S, button(Attrs, Children)).

close_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_controls(Opts0, ControlsOpt, Opts1),
    merge_class(Opts1, "px-popover-close", ClassVal, Opts2),
    (   ControlsOpt = controls(Id)
    ->  WireAttrs = [popovertarget(Id), popovertargetaction(hide)]
    ;   WireAttrs = []
    ),
    append([ [type(button), aria_label("Close")], WireAttrs, [class(ClassVal)], Opts2 ], Attrs).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  popover(+Opts, +Parts) is det.
%
%   Parts = [TriggerChildren, ContentChildren]. The common case: a Root
%   wrapping one Trigger and one Content (with an Arrow appended
%   automatically), `open(_)` threaded to both, Trigger's
%   `aria-controls`/`popovertarget` wired to Content's `id`
%   automatically -- same division of labour as collapsible.pl's
%   `collapsible/2`.
popover(Opts, Parts) ~> \popover_render(Opts, Parts).

px_template:render_helper(popover_render(Opts, [TriggerKids, ContentKids]), S) :-
    must_be(list, Opts),
    take_open(Opts, Open, _),
    take_side(Opts, Side, _),
    take_align(Opts, Align, _),
    take_offset(side_offset, Opts, SideOffset, _),
    take_offset(align_offset, Opts, AlignOffset, _),
    content_id(Opts, ContentId),
    exclude(convenience_only_opt, Opts, RootOpts),
    TriggerOpts = [open(Open), controls(ContentId)],
    ContentOpts = [ open(Open), id(ContentId), side(Side), align(Align),
                     side_offset(SideOffset), align_offset(AlignOffset)
                   ],
    px_template:render(S,
        popover_root(RootOpts,
          [ popover_trigger(TriggerOpts, TriggerKids),
            popover_content(ContentOpts, [ContentKids, popover_arrow([])])
          ])).

%!  convenience_only_opt(+Opt) is semidet.
%
%   `open(_)`/`side(_)`/`align(_)`/`side_offset(_)`/`align_offset(_)`
%   are Trigger/Content-only concepts (see `popover_render/2` above) --
%   NOT stripped from Root's own pass-through would leak them onto the
%   Root `<div>` as literal, meaningless HTML attributes (`open="true"`,
%   `side="top"`, ...). `id(_)`/`class(_)` are deliberately NOT in this
%   list: Root legitimately carries the base `id` (same convention as
%   tabs.pl's `tabs_render/2` giving Root `id(RootBase)`) and `class(_)`
%   is handled separately by `popover_root/2`'s own `merge_class/4`.
convenience_only_opt(open(_)).
convenience_only_opt(side(_)).
convenience_only_opt(align(_)).
convenience_only_opt(side_offset(_)).
convenience_only_opt(align_offset(_)).

%!  content_id(+Opts, -ContentId) is det.
%
%   `id(Base)` from Opts, suffixed "-content", if the caller supplied
%   one; otherwise a fresh gensym'd id (`px-popover-N-content`) --
%   same convention as collapsible.pl's own `content_id/2`.
content_id(Opts, ContentId) :-
    (   memberchk(id(Base), Opts)
    ->  true
    ;   gensym(px_popover_, Base)
    ),
    format(atom(ContentId), '~w-content', [Base]).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Order 15: the next free slot after accordion.pl's Order 14 (adr/0026
%   rule 8: Popover is the positioning tier's proving consumer,
%   scheduled right after the roving-focus/dialog-adjacent components
%   already landed).
px_ui:demo(popover, 15, \popover_demo).

%   `\popover_demo`, not the bare atom -- same explicit `\Goal` escape
%   every other component's demo template needs (adr/0019: a bare atom
%   is always a text node in render/2's dispatch). A basic popover
%   (title + text + Close button, composed directly via
%   popover_root/popover_trigger/popover_content rather than the `/2`
%   convenience, to fit a Close button inside Content) plus one per
%   side to show placement.
popover_demo ~>
    div(class("px-popover-demo"),
      [ section(class("ui-demo-block"),
          [ h3("Basic -- title, text, Close button"),
            p("Click the trigger: the native popover attribute + popovertarget open/close and light-dismiss (Escape, click-outside) with zero JS; <px-popover> positions the panel below the trigger via lib/popper.js and keeps it positioned across scroll/resize while open."),
            popover_root([],
              [ popover_trigger([controls("popover-demo-basic")], "Open popover"),
                popover_content(
                    [ id("popover-demo-basic"), side(bottom), align(start),
                      side_offset(8), labelledby("popover-demo-basic-title")
                    ],
                    [ popover_arrow([]),
                      h4([id("popover-demo-basic-title")], "Popover title"),
                      p("Rich content lives here -- any markup, same as Radix's own Content."),
                      popover_close([controls("popover-demo-basic")])
                    ])
              ])
          ]),

        h3("Every side, align(center)"),
        p("side(top|right|bottom|left) -- data-side drives both the arrow's CSS direction and, via lib/popper.js, which edge of the trigger the panel is placed against; flip is on by default, so a side without enough viewport room flips to its opposite automatically."),
        div(class("px-popover-sides-row"),
          [ popover_side_demo(top, "Top"),
            popover_side_demo(right, "Right"),
            popover_side_demo(bottom, "Bottom"),
            popover_side_demo(left, "Left")
          ])
      ]).

%!  popover_side_demo(+Side, +Label) is det.
%
%   One popover per side, `side_offset(8)` for a visible gap off the
%   trigger (Radix's own primitive default is 0 -- this demo picks a
%   friendlier value, same as most consumer apps would).
popover_side_demo(Side, Label) ~>
    div(class("px-popover-side-demo-item"), \popover_side_demo_render(Side, Label)).

px_template:render_helper(popover_side_demo_render(Side, Label), S) :-
    format(atom(Id), 'popover-demo-side-~w', [Side]),
    px_template:render(S,
        popover_root([],
          [ popover_trigger([controls(Id)], Label),
            popover_content([id(Id), side(Side), align(center), side_offset(8)],
              [ popover_arrow([]),
                p(["Positioned ", Label, "."])
              ])
          ])).
