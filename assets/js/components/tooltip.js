// assets/js/components/tooltip.js -- <px-tooltip> (adr/0026): the
// irreducible interactive sliver of the Tooltip port
// (prolog/ui/tooltip.pl). Plain ES module, no build step -- served
// through the importmap under the bare specifier "components/tooltip"
// (adr/0025), imported once from assets/js/app.js. popper.js's second
// consumer after assets/js/components/popover.js.
//
// prolog/ui/tooltip.pl already renders the full, correct static
// contract on every request (role="tooltip", aria-describedby wired
// to Content's id, the three-way data-state, data-side/data-align/
// offsets) -- see that module's header, "Platform choice", for why
// Content's native `popover="manual"` attribute is used rather than
// "auto" (auto's light-dismiss/single-open-elsewhere behavior fights
// hover semantics). Without this element ever loading, Content simply
// never becomes visible -- there is no click/popovertarget path to
// hang a no-JS fallback off, unlike Popover; hover/focus-driven
// opening is entirely this element's job. This element's work:
//
//   1. delay/skip-delay coordination (docs/radix-port-analysis.md's
//      "Tooltip" entry, "irreducibly custom -- no platform analog"):
//      pointerenter/focus on Trigger starts a `delayDuration` (700ms,
//      Radix's own default) timer before opening, UNLESS a tooltip
//      anywhere on the page closed within the last `skipDelayDuration`
//      (300ms, Radix's own default) window, in which case this one
//      opens INSTANTLY. Upstream implements the shared "did anything
//      close recently" fact via a `TooltipProvider` React context
//      every `Tooltip.Root` reads; there is no React context here, so
//      it is instead a single MODULE-LEVEL variable, `lastClosedAt`
//      (below) -- every `<px-tooltip>` instance reads/writes the same
//      one, because ES modules are singletons (one instance of this
//      module's top-level state exists no matter how many `<px-
//      tooltip>` elements import it), which is exactly the "shared
//      document-wide fact" Provider exists to give React. This is why
//      prolog/ui/tooltip.pl ships no Provider template at all -- see
//      that module's header.
//   2. single-open-at-a-time: opening a tooltip closes whatever OTHER
//      `<px-tooltip>` instance was open, via a second module-level
//      variable, `openInstance` -- upstream's own "a custom document
//      event ensures only one tooltip is open at a time anywhere on
//      the page", ported as the simplest thing that gives the same
//      externally-observable behavior.
//   3. positioning: `lib/popper.js`'s `position`/`autoUpdate` pair,
//      same contract popover.js already proved out -- side/align read
//      straight off Content's own data-side/data-align/data-side-
//      offset/data-align-offset attributes, no separate config.
//   4. the close paths: pointerleave, blur, and Escape all close
//      IMMEDIATELY (no closeDelay -- that is a HoverCard concept, not
//      Tooltip's; docs/radix-port-analysis.md's Tooltip entry lists no
//      close-delay at all). A pointerdown on Trigger also closes
//      immediately and suppresses the very next focus-driven open
//      (upstream: "onPointerDown closes immediately and suppresses
//      the following onFocus -- a mouse click shouldn't also show a
//      tooltip via focus"), and an Escape-close is latched so the
//      tooltip does not instantly reopen while the pointer is still
//      resting over Trigger (matches upstream's own Escape behavior).
//   5. touch: `pointerType === "touch"` is ignored entirely for
//      opening (upstream: "ignoring touch pointer types" -- Tooltip
//      has no long-press affordance upstream either, so none is added
//      here; a touch user can still reach the description via a
//      screen reader's own focus-driven announcement of
//      aria-describedby, or via a real keyboard/switch-control focus
//      event, which IS still honoured).
//
// NOT ported (documented gap, see prolog/ui/tooltip.pl's header):
// the convex-hull grace-area polygon for `disableHoverableContent=
// false` (moving the pointer from Trigger into Content along a
// protected diagonal without closing) -- this port's Content is plain
// hint text, not interactive, so there is nothing inside Content a
// user would need to move the pointer into. Also not ported: "scrolling
// any trigger ancestor closes the tooltip" -- simplified to
// `autoUpdate`'s normal scroll-reposition behavior (same as Popover),
// so a tooltip follows its trigger on scroll rather than closing.

import { position, autoUpdate } from "lib/popper";

const TRIGGER_SELECTOR = ".px-tooltip-trigger";
const CONTENT_SELECTOR = ".px-tooltip-content";

const DELAY_DURATION = 700; // ms -- Radix's own TooltipProvider default.
const SKIP_DELAY_DURATION = 300; // ms -- Radix's own default.

// Module-level, shared by every <px-tooltip> instance (see header,
// point 1/2) -- this IS the Provider-equivalent state, deliberately
// not per-instance.
let lastClosedAt = -Infinity;
let openInstance = null;

