:- module(ui_dropdown_menu, []).

%   No predicates are exported: dropdown_menu/2, dropdown_menu_root/2,
%   dropdown_menu_trigger/2, dropdown_menu_content/2 are never called
%   module-qualified -- bare-call dispatch through px_template's
%   tmpl/2 / render_helper/2 tables resolves them (adr/0019), the same
%   pattern prolog/ui/popover.pl uses. Every anatomy part beyond
%   Root/Trigger/Content is a direct re-export of `prolog/ui/_menu.pl`'s
%   shared vocabulary -- `menu_item/1,2`, `menu_checkbox_item/2`,
%   `menu_radio_group/2`, `menu_radio_item/2`, `menu_label/2`,
%   `menu_separator/1`, `menu_sub/2` -- used directly, unwrapped, by
%   any caller composing a Dropdown Menu's Content; this module adds
%   NO `dropdown_menu_item/2`-style renamed wrappers around them (the
%   analysis doc's own framing: Dropdown Menu "supplies only its own
%   trigger-opening semantics on top" of the shared Menu primitive).

/** <module> Dropdown Menu (adr/0026): click-triggered menu anchored to
a real trigger `<button>` -- the standard app-menu pattern, and this
library's proving consumer for `prolog/ui/_menu.pl` /
`assets/js/lib/menu.js` (the shared Menu engine, ported once as
`docs/radix-port-analysis.md`'s "Menu (shared machinery, not a public
component)" entry requires: "any port of [dropdown-menu, context-menu,
menubar] requires porting this state machine ONCE... rather than three
times").

Ported from Radix UI's DropdownMenu primitive (docs/radix-port-
analysis.md, "Dropdown Menu" entry). Anatomy: `Root` (`dropdown_menu_root/2`),
`Trigger` (`dropdown_menu_trigger/2`), `Content` (`dropdown_menu_content/2`,
a thin wrapper over `_menu.pl`'s `menu_content/2` -- see below), plus
every part `_menu.pl` already exports used directly (`menu_item/1,2`,
`menu_checkbox_item/2`, `menu_radio_group/2`, `menu_radio_item/2`,
`menu_label/2`, `menu_separator/1`, `menu_sub/2`/`menu_sub_trigger/2`/
`menu_sub_content/2`, `menu_item_indicator/2`, `menu_arrow/1`).
`dropdown_menu/2` is the rule-1 top-level convenience: a Root wrapping
one Trigger and one Content, id-wiring (`aria-controls`/`popovertarget`/
`aria-labelledby`/`id`) and `open(_)` threaded automatically, same
division of labour as `popover/2`.

**What this module adds on top of the shared Menu primitive** (the
analysis doc's own framing -- "Dropdown Menu's own incremental logic
is straightforward"):

  - A real, stable `<button>` Trigger (not Context Menu's virtual
    point): `aria-haspopup="menu"` (Menu's own haspopup value --
    DIFFERENT from Dialog/Popover's `"dialog"`), `aria-expanded`,
    `aria-controls`, `data-state`, PLUS native `popovertarget` pointing
    at Content's id -- same "declarative zero-JS baseline, JS layers
    semantics on top" platform split `popover.pl`'s own Trigger uses
    (see "Platform choice" below): a page with
    `assets/js/components/dropdown_menu.js` never loaded still opens/
    closes Content on click, native `popover="auto"` light-dismiss
    still works, just without ArrowDown-always-opens, auto-focus-first-
    item, or any of `lib/menu.js`'s own item interactions.
  - Content: `aria-labelledby={triggerId}` -- Context Menu's own future
    Content has no such link (it has no persistent trigger element);
    Dropdown Menu's does, wired automatically by `dropdown_menu/2`.

**Platform choice (adr/0026 rule 3) -- native `popovertarget` +
`popover="auto"` carries open/close/light-dismiss; `assets/js/lib/menu.js`
carries everything the analysis doc names as genuinely irreducible
(roving highlight, typeahead, submenu hover/keyboard/positioning,
checkbox/radio toggling, close-on-select).** Exactly `popover.pl`'s own
split, ported to Menu's own `aria-haspopup="menu"` contract:

  - Trigger renders BOTH `aria-controls` (the sacred contract) AND the
    native `popovertarget` attribute (additive, same convention as
    `popover_trigger/2`) pointing at Content's id -- clicking it opens/
    closes Content, Enter/Space activate it too (native button
    activation, not anything this port re-implements), with zero JS.
  - Content renders the native `popover="auto"` attribute (via
    `_menu.pl`'s `menu_content/2`, which every Content level already
    carries) -- Escape-to-dismiss, outside-click-to-dismiss, and
    top-layer stacking are the browser's job.
  - `assets/js/components/dropdown_menu.js`'s `<px-dropdown-menu>` is
    the irreducible sliver: ArrowDown-always-opens (native
    `popovertarget` only TOGGLES, so an already-open menu must not be
    re-closed by ArrowDown -- ArrowDown needs its own `showPopover()`
    call, guarded), auto-focusing the first item on every open path
    (click OR ArrowDown), wiring `lib/menu.js` onto Content once, and
    mirroring `data-state`/`aria-expanded` off the native `toggle`
    event so they never drift from what the browser actually did --
    the exact same `beforetoggle`/`toggle` split `popover.js`/
    `hover_card.js` already established.

**Gap (documented, not shipped as JS): `modal(true)` has no native
counterpart, same gap `popover.pl` already accepts.** Upstream
DropdownMenu defaults `modal` to `true` (focus-trapped, outside pointer
events disabled, siblings `aria-hidden`d); this port ships only the
`popover="auto"`-native equivalent -- top-layer stacking and light-
dismiss, no focus trap, no scroll lock, no sibling `aria-hidden`ing --
same `modal=false`-shaped subset `popover.pl`'s own header documents,
for the identical reason (rule 8: Dialog's focus-trap/branch-registry
machinery, this gap's actual dependency, has not been extended to Menu
yet). No `modal(_)` option exists on any part here.

**DOM/ARIA contract emitted** (docs/radix-port-analysis.md's "Dropdown
Menu" entry plus `_menu.pl`'s own Content contract, adr/0026 rule 2):

    Trigger (`<button>`): aria-haspopup="menu", aria-expanded,
                          aria-controls (Content's id), data-state,
                          PLUS native popovertarget (additive).
    Content (`<div>`):   role="menu" (via menu_content/2), popover="auto",
                          tabindex="-1", data-state, data-side,
                          data-align, data-side-offset, data-align-offset,
                          aria-labelledby (Trigger's id, when
                          `dropdown_menu/2` assembles the common case,
                          or when a standalone caller supplies
                          `labelledby(_)`).

Options (plain lists, adr/0026 rule 1):

  `dropdown_menu_root/2` Opts:
    class(C)        merged with the default class, default first
                    ("px-dropdown-menu C").
    anything else   passed through verbatim, appended AFTER the
                    computed attributes.

  `dropdown_menu_trigger/2` Opts:
    open(Bool)      default `false`. Drives `aria-expanded`,
                    `data-state` (open|closed).
    controls(Id)    REQUIRED for a standalone call to actually wire
                    anything (Content's id) -- emitted as BOTH
                    `aria-controls` and the native `popovertarget`.
                    Without it the Trigger still renders (a plain,
                    inert button) rather than throwing -- same
                    graceful-degradation posture as `popover_trigger/2`.
    class(C), anything else  pass-through, as usual.

  `dropdown_menu_content/2` Opts: everything `menu_content/2` takes
                    (`id(_)`, `open(_)`, `labelledby(_)`, `side(_)`
                    default `bottom`, `align(_)` default `start`,
                    `side_offset(_)`, `align_offset(_)`, `class(_)`) --
                    forwarded verbatim; this template adds no new
                    option of its own, only the `dropdown_menu_content`
                    bare-call name (so a caller composing a Dropdown
                    Menu by hand can spell it the way it reads, even
                    though it renders byte-identically to calling
                    `menu_content/2` directly).

  `dropdown_menu/2` Opts: everything `dropdown_menu_root/2` takes, PLUS
    open(Bool)      default `false`. Forwarded to both Trigger and
                    Content.
    side(_), align(_), side_offset(_), align_offset(_)  forwarded to
                    Content, same defaults as `dropdown_menu_content/2`.
    id(Id)          optional; base every generated part's id is built
                    from (`<Id>-trigger`/`-content`); gensym'd
                    (`px-dropdown-menu-N`) when absent, same convention
                    as `popover/2`'s `content_id/2`.

  `dropdown_menu/2` second argument: `[TriggerChildren, ContentChildren]`
                    (mirrors `popover/2`'s Parts shape exactly).
*/

:- use_module(library(lists)).
:- use_module(library(gensym)).
:- use_module('../px_template').
:- use_module('_menu').

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

		 /*******************************
		 *        OPTION HELPERS        *
		 *******************************/

take_bool(Name, Default, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Rest)
    ->  ( V0 == true -> Value = true ; Value = false )
    ;   Value = Default, Rest = Opts0
    ).

