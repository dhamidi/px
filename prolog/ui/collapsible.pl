:- module(ui_collapsible, []).

%   No predicates are exported: collapsible/2, collapsible_root/2,
%   collapsible_trigger/2 and collapsible_content/2 are never called
%   module-qualified -- they are term SHAPES that px_template's
%   bare-call dispatch resolves via the multifile
%   px_template:render_helper/2 table (registered below), the same
%   pattern prolog/ui/progress.pl and prolog/ui/separator.pl use.

/** <module> Collapsible (adr/0026): single show/hide disclosure region.

Ported from Radix UI's Collapsible primitive (docs/radix-port-analysis.md,
"Collapsible" entry). Anatomy: `Root` (`collapsible_root/2`), `Trigger`
(`collapsible_trigger/2`), `Content` (`collapsible_content/2`);
`collapsible/2` is the rule-1 top-level convenience assembling the
common case: a Root wrapping one Trigger and one Content, `open(_)`/
`disabled(_)` threaded to all three.

**Platform choice (adr/0026 rule 3).** The analysis doc calls
Collapsible "NATIVE-capable with real gaps": `<details>`/`<summary>`
gives zero-JS open/closed disclosure with a real `open` attribute
settable server-side, for the *static* case (no smooth animation --
see Gaps below). This port takes that path: `Root` renders `<details>`,
`Trigger` renders `<summary>` (browsers already give it the disclosure-
triangle affordance and button semantics for free), and `Content`
renders a plain `<div>` -- the child that lives after `<summary>`
inside `<details>`, whose visibility the browser already fully owns via
the `open` attribute; no other DOM structure is needed to get show/hide
working with zero JS. `open(true/false)` (default `false`) maps
directly to the native `open` boolean attribute on `<details>`.

**Contract emitted** (docs/radix-port-analysis.md's "Collapsible"
entry, adr/0026 rule 2 -- sacred except where noted below):

    Root (`<details>`):     data-state ∈ open|closed, data-disabled
                             (`""`, empty-string, present only when
                             disabled -- same convention as Switch/
                             Checkbox's `data-disabled=""` per the
                             analysis doc), native `open`.
    Trigger (`<summary>`):  aria-controls (Content's id; only emitted
                             while open, per the analysis doc's "only
                             set while open" -- a literal upstream
                             quirk, kept as-is), aria-expanded (always,
                             "true"/"false"), data-state, data-disabled.
    Content (`<div>`):      data-state, data-disabled, id (matches
                             Trigger's aria-controls when supplied via
                             the `controls(Id)` option -- see
                             `collapsible/2` below for how the
                             convenience wires the two together).

**Contract deviation (rule 2, documented as required):** Content's
`hidden={!open}` from upstream Radix is deliberately **NOT** emitted.
Layering a *static*, render-time `hidden` attribute on top of a native
`<details>` would work only for the very first render: the browser
owns `<details>`'s open/closed visibility entirely itself (toggling
`open` on user click, no JS involved), but it does **not** touch a
descendant's independent `hidden` attribute when it does -- so a
content div rendered `hidden` for an initially-closed disclosure would
stay `hidden="hidden"` (and thus invisible) even after the user natively
reopens it, permanently breaking the component. Native `<details>`
visibility and an explicit `hidden` attribute are two independent
mechanisms; only one may safely drive this element, and the native one
is strictly more correct here since it is the one the browser actually
keeps in sync with user interaction.

**Disabled handling (no contract entry for a native disabled
mechanism):** unlike `<button>`/`<input>`, `<summary>` has no `disabled`
attribute -- there is no native way to block a disclosure toggle. This
port's best-effort, JS-free mitigation: when `disabled(true)`,
`Trigger` additionally gets `tabindex="-1"` (removes it from the tab
order, blocking keyboard activation) and assets/css/ui.css pairs
`[data-disabled]` with `pointer-events: none` (blocks pointer
activation) plus a dimmed visual treatment. Together these fully block
interaction without JS, though neither is part of upstream Radix's own
attribute contract, so they are additive, not a substitution for it.

**Gaps versus Radix (future work, adr/0026 rule 3 -- documented, not
shipped as JS):**

  1. **No smooth open/close animation.** Radix measures Content's
     height/width via `getBoundingClientRect()` (transitions briefly
     disabled during measurement) and exposes
     `--radix-collapsible-content-height/-width` CSS vars so consumer
     CSS can animate to/from an a-priori-unknown size. `<details>` has
     no such hook: it shows/hides content abruptly. Closing this gap
     needs a small custom element (`assets/js/components/collapsible.js`,
     not written here per adr/0026 rule 4's "irreducible behavior
     only" bar) that measures Content on toggle and writes the same
     CSS vars.
  2. **No controlled-state sync after native interaction.** Every
     attribute this module emits (`data-state`, `aria-expanded`,
     `aria-controls`, `data-disabled`) is computed ONCE, server-side,
     from the `open(_)`/`disabled(_)` options at render time. When a
     user clicks `<summary>`, the browser flips `<details>`'s `open`
     attribute entirely on its own -- our other, statically-rendered
     attributes do NOT follow it (there is no JS here to listen for
     the native `toggle` event and mirror `data-state`/`aria-expanded`
     back onto Root/Trigger/Content). Upstream Radix never has this
     problem because React re-renders from state on every change. A
     future custom element wrapping the rendered markup, listening for
     `toggle` on its `<details>`, is the natural place to close this
     gap (and #1's animation measurement) at the same time -- not
     needed for the static open/closed case this port targets.

Options (a plain list, adr/0026 rule 1), recognised by all three parts:

    open(true|false)      default `false`. Root: native `open` boolean
                           attribute. All three parts: drives
                           data-state (open|closed).
    disabled(true|false)  default `false`. All three parts: drives
                           data-disabled ("", only when true). Trigger
                           additionally gets tabindex="-1" (see above).
    class(C)              merged with the part's own default class,
                           default first ("px-collapsible C", etc).
    anything else         (id(...), data_*(...), ...) passed through
                           verbatim, appended AFTER the computed
                           attributes -- same last-wins order as
                           progress.pl/separator.pl.

`Trigger` additionally recognises `controls(Id)`: the id of the
Content it discloses, emitted as `aria-controls` (only while open, per
the contract above). Not a Radix prop -- Radix's Trigger reads this off
context internally; here, since there is no context, `collapsible/2`
(below) is what supplies it when assembling the common case.

`collapsible/2`'s forwarding rule (mirrors progress.pl's
`progress/1`'s "value/max only" precedent): the full Opts list --
including `id(...)`/`class(...)`/anything else -- goes to Root; only
`open(_)`/`disabled(_)` are forwarded to Trigger and Content, plus the
auto-derived `controls(_)`/`id(_)` pair that links them (Content's id
is `id(_)` from Opts if supplied, suffixed `-content`; otherwise a
fresh gensym'd id). Callers who need independent per-part `class`/`id`
customisation call `collapsible_root/2`, `collapsible_trigger/2` and
`collapsible_content/2` directly instead.
*/

