:- module(ui_navigation_menu, []).

%   No predicates are exported: navigation_menu/2, navigation_menu_root/2,
%   navigation_menu_list/2, navigation_menu_item/2,
%   navigation_menu_trigger/2, navigation_menu_content/2,
%   navigation_menu_link/2, navigation_menu_trigger_item/2,
%   navigation_menu_link_item/2 are never called module-qualified --
%   bare-call dispatch through px_template's tmpl/2 / render_helper/2
%   tables resolves them (adr/0019), the same pattern every other
%   prolog/ui/*.pl module uses.

/** <module> Navigation Menu (adr/0026): hover/focus-activated flyout
site navigation -- the "Learn ▾ / Overview ▾ / GitHub" header pattern.

Ported from Radix UI's NavigationMenu primitive (docs/radix-port-
analysis.md, "Navigation Menu" entry). **STANDALONE per that entry
("benefits from nothing built in phases 8-12 (it doesn't use popper or
roving-focus). Schedule independently.")** -- unlike Dropdown Menu/
Context Menu/Menubar, this component does NOT reuse `prolog/ui/_menu.pl`
/ `assets/js/lib/menu.js` (the shared Menu engine): it has no `role=menu`
anywhere, no menuitem roving-highlight, no typeahead. Its anatomy is a
bespoke disclosure-button (`aria-expanded`/`aria-controls`) plus
`aria-current`-flavoured link state (`data-active` here) wrapped in
plain `<nav>/<ul>/<li>` -- ordinary link navigation with rich flyout
panels, not menu semantics. It also does NOT use `assets/js/lib/popper.js`
-- the analysis doc's own verdict: "No popper import at all -- positioning
here is bespoke CSS-variable-driven measurement, not reusable from the
Popper port." This port goes further than upstream's own measurement
approach; see "Viewport decision" below.

**Anatomy shipped** (docs/radix-port-analysis.md's own list, minus two
items -- see "Viewport decision"): `Root` (`navigation_menu_root/2`,
`<nav>`), `List` (`navigation_menu_list/2`, `<ul>`), `Item`
(`navigation_menu_item/2`, `<li>`), `Trigger` (`navigation_menu_trigger/2`,
`<button>`), `Content` (`navigation_menu_content/2`, the flyout panel),
`Link` (`navigation_menu_link/2`, a plain `<a>`, used either bare inside
an Item with no Trigger, or inside a Content panel). Plus two rule-1
convenience layers: `navigation_menu_trigger_item/2` (auto id-wires one
Trigger+Content pair inside an Item -- the fiddly boilerplate every
sibling component's own `/2` convenience automates) and
`navigation_menu_link_item/2` (an Item wrapping a bare Link). The
top-level `navigation_menu/2` wraps Root+List around a caller-supplied
list of already-built Items (mixing `navigation_menu_trigger_item/2` and
`navigation_menu_link_item/2` calls, or hand-built `navigation_menu_item/2`
calls) -- the common case for a whole nav bar.

**Viewport decision (documented deviation, adr/0026 rule 2): NO shared
`Viewport`, NO `Indicator`.** The analysis doc names these as the
component's "complexity center" -- both require `ResizeObserver`-derived
pixel geometry ("Indicator and Viewport both expose JS-measured
ResizeObserver-derived CSS vars (pixel position/size) -- not achievable
in pure CSS") and Viewport additionally requires portal-relocating every
Content into one shared node with manual Tab-order proxying (focus-proxy
elements, `relatedTarget` sniffing) to keep keyboard order sane once
Content is visually elsewhere in the DOM. None of that machinery exists
in this codebase (Navigation Menu is explicitly scheduled to build
nothing from it -- "benefits from nothing built in phases 8-12"), and
building it from scratch for one component is exactly the effort
tradeoff adr/0026 rule 3 asks a porting agent to weigh against a
platform-first alternative. **This port keeps each Content inside its
own Item** (`position: relative` on `.px-navigation-menu-item`,
`position: absolute` on `.px-navigation-menu-content`, anchored via
plain CSS, zero JS measurement) rather than portaling into one morphing
shared panel. Consequences, honestly: (1) no shared-viewport
resize-morph animation between differently-sized panels (each panel
independently fades/slides in its own place -- still directional, see
below); (2) no Indicator caret tracking the active trigger's underline
position (a plain CSS `::after` chevron on Trigger, rotated via
`[data-state=open]`, substitutes -- see `assets/css/ui.css`); (3) no
Tab-order proxy is needed at all, because there is nothing to proxy --
Content never leaves its own Item, so natural DOM tab order already
visits Trigger then (if open) straight into Content, exactly where a
sighted user's eyes are. The *feel* upstream's viewport chiefly buys --
"switching between two open flyouts slides directionally instead of
just swapping" -- is still delivered: `data-motion` (below) is computed
and animated per-panel exactly as upstream's own Content wrapper
consumes it, independent of whether Content lives in a shared viewport
or its own Item.

**DOM/ARIA contract emitted** (docs/radix-port-analysis.md's "Navigation
Menu" entry, the parts this port ships):

    Root (`<nav>`):      aria-label (default "Main", Radix's own
                         default), data-orientation (horizontal|vertical).
    List (`<ul>`):       data-orientation.
    Item (`<li>`):       no state of its own -- pure grouping, exactly
                         upstream.
    Trigger (`<button>`): type="button", aria-expanded, aria-controls
                         (Content's id, when wired), data-state
                         (open|closed). Deliberately NO `aria-haspopup`
                         -- upstream's own Trigger carries none either
                         (Navigation Menu is not a menu; see the module
                         header's opening paragraph).
    Content (`<div>`):   id, aria-labelledby (Trigger's id, when wired),
                         data-state (open|closed), data-motion ∈
                         `from-start|from-end|to-start|to-end|null` --
                         a JS-computed direction-of-travel hint from
                         comparing the previously-open and newly-open
                         Trigger's list-order indices, upstream's own
                         semantics, ported verbatim (see
                         `assets/js/components/navigation_menu.js`'s
                         header for the exact algorithm). `null` renders
                         as the attribute being **absent**, matching the
                         analysis doc's own "`|null`" notation.
    Link (`<a>`):        data-active (true|false) -- this port's spelling
                         of upstream's own current-page link-state
                         attribute (upstream also emits `data-active` on
                         NavigationMenuLink, verbatim -- no rename here).

**Keyboard** (docs/radix-port-analysis.md's entry, the reachable subset
given the Viewport/Indicator cut above -- see
`assets/js/components/navigation_menu.js`'s header for the exact event
wiring): Triggers are ordinary tab stops (real `<button>`s, no roving-
tabindex system at all -- upstream's own "independent... FocusGroup...
no wraparound/looping" reduces, for a flat trigger row with no
looping requirement, to "just use native Tab order", so no JS roving
focus module is used or needed here, unlike Tabs/Toolbar/Accordion).
Enter/Space open a Trigger's Content **immediately, no delay** --
free, native `<button>` activation behaviour, nothing to port. A mouse
hover starts upstream's own delay/skip-delay timer machinery (ported in
JS, not CSS -- see the JS header for the exact "menubar-like switch
when another item is already open" rule the brief asks for). Escape
closes the open Content and refocuses its Trigger. Focus leaving the
whole component (a "blur-out", not merely `Tab` to the next Trigger --
switching between two Triggers is normal navigation, not a dismiss)
closes any open Content. `ArrowDown` while a Trigger is focused opens
its Content (if not already open) and moves focus to the first
`navigation_menu_link/2` inside it -- upstream's own TreeWalker-into-
Content entry key, reduced to a plain `querySelector` (cheap, because
Content never leaves its own Item -- see "Viewport decision").

**Platform choice (adr/0026 rule 3) -- there is no native
`popovertarget`/`popover` here, unlike Popover/Dropdown Menu/Hover
Card.** Two reasons, both documented in the analysis doc's own
"Navigation Menu" entry and worth restating: (1) native `popover`
promotes an element to the top layer, which strips it from its
ancestor's normal-flow box -- exactly what this port's Viewport-free
CSS positioning (`position: absolute` relative to its own
`.px-navigation-menu-item`) depends on NOT happening; escaping to the
top layer would reintroduce the geometry-measurement problem the
Viewport cut was written to avoid. (2) upstream's own hover-open timer
machinery (open delay + instant menubar-style switching) has no native
disclosure equivalent regardless -- same "no platform primitive for
timed hover-open" gap Hover Card's own header documents. So Content
renders a plain `<div>` (no `popover` attribute at all) and
`assets/js/components/navigation_menu.js` owns dismissal end to end:
Escape, blur-out, and outside-pointerdown are all bespoke listeners in
that element (documented there, not reused from any shared dismiss
module -- `dismissable-layer`-equivalent logic here is a handful of
lines, not worth extracting into shared machinery for one, standalone
consumer).

**Without JS, this component still renders full site navigation** --
every Trigger, Link, and Content is present in the initial HTML (no
`hidden`/`display:none` gate that only JS lifts); a no-JS visitor sees
every panel's contents already in the document (Content defaults
`data-state="closed"`, so CSS keeps it visually collapsed/positioned
off-panel, but nothing stops a determined no-JS user agent, e.g. a
text browser or a search-engine crawler, from reading straight through
to every link). What is lost without
`assets/js/components/navigation_menu.js`: hover-to-open entirely (no
`popovertarget` fallback exists here, same gap Hover Card's Trigger
has, for the same "no platform primitive" reason above) -- Triggers
render as inert, unclickable-looking buttons. Plain
`navigation_menu_link/2` items (the "GitHub"-style bare links) are
unaffected either way -- they are ordinary anchors.

Options (plain lists, adr/0026 rule 1):

  `navigation_menu_root/2` Opts:
    orientation(horizontal|vertical)  default `horizontal`. Drives
                    `data-orientation` on Root; forwarded to List too
                    by `navigation_menu/2` (see below). Invalid values
                    degrade to `horizontal`.
    aria_label(Label)  default `"Main"` (Radix's own default).
    class(C)        merged with the default class, default first.
    anything else   passed through verbatim.

  `navigation_menu_list/2` Opts:
    orientation(horizontal|vertical)  default `horizontal`, same
                    validation as Root's.
    class(C), anything else  as usual.

  `navigation_menu_item/2` Opts:
    class(C), anything else  as usual -- no state option; Item is
                    pure grouping, exactly upstream.

  `navigation_menu_trigger/2` Opts:
    open(Bool)      default `false`. Drives `aria-expanded`,
                    `data-state`.
    controls(Id)    Content's id, emitted as `aria-controls`. Graceful
                    degradation (no throw) when absent, same posture
                    as `dropdown_menu_trigger/2`'s `controls(_)`.
    class(C), anything else  as usual.

  `navigation_menu_content/2` Opts:
    open(Bool)      default `false`. Drives `data-state`.
    labelledby(Id)  Trigger's id, emitted as `aria-labelledby`. Omitted
                    (no attribute at all) when absent.
    motion(none|from_start|from_end|to_start|to_end)  default `none`
                    -- `none` renders NO `data-motion` attribute at
                    all (the contract's own `|null`); any other value
                    renders `data-motion="from-start"` etc (underscore
                    -> dash, same convention every other multi-word
                    data-attribute value in this codebase already
                    uses at the Prolog call site, e.g.
                    `menu_content/2`'s `side(side_offset)`-style atoms
                    are single words already, so this is this port's
                    own new instance of the pattern -- see
                    `motion_atom/2` below for the exact mapping).
    class(C), anything else  as usual.

  `navigation_menu_link/2` Opts:
    active(Bool)    default `false`. Drives `data-active`.
    href(Href)      ordinary pass-through, no default -- same
                    documented non-throwing gap as `hover_card_trigger/2`'s
                    `href(_)`.
    class(C), anything else  as usual.

  `navigation_menu_trigger_item/2` Opts: the common case -- one Item
                    wrapping one auto id-wired Trigger+Content pair.
    id(Base)        optional; Trigger/Content ids built from it
                    (`<Base>-trigger`/`<Base>-content`); gensym'd
                    (`px_navigation_menu_N`) when absent, same
                    convention as `dropdown_menu/2`'s `base_id/2`.
    open(Bool)      default `false`. Forwarded to both Trigger and
                    Content.
    motion(_)       forwarded to Content, default `none` (see above);
                    a caller driving a demo's initial-open panel by
                    hand can set this, though in the live component
                    `<px-navigation-menu>` computes and overwrites it
                    on every real open/switch.
    class(C)        forwarded to Item (NOT Trigger/Content -- Item is
                    the "one navigable unit" this option describes).

    Second argument: `[Label, ContentChildren]` -- Label is the
    Trigger's children (usually just text, e.g. `"Learn"`);
    ContentChildren is Content's children (typically a
    `navigation_menu_content_grid/1`-shaped list of link cards, though
    this template does not require or inspect that shape).

  `navigation_menu_link_item/2` Opts: forwarded verbatim to
                    `navigation_menu_link/2` (`active(_)`, `href(_)`,
                    `class(_)` all apply to the Link, not the wrapping
                    Item -- there is no Item-level option here, same
                    "no state of its own" as `navigation_menu_item/2`).

    Second argument: Text -- the Link's children.

  `navigation_menu/2` Opts: everything `navigation_menu_root/2` takes
                    (`orientation(_)` forwarded to List too,
                    `aria_label(_)`, `class(_)`, `id(_)`).

    Second argument: Items -- a list of already-built
                    `navigation_menu_item/2` /
                    `navigation_menu_trigger_item/2` /
                    `navigation_menu_link_item/2` calls, rendered
                    as-is inside List. `navigation_menu/2` itself only
                    assembles Root+List (the boilerplate every Item
                    would otherwise repeat) -- unlike `popover/2`/
                    `dropdown_menu/2`/`hover_card/2`'s single-
                    Trigger/Content id-wiring, there is no cross-Item
                    wiring to compute here (each Item already wires
                    its own Trigger<->Content via
                    `navigation_menu_trigger_item/2`), so this
                    convenience is deliberately thinner than those
                    siblings'.
*/

