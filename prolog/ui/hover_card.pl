:- module(ui_hover_card, []).

%   No predicates are exported: hover_card/2, hover_card_root/2,
%   hover_card_trigger/2, hover_card_content/2 and hover_card_arrow/1
%   are never called module-qualified -- they are term SHAPES that
%   px_template's bare-call dispatch resolves via the multifile
%   px_template:render_helper/2 table (registered below), the same
%   pattern prolog/ui/popover.pl uses.

/** <module> Hover Card (adr/0026): a rich, HOVER-triggered (never
click-, focus- or touch-triggered) preview panel anchored to a link --
e.g. the classic "@handle preview card" -- positioned by
`assets/js/lib/popper.js`, the same shared module `prolog/ui/popover.pl`
proved out.

Ported from Radix UI's HoverCard primitive (docs/radix-port-analysis.md,
"Hover Card" entry). Anatomy (this module's public template surface,
per the analysis doc's own list -- "the simplest anatomy of the overlay
family"): `Root` (`hover_card_root/2`), `Trigger` (`hover_card_trigger/2`,
an `<a>`, NOT a button -- reflects the "preview a link" use case),
`Content` (`hover_card_content/2`), `Arrow` (`hover_card_arrow/1`). No
`Anchor`/`Title`/`Description`/`Close` -- there is nothing to close with
a button (only hover/Escape dismiss this), and no accessible-name
wiring exists to give a Title/Description anything to point at (see the
DOM/ARIA contract below). `hover_card/2` is the rule-1 top-level
convenience: a Root wrapping one Trigger and one Content, `open(_)`
threaded to both, with an Arrow appended to Content automatically --
same division of labour as `popover/2`.

**Anatomy omission (contract deviation, noted per adr/0026 rule 2):**
no `Portal` -- per the analysis doc (and exactly popover.pl's own
"Platform choice" precedent), the native `popover` attribute's
top-layer promotion already gives the stacking-context escape Portal
existed for in React; there is no separate DOM node needed here either.

**DOM/ARIA contract emitted** (docs/radix-port-analysis.md's "Hover
Card" entry, verbatim -- adr/0026 rule 2, sacred): Trigger sets
**only** `data-state` -- deliberately **no** `aria-haspopup`/
`aria-expanded`/`aria-controls` (unlike Popover's Trigger); Content
sets **no `role` at all** (unlike Popover's `role="dialog"` or
Tooltip's future `role="tooltip"`) -- the analysis doc's own words:
"HoverCard content is treated as supplementary/non-essential and
intentionally excluded from the formal ARIA relationship tree". This
is *smaller*, not larger, than Popover's contract -- there is no
extra attribute this port is skipping; Popover's aria-haspopup/
aria-expanded/aria-controls/role genuinely do not apply here.

    Trigger (`<a>`):     data-state ONLY, plus whatever `href`/other
                         attrs the caller passes through (this port
                         renders no default `href` -- see
                         `hover_card_trigger/2` Opts below).
    Content (`<div>`):   NO role, data-state, data-side, data-align
                         (the popper.js styling contract -- same
                         `[data-side=...]`/`[data-align=...]` API
                         popover.pl ships), PLUS native
                         `popover="auto"` (see "Platform choice"
                         below) and data-side-offset/data-align-offset
                         (additive DOM-level handoff to
                         `<px-hover-card>`, same justification as
                         popover.pl's own identical extension).
    Arrow (`<div>`):     aria-hidden="true" only -- pure CSS-positioned
                         nub keyed off Content's own `[data-side]`,
                         identical shape to popover.pl's Arrow.

**Platform choice (adr/0026 rule 3) -- native `popover="auto"` carries
Escape/outside-click dismissal and top-layer stacking; ALL opening/
closing is driven by `<px-hover-card>`'s hover-delay timers, never by
`popovertarget`.** This is the one place this port's platform split
differs from popover.pl's: Popover's Trigger is a `<button
popovertarget>` -- a *click* the browser itself turns into show/hide,
zero JS. HoverCard's Trigger is hover-driven, and **there is no native
"open after N ms of hover" primitive at all** (the analysis doc's own
verdict: "`popover=\"auto\"` gives outside-click/Escape dismiss, but
**zero** hover-delay logic... the entire defining behavior here --
delay timers, hover-bridging -- has no platform analog whatsoever").
So Content still renders native `popover="auto"` (Escape-to-dismiss and
outside-click-to-dismiss are still entirely the browser's job, zero
JS for those two paths), but Trigger renders **no** `popovertarget`
attribute -- opening/closing is exclusively
`assets/js/components/hover_card.js`'s job, calling
`.showPopover()`/`.hidePopover()` from its own delay timers.

**Why `auto`, not `manual` (contrast with `prolog/ui/tooltip.pl`, if it
has landed by the time this reads -- DO NOT edit that module, this note
is comparative only).** Tooltip picks `popover="manual"` because its
content is short, non-interactive hint text with no click-outside
concept at all, and `auto`'s own light-dismiss/stacking behavior would
actively fight hover-only semantics. HoverCard is the opposite case:
the analysis doc's own verdict for THIS component is "`popover=\"auto\"`
gives outside-click/Escape dismiss" -- stated as a benefit, not a
fight -- because HoverCard's Content is rich, often-interactive
preview content (the classic profile card has real links in it); a
user clicking elsewhere on the page has clearly moved on, and Escape/
outside-click dismissing the card immediately is exactly upstream's
own `dismissable-layer` dependency (listed in the analysis doc's Hover
Card entry) earning its keep. One accepted, documented consequence of
`auto`: showing this card will also close any *other* unrelated
`auto` popover currently open elsewhere on the page (the native
same-top-layer-stack rule) -- a page mixing an open Popover and a
hovered HoverCard simultaneously will see the Popover close. This
matches how native `auto` popovers behave everywhere else in this
library (popover.pl's own Content is `auto` too) and is judged an
acceptable, not a fought-against, interaction.

**Without JS, this component never opens at all** (a strictly narrower no-JS
story than Popover's "opens unpositioned" fallback) -- there is no
click/focus/touch fallback to wire, on purpose: upstream Radix's
HoverCard is hover-only *by design*, deliberately excluded from
keyboard and touch interaction (a screen-reader or keyboard user gets
nothing from this component at all, same as upstream -- the
`data-state`-only Trigger contract above is the documented consequence).

**The delay/grace-area port (the actual substance of this component;
docs/radix-port-analysis.md's own words): `openDelay` defaults 700ms,
`closeDelay` 300ms.** Ported faithfully, with two documented,
deliberately narrower omissions -- see
`assets/js/components/hover_card.js`'s own header for the full
mechanics and the grace-area simplification writeup (short version:
**the analysis doc itself says HoverCard has "no gap-tolerance polygon
here -- unlike Tooltip, HoverCard relies purely on delay timers, not
grace-area geometry"** -- so a closeDelay timer canceled by
`pointerover` on Content, exactly what this port implements, is not a
reduced approximation of upstream HoverCard; it IS upstream HoverCard's
actual algorithm. The convex-hull point-in-polygon math belongs to
Tooltip/Menu, ported separately, never to this component).

Options (plain lists, adr/0026 rule 1):

  `hover_card_root/2` Opts:
    open_delay(Ms)  default `700` (Radix's own default). Drives
                    `data-open-delay` on the Root `<div>` --
                    `<px-hover-card>` reads it as the open-timer delay.
    close_delay(Ms) default `300` (Radix's own default). Drives
                    `data-close-delay`, read the same way.
    class(C)        merged with the default class, default first
                    ("px-hover-card C").
    anything else   passed through verbatim, appended AFTER the
                    computed attributes.

  `hover_card_trigger/2` Opts:
    open(Bool)      default `false`. Drives `data-state` (open|closed)
                    ONLY -- see the DOM/ARIA contract above for why
                    there is nothing else here.
    href(Href)      NOT a distinguished option -- pass it like any
                    other pass-through attribute
                    (`hover_card_trigger([href("/u/ada")], "@ada")`).
                    Documented gap: this port does not require or
                    default one (an anchor with no `href` renders but
                    is not a real, keyboard-focusable link) -- a
                    caller previewing a real link is expected to
                    always supply one, same graceful-non-throwing
                    posture as popover.pl's `controls(Id)`.
    class(C), anything else  pass-through, as usual.

  `hover_card_content/2` Opts:
    open(Bool)      default `false`. Drives `data-state`.
    side(top|right|bottom|left)  default `bottom` (Radix's own
                    default). Drives `data-side`, read by
                    `<px-hover-card>` as popper.js's `side` option.
    align(start|center|end)  default `center` (Radix's own default).
                    Drives `data-align`, read the same way.
    side_offset(N)  default `0` (Radix's own default). Drives
                    `data-side-offset`.
    align_offset(N)  default `0` (Radix's own default). Drives
                    `data-align-offset`.
    class(C), anything else  pass-through, as usual. `id(Id)`, if
                    supplied, passes through like any other attribute
                    -- not required for anything (no aria-controls/
                    popovertarget wiring exists for this component).

  `hover_card_arrow/1` Opts:
    class(C), anything else  pass-through onto the `<div>`. No other
                    options -- pure markup, positioned entirely by CSS
                    keyed off the parent Content's `[data-side]`,
                    identical to popover.pl's Arrow.

  `hover_card/2` Opts: everything `hover_card_root/2` takes
                    (`open_delay(_)`/`close_delay(_)` forwarded to
                    Root), PLUS
    open(Bool)      default `false`. Forwarded to both Trigger and
                    Content.
    href(Href)      forwarded to Trigger ONLY (stripped from Root --
                    see `convenience_only_opt/1`). Same documented gap
                    as `hover_card_trigger/2`'s own `href(_)` above.
    side(_), align(_), side_offset(_), align_offset(_)  forwarded to
                    Content, same defaults as `hover_card_content/2`.
    id(Id), class(C)  legitimately Root-level -- NOT stripped, same
                    convention as `popover/2`.

  `hover_card/2` second argument: `[TriggerChildren, ContentChildren]`
                    (mirrors `popover/2`'s Parts shape exactly) --
                    Content is wrapped with an Arrow automatically
                    (`hover_card_arrow([])`, appended after
                    ContentChildren) so the common case gets an arrow
                    for free.
*/

