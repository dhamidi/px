:- module(ui_progress, []).

%   No predicates are exported: progress/1, progress_root/2 and
%   progress_indicator/1 are never called module-qualified -- they are
%   term SHAPES that px_template's bare-call dispatch resolves via the
%   multifile px_template:tmpl/2 / px_template:render_helper/2 tables
%   (both explicitly module-qualified at the point of registration
%   below), the same way link_to/2 or stylesheet_tag/2 are called from
%   any template body with no `Module:` prefix (adr/0019).

/** <module> Progress (adr/0026): determinate/indeterminate progress bar.

Ported from Radix UI's Progress primitive (docs/radix-port-analysis.md,
"Progress" entry). Anatomy: `Root` (`progress_root/2`, `role=progressbar`)
wrapping a single `Indicator` (`progress_indicator/1`, the fill bar --
no visual width logic of its own upstream either; here it *does* carry
the width, computed server-side, since there is no consumer stylesheet
free to invent one the way a real app's CSS would). `progress/1` is the
convenience template assembling the common case: `Root` around one
`Indicator`, both fed the same `value`/`max`.

Interactivity class: STATIC (adr/0026 rule 3) -- every attribute below
is a pure function of `value`/`max`, computed once at render time; nothing
here ever polls or animates itself (same as upstream Radix: driving a
value change over time, e.g. via a Turbo-stream replace, is a generic
"update this element" concern outside the primitive's own scope). The
one deviation from a literal transcription: `Indicator`'s inline
`style="width: N%;"` (for determinate state) is *this port's* addition,
since Radix ships no default indicator CSS at all and a consumer
stylesheet is expected to supply `transform`/`width`; without a build
step or client JS to do that here, the percentage is computed
server-side and written as an inline style instead (assets/css/ui.css's
`.px-progress-indicator[data-state="indeterminate"]` covers the
indeterminate case with a pure-CSS sweep animation, no JS).

Options (a plain list, adr/0026 rule 1):

    value(V)    the current value; ABSENT => indeterminate (mirrors
                Radix: `value` defaults to `null`). Must be a number
                with `0 =< V =< Max` to count as determinate -- an
                out-of-range value degrades to indeterminate, same as
                Radix's own `isValidValueNumber` guard (it just warns
                to the console there; there is no console here, so it
                silently degrades instead).
    max(M)      default 100 (Radix's default).
    class(C)    merged with the part's default class, default first
                ("px-progress C" / "px-progress-indicator C").
    anything else (id(...), data_*(...), ...) passed through verbatim,
                appended AFTER the computed attributes -- same
                last-wins spread order as Radix's own
                `{...progressProps}` placed after its explicit
                aria/data attributes in JSX.

DOM/ARIA contract emitted (exactly the analysis doc's "Progress" entry):

    Root:       role="progressbar", aria-valuemax, aria-valuemin="0",
                aria-valuenow (OMITTED when indeterminate),
                aria-valuetext (rounded "N%", OMITTED when
                indeterminate), data-state in
                indeterminate|complete|loading, data-value (OMITTED
                when indeterminate), data-max.
    Indicator:  data-state, data-value (OMITTED when indeterminate),
                data-max -- the same triplet, no ARIA (Radix's
                Indicator carries no role/aria attributes of its own).

progress_root/2 and progress_indicator/1 are registered as
px_template:render_helper/2 hooks (adr/0019), the same pattern
prolog/px_form.pl and prolog/px_assets.pl use for markup that needs
computation from its options rather than pure pattern matching --
bare-call dispatch (`progress_root(Opts, Kids)` in a template body)
resolves to them exactly like an ordinary `~>` template (tmpl/2 is
tried first, then render_helper/2 -- px_template.pl's render_call/2).
*/

:- use_module('../px_template').

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

		 /*******************************
		 *        OPTION HELPERS        *
		 *******************************/

%!  take_value_max(+Opts0, -ValueOpt, -Max, -Rest) is det.
%
%   Pulls `value(V)` (ValueOpt = value(V), or `none` if absent) and
%   `max(M)` (Max, default 100) out of Opts0; Rest is everything else,
%   in its original relative order.
take_value_max(Opts0, ValueOpt, Max, Rest) :-
    (   selectchk(value(V0), Opts0, Opts1)
    ->  ValueOpt = value(V0)
    ;   ValueOpt = none, Opts1 = Opts0
    ),
    (   selectchk(max(M0), Opts1, Opts2)
    ->  Max = M0
    ;   Max = 100, Opts2 = Opts1
    ),
    Rest = Opts2.

%!  is_determinate(+ValueOpt, +Max, -V) is semidet.
%
%   True, unifying V, iff ValueOpt = value(V), V and Max are numbers,
%   Max > 0, and 0 =< V =< Max -- Radix's `isValidValueNumber` guard.
is_determinate(value(V), Max, V) :-
    number(V),
    number(Max),
    Max > 0,
    V >= 0,
    V =< Max.

%!  progress_state(+ValueOpt, +Max, -State) is det.
%
%   State in indeterminate|complete|loading -- Radix's
%   `getProgressState`.
progress_state(ValueOpt, Max, State) :-
    (   is_determinate(ValueOpt, Max, V)
    ->  ( V =:= Max -> State = complete ; State = loading )
    ;   State = indeterminate
    ).

