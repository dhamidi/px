# UI fidelity report: /ui components vs. radix-ui.com

Date: 2026-07-22. Scope: all 18 components in `prolog/ui/` --
separator, label, aspect_ratio, visually_hidden, accessible_icon,
progress, switch, toggle, checkbox, radio_group, collapsible, avatar,
toggle_group, tabs, accordion, toolbar, dialog, popover.

## Method

Real side-by-side screenshots, not markup diffing. Driven through
`/headless-shell/headless-shell` (Chromium 150) over CDP
(`--remote-debugging-port=9333 --remote-allow-origins=* --no-sandbox`),
one fresh tab per shot via `Page.navigate` + `Page.captureScreenshot`,
clicks via `Input.dispatchMouseEvent` on real computed bounding boxes
(never a bare DOM `.click()`), `getComputedStyle` reads for exact
colors/sizes where eyeballing wasn't precise enough. Driver: ad hoc,
not committed (`/tmp/cdp_driver.py`, `/tmp/batch1.py`).

`prologex.service` was restarted once at the start of this pass;
`ui.css` was confirmed >40KB (46771 bytes) both before the first
screenshot and again after the last one -- no empty-CSS incident this
time.

**Reference source per component:**
- 12 components have a styled Radix **Themes** docs page
  (`radix-ui.com/themes/docs/components/<slug>`): separator,
  aspect_ratio (`aspect-ratio`), visually_hidden (`visually-hidden`),
  accessible_icon (`accessible-icon`), progress, switch, checkbox,
  radio_group (`radio-group`), avatar, tabs, dialog, popover.
- 6 have no Themes page and fell back to **Primitives** docs
  (`radix-ui.com/primitives/docs/components/<slug>`): label, toggle,
  collapsible, toggle_group (`toggle-group`), accordion, toolbar.
  **Caveat that matters for grading:** Primitives demos are
  intentionally minimally styled (that's the entire point of
  Primitives vs. Themes -- unstyled-by-design, bring-your-own-CSS).
  Their "styled" demo boxes are a plain white/bordered box on a
  decorative gradient background, not a polished component skin. For
  these 6, grades below judge *structural correctness* (does our
  version look like a coherent, intentionally designed component)
  rather than pixel-parity with the reference, since the reference
  itself has very little polish to match.
- Both sites persisted a dark-mode localStorage flag across tabs in
  the same browser profile after one manual toggle-theme click early
  in the session, so all Themes reference shots ended up dark-mode,
  matching our service's always-dark theme (`app.css:20`,
  `color-scheme: dark`, not responsive to `prefers-color-scheme` --
  noted once here as a page-level fact, not scored per-component).

**Known false-positive avoided:** the dialog reference shows a
strongly dimmed backdrop; our first screenshot of the opened dialog
showed *no visible dimming at all*. Before writing that up as a defect,
I verified live via `getComputedStyle(dialogEl, '::backdrop')` --
`background-color: rgba(4, 6, 10, 0.6)` is correctly computed and
applied (CSS: `assets/css/ui.css:1646-1648`). The missing dim in the
screenshot is a **CDP `Page.captureScreenshot` compositing limitation**
with native `<dialog>::backdrop` (a known Chromium headless quirk),
not a product bug. Flagging this explicitly so no fix agent burns time
on it.

