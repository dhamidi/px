:- module(ui_accessible_icon, []).

%   No predicates are exported: accessible_icon_root/3 and
%   accessible_icon/3 are never called module-qualified -- they are
%   term SHAPES that px_template's bare-call dispatch resolves via the
%   multifile tmpl/2 database (adr/0019), the same convention every
%   other ui/*.pl module in this port follows. visually_hidden.pl is
%   use_module'd for its side effect only (registering its own tmpl/2
%   clauses, so `visually_hidden([], Label)` below resolves) -- it
%   exports nothing either, per its own header.

:- prolog_load_context(directory, Here),
   atomic_list_concat([Here, '/../px_template'], TemplateSpec),
   atomic_list_concat([Here, '/visually_hidden'], VisuallyHiddenSpec),
   use_module(TemplateSpec),
   use_module(VisuallyHiddenSpec).

:- multifile px_ui:demo/3.

/** <module> ui/accessible_icon -- Radix AccessibleIcon (adr/0026).

Anatomy: single part, Root. Takes exactly one icon term and gives it an
accessible name, the same job `alt` does on `<img>` -- for icons that
have no native text-alternative attribute (an inline SVG, a font-icon
span, ...). Dependency: visually-hidden (ui/visually_hidden.pl), per
the analysis doc.

DOM/ARIA contract (docs/radix-port-analysis.md "AccessibleIcon"):
clones `aria-hidden="true" focusable="false"` onto the icon, and
renders a visually-hidden sibling `<span>` holding the label TEXT (the
accessible name comes from text content, not `aria-label`). In React
this is a Fragment: Root introduces no DOM node of its own, it just
emits the (cloned) icon and the hidden label as two siblings wherever
it's placed. Zero JS: interactivity class STATIC, per the analysis doc.

**Deviation, noted per adr/0026 rule 2**: Radix clones the two
attributes directly onto whatever element the caller passed as a
child, via React's `cloneElement` -- an arbitrary-term prop-merge
operation. px_template has no equivalent generic "merge these
attributes onto an already-built term" primitive (that's `react-slot`'s
job upstream; the analysis doc flags it as "a genuinely reusable
pattern worth keeping ... if prologex ever needs it" -- not yet built).
This port instead wraps the icon term in a plain `<span
aria-hidden="true">`. `aria-hidden` is what actually matters to
assistive tech (a screen reader / AT skips the entire subtree under
it, same effect either way); `focusable="false"` is a legacy IE/old-
Edge-only SVG-specific fallback with no meaningful effect in a modern
browser and no non-SVG equivalent, so it is not forced onto the
wrapper -- a caller building a raw `<svg>` icon term is free to also
set `focusable="false"` on the `<svg>` tag itself for maximum fidelity
(the demo below does exactly that), belt-and-suspenders with the
wrapper's `aria-hidden`.

Templates: `accessible_icon_root(Opts, IconTerm, Label)` is the (only)
part; `accessible_icon(Opts, IconTerm, Label)` is the top-level
convenience (adr/0026 rule 1) -- identical to Root for a single-part
component. Opts is a list of extra attributes landing on the icon
wrapper span (there is no separate Root container to put them on,
matching Radix's own no-extra-DOM-node output).
*/

accessible_icon_root(Opts, IconTerm, Label) ~>
    [ span([aria_hidden(true) | Opts], IconTerm),
      visually_hidden([], Label)
    ].

accessible_icon(Opts, IconTerm, Label) ~>
    accessible_icon_root(Opts, IconTerm, Label).

           /*******************************
           *             DEMO             *
           *******************************/

%   /ui/accessible_icon (adr/0026 rule 7b). Same icon-button pattern as
%   the VisuallyHidden demo (ui/visually_hidden.pl) -- a checkmark icon
%   plus a hidden accessible-name label -- built with one call instead
%   of by hand, to show what AccessibleIcon buys over composing
%   VisuallyHidden directly.

px_ui:demo(accessible_icon, 2, \accessible_icon_demo).

accessible_icon_demo ~>
    [ p("AccessibleIcon packages the exact pattern from the \
VisuallyHidden demo -- aria-hidden icon plus a visually-hidden label \
-- as a single call: give it an icon term and a label string, get both \
nodes back."),
      button([type(button), class("px-icon-button")],
        accessible_icon([],
          raw("<svg viewBox=\"0 0 24 24\" width=\"16\" height=\"16\" focusable=\"false\"><path fill=\"currentColor\" d=\"M9.5 16.2 4.8 11.5 3.4 12.9l6.1 6.1L20.6 7.9l-1.4-1.4z\"/></svg>"),
          "Mark task as complete")),
      p("Same result, visible vs. screen reader, as the VisuallyHidden \
demo: sighted users see only the checkmark; a screen reader announces \
\"button, Mark task as complete\" from the hidden sibling span, while \
the icon's own subtree is aria-hidden and skipped entirely -- view \
source / devtools to see the wrapper span carrying aria-hidden=\"true\" \
around the <svg>.")
    ].