class PxTooltip extends HTMLElement {
  connectedCallback() {
    this._trigger = this.querySelector(TRIGGER_SELECTOR);
    this._content = this.querySelector(CONTENT_SELECTOR);
    if (!this._trigger || !this._content) return;

    this._openTimer = null;
    this._stopAutoUpdate = null;
    this._isOpen = false;
    this._suppressFocus = false;
    this._escaped = false;

    this._onPointerEnter = this._onPointerEnter.bind(this);
    this._onPointerLeave = this._onPointerLeave.bind(this);
    this._onPointerDown = this._onPointerDown.bind(this);
    this._onFocus = this._onFocus.bind(this);
    this._onBlur = this._onBlur.bind(this);
    this._onKeydown = this._onKeydown.bind(this);

    this._trigger.addEventListener("pointerenter", this._onPointerEnter);
    this._trigger.addEventListener("pointerleave", this._onPointerLeave);
    this._trigger.addEventListener("pointerdown", this._onPointerDown);
    this._trigger.addEventListener("focus", this._onFocus);
    this._trigger.addEventListener("blur", this._onBlur);
    this._trigger.addEventListener("keydown", this._onKeydown);
  }

  disconnectedCallback() {
    if (this._trigger) {
      this._trigger.removeEventListener("pointerenter", this._onPointerEnter);
      this._trigger.removeEventListener("pointerleave", this._onPointerLeave);
      this._trigger.removeEventListener("pointerdown", this._onPointerDown);
      this._trigger.removeEventListener("focus", this._onFocus);
      this._trigger.removeEventListener("blur", this._onBlur);
      this._trigger.removeEventListener("keydown", this._onKeydown);
    }
    this._clearOpenTimer();
    this._stopPositioning();
    if (openInstance === this) openInstance = null;
  }

  // -- pointer -----------------------------------------------------

  _onPointerEnter(event) {
    if (event.pointerType === "touch") return; // header point 5.
    this._escaped = false;
    this._scheduleOpen();
  }

  _onPointerLeave(event) {
    if (event.pointerType === "touch") return;
    this._escaped = false;
    this._close();
  }

  _onPointerDown() {
    // Header point 4: a click shouldn't also show a tooltip via the
    // focus event the same click is about to cause.
    this._close();
    this._suppressFocus = true;
    setTimeout(() => {
      this._suppressFocus = false;
    }, 0);
  }

  // -- focus ---------------------------------------------------------

  _onFocus() {
    if (this._suppressFocus) return;
    this._escaped = false;
    this._scheduleOpen();
  }

  _onBlur() {
    this._close();
  }

  _onKeydown(event) {
    if (event.key === "Escape" && this._isOpen) {
      this._escaped = true;
      this._close();
    }
  }

  // -- delay / skip-delay (header point 1) --------------------------

  _scheduleOpen() {
    if (this._escaped || this._isOpen) return;
    this._clearOpenTimer();
    const withinSkipWindow = performance.now() - lastClosedAt < SKIP_DELAY_DURATION;
    if (withinSkipWindow) {
      this._open("instant-open");
    } else {
      this._openTimer = setTimeout(() => this._open("delayed-open"), DELAY_DURATION);
    }
  }

  _clearOpenTimer() {
    if (this._openTimer !== null) {
      clearTimeout(this._openTimer);
      this._openTimer = null;
    }
  }

  // -- open/close (header point 2/3) --------------------------------

  _open(state) {
    this._clearOpenTimer();
    if (this._isOpen) return;

    if (openInstance && openInstance !== this) openInstance._close();

    this._isOpen = true;
    openInstance = this;
    this._setState(state);
    if (!this._content.matches(":popover-open")) this._content.showPopover();
    this._startPositioning();
  }

  _close() {
    this._clearOpenTimer();
    if (!this._isOpen) return;

    this._isOpen = false;
    if (openInstance === this) openInstance = null;
    this._setState("closed");
    if (this._content.matches(":popover-open")) this._content.hidePopover();
    this._stopPositioning();
    lastClosedAt = performance.now(); // starts the skip-delay window for every <px-tooltip>.
  }

  _setState(state) {
    this._trigger.setAttribute("data-state", state);
    this._content.setAttribute("data-state", state);
  }

  // -- positioning ----------------------------------------------------

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
    const side = this._content.getAttribute("data-side") || "top";
    const align = this._content.getAttribute("data-align") || "center";
    const sideOffset = Number(this._content.getAttribute("data-side-offset")) || 0;
    const alignOffset = Number(this._content.getAttribute("data-align-offset")) || 0;
    return { side, align, sideOffset, alignOffset, flip: true, boundaryPadding: 8 };
  }
}

customElements.define("px-tooltip", PxTooltip);
