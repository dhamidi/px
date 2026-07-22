:- module(ui_switch, []).

%   No predicates are exported: switch/1, switch_root/2,
%   switch_trigger/1, switch_thumb/1 are never called module-qualified
%   -- bare-call dispatch through px_template's tmpl/2 /
%   render_helper/2 tables resolves them (adr/0019), the same pattern
%   prolog/ui/progress.pl and prolog/ui/toggle.pl use.

/** <module> Switch (adr/0026): boolean on/off toggle, form-integrated.

Ported from Radix UI's Switch primitive (docs/radix-port-analysis.md,
"Switch" entry: "Purpose: boolean on/off toggle, form-integrated.
Structurally Checkbox minus indeterminate."). Upstream anatomy: `Root`,
`Provider`, `Trigger` (button), `Thumb` (span, always rendered -- no
Presence gating), `BubbleInput` (a hidden native `<input
type=checkbox>` only there so a `<button>`-based Root still
participates in `<form>` submission/autofill).

**Interactivity class: NATIVE** (the analysis doc's own verdict):
"`<input type=checkbox>` styled as a switch via `:checked` covers the
entire binary state with zero JS; server-rendered `checked` attribute
plus reload/turbo-frame handles the toggle. JS only buys
instant-visual-flip snappiness." This port takes that literally and
makes the platform-first substitution rule 3 asks for: the actual
control IS a real `<input type=checkbox role="switch">`, not a
`<button>` wrapping a separately-bubbled hidden input --
**`Trigger`/`BubbleInput` collapse into one element**: a native
checkbox already gives real `<form>` participation (submission,
`name`/`value`, autofill, `:required`) for free, so there is nothing
left for a separate `BubbleInput` to bubble. This is the one deviation
from a literal transcription of the anatomy list (adr/0026 rule 2).

DOM/ARIA contract emitted (exactly the analysis doc's "Switch" entry):

    Trigger:  role="switch", aria-checked (plain boolean, no "mixed"),
              aria-required, data-state in checked|unchecked,
              data-disabled="" (empty-string, only when disabled) --
              plus the native `checked`/`disabled`/`required`/`value`/
              `name` attributes that make it a real form control.
    Thumb:    mirrors both data-state and data-disabled (no role/aria
              of its own, same as upstream).

One additive-only extension, noted per rule 2: `Root` (realised here
as a `<label>` wrapping Trigger+Thumb -- see below) ALSO mirrors
data-state/data-disabled, even though the analysis text names only
Trigger and Thumb. Upstream's real Root and Trigger are literally the
same DOM node (the button); this port's Root is a genuinely different
element (the label), introduced so the click-anywhere-toggles behavior
survives replacing that button with an `<input>` (an `<input>` cannot
have children, so the visual Thumb needs a sibling, and *something*
has to be the click target that also happens to cover the Thumb). A
native `<label>` wrapping both gives that for free -- clicking the
label, including the thumb, toggles the wrapped checkbox, zero JS
(the same "for-less" association `prolog/ui/label.pl` documents).
Mirroring data-state/data-disabled onto it is what lets
`assets/css/ui.css` style the *track* (`.px-switch`, this label) the
same data-attribute-keyed way it styles the thumb, per adr/0026 rule
6's "styled track+thumb keyed off data-state" -- additive to the
sacred contract, never contradicting the Trigger/Thumb attributes that
contract already pins down.

Keyboard: none custom (the analysis doc's own note) -- a native
`<input type=checkbox>` gives Space activation for free (unlike
Checkbox, nothing here needs to block Enter either: an unwrapped
checkbox never submits its enclosing form on Enter the way a text
input does).

Options (a plain list, adr/0026 rule 1):

    checked(Bool)   default `false`. Drives `aria-checked`/`data-state`
                    (mirrored onto Root/Thumb too) and the native
                    `checked` attribute.
    disabled(Bool)  default `false`. Adds `data-disabled=""` (mirrored
                    onto Root/Thumb) and the native `disabled`
                    attribute -- which also does the real work of
                    suppressing activation without JS.
    required(Bool)  default `false`. Drives `aria-required` and the
                    native `required` attribute.
    value(V)        the value submitted when checked; default `"on"`
                    (Radix's own default, and the HTML default for a
                    checkbox with no `value` attribute at all).
    name(N)         the form field name; ABSENT by default (an
                    unnamed checkbox does not submit, same as a plain
                    `<input type=checkbox>`).
    class(C)        merged with Root's default class, default first
                    ("px-switch C") -- same convention as every other
                    component in this library; Trigger/Thumb keep
                    their own fixed classes, not user-overridable
                    (same split progress.pl uses between Root and
                    Indicator).
    anything else (id(...), data_*(...), aria_*(...), ...) passed
                    through verbatim to Root, appended AFTER the
                    computed attributes -- same last-wins spread order
                    as every other component here.

`switch_root/2` wraps its Children in the `<px-switch>` custom element
(`assets/js/components/switch.js`, imported from assets/js/app.js via
the importmap, adr/0025) around a `<label>` -- the same wrapper shape
`prolog/ui/toggle.pl`'s `<px-toggle>` established, kept here for
consistency across the library. `<px-switch>`'s entire job is the
platform's one genuine gap: an explicit `aria-checked`/`data-state`
*attribute*, once written, does not update itself just because the
underlying `<input>`'s `checked` *property* flips on click the way a
plain, ARIA-free checkbox's implicit semantics would -- so without JS,
a user's click still genuinely toggles the real checkbox (native
keyboard/pointer activation, focus, and `<form>` submission all keep
working -- adr/0026 rule 4's progressive-enhancement bar), but the
explicit `data-state`/`aria-checked` attributes this contract requires
go stale until the next server render. `<px-switch>` listens for the
wrapped input's `change` event and, on every toggle, rewrites
`aria-checked`/`data-state` on the input and `data-state` on the label
and thumb to match -- purely a same-tick DOM-attribute sync, no
parallel JS store (adr/0026 rule 4), so a later Turbo morph/stream
re-render can never desync from it. Without JS, `<px-switch>` never
upgrades and is a plain unknown inline element around already-correct,
already-functional markup.

`switch_root/2`, `switch_trigger/1` and `switch_thumb/1` are registered
as `px_template:render_helper/2` hooks (adr/0019) -- the Opts-list
defaults/merge/attribute-computation logic below is genuine
computation, so it cannot live in a plain `~>` clause. `switch/1`, the
rule-1 top-level convenience template, IS a plain `~>`: pure structural
delegation assembling Root around one Trigger and one Thumb, all three
fed the same Opts -- Switch's only "context" dependency (the analysis
doc's own note), trivially satisfied by passing the same options to
each part, no shared client state needed, same as Progress's
value/max. `use-size`, Switch's other declared dependency, is likewise
not needed here: it exists upstream only to keep BubbleInput's hidden
`<input>` correctly sized to the visible Root/Trigger button via
`ResizeObserver`; this port has no separate BubbleInput to size in the
first place (the collapse above), so there is nothing left for
`use-size` to do.
*/

