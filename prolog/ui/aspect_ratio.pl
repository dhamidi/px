:- module(ui_aspect_ratio, []).

/** <module> ui/aspect_ratio -- Radix AspectRatio port (adr/0026).

Radix's AspectRatio (packages/react/aspect-ratio) renders TWO divs: an
outer wrapper whose `padding-bottom: {100/ratio}%` reserves the box's
height with the old intrinsic-ratio hack, and an inner
`position: absolute; inset: 0` div holding the actual content -- the
hack every pre-2021 "responsive embed" trick used, needed only because
there was no way to size a box by aspect ratio directly.

**Platform choice (adr/0026 rule 3).** prologex ships in 2026; CSS
`aspect-ratio` has been supported in every evergreen browser for years
(the analysis doc calls this out explicitly: "Modern CSS `aspect-ratio`
could collapse this to one div if legacy-browser support isn't a
concern"). This port takes that collapse: ONE div, `aspect-ratio: <w> /
<h>` set directly via an inline style. No padding math, no absolutely
positioned inner div, no wrapper/content split at all.

**Contract note (rule 2 deviation).** Radix's DOM/ARIA entry lists a
single hook: `data-radix-aspect-ratio-wrapper=""`, a query/styling
anchor, not semantic (no role, no aria-*, no data-state -- there is no
state to track). That attribute is kept, verbatim, on the (now single)
div, so any Radix-ecosystem CSS keyed off it still finds the right
element. Nothing else changes: this is the only DOM node the component
ever emits.

**Anatomy.** Radix's AspectRatio has exactly one exported part, `Root`;
`aspect_ratio_root/2` is that part's template (adr/0026 rule 1 naming),
and `aspect_ratio/2` is the top-level convenience -- for a single-part
component the two are the same call, but both exist so the family
naming (`<component>_<part>` plus `<component>(Opts, Parts)`) holds
uniformly across the library.

**Ratio term.** `ratio(W/H)`, e.g. `ratio(16/9)` (widescreen media),
`ratio(1/1)` (square), `ratio(4/3)`. `/` was chosen over `-`: it reads
as a fraction (the way humans say "sixteen by nine") AND mirrors the
CSS syntax it compiles to almost verbatim (`aspect-ratio: 16 / 9`).
Critically, `16/9` here is never evaluated with `is/2` -- it stays the
plain compound `/(16,9)`, so W and H are never collapsed into a single
float before CSS needs them apart. Default when `ratio/1` is omitted:
`1/1` (a square), matching Radix's own default (`ratio={1}`).

Any other `Opts` element (`id(...)`, `class(...)`, `style(...)`, ...)
passes through to the div's attributes unchanged; a caller-supplied
`style(...)` is appended after the computed `aspect-ratio` declaration
rather than overwritten.
*/

:- prolog_load_context(directory, Here),
   atomic_list_concat([Here, '/../px_template'], TemplateSpec),
   use_module(TemplateSpec).

:- use_module(library(lists)).
:- use_module(library(error)).

:- multifile px_ui:demo/3.
:- multifile px_template:render_helper/2.

		 /*******************************
		 *           TEMPLATES          *
		 *******************************/

%!  aspect_ratio(+Opts, +Content) is det.
%
%   Top-level convenience (adr/0026 rule 1). Single-part component, so
%   this is a straight delegate to the Root part template below.

aspect_ratio(Opts, Content) ~>
    aspect_ratio_root(Opts, Content).

%!  aspect_ratio_root(+Opts, +Content) is det.
%
%   The Root part. The style attribute is computed from Opts (ratio,
%   any caller style to merge), which `~>` bodies -- plain unification
%   of a literal term, no goal execution -- cannot do; so, same
%   pattern as px_form's form_for/4 and px_template's own link_to/2,
%   the body escapes to a render_helper/2 goal that builds the real
%   element term and hands it to render/2.

aspect_ratio_root(Opts, Content) ~>
    \render_aspect_ratio_root(Opts, Content).

px_template:render_helper(render_aspect_ratio_root(Opts, Content), S) :-
    build_root_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, Content)).

		 /*******************************
		 *           ATTRIBUTES         *
		 *******************************/

%!  build_root_attrs(+Opts, -Attrs) is det.
%
%   Attrs = [data_radix_aspect_ratio_wrapper(""), style(Style) | Rest]
%   where Style is "aspect-ratio: W / H;" (plus any caller style(...)
%   appended) and Rest is Opts with ratio/1 and style/1 removed --
%   everything else (id, class, data-*, ...) passes through untouched.

build_root_attrs(Opts, [data_radix_aspect_ratio_wrapper(""), style(Style) | Rest]) :-
    (   select(ratio(Ratio), Opts, Opts1)
    ->  true
    ;   Ratio = 1/1, Opts1 = Opts
    ),
    ratio_css(Ratio, RatioCss),
    (   select(style(UserStyle), Opts1, Rest)
    ->  format(string(Style), "~w ~w", [RatioCss, UserStyle])
    ;   Style = RatioCss, Rest = Opts1
    ).

%!  ratio_css(+Ratio, -Css) is det.
%
%   ratio(16/9) -> "aspect-ratio: 16 / 9;". Anything else is a caller
%   error, not something to silently coerce.

ratio_css(W/H, Css) :-
    !,
    must_be(number, W),
    must_be(number, H),
    format(string(Css), "aspect-ratio: ~w / ~w;", [W, H]).
ratio_css(Ratio, _) :-
    throw(error(domain_error(px_aspect_ratio, Ratio),
                context(ui_aspect_ratio:ratio_css/2,
                        'ratio(W/H) expected, e.g. ratio(16/9)'))).

		 /*******************************
		 *             DEMO             *
		 *******************************/

%   adr/0026 rule 7b: registers /ui/aspect_ratio on the kitchen-sink
%   app automatically. One image at 16/9, one colored div at 1/1 --
%   the image is an inline SVG data URI so the demo has no external
%   asset dependency.

%   \aspect_ratio_demo, not the bare atom: aspect_ratio_demo has arity
%   0, and px_template's render/2 treats a bare atom as a TEXT NODE
%   (matching every other zero-arg demo in this library) -- the
%   explicit \Goal escape is what makes it a template call instead.
px_ui:demo(aspect_ratio, 10, \aspect_ratio_demo).

aspect_ratio_demo ~>
    div(class("aspect-ratio-demo"),
      [ section(
          [ h3("ratio(16/9)"),
            aspect_ratio([ratio(16/9)],
              img([ src("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='400' height='225'%3E%3Crect width='100%25' height='100%25' fill='%237dd3fc'/%3E%3C/svg%3E"),
                    alt("A 16 by 9 placeholder graphic")
                  ]))
          ]),
        section(
          [ h3("ratio(1/1)"),
            aspect_ratio([ratio(1/1)],
              div(class("aspect-ratio-swatch"), []))
          ])
      ]).
