// assets/js/components/hover_card.js -- <px-hover-card> (adr/0026): the
// irreducible interactive sliver of the Hover Card port
// (prolog/ui/hover_card.pl). Plain ES module, no build step -- served
// through the importmap under the bare specifier "components/hover_card"
// (adr/0025), imported once from assets/js/app.js.
//
// Unlike <px-popover> (assets/js/components/popover.js), this element is
// NOT optional-enhancement-only: prolog/ui/hover_card.pl's own header
// documents that HoverCard never opens at all without this element --
// there is no `popovertarget` on Trigger (opening is hover-driven, and
// there is no native "open after N ms of hover" primitive whatsoever;
// see docs/radix-port-analysis.md's "Hover Card" entry). What Content's
// native `popover="auto"` attribute still gives for free, with zero JS,
// is Escape-to-dismiss and outside-click-to-dismiss (the browser's own
// light-dismiss algorithm for an "auto" popover) plus top-layer
// stacking -- this element's entire job is (1) the hover-delay open/
// close timers with the content-hover "grace" extension, (2) driving
// `.showPopover()`/`.hidePopover()` from those timers (never a native
// toggle), and (3) positioning, via lib/popper.js, exactly the same
// `beforetoggle`/`toggle`-driven pattern popover.js established.
//
// ---------------------------------------------------------------------
// THE DELAY / GRACE-AREA PORT -- read this before touching the timers.
// ---------------------------------------------------------------------
//
// Upstream Radix HoverCard (docs/radix-port-analysis.md's own words,
// quoted in prolog/ui/hover_card.pl's header too): "openDelay defaults
// 700ms, closeDelay 300ms. Pointer-enter starts an open timer (clearing
// any pending close); pointer-leave starts a close timer... Content
// itself also wires pointer-enter/leave to keep it open while the
// cursor is over it (**no gap-tolerance polygon here -- unlike Tooltip,
// HoverCard relies purely on delay timers, not grace-area geometry**)."
//
// That is the load-bearing fact this port leans on: the convex-hull
// point-in-polygon "safe diagonal travel cone" math the task brief
// warns is "the hard part" belongs to **Tooltip** (and Menu's submenu
// hover), not HoverCard -- HoverCard's own upstream algorithm already
// IS "closeDelay tolerance + pointerover-on-Content cancels the pending
// close timer". So what follows is a faithful port of upstream
// HoverCard's actual behavior, not a simplification of it. The
// simplification is real, but narrower than "no polygon": two upstream
// HoverCard nuances beyond the delay/grace-bridge core are deliberately
// NOT ported here --
//
//   1. Upstream also suppresses the close timer while the user is
//      mid-text-selection inside Content, or has a pointer *down* on
//      it (so starting a drag-select just before the cursor happens to
//      cross Content's edge doesn't close the card under you).  This
//      port has no `selectionchange`/`pointerdown` tracking at all --
//      the closeDelay + pointerover-cancels-close mechanism below
//      already covers the practical case (the cursor IS over Content
//      while selecting), and only regresses the rarer "select right up
//      to the content's boundary, closeDelay lapses mid-drag" edge.
//   2. Upstream forces `document.body.style.userSelect = "none"` during
//      an in-content pointer-down, so a drag-selection can't leak a
//      page-wide text-select. Not ported -- no drag-selection support
//      is claimed here at all, so there is nothing to contain.
//
// Both are documented, deliberate scope cuts (adr/0026 rule 2:
// deviations require a note in the module header -- see
// prolog/ui/hover_card.pl's own header for the DOM/ARIA side of this
// same accounting), not oversights.
//
// The mechanics actually ported, precisely:
//
//   - Trigger `pointerenter` (mouse only -- `event.pointerType !==
//     "mouse"` is ignored outright, matching upstream's "touch pointer
//     types are excluded from hover triggering entirely"; this element
//     never listens for `focus`/`blur`/`click` on Trigger at all, so
//     keyboard and touch users get nothing here, exactly upstream's
//     documented hover-only-by-design posture): cancels any pending
//     close timer, then (if not already open and no open timer is
//     already pending) starts an `openDelayMs` timer that calls
//     `showPopover()`.
//   - Trigger `pointerleave`: cancels a still-pending OPEN timer
//     outright (a brief hover-and-leave never opens the card at all);
//     if the card is already open, starts a `closeDelayMs` timer that
//     calls `hidePopover()`.
//   - Content `pointerenter`: cancels a pending CLOSE timer -- this is
//     the entire "grace" mechanism. As long as the pointer reaches
//     Content before `closeDelayMs` elapses after leaving Trigger
//     (upstream's own tolerance, not a geometric cone), the card stays
//     open regardless of the path the pointer took to get there.
//   - Content `pointerleave`: starts its own `closeDelayMs` timer (so
//     moving off Content without returning to Trigger still closes the
//     card, same as moving off Trigger).
//   - `beforetoggle`/`toggle` on Content (fired for EVERY path Content
//     leaves/enters the top layer -- our own `showPopover()`/
//     `hidePopover()` calls, an outside click, or Escape's native
//     light-dismiss): mirrors `data-state` onto Content/Trigger and
//     starts/stops `lib/popper.js`'s `autoUpdate`, the identical
//     `beforetoggle` (sync + stop-positioning-before-close)/`toggle`
//     (start-positioning-after-open) split popover.js documents in
//     full. On close, BOTH timers are also cleared here -- closing via
//     Escape or an outside click must not leave a stale open/close
//     timer around to fire later against a card that already left the
//     top layer for an unrelated reason.
//
// Escape and outside-click dismissal need NO code here at all: Content
// renders native `popover="auto"` (prolog/ui/hover_card.pl), and the
// browser's own light-dismiss algorithm already closes the topmost auto
// popover on Escape or a pointerdown outside it -- that dismissal is
// itself just another `hidePopover()` call under the hood, so it flows
// through the exact same `beforetoggle`/`toggle` handlers as a
// timer-driven close.
//
// One more upstream nuance ported here, statically rather than via a
// timer: "All tabbable descendants inside content are forced
// tabindex=\"-1\" by default (no focus trap exists, so this prevents
// accidental Tab-into behavior)." Applied once in `connectedCallback`
// to every already-server-rendered focusable descendant of Content
// (documented scope limit: content added to the DOM later would not be
// caught -- the demo/common case is static content, same limit
// popover.pl's own progressive-enhancement gaps accept elsewhere).
//
// `side`/`align`/`sideOffset`/`alignOffset` are read straight off
// Content's own `data-side`/`data-align`/`data-side-offset`/
// `data-align-offset` attributes and `openDelay`/`closeDelay` off the
// Root `<div class="px-hover-card">`'s `data-open-delay`/
// `data-close-delay` -- no separate JS configuration surface, same
// "DOM IS the state" rule popper.js's consumers all follow.

