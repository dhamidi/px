:- module(ui_scroll_area, []).

%   No predicates are exported: scroll_area/2, scroll_area_root/2,
%   scroll_area_viewport/2, scroll_area_scrollbar/2, scroll_area_thumb/1,
%   scroll_area_corner/1 are never called module-qualified -- they are
%   term SHAPES that px_template's bare-call dispatch resolves via the
%   multifile px_template:render_helper/2 table (registered below), the
%   same pattern every other ui/*.pl module uses.

/** <module> Scroll Area (adr/0026): cross-browser custom-styleable
scrollbars over an otherwise perfectly native scrollable region.

Ported from Radix UI's ScrollArea primitive (docs/radix-port-analysis.md,
"Scroll Area" entry). Anatomy (this module's public template surface,
verbatim from the analysis doc): `Root` (`scroll_area_root/2`),
`Viewport` (`scroll_area_viewport/2`), `Scrollbar`
(`scroll_area_scrollbar/2`, one per axis), `Thumb`
(`scroll_area_thumb/1`), `Corner` (`scroll_area_corner/1`).
`scroll_area/2` is the rule-1 top-level convenience: a Root wrapping one
Viewport around Children, a vertical Scrollbar+Thumb always, and (when
`orientation(both)` is requested) a horizontal Scrollbar+Thumb plus a
Corner.

**DOM/ARIA contract emitted** (docs/radix-port-analysis.md's "Scroll
Area" entry, verbatim -- adr/0026 rule 2, sacred): **no `role`,
`aria-hidden`, `aria-orientation`, `aria-controls`, or `tabIndex`
anywhere in this component at all** -- upstream's own accessibility
story is "the underlying `overflow:scroll` div behaves like a native
scrollable div", and this port's Viewport really is exactly that
native div, so there is nothing to add. `data-orientation`
(`vertical`/`horizontal`) on Scrollbar; `data-state` (`visible`/
`hidden`) on Scrollbar, computed per `type` (see below). Sizes are
never exposed as `--radix-scroll-area-*` CSS vars here (nothing reads
them -- see "What is deferred" below); everything else the analysis doc
lists (Root/Viewport/Thumb/Corner) carries no attribute beyond `class`
and, for Root, `data-type`/`data-scroll-hide-delay` (this port's
additive DOM-level handoff to `<px-scroll-area>`, same convention every
other custom-element-backed component here uses, e.g.
`hover_card_root/2`'s `data-open-delay`).

**Platform choice (adr/0026 rule 3) -- THE decision this port makes,
spelled out precisely (docs/radix-port-analysis.md's own "Scroll Area"
entry is the source for every claim below):**

Upstream ScrollArea is a fully custom-JS scrollbar: the REAL native
scrollbar is hidden (a `<style>` tag injected into Viewport specifically
to zero out `::-webkit-scrollbar` and set `scrollbar-width: none`), and
a hand-built, pointer-dragged Thumb/track pair is drawn on top,
synchronized to `scrollLeft`/`scrollTop` via `requestAnimationFrame`
polling, `ResizeObserver`-sized, RTL-aware, with four independently
timed auto-hide behaviors (`hover`/`scroll`/`auto`/`always`). The stated
purpose of all that machinery is *pixel-identical cross-browser
scrollbar styling* -- upstream explicitly does NOT need it for the
underlying scroll behavior itself (keyboard scrolling, wheel scrolling,
drag-to-scroll on the real scrollbar all already work on a plain
`overflow:scroll` div with zero JS; the analysis doc's own words:
"zero `onKeyDown` handlers anywhere -- keyboard scrolling ... works
unmodified/natively because real scrolling happens on the native
viewport underneath").

prologex ships in 2026. `scrollbar-color`/`scrollbar-width` (Chrome
121+, Firefox for years, Safari via `::-webkit-scrollbar`) let CSS
recolor and thin the REAL scrollbar directly -- narrower than upstream's
custom Thumb (no arbitrary child content inside the thumb, no scripted
corner geometry, and cross-engine styling still isn't pixel-identical:
Firefox honors `scrollbar-color`, Chromium honors `::-webkit-scrollbar`
*in preference to* `scrollbar-color` when both are present, so both
rule sets are shipped in `assets/css/ui.css` for full coverage), but it
covers the entire VISUAL goal this component exists for -- a thin,
accent-tinted, rounded-thumb scrollbar -- with zero JS and zero
duplicated scroll mechanism. This port takes that substitution:

  - **Viewport is the real scrolling element** (`overflow: auto`),
    styled directly (`assets/css/ui.css`) with `scrollbar-width: thin`
    + `scrollbar-color` (Firefox/Chrome-native path) and
    `::-webkit-scrollbar`/`-thumb`/`-track` (Chromium/Safari path).
    Keyboard scrolling, wheel scrolling, and drag-scrolling the real
    scrollbar thumb all come free from the platform -- nothing here
    reimplements any of it.
  - **Scrollbar/Thumb/Corner are rendered for CONTRACT fidelity only --
    they are never painted** (`display: none` in `assets/css/ui.css`).
    Their entire job is carrying the `data-orientation`/`data-state`
    attributes the analysis doc's contract pins down, so CSS (and any
    Radix-ecosystem styling keyed off that exact contract) has
    something real to select against, and so `<px-scroll-area>` (see
    below) has an attribute to toggle. The REAL scrollbar's color is
    driven off that same `data-state` via a `:has()` selector
    (`.px-scroll-area:has(.px-scroll-area-scrollbar[data-state=
    "visible"]) .px-scroll-area-viewport { scrollbar-color: ...; }`) --
    one data source, zero duplicated visual scrollbar.
  - **`type=auto`/`type=always` need no JS at all.** `always`: Scrollbar
    renders `data-state="visible"` unconditionally, statically, forever
    -- CSS keys the native scrollbar's color off `[data-type="always"]`
    directly, no `:has()` needed. `auto`: Scrollbar ALSO renders
    `data-state="visible"` statically (**a documented, narrower gap**:
    upstream's `auto` computes *actual* overflow via `ResizeObserver`
    and hides the Scrollbar wrapper when content does not overflow;
    this port does not replicate that JS-driven check -- instead it
    leans on the fact that a real `overflow: auto` viewport's native
    scrollbar-track machinery *already* only paints when content
    genuinely overflows, so the practical visual outcome -- "a
    scrollbar appears only when there is something to scroll" -- still
    holds, just decided by the platform's own layout engine rather than
    by this port's markup or JS).
  - **`type=hover`/`type=scroll` are the only two paths that need any
    JS**, exactly the task's own instruction: `assets/js/components/
    scroll_area.js`'s entire job is toggling `data-state` on the
    decorative Scrollbar part(s) -- `hover`: Root `pointerenter`/
    `pointerleave`; `scroll`: Viewport `scroll` (visible immediately)
    plus a `scrollHideDelay`-driven `setTimeout` back to hidden (600ms
    default, Radix's own default, threaded through as
    `data-scroll-hide-delay`). See that file's own header for the full
    mechanics -- it is deliberately small (no `ResizeObserver`, no
    `requestAnimationFrame` polling, no pointer-capture drag math: none
    of that is needed once the real scrollbar IS the visual thumb).

**What is deferred, honestly (adr/0026 rule 2):**

  1. **Thumb pointer-drag on the decorative Thumb part is not
     implemented at all** -- there is nothing to drag: the decorative
     Thumb is never painted (`display: none`), and the REAL scrollbar
     (native, styled per above) already gives pointer-drag-to-scroll
     for free, out of the box, on every evergreen browser. Porting
     upstream's bidirectional pointer<->scroll coordinate transform
     (RTL-aware linear-scale interpolation) would be re-implementing
     what the platform's own scrollbar drag handling already does.
  2. **No `--radix-scroll-area-corner-width/height`/`-thumb-width/
     height` CSS custom properties are emitted** -- nothing in this
     port ever needs a script-computed thumb size (there is no
     script-drawn thumb to size); a caller wanting Radix-ecosystem CSS
     keyed off those vars will not find them here, an explicit,
     documented gap rather than a silent omission.
  3. **Corner never gets bespoke sizing/positioning logic** -- it is
     never painted (`display: none`); when both axes genuinely overflow,
     the BROWSER's own native scrollbar-corner (the small square where
     a vertical and horizontal native scrollbar meet) already renders
     itself, with zero markup or JS from this port.
  4. **`type=auto`'s hide-when-not-overflowing behavior is
     platform-derived, not computed** -- see the "Platform choice"
     writeup above; no `ResizeObserver` runs here.

Options (plain lists, adr/0026 rule 1):

  `scroll_area_root/2` Opts:
    type(auto|always|scroll|hover)  default `auto` (Radix's own
                    default). Drives `data-type` -- read by
                    `<px-scroll-area>` to decide whether it does
                    anything at all (a no-op for `auto`/`always`), and
                    by `assets/css/ui.css` to pick the static-visible
                    vs. `:has()`-driven CSS path.
    scroll_hide_delay(Ms)  default `600` (Radix's own `scrollHideDelay`
                    default). Drives `data-scroll-hide-delay`, read by
                    `<px-scroll-area>` for `type(scroll)`'s hide timer
                    only (irrelevant, but still rendered, for the other
                    three types).
    class(C)        merged with the default class, default first
                    ("px-scroll-area C").
    anything else   passed through verbatim, appended AFTER the
                    computed attributes.

  `scroll_area_viewport/2` Opts:
    class(C), anything else  pass-through, as usual. No other options
                    -- no role/aria/tabIndex exists to compute (see the
                    DOM/ARIA contract above).

  `scroll_area_scrollbar/2` Opts:
    orientation(vertical|horizontal)  default `vertical`. Drives
                    `data-orientation`.
    type(auto|always|scroll|hover)  default `auto` -- used ONLY to
                    compute the DEFAULT `data-state` (see
                    `default_scrollbar_state/2` below); not itself
                    rendered as an attribute here (that is Root's job).
    visible(Bool)   optional explicit override for the initial
                    `data-state` (`true` -> `visible`, anything else ->
                    `hidden`), taking precedence over the `type`-derived
                    default -- useful for demoing/testing a `type(scroll)`
                    or `type(hover)` bar in its already-visible state
                    without waiting on `<px-scroll-area>`'s JS.
    class(C), anything else  pass-through, as usual.

  `scroll_area_thumb/1` Opts:
    class(C), anything else  pass-through onto the `<div>`. No other
                    options -- pure, never-painted markup (see "What is
                    deferred" above).

  `scroll_area_corner/1` Opts:
    class(C), anything else  pass-through onto the `<div>`. No other
                    options -- pure, never-painted markup, same as
                    Thumb.

  `scroll_area/2` Opts: everything `scroll_area_root/2` takes
                    (`type(_)`/`scroll_hide_delay(_)` forwarded to
                    Root AND to every Scrollbar's `type(_)`), PLUS
    orientation(vertical|horizontal|both)  default `vertical`. `vertical`
                    renders one vertical Scrollbar+Thumb (the common
                    case); `horizontal` renders one horizontal
                    Scrollbar+Thumb instead; `both` renders one of each
                    plus a Corner.
    id(Id), class(C)  legitimately Root-level -- NOT stripped, same
                    convention as `popover/2`/`hover_card/2`.

  `scroll_area/2` second argument: Children, rendered directly inside
                    Viewport -- the scrollable content itself (a list,
                    a row of chips, ... whatever the caller supplies).
*/

