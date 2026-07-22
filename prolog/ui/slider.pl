:- module(ui_slider, []).

%   No predicates are exported: slider/1, slider_root/2, slider_track/2,
%   slider_range/1, slider_thumb/1 are never called module-qualified --
%   bare-call dispatch through px_template's tmpl/2 / render_helper/2
%   tables resolves them (adr/0019), the same pattern
%   prolog/ui/switch.pl, prolog/ui/progress.pl and prolog/ui/checkbox.pl
%   use.

/** <module> Slider (adr/0026): drag/keyboard-operable numeric value
    selector -- SINGLE-THUMB variant only (see "Multi-thumb: DEFERRED"
    below).

Ported from Radix UI's Slider primitive (docs/radix-port-analysis.md,
"Slider" entry). Upstream anatomy: `Root` (orientation-dispatching),
`Track`, `Range` (absolutely positioned via computed start/end edge
percentages), `Thumb` (composite: provider context + interactive
trigger span + conditional `BubbleInput`).

**Interactivity class: NATIVE** for single-thumb (the analysis doc's
own verdict): "`<input type=range>` fully covers the single-thumb case
-- native drag, keyboard, min/max/step, real form participation,
styleable via `::-webkit-slider-thumb`/emerging `::thumb`/`::track` --
and should be the default port target for single sliders." This port
takes that literally, the same way switch.pl/checkbox.pl collapse
upstream's Trigger+BubbleInput pair into one real native control:
**Thumb collapses into the native `<input type=range>` itself.**
Rather than a decorative thumb span sitting on top of an invisible
full-track input (switch.pl's technique), the real `<input
type=range>` here IS both the interactive control AND the visible
thumb -- styled directly via `::-webkit-slider-thumb`/`::-moz-range-
thumb` pseudo-elements (checkbox.pl's "style the real control
directly" technique, not switch.pl's "hide the real control, decorate
a sibling" technique), with its own native track backgrounds made
transparent (`::-webkit-slider-runnable-track`/`::-moz-range-track`)
so only the custom thumb knob paints from the input itself. It is
layered exactly over the decorative `Track`/`Range` beneath it (same
absolute bounding box), so the browser's own native thumb-position
math and this port's CSS-var-driven `Range` fill agree pixel-for-pixel
automatically -- no JS position math anywhere, unlike a hand-rolled
thumb would need.

DOM/ARIA contract emitted (the analysis doc's "Slider" entry, adapted
to a native `<input type=range>` per rule 2's "platform-first"
substitution):

    Thumb (-> our native <input>): NO explicit role/aria-valuemin/
              aria-valuenow/aria-valuemax/aria-label -- "aria comes
              native from the range input": a browser already derives
              the accessibility-tree role ("slider") and
              valuemin/valuenow/valuemax from the input's own
              min/max/value attributes for free, matching the analysis
              doc's own "No aria-valuetext anywhere" / "aria-label ...
              else omitted" notes for the single-thumb (1-thumb) case.
              The ONE ARIA attribute this port DOES write explicitly is
              `aria-orientation` -- and, mirroring separator.pl's own
              "horizontal is the ARIA default so it is omitted"
              convention, only when `orientation(vertical)`: unlike
              valuenow/min/max, a browser does not reliably infer
              vertical orientation for a range input from
              `writing-mode` CSS alone, and upstream's own contract
              lists `aria-orientation` on Thumb explicitly, so rule 2's
              "sacred contract" wins here over platform redundancy
              (same tradeoff switch.pl/checkbox.pl make for
              `role`/`aria-checked`) -- but only for the non-default
              value, exactly separator.pl's existing precedent for
              this same ARIA property. `data-orientation` and
              `data-disabled` are mirrored here too (upstream's own
              Thumb contract lists both), plus the native
              `disabled`/`name`/`value`/`min`/`max`/`step` attributes
              that make it a real, independently-functional form
              control.
    Root:     `data-orientation`, `data-disabled` (empty-string, only
              when disabled) -- additive mirrors, same rule-2
              "additive-only" extension switch.pl's/checkbox.pl's Root
              make (upstream's real Root and Thumb are different DOM
              nodes to begin with here, so this isn't even a new
              deviation shape). Also carries the `--slider-value` CSS
              custom property (a bare percentage number, e.g. `42.5`)
              computed server-side from `value`/`min`/`max` -- CSS
              custom properties inherit, so `Range`'s width/height
              formula (`calc(var(--slider-value) * 1%)`) reads it
              straight off Root with no need to repeat it lower down.
    Track:    `data-orientation` mirrored (its own absolute-positioning
              CSS genuinely branches on it -- horizontal fills
              left-to-right, vertical fills bottom-to-top). No
              `data-disabled` of its own: purely decorative dimming
              cascades from `.px-slider[data-disabled] .px-slider-track`
              in assets/css/ui.css rather than duplicating the
              attribute onto two more decorative, non-interactive
              parts (`Track`/`Range`) the way switch.pl/checkbox.pl
              duplicate onto their (interactive) Thumb/Indicator --
              those parts are never independently clickable/focusable,
              so there is nothing for a screen reader or a `:disabled`-
              style pseudo-class to key off there directly.
    Range:    `data-orientation` mirrored, same reasoning as Track. No
              inline `style="width: ..."` the way progress.pl's
              Indicator carries one -- the whole point of the
              `--slider-value` custom property (vs. progress.pl's
              per-render inline percentage) is that a *client-side*
              `input` event, not just a server re-render, can keep it
              live during an in-progress drag; see `<px-slider>` below.

Options (a plain list, adr/0026 rule 1):

    value(V)        the current value; default the midpoint of
                     min/max (`(Min+Max)/2`) -- matches a plain
                     `<input type=range>`'s own implicit default (no
                     `value` attribute at all defaults to the
                     min/max midpoint) and Radix Themes' own basic
                     example, `<Slider defaultValue={[50]} />` against
                     the implicit 0..100 range. Clamped into
                     `[Min,Max]` if out of range.
    min(Min)        default `0` (native `<input type=range>`'s own
                     default, and Radix's).
    max(Max)        default `100` (ditto).
    step(Step)      default `1` (ditto).
    orientation(horizontal|vertical)
                     default `horizontal`; an unrecognised value falls
                     back to the default, same guard shape as
                     separator.pl's `orientation` option.
    disabled(Bool)  default `false`. Adds `data-disabled=""` (mirrored
                     onto Root and Thumb) and the native `disabled`
                     attribute -- which also does the real work of
                     suppressing activation without JS.
    name(N)         the form field name; ABSENT by default (an
                     unnamed range input does not submit, same as
                     switch.pl's/checkbox.pl's `name(_)` convention).
    aria_label(L)   routed to Thumb (the actual accessible element),
                     not Root -- present only when given; this is the
                     port's stand-in for upstream's auto-computed
                     Thumb `aria-label` (">2 thumbs -> 'Value N of M',
                     exactly 2 -> 'Minimum'/'Maximum', else omitted"):
                     since single-thumb always hits the "else omitted"
                     branch, there is nothing to auto-compute here, so
                     a consumer who wants one just supplies it
                     directly.
    class(C)        merged with Root's default class, default first
                     ("px-slider C") -- same convention as every other
                     component in this library; Track/Range/Thumb keep
                     their own fixed classes, not user-overridable.
    anything else (id(...), data_*(...), ...) passed through verbatim
                     to Root, appended AFTER the computed attributes --
                     same last-wins spread order as every other
                     component here.

`<px-slider>` (assets/js/components/slider.js) wraps every instance
(switch.js's always-wrap choice, not checkbox.js's conditional one --
there is no state here that is ever "done and needs no more updates"
the way checkbox's checked/unchecked is once painted; a slider is
mid-interaction the whole time it is being dragged). Its entire job:
listen for the wrapped `<input>`'s native `input` event (fired
continuously while dragging/keying, unlike `change` which only fires
once released/committed) and rewrite Root's `--slider-value` custom
property on every tick, so the decorative `Range` fill tracks the
thumb in real time. The native input's own value/position/keyboard/
drag/focus/aria all keep working with zero JS regardless (rule 4's
progressive-enhancement bar) -- without JS, `--slider-value` simply
freezes at whatever the last server render wrote until the next
request, exactly progress.pl's own "no client JS, value only updates
on reload" story, just for an interactive control instead of a static
one.

`slider_root/2`, `slider_track/2`, `slider_range/1` and `slider_thumb/1`
are registered as `px_template:render_helper/2` hooks (adr/0019) --
the Opts-list defaults/merge/attribute-computation logic below is
genuine computation, so it cannot live in a plain `~>` clause.
`slider/1`, the rule-1 top-level convenience template, IS a plain `~>`:
pure structural delegation assembling Root around one Track (wrapping
one Range) and one Thumb, all fed the same Opts -- same shape as
progress.pl's `progress/1` and switch.pl's `switch/1`.

## Multi-thumb: DEFERRED (honest deferral per this port's brief)

The analysis doc is explicit that multi-thumb has **no native
shortcut**: "native inputs support exactly one thumb; the classic
two-overlapping-inputs hack has real hit-testing breakage (the top
input's hit area swallows pointer events across its whole track, not
just near its own thumb), no native way to render a connecting `Range`
highlight, and no `minStepsBetweenThumbs`/ordering coordination --
multi-thumb sliders need the full custom-element port with no native
shortcut." Port difficulty **L** (vs. **S** for single-thumb), per the
doc's own split rating and adr/0026 rule 8's porting-order note:
"ship the native single-thumb case early ..., treat multi-thumb as a
distinct, later L-effort project." Attempting it as a bolt-on inside
this single-thumb session's scope would mean either a broken hit-test
hack (the exact anti-pattern the analysis doc names) or a rushed,
under-tested collision/keyboard state machine shipped without the CDP
drag-interaction proof adr/0026 rule 7 requires -- an honest deferral
beats a broken ship.

**Future-work API sketch**, for whoever picks this up:

    slider([values([V1,V2,...]), min(Min), max(Max), step(Step),
            min_steps_between_thumbs(N), preserve_order(Bool), ...])

  rendering `slider_root/2` around one `Track`/`Range` (Range now
  spanning between the lowest and highest selected thumb, not from
  `Min`) and *N* `slider_thumb/1` parts -- each now a hand-rolled
  `<span role="slider" tabindex="0" aria-valuemin aria-valuenow
  aria-valuemax aria-orientation data-orientation data-disabled>`
  (Radix's own Thumb shape, no longer backed by a real `<input>`,
  since no native element supports N independent draggable handles),
  plus one hidden multi-value `<input>` (or N hidden inputs) purely for
  `<form>` participation (a real BubbleInput, unlike this single-thumb
  port's collapse). The needed custom element,
  `assets/js/components/slider_range.js` (a distinct
  `<px-slider-range>`, not an extension of this file's `<px-slider>`),
  would own: pointer-capture-driven drag per thumb (pointerdown on a
  thumb focuses it only; pointerdown on the track computes the
  nearest thumb by value-distance and moves it -- the analysis doc's
  own pointer-model note), the two collision strategies verbatim
  (default: re-sort + reject on `minStepsBetweenThumbs` violation;
  opt-in `preserveThumbOrder`: clamp each candidate move to stay
  between its neighbors), and the 4-combination (horizontal
  LTR/RTL x vertical normal/inverted) Home/End/Arrow/PageUp/Down
  keyboard lookup table the analysis doc describes. None of this is
  implemented in this file; `slider/1` here only ever renders one
  Thumb.
*/

