:- module(ui_select, []).

%   No predicates are exported: select_root/2, select_value/2,
%   select_icon/1,2, select_content/2 (rendered inline by
%   select_root/2, not separately callable -- see below), select_item/1,2,
%   select_item_text/2, select_item_indicator/2, select_group/2,
%   select_label/2, select_separator/1 are never called module-qualified
%   -- bare-call dispatch through px_template's tmpl/2 / render_helper/2
%   tables (adr/0019) resolves them, the same pattern every other
%   prolog/ui/*.pl module uses.

/** <module> Select (adr/0026): the port's finale (33/33) -- WAI-ARIA
listbox-pattern replacement for native `<select>`, composing nearly
everything built before it: `lib/popper.js` (positioning, its third
consumer after Popover/Tooltip/HoverCard/Menu), the roving-highlight-
is-focus/typeahead IDEAS `lib/menu.js` established (but NOT that
module itself -- see "Why not lib/menu.js" below), and native `<form>`
participation via a real hidden-after-upgrade `<select>` (the
technique docs/radix-port-analysis.md's own "Select" entry flags as
"directly reusable, framework-agnostic... the port's answer to form
participation", ported here as the SERVER-rendered fallback itself,
not a JS-remounted afterthought -- see "No-JS fallback" below).

Ported from Radix UI's Select primitive (docs/radix-port-analysis.md,
"Select" entry -- "the single hardest primitive in the library").
Anatomy (this module's public template surface): `Root` (`select_root/2`,
doubles as the top-level entry point -- see "Naming" below), `Trigger`
(rendered inline by `select_root/2`, not a separately callable part --
see "Why Trigger/Content aren't standalone templates"), `Value`
(`select_value/2`), `Icon` (`select_icon/1,2`), `Content` (rendered
inline, see below), `Item` (`select_item/1,2`), `ItemText`
(`select_item_text/2`), `ItemIndicator` (`select_item_indicator/2`),
`Group` (`select_group/2`), `Label` (`select_label/2`), `Separator`
(`select_separator/1`).

**Anatomy omissions (contract deviations, noted per adr/0026 rule 2):**
no `Portal` (same rationale as popover.pl/`_menu.pl`: native `popover`
top-layer already escapes any ancestor stacking context server-side,
no abstraction needed); no `Arrow` (Radix's own Select Content rarely
ships one either -- popper's `position/3` result is available to a
future consumer that wants it, same "not every popper consumer needs
Arrow" precedent `_menu.pl`'s Content already sets); no `ScrollUpButton`/
`ScrollDownButton` -- **documented deferral**: this port's Content has
no max-height/overflow clamp, so it never scrolls and there is nothing
for a scroll button to do; a future consumer with a very long option
list gets a plain overflowing panel today, not a broken one, but not
Radix's "shrink to viewport + auto-scroll buttons" behaviour either.
No `Anchor` (Trigger doubles as the anchor point, same choice
popover.pl makes).

**Naming (deviation from adr/0026 rule 1, same shadowing prolog/ui/
label.pl's and prolog/ui/form.pl's headers document):** `select` is
itself a whitelisted HTML5 element functor (prolog/px_template.pl's
`html_element/1`), so a top-level convenience template literally named
`select/2` is impossible -- `select_root/2` IS what a caller reaches
for.

**Why Trigger/Content aren't standalone templates.** Every other
ported component with a Trigger+Content pair (Popover, Dropdown Menu)
exposes `<component>_trigger/2` and `<component>_content/2` as
independently callable parts, because their Trigger's `aria-controls`/
`popovertarget` and Content's `id` are the ONLY cross-part wiring
needed. Select's Trigger additionally needs the CURRENT SELECTION'S
LABEL (for `select_value`'s text and `data-placeholder`) and Content
needs the SAME item list rendered twice -- once flattened into the
native `<select>`'s `<option>`/`<optgroup>` tree (see "No-JS fallback"
below), once as the rich custom listbox -- both derived from ONE
`Items` list `select_root/2` receives. Splitting Trigger/Content into
separately-callable parts would force every caller to duplicate that
derivation by hand (compute the selected label, flatten the native
options) for no benefit, since a Select without its own item list
first isn't a meaningful thing to render standalone the way an empty
Popover Content is. `select_root/2` is therefore the ONE entry point;
`select_value/2`, `select_icon/1,2`, `select_item/1,2`,
`select_item_text/2`, `select_item_indicator/2`, `select_group/2`,
`select_label/2`, `select_separator/1` remain independently callable
(and are what `select_root/2` itself calls internally) for a caller
composing custom trigger/content markup by hand -- but the id-wiring
and native-`<select>`-derivation stay `select_root/2`-only.

**No-JS fallback (adr/0026 rule 4, and this task's key decision):
`select_root/2` renders a REAL, fully-functional native `<select>`
first** -- every declared `select_item` becomes a real `<option>`
(grouped into `<optgroup>` for a `select_group`), `name(N)` makes it
form-submittable, `required(_)`/`disabled(_)` are real native
attributes, and a synthesized leading `<option value="" disabled
hidden [selected]>Placeholder</option>` represents "nothing chosen yet"
so `required` validation and the placeholder concept both work with
ZERO JS, exactly like any hand-written `<select>` with a prompt
option. This is the WHOLE experience without JS: the custom
trigger+listbox markup is also present in the initial HTML (rendered
from the SAME `Items` list, guaranteeing the two can never drift out
of sync with each other) but is kept invisible by `assets/css/ui.css`
until upgraded (`px-select:defined .px-select-trigger { display: ...
}` -- see that section's own header for why `:defined` was chosen over
a JS-set marker attribute: it needs no JS to flip, matching rule 3's
"platform first" the furthest this port can push it). **`<px-select>`
(`assets/js/components/select.js`) upgrades it**: on connect, it
visually hides the native `<select>` (a clip-rect technique, same
shape as `visually_hidden.pl`'s CSS, plus `tabindex="-1"` so it drops
out of the tab order -- the custom Trigger takes over as the focusable
control) while KEEPING it in the DOM as the form-submitted value store,
and enables the custom trigger+listbox interaction. Every selection
made through the custom UI is synced onto the native `<select>`'s
`value` via its own property-setter descriptor (bypassing any
overridden instance property) followed by a real, bubbling `change`
event -- the exact technique docs/radix-port-analysis.md's own header
flags as `SelectBubbleInput`'s "directly reusable, framework-agnostic"
core, applied here to the fallback element itself rather than a
separate hidden shadow input. This is the CDP-verifiable form-
participation proof this port ships with: selecting an item through
the custom listbox changes `document.querySelector('select').value`,
because that native element never stopped being the real form control.

**Positioning (task decision 2): Radix's `position="popper"` mode
ONLY** -- `side="bottom"` always (no `top`/`left`/`right`, no flip
target beyond the one `lib/popper.js` itself computes if `bottom`
overflows), Content's width pinned to the Trigger's own width via a
CSS custom property (`--px-select-trigger-width`, written by
`assets/js/components/select.js` on every position pass, read by
`.px-select-content { width: var(--px-select-trigger-width) }`) --
matching upstream's own popper-mode "full trigger width" behaviour.
Radix's OTHER mode, `position="item-aligned"` (macOS-style: the panel
overlaps the trigger so the SELECTED item lands exactly under the
pointer, with per-item pixel math), is a **documented deferral** -- no
`position(_)` option exists on any part here; a future consumer
wanting it is a separate, additive port, not a breaking change to this
one.

**`aria-selected` simplification (documented deviation, rule 2):**
docs/radix-port-analysis.md's own text: Item's `aria-selected` is
"deliberately coupled to focus, not just selection... fixes VoiceOver
stuttering" -- upstream computes `isSelected && isFocused` continuously
client-side. This port's SERVER-rendered `aria-selected` reflects
PLAIN selection truth only (the `selected(Bool)` opt on `select_item/2`)
-- there is no DOM focus at render time to couple it to.
`assets/js/components/select.js` refines this to the real
`isSelected && isHighlighted` (== focused) rule the moment the listbox
opens and highlight starts moving, per that file's own header.

DOM/ARIA contract emitted (per this task's brief, adr/0026 rule 2):

    Trigger (`<button>`):  aria-haspopup="listbox", aria-expanded,
              aria-controls (Content's id), data-state, data-placeholder
              (present only when nothing is selected), [disabled +
              data-disabled].
    Value (`<span>`):      data-placeholder (mirrors Trigger's).
    Icon (`<span>`):       aria-hidden="true".
    Content (`<div>`):     role="listbox", native popover="auto",
              tabindex="-1", data-state, data-side="bottom",
              aria-labelledby (Trigger's id).
    Item (`<div>`):        role="option", aria-selected, data-state
              (checked|unchecked), data-value, data-text-value,
              [data-disabled + aria-disabled], tabindex="-1".
              `data-highlighted` is NEVER server-rendered -- mirrors
              live DOM focus, assets/js/components/select.js's job
              entirely (same convention as `_menu.pl`'s own Item).
    ItemIndicator (`<span>`): aria-hidden="true", data-state -- always
              rendered (never Presence-gated), same "documented
              simplification" `_menu.pl`'s own ItemIndicator makes;
              `assets/css/ui.css` hides it visually when unchecked.
    Group (`<div>`):       role="group", aria-labelledby (wired
              automatically to a leading `select_label/2` child's id,
              same technique `_menu.pl`'s RadioGroup could use but
              doesn't need -- Select's Group genuinely nests a Label
              part, upstream's RadioGroup does not).
    Label (`<div>`):       no role (plain grouping heading, matches
              upstream and `_menu.pl`'s own Label).
    Separator:              delegates wholesale to
              `prolog/ui/separator.pl`'s `separator_root/2`, same
              technique `_menu.pl`'s `menu_separator/1` uses.

Options (plain lists, adr/0026 rule 1):

  `select_root/2` Opts:
    name(N)         native `<select>`'s `name` -- omitted (no name
                    attribute, not form-submitted) if absent.
    placeholder(Text)  default "Select an option…". Shown by both the
                    native `<select>`'s synthesized prompt option and
                    the custom Trigger's Value whenever no item in
                    Items carries `selected(true)`.
    disabled(Bool)  default `false`. Native `<select disabled>` PLUS
                    the custom Trigger's own `disabled`/`data-disabled`.
    required(Bool)  default `false`. Native `<select required>` only
                    (no ARIA mirror on Trigger -- native constraint
                    validation is this port's answer, same
                    `px_form.pl`-adjacent philosophy prolog/ui/form.pl's
                    header documents).
    open(Bool)      default `false`. Initial `data-state` of Content
                    (and Trigger) -- same documented gap popover.pl's
                    own `open(true)` has: without JS reconciling it on
                    connect, a native `popover` element never starts
                    visibly open (no static HTML attribute for that).
    id(Id)          base id every generated part's id is built from
                    (`<Id>-native`/`-trigger`/`-content`); gensym'd
                    (`px-select-N`) when absent, and (same convention
                    as `tabs.pl`'s `tabs_render/2`) also carries onto
                    the outer `<px-select>` wrapper's own `<div>`.
    class(C)        merged with the default class, default first
                    ("px-select C").
    anything else   passed through onto the outer wrapper `<div>`.

  `select_root/2` second argument, `Items`: a list of `select_item/1,2`,
  `select_group/2`, `select_separator/1` terms, in display order --
  exactly ONE of which should carry `selected(true)` (unmarked means
  "nothing selected", the placeholder state).

  `select_item/1,2` Opts:
    value(V)        REQUIRED -- the native `<option>`'s `value` AND
                    this Item's `data-value`.
    selected(Bool)  default `false`. Drives `aria-selected`,
                    `data-state` (checked|unchecked), and the matching
                    native `<option selected>`.
    disabled(Bool)  default `false`.
    textvalue(T)    the plain-text label used for the native
                    `<option>`'s own text AND this Item's
                    `data-text-value` (typeahead). REQUIRED when
                    Children is not itself plain text (an atom/string/
                    number) -- rich Item content (an icon plus a
                    label, say) has no other way to derive a single
                    plain-text label; omitting it in that case is a
                    load ERROR, not a silent fallback, so a caller
                    never ships a Select whose native fallback or
                    typeahead is silently text-less.
    id(Id)          gensym'd (`px-select-item-N`) when absent.
    class(C), anything else  pass-through, as usual.
    `select_item/1` is the no-label shorthand (Children = ""),
    delegating to `/2` (same shape as `_menu.pl`'s `menu_item/1,2`).

  `select_group/2` Opts: `class(C)`, pass-through. Children: normally
    one `select_label/2` FIRST, followed by any number of
    `select_item/1,2` -- the leading Label (if present) is
    auto-`id`'d (gensym'd unless it already carries one) and wired as
    the Group's own `aria-labelledby`; a Group with no leading Label
    renders with no `aria-labelledby` at all.

  `select_label/2` Opts: `id(Id)` (normally injected by the enclosing
    `select_group/2`), `class(C)`, pass-through.

  `select_separator/1` Opts: `class(C)`, pass-through -- forwarded
    verbatim to `separator_root/2`. Contributes NOTHING to the native
    `<select>` (no visual separator concept there); purely a custom-UI
    divider.

  `select_value/2` Opts: `placeholder(Bool)` default `false` (drives
    `data-placeholder`), `class(C)`, pass-through. Normally rendered
    by `select_root/2` itself with the correct value precomputed;
    directly callable for a caller hand-composing a custom Trigger.

  `select_icon/1,2` Opts: `class(C)`, pass-through. `/1` is the
    default-glyph shorthand (Children = "▾", the same chevron
    `_menu.pl`'s SubTrigger's CSS `::after` glyph shape draws, here as
    real markup since Icon is upstream's own anatomy part).

  `select_item_text/2` Opts: `class(C)`, pass-through.
  `select_item_indicator/2` Opts: `state(checked|unchecked)` default
    `unchecked`, `class(C)`, pass-through.
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

take_bool(Name, Default, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Rest)
    ->  ( V0 == true -> Value = true ; Value = false )
    ;   Value = Default, Rest = Opts0
    ).

take_id(Opts0, Id, Rest) :-
    (   selectchk(id(Id0), Opts0, Rest)
    ->  Id = Id0
    ;   gensym(px_select_, Id), Rest = Opts0
    ).

take_name(Opts0, NameOpt, Rest) :-
    (   selectchk(name(N), Opts0, Rest)
    ->  NameOpt = name(N)
    ;   NameOpt = none, Rest = Opts0
    ).

take_textvalue(Opts0, TOpt, Rest) :-
    (   selectchk(textvalue(T), Opts0, Rest)
    ->  TOpt = textvalue(T)
    ;   TOpt = none, Rest = Opts0
    ).

merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

state_atom(true,  open)   :- !.
state_atom(false, closed).

checked_state(true,  checked)   :- !.
checked_state(false, unchecked).

%!  text_of(+Term, -String) is det.
%
%   Plain text coercion for a native `<option>`'s text / an Item's
%   `data-text-value` -- atoms/strings/numbers only. Anything else
%   throws (module header's "load ERROR, not a silent fallback").
text_of(V, S) :- string(V), !, S = V.
text_of(V, S) :- atom(V), !, atom_string(V, S).
text_of(V, S) :- number(V), !, number_string(V, S).
text_of(V, _) :-
    throw(error(type_error(px_select_plain_text, V),
                context(_, 'plain atom/string/number, or supply textvalue(_) explicitly'))).

%!  resolve_text_value(+TOpt, +Children, -Text) is det.
resolve_text_value(textvalue(T), _, Text) :- !, text_of(T, Text).
resolve_text_value(none, Children, Text) :- text_of(Children, Text).

		 /*******************************
		 *   NATIVE <select> DERIVATION *
		 *******************************/