:- use_module(library(lists)).
:- use_module(library(gensym)).
:- use_module('../px_template').

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

valid_orientation(horizontal).
valid_orientation(vertical).

take_orientation(Opts0, Orientation, Rest) :-
    (   selectchk(orientation(O0), Opts0, Rest)
    ->  ( valid_orientation(O0) -> Orientation = O0 ; Orientation = horizontal )
    ;   Orientation = horizontal, Rest = Opts0
    ).

take_aria_label(Opts0, Label, Rest) :-
    (   selectchk(aria_label(L0), Opts0, Rest)
    ->  Label = L0
    ;   Label = "Main", Rest = Opts0
    ).

take_controls(Opts0, ControlsOpt, Rest) :-
    (   selectchk(controls(Id), Opts0, Rest)
    ->  ControlsOpt = controls(Id)
    ;   ControlsOpt = none, Rest = Opts0
    ).

take_labelledby(Opts0, LabelledbyOpt, Rest) :-
    (   selectchk(labelledby(Id), Opts0, Rest)
    ->  LabelledbyOpt = labelledby(Id)
    ;   LabelledbyOpt = none, Rest = Opts0
    ).

%!  motion_atom(?Opt, ?Dashed) is semidet.
%
%   `none` renders no attribute at all (the contract's `|null`); every
%   other value maps underscore -> dash for the rendered attribute
%   value, matching every other multi-word data-attribute value
%   convention in this codebase.
motion_atom(from_start, 'from-start').
motion_atom(from_end,   'from-end').
motion_atom(to_start,   'to-start').
motion_atom(to_end,     'to-end').

take_motion(Opts0, MotionOpt, Rest) :-
    (   selectchk(motion(M0), Opts0, Rest)
    ->  ( M0 == none
        -> MotionOpt = none
        ;  motion_atom(M0, Dashed)
        -> MotionOpt = motion(Dashed)
        ;  MotionOpt = none
        )
    ;   MotionOpt = none, Rest = Opts0
    ).

merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

		 /*******************************
		 *             ROOT             *
		 *******************************/

%!  navigation_menu_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `navigation_menu_root([], [List])`.
%   Renders the `<px-navigation-menu>` custom-element wrapper
%   (adr/0026 rule 4) around a server-rendered `<nav>` -- see the
%   module header's "Without JS" note for exactly what still works
%   with `<px-navigation-menu>` never loaded.
px_template:render_helper(navigation_menu_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_navigation_menu, [], [nav(Attrs, Children)]).

root_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_orientation(Opts0, Orientation, Opts1),
    take_aria_label(Opts1, Label, Opts2),
    merge_class(Opts2, "px-navigation-menu", ClassVal, Opts3),
    append([ [aria_label(Label), data_orientation(Orientation), class(ClassVal)],
             Opts3
           ], Attrs).

		 /*******************************
		 *             LIST             *
		 *******************************/

%!  navigation_menu_list(+Opts, +Children) is det.
px_template:render_helper(navigation_menu_list(Opts, Children), S) :-
    list_attrs(Opts, Attrs),
    px_template:render(S, ul(Attrs, Children)).

list_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_orientation(Opts0, Orientation, Opts1),
    merge_class(Opts1, "px-navigation-menu-list", ClassVal, Opts2),
    append([ [data_orientation(Orientation), class(ClassVal)], Opts2 ], Attrs).

		 /*******************************
		 *             ITEM             *
		 *******************************/

%!  navigation_menu_item(+Opts, +Children) is det.
px_template:render_helper(navigation_menu_item(Opts, Children), S) :-
    item_attrs(Opts, Attrs),
    px_template:render(S, li(Attrs, Children)).

item_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-navigation-menu-item", ClassVal, Opts1),
    append([ [class(ClassVal)], Opts1 ], Attrs).

		 /*******************************
		 *            TRIGGER           *
		 *******************************/

%!  navigation_menu_trigger(+Opts, +Children) is det.
px_template:render_helper(navigation_menu_trigger(Opts, Children), S) :-
    trigger_attrs(Opts, Attrs),
    px_template:render(S, button(Attrs, Children)).

trigger_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_bool(open, false, Opts0, Open, Opts1),
    take_controls(Opts1, ControlsOpt, Opts2),
    merge_class(Opts2, "px-navigation-menu-trigger", ClassVal, Opts3),
    state_atom(Open, State),
    (   ControlsOpt = controls(Id)
    ->  WireAttrs = [aria_controls(Id)]
    ;   WireAttrs = []
    ),
    append([ [type(button)],
             WireAttrs,
             [aria_expanded(Open), data_state(State), class(ClassVal)],
             Opts3
           ], Attrs).

		 /*******************************
		 *            CONTENT           *
		 *******************************/

%!  navigation_menu_content(+Opts, +Children) is det.
px_template:render_helper(navigation_menu_content(Opts, Children), S) :-
    content_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, Children)).

