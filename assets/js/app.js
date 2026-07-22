// assets/js/app.js -- the application's JS entrypoint (adr/0025).
//
// Loaded as a <script type="module"> by javascript_importmap_tags via the
// import map, so "turbo" below resolves to the content-hashed
// /assets/js/turbo-<hash>.js URL -- no bundler, no build step, exactly
// Rails 8's importmap-rails model.
import "turbo";
// px_ui components (adr/0026): each ships its own custom element,
// registered on import here. <px-toggle> is ui/toggle.pl's.
import "components/toggle";
// <px-avatar> is ui/avatar.pl's (adr/0026): watches its <img> for
// load/error and reflects the result onto its own data-state attribute.
import "components/avatar";
// <px-switch> is ui/switch.pl's (adr/0026): keeps aria-checked/data-state
// live on click -- the platform already handles the toggle itself.
import "components/switch";
// <px-checkbox> is ui/checkbox.pl's (adr/0026): only wraps the
// indeterminate case -- sets the JS-only .indeterminate property and
// keeps aria-checked/data-state live once a click resolves it away.
import "components/checkbox";
// <px-toggle-group> is ui/toggle_group.pl's (adr/0026): the library's
// first roving-focus consumer (assets/js/lib/roving-focus.js) --
// arrow-key/Home/End navigation across Items, plus instant click-flip
// of aria-pressed/aria-checked/data-state (type=single also enforces
// radio-like exclusivity across siblings).
import "components/toggle_group";
// <px-tabs> is ui/tabs.pl's (adr/0026): the library's second
// roving-focus consumer -- arrow-key/Home/End navigation across
// Triggers, plus automatic (focus-driven) activation switching
// aria-selected/data-state/hidden across Triggers/Content.
import "components/tabs";
// <px-accordion> is ui/accordion.pl's (adr/0026): a roving-focus
// consumer over Triggers (vertical), blocking the close of the one
// mandatory-open item via `beforetoggle` when type=single/
// collapsible=false (native <details name> grouping already handles
// opening-exclusivity with zero JS), and re-syncing data-state/
// aria-expanded/aria-controls/aria-disabled after native toggle
// events.
import "components/accordion";
// <px-toolbar> is ui/toolbar.pl's (adr/0026): another roving-focus
// consumer -- ONE arrow-key/Home/End scope spanning every Button, Link
// and embedded Toggle Group Item as a single flat tab-stop domain, plus
// the Link Space-key patch. Reaches into any nested <px-toggle-group>
// to disable ITS independent roving-focus scope (see the component's
// own header) -- must load after "components/toggle_group" so that
// reach-in target is registered first.
import "components/toolbar";
// <px-popover> is ui/popover.pl's (adr/0026): the first consumer of
// "lib/popper" (assets/js/lib/popper.js). Trigger's native
// `popovertarget` and Content's native `popover="auto"` already
// open/close/dismiss with zero JS (top-layer + Escape/click-outside);
// this element's only job is positioning Content relative to Trigger
// (side/align/collision-flip) on the native `beforetoggle`/`toggle`
// events, keeping it positioned via popper.js's `autoUpdate` while
// open.
import "components/popover";
// <px-dialog> is ui/dialog.pl's (adr/0026): native <dialog> +
// showModal() already gives top-layer stacking, ::backdrop, Escape-to-
// close and a basic focus trap with zero JS; this element only adds
// what the platform doesn't -- body scroll-lock while open and
// outside-click (backdrop) light-dismiss for the modal case -- plus
// keeping the Trigger's aria-expanded/data-state in sync with
// Content's own data-state across every close path.
import "components/dialog";
// <px-tooltip> is ui/tooltip.pl's (adr/0026): "lib/popper"'s second
// consumer. Content's native `popover="manual"` gives top-layer
// stacking with zero JS auto-dismiss/single-open behavior to fight
// (unlike Popover's "auto", hover semantics need fully custom control
// over when to show/hide); this element supplies that control --
// delay/skip-delay timer coordination (delayDuration 700ms,
// skipDelayDuration 300ms, both Radix defaults) via a module-level
// shared "last closed at" timestamp, single-open-at-a-time
// enforcement, pointerenter/focus to open and pointerleave/blur/
// Escape to close immediately, touch pointers ignored -- plus
// position/autoUpdate for placement, same as components/popover.js.
import "components/tooltip";
