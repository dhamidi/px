:- module(ui_menu_parts, []).

%   No predicates are exported: every template below (menu_content/2,
%   menu_item/1,2, menu_checkbox_item/2, menu_radio_group/2,
%   menu_radio_item/2, menu_label/2, menu_separator/1, menu_sub/2,
%   menu_sub_trigger/2, menu_sub_content/2, menu_item_indicator/2,
%   menu_arrow/1) is never called module-qualified -- they are term
%   SHAPES that px_template's bare-call dispatch resolves via the
%   multifile px_template:render_helper/2 table (registered below),
%   the same pattern every other prolog/ui/*.pl module uses.
%
%   A leading-underscore filename: `prolog/px_ui.pl` auto-loads every
%   `.pl` file under prolog/ui/ (adr/0026's own header note), and a
%   leading underscore does not opt a file out of that -- this module
%   IS loaded, at the same time as every sibling. It registers NO
%   `px_ui:demo/3` clause, though (see the tail of this file): it is
%   not itself a kitchen-sink component, just the shared vocabulary
%   `prolog/ui/dropdown_menu.pl` (and, later, context_menu.pl/
%   menubar.pl) compose into one.

/** <module> Menu shared machinery (adr/0026): the part templates every
menu wrapper (Dropdown Menu first, Context Menu/Menubar next) composes,
ported from Radix UI's internal `menu` package (docs/radix-port-
analysis.md, "Menu (shared machinery, not a public component)" entry
-- "`dropdown-menu`, `context-menu`, and `menubar` are all thin
composers over this internal package... Any port of those three
requires porting this state machine ONCE, as shared infrastructure,
rather than three times").

This module owns the SERVER-RENDERED half of that shared machinery --
the anatomy/ARIA/data-attribute contract every part below is generic
over which wrapper composes it. `assets/js/lib/menu.js` owns the
CLIENT half (roving highlight, typeahead, submenu hover/keyboard,
checkbox/radio toggling, close-on-select) -- see that file's header for
the exact API a wrapper's own custom element (e.g.
`assets/js/components/dropdown_menu.js`'s `<px-dropdown-menu>`) drives
it through. Neither half knows which wrapper is using it: Dropdown
Menu supplies only its own trigger-opening semantics on top (exactly
the analysis doc's own "port implication": "parameterized by trigger
type (click / right-click / hover-switch)... with dropdown-menu /
context-menu / menubar each supplying only trigger-opening semantics").

**Platform choice (adr/0026 rule 3) -- every Content level is a native
`popover="auto"` element, DOM-NESTED inside its parent's Content rather
than portaled.** Upstream Radix portals every Content (root and every
submenu level) to the end of `<body>`, relying on its own dismissable-
layer/focus-scope machinery to make nested levels behave as one
logical unit. This port has neither dismissable-layer nor a portal
abstraction (rule 3: "prefer... `popover`... before writing any JS");
instead, `menu_sub_content/2` is rendered as a literal DOM descendant
of the `menu_sub/2` wrapper it belongs to, which is itself a descendant
of the parent level's Content. Two things fall out of that nesting
choice, both load-bearing, both exploited by `lib/menu.js` rather than
re-solved there:

  1. **Light-dismiss stacking is free and correct.** The Popover
     light-dismiss algorithm (HTML spec) only auto-closes OTHER "auto"
     popovers that are not its own DOM ancestor/descendant. Because a
     submenu's Content is a genuine DOM descendant of its parent
     Content, opening it never auto-closes the parent, and Escape
     (which closes the topmost open auto popover) naturally closes
     exactly one level at a time -- upstream's "ArrowLeft/Escape closes
     back" requirement, for the Escape half, with zero JS.
  2. **"Close the entire tree" is a plain DOM walk.** `lib/menu.js`'s
     close-on-select path (see its header) climbs `parentElement.closest`
     from the activated item's own Content up through every ancestor
     Content and calls `hidePopover()` on each -- again possible only
     because the levels are real DOM ancestors, not portal siblings
     Radix's own React tree tracks out-of-band.

**Every Content level shares one class marker, `px-menu-content`**
(`menu_sub_content/2` adds `px-menu-sub-content` ADDITIONALLY, never
instead) -- this is what lets `lib/menu.js` scope its roving-focus
item collection to "items belonging to THIS level" via
`item.closest('.px-menu-content') === thisContentEl`, regardless of
how many `menu_radio_group`/`menu_label`/`menu_sub` wrapper `<div>`s
sit between Content and a given Item. See that file's header for the
full mechanism.

**DOM/ARIA contract emitted** (docs/radix-port-analysis.md's "Menu"
entry, adr/0026 rule 2 -- sacred except where noted below):

    Content (`menu_content/2`, `menu_sub_content/2`):
        <div role="menu" tabindex="-1" popover="auto"
             data-state="open|closed" data-orientation="vertical"
             data-side="..." data-align="..." data-side-offset="..."
             data-align-offset="..." [aria-labelledby="..."]
             class="px-menu-content [px-menu-sub-content]">
    Item (`menu_item/1,2`):
        <div role="menuitem" tabindex="-1" [data-disabled=""]
             [aria-disabled="true"] class="px-menu-item">
        (`data-highlighted` is NEVER server-rendered -- it mirrors live
        DOM focus, `lib/menu.js`'s job entirely; see its header.)
    CheckboxItem (`menu_checkbox_item/2`):
        <div role="menuitemcheckbox" tabindex="-1" aria-checked="..."
             data-state="checked|unchecked" [data-disabled=""]
             class="px-menu-item px-menu-checkbox-item">
          <span aria-hidden="true" data-state="..."
                class="px-menu-item-indicator">...</span>
          ...Children
        </div>
    RadioGroup (`menu_radio_group/2`): <div role="group" [aria-label]>
    RadioItem (`menu_radio_item/2`):
        <div role="menuitemradio" tabindex="-1" aria-checked="..."
             data-state="checked|unchecked" [data-value="..."]
             [data-disabled=""] class="px-menu-item px-menu-radio-item">
          <span aria-hidden="true" ...>...</span> ...Children
        </div>
    Label (`menu_label/2`): <div class="px-menu-label"> -- NO role
        (matches upstream: Menu.Label is a plain grouping heading, not
        part of the formal ARIA tree).
    Separator (`menu_separator/1`): delegates wholesale to
        `prolog/ui/separator.pl`'s `separator_root/2` -- see that
        template's own contract (`role="separator"`, `data-orientation
        ="horizontal"`); this module only merges in the additional
        `px-menu-separator` styling hook.
    Sub (`menu_sub/2`): <div class="px-menu-sub" data-state="open|closed">
        wrapping one SubTrigger + one SubContent -- a wrapper node
        upstream doesn't have (Sub is a React-context-only component
        there); needed here purely as the DOM anchor `lib/menu.js`
        scopes its per-submenu hover/keyboard wiring against, and to
        give Content's own `px-menu-content` scoping (above) a single
        parent to nest SubContent under.
    SubTrigger (`menu_sub_trigger/2`):
        <div role="menuitem" tabindex="-1" aria-haspopup="menu"
             aria-expanded="true|false" [aria-controls="..."]
             data-state="open|closed" [data-disabled=""]
             class="px-menu-item px-menu-sub-trigger">
    ItemIndicator (`menu_item_indicator/2`): <span aria-hidden="true"
        data-state="checked|unchecked" class="px-menu-item-indicator">
        -- **documented simplification** vs upstream's `Presence`-gated
        conditional mount (only in the DOM while checked, animating
        out): this port ALWAYS renders it (like `popover_arrow/1`'s
        always-present nub, not `checkbox_indicator/1`'s presence-gated
        one) and lets `assets/css/ui.css` hide it visually via
        `[data-state="unchecked"] { visibility: hidden }` -- simpler,
        deterministic for the css_coverage test (adr/0026 rule 7d), and
        with no animation lifecycle to gate in the first place (there
        is no JS-driven exit-animation machinery in this port at all,
        same "Presence" gap every other component here already accepts
        -- e.g. Tabs Content's own analysis-doc-noted `Presence` gate is
        similarly not reproduced).
    Arrow (`menu_arrow/1`): <div aria-hidden="true" class="px-menu-arrow">
        -- pure markup, CSS-positioned off the parent Content's own
        `[data-side]`, identical technique to `popover_arrow/1`/
        `tooltip_arrow/1`.

**Close-on-select default, a documented deviation (rule 2) worth
calling out explicitly.** The analysis doc's own text: "item selection
dispatches a cancelable custom event; unless prevented, closes the
entire menu tree (not just the current submenu level)" -- stated once,
with no distinction drawn between plain Items and Checkbox/Radio
Items. Upstream's actual source, however, builds CheckboxItem/RadioItem
on the same underlying Item primitive WITHOUT special-casing their
`onSelect` (selecting one bubbles the identical cancelable event a
plain Item's selection does) -- so upstream's literal DEFAULT is that
a Checkbox/Radio Item selection closes the menu exactly like a plain
Item does, and an application wanting a "stays open while you flip
settings" checkbox item must opt in with its own
`onSelect={e => e.preventDefault()}`. This port flips that default:
`menu_checkbox_item/2`/`menu_radio_item/2` do NOT close the menu on
selection unless the caller opts in with `close_on_select(true)`;
`menu_item/1,2` DOES close unless the caller opts out with
`close_on_select(false)`. Rationale: a settings-style toggle menu item
that closes the whole menu on every flip (forcing a reopen to flip a
second option) is poor, un-Radix-like UX that essentially every real
consumer of upstream Radix overrides anyway -- this port bakes the
override in as the more useful default rather than reproducing a
default nobody actually ships with. Either behaviour is fully under
the caller's control via `close_on_select(Bool)` on any Item variant;
`assets/js/lib/menu.js`'s header documents the exact resolution rule.

Options (plain lists, adr/0026 rule 1) -- see each predicate's own
`take_<name>/3` helper below for the precise default/coercion; the
list here is only the option NAMES:

  `menu_content/2`, `menu_sub_content/2`:
    id(Id), open(Bool), labelledby(Id), side(top|right|bottom|left),
    align(start|center|end), side_offset(N), align_offset(N),
    class(C), pass-through.
  `menu_item/1,2`:
    disabled(Bool), textvalue(Text), close_on_select(Bool), class(C),
    pass-through.
  `menu_checkbox_item/2`:
    checked(Bool), disabled(Bool), textvalue(Text),
    close_on_select(Bool), class(C), pass-through.
  `menu_radio_group/2`:
    aria_label(Text) (pass-through already handles this; named here
    only because it is the one option a caller will actually reach
    for), class(C), pass-through.
  `menu_radio_item/2`:
    checked(Bool), value(V), disabled(Bool), textvalue(Text),
    close_on_select(Bool), class(C), pass-through.
  `menu_label/2`:
    class(C), pass-through (typically `id(Id)` for a
    `menu_radio_group/2`'s `aria_labelledby` to point at).
  `menu_separator/1`:
    class(C), pass-through -- forwarded verbatim to
    `separator_root/2`.
  `menu_sub/2` Parts = `[TriggerChildren, ContentChildren]`:
    id(Id), open(Bool), disabled(Bool), class(C).
  `menu_sub_trigger/2`:
    open(Bool), controls(Id), disabled(Bool), class(C), pass-through.
  `menu_item_indicator/2`:
    state(checked|unchecked), class(C), pass-through.
  `menu_arrow/1`:
    class(C), pass-through.
*/