:- use_module('../px_template').
:- use_module(library(lists)).
:- use_module(library(gensym)).

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

		 /*******************************
		 *        OPTION HELPERS        *
		 *******************************/

%!  take_open(+Opts0, -Open, -Rest) is det.
%
%   Pulls `open(true|false)` out of Opts0 (default `false`); anything
%   other than the atom `true` counts as not-open, matching how
%   `is_determinate/3` in progress.pl treats "anything unexpected
%   degrades to the safe default" rather than erroring.
take_open(Opts0, Open, Rest) :-
    (   selectchk(open(O0), Opts0, Rest)
    ->  ( O0 == true -> Open = true ; Open = false )
    ;   Open = false, Rest = Opts0
    ).

%!  take_disabled(+Opts0, -Disabled, -Rest) is det.
take_disabled(Opts0, Disabled, Rest) :-
    (   selectchk(disabled(D0), Opts0, Rest)
    ->  ( D0 == true -> Disabled = true ; Disabled = false )
    ;   Disabled = false, Rest = Opts0
    ).

%!  take_controls(+Opts0, -ControlsOpt, -Rest) is det.
%
%   ControlsOpt = controls(Id), or `none` if absent.
take_controls(Opts0, ControlsOpt, Rest) :-
    (   selectchk(controls(Id), Opts0, Rest)
    ->  ControlsOpt = controls(Id)
    ;   ControlsOpt = none, Rest = Opts0
    ).

