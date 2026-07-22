:- module(ui_visually_hidden, []).

%   No predicates are exported: visually_hidden_root/2 and
%   visually_hidden/2 are never called module-qualified -- they are
%   term SHAPES that px_template's bare-call dispatch resolves via the
%   multifile tmpl/2 database (adr/0019), the same convention every
%   other ui/*.pl module in this port follows (see e.g.
%   prolog/ui/progress.pl's header).

:- prolog_load_context(directory, Here),
   atomic_list_concat([Here, '/../px_template'], TemplateSpec),
   use_module(TemplateSpec).

:- multifile px_ui:demo/3.

/** <module> ui/visually_hidden -- Radix VisuallyHidden (adr/0026).

Anatomy: single part, Root (`<span>`). Purpose: the standard "sr-only"
technique -- content stays in the DOM and the accessibility tree but is
removed from visual layout, for an accessible name/description that
should be announced but never seen (a hidden label beside an icon-only
control, extra screen-reader-only context, ...). It must NOT be done
with `display:none`/`hidden` -- those remove a node from the
accessibility tree too, which defeats the purpose.

DOM/ARIA contract (docs/radix-port-analysis.md "VisuallyHidden"): none
-- no role, no aria-*; the whole component is a fixed visual-clipping
style applied to whatever markup the caller wraps. Radix ships that as
an inline `style` object (the Bootstrap-derived clip-rect technique:
absolute position, 1x1px box, negative margin, `clip: rect(0,0,0,0)`,
`overflow: hidden`, `white-space: nowrap`). This port keeps the exact
same technique but moves it into a CSS class, `.px-visually-hidden`
(assets/css/ui.css), per adr/0026 rule 6 ("styling ... using the app
theme vars", overridable by apps) -- there is no data-state to key off
here, so the class itself is the styling hook, same idea as Radix
consumers overriding the inline style via their own CSS specificity.
Zero JS: interactivity class STATIC, per the analysis doc.

Templates: `visually_hidden_root(Opts, Children)` is the (only) part;
`visually_hidden(Opts, Children)` is the top-level convenience (adr/0026
rule 1) -- identical to Root for a single-part component. Opts is a
list of extra attributes (id(...), data_*(...), ...) rendered alongside
the fixed class; it is NOT merged with a caller-supplied class(...) (two
class attributes would just mean "last one wins" in most browsers) --
not worth the complexity for the one consumer this has so far
(AccessibleIcon, below).
*/

visually_hidden_root(Opts, Children) ~>
    span([class("px-visually-hidden") | Opts], Children).

visually_hidden(Opts, Children) ~>
    visually_hidden_root(Opts, Children).

           /*******************************
           *             DEMO             *
           *******************************/

%   /ui/visually_hidden (adr/0026 rule 7b). Builds the icon-button
%   pattern "by hand" -- a decorative checkmark glyph plus a
%   visually-hidden text sibling supplying the accessible name --
%   which is exactly the pattern AccessibleIcon (ui/accessible_icon.pl)
%   packages as one call.

px_ui:demo(visually_hidden, 1, \visually_hidden_demo).

visually_hidden_demo ~>
    [ p("VisuallyHidden is the raw sr-only primitive: it clips its \
content out of the visual layout with CSS (the \".px-visually-hidden\" \
class below), while leaving it in place in the DOM and the \
accessibility tree -- unlike display:none/hidden, which remove a node \
from BOTH."),
      button([type(button), class("px-icon-button")],
        [ raw("<svg viewBox=\"0 0 24 24\" width=\"16\" height=\"16\" aria-hidden=\"true\" focusable=\"false\"><path fill=\"currentColor\" d=\"M9.5 16.2 4.8 11.5 3.4 12.9l6.1 6.1L20.6 7.9l-1.4-1.4z\"/></svg>"),
          visually_hidden([], "Mark task as complete")
        ]),
      p("Visible to a sighted user: a plain checkmark button, no \
visible text. To a screen reader: a button named \"Mark task as \
complete\" -- the accessible name comes from the hidden span's text \
content, which is read aloud but never rendered on screen. Inspect \
the button in devtools to see both nodes sitting side by side in the \
DOM.")
    ].