import { position, autoUpdate } from "lib/popper";

const TRIGGER_SELECTOR = ".px-hover-card-trigger";
const CONTENT_SELECTOR = ".px-hover-card-content";
const PANEL_SELECTOR = ".px-hover-card";
const FOCUSABLE_SELECTOR = "a[href], button, input, select, textarea, [tabindex]";

class PxHoverCard extends HTMLElement {
  connectedCallback() {
    this._panel = this.querySelector(PANEL_SELECTOR);
    this._trigger = this.querySelector(TRIGGER_SELECTOR);
    this._content = this.querySelector(CONTENT_SELECTOR);
    if (!this._trigger || !this._content) return;

    this._openTimer = null;
    this._closeTimer = null;
    this._stopAutoUpdate = null;

    this._onTriggerPointerEnter = this._onTriggerPointerEnter.bind(this);
    this._onTriggerPointerLeave = this._onTriggerPointerLeave.bind(this);
    this._onContentPointerEnter = this._onContentPointerEnter.bind(this);
    this._onContentPointerLeave = this._onContentPointerLeave.bind(this);
    this._onBeforeToggle = this._onBeforeToggle.bind(this);
    this._onToggle = this._onToggle.bind(this);

    this._trigger.addEventListener("pointerenter", this._onTriggerPointerEnter);
    this._trigger.addEventListener("pointerleave", this._onTriggerPointerLeave);
    this._content.addEventListener("pointerenter", this._onContentPointerEnter);
    this._content.addEventListener("pointerleave", this._onContentPointerLeave);
    this._content.addEventListener("beforetoggle", this._onBeforeToggle);
    this._content.addEventListener("toggle", this._onToggle);

    this._forceTabIndex();

    if (this._content.getAttribute("data-state") === "open" && !this._content.matches(":popover-open")) {
      this._content.showPopover();
    }
  }