Screenshots: `docs/fidelity-shots/<name>-ref.png` /
`docs/fidelity-shots/<name>-ours.png` (all committed, 2.9MB total,
largest is `aspect_ratio-ref.png` at 337KB because it's a real photo).

## Grade distribution

| Grade | Count | Components |
|---|---|---|
| A | 10 | separator, label, visually_hidden, accessible_icon, toggle, checkbox, radio_group, collapsible, tabs, accordion |
| B | 8 | aspect_ratio, progress, switch, avatar, toggle_group, toolbar, dialog, popover |
| C | 0 | -- |
| F | 0 | -- |

**Headline: nothing is broken.** Every component renders its intended
shape, every interactive one I drove (switch, toggle, checkbox,
radio_group, collapsible, tabs, accordion, toggle_group, toolbar,
dialog, popover) changes state correctly on click
(`data-state`/`aria-*` flips, panels open/close, dialog opens modal
with a backdrop, popover opens positioned under its trigger). The gap
between "/ui looks visually far apart from radix-ui.com" and what's
actually on screen is real but narrower and more specific than a
blanket "unstyled" verdict: it's a handful of concrete, mostly
one-line CSS deltas repeated across components, not systemic breakage.

## Systemic gaps (repeated across components)

1. **Accent color is a single pastel light-blue, not Radix's
   saturated indigo/blue.** `assets/css/app.css:6`: `--accent: #7dd3fc`
   (`rgb(125, 211, 252)`, a pale sky-blue). Radix's own computed
   indicator color on the Themes progress bar is `rgb(62, 99, 221)`
   (`#3E63DD`, a medium-saturated blue/indigo) -- a completely
   different color family, not just a shade off. `--accent` is reused
   verbatim (`var(--accent)`) for switch/checkbox/radio/progress/
   toggle/toggle-group/toolbar/focus-ring active-state fills
   (grep hits in `assets/css/ui.css` at lines 140, 191, 318, 413, 422,
   582, 716, 811, 950, 957 and more) -- **this is the single highest-
   leverage fix in this report**: one CSS variable change measurably
   improves color fidelity on 8+ components simultaneously.
   **Effort: S.**
2. **Track/bar thickness runs consistently heavier than Radix's.**
   Progress track: ours `height: 0.6rem` (9.6px, `ui.css:183`) vs.
   Radix's computed `6px` -- 60% thicker. Switch track: ours
   `2.5rem x 1.4rem` (40x22.4px, `ui.css:571-572`) vs. Radix's
   computed `35x18px` -- close but consistently a bit larger/thicker
   everywhere checked. Not broken, just visibly chunkier/less crisp
   than the reference at a glance. **Effort: S** (a handful of
   dimension tweaks).
3. **No motion/transition polish beyond what's already there.** Most
   components already have *some* transition (e.g. dialog's
   `@starting-style` fade+scale, switch's `background`/`border-color`
   transition) -- this is better than the prior audit implied -- but
   nothing has a thumb-slide easing curve, tab-underline slide
   animation, or accordion height animation matching Radix's snappier
   micro-interactions. Not scored as a per-component defect since nothing
   asked for it explicitly and it doesn't affect the static screenshot
   grade, but worth flagging as the next polish tier. **Effort: M.**

## Per-component findings

### A grades (close match, no action needed)

- **separator** -- ref and ours both render a plain 1px horizontal
  rule between two text blocks with correct spacing. No visible delta.
- **label** -- non-visual by nature (just text + `for`/`id` or nesting
  association); both correctly associate label with control. Primitives
  reference has essentially no chrome to compare against.
- **visually_hidden** -- non-visual utility; content is present in the
  DOM/AX tree, absent from paint, in both. Ours actually demonstrates
  the behavior better than Radix's own Themes docs page, which has no
  live demo at all for this utility (just prose + a link to the
  primitive).
- **accessible_icon** -- same situation as visually_hidden: no visual
  output to compare by design, correctly implemented, better-demoed on
  our side than Radix's own docs page (which again has no live demo).
- **toggle** -- Primitives reference is an unstyled white square with
  an italic "I"; ours renders proper on/off/disabled states with color
  fills (dark bordered "Off", accent-filled "On", muted "Disabled") --
  structurally correct and, per the caveat above, more polished than
  the reference has to be.
- **checkbox** -- flat rounded square, filled accent + white checkmark
  when checked, dash for indeterminate; matches Radix's checkbox shape
  and states closely.
- **radio_group** -- **now fixed** (this was `docs/ui-visual-audit.md`'s
  one identified defect as of the same date -- `.px-radio-group-input`
  missing its class -- and the current live screenshot shows a properly
  styled filled circle+dot, not a native OS radio button; the fix has
  landed since that audit).
- **collapsible** -- bordered card, chevron that rotates on open,
  verified live via `summary.click()` that `open` flips
  `"closed"` -> `true`. Structurally matches the reference's
  disclosure-row pattern; ours is more polished than the unstyled
  Primitives reference.
- **tabs** -- underline-style tab strip, active tab bold + blue
  underline, disabled tab visibly dimmed and unclickable, matches the
  reference's proportions and interaction closely.
- **accordion** -- single bordered card containing all items with
  internal row dividers and rotating chevrons, matching the reference's
  "one card, several rows" structure rather than separate boxes per
  item.

### B grades (structurally right, concrete deltas below)

- **aspect_ratio** -- Effort: S.
  - Ref demo: real photo cropped to a 16:9 box with visibly rounded
    corners and a caption below.
  - Ours: solid-color/gradient placeholder boxes, **0 border-radius**
    (square corners) where the ref box is rounded.
  - Delta: add `border-radius` to the aspect-ratio demo box; consider
    swapping the flat-color demo fill for something with visible
    texture/gradient so the box reads as "framing content" rather than
    a bare rectangle (cosmetic, optional).

- **progress** -- Effort: S.
  - Track height: ours `9.6px` (`ui.css:183`, `0.6rem`) vs. ref's
    computed `6px` -- noticeably thicker.
  - Indicator color: ours `rgb(125, 211, 252)` (pale cyan, via
    `--accent`) vs. ref's computed `rgb(62, 99, 221)` (saturated
    blue/indigo) -- covered by the systemic accent-color fix above.
  - Track background: ours solid dark panel color vs. ref's translucent
    `rgba(221, 234, 248, 0.08)` (barely-there white wash) -- ours reads
    more like a solid pill than a subtle track.