:- use_module(library(lists)).
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
%   Same coercing helper as popover.pl's: anything other than the
%   atom `true` degrades to `false`.
take_open(Opts0, Open, Rest) :-
    (   selectchk(open(O0), Opts0, Rest)
    ->  ( O0 == true -> Open = true ; Open = false )
    ;   Open = false, Rest = Opts0
    ).

%!  take_side(+Opts0, -Side, -Rest) is det.
%
%   Default `bottom` -- Radix's own HoverCard Content default.
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
%   Generalised over `side_offset`/`align_offset` -- both default `0`.
take_offset(Name, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Rest)
    ->  Value = V0
    ;   Value = 0, Rest = Opts0
    ).

%!  take_delay(+Name, +Default, +Opts0, -Value, -Rest) is det.
%
%   Generalised over `open_delay`/`close_delay` -- Radix's own defaults
%   are 700/300ms respectively (passed in by the caller as Default).
take_delay(Name, Default, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Rest)
    ->  Value = V0
    ;   Value = Default, Rest = Opts0
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

%!  hover_card_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `hover_card_root([], [Trigger,
%   Content])`. Renders the `<px-hover-card>` custom-element wrapper
%   (adr/0026 rule 4) around a server-rendered `<div>` carrying the
%   open/close delay handoff -- see the module header's "Platform
%   choice": without `<px-hover-card>` ever loading, Content never
%   opens at all (there is no click/focus/touch fallback path, by
%   upstream design).
px_template:render_helper(hover_card_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_hover_card, [], [div(Attrs, Children)]).