  disconnectedCallback() {
    this._clearOpenTimer();
    this._clearCloseTimer();
    if (this._trigger) {
      this._trigger.removeEventListener("pointerenter", this._onTriggerPointerEnter);
      this._trigger.removeEventListener("pointerleave", this._onTriggerPointerLeave);
    }
    if (this._content) {
      this._content.removeEventListener("pointerenter", this._onContentPointerEnter);
      this._content.removeEventListener("pointerleave", this._onContentPointerLeave);
      this._content.removeEventListener("beforetoggle", this._onBeforeToggle);
      this._content.removeEventListener("toggle", this._onToggle);
    }
    this._stopPositioning();
  }

  // -- Trigger: open timer, cancel-on-leave -----------------------------

  _onTriggerPointerEnter(event) {
    if (event.pointerType !== "mouse") return; // touch/pen never trigger (upstream).
    this._clearCloseTimer();
    if (this._isOpen() || this._openTimer) return;
    const delay = this._delayMs("openDelay", 700);
    this._openTimer = setTimeout(() => {
      this._openTimer = null;
      this._show();
    }, delay);
  }

  _onTriggerPointerLeave(event) {
    if (event.pointerType !== "mouse") return;
    this._clearOpenTimer(); // a brief hover-and-leave never opens at all.
    if (!this._isOpen() || this._closeTimer) return;
    this._scheduleClose();
  }

  // -- Content: the grace bridge -----------------------------------------

  _onContentPointerEnter() {
    // The entire grace mechanism: reaching Content before closeDelay
    // elapses cancels the pending close, regardless of travel path.
    this._clearCloseTimer();
  }

  _onContentPointerLeave() {
    if (!this._isOpen() || this._closeTimer) return;
    this._scheduleClose();
  }

  _scheduleClose() {
    const delay = this._delayMs("closeDelay", 300);
    this._closeTimer = setTimeout(() => {
      this._closeTimer = null;
      this._hide();
    }, delay);
  }

  // -- Native popover state <-> data-state/positioning sync -------------

  _onBeforeToggle(event) {
    const opening = event.newState === "open";
    this._syncState(opening);
    if (!opening) {
      this._stopPositioning();
      // A close via Escape/outside-click bypasses our own timers
      // entirely -- clear both so neither can fire later against a
      // card that already left the top layer.
      this._clearOpenTimer();
      this._clearCloseTimer();
    }
  }

  _onToggle(event) {
    if (event.newState === "open") this._startPositioning();
  }

  _syncState(open) {
    const state = open ? "open" : "closed";
    this._content.setAttribute("data-state", state);
    this._trigger.setAttribute("data-state", state);
  }

  _isOpen() {
    return this._content.matches(":popover-open");
  }

  _show() {
    if (this._isOpen()) return;
    this._content.showPopover();
  }

  _hide() {
    if (!this._isOpen()) return;
    this._content.hidePopover();
  }

  _clearOpenTimer() {
    if (this._openTimer) {
      clearTimeout(this._openTimer);
      this._openTimer = null;
    }
  }

  _clearCloseTimer() {
    if (this._closeTimer) {
      clearTimeout(this._closeTimer);
      this._closeTimer = null;
    }
  }

  _delayMs(camelName, fallback) {
    const attr = camelName === "openDelay" ? "data-open-delay" : "data-close-delay";
    const raw = this._panel ? this._panel.getAttribute(attr) : null;
    const n = Number(raw);
    return Number.isFinite(n) && raw !== null ? n : fallback;
  }

  // -- Positioning (lib/popper.js) ---------------------------------------

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

  // -- No focus trap exists here (never traps focus at all -- upstream's
  // own "never traps focus" purpose statement); this only prevents
  // Tab from accidentally landing inside hidden/closed Content.
  _forceTabIndex() {
    const focusable = this._content.querySelectorAll(FOCUSABLE_SELECTOR);
    focusable.forEach((el) => {
      if (!el.hasAttribute("tabindex")) el.setAttribute("tabindex", "-1");
    });
  }
}

customElements.define("px-hover-card", PxHoverCard);
