:- module(ui_radio_group, []).

%   No predicates are exported: radio_group_root/2, radio_group_item/1,2
%   and radio_group/2 are never called module-qualified -- they are term
%   SHAPES that px_template's bare-call dispatch resolves via the
%   multifile tmpl/2 / render_helper/2 tables (adr/0019), the same
%   pattern prolog/ui/progress.pl and prolog/ui/toggle.pl use.

/** <module> Radio Group (adr/0026): single-select group of radio inputs.

Ported from Radix UI's RadioGroup primitive (docs/radix-port-analysis.md,
"Radio Group" entry). Anatomy: `Root` (`radio_group_root/2`,
`role="radiogroup"`) wrapping any number of `Item`s (`radio_group_item/2`,
each one a native `<input type="radio">`). `radio_group/2` is the
convenience template (adr/0026 rule 1) assembling the common case: Root
around a list of Items, threading Root's `name` onto every Item that
doesn't already carry its own.

**Interactivity class: NATIVE -- "the strongest native-coverage case in
this family"** (the analysis doc's own words). A real
`<input type="radio" name="x">` group gets roving-tabindex-equivalent
Tab behaviour *and* arrow-key auto-select for free from the browser --
including the auto-check-on-arrow-focus affordance Radix hand-rolls with
a document-level keydown/keyup pair plus a synthetic `.click()` -- with
*zero* JS. This port leans on that fully (adr/0026 rule 3): there is no
`assets/js/components/radio_group.js`, no roving-focus controller, no
`<px-radio-group>` custom element. The only gap the analysis doc calls
out is a styling-technique one -- `:checked` sibling selectors instead
of a `data-state` hook on an arbitrary wrapper -- "a CSS technique
difference, not a capability gap"; see the CSS notes below and in
assets/css/ui.css for exactly how this port resolves it.

Anatomy templates emit the analysis doc's role/aria/data-state contract
on **styled wrappers around the native inputs** (per adr/0026 rule 2,
"the contract is sacred"), with two documented deviations specific to
choosing the native-input variant over the hand-rolled `role="radio"`
custom-button variant:

  1. **No explicit `role="radio"` / `aria-checked` on the input.** The
     analysis doc's contract lists them on the "Item trigger" -- in the
     hand-rolled variant that trigger is a plain `<button>`, which needs
     both authored manually. Here the trigger *is* a native
     `<input type="radio">`, which already carries an implicit
     `role="radio"` and an `aria-checked` that tracks its `checked` IDL
     property automatically (HTML-AAM); authoring them explicitly would
     be redundant at best and, since there is no JS here to keep a
     manually-set `aria-checked` in sync after the user clicks a
     *different* sibling radio, actively wrong at worst. Every
     accessibility-tree inspector confirms the native semantics are
     already exactly the contract's `role="radio"`/`aria-checked` pair.
  2. **`data-state`/`data-disabled` live on the wrapper `<label>`, not
     the input.** These two have no native equivalent, so they are
     authored explicitly -- on the styled wrapper each Item renders
     around its input (a `<label>`, so clicking the visible text also
     selects the radio, the same native "wrapping the control directly"
     association ui/label.pl's own demo uses). `data-state` is computed
     **once, server-side, from the `checked(_)` option at render time**
     -- like every other STATIC/NATIVE-capable port in this library
     (progress.pl, toggle.pl, ...), nothing here polls or observes DOM
     events. Concretely: after the user arrow-keys or clicks to a
     *different* radio in the group, that DOM's `data-state` attributes
     go stale (the browser updates `:checked` live; nothing rewrites
     `data-state` without JS, and adding JS just for this would violate
     rule 3 -- native input coverage is already total for selection and
     keyboard behaviour, so a custom element is not "justified for
     behaviour the platform cannot express"). Consequently
     assets/css/ui.css keys the *visual* selected/unselected treatment
     off the live `:checked` pseudo-class (never wrong), and only uses
     `[data-state=...]`/`[data-disabled]` for the initial-render/
     no-JS-inspection parity the sacred contract asks for -- exactly the
     "CSS technique difference" the analysis doc anticipates.

  Also dropped as a separate anatomy part: Radix's `ItemIndicator`
  (`Presence`-gated). With no mount/unmount animation lifecycle to gate
  (there is no JS here to drive one), the selected-dot is drawn as the
  native input's own `::before` pseudo-element, shown purely by
  `:checked` -- a separate DOM node would buy nothing.

Options (a plain list, adr/0026 rule 1):

  `radio_group_root/2` Opts:
    orientation(horizontal|vertical)  optional; when given (and valid),
                    emits `aria-orientation` (mirrors Radix: the prop is
                    passed straight through, so an *absent* orientation
                    omits the attribute entirely -- `undefined` props
                    don't render in JSX either) and also drives the
                    layout via the very same `[aria-orientation=...]`
                    selector (adr/0026 rule 2 -- no extra invented
                    `data-orientation`, since the analysis doc's Root
                    contract doesn't list one).
    required(Bool)  `true`/`false`, default `false` (Radix's own
                    default). Always emits `aria-required="true"` or
                    `"false"` -- unlike `orientation`, Radix's
                    `required` prop itself defaults to `false` rather
                    than `undefined`, so the attribute is always
                    present.
    disabled(true)  optional. Emits `data-disabled=""` (empty-string,
                    not `"true"` -- the same convention documented for
                    Checkbox/Switch and already followed by
                    ui/toggle.pl, applied uniformly across this family).
                    Deviation, noted per rule 2: unlike Radix's
                    context-based inheritance, this port's Root
                    `disabled(true)` only dims/marks the group
                    container -- it does NOT auto-propagate down to
                    every Item's native `disabled` attribute (there is
                    no context here to propagate through); disable
                    individual items explicitly via their own
                    `disabled(true)`.
    class(C)        merged with the default class, default first
                    ("px-radio-group C").
    anything else (id(...), data_*(...), ...) passed through verbatim
                    onto the root div, appended after the computed
                    attributes -- same last-wins spread order as every
                    other port in this library.

  `radio_group_item/1,2` Opts:
    value(V)        REQUIRED. The native input's `value` -- what a
                    wrapping `<form>` submits for this group.
    name(N)         REQUIRED when calling `radio_group_item/1,2`
                    directly (this is what makes several inputs one
                    native radio *group*, so a mismatch here silently
                    breaks selection/keyboard behaviour). The
                    `radio_group/2` convenience supplies it
                    automatically from Root's Opts (or a generated
                    default) for any Item that doesn't set its own.
    checked(true)   marks this item selected: native `checked` boolean
                    attribute on the input, `data-state="checked"` on
                    the wrapper (default, when absent: `"unchecked"`).
    disabled(true)  native `disabled` boolean attribute on the input,
                    `data-disabled=""` on the wrapper.
    class(C)        merged with the default wrapper class, default
                    first ("px-radio-group-item C").
    anything else (id(...), aria_describedby(...), autofocus, ...)
                    passed through verbatim onto the native `<input>`
                    (the actual interactive form control) -- not the
                    wrapper, which carries only presentation/state.

  `radio_group/2` Opts: everything `radio_group_root/2` takes, PLUS
    name(N)         optional; extracted before building Root (a `name`
                    attribute on the wrapping `<div>` would be
                    meaningless) and threaded onto every Item in the
                    second argument that doesn't already specify its
                    own `name(_)`. Defaults to a generated
                    `px-radio-group-N` (`library(gensym)`) when absent,
                    so callers never have to invent one just to keep a
                    group's inputs correctly associated.
  `radio_group/2` second argument: a list of `radio_group_item(Opts,
                    Children)` / `radio_group_item(Opts)` terms (rule 1:
                    "parts are template terms"); any other term is
                    passed through to Root's children unmodified, with
                    no name-injection attempted on it.

Both `radio_group_root/2` and `radio_group_item/1,2` are registered as
px_template:render_helper/2 hooks (adr/0019) -- the Opts-list
defaults/merge/validation logic below is genuine computation, the same
reason progress.pl, separator.pl and toggle.pl register theirs the same
way rather than as plain `~>` clauses.
*/

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(gensym)).
:- use_module('../px_template').

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

		 /*******************************
		 *        OPTION HELPERS        *
		 *******************************/

