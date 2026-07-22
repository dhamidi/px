:- module(ui_accordion, []).

%   No predicates are exported: accordion/2, accordion_root/2,
%   accordion_item/2, accordion_trigger/2 and accordion_content/2 are
%   never called module-qualified -- bare-call dispatch through
%   px_template's tmpl/2 / render_helper/2 tables (adr/0019) resolves
%   them, the same pattern prolog/ui/collapsible.pl and
%   prolog/ui/toggle_group.pl use.

/** <module> Accordion (adr/0026): a set of Collapsible-like items,
`single` (one open, with a `collapsible` sub-option controlling whether
the sole open item can be closed) or `multiple` (independent), with
arrow-key navigation between triggers.

Ported from Radix UI's Accordion primitive (docs/radix-port-analysis.md,
"Accordion" entry). Built directly on the `<details>`/`<summary>`
platform choice prolog/ui/collapsible.pl already established -- read
that module's header first; every gap documented there (no smooth
animation, no controlled-state sync after native interaction) applies
here too, on a per-Item basis, and this module's custom element
(assets/js/components/accordion.js) is where the controlled-state-sync
gap finally gets closed (Collapsible itself still ships with it open).

**Anatomy (this module's public template surface, deliberately just
four parts):** `Root` (`accordion_root/2`), `Item` (`accordion_item/2`,
wraps a `<details>`, analogous to Collapsible's own Root), `Trigger`
(`accordion_trigger/2`, wraps a `<summary>`), `Content`
(`accordion_content/2`, wraps a `<div role="region">`). Upstream Radix
additionally has a `Header` part (a hardcoded `<h3>`, no per-instance
level override, wrapping Trigger). **This port does not expose Header
as its own template** -- see "Header placement" below for why, and note
this is a deliberate difference from the anatomy list, not an
oversight. `accordion/2` is the rule-1 top-level convenience: a Root
around a list of Items, each given as `accordion_item(ItemOpts,
[TriggerChildren, ContentChildren])`, with `type`/`collapsible`/
`orientation` threaded from Root onto every Item/Trigger/Content and
Trigger<->Content id wiring (and, for `type=single`, a shared `name`
group -- see below) done automatically, the same division of labour as
collapsible.pl's `collapsible/2` and toggle_group.pl's `toggle_group/2`.

**Header placement (contract deviation, required by a hard HTML
constraint, noted per adr/0026 rule 2).** Upstream Radix's Header wraps
Trigger from the OUTSIDE (`<h3><button>...</button></h3>`) because
upstream is plain divs/buttons with no native semantics to preserve.
This port's Trigger is a real `<summary>`, and per the HTML spec a
`<summary>` element only gets its native disclosure-widget behaviour
(click-to-toggle, default triangle marker, keyboard activation) when it
is literally the `<details>` element's first `summary` CHILD -- nesting
it one level deeper (inside an `<h3>`) would silently strip all of
that for zero benefit. The only spec-valid way to keep both the native
`<summary>` behaviour AND an `<h3>` in the DOM is to nest the `<h3>`
INSIDE `<summary>` instead of the reverse:

    accordion_trigger(Opts, Children) emits
      <summary class="px-accordion-trigger" ...>
        <h3 class="px-accordion-header" data-orientation="..." data-state="..." ...>
          Children
        </h3>
      </summary>

so `Header`'s own documented attribute set (`data-orientation`,
`data-state`, `data-disabled` -- exactly the analysis doc's "Header"
line) is emitted on that inner `<h3>` by `accordion_trigger/2` itself;
there is no separate `accordion_header/2` bare-call surface because
Header, per the analysis doc, is never independently configurable
anyway ("hardcoded level -- no per-instance override").

**Platform choice (adr/0026 rule 3) -- "modern platform exclusive
accordions".** `type=single` maps to native `<details name="...">`
grouping (supported across all major engines since ~2023-2024, per the
analysis doc): every Item in the group renders the SAME `name`
attribute value, and the browser then enforces "at most one open" all
by itself -- opening one native-toggles every other same-named
`<details>` closed, zero JS. This alone fully covers `type=single,
collapsible=true` (Radix's own default -- see Options below): a caller
gets working exclusive-accordion behaviour from server-rendered HTML
with NO custom element upgrade required. `type=multiple` renders no
`name` attribute at all (native grouping is unconditionally exclusive;
sharing a name across "independent" Items would be actively wrong).

**Interactivity class: CUSTOM-ELEMENT -- unavoidably, same verdict as
Toggle Group** (the analysis doc's own words): arrow-key navigation
between triggers cannot be done without client JS. `type=single,
collapsible=false` additionally needs JS for one thing native grouping
cannot do alone: BLOCKING the close of the one mandatory-open item
(native grouping only handles the OPEN side of exclusivity). Without
JS, `collapsible=false` silently degrades to `collapsible=true`
behaviour (every item closable) -- documented, acceptable regression
under adr/0026 rule 4's progressive-enhancement bar (nothing breaks,
the strict "always one open" invariant just isn't enforced without the
upgrade). See assets/js/components/accordion.js's header for exactly
how `<px-accordion>` closes this gap using the `beforetoggle` event
(`ToggleEvent.newState`) -- itself a "modern platform" feature this
port leans on rather than hand-rolling.

**Keyboard: roving-focus reuse, not the analysis doc's hand-rolled
walk (documented deviation, adr/0026 rule 2).** The analysis doc notes
upstream Radix Accordion hand-rolls its own Home/End/Arrow-key
collection walker rather than using react-roving-focus, leaving
triggers independently Tab-focusable. This port instead reuses
`assets/js/lib/roving-focus.js`'s `installRovingFocus/2` wholesale --
the same shared module Toggle Group already proved out -- trading
upstream's "every trigger independently Tab-focusable" nuance for the
single-tab-stop model roving-focus already implements (adr/0026 rule
5's reuse-first mandate: shared machinery is ported once and consumed,
not re-implemented per component). Concretely: `itemSelector:
".px-accordion-trigger"`, `orientation: "vertical"` (Accordion's
default orientation, read from Root's `data-orientation`), `loop:
false`. A trigger already carrying `aria-disabled="true"` (the
mandatory-open-item case above) is correctly excluded from arrow-key
targets by roving-focus's own `isDisabled/1` check -- consistent with
upstream Radix's own intent for that state (a trigger that cannot be
usefully activated should not be a navigation target either).

**DOM/ARIA contract emitted** (docs/radix-port-analysis.md's
"Accordion" entry, adr/0026 rule 2 -- sacred except where noted above):

    Root (`<px-accordion><div>`):  data-orientation (default vertical),
                          no role. Additive (rule 2): data-type
                          ("single"/"multiple") and data-collapsible
                          (empty-string, only when true) -- neither is
                          a literal Radix-rendered attribute (upstream
                          reads both off React context/state), but
                          `<px-accordion>` needs SOME markup-level way
                          to learn them (rule 4: state lives in DOM
                          attributes, never a parallel JS store) --
                          same rationale as toggle_group.pl's own
                          `data-loop`.
    Item (`<details>`):  data-orientation, data-state (open|closed --
                          this component's own tracking, layered on
                          top of Collapsible's identical convention),
                          native `open`, native `name` (type=single
                          only, shared across the group -- see above).
                          Per the analysis doc's own attribute list for
                          Item, no data-disabled here (unlike
                          Collapsible's Root) -- disabledness is a
                          Header/Trigger/Content-level concept only, so
                          `accordion_item/2` does not even take a
                          `disabled` option.
    Header (`<h3>`, nested inside Trigger -- see above):
                          data-orientation, data-state, data-disabled.
    Trigger (`<summary>`): everything Collapsible's trigger sets
                          (aria-controls -- only while open, an
                          upstream quirk collapsible.pl already
                          documents and keeps; aria-expanded, always;
                          data-state; data-disabled), PLUS aria-disabled
                          on the currently-open trigger when
                          type=single and NOT collapsible (can't
                          re-close the one mandatory-open item -- see
                          "Platform choice" above for why native
                          grouping alone cannot express this).
    Content (`<div>`):   everything Collapsible's content sets
                          (data-state, data-disabled, id), PLUS
                          role="region" and aria-labelledby={triggerId}
                          (the standard APG region-labelled-by-trigger
                          pattern). Radix's accordion-prefixed
                          height/width CSS vars for animation are NOT
                          emitted -- same documented gap as
                          collapsible.pl's gap #1 (no measurement JS
                          here either); `<details>` toggles content
                          display abruptly, exactly as Collapsible's
                          static case already does.

**Disabled handling:** same JS-free best-effort mitigation as
collapsible.pl (`<summary>` has no native `disabled` attribute):
Trigger's `disabled(true)` adds `data-disabled=""` (also mirrored onto
the nested Header `<h3>`) plus `tabindex="-1"`; assets/css/ui.css pairs
`[data-disabled]` with `pointer-events: none` plus a dimmed treatment.

Options (plain lists, adr/0026 rule 1):

  `accordion_root/2` Opts:
    type(single|multiple)  REQUIRED, no sane default (same as
                    toggle_group.pl's own `type`). Drives `data-type`
                    and is what `<px-accordion>` reads to decide
                    whether the `collapsible=false` close-blocking
                    logic applies at all.
    collapsible(Bool)  default `false` (Radix's own default). Only
                    meaningful when `type=single`; harmless no-op
                    otherwise. `true` emits `data-collapsible=""`.
    orientation(horizontal|vertical)  default `vertical` (Radix's own
                    default for Accordion -- note this is the OPPOSITE
                    default from toggle_group.pl's `horizontal`).
    class(C)        merged with the default class, default first.
    anything else   passed through verbatim, appended AFTER the
                    computed attributes.

  `accordion_item/2` Opts:
    open(Bool)      default `false`. Native `open` boolean attribute +
                    `data-state`.
    orientation(...)  default `vertical`; independently settable when
                    calling this part directly (the `accordion/2`
                    convenience threads Root's value automatically).
    name(Name)      low-level escape hatch: renders the native `name`
                    attribute directly (mirrors collapsible.pl's own
                    `controls(Id)` precedent -- not a Radix prop,
                    supplied by `accordion/2` when assembling the
                    common case, see below).
    class(C), anything else  same pass-through convention as every
                    other part in this library.

  `accordion_trigger/2` Opts:
    open(Bool)      default `false`.
    disabled(Bool)  default `false`.
    controls(Id)    the Content id this Trigger discloses; emitted as
                    `aria-controls` only while open (same upstream
                    quirk as collapsible.pl's Trigger).
    type(single|multiple)  default `multiple` when omitted (i.e. "never
                    apply the aria-disabled-when-mandatory-open rule")
                    -- unlike Root, NOT required here: a standalone
                    Trigger call has no group to be inconsistent with.
    collapsible(Bool)  default `false`. Together with `type` and
                    `open`, drives the `aria-disabled="true"` case
                    above.
    orientation(...)  default `vertical`; applied to the nested Header
                    `<h3>`, not to the `<summary>` itself (the contract
                    does not list `data-orientation` on Trigger).
    class(C), anything else  pass-through, as usual.

  `accordion_content/2` Opts:
    open(Bool)      default `false`. Drives `data-state`.
    disabled(Bool)  default `false`. Drives `data-disabled`.
    labelledby(TriggerId)  emits `aria-labelledby`, unconditionally
                    (unlike Trigger's conditional `aria-controls` --
                    Content's own labelling has no "only while open"
                    quirk documented anywhere upstream).
    id(Id), class(C), anything else  pass-through, as usual (`id` is
                    never specially "taken" -- same as
                    collapsible_content/2's own `id(Id)`).

  `accordion/2` second argument: a list of `accordion_item(ItemOpts,
                    [TriggerChildren, ContentChildren])` terms.
                    ItemOpts recognises `open(Bool)`, `disabled(Bool)`
                    (routed to that Item's Trigger AND Content --
                    `accordion_item/2` itself never sees it, per the
                    contract note above), `id(Id)` (base id; suffixed
                    `-trigger`/`-content` for the two generated parts,
                    and used as-is for the Item's own `<details>` id;
                    gensym'd when absent, same convention as
                    collapsible.pl's `content_id/2`), and `class(C)`
                    (passed straight through to the Item's `<details>`
                    tag). `type`/`collapsible`/`orientation` are always
                    Root's values, injected onto every generated
                    Trigger/Content/Item -- never read from ItemOpts.
                    Any list element that is not an
                    `accordion_item(_,_)` shape passes through to
                    Root's children unmodified (same rule
                    toggle_group.pl's `inject_type/3` uses for raw
                    interleaved markup).
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

valid_type(single).
valid_type(multiple).

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

%!  require_type(+Opts, +Context, -Type) is det.
require_type(Opts, Context, Type) :-
    require_opt(Opts, type, Context, Type0),
    (   valid_type(Type0)
    ->  Type = Type0
    ;   throw(error(domain_error(accordion_type, Type0), context(Context, _)))
    ).

%!  take_open(+Opts0, -Open, -Rest) is det.
%
%   Same coercing helper as collapsible.pl's: anything other than the
%   atom `true` degrades to `false`.
take_open(Opts0, Open, Rest) :-
    (   selectchk(open(O0), Opts0, Rest)
    ->  ( O0 == true -> Open = true ; Open = false )
    ;   Open = false, Rest = Opts0
    ).

%!  take_disabled(+Opts0, -Disabled, -Rest) is det.
take_disabled(Opts0, Disabled, Rest) :-
    (   selectchk(disabled(D0), Opts0, Rest)
    ->  ( D0 == true -> Disabled = true ; Disabled = false )
    ;   Disabled = false, Rest = Opts0
    ).

%!  take_bool(+Name, +Opts0, -Value, -Rest) is det.
%
%   Same helper as toggle_group.pl's (non-coercing: the caller is
%   expected to pass proper `true`/`false` atoms). Used for
%   `collapsible(_)`.
take_bool(Name, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Opts1)
    ->  Value = V0
    ;   Value = false, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  take_orientation(+Opts0, -Orientation, -Rest) is det.
%
%   Default `vertical` -- Accordion's own default, the opposite of
%   toggle_group.pl's `horizontal` default. An unrecognised value falls
%   back to the default (same guard as toggle_group.pl's
%   `orientation_opt/2`).
take_orientation(Opts0, Orientation, Rest) :-
    (   selectchk(orientation(O0), Opts0, Rest)
    ->  ( valid_orientation(O0) -> Orientation = O0 ; Orientation = vertical )
    ;   Orientation = vertical, Rest = Opts0
    ).

%!  take_controls(+Opts0, -ControlsOpt, -Rest) is det.
take_controls(Opts0, ControlsOpt, Rest) :-
    (   selectchk(controls(Id), Opts0, Rest)
    ->  ControlsOpt = controls(Id)
    ;   ControlsOpt = none, Rest = Opts0
    ).

%!  take_labelledby(+Opts0, -LabelledbyOpt, -Rest) is det.
take_labelledby(Opts0, LabelledbyOpt, Rest) :-
    (   selectchk(labelledby(Id), Opts0, Rest)
    ->  LabelledbyOpt = labelledby(Id)
    ;   LabelledbyOpt = none, Rest = Opts0
    ).

%!  take_name_opt(+Opts0, -NameOpt, -Rest) is det.
take_name_opt(Opts0, NameOpt, Rest) :-
    (   selectchk(name(N), Opts0, Rest)
    ->  NameOpt = name(N)
    ;   NameOpt = none, Rest = Opts0
    ).

%!  take_type(+Opts0, -Type, -Rest) is det.
%
%   Non-throwing: a standalone accordion_trigger/2 call has no group
%   to be inconsistent with, so an absent or invalid `type(_)` just
%   degrades to `multiple` (i.e. "never apply the
%   aria-disabled-when-mandatory-open rule").
take_type(Opts0, Type, Rest) :-
    (   selectchk(type(T0), Opts0, Rest)
    ->  ( valid_type(T0) -> Type = T0 ; Type = multiple )
    ;   Type = multiple, Rest = Opts0
    ).

%!  state_atom(+Open, -State) is det.
state_atom(true,  open)   :- !.
state_atom(false, closed).

%!  disabled_attrs(+Disabled, -Attrs) is det.
%
%   `data-disabled=""` when true, nothing otherwise -- same family-wide
%   convention as collapsible.pl/toggle_group.pl.
disabled_attrs(true,  [data_disabled("")]) :- !.
disabled_attrs(false, []).

%!  merge_class(+Opts0, +Default, -ClassVal, -Rest) is det.
merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

		 /*******************************
		 *             ROOT             *
		 *******************************/

