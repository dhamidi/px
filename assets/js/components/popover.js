// assets/js/components/popover.js -- <px-popover> (adr/0026): the
// irreducible interactive sliver of the Popover port
// (prolog/ui/popover.pl). Plain ES module, no build step -- served
// through the importmap under the bare specifier "components/popover"
// (adr/0025), imported once from assets/js/app.js.
//
// prolog/ui/popover.pl already renders a fully working, if unpositioned,
// popover with ZERO JS: Trigger's native `popovertarget` attribute
// opens/closes Content, Content's native `popover="auto"` attribute
// gives top-layer stacking plus Escape/click-outside light-dismiss, and
// Close's `popovertarget`+`popovertargetaction="hide"` closes it --
// all browser-native, per the analysis doc's own recommended platform
// split (see prolog/ui/popover.pl's header, "Platform choice"). Without
// this element ever loading, Content still opens/closes/dismisses
// correctly; it just renders wherever the UA's top-layer default puts
// it, with no side/align/collision-flip relative to Trigger.
//
// This element's entire job is the one thing the platform genuinely
// cannot give for free (the analysis doc's own gap (1) for Popover):
// "`popover` doesn't position anything -- CSS anchor positioning or a
// JS positioner is still needed for side/align/collision/arrow." That
// positioner is assets/js/lib/popper.js's `position`/`autoUpdate` pair
// -- this is that shared module's first, proving consumer.
//
// Wiring: `<div popover>` elements fire a `ToggleEvent` named
// `beforetoggle` (state about to change) and `toggle` (state just
// changed) -- exactly the same two events `<details>` fires, which
// assets/js/components/accordion.js already showed this codebase's
// pattern for. Both are listened for here, each doing half the job:
//
//   - `beforetoggle` fires before the browser's own show/hide takes
//     effect. Used ONLY to mirror `data-state`/`aria-expanded` onto
//     Trigger/Content immediately (so any CSS transition keyed off
//     `[data-state]` starts right away) and, on a close, to stop
//     `autoUpdate` right away -- no point positioning a panel that's
//     about to leave the top layer.
//   - `toggle` fires after the state change has taken effect -- Content
//     is now actually in the top layer / laid out, so its
//     `getBoundingClientRect()` is meaningful. Used ONLY to START
//     `lib/popper.js`'s `autoUpdate` (which itself calls `position`
//     once immediately, then keeps repositioning on scroll/resize/rAF
//     while open -- see that module's own header for the full
//     contract).
//
// `side`/`align`/`sideOffset`/`alignOffset` are read straight off
// Content's own `data-side`/`data-align`/`data-side-offset`/
// `data-align-offset` attributes (prolog/ui/popover.pl's own rendered
// values) -- no separate configuration surface, so a later server
// re-render that changes any of them is picked up on the next open with
// no separate sync code needed, same "DOM IS the state" rule
// roving-focus.js documents (adr/0026 rule 4).
//
// One more native-platform assist used here: since there is no static
// HTML attribute that starts a `[popover]` element already open (unlike
// `<dialog open>`), `connectedCallback` calls `.showPopover()` once if
// Content's server-rendered `data-state` is already `"open"` -- see
// prolog/ui/popover.pl's header, "open(true) needs JS to visually
// manifest", for the full rationale. That call fires this element's own
// `toggle` handler, so it runs down the exact same code path a user
// click would; nothing here special-cases the initial-open case beyond
// that one call.

import { position, autoUpdate } from "lib/popper";

const TRIGGER_SELECTOR = ".px-popover-trigger";
const CONTENT_SELECTOR = ".px-popover-content";

class PxPopover extends HTMLElement {
  connectedCallback() {
    this._trigger = this.querySelector(TRIGGER_SELECTOR);
    this._content = this.querySelector(CONTENT_SELECTOR);
    if (!this._trigger || !this._content) return;

    this._stopAutoUpdate = null;

    this._onBeforeToggle = this._onBeforeToggle.bind(this);
    this._onToggle = this._onToggle.bind(this);
    this._content.addEventListener("beforetoggle", this._onBeforeToggle);
    this._content.addEventListener("toggle", this._onToggle);

    if (this._content.getAttribute("data-state") === "open" && !this._content.matches(":popover-open")) {
      this._content.showPopover();
    }
  }

  disconnectedCallback() {
    if (this._content) {
      this._content.removeEventListener("beforetoggle", this._onBeforeToggle);
      this._content.removeEventListener("toggle", this._onToggle);
    }
    this._stopPositioning();
  }

  _onBeforeToggle(event) {
    const opening = event.newState === "open";
    this._syncState(opening);
    if (!opening) this._stopPositioning();
  }

  _onToggle(event) {
    if (event.newState === "open") this._startPositioning();
  }

  _syncState(open) {
    const state = open ? "open" : "closed";
    this._content.setAttribute("data-state", state);
    this._trigger.setAttribute("data-state", state);
    this._trigger.setAttribute("aria-expanded", String(open));
  }

  _startPositioning() {
    this._stopPositioning();
    const options = this._readOptions();
    this._stopAutoUpdate = autoUpdate(this._trigger, this._content, () => {
      position(this._trigger, this._content, options);
    });
  }

  _stopPositioning() {
    if (this._stopAutoUpdate) {
      this._stopAutoUpdate();
      this._stopAutoUpdate = null;
    }
  }

  _readOptions() {
    const side = this._content.getAttribute("data-side") || "bottom";
    const align = this._content.getAttribute("data-align") || "center";
    const sideOffset = Number(this._content.getAttribute("data-side-offset")) || 0;
    const alignOffset = Number(this._content.getAttribute("data-align-offset")) || 0;
    return { side, align, sideOffset, alignOffset, flip: true, boundaryPadding: 8 };
  }
}

customElements.define("px-popover", PxPopover);