content_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_bool(open, false, Opts0, Open, Opts1),
    take_labelledby(Opts1, LabelledbyOpt, Opts2),
    take_motion(Opts2, MotionOpt, Opts3),
    merge_class(Opts3, "px-navigation-menu-content", ClassVal, Opts4),
    state_atom(Open, State),
    (   LabelledbyOpt = labelledby(Id)
    ->  LabelAttrs = [aria_labelledby(Id)]
    ;   LabelAttrs = []
    ),
    (   MotionOpt = motion(M)
    ->  MotionAttrs = [data_motion(M)]
    ;   MotionAttrs = []
    ),
    append([ LabelAttrs,
             [data_state(State)],
             MotionAttrs,
             [class(ClassVal)],
             Opts4
           ], Attrs).

		 /*******************************
		 *             LINK             *
		 *******************************/

%!  navigation_menu_link(+Opts, +Children) is det.
px_template:render_helper(navigation_menu_link(Opts, Children), S) :-
    link_attrs(Opts, Attrs),
    px_template:render(S, a(Attrs, Children)).

link_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_bool(active, false, Opts0, Active, Opts1),
    merge_class(Opts1, "px-navigation-menu-link", ClassVal, Opts2),
    append([ [data_active(Active), class(ClassVal)], Opts2 ], Attrs).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  navigation_menu_trigger_item(+Opts, +Parts) is det.