:- use_module('../px_template').

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

		 /*******************************
		 *        OPTION HELPERS        *
		 *******************************/

%!  merge_class(+Opts0, +Default, -ClassVal, -Rest) is det.
%
%   Same helper as progress.pl / toggle.pl / switch.pl / checkbox.pl's.
merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  valid_orientation(?O) is semidet.
valid_orientation(horizontal).
valid_orientation(vertical).

%!  take_slider_opts(+Opts0, -Value, -Min, -Max, -Step, -Orientation,
%!                    -Disabled, -NameAttrs, -AriaLabelAttrs, -Rest)
%!  is det.
%
%   Pulls every recognised Slider opt out of Opts0; Rest is everything
%   else, in original relative order (id/class/data_*/... -- Root's
%   pass-through, same spread-order convention as every sibling
%   component). Value is clamped into [Min,Max] once Min/Max are
%   resolved; an out-of-range or absent `value(_)` cannot desync
%   `--slider-value` from what the native input itself would also
%   clamp to.
take_slider_opts(Opts0, Value, Min, Max, Step, Orientation, Disabled,
                  NameAttrs, AriaLabelAttrs, Rest) :-
    (   selectchk(min(Min0), Opts0, Opts1)
    ->  Min = Min0
    ;   Min = 0, Opts1 = Opts0
    ),
    (   selectchk(max(Max0), Opts1, Opts2)
    ->  Max = Max0
    ;   Max = 100, Opts2 = Opts1
    ),
    (   selectchk(value(V0), Opts2, Opts3)
    ->  clamp(V0, Min, Max, Value)
    ;   Value is (Min + Max) / 2, Opts3 = Opts2
    ),
    (   selectchk(step(Step0), Opts3, Opts4)
    ->  Step = Step0
    ;   Step = 1, Opts4 = Opts3
    ),
    (   selectchk(orientation(O0), Opts4, Opts5),
        valid_orientation(O0)
    ->  Orientation = O0
    ;   Orientation = horizontal,
        ( selectchk(orientation(_), Opts4, Opts5) -> true ; Opts5 = Opts4 )
    ),
    (   selectchk(disabled(D0), Opts5, Opts6)
    ->  Disabled = D0
    ;   Disabled = false, Opts6 = Opts5
    ),
    (   selectchk(name(N0), Opts6, Opts7)
    ->  NameAttrs = [name(N0)]
    ;   NameAttrs = [], Opts7 = Opts6
    ),
    (   selectchk(aria_label(L0), Opts7, Opts8)
    ->  AriaLabelAttrs = [aria_label(L0)]
    ;   AriaLabelAttrs = [], Opts8 = Opts7
    ),
    Rest = Opts8.