:- use_module(library(lists)).
:- use_module(library(gensym)).
:- use_module('../px_template').
:- use_module(separator).

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

		 /*******************************
		 *        OPTION HELPERS        *
		 *******************************/

valid_side(top).
valid_side(right).
valid_side(bottom).
valid_side(left).

valid_align(start).
valid_align(center).
valid_align(end).

%!  take_bool(+Name, +Default, +Opts0, -Value, -Rest) is det.
%
%   Same shape as dialog.pl's/tabs.pl's own take_bool/5.
take_bool(Name, Default, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Rest)
    ->  ( V0 == true -> Value = true ; Value = false )
    ;   Value = Default, Rest = Opts0
    ).

take_side(Opts0, Side, Default, Rest) :-
    (   selectchk(side(S0), Opts0, Rest)
    ->  ( valid_side(S0) -> Side = S0 ; Side = Default )
    ;   Side = Default, Rest = Opts0
    ).

take_align(Opts0, Align, Default, Rest) :-
    (   selectchk(align(A0), Opts0, Rest)
    ->  ( valid_align(A0) -> Align = A0 ; Align = Default )
    ;   Align = Default, Rest = Opts0
    ).

take_offset(Name, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Rest)
    ->  Value = V0
    ;   Value = 0, Rest = Opts0
    ).

