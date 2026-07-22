:- module(ui_toggle_group, []).

%   No predicates are exported: toggle_group/2, toggle_group_root/2,
%   toggle_group_item/1,2 are never called module-qualified -- bare-call
%   dispatch through px_template's tmpl/2 / render_helper/2 tables
%   resolves them (adr/0019), the same pattern prolog/ui/radio_group.pl
%   and prolog/ui/toggle.pl use.

/** <module> Toggle Group (adr/0026): a row/column of Toggles, roving-
focus keyboard nav, `single` (radio-like) or `multiple` selection.

Ported from Radix UI's ToggleGroup primitive (docs/radix-port-
analysis.md, "Toggle Group" entry). Anatomy: `Root`
(`toggle_group_root/2`), `Item` (`toggle_group_item/1,2`).
`toggle_group/2` is the rule-1 top-level convenience template
assembling the common case: Root around a list of Items.

Toggle Group is this library's first **roving-focus consumer**
(adr/0026 rule 5, rule 8's porting order: "roving-focus consumers"
comes right after the native-backed family) -- it is what proves
`assets/js/lib/roving-focus.js`'s `installRovingFocus/2` API for the
Tabs/Toolbar/Accordion ports that follow.

**Interactivity class: CUSTOM-ELEMENT -- unavoidably** (the analysis
doc's own verdict): "arrow-key roving-tabindex navigation between
items cannot be done via a network round trip per keypress without
breaking the ARIA pattern's UX contract." Everything else (which item
is pressed, which is disabled) is perfectly server-renderable and
reload-safe; `assets/js/components/toggle_group.js`'s
`<px-toggle-group>` is the one irreducible sliver, wrapping the whole
Root (once, not once per Item -- unlike Toggle/Switch, which each wrap
their own single control) around the server-rendered `<div>` +
`<button>`s.

DOM/ARIA contract emitted (exactly the analysis doc's "Toggle Group"
entry):

    Root  <div role="radiogroup" data-orientation="horizontal|vertical">   (type=single)
          <div role="toolbar"    data-orientation="horizontal|vertical">   (type=multiple)

    Item  <button type="button" role="radio" aria-checked="true|false"
                  data-state="on|off" tabindex="0|-1">                     (type=single)
          <button type="button" aria-pressed="true|false"
                  data-state="on|off" tabindex="0|-1">                     (type=multiple)

`data-state` is carried on every Item regardless of type -- Toggle
Group items are still, underneath, Toggles (the analysis doc's own
dependency list: "context, roving-focus, toggle, direction"; the
"Toggle" entry's `data-state` convention is exactly what this reuses),
so both variants keep the same styling hook `assets/css/ui.css` keys
off; `type=single` additionally swaps `aria-pressed` for
`role="radio"` + `aria-checked` (a `role="radio"` element combined
with `aria-pressed` would be an invalid ARIA state pairing).
`data-disabled=""` (empty-string, not `"true"` -- the family-wide
convention) plus the native `disabled` attribute are added to a
disabled Item; a disabled Root gets `data-disabled=""` only (does not
propagate to Items, same documented deviation as radio_group.pl's
Root `disabled(true)` -- see below).

Two additive-only extensions, noted per rule 2:

  1. `tabindex="0"` on exactly one non-disabled Item (the "current tab
     stop"), `tabindex="-1"` on every other Item, ALWAYS explicit on
     every Item -- not literally in the analysis doc's attribute list
     (upstream expresses this as a `tabIndex` React prop, not prose
     naming a rendered attribute) but is exactly what "Items wrapped in
     a roving-focus item (tabIndex 0/-1 per current tab stop)" (the
     same entry, one line up) requires as the DOM-level encoding of
     that wrapping, and is the one piece of state
     `assets/js/lib/roving-focus.js`'s `installRovingFocus/2` reads on
     install (its own header: "The initial choice is whichever item
     the SERVER already marked tabindex=0"). Which Item that is:
     `toggle_group/2` picks the first PRESSED, non-disabled Item if any
     exist, else the first non-disabled Item -- the caller can always
     override by passing `active(true)` on a specific
     `toggle_group_item/1,2` term directly.
  2. `data-loop=""` on Root, only when `loop(true)` -- there is no
     upstream rendered attribute for this at all (Radix's `loop` prop
     is a plain JS boolean read straight out of React state/context);
     since this port's state must live entirely in DOM attributes
     (adr/0026 rule 4 -- no parallel JS store), `<px-toggle-group>`
     needs SOME markup-level way to learn the flag, and an
     empty-string-when-true data attribute is the same convention
     `data-disabled` already established in this family.

Keyboard: entirely delegated to `installRovingFocus/2`
(`assets/js/lib/roving-focus.js`, `itemSelector: ".px-toggle-group-item"`,
`orientation` taken from `data-orientation`, `loop` taken from
`data-loop`'s presence) -- ArrowLeft/Up -> prev, ArrowRight/Down ->
next (RTL- and orientation-aware), Home/PageUp -> first, End/PageDown
-> last, wrapping only when `loop(true)`. Space/Enter activation
(pressing/toggling an Item) is native `<button>` behaviour;
roving-focus only ever touches `tabindex`/focus, never click handling
(the analysis doc's own note: "roving-focus only intercepts navigation
keys").

Options (a plain list, adr/0026 rule 1):

  `toggle_group_root/2` Opts:
    type(single|multiple)   REQUIRED. Drives Root's `role`
                    (`radiogroup`/`toolbar`) and every Item's
                    `role`/`aria-*` pair. No default -- Radix's own
                    `type` prop is required too; there is no sane
                    default between mutually-exclusive-select and
                    independent-select.
    orientation(horizontal|vertical)  default `horizontal` (Radix's own
                    default). Drives `data-orientation`, which both the
                    CSS layout (assets/css/ui.css) and
                    `<px-toggle-group>`'s roving-focus install read.
    loop(Bool)      `true`/`false`, default `false` (Radix's own
                    default). Emits `data-loop=""` only when `true` --
                    see extension 2 above.
    disabled(Bool)  `true`/`false`, default `false`. Adds
                    `data-disabled=""` to Root ONLY -- deviation, noted
                    per rule 2: unlike Radix's context-based
                    inheritance, this does NOT auto-propagate to every
                    Item's own `disabled(true)` (no context to
                    propagate through, same as radio_group.pl's Root
                    `disabled(true)`); disable individual Items
                    explicitly.
    class(C)        merged with the default class, default first
                    ("px-toggle-group C").
    anything else (id(...), aria_label(...), data_*(...), ...) passed
                    through verbatim, appended AFTER the computed
                    attributes -- same last-wins spread order as every
                    other port in this library.

  `toggle_group_item/1,2` Opts:
    type(single|multiple)   REQUIRED when calling `toggle_group_item/1,2`
                    directly (mirrors radio_group_item's own `name`
                    requirement); `toggle_group/2` injects Root's type
                    onto every Item automatically, overriding any
                    per-Item value (type is a group-wide concept, never
                    meaningfully per-Item -- unlike radio_group.pl's
                    `name`, which only fills in a default when absent).
    pressed(Bool)   `true`/`false`, default `false` -- same option name
                    and same on/off `data-state` derivation as
                    ui/toggle.pl's `pressed(Bool)` (Toggle Group Items
                    ARE Toggles, per the analysis doc's dependency
                    list), reused verbatim rather than renamed
                    `checked` for `type=single`, so a caller does not
                    have to know an Item's rendered `aria-*` name
                    differs by group type just to set its own state.
    disabled(Bool)  `true`/`false`, default `false`. Adds
                    `data-disabled=""` plus the native `disabled`
                    attribute; also excludes the Item from
                    `toggle_group/2`'s active-item pick and from
                    `installRovingFocus/2`'s arrow-key targets.
    active(Bool)    `true`/`false`, default `false`. `true` renders
                    `tabindex="0"` (this Item is the roving-focus
                    group's current tab stop); `toggle_group/2`
                    computes and injects this automatically (extension
                    1 above) onto exactly one Item unless the caller
                    already set it explicitly on one, in which case
                    that explicit choice always wins.
    class(C)        merged with the default class, default first
                    ("px-toggle-group-item C").
    anything else (id(...), aria_label(...), data_*(...), ...) passed
                    through verbatim onto the `<button>`, appended
                    AFTER the computed attributes.

  `toggle_group/2` second argument: a list of `toggle_group_item(Opts)`
                    / `toggle_group_item(Opts, Children)` terms (rule 1:
                    "parts are template terms"); any other term is
                    passed through to Root's children unmodified, with
                    neither `type` injection nor active-item
                    consideration attempted on it (same
                    pass-through-unmodified rule radio_group.pl's
                    `inject_name/3` uses).

Both `toggle_group_root/2` and `toggle_group_item/1,2` are registered
as `px_template:render_helper/2` hooks (adr/0019) -- the Opts-list
defaults/merge/validation logic below is genuine computation, the same
reason progress.pl, toggle.pl, switch.pl and radio_group.pl register
theirs the same way. `toggle_group/2`, the rule-1 top-level convenience
template, is ALSO a `render_helper/2` hook rather than a plain `~>`
(unlike toggle.pl's/separator.pl's own convenience templates) --
picking the active Item and injecting `type` into every Item is genuine
cross-item computation, the same reason radio_group.pl's `radio_group/2`
is a `render_helper/2` hook rather than a plain `~>` too.
*/

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module('../px_template').

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

		 /*******************************
		 *        OPTION HELPERS        *
		 *******************************/