:- use_module(library(lists)).
:- use_module('../px_template').

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

		 /*******************************
		 *        OPTION HELPERS        *
		 *******************************/

valid_type(auto).
valid_type(always).
valid_type(scroll).
valid_type(hover).

valid_orientation(vertical).
valid_orientation(horizontal).

%!  take_type(+Opts0, -Type, -Rest) is det.
%
%   Default `auto` -- Radix's own ScrollArea Root default.
take_type(Opts0, Type, Rest) :-
    (   selectchk(type(T0), Opts0, Rest)
    ->  ( valid_type(T0) -> Type = T0 ; Type = auto )
    ;   Type = auto, Rest = Opts0
    ).

%!  take_scroll_hide_delay(+Opts0, -Ms, -Rest) is det.
%
%   Default `600` -- Radix's own `scrollHideDelay` default.
take_scroll_hide_delay(Opts0, Ms, Rest) :-
    (   selectchk(scroll_hide_delay(M0), Opts0, Rest)
    ->  Ms = M0
    ;   Ms = 600, Rest = Opts0
    ).

%!  take_orientation(+Opts0, -Orientation, -Rest) is det.
%
%   Default `vertical`. `scroll_area_scrollbar/2`-only: a single
%   Scrollbar's `data-orientation` is vertical|horizontal, never
%   "both" (see `take_group_orientation/3` below for `scroll_area/2`'s
%   own, wider vocabulary).
take_orientation(Opts0, Orientation, Rest) :-
    (   selectchk(orientation(O0), Opts0, Rest)
    ->  ( valid_orientation(O0) -> Orientation = O0 ; Orientation = vertical )
    ;   Orientation = vertical, Rest = Opts0
    ).