%!  clamp(+V, +Min, +Max, -Clamped) is det.
clamp(V, Min, _Max, Min)  :- V =< Min, !.
clamp(V, _Min, Max, Max)  :- V >= Max, !.
clamp(V, _,   _,   V).

%!  disabled_attrs(+Disabled, -Attrs) is det.
%
%   `[data_disabled("")]` when Disabled == true, `[]` otherwise --
%   same convention as switch.pl/checkbox.pl.
disabled_attrs(true, [data_disabled("")]) :- !.
disabled_attrs(_,    []).

%!  slider_value_percent(+Value, +Min, +Max, -PctString) is det.
%
%   The `--slider-value` custom property's value: a bare (unitless)
%   percentage number, 2 decimal places, guarded against a degenerate
%   Min == Max (division by zero) by clamping to 0.
slider_value_percent(_, Min, Max, "0.00") :-
    Max =< Min, !.
slider_value_percent(Value, Min, Max, PctString) :-
    Pct is (Value - Min) / (Max - Min) * 100,
    format(string(PctString), "~2f", [Pct]).

		 /*******************************
		 *             PARTS            *
		 *******************************/

%!  slider_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `slider_root([value(30)], Kids)`.
%   Renders the `<px-slider>` custom-element wrapper (adr/0026 rule 4)
%   around a `<div class="px-slider">` (this port's Root) carrying
%   Children (typically one Track and one Thumb).
px_template:render_helper(slider_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_slider, [], [div(Attrs, Children)]).

root_attrs(Opts0, Attrs) :-
    take_slider_opts(Opts0, Value, Min, Max, _Step, Orientation, Disabled,
                      _NameAttrs, _AriaLabelAttrs, Rest0),
    merge_class(Rest0, "px-slider", ClassVal, Rest),
    disabled_attrs(Disabled, DisabledAttrs),
    slider_value_percent(Value, Min, Max, Pct),
    format(string(Style), "--slider-value: ~w;", [Pct]),
    append([ [class(ClassVal), data_orientation(Orientation)],
             DisabledAttrs,
             [style(Style)],
             Rest
           ], Attrs).

%!  slider_track(+Opts, +Children) is det.
%
%   Bare-call template surface: `slider_track([orientation(vertical)],
%   Kids)`. Purely decorative -- no role/aria/data-disabled of its own
%   (see the module header for why).
px_template:render_helper(slider_track(Opts, Children), S) :-
    track_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, Children)).

