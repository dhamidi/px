// assets/js/components/navigation_menu.js -- <px-navigation-menu>
// (adr/0026): the irreducible interactive sliver of the Navigation Menu
// port (prolog/ui/navigation_menu.pl). Plain ES module, no build step --
// served through the importmap under the bare specifier
// "components/navigation_menu" (adr/0025), imported once from
// assets/js/app.js.
//
// STANDALONE (docs/radix-port-analysis.md's own classification --
// "benefits from nothing built in phases 8-12"): this element imports
// NEITHER "lib/menu" (the shared Menu engine -- this component has no
// role=menu/menuitem semantics at all, see prolog/ui/navigation_menu.pl's
// header) NOR "lib/popper" (positioning here is plain CSS, `position:
// absolute` on `.px-navigation-menu-content` relative to its own
// `.px-navigation-menu-item` -- see that module header's "Viewport
// decision" for why: no shared viewport means no cross-item geometry to
// measure). Nothing here is reused from any sibling component; nothing
// here is meant to be reused by one either, beyond the ordinary DOM.
//
// ---------------------------------------------------------------------
// THE INTERACTION MODEL -- read this before touching the timers.
// ---------------------------------------------------------------------
//
// One <px-navigation-menu> instance owns at most one open
// Trigger/Content pair at a time (this._openTrigger/._openContent).
// Triggers are discovered at connect time; each Trigger's Content is
// resolved via its own `aria-controls` (falling back to the nearest
// `.px-navigation-menu-content` inside the same `<li>` if `aria-controls`
// is missing or stale -- graceful degradation, same posture every other
// component's "controls(Id) is optional" Prolog-side option documents).
// Trigger order (DOM order among triggers that resolved a Content) is
// captured once as each trigger's index -- this is the ONLY "geometry"
// this port ever computes, a plain array position, not a pixel
// measurement (contrast upstream's own ResizeObserver-driven Indicator/
// Viewport, deliberately not ported -- see the Prolog module header).
//
//   - Trigger `pointerenter` (mouse only -- touch/pen ignored, same
//     convention as Hover Card/Tooltip's own pointerType guard; a
//     touch user still gets the click-to-open path below):
//       * if this trigger is already the open one -- cancel any
//         pending close (grace) and stop.
//       * else if ANOTHER trigger is currently open -- switch
//         INSTANTLY, no delay at all (the brief's own "switch-on-hover
//         between triggers when one is open (menubar-like)" -- this is
//         this port's version of upstream Menubar's "hovering across
//         the bar while one menu is open switches directly between
//         menus", applied here because Navigation Menu's own upstream
//         behavior is the same: once any panel is open, adjacent
//         triggers open on mere hover with no additional delay).
//       * else (nothing open yet) -- schedule an open after
//         OPEN_DELAY_MS (200ms, matching the task brief's own "~200ms
//         delay" and upstream NavigationMenu.Root's own
//         `delayDuration` default).
//   - Trigger `pointerleave`: cancels a still-pending OPEN timer
//     outright (a brief hover-and-leave never opens); if this
//     trigger's Content is open, schedules a close after
//     CLOSE_DELAY_MS, UNLESS the pointer is heading onto that same
//     Content (handled by Content's own pointerenter canceling the
//     pending close below -- the exact grace bridge
//     assets/js/components/hover_card.js's header documents and this
//     port's own task brief calls out by name: "pointerover on the
//     panel cancels close -- the hover_card precedent").
//   - Content `pointerenter`: cancels a pending close for the
//     currently-open pair. Content `pointerleave`: schedules a close,
//     same delay.
//   - Trigger `click`: real `<button>` native activation (also fires
//     for Enter/Space on a focused trigger -- nothing to wire for
//     that, the platform already does it). Toggles immediately, NO
//     delay either direction -- opening a panel by keyboard/click must
//     not wait on a hover timer meant for mouse-intent disambiguation.
//   - Trigger `keydown` ArrowDown: opens this trigger's Content
//     immediately if not already open (same no-delay path as click),
//     then moves focus to the first `.px-navigation-menu-link` inside
//     it -- upstream's own "entry key focuses into Content" behavior,
//     reduced from a TreeWalker to a plain querySelector because
//     Content never leaves its own Item (see the Prolog header).
//   - `keydown` Escape anywhere in the component while a panel is
//     open: closes it immediately and refocuses its Trigger.
//   - `focusout` on the component root: if focus is landing outside the
//     whole `<px-navigation-menu>` -- read off the event's own
//     `relatedTarget`, NOT a deferred re-check of
//     `document.activeElement` (see `_onFocusOut`'s own header comment
//     for why the latter misfires) -- closes any open panel. A focus
//     move BETWEEN two elements still inside it (e.g. Trigger to its
//     own Content's first link via ArrowDown, or Tab from one link to
//     the next inside an open Content) never misfires. This is the
//     brief's own "closes on Escape/blur-out" -- Tab from one Trigger
//     to the next Trigger is NOT a blur-out (focus stays inside the
//     component) and correctly leaves whatever is open alone.
//   - `pointerdown` on `document`, outside this component: closes any
//     open panel immediately -- there is no native `popover` here (see
//     the Prolog module header's "Platform choice": top-layer
//     promotion would break the Viewport-free CSS positioning this
//     port depends on), so outside-click dismissal is this element's
//     own small responsibility, not the browser's.
//
// ---------------------------------------------------------------------
// data-motion -- the directional slide hint (upstream's own semantics).
// ---------------------------------------------------------------------
//
// Whenever the open pair actually changes, `_switchTo` compares the
// previous and next Trigger's captured index:
//
//   - no previous panel was open (a fresh open, not a switch): the new
//     Content gets NO `data-motion` attribute at all (a plain fade/
//     rise entrance, same treatment Hover Card's Content already
//     uses).
//   - next index > previous index (moving "forward" through the bar):
//     the closing Content gets `data-motion="to-start"` (exits toward
//     the start) and the opening Content gets `data-motion="from-end"`
//     (enters from the end) -- matching upstream's own to-start/
//     from-end pairing for a forward switch.
//   - next index < previous index ("backward"): the closing Content
//     gets `data-motion="to-end"`, the opening Content gets
//     `data-motion="from-start"`.
//
// assets/css/ui.css's Navigation Menu section keys the actual slide
// transform off these two attributes (`[data-motion="from-start"]`
// etc) -- this element only ever sets/removes the attribute, never
// touches inline styles, keeping the "DOM IS the state" rule every
// other component's element already follows.
//
// Plain closes (no next panel opening) clear `data-motion` entirely --
// a simple fade/rise exit, matching the fresh-open case's own
// no-attribute treatment.

