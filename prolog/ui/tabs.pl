:- module(ui_tabs, []).

%   No predicates are exported: tabs/2, tabs_root/2, tabs_list/2,
%   tabs_trigger/1,2, tabs_content/1,2 are never called module-qualified
%   -- they are term SHAPES that px_template's bare-call dispatch
%   resolves via the multifile tmpl/2 / render_helper/2 tables
%   (adr/0019), the same pattern prolog/ui/toggle_group.pl uses.

/** <module> Tabs (adr/0026): layered content sections shown one at a
time, roving-focus keyboard nav across triggers, automatic (focus-
driven) activation.

Ported from Radix UI's Tabs primitive (docs/radix-port-analysis.md,
"Tabs" entry). Anatomy: `Root` (`tabs_root/2`), `List` (`tabs_list/2`,
`role="tablist"`, wraps roving-focus), `Trigger` (`tabs_trigger/1,2`,
`role="tab"`, one per tab), `Content` (`tabs_content/1,2`,
`role="tabpanel"`, a SIBLING of List inside Root, not a child of
Trigger). `tabs/2` is the rule-1 top-level convenience template
assembling the common case: Root wrapping one List of Triggers followed
by every Content, with the trigger<->panel id-wiring
(`aria-controls`/`aria-labelledby`/`id`) computed automatically and each
part's `data-state`/`aria-selected`/`hidden` computed by comparing the
tab's own `value(_)` against Root's `value(_)` (adr/0026 rule 1: "Opts
is a list; parts are template terms").

Tabs is this library's second roving-focus consumer (adr/0026 rule 5;
`prolog/ui/toggle_group.pl` was the first, proving
`assets/js/lib/roving-focus.js`'s `installRovingFocus/2` API) --
`assets/js/components/tabs.js`'s `<px-tabs>` installs it on the List,
exactly the toggle_group.js precedent, PLUS the one behaviour Toggle
Group never needed: automatic activation (selecting a tab just by
moving focus/keyboard nav to it, no separate Enter/Space press), the
analysis doc's own default (`activationMode="automatic"`).

**Interactivity class: CUSTOM-ELEMENT -- unavoidably** (the analysis
doc's own verdict: "real state-machine work: roving-tabindex + activation
modes"). Which tab is selected server-side (`value(_)` at render time)
is perfectly reload-safe and JS-free; `<px-tabs>` is the one irreducible
sliver that keeps `data-state`/`aria-selected`/`hidden` live as the user
tabs/arrows/clicks between triggers, wrapping the whole Root once (like
`<px-toggle-group>`, not once per Trigger).

DOM/ARIA contract emitted (docs/radix-port-analysis.md's "Tabs" entry):

    Root     <div data-orientation="horizontal|vertical">                (inside <px-tabs>)
    List     <div role="tablist" aria-orientation="horizontal|vertical">
    Trigger  <button type="button" role="tab" aria-selected="true|false"
                     aria-controls="{contentId}" data-state="active|inactive"
                     data-disabled tabindex="0|-1" id="{triggerId}">
    Content  <div role="tabpanel" aria-labelledby="{triggerId}"
                  data-state="active|inactive" data-orientation="..."
                  tabindex="0" hidden id="{contentId}">

Two additive-only extensions, noted per rule 2:

  1. `data-orientation` on Root. Not literally in the analysis doc's own
     summary line for Root (only List's `aria-orientation` and Content's
     `data-orientation` are named there), but upstream Radix's real
     `Tabs.Root` renders it too, and this port needs SOME single
     attribute `assets/css/ui.css` can key the whole component's
     row-vs-column layout off (List and each Content are siblings, not
     nested, so a single shared selector needs a common ancestor
     attribute) -- the same "DOM-level encoding" justification
     toggle_group.pl's own extensions use.
  2. `tabindex="0"`/`"-1"` on every Trigger, ALWAYS explicit -- not in
     the doc's prose (upstream expresses this as `RovingFocusGroupItem`
     wrapping, a React behaviour, not a named rendered attribute) but
     exactly the DOM-level encoding `installRovingFocus/2` reads on
     install (same justification as toggle_group.pl's extension 1).
     Here the current tab stop is always exactly the SELECTED trigger
     (Tabs' default `activationMode="automatic"` means "focused" and
     "selected" can never disagree in the no-JS-disabled-trigger case),
     so -- unlike Toggle Group, which needed a separate `active(_)` opt
     because a Toggle Group's pressed item and its roving tab stop are
     independent concepts -- Tabs' `selected(Bool)` alone drives both
     `aria-selected`/`data-state` AND `tabindex`.

`data-loop` on List mirrors toggle_group.pl's own convention (an
empty-string data attribute is the only markup-level way to hand
`<px-tabs>` a boolean flag with no upstream-rendered attribute of its
own -- Radix's `loop` prop is a plain JS default) with ONE default flip,
documented explicitly: Tabs' own Radix default is `loop=true`
("optional `loop` (default true)" -- the analysis doc's own words),
the opposite of Toggle Group's `loop=false` default.

Options (a plain list, adr/0026 rule 1):

  `tabs_root/2` Opts:
    orientation(horizontal|vertical)  default `horizontal`. Drives
                    `data-orientation` (extension 1 above).
    class(C)        merged with the default class, default first
                    ("px-tabs C").
    anything else (id(...), aria_label(...), data_*(...), ...) passed
                    through verbatim, appended AFTER the computed
                    attributes -- same last-wins spread order as every
                    other port in this library.

  `tabs_list/2` Opts:
    orientation(horizontal|vertical)  default `horizontal`. Drives
                    `aria-orientation` (the analysis doc's own List
                    contract) -- also what `<px-tabs>` reads to pick
                    `installRovingFocus/2`'s `orientation` option.
    loop(Bool)      `true`/`false`, default `true` (Radix's own Tabs
                    default -- see above). Emits `data-loop=""` only
                    when `true`.
    class(C)        merged with the default class, default first
                    ("px-tabs-list C").
    anything else   passed through verbatim, same rule as Root.

  `tabs_trigger/1,2` Opts:
    selected(Bool)  `true`/`false`, default `false`. Drives
                    `aria-selected`, `data-state` (active|inactive) AND
                    `tabindex` (0 when selected, -1 otherwise --
                    extension 2 above; the current roving-focus tab
                    stop is always the selected trigger under automatic
                    activation).
    disabled(Bool)  `true`/`false`, default `false`. Adds
                    `data-disabled=""` plus the native `disabled`
                    attribute; excludes the Trigger from
                    `installRovingFocus/2`'s arrow-key targets and from
                    `tabs/2`'s selection (a disabled tab can never be
                    the matched `value(_)` in practice -- the caller
                    simply should not pass `disabled(true)` on the
                    currently-selected item).
    controls(Id)    the Content's id this Trigger discloses; emitted as
                    `aria-controls`. Not a Radix prop the way it reads
                    here -- Radix's Trigger reads it off context
                    internally; here, since there is no context,
                    `tabs/2` (below) is what supplies it when assembling
                    the common case, same role as collapsible.pl's own
                    `controls(Id)` Trigger option.
    class(C)        merged with the default class, default first
                    ("px-tabs-trigger C").
    anything else (id(...), aria_label(...), ...) passed through
                    verbatim onto the `<button>`, appended AFTER the
                    computed attributes. `tabs_trigger/1` is the
                    no-label shorthand (Children = []).

  `tabs_content/1,2` Opts:
    selected(Bool)  `true`/`false`, default `false`. Drives
                    `data-state` (active|inactive) and whether `hidden`
                    is emitted (present when NOT selected, absent when
                    selected -- the doc's own `hidden={!present}`).
    orientation(horizontal|vertical)  default `horizontal`. Drives
                    `data-orientation` (the doc's own Content contract).
    labelledby(Id)  the Trigger's id that discloses this Content;
                    emitted as `aria-labelledby`. Same role as
                    `controls(Id)` above, supplied by `tabs/2` when
                    assembling the common case.
    class(C)        merged with the default class, default first
                    ("px-tabs-content C").
    anything else   passed through verbatim onto the `<div>`, same rule
                    as Trigger. `tabindex="0"` is ALWAYS emitted (the
                    doc's own `tabIndex={0}`, unconditional -- unlike
                    Trigger's roving 0/-1, Content is not part of the
                    roving-focus domain at all). `tabs_content/1` is the
                    no-children shorthand.

  `tabs/2` Opts: everything `tabs_root/2` takes, PLUS
    value(V)        REQUIRED. The identifier of the currently-active
                    tab -- compared (see `tabs_item/3` below) against
                    every item's own `value(_)` to compute that item's
                    `selected(Bool)`. No sane default (mirrors
                    toggle_group_root/2's required `type(_)`: there is
                    no meaningful "no tab selected" state for a
                    single-select tablist).
    loop(Bool)      forwarded to `tabs_list/2`, default `true`.
    id(Id)          optional; also the base every item's derived
                    trigger/content ids are built from
                    (`<Id>-<Value>-trigger`/`-content`) unless an item
                    supplies its own `id(_)`. Defaults to a fresh
                    gensym'd `px-tabs-N` when absent (mirrors
                    collapsible.pl's own `content_id/2` gensym
                    fallback).

  `tabs/2` second argument: a list of `tabs_item(ItemOpts, TriggerKids,
                    ContentKids)` terms ONLY -- a deliberate, documented
                    deviation from toggle_group.pl's/radio_group.pl's
                    "pass any other term through unmodified" rule
                    (rule 2): each Tabs item's markup is split across
                    TWO different structural locations (its Trigger
                    lives inside List; its Content lives as a Root-level
                    sibling of List) -- there is no single sensible
                    "pass through unmodified" placement for an arbitrary
                    interleaved term the way there is for toggle_group's
                    flat single-level Item list. `ItemOpts` recognises:
      value(V)        REQUIRED. This item's own tab identifier, compared
                      against `tabs/2`'s Opts `value(_)` (via
                      `atom_string/2` normalisation, so `foo`/`"foo"`
                      compare equal) to compute `selected(Bool)`.
      disabled(Bool)  `true`/`false`, default `false`. Forwarded to the
                      generated Trigger only (Content has no disabled
                      concept in the contract).
      id(Id)          optional per-item id base override (see `tabs/2`'s
                      own `id(Id)` above).

Both `tabs_root/2`/`tabs_list/2`/`tabs_trigger/1,2`/`tabs_content/1,2`
and `tabs/2` are registered as `px_template:render_helper/2` hooks
(adr/0019) -- the Opts-list defaults/merge/id-wiring/value-matching logic
below is genuine computation, the same reason toggle_group.pl,
collapsible.pl and radio_group.pl register theirs the same way.
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

valid_orientation(horizontal).
valid_orientation(vertical).

%!  require_opt(+Opts, +Key, +Context, -Value) is det.
%
%   Same helper as toggle_group.pl's: reads Key(Value) out of Opts, or
%   throws a clear existence_error naming both the missing option and
%   the template that needed it.
require_opt(Opts, Key, Context, Value) :-
    Probe =.. [Key, Value],
    (   memberchk(Probe, Opts)
    ->  true
    ;   throw(error(existence_error(option, Key), context(Context, _)))
    ).

%!  take_bool(+Name, +Default, +Opts0, -Value, -Rest) is det.
%
%   Pulls Name(Value) out of Opts0, defaulting to Default when absent --
%   the same shape as toggle_group.pl's/switch.pl's own take_bool/4,
%   generalised with an explicit default so this module can reuse it for
%   both `selected`/`disabled` (default `false`) and `loop` (Tabs'
%   default `true`, the opposite of toggle_group.pl's).
take_bool(Name, Default, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Rest)
    ->  Value = V0
    ;   Value = Default, Rest = Opts0
    ).

%!  take_orientation(+Opts0, -Orientation, -Rest) is det.
%
%   Orientation(_) out of Opts0 (default `horizontal`, same fallback an
%   invalid value gets) -- ALWAYS removed from Rest so a caller-supplied
%   orientation(_) never leaks through to the pass-through Extra tail.
take_orientation(Opts0, Orientation, Rest) :-
    (   selectchk(orientation(O), Opts0, Rest0)
    ->  ( valid_orientation(O) -> Orientation = O ; Orientation = horizontal ),
        Rest = Rest0
    ;   Orientation = horizontal, Rest = Opts0
    ).

%!  merge_class(+Opts0, +Default, -ClassVal, -Rest) is det.
%
%   Same helper as toggle_group.pl's/progress.pl's.
merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  tab_state(+Selected, -State) is det.
%
%   State in active|inactive -- the analysis doc's own
%   `data-state={active ? "active" : "inactive"}`.
tab_state(true, active) :- !.
tab_state(_,    inactive).

		 /*******************************
		 *             ROOT             *
		 *******************************/

