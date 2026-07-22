// assets/js/components/toast.js -- <px-toast-viewport> / <px-toast>
// (adr/0026): the two coordinating pieces of the Toast port
// (prolog/ui/toast.pl). Plain ES module, no build step -- served
// through the importmap under the bare specifiers
// "components/toast" is the module specifier; both custom elements it
// defines are imported together, exactly like accordion.js/dialog.js
// bundling their own single custom element (this file just happens to
// own two, one per adr/0026 rule 4's "two coordinating pieces" case,
// same precedent as roving-focus's single module backing several
// component elements, just inverted -- one file, two elements, no
// shared module needed between them beyond this file itself).
//
// prolog/ui/toast.pl already renders the full, correct static contract
// on every request: an <ol role="region" aria-live="polite"> Viewport
// and <li role="status" data-state="open" data-duration="..."> Root
// items. Without this file ever loading, every already-rendered toast
// is fully visible, its Close button is a plain, focusable <button>
// (inert -- nothing removes it from the DOM without JS, so it stays
// visible after a "close" click, the honest no-JS degrade), and
// nothing ever auto-dismisses -- the documented no-JS story (adr/0026
// rule 4's progressive-enhancement bar). This file's entire job:
//
//   <px-toast-viewport> (see PxToastViewport below):
//     1. An F8 hotkey (module-level `document` keydown listener,
//        installed once per connected viewport instance -- see that
//        class's own header note on the single-viewport assumption)
//        that focuses the viewport's own <ol> (tabindex="-1", so it is
//        programmatically focusable despite never being in the normal
//        tab order) -- upstream Radix's own behaviour, including the
//        "press again to return focus to what you were on before"
//        toggle.
//
//   <px-toast> (see PxToast below), one per toast <li>:
//     1. Reads `data-duration` (ms) off the <li>; `0` means "never
//        auto-dismiss" (prolog/ui/toast.pl's own documented convention
//        replacing upstream's `Infinity`, which has no clean HTML
//        attribute spelling).
//     2. Starts a dismiss timer for that duration on connect.
//     3. Pause on `pointerenter`/`focusin`, resume on `pointerleave`/
//        `focusout` -- resume recomputes the REMAINING time by
//        elapsed-time subtraction (`remaining -= Date.now() -
//        startedAt`), not a hard reset to the full duration, matching
//        docs/radix-port-analysis.md's own description of upstream's
//        per-toast timer bookkeeping. A `data-paused="true"` attribute
//        is set/cleared alongside (assets/css/ui.css's pause-affordance
//        hook -- a highlighted border while paused).
//     4. `data-toast-close` button clicks (delegated, same pattern as
//        dialog.js's `data-dialog-close` handling) trigger dismissal
//        immediately, bypassing whatever remains of the timer.
//     5. Dismissal itself: sets `data-state="closed"` on the <li>
//        (assets/css/ui.css keys the exit fade/slide transition off
//        this), then -- after `EXIT_MS`, matching that CSS transition's
//        own duration, rather than a `transitionend` listener (which
//        would need de-duplicating across the multiple properties the
//        CSS rule transitions, exactly the kind of "close enough"
//        multi-fire footgun a fixed timeout sidesteps) -- removes the
//        WHOLE <px-toast> wrapper element (the <li> along with it)
//        from the DOM. `disconnectedCallback` also clears any pending
//        timer defensively, in case the element is removed by some
//        other means (a future re-render, an app's own script) while
//        a dismiss timer is still pending.
//
// NOT implemented here, matching prolog/ui/toast.pl's own documented
// deferral: swipe-to-dismiss (no pointerdown/move/up drag math at
// all -- `data-swipe-direction` is emitted statically by the server
// and never touched by this file; `data-swipe`, the gesture-progress
// attribute, is never written because no gesture is ever recognized).
// Close button, F8-reachable viewport, and duration expiry remain the
// fully-functional non-pointer dismiss paths regardless.
//
// State lives entirely on the <li>'s own `data-state`/`data-paused`
// attributes -- never a parallel JS store (adr/0026 rule 4) -- so a
// later Turbo Stream/DOM mutation can't desync from what this element
// last wrote. The one exception, same class of exception dialog.js's
// scroll-lock value is, is the per-instance timer bookkeeping
// (`_remaining`/`_startedAt`) -- necessarily transient JS state with no
// DOM-attribute equivalent a page reload would need to reproduce.

const CLOSE_SELECTOR = "[data-toast-close]";
const EXIT_MS = 200; // matches assets/css/ui.css's .px-toast[data-state="closed"] transition.

class PxToastViewport extends HTMLElement {
  connectedCallback() {
    this._list = this.querySelector("ol");
    if (!this._list) return;

    this._savedFocus = null;
    this._onKeyDown = this._onKeyDown.bind(this);
    document.addEventListener("keydown", this._onKeyDown);
  }