const TRIGGER_SELECTOR = ".px-navigation-menu-trigger";
const CONTENT_SELECTOR = ".px-navigation-menu-content";
const LINK_SELECTOR = ".px-navigation-menu-link";
const ITEM_SELECTOR = ".px-navigation-menu-item";

const OPEN_DELAY_MS = 200; // Radix's own NavigationMenu.Root `delayDuration` default.
const CLOSE_DELAY_MS = 200; // no separate upstream constant is named in the analysis
// doc for this component; matched to the open delay so open/close feel symmetric --
// documented choice, not a literal upstream value (contrast Tooltip/Hover Card, whose
// 700/300ms figures ARE upstream's own named defaults).

class PxNavigationMenu extends HTMLElement {
  connectedCallback() {
    this._pairs = this._collectPairs();
    if (this._pairs.length === 0) return;

    this._openTrigger = null;
    this._openContent = null;
    this._openTimer = null;
    this._closeTimer = null;

    this._onTriggerPointerEnter = this._onTriggerPointerEnter.bind(this);
    this._onTriggerPointerLeave = this._onTriggerPointerLeave.bind(this);
    this._onTriggerClick = this._onTriggerClick.bind(this);
    this._onTriggerKeydown = this._onTriggerKeydown.bind(this);
    this._onContentPointerEnter = this._onContentPointerEnter.bind(this);
    this._onContentPointerLeave = this._onContentPointerLeave.bind(this);
    this._onContentClick = this._onContentClick.bind(this);
    this._onKeydown = this._onKeydown.bind(this);
    this._onFocusOut = this._onFocusOut.bind(this);
    this._onDocumentPointerDown = this._onDocumentPointerDown.bind(this);

    for (const pair of this._pairs) {
      pair.trigger.addEventListener("pointerenter", this._onTriggerPointerEnter);
      pair.trigger.addEventListener("pointerleave", this._onTriggerPointerLeave);
      pair.trigger.addEventListener("click", this._onTriggerClick);
      pair.trigger.addEventListener("keydown", this._onTriggerKeydown);
      pair.content.addEventListener("pointerenter", this._onContentPointerEnter);
      pair.content.addEventListener("pointerleave", this._onContentPointerLeave);
      pair.content.addEventListener("click", this._onContentClick);
    }

    this.addEventListener("keydown", this._onKeydown);
    this.addEventListener("focusout", this._onFocusOut);
    document.addEventListener("pointerdown", this._onDocumentPointerDown);
  }