%!  tabs_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `tabs_root([orientation(vertical)],
%   [List, Content1, Content2])`. Renders the `<px-tabs>` custom-element
%   wrapper (adr/0026 rule 4) around the server-rendered `<div>` -- the
%   wrapper is what the custom element registers against; the markup
%   inside is exactly as usable (minus arrow-key roving nav and
%   automatic focus-activation -- plain Tab-through to the selected
%   trigger, whose panel is already correctly un-hidden server-side,
%   still works) if `<px-tabs>` is never upgraded.
px_template:render_helper(tabs_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_tabs, [], [div(Attrs, Children)]).

root_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_orientation(Opts0, Orientation, Opts1),
    merge_class(Opts1, "px-tabs", ClassVal, Opts2),
    append([ [data_orientation(Orientation), class(ClassVal)], Opts2 ], Attrs).

		 /*******************************
		 *             LIST             *
		 *******************************/

%!  tabs_list(+Opts, +Children) is det.
%
%   Bare-call template surface: `tabs_list([orientation(vertical)],
%   Triggers)`.
px_template:render_helper(tabs_list(Opts, Children), S) :-
    list_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, Children)).

list_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_orientation(Opts0, Orientation, Opts1),
    take_bool(loop, true, Opts1, Loop, Opts2),
    merge_class(Opts2, "px-tabs-list", ClassVal, Opts3),
    loop_attrs(Loop, LoopAttrs),
    append([ [role(tablist), aria_orientation(Orientation)],
             LoopAttrs, [class(ClassVal)], Opts3
           ], Attrs).