%!  state_atom(+Open, -State) is det.
state_atom(true,  open)   :- !.
state_atom(false, closed).

%!  disabled_attrs(+Disabled, -Attrs) is det.
%
%   `data-disabled=""` when true (empty-string, matching Switch/
%   Checkbox's documented convention), nothing at all otherwise.
disabled_attrs(true,  [data_disabled("")]) :- !.
disabled_attrs(false, []).

%!  merge_class(+Opts0, +Default, -ClassVal, -Rest) is det.
%
%   Same pattern as progress.pl: pulls class(C) out of Opts0 if
%   present and merges it after Default; Rest is Opts0 minus class(_).
merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C]),
        Rest = Opts1
    ;   ClassVal = Default, Rest = Opts0
    ).

		 /*******************************
		 *             PARTS            *
		 *******************************/

%!  collapsible_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `collapsible_root([open(true)], Kids)`.
px_template:render_helper(collapsible_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render(S, details(Attrs, Children)).

root_attrs(Opts0, Attrs) :-
    take_open(Opts0, Open, Opts1),
    take_disabled(Opts1, Disabled, Opts2),
    merge_class(Opts2, "px-collapsible", ClassVal, Opts3),
    state_atom(Open, State),
    disabled_attrs(Disabled, DisabledAttrs),
    ( Open == true -> OpenAttrs = [open] ; OpenAttrs = [] ),
    append([ [data_state(State)],
             DisabledAttrs,
             [class(ClassVal)],
             OpenAttrs,
             Opts3
           ], Attrs).

%!  collapsible_trigger(+Opts, +Children) is det.
%
%   Bare-call template surface:
%   `collapsible_trigger([open(true), controls(Id)], "Toggle")`.
px_template:render_helper(collapsible_trigger(Opts, Children), S) :-
    trigger_attrs(Opts, Attrs),
    px_template:render(S, summary(Attrs, Children)).

trigger_attrs(Opts0, Attrs) :-
    take_open(Opts0, Open, Opts1),
    take_disabled(Opts1, Disabled, Opts2),
    take_controls(Opts2, ControlsOpt, Opts3),
    merge_class(Opts3, "px-collapsible-trigger", ClassVal, Opts4),
    state_atom(Open, State),
    (   Open == true, ControlsOpt = controls(Id)
    ->  ControlsAttrs = [aria_controls(Id)]
    ;   ControlsAttrs = []
    ),
    disabled_attrs(Disabled, DisabledAttrs),
    ( Disabled == true -> TabAttrs = [tabindex(-1)] ; TabAttrs = [] ),
    append([ ControlsAttrs,
             [aria_expanded(Open)],
             [data_state(State)],
             DisabledAttrs,
             [class(ClassVal)],
             TabAttrs,
             Opts4
           ], Attrs).

%!  collapsible_content(+Opts, +Children) is det.
%
%   Bare-call template surface:
%   `collapsible_content([open(true), id(Id)], "...")`. No `hidden`
%   attribute -- see the module header's documented contract
%   deviation.
px_template:render_helper(collapsible_content(Opts, Children), S) :-
    content_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, Children)).