%!  accordion_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `accordion_root([type(single)],
%   Items)`. Renders the `<px-accordion>` custom-element wrapper
%   (adr/0026 rule 4) around the server-rendered `<div>` -- exactly
%   toggle_group.pl's own `toggle_group_root/2` pattern. Without JS
%   upgrade: `type=single, collapsible=true` still fully works (native
%   `name` grouping); `type=multiple` still fully works minus
%   arrow-key nav (plain sequential Tab-through, same degrade story as
%   Toggle Group); `type=single, collapsible=false` degrades to
%   `collapsible=true` behaviour (documented above).
px_template:render_helper(accordion_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_accordion, [], [div(Attrs, Children)]).

root_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    require_type(Opts0, accordion_root/2, Type),
    take_orientation(Opts0, Orientation, Opts1),
    take_bool(collapsible, Opts1, Collapsible, Opts2),
    merge_class(Opts2, "px-accordion", ClassVal, Opts3),
    exclude(root_reserved_opt, Opts3, Extra),
    collapsible_root_attrs(Collapsible, CollapsibleAttrs),
    append([ [data_orientation(Orientation), data_type(Type), class(ClassVal)],
             CollapsibleAttrs, Extra
           ], Attrs).

collapsible_root_attrs(true, [data_collapsible("")]) :- !.
collapsible_root_attrs(_,    []).