%!  collect_native(+Items, -Elements, -SelectedText) is det.
%
%   Walks Items once, producing the native `<select>`'s own children
%   (a flat list of `option(...)`/`optgroup(...)` element terms,
%   `select_separator/1` contributing nothing -- module header) plus
%   SelectedText = some(Text) for the first Item found with
%   `selected(true)`, or `none`.
collect_native(Items, Elements, SelectedText) :-
    collect_native_(Items, Elements, none, SelectedText).

collect_native_([], [], Sel, Sel).
collect_native_([select_item(IOpts, IC)|T], [OptElem|Elems], SelIn, SelOut) :-
    !,
    native_option(IOpts, IC, OptElem, ThisSel),
    ( ThisSel = some(_) -> SelMid = ThisSel ; SelMid = SelIn ),
    collect_native_(T, Elems, SelMid, SelOut).
collect_native_([select_item(IOpts)|T], Elems, SelIn, SelOut) :-
    !,
    collect_native_([select_item(IOpts, "")|T], Elems, SelIn, SelOut).
collect_native_([select_group(_, GChildren)|T], [OptGroupElem|Elems], SelIn, SelOut) :-
    !,
    group_label_and_items(GChildren, LabelText, ItemsOnly),
    collect_native_(ItemsOnly, InnerElems, SelIn, SelMid),
    % `optgroup` is not in px_template's HTML5 element whitelist (only
    % `select`/`option` are -- prolog/px_template.pl's `normal_element/1`);
    % native_optgroup/2, below, is a render_helper/2-dispatched bare call
    % that reaches for `render_tag/4` (the same "literal tag NOT on the
    % whitelist" escape hatch `_menu.pl`'s px-prefixed wrapper elements
    % use) instead.
    OptGroupElem = native_optgroup(LabelText, InnerElems),
    collect_native_(T, Elems, SelMid, SelOut).