%!  take_group_orientation(+Opts0, -Orientation, -Rest) is det.
%
%   `scroll_area/2`-only: vertical|horizontal|both, default `vertical`
%   -- "both" picks how many Scrollbar parts (and whether a Corner) to
%   assemble; it is never itself a valid `data-orientation` value on
%   any single Scrollbar (see `scrollbars_for/3` below).
take_group_orientation(Opts0, Orientation, Rest) :-
    (   selectchk(orientation(O0), Opts0, Rest)
    ->  ( memberchk(O0, [vertical, horizontal, both]) -> Orientation = O0 ; Orientation = vertical )
    ;   Orientation = vertical, Rest = Opts0
    ).

%!  default_scrollbar_state(+Type, -State) is det.
%
%   `always`/`auto` are statically visible (see the module header's
%   "Platform choice" -- `auto`'s real hide-when-not-overflowing is
%   left to the native scrollbar, never computed here); `scroll`/
%   `hover` start `hidden` -- `<px-scroll-area>` (assets/js/components/
%   scroll_area.js) is what ever flips them to `visible`.
default_scrollbar_state(always, visible) :- !.
default_scrollbar_state(auto,   visible) :- !.
default_scrollbar_state(scroll, hidden)  :- !.
default_scrollbar_state(hover,  hidden).

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