loop_attrs(true, [data_loop("")]) :- !.
loop_attrs(_,    []).

		 /*******************************
		 *            TRIGGER           *
		 *******************************/

%!  tabs_trigger(+Opts) is det.
%!  tabs_trigger(+Opts, +Children) is det.
%
%   Bare-call template surface: `tabs_trigger([selected(true),
%   controls(Id)], "Account")`. `tabs_trigger/1` is the no-label
%   shorthand (Children = []), same `/1` delegates to `/2` shape as
%   toggle_group.pl's `toggle_group_item/1,2`.
px_template:render_helper(tabs_trigger(Opts), S) :-
    px_template:render_helper(tabs_trigger(Opts, []), S).
px_template:render_helper(tabs_trigger(Opts, Children), S) :-
    trigger_attrs(Opts, Attrs),
    px_template:render(S, button(Attrs, Children)).

trigger_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_bool(selected, false, Opts0, Selected, Opts1),
    take_bool(disabled, false, Opts1, Disabled, Opts2),
    take_controls(Opts2, ControlsOpt, Opts3),
    merge_class(Opts3, "px-tabs-trigger", ClassVal, Opts4),
    tab_state(Selected, State),
    controls_attrs(ControlsOpt, ControlsAttrs),
    tabindex_attrs(Selected, TabAttrs),
    trigger_disabled_attrs(Disabled, DisAttrs),
    append([ [type(button), role(tab), aria_selected(Selected)],
             ControlsAttrs, [data_state(State)], TabAttrs,
             [class(ClassVal)], DisAttrs, Opts4
           ], Attrs).