%!  class_opt(+Opts, +Default, -ClassVal) is det.
%
%   ClassVal is Default alone, or "Default Caller" when Opts carries a
%   class(Caller) -- additive, never overwriting (same helper shape as
%   progress.pl/toggle.pl's merge_class/4, read-only here since the
%   callers below build their pass-through tail with exclude/3
%   instead).
class_opt(Opts, Default, ClassVal) :-
    (   memberchk(class(Caller), Opts)
    ->  format(string(ClassVal), "~w ~w", [Default, Caller])
    ;   ClassVal = Default
    ).

valid_orientation(horizontal).
valid_orientation(vertical).

		 /*******************************
		 *             ROOT             *
		 *******************************/

%!  radio_group_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `radio_group_root([required(true)],
%   Items)`.
px_template:render_helper(radio_group_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, Children)).

root_attrs(Opts, Attrs) :-
    must_be(list, Opts),
    orientation_attrs(Opts, OrientAttrs),
    required_attrs(Opts, ReqAttrs),
    disabled_attrs(Opts, DisAttrs),
    class_opt(Opts, "px-radio-group", ClassVal),
    exclude(root_reserved_opt, Opts, Extra),
    append([ [role(radiogroup)], ReqAttrs, OrientAttrs,
             [class(ClassVal)], DisAttrs, Extra
           ], Attrs).

