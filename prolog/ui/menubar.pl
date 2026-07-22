:- module(ui_menubar, []).

%   No predicates are exported: menubar_root/2, menubar_menu/2,
%   menubar_trigger/2, menubar_content/2, menubar/2 are never called
%   module-qualified -- bare-call dispatch through px_template's
%   tmpl/2 / render_helper/2 tables (adr/0019) resolves them, the same
%   pattern every other prolog/ui/*.pl module uses. Every anatomy part
%   beyond Trigger/Content/Menu is a direct re-export of
%   `prolog/ui/_menu.pl`'s shared vocabulary -- `menu_item/1,2`,
%   `menu_checkbox_item/2`, `menu_radio_group/2`, `menu_radio_item/2`,
%   `menu_label/2`, `menu_separator/1`, `menu_sub/2` -- used directly,
%   unwrapped, by any caller composing a Menubar menu's Content; this
%   module adds NO `menubar_item/2`-style renamed wrappers around them
%   (the analysis doc's own framing: "nearly every non-Trigger export
%   is a one-line pass-through to the corresponding `menu` part").

/** <module> Menubar (adr/0026): a horizontal bar of menu buttons
(File/Edit/View...) where hovering across the bar while one menu is
open switches directly between menus, and ArrowLeft/ArrowRight both
move between top-level triggers AND, from inside an open menu's
Content, jump to the adjacent menubar menu.

Ported from Radix UI's Menubar primitive (docs/radix-port-analysis.md,
"Menubar" entry -- "Built as a thin composer over the base `menu`
primitive... nearly every non-Trigger export is a one-line pass-
through"). Anatomy: `Root` (`menubar_root/2`), `Menu` (grouping only --
`menubar_menu/2`, the rule-1-shaped convenience assembling one Trigger
+ one Content), `Trigger` (`menubar_trigger/2`), `Content`
(`menubar_content/2`, a thin wrapper over `_menu.pl`'s `menu_content/2`
-- see below), plus every part `_menu.pl` already exports, used
directly, exactly as `prolog/ui/dropdown_menu.pl` already does.
`menubar/2` is the rule-1 top-level convenience: a Root wrapping a list
of Menus, with the cross-menu roving-tabindex computation described
below (mirrors `prolog/ui/toolbar.pl`'s own `mark_active_parts/2`
precedent -- Menubar is this library's SECOND top-level-roving-focus
port after Toolbar, reusing the identical "exactly one explicit
tabindex=0 across the whole Root, auto-picked, explicit `active(true)`
anywhere wins" shape).

**This module's own incremental logic on top of the shared Menu
primitive** (the analysis doc's own framing):

  - `Trigger` is a real `<button role="menuitem">` -- role OVERRIDES
    the implicit `"button"` ARIA role (matching the analysis doc's own
    contract: "Trigger: role='menuitem' aria-haspopup='menu'
    aria-expanded aria-controls data-highlighted data-state
    data-disabled"), PLUS native `popovertarget` pointing at Content's
    id -- same "declarative zero-JS baseline, JS layers semantics on
    top" platform split `dropdown_menu.pl`'s own Trigger uses: a page
    with `assets/js/components/menubar.js` never loaded still opens/
    closes each menu independently on click (native `popover="auto"`
    light-dismiss still works), just without hover-switch, cross-menu
    arrow nav, roving tabindex across triggers, or any of
    `lib/menu.js`'s own item interactions.
  - `Content` delegates wholesale to `menu_content/2` -- `side(bottom)`
    `align(start)` (already `menu_content/2`'s own defaults, matching
    the analysis doc's own "positioned below its trigger" placement),
    `aria-labelledby` wired to the owning Trigger's id.
  - `data-highlighted` on Trigger is NEVER server-rendered (same
    documented convention as `_menu.pl`'s own Item contract) -- it is
    entirely `assets/js/components/menubar.js`'s job, mirroring which
    trigger's menu is the currently-open one.
  - `menubar/2`'s own cross-part computation: exactly one Trigger,
    across the WHOLE bar, carries an explicit `tabindex="0"` (the
    initial roving-focus tab stop -- first non-disabled Trigger unless
    the caller already marked one `active(true)`), every other Trigger
    `tabindex="-1"` -- same "convenience template does the cross-item
    computation, the bare part template does not" split
    `toolbar.pl`/`toggle_group.pl` already use.

**Platform choice (adr/0026 rule 3) -- identical split to Dropdown
Menu.** Native `popovertarget` + `popover="auto"` carries open/close/
light-dismiss per menu; `assets/js/lib/menu.js` (REUSED, unmodified)
carries everything genuinely irreducible inside each Content (roving
highlight, typeahead, submenu hover/keyboard/positioning, checkbox/
radio toggling, close-on-select); `assets/js/lib/roving-focus.js`
(REUSED, unmodified) carries the top-level trigger row's own single-
tab-stop arrow-key nav, exactly as `prolog/ui/toolbar.pl`'s own
`<px-toolbar>` already uses it. `assets/js/components/menubar.js`'s
`<px-menubar>` is the coordination layer described in that file's own
header: hover-switch-when-open, and bridging ArrowLeft/ArrowRight
between "move between top-level triggers" (free, via
`installRovingFocus`) and "move between adjacent menubar menus from
inside an open Content" (new code, reading `event.defaultPrevented` to
detect and yield to `lib/menu.js`'s own submenu ArrowRight/ArrowLeft
handling -- see that file's header for the full mechanism, since
NEITHER `_menu.pl` nor `lib/menu.js` is modified for this port, per
the task's REUSE constraint).

**Gap (documented, not shipped): no per-Trigger `currentTabStopId`
ownership separate from `lib/roving-focus.js`'s own tabindex-is-the-
state model.** Upstream Radix has Menubar itself own
`currentTabStopId` rather than letting its embedded RovingFocusGroup
own it, specifically to handle a trigger that was opened by CLICK then
dismissed by OUTSIDE-click without ever receiving real DOM focus (a
known Safari quirk: `<button>` does not always receive focus on
click). This port's Trigger is a real, always-clickable-and-
focusable `<button>`, and Chromium (this port's verification target,
adr/0026 rule 7(c)) DOES focus a button on click, so
`lib/roving-focus.js`'s own "tabindex IS the state" model (unmodified,
per the REUSE constraint) is sufficient here without a parallel
Prolog/JS-side `currentTabStopId` -- same accepted-gap shape every
other documented platform simplification in this library uses.

**DOM/ARIA contract emitted** (docs/radix-port-analysis.md's "Menubar"
entry plus `_menu.pl`'s own Content contract, adr/0026 rule 2):

    Root (`<div role="menubar">`, wrapped in `<px-menubar>`):
        data-orientation="horizontal" (this port's own additive CSS/JS
        hook, same convention as every other roving-focus family
        member -- Menubar has no orientation OPTION, it is always
        horizontal, matching upstream, so this is never conditional).
    Menu (`menubar_menu/2`'s wrapper `<div class="px-menubar-menu">`):
        data-state="open|closed" -- a wrapper node upstream doesn't
        have (Menu is a React-context-only grouping component there);
        needed here purely as the DOM anchor
        `assets/js/components/menubar.js` scopes one Trigger+Content
        pair against, same rationale as `_menu.pl`'s own `menu_sub/2`
        wrapper.
    Trigger (`<button role="menuitem">`):
        aria-haspopup="menu", aria-expanded, aria-controls (Content's
        id), data-state, tabindex="0|-1" (menubar/2's own roving-
        tabindex computation), [data-disabled="" disabled], PLUS
        native popovertarget (additive).
    Content (`<div>`): `menu_content/2`'s own full contract --
        role="menu", popover="auto", tabindex="-1", data-state,
        data-side (default "bottom"), data-align (default "start"),
        data-side-offset, data-align-offset, aria-labelledby
        (Trigger's id).

Options (plain lists, adr/0026 rule 1):

  `menubar_root/2` Opts:
    class(C)        merged with the default class, default first
                    ("px-menubar C").
    anything else   passed through verbatim, appended AFTER the
                    computed attributes.

  `menubar_trigger/2` Opts:
    open(Bool)      default `false`. Drives `aria-expanded`,
                    `data-state` (open|closed).
    active(Bool)    default `false`. `true` renders `tabindex="0"`;
                    `menubar/2` computes and injects this
                    automatically (see below) unless the caller
                    already set it explicitly.
    disabled(Bool)  default `false`. Adds `data-disabled=""` plus the
                    native `disabled` attribute; excluded from
                    `menubar/2`'s active-trigger auto-pick.
    controls(Id)    REQUIRED for a standalone call to actually wire
                    anything (Content's id) -- emitted as BOTH
                    `aria-controls` and the native `popovertarget`.
                    Without it the Trigger still renders (a plain,
                    inert menuitem button) rather than throwing --
                    same graceful-degradation posture as
                    `dropdown_menu_trigger/2`.
    class(C), anything else  pass-through, as usual.

  `menubar_content/2` Opts: everything `menu_content/2` takes (`id(_)`,
                    `open(_)`, `labelledby(_)`, `side(_)` default
                    `bottom`, `align(_)` default `start`,
                    `side_offset(_)`, `align_offset(_)`, `class(_)`) --
                    forwarded verbatim; this template adds no new
                    option of its own, only the `menubar_content` bare-
                    call name, same reason `dropdown_menu_content/2`
                    exists.

  `menubar_menu/2` Opts: everything `menubar_root/2`-adjacent parts
                    need, PLUS
    open(Bool)      default `false`. Forwarded to both Trigger and
                    Content.
    disabled(Bool)  forwarded to Trigger only.
    active(Bool)    forwarded to Trigger (see `menubar/2`'s own
                    override below).
    id(Id)          optional; base every generated part's id is built
                    from (`<Id>-trigger`/`-content`); gensym'd
                    (`px-menubar-menu-N`) when absent, same convention
                    as `dropdown_menu/2`'s `base_id/2`.
    class(C)        merged onto the `.px-menubar-menu` wrapper.

  `menubar_menu/2` second argument: `[TriggerChildren, ContentChildren]`
                    (mirrors `dropdown_menu/2`'s Parts shape exactly).

  `menubar/2` Opts: everything `menubar_root/2` takes -- no options of
                    its own beyond what it forwards.
  `menubar/2` second argument: a list of `menubar_menu/2` terms (rule
                    1: "parts are template terms"); any other term is
                    passed through to Root's children unmodified, same
                    pass-through-unmodified rule `toolbar/2` uses.
                    Cross-part computation: exactly one Trigger across
                    every Menu gets `active(true)` injected (first
                    explicit `active(true)` anywhere wins; else the
                    first non-disabled Trigger in DOM order; else none)
                    -- identical algorithm shape to `toolbar.pl`'s own
                    `mark_active_parts/2`, simplified for Menubar's
                    single-level (no nested-group) candidate list.
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

tabindex_attrs(true, [tabindex(0)])  :- !.
tabindex_attrs(_,    [tabindex(-1)]).

disabled_attrs(true, [data_disabled(""), disabled]) :- !.
disabled_attrs(_,    []).

		 /*******************************
		 *             ROOT             *
		 *******************************/