take_controls(Opts0, ControlsOpt, Rest) :-
    (   selectchk(controls(Id), Opts0, Rest)
    ->  ControlsOpt = controls(Id)
    ;   ControlsOpt = none, Rest = Opts0
    ).

state_atom(true,  open)   :- !.
state_atom(false, closed).

merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

		 /*******************************
		 *             ROOT             *
		 *******************************/

%!  dropdown_menu_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `dropdown_menu_root([], [Trigger,
%   Content])`. Renders the `<px-dropdown-menu>` custom-element wrapper
%   (adr/0026 rule 4) around a server-rendered `<div>` -- without JS
%   upgrade, Trigger's native `popovertarget` still fully opens/closes
%   Content (native `popover="auto"` handles dismissal); see the module
%   header's "Platform choice" for exactly what stays and what's lost.
px_template:render_helper(dropdown_menu_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_dropdown_menu, [], [div(Attrs, Children)]).

root_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-dropdown-menu", ClassVal, Opts1),
    append([ [class(ClassVal)], Opts1 ], Attrs).

		 /*******************************
		 *            TRIGGER           *
		 *******************************/

%!  dropdown_menu_trigger(+Opts, +Children) is det.
%
%   Bare-call template surface: `dropdown_menu_trigger([open(true),
%   controls(Id)], "Open menu")`.
px_template:render_helper(dropdown_menu_trigger(Opts, Children), S) :-
    trigger_attrs(Opts, Attrs),
    px_template:render(S, button(Attrs, Children)).