valid_type(single).
valid_type(multiple).

valid_orientation(horizontal).
valid_orientation(vertical).

%!  require_opt(+Opts, +Key, +Context, -Value) is det.
%
%   Reads Key(Value) out of Opts, or throws a clear existence_error
%   naming both the missing option and the template that needed it --
%   same helper radio_group.pl uses for its own required `value`/`name`
%   Item options.
require_opt(Opts, Key, Context, Value) :-
    Probe =.. [Key, Value],
    (   memberchk(Probe, Opts)
    ->  true
    ;   throw(error(existence_error(option, Key), context(Context, _)))
    ).

%!  require_type(+Opts, +Context, -Type) is det.
%
%   Type is Opts' `type(_)` option, validated against valid_type/1 --
%   an invalid or missing value is always a caller error (there is no
%   sane default between mutually-exclusive-select and
%   independent-select), so both cases throw.
require_type(Opts, Context, Type) :-
    require_opt(Opts, type, Context, Type0),
    (   valid_type(Type0)
    ->  Type = Type0
    ;   throw(error(domain_error(toggle_group_type, Type0), context(Context, _)))
    ).

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

%!  toggle_state(+Pressed, -State) is det.
%
%   State in on|off -- Radix's `data-state={pressed ? "on" : "off"}`,
%   same rule as ui/toggle.pl's own toggle_state/2 (Toggle Group Items
%   ARE Toggles).
toggle_state(true, on) :- !.
toggle_state(_,    off).

		 /*******************************
		 *             ROOT             *
		 *******************************/