content_attrs(Opts0, Attrs) :-
    take_open(Opts0, Open, Opts1),
    take_disabled(Opts1, Disabled, Opts2),
    merge_class(Opts2, "px-collapsible-content", ClassVal, Opts3),
    state_atom(Open, State),
    disabled_attrs(Disabled, DisabledAttrs),
    append([ [data_state(State)],
             DisabledAttrs,
             [class(ClassVal)],
             Opts3
           ], Attrs).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  collapsible(+Opts, +Parts) is det.
%
%   Parts = [TriggerChildren, ContentChildren]. The common case: a
%   Root wrapping one Trigger and one Content, `open(_)`/`disabled(_)`
%   threaded to all three, Trigger's `aria-controls` wired to
%   Content's `id` automatically (see the module header's forwarding
%   rule for exactly what is/isn't forwarded).
collapsible(Opts, Parts) ~> \collapsible_render(Opts, Parts).

px_template:render_helper(collapsible_render(Opts, [TriggerKids, ContentKids]), S) :-
    take_open(Opts, Open, _),
    take_disabled(Opts, Disabled, _),
    content_id(Opts, ContentId),
    TriggerOpts = [open(Open), disabled(Disabled), controls(ContentId)],
    ContentOpts = [open(Open), disabled(Disabled), id(ContentId)],
    px_template:render(S,
        collapsible_root(Opts,
          [ collapsible_trigger(TriggerOpts, TriggerKids),
            collapsible_content(ContentOpts, ContentKids)
          ])).

%!  content_id(+Opts, -ContentId) is det.
%
%   `id(Base)` from Opts, suffixed "-content", if the caller supplied
%   one; otherwise a fresh gensym'd id (`px-collapsible-N-content`) --
%   uniqueness across multiple collapsibles rendered on the same page
%   without explicit ids, upstream Radix's own `useId()` role here.
content_id(Opts, ContentId) :-
    (   memberchk(id(Base), Opts)
    ->  true
    ;   gensym(px_collapsible_, Base)
    ),
    format(atom(ContentId), '~w-content', [Base]).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Order 5: the analysis doc's recommended porting order places
%   Collapsible right after the phase-1 foundations (AspectRatio=10,
%   Label=3, Separator=4, VisuallyHidden=1, AccessibleIcon=2,
%   Progress=6) and before Accordion, which is built on it.
px_ui:demo(collapsible, 5, \collapsible_demo).

%   `\collapsible_demo`, not the bare atom -- px_ui embeds it as the
%   sole Children argument of a div (ui_show_view in prolog/px_ui.pl),
%   and a bare ATOM is always a text node in px_template's dispatch
%   (adr/0019); the explicit `\Goal` escape is what makes it a
%   template call instead, same as every other component's demo.
collapsible_demo ~>
    div(class("px-collapsible-demo"),
      [ section(class("ui-demo-block"),
          [ h3("Closed by default"),
            p("open(false) (the default): data-state=\"closed\" throughout, no native `open` attribute, no aria-controls on the trigger (only set while open, per the upstream contract)."),
            collapsible([id("collapsible-demo-closed")],
              [ "What is prologex?",
                p("A batteries-included Prolog web framework: px_template for streaming server-rendered HTML, px_router for routing, and px_ui -- this very component library -- ported from Radix UI.")
              ])
          ]),
        section(class("ui-demo-block"),
          [ h3("Initially open"),
            p("open(true): data-state=\"open\", native `open` on the <details>, aria-expanded=\"true\" and aria-controls pointing at the content's id."),
            collapsible([id("collapsible-demo-open"), open(true)],
              [ "Why <details>/<summary>?",
                p("Zero-JS disclosure with a real, server-settable `open` attribute -- docs/radix-port-analysis.md flags it as the native path for Collapsible's static case; see this module's header for the gaps versus upstream Radix (animation, controlled-state sync) left as documented future work.")
              ])
          ])
      ]).