root_reserved_opt(type(_)).
root_reserved_opt(orientation(_)).
root_reserved_opt(collapsible(_)).
root_reserved_opt(class(_)).

		 /*******************************
		 *             ITEM             *
		 *******************************/

%!  accordion_item(+Opts, +Children) is det.
%
%   Bare-call template surface: `accordion_item([open(true)], [Trigger,
%   Content])`. Renders `<details>` -- no `data-disabled` here, see the
%   module header's contract note (disabledness is a Header/Trigger/
%   Content-only concept for Accordion, unlike Collapsible's Root).
px_template:render_helper(accordion_item(Opts, Children), S) :-
    item_attrs(Opts, Attrs),
    px_template:render(S, details(Attrs, Children)).

item_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_open(Opts0, Open, Opts1),
    take_orientation(Opts1, Orientation, Opts2),
    take_name_opt(Opts2, NameOpt, Opts3),
    merge_class(Opts3, "px-accordion-item", ClassVal, Opts4),
    exclude(item_reserved_opt, Opts4, Extra),
    state_atom(Open, State),
    ( Open == true -> OpenAttrs = [open] ; OpenAttrs = [] ),
    ( NameOpt = name(N) -> NameAttrs = [name(N)] ; NameAttrs = [] ),
    append([ [data_orientation(Orientation), data_state(State), class(ClassVal)],
             NameAttrs, OpenAttrs, Extra
           ], Attrs).