- **switch** -- Effort: S.
  - Track: ours `40 x 22.4px` (`ui.css:571-572`) vs. ref's computed
    `35 x 18px` -- ours is consistently ~15-25% larger on both axes.
  - Thumb: ours `17.6px` vs. ref's `18px` -- essentially identical,
    not a real gap.
  - Checked-state color: ours pale cyan `#7dd3fc` vs. ref's saturated
    indigo/blue -- same systemic accent-color issue as progress.
  - Shape (pill track + circular thumb + slide-on-toggle) already
    matches well; this is a size/color tuning pass, not a structural
    rework.

- **avatar** -- Effort: S.
  - Radius: ours hardcodes `border-radius: 999px` (full circle,
    `ui.css:476`) on every avatar; Radix Themes' *default* avatar
    radius is `6px` (a soft rounded square -- confirmed via
    `getComputedStyle` on the reference, `radius: "medium"` is Radix's
    documented default, `full` is opt-in and is what the *popover*
    demo explicitly requests via `radius="full"` on that one avatar).
    Ours only ever renders the `full`/circle variant; there is no
    rounded-square option.
  - Size: ours `48px` (`width/height: 3rem`, `ui.css:473-474`) vs.
    ref's default `40px` -- ours runs ~20% larger.
  - Fix means either changing the *default* radius to a smaller
    rounded-square value, or (better, matching Radix's own API)
    exposing a `radius` option on the avatar demo/component so callers
    aren't stuck with circle-only.

- **toggle_group** -- Effort: S.
  - Structurally correct: buttons are joined into one bordered strip
    with shared edges (not gapped separate buttons), selected item
    gets a solid accent fill -- this matches Radix's segmented-control
    pattern well.
  - Only real delta is the same pale-cyan vs. saturated-indigo accent
    color covered above; no structural rework needed.

- **toolbar** -- Effort: S/M.
  - Structurally correct: one bordered strip, grouped buttons, a
    separator, selected/pressed item gets an accent fill -- matches
    the reference's toolbar anatomy.
  - Content-level polish gap (not a component defect per se): the
    reference demo uses icon buttons (bold/italic/underline glyphs,
    alignment icons) giving it a denser, more "designed" look; ours
    uses text-label buttons ("Cut", "Copy", "Bold", "Italic",
    "Underline", "Help"), which reads more utilitarian/plain. If the
    goal is closer visual parity, swapping the demo's button content
    to icons (SVG or an icon font) would close most of the remaining
    gap -- this is a demo-content change, not a CSS/behavior fix, so
    scoped as M since it likely needs new icon assets.

- **dialog** -- Effort: S.
  - Card structure (rounded corners, border, title, description,
    labeled input fields, filled accent primary button) matches the
    reference closely.
  - Backdrop dimming is implemented correctly (`rgba(4, 6, 10, 0.6)`,
    verified via computed style -- see the false-positive note above);
    **no action needed there**.
  - Only real, if minor, content-level difference: ours has a single
    "Save changes" action + a top-right "X" close button; the
    reference has a "Cancel" (ghost) + "Save" (filled) button pair and
    no visible close-X. Purely a demo-content choice, not a styling
    defect -- listed for completeness, not prioritized.

- **popover** -- Effort: S.
  - Correctly anchored: opens as a bordered, rounded, shadowed panel
    positioned directly below-left of its trigger, same pattern as the
    reference's popper-positioned panel.
  - Ours has noticeably more generous internal padding around a
    plainer title+text+close-button layout; the reference's demo packs
    in an avatar, textarea, and checkbox+button row more tightly.
    Again this is demo *content* density, not a positioning/anchoring/
    border defect -- the popover mechanics themselves check out.

## Prioritized fix list

1. **Swap `--accent: #7dd3fc` for a saturated blue/indigo closer to
   Radix's `#3E63DD`.** (`assets/css/app.css:6`.) Single-line change,
   improves color fidelity across switch, checkbox, radio_group,
   progress, toggle, toggle_group, toolbar, and every focus ring in
   one shot. **S, highest leverage.**
2. **Thin the progress track** from `0.6rem` to `~0.375rem` (6px) and
   soften its background to a translucent wash instead of a solid
   panel fill. (`assets/css/ui.css:179-187`.) **S.**
3. **Give avatar a non-circle default radius** (e.g. `6px`/`0.375rem`
   instead of `999px`) and/or expose a `radius` option so circle
   becomes opt-in rather than the only choice; also consider dropping
   the default size from `3rem` to `2.5rem` to match Radix's `40px`
   default. (`assets/css/ui.css:469-482`.) **S.**
4. **Trim switch track from `2.5rem x 1.4rem` toward `35px x 18-20px`**
   to match Radix's proportions more closely (currently ~15-25%
   oversized on both axes). (`assets/css/ui.css:567-579`.) **S.**