collect_native_([select_separator(_)|T], Elems, SelIn, SelOut) :-
    !,
    collect_native_(T, Elems, SelIn, SelOut).
collect_native_([Other|_], _, _, _) :-
    throw(error(domain_error(px_select_item, Other),
                context(select_root/2,
                        'items: select_item/1,2, select_group/2, select_separator/1'))).

native_option(IOpts0, IC, option(Attrs, Text), Sel) :-
    (   selectchk(value(V), IOpts0, IOpts1)
    ->  true
    ;   throw(error(existence_error(option, value),
                    context(select_item/2, 'value(V) is required')))
    ),
    take_bool(selected, false, IOpts1, Selected, IOpts2),
    take_bool(disabled, false, IOpts2, Disabled, IOpts3),
    take_textvalue(IOpts3, TOpt, _),
    resolve_text_value(TOpt, IC, Text),
    ( Selected == true -> SelAttrs = [selected], Sel = some(Text) ; SelAttrs = [], Sel = none ),
    ( Disabled == true -> DisAttrs = [disabled] ; DisAttrs = [] ),
    append([[value(V)], SelAttrs, DisAttrs], Attrs).

group_label_and_items([select_label(_, LC)|Rest], LabelText, Rest) :- !, text_of(LC, LabelText).
group_label_and_items(Items, "", Items).

