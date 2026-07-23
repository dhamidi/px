# Mobile baseline verification (adr/0028)

Viewport: 390×844 (deviceScaleFactor 2, mobile), driven over CDP
against the running app; screenshots in this directory.

## What changed

- `assets/css/app.css` — mobile-first rewrite of the base styles:
  viewport-relative heading sizes via clamp(), tighter page/form
  padding below 640px, `overflow-wrap: anywhere` on headings and the
  ADR slug list, full-width submit buttons below 480px, taller list
  rows and `text-size-adjust: 100%` under `(pointer: coarse)`.
- `assets/css/ui.css` — one appended section, two media blocks:
  - `@media (pointer: coarse)`: ≥44px effective touch targets for
    menu/select items, tab and accordion/collapsible triggers,
    toolbar/toggle buttons, nav-menu rows; checkbox/radio/switch grow
    an invisible hit area while the painted glyph stays desktop-sized
    (switch via an `inset: -12px -6px` pseudo-element on its label).
  - `@media (max-width: 480px)`: popover/dropdown/context/menubar/
    select/hover-card/tooltip/nav-menu content clamped to
    `calc(100vw - 2rem)`; nav-menu link grid single-column; toolbar
    wraps. Dialog, alert-dialog and toast already met adr/0028
    decision 4 and were left untouched.

## Verification matrix

- **No horizontal overflow** (`scrollWidth <= visualViewport.width`)
  on all 32 `/ui/<name>` demos and the content pages `/`,
  `/adr/:id`, `/comments`, `/ui`. Two real overflows found and
  fixed: toolbar (489px, non-wrapping row) and navigation_menu
  (509px, closed flyouts still contributing layout width — collapsed
  via `max-width: 0` when `data-state` ≠ open).
- **Touch targets**: with touch emulation flipping
  `(pointer: coarse)`, `getBoundingClientRect()` confirms ≥44px on
  menu item, tab trigger, accordion header, checkbox/radio/toolbar/
  toggle/toggle-group/select item; switch hit area confirmed via
  computed pseudo-element style + `elementFromPoint` sweep.
- **Overlays open at phone width**: dialog, alert_dialog, popover,
  dropdown_menu, context_menu, select, hover_card, toast, tooltip,
  navigation_menu, menubar each opened via dispatched input and
  screenshotted (`<name>-390.png`) — content fits with a visible
  inset.
- `test/ui/css_coverage.pl` green (186 selectors, 0 orphaned); all
  `test/ui/*.pl` render suites pass.

## Known limitations (need JS/template work, out of scope here)

1. **navigation_menu**: `.px-navigation-menu-content` positions with
   plain `position: absolute` (popper.js wiring was a documented
   scope cut in `prolog/ui/navigation_menu.pl`); a trigger far from
   the left edge can still push its flyout past the viewport.
2. **context_menu**: `lib/popper.js` implements flip but not shift
   for the virtual-anchor-at-tap-point case; a tap near the exact
   horizontal center can overflow by ~31px. (Also: headless-shell
   paints its own native context menu over screenshots of this demo
   — tooling artifact; verification used DOM rects.)

Measurement note: after an overflow, headless Chrome reports
`window.innerWidth` equal to the overflowing content width;
`window.visualViewport.width` stays pinned at 390 and is what the
checks use.
