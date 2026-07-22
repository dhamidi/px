:- module(ui_context_menu, []).

%   No predicates are exported: context_menu/2, context_menu_root/2,
%   context_menu_trigger/2, context_menu_content/2 are never called
%   module-qualified -- bare-call dispatch through px_template's
%   tmpl/2 / render_helper/2 tables resolves them (adr/0019), exactly
%   `prolog/ui/dropdown_menu.pl`'s own pattern. Every anatomy part
%   beyond Root/Trigger/Content is a direct re-export of
%   `prolog/ui/_menu.pl`'s shared vocabulary -- `menu_item/1,2`,
%   `menu_checkbox_item/2`, `menu_radio_group/2`, `menu_radio_item/2`,
%   `menu_label/2`, `menu_separator/1`, `menu_sub/2` -- used directly,
%   unwrapped, exactly as `dropdown_menu.pl` uses them; this module
%   adds NO `context_menu_item/2`-style renamed wrappers around them
%   (the analysis doc's own framing: Context Menu's "own anatomy list
%   is nearly identical to Dropdown Menu's, both being thin skins over
%   the same engine").

/** <module> Context Menu (adr/0026): a right-click- (or long-press-)
triggered menu anchored to the POINTER, not to any real DOM element --
this library's second consumer of `prolog/ui/_menu.pl` /
`assets/js/lib/menu.js` (the shared Menu engine ported once, per
`docs/radix-port-analysis.md`'s "Menu (shared machinery, not a public
component)" entry: "any port of [dropdown-menu, context-menu, menubar]
requires porting this state machine ONCE... rather than three times").
`prolog/ui/dropdown_menu.pl` is this module's closest sibling --
literally the same wrapper shape, minus a real trigger element, plus a
pointer-anchored open path -- read that module's header first; only
the deltas are documented at length here.

Ported from Radix UI's ContextMenu primitive (docs/radix-port-
analysis.md, "Context Menu" entry). Anatomy: `Root`
(`context_menu_root/2`), `Trigger` (`context_menu_trigger/2`, a
`<span>` wrapping arbitrary content -- see "Trigger is not a button"
below), `Content` (`context_menu_content/2`, a thin wrapper over
`_menu.pl`'s `menu_content/2` with Context-Menu-specific defaults --
see below), plus every part `_menu.pl` already exports used directly
(`menu_item/1,2`, `menu_checkbox_item/2`, `menu_radio_group/2`,
`menu_radio_item/2`, `menu_label/2`, `menu_separator/1`, `menu_sub/2`/
`menu_sub_trigger/2`/`menu_sub_content/2`, `menu_item_indicator/2`,
`menu_arrow/1`). `context_menu/2` is the rule-1 top-level convenience:
a Root wrapping one Trigger and one Content, id-wiring (both parts get
a base-derived `id`, for `assets/js/components/context_menu.js` and
tests to address them by -- see "No aria-controls" below for why this
is NOT the same wiring `dropdown_menu/2` does) and `open(_)`/
`disabled(_)` threaded automatically, same division of labour as
`popover/2`/`dropdown_menu/2`.

**Trigger is not a button, and carries no `aria-haspopup`/
`aria-expanded`/`aria-controls` at all (a documented, deliberate
CONTRAST with `dropdown_menu_trigger/2`'s contract, not an omission).**
The analysis doc's own words: Trigger "renders a `<span>` (wraps
arbitrary content, not a button)... anchors the menu to a zero-size
virtual `DOMRect`... rather than to any real DOM element." A `<span>`
wrapping an arbitrary block of a page (a table row, an image, a canvas)
has no button-like "opens a menu" semantic for assistive tech to
announce -- unlike Dropdown Menu's real, standalone `<button
aria-haspopup="menu">`, matching the analysis doc's own explicit
contrast in the "Dropdown Menu" entry: "Content sets
`aria-labelledby={triggerId}` -- Context Menu's content has no such
link since it has no persistent trigger element." This port carries
that contrast through structurally: `context_menu_trigger/2` emits
`data-state` only (open|closed, mirroring whether ITS content is
currently open -- exactly `hover_card_trigger/2`'s own "data-state
ONLY" contract, for the identical reason: no formal ARIA relationship
exists here to name with `aria-*`), plus `data-disabled` when
`disabled(true)` (see below). `context_menu_content/2` never receives
an automatic `aria-labelledby` from `context_menu/2` (contrast with
`dropdown_menu/2`, which always wires one) -- a caller wanting one
anyway may still pass `labelledby(Id)` through to Content by hand
(`_menu.pl`'s own `menu_content/2` option), just never defaulted here.

**`disabled(Bool)` on Trigger -- "leaves the native `onContextMenu`
passthrough untouched... an explicit escape hatch back to the OS
context menu"** (analysis doc, verbatim). `context_menu_trigger/2`
renders `data-disabled` (no value, matching `_menu.pl`'s own
`disabled_attrs/1` convention for menu Items) when `disabled(true)`;
`assets/js/components/context_menu.js` reads that attribute and, when
present, skips `preventDefault()` on the native `contextmenu` event
entirely -- the browser's own OS-native context menu opens exactly as
if this component didn't exist. No `aria-disabled` is emitted (Trigger
carries no ARIA role to begin with, per the contract above).

**Content defaults: `side(right) side_offset(2) align(start)`** --
the analysis doc's own figures, "opens to the right of the click point,
unlike Dropdown Menu's below-trigger default" (Dropdown Menu's own
`bottom`/`start`/`0`). Unlike `dropdown_menu_content/2` (a byte-
identical rename over `menu_content/2`, inheriting ITS `bottom`/
`start`/`0` defaults because Dropdown Menu's own defaults happen to
match `_menu.pl`'s baked-in ones), `context_menu_content/2` cannot
simply delegate: `menu_content/2`'s own `content_attrs/5` hard-codes
`bottom`/`start` (`_menu.pl`'s own Dropdown-Menu-flavoured defaults),
so this module fills in `side(right)`/`align(start)`/`side_offset(2)`
itself -- ONLY when the caller didn't already supply one (see
`ensure_default/4` below) -- before delegating, so a STANDALONE call to
`context_menu_content/2` gets Context Menu's own contractual defaults
too, not just calls routed through `context_menu/2`.

**Platform choice (adr/0026 rule 3) -- native `popover="auto"` still
carries Escape/outside-click dismissal and top-layer stacking on
Content; `assets/js/lib/menu.js` still carries every irreducible
per-item interaction (roving highlight, typeahead, submenu hover/
keyboard/positioning, checkbox/radio toggling, close-on-select),
EXACTLY as `dropdown_menu.pl`'s own split -- but OPENING Content is
100% `assets/js/components/context_menu.js`'s job, with NO native
fallback at all.** This is the one place this port's platform split is
strictly narrower than Dropdown Menu's: `popovertarget` is a *click*-
activated attribute -- there is no native HTML mechanism that opens a
popover in response to the `contextmenu` event (or a long-press
gesture), and "the analysis doc's own verdict, quoted verbatim: "There
is no platform replacement for suppressing and replacing the native
context menu -- `event.preventDefault()` on `contextmenu` is required
in 2026 exactly as it was in 2020." So `context_menu_trigger/2` renders
NO `popovertarget` (nothing to point it at that would fire on the right
gesture even if it existed) -- **without
`assets/js/components/context_menu.js` loaded, right-clicking (or
long-pressing) the Trigger never opens Content at all**; only the
browser's own native OS context menu appears, same as if this
component were never mounted. This is a strictly narrower no-JS story
than every other port in this library (even Hover Card's Content still
renders, unstyled-but-present, before JS loads) -- documented here
because it is a direct, necessary consequence of "opens on a native
event with no click-equivalent platform primitive," not an oversight.

**Virtual-point anchoring -- the actual substance of this port; see
`assets/js/components/context_menu.js`'s own header for the full
mechanics.** Short version: `assets/js/lib/popper.js`'s `position/3`
calls exactly one method on its `anchorEl` argument --
`anchorEl.getBoundingClientRect()` -- nothing else, ever (verified by
reading that file: no `.closest`, no `.contains`, no DOM-membership
check anywhere in `position/3` or `autoUpdate/3`). That means anything
satisfying the single-method `{ getBoundingClientRect() }` duck-typed
interface positions correctly, with ZERO changes to `lib/popper.js`
itself -- exactly Radix's own upstream `VirtualElement` API
(`react-popper`'s `virtualElement` prop), independently arrived at
here from the same constraint. `context_menu.js` constructs a plain JS
object (`virtualAnchor(x, y)`) whose `getBoundingClientRect()` returns
a zero-size rect at the captured `{clientX, clientY}` -- NOT a
synthesized 0x0 positioned DOM shim element (the analysis doc's own
alternative, "an extra step the Dropdown Menu case doesn't need").
The plain-object route was chosen over the DOM-shim route because it
needs no insertion/removal lifecycle, no extra paint, and no risk of
the shim itself becoming an accidental click/focus target -- a strict
subset of what a real element could do, and popper.js's contract asks
for nothing more. Recreated fresh on every `contextmenu`/long-press
open (never reused across opens), matching the analysis doc's own
"recreated on every reopen so right-clicking a new spot re-anchors
correctly."

**Long-press for touch/pen** (analysis doc: "a 700ms timer armed on
pointerdown (mouse excluded), cancelled on pointermove/up/cancel --
must be held stationary to trigger"), ported as a best-effort,
DELIBERATELY simplified addition (documented deviation, adr/0026 rule
2) in `assets/js/components/context_menu.js` -- see that file's header
for the one narrowing accepted: no suppression of native text-
selection/scrolling during the hold (upstream's own extra gesture
guard), just the timer + movement-cancels-it core, "cheap" per this
component's own task brief.

**DOM/ARIA contract emitted** (docs/radix-port-analysis.md's "Context
Menu" entry plus `_menu.pl`'s own Content contract, adr/0026 rule 2):

    Trigger (`<span>`): data-state="open|closed" ONLY,
                          PLUS data-disabled (no value) when
                          disabled(true). NO aria-haspopup/
                          aria-expanded/aria-controls/popovertarget --
                          see "Trigger is not a button" above.
    Content (`<div>`):   role="menu" (via menu_content/2), popover="auto",
                          tabindex="-1", data-state, data-side (default
                          "right"), data-align (default "start"),
                          data-side-offset (default "2"),
                          data-align-offset (default "0"). No automatic
                          aria-labelledby (see above).

Options (plain lists, adr/0026 rule 1):

  `context_menu_root/2` Opts:
    class(C)        merged with the default class, default first
                    ("px-context-menu C").
    anything else   passed through verbatim, appended AFTER the
                    computed attributes.

  `context_menu_trigger/2` Opts:
    open(Bool)      default `false`. Drives `data-state` (open|closed)
                    ONLY -- see the DOM/ARIA contract above.
    disabled(Bool)  default `false`. Drives `data-disabled` (no
                    value) -- read by `<px-context-menu>` as the "skip
                    preventDefault, let the OS menu through" escape
                    hatch. No `aria-disabled` (Trigger carries no ARIA
                    role at all).
    class(C), anything else  pass-through, as usual.

  `context_menu_content/2` Opts: everything `menu_content/2` takes
                    (`id(_)`, `open(_)`, `labelledby(_)`, `side(_)`
                    default `right`, `align(_)` default `start`,
                    `side_offset(_)` default `2`, `align_offset(_)`,
                    `class(_)`) -- `side`/`align`/`side_offset` default
                    to Context Menu's OWN figures (not `menu_content/2`'s
                    baked-in `bottom`/`start`/`0`) when the caller
                    doesn't supply one; every other option forwarded
                    verbatim.

  `context_menu/2` Opts: everything `context_menu_root/2` takes, PLUS
    open(Bool)      default `false`. Forwarded to both Trigger and
                    Content.
    disabled(Bool)  default `false`. Forwarded to Trigger only.
    side(_), align(_), side_offset(_), align_offset(_)  forwarded to
                    Content, same defaults as `context_menu_content/2`
                    (right/start/2/0).
    id(Id)          optional; base every generated part's id is built
                    from (`<Id>-trigger`/`-content`); gensym'd
                    (`px-context-menu-N`) when absent, same convention
                    as `dropdown_menu/2`'s `base_id/2`. Not wired into
                    any `aria-*` attribute (see "No aria-controls"
                    above) -- exists purely so
                    `assets/js/components/context_menu.js` and tests
                    have stable ids to address each part by.

  `context_menu/2` second argument: `[TriggerChildren, ContentChildren]`
                    (mirrors `dropdown_menu/2`'s Parts shape exactly).
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

state_atom(true,  open)   :- !.
state_atom(false, closed).

merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  ensure_default(+Name, +Default, +Opts0, -Opts) is det.
%
%   Adds `Name(Default)` to Opts0 UNLESS the caller already supplied
%   `Name(_)` -- used by `context_menu_content/2` to inject Context
%   Menu's own side/align/side_offset defaults before delegating to
%   `menu_content/2` (whose own baked-in defaults are Dropdown Menu's,
%   `bottom`/`start`/`0` -- see the module header for why this can't
%   just be a bare rename the way `dropdown_menu_content/2` is).
ensure_default(Name, Default, Opts0, Opts) :-
    Probe =.. [Name, _],
    (   memberchk(Probe, Opts0)
    ->  Opts = Opts0
    ;   DefaultOpt =.. [Name, Default],
        Opts = [DefaultOpt|Opts0]
    ).

		 /*******************************
		 *             ROOT             *
		 *******************************/

%!  context_menu_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `context_menu_root([], [Trigger,
%   Content])`. Renders the `<px-context-menu>` custom-element wrapper
%   (adr/0026 rule 4) around a server-rendered `<div>` -- see the
%   module header's "Platform choice": without JS, right-clicking (or
%   long-pressing) Trigger opens nothing at all; only the native OS
%   context menu appears.
px_template:render_helper(context_menu_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_context_menu, [], [div(Attrs, Children)]).