%!  native_optgroup(+LabelText, +Items) is det.
%
%   The `<optgroup>` escape hatch -- see `collect_native_/4`'s own
%   comment for why this can't just be an `optgroup(...)` element term.
px_template:render_helper(native_optgroup(LabelText, Items), S) :-
    px_template:render_tag(S, optgroup, [label(LabelText)], Items).

		 /*******************************
		 *             ROOT             *
		 *******************************/

%!  select_root(+Opts, +Items) is det.
%
%   Bare-call template surface: `select_root([name(fruit),
%   placeholder("Select a fruit…")], [select_item([value(apple)],
%   "Apple"), ...])`. The one entry point (module header, "Naming").
px_template:render_helper(select_root(Opts0, Items), S) :-
    must_be(list, Opts0),
    take_name(Opts0, NameOpt, Opts1),
    (   selectchk(placeholder(P0), Opts1, Opts2)
    ->  text_of(P0, Placeholder)
    ;   Placeholder = "Select an option…", Opts2 = Opts1
    ),
    take_bool(disabled, false, Opts2, Disabled, Opts3),
    take_bool(required, false, Opts3, Required, Opts4),
    take_bool(open, false, Opts4, Open, Opts5),
    take_id(Opts5, Base, Opts6),
    merge_class(Opts6, "px-select", ClassVal, Opts7),

    format(atom(NativeId), '~w-native', [Base]),
    format(atom(TriggerId), '~w-trigger', [Base]),
    format(atom(ContentId), '~w-content', [Base]),

    collect_native(Items, NativeItemElems, SelectedText),
    (   SelectedText = some(Text)
    ->  HasSelected = true, ValueLabel = Text
    ;   HasSelected = false, ValueLabel = Placeholder
    ),
    ( HasSelected == true -> PlaceholderSelAttrs = [] ; PlaceholderSelAttrs = [selected] ),
    PlaceholderOpt = option([value(''), disabled, hidden|PlaceholderSelAttrs], Placeholder),

    ( NameOpt = name(N) -> NameAttrs = [name(N)] ; NameAttrs = [] ),
    ( Disabled == true -> NativeDisabledAttrs = [disabled] ; NativeDisabledAttrs = [] ),
    ( Required == true -> NativeRequiredAttrs = [required] ; NativeRequiredAttrs = [] ),
    append([ [id(NativeId), class("px-select-native")],
             NameAttrs, NativeDisabledAttrs, NativeRequiredAttrs
           ], NativeAttrs),
    NativeSelectElem = select(NativeAttrs, [PlaceholderOpt|NativeItemElems]),

    state_atom(Open, State),
    ( HasSelected == true -> ValuePlaceholderFlag = false ; ValuePlaceholderFlag = true ),
    ( ValuePlaceholderFlag == true -> TriggerPlaceholderAttrs = [data_placeholder("")] ; TriggerPlaceholderAttrs = [] ),
    ( Disabled == true -> TriggerDisabledAttrs = [disabled, data_disabled("")] ; TriggerDisabledAttrs = [] ),
    append([ [type(button), id(TriggerId), aria_haspopup(listbox),
              aria_controls(ContentId), aria_expanded(Open)],
             TriggerPlaceholderAttrs, TriggerDisabledAttrs,
             [data_state(State), class("px-select-trigger")]
           ], TriggerAttrs),
    TriggerElem = button(TriggerAttrs,
        [ select_value([placeholder(ValuePlaceholderFlag)], ValueLabel),
          select_icon([])
        ]),

    ContentAttrs = [ role(listbox), id(ContentId), popover(auto), tabindex(-1),
                     data_state(State), data_side(bottom), aria_labelledby(TriggerId),
                     class("px-select-content")
                   ],
    ContentElem = div(ContentAttrs, Items),

    append([[id(Base), class(ClassVal)], Opts7], WrapperAttrs),
    px_template:render_tag(S, px_select, [],
        [div(WrapperAttrs, [NativeSelectElem, TriggerElem, ContentElem])]).

		 /*******************************
		 *             VALUE            *
		 *******************************/

