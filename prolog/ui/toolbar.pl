:- module(ui_toolbar, []).

%   No predicates are exported: toolbar_root/2, toolbar_button/1,2,
%   toolbar_link/1,2, toolbar_separator/1, toolbar_toggle_group/2 and
%   toolbar/2 are never called module-qualified -- bare-call dispatch
%   through px_template's tmpl/2 / render_helper/2 tables (adr/0019)
%   resolves them, the same pattern every other prolog/ui/*.pl module
%   uses.

/** <module> Toolbar (adr/0026): a row/column of heterogeneous controls
(buttons, links, an embedded Toggle Group) under ONE shared
roving-tabindex domain. WAI-ARIA Toolbar pattern.

Ported from Radix UI's Toolbar primitive (docs/radix-port-analysis.md,
"Toolbar" entry). Anatomy: `Root` (`toolbar_root/2`), `Button`
(`toolbar_button/1,2`), `Link` (`toolbar_link/1,2`), `Separator`
(`toolbar_separator/1`, delegating to `prolog/ui/separator.pl`'s
`separator/1` per the analysis doc -- Toolbar does not reimplement
Separator, it composes it), `ToggleGroup` (`toolbar_toggle_group/2`,
delegating to `prolog/ui/toggle_group.pl`'s `toggle_group/2`).
`toolbar/2` is the rule-1 top-level convenience template: Root around a
list of Parts, with the cross-part computation described below.

**Interactivity class: CUSTOM-ELEMENT** (the analysis doc's own
verdict, "same roving-tabindex justification as Tabs/Toggle Group").
`assets/js/components/toolbar.js`'s `<px-toolbar>` installs exactly
ONE `installRovingFocus/2` (`assets/js/lib/roving-focus.js`, this
port's second consumer after Toggle Group) scope over the Root, whose
`itemSelector` matches every focusable Toolbar item -- Buttons, Links,
AND an embedded Toggle Group's own Items -- so keyboard nav is one flat
tab-stop domain spanning heterogeneous children exactly as the analysis
doc specifies ("Toolbar's roving-focus group already spans all
children"), never per-part. Every part still renders its full,
reload-safe, no-JS-fallback state server-side (adr/0026 rule 4); without
JS, the whole toolbar degrades to a plain sequential Tab-through over
real `<button>`/`<a>` elements (whichever single one currently carries
`tabindex="0"`), no navigation lost, no error.

DOM/ARIA contract emitted (exactly the analysis doc's "Toolbar" entry):

    Root       <div role="toolbar" aria-orientation="horizontal|vertical"
                    data-orientation="horizontal|vertical" [dir="ltr|rtl"]>
    Button     <button type="button" tabindex="0|-1" [data-disabled="" disabled]>
    Link       <a tabindex="0|-1" href="...">
    Separator  -- prolog/ui/separator.pl's own contract, orientation
                  auto-flipped relative to Root's (see below)
    ToggleGroup -- prolog/ui/toggle_group.pl's own contract, unchanged

`aria-orientation` is ALWAYS emitted (unlike Separator's own
conditional-omit-when-horizontal convention) -- the analysis doc lists
it flatly on Root with no caveat, matching Radix's own
`aria-orientation={orientation}` (always rendered, both orientations).
`data-orientation` is this port's own additive CSS/JS hook, same
convention as every other roving-focus family member (Toggle Group,
soon Tabs). `dir` is pass-through only -- rendered on Root only when the
caller supplies `dir(ltr|rtl)`, both for native bidi rendering AND
because `installRovingFocus/2` (when not given an explicit `dir`
option) reads it straight off `getComputedStyle(container).direction`
at every keydown (`assets/js/lib/roving-focus.js`'s own header) -- no
separate JS-side direction sync needed.

Two additive-only extensions, per rule 2, both reusing conventions
already established by `prolog/ui/toggle_group.pl` (this library's
first roving-focus consumer):

  1. `tabindex="0"` on exactly one non-disabled candidate item ACROSS
     THE WHOLE TOOLBAR (Buttons, Links, and an embedded Toggle Group's
     own Items all count as candidates), `tabindex="-1"` on every
     other one, ALWAYS explicit -- same DOM-level encoding of "the
     current tab stop" `installRovingFocus/2` reads on install.
  2. `data-loop=""` on Root, only when `loop(true)` (default `false`,
     same as Toggle Group's own default and for the same reason: no
     upstream rendered attribute exists for this at all, so it needs
     SOME markup-level encoding, and this is the family's existing
     convention for it).

**The nested-Toggle-Group tab-stop problem, and how this port solves
it** (the analysis doc's own callout: "an embedded toggle group must
expose a 'roving focus disabled' mode so it defers to the parent
toolbar's single controller instead of running its own"):

`toolbar_toggle_group/2` is PURE structural delegation straight to
`toggle_group/2` (no Opts of its own) -- it does NOT, and does not need
to, know it is embedded in a Toolbar. Left alone, `toggle_group/2`
would run its OWN "pick exactly one non-disabled Item active" logic
(`mark_active/2` in toggle_group.pl) independently of Toolbar's own
pick, producing TWO `tabindex="0"` elements in the same DOM subtree --
one Toolbar thinks is the tab stop, one the embedded group thinks is.
`toolbar/2` (below) prevents this at the Prolog/markup layer, not the
JS layer: its cross-part computation treats a `toolbar_toggle_group/2`
part's Items as ordinary flat-list candidates alongside Buttons and
Links, and -- because `toggle_group/2`'s own auto-pick is defined to
never fire once ANY Item already carries an explicit `active(_)` option
(toggle_group.pl's `mark_active/2`: "UNLESS some Item already carries
its own `active(_)`") -- `toolbar/2` ALWAYS injects an explicit
`active(true)` on its one chosen candidate and `active(false)` on every
OTHER candidate, everywhere, including every Item inside every embedded
Toggle Group. That unconditionally short-circuits `toggle_group/2`'s
own auto-pick for any Toggle Group embedded via `toolbar/2`, so exactly
one `tabindex="0"` ever exists in the rendered markup, decided once, by
Toolbar. (Calling `toolbar_toggle_group/2` directly, bypassing
`toolbar/2`, does NOT get this treatment -- same "convenience template
does the cross-item computation, the bare part template does not" split
`toggle_group.pl` itself uses.)

The matching JS-layer half of the same problem -- an embedded
`<px-toggle-group>` custom element ALSO independently calls
`installRovingFocus/2` on its own connectedCallback, attaching a SECOND
keydown/focusin listener pair to the very same buttons Toolbar's own
scope already governs -- is solved in `assets/js/components/toolbar.js`,
documented there; see its header for the full explanation (short
version: `<px-toolbar>` reaches into every nested `<px-toggle-group>` it
finds and calls the uninstall function that element already stores on
itself, tearing down ONLY that nested roving-focus scope while leaving
the Toggle Group's own click-to-press behaviour untouched -- zero
changes needed to `toggle_group.pl`/`toggle_group.js`).

Options (a plain list, adr/0026 rule 1):

  `toolbar_root/2` Opts:
    orientation(horizontal|vertical)  default `horizontal` (Radix's own
                    default). Drives `data-orientation` AND
                    `aria-orientation`, both always emitted.
    dir(ltr|rtl)    optional, no default. Rendered verbatim as the
                    native `dir` attribute when given.
    loop(Bool)      `true`/`false`, default `false`. Emits
                    `data-loop=""` only when `true` -- extension 2
                    above.
    class(C)        merged with the default class, default first
                    ("px-toolbar C").
    anything else passed through verbatim, appended AFTER the computed
                    attributes -- same last-wins spread order as every
                    other port in this library.

  `toolbar_button/1,2` Opts:
    disabled(Bool)  `true`/`false`, default `false`. Adds
                    `data-disabled=""` plus the native `disabled`
                    attribute; excludes the Button from
                    `installRovingFocus/2`'s arrow-key targets and from
                    `toolbar/2`'s active-item pick.
    active(Bool)    `true`/`false`, default `false`. `true` renders
                    `tabindex="0"`; `toolbar/2` computes and injects
                    this automatically (extension 1 above) unless the
                    caller already set it explicitly somewhere in the
                    Parts list.
    class(C)        merged with the default class, default first
                    ("px-toolbar-item px-toolbar-button C").
    anything else (id(...), aria_label(...), data_*(...), ...) passed
                    through verbatim onto the `<button>`.

  `toolbar_link/1,2` Opts: same `active(Bool)`/`class(C)`/pass-through
                    shape as `toolbar_button/1,2` (default class
                    "px-toolbar-item px-toolbar-link"), but no
                    `disabled(_)` option -- upstream Radix's own
                    `Toolbar.Link` has no such prop either (a native
                    `<a>` has no `disabled` attribute; an
                    intentionally-inert link is simply not rendered as
                    one). `href(...)` is ordinary pass-through.

  `toolbar_separator/1` Opts:
    orientation(horizontal|vertical)  default `vertical` (the sensible
                    standalone default -- perpendicular to a
                    default-horizontal toolbar). `toolbar/2` overrides
                    this to the perpendicular of ROOT's own orientation
                    option automatically, UNLESS the caller already
                    passed `orientation(_)` explicitly on this specific
                    Separator (explicit always wins, same rule
                    `toggle_group.pl`'s `active(_)` override uses).
    anything else forwarded verbatim to `separator/1`
                    (`decorative(Bool)`, `class(C)`, `id(...)`, ...) --
                    `toolbar_separator/1` adds its own additive styling
                    hook `px-toolbar-separator` (merged in ahead of any
                    caller class, same last-wins order as everywhere
                    else) on top of `separator/1`'s own `px-separator`.

  `toolbar_toggle_group/2`: no Opts of its own -- pure delegation,
                    `toolbar_toggle_group(Opts, Items) ~>
                    toggle_group(Opts, Items)`. Opts/Items are exactly
                    `toggle_group/2`'s own (`type(single|multiple)`
                    required, etc.) See "the nested-Toggle-Group tab-
                    stop problem" above for how `toolbar/2` overrides
                    its Items' `active(_)`.

  `toolbar/2` second argument: a list of `toolbar_button/1,2`,
                    `toolbar_link/1,2`, `toolbar_separator/1` and
                    `toolbar_toggle_group/2` terms (rule 1: "parts are
                    template terms"); any other term is passed through
                    to Root's children unmodified, with no candidacy/
                    injection consideration attempted on it (same
                    pass-through-unmodified rule `toggle_group.pl`'s
                    `toggle_group/2` uses).

Both `toolbar_root/2` and `toolbar_button/1,2`/`toolbar_link/1,2`/
`toolbar_separator/1` are registered as `px_template:render_helper/2`
hooks (adr/0019) -- the Opts-list defaults/merge logic below is genuine
computation, the same reason `toggle_group.pl`'s equivalents are.
`toolbar_toggle_group/2` is a plain `~>` (pure structural delegation,
no computation of its own -- same shape `separator.pl`'s own
convenience template uses). `toolbar/2`, the rule-1 top-level
convenience template, is ALSO a `render_helper/2` hook -- picking the
one active candidate across heterogeneous, possibly-nested parts and
auto-flipping Separator orientation are genuine cross-part computation,
the same reason `toggle_group.pl`'s `toggle_group/2` is one too.
*/

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module('../px_template').
:- use_module(separator).
:- use_module(toggle_group).

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

		 /*******************************
		 *        OPTION HELPERS        *
		 *******************************/

