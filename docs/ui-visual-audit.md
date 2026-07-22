# UI visual audit: why /ui does not match Radix

Date: 2026-07-22. Scope: the ten components named in the diagnostic
mission -- switch, toggle, checkbox, radio_group, progress, tabs,
accordion, toggle_group, toolbar, avatar -- served live by the
systemd-managed `swipl apps/adr_site.pl` process on `127.0.0.1:8090`.

## Method

Driven entirely through `/headless-shell/headless-shell` (Chromium
150) over CDP -- no `curl`/markup-only checks. For each component:
`Page.navigate` to `/ui/<name>`, `Page.captureScreenshot` (saved to
`docs/audit-shots/`), `Runtime.evaluate` for `customElements.get(...)`,
computed styles on the actual interactive element, console/exception
capture via `Runtime.consoleAPICalled` / `Runtime.exceptionThrown` /
`Log.entryAdded` hooked before navigation, then `Input.dispatchMouseEvent`
on the real control with a before/after screenshot and a before/after
read of `data-state`/`aria-*`. Browser launched with
`--remote-allow-origins=*` (the CDP websocket handshake otherwise
403s from a same-origin Python client) and `--no-sandbox` (required
in this VM). Driver scripts: ad hoc, not committed (`/tmp/run_audit.py`,
`/tmp/radio_recheck.py`, `/tmp/recheck2.py`).

Additionally, a static cross-check: every `.px-*` class selector in
`assets/css/ui.css` (51 unique) was regex-extracted and checked for
at least one occurrence in the concatenated rendered HTML of all
`/ui/<name>` pages (plus a few not in-scope) -- catching any selector
that can structurally never match anything the server emits.

## Result up front

**Nine of the ten components are correctly styled and interactive in
the live service.** The mission brief's headline symptom --
`switch` "renders as a plain native checkbox instead of a styled
pill-slider" -- **does not reproduce**: `/ui/switch`, screenshotted
fresh from a real Chromium instance, is an accent-blue pill with a
sliding thumb, and clicking it (via synthetic `Input.dispatchMouseEvent`,
not just DOM `.click()`) flips both the visual thumb position and the
`data-state`/`aria-checked` attributes in the same tick. The one
component that **does** show the exact "unstyled native control"
symptom is **`radio_group`** -- and it is a genuine, isolated,
single-line-fix defect, evidenced below.

## Per-component findings

### switch -- STYLED, INTERACTIVE. No defect found.
`customElements.get('px-switch')` → defined. Zero console
errors/exceptions. Computed style on `.px-switch-trigger` (the real
`<input type=checkbox role=switch>`): `opacity: 0`, `position:
absolute` (intentionally invisible -- it's the click target, not the
visible paint); the visible track is the sibling `<label
class="px-switch">` (`position: relative`, pill `border-radius:
999px`) and the thumb is `.px-switch-thumb` (`position: absolute`,
circular). Before click: `data-state="unchecked"`,
`aria-checked="false"`. After a real synthetic click on the input:
`data-state="checked"`, `aria-checked="true"`, thumb visibly slid
right, track visibly turned accent-blue.
Screenshots: `docs/audit-shots/switch-before.png`,
`docs/audit-shots/switch-after.png` (row 1 pill visibly flips
off→on; row 2 pre-checked pill unaffected).

### toggle -- STYLED, INTERACTIVE. No defect found.
`customElements.get('px-toggle')` → defined, no console errors. The
button renders with real padding/border (not a bare `<button>`);
`data-state` flips `off`→`on` and the fill turns accent-blue on click,
confirmed via `Input.dispatchMouseEvent` + before/after
`getAttribute('data-state')`. Screenshots:
`docs/audit-shots/toggle-before.png` / `toggle-after.png` (top row
button visibly re-colors).

### checkbox -- STYLED, INTERACTIVE. No defect found.
`.px-checkbox-input` computed `appearance: none` (confirmed via
`getComputedStyle`, not just reading the CSS source) -- the class the
CSS depends on is present in the rendered `<input class="px-checkbox-input">`.
18x18px custom box with an `::after`-drawn checkmark, indeterminate
dash rendered correctly. No console errors.

### radio_group -- **UNSTYLED NATIVE CONTROL. Root cause identified.**
This is the one real defect, and it is exactly the failure mode the
mission suspected switch of having. Screenshot
`docs/audit-shots/radio_group-before.png` shows three plain OS-native
radio buttons (visible blue radial-gradient native rendering, not any
custom paint) -- compare to every other component's crisp flat/pill
styling.

**Evidence chain:**
1. Rendered markup (`curl -s http://127.0.0.1:8090/ui/radio_group`):
   `<input type="radio" name="px-radio-group-3" value="default" checked>`
   -- **no `class` attribute at all** on the `<input>`.