%!  toggle_group_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `toggle_group_root([type(single)],
%   Items)`. Renders the `<px-toggle-group>` custom-element wrapper
%   (adr/0026 rule 4) around the server-rendered `<div>` -- the wrapper
%   is what the custom element registers against; the div/buttons
%   inside carry the whole ARIA/data contract and are exactly as usable
%   (minus arrow-key roving nav -- plain sequential Tab-through over
%   whichever single button currently has tabindex="0" still works) if
%   `<px-toggle-group>` is never upgraded.
px_template:render_helper(toggle_group_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_toggle_group, [], [div(Attrs, Children)]).

root_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    require_type(Opts0, toggle_group_root/2, Type),
    role_for_type(Type, Role),
    orientation_opt(Opts0, Orientation),
    take_bool(loop, Opts0, Loop, Opts1),
    take_bool(disabled, Opts1, Disabled, Opts2),
    merge_class(Opts2, "px-toggle-group", ClassVal, Opts3),
    exclude(root_reserved_opt, Opts3, Extra),
    loop_attrs(Loop, LoopAttrs),
    root_disabled_attrs(Disabled, DisAttrs),
    append([ [role(Role), data_orientation(Orientation), class(ClassVal)],
             LoopAttrs, DisAttrs, Extra
           ], Attrs).

role_for_type(single,   radiogroup).
role_for_type(multiple, toolbar).

orientation_opt(Opts, Orientation) :-
    (   memberchk(orientation(O), Opts),
        valid_orientation(O)
    ->  Orientation = O
    ;   Orientation = horizontal
    ).

loop_attrs(true, [data_loop("")]) :- !.
loop_attrs(_,    []).

root_disabled_attrs(true, [data_disabled("")]) :- !.
root_disabled_attrs(_,    []).

root_reserved_opt(type(_)).
root_reserved_opt(orientation(_)).
root_reserved_opt(loop(_)).
root_reserved_opt(disabled(_)).
root_reserved_opt(class(_)).

		 /*******************************
		 *             ITEM             *
		 *******************************/