item_reserved_opt(open(_)).
item_reserved_opt(orientation(_)).
item_reserved_opt(name(_)).
item_reserved_opt(class(_)).

		 /*******************************
		 *            TRIGGER           *
		 *******************************/

%!  accordion_trigger(+Opts, +Children) is det.
%
%   Bare-call template surface: `accordion_trigger([open(true),
%   controls(Id)], "Section title")`. Renders `<summary>` wrapping an
%   inner `<h3>` -- see the module header's "Header placement" section
%   for why the nesting is inverted from upstream Radix.
px_template:render_helper(accordion_trigger(Opts, Children), S) :-
    trigger_attrs(Opts, TriggerAttrs, HeaderAttrs),
    px_template:render(S, summary(TriggerAttrs, [h3(HeaderAttrs, Children)])).

trigger_attrs(Opts0, TriggerAttrs, HeaderAttrs) :-
    must_be(list, Opts0),
    take_open(Opts0, Open, Opts1),
    take_disabled(Opts1, Disabled, Opts2),
    take_controls(Opts2, ControlsOpt, Opts3),
    take_type(Opts3, Type, Opts4),
    take_bool(collapsible, Opts4, Collapsible, Opts5),
    take_orientation(Opts5, Orientation, Opts6),
    merge_class(Opts6, "px-accordion-trigger", ClassVal, Opts7),
    exclude(trigger_reserved_opt, Opts7, Extra),
    state_atom(Open, State),
    disabled_attrs(Disabled, DisabledAttrs),
    (   Open == true, ControlsOpt = controls(Id)
    ->  ControlsAttrs = [aria_controls(Id)]
    ;   ControlsAttrs = []
    ),
    ( Disabled == true -> TabAttrs = [tabindex(-1)] ; TabAttrs = [] ),
    aria_disabled_attrs(Type, Collapsible, Open, AriaDisabledAttrs),
    append([ ControlsAttrs, [aria_expanded(Open)], [data_state(State)],
             DisabledAttrs, AriaDisabledAttrs, [class(ClassVal)], TabAttrs, Extra
           ], TriggerAttrs),
    append([ [data_orientation(Orientation), data_state(State)],
             DisabledAttrs, [class("px-accordion-header")]
           ], HeaderAttrs).