root_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-context-menu", ClassVal, Opts1),
    append([ [class(ClassVal)], Opts1 ], Attrs).

		 /*******************************
		 *            TRIGGER           *
		 *******************************/

%!  context_menu_trigger(+Opts, +Children) is det.
%
%   Bare-call template surface: `context_menu_trigger([disabled(true)],
%   [...arbitrary content...])`. Renders a `<span>` -- see the module
%   header's "Trigger is not a button" for why this carries no
%   `aria-haspopup`/`aria-expanded`/`aria-controls`/`popovertarget` at
%   all, unlike `dropdown_menu_trigger/2`.
px_template:render_helper(context_menu_trigger(Opts, Children), S) :-
    trigger_attrs(Opts, Attrs),
    px_template:render(S, span(Attrs, Children)).

trigger_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_bool(open, false, Opts0, Open, Opts1),
    take_bool(disabled, false, Opts1, Disabled, Opts2),
    merge_class(Opts2, "px-context-menu-trigger", ClassVal, Opts3),
    state_atom(Open, State),
    ( Disabled == true -> DisabledAttrs = [data_disabled("")] ; DisabledAttrs = [] ),
    append([ [data_state(State)],
             DisabledAttrs,
             [class(ClassVal)],
             Opts3
           ], Attrs).

		 /*******************************
		 *            CONTENT           *
		 *******************************/

