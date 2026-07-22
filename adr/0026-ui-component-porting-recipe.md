# 0026. px_ui: the Radix porting recipe

Status: Accepted

## Context

prologex gets a built-in component library by porting Radix UI's
primitives (docs/radix-port-analysis.md is the per-component analysis:
33 primitives — 6 STATIC, 7 NATIVE, 20 CUSTOM-ELEMENT — plus shared
machinery). Radix's React code is the behavioral spec, not code we
reuse: what we port is the *anatomy* (part hierarchy), the *DOM/ARIA
and data-attribute contract* (which is Radix's styling API), and the
*keyboard behavior*. Rendering is server-side through px_template
(adr/0019); interactivity, only where irreducible, ships as vanilla-JS
custom elements served through the asset pipeline (adr/0025) importmap.

## Decision — the recipe every component port follows

1. **One module per component**: `prolog/ui/<name>.pl`, loaded by
   `prolog/px_ui.pl`. Templates (`~>`) named `<component>_<part>`
   after Radix's anatomy — `dialog_trigger`, `dialog_content`,
   `tabs_list` — plus a top-level convenience template
   `<component>(Opts, Parts)` assembling the common case. Opts is a
   list (`[id(x), open(true), ...]`); parts are template terms.
2. **The contract is sacred**: every part emits exactly the roles,
   `aria-*`, and `data-state`/`data-*` attributes listed in the
   analysis doc for it. CSS targets `[data-state=...]` — same styling
   API as Radix. Deviations require a note in the module header.
3. **Platform first**: prefer `<dialog>`/`showModal`, the `popover`
   attribute + `popovertarget`, `<details>/<summary>`, native inputs —
   per the analysis doc's platform-replaces-React notes — before
   writing any JS. A custom element is only justified for behavior the
   platform cannot express (roving tabindex, typeahead, grace-area
   polygons, hover-delay coordination, multi-thumb sliders).
4. **Custom elements wrap server markup**: `<px-<name>>` in
   `assets/js/components/<name>.js`, plain ES module, class extending
   HTMLElement, registered with `customElements.define` and imported
   via the importmap (`import "components/<name>"` from
   `assets/js/app.js`). The server-rendered markup inside must degrade
   usably without JS wherever the component allows it (progressive
   enhancement); where it can't (e.g. Select), the no-JS fallback is
   the native element variant. State lives in DOM attributes
   (`data-state`), mutated by the element — never a parallel JS store —
   so Turbo morphs/streams (adr/0024) can't desync it.
5. **Shared machinery are shared modules**: `assets/js/lib/<name>.js`
   (roving-focus.js, dismissable-layer.js, popper.js, presence.js…)
   ported once, in the analysis doc's dependency order, imported by
   component elements via the importmap. Prolog-side shared helpers
   (id generation, part-attr merging) live in `prolog/ui/_shared.pl`.
6. **Styling**: each component appends a section to
   `assets/css/ui.css` keyed off its data-attributes, using the app
   theme vars (adr/0025 pipeline serves it; px_ui's demo layout links
   it). Tasteful defaults, dark-theme native, overridable by apps.
7. **Every port ships with proof**: (a) a render test in
   `test/ui/<name>.pl` asserting the ARIA/data contract from rendered
   output (render_to_string), (b) a live demo: the component registers
   `px_ui:demo(Name, Order, DemoTemplateCall)` (multifile) and the
   kitchen-sink app at `/ui` (list) + `/ui/<name>` (render) picks it
   up automatically — the reviewer's acceptance bar is the demo page
   looking and behaving right, (c) a `git commit` + push of exactly
   its files: `Port ui/<name> (adr/0026)` with the standard
   Co-Authored-By trailer.
8. **Porting order** is the analysis doc's recommended order —
   statics, then native-backed, then roving-focus consumers, dialogs,
   positioning tier, menus, and Select last. A component agent must
   not begin a component whose listed dependencies aren't merged.

## Consequences

The library accretes component-by-component with no cross-component
coupling beyond declared machinery; each landing is independently
demoable at `/ui/<name>` and revertable as one commit. The data-state
contract means Radix's ecosystem styling knowledge transfers directly.
The custom-element rule keeps the framework's server-rendered,
no-build-step character: the importmap serves plain files; there is
still no bundler anywhere.