%   "can't re-close the one mandatory-open item" -- the analysis doc's
%   own phrasing. Only fires for type=single, non-collapsible, and only
%   while THIS trigger is the open one -- by definition of `single`, an
%   open trigger under these conditions IS the sole open trigger, no
%   sibling lookup needed at render time.
aria_disabled_attrs(single, Collapsible, true, [aria_disabled(true)]) :-
    Collapsible \== true, !.
aria_disabled_attrs(_, _, _, []).

trigger_reserved_opt(open(_)).
trigger_reserved_opt(disabled(_)).
trigger_reserved_opt(controls(_)).
trigger_reserved_opt(type(_)).
trigger_reserved_opt(collapsible(_)).
trigger_reserved_opt(orientation(_)).
trigger_reserved_opt(class(_)).

		 /*******************************
		 *            CONTENT           *
		 *******************************/

%!  accordion_content(+Opts, +Children) is det.
%
%   Bare-call template surface: `accordion_content([open(true),
%   id(Id), labelledby(TriggerId)], "...")`. No `hidden` attribute --
%   same documented reason as collapsible_content/2 (native `<details>`
%   already owns show/hide).
px_template:render_helper(accordion_content(Opts, Children), S) :-
    content_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, Children)).

content_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_open(Opts0, Open, Opts1),
    take_disabled(Opts1, Disabled, Opts2),
    take_labelledby(Opts2, LabelledbyOpt, Opts3),
    merge_class(Opts3, "px-accordion-content", ClassVal, Opts4),
    exclude(content_reserved_opt, Opts4, Extra),
    state_atom(Open, State),
    disabled_attrs(Disabled, DisabledAttrs),
    (   LabelledbyOpt = labelledby(TId)
    ->  LabelledbyAttrs = [aria_labelledby(TId)]
    ;   LabelledbyAttrs = []
    ),
    append([ [role(region)], LabelledbyAttrs, [data_state(State)],
             DisabledAttrs, [class(ClassVal)], Extra
           ], Attrs).