%!  select_value(+Opts, +Children) is det.
px_template:render_helper(select_value(Opts0, Children), S) :-
    must_be(list, Opts0),
    take_bool(placeholder, false, Opts0, Placeholder, Opts1),
    merge_class(Opts1, "px-select-value", ClassVal, Opts2),
    ( Placeholder == true -> PAttrs = [data_placeholder("")] ; PAttrs = [] ),
    append([PAttrs, [class(ClassVal)], Opts2], Attrs),
    px_template:render(S, span(Attrs, Children)).

		 /*******************************
		 *             ICON             *
		 *******************************/

%!  select_icon(+Opts) is det.
%!  select_icon(+Opts, +Children) is det.
px_template:render_helper(select_icon(Opts), S) :-
    px_template:render_helper(select_icon(Opts, "▾"), S).
px_template:render_helper(select_icon(Opts0, Children), S) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-select-icon", ClassVal, Opts1),
    append([[aria_hidden(true), class(ClassVal)], Opts1], Attrs),
    px_template:render(S, span(Attrs, Children)).

		 /*******************************
		 *             ITEM             *
		 *******************************/

%!  select_item(+Opts) is det.
%!  select_item(+Opts, +Children) is det.
px_template:render_helper(select_item(Opts), S) :-
    px_template:render_helper(select_item(Opts, ""), S).