valid_orientation(horizontal).
valid_orientation(vertical).

perpendicular(horizontal, vertical).
perpendicular(vertical, horizontal).

%!  take_bool(+Name, +Opts0, -Value, -Rest) is det.
%
%   Same helper as toggle_group.pl's / toggle.pl's.
take_bool(Name, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Opts1)
    ->  Value = V0
    ;   Value = false, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  merge_class(+Opts0, +Default, -ClassVal, -Rest) is det.
%
%   Same helper as toggle_group.pl's.
merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

orientation_opt(Opts, Orientation) :-
    (   memberchk(orientation(O), Opts),
        valid_orientation(O)
    ->  Orientation = O
    ;   Orientation = horizontal
    ).

		 /*******************************
		 *             ROOT             *
		 *******************************/

%!  toolbar_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `toolbar_root([], Parts)`. Renders the
%   `<px-toolbar>` custom-element wrapper (adr/0026 rule 4) around the
%   server-rendered `<div>` -- the wrapper is what the custom element
%   registers against; the div/buttons/links/separator/toggle-group
%   inside carry the whole ARIA/data contract and are exactly as usable
%   (minus arrow-key roving nav -- plain sequential Tab-through over
%   whichever single item currently has tabindex="0" still works) if
%   `<px-toolbar>` is never upgraded.
px_template:render_helper(toolbar_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_toolbar, [], [div(Attrs, Children)]).