%!  scroll_area_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `scroll_area_root([type(hover)],
%   [Viewport, Scrollbar])`. Renders the `<px-scroll-area>` custom-
%   element wrapper (adr/0026 rule 4) around a plain `<div>` carrying
%   `data-type`/`data-scroll-hide-delay` -- see the module header's
%   "Platform choice" for why this element is a no-op for
%   `type(auto)`/`type(always)`.
px_template:render_helper(scroll_area_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_scroll_area, [], [div(Attrs, Children)]).

root_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_type(Opts0, Type, Opts1),
    take_scroll_hide_delay(Opts1, Ms, Opts2),
    merge_class(Opts2, "px-scroll-area", ClassVal, Opts3),
    append([ [class(ClassVal), data_type(Type), data_scroll_hide_delay(Ms)],
             Opts3
           ], Attrs).

		 /*******************************
		 *            VIEWPORT          *
		 *******************************/

%!  scroll_area_viewport(+Opts, +Children) is det.
%
%   Bare-call template surface: `scroll_area_viewport([], Content)`.
%   Renders the REAL scrolling `<div>` (`overflow: auto`, styled by
%   `assets/css/ui.css`) -- see the module header's DOM/ARIA contract
%   for why this carries no role/aria/tabIndex at all.
px_template:render_helper(scroll_area_viewport(Opts, Children), S) :-
    viewport_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, Children)).

viewport_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-scroll-area-viewport", ClassVal, Opts1),
    append([ [class(ClassVal)], Opts1 ], Attrs).

		 /*******************************
		 *           SCROLLBAR          *
		 *******************************/

%!  scroll_area_scrollbar(+Opts, +Children) is det.
%
%   Bare-call template surface: `scroll_area_scrollbar([orientation(
%   horizontal), type(hover)], [scroll_area_thumb([])])`. Renders the
%   decorative, never-painted `<div>` carrying `data-orientation`/
%   `data-state` -- see the module header's "Platform choice" for why
%   this part exists (contract fidelity + a JS toggle target) without
%   ever being drawn.
px_template:render_helper(scroll_area_scrollbar(Opts, Children), S) :-
    scrollbar_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, Children)).

scrollbar_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_orientation(Opts0, Orientation, Opts1),
    take_type(Opts1, Type, Opts2),
    default_scrollbar_state(Type, DefaultState),
    (   selectchk(visible(V0), Opts2, Opts3)
    ->  ( V0 == true -> State = visible ; State = hidden )
    ;   State = DefaultState, Opts3 = Opts2
    ),
    merge_class(Opts3, "px-scroll-area-scrollbar", ClassVal, Opts4),
    append([ [data_orientation(Orientation), data_state(State), class(ClassVal)],
             Opts4
           ], Attrs).

		 /*******************************
		 *             THUMB            *
		 *******************************/

%!  scroll_area_thumb(+Opts) is det.
%
%   Bare-call template surface: `scroll_area_thumb([])`. No children --
%   Radix's Thumb never has any either. Pure, never-painted markup (see
%   the module header's "What is deferred").
px_template:render_helper(scroll_area_thumb(Opts), S) :-
    thumb_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, [])).