orientation_attrs(Opts, [aria_orientation(O)]) :-
    memberchk(orientation(O), Opts),
    valid_orientation(O),
    !.
orientation_attrs(_, []).

%   Radix's own `required` prop defaults to `false` (not `undefined`),
%   so -- unlike orientation -- aria-required is always present.
required_attrs(Opts, [aria_required(Bool)]) :-
    (   memberchk(required(true), Opts)
    ->  Bool = true
    ;   Bool = false
    ).

disabled_attrs(Opts, [data_disabled("")]) :-
    memberchk(disabled(true), Opts),
    !.
disabled_attrs(_, []).

root_reserved_opt(orientation(_)).
root_reserved_opt(required(_)).
root_reserved_opt(disabled(_)).
root_reserved_opt(class(_)).

		 /*******************************
		 *             ITEM             *
		 *******************************/

%!  radio_group_item(+Opts) is det.
%!  radio_group_item(+Opts, +Children) is det.
%
%   Bare-call template surface: `radio_group_item([name(g), value(v1),
%   checked(true)], "Option 1")`. `radio_group_item/1` is the no-label
%   shorthand (Children = []), same `/1` delegates to `/2` shape as
%   ui/separator.pl's `separator_root/1,2`.
px_template:render_helper(radio_group_item(Opts), S) :-
    px_template:render_helper(radio_group_item(Opts, []), S).
px_template:render_helper(radio_group_item(Opts, Children), S) :-
    item_attrs(Opts, WrapperAttrs, InputAttrs),
    px_template:render(S,
        label(WrapperAttrs,
          [ input(InputAttrs),
            span(class("px-radio-group-label"), Children)
          ])).

item_attrs(Opts, WrapperAttrs, InputAttrs) :-
    must_be(list, Opts),
    require_opt(Opts, value, radio_group_item/2, V),
    require_opt(Opts, name, radio_group_item/2, N),
    item_state(Opts, State, CheckedAttrs),
    item_disabled(Opts, DisWrapAttrs, DisInAttrs),
    class_opt(Opts, "px-radio-group-item", ClassVal),
    exclude(item_reserved_opt, Opts, Extra),
    append([ [class(ClassVal), data_state(State)], DisWrapAttrs
           ], WrapperAttrs),
    append([ [type(radio), name(N), value(V)],
             [class("px-radio-group-input")],
             CheckedAttrs, DisInAttrs, Extra
           ], InputAttrs).

%!  require_opt(+Opts, +Key, +Context, -Value) is det.
%
%   Reads Key(Value) out of Opts, or throws a clear existence_error
%   naming both the missing option and the template that needed it --
%   `value` and `name` are the two Item options with no sane default
%   (an omitted `value` breaks form submission silently; an omitted/
%   mismatched `name` silently breaks the native grouping this whole
%   port leans on).
require_opt(Opts, Key, Context, Value) :-
    Probe =.. [Key, Value],
    (   memberchk(Probe, Opts)
    ->  true
    ;   throw(error(existence_error(option, Key), context(Context, _)))
    ).

item_state(Opts, checked, [checked]) :-
    memberchk(checked(true), Opts),
    !.
item_state(_, unchecked, []).

item_disabled(Opts, [data_disabled("")], [disabled]) :-
    memberchk(disabled(true), Opts),
    !.