%!  toggle_group_item(+Opts) is det.
%!  toggle_group_item(+Opts, +Children) is det.
%
%   Bare-call template surface: `toggle_group_item([type(single),
%   pressed(true)], "Bold")`. `toggle_group_item/1` is the no-label
%   shorthand (Children = []), same `/1` delegates to `/2` shape as
%   radio_group.pl's `radio_group_item/1,2`.
px_template:render_helper(toggle_group_item(Opts), S) :-
    px_template:render_helper(toggle_group_item(Opts, []), S).
px_template:render_helper(toggle_group_item(Opts, Children), S) :-
    item_attrs(Opts, Attrs),
    px_template:render(S, button(Attrs, Children)).

item_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    require_type(Opts0, toggle_group_item/2, Type),
    take_bool(pressed, Opts0, Pressed, Opts1),
    take_bool(disabled, Opts1, Disabled, Opts2),
    take_bool(active, Opts2, Active, Opts3),
    merge_class(Opts3, "px-toggle-group-item", ClassVal, Opts4),
    exclude(item_reserved_opt, Opts4, Extra),
    toggle_state(Pressed, State),
    type_attrs(Type, Pressed, TypeAttrs),
    tabindex_attrs(Active, TabAttrs),
    item_disabled_attrs(Disabled, DisAttrs),
    append([ [type(button)], TypeAttrs, [data_state(State)], TabAttrs,
             [class(ClassVal)], DisAttrs, Extra
           ], Attrs).

%   type=single: role="radio" + aria-checked (aria-pressed would be an
%   invalid pairing with role="radio"). type=multiple: ordinary Toggle
%   semantics, aria-pressed, implicit native button role.
type_attrs(single,   Pressed, [role(radio), aria_checked(Pressed)]).
type_attrs(multiple, Pressed, [aria_pressed(Pressed)]).

tabindex_attrs(true, [tabindex(0)])  :- !.
tabindex_attrs(_,    [tabindex(-1)]).

item_disabled_attrs(true, [data_disabled(""), disabled]) :- !.
item_disabled_attrs(_,    []).

item_reserved_opt(type(_)).
item_reserved_opt(pressed(_)).
item_reserved_opt(disabled(_)).
item_reserved_opt(active(_)).
item_reserved_opt(class(_)).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  toggle_group(+Opts, +Items) is det.
%
%   The common case: Root around a list of Items, with Root's `type`
%   threaded onto every Item (overriding any per-Item value -- `type`
%   is group-wide, never meaningfully per-Item) and exactly one
%   non-disabled Item marked `active(true)` (the roving-focus group's
%   initial tab stop) unless the caller already marked one explicitly.
toggle_group(Opts, Items) ~> \toggle_group_render(Opts, Items).

px_template:render_helper(toggle_group_render(Opts, Items), S) :-
    require_type(Opts, toggle_group/2, Type),
    maplist(inject_type(Type), Items, Items1),
    mark_active(Items1, Items2),
    px_template:render(S, toggle_group_root(Opts, Items2)).

%!  inject_type(+Type, +Item0, -Item) is det.
%
%   Item0 with `type(Type)` set, overriding any `type(_)` it already
%   carries -- unlike radio_group.pl's name-injection (which only
%   fills in a default when absent), `type` is a group-wide contract
%   property that must always match Root's, so the group always wins.
%   Any term that isn't a `toggle_group_item(_)` / `(_,_)` shape (e.g.
%   raw markup a caller interleaves between Items) passes through
%   unmodified.
inject_type(Type, toggle_group_item(O0), toggle_group_item(O)) :-
    !,
    set_type(Type, O0, O).
inject_type(Type, toggle_group_item(O0, C), toggle_group_item(O, C)) :-
    !,
    set_type(Type, O0, O).
inject_type(_, Other, Other).

set_type(Type, O0, O) :-
    (   selectchk(type(_), O0, O1)
    ->  true
    ;   O1 = O0
    ),
    O = [type(Type)|O1].