px_template:render_helper(select_item(Opts0, Children), S) :-
    must_be(list, Opts0),
    (   selectchk(value(V), Opts0, Opts1)
    ->  true
    ;   throw(error(existence_error(option, value),
                    context(select_item/2, 'value(V) is required')))
    ),
    take_bool(selected, false, Opts1, Selected, Opts2),
    take_bool(disabled, false, Opts2, Disabled, Opts3),
    take_textvalue(Opts3, TOpt, Opts4),
    (   selectchk(id(Id), Opts4, Opts5)
    ->  true
    ;   gensym(px_select_item_, Id), Opts5 = Opts4
    ),
    merge_class(Opts5, "px-select-item", ClassVal, Opts6),
    checked_state(Selected, State),
    resolve_text_value(TOpt, Children, TextValue),
    ( Disabled == true -> DisAttrs = [data_disabled(""), aria_disabled(true)] ; DisAttrs = [] ),
    append([ [id(Id), role(option), tabindex(-1), aria_selected(Selected)],
             DisAttrs,
             [data_state(State), data_value(V), data_text_value(TextValue), class(ClassVal)],
             Opts6
           ], Attrs),
    px_template:render(S,
        div(Attrs,
          [ select_item_indicator([state(State)], "✓"),
            select_item_text([], Children)
          ])).