take_id(Opts0, IdOpt, Rest) :-
    (   selectchk(id(Id), Opts0, Rest)
    ->  IdOpt = id(Id)
    ;   IdOpt = none, Rest = Opts0
    ).

take_labelledby(Opts0, LOpt, Rest) :-
    (   selectchk(labelledby(Id), Opts0, Rest)
    ->  LOpt = labelledby(Id)
    ;   LOpt = none, Rest = Opts0
    ).

take_controls(Opts0, COpt, Rest) :-
    (   selectchk(controls(Id), Opts0, Rest)
    ->  COpt = controls(Id)
    ;   COpt = none, Rest = Opts0
    ).

take_textvalue(Opts0, TOpt, Rest) :-
    (   selectchk(textvalue(T), Opts0, Rest)
    ->  TOpt = textvalue(T)
    ;   TOpt = none, Rest = Opts0
    ).

take_close_on_select(Opts0, COpt, Rest) :-
    (   selectchk(close_on_select(B0), Opts0, Rest)
    ->  ( B0 == true -> COpt = close_on_select(true) ; COpt = close_on_select(false) )
    ;   COpt = none, Rest = Opts0
    ).

take_value(Opts0, VOpt, Rest) :-
    (   selectchk(value(V), Opts0, Rest)
    ->  VOpt = value(V)
    ;   VOpt = none, Rest = Opts0
    ).