  disconnectedCallback() {
    document.removeEventListener("keydown", this._onKeyDown);
  }

  // F8: focus the viewport; press again (while focus is still inside
  // it) to return focus to whatever had it before -- upstream Radix's
  // own toggle behaviour. Only one <px-toast-viewport> per page is
  // assumed to install this (the common case, matching every kitchen-
  // sink demo and the "prologex-native angle" default single viewport
  // id) -- multiple simultaneous viewports would each install their
  // own document-level listener and race for F8, an out-of-scope edge
  // case upstream itself handles via a shared Provider registry this
  // port does not have (see the module header's Provider-collapse
  // note).
  _onKeyDown(event) {
    if (event.key !== "F8") return;
    event.preventDefault();
    const active = document.activeElement;
    if (active === this._list || this._list.contains(active)) {
      if (this._savedFocus && document.contains(this._savedFocus)) {
        this._savedFocus.focus();
      }
      this._savedFocus = null;
    } else {
      this._savedFocus = active;
      this._list.focus();
    }
  }
}

class PxToast extends HTMLElement {
  connectedCallback() {
    this._li = this.querySelector("li");
    if (!this._li) return;

    this._duration = Number(this._li.getAttribute("data-duration"));
    if (!Number.isFinite(this._duration) || this._duration < 0) {
      this._duration = 0;
    }
    this._remaining = this._duration;
    this._startedAt = null;
    this._timer = null;
    this._closing = false;

    this._onPointerEnter = this._pause.bind(this);
    this._onPointerLeave = this._resume.bind(this);
    this._onFocusIn = this._pause.bind(this);
    this._onFocusOut = this._resume.bind(this);
    this._onClick = this._onClick.bind(this);

    this._li.addEventListener("pointerenter", this._onPointerEnter);
    this._li.addEventListener("pointerleave", this._onPointerLeave);
    this._li.addEventListener("focusin", this._onFocusIn);
    this._li.addEventListener("focusout", this._onFocusOut);
    this._li.addEventListener("click", this._onClick);

    this._resume(); // arms the initial timer (a no-op if duration is 0).
  }

  disconnectedCallback() {
    this._clearTimer();
    if (this._li) {
      this._li.removeEventListener("pointerenter", this._onPointerEnter);
      this._li.removeEventListener("pointerleave", this._onPointerLeave);
      this._li.removeEventListener("focusin", this._onFocusIn);
      this._li.removeEventListener("focusout", this._onFocusOut);
      this._li.removeEventListener("click", this._onClick);
    }
  }

  _onClick(event) {
    const closeEl = event.target.closest(CLOSE_SELECTOR);
    if (!closeEl || !this._li.contains(closeEl)) return;
    this._dismiss();
  }

  // Pause: stop the pending timer (if any) and fold the elapsed time
  // into `_remaining` -- elapsed-time SUBTRACTION, not a hard reset,
  // so resuming later picks up exactly where it left off (module
  // header's own description of upstream's own bookkeeping).
  _pause() {
    if (this._closing) return;
    if (this._timer) {
      clearTimeout(this._timer);
      this._timer = null;
      const elapsed = Date.now() - this._startedAt;
      this._remaining = Math.max(0, this._remaining - elapsed);
    }
    this._li.setAttribute("data-paused", "true");
  }

  // Resume: (re)arm a timer for whatever `_remaining` currently is.
  // `_duration === 0` means "never auto-dismiss" -- no timer is ever
  // armed, matching prolog/ui/toast.pl's documented `duration(0)`
  // convention.
  _resume() {
    if (this._closing) return;
    this._li.removeAttribute("data-paused");
    if (this._duration <= 0) return;
    if (this._timer) return; // already running (e.g. duplicate resume calls).
    this._startedAt = Date.now();
    this._timer = setTimeout(() => this._dismiss(), this._remaining);
  }

  _clearTimer() {
    if (this._timer) {
      clearTimeout(this._timer);
      this._timer = null;
    }
  }

  // Fires for every dismiss path: the duration timer elapsing, or a
  // data-toast-close button click. Sets the exit data-state, then
  // removes the whole element from the DOM once the CSS exit
  // transition has had time to play (see the module header's own
  // rationale for a fixed timeout over transitionend).
  _dismiss() {
    if (this._closing) return;
    this._closing = true;
    this._clearTimer();
    this._li.removeAttribute("data-paused");
    this._li.setAttribute("data-state", "closed");
    setTimeout(() => {
      this.remove();
    }, EXIT_MS);
  }
}

customElements.define("px-toast-viewport", PxToastViewport);
customElements.define("px-toast", PxToast);