  disconnectedCallback() {
    this._clearOpenTimer();
    this._clearCloseTimer();
    for (const pair of this._pairs || []) {
      pair.trigger.removeEventListener("pointerenter", this._onTriggerPointerEnter);
      pair.trigger.removeEventListener("pointerleave", this._onTriggerPointerLeave);
      pair.trigger.removeEventListener("click", this._onTriggerClick);
      pair.trigger.removeEventListener("keydown", this._onTriggerKeydown);
      pair.content.removeEventListener("pointerenter", this._onContentPointerEnter);
      pair.content.removeEventListener("pointerleave", this._onContentPointerLeave);
      pair.content.removeEventListener("click", this._onContentClick);
    }
    this.removeEventListener("keydown", this._onKeydown);
    this.removeEventListener("focusout", this._onFocusOut);
    document.removeEventListener("pointerdown", this._onDocumentPointerDown);
  }

  // -- discovery ----------------------------------------------------

  _collectPairs() {
    const triggers = Array.from(this.querySelectorAll(TRIGGER_SELECTOR));
    const pairs = [];
    triggers.forEach((trigger) => {
      const content = this._resolveContent(trigger);
      if (!content) return;
      pairs.push({ trigger, content, index: pairs.length });
    });
    return pairs;
  }

  _resolveContent(trigger) {
    const id = trigger.getAttribute("aria-controls");
    if (id) {
      const byId = this.querySelector(`#${CSS.escape(id)}`);
      if (byId) return byId;
    }
    const item = trigger.closest(ITEM_SELECTOR);
    return item ? item.querySelector(CONTENT_SELECTOR) : null;
  }

  _pairFor(el) {
    return this._pairs.find((p) => p.trigger === el || p.content === el);
  }

  // -- Trigger: hover open (delayed, unless switching), click/keyboard --

  _onTriggerPointerEnter(event) {
    if (event.pointerType === "touch" || event.pointerType === "pen") return; // mouse-equivalent only.
    const pair = this._pairFor(event.currentTarget);
    if (!pair) return;
    this._clearCloseTimer();
    if (this._openTrigger === pair.trigger) return; // already open -- just cancel close (grace).
    this._clearOpenTimer();
    if (this._openTrigger) {
      // "switch-on-hover between triggers when one is open (menubar-like)" -- instant.
      this._switchTo(pair);
    } else {
      this._openTimer = setTimeout(() => this._switchTo(pair), OPEN_DELAY_MS);
    }
  }

  _onTriggerPointerLeave(event) {
    if (event.pointerType === "touch" || event.pointerType === "pen") return;
    this._clearOpenTimer();
    const pair = this._pairFor(event.currentTarget);
    if (!pair || this._openTrigger !== pair.trigger) return;
    this._scheduleClose(pair);
  }

  _onTriggerClick(event) {
    const pair = this._pairFor(event.currentTarget);
    if (!pair) return;
    this._clearOpenTimer();
    this._clearCloseTimer();
    if (this._openTrigger === pair.trigger) {
      this._closeCurrent();
    } else {
      this._switchTo(pair);
    }
  }

  _onTriggerKeydown(event) {
    if (event.key !== "ArrowDown") return;
    const pair = this._pairFor(event.currentTarget);
    if (!pair) return;
    event.preventDefault();
    if (this._openTrigger !== pair.trigger) {
      this._clearOpenTimer();
      this._clearCloseTimer();
      this._switchTo(pair);
    }
    const firstLink = pair.content.querySelector(LINK_SELECTOR);
    if (firstLink) firstLink.focus();
  }

  // -- Content: grace bridge, click-a-link closes --------------------