%!  mark_active(+Items0, -Items) is det.
%
%   Items0 with `active(true)` injected into exactly one Item's Opts,
%   UNLESS some Item already carries its own `active(_)` (an explicit
%   caller choice always wins and short-circuits the auto-pick
%   entirely -- same "explicit always wins" rule radio_group.pl's
%   `add_name/3` uses for `name`). The auto-pick is the first PRESSED,
%   non-disabled Item if one exists, else the first non-disabled Item;
%   if every Item is disabled (or Items0 is empty), no Item is marked
%   and every rendered Item keeps `tabindex="-1"` (an all-disabled
%   group has nothing to make a tab stop of -- installRovingFocus/2's
%   own fallback agrees: "the first non-disabled item wins", and there
%   is none).
mark_active(Items0, Items) :-
    (   member(Item, Items0), item_opts(Item, O), memberchk(active(_), O)
    ->  Items = Items0
    ;   pick_active(Items0, Active)
    ->  maplist(set_active_if(Active), Items0, Items)
    ;   Items = Items0
    ).

item_opts(toggle_group_item(O),    O).
item_opts(toggle_group_item(O, _), O).

item_pressed(Item)  :- item_opts(Item, O), memberchk(pressed(true), O).
item_disabled(Item) :- item_opts(Item, O), memberchk(disabled(true), O).

pick_active(Items, Active) :-
    (   member(Active, Items), item_opts(Active, _),
        item_pressed(Active), \+ item_disabled(Active)
    ->  true
    ;   member(Active, Items), item_opts(Active, _),
        \+ item_disabled(Active)
    ->  true
    ).

set_active_if(Active, Item, ItemOut) :-
    (   Item == Active
    ->  add_active_true(Item, ItemOut)
    ;   ItemOut = Item
    ).

add_active_true(toggle_group_item(O0), toggle_group_item([active(true)|O0])) :- !.
add_active_true(toggle_group_item(O0, C), toggle_group_item([active(true)|O0], C)) :- !.
add_active_true(Other, Other).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Toggle Group is this library's first Phase-4 "roving-focus
%   consumer" (adr/0026 rule 8's porting order, right after the
%   Phase-3 native-backed family) -- Order 12 is the next free slot (1
%   visually_hidden, 2 accessible_icon, 3 label, 4 separator, 5
%   collapsible, 6 progress, 7 toggle, 8 radio_group, 9 checkbox/switch
%   already both registered at 9 -- a pre-existing collision this port
%   does not repeat, 10 aspect_ratio, 11 avatar already registered).
px_ui:demo(toggle_group, 12, \toggle_group_demo).

%   Arity-0, so it is an ATOM -- called via the explicit \ escape, same
%   as every other component's demo template (a bare atom is a text
%   node, not a callable dispatch, in render/2 -- adr/0019). Four
%   groups: single-select, multiple-select, a disabled item inside an
%   otherwise-ordinary multiple-select group, and a vertical
%   single-select group -- covers every option this port exposes.
toggle_group_demo ~>
    div(class("px-toggle-group-demo"),
      [ h3("type(single) -- role=\"radiogroup\", exactly one Item pressed"),
        p("Arrow keys move focus AND selection (role=\"radio\" + aria-checked); Home/End jump to the ends."),
        toggle_group([id("tg-single"), type(single)],
          [ toggle_group_item([pressed(true)], "Left"),
            toggle_group_item([], "Center"),
            toggle_group_item([], "Right")
          ]),

        h3("type(multiple) -- role=\"toolbar\", independent aria-pressed per Item"),
        p("Each Item toggles independently; arrow keys still move the single roving tab stop across all three."),
        toggle_group([id("tg-multiple"), type(multiple)],
          [ toggle_group_item([pressed(true)], "Bold"),
            toggle_group_item([pressed(true)], "Italic"),
            toggle_group_item([], "Underline")
          ]),

        h3("Disabled item"),
        p("The disabled Item is skipped by both the auto-picked tab stop and arrow-key navigation."),
        toggle_group([id("tg-disabled"), type(multiple)],
          [ toggle_group_item([], "Left"),
            toggle_group_item([disabled(true)], "Center (disabled)"),
            toggle_group_item([], "Right")
          ]),

        h3("Vertical orientation"),
        p("orientation(vertical) -- data-orientation=\"vertical\"; ArrowUp/ArrowDown replace ArrowLeft/ArrowRight."),
        toggle_group([id("tg-vertical"), type(single), orientation(vertical)],
          [ toggle_group_item([pressed(true)], "Small"),
            toggle_group_item([], "Medium"),
            toggle_group_item([], "Large")
          ])
      ]).