trigger_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_bool(open, false, Opts0, Open, Opts1),
    take_controls(Opts1, ControlsOpt, Opts2),
    merge_class(Opts2, "px-dropdown-menu-trigger", ClassVal, Opts3),
    state_atom(Open, State),
    (   ControlsOpt = controls(Id)
    ->  WireAttrs = [aria_controls(Id), popovertarget(Id)]
    ;   WireAttrs = []
    ),
    append([ [type(button), aria_haspopup(menu)],
             WireAttrs,
             [aria_expanded(Open), data_state(State), class(ClassVal)],
             Opts3
           ], Attrs).

		 /*******************************
		 *            CONTENT           *
		 *******************************/

%!  dropdown_menu_content(+Opts, +Children) is det.
%
%   Bare-call template surface: `dropdown_menu_content([id("m1"),
%   open(true), labelledby("m1-trigger")], [...])`. A thin rename over
%   `menu_content/2` -- see the module header for why no attribute
%   computation lives here at all.
px_template:render_helper(dropdown_menu_content(Opts, Children), S) :-
    must_be(list, Opts),
    px_template:render(S, menu_content(Opts, Children)).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  dropdown_menu(+Opts, +Parts) is det.
%
%   Parts = [TriggerChildren, ContentChildren]. The common case: a Root
%   wrapping one Trigger and one Content, `open(_)` threaded to both,
%   Trigger's `aria-controls`/`popovertarget` wired to Content's `id`,
%   and Content's `aria-labelledby` wired to Trigger's `id` --
%   automatically, both directions, same division of labour as
%   `popover/2`.
dropdown_menu(Opts, Parts) ~> \dropdown_menu_render(Opts, Parts).

px_template:render_helper(dropdown_menu_render(Opts, [TriggerKids, ContentKids]), S) :-
    must_be(list, Opts),
    take_bool(open, false, Opts, Open, _),
    base_id(Opts, Base),
    format(atom(TriggerId), '~w-trigger', [Base]),
    format(atom(ContentId), '~w-content', [Base]),
    read_or_default(side, Opts, bottom, Side),
    read_or_default(align, Opts, start, Align),
    read_or_default(side_offset, Opts, 0, SideOffset),
    read_or_default(align_offset, Opts, 0, AlignOffset),
    exclude(convenience_only_opt, Opts, RootOpts),
    TriggerOpts = [open(Open), controls(ContentId), id(TriggerId)],
    ContentOpts = [ open(Open), id(ContentId), labelledby(TriggerId),
                     side(Side), align(Align),
                     side_offset(SideOffset), align_offset(AlignOffset)
                   ],
    px_template:render(S,
        dropdown_menu_root(RootOpts,
          [ dropdown_menu_trigger(TriggerOpts, TriggerKids),
            dropdown_menu_content(ContentOpts, ContentKids)
          ])).