root_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    orientation_opt(Opts0, Orientation),
    take_bool(loop, Opts0, Loop, Opts1),
    merge_class(Opts1, "px-toolbar", ClassVal, Opts2),
    exclude(root_reserved_opt, Opts2, Extra0),
    dir_attrs(Opts2, DirAttrs),
    exclude(dir_opt, Extra0, Extra),
    loop_attrs(Loop, LoopAttrs),
    append([ [role(toolbar), aria_orientation(Orientation),
              data_orientation(Orientation)],
             DirAttrs, LoopAttrs, [class(ClassVal)], Extra
           ], Attrs).

dir_attrs(Opts, [dir(D)]) :- memberchk(dir(D), Opts), !.
dir_attrs(_, []).

dir_opt(dir(_)).

loop_attrs(true, [data_loop("")]) :- !.
loop_attrs(_,    []).

root_reserved_opt(orientation(_)).
root_reserved_opt(loop(_)).
root_reserved_opt(class(_)).

		 /*******************************
		 *            BUTTON            *
		 *******************************/

%!  toolbar_button(+Opts) is det.
%!  toolbar_button(+Opts, +Children) is det.
%
%   Bare-call template surface: `toolbar_button([], "Copy")`.
%   `toolbar_button/1` is the no-label shorthand (Children = []), same
%   `/1` delegates to `/2` shape as `toggle_group_item/1,2`.
px_template:render_helper(toolbar_button(Opts), S) :-
    px_template:render_helper(toolbar_button(Opts, []), S).