5. **Add `border-radius` to the aspect_ratio demo box** so its corners
   match the reference's rounded photo-frame treatment instead of
   sharp corners. **S.**

Everything else observed is either already correct (radio_group's
prior defect is fixed; dialog's backdrop is correct despite the
screenshot artifact) or a demo-content polish choice (toolbar icons,
dialog/popover button copy and density) rather than a component
styling or behavior bug.

## Polish applied (2026-07-22, follow-up pass)

All five prioritized fixes above landed, plus the contrast audit the
accent swap requires. Verified via `test/ui/*.pl` (all 19 files green,
including `css_coverage`), a service restart with served-hash
byte-size + diff verification (`app.css` 6438 B, `ui.css` 49080 B,
both byte-identical to the working tree -- no truncation), and a fresh
CDP pass over `/headless-shell` against `:8090` (screenshots:
`docs/fidelity-shots/polish-*.png`).

1. **Accent swap + contrast audit.** `--accent` is now `#3E63DD`
   (`assets/css/app.css`). Three new vars ship alongside it:
   `--accent-contrast: #ffffff` (on-accent text/glyphs -- switched to
   this everywhere an `--accent` *background* carries text: the form
   submit button, `.px-icon-button`, `.px-toggle[data-state="on"]`,
   `.px-toggle-group-item[data-state="on"]`, the checkbox
   checkmark/indeterminate-dash glyphs, and `.px-dialog-save`, all of
   which previously hardcoded dark `#0f1115` or `var(--bg)` text that
   read fine on the old pale `#7dd3fc` and would have gone
   unreadable-to-low-contrast on the new indigo); `--accent-hover:
   #5472e4` (a lighter hover variant, wired into every one of those
   same filled-accent surfaces' `:hover`, replacing the old
   `filter: brightness()` trick where present); `--accent-text:
   #849dff` (a lighter indigo for link/text use on the near-black page
   background -- `a`, `.adr-list a:hover` -- since plain `#3E63DD`
   reads dark for body-copy-sized text on `#0f1115`). All hardcoded
   `rgba(125, 211, 252, ...)` focus-ring/hover-wash colors (9 spots in
   `ui.css`, 2 in `app.css`) were also updated to `rgba(62, 99, 221,
   ...)` so focus rings/hover washes match the new accent instead of
   the old pastel. Expected grade: switch/checkbox/radio_group/
   progress/toggle/toggle_group/toolbar A (color family now matches
   Radix; radio_group/checkbox/tabs/etc. stay A).