%
%   Parts = [Label, ContentChildren]. Auto id-wires one Trigger+Content
%   pair inside one Item -- see the module header.
navigation_menu_trigger_item(Opts, Parts) ~>
    \navigation_menu_trigger_item_render(Opts, Parts).

px_template:render_helper(
        navigation_menu_trigger_item_render(Opts, [Label, ContentKids]), S) :-
    must_be(list, Opts),
    take_bool(open, false, Opts, Open, _),
    ( selectchk(motion(M), Opts, _) -> MotionOpt = [motion(M)] ; MotionOpt = [] ),
    base_id(Opts, Base),
    format(atom(TriggerId), '~w-trigger', [Base]),
    format(atom(ContentId), '~w-content', [Base]),
    exclude(trigger_item_only_opt, Opts, ItemOpts),
    TriggerOpts = [id(TriggerId), open(Open), controls(ContentId)],
    append([id(ContentId), open(Open), labelledby(TriggerId)], MotionOpt, ContentOpts),
    px_template:render(S,
        navigation_menu_item(ItemOpts,
          [ navigation_menu_trigger(TriggerOpts, Label),
            navigation_menu_content(ContentOpts, ContentKids)
          ])).

trigger_item_only_opt(open(_)).
trigger_item_only_opt(motion(_)).
trigger_item_only_opt(id(_)).