track_attrs(Opts0, Attrs) :-
    take_slider_opts(Opts0, _Value, _Min, _Max, _Step, Orientation, _Disabled,
                      _NameAttrs, _AriaLabelAttrs, _Rest),
    Attrs = [class("px-slider-track"), data_orientation(Orientation)].

%!  slider_range(+Opts) is det.
%
%   Bare-call template surface: `slider_range([orientation(vertical)])`.
%   No children, no inline style -- its width/height comes purely from
%   CSS reading the inherited `--slider-value` custom property Root
%   writes (see the module header on why that, not an inline style
%   the way progress.pl's Indicator uses, is the point here).
px_template:render_helper(slider_range(Opts), S) :-
    range_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, [])).

range_attrs(Opts0, Attrs) :-
    take_slider_opts(Opts0, _Value, _Min, _Max, _Step, Orientation, _Disabled,
                      _NameAttrs, _AriaLabelAttrs, _Rest),
    Attrs = [class("px-slider-range"), data_orientation(Orientation)].

%!  slider_thumb(+Opts) is det.
%
%   Bare-call template surface: `slider_thumb([value(30)])`. No
%   children -- an `<input>` is a void element. This port's NATIVE
%   substitution for upstream's Thumb (interactive trigger +
%   BubbleInput collapse into one real `<input type=range>`, the same
%   move switch.pl/checkbox.pl make -- see the module header).
px_template:render_helper(slider_thumb(Opts), S) :-
    thumb_attrs(Opts, Attrs),
    px_template:render(S, input(Attrs)).