root_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_delay(open_delay, 700, Opts0, OpenDelay, Opts1),
    take_delay(close_delay, 300, Opts1, CloseDelay, Opts2),
    merge_class(Opts2, "px-hover-card", ClassVal, Opts3),
    append([ [class(ClassVal), data_open_delay(OpenDelay), data_close_delay(CloseDelay)],
             Opts3
           ], Attrs).

		 /*******************************
		 *            TRIGGER           *
		 *******************************/

%!  hover_card_trigger(+Opts, +Children) is det.
%
%   Bare-call template surface: `hover_card_trigger([open(true),
%   href("/u/ada")], "@ada")`. Renders an `<a>` -- see the module
%   header's DOM/ARIA contract for why this carries `data-state` and
%   nothing else.
px_template:render_helper(hover_card_trigger(Opts, Children), S) :-
    trigger_attrs(Opts, Attrs),
    px_template:render(S, a(Attrs, Children)).

trigger_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_open(Opts0, Open, Opts1),
    merge_class(Opts1, "px-hover-card-trigger", ClassVal, Opts2),
    state_atom(Open, State),
    append([ [data_state(State), class(ClassVal)], Opts2 ], Attrs).

		 /*******************************
		 *            CONTENT           *
		 *******************************/

%!  hover_card_content(+Opts, +Children) is det.
%
%   Bare-call template surface: `hover_card_content([open(true),
%   side(top)], "Profile preview")`. Renders the native
%   `popover="auto"` panel `<px-hover-card>` opens/closes on its own
%   hover-delay timers and positions via popper.js -- see the module
%   header for the full platform split. Deliberately no `role` (see
%   the DOM/ARIA contract above).
px_template:render_helper(hover_card_content(Opts, Children), S) :-
    content_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, Children)).