%!  navigation_menu_link_item(+Opts, +Text) is det.
%
%   An Item wrapping one bare Link -- the "GitHub"-style plain nav
%   entry with no Trigger/Content.
navigation_menu_link_item(Opts, Text) ~>
    \navigation_menu_link_item_render(Opts, Text).

px_template:render_helper(navigation_menu_link_item_render(Opts, Text), S) :-
    must_be(list, Opts),
    px_template:render(S,
        navigation_menu_item([], [navigation_menu_link(Opts, Text)])).

%!  navigation_menu(+Opts, +Items) is det.
%
%   Root wrapping List wrapping the caller-supplied Items -- see the
%   module header for why this is thinner than `popover/2`'s own
%   convenience (no cross-Item wiring to compute here).
navigation_menu(Opts, Items) ~> \navigation_menu_render(Opts, Items).

px_template:render_helper(navigation_menu_render(Opts, Items), S) :-
    must_be(list, Opts),
    take_orientation(Opts, Orientation, _),
    take_aria_label(Opts, Label, _),
    exclude(root_only_opt, Opts, RootOpts0),
    exclude(is_orientation_opt, RootOpts0, RootOpts),
    px_template:render(S,
        navigation_menu_root([orientation(Orientation), aria_label(Label) | RootOpts],
          [ navigation_menu_list([orientation(Orientation)], Items) ])).

