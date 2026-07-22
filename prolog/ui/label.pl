:- module(ui_label, []).

:- use_module('../px_template').

/** <module> Radix Label port (adr/0026, docs/radix-port-analysis.md
    "Label" section).

Anatomy: a single part, `Root`, a native `<label>`. DOM/ARIA: none
beyond the native `for`/wrapping association -- there is no data-state,
no role, nothing Radix computes here beyond what `<label>` already
gives the accessibility tree for free.

Naming (deviation from adr/0026 rule 1, noted per that rule): the
recipe's convention is `<component>_<part>` templates plus a top-level
convenience template literally named `<component>(Opts, Parts)`. That
second half is impossible for Label: `label` is itself a whitelisted
HTML5 element functor (prolog/px_template.pl's html_element/1), and
expand_template/3 throws a permission_error rather than let a template
shadow an element name (bare calls resolve element-first, so
`label/2` could never be reached from a template body). Label has
exactly one anatomy part, so the part template doubles as the
convenience entry point: `label_root(Opts, Children)` is the only
template this module defines for the component itself.

Kept vs dropped (rule 3, platform first):

  - KEPT: native `<label for="Id">` / label-wraps-control association.
    Interactivity class STATIC (per the analysis doc) -- zero JS,
    zero custom element, zero assets/js/components/label.js.
    `label_root/2`'s Opts list is close to a raw HTML attribute list:
    `for(Id)` and any other native attribute (`id(...)`, `data_*(...)`,
    ...) pass straight through to the `<label>` tag; `class(C)` is
    special-cased and merged with the component's own `px-label` hook
    class rather than overwritten, so callers can add their own class
    without losing the CSS contract below.

  - DROPPED, replaced with CSS: Radix's Label ships one behavioral
    nicety implemented in JS -- an `onMouseDown` handler that calls
    `preventDefault()` on double/triple click (`event.detail > 1`)
    *unless* the mousedown target is already inside a nested form
    control, so rapid clicks on the label text don't select it instead
    of focusing/toggling the associated control. The analysis doc calls
    out the platform-first replacement directly: "the double-click-
    selection nicety is better solved with CSS `user-select: none` on
    the label ... than with a JS handler" -- that is what
    assets/css/ui.css's `.px-label` section does (`user-select: none`
    on the label, re-enabled on any nested form control so text
    *inside* a label-wrapped control still selects normally). No JS
    ships for this component at all: this module is the entire port.
*/

%!  label_root(+Opts, +Children) // bare call (px_template render_helper)
%
%   Opts: a list of native `<label>` attribute terms. `for(Id)` is the
%   Radix-anatomy association (label -> control by id); any other
%   attribute term (`id(...)`, `data_*(...)`, boolean atoms like
%   `hidden`, ...) passes straight through. `class(C)` is merged with
%   the fixed `px-label` hook class instead of replacing it, so the
%   CSS contract below always applies.
%
%   Registered as a px_template:render_helper/2 clause (same mechanism
%   px_form.pl's form_for/4 and ui/separator.pl's separator_root/2
%   use) rather than a plain `~>` clause, because the Opts-list
%   class-merge below is genuine computation -- a `~>` body is pure
%   unification-built data (px_template.pl's expand_template/3), so it
%   cannot branch on whether the caller supplied a class.

:- multifile px_template:render_helper/2.
px_template:render_helper(label_root(Opts, Children), S) :-
    label_attrs(Opts, Attrs),
    px_template:render(S, label(Attrs, Children)).

%!  label_attrs(+Opts, -Attrs) is det.
%
%   Attrs = [class(Merged)|Rest]: Rest is Opts with any class(_) term
%   removed, Merged is "px-label" alone, or "px-label <caller's
%   class>" when the caller supplied one -- additive, never
%   overwriting, so `.px-label`'s CSS contract always applies.

label_attrs(Opts, [class(Merged)|Rest]) :-
    (   selectchk(class(Caller), Opts, Rest)
    ->  format(string(Merged), "px-label ~w", [Caller])
    ;   Rest = Opts,
        Merged = "px-label"
    ).

                 /*******************************
                 *      KITCHEN-SINK DEMO        *
                 *******************************/

%   adr/0026 rule 7(b): registers at /ui/label. Two association
%   patterns, both native, both STATIC: `for`/`id` pointing at a
%   sibling control, and a label wrapping its control directly (no
%   `for` needed -- the wrapping itself is the association).

:- multifile px_ui:demo/3.
px_ui:demo(label, 3, \label_demo).

%   Arity-0, so it is an ATOM -- called via the explicit \ escape
%   above, same as every other component's demo template (a bare atom
%   is a text node, not a callable dispatch, in render/2).
label_demo ~>
    div(class("ui-demo-label"),
      [ p([ "Two native association patterns -- both zero-JS. Try ",
            "double/triple-clicking either label: text selection is ",
            "suppressed on the label itself (",
            code("user-select: none"),
            ") but still works normally inside the control."
          ]),
        div(class("field"),
          [ label_root([for("label-demo-email")], "Email address"),
            input([ type(email), id("label-demo-email"), name(email),
                    placeholder("you@example.com")
                  ])
          ]),
        div(class("field"),
          label_root([],
            [ "Subscribe to updates ",
              input([type(checkbox), name(subscribe)])
            ]))
      ]).
