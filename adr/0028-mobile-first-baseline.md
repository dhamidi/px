# 0028. Mobile out of the box

Status: Accepted

## Context

The pages this framework produced looked broken on phones — not
because the CSS was desktop-only, but mostly because no layout
emitted a viewport meta tag, so mobile browsers rendered a 980px
virtual viewport and scaled it down: tiny text, tiny controls, and
component CSS whose media assumptions never applied. Fixing that one
tag exposed the second tier of problems: paddings and type sized for
a desk, overlay components (dialogs, menus, popovers) that position
as floating cards even when the screen is barely wider than the card,
and touch targets sized for a mouse.

Rails leaves responsiveness entirely to the app. We do not want that:
px_ui is a *framework-level* component library (adr/0026), so "looks
right on a phone" is part of each component's contract, exactly like
its ARIA contract.

## Decision

1. **The viewport tag is the framework's job.** The default layout
   (adr/0027 decision 5) emits
   `<meta name="viewport" content="width=device-width, initial-scale=1">`;
   the app-layout convention documents it as mandatory. A prologex
   page can not be shipped without one short of deliberately writing
   a layout that omits it.

2. **Base styles are mobile-first.** `assets/css/app.css` styles the
   narrow screen as the default and widens under `min-width` queries
   — never the reverse. Concretely: fluid type via clamp() for
   headings, spacing that tightens below 480px, form controls and
   submit buttons full-width on narrow screens, `overflow-wrap:
   anywhere` on link lists that carry long monospace slugs,
   `text-size-adjust: 100%` so landscape rotation doesn't inflate
   text.

3. **Interactive components meet the 44px rule on coarse pointers.**
   A `@media (pointer: coarse)` block in ui.css raises effective
   target sizes (menu items, list-link rows, toggles, tab triggers)
   to ≥ 44 CSS px — Apple's HIG floor, matching Radix Themes' own
   size-3-on-touch behavior — without inflating the desktop design.

4. **Overlay components degrade to sheets, not scaled-down cards.**
   Below 480px: dialog and alert-dialog content spans the viewport
   width (minus a small inset) instead of a centered fixed-width
   card; popover/dropdown/context/select content clamps its
   `max-width` to the viewport minus padding; toasts span the bottom
   edge. Positioning JS (`lib/popper.js`) already clamps to the
   boundary padding — the CSS must not fight it with fixed widths.

5. **Proof, per adr/0026 rule 7 discipline:** every claim above is
   verified over CDP at a real phone viewport (390×844, the iPhone
   12-15 logical size) — screenshots of the content pages and the
   overlay components *open*, compared against the same flows at
   desktop width, plus `Runtime.evaluate` assertions that
   `document.documentElement.scrollWidth <= innerWidth` (no
   horizontal overflow) on every demo page.

## Consequences

Apps inherit a phone-usable baseline with zero configuration, and the
kitchen sink at /ui doubles as the mobile regression surface: the
no-horizontal-overflow check across all demos is cheap to re-run
after any component change. The cost is that component CSS now has
two pointer/viewport regimes to keep consistent; the css-coverage
guard and the CDP pass are what keep the second regime honest.