state_atom(true,  open)   :- !.
state_atom(false, closed).

checked_state(true,  checked)   :- !.
checked_state(false, unchecked).

merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

labelledby_attrs(labelledby(Id), [aria_labelledby(Id)]) :- !.
labelledby_attrs(none, []).

controls_attrs(controls(Id), [aria_controls(Id)]) :- !.
controls_attrs(none, []).

textvalue_attrs(textvalue(T), [data_text_value(T)]) :- !.
textvalue_attrs(none, []).

close_on_select_attrs(close_on_select(true),  [data_close_on_select(true)])  :- !.
close_on_select_attrs(close_on_select(false), [data_close_on_select(false)]) :- !.
close_on_select_attrs(none, []).

value_attrs(value(V), [data_value(V)]) :- !.
value_attrs(none, []).

disabled_attrs(true,  [data_disabled(""), aria_disabled(true)]) :- !.
disabled_attrs(false, []).

id_attrs(id(Id), [id(Id)]) :- !.
id_attrs(none, []).

		 /*******************************
		 *            CONTENT           *
		 *******************************/

%!  menu_content(+Opts, +Children) is det.
%
%   Bare-call template surface: `menu_content([id("m1"), open(true),
%   labelledby("trigger-id")], [...Items...])`. The root level of a
%   menu -- `side(bottom)`/`align(start)` default (Dropdown Menu's own
%   upstream default; a submenu's `menu_sub_content/2` defaults
%   `side(right)`/`align(start)` instead, see below).
px_template:render_helper(menu_content(Opts, Children), S) :-
    content_attrs(Opts, "px-menu-content", bottom, start, Attrs),
    px_template:render(S, div(Attrs, Children)).

%!  menu_sub_content(+Opts, +Children) is det.
%
%   Bare-call template surface: `menu_sub_content([id("sub1"),
%   open(false)], [...Items...])`. A nested level -- see the module
%   header's "Platform choice" for why this is a DOM descendant of its
%   `menu_sub/2` wrapper rather than a portal sibling, and why that
%   nesting is load-bearing, not incidental.
px_template:render_helper(menu_sub_content(Opts, Children), S) :-
    content_attrs(Opts, "px-menu-content px-menu-sub-content", right, start, Attrs),
    px_template:render(S, div(Attrs, Children)).