thumb_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-scroll-area-thumb", ClassVal, Opts1),
    append([ [class(ClassVal)], Opts1 ], Attrs).

		 /*******************************
		 *             CORNER           *
		 *******************************/

%!  scroll_area_corner(+Opts) is det.
%
%   Bare-call template surface: `scroll_area_corner([])`. No children.
%   Pure, never-painted markup -- see the module header's "What is
%   deferred": the native scrollbar corner already renders itself.
px_template:render_helper(scroll_area_corner(Opts), S) :-
    corner_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, [])).

corner_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    merge_class(Opts0, "px-scroll-area-corner", ClassVal, Opts1),
    append([ [class(ClassVal)], Opts1 ], Attrs).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  scroll_area(+Opts, +Children) is det.
%
%   Children rendered directly inside Viewport. The common case: a Root
%   wrapping one Viewport, a vertical Scrollbar+Thumb always, and (when
%   `orientation(both)` is requested) a horizontal Scrollbar+Thumb plus
%   a Corner -- same division of labour as `popover/2`/`hover_card/2`.
scroll_area(Opts, Children) ~> \scroll_area_render(Opts, Children).

px_template:render_helper(scroll_area_render(Opts, Children), S) :-
    must_be(list, Opts),
    take_group_orientation(Opts, Orientation, _),
    take_type(Opts, Type, _),
    take_scroll_hide_delay(Opts, Ms, _),
    exclude(convenience_only_opt, Opts, RootOpts0),
    RootOpts = [type(Type), scroll_hide_delay(Ms) | RootOpts0],
    scrollbars_for(Orientation, Type, Scrollbars),
    corner_for(Orientation, Corner),
    append([ [scroll_area_viewport([], Children)], Scrollbars, Corner ], RootChildren),
    px_template:render(S, scroll_area_root(RootOpts, RootChildren)).

%!  scrollbars_for(+Orientation, +Type, -Scrollbars) is det.
scrollbars_for(vertical, Type,
    [scroll_area_scrollbar([orientation(vertical), type(Type)],
       [scroll_area_thumb([])])]) :- !.
scrollbars_for(horizontal, Type,
    [scroll_area_scrollbar([orientation(horizontal), type(Type)],
       [scroll_area_thumb([])])]) :- !.
scrollbars_for(both, Type,
    [ scroll_area_scrollbar([orientation(vertical), type(Type)],
        [scroll_area_thumb([])]),
      scroll_area_scrollbar([orientation(horizontal), type(Type)],
        [scroll_area_thumb([])])
    ]).

%!  corner_for(+Orientation, -CornerParts) is det.
corner_for(both, [scroll_area_corner([])]) :- !.
corner_for(_,    []).

%!  convenience_only_opt(+Opt) is semidet.
%
%   `orientation(_)` is a `scroll_area/2`-only concept -- NOT stripped,
%   it would leak onto Root's `<div>` as a literal, meaningless HTML
%   attribute. `type(_)`/`scroll_hide_delay(_)` ARE stripped from the
%   pass-through remainder because `scroll_area_render/3` recomputes
%   them explicitly onto `RootOpts` itself (so they are never duplicated).
convenience_only_opt(orientation(_)).
convenience_only_opt(type(_)).
convenience_only_opt(scroll_hide_delay(_)).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Order 19: docs/radix-port-analysis.md's own recommended porting
%   order lists Scroll Area 19th -- "the most self-contained L: no
%   ARIA, no focus management, no dependency on any other primitive's
%   port... scheduled last only because it's pure observer/gesture
%   engineering with no reuse payoff for anything else." 18 is already
%   taken (context_menu/menubar/navigation_menu); 19 is the next free
%   slot.
px_ui:demo(scroll_area, 19, \scroll_area_demo).

%   A ~50-item tag/version list, wide enough to force real overflow --
%   the same "long scrollable list" shape Radix's own docs demo uses.
tag_list_items(Items) :-
    numlist(1, 50, Ns),
    findall(Item,
            ( member(N, Ns),
              Minor is N mod 7,
              format(atom(Item), "v1.~w.~w", [N, Minor])
            ),
            Items).

tag_list ~>
    ul(class("px-scroll-area-tag-list"), \tag_list_items_render).

px_template:render_helper(tag_list_items_render, S) :-
    tag_list_items(Items),
    px_template:render(S, each(Items, tag_list_item)).