:- use_module('../px_template').

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

		 /*******************************
		 *        OPTION HELPERS        *
		 *******************************/

%!  take_bool(+Name, +Opts0, -Value, -Rest) is det.
%
%   Pulls Name(Value) out of Opts0 (default `false` if absent). Same
%   helper as toggle.pl's.
take_bool(Name, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Opts1)
    ->  Value = V0
    ;   Value = false, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  take_switch_opts(+Opts0, -Checked, -Disabled, -Required, -Value,
%!                    -NameAttrs, -Rest) is det.
%
%   Pulls the five state/form opts out of Opts0; Rest is everything
%   else, in original relative order (id/class/data_*/... -- Root's
%   pass-through). NameAttrs is `[name(N)]` when `name(N)` was given,
%   `[]` otherwise (an unnamed checkbox does not submit, same as plain
%   HTML).
take_switch_opts(Opts0, Checked, Disabled, Required, Value, NameAttrs, Rest) :-
    take_bool(checked, Opts0, Checked, Opts1),
    take_bool(disabled, Opts1, Disabled, Opts2),
    take_bool(required, Opts2, Required, Opts3),
    (   selectchk(value(V0), Opts3, Opts4)
    ->  Value = V0
    ;   Value = "on", Opts4 = Opts3
    ),
    (   selectchk(name(N0), Opts4, Opts5)
    ->  NameAttrs = [name(N0)]
    ;   NameAttrs = [], Opts5 = Opts4
    ),
    Rest = Opts5.