%!  menubar_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `menubar_root([], Menus)`. Renders the
%   `<px-menubar>` custom-element wrapper (adr/0026 rule 4) around a
%   server-rendered `<div role="menubar">` -- without JS upgrade, every
%   Trigger's native `popovertarget` still fully opens/closes its own
%   Content independently (native `popover="auto"` handles dismissal);
%   see the module header's "Platform choice" for exactly what stays
%   and what's lost (hover-switch, cross-menu arrow nav, roving
%   tabindex).
px_template:render_helper(menubar_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_menubar, [], [div(Attrs, Children)]).

root_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-menubar", ClassVal, Opts1),
    append([ [role(menubar), data_orientation(horizontal), class(ClassVal)],
             Opts1
           ], Attrs).

		 /*******************************
		 *            TRIGGER           *
		 *******************************/

%!  menubar_trigger(+Opts, +Children) is det.
%
%   Bare-call template surface: `menubar_trigger([open(true),
%   controls(Id)], "File")`. A real `<button>` with `role="menuitem"`
%   overriding the implicit button role -- see the module header.
px_template:render_helper(menubar_trigger(Opts, Children), S) :-
    trigger_attrs(Opts, Attrs),
    px_template:render(S, button(Attrs, Children)).

trigger_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_bool(open, false, Opts0, Open, Opts1),
    take_bool(active, false, Opts1, Active, Opts2),
    take_bool(disabled, false, Opts2, Disabled, Opts3),
    take_controls(Opts3, ControlsOpt, Opts4),
    merge_class(Opts4, "px-menubar-trigger", ClassVal, Opts5),
    state_atom(Open, State),
    tabindex_attrs(Active, TabAttrs),
    disabled_attrs(Disabled, DisabledAttrs),
    (   ControlsOpt = controls(Id)
    ->  WireAttrs = [aria_controls(Id), popovertarget(Id)]
    ;   WireAttrs = []
    ),
    append([ [type(button), role(menuitem), aria_haspopup(menu)],
             WireAttrs,
             TabAttrs,
             [aria_expanded(Open), data_state(State), class(ClassVal)],
             DisabledAttrs,
             Opts5
           ], Attrs).

		 /*******************************
		 *            CONTENT           *
		 *******************************/