content_attrs(Opts0, DefaultClass, DefaultSide, DefaultAlign, Attrs) :-
    must_be(list, Opts0),
    take_bool(open, false, Opts0, Open, Opts1),
    take_id(Opts1, IdOpt, Opts2),
    take_labelledby(Opts2, LOpt, Opts3),
    take_side(Opts3, Side, DefaultSide, Opts4),
    take_align(Opts4, Align, DefaultAlign, Opts5),
    take_offset(side_offset, Opts5, SideOffset, Opts6),
    take_offset(align_offset, Opts6, AlignOffset, Opts7),
    merge_class(Opts7, DefaultClass, ClassVal, Opts8),
    state_atom(Open, State),
    id_attrs(IdOpt, IdAttrs),
    labelledby_attrs(LOpt, LAttrs),
    append([ [role(menu), tabindex(-1), popover(auto)],
             IdAttrs, LAttrs,
             [data_state(State), data_orientation(vertical),
              data_side(Side), data_align(Align),
              data_side_offset(SideOffset), data_align_offset(AlignOffset),
              class(ClassVal)
             ],
             Opts8
           ], Attrs).

		 /*******************************
		 *             ITEM             *
		 *******************************/

%!  menu_item(+Opts) is det.
%!  menu_item(+Opts, +Children) is det.
%
%   Bare-call template surface: `menu_item([disabled(true)], "Copy")`.
%   `menu_item/1` is the no-label shorthand (Children = ""), delegating
%   to `/2`, same `/1`-calls-`/2` shape as `popover_close/1,2`.
px_template:render_helper(menu_item(Opts), S) :-
    px_template:render_helper(menu_item(Opts, ""), S).
px_template:render_helper(menu_item(Opts, Children), S) :-
    item_attrs(Opts, "px-menu-item", Attrs),
    px_template:render(S, div(Attrs, Children)).

item_attrs(Opts0, DefaultClass, Attrs) :-
    must_be(list, Opts0),
    take_bool(disabled, false, Opts0, Disabled, Opts1),
    take_textvalue(Opts1, TOpt, Opts2),
    take_close_on_select(Opts2, COpt, Opts3),
    merge_class(Opts3, DefaultClass, ClassVal, Opts4),
    disabled_attrs(Disabled, DisabledAttrs),
    textvalue_attrs(TOpt, TAttrs),
    close_on_select_attrs(COpt, CAttrs),
    append([ [role(menuitem), tabindex(-1)],
             DisabledAttrs, TAttrs, CAttrs,
             [class(ClassVal)],
             Opts4
           ], Attrs).

		 /*******************************
		 *         CHECKBOX ITEM        *
		 *******************************/

%!  menu_checkbox_item(+Opts, +Children) is det.
%
%   Bare-call template surface: `menu_checkbox_item([checked(true)],
%   "Show hidden files")`. `close_on_select(_)` default `false` -- see
%   the module header's "Close-on-select default" section.
px_template:render_helper(menu_checkbox_item(Opts, Children), S) :-
    must_be(list, Opts),
    take_bool(checked, false, Opts, Checked, Opts1),
    take_bool(disabled, false, Opts1, Disabled, Opts2),
    take_textvalue(Opts2, TOpt, Opts3),
    take_close_on_select(Opts3, COpt0, Opts4),
    ( COpt0 == none -> COpt = close_on_select(false) ; COpt = COpt0 ),
    merge_class(Opts4, "px-menu-item px-menu-checkbox-item", ClassVal, Opts5),
    checked_state(Checked, State),
    disabled_attrs(Disabled, DisabledAttrs),
    textvalue_attrs(TOpt, TAttrs),
    close_on_select_attrs(COpt, CAttrs),
    append([ [role(menuitemcheckbox), tabindex(-1), aria_checked(Checked)],
             DisabledAttrs, TAttrs, CAttrs,
             [data_state(State), class(ClassVal)],
             Opts5
           ], Attrs),
    px_template:render(S,
        div(Attrs,
          [ menu_item_indicator([state(State)], "✓"),
            Children
          ])).

		 /*******************************
		 *          RADIO GROUP          *
		 *******************************/