%!  read_or_default(+Name, +Opts, +Default, -Value) is det.
%
%   Forwards Content-only positioning options (`side(_)`/`align(_)`/
%   `side_offset(_)`/`align_offset(_)`) from `dropdown_menu/2`'s own
%   Opts down to the assembled Content, same defaults `menu_content/2`
%   itself uses (`bottom`/`start`/`0`/`0`) when the caller didn't
%   override them here.
read_or_default(Name, Opts, Default, Value) :-
    Probe =.. [Name, V0],
    ( memberchk(Probe, Opts) -> Value = V0 ; Value = Default ).

%!  convenience_only_opt(+Opt) is semidet.
%
%   Trigger/Content-only concepts that must NOT leak onto Root's own
%   `<div>` as literal, meaningless HTML attributes -- same rationale
%   as `popover/2`'s own `convenience_only_opt/1`.
convenience_only_opt(open(_)).
convenience_only_opt(side(_)).
convenience_only_opt(align(_)).
convenience_only_opt(side_offset(_)).
convenience_only_opt(align_offset(_)).

%!  base_id(+Opts, -Base) is det.
%
%   `id(Base)` from Opts if the caller supplied one; otherwise a fresh
%   gensym'd id -- same convention as `popover.pl`'s `content_id/2`.
base_id(Opts, Base) :-
    (   memberchk(id(Base), Opts)
    ->  true
    ;   gensym(px_dropdown_menu_, Base)
    ).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Order 17: the next free slot after tooltip.pl's Order 16 (adr/0026
%   rule 8: Dropdown Menu is the menus tier's first entry, right after
%   the positioning tier Popover/Tooltip/HoverCard already landed --
%   Menu's own dependencies, popper + roving-focus concepts, are both
%   already merged).
px_ui:demo(dropdown_menu, 17, \dropdown_menu_demo).

dropdown_menu_demo ~>
    div(class("px-dropdown-menu-demo"),
      [ section(class("ui-demo-block"),
          [ h3("Basic -- items, shortcuts, separator, checkbox, radio group, submenu, disabled item"),
            p("Click the trigger (or focus it and press Enter/Space/ArrowDown): native popovertarget + popover=\"auto\" open/close/light-dismiss with zero JS; <px-dropdown-menu> layers ArrowDown-always-opens, auto-focus-first-item, and assets/js/lib/menu.js's full engine (roving highlight, typeahead, submenu hover+keyboard, checkbox/radio toggling, close-on-select) on top."),
            dropdown_menu([id("ddm-demo")],
              [ "Edit ▾",
                [ menu_arrow([]),
                  menu_item([], [span("Cut"), span(class("px-menu-shortcut"), "⌘X")]),
                  menu_item([], [span("Copy"), span(class("px-menu-shortcut"), "⌘C")]),
                  menu_item([], [span("Paste"), span(class("px-menu-shortcut"), "⌘V")]),
                  menu_separator([]),
                  menu_checkbox_item([checked(true)], "Show hidden files"),
                  menu_checkbox_item([], "Show line numbers"),
                  menu_separator([]),
                  menu_label([], "Text size"),
                  menu_radio_group([aria_label("Text size")],
                    [ menu_radio_item([value("sm")], "Small"),
                      menu_radio_item([value("md"), checked(true)], "Medium"),
                      menu_radio_item([value("lg")], "Large")
                    ]),
                  menu_separator([]),
                  menu_sub([id("ddm-demo-share")],
                    [ "Share",
                      [ menu_item([], "Copy link"),
                        menu_item([], "Email"),
                        menu_item([], "Embed")
                      ]
                    ]),
                  menu_separator([]),
                  menu_item([disabled(true)], "Delete (disabled)")
                ]
              ])
          ])
      ]).