take_controls(Opts0, ControlsOpt, Rest) :-
    (   selectchk(controls(Id), Opts0, Rest)
    ->  ControlsOpt = controls(Id)
    ;   ControlsOpt = none, Rest = Opts0
    ).

controls_attrs(controls(Id), [aria_controls(Id)]) :- !.
controls_attrs(none, []).

tabindex_attrs(true, [tabindex(0)])  :- !.
tabindex_attrs(_,    [tabindex(-1)]).

trigger_disabled_attrs(true, [data_disabled(""), disabled]) :- !.
trigger_disabled_attrs(_,    []).

		 /*******************************
		 *            CONTENT           *
		 *******************************/

%!  tabs_content(+Opts) is det.
%!  tabs_content(+Opts, +Children) is det.
%
%   Bare-call template surface: `tabs_content([selected(true),
%   labelledby(Id)], "...")`. `tabs_content/1` is the no-children
%   shorthand.
px_template:render_helper(tabs_content(Opts), S) :-
    px_template:render_helper(tabs_content(Opts, []), S).
px_template:render_helper(tabs_content(Opts, Children), S) :-
    content_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, Children)).

content_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_bool(selected, false, Opts0, Selected, Opts1),
    take_orientation(Opts1, Orientation, Opts2),
    take_labelledby(Opts2, LOpt, Opts3),
    merge_class(Opts3, "px-tabs-content", ClassVal, Opts4),
    tab_state(Selected, State),
    labelledby_attrs(LOpt, LabelledbyAttrs),
    hidden_attrs(Selected, HiddenAttrs),
    append([ [role(tabpanel)], LabelledbyAttrs,
             [data_state(State), data_orientation(Orientation),
              tabindex(0), class(ClassVal)],
             HiddenAttrs, Opts4
           ], Attrs).