%!  menubar_content(+Opts, +Children) is det.
%
%   Bare-call template surface: `menubar_content([id("m1"), open(true),
%   labelledby("m1-trigger")], [...])`. A thin rename over
%   `menu_content/2` -- see the module header for why no attribute
%   computation lives here at all (`side(bottom)`/`align(start)` are
%   already that template's own defaults).
px_template:render_helper(menubar_content(Opts, Children), S) :-
    must_be(list, Opts),
    px_template:render(S, menu_content(Opts, Children)).

		 /*******************************
		 *             MENU             *
		 *******************************/

%!  menubar_menu(+Opts, +Parts) is det.
%
%   Parts = [TriggerChildren, ContentChildren]. The common case: a
%   `.px-menubar-menu` wrapper around one Trigger + one Content,
%   `open(_)` threaded to both, Trigger's `aria-controls`/
%   `popovertarget` wired to Content's `id` automatically, and
%   Content's `aria-labelledby` wired to Trigger's `id` -- same
%   division of labour as `dropdown_menu/2`.
menubar_menu(Opts, Parts) ~> \menubar_menu_render(Opts, Parts).

px_template:render_helper(menubar_menu_render(Opts, [TriggerKids, ContentKids]), S) :-
    must_be(list, Opts),
    take_bool(open, false, Opts, Open, _),
    take_bool(disabled, false, Opts, Disabled, _),
    take_bool(active, false, Opts, Active, _),
    base_id(Opts, Base),
    format(atom(TriggerId), '~w-trigger', [Base]),
    format(atom(ContentId), '~w-content', [Base]),
    exclude(menu_convenience_only_opt, Opts, WrapperOpts0),
    merge_class(WrapperOpts0, "px-menubar-menu", WrapperClass, WrapperOpts1),
    state_atom(Open, State),
    TriggerOpts = [ open(Open), active(Active), disabled(Disabled),
                     controls(ContentId), id(TriggerId)
                   ],
    ContentOpts = [open(Open), id(ContentId), labelledby(TriggerId)],
    append([ [data_state(State), class(WrapperClass)], WrapperOpts1 ], WrapperAttrs),
    px_template:render(S,
        div(WrapperAttrs,
          [ menubar_trigger(TriggerOpts, TriggerKids),
            menubar_content(ContentOpts, ContentKids)
          ])).

menu_convenience_only_opt(open(_)).
menu_convenience_only_opt(disabled(_)).
menu_convenience_only_opt(active(_)).
menu_convenience_only_opt(id(_)).

%!  base_id(+Opts, -Base) is det.
%
%   `id(Base)` from Opts if the caller supplied one; otherwise a fresh
%   gensym'd id -- same convention as `dropdown_menu.pl`'s
%   `base_id/2`.
base_id(Opts, Base) :-
    (   memberchk(id(Base), Opts)
    ->  true
    ;   gensym(px_menubar_menu_, Base)
    ).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  menubar(+Opts, +Menus) is det.
%
%   The common case: Root around a list of `menubar_menu/2` terms, with
%   exactly one Trigger across the WHOLE bar marked `active(true)` (the
%   top-level roving-focus group's initial, and ONLY, tab stop) unless
%   the caller already marked one explicitly -- see the module header.
menubar(Opts, Menus) ~> \menubar_render(Opts, Menus).

px_template:render_helper(menubar_render(Opts, Menus), S) :-
    must_be(list, Opts),
    mark_active_menus(Menus, Menus1),
    px_template:render(S, menubar_root(Opts, Menus1)).

%!  mark_active_menus(+Menus0, -Menus) is det.
%
%   Picks exactly one `menubar_menu/2` Trigger to be the top-level
%   roving-focus tab stop (first explicit `active(true)` anywhere;
%   else the first non-disabled Menu in DOM order; else none, if every
%   Menu is disabled or there are none at all), then rewrites Menus0 so
%   EVERY `menubar_menu/2` term carries an explicit `active(true)` or
%   `active(false)` -- same "force the explicit value everywhere, not
%   just on the winner" shape as `toolbar.pl`'s `mark_active_parts/2`,
%   simplified here to a single flat level (Menubar has no nested-
%   group analogue to Toolbar's embedded Toggle Group).
mark_active_menus(Menus0, Menus) :-
    pick_chosen_menu_index(Menus0, ChosenIndex),
    rewrite_menus(Menus0, 1, ChosenIndex, Menus).

menu_status(menubar_menu(O, _), status(Disabled, Explicit)) :-
    !,
    ( memberchk(disabled(true), O) -> Disabled = true ; Disabled = false ),
    ( memberchk(active(true), O)   -> Explicit = true ; Explicit = false ).
menu_status(_, status(true, false)).
    % A non-menubar_menu/2 term (pass-through, per the module header)
    % is never a roving-focus candidate -- treated as "disabled" so it
    % can never be auto-picked, and carries no `active(_)` to force.

pick_chosen_menu_index(Menus, ChosenIndex) :-
    maplist(menu_status, Menus, Statuses),
    (   nth1(Idx, Statuses, status(_, true))
    ->  ChosenIndex = Idx
    ;   nth1(Idx, Statuses, status(false, _))
    ->  ChosenIndex = Idx
    ;   ChosenIndex = 0
    ).

rewrite_menus([], _, _, []).
rewrite_menus([M0|Ms0], Idx0, ChosenIndex, [M|Ms]) :-
    rewrite_menu(M0, Idx0, ChosenIndex, M),
    Idx1 is Idx0 + 1,
    rewrite_menus(Ms0, Idx1, ChosenIndex, Ms).

rewrite_menu(menubar_menu(O0, C), Idx, ChosenIndex, menubar_menu(O, C)) :-
    !,
    ( Idx =:= ChosenIndex -> set_active(O0, true, O) ; set_active(O0, false, O) ).
rewrite_menu(Other, _, _, Other).

set_active(O0, Val, [active(Val)|O1]) :-
    ( selectchk(active(_), O0, O1) -> true ; O1 = O0 ).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Order 18: the next free slot after dropdown_menu.pl's Order 17
%   (adr/0026 rule 8: Menubar is the menus tier's second entry, right
%   after Dropdown Menu -- its own explicit dependency, "cannot be
%   ported before Menu").
px_ui:demo(menubar, 18, \menubar_demo).

menubar_demo ~>
    div(class("px-menubar-demo"),
      [ section(class("ui-demo-block"),
          [ h3("Classic File / Edit / View menu bar"),
            p("Click a trigger to open its menu (native popovertarget + popover=\"auto\" open/close/light-dismiss with zero JS). Once ANY menu is open, hovering a different trigger switches directly to it -- File closes, the hovered one opens. ArrowLeft/ArrowRight move between triggers at the top level, and, from inside an open menu, jump to the adjacent menubar menu (unless the highlighted item is a submenu trigger, or ArrowLeft is closing a submenu back one level -- both yield to assets/js/lib/menu.js's own handling)."),
            menubar([id("mb-demo"), aria_label("Main menu")],
              [ menubar_menu([id("mb-demo-file")],
                  [ "File",
                    [ menu_item([], [span("New Tab"), span(class("px-menu-shortcut"), "⌘T")]),
                      menu_item([], [span("New Window"), span(class("px-menu-shortcut"), "⌘N")]),
                      menu_separator([]),
                      menu_sub([id("mb-demo-file-share")],
                        [ "Share",
                          [ menu_item([], "Email link"),
                            menu_item([], "Copy link"),
                            menu_item([], "Embed")
                          ]
                        ]),
                      menu_separator([]),
                      menu_item([], [span("Print..."), span(class("px-menu-shortcut"), "⌘P")]),
                      menu_item([disabled(true)], "Print preview (disabled)")
                    ]
                  ]),
                menubar_menu([id("mb-demo-edit")],
                  [ "Edit",
                    [ menu_item([], [span("Undo"), span(class("px-menu-shortcut"), "⌘Z")]),
                      menu_item([], [span("Redo"), span(class("px-menu-shortcut"), "⇧⌘Z")]),
                      menu_separator([]),
                      menu_item([], [span("Cut"), span(class("px-menu-shortcut"), "⌘X")]),
                      menu_item([], [span("Copy"), span(class("px-menu-shortcut"), "⌘C")]),
                      menu_item([], [span("Paste"), span(class("px-menu-shortcut"), "⌘V")])
                    ]
                  ]),
                menubar_menu([id("mb-demo-view")],
                  [ "View",
                    [ menu_checkbox_item([checked(true)], "Always show bookmarks bar"),
                      menu_checkbox_item([], "Always show full URLs"),
                      menu_separator([]),
                      menu_item([], [span("Reload"), span(class("px-menu-shortcut"), "⌘R")]),
                      menu_item([disabled(true)], "Force reload (disabled)"),
                      menu_separator([]),
                      menu_label([], "Appearance"),
                      menu_radio_group([aria_label("Appearance")],
                        [ menu_radio_item([value("system"), checked(true)], "System"),
                          menu_radio_item([value("light")], "Light"),
                          menu_radio_item([value("dark")], "Dark")
                        ])
                    ]
                  ])
              ])
          ])
      ]).