item_disabled(_, [], []).

item_reserved_opt(value(_)).
item_reserved_opt(name(_)).
item_reserved_opt(checked(_)).
item_reserved_opt(disabled(_)).
item_reserved_opt(class(_)).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  radio_group(+Opts, +Items) is det.
%
%   The common case: Root around a list of Items, with Root's `name`
%   (explicit, or a fresh `px-radio-group-N` gensym) threaded onto every
%   Item that doesn't already carry its own -- the one piece of context
%   Items genuinely share (same category as progress.pl threading
%   value/max onto Indicator): get the `name` wrong or miss it on one
%   Item and the native grouping this whole port relies on for
%   selection/keyboard behaviour silently breaks.
radio_group(Opts, Items) ~> \radio_group_render(Opts, Items).

px_template:render_helper(radio_group_render(Opts, Items), S) :-
    group_name(Opts, Name, RootOpts),
    maplist(inject_name(Name), Items, Items1),
    px_template:render(S, radio_group_root(RootOpts, Items1)).

%!  group_name(+Opts, -Name, -RootOpts) is det.
%
%   Name is Opts' own name(_) if given, else a fresh gensym default.
%   RootOpts is Opts with name(_) removed -- a `name` attribute on the
%   wrapping <div> would be meaningless, so it is never forwarded to
%   radio_group_root/2.
group_name(Opts, Name, RootOpts) :-
    (   selectchk(name(N0), Opts, RootOpts)
    ->  Name = N0
    ;   RootOpts = Opts,
        gensym('px-radio-group-', Name)
    ).

%!  inject_name(+Name, +Item0, -Item) is det.
%
%   Item0 with `name(Name)` added to its Opts, UNLESS it already
%   specifies its own name(_) (explicit always wins over the group
%   default). Any term that isn't a radio_group_item(_) / (_,_) shape
%   (e.g. raw markup a caller interleaves between items) passes through
%   unmodified -- no name-injection attempted on it.
inject_name(Name, radio_group_item(ItemOpts0), radio_group_item(ItemOpts)) :-
    !,
    add_name(Name, ItemOpts0, ItemOpts).
inject_name(Name, radio_group_item(ItemOpts0, Children),
            radio_group_item(ItemOpts, Children)) :-
    !,
    add_name(Name, ItemOpts0, ItemOpts).
inject_name(_, Other, Other).

add_name(Name, Opts0, Opts) :-
    (   memberchk(name(_), Opts0)
    ->  Opts = Opts0
    ;   Opts = [name(Name)|Opts0]
    ).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Radio Group is a Phase-3 "native-backed form control" (docs/radix-
%   port-analysis.md's recommended order: Switch, Toggle, Radio Group,
%   Checkbox) -- Order 8 lands right after ui/toggle.pl's Order 7,
%   leaving 5 free for Collapsible (already landed) and 9 free for a
%   still-unported Checkbox, without colliding with any Order already
%   registered (1 visually_hidden, 2 accessible_icon, 3 label,
%   4 separator, 5 collapsible, 6 progress, 7 toggle, 10 aspect_ratio).
px_ui:demo(radio_group, 8, \radio_group_demo).

%   Arity-0, so it is an ATOM -- called via the explicit \ escape, same
%   as every other component's demo template (a bare atom is a text
%   node, not a callable dispatch, in render/2 -- adr/0019). Three
%   options, one checked, one disabled -- exactly the sacred contract's
%   three item states (checked, unchecked, checked+disabled is left for
%   the reader; unchecked+disabled shown here).
radio_group_demo ~>
    div(class("px-radio-group-demo"),
      [ p([ "Native ",
            code("<input type=\"radio\">"),
            " grouped by ",
            code("name"),
            " -- zero JS. Tab lands on the whole group once; arrow keys ",
            "move focus AND auto-select the newly-focused radio, the ",
            "browser's own equivalent of Radix's hand-rolled roving-",
            "tabindex-plus-synthetic-click behaviour."
          ]),
        radio_group([id("radio-group-demo"), required(true)],
          [ radio_group_item([value("default"), checked(true)],
                              "Default"),
            radio_group_item([value("comfortable")], "Comfortable"),
            radio_group_item([value("compact"), disabled(true)],
                              "Compact (disabled)")
          ])
      ]).