take_labelledby(Opts0, LOpt, Rest) :-
    (   selectchk(labelledby(Id), Opts0, Rest)
    ->  LOpt = labelledby(Id)
    ;   LOpt = none, Rest = Opts0
    ).

labelledby_attrs(labelledby(Id), [aria_labelledby(Id)]) :- !.
labelledby_attrs(none, []).

%   `hidden={!present}` (the doc's own words): present (bare `hidden`
%   attribute) exactly when NOT selected.
hidden_attrs(true, []) :- !.
hidden_attrs(_,    [hidden]).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  tabs(+Opts, +Items) is det.
%
%   The common case: Root wrapping one List of Triggers followed by
%   every Content (siblings, per the anatomy), with `selected(Bool)`
%   computed per item by matching its own `value(_)` against Opts'
%   `value(_)`, and the Trigger<->Content id-wiring
%   (`aria-controls`/`aria-labelledby`/`id`) generated automatically.
tabs(Opts, Items) ~> \tabs_render(Opts, Items).

px_template:render_helper(tabs_render(Opts0, Items), S) :-
    must_be(list, Opts0),
    require_opt(Opts0, value, tabs/2, RootValue),
    selectchk(value(_), Opts0, Opts1),
    take_orientation(Opts1, Orientation, Opts2),
    take_bool(loop, true, Opts2, Loop, Opts3),
    take_root_base(Opts3, RootBase, Opts4),
    maplist(build_item(RootBase, RootValue, Orientation), Items,
            Triggers, Contents),
    RootOpts = [orientation(Orientation), id(RootBase) | Opts4],
    ListOpts = [orientation(Orientation), loop(Loop)],
    px_template:render(S,
        tabs_root(RootOpts,
          [ tabs_list(ListOpts, Triggers)
          | Contents
          ])).

%!  take_root_base(+Opts0, -RootBase, -Rest) is det.
%
%   `id(Base)` from Opts0 if the caller supplied one (ALSO removed from
%   Rest -- it is re-added, once, by tabs_render/2 above, so it must not
%   double up via the Extra pass-through tail); otherwise a fresh
%   gensym'd `px-tabs-N` -- same fallback shape as collapsible.pl's own
%   `content_id/2`.
take_root_base(Opts0, RootBase, Rest) :-
    (   selectchk(id(Id), Opts0, Rest)
    ->  RootBase = Id
    ;   Rest = Opts0, gensym('px-tabs-', RootBase)
    ).