content_reserved_opt(open(_)).
content_reserved_opt(disabled(_)).
content_reserved_opt(labelledby(_)).
content_reserved_opt(class(_)).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  accordion(+Opts, +Items) is det.
%
%   The common case: Root around a list of Items, each expanded from
%   `accordion_item(ItemOpts, [TriggerKids, ContentKids])` into a fully
%   wired Item > Trigger + Content triple -- Root's `type`/
%   `collapsible`/`orientation` threaded onto every generated part, a
%   shared `name` computed once and injected on every Item when
%   `type=single` (native exclusive-accordion grouping), and
%   Trigger<->Content id wiring (`aria-controls`/`id`/
%   `aria-labelledby`) done automatically -- same division of labour as
%   collapsible.pl's `collapsible/2` and toggle_group.pl's
%   `toggle_group/2`.
accordion(Opts, Items) ~> \accordion_render(Opts, Items).

px_template:render_helper(accordion_render(Opts, Items), S) :-
    require_type(Opts, accordion/2, Type),
    take_bool(collapsible, Opts, Collapsible, _),
    take_orientation(Opts, Orientation, _),
    group_name_opt(Type, Opts, GroupNameOpt),
    maplist(expand_item(Type, Collapsible, Orientation, GroupNameOpt), Items, Items1),
    px_template:render(S, accordion_root(Opts, Items1)).