  _onContentPointerEnter(event) {
    const pair = this._pairFor(event.currentTarget);
    if (!pair || this._openTrigger !== pair.trigger) return;
    this._clearCloseTimer(); // reaching Content before CLOSE_DELAY_MS elapses cancels the close.
  }

  _onContentPointerLeave(event) {
    const pair = this._pairFor(event.currentTarget);
    if (!pair || this._openTrigger !== pair.trigger) return;
    this._scheduleClose(pair);
  }

  _onContentClick(event) {
    if (event.target.closest(LINK_SELECTOR)) this._closeCurrent();
  }

  // -- Escape / blur-out / outside click ------------------------------

  _onKeydown(event) {
    if (event.key === "Escape" && this._openTrigger) {
      const trigger = this._openTrigger;
      this._closeCurrent();
      trigger.focus();
    }
  }

  _onFocusOut(event) {
    if (!this._openTrigger) return;
    // `event.relatedTarget` (the element about to receive focus) is the
    // signal used here, NOT `document.activeElement` (even deferred to a
    // microtask): CDP-driven verification of this exact port found
    // `document.activeElement` still transiently reporting `<body>` --
    // neither updated yet nor settled one microtask later -- while a
    // plain Tab moved focus between two links THIS component itself
    // renders (Introduction -> Getting started inside one open Content);
    // reading it here misclassified every in-component Tab as a
    // blur-out, which then hid Content (CSS `visibility: hidden`) out
    // from under the still-tabbing user, forcibly blurring it to
    // `<body>` on top -- a self-inflicted cascade traced back to this
    // one read. `relatedTarget` has no such lag: the browser hands it
    // over already correct for keyboard Tab, this element's own
    // `.focus()` calls (ArrowDown's entry-focus, Escape's
    // refocus-trigger), and ordinary mouse-driven focus changes alike.
    // `null` (focus left the document/window entirely) correctly still
    // reads as "outside" via `contains(null) === false`.
    const next = event.relatedTarget;
    if (next !== undefined && !this.contains(next)) {
      this._closeCurrent();
    }
  }

  _onDocumentPointerDown(event) {
    if (this._openTrigger && !this.contains(event.target)) {
      this._closeCurrent();
    }
  }

  // -- open/close/switch state machine --------------------------------

  _switchTo(pair) {
    this._clearOpenTimer();
    this._clearCloseTimer();
    const prevTrigger = this._openTrigger;
    const prevContent = this._openContent;
    if (prevTrigger === pair.trigger) return;

    const prevIndex = prevTrigger ? this._pairFor(prevTrigger).index : null;
    const forward = prevIndex !== null && pair.index > prevIndex;

    if (prevContent) {
      this._setMotion(prevContent, forward ? "to-start" : "to-end");
      this._setState(prevTrigger, prevContent, false);
    }
    this._setMotion(pair.content, prevIndex === null ? null : forward ? "from-end" : "from-start");
    this._setState(pair.trigger, pair.content, true);

    this._openTrigger = pair.trigger;
    this._openContent = pair.content;
  }

  _scheduleClose(pair) {
    this._clearCloseTimer();
    this._closeTimer = setTimeout(() => {
      this._closeTimer = null;
      if (this._openTrigger === pair.trigger) this._closeCurrent();
    }, CLOSE_DELAY_MS);
  }

  _closeCurrent() {
    this._clearOpenTimer();
    this._clearCloseTimer();
    if (!this._openTrigger) return;
    this._setMotion(this._openContent, null);
    this._setState(this._openTrigger, this._openContent, false);
    this._openTrigger = null;
    this._openContent = null;
  }

  _setState(trigger, content, open) {
    const state = open ? "open" : "closed";
    trigger.setAttribute("data-state", state);
    trigger.setAttribute("aria-expanded", String(open));
    content.setAttribute("data-state", state);
  }

  _setMotion(content, motion) {
    if (motion) content.setAttribute("data-motion", motion);
    else content.removeAttribute("data-motion");
  }

  _clearOpenTimer() {
    if (this._openTimer !== null) {
      clearTimeout(this._openTimer);
      this._openTimer = null;
    }
  }

  _clearCloseTimer() {
    if (this._closeTimer !== null) {
      clearTimeout(this._closeTimer);
      this._closeTimer = null;
    }
  }
}

customElements.define("px-navigation-menu", PxNavigationMenu);