%!  build_item(+RootBase, +RootValue, +Orientation, +Item, -Trigger, -Content) is det.
%
%   Item = `tabs_item(ItemOpts, TriggerKids, ContentKids)`. Computes
%   `Selected` by comparing ItemOpts' own REQUIRED `value(_)` against
%   RootValue (`values_match/2`, below), derives this item's
%   trigger/content id pair from RootBase + the item's own `value(_)`
%   (or its own `id(_)` override), and wires `controls(_)`/
%   `labelledby(_)` between them.
build_item(RootBase, RootValue, Orientation,
           tabs_item(ItemOpts, TriggerKids, ContentKids),
           tabs_trigger(TriggerOpts, TriggerKids),
           tabs_content(ContentOpts, ContentKids)) :-
    require_opt(ItemOpts, value, tabs_item/3, ItemValue),
    take_bool(disabled, false, ItemOpts, Disabled, _),
    (   values_match(ItemValue, RootValue)
    ->  Selected = true
    ;   Selected = false
    ),
    item_base(RootBase, ItemValue, ItemOpts, Base),
    format(atom(TriggerId), '~w-trigger', [Base]),
    format(atom(ContentId), '~w-content', [Base]),
    TriggerOpts = [ selected(Selected), disabled(Disabled),
                     controls(ContentId), id(TriggerId)
                   ],
    ContentOpts = [ selected(Selected), orientation(Orientation),
                     labelledby(TriggerId), id(ContentId)
                   ].

%!  item_base(+RootBase, +ItemValue, +ItemOpts, -Base) is det.
%
%   ItemOpts' own `id(_)` if supplied, else `<RootBase>-<ItemValue>`.
item_base(RootBase, ItemValue, ItemOpts, Base) :-
    (   memberchk(id(B), ItemOpts)
    ->  Base = B
    ;   format(atom(Base), '~w-~w', [RootBase, ItemValue])
    ).

%!  values_match(+A, +B) is semidet.
%
%   True when A and B print identically once both are normalised to a
%   string via atom_string/2 -- so `value(account)` (an item's own
%   value) and `value("account")` (Opts' Root value, or vice versa)
%   compare equal regardless of which atomic type the caller happened
%   to use for either side.
values_match(A, B) :-
    atomic(A), atomic(B),
    atom_string(A, SA), atom_string(B, SB),
    SA == SB.

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Order 13 is the next free slot after toggle_group.pl's Order 12
%   (adr/0026 rule 8's porting order: Tabs is a roving-focus consumer,
%   same phase as Toggle Group).
px_ui:demo(tabs, 13, \tabs_demo).

%   Arity-0, so it is an ATOM -- called via the explicit \ escape, same
%   as every other component's demo template (a bare atom is a text
%   node, not a callable dispatch, in render/2 -- adr/0019). Two groups:
%   a horizontal 3-tab tablist with one disabled tab, and a vertical
%   variant -- covers every option this port exposes.
tabs_demo ~>
    div(class("px-tabs-demo"),
      [ h3("Horizontal (default) -- one tab disabled"),
        p("Tab into the tablist, then arrow keys move focus AND selection together (automatic activation); the disabled trigger is skipped by both."),
        tabs([id("tabs-demo-h"), value(account)],
          [ tabs_item([value(account)], "Account",
              [ h4("Account"), p("Manage your account details and preferences.") ]),
            tabs_item([value(billing), disabled(true)], "Billing (disabled)",
              [ p("Billing settings -- unreachable while disabled.") ]),
            tabs_item([value(notifications)], "Notifications",
              [ h4("Notifications"), p("Configure how and when you're notified.") ])
          ]),

        h3("Vertical"),
        p("orientation(vertical) -- aria-orientation on the tablist, data-orientation on Root/Content; ArrowUp/ArrowDown replace ArrowLeft/ArrowRight, loop(true) (Tabs' own default) wraps past the last tab back to the first."),
        tabs([id("tabs-demo-v"), value(general), orientation(vertical)],
          [ tabs_item([value(general)], "General",
              [ p("General settings.") ]),
            tabs_item([value(security)], "Security",
              [ p("Security settings.") ]),
            tabs_item([value(advanced)], "Advanced",
              [ p("Advanced settings.") ])
          ])
      ]).
