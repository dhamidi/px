:- module(ui_separator, []).

:- use_module(library(lists)).
:- use_module('../px_template').

/** <module> ui/separator -- Radix Separator port (adr/0026).

Purpose: a visual/semantic divider, horizontal or vertical, optionally
decorative (docs/radix-port-analysis.md "Separator").

Anatomy: a single part, `Root` (`<div>`). **Interactivity class:
STATIC** -- every attribute is a pure conditional on `orientation`/
`decorative`, computable server-side; no client JS, ever.

Contract (adr/0026 rule 2 -- sacred):
  - `data-orientation="horizontal|vertical"` -- always emitted.
  - `decorative(true)`  -> `role="none"` ONLY; no `aria-orientation`
    at all, even when vertical (a decorative separator is dropped from
    the accessibility tree, so there is nothing to orient).
  - `decorative(false)` -> `role="separator"`, plus `aria-orientation`
    ONLY when vertical (horizontal is the ARIA default for
    `role="separator"`, so it is omitted there) -- matches upstream
    Radix's `Separator` exactly.

Opts (a list, adr/0026 rule 1) recognised by `separator_root/1,2`:
  - `orientation(horizontal|vertical)` -- default `horizontal`; an
    unrecognised value falls back to the default, same as upstream's
    `isValidOrientation` guard.
  - `decorative(true|false)` -- default `false`.
  - anything else passes through verbatim as an attribute on the root
    div (`id(...)`, `data_testid(...)`, ...); `class(...)` is merged
    with (not replaced by) this port's own default styling hook
    `px-separator` (adr/0026 rule 6 -- additive to, not part of, the
    ARIA/data contract above).

Implementation note: `separator_root/1,2` are registered as
`px_template:render_helper/2` clauses (the same mechanism px_form.pl's
`form_for/4` uses) rather than plain `~>` clauses, because the
Opts-list defaults/merge logic is genuine computation -- a `~>` body is
pure unification-built data (px_template.pl `expand_template/3`), so
conditional attribute-list construction cannot live there directly.
`separator/1,2`, the rule-1 top-level convenience template, IS a plain
`~>` (structural delegation only, no computation of its own).
*/

		 /*******************************
		 *        ATTRIBUTE LOGIC       *
		 *******************************/

%!  separator_attrs(+Opts, -Attrs) is det.
%
%   Opts -> the root div's attribute list, per the contract above.

separator_attrs(Opts, Attrs) :-
    must_be(list, Opts),
    orientation_opt(Opts, Orientation),
    decorative_opt(Opts, Decorative),
    class_opt(Opts, Class),
    exclude(reserved_opt, Opts, Extra),
    semantic_attrs(Decorative, Orientation, Semantic),
    append([class(Class), data_orientation(Orientation) | Semantic], Extra, Attrs).

orientation_opt(Opts, Orientation) :-
    (   memberchk(orientation(O), Opts),
        valid_orientation(O)
    ->  Orientation = O
    ;   Orientation = horizontal
    ).

valid_orientation(horizontal).
valid_orientation(vertical).

decorative_opt(Opts, Decorative) :-
    (   memberchk(decorative(D), Opts),
        ( D == true ; D == false )
    ->  Decorative = D
    ;   Decorative = false
    ).

%   The default class always applies; a user-supplied class(...) is
%   appended to it rather than overriding it, so the tasteful default
%   (adr/0026 rule 6) survives app customisation.
class_opt(Opts, Class) :-
    (   memberchk(class(UserClass), Opts)
    ->  format(atom(Class), 'px-separator ~w', [UserClass])
    ;   Class = 'px-separator'
    ).

%   Opts consumed above, or contract-owned output attributes -- never
%   duplicated into the pass-through tail.
reserved_opt(orientation(_)).
reserved_opt(decorative(_)).
reserved_opt(class(_)).
reserved_opt(role(_)).
reserved_opt(aria_orientation(_)).
reserved_opt(data_orientation(_)).

semantic_attrs(true, _, [role(none)]) :- !.
semantic_attrs(false, vertical, [role(separator), aria_orientation(vertical)]) :- !.
semantic_attrs(false, horizontal, [role(separator)]).

		 /*******************************
		 *          TEMPLATES           *
		 *******************************/

%   separator_root/1,2 -- the anatomy's one part, `Root`. Bare calls
%   (px_template's user-facing surface, adr/0019): no tmpl/2 clause
%   matches this head, so render/2's bare-compound dispatch falls
%   through to this render_helper/2 registration.
:- multifile px_template:render_helper/2.

px_template:render_helper(separator_root(Opts), S) :-
    px_template:render_helper(separator_root(Opts, []), S).
px_template:render_helper(separator_root(Opts, Children), S) :-
    separator_attrs(Opts, Attrs),
    px_template:render(S, div(Attrs, Children)).

%   separator/1,2 -- the rule-1 top-level convenience template:
%   Separator has no other parts to assemble, so this is pure
%   structural delegation to Root, expressible as an ordinary `~>`.
separator(Opts) ~>
    separator_root(Opts, []).
separator(Opts, Children) ~>
    separator_root(Opts, Children).

		 /*******************************
		 *         KITCHEN SINK          *
		 *******************************/

%   Registered with px_ui's kitchen-sink (adr/0026 rule 7b): appears
%   at /ui and renders at /ui/separator.
:- multifile px_ui:demo/3.
px_ui:demo(separator, 4, \separator_demo).

%   Arity-0, so it is an ATOM -- called via the explicit \ escape,
%   same as milestone10_templates.pl's demo templates (a bare atom is
%   a text node, not a callable dispatch, in render/2).
separator_demo ~>
    [ section(class('ui-demo-block'),
        [ h3("Horizontal (default)"),
          p("role=\"separator\", data-orientation=\"horizontal\", no aria-orientation (horizontal is the ARIA default so it is omitted)."),
          separator([]),
          p("Content below the divider.")
        ]),
      section(class('ui-demo-block'),
        [ h3("Vertical"),
          p("orientation(vertical) adds aria-orientation=\"vertical\" alongside role=\"separator\"."),
          div(class('ui-demo-row'),
            [ span("Blog"),
              separator([orientation(vertical)]),
              span("Docs"),
              separator([orientation(vertical)]),
              span("Source")
            ])
        ]),
      section(class('ui-demo-block'),
        [ h3("Decorative"),
          p("decorative(true) drops accessibility semantics entirely: role=\"none\", and no aria-orientation even though this one is vertical too -- for a divider that is purely visual, with something else already conveying the boundary to assistive tech."),
          div(class('ui-demo-row'),
            [ span("Item A"),
              separator([orientation(vertical), decorative(true)]),
              span("Item B")
            ])
        ])
    ].
