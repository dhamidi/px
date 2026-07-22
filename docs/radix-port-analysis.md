# Radix Primitives → prologex: porting analysis

Status: research (no code ported)

## Scope and method

This document inventories every package in [radix-ui/primitives](https://github.com/radix-ui/primitives)
`packages/react/*` (cloned at `HEAD`, depth 1, 2026-07-22) as raw material for porting
Radix's semantic/ARIA anatomy to prologex: server-rendered `~>` templates
(adr/0019) emitting Radix's HTML/ARIA contract, with vanilla-JS custom
elements used *only* where behavior genuinely requires client-side state
(adr/0024's "no client JS unless the platform can't do it" philosophy,
extended from Turbo to general widget behavior).

The React source is the **behavioral spec**, not code to reuse — every
`useState`/`useEffect`/context-scoping mechanism here exists to solve a
React-only problem (hydration matching, ref composition, controlled/
uncontrolled prop duality, batching). None of that carries over. What
carries over is: the DOM structure, the ARIA roles/attributes, the
`data-state`/`data-*` styling hooks, and the keyboard/pointer state
machines that have no native platform equivalent.

Two axes drive every entry below:

- **interactivity class** — STATIC (zero JS, ever), NATIVE (a native
  HTML element/attribute already implements the behavior), or
  CUSTOM-ELEMENT (needs real client JS; no platform shortcut, or only a
  partial one).
- **port difficulty** — S/M/L, independent of interactivity class (a
  STATIC component can still be M if it has many attribute-computation
  edge cases; a CUSTOM-ELEMENT can be S if it wraps one native control).

33 public/primitive component packages and 25 shared-machinery packages
were inventoried. Component entries are grouped by family; shared
machinery gets its own section since those packages become shared JS
modules (or vanish entirely) in the port, used by many components.

---

## Shared machinery

These are the internal packages every primitive composes. In React they
solve two kinds of problems: (1) genuine cross-widget interaction
patterns (focus trapping, outside-dismiss, floating positioning, roving
tabindex, ordered item registries) that any port needs an answer for,
and (2) React-runtime-only problems (ref composition, context scoping,
hydration-safe effects, controlled/uncontrolled prop duality) that
**do not exist** in a server-rendered/vanilla-JS architecture and should
simply be dropped, not translated.

### Genuinely reusable (port the concept, not the code)

- **dismissable-layer** (`react-dismissable-layer`) — layered
  outside-pointerdown/focus/Escape dismissal for popups, with a
  document-scoped stack (`layers`, `layersWithOutsidePointerEventsDisabled`,
  `branches`, `dismissableSurfaces`) so only the topmost layer reacts,
  nested/portalled content can count as "inside," and a dismiss surface
  (e.g. a dialog overlay) still closes even if something calls
  `stopPropagation()` on it. Dispatch is deferred to the following
  `click` event (`deferPointerDownOutside`) so later code can still
  cancel dismissal, and to smooth over the ~350ms mobile tap delay.
  Consumers: dialog, hover-card, menu, navigation-menu, popover, select,
  toast, tooltip. **Largely replaceable by the `popover` attribute**
  (native top-layer + light-dismiss) for the common case; the
  branch/surface/deferred-cancellation semantics have no native
  equivalent and still need a small JS layer for pixel-parity behavior.
- **focus-scope** (`react-focus-scope`) — focus trap: a stack of scopes
  (only the top one active, so nested traps hand off correctly),
  auto-focus into the container on mount (first tabbable candidate via
  `TreeWalker` + visibility check), restore focus to the pre-open
  element on unmount, optional `loop` wraparound at Tab edges, and a
  `MutationObserver` refocus-guard if the focused node gets removed.
  Consumers: dialog, hover-card, menu, popover, select. **Mostly
  replaceable by `<dialog>`'s native `showModal()` trap** for modal
  dialogs; `loop` and the "branch" concept (a non-modal popover
  portalled outside the DOM subtree but logically inside the trap) have
  no native equivalent.
- **focus-guards** (`react-focus-guards`) — inserts two invisible
  `tabIndex=0` sentinel spans at `document.body`'s start/end so
  Tab/Shift+Tab crossing the page edges reliably fires `focusin`, since
  portalled content isn't at the literal DOM edge. Consumers: dialog,
  menu, popover, select. **Fully obsoleted by `<dialog>`/`popover`** —
  native top-layer focus containment doesn't need this workaround at
  all.
- **popper** (`react-popper`) — floating-element positioning: side/
  align, offset, collision-aware flip/shift, arrow placement,
  hide-when-anchor-clipped, `--radix-popper-available-width/height` CSS
  vars for consumer sizing. Now a thin wrapper around `@floating-ui/
  react-dom`; own logic is anchor context (real DOM ref or a virtual
  ref for cursor-anchored menus), `transform-origin` computation, and
  `strategy: 'fixed'` + `autoUpdate`. Consumers: hover-card, menu,
  popover, select, tooltip. **CSS anchor positioning
  (`anchor()`/`position-anchor`/`position-try`) covers static
  placement and simple flip-fallback declaratively**, but not
  `shift`/`limitShift` (partial-overlap sliding), the `size` middleware
  (available-space measurement), custom (non-viewport) collision
  boundaries, or the `hide` middleware — those need a JS fallback, and
  cross-browser anchor-positioning support is still uneven as of 2026
  (Safari/Firefox lag Chromium).
- **roving-focus** (`react-roving-focus`) — single-tab-stop keyboard
  navigation: only one item in a group has `tabIndex=0`; Arrow keys
  (orientation- and RTL-aware, via a direction-flipped key→intent map)
  move both focus and the tab-stop, Home/End/PageUp/PageDown jump to
  first/last, optional `loop`. Built on `collection` for DOM-order
  enumeration; defers the actual `.focus()` call via `setTimeout` to
  dodge a React batching bug (irrelevant outside React, but the
  deferral pattern of "don't call focus synchronously inside keydown if
  it fights other synchronous DOM work" is worth keeping in mind).
  Consumers: menu, menubar, one-time-password-field, radio-group, tabs,
  toggle-group, toolbar. **No native replacement whatsoever** — this is
  the single largest must-port interaction primitive in the whole
  library; every one of `popover`/`<dialog>`/anchor-positioning/`inert`/
  `ElementInternals` is silent on composite-widget arrow-key navigation.
  Best implemented once as a shared vanilla-JS controller (or custom
  element mixin) reused by every consumer above.
- **collection** (`react-collection`) — an ordered registry of a
  group's interactive child items, used for arrow-nav/typeahead/
  first-last queries. In React this exists because render order and
  DOM order can diverge (portals, scheduling); it re-sorts a `Map` by
  `Node.compareDocumentPosition` on every registration. In a
  server-rendered/vanilla-DOM world, **DOM order already is the
  registration order** — port the *concept* (a live registry an
  arrow-key controller can enumerate, updated as custom-element children
  connect/disconnect) as a much simpler `querySelectorAll`-based lookup,
  not the document-position-sorting machinery.
- **presence** (`react-presence`) — keeps a node mounted through its
  CSS exit animation before removing it, via a `mounted →
  unmountSuspended → unmounted` state machine driven by comparing
  computed `animation-name` before/after and waiting for a real
  `animationend`. Most of its intricacy (concurrent-render flash
  avoidance, effect-ordering vs. sibling layout dirtying, ref-identity
  churn) is compensating for React-specific timing problems that don't
  exist in vanilla JS. **Substantially replaceable**: a plain
  `animationend`/`transitionend` listener covers the core need, and CSS
  `@starting-style` + `transition-behavior: allow-discrete` (2023+ spec,
  decent 2024-2026 support) lets `display: none ⇄ block` itself be
  transitioned, removing the need for a JS wait-for-animation state
  machine in most cases.
- **portal** (`react-portal`) — renders into `document.body` (or a
  given container) to escape `overflow`/`z-index` stacking contexts.
  Pure React-reconciliation concern (decoupling the logical tree from
  the physical DOM tree); **not needed as an abstraction** server-side —
  a template just emits the overlay markup wherever it needs to live,
  and `popover`/top-layer (or plain `position: fixed` + body-appended
  custom element) handles the stacking-context escape natively.
- **slot** (`react-slot`) — merges a wrapper's props/ref onto its one
  child instead of adding a wrapper DOM node (the mechanism behind
  every primitive's `asChild`). The ref/child-cloning machinery is
  pure-React and irrelevant server-side, but its **prop-merging
  semantics** — compose event handlers instead of clobbering, shallow-
  merge `style`, concatenate `class`, dedupe-and-join `aria-describedby`
  — is a genuinely reusable, framework-agnostic pattern worth keeping as
  a plain helper function if prologex ever needs to merge
  server-supplied default attributes with caller-supplied ones.
- **id** (`react-id`) — SSR-safe unique ID generation for
  `aria-*` wiring. Exists purely because client-generated random IDs
  would mismatch server-rendered HTML during React hydration. **Not
  needed as JS** — prologex generates IDs once at template-render time
  (a gensym/counter helper in the template engine) and ships them as
  static attributes; there is no hydration-mismatch problem to solve
  because there is no client-side re-render pass.
- **arrow** (`react-arrow`) — small SVG pointer-nub for popper content.
  Pure markup; a server-rendered SVG partial, no JS.
- **use-size**'s underlying logic — `ResizeObserver` with
  `requestAnimationFrame` debouncing (to dodge the benign "loop
  completed with undelivered notifications" warning) is plain portable
  DOM code; worth keeping as a small shared vanilla helper for anything
  needing live element size (e.g. a hand-rolled popper arrow), minus the
  React `useState` wrapper.

### Obsoleted by 2024-2026 platform features (see the dedicated section below for full detail)

- **focus-guards** — gone once `<dialog>`/`popover` are used for their
  native trap/top-layer instead of hand-rolled `focus-scope`.
- Most of **presence**'s state machine — gone once exit transitions use
  `@starting-style`/`allow-discrete`.
- Much of **dismissable-layer**'s stacking/z-index bookkeeping — gone
  once `popover`'s native top-layer + light-dismiss is the baseline.
- **portal** — gone; native top-layer or direct server-side placement
  supersedes it.

### Pure React-runtime concerns — no server-rendered/vanilla-JS equivalent needed at all

- **compose-refs** — merging multiple refs is a React `forwardRef`
  problem; vanilla JS has exactly one variable holding an element
  reference.
- **context** (`createContext`/`createContextScope`) — React
  tree-scoped state sharing; in a DOM-containment world, a custom
  element just looks up `closest('px-select')` or reads server-rendered
  data attributes instead.
- **direction** (`DirectionProvider`/`useDirection`) — a React-context
  fallback chain for `dir`; the DOM already inherits `dir` natively
  (`element.closest('[dir]')`, CSS `:dir()`, logical properties) with no
  JS needed, or it's read once at render time server-side.
- **primitive**'s `asChild`/polymorphic-tag machinery and
  `dispatchDiscreteCustomEvent`'s `flushSync` workaround — both
  compensate for JSX's fixed-tag-per-call-site nature and React 18's
  event batching; irrelevant when a template author just writes the tag
  they want.
- **use-callback-ref, use-controllable-state, use-effect-event,
  use-is-hydrated, use-layout-effect, use-previous** — all solve
  React-only problems (referential-equality-triggers-effects,
  controlled/uncontrolled prop duality, stale-closure-in-effects,
  distinguishing SSR-pass from hydration-pass, SSR-safe effect timing,
  "previous render's value"). None of these concepts exist outside
  React's render/reconciliation model. `use-controllable-state`'s
  *design idea* — "always emit a change event, let the caller decide
  whether to keep state" — is worth keeping as a loose convention for
  custom elements, but the hook itself is not portable.
- **compose-refs**' sibling **use-rect** — appears **orphaned in the
  current Radix codebase**: zero source imports found (`popper.tsx` no
  longer imports it despite still listing it as a `package.json`
  dependency; sizing now goes through floating-ui + `use-size`
  directly). Not worth chasing.
- **announce** (`react-announce`) — also apparently **unused
  internally**: zero consumers found via import grep; `toast`
  reimplements a live region inline rather than using this package. The
  underlying idea (a shared `aria-live` region, portaled once,
  patched on `visibilitychange` to avoid background-tab announcements)
  is a simple static server-rendered `<div aria-live="polite">` updated
  by a tiny script — no framework concern here.
- **use-escape-keydown** — deprecated even in Radix itself (superseded
  by inline listeners in `dismissable-layer`); its entire body is a
  3-line `document.addEventListener('keydown', ..., {capture:true})`,
  directly portable if ever needed standalone.

---

## Component inventory

Each entry: name/purpose, anatomy, DOM/ARIA contract, keyboard
interactions, interactivity class (+ custom-element sketch where
relevant), dependencies, port difficulty.

### Static / presentational family

#### AccessibleIcon
- **Purpose**: gives a raw icon/SVG an accessible name, like `alt` on
  `<img>`.
- **Anatomy**: single part, `Root`. Takes exactly one child (the icon).
- **DOM/ARIA**: clones `aria-hidden="true" focusable="false"` onto the
  icon, renders a visually-hidden sibling `<span>` with the label text
  (accessible name via text content, not `aria-label`).
- **Keyboard**: none.
- **Interactivity class: STATIC.** Pure render-time markup transform —
  emit `aria-hidden`/`focusable` on the icon plus a visually-hidden text
  sibling, zero client JS.
- **Dependencies**: visually-hidden.
- **Port difficulty: S.**

#### AspectRatio
- **Purpose**: constrains content to a width/height ratio.
- **Anatomy**: single part, `Root` (outer ratio div + inner absolutely-
  positioned content div; inner div is an implementation detail, not a
  separate exported part).
- **DOM/ARIA**: none. `data-radix-aspect-ratio-wrapper=""` is a
  query/styling hook, not semantic. Outer: `padding-bottom:
  {100/ratio}%`. Inner: `inset: 0`.
- **Keyboard**: none.
- **Interactivity class: STATIC.** Pure CSS math from a prop, computable
  at template-render time. Modern CSS `aspect-ratio` could collapse this
  to one div if legacy-browser support isn't a concern.
- **Dependencies**: none beyond base element rendering.
- **Port difficulty: S.**

#### Avatar
- **Purpose**: user/entity avatar with automatic fallback while the
  image loads or on error.
- **Anatomy**: `Root` (span, context), `Image` (img, rendered only once
  loaded), `Fallback` (span, rendered unless loaded).
- **DOM/ARIA**: no explicit role/aria-* anywhere; no `data-state`
  exposed either (unlike Progress) — load status is purely internal.
- **Keyboard**: none.
- **Interactivity class: CUSTOM-ELEMENT (small).** `useImageLoadingStatus`
  constructs a `new Image()`, listens for `load`/`error`, and derives
  status from `image.complete && image.naturalWidth > 0` (catches
  "loaded but 0×0" broken images that fire `load`). `Fallback` also
  supports a `delayMs` to avoid flashing on fast loads. No CSS-only
  equivalent exists — there is no `:error`/`:broken` pseudo-class and
  `:has()` cannot observe a failed image decode — so a minimal custom
  element (or a couple-line inline `onload`/`onerror` pair) toggling a
  `data-state="loading|loaded|error"` attribute for CSS to key off is
  the right-sized port; no polling, no full hook needed.
- **Dependencies**: context (scoping only, trivially replaced by
  passing the same values to both part templates).
- **Port difficulty: M.**

#### Label
- **Purpose**: accessible form label; prevents double-click text
  selection from stealing focus over the control.
- **Anatomy**: single part, `Root` (`<label>`).
- **DOM/ARIA**: none beyond native `<label for>`/wrapping association.
- **Keyboard**: none. The only logic is an `onMouseDown` guard: if the
  mousedown target is inside a nested form control, do nothing; else,
  on `event.detail > 1` (double/triple click), `preventDefault()` to
  stop text selection.
- **Interactivity class: STATIC.** Native `<label for>` needs no JS at
  all; the double-click-selection nicety is better solved with CSS
  `user-select: none` on the label (re-enabled on nested controls) than
  with a JS handler.
- **Dependencies**: none.
- **Port difficulty: S.**

#### Separator
- **Purpose**: visual/semantic divider, horizontal or vertical,
  optionally decorative.
- **Anatomy**: single part, `Root` (`<div>`).
- **DOM/ARIA**: always `data-orientation`; `role="none"` if decorative,
  else `role="separator"` plus `aria-orientation` (only emitted for
  vertical — horizontal is the ARIA default so it's omitted).
- **Keyboard**: none.
- **Interactivity class: STATIC.** All attributes are pure conditionals
  on `orientation`/`decorative` props, computable server-side.
- **Dependencies**: none.
- **Port difficulty: S.**

#### VisuallyHidden
- **Purpose**: the standard "sr-only" pattern — visually hidden, still
  in the accessibility tree.
- **Anatomy**: single part, `Root` (`<span>`).
- **DOM/ARIA**: none; entirely a fixed inline-style object (`position:
  absolute; clip: rect(0,0,0,0); ...`, the Bootstrap-derived technique).
- **Keyboard**: none.
- **Interactivity class: STATIC.** Ship as one reusable CSS class
  server-side.
- **Dependencies**: none.
- **Port difficulty: S.**

#### Progress
- **Purpose**: determinate/indeterminate progress bar.
- **Anatomy**: `Root` (div, context), `Indicator` (div, fill bar; no
  visual width logic of its own — that's consumer CSS keyed off
  `data-value`/`data-max`).
- **DOM/ARIA**: Root: `role="progressbar"`, `aria-valuemax={max}`,
  `aria-valuemin={0}`, `aria-valuenow` (omitted when indeterminate),
  `aria-valuetext` (from a `getValueLabel(value,max)` default of
  rounded `%`), `data-state` ∈ `indeterminate|complete|loading`,
  `data-value`, `data-max`. Indicator mirrors the same triplet.
- **Keyboard**: none.
- **Interactivity class: STATIC.** All attributes are pure functions of
  `value`/`max` computable at render time; the primitive itself never
  animates or polls — that's a generic "update this element" concern
  (e.g. a Turbo-stream replace) outside the primitive's own scope, same
  as upstream Radix.
- **Dependencies**: context (prop-plumbing only).
- **Port difficulty: S.**

### Form controls & disclosure family

#### Checkbox
- **Purpose**: tri-state (checked/unchecked/indeterminate) toggle,
  form-integrated.
- **Anatomy**: `Root` (composite), `Provider`, `Trigger` (button),
  `Indicator` (span, `Presence`-gated), `BubbleInput` (hidden native
  `<input type=checkbox>` that bubbles a real `change`/`click` for
  ancestor `<form>` participation/autofill — absolutely positioned,
  opacity 0, sized to match the trigger via `ResizeObserver`).
- **DOM/ARIA**: Trigger: `<button type="button" role="checkbox">`,
  `aria-checked` = `"mixed"` string when indeterminate else boolean,
  `aria-required`, `data-state` ∈ `indeterminate|checked|unchecked`,
  `data-disabled=""` (empty-string, not `"true"`), native `disabled`.
  Indicator mirrors `data-state`/`data-disabled`.
- **Keyboard**: Space toggles via native button semantics; `Enter` is
  explicitly `preventDefault()`ed (WAI-ARIA: checkboxes don't activate
  on Enter). No arrow-key handling (single control).
- **Interactivity class: NATIVE for 2-state; CUSTOM-ELEMENT for
  indeterminate.** `<input type=checkbox>` + `:checked` CSS covers
  checked/unchecked with zero JS, including toggle-via-click (browser
  handles it; a full reload/turbo-frame re-render covers server-driven
  toggling). The gap: `.indeterminate` is a JS-only DOM property with
  **no HTML attribute**, and native indeterminate reports
  `aria-checked="false"` to AT unless `aria-checked` is set manually —
  so indeterminate-on-load or programmatically-driven tri-state needs a
  small custom element (or inline script) to set `.indeterminate` and
  `aria-checked="mixed"` after render.
- **Dependencies**: context, use-size, presence (Indicator).
- **Port difficulty: S** (2-state) — the indeterminate visual is a
  small, well-contained addition, not a difficulty escalation.

#### Switch
- **Purpose**: boolean on/off toggle, form-integrated. Structurally
  Checkbox minus indeterminate.
- **Anatomy**: `Root`, `Provider`, `Trigger` (button), `Thumb` (span,
  always rendered — no Presence gating), `BubbleInput`.
- **DOM/ARIA**: Trigger: `role="switch"`, `aria-checked` (plain
  boolean, no "mixed"), `aria-required`, `data-state` ∈
  `checked|unchecked`, `data-disabled=""`. Thumb mirrors both.
- **Keyboard**: none custom — native `<button>` gives both Space and
  Enter activation (unlike Checkbox, no Enter-blocking override).
- **Interactivity class: NATIVE.** `<input type=checkbox>` styled as a
  switch via `:checked` covers the entire binary state with zero JS;
  server-rendered `checked` attribute plus reload/turbo-frame handles
  the toggle. JS only buys instant-visual-flip snappiness.
- **Dependencies**: context, use-size.
- **Port difficulty: S.**

#### Toggle
- **Purpose**: single pressed/unpressed button (e.g. a toolbar bold
  button). Not form-integrated — no bubble input.
- **Anatomy**: single part, `Root`.
- **DOM/ARIA**: `<button type="button" aria-pressed={pressed}
  data-state={pressed?'on':'off'} data-disabled>`.
- **Keyboard**: none custom — native button Space/Enter toggles via
  click.
- **Interactivity class: NATIVE-capable, arguably STATIC.** A server-
  rendered `<button aria-pressed>` inside a form, POSTing and
  re-rendering on click, reproduces this exactly with zero client JS;
  JS is a pure optional-snappiness layer.
- **Dependencies**: none beyond base rendering. (Building block for
  Toggle Group.)
- **Port difficulty: S.**

#### Toggle Group
- **Purpose**: a row/column of Toggles, either `single` (radio-like,
  exactly one pressed) or `multiple` (independent), with roving-
  tabindex keyboard nav.
- **Anatomy**: `Root`, `Item`.
- **DOM/ARIA**: Root: `role="radiogroup"` (`type=single`) or
  `role="toolbar"` (`type=multiple`); `data-orientation` from the
  roving-focus group. Item: when `type=single`, `role="radio"` +
  `aria-checked`; when `type=multiple`, ordinary Toggle semantics
  (`aria-pressed`, `data-state`). Items wrapped in a roving-focus
  item (`tabIndex` 0/-1 per current tab stop).
- **Keyboard**: entirely delegated to roving-focus — ArrowLeft/Up→prev,
  ArrowRight/Down→next (RTL- and orientation-aware), Home/PageUp→first,
  End/PageDown→last, optional `loop`. Activation (Space/Enter) is native
  button behavior; roving-focus only intercepts navigation keys.
- **Interactivity class: CUSTOM-ELEMENT — unavoidably.** The toggle
  state itself is server-renderable and reload-safe, but arrow-key
  roving-tabindex navigation between items cannot be done via a network
  round trip per keypress without breaking the ARIA pattern's UX
  contract; this is real, unavoidable client JS (a keydown listener
  managing `tabindex`/`.focus()` across a collection, RTL/orientation-
  aware). If the port drops arrow-key roving nav (accepting plain
  sequential Tab-through instead), the rest needs no JS beyond optional
  snappy click handling.
- **Dependencies**: context, roving-focus, toggle, direction.
- **Port difficulty: M.**

#### Radio Group
- **Purpose**: single-select group with roving-tabindex and
  auto-select-on-arrow-focus.
- **Anatomy**: `Root`, `Item`, `ItemIndicator` (`Presence`-gated),
  per-item `BubbleInput` (hidden native `<input type=radio>`).
- **DOM/ARIA**: Root: `role="radiogroup"`, `aria-required`,
  `aria-orientation`, `data-disabled`. Item trigger: `role="radio"`,
  `aria-checked`, `data-state`, `data-disabled`, wrapped in a
  roving-focus item with `active={checked}`.
- **Keyboard**: `Enter` is `preventDefault()`ed (radios don't activate
  on Enter, same WAI-ARIA note as checkboxes). A document-level
  `keydown`/`keyup` pair tracks "was this focus change caused by an
  arrow key," and on such a focus event the item **synthetically
  `.click()`s itself** — this is what makes RadioGroup auto-select on
  arrow navigation, unlike ToggleGroup's `type=multiple` (which only
  moves focus). Clicking an already-checked radio is a no-op. Arrow/
  Home/End navigation itself is the same roving-focus machinery as
  ToggleGroup.
- **Interactivity class: NATIVE-capable — the strongest native-coverage
  case in this family.** A real `<input type=radio name=x>` group gets
  roving-tabindex-equivalent behavior *and* arrow-key auto-select for
  free from the browser, with zero JS, including the auto-check-on-
  arrow affordance Radix hand-rolls. The only gap is styling ergonomics
  (`:checked` sibling selectors instead of a `data-state` hook on an
  arbitrary wrapper) — a CSS technique difference, not a capability
  gap. Only the decoupled custom-visual `role=radio` variant (independent
  `Indicator` part, non-native-input styling) needs the full
  roving-focus custom element.
- **Dependencies**: context, roving-focus, direction, use-size,
  presence.
- **Port difficulty: S** if native `<input type=radio>` is accepted as
  the port target (browser does all the keyboard work) / **M** for a
  faithful hand-rolled `role=radio` custom-button port.

#### Collapsible
- **Purpose**: single show/hide disclosure region; the base Accordion's
  `Item` is built on this.
- **Anatomy**: `Root` (div), `Trigger` (button), `Content` (div,
  `Presence`-gated, height/width measured for animation).
- **DOM/ARIA**: Root: `data-state` ∈ `open|closed`, `data-disabled`.
  Trigger: `aria-controls` (only set while open), `aria-expanded`,
  `data-state`, `data-disabled`. Content: `data-state`, `data-disabled`,
  `id` (matches trigger's `aria-controls`), `hidden={!open}`; exposes
  `--radix-collapsible-content-height/-width` CSS vars measured via
  `getBoundingClientRect()` (with transitions temporarily disabled
  during measurement) to support animating to/from an unknown height.
- **Keyboard**: none beyond native button Space/Enter.
- **Interactivity class: NATIVE-capable with real gaps.** `<details>`/
  `<summary>` gives zero-JS open/closed disclosure with a real `open`
  attribute settable server-side. Gaps versus Radix: no `data-state`
  styling hook (style off `[open]` instead — a workable but different
  idiom), no separate trigger/content split with `aria-controls`/
  `aria-expanded` wiring, and critically, **no smooth height animation**
  — `<details>` toggles content display abruptly; Radix's measured-
  height CSS-var dance is exactly the JS work needed to animate
  open/close smoothly, which `<details>` cannot do alone. Static
  open/closed: zero JS via `<details open>`. Animated open/close: JS
  required.
- **Dependencies**: context, use-controllable-state, use-layout-effect,
  presence, id. (Accordion depends on this package.)
- **Port difficulty: S** (static case) / **M** (animated case).

#### Accordion
- **Purpose**: a set of Collapsible items, `single` (one open, with a
  `collapsible` sub-option allowing/forbidding closing the last one) or
  `multiple` (independent), with arrow-key navigation between triggers.
  Built directly on Collapsible.
- **Anatomy**: `Root`, `Item` (wraps `Collapsible.Root`), `Header`
  (`<h3>`, hardcoded level — no per-instance override), `Trigger`
  (wraps `Collapsible.Trigger`), `Content` (wraps `Collapsible.Content`,
  adds `role="region"`).
- **DOM/ARIA**: Root: `data-orientation` (default vertical), no role.
  Item: `data-orientation`, `data-state` (accordion's own tracking,
  layered on Collapsible's). Header: `data-orientation`, `data-state`,
  `data-disabled`. Trigger: everything Collapsible's trigger sets, plus
  `aria-disabled` on the currently-open trigger when `type=single` and
  **not** `collapsible` (can't re-close the one mandatory-open item).
  Content: everything Collapsible's content sets, plus `role="region"
  aria-labelledby={triggerId}` (standard APG region-labelled-by-trigger
  pattern) and accordion-prefixed re-exports of the height/width CSS
  vars.
- **Keyboard**: **hand-rolled, not delegated to roving-focus** — a
  standalone `handleKeyDown` walks a `collection` of triggers (filtering
  disabled ones), computes the next index for Home/End/Arrow keys
  (orientation- and direction-aware, same mapping style as roving-focus)
  and calls `.focus()` directly; no `tabIndex` manipulation is visible,
  meaning triggers likely remain independently Tab-focusable rather
  than using a strict single-tab-stop scheme. Space/Enter activation is
  plain native-button behavor (no Enter-blocking, unlike Checkbox/Radio).
- **Interactivity class: CUSTOM-ELEMENT — needs client JS for
  navigation, same unavoidable category as Toggle Group.** The
  open/closed state is fully server-renderable, and native `<details
  name="group">` (supported across major engines since ~2023-2024)
  covers `type=single, collapsible=true` specifically — but not
  `collapsible=false` (needs JS or server-side validation to block
  closing the last-open item), not the `data-state`/`aria-disabled`
  styling hooks, and not arrow-key-between-triggers navigation (native
  `<details>` elements have no roving nav, no Home/End). Recommend:
  treat `single+collapsible=true` as native-`<details name>`-backed
  with zero JS, and treat `multiple`, `collapsible=false`, and
  arrow-key navigation as opt-in JS enhancements layered on top.
- **Dependencies**: context, collection, collapsible, id, direction.
  Notably does **not** use roving-focus despite implementing equivalent
  behavior by hand.
- **Port difficulty: L** — the hardest of this family: a composite of
  two ports (Collapsible + a hand-rolled collection-walking keyboard
  layer distinct from roving-focus), a 4-combination state machine
  (`single`/`multiple` × `collapsible`), the `aria-disabled`-on-last-open
  edge case, and animation inheritance from Collapsible. Difficulty
  drops substantially if the port accepts native `<details name>` for
  the common case and treats the rest as progressive enhancement.

### Menu & navigation family

These are, along with Select, the most JS-intensive primitives in the
library — none are native-replaceable beyond edge positioning.

#### Tabs
- **Purpose**: layered content sections shown one at a time. WAI-ARIA
  Tabs pattern.
- **Anatomy**: `Root`, `List` (`role="tablist"`, wraps roving-focus),
  `Trigger` (`role="tab"`, one per tab), `Content` (`role="tabpanel"`,
  sibling of List, not child of Trigger).
- **DOM/ARIA**: List: `role="tablist" aria-orientation`. Trigger:
  `role="tab" aria-selected aria-controls={contentId}
  data-state={active|inactive} data-disabled id={triggerId}`. Content:
  `role="tabpanel" aria-labelledby={triggerId} data-state
  data-orientation hidden={!present} id={contentId} tabIndex={0}`,
  `Presence`-gated for exit animation.
- **Keyboard**: left-click only opens on `onMouseDown` (guards against
  ctrl-click); Space/Enter on the focused trigger selects it when
  `activationMode="manual"`. Default `activationMode="automatic"`:
  **selecting on focus alone** — `onFocus` immediately fires
  `onValueChange` unless already selected/disabled. All Arrow/Home/End/
  PageUp/PageDown navigation, RTL- and orientation-aware, with optional
  `loop` (default true), comes entirely from roving-focus.
  `Shift+Tab` from a trigger sets a "tabbing back out" flag that
  forces the whole tablist wrapper's tabIndex to -1 for that blur
  cycle, so Tab skips the tablist cleanly when backing out.
- **Interactivity class: CUSTOM-ELEMENT.** State machine to replicate:
  a roving-tabindex controller over `[role=tab]` children (orientation/
  RTL-aware Arrow/Home/End, optional loop); an activation-mode switch
  (immediate-on-focus vs. wait-for-Enter/Space); toggling `hidden` +
  `data-state` on the matching panel and `aria-selected`/`data-state` on
  triggers whenever the value changes.
- **Dependencies**: context, roving-focus, presence, direction,
  use-controllable-state, id.
- **Port difficulty: M** — real state-machine work (roving-tabindex +
  activation modes) but no popper/portal/submenu complexity; a flat
  list, not nested.

#### Toolbar
- **Purpose**: a row/column grouping heterogeneous controls (buttons,
  links, toggle groups) under one shared roving-tabindex domain. WAI-
  ARIA Toolbar pattern.
- **Anatomy**: `Root`, `Button`, `Link`, `Separator` (orientation
  auto-flipped relative to the toolbar), `ToggleGroup` (wraps Toggle
  Group with its own internal roving-focus **disabled**, since the
  Toolbar's roving-focus group already spans all children), `ToggleItem`.
- **DOM/ARIA**: Root: `role="toolbar" aria-orientation dir`. Button:
  native button, wrapped as a roving-focus item. Link: `<a>`, wrapped
  as a roving-focus item, with a Space→`.click()` patch since links
  don't natively activate on Space.
- **Keyboard**: entirely delegated to roving-focus, one flat tab-stop
  domain spanning heterogeneous children (separators excluded, not
  focusable); the only toolbar-specific addition is the Link Space-key
  patch.
- **Interactivity class: CUSTOM-ELEMENT.** Same roving-tabindex
  justification as Tabs, with the added twist that an embedded toggle
  group must expose a "roving focus disabled" mode so it defers to the
  parent toolbar's single controller instead of running its own.
- **Dependencies**: context, roving-focus, separator, toggle-group,
  direction.
- **Port difficulty: S.** No open/close state, no portals, no
  animation — nearly a thin composition once roving-focus exists as a
  shared module.

#### Navigation Menu
- **Purpose**: hover/focus-activated flyout navigation with a shared
  animated viewport panel. Not a canonical WAI-ARIA pattern — a bespoke
  disclosure-button (`aria-expanded`/`aria-controls`) + `aria-current`
  link-state composition with its own non-looping roaming-focus helper.
- **Anatomy**: `Root` (`<nav aria-label="Main">`), `List` (`<ul>`),
  `Item` (`<li>`), `Trigger` + `Content` (or a bare `Link` in an item
  without a trigger), `Indicator` (animated caret tracking the active
  trigger, portaled), `Viewport` (single shared container all `Content`s
  render into), `Sub` (recursive nested submenu, re-provides context
  with `isRootMenu: false`).
- **DOM/ARIA**: Trigger: `data-state`, `aria-expanded`, `aria-controls`;
  when open, renders a hidden focus-proxy `VisuallyHidden` element
  after itself to redirect Tab order into/out of the (possibly visually
  relocated) content, plus `aria-owns` when a shared viewport is in use.
  Content: `aria-labelledby={triggerId}`, `data-motion` ∈
  `to-start|to-end|from-start|from-end|null` (a JS-computed
  direction-of-travel animation hint from comparing item indices,
  RTL-aware). Indicator and Viewport both expose JS-measured
  `ResizeObserver`-derived CSS vars (pixel position/size) — not
  achievable in pure CSS.
- **Keyboard**: an orientation/RTL-aware "entry key" (ArrowDown or
  ArrowRight/Left) focuses into an open Content's first tabbable node
  via a `TreeWalker`. Because Content can be visually relocated into a
  shared Viewport, Tab order is manually proxied: a focus-proxy element
  after each trigger detects entry-from-trigger vs. exit-from-content
  via `relatedTarget`, and closing content temporarily sets `tabindex
  =-1` on its tabbables so wraparound Tab doesn't refocus stale hidden
  content. Escape sets a ref consumed by dismissal logic and by pointer
  handlers (suppresses reopen right after Escape). A custom
  `rootContentDismiss` event bubbles from link clicks to close the
  whole menu and refocus the trigger. A **second, independent roving-
  nav system** (`FocusGroup`, not the shared roving-focus package) wraps
  both the root list and each open Content, with no wraparound/looping
  at all. Separately, an **open/close timer state machine**: hover-in
  schedules open after `delayDuration` (200ms default) unless already
  in a `skipDelayDuration` window (300ms after the last close) in which
  case it opens instantly; hover-out schedules close after a fixed
  150ms, cancelled if the pointer moves onto the content itself.
- **Interactivity class: CUSTOM-ELEMENT — the hardest of this family.**
  Combines a hover/focus timer state machine (two delays + skip-delay
  window), a portaled/relocated viewport requiring manual tab-order
  proxying, `ResizeObserver`-driven geometry for both the indicator and
  the viewport (impossible to precompute server-side or express in pure
  CSS), direction-of-travel animation state, two simultaneous keyboard-
  nav systems, and recursive submenu nesting. No popper import at all —
  positioning here is bespoke CSS-variable-driven measurement, not
  reusable from the Popper port.
- **Dependencies**: context, collection (two separate collections — item
  lookup and the FocusGroup), dismissable-layer, use-previous (motion-
  direction diffing), use-layout-effect, use-callback-ref,
  visually-hidden, presence, direction, id. Notably **no** popper, no
  roving-focus, no focus-scope/focus-guards (not modal).
- **Port difficulty: L.**

#### Menubar
- **Purpose**: a horizontal bar of menu buttons (File/Edit/View…),
  where hovering across the bar while one menu is open switches
  directly between menus. Built as a thin composer over the base `menu`
  primitive — nearly every non-Trigger export is a one-line pass-through
  to the corresponding `menu` part.
- **Anatomy**: `Root`, `Menu` (grouping only), `Trigger`, `Portal`,
  `Content`, `Item`, `CheckboxItem`, `RadioGroup`/`RadioItem`,
  `ItemIndicator`, `Separator`, `Label`, `Group`, `Arrow`, `Sub`/
  `SubTrigger`/`SubContent`.
- **DOM/ARIA**: Root: `role="menubar"`, wraps roving-focus with
  Menubar itself owning `currentTabStopId` (rather than letting
  roving-focus own it, since a trigger may never receive real focus if
  opened by click then dismissed by outside-click). Trigger: `role=
  "menuitem" aria-haspopup="menu" aria-expanded aria-controls
  data-highlighted data-state data-disabled`, tab-stop keyed by the
  menu's value. Content: delegates to the base menu's content contract
  (see Menu below) plus CSS var re-namespacing.
- **Keyboard**: Trigger: Enter/Space toggles, ArrowDown opens (doesn't
  toggle); all three set a "was keyboard-opened" flag consumed by
  entry-focus suppression (see below). `onPointerEnter` on a trigger
  switches directly to that menu if a *different* one is already open —
  the hover-to-switch behavior. Content adds its own `ArrowLeft`/
  `ArrowRight` handling on top of the base Menu's: normally these
  switch to the adjacent top-level menu (wrapping per `loop`), but two
  escape hatches yield to the base Menu's own submenu handling instead —
  an Arrow-toward-open-submenu on a subtrigger, and Arrow-back while
  inside a submenu (closes one level, not the whole bar). `onEntryFocus`
  suppresses auto-focusing the first item unless the menu was actually
  opened via keyboard (matches native OS menu-bar behavior: mouse-open
  doesn't auto-highlight). `onFocusOutside` to another menubar trigger
  is treated as an internal switch, not a dismiss.
- **Interactivity class: CUSTOM-ELEMENT.** Needs everything the base
  Menu needs (below) plus: a top-level roving-tabindex keyed by
  open-menu-value rather than focus, and an ArrowLeft/Right
  "switch-adjacent-top-level-menu, but yield to submenu semantics"
  branch.
- **Dependencies**: collection, direction, context, id, **menu** (the
  base primitive — this is the defining dependency), roving-focus
  (top-level trigger row only).
- **Port difficulty: M leaning L** — not as hard as Navigation Menu
  since it reuses the base Menu's submenu/typeahead/pointer-grace
  machinery wholesale; its own new surface (top-level roving-tabindex-
  by-value + the Arrow-switch branch) is small, but its difficulty is
  really "base Menu difficulty + a coordination layer," so it cannot be
  ported before Menu.

#### Menu (shared machinery, not a public component)
`dropdown-menu`, `context-menu`, and `menubar` are all thin composers
over this internal package (explicitly marked "not intended for public
usage" in its own README). Any port of those three requires porting
this state machine **once**, as shared infrastructure, rather than
three times.

- **Positioning/portal/modality**: wraps children in the popper root;
  branches into a modal content variant (focus-trapped via
  `focus-scope`, siblings `aria-hidden`d via the `aria-hidden` package,
  outside pointer events disabled, scroll locked with shard-aware
  `react-remove-scroll`) versus a non-modal variant (none of that) —
  Menubar always uses non-modal since a persistent menu bar shouldn't
  scroll-lock or trap focus.
- **Roving-focus + collection over items**: content is `role="menu"`
  wrapped in a vertical, looping roving-focus group; every item is a
  roving-focus item self-registered in a collection (keyed by
  `disabled`+`textValue`) used for typeahead and Home/End (focus
  first/last non-disabled item).
- **Typeahead**: accumulates typed characters, 1s reset timer; a
  matching function normalizes repeated single-character presses (e.g.
  mashing "b" cycles items) by detecting a same-character-repeated
  search string and collapsing it to one character, wrapping the
  candidate list to search forward from just past the current match.
- **Submenu open-on-hover-with-delay**: mouse-only 100ms timer to open
  a submenu on pointer-move over its trigger (guarded by
  `pointerType==='mouse'`); keyboard uses direction-aware open/close key
  sets (`ArrowRight`/`ArrowLeft` swapped under RTL) and opens
  immediately, refocusing the trigger on close (since auto-focus-on-
  close is deliberately suppressed to avoid a refocus flash when moving
  between sibling items).
- **RTL/LTR awareness**: threaded through submenu open/close key maps,
  submenu popper side, and the ambient direction provider.
- **Close-on-select**: item selection dispatches a cancelable custom
  event; unless prevented, closes the *entire* menu tree (not just the
  current submenu level).
- **Pointer-grace-area handling** (the gnarliest bit, worth flagging
  explicitly for the recipe): when the pointer leaves a submenu trigger
  while its submenu is open, instead of closing immediately, Radix
  computes a 5-point polygon ("cone") between the cursor's current
  position (with a small directional bleed) and the submenu content's
  near/far corners, stores it with a 300ms expiry timer, and on every
  subsequent pointer move checks (a) the last observed horizontal
  travel direction matches the submenu's side and (b) a ray-casting
  point-in-polygon test confirms the cursor is still inside the cone —
  while both hold, item-highlight-follow and close-on-leave are
  suppressed, letting the user travel diagonally into the submenu
  without it flickering shut. This is pure, portable geometry (just
  `PointerEvent.clientX/Y` and `getBoundingClientRect()`) and should be
  lifted near-verbatim into the vanilla-JS port rather than redesigned.
- **Edge cases worth carrying forward**: window blur closes the whole
  menu tree; an "is using keyboard" flag (set on keydown, cleared on
  next pointerdown/move) gates whether opening auto-focuses the first
  item; Tab is fully swallowed inside menu content (menus aren't
  tab-navigable, only Escape/outside-click/select dismiss them); every
  keydown handler checks `event.target === event.currentTarget` to
  avoid swallowing keys bubbling from nested focusables inside items —
  replicate this guard on custom-element listeners or inputs-inside-
  items will break.
- **Port implication**: build **one** shared vanilla-JS module/custom-
  element implementing items 2-6 above (roving-focus-in-a-popup +
  typeahead + hover-delay submenus + pointer-grace polygon + RTL key
  maps + close-tree-on-select), parameterized by trigger type (click /
  right-click / hover-switch) and modality, with dropdown-menu /
  context-menu / menubar each supplying only trigger-opening semantics
  on top.
- **Port difficulty: L**, as a standalone unit — it combines more
  distinct interacting subsystems (popper, modal branching, roving-
  focus, typeahead, hover-delay nesting, RTL key maps, grace-area
  geometry) than any other single package in the library, which is
  exactly why upstream Radix factors it out as shared infrastructure.

### Overlay / floating family

#### Dialog
- **Purpose**: modal (default) or non-modal window overlay.
- **Anatomy**: `Root`, `Trigger`, `Portal`, `Overlay` (modal only),
  `Content`, `Title`, `Description`, `Close`.
- **DOM/ARIA**: Trigger: `aria-haspopup="dialog" aria-expanded
  aria-controls data-state`. Content: `role="dialog" id aria-labelledby`
  (only if a Title is mounted) `aria-describedby` (consumer value
  concatenated with the internal description id, only if a Description
  is mounted) `data-state`. **No `aria-modal` is ever set** — instead
  modal Dialog calls `hideOthers(content)` from the `aria-hidden`
  package to mark sibling subtrees `aria-hidden`, described in source
  as "a better-supported equivalent to `aria-modal`." Overlay:
  `data-state`, only rendered when modal.
- **Keyboard**: Escape/outside-dismiss via dismissable-layer
  (`deferPointerDownOutside`). Focus trap via focus-scope with `loop`,
  `trapped={open}` for modal / always `false` for non-modal, and a
  `branches` list so nested portalled non-modal layers (e.g. a Popover
  opened from inside the Dialog) count as part of the trap.
  `focus-guards` ensures Tab-edge sentinels exist since Portal moves
  content to the end of the DOM. Right-click (and ctrl-left-click, which
  macOS treats as right-click) on the overlay is explicitly excluded
  from triggering dismiss. Modal `onCloseAutoFocus` returns focus to the
  trigger; non-modal only does so if the user didn't interact outside
  first.
- **Interactivity class: CUSTOM-ELEMENT, substantially platform-
  assisted.** `<dialog>` + `showModal()` gives native top-layer
  stacking, `::backdrop` (replacing Overlay), Escape-to-close, and a
  basic focus trap with default focus-return, for free — covering the
  simple modal case well. What it does **not** give you, and what
  still needs custom JS: (1) the non-modal-branch-registry system
  (a portalled Popover nested logically-but-not-DOM-inside a modal
  Dialog) — no native concept of one top-layer element being "inside"
  another; (2) scroll-lock — `showModal()` does **not** lock body
  scroll on its own, so page-behind-modal scrolling needs its own fix
  regardless; (3) `<dialog>` has no light-dismiss (no backdrop-click-
  to-close) built in — you add a manual `::backdrop`/`event.target`
  click check yourself for the default Dialog case, and skip it
  entirely for Alert Dialog; (4) the non-modal Dialog variant has no
  `<dialog>` equivalent at all (non-modal `.show()` has no backdrop, no
  trap, no light-dismiss) and needs the full hand-rolled
  interact-outside bookkeeping Radix does.
- **Dependencies**: context, id, use-controllable-state, dismissable-
  layer, focus-scope, portal, presence, focus-guards. No popper —
  Dialog is centered via CSS, not anchored.
- **Port difficulty: M** — `<dialog>` covers the base modal case well;
  the branch-registry/scroll-lock-with-shards/non-modal remainder is
  the harder 20%.

#### Alert Dialog
- **Purpose**: an interruptive dialog requiring an explicit response
  (confirm/cancel) — e.g. destructive-action confirmation.
- **Anatomy**: `Root`, `Trigger`, `Portal`, `Overlay`, `Content`,
  `Action`, `Cancel` (both are just `Dialog.Close` under a different
  name — no separate `Close` export), `Title`, `Description`.
- **Relationship to Dialog**: a **thin config wrapper**, not a
  reimplementation — every non-Trigger/Content export is a literal
  pass-through to the corresponding `Dialog.*` part. The differences,
  precisely:
  - `modal` is forced `true` and not exposed as a prop — alert dialogs
    cannot be non-modal.
  - Content sets `role="alertdialog"` instead of `role="dialog"`.
  - Content hardcodes `onPointerDownOutside`/`onInteractOutside` to
    always `preventDefault()` — **outside click never dismisses an
    Alert Dialog** (matches the ARIA alertdialog pattern: must be
    dismissed via an explicit action). Escape is *not* overridden —
    Escape still closes it.
  - `onOpenAutoFocus` is overridden to focus the **Cancel** button
    specifically, not the first tabbable element (focus starts on the
    least-destructive action).
- **Interactivity class: CUSTOM-ELEMENT, same platform story as
  Dialog**, with one advantage: native `<dialog>` doesn't light-dismiss
  on backdrop click by default anyway, so "no outside-dismiss" is
  actually the natural default for `<dialog>`-backed Alert Dialog
  (easier than Dialog, which has to *add* light-dismiss you then have
  to *not* add here). Cancel-button auto-focus still needs a small
  script.
- **Dependencies**: context, dialog (wraps it wholesale).
- **Port difficulty: S** — nearly free once Dialog is ported: same base
  element, different default config.

#### Popover
- **Purpose**: anchored, click-triggered, non-modal-by-default overlay
  for rich content (vs. Dialog's centered, always-modal-by-default
  window).
- **Anatomy**: `Root`, `Anchor`, `Trigger`, `Portal`, `Content`, `Title`,
  `Description`, `Close`, `Arrow`.
- **DOM/ARIA**: Trigger: `aria-haspopup="dialog" aria-expanded
  aria-controls data-state`, auto-wrapped in a popper anchor. Content:
  `role="dialog"` (same role as Dialog, not a menu/tooltip role),
  `id aria-labelledby aria-describedby data-state`; exposes
  `--radix-popover-content-*` CSS vars (transform-origin, available-
  width/height, trigger-width/height) sourced from popper. Modal
  variant (opt-in, default `modal=false`): same `hideOthers`/branch-
  registry/disabled-outside-pointer-events pattern as Dialog's modal
  content.
- **Keyboard**: same dismissable-layer Escape/outside-dismiss and
  focus-scope trap pattern as Dialog, gated by `modal`.
- **Interactivity class: CUSTOM-ELEMENT, partially platform-assisted.**
  `popover="auto"` gives native top-layer + light-dismiss for the
  non-modal (default) case — a direct replacement for dismissable-
  layer's core job here. Gaps: (1) `popover` doesn't position anything —
  CSS anchor positioning or a JS positioner is still needed for side/
  align/collision/arrow; (2) `popover` has no modal mode — a
  `modal=true` Popover has no clean native counterpart and would need
  to fall back to `<dialog>`, an awkward two-element story; (3) the
  right-click/ctrl-click-outside guard and Safari tabIndex-container
  quirk are custom heuristics with no native equivalent. CSS anchor
  positioning covers flip/fallback but not the `available-width/height`
  reporting Popover's Content relies on for sizing — that still needs a
  `ResizeObserver` fallback, especially given uneven 2026 cross-browser
  anchor-positioning support.
- **Dependencies**: context, dismissable-layer, focus-guards, focus-
  scope, id, popper, portal, presence.
- **Port difficulty: L** — combines Dialog's focus-trap/branch-registry
  complexity (for modal mode) with full popper positioning; two
  orthogonal hard concerns in one component, though `popover=auto` +
  anchor positioning meaningfully shrinks the non-modal-only subset.

#### Hover Card
- **Purpose**: rich hover-triggered preview (e.g. a user-profile card
  on a link), non-modal, never traps focus.
- **Anatomy**: `Root`, `Trigger` (an `<a>`, not a button — reflects the
  "preview a link" use case), `Portal`, `Content`, `Arrow`. No
  Anchor/Title/Description/Close — the simplest anatomy of the overlay
  family.
- **DOM/ARIA**: Trigger sets only `data-state` — **deliberately no
  `aria-haspopup`/`aria-expanded`/`aria-controls`**, and Content sets
  **no `role` at all** — HoverCard content is treated as supplementary/
  non-essential and intentionally excluded from the formal ARIA
  relationship tree (unlike Tooltip's `role="tooltip"` +
  `aria-describedby`).
- **Keyboard/delay interactions** (the actual substance of this
  component): `openDelay` defaults 700ms, `closeDelay` 300ms.
  Pointer-enter starts an open timer (clearing any pending close);
  pointer-leave starts a close timer **unless** the user is mid-text-
  selection inside the content or has a pointer down on it (so you can
  select text in the card without it closing under you). Touch pointer
  types are excluded from hover triggering entirely. Content itself
  also wires pointer-enter/leave to keep it open while the cursor is
  over it (no gap-tolerance polygon here — unlike Tooltip, HoverCard
  relies purely on delay timers, not grace-area geometry). While open,
  `document.body.style.userSelect` is forced `none` during an
  in-content pointer-down so a drag-selection doesn't leak to the page.
  All tabbable descendants inside content are forced `tabindex="-1"` by
  default (no focus trap exists, so this prevents accidental Tab-into
  behavior unless a consumer opts back in).
- **Interactivity class: CUSTOM-ELEMENT — one of the least platform-
  replaceable in the library.** `popover="auto"` gives outside-click/
  Escape dismiss, but **zero** hover-delay logic — there is no native
  "open after N ms of hover" primitive at all, and the entire defining
  behavior here (delay timers, hover-bridging, selection-aware close-
  suppression) has no platform analog whatsoever. Positioning can share
  whatever CSS-anchor-positioning-first approach is built for Popover.
- **Dependencies**: context, use-controllable-state, popper, portal,
  presence, dismissable-layer, focus-scope (branch registration only,
  no trapping).
- **Port difficulty: M** — no focus-trap complexity lowers it relative
  to Dialog/Popover, but the delay/hover-bridge/selection-containment
  logic must be ported faithfully.

#### Tooltip
- **Purpose**: short, typically non-interactive text hint on hover/
  focus of a trigger. The most algorithmically involved primitive in
  the overlay family.
- **Anatomy**: `Provider` (new concept — coordinates delay-skipping
  *across* tooltips document-wide), `Root`, `Trigger`, `Portal`,
  `Content`, `Arrow`.
- **DOM/ARIA**: Trigger deliberately omits `type="button"` (tooltip
  triggers are often anchors, and `type` on an anchor means MIME type,
  not button type) and sets `aria-describedby` pointing at the content.
  Content: `role="tooltip"` **unless** an explicit `aria-label` override
  is given, in which case the visible content gets no role and a
  separate visually-hidden element carries `role="tooltip"` with the
  label — avoids double-announcing rich tooltip content.
  `data-state` is **three-way**: `closed | delayed-open | instant-open`
  (reflects whether the open went through the delay timer or the
  skip-delay fast path).
- **Keyboard/delay interactions**: default `delayDuration` 700ms.
  `TooltipProvider` tracks a document-wide `isOpenDelayed` flag and a
  `skipDelayDuration` (300ms): once any tooltip opens, subsequent
  tooltips within the grace window open **instantly**, resetting to
  delayed again 300ms after the last close. A custom document event
  ensures **only one tooltip is open at a time** anywhere on the page.
  Trigger uses `onPointerMove` (not `onPointerEnter`) to open, ignoring
  touch pointers and pointer-in-transit states (see below);
  `onPointerDown` closes immediately and suppresses the following
  `onFocus` (a mouse click shouldn't also show a tooltip via focus).
  When `disableHoverableContent` is false (default) and the content is
  itself interactive, moving the pointer from trigger to content is
  protected by a **convex-hull grace-area polygon** (Andrew's monotone
  chain algorithm) computed between the padded trigger-exit point and
  the content's corners — a global pointermove listener does a
  ray-casting point-in-polygon test and keeps the tooltip open while
  the cursor is inside this "safe diagonal travel" cone, closing it
  only if the cursor strays outside without reaching the content.
  Scrolling any trigger ancestor closes the tooltip. `aria-describedby`
  wiring plus this whole delay/skip-delay/single-open/grace-area system
  is the entirety of what needs porting — there is no focus trap and no
  modal behavior at all.
- **Interactivity class: CUSTOM-ELEMENT — least platform-replaceable of
  the batch.** Nothing in `popover`, `<dialog>`, or CSS anchor
  positioning addresses delay timers, cross-tooltip skip-delay
  coordination, single-open-at-a-time enforcement, or the convex-hull
  grace-area math — all of it is pure custom interaction logic with zero
  2024-2026 platform analog. Positioning alone can lean on anchor
  positioning, same caveats as the rest of the family.
- **Dependencies**: context, dismissable-layer, id, popper, portal,
  presence, use-controllable-state, visually-hidden. No focus-scope/
  focus-guards at all — Tooltip never traps or programmatically moves
  focus.
- **Port difficulty: L** — no focus-trap complexity, but the delay/
  skip-delay provider coordination and especially the point-in-polygon
  grace-area math make this the most algorithmically involved of the
  overlay family; dropping the grace-area logic in a "simplified" port
  would visibly regress UX (tooltip flickers shut on diagonal mouse
  travel).

#### Context Menu
- **Purpose**: right-click (or long-press on touch/pen) triggered menu
  anchored to the cursor/touch point. Wraps the base Menu primitive
  entirely — its own anatomy list is nearly identical to Dropdown
  Menu's, both being thin skins over the same engine.
- **What it adds on top of base Menu** (Menu's own internals are
  documented once, above, not repeated per wrapper):
  - **Virtual-point anchor**: `Trigger` renders a `<span>` (wraps
    arbitrary content, not a button), listens for the native
    `contextmenu` event, calls `preventDefault()`, captures
    `{x: clientX, y: clientY}`, and anchors the menu to a zero-size
    virtual `DOMRect` at that point rather than to any real DOM
    element — recreated on every reopen so right-clicking a new spot
    re-anchors correctly.
  - **Long-press for touch/pen**: a 700ms timer armed on pointerdown
    (mouse excluded), cancelled on pointermove/up/cancel — must be held
    stationary to trigger.
  - `disabled` leaves the native `onContextMenu` passthrough untouched —
    an explicit escape hatch back to the OS context menu.
  - Content defaults to `side="right" sideOffset={2} align="start"`
    (opens to the right of the click point, unlike Dropdown Menu's
    below-trigger default).
  - There is **no platform replacement for suppressing and replacing
    the native context menu** — `event.preventDefault()` on
    `contextmenu` is required in 2026 exactly as it was in 2020.
- **Interactivity class: CUSTOM-ELEMENT.** CSS anchor positioning is
  awkward here specifically because the anchor is a synthesized
  zero-size point, not a real stable element — it would need a
  synthesized 0×0 positioned DOM shim at the click coordinates to
  qualify as an `anchor-name` target, an extra step the Dropdown Menu
  case doesn't need.
- **Dependencies**: context, primitive, menu (the defining dependency),
  use-controllable-state.
- **Port difficulty: M**, assuming the base Menu primitive exists —
  its own incremental logic (virtual anchor, long-press timer,
  contextmenu interception) is self-contained and moderate.

#### Dropdown Menu
- **Purpose**: click-triggered menu anchored to a real trigger button —
  the standard app-menu pattern. Also a thin wrapper over base Menu.
- **What it adds on top of base Menu**:
  - Real anchored `<button>` trigger (not a virtual point):
    `aria-haspopup="menu"` (distinct from Dialog/Popover's
    `aria-haspopup="dialog"`), `aria-expanded`, `aria-controls`,
    `data-state`, `data-disabled`.
  - `onPointerDown`: left-button, non-ctrl clicks toggle open, and
    calls `preventDefault()` specifically when *opening* (not closing)
    so the trigger doesn't retain focus once content opens and compete
    with the content for it.
  - `onKeyDown`: Enter/Space toggles, **ArrowDown always opens**
    (doesn't toggle) — matches native combobox/menu-button convention
    of Down-arrow opening and moving into the list.
  - Content sets `aria-labelledby={triggerId}` — Context Menu's content
    has no such link since it has no persistent trigger element.
  - `modal` defaults `true`.
- **Comparison to Context Menu** (both wrap the same base Menu):
  Dropdown Menu's anchor is a real, stable DOM element, so CSS anchor
  positioning is a much cleaner fit here (`anchor-name` on the actual
  button, no virtual-point shim needed) — Dropdown Menu benefits most
  from anchor positioning of any primitive in this family, modulo
  submenu-chain positioning, which no platform feature addresses
  regardless of top-level anchor support.
- **Interactivity class: CUSTOM-ELEMENT.**
- **Dependencies**: context, use-controllable-state, primitive, menu,
  id.
- **Port difficulty: M**, dominated by the shared Menu primitive's
  difficulty — Dropdown Menu's own incremental logic is straightforward.

### Complex/bespoke widgets

These are the hardest primitives in the library, each combining several
of the shared-machinery concerns above plus bespoke measurement/gesture
logic of their own.

#### Select
- **Purpose**: WAI-ARIA listbox-pattern replacement for native
  `<select>` — rich option content, custom positioning, typeahead,
  native-form participation via a hidden shadow `<select>`.
- **Anatomy**: `Root`, `Trigger` (`role="combobox"`), `Value`, `Icon`
  (`aria-hidden`), `Portal`, `Content` (`role="listbox"`, one of two
  positioning strategies — item-aligned pixel math keeping the selected
  item under the trigger, or popper-anchored), `Viewport`
  (`role="presentation"`), `Group` (`role="group"`), `Label`, `Item`
  (`role="option"`), `ItemText`, `ItemIndicator` (`aria-hidden`),
  `ScrollUpButton`/`ScrollDownButton` (`aria-hidden`), `Separator`
  (`aria-hidden`), `Arrow`, and `BubbleInput` (a real hidden native
  `<select>`).
- **DOM/ARIA**: Trigger: `role="combobox" aria-controls aria-expanded
  aria-required aria-autocomplete="none" data-state data-disabled
  data-placeholder`. Content: `role="listbox" data-state`. Item:
  `role="option" aria-labelledby={textId} aria-selected={isSelected &&
  isFocused}` (deliberately coupled to focus, not just selection —
  Radix's own comment notes this fixes VoiceOver stuttering),
  `data-state data-highlighted data-disabled tabIndex={-1}`. **No
  `aria-activedescendant`** anywhere — Select moves real DOM focus onto
  option elements inside the portalled content, rather than using the
  combobox-activedescendant pattern.
- **Keyboard/pointer**: closed-trigger single-char keys do direct-jump
  typeahead (like native `<select>`); Space/Enter/Arrow keys open.
  Inside open content, Tab is blocked; Arrow/Home/End navigate a
  candidate list of enabled items. Mouse opens on `pointerdown` and
  selects on `pointerup` (drag-to-select pattern, with a 10px move
  threshold disambiguating "click that opened it" from "drag to
  select"); touch/pen instead open/select on plain `click`. Typeahead:
  1s reset timer, wraparound, repeated-character cycling.
- **Interactivity class: CUSTOM-ELEMENT.** State machine: closed →
  opening (pointer tracked) → open (focus moved in, position computed)
  → closing (focus returned to trigger); a live options registry; two
  full positioning engines; scroll-into-view + "expand viewport on
  scroll" + timer-driven auto-scroll buttons; dual-mode typeahead. The
  2024-2026 customizable `<select>` (`<selectedcontent>`,
  `::picker(select)`, `appearance:base-select`) is Chromium-only as of
  this writing, has no equivalent to Radix's pixel-aligned
  item-under-trigger positioning or its granular multi-part
  composition, and does not yet uniformly replace this primitive
  cross-browser. **Radix's own strongest hint for the port**:
  `SelectBubbleInput` — a real, visually-hidden, `aria-hidden`,
  `tabIndex={-1}` native `<select>` populated with real `<option>`s
  collected from every visible `Item` (remounted on option-set change,
  since native `<select>` only honors default-value if all options
  render simultaneously), dispatching a manual `change` event through
  the native property-setter descriptor for form/autofill participation
  — this hidden-native-select technique is directly reusable, framework-
  agnostic, and should be the port's answer to form participation.
- **Dependencies**: the largest in the library — collection, context,
  direction, dismissable-layer, focus-guards, focus-scope, id, popper,
  portal, presence, slot, use-controllable-state.
- **Port difficulty: L — the single hardest primitive in the library.**
  Two full hand-rolled positioning engines selectable per instance, the
  overlay/focus-trap complexity of Dialog/Popover combined with the
  scroll/measurement complexity of Scroll Area and the native-form-
  shimming of Slider/OTP, on the largest dependency surface of any
  primitive researched.

#### Slider
- **Purpose**: drag/keyboard-operable numeric value or multi-thumb
  range selector.
- **Anatomy**: `Root` (orientation-dispatching), `Track`, `Range`
  (absolutely positioned via computed start/end edge percentages),
  `Thumb` (composite: provider context + interactive trigger span +
  conditional `BubbleInput`).
- **DOM/ARIA**: Thumb: `role="slider" aria-label aria-valuemin
  aria-valuenow aria-valuemax aria-orientation data-orientation
  data-disabled tabIndex={0 unless disabled}`. **No `aria-valuetext`
  anywhere.** `aria-label` is auto-computed: >2 thumbs → "Value N of M",
  exactly 2 → "Minimum"/"Maximum", else omitted. **No `data-state`
  anywhere in this package** (unlike almost everything else in the
  library).
- **Keyboard**: Home/End jump the target thumb to min/max. Arrow/Page
  keys route through orientation- and direction-aware lookup tables (4
  combinations: horizontal LTR/RTL × vertical normal/inverted)
  determining step sign; PageUp/PageDown and Shift+Arrow step ×10,
  plain arrows ×1; a step-grid snap function handles on-grid vs.
  off-grid current values differently. **Multi-thumb collision**: two
  selectable strategies — default re-sorts the whole value array after
  each move and rejects the update if `minStepsBetweenThumbs` is
  violated (thumbs can swap identity/cross), or opt-in
  `preserveThumbOrder` clamps each candidate move to stay between its
  neighbors (thumbs halt, never cross). Pointer: clicking a thumb only
  focuses it; clicking the track computes the nearest thumb by value-
  distance and moves it; position→value uses a cached bounding-rect and
  a linear-scale interpolation whose range flips per orientation/RTL/
  inverted configuration.
- **Interactivity class: CUSTOM-ELEMENT for multi-thumb; NATIVE for
  single-thumb.** `<input type=range>` fully covers the **single-thumb**
  case — native drag, keyboard, min/max/step, real form participation,
  styleable via `::-webkit-slider-thumb`/emerging `::thumb`/`::track` —
  and should be the default port target for single sliders. It does
  **not** cover multi-thumb: native inputs support exactly one thumb;
  the classic two-overlapping-inputs hack has real hit-testing breakage
  (the top input's hit area swallows pointer events across its whole
  track, not just near its own thumb), no native way to render a
  connecting `Range` highlight, and no `minStepsBetweenThumbs`/ordering
  coordination — multi-thumb sliders need the full custom-element port
  with no native shortcut.
- **Dependencies**: context, use-controllable-state, direction,
  use-previous, use-size, collection.
- **Port difficulty: S** (single-thumb, native `<input type=range>`) /
  **L** (multi-thumb — full drag/pointer-capture state machine with
  RTL-aware math, step-grid snapping, two collision strategies, and a
  `BubbleInput` form shim, no native shortcut available).

#### Scroll Area
- **Purpose**: cross-browser custom-styleable scrollbars — native
  scrollbar hidden, replaced by a fully custom pointer-drag thumb/track,
  while actual scrolling stays on a native (visually-hidden-scrollbar)
  viewport underneath.
- **Anatomy**: `Root`, `Viewport` (`overflow:scroll`, injects a
  `<style>` tag hiding the native scrollbar cross-browser), `Scrollbar`
  (dispatches to four internal auto-hide variants — hover, scroll,
  auto, always-visible — by configured `type`), `Thumb`
  (`Presence`-gated), `Corner` (only when both axes are mounted and
  `type !== 'scroll'`).
- **DOM/ARIA**: **no `role`, `aria-hidden`, `aria-orientation`,
  `aria-controls`, or `tabIndex` anywhere in the package** — the entire
  accessibility story is "the underlying `overflow:scroll` div behaves
  like a native scrollable div," confirmed by full source read.
  `data-orientation` on the scrollbar wrapper; `data-state` ∈
  `visible|hidden`, computed independently per auto-hide variant (hover:
  pointerenter/leave on the root; scroll: its own small state machine;
  auto: `ResizeObserver`-derived overflow check; always: static
  visible). Sizes are exposed only as CSS vars
  (`--radix-scroll-area-corner-width/height`,
  `-thumb-width/height`), never ARIA.
- **Keyboard/pointer**: **zero `onKeyDown` handlers anywhere** — keyboard
  scrolling (arrows, space, PgUp/Dn, Home/End) works unmodified/natively
  because real scrolling happens on the native viewport underneath.
  Pointer drag: thumb pointerdown records offset-within-thumb; track
  pointerdown captures the pointer, caches the bounding rect, disables
  Safari text-selection, forces `scroll-behavior:auto`; drag position is
  converted through a linear-scale (RTL-flipped) interpolation into
  `scrollLeft`/`scrollTop`. The thumb's visual position is synced the
  other direction via an **`requestAnimationFrame` polling loop**
  (deliberately not raw `scroll` events, to avoid scroll-linked-effects
  jank), applying `translate3d`. A non-passive `wheel` listener on
  `document` selectively `preventDefault()`s only within scrollbar
  bounds. Three separate `ResizeObserver`s (thumb sizing, auto-hide
  visibility, corner sizing), each rAF-guarded against the benign
  ResizeObserver loop-limit warning.
- **Interactivity class: CUSTOM-ELEMENT.** Needs: a `ResizeObserver`
  pair computing thumb ratio/size (18px floor, matching macOS);
  bidirectional pointer↔scroll coordinate transforms (RTL-aware); four
  independent auto-hide behaviors driven by a `scrollHideDelay` (600ms
  default); corner cross-observation of both perpendicular scrollbars.
  CSS `scrollbar-color`/`scrollbar-width` (or the emerging `::scrollbar`
  pseudo-element) covers a **narrower** case — recoloring the browser's
  own scrollbar, with no arbitrary child content in the thumb, no
  scriptable corner, and critically no coordinated show/hide choreography
  (native auto-hide is OS-controlled, not stylable) — and cross-engine
  CSS scrollbar-styling parity is still uneven in 2026 (Safari
  `::-webkit-scrollbar` vs. Firefox `scrollbar-color` vs. standardizing
  `::scrollbar`). CSS-only suffices for simple recoloring; Radix's fully
  custom thumb solves for pixel-identical cross-browser styling plus
  corner-handling plus coordinated hide/show that CSS scrollbar styling
  still can't fully replicate.
- **Dependencies**: notably lean for a CUSTOM-ELEMENT case — primitive,
  presence, context, use-callback-ref, direction, use-layout-effect. No
  focus/portal/controllable-state dependency at all (no ARIA, no focus
  management, no open/close state).
- **Port difficulty: L** — driven entirely by observer/measurement/
  drag-math density (four show/hide variants, bidirectional coordinate
  transforms, three independently-debounced `ResizeObserver`s,
  non-passive wheel handling, Safari text-selection workaround) rather
  than by ARIA/focus complexity, of which there is none.

#### Toast
- **Purpose**: auto-dismissing notifications with a fixed viewport,
  swipe-to-dismiss, pause-on-hover/focus, and a screen-reader
  announcement mechanism engineered around real Safari/VoiceOver/NVDA
  live-region bugs.
- **Anatomy**: `Provider` (no DOM — context + collection), `Viewport`
  (`role="region" aria-label`, wraps two focus-proxy elements plus a
  `<ol tabIndex={-1}>`), `Root` (portals a `<li tabIndex={0}>` into the
  viewport's list, plus a separately-portaled announce node), `Title`/
  `Description` (plain divs), `Action`/`Close` (buttons).
- **DOM/ARIA**: **always `role="status"`** — Radix explicitly avoids
  `role="alert"` in source comments, citing SR "stuttering" issues; only
  `aria-live` varies by `type`: `foreground` → `assertive`, `background`
  → `polite`. **No `aria-atomic` anywhere.** The live-region mechanism
  is unusual: a *separate*, freshly-created announce node (not the
  visible toast) is portaled to `document.body`, populated by walking
  the toast's DOM into an *array* of text strings (not concatenated —
  the array form lets screen readers pause naturally between nodes),
  rendered after a double-`requestAnimationFrame` delay (needed for
  reliable NVDA announcement) and unmounted roughly a second later —
  this fresh-node-per-announcement pattern is a deliberate workaround
  for AT engines failing to announce updates to an already-populated
  live region. `data-state`/`data-swipe-direction` are always present;
  `data-swipe` ∈ `start|move|cancel|end` and swipe-offset CSS vars are
  set imperatively during the gesture.
- **Keyboard/pointer**: swipe uses pointer capture with a directional
  dead-zone (2px mouse / 10px touch) to recognize intent, clamped so the
  toast can't be dragged the wrong way, and a configurable distance
  threshold (50px default) deciding close-vs-snap-back on release.
  Pause/resume: per-toast timers recompute remaining time by
  elapsed-time subtraction (not a hard reset) on `focusin`/`focusout`/
  `pointermove`/`pointerleave`/window blur-focus, broadcast via custom
  DOM events since toasts are portaled outside the viewport's own React
  tree. An **F8 hotkey** focuses the viewport; manual head/tail
  focus-proxy elements compensate for reverse-tab-order since toasts
  are portaled outside natural DOM order.
- **Interactivity class: CUSTOM-ELEMENT (two coordinating pieces —
  viewport and per-toast item).** `popover="auto"` covers the *baseline*
  stacking/rendering problem for free (no z-index fights), and
  `role="status" aria-live="polite"` handles simple announcements — but
  gives **nothing** for swipe-to-dismiss (bespoke pointer math
  regardless), pause/resume timer bookkeeping (no native auto-dismiss-
  timer concept exists at all), inter-toast viewport stacking/ordering/
  F8-focus/reverse-tab-order (`popover` manages one element's own
  layering, not a sibling-ordering policy), or the fresh-node-per-
  announcement AT workaround (a static reused `aria-live` div is exactly
  the failure pattern this workaround exists to avoid). Note: Radix
  itself does not implement max-visible-count/collapsed-toast-count
  logic — that's left to consumer CSS/JS, so it's not something to port
  from source.
- **Dependencies**: primitive, collection, context, dismissable-layer,
  portal, presence, visually-hidden. No focus-guards/focus-scope — Toast
  hand-rolls its own tab-order proxying instead.
- **Port difficulty: L** — multi-toast distributed timer coordination
  across a portal boundary via custom DOM events, non-trivial swipe
  gesture math, and an accessibility workaround intricate enough that a
  "close enough" reimplementation risks silent regressions.

#### Form
- **Purpose**: wraps native `<form>` to wire label/control/message
  associations and surface the browser's Constraint Validation API
  (plus custom sync/async matchers) as declarative state, with a
  server-validation escape hatch.
- **Anatomy**: `Root` (`<form>`), `Field` (context: name/id/
  serverInvalid), `Label` (wraps the Label primitive), `Control`
  (`<input>` by default), `Message` (a `<span>`), `ValidityState`
  (render-prop only, no DOM), `Submit`.
- **DOM/ARIA**: `Label`'s `htmlFor` resolves from the Field's id.
  `Control`: `id` from the Field, `aria-invalid={serverInvalid ||
  undefined}` — **local/native invalidity is NOT mirrored to
  `aria-invalid`**, only server-side invalidity is — `aria-describedby`
  built by joining every currently-mounted `Message`'s id for that
  field (dedup'd against any author-supplied value), and `title=""`
  explicitly disabling the native validation-bubble tooltip. `data-
  valid`/`data-invalid` (present-or-omitted, never `"false"`) applied
  identically to Field, Label, and Control, from `validity?.valid`
  combined with `serverInvalid`. **No `role="alert"` anywhere** on
  Message — accessibility relies purely on `aria-describedby`, not
  live-region announcement.
- **Behavior**: built-in matchers are exactly the native `ValidityState`
  keys (`valueMissing`, `typeMismatch`, `patternMismatch`, `tooShort`,
  …) with default messages; custom matchers get cross-field access via
  `new FormData(control.form)` and are folded into the native validity
  object via `setCustomValidity`. Re-validation triggers on the native
  `change` event and on native `invalid` (submit-time), not on every
  keystroke — React's `onChange` only clears the error state
  immediately so it disappears as soon as retyping starts, but doesn't
  re-validate until `change`/submit. `checkValidity`/`reportValidity`
  are never called explicitly — Radix relies on native submission
  validation firing `invalid` per control. `serverInvalid` is the
  server-side escape hatch, auto-cleared on submit/reset. Focuses the
  first invalid control on native-invalid submit, separately auto-
  focuses on a `serverInvalid` transition.
- **Interactivity class: NATIVE-dominant — by far the thinnest JS layer
  in the complex-widget batch.** The native Constraint Validation API
  (`required`, `pattern`, `type=email`, `min`/`max`, `:valid`/`:invalid`
  CSS, `element.validity`, the native `invalid` event on submit) does
  the overwhelming majority of the work with zero JS. The only genuinely
  needed JS: `change`/`invalid`/`reset` listeners toggling `data-valid`/
  `data-invalid`, `setCustomValidity` + `FormData` glue if cross-field/
  async validators are wanted, `aria-describedby` string maintenance as
  messages mount/unmount, and two focus-management routines. No portals,
  no keyboard-nav graph, no floating positioning, no lifecycle
  complexity — a small progressive-enhancement controller suffices, and
  it degrades gracefully to native validation bubbles with zero JS.
- **Dependencies**: context, id, label.
- **Port difficulty: S — the easiest primitive in the complex-widget
  batch.** Almost entirely server-rendered `id`/`name`/`htmlFor`/
  `aria-describedby` bookkeeping computable at template-render time;
  only validation re-trigger glue and the describedby-dedup logic need
  real JS. (Note: adr/0023 already specifies prologex's own forms
  subsystem — this package is worth reading closely for the exact
  `aria-invalid`/`aria-describedby` wiring convention to match, not for
  a wholesale port of Radix's validation model.)

#### One-Time Password Field
- **Purpose**: multi-box OTP/verification-code entry — N real
  single-character `<input>`s with unified keyboard nav, paste-
  splitting, and Safari/iOS-autofill-compatible `autocomplete="one-
  time-code"` heuristics.
- **Anatomy**: `Root` (`role="group"`, wraps roving-focus + a
  collection, handles paste at the group level), `Input` (one real
  `<input>` per character box), `HiddenInput` (`<input type="hidden"
  readOnly>` — the actual form-submittable value).
- **DOM/ARIA**: each box: `aria-label="Character {i+1} of {N}"` — no
  `aria-hidden` anywhere; each box carries its own label instead of a
  combobox-style pattern. **Only the currently-tab-stopped box** gets
  `autoComplete="one-time-code"` plus a full-length `maxLength`
  matching the total box count (masquerading as able to accept the
  whole pasted code, to satisfy Safari/iOS autofill heuristics); every
  other box gets `autoComplete="off"` plus four distinct password-
  manager-suppression `data-*` attributes.
- **Keyboard/paste**: paste (or an autofill-driven multi-character
  input event) strips whitespace, filters through the configured
  validation pattern, slices to the box count, updates every box
  synchronously, and focuses the last-filled box. Typing a character
  auto-advances to the next box, or re-selects the last box for easy
  retyping. Backspace on an empty box focuses the previous box;
  backspace on a filled box clears it; Cmd/Ctrl+Backspace clears
  everything and refocuses the first box. Left/Right arrow movement is
  fully delegated to roving-focus. An "overtype-when-full" branch
  intelligently routes a new keystroke to the current or next box
  depending on caret position, emulating overflow-to-next-box UX
  despite each input's own `maxLength=1`. Enter submits the enclosing
  form. Clicking anywhere clamps focus to the first not-yet-fillable
  position — you cannot focus a "future" empty box out of order.
- **Interactivity class: CUSTOM-ELEMENT — genuinely unavoidable, no
  native equivalent.** No `ElementInternals`/`attachInternals()` usage
  anywhere in the source — form participation is the plain hidden-input
  sibling technique, not the form-associated-custom-element API. There
  is no native "OTP box group" HTML element; `autocomplete="one-time-
  code"` is only a hint on ordinary text inputs. State machine: an
  ordered box registry, a single source-of-truth value array, a
  roving-tabindex focus layer, and a reducer (set/clear/clear-all/paste)
  with synchronous state-and-focus updates to avoid flicker, plus a
  short-lived flag disambiguating native `change`/`input` firing after
  keydown vs. cut vs. autofill.
- **Dependencies**: roving-focus, collection, use-controllable-state,
  context, direction — this primitive alone requires three of the
  meatiest shared-machinery packages to already exist.
- **Port difficulty: L** — requires three cross-cutting abstractions
  (ordered collection, roving-focus, controllable-state-equivalent) as
  prerequisites, plus a synchronous state+focus dispatcher (no direct
  vanilla-JS equivalent to React's `flushSync` — state and focus updates
  must land in the same task/microtask to avoid visible flicker) and
  several easy-to-regress behaviors (overtype-to-next-box, cut/paste/
  autofill disambiguation, the single-active-box autocomplete trick).

#### Password Toggle Field
- **Purpose**: wraps a native password `<input>` with a `<button>` that
  toggles `type` between `password`/`text`, preserving focus/cursor
  position, and auto-hiding on form submit/reset.
- **Anatomy**: `Root` (context only, no DOM), `Input`, `Toggle`
  (button), `Slot` (conditional-render helper, no DOM), `Icon` (`<svg
  aria-hidden>` picking a visible/hidden glyph).
- **DOM/ARIA**: Input: `type={visible ? 'text' : 'password'}`,
  `autoComplete` (default `current-password`), `autoCapitalize="off"`,
  `spellCheck={false}`. Toggle: `aria-controls={inputId}`, `aria-label`
  (caller-provided, or auto-derived from the absence of inner text
  content via a `MutationObserver`). **No `aria-pressed` anywhere** —
  state is communicated purely via the dynamic label text, not the
  toggle-button ARIA pattern. **Pre-hydration**, the toggle defaults to
  `aria-hidden ??= true` and `tabIndex ??= -1` — deliberately inert to
  AT/keyboard before client JS attaches, avoiding both layout shift and
  exposing a non-functional control. Icon is unconditionally
  `aria-hidden`. **No `data-*` attributes anywhere** in this package.
- **Keyboard/focus interactions**: toggling is click-only (no keyboard
  shortcut). The input's `onBlur` (which fires naturally when the
  toggle button is clicked) records `selectionStart`/`selectionEnd`;
  after the type swap, focus is restored to the input and the recorded
  selection is reapplied via a deferred `requestAnimationFrame` — this
  is necessary because changing an `<input>`'s `type` resets native
  selection state. A pointer-vs-keyboard-activation flag (set on
  pointerdown, cleared via a fallback timer/idle callback) disambiguates
  real pointer clicks (which need focus restored) from keyboard-driven
  button activation. **No auto-hide-after-N-seconds and no auto-hide-
  on-blur** — the only auto-hide is on the ancestor `<form>`'s native
  `reset`/`submit` events, to prevent the browser from remembering the
  revealed value.
- **Interactivity class: CUSTOM-ELEMENT, but narrow scope; no
  `ElementInternals`/form-associated-custom-element usage** — not
  needed, since the wrapped `<input>` is itself the real
  form-participating element. There is no native "reveal password"
  control exposed to page authors (built-in browser reveal icons in
  `type=password` inputs aren't controllable this way), so some custom
  toggle logic is unavoidable, but the scope — one button, one input, no
  multi-element orchestration — is much smaller than OTP's. The
  pre-hydration `aria-hidden`+`tabindex=-1` pattern maps directly onto
  prologex's server-streamed-then-upgraded custom-element lifecycle:
  render inert, then flip both attributes on custom-element upgrade.
- **Dependencies**: use-controllable-state, id, use-effect-event
  (React-only, droppable), context.
- **Port difficulty: M** — far simpler than OTP (no collection/
  roving-focus, no multi-element synchronized-update cascades); the
  nuance is entirely in precise focus/selection restoration across the
  type swap and the pre-hydration inert-button pattern.

---

## Recommended porting order

Grouped by shared-machinery dependency so each phase's prerequisites are
already done. Within a phase, order is roughly cheapest/most-isolated
first.

1. **Foundations (no client JS, unblock everything downstream)**
   AspectRatio, Label, Separator, VisuallyHidden, AccessibleIcon,
   Progress. Establishes the template-authoring conventions
   (attribute computation from props, `data-state` idioms) every later
   component reuses.
2. **Shared machinery, tier 1 (needed by almost everything)**
   Port as vanilla-JS modules, not components: the `composeEventHandlers`/
   prop-merge helper (from `primitive`/`slot`'s reusable parts), an ID
   generator template helper (`id`), a `ResizeObserver`+rAF-debounce
   helper (`use-size`'s core), the collection/ordered-registry pattern
   (`collection`, simplified for real DOM order), and the roving-focus
   controller (`roving-focus`) — the single highest-leverage shared
   module, since Tabs/Toolbar/Menu/Menubar/RadioGroup/ToggleGroup/OTP
   all need it.
3. **Native-backed form controls (S, mostly zero JS)**
   Switch, Toggle, Radio Group (native `<input>` variant), Checkbox
   (2-state; indeterminate as a small follow-up). Confirms the
   native-first pattern before tackling anything harder.
4. **Avatar** (S/M) — first small CUSTOM-ELEMENT, isolated scope
   (image load/error), good pilot for the "minimal custom element"
   pattern the rest of the port will reuse.
5. **Collapsible → Accordion** (S/M → L) — Collapsible first (static
   `<details>`-backed case, then animated JS case); Accordion reuses it
   plus the collection pattern from phase 2. Ship the native
   `<details name>`-backed `single+collapsible` case first, treat
   `multiple`/`collapsible=false`/arrow-nav as later enhancement.
6. **Roving-focus consumers (M, now that phase 2 exists)**
   Toggle Group, Toolbar, Tabs — all thin applications of the shared
   roving-focus controller with component-specific ARIA wiring.
7. **Dialog family (M, biggest native-platform win)**
   Dialog on `<dialog>`/`showModal()`, then Alert Dialog (S, a config
   wrapper once Dialog exists). Establishes the `<dialog>`-based
   pattern and the branch-registry concept needed later by Popover.
8. **Shared machinery, tier 2 (popper-adjacent)**
   Build the positioning module: CSS-anchor-positioning-first with a
   JS (floating-ui-style, but much smaller) fallback for `shift`,
   custom collision boundaries, and available-size reporting. Needed by
   everything below.
9. **Popper-based overlays without hover-delay (M/L)**
   Popover (reuses Dialog's branch-registry + tier-2 positioning).
10. **Menu (L, shared machinery, do this once)**
    The base Menu engine — roving-focus-in-a-popup, typeahead,
    hover-delay submenus, pointer-grace polygon, RTL key maps,
    close-tree-on-select — built as one module, not per-wrapper.
11. **Menu wrappers (M each, thin once Menu exists)**
    Dropdown Menu, Context Menu, Menubar (in that order — Menubar adds
    a coordination layer on top and should come last).
12. **Delay-driven overlays (M/L, no native shortcut)**
    Hover Card, then Tooltip (hardest of the pair — grace-area convex-
    hull math).
13. **Navigation Menu (L, standalone — don't block other work on it)**
    Hardest in the menu/nav family; benefits from nothing built in
    phases 8-12 (it doesn't use popper or roving-focus). Schedule
    independently.
14. **Form** (S) — can actually be ported any time after phase 1; listed
    here because it's a natural pairing with prologex's own adr/0023
    forms work, not because of a dependency chain.
15. **Slider** (S for single-thumb via `<input type=range>`, L for
    multi-thumb) — ship the native single-thumb case early (could move
    up near phase 3), treat multi-thumb as a distinct, later L-effort
    project.
16. **Password Toggle Field** (M) — small, isolated, no shared-machinery
    prerequisites beyond phase 2's helpers.
17. **One-Time Password Field** (L) — needs roving-focus and collection
    (phase 2) plus a synchronous state+focus dispatch pattern; schedule
    after phase 6 proves the roving-focus module works.
18. **Toast** (L) — needs `popover`-based stacking (a simpler
    replacement for `dismissable-layer`'s job here) plus its own
    swipe-gesture and cross-portal timer-coordination logic; largely
    independent of the menu/overlay track, can run in parallel with
    phases 9-13.
19. **Scroll Area** (L) — the most self-contained L: no ARIA, no focus
    management, no dependency on any other primitive's port. Can be
    done any time; scheduled last only because it's pure
    observer/gesture engineering with no reuse payoff for anything else.
20. **Select** (L, hardest in the library) — deliberately last: it
    depends on positioning (phase 8), dismissable-layer-equivalent
    dismiss (phase 7/9), focus-scope, collection, and presence, and
    benefits from every pattern proven out in phases 1-19 (native hidden-
    input form participation from Slider/OTP, two positioning engines
    from Popover's playbook, scroll/measurement lessons from Scroll
    Area).

---

## Summary counts

**By interactivity class** (33 components; several are marked with a
split because the "simple"/native path and the "full-fidelity" path
genuinely differ):

- **STATIC** (zero JS ever): AspectRatio, Label, Separator,
  VisuallyHidden, AccessibleIcon, Progress, AccessibleIcon's dependency
  VisuallyHidden (counted once) — **6 components**.
- **NATIVE** (a native element/attribute covers the common case with
  zero or near-zero JS): Switch, Toggle, Radio Group (native-input
  variant), Checkbox (2-state variant), Collapsible (static-open/closed
  variant), Slider (single-thumb variant), Form (Constraint Validation
  API does most of the work) — **7 components** (each with a
  CUSTOM-ELEMENT escalation path noted below for their non-trivial
  variant).
- **CUSTOM-ELEMENT** (no full native substitute; real client JS
  required): Avatar, Toggle Group, Accordion, Tabs, Toolbar, Navigation
  Menu, Menubar, Dialog, Alert Dialog, Popover, Hover Card, Tooltip,
  Context Menu, Dropdown Menu, Select, Slider (multi-thumb), Scroll
  Area, Toast, One-Time Password Field, Password Toggle Field —
  **20 components** (several of these are still substantially
  *platform-assisted*, see below — "needs a custom element" is not the
  same as "gets nothing from the platform").

**By port difficulty** (33 components, using the harder end where an
entry spans two difficulties):

- **S**: AspectRatio, Label, Separator, VisuallyHidden, AccessibleIcon,
  Progress, Switch, Toggle, Radio Group (native variant), Checkbox,
  Collapsible (static variant), Toolbar, Alert Dialog, Form, Slider
  (single-thumb variant) — **15**.
- **M**: Avatar, Toggle Group, Collapsible (animated variant), Tabs,
  Menubar, Context Menu, Dropdown Menu, Dialog, Hover Card, Password
  Toggle Field — **10**.
- **L**: Accordion, Navigation Menu, Popover, Tooltip, Select, Slider
  (multi-thumb variant), Scroll Area, Toast, One-Time Password Field —
  **9** (plus the base Menu shared-machinery package itself, which is L
  as a standalone porting unit even though it's infrastructure, not a
  public component).

**Shared machinery** (25 packages inventoried): 11 are genuinely
reusable concepts worth porting (dismissable-layer, focus-scope,
focus-guards, popper, roving-focus, collection, presence, portal, slot,
id, arrow — arrow and id being trivial); of those, 4 are substantially
or fully obsoleted by native platform features (focus-guards, most of
presence, much of dismissable-layer, all of portal); the remaining 14
(compose-refs, context, direction, primitive's asChild machinery,
use-callback-ref, use-controllable-state, use-effect-event,
use-is-hydrated, use-layout-effect, use-previous, use-escape-keydown,
use-rect, announce, use-size's React wrapper) are pure React-runtime
concerns with no server-rendered/vanilla-JS equivalent needed at all —
two of them (use-rect, announce) appear to be dead/orphaned even inside
Radix's own current codebase.

---

## Where the 2026 HTML platform replaces Radix's React machinery

This is the single biggest simplification lever available to a
server-rendered port, and it applies unevenly — some primitives shed
most of their JS, others shed almost none. Ranked by impact:

1. **`<dialog>` + `showModal()` — the biggest win, for Dialog and Alert
   Dialog.** Native top-layer stacking, `::backdrop` (replacing
   `Overlay`), Escape-to-close, and a basic focus trap with
   default focus-return all come for free, eliminating the need for
   `focus-guards` entirely and most of `focus-scope`/`dismissable-layer`
   for the modal case. What remains, and must still be hand-built: (a)
   scroll-lock — `showModal()` does **not** lock body scroll, so this is
   not actually free; (b) the branch-registry concept for a non-modal
   popover nested logically-but-not-DOM-inside a modal dialog (adr/0024's
   Turbo Frame world will make cross-boundary "logically nested" content
   common, so don't skip this); (c) light-dismiss (backdrop-click-to-
   close) isn't native to `<dialog>` at all and must be added by hand for
   the default Dialog case (and *not* added for Alert Dialog, which is
   the easy path); (d) the non-modal Dialog variant has no `<dialog>`
   equivalent whatsoever.
2. **`popover="auto"` + `popovertarget` — a large but partial win for
   Popover, Dropdown Menu, Context Menu, and Toast; near-zero win for
   Hover Card and Tooltip.** Native top-layer rendering and light-dismiss
   (outside click + Escape) directly replace `dismissable-layer`'s core
   job for the common non-modal case, with zero z-index/portal
   management needed. The ceiling on this win is sharply different per
   component: Dropdown Menu and Popover get real value (their
   dismissal model *is* light-dismiss); Toast gets the stacking/z-index
   piece but nothing for its swipe/pause/timer/multi-toast-ordering
   logic; Hover Card and Tooltip get essentially nothing, because their
   defining behavior is hover-delay timing, not dismissal — `popover`
   has no concept of "open after N ms of hover" at all. Context Menu's
   anchor is a synthesized cursor point, not a real element, so even the
   positioning half of this win is awkward there. There is also **no
   native modal-popover mode** — a `modal=true` Popover has to fall back
   to `<dialog>`, which is an awkward two-primitive story worth deciding
   on deliberately rather than discovering mid-port.
3. **CSS anchor positioning (`anchor()`/`position-anchor`/
   `position-try`) — solid but incomplete replacement for `popper`
   across every anchored primitive (Popover, Hover Card, Tooltip,
   Dropdown Menu, Context Menu, Select, Menu/submenus).** Declaratively
   covers static side/align placement and simple flip-on-overflow
   fallback for browsers that support it. It does **not** cover: (a)
   `shift`/`limitShift` (sliding to stay in-viewport while remaining
   attached to an edge, distinct from flipping to the opposite side);
   (b) the `size` middleware's dynamic "available space" measurement,
   which Popover/Tooltip/Hover Card/Select all expose as
   `--radix-*-content-available-width/height` CSS custom properties for
   consumers to size scrollable content against — CSS anchor positioning
   has no direct JS-readable equivalent to this yet, so a
   `ResizeObserver` fallback is still required wherever content needs to
   size itself to available space, not just avoid overflow; (c) custom
   (non-viewport) collision boundaries; (d) the `hide` middleware
   (fully hiding content when its *anchor* scrolls out of view, not just
   repositioning); (e) cross-browser support is still uneven as of 2026
   (Safari and Firefox lag Chromium's implementation), so a JS
   positioning fallback path is a hard requirement, not an edge case, for
   any primitive that needs to work everywhere. Recommendation: ship a
   CSS-anchor-positioning fast path with a small JS fallback/enhancement
   layer, not a JS-only or CSS-only decision.

Two secondary but concrete wins worth calling out separately: `<details
name="group">` (broad support since ~2023-2024) covers Accordion's most
common configuration (`type=single, collapsible=true`) with zero JS,
though not `collapsible=false`, multi-open, `data-state` styling hooks,
or arrow-key navigation between headers; and native `<input
type=checkbox>`/`<input type=radio>` fully cover Switch/Toggle/2-state-
Checkbox/Radio-Group with zero JS at all, including — for Radio
Group specifically — the arrow-key-auto-select behavior Radix hand-rolls
elsewhere, which the browser already implements for real radio inputs.
The recurring theme across every "no native win" case (roving-focus
arrow navigation in Tabs/Toolbar/Toggle Group/Accordion/OTP, the
pointer-grace-area polygon math in Menu/Tooltip, the hover-delay timers
in Hover Card/Tooltip, and Navigation Menu's viewport/indicator geometry
end to end) is the same: the platform has no concept of composite-widget
keyboard navigation, timed hover intent, or gesture-based dismissal
tolerance — these remain irreducibly custom-element territory regardless
of how far `popover`/`<dialog>`/anchor-positioning advance.