content_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_open(Opts0, Open, Opts1),
    take_side(Opts1, Side, Opts2),
    take_align(Opts2, Align, Opts3),
    take_offset(side_offset, Opts3, SideOffset, Opts4),
    take_offset(align_offset, Opts4, AlignOffset, Opts5),
    merge_class(Opts5, "px-hover-card-content", ClassVal, Opts6),
    state_atom(Open, State),
    append([ [popover(auto)],
             [data_state(State), data_side(Side), data_align(Align),
              data_side_offset(SideOffset), data_align_offset(AlignOffset),
              class(ClassVal)
             ],
             Opts6
           ], Attrs).

		 /*******************************
		 *             ARROW            *
		 *******************************/

%!  hover_card_arrow(+Opts) is det.
%
%   Bare-call template surface: `hover_card_arrow([])`. Pure markup,
%   identical shape to popover.pl's Arrow -- positioned entirely by
%   CSS keyed off the parent Content's own `[data-side]`.
px_template:render_helper(hover_card_arrow(Opts), S) :-
    arrow_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, [])).

arrow_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-hover-card-arrow", ClassVal, Opts1),
    append([ [aria_hidden(true), class(ClassVal)], Opts1 ], Attrs).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  hover_card(+Opts, +Parts) is det.
%
%   Parts = [TriggerChildren, ContentChildren]. The common case: a
%   Root wrapping one Trigger and one Content (with an Arrow appended
%   automatically), `open(_)` threaded to both -- same division of
%   labour as `popover/2`. Unlike `popover/2`, there is no
%   Trigger<->Content id wiring to compute (see the module header's
%   DOM/ARIA contract: no aria-controls exists here to wire).
hover_card(Opts, Parts) ~> \hover_card_render(Opts, Parts).

px_template:render_helper(hover_card_render(Opts, [TriggerKids, ContentKids]), S) :-
    must_be(list, Opts),
    take_open(Opts, Open, _),
    take_side(Opts, Side, _),
    take_align(Opts, Align, _),
    take_offset(side_offset, Opts, SideOffset, _),
    take_offset(align_offset, Opts, AlignOffset, _),
    take_href(Opts, HrefAttrs, _),
    exclude(convenience_only_opt, Opts, RootOpts),
    TriggerOpts = [open(Open) | HrefAttrs],
    ContentOpts = [ open(Open), side(Side), align(Align),
                     side_offset(SideOffset), align_offset(AlignOffset)
                   ],
    px_template:render(S,
        hover_card_root(RootOpts,
          [ hover_card_trigger(TriggerOpts, TriggerKids),
            hover_card_content(ContentOpts, [ContentKids, hover_card_arrow([])])
          ])).

%!  take_href(+Opts0, -HrefAttrs, -Rest) is det.
%
%   `href(Href)`, if supplied, forwarded to Trigger as a one-element
%   attribute list; otherwise `[]` -- see the module header's
%   documented "no default href" gap.
take_href(Opts0, HrefAttrs, Rest) :-
    (   selectchk(href(H), Opts0, Rest)
    ->  HrefAttrs = [href(H)]
    ;   HrefAttrs = [], Rest = Opts0
    ).

