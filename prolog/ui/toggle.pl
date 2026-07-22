:- module(ui_toggle, []).

%   No predicates are exported: toggle/2, toggle_root/2 are never called
%   module-qualified -- bare-call dispatch through px_template's tmpl/2 /
%   render_helper/2 tables resolves them (adr/0019), the same pattern
%   prolog/ui/progress.pl and prolog/ui/separator.pl use.

/** <module> Toggle (adr/0026): a single pressed/unpressed button.

Ported from Radix UI's Toggle primitive (docs/radix-port-analysis.md,
"Toggle" entry). Anatomy: a single part, `Root` -- unlike Switch/
Checkbox, Toggle is not form-integrated (no bubble input, no `name`/
`value` submission story); it is a bare pressed/unpressed button, the
building block Toggle Group later composes.

DOM/ARIA contract emitted (exactly the analysis doc's "Toggle" entry):

    <button type="button" aria-pressed="true|false"
            data-state="on|off" data-disabled="">

`aria-pressed` and `data-state` are the two attributes that carry all
the state; `data-disabled=""` (empty-string, not `"true"` -- the same
convention the analysis doc spells out explicitly for Checkbox/Switch
and applies uniformly to every disableable primitive in this family)
plus the native `disabled` attribute are added only when disabled.

**Interactivity class: NATIVE-capable** (adr/0026 rule 3): a server-
rendered `<button aria-pressed>` already carries its correct state on
every render -- reload, Turbo visit, or Turbo-stream replace (adr/0024)
all reproduce it with zero client JS. The one thing the platform cannot
give for free is the *instant* visual flip on click without a round
trip: that irreducible sliver is `assets/js/components/toggle.js`'s
`<px-toggle>` custom element (adr/0026 rule 4), a plain ES module
imported from assets/js/app.js via the importmap (adr/0025). It wraps
the server-rendered button (never replaces it) and, on click, flips
`aria-pressed`/`data-state` on that same DOM node -- state lives in DOM
attributes, never a parallel JS store, so a later Turbo morph/stream
that re-renders the button server-side can never desync from it. Without
JS, the button still renders its correct initial state and is inert but
harmless: no navigation, no form submit, no error (adr/0026 rule 4's
progressive-enhancement bar) -- it simply does not flip client-side
until the module loads.

Options (a plain list, adr/0026 rule 1):

    pressed(Bool)   `true`/`false`, default `false` (Radix's own
                    `pressed` default). Drives both `aria-pressed` and
                    `data-state`.
    disabled(Bool)  `true`/`false`, default `false`. Adds
                    `data-disabled=""` and the native `disabled`
                    attribute (which also does the real work of
                    suppressing click/keyboard activation without JS).
    class(C)        merged with the default class, default first
                    ("px-toggle C").
    anything else (id(...), aria_label(...), data_*(...), ...) passed
                    through verbatim, appended AFTER the computed
                    attributes -- same last-wins spread order as
                    progress.pl / separator.pl.

toggle_root/2 is registered as a px_template:render_helper/2 hook
(adr/0019) -- the Opts-list defaults/merge logic below is genuine
computation, so it cannot live in a plain `~>` clause (px_template.pl's
expand_template/3 builds pure unification data only). toggle/2, the
rule-1 top-level convenience template, IS a plain `~>`: Toggle has no
other parts to assemble, so it is pure structural delegation to Root.
*/

:- use_module('../px_template').

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

		 /*******************************
		 *        OPTION HELPERS        *
		 *******************************/

%!  take_bool(+Opt, +Opts0, -Value, -Rest) is det.
%
%   Pulls Opt(Value) out of Opts0 (default `false` if absent). Opt is
%   the option functor (`pressed` or `disabled`).
take_bool(Name, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Opts1)
    ->  Value = V0
    ;   Value = false, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  merge_class(+Opts0, +Default, -ClassVal, -Rest) is det.
%
%   Pulls `class(C)` out of Opts0 if present and merges it after
%   Default ("px-toggle C"); otherwise ClassVal = Default. Rest is
%   Opts0 minus the class(_) option. Same helper as progress.pl's.
merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  toggle_state(+Pressed, -State) is det.
%
%   State in on|off -- Radix's `data-state={pressed ? "on" : "off"}`.
toggle_state(true, on) :- !.
toggle_state(_,    off).

		 /*******************************
		 *             PART             *
		 *******************************/

%!  toggle_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `toggle_root([pressed(true)], "B")`.
%   Renders the `<px-toggle>` custom-element wrapper (adr/0026 rule 4)
%   around the server-rendered `<button>` -- the wrapper is what the
%   custom element registers against; the button inside is the whole
%   ARIA/data contract and is exactly as usable if `<px-toggle>` is
%   never upgraded (no JS loaded).
px_template:render_helper(toggle_root(Opts, Children), S) :-
    button_attrs(Opts, Attrs),
    px_template:render_tag(S, px_toggle, [], [button(Attrs, Children)]).

button_attrs(Opts0, Attrs) :-
    take_bool(pressed, Opts0, Pressed, Opts1),
    take_bool(disabled, Opts1, Disabled, Opts2),
    merge_class(Opts2, "px-toggle", ClassVal, Opts3),
    toggle_state(Pressed, State),
    (   Disabled == true
    ->  DisabledAttrs = [data_disabled(""), disabled]
    ;   DisabledAttrs = []
    ),
    append([ [type(button), aria_pressed(Pressed), data_state(State),
              class(ClassVal)],
             DisabledAttrs,
             Opts3
           ], Attrs).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  toggle(+Opts, +Children) is det.
%
%   The common (only) case: Toggle has a single anatomy part, so this
%   is pure structural delegation to Root -- same shape as
%   separator.pl's separator/2.
toggle(Opts, Children) ~> toggle_root(Opts, Children).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Toggle is a Phase-3 "native-backed form control" (docs/radix-port-
%   analysis.md's recommended order: Switch, Toggle, Radio Group,
%   Checkbox) -- Order 7 leaves 5 free for a still-unported Switch to
%   land ahead of it, matching that doc's listed sequence, without
%   colliding with any Order already registered (1 visually_hidden, 2
%   accessible_icon, 3 label, 4 separator, 6 progress, 10 aspect_ratio).
px_ui:demo(toggle, 7, \toggle_demo).

%   Arity-0, so it is an ATOM -- called via the explicit \ escape, same
%   as every other component's demo template (a bare atom is a text
%   node, not a callable dispatch, in render/2 -- adr/0019).
toggle_demo ~>
    div(class("px-toggle-demo"),
      [ div(class("px-toggle-row"),
          [ toggle([id("toggle-demo-off"), aria_label("Off toggle")],
                   "Off"),
            p("pressed(false) (default) -- aria-pressed=\"false\", data-state=\"off\".")
          ]),
        div(class("px-toggle-row"),
          [ toggle([id("toggle-demo-on"), pressed(true),
                    aria_label("On toggle")],
                   "On"),
            p("pressed(true) -- aria-pressed=\"true\", data-state=\"on\".")
          ]),
        div(class("px-toggle-row"),
          [ toggle([id("toggle-demo-disabled"), disabled(true),
                    aria_label("Disabled toggle")],
                   "Disabled"),
            p("disabled(true) -- data-disabled=\"\" plus the native disabled attribute; try clicking it.")
          ])
      ]).