2. `assets/css/ui.css:695` styles `.px-radio-group-input` (`appearance:
   none; ...; border-radius: 999px; ...`) -- a selector that requires
   that class.
3. `getComputedStyle()` on the live input confirms the CSS never
   matches: `appearance: auto`, `-webkit-appearance: auto` (the
   browser's native default, not the CSS's `none`), `13px × 13px`
   native size (not the CSS's `1.1rem`), `input.className === ""`.
4. Source: `prolog/ui/radio_group.pl:256-268`, `item_attrs/3`, builds
   `InputAttrs` as
   `[type(radio), name(N), value(V)], CheckedAttrs, DisInAttrs, Extra`
   -- **`class("px-radio-group-input")` is never added**, unlike every
   sibling component in the library, which all put a class on the
   actual interactive element (`.px-switch-trigger`,
   `.px-checkbox-input`, `.px-toggle-group-item`, `.px-toolbar-button`,
   ...). `radio_group`'s own Item wrapper (`<label
   class="px-radio-group-item">`) gets a class; the `<input>` inside
   it does not.
5. **The render test enshrines the bug as correct.**
   `test/ui/radio_group.pl:153` asserts the exact string
   `<input type="radio" name="g" value="v1" checked>` (again, no
   class) as the expected output of `radio_group_item/2` -- so
   adr/0026 rule 7(a)'s "proof" step passes cleanly *because* it was
   written against the actual (buggy) output rather than against the
   CSS contract the same PR's own `assets/css/ui.css` changes assume.
6. Interaction is also broken, independent of the paint issue: after
   a real click (`docs/audit-shots/radio_group-after.png`), the
   native `input.checked` flips fine (browser radio semantics, free),
   but the wrapping `<label>`'s `data-state` attribute stays
   `"unchecked"` -- confirmed via
   `label.getAttribute('data-state') === 'unchecked'` post-click. The
   component's own module header (`prolog/ui/radio_group.pl` docstring)
   acknowledges this staleness as an accepted tradeoff *conditioned on*
   `:checked` doing the real visual work instead -- but `:checked`
   never fires visually either, because (per #3) the selector that
   would use it never matches. The documented fallback plan and the
   actual CSS selector do not agree with each other.

**Repair classification: recipe gap -- the fix itself is a one-line
Prolog change** (add `class("px-radio-group-input")` -- possibly
merged with any caller-supplied class, same pattern as every other
component's `merge_class`/`class_opt` helper -- to `InputAttrs` in
`item_attrs/3`), **but the process gap is what let it ship**: the
render test was authored to match the code instead of the contract,
and adr/0026 rule 7(b)'s "the reviewer's acceptance bar is the demo
page looking and behaving right" was evidently never actually
exercised with eyes (or a screenshot) on `/ui/radio_group` -- three
native OS radio buttons next to prose that says "type=\"radio\">
grouped by name" is not subtle in a real browser.

### progress -- STYLED (STATIC, no JS). No defect found.
No `px-progress` custom element (correct -- STATIC per the analysis
doc, confirmed no `assets/js/components/progress.js` exists and none
is expected). Rounded track/fill bars visible with correct
percentages (30%, 100%, indeterminate track empty with its own
`@keyframes` animation class present in CSS). `docs/audit-shots/progress-before.png`.

### tabs -- STYLED, INTERACTIVE. No defect found.
`customElements.get('px-tabs')` → defined, no console errors.
Underline-style tablist renders correctly. Verified a **real state
change**, not just an already-active element: clicked the
*Notifications* tab (initially `data-state="inactive"`,
`aria-selected="false"`) and confirmed post-click
`data-state="active"`, `aria-selected="true"`, underline visibly
moved and panel content switched.
Screenshots: `docs/audit-shots/tabs-before.png` /
`docs/audit-shots/tabs-after.png`.
(Note: an earlier pass clicked the already-active first tab, which
produced a byte-identical before/after pair and would have been a
false "looks unresponsive" reading -- the recipe-hardening section
below calls this out explicitly.)

### accordion -- STYLED, INTERACTIVE. No defect found.
`customElements.get('px-accordion')` → defined, no console errors.
Native `<details>`/`<summary>` styled as bordered/rounded cards with a
chevron. Clicked the open item's trigger: `data-state` flipped
`open`→`closed`, `<details open>` attribute removed, chevron rotation
CSS class updated. `docs/audit-shots/accordion-before.png` /
`accordion-after.png`.

### toggle_group -- STYLED, INTERACTIVE. No defect found.
`customElements.get('px-toggle-group')` → defined, no console errors.
Joined-button strip renders correctly (`Left | Center | Right`).
Verified real `type=single` exclusivity: clicked *Center* (initially
`data-state="off"`, sibling *Left* `"on"`) and confirmed after click
*Center* → `"on"`, *Left* → `"off"` -- single-select roving behavior
genuinely works, not just cosmetic.
Screenshots: `docs/audit-shots/toggle_group-before.png` /
`toggle_group-after.png`.

### toolbar -- STYLED, INTERACTIVE. No defect found.
`customElements.get('px-toolbar')` → defined, no console errors.
Buttons + embedded toggle group render as one continuous strip.
Verified the toolbar's embedded `type=multiple` toggle group: clicked
*Italic* (initially `data-state="off"`, *Bold* pre-pressed `"on"`),
confirmed after click both *Bold* and *Italic* are `"on"`
(independent toggling, not exclusive) -- matches the demo's own
documented `role="toolbar"` semantics.
Screenshots: `docs/audit-shots/toolbar-before.png` /
`toolbar-after.png`.

### avatar -- STYLED. No defect found; two console 404s are an
intentional demo fixture, not a bug.
`customElements.get('px-avatar')` → defined. Two
`Failed to load resource: 404` console entries were captured --
traced to `<img src="/assets/does-not-exist.png">`, which the demo
template deliberately uses twice (`prolog/ui/avatar.pl`'s "Broken
src" and "Broken src + delay_ms(600)" rows) to exercise the
fallback-on-error path. `getComputedStyle`/DOM check confirms the
fallback (`AL`/`BS`/`DL`/`FB` initials) is what actually paints, and
`data-state` correctly reads `"loaded"` for the one row with a real
(base64 data-URI) image. Not a defect -- flagged here only because
the mission asked for every console error found.
`docs/audit-shots/avatar-before.png`.

## Systemic checks (ruled out, with evidence)

The mission listed several "likely culprit classes" to confirm or
refute. All were checked directly; none reproduce:

- **Stylesheet compiled but selectors don't hide/replace native
  widgets** -- true for exactly one component (`radio_group`, see
  above), false for the other nine. `appearance: none` is present and
  *computed* (not just source) on `.px-switch-trigger`,
  `.px-checkbox-input` — confirmed live.
- **Custom elements failing to load (importmap path wrong, module
  error)** -- refuted. Every page's `<script type=importmap>` lists
  all eleven expected bare specifiers
  (`app`, `turbo`, `lib/roving-focus`, and all eight
  `components/<name>` entries) resolving to the correct
  content-hashed `/assets/...` URLs, matching
  `public/assets/.manifest.json` exactly. `customElements.get(...)`
  returned a defined constructor for every component that is supposed
  to have one, on every page tested.
- **CSS keyed to `[data-state]` that never updates because JS didn't
  run** -- refuted for switch/toggle/checkbox/tabs/accordion/
  toggle_group/toolbar (all verified live via a real synthetic click,
  not just reading the initial server-rendered HTML). This *is* the
  failure mode for `radio_group`, but for a different underlying
  reason (missing class defeats the paint entirely; the `data-state`
  staleness on click is a secondary, separately-documented,
  accepted tradeoff in that component's own design that only matters
  because the primary `:checked`-based fallback also silently never
  fires).
- **Stale hashed asset files (manifest vs. source mtimes)** --
  refuted. `compile_assets/0` runs at server start
  (`prolog/prologex.pl:148`); every `public/assets/*` file's mtime is
  newer than its `assets/` source; `diff` between `assets/css/ui.css`
  and the currently-served `public/assets/ui-f5211ed2214e.css` is
  empty (byte-identical); `.manifest.json` hashes match the actual
  served files (spot-checked via repeated `curl -D-` -- consistent
  `200`/no drift across three consecutive requests, `config/app.pl`'s
  2 workers included).
- **One bad ES module import poisoning the whole `app.js` chain** --
  refuted. Zero `Runtime.exceptionThrown` events and zero
  `Failed to load resource` console entries for any JS/CSS asset
  across all ten pages (only the two *intentional* broken-`<img>`
  404s on the avatar page, which are unrelated to the module chain).
  Every component after `switch`/`checkbox` in `app.js`'s import order
  (`toggle_group`, `tabs`, `accordion`, `toolbar` -- the later,
  more dependency-laden imports) registered its custom element fine,
  which would not happen if an earlier import in the chain had thrown.

## Ranked summary

### Systemic root causes (would affect many/all components)
**None found.** The asset pipeline, importmap wiring, and JS module
chain are all healthy for every component checked. This is worth
stating plainly because the mission brief's framing (and the specific
symptom named for `switch`) strongly implied a systemic cause; the
real-browser evidence does not support one. If the reporter's browser
session showed a broken `switch`, the likely explanations are a stale
browser cache pinned to an older `ui.css`/`switch.js` hash from before
a since-landed fix, or a build predating the current commit -- not
anything currently wrong with the live `127.0.0.1:8090` service as
audited here.

### Per-component defects
1. **`radio_group`** (real, confirmed, isolated) -- `.px-radio-group-input`
   CSS rule can never match because `prolog/ui/radio_group.pl`'s
   `item_attrs/3` never emits that class on the `<input>`. Verified
   as the *only* orphaned `.px-*` selector across all 51 in
   `assets/css/ui.css` (regex-extracted and cross-checked against the
   concatenated rendered HTML of every `/ui/<name>` page) -- i.e.
   this is not a pattern repeated elsewhere, just missed once.
   **Repair classification: recipe gap** (one-line template fix, but
   shipped past both the render-test proof and the demo-page-review
   bar rule 7 requires).

No other per-component defects found in this pass.

## Recommendations: what adr/0026 must additionally REQUIRE

1. **A screenshot-verified interaction step is not optional and must
   assert observable *change*, not just presence.** Rule 7(b) currently
   says "the reviewer's acceptance bar is the demo page looking and
   behaving right" but specifies no artifact and no process — that's
   exactly how `radio_group` shipped unnoticed. Require, per component:
   a screenshot of the demo page at merge time, PLUS a driven
   interaction (real `Input.dispatchMouseEvent`/keyboard event through
   CDP or equivalent, not a bare DOM `.click()`, since the latter can
   mask real pointer/focus-path bugs) that reads `data-state`/`aria-*`
   *before* and *after*, asserting they differ where the component's
   own contract says they should. This audit's own first pass shows
   the trap concretely: clicking the tabs demo's *already-active*
   first tab produced a byte-identical before/after screenshot that
   would have read as "looks unresponsive" — the check must target an
   element whose state is expected to *change*, and assert the delta,
   not just "no crash."
2. **The render test must be written against the CSS contract, not
   reverse-engineered from the implementation.** `radio_group`'s test
   passed because it asserted exactly what the (buggy) code produced.
   Require: whenever a component's CSS file introduces a new class
   selector on a specific anatomy part, the corresponding render test
   must assert that class's presence on that part by name (not just
   snapshot the whole string) — makes the omission fail loudly instead
   of being silently absorbed into the "expected" fixture.
3. **Add the static cross-check this audit ran by hand as a
   permanent, automated CI/test-suite step**: every `.px-*` (or
   equivalent) selector in `assets/css/ui.css` must appear at least
   once in the rendered output of *some* demo page. This is a cheap,
   mechanical, whole-library net that would have caught `radio_group`
   in seconds without needing a browser at all, and catches the same
   defect class (CSS written for a hook the template never emits) for
   any future component.
4. **Component modules that deviate from the library's own established
   convention should be flagged, not just documented in prose.**
   Every other component in this library puts a styling class directly
   on its actual interactive element (`.px-switch-trigger`,
   `.px-checkbox-input`, `.px-toggle-group-item`...); `radio_group` is
   the only one that doesn't, and its own module header spends several
   paragraphs explaining why that's supposedly fine (native `:checked`
   coverage) — but the CSS file *itself* was written assuming the
   convention held anyway. When a component's design doc explicitly
   claims a deviation from the library's own pattern, rule 7's review
   should require a reviewer (or agent) to specifically re-verify the
   claimed deviation still holds after the CSS is written, since CSS
   and Prolog module are authored/reviewed somewhat independently and
   can drift apart exactly like this.
5. **Verify in a real browser, every time, not just via
   `render_to_string`/curl.** This mission's instructions to distrust
   curl/markup were correct in spirit but, empirically, curl/markup
   *would* have caught this specific bug too (the missing `class=`
   attribute is visible in raw HTML) — the actual gap was that nobody
   looked. The stronger version of this recommendation is #1 above:
   require the artifact to exist and be checked, not just require the
   right tool.

## Files referenced

- `prolog/ui/radio_group.pl:256-268` (`item_attrs/3` -- the bug)
- `assets/css/ui.css:695-737` (`.px-radio-group-input` rules that can
  never match)
- `test/ui/radio_group.pl:150-154` (render test that enshrines the bug)
- `assets/js/components/switch.js`, `prolog/ui/switch.pl`,
  `assets/css/ui.css:563-621` (switch -- verified correct)
- `prolog/px_assets.pl` (asset pipeline -- verified fresh/correct)
- `apps/adr_site.pl:87-96` (`layout/2` -- confirms `ui.css` +
  importmap are linked on every `/ui/*` page)
- `docs/audit-shots/*.png` (screenshots referenced throughout)