%!  context_menu_content(+Opts, +Children) is det.
%
%   Bare-call template surface: `context_menu_content([id("m1"),
%   open(true)], [...])`. Fills in Context Menu's own
%   `side(right)`/`align(start)`/`side_offset(2)` defaults (ONLY when
%   the caller didn't already supply one, via `ensure_default/4`) then
%   delegates to `menu_content/2` -- see the module header for why a
%   bare rename (`dropdown_menu_content/2`'s own approach) isn't
%   enough here.
px_template:render_helper(context_menu_content(Opts, Children), S) :-
    must_be(list, Opts),
    ensure_default(side, right, Opts, Opts1),
    ensure_default(align, start, Opts1, Opts2),
    ensure_default(side_offset, 2, Opts2, Opts3),
    px_template:render(S, menu_content(Opts3, Children)).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  context_menu(+Opts, +Parts) is det.
%
%   Parts = [TriggerChildren, ContentChildren]. The common case: a Root
%   wrapping one Trigger and one Content, `open(_)`/`disabled(_)`
%   threaded appropriately, both parts given a base-derived `id` (for
%   `<px-context-menu>` and tests to address them by -- NOT wired into
%   any `aria-*` attribute, see the module header's "No aria-controls").
context_menu(Opts, Parts) ~> \context_menu_render(Opts, Parts).

px_template:render_helper(context_menu_render(Opts, [TriggerKids, ContentKids]), S) :-
    must_be(list, Opts),
    take_bool(open, false, Opts, Open, _),
    take_bool(disabled, false, Opts, Disabled, _),
    base_id(Opts, Base),
    format(atom(TriggerId), '~w-trigger', [Base]),
    format(atom(ContentId), '~w-content', [Base]),
    read_or_default(side, Opts, right, Side),
    read_or_default(align, Opts, start, Align),
    read_or_default(side_offset, Opts, 2, SideOffset),
    read_or_default(align_offset, Opts, 0, AlignOffset),
    exclude(convenience_only_opt, Opts, RootOpts),
    TriggerOpts = [open(Open), disabled(Disabled), id(TriggerId)],
    ContentOpts = [ open(Open), id(ContentId),
                     side(Side), align(Align),
                     side_offset(SideOffset), align_offset(AlignOffset)
                   ],
    px_template:render(S,
        context_menu_root(RootOpts,
          [ context_menu_trigger(TriggerOpts, TriggerKids),
            context_menu_content(ContentOpts, ContentKids)
          ])).

%!  read_or_default(+Name, +Opts, +Default, -Value) is det.
%
%   Forwards Content-only positioning options
%   (`side(_)`/`align(_)`/`side_offset(_)`/`align_offset(_)`) from
%   `context_menu/2`'s own Opts down to the assembled Content, Context
%   Menu's own defaults (`right`/`start`/`2`/`0`) when the caller
%   didn't override them here.
read_or_default(Name, Opts, Default, Value) :-
    Probe =.. [Name, V0],
    ( memberchk(Probe, Opts) -> Value = V0 ; Value = Default ).

%!  convenience_only_opt(+Opt) is semidet.
%
%   Trigger/Content-only concepts that must NOT leak onto Root's own
%   `<div>` as literal, meaningless HTML attributes -- same rationale
%   as `dropdown_menu.pl`'s own `convenience_only_opt/1`.
convenience_only_opt(open(_)).
convenience_only_opt(disabled(_)).
convenience_only_opt(side(_)).
convenience_only_opt(align(_)).
convenience_only_opt(side_offset(_)).
convenience_only_opt(align_offset(_)).

%!  base_id(+Opts, -Base) is det.
%
%   `id(Base)` from Opts if the caller supplied one; otherwise a fresh
%   gensym'd id -- same convention as `dropdown_menu.pl`'s own
%   `base_id/2`.
base_id(Opts, Base) :-
    (   memberchk(id(Base), Opts)
    ->  true
    ;   gensym(px_context_menu_, Base)
    ).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Order 18: the next free slot after dropdown_menu.pl's Order 17
%   (adr/0026 rule 8: Context Menu is the menus tier's second entry,
%   right after Dropdown Menu -- "Dropdown Menu, Context Menu, Menubar
%   (in that order)").
px_ui:demo(context_menu, 18, \context_menu_demo).

context_menu_demo ~>
    div(class("px-context-menu-demo"),
      [ section(class("ui-demo-block"),
          [ h3("Basic -- right-click (or long-press ~700ms on touch) the dashed area"),
            p("The native contextmenu event on the dashed area is intercepted (preventDefault) by <px-context-menu>, which anchors Content to the pointer's exact (clientX, clientY) via a virtual anchor object (assets/js/lib/popper.js's position() only ever calls anchorEl.getBoundingClientRect(), so a plain JS object satisfying that one method positions exactly like a real element -- no synthesized DOM shim needed). Content defaults to side=\"right\" align=\"start\" side-offset=\"2\", unlike Dropdown Menu's below-trigger default. Escape/outside dismiss via native popover=\"auto\"; ArrowDown/Up/typeahead/submenu hover+keyboard are the identical assets/js/lib/menu.js engine Dropdown Menu already proved out."),
            context_menu([id("cm-demo")],
              [ div(class("px-context-menu-area"), "Right-click here"),
                [ menu_item([], [span("Back"), span(class("px-menu-shortcut"), "⌘[")]),
                  menu_item([], [span("Forward"), span(class("px-menu-shortcut"), "⌘]")]),
                  menu_item([], [span("Reload"), span(class("px-menu-shortcut"), "⌘R")]),
                  menu_separator([]),
                  menu_checkbox_item([checked(true)], "Show bookmarks bar"),
                  menu_checkbox_item([], "Show full URLs"),
                  menu_separator([]),
                  menu_label([], "Zoom"),
                  menu_radio_group([aria_label("Zoom level")],
                    [ menu_radio_item([value("75")], "75%"),
                      menu_radio_item([value("100"), checked(true)], "100%"),
                      menu_radio_item([value("125")], "125%")
                    ]),
                  menu_separator([]),
                  menu_sub([id("cm-demo-more")],
                    [ "More tools",
                      [ menu_item([], "Developer tools"),
                        menu_item([], "Task manager"),
                        menu_item([], "Extensions")
                      ]
                    ]),
                  menu_separator([]),
                  menu_item([disabled(true)], "View page source (disabled)")
                ]
              ])
          ])
      ]).
