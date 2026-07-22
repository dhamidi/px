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
// <px-hover-card> is ui/hover_card.pl's (adr/0026): "lib/popper"'s next
// consumer after Popover/Tooltip, standalone (no dependency on either
// sibling's element -- shares only the popper.js positioning module).
// Content's native `popover="auto"` gives Escape/outside-click dismiss
// with zero JS (a deliberately different choice than Tooltip's
// `manual` -- see prolog/ui/hover_card.pl's header for why); this
// element supplies the one thing the platform has no primitive for at
// all -- openDelay/closeDelay hover timers (700ms/300ms, Radix's
// defaults), with pointerenter on Content itself canceling a pending
// close timer as the "reach the card before closeDelay elapses" grace
// bridge -- plus position/autoUpdate for placement, same as
// components/popover.js. Mouse-pointer only; never opens via focus,
// click, or touch, matching upstream's hover-only-by-design scope.
import "components/hover_card";
// <px-dropdown-menu> is ui/dropdown_menu.pl's (adr/0026): "lib/menu"'s
// proving consumer -- the shared Menu engine (roving highlight,
// typeahead, submenu hover-delay/keyboard/positioning via "lib/popper",
// checkbox/radio toggling, close-on-select) ported once as shared
// infrastructure for Dropdown Menu now and Context Menu/Menubar next.
// Trigger's native `popovertarget` and Content's native `popover=
// "auto"` already open/close/dismiss with zero JS; this element adds
// ArrowDown-always-opens, auto-focus-first-item on every open path,
// and installs "lib/menu" onto Content once at connect time.
import "components/dropdown_menu";
// <px-context-menu> is ui/context_menu.pl's (adr/0026): "lib/menu"'s
// second consumer -- Dropdown Menu's closest sibling, minus a real
// trigger element, plus a pointer-anchored open path. Content's native
// `popover="auto"` still gives Escape/outside-click dismiss with zero
// JS, but OPENING has no native equivalent at all (no click-triggered
// `popovertarget` exists for the `contextmenu` event or a long-press
// gesture) -- this element's own job is preventDefault()-ing the
// native contextmenu event (mouse) / running a 700ms long-press timer
// (touch/pen), anchoring Content to the pointer's exact point via a
// virtual anchor object ("lib/popper"'s position() only ever calls
// anchorEl.getBoundingClientRect(), so a plain JS object works), and
// installing "lib/menu" onto Content once at connect time -- same
// engine Dropdown Menu already proved out.
import "components/context_menu";
// <px-menubar> is ui/menubar.pl's (adr/0026): "lib/menu"'s third
// consumer -- one instance per top-level menu's Content, same as
// Dropdown Menu -- PLUS "lib/roving-focus" (reused unmodified, same as
// components/toolbar.js) over the trigger row for top-level
// ArrowLeft/ArrowRight. This element's own job is purely coordination:
// hover-switch-to-a-different-menu once ANY menu is already open (one
// showPopover() call -- native popover light-dismiss auto-closes the
// previously-open sibling), and bridging ArrowLeft/ArrowRight between
// "move between top-level triggers" (lib/roving-focus's job) and "move
// to the adjacent menubar menu from inside an open Content" (yielding
// to lib/menu.js's own submenu open/close handling via
// event.defaultPrevented) -- see that file's header for the full
// mechanism. Neither shared engine is modified for this.
import "components/menubar";
// <px-navigation-menu> is ui/navigation_menu.pl's (adr/0026): STANDALONE
// per docs/radix-port-analysis.md ("benefits from nothing built in
// phases 8-12... schedule independently") -- imports NEITHER "lib/menu"
// (no role=menu semantics here at all) NOR "lib/popper" (Content is
// positioned by plain CSS relative to its own Item, not a shared
// portaled viewport -- see prolog/ui/navigation_menu.pl's header,
// "Viewport decision"). This element's own job: a ~200ms hover-open
// delay that becomes instant when switching directly between two
// triggers while one is already open (menubar-like), a pointerover-on-
// panel grace bridge (same precedent as components/hover_card.js),
// click/Enter open with no delay (native <button> activation), Escape/
// blur-out/outside-pointerdown dismissal (no native `popover` here --
// see that module's "Platform choice"), and computing `data-motion`
// (from-start/from-end/to-start/to-end) from comparing trigger list
// order on every switch.
import "components/navigation_menu";
// <px-otp-field> is ui/otp_field.pl's (adr/0026): a hand-rolled
// keyboard/paste state machine over N single-character cells -- does
// NOT import "lib/roving-focus" (see that module's Prolog header for
// why the shape doesn't fit: every cell stays in the normal Tab
// order, there is no single roving tab stop). This element's own job:
// auto-advance focus on typing, Backspace/Cmd+Backspace/ArrowLeft/
// ArrowRight navigation, sanitizing + distributing a pasted or
// autofill-delivered full code across every cell, clamping click-to-
// focus at the first not-yet-filled cell, and keeping the sibling
// HiddenInput's `value` (plus each cell's own `data-filled` styling
// hook) live on every change.
import "components/otp_field";
// <px-scroll-area> is ui/scroll_area.pl's (adr/0026): platform-first --
// the real scrolling and the real visible scrollbar are both native
// (Viewport is `overflow: auto`, recolored via scrollbar-width/
// scrollbar-color + ::-webkit-scrollbar*, assets/css/ui.css); the
// decorative Scrollbar/Thumb/Corner anatomy is rendered for DOM/
// data-attribute contract fidelity only and is never painted. This
// element is a no-op for type=auto/always (both are static, zero JS);
// for type=hover/scroll -- the only two paths with no platform
// equivalent -- it toggles data-state=visible|hidden on the decorative
// Scrollbar part(s) (pointerenter/leave on Root for hover; Viewport
// `scroll` + a scrollHideDelay-driven timeout, 600ms default, for
// scroll), which a `:has()` selector in ui.css keys the real
// scrollbar's color off. No ResizeObserver, no requestAnimationFrame
// polling, no pointer-capture drag math -- none of that is needed once
// the real scrollbar already IS the visual thumb.
import "components/scroll_area";
// <px-slider> is ui/slider.pl's (adr/0026): NATIVE single-thumb --
// the real, styled `<input type=range>` already drags, keys and
// submits with zero JS (it IS the visible thumb; see that module's
// Prolog header for why Thumb collapses into it rather than a
// decorated sibling the way components/switch.js's control does).
// This element's only job is keeping the decorative `.px-slider-range`
// accent fill's `--slider-value` CSS custom property live off the
// input's native `input` event while dragging/keying, since nothing
// re-runs server-side markup mid-drag.
import "components/slider";
import "components/password_toggle_field";
// <px-form> is ui/form.pl's (adr/0026): the native Constraint
// Validation API (required/type=email/pattern/minlength/...) already
// computes correct element.validity with zero JS; this element's own
// job is purely the trigger + attribute mirroring novalidate turns
// off -- checkValidity() on focusout/submit, toggling
// data-valid/data-invalid on Field/Label/Control and hidden on the
// matching Message(s), preventDefault()-ing an invalid submit and
// focusing the first invalid control. Never touches aria-invalid
// (server-only truth, prolog/px_form.pl's adr/0023 422 escape hatch)
// or any Message carrying data-forced (real server error text, left
// undisturbed).
import "components/form";
// <px-toast-viewport>/<px-toast> are ui/toast.pl's (adr/0026): an F8
// hotkey that focuses the viewport's <ol> (toggling focus back on a
// second press), plus per-toast duration auto-dismiss timers that
// pause on pointerenter/focusin and resume -- via elapsed-time
// SUBTRACTION, not a hard reset -- on pointerleave/focusout, a
// data-toast-close click handler, and DOM removal once the
// data-state="closed" exit transition has had time to play. Nothing
// here implements swipe-to-dismiss (data-swipe-direction is emitted
// statically by the server and never touched) -- a documented,
// deliberate deferral; see that module's own header and
// prolog/ui/toast.pl's for the full accounting. Any toast reaching the
// DOM upgrades identically regardless of how it arrived: a page load,
// a client-side <template> clone, or a Turbo Stream `prepend` action
// from any server handler (adr/0024) -- the "prologex-native angle"
// prolog/ui/toast.pl's header and /ui/toast's own demo both document.
import "components/toast";