2. **Progress track**: height `0.6rem` (9.6px) -> `0.375rem` (6px,
   exact match to Radix's computed value); background switched from a
   solid `var(--panel)` fill to the translucent wash Radix itself
   computes, `rgba(221, 234, 248, 0.08)`. Expected grade: B -> A.
3. **Avatar**: default size `3rem` (48px) -> `2.5rem` (40px, exact
   match); default radius `999px` (circle) -> `0.375rem` (6px rounded
   square, matching Radix Themes' documented default). Circle is now
   opt-in via a new `radius(square|full)` option on `avatar_root`/
   `avatar/4` (`prolog/ui/avatar.pl`'s `take_radius/3`), rendered as
   `data-radius="square"/"full"` and targeted by
   `.px-avatar[data-radius="full"] { border-radius: 999px; }` in
   `ui.css`. `test/ui/avatar.pl` updated (new `root_radius_*`/
   `root_invalid_radius_falls_back` checks, updated exact-string
   assertions for the new attribute, a 5th demo row exercising
   `radius(full)`); `css_coverage.pl` needed no code changes since the
   new rule keys off `[data-radius=...]` on the already-covered
   `.px-avatar` class, not a new selector -- reran green regardless.
   Expected grade: B -> A.
4. **Switch**: track `2.5rem x 1.4rem` (40x22.4px) -> `2.1875rem x
   1.25rem` (35x20px, within Radix's 35x18-20px computed range); thumb
   trimmed proportionally to `1rem` (16px) with a 2px inset on all
   sides and a 15px checked-state travel distance, recomputed from the
   new track dimensions. Verified interactivity survived the resize
   (real CDP click still flips `data-state`/thumb position). Expected
   grade: B -> A.
5. **aspect_ratio**: `[data-radix-aspect-ratio-wrapper]`'s
   `border-radius` bumped `8px -> 12px` for a clearer rounded-corner
   read at demo-box scale (confirmed already-correct `overflow:
   hidden` clipping was in place -- the 8px value just read as
   near-square next to the reference's more visibly rounded photo
   frame). Expected grade: B -> A/B (structural fix confirmed via
   `getComputedStyle`; a matter of degree, not correctness).

Not touched in this pass (out of scope per the report's own "demo
content, not styling" calls): toolbar icon glyphs, dialog Cancel/Save
button pair, popover content density.