%!  group_name_opt(+Type, +Opts, -GroupNameOpt) is det.
%
%   `name(Name)` when Type == single (Name derived from Opts' `id(_)`
%   if supplied, else a fresh gensym -- same base-id convention as
%   collapsible.pl's `content_id/2`), `none` when Type == multiple
%   (native `name` grouping is unconditionally exclusive -- sharing one
%   across "independent" Items would be actively wrong).
group_name_opt(single, Opts, name(Name)) :-
    !,
    (   memberchk(id(Base), Opts)
    ->  true
    ;   gensym(px_accordion_, Base)
    ),
    format(atom(Name), '~w-group', [Base]).
group_name_opt(multiple, _, none).

%!  expand_item(+Type, +Collapsible, +Orientation, +GroupNameOpt,
%!              +Item0, -Item) is det.
%
%   Item0 = `accordion_item(ItemOpts0, [TriggerKids, ContentKids])`
%   becomes a fully wired `accordion_item(ItemOptsFinal, [TriggerCall,
%   ContentCall])`. Any other term (e.g. raw markup a caller interleaves
%   between Items) passes through unmodified -- same rule
%   toggle_group.pl's `inject_type/3` uses.
expand_item(Type, Collapsible, Orientation, GroupNameOpt,
            accordion_item(ItemOpts0, [TriggerKids, ContentKids]),
            accordion_item(ItemOptsFinal, [TriggerCall, ContentCall])) :-
    !,
    take_open(ItemOpts0, Open, ItemOpts1),
    take_disabled(ItemOpts1, Disabled, ItemOpts2),
    item_base_id(ItemOpts2, ItemOpts3, ItemBase),
    format(atom(TriggerId), '~w-trigger', [ItemBase]),
    format(atom(ContentId), '~w-content', [ItemBase]),
    ( GroupNameOpt = name(GN) -> NameOpts = [name(GN)] ; NameOpts = [] ),
    append([ [open(Open), orientation(Orientation), id(ItemBase)], NameOpts, ItemOpts3 ],
           ItemOptsFinal),
    TriggerOpts = [ open(Open), disabled(Disabled), type(Type), collapsible(Collapsible),
                     controls(ContentId), id(TriggerId)
                   ],
    ContentOpts = [ open(Open), disabled(Disabled), id(ContentId), labelledby(TriggerId) ],
    TriggerCall = accordion_trigger(TriggerOpts, TriggerKids),
    ContentCall = accordion_content(ContentOpts, ContentKids).
expand_item(_, _, _, _, Other, Other).

%!  item_base_id(+Opts0, -Rest, -Base) is det.
%
%   `id(Base)` from Opts0 if supplied (and removed from Rest); a fresh
%   gensym'd id otherwise -- same convention as collapsible.pl's
%   `content_id/2`, but per-Item rather than per-component.
item_base_id(Opts0, Rest, Base) :-
    (   selectchk(id(Base), Opts0, Rest)
    ->  true
    ;   gensym(px_accordion_item_, Base), Rest = Opts0
    ).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Order 14: the next free slot after toggle_group (12); tabs.pl and
%   toolbar.pl both independently claimed 13 already, so this port
%   takes the following one rather than adding a third collision on
%   top of theirs -- the demo registry's Order values track completion
%   order, not the analysis doc's theoretical phase numbering (rule 8's
%   own phase list already has toggle_group.pl landing ahead of
%   Accordion in this codebase).
px_ui:demo(accordion, 14, \accordion_demo).