%!  convenience_only_opt(+Opt) is semidet.
%
%   `open(_)`/`side(_)`/`align(_)`/`side_offset(_)`/`align_offset(_)`/
%   `href(_)` are Trigger/Content-only concepts (see
%   `hover_card_render/2` above) -- NOT stripped, they would leak onto
%   Root's `<div>` as literal, meaningless HTML attributes. `id(_)`/
%   `class(_)`/`open_delay(_)`/`close_delay(_)` are deliberately NOT in
%   this list: Root legitimately carries the base `id`, `class(_)` is
%   handled separately by `hover_card_root/2`'s own `merge_class/4`,
%   and `open_delay(_)`/`close_delay(_)` are genuinely Root-level
%   options `hover_card_root/2` itself consumes.
convenience_only_opt(open(_)).
convenience_only_opt(side(_)).
convenience_only_opt(align(_)).
convenience_only_opt(side_offset(_)).
convenience_only_opt(align_offset(_)).
convenience_only_opt(href(_)).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Order 16: the next free slot after dialog.pl's/popover.pl's Order
%   15 (adr/0026 rule 8: Hover Card is next in the positioning tier,
%   scheduled right after Popover -- "Hover Card, then Tooltip" per
%   the analysis doc's own phase-ordering note).
px_ui:demo(hover_card, 16, \hover_card_demo).

%   `\hover_card_demo`, not the bare atom -- same explicit `\Goal`
%   escape every other component's demo template needs (adr/0019). The
%   classic "@handle" profile-preview card, composed directly via
%   hover_card_root/hover_card_trigger/hover_card_content rather than
%   the `/2` convenience, to fit a richer body (avatar + name + bio +
%   stats) inside Content.
hover_card_demo ~>
    div(class("px-hover-card-demo"),
      [ section(class("ui-demo-block"),
          [ h3("Profile preview -- hover the @handle link"),
            p("Hover (mouse only -- per upstream, this never opens via keyboard focus or touch): after openDelay (700ms) the card fades in below the link, positioned by lib/popper.js; move the pointer onto the card itself and it stays open (pointerover on Content cancels the pending close timer); move away and it closes after closeDelay (300ms). Escape, or a click outside, dismiss it immediately via the native popover=\"auto\" attribute -- zero JS for either."),
            % A `<div>`, NOT a `<p>`, despite reading as prose text --
            % load-bearing, not a style choice: hover_card_content/2
            % renders a `<div>` (Content is never portaled -- see the
            % module header's "no Portal" note), and the HTML parser
            % force-closes an ANCESTOR `<p>` the instant it meets a
            % nested `<div>` (the standard "block content implicitly
            % closes an open p" rule), silently truncating the
            % paragraph and detaching everything after it -- caught by
            % CDP browser verification (adr/0026 rule 7(c): a raw-HTML
            % substring-matching render test cannot see a DOM-parsing
            % defect like this one), not by any string-level test.
            div(class("px-hover-card-demo-prose"),
              [ "Follow ", hover_card_root([],
                  [ hover_card_trigger([href("https://radix-ui.com")], "@radix_ui"),
                    hover_card_content([side(bottom), align(start), side_offset(8)],
                      [ hover_card_arrow([]),
                        div(class("px-hover-card-profile"),
                          [ div(class("px-hover-card-avatar"), "R"),
                            div([],
                              [ h4("Radix UI"),
                                p(class("px-hover-card-handle"), "@radix_ui"),
                                p("Accessible, unstyled UI primitives for building high-quality design systems and web apps."),
                                div(class("px-hover-card-stats"),
                                  [ span([strong("920"), " Following"]),
                                    span([strong("34.2k"), " Followers"])
                                  ])
                              ])
                          ])
                      ])
                  ]), " for updates on the component library."
              ])
          ]),

        h3("Every side, align(center)"),
        p("side(top|right|bottom|left) -- data-side drives both the arrow's CSS direction and, via lib/popper.js, which edge of the trigger the panel is placed against; flip is on by default."),
        div(class("px-hover-card-sides-row"),
          [ hover_card_side_demo(top, "Top"),
            hover_card_side_demo(right, "Right"),
            hover_card_side_demo(bottom, "Bottom"),
            hover_card_side_demo(left, "Left")
          ])
      ]).

%!  hover_card_side_demo(+Side, +Label) is det.
%
%   One hover card per side, `side_offset(8)` for a visible gap off
%   the trigger, same friendlier-than-upstream-default value
%   popover.pl's own side-demo picks.
hover_card_side_demo(Side, Label) ~>
    div(class("px-hover-card-side-demo-item"), \hover_card_side_demo_render(Side, Label)).

px_template:render_helper(hover_card_side_demo_render(Side, Label), S) :-
    px_template:render(S,
        hover_card_root([],
          [ hover_card_trigger([href("#")], Label),
            hover_card_content([side(Side), align(center), side_offset(8)],
              [ hover_card_arrow([]),
                p(["Positioned ", Label, "."])
              ])
          ])).