px_template:render_helper(toolbar_button(Opts, Children), S) :-
    button_attrs(Opts, Attrs),
    px_template:render(S, button(Attrs, Children)).

button_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_bool(disabled, Opts0, Disabled, Opts1),
    take_bool(active, Opts1, Active, Opts2),
    merge_class(Opts2, "px-toolbar-item px-toolbar-button", ClassVal, Opts3),
    exclude(item_reserved_opt, Opts3, Extra),
    tabindex_attrs(Active, TabAttrs),
    disabled_attrs(Disabled, DisAttrs),
    append([ [type(button)], TabAttrs, [class(ClassVal)], DisAttrs, Extra ],
           Attrs).

tabindex_attrs(true, [tabindex(0)])  :- !.
tabindex_attrs(_,    [tabindex(-1)]).

disabled_attrs(true, [data_disabled(""), disabled]) :- !.
disabled_attrs(_,    []).

item_reserved_opt(disabled(_)).
item_reserved_opt(active(_)).
item_reserved_opt(class(_)).

		 /*******************************
		 *             LINK             *
		 *******************************/

%!  toolbar_link(+Opts) is det.
%!  toolbar_link(+Opts, +Children) is det.
%
%   Bare-call template surface: `toolbar_link([href("/docs")], "Docs")`.
%   No `disabled(_)` option -- see the module header.
px_template:render_helper(toolbar_link(Opts), S) :-
    px_template:render_helper(toolbar_link(Opts, []), S).