%!  menu_radio_group(+Opts, +Children) is det.
%
%   Bare-call template surface: `menu_radio_group([aria_label("Zoom
%   level")], [...RadioItems...])`. `role="group"` -- upstream's own
%   RadioGroup anatomy part; no other computed contract beyond the
%   default styling class.
px_template:render_helper(menu_radio_group(Opts, Children), S) :-
    must_be(list, Opts),
    merge_class(Opts, "px-menu-radio-group", ClassVal, Opts1),
    append([ [role(group), class(ClassVal)], Opts1 ], Attrs),
    px_template:render(S, div(Attrs, Children)).

%!  menu_radio_item(+Opts, +Children) is det.
%
%   Bare-call template surface: `menu_radio_item([checked(true),
%   value("100")], "100%")`. `close_on_select(_)` default `false` --
%   same rationale as `menu_checkbox_item/2`.
px_template:render_helper(menu_radio_item(Opts, Children), S) :-
    must_be(list, Opts),
    take_bool(checked, false, Opts, Checked, Opts1),
    take_bool(disabled, false, Opts1, Disabled, Opts2),
    take_value(Opts2, VOpt, Opts3),
    take_textvalue(Opts3, TOpt, Opts4),
    take_close_on_select(Opts4, COpt0, Opts5),
    ( COpt0 == none -> COpt = close_on_select(false) ; COpt = COpt0 ),
    merge_class(Opts5, "px-menu-item px-menu-radio-item", ClassVal, Opts6),
    checked_state(Checked, State),
    disabled_attrs(Disabled, DisabledAttrs),
    value_attrs(VOpt, VAttrs),
    textvalue_attrs(TOpt, TAttrs),
    close_on_select_attrs(COpt, CAttrs),
    append([ [role(menuitemradio), tabindex(-1), aria_checked(Checked)],
             DisabledAttrs, VAttrs, TAttrs, CAttrs,
             [data_state(State), class(ClassVal)],
             Opts6
           ], Attrs),
    px_template:render(S,
        div(Attrs,
          [ menu_item_indicator([state(State)], "●"),
            Children
          ])).

		 /*******************************
		 *             LABEL            *
		 *******************************/

%!  menu_label(+Opts, +Children) is det.
%
%   Bare-call template surface: `menu_label([], "Appearance")`. No
%   `role` -- matches upstream: a plain grouping heading, not part of
%   the formal ARIA tree.
px_template:render_helper(menu_label(Opts, Children), S) :-
    must_be(list, Opts),
    merge_class(Opts, "px-menu-label", ClassVal, Opts1),
    append([ [class(ClassVal)], Opts1 ], Attrs),
    px_template:render(S, div(Attrs, Children)).

		 /*******************************
		 *           SEPARATOR          *
		 *******************************/