%   `\accordion_demo`, not the bare atom -- same explicit `\Goal` escape
%   every other component's demo template needs (adr/0019: a bare atom
%   is always a text node in render/2's dispatch).
accordion_demo ~>
    div(class("px-accordion-demo"),
      [ h3("type(single), collapsible(true) -- native <details name> exclusivity, zero JS needed to open/close"),
        p("Opening any item natively closes whichever other item was open (shared `name` attribute) -- try it with JavaScript disabled."),
        accordion([id("acc-single"), type(single), collapsible(true)],
          [ accordion_item([open(true)],
              [ "What is prologex?",
                p("A batteries-included Prolog web framework: px_template for streaming server-rendered HTML, px_router for routing, and px_ui -- this very component library -- ported from Radix UI.")
              ]),
            accordion_item([],
              [ "Why <details>/<summary>?",
                p("Zero-JS disclosure with a real, server-settable `open` attribute, same platform choice as ui/collapsible.pl -- see this module's header for the full story.")
              ]),
            accordion_item([],
              [ "What about smooth open/close animation?",
                p("Not shipped -- <details> toggles abruptly, the same documented gap as Collapsible's own static case.")
              ])
          ]),

        h3("type(single), collapsible(false) -- exactly one item always open"),
        p("Native `name` grouping still handles switching which item is open for free; <px-accordion> additionally blocks closing the LAST open item (data-state/aria-disabled) via the `beforetoggle` event -- JS required for this one guarantee."),
        accordion([id("acc-single-mandatory"), type(single), collapsible(false)],
          [ accordion_item([open(true)],
              [ "Always at least one item open",
                p("Its trigger carries aria-disabled=\"true\" while it's the sole open item -- still focusable and reachable, just not closable.")
              ]),
            accordion_item([], [ "Second item", p("Opening this one closes the first automatically.") ])
          ]),

        h3("type(multiple) -- independent, no name grouping"),
        p("Each item opens and closes independently; arrow keys still move the single roving tab stop across all triggers."),
        accordion([id("acc-multiple"), type(multiple)],
          [ accordion_item([open(true)], [ "First", p("Independently open.") ]),
            accordion_item([], [ "Second", p("Independently closed.") ]),
            accordion_item([open(true)], [ "Third", p("Also independently open -- multiple items open at once is exactly the point.") ])
          ]),

        h3("Disabled item"),
        p("An item's trigger can be independently disabled -- data-disabled plus tabindex=\"-1\" (no native <summary> disabled attribute, same JS-free mitigation as Collapsible); the roving-focus arrow-key nav skips it."),
        accordion([id("acc-disabled"), type(multiple)],
          [ accordion_item([], [ "Enabled", p("Reachable and toggleable as normal.") ]),
            accordion_item([disabled(true)], [ "Disabled", p("Skipped by arrow-key navigation; its content is still server-rendered underneath.") ]),
            accordion_item([], [ "Enabled too", p("Reachable and toggleable as normal.") ])
          ])
      ]).
