:- module(ui_checkbox, []).

%   No predicates are exported: checkbox/1, checkbox_root/2,
%   checkbox_input/1, checkbox_indicator/1 are never called
%   module-qualified -- bare-call dispatch through px_template's
%   tmpl/2 / render_helper/2 tables resolves them (adr/0019), the same
%   pattern prolog/ui/switch.pl and prolog/ui/toggle.pl use.

/** <module> Checkbox (adr/0026): tri-state (checked/unchecked/
    indeterminate) toggle, form-integrated.

Ported from Radix UI's Checkbox primitive (docs/radix-port-analysis.md,
"Checkbox" entry). Upstream anatomy: `Root` (composite), `Provider`,
`Trigger` (button, `role="checkbox"`), `Indicator` (span,
Presence-gated), `BubbleInput` (a hidden native `<input
type=checkbox>` only there so a `<button>`-based Root still
participates in `<form>` submission/autofill/`change` events).

**Interactivity class: NATIVE for 2-state; CUSTOM-ELEMENT for
indeterminate** -- the analysis doc's own verdict, and, unlike Switch's
undivided "NATIVE", it draws an explicit line: "`<input type=checkbox>`
+ `:checked` CSS covers checked/unchecked with zero JS ... The gap:
`.indeterminate` is a JS-only DOM property with no HTML attribute ...
so indeterminate ... needs a small custom element ... to set
`.indeterminate` and `aria-checked="mixed"` after render." This port
takes rule 3's platform-first substitution the same way
prolog/ui/switch.pl does -- **`Trigger`/`BubbleInput` collapse into one
real `<input type=checkbox role="checkbox">`** (a native checkbox
already gives real `<form>` participation for free, so there is
nothing left for a separate `BubbleInput` to bubble) -- but then
DIVERGES from switch.pl's choice to always wrap in a custom element:
`checkbox_root/2` only reaches for `<px-checkbox>`
(`assets/js/components/checkbox.js`) when the *initial* state is
`indeterminate`. A plain checked/unchecked Checkbox therefore ships
with **no custom element at all**: the box's background/border still
flip instantly on click via the native `:checked` pseudo-class
(assets/css/ui.css), zero JS -- only the Presence-gated Indicator's
glyph and the `data-state`/`aria-checked` *attributes* go stale until
the next server render without JS, the same progressive-enhancement
bar prolog/ui/toggle.pl's and prolog/ui/switch.pl's own JS-dependent
slivers already accept, drawn one native limitation further out here
because the analysis doc itself only asks for JS in the indeterminate
case.

DOM/ARIA contract emitted (exactly the analysis doc's "Checkbox"
entry):

    Trigger (-> our native <input>): role="checkbox", aria-checked
              ("mixed" when indeterminate, else the plain boolean
              word), aria-required, data-state in
              indeterminate|checked|unchecked, data-disabled=""
              (empty-string, only when disabled) -- plus the native
              checked/disabled/required/value/name attributes that
              make it a real, independently-functional form control.
              `role="checkbox"` and `aria-checked` are written
              explicitly even though a native `<input type=checkbox>`
              already carries correct implicit checkbox semantics for
              the checked/unchecked cases on its own -- same choice
              switch.pl makes for `role="switch"`/`aria-checked`
              (rule 2's "sacred" contract wins over platform
              redundancy); the ONE case where the explicit
              `aria-checked="mixed"` is not just belt-and-braces but
              load-bearing is indeterminate, per the analysis doc's own
              gap note quoted above.
    Indicator:  data-state, data-disabled -- mirrors the same pair, no
                role/aria of its own (same as upstream). Presence-gated
                (upstream's own anatomy note, UNLIKE Switch's
                always-rendered Thumb): `checkbox/1`'s convenience only
                includes it in Root's children when the state is
                `checked` or `indeterminate`; calling `checkbox_indicator/1`
                directly always mounts it (upstream's `forceMount`
                escape hatch), computing whatever data-state/
                data-disabled its own Opts describe.

One additive-only extension, noted per rule 2 (same one switch.pl
makes): `Root` (realised here as a `<label>` wrapping Trigger and,
when present, Indicator) ALSO mirrors `data-state`/`data-disabled`,
even though the analysis text only names Trigger and Indicator.
Upstream's real Root and Trigger are the same DOM node (the button);
this port's Root is a genuinely different element (the label),
introduced for exactly the reason switch.pl's Root is: an `<input>`
cannot have children, so the Indicator needs a sibling, and *something*
has to be the click target that also covers it. A native `<label>`
wrapping both gives click-anywhere-toggles for free, zero JS -- the
same "for-less" association prolog/ui/label.pl documents.

Keyboard: Space toggles via native `<input type=checkbox>` semantics,
free. Enter is a non-issue for an unwrapped checkbox (it never submits
an ancestor `<form>` the way a text input does), so there is nothing
here to `preventDefault()` -- unlike a hand-rolled `role=checkbox`
button, a native input needs no keyboard code of its own at all.

Options (a plain list, adr/0026 rule 1):

    checked(V)      `true`, `false`, or `indeterminate` -- mirrors
                    Radix's own `CheckedState = boolean | "indeterminate"`
                    type directly as one option instead of two.
                    Default `false`. Any other value is treated as
                    `false` (same "fall back to the default" guard
                    separator.pl's `orientation` option uses).
    disabled(Bool)  default `false`. Adds `data-disabled=""` (mirrored
                    onto Root/Indicator) and the native `disabled`
                    attribute -- which also does the real work of
                    suppressing activation without JS.
    required(Bool)  default `false`. Drives `aria-required` (always
                    present, boolean-valued -- switch.pl's convention)
                    and the native `required` attribute.
    value(V)        the value submitted when checked; default `"on"`
                    (Radix's own default, and the HTML default for a
                    checkbox with no `value` attribute at all).
    name(N)         the form field name; ABSENT by default (an unnamed
                    checkbox does not submit, same as a plain
                    `<input type=checkbox>`).
    class(C)        merged with Root's default class, default first
                    ("px-checkbox C") -- same convention as every other
                    component in this library; Trigger/Indicator keep
                    their own fixed classes, not user-overridable
                    (same split progress.pl/switch.pl use between Root
                    and their second part).
    anything else (id(...), data_*(...), aria_*(...), ...) passed
                    through verbatim to Root, appended AFTER the
                    computed attributes -- same last-wins spread order
                    as every other component here.

`checkbox_root/2`, `checkbox_input/1` and `checkbox_indicator/1` are
registered as `px_template:render_helper/2` hooks (adr/0019) -- the
Opts-list defaults/merge/attribute-computation logic below is genuine
computation, so it cannot live in a plain `~>` clause. `checkbox/1`,
the rule-1 top-level convenience template, is ALSO a render_helper
rather than a plain `~>` (unlike switch.pl's `switch/1`): Presence-
gating the Indicator (include it only when checked/indeterminate) is a
conditional Children list, which a `~>` body -- pure unification-built
data, px_template.pl's expand_template/3 -- cannot express.

`checked(_)`/`disabled(_)`/`required(_)`/`value(_)`/`name(_)` are
Checkbox's only "context" dependency (the analysis doc's own note),
trivially satisfied the same way Progress's value/max and Switch's
five state opts are: `checkbox/1` feeds the very same Opts list to
both `checkbox_input/1` and `checkbox_indicator/1` untouched -- no
shared client state needed. `use-size`, Checkbox's other declared
dependency, is likewise not needed here for the same reason it is not
needed in switch.pl: it exists upstream only to keep a separate hidden
BubbleInput sized to the visible Trigger via `ResizeObserver`; this
port has no separate BubbleInput in the first place (the collapse
above), so there is nothing left for `use-size` to do.
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
%   helper as toggle.pl's / switch.pl's.
take_bool(Name, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Opts1)
    ->  Value = V0
    ;   Value = false, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  merge_class(+Opts0, +Default, -ClassVal, -Rest) is det.
%
%   Same helper as progress.pl / toggle.pl / switch.pl's.
merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  valid_checked(?V) is semidet.
%
%   Radix's `CheckedState = boolean | "indeterminate"`.
valid_checked(true).
valid_checked(false).
valid_checked(indeterminate).

%!  take_checkbox_opts(+Opts0, -Checked, -Disabled, -Required, -Value,
%!                      -NameAttrs, -Rest) is det.
%
%   Pulls the five state/form opts out of Opts0; Rest is everything
%   else, in original relative order (id/class/data_*/... -- Root's
%   pass-through). NameAttrs is `[name(N)]` when `name(N)` was given,
%   `[]` otherwise (an unnamed checkbox does not submit, same as plain
%   HTML). An invalid `checked(_)` value falls back to `false`, same
%   guard shape as separator.pl's `orientation` option.
take_checkbox_opts(Opts0, Checked, Disabled, Required, Value, NameAttrs, Rest) :-
    (   selectchk(checked(C0), Opts0, Opts1)
    ->  ( valid_checked(C0) -> Checked = C0 ; Checked = false )
    ;   Checked = false, Opts1 = Opts0
    ),
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