%!  menu_separator(+Opts) is det.
%
%   Bare-call template surface: `menu_separator([])`. Delegates
%   wholesale to `prolog/ui/separator.pl`'s `separator_root/2` -- see
%   the module header's contract note. `orientation(_)`/`decorative(_)`
%   pass straight through to `separator_root/2` if the caller supplies
%   them (a horizontal Menu Separator never needs either -- both left
%   at `separator_root/2`'s own defaults, which already produce exactly
%   upstream's `role="separator"` no-`aria-orientation` contract).
px_template:render_helper(menu_separator(Opts), S) :-
    must_be(list, Opts),
    (   selectchk(class(C), Opts, Opts1)
    ->  format(string(ClassVal), "px-menu-separator ~w", [C])
    ;   ClassVal = "px-menu-separator", Opts1 = Opts
    ),
    px_template:render(S, separator_root([class(ClassVal)|Opts1], [])).

		 /*******************************
		 *              SUB             *
		 *******************************/

%!  menu_sub(+Opts, +Parts) is det.
%
%   Parts = [TriggerChildren, ContentChildren]. The common case: a
%   `.px-menu-sub` wrapper (see the module header for why this wrapper
%   node exists) around one SubTrigger + one SubContent, `open(_)`
%   threaded to both, SubTrigger's `aria-controls` wired to SubContent's
%   `id` automatically -- same division of labour as `popover/2`.
menu_sub(Opts, Parts) ~> \menu_sub_render(Opts, Parts).

px_template:render_helper(menu_sub_render(Opts, [TriggerKids, ContentKids]), S) :-
    must_be(list, Opts),
    take_bool(open, false, Opts, Open, _),
    take_bool(disabled, false, Opts, Disabled, _),
    sub_content_id(Opts, ContentId),
    exclude(sub_convenience_only_opt, Opts, WrapperOpts0),
    merge_class(WrapperOpts0, "px-menu-sub", WrapperClass, WrapperOpts1),
    state_atom(Open, State),
    TriggerOpts = [open(Open), disabled(Disabled), controls(ContentId)],
    ContentOpts = [open(Open), id(ContentId)],
    append([ [data_state(State), class(WrapperClass)], WrapperOpts1 ], WrapperAttrs),
    px_template:render(S,
        div(WrapperAttrs,
          [ menu_sub_trigger(TriggerOpts, TriggerKids),
            menu_sub_content(ContentOpts, ContentKids)
          ])).

sub_convenience_only_opt(open(_)).
sub_convenience_only_opt(disabled(_)).
sub_convenience_only_opt(id(_)).

sub_content_id(Opts, ContentId) :-
    (   memberchk(id(Base), Opts)
    ->  true
    ;   gensym(px_menu_sub_, Base)
    ),
    format(atom(ContentId), '~w-content', [Base]).

%!  menu_sub_trigger(+Opts, +Children) is det.
%
%   Bare-call template surface: `menu_sub_trigger([open(false),
%   controls("sub1-content")], "More Tools")`. Not the top-level
%   `Trigger` -- a menuitem-that-opens-a-submenu, hence `role="menuitem"`
%   (not `"button"`) plus `aria-haspopup="menu"`, matching the analysis
%   doc's own contrast with Dropdown Menu's real `<button>` trigger.
px_template:render_helper(menu_sub_trigger(Opts, Children), S) :-
    must_be(list, Opts),
    take_bool(open, false, Opts, Open, Opts1),
    take_bool(disabled, false, Opts1, Disabled, Opts2),
    take_controls(Opts2, COpt, Opts3),
    merge_class(Opts3, "px-menu-item px-menu-sub-trigger", ClassVal, Opts4),
    state_atom(Open, State),
    disabled_attrs(Disabled, DisabledAttrs),
    controls_attrs(COpt, ControlsAttrs),
    append([ [role(menuitem), tabindex(-1), aria_haspopup(menu), aria_expanded(Open)],
             ControlsAttrs, DisabledAttrs,
             [data_state(State), class(ClassVal)],
             Opts4
           ], Attrs),
    px_template:render(S, div(Attrs, Children)).

		 /*******************************
		 *            INDICATOR         *
		 *******************************/

%!  menu_item_indicator(+Opts, +Children) is det.
%
%   Bare-call template surface: `menu_item_indicator([state(checked)],
%   "✓")`. See the module header's "documented simplification" --
%   always rendered, never `Presence`-gated; `assets/css/ui.css` hides
%   it visually when `data-state="unchecked"`.
px_template:render_helper(menu_item_indicator(Opts, Children), S) :-
    must_be(list, Opts),
    (   selectchk(state(St0), Opts, Opts1)
    ->  ( (St0 == checked ; St0 == unchecked) -> St = St0 ; St = unchecked )
    ;   St = unchecked, Opts1 = Opts
    ),
    merge_class(Opts1, "px-menu-item-indicator", ClassVal, Opts2),
    append([ [aria_hidden(true), data_state(St), class(ClassVal)], Opts2 ], Attrs),
    px_template:render(S, span(Attrs, Children)).

		 /*******************************
		 *             ARROW            *
		 *******************************/

%!  menu_arrow(+Opts) is det.
%
%   Bare-call template surface: `menu_arrow([])`. Pure markup, same
%   "plain div, CSS rotate" choice as `popover_arrow/1`/`tooltip_arrow/1`.
px_template:render_helper(menu_arrow(Opts), S) :-
    must_be(list, Opts),
    merge_class(Opts, "px-menu-arrow", ClassVal, Opts1),
    append([ [aria_hidden(true), class(ClassVal)], Opts1 ], Attrs),
    px_template:render(S, div(Attrs, [])).