%!  value_label(+V, +Max, -Label) is det.
%
%   Radix's default `getValueLabel`: rounded percentage, e.g. "30%".
value_label(V, Max, Label) :-
    Pct is round((V / Max) * 100),
    format(string(Label), "~d%", [Pct]).

%!  merge_class(+Opts0, +Default, -ClassVal, -Rest) is det.
%
%   Pulls `class(C)` out of Opts0 if present and merges it after
%   Default ("px-progress C"); otherwise ClassVal = Default. Rest is
%   Opts0 minus the class(_) option.
merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C]),
        Rest = Opts1
    ;   ClassVal = Default, Rest = Opts0
    ).

		 /*******************************
		 *             PARTS            *
		 *******************************/

%!  progress_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `progress_root([value(30)], Kids)`.
px_template:render_helper(progress_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, Children)).

root_attrs(Opts0, Attrs) :-
    take_value_max(Opts0, ValueOpt, Max, Opts1),
    merge_class(Opts1, "px-progress", ClassVal, Opts2),
    progress_state(ValueOpt, Max, State),
    (   is_determinate(ValueOpt, Max, V)
    ->  value_label(V, Max, Label),
        NowAttrs = [aria_valuenow(V), aria_valuetext(Label)],
        ValueAttrs = [data_value(V)]
    ;   NowAttrs = [], ValueAttrs = []
    ),
    append([ [role(progressbar), aria_valuemax(Max), aria_valuemin(0)],
             NowAttrs,
             [data_state(State), class(ClassVal)],
             ValueAttrs,
             [data_max(Max)],
             Opts2
           ], Attrs).

%!  progress_indicator(+Opts) is det.
%
%   Bare-call template surface: `progress_indicator([value(30)])`. No
%   children -- Radix's Indicator never has any either; it is a plain
%   fill bar, its width entirely a function of `value`/`max` (see the
%   module header on why this port computes it server-side).
px_template:render_helper(progress_indicator(Opts), S) :-
    indicator_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, [])).

indicator_attrs(Opts0, Attrs) :-
    take_value_max(Opts0, ValueOpt, Max, Opts1),
    merge_class(Opts1, "px-progress-indicator", ClassVal, Opts2),
    progress_state(ValueOpt, Max, State),
    (   is_determinate(ValueOpt, Max, V)
    ->  Pct is round((V / Max) * 100),
        format(string(Style), "width: ~d%;", [Pct]),
        ValueAttrs = [data_value(V)],
        StyleAttrs = [style(Style)]
    ;   ValueAttrs = [], StyleAttrs = []
    ),
    append([ [data_state(State), class(ClassVal)],
             ValueAttrs,
             [data_max(Max)],
             StyleAttrs,
             Opts2
           ], Attrs).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  progress(+Opts) is det.
%
%   The common case: Root around one Indicator, both fed the same
%   value/max (Progress's only "context" dependency -- adr/0026's
%   analysis doc notes it is trivially replaced by passing the same
%   values to both part templates; there is no other shared state).
%   Opts as a whole -- including id(...)/class(...)/anything else --
%   goes to the Root; only value(_)/max(_) are forwarded to the
%   Indicator, so an id given for the bar as a whole does not get
%   duplicated onto its child.
progress(Opts) ~> \progress_render(Opts).

px_template:render_helper(progress_render(Opts), S) :-
    value_max_only(Opts, VM),
    px_template:render(S, progress_root(Opts, progress_indicator(VM))).

value_max_only(Opts, VM) :-
    findall(T, ( member(T, Opts), ( T = value(_) ; T = max(_) ) ), VM).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Progress is a Phase-1 "foundation" component (docs/radix-port-
%   analysis.md's porting order: AspectRatio, Label, Separator,
%   VisuallyHidden, AccessibleIcon, Progress) -- Order 6 leaves 1-5
%   free for its four static/presentational siblings to land with
%   lower numbers, whenever they do.
%
%   The registered call is `\progress_demo`, not the bare atom: px_ui
%   embeds it as the sole Children argument of a div (ui_show_view in
%   prolog/px_ui.pl), and a bare ATOM is always a text node in
%   px_template's dispatch (only compound terms resolve
%   element/template/helper -- adr/0019, same reason milestone10's
%   arity-0 demo templates are called via `\Goal`). `\progress_demo` is
%   itself the compound term render/2 already special-cases first,
%   so it renders through to the tmpl/2 clause below unmodified.
px_ui:demo(progress, 6, \progress_demo).

progress_demo ~>
    div(class("px-progress-demo"),
      [ div(class("px-progress-row"),
          [ p("30%"),
            progress([value(30), max(100), id("progress-demo-30")])
          ]),
        div(class("px-progress-row"),
          [ p("100% (complete)"),
            progress([value(100), max(100), id("progress-demo-complete")])
          ]),
        div(class("px-progress-row"),
          [ p("indeterminate (no value)"),
            progress([id("progress-demo-indeterminate")])
          ])
      ]).