px_template:render_helper(toolbar_link(Opts, Children), S) :-
    link_attrs(Opts, Attrs),
    px_template:render(S, a(Attrs, Children)).

link_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_bool(active, Opts0, Active, Opts1),
    merge_class(Opts1, "px-toolbar-item px-toolbar-link", ClassVal, Opts2),
    exclude(link_reserved_opt, Opts2, Extra),
    tabindex_attrs(Active, TabAttrs),
    append([ TabAttrs, [class(ClassVal)], Extra ], Attrs).

link_reserved_opt(active(_)).
link_reserved_opt(class(_)).

		 /*******************************
		 *           SEPARATOR          *
		 *******************************/

%!  toolbar_separator(+Opts) is det.
%
%   Bare-call template surface: `toolbar_separator([])`. Delegates to
%   `separator/1` (`prolog/ui/separator.pl`) -- Toolbar composes
%   Separator rather than reimplementing it, per the analysis doc's own
%   dependency list ("context, roving-focus, separator, toggle-group,
%   direction"). Default `orientation(vertical)` here is the sensible
%   standalone default; `toolbar/2` overrides it to the perpendicular
%   of Root's own orientation automatically (see module header).
px_template:render_helper(toolbar_separator(Opts0), S) :-
    must_be(list, Opts0),
    orientation_opt_default(Opts0, vertical, Orientation),
    merge_class(Opts0, "px-toolbar-separator", ClassVal, Opts1),
    exclude(sep_reserved_opt, Opts1, Extra),
    append([ [orientation(Orientation), class(ClassVal)], Extra ], SepOpts),
    px_template:render(S, separator(SepOpts)).

orientation_opt_default(Opts, Default, Orientation) :-
    (   memberchk(orientation(O), Opts),
        valid_orientation(O)
    ->  Orientation = O
    ;   Orientation = Default
    ).

sep_reserved_opt(orientation(_)).
sep_reserved_opt(class(_)).

		 /*******************************
		 *          TOGGLE GROUP         *
		 *******************************/

%!  toolbar_toggle_group(+Opts, +Items) is det.
%
%   Pure structural delegation to `toggle_group/2` -- see the module
%   header, "the nested-Toggle-Group tab-stop problem", for why this
%   stays a plain, computation-free `~>` and where the actual
%   coordination logic lives (`toolbar/2`, below).
toolbar_toggle_group(Opts, Items) ~> toggle_group(Opts, Items).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  toolbar(+Opts, +Parts) is det.
%
%   The common case: Root around a list of Parts, with Root's
%   orientation threaded onto every `toolbar_separator/1` Part
%   (auto-flipped to the perpendicular, unless that Part already
%   carries its own explicit `orientation(_)`) and exactly one
%   non-disabled candidate item -- across Buttons, Links, AND every
%   Item inside every embedded `toolbar_toggle_group/2` -- marked
%   `active(true)` (the roving-focus group's initial, and ONLY, tab
%   stop) unless the caller already marked one explicitly.
toolbar(Opts, Parts) ~> \toolbar_render(Opts, Parts).

px_template:render_helper(toolbar_render(Opts, Parts), S) :-
    orientation_opt(Opts, Orientation),
    perpendicular(Orientation, Perp),
    maplist(inject_separator_orientation(Perp), Parts, Parts1),
    mark_active_parts(Parts1, Parts2),
    px_template:render(S, toolbar_root(Opts, Parts2)).

%!  inject_separator_orientation(+Perp, +Part0, -Part) is det.
%
%   A `toolbar_separator(_)` Part without its own explicit
%   `orientation(_)` gets Root's perpendicular orientation injected;
%   any other term (including one that already set `orientation(_)`
%   itself) passes through unmodified.
inject_separator_orientation(Perp, toolbar_separator(O0), toolbar_separator(O)) :-
    !,
    (   memberchk(orientation(_), O0)
    ->  O = O0
    ;   O = [orientation(Perp)|O0]
    ).
inject_separator_orientation(_, Other, Other).

%!  mark_active_parts(+Parts0, -Parts) is det.
%
%   Flattens Parts0 into the ordered list of roving-focus candidates
%   (every `toolbar_button/1,2`, `toolbar_link/1,2`, and every
%   `toggle_group_item/1,2` inside every `toolbar_toggle_group/2`),
%   picks exactly one to be the tab stop (first explicit `active(true)`
%   anywhere; else the first non-disabled candidate in flat DOM order --
%   deliberately NOT `toggle_group.pl`'s own "prefer the pressed Item"
%   nicety: Toolbar is a plain heterogeneous container, not a
%   radio-like selection widget, and the WAI-ARIA APG toolbar pattern's
%   own convention is "the first item", full stop, regardless of what
%   any embedded control's state happens to be; else none, if every
%   candidate is disabled or there are none at all), then rewrites
%   Parts0 so EVERY candidate carries an explicit `active(true)` or
%   `active(false)` -- forcing the explicit value everywhere, not just
%   on the winner, is what unconditionally suppresses `toggle_group/2`'s
%   own independent auto-pick for any embedded Toggle Group (see module
%   header).
mark_active_parts(Parts0, Parts) :-
    flatten_candidates(Parts0, Flat),
    pick_chosen_index(Flat, ChosenIndex),
    rewrite_parts(Parts0, 1, ChosenIndex, Parts).

flatten_candidates(Parts, Flat) :-
    findall(O,
            ( member(P, Parts), part_candidate_opts(P, Os), member(O, Os) ),
            Flat).

part_candidate_opts(toolbar_button(O),    [O]) :- !.
part_candidate_opts(toolbar_button(O,_),  [O]) :- !.
part_candidate_opts(toolbar_link(O),      [O]) :- !.
part_candidate_opts(toolbar_link(O,_),    [O]) :- !.
part_candidate_opts(toolbar_toggle_group(_, Items), Os) :-
    !,
    findall(O, ( member(It, Items), toggle_group_item_opts(It, O) ), Os).
part_candidate_opts(_, []).

toggle_group_item_opts(toggle_group_item(O),   O).
toggle_group_item_opts(toggle_group_item(O,_), O).

opts_status(O, status(Disabled, Explicit)) :-
    (   memberchk(disabled(true), O) -> Disabled = true ; Disabled = false ),
    (   memberchk(active(true), O)   -> Explicit = true ; Explicit = false ).

pick_chosen_index(Flat, ChosenIndex) :-
    maplist(opts_status, Flat, Statuses),
    (   nth1(Idx, Statuses, status(_, true))
    ->  ChosenIndex = Idx
    ;   nth1(Idx, Statuses, status(false, _))
    ->  ChosenIndex = Idx
    ;   ChosenIndex = 0
    ).

rewrite_parts([], _, _, []).
rewrite_parts([P0|Ps0], Idx0, ChosenIndex, [P|Ps]) :-
    rewrite_part(P0, Idx0, ChosenIndex, P, Idx1),
    rewrite_parts(Ps0, Idx1, ChosenIndex, Ps).

rewrite_part(toolbar_button(O0), Idx0, ChosenIndex, toolbar_button(O), Idx) :-
    !, set_active_at(O0, Idx0, ChosenIndex, O), Idx is Idx0 + 1.
rewrite_part(toolbar_button(O0,C), Idx0, ChosenIndex, toolbar_button(O,C), Idx) :-
    !, set_active_at(O0, Idx0, ChosenIndex, O), Idx is Idx0 + 1.
rewrite_part(toolbar_link(O0), Idx0, ChosenIndex, toolbar_link(O), Idx) :-
    !, set_active_at(O0, Idx0, ChosenIndex, O), Idx is Idx0 + 1.
rewrite_part(toolbar_link(O0,C), Idx0, ChosenIndex, toolbar_link(O,C), Idx) :-
    !, set_active_at(O0, Idx0, ChosenIndex, O), Idx is Idx0 + 1.
rewrite_part(toolbar_toggle_group(GO, Items0), Idx0, ChosenIndex,
             toolbar_toggle_group(GO, Items), Idx) :-
    !, rewrite_items(Items0, Idx0, ChosenIndex, Items, Idx).
rewrite_part(Other, Idx0, _, Other, Idx0).

rewrite_items([], Idx, _, [], Idx).
rewrite_items([It0|Its0], Idx0, ChosenIndex, [It|Its], Idx) :-
    (   toggle_group_item_opts(It0, O0)
    ->  set_active_at(O0, Idx0, ChosenIndex, O),
        Idx1 is Idx0 + 1,
        rebuild_item(It0, O, It)
    ;   It = It0, Idx1 = Idx0
    ),
    rewrite_items(Its0, Idx1, ChosenIndex, Its, Idx).

rebuild_item(toggle_group_item(_),    O, toggle_group_item(O)).
rebuild_item(toggle_group_item(_,C),  O, toggle_group_item(O,C)).

set_active_at(O0, Idx, Idx, O) :- !, set_active(O0, true, O).
set_active_at(O0, _,   _,   O) :- set_active(O0, false, O).

set_active(O0, Val, [active(Val)|O1]) :-
    (   selectchk(active(_), O0, O1)
    ->  true
    ;   O1 = O0
    ).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Toolbar is a "roving-focus consumer" (adr/0026 rule 8's porting
%   order), landing right after Toggle Group -- Order 13 is the next
%   free slot (1 visually_hidden, 2 accessible_icon, 3 label,
%   4 separator, 5 collapsible, 6 progress, 7 toggle, 8 radio_group,
%   9 checkbox/switch, 10 aspect_ratio, 11 avatar, 12 toggle_group).
px_ui:demo(toolbar, 13, \toolbar_demo).

%   Arity-0, so it is an ATOM -- called via the explicit \ escape, same
%   as every other component's demo template (a bare atom is a text
%   node, not a callable dispatch, in render/2 -- adr/0019). One
%   horizontal text-editing toolbar: two plain Buttons, a Separator
%   (auto-flipped vertical), an embedded single-select Toggle Group
%   (bold/italic/underline -- exercises the nested-tab-stop
%   coordination), another Separator, and a Link -- covers every part
%   this port has.
toolbar_demo ~>
    div(class("px-toolbar-demo"),
      [ h3("Text-editing toolbar"),
        p("Tab reaches exactly ONE stop; Arrow keys move focus across every item -- Buttons, the embedded Toggle Group's own Items, and the Link -- as a single flat sequence. Separators are skipped and auto-flipped vertical (perpendicular to this horizontal toolbar)."),
        toolbar([id("tb-demo"), aria_label("Text formatting")],
          [ toolbar_button([id("tb-cut")], "Cut"),
            toolbar_button([id("tb-copy")], "Copy"),
            toolbar_separator([]),
            toolbar_toggle_group([id("tb-format"), type(single)],
              [ toggle_group_item([pressed(true)], "Bold"),
                toggle_group_item([], "Italic"),
                toggle_group_item([], "Underline")
              ]),
            toolbar_separator([]),
            toolbar_link([href("#")], "Help")
          ]),

        h3("Vertical orientation, with a disabled Button"),
        p("orientation(vertical) flips both the layout and every un-overridden Separator back to horizontal."),
        toolbar([id("tb-vertical"), orientation(vertical)],
          [ toolbar_button([], "Up"),
            toolbar_button([disabled(true)], "Middle (disabled)"),
            toolbar_separator([]),
            toolbar_button([], "Down")
          ])
      ]).