tag_list_item(Tag) ~> li(["Tag ", Tag]).

%   A row of category chips, wide enough to force horizontal overflow.
chip_row ~>
    div(class("px-scroll-area-chip-row"), \chip_row_render).

%   A grid, both taller AND wider than its box -- forces both axes to
%   overflow at once, so orientation(both)'s second Scrollbar+Thumb AND
%   its Corner all have somewhere real to render (and, not
%   incidentally, is what test/ui/css_coverage.pl needs to find
%   .px-scroll-area-corner reachable from an actual demo -- adr/0026
%   rule 7(d)).
wide_grid ~>
    div(class("px-scroll-area-grid"), \wide_grid_render).

px_template:render_helper(wide_grid_render, S) :-
    numlist(1, 24, Rows),
    px_template:render(S, each(Rows, wide_grid_row)).

wide_grid_row(N) ~>
    div(class("px-scroll-area-chip"), ["Row ", N, " -- a long, non-wrapping label wide enough to force horizontal overflow too"]).

chip_row_render_labels(
    [ "Design", "Engineering", "Marketing", "Sales", "Support",
      "Product", "Legal", "Finance", "Operations", "Research",
      "Security", "Infrastructure", "Growth", "Community", "Docs"
    ]).

px_template:render_helper(chip_row_render, S) :-
    chip_row_render_labels(Labels),
    px_template:render(S, each(Labels, chip)).

chip(Label) ~> span(class("px-scroll-area-chip"), Label).

%   `\scroll_area_demo`, not the bare atom -- same explicit `\Goal`
%   escape every other component's demo template needs (adr/0019).
scroll_area_demo ~>
    div(class("px-scroll-area-demo"),
      [ section(class("ui-demo-block"),
          [ h3("type(auto) -- the default"),
            p("A real, native overflow:auto viewport underneath, thin/tinted via scrollbar-width+scrollbar-color and ::-webkit-scrollbar (assets/css/ui.css) -- zero JS. Scroll it, or Tab to focus it and use arrow keys/PageUp/PageDown/Home/End -- all native."),
            div(class("px-scroll-area-demo-box"),
              scroll_area([id("scroll-area-demo-auto")], \tag_list))
          ]),

        section(class("ui-demo-block"),
          [ h3("type(always)"),
            p("data-state=\"visible\" statically, forever -- no JS at all, not even the small toggle <px-scroll-area> provides for hover/scroll."),
            div(class("px-scroll-area-demo-box"),
              scroll_area([id("scroll-area-demo-always"), type(always)], \tag_list))
          ]),

        section(class("ui-demo-block"),
          [ h3("type(hover) -- hidden until you hover the area"),
            p("data-state starts \"hidden\"; <px-scroll-area> flips it to \"visible\" on pointerenter of the whole Root and back to \"hidden\" on pointerleave -- move your pointer over the box below."),
            div(class("px-scroll-area-demo-box"),
              scroll_area([id("scroll-area-demo-hover"), type(hover)], \tag_list))
          ]),

        section(class("ui-demo-block"),
          [ h3("type(scroll) -- visible only while actively scrolling"),
            p("data-state starts \"hidden\"; <px-scroll-area> flips it to \"visible\" on every Viewport scroll event and back to \"hidden\" scroll_hide_delay(600) ms after the last one -- scroll the box below and watch it fade."),
            div(class("px-scroll-area-demo-box"),
              scroll_area([id("scroll-area-demo-scroll"), type(scroll)], \tag_list))
          ]),

        section(class("ui-demo-block"),
          [ h3("orientation(horizontal)"),
            p("A single horizontal Scrollbar -- same native-viewport substitution, just the perpendicular axis."),
            div(class("px-scroll-area-demo-box px-scroll-area-horizontal-box"),
              scroll_area(
                  [id("scroll-area-demo-horizontal"), type(hover), orientation(horizontal)],
                  \chip_row))
          ]),

        section(class("ui-demo-block"),
          [ h3("orientation(both)"),
            p("Vertical AND horizontal Scrollbars plus a Corner where they meet -- the native scrollbar-corner square renders itself with zero markup/JS once both axes genuinely overflow (see the module header's \"What is deferred\")."),
            div(class("px-scroll-area-demo-box"),
              scroll_area(
                  [id("scroll-area-demo-both"), type(always), orientation(both)],
                  \wide_grid))
          ])
      ]).