root_only_opt(aria_label(_)).
is_orientation_opt(orientation(_)).

%!  base_id(+Opts, -Base) is det.
%
%   `id(Base)` from Opts if the caller supplied one; otherwise a fresh
%   gensym'd id -- same convention as `dropdown_menu.pl`'s `base_id/2`.
base_id(Opts, Base) :-
    (   memberchk(id(Base), Opts)
    ->  true
    ;   gensym(px_navigation_menu_, Base)
    ).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Order 18: the next free slot after dropdown_menu.pl's Order 17
%   (adr/0026 rule 8: Navigation Menu is scheduled independently --
%   "standalone... schedule independently" -- it does not gate on, or
%   get gated by, the menus tier's own ordering).
px_ui:demo(navigation_menu, 18, \navigation_menu_demo).

%   Radix-style hero demo: "Learn"/"Overview" triggers with rich
%   link-card panels, plus a plain "GitHub" link -- the reference
%   page's own top-of-docs navigation bar
%   (https://www.radix-ui.com/primitives/docs/components/navigation-menu).
navigation_menu_demo ~>
    div(class("px-navigation-menu-demo"),
      [ section(class("ui-demo-block"),
          [ h3("Site navigation -- hover a trigger (~200ms delay), or click/focus+Enter"),
            p("Hover \"Learn\" or \"Overview\" (or Tab to one and press Enter/Space -- real <button> activation, zero JS needed for that path): after ~200ms the flyout panel opens, positioned by plain CSS relative to its own Item (no shared viewport -- see prolog/ui/navigation_menu.pl's header, \"Viewport decision\"). Hover the other trigger while one is open and panels switch instantly (menubar-like) with a directional data-motion slide. Move the pointer onto the open panel itself and it stays open (pointerover cancels the pending close, same grace bridge as Hover Card). Escape, or tabbing focus out of the whole bar, closes it."),
            navigation_menu([aria_label("Main demo navigation")],
              [ navigation_menu_trigger_item([id("nm-demo-overview")],
                  [ "Overview",
                    [ div(class("px-navigation-menu-content-grid px-navigation-menu-content-grid-featured"),
                        [ a([class("px-navigation-menu-featured"), href("#introduction")],
                            [ div(class("px-navigation-menu-featured-title"), "Radix Primitives"),
                              div(class("px-navigation-menu-featured-desc"),
                                  "Unstyled, accessible components for building high-quality design systems and web apps.")
                            ]),
                          navigation_menu_content_card("#introduction", "Introduction", "Build accessible design systems and web apps."),
                          navigation_menu_content_card("#getting-started", "Getting started", "A quick tutorial to get you up and running."),
                          navigation_menu_content_card("#styling", "Styling", "Unstyled and compatible with any styling solution.")
                        ])
                    ]
                  ]),
                navigation_menu_trigger_item([id("nm-demo-learn")],
                  [ "Learn",
                    [ div(class("px-navigation-menu-content-grid"),
                        [ navigation_menu_content_card("#introduction", "Introduction", "Build accessible design systems and web apps."),
                          navigation_menu_content_card("#getting-started", "Getting started", "A quick tutorial to get you up and running."),
                          navigation_menu_content_card("#styling", "Styling", "Unstyled and compatible with any styling solution."),
                          navigation_menu_content_card("#animation", "Animation", "Use the animation utility to create smooth animations."),
                          navigation_menu_content_card("#accessibility", "Accessibility", "Tested in a wide variety of screen readers and browsers."),
                          navigation_menu_content_card("#releases", "Releases", "Radix Primitives releases and their changelogs.")
                        ])
                    ]
                  ]),
                navigation_menu_link_item([href("https://github.com/radix-ui/primitives"), active(false)], "GitHub")
              ])
          ]),

        h3("Vertical orientation"),
        p("orientation(vertical) -- data-orientation drives both Root/List's own attribute and this demo's layout; a caller may lay out the sidebar however it likes."),
        navigation_menu([orientation(vertical), aria_label("Vertical demo navigation")],
          [ navigation_menu_link_item([href("#docs"), active(true)], "Docs"),
            navigation_menu_link_item([href("#blog"), active(false)], "Blog"),
            navigation_menu_trigger_item([id("nm-demo-vertical-community")],
              [ "Community",
                [ div(class("px-navigation-menu-content-grid"),
                    [ navigation_menu_content_card("#discord", "Discord", "Chat with the community."),
                      navigation_menu_content_card("#twitter", "Twitter", "Follow for updates.")
                    ])
                ]
              ])
          ])
      ]).

%!  navigation_menu_content_card(+Href, +Title, +Desc) is det.
%
%   One link card inside a Content grid -- demo-only scaffolding
%   (`.px-navigation-menu-card*`, css_coverage-checked like every
%   other component's demo-only classes, e.g. hover_card.pl's
%   `.px-hover-card-profile`).
navigation_menu_content_card(Href, Title, Desc) ~>
    \navigation_menu_content_card_render(Href, Title, Desc).

px_template:render_helper(navigation_menu_content_card_render(Href, Title, Desc), S) :-
    px_template:render(S,
        navigation_menu_link([href(Href), class("px-navigation-menu-card")],
          [ div(class("px-navigation-menu-card-title"), Title),
            div(class("px-navigation-menu-card-desc"), Desc)
          ])).