%!  select_item_text(+Opts, +Children) is det.
px_template:render_helper(select_item_text(Opts0, Children), S) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-select-item-text", ClassVal, Opts1),
    append([[class(ClassVal)], Opts1], Attrs),
    px_template:render(S, span(Attrs, Children)).

%!  select_item_indicator(+Opts, +Children) is det.
px_template:render_helper(select_item_indicator(Opts0, Children), S) :-
    must_be(list, Opts0),
    (   selectchk(state(St0), Opts0, Opts1)
    ->  ( (St0 == checked ; St0 == unchecked) -> St = St0 ; St = unchecked )
    ;   St = unchecked, Opts1 = Opts0
    ),
    merge_class(Opts1, "px-select-item-indicator", ClassVal, Opts2),
    append([[aria_hidden(true), data_state(St), class(ClassVal)], Opts2], Attrs),
    px_template:render(S, span(Attrs, Children)).

		 /*******************************
		 *             GROUP             *
		 *******************************/

%!  select_group(+Opts, +Children) is det.
px_template:render_helper(select_group(Opts0, Children0), S) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-select-group", ClassVal, Opts1),
    (   wire_group_label(Children0, LabelId, Children1)
    ->  LAttrs = [aria_labelledby(LabelId)]
    ;   LAttrs = [], Children1 = Children0
    ),
    append([[role(group)], LAttrs, [class(ClassVal)], Opts1], Attrs),
    px_template:render(S, div(Attrs, Children1)).