%!  checkbox_state(+Checked, -State) is det.
%
%   State in indeterminate|checked|unchecked -- Radix's own
%   `getState`.
checkbox_state(true,          checked)       :- !.
checkbox_state(indeterminate, indeterminate) :- !.
checkbox_state(_,             unchecked).

%!  aria_checked_word(+State, -Word) is det.
%
%   Word in true|false|mixed, derived from the already-normalised
%   State so `aria-checked` and `data-state` can never disagree.
aria_checked_word(checked,       true).
aria_checked_word(unchecked,     false).
aria_checked_word(indeterminate, mixed).

%!  disabled_attrs(+Disabled, -Attrs) is det.
%
%   `[data_disabled("")]` when Disabled == true, `[]` otherwise --
%   empty-string, not `"true"`, the analysis doc's explicit convention
%   for Checkbox/Switch, applied uniformly (same helper as switch.pl's).
disabled_attrs(true, [data_disabled("")]) :- !.
disabled_attrs(_,    []).

		 /*******************************
		 *             PARTS            *
		 *******************************/

%!  checkbox_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `checkbox_root([checked(true)], Kids)`.
%   Renders a `<label>` (this port's Root -- see the module header for
%   why a label, not upstream's button) carrying Children (typically
%   one Trigger and, when present, one Indicator). Only wrapped in the
%   `<px-checkbox>` custom element (adr/0026 rule 4) when the state is
%   `indeterminate` -- the one case the analysis doc says needs JS;
%   checked/unchecked ship as plain, JS-free markup.
px_template:render_helper(checkbox_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs, State),
    (   State == indeterminate
    ->  px_template:render_tag(S, px_checkbox, [], [label(Attrs, Children)])
    ;   px_template:render(S, label(Attrs, Children))
    ).

root_attrs(Opts0, Attrs, State) :-
    take_checkbox_opts(Opts0, Checked, Disabled, _Required, _Value, _NameAttrs, Rest0),
    merge_class(Rest0, "px-checkbox", ClassVal, Rest),
    checkbox_state(Checked, State),
    disabled_attrs(Disabled, DisabledAttrs),
    append([ [class(ClassVal), data_state(State)],
             DisabledAttrs,
             Rest
           ], Attrs).

%!  checkbox_input(+Opts) is det.
%
%   Bare-call template surface: `checkbox_input([checked(true)])`. No
%   children -- an `<input>` is a void element. Carries the entire
%   ARIA/data contract the analysis doc pins to "Trigger", plus the
%   native attributes (`type`, `checked`, `disabled`, `required`,
%   `value`, `name`) that make it a real, independently-functional
%   form control (this port's NATIVE substitution for upstream's
%   separate Trigger+BubbleInput pair -- see the module header).
px_template:render_helper(checkbox_input(Opts), S) :-
    input_attrs(Opts, Attrs),
    px_template:render(S, input(Attrs)).

input_attrs(Opts0, Attrs) :-
    take_checkbox_opts(Opts0, Checked, Disabled, Required, Value, NameAttrs, _Rest),
    checkbox_state(Checked, State),
    aria_checked_word(State, CheckedWord),
    disabled_attrs(Disabled, DataDisabledAttrs),
    (   Checked == true  -> CheckedAttr  = [checked]  ; CheckedAttr  = [] ),
    (   Disabled == true -> DisabledAttr = [disabled] ; DisabledAttr = [] ),
    (   Required == true -> RequiredAttr = [required] ; RequiredAttr = [] ),
    append([ [type(checkbox), role(checkbox)],
             [aria_checked(CheckedWord), aria_required(Required)],
             [data_state(State)],
             DataDisabledAttrs,
             [class("px-checkbox-input")],
             CheckedAttr, DisabledAttr, RequiredAttr,
             NameAttrs, [value(Value)]
           ], Attrs).

%!  checkbox_indicator(+Opts) is det.
%
%   Bare-call template surface: `checkbox_indicator([checked(true)])`.
%   No children -- Radix's Indicator never has any either; the
%   check/dash glyph is drawn entirely by assets/css/ui.css off
%   `data-state`. Presence-gating (only mount when checked/
%   indeterminate) is the CALLER's job (`checkbox/1`, below) -- calling
%   this part directly always mounts it, matching upstream's
%   `forceMount` escape hatch.
px_template:render_helper(checkbox_indicator(Opts), S) :-
    indicator_attrs(Opts, Attrs),
    px_template:render(S, span(Attrs, [])).

indicator_attrs(Opts0, Attrs) :-
    take_checkbox_opts(Opts0, Checked, Disabled, _Required, _Value, _NameAttrs, _Rest),
    checkbox_state(Checked, State),
    disabled_attrs(Disabled, DisabledAttrs),
    append([ [data_state(State), class("px-checkbox-indicator")],
             DisabledAttrs
           ], Attrs).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  checkbox(+Opts) is det.
%
%   The common case: Root around one Trigger and, when the state is
%   checked or indeterminate, one Indicator (Presence-gating -- the
%   module header explains why this cannot be a plain `~>`). All parts
%   fed the same Opts, same shape as switch.pl's `switch/1`.
checkbox(Opts) ~> \checkbox_render(Opts).

px_template:render_helper(checkbox_render(Opts), S) :-
    take_checkbox_opts(Opts, Checked, _Disabled, _Required, _Value, _NameAttrs, _Rest),
    checkbox_state(Checked, State),
    (   State == unchecked
    ->  Children = [checkbox_input(Opts)]
    ;   Children = [checkbox_input(Opts), checkbox_indicator(Opts)]
    ),
    px_template:render(S, checkbox_root(Opts, Children)).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Checkbox is a Phase-3 "native-backed form control" (docs/radix-
%   port-analysis.md's recommended order: Switch, Toggle, Radio Group,
%   Checkbox) -- Order 9 is the next free slot (1 visually_hidden, 2
%   accessible_icon, 3 label, 4 separator, 5 collapsible, 6 progress, 7
%   toggle, 8 switch/radio_group, 10 aspect_ratio, 11 avatar already
%   registered).
px_ui:demo(checkbox, 9, \checkbox_demo).

%   Arity-0, so it is an ATOM -- called via the explicit \ escape, same
%   as every other component's demo template (a bare atom is a text
%   node, not a callable dispatch, in render/2 -- adr/0019).
checkbox_demo ~>
    div(class("ui-demo-checkbox"),
      [ div(class("field-row"),
          [ checkbox([id("checkbox-demo-unchecked"), name("unchecked")]),
            p("checked(false) (default) -- data-state=\"unchecked\", the Indicator is Presence-gated out of the DOM entirely.")
          ]),
        div(class("field-row"),
          [ checkbox([id("checkbox-demo-checked"), checked(true),
                      name("checked")]),
            p("checked(true) -- aria-checked=\"true\", data-state=\"checked\", real native checked attribute.")
          ]),
        div(class("field-row"),
          [ checkbox([id("checkbox-demo-indeterminate"),
                      checked(indeterminate), name("indeterminate")]),
            p("checked(indeterminate) -- aria-checked=\"mixed\", wrapped in <px-checkbox> so assets/js/components/checkbox.js can set the JS-only .indeterminate property on load; clicking it resolves to a concrete checked/unchecked state, same as native browser behavior.")
          ]),
        div(class("field-row"),
          [ checkbox([id("checkbox-demo-disabled"), disabled(true),
                      name("disabled-unchecked")]),
            p("disabled(true) -- data-disabled=\"\" plus the native disabled attribute; try clicking it.")
          ]),
        div(class("field-row"),
          [ checkbox([id("checkbox-demo-disabled-checked"),
                      checked(true), disabled(true),
                      name("disabled-checked")]),
            p("checked(true) + disabled(true) together -- both contracts hold independently, same as switch.pl's equivalent demo row.")
          ]),

        h3("Form participation"),
        p("Real name/value pairs on real native inputs -- no JS required for any of this, including submission: it is a plain GET form."),
        form([method(get), action("/ui/checkbox")],
          [ div(class("field-row"),
              [ checkbox([id("checkbox-demo-form-newsletter"),
                          name("newsletter"), checked(true)]),
                p("Subscribe to the newsletter")
              ]),
            div(class("field-row"),
              [ checkbox([id("checkbox-demo-form-terms"),
                          name("terms"), required(true)]),
                p("Accept the terms (required)")
              ]),
            button([type(submit)], "Submit")
          ])
      ]).