%!  merge_class(+Opts0, +Default, -ClassVal, -Rest) is det.
%
%   Same helper as progress.pl / toggle.pl's.
merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  switch_state(+Checked, -State) is det.
%
%   State in checked|unchecked -- Radix's `data-state={checked ?
%   "checked" : "unchecked"}`.
switch_state(true, checked) :- !.
switch_state(_,    unchecked).

%!  aria_checked_word(+State, -Word) is det.
%
%   Word in true|false, derived from the already-normalised State so
%   `aria-checked` and `data-state` can never disagree, even for a
%   caller-supplied `checked(_)` value that is neither `true` nor
%   `false`.
aria_checked_word(checked,   true).
aria_checked_word(unchecked, false).

%!  disabled_attrs(+Disabled, -Attrs) is det.
%
%   `[data_disabled("")]` when Disabled == true, `[]` otherwise --
%   empty-string, not `"true"`, same convention as Checkbox/Toggle
%   (docs/radix-port-analysis.md spells it out explicitly).
disabled_attrs(true, [data_disabled("")]) :- !.
disabled_attrs(_,    []).

		 /*******************************
		 *             PARTS            *
		 *******************************/

%!  switch_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `switch_root([checked(true)], Kids)`.
%   Renders the `<px-switch>` custom-element wrapper (adr/0026 rule 4)
%   around a `<label>` (this port's Root -- see the module header for
%   why a label, not upstream's button) carrying Children (typically
%   one Trigger and one Thumb).
px_template:render_helper(switch_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_switch, [], [label(Attrs, Children)]).

root_attrs(Opts0, Attrs) :-
    take_switch_opts(Opts0, Checked, Disabled, _Required, _Value, _NameAttrs, Rest0),
    merge_class(Rest0, "px-switch", ClassVal, Rest),
    switch_state(Checked, State),
    disabled_attrs(Disabled, DisabledAttrs),
    append([ [class(ClassVal), data_state(State)],
             DisabledAttrs,
             Rest
           ], Attrs).

%!  switch_trigger(+Opts) is det.
%
%   Bare-call template surface: `switch_trigger([checked(true)])`. No
%   children -- an `<input>` is a void element. Carries the entire
%   ARIA/data contract the analysis doc pins to "Trigger", plus the
%   native attributes (`type`, `checked`, `disabled`, `required`,
%   `value`, `name`) that make it a real, independently-functional
%   form control (this port's NATIVE substitution for upstream's
%   separate Trigger+BubbleInput pair -- see the module header).
px_template:render_helper(switch_trigger(Opts), S) :-
    trigger_attrs(Opts, Attrs),
    px_template:render(S, input(Attrs)).

trigger_attrs(Opts0, Attrs) :-
    take_switch_opts(Opts0, Checked, Disabled, Required, Value, NameAttrs, _Rest),
    switch_state(Checked, State),
    aria_checked_word(State, CheckedWord),
    disabled_attrs(Disabled, DataDisabledAttrs),
    (   Checked == true  -> CheckedAttr  = [checked]  ; CheckedAttr  = [] ),
    (   Disabled == true -> DisabledAttr = [disabled] ; DisabledAttr = [] ),
    (   Required == true -> RequiredAttr = [required] ; RequiredAttr = [] ),
    append([ [type(checkbox), role(switch)],
             [aria_checked(CheckedWord), aria_required(Required)],
             [data_state(State)],
             DataDisabledAttrs,
             [class("px-switch-trigger")],
             CheckedAttr, DisabledAttr, RequiredAttr,
             NameAttrs, [value(Value)]
           ], Attrs).

%!  switch_thumb(+Opts) is det.
%
%   Bare-call template surface: `switch_thumb([checked(true)])`. No
%   children -- Radix's Thumb never has any either; always rendered,
%   no Presence gating (the analysis doc's own note -- unlike
%   Checkbox's Indicator).
px_template:render_helper(switch_thumb(Opts), S) :-
    thumb_attrs(Opts, Attrs),
    px_template:render(S, span(Attrs, [])).

thumb_attrs(Opts0, Attrs) :-
    take_switch_opts(Opts0, Checked, Disabled, _Required, _Value, _NameAttrs, _Rest),
    switch_state(Checked, State),
    disabled_attrs(Disabled, DisabledAttrs),
    append([ [data_state(State), class("px-switch-thumb")],
             DisabledAttrs
           ], Attrs).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  switch(+Opts) is det.
%
%   The common case: Root around one Trigger and one Thumb, all three
%   fed the same Opts -- same shape as progress.pl's `progress/1`.
switch(Opts) ~> switch_root(Opts, [switch_trigger(Opts), switch_thumb(Opts)]).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Switch is a Phase-3 "native-backed form control" (docs/radix-port-
%   analysis.md's recommended order: Switch, Toggle, Radio Group,
%   Checkbox) -- Order 9 is the next free slot (1 visually_hidden, 2
%   accessible_icon, 3 label, 4 separator, 5 collapsible, 6 progress, 7
%   toggle, 8 radio_group, 10 aspect_ratio, 11 avatar already
%   registered); textually landing after Toggle/Radio Group rather
%   than ahead of them as the doc's prose lists them is a harmless
%   ordering nit, not a contract deviation.
px_ui:demo(switch, 9, \switch_demo).

%   Arity-0, so it is an ATOM -- called via the explicit \ escape, same
%   as every other component's demo template (a bare atom is a text
%   node, not a callable dispatch, in render/2 -- adr/0019).
switch_demo ~>
    div(class("px-switch-demo"),
      [ div(class("px-switch-row"),
          [ switch([id("switch-demo-off")]),
            p("checked(false) (default) -- aria-checked=\"false\", data-state=\"unchecked\".")
          ]),
        div(class("px-switch-row"),
          [ switch([id("switch-demo-on"), checked(true)]),
            p("checked(true) -- aria-checked=\"true\", data-state=\"checked\".")
          ]),
        div(class("px-switch-row"),
          [ switch([id("switch-demo-disabled"), disabled(true)]),
            p("disabled(true) -- data-disabled=\"\" plus the native disabled attribute; try clicking it.")
          ]),
        div(class("px-switch-row"),
          [ switch([id("switch-demo-form"), name("notifications"),
                    required(true)]),
            p("name(\"notifications\") + required(true) -- real name/value/required on the underlying <input>, so it participates in an ancestor <form>, validation included, with zero JS.")
          ])
      ]).