thumb_attrs(Opts0, Attrs) :-
    take_slider_opts(Opts0, Value, Min, Max, Step, Orientation, Disabled,
                      NameAttrs, AriaLabelAttrs, _Rest),
    disabled_attrs(Disabled, DataDisabledAttrs),
    ( Disabled == true -> DisabledAttr = [disabled] ; DisabledAttr = [] ),
    ( Orientation == vertical -> AriaOrientAttrs = [aria_orientation(vertical)] ; AriaOrientAttrs = [] ),
    append([ [type(range), min(Min), max(Max), step(Step), value(Value)],
             AriaOrientAttrs,
             [data_orientation(Orientation)],
             DataDisabledAttrs,
             [class("px-slider-thumb")],
             DisabledAttr,
             NameAttrs, AriaLabelAttrs
           ], Attrs).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  slider(+Opts) is det.
%
%   The common case: Root around one Track (wrapping one Range) and
%   one Thumb, all fed the same Opts -- same shape as progress.pl's
%   `progress/1` and switch.pl's `switch/1`.
slider(Opts) ~> slider_root(Opts, [slider_track(Opts, [slider_range(Opts)]),
                                    slider_thumb(Opts)]).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Slider is a NATIVE single-thumb form control, same tier as
%   Switch/Toggle/Radio Group/Checkbox (docs/radix-port-analysis.md's
%   recommended order explicitly calls out shipping single-thumb Slider
%   early, "could move up near phase 3") -- Order 12 is the next free
%   slot (1 visually_hidden, 2 accessible_icon, 3 label, 4 separator,
%   5 collapsible, 6 progress, 7 toggle, 8 switch, 9 radio_group/
%   checkbox, 10 aspect_ratio, 11 avatar already registered).
px_ui:demo(slider, 12, \slider_demo).

%   Arity-0, so it is an ATOM -- called via the explicit \ escape, same
%   as every other component's demo template (a bare atom is a text
%   node, not a callable dispatch, in render/2 -- adr/0019).
slider_demo ~>
    div(class("px-slider-demo"),
      [ div(class("px-slider-row"),
          [ p("default -- value(50) (implicit midpoint of 0..100)."),
            slider([id("slider-demo-default")])
          ]),
        div(class("px-slider-row"),
          [ p("value(75), step(5) -- explicit value/step."),
            slider([id("slider-demo-value"), value(75), step(5)])
          ]),
        div(class("px-slider-row"),
          [ p("disabled(true) -- data-disabled=\"\" plus the native disabled attribute; try dragging it."),
            slider([id("slider-demo-disabled"), value(40), disabled(true)])
          ]),
        div(class("px-slider-row px-slider-row-vertical"),
          [ p("orientation(vertical)."),
            slider([id("slider-demo-vertical"), orientation(vertical), value(60)])
          ])
      ]).