wire_group_label([select_label(LOpts0, LC)|Rest], LabelId, [select_label(LOpts1, LC)|Rest]) :-
    !,
    (   selectchk(id(LabelId0), LOpts0, LOpts1a)
    ->  LabelId = LabelId0, LOpts1 = [id(LabelId0)|LOpts1a]
    ;   gensym(px_select_label_, LabelId), LOpts1 = [id(LabelId)|LOpts0]
    ).

		 /*******************************
		 *             LABEL             *
		 *******************************/

%!  select_label(+Opts, +Children) is det.
px_template:render_helper(select_label(Opts0, Children), S) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-select-label", ClassVal, Opts1),
    append([[class(ClassVal)], Opts1], Attrs),
    px_template:render(S, div(Attrs, Children)).

		 /*******************************
		 *           SEPARATOR           *
		 *******************************/

%!  select_separator(+Opts) is det.
px_template:render_helper(select_separator(Opts0), S) :-
    must_be(list, Opts0),
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "px-select-separator ~w", [C])
    ;   ClassVal = "px-select-separator", Opts1 = Opts0
    ),
    px_template:render(S, separator_root([class(ClassVal)|Opts1], [])).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Order 20: the next free slot after form.pl's Order 19 -- Select is
%   deliberately last (adr/0026 rule 8's own porting order: "menus, and
%   Select last").
px_ui:demo(select, 20, \select_demo).

select_demo ~>
    div(class("px-select-demo"),
      [ section(class("ui-demo-block"),
          [ h3("Basic -- groups, labels, separator, disabled item, inside a form"),
            p([ "Click the trigger (or focus it and press ArrowDown/Enter/Space): ",
                "the native <select> underneath is the real, always-present, no-JS ",
                "fallback and form-submitted value store -- <px-select> hides it and ",
                "layers the custom trigger+listbox on top, syncing every selection ",
                "back onto it. Submitting performs a real GET to this page -- watch ",
                "the address bar for ?fruit=... to confirm the native control's ",
                "value is what's actually submitted."
              ]),
            form([action(""), method(get), class("px-select-demo-form")],
              [ select_root([id("select-demo-basic"), name(fruit),
                              placeholder("Select a fruit…")],
                  [ select_group([],
                      [ select_label([], "Fruits"),
                        select_item([value(apple)], "Apple"),
                        select_item([value(banana)], "Banana"),
                        select_item([value(blueberry), disabled(true)], "Blueberry"),
                        select_item([value(grapes)], "Grapes"),
                        select_item([value(pineapple)], "Pineapple")
                      ]),
                    select_separator([]),
                    select_group([],
                      [ select_label([], "Vegetables"),
                        select_item([value(aubergine)], "Aubergine"),
                        select_item([value(broccoli)], "Broccoli"),
                        select_item([value(carrot)], "Carrot"),
                        select_item([value(courgette)], "Courgette")
                      ])
                  ]),
                button([type(submit), class("px-select-demo-submit")], "Submit")
              ])
          ]),

        section(class("ui-demo-block"),
          [ h3("Preselected -- value(true) on one Item, no placeholder shown"),
            p("aria-selected/data-state=\"checked\"/the checkmark/the native <option selected> are all already correct on first paint, no JS needed to see the right initial state."),
            select_root([id("select-demo-preselected"), name(fruit2)],
                [ select_item([value(apple)], "Apple"),
                  select_item([value(banana), selected(true)], "Banana"),
                  select_item([value(grapes)], "Grapes"),
                  select_item([value(pineapple)], "Pineapple")
                ])
          ]),

        section(class("ui-demo-block"),
          [ h3("Placeholder variant -- a custom placeholder string, nothing selected"),
            p("data-placeholder is present on both the Trigger and the Value span until something is chosen."),
            select_root([id("select-demo-placeholder"), name(color), placeholder("Pick a color")],
                [ select_item([value(red)], "Red"),
                  select_item([value(green)], "Green"),
                  select_item([value(blue)], "Blue")
                ])
          ])
      ]).
