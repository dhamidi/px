// assets/js/components/scroll_area.js -- <px-scroll-area> (adr/0026):
// the irreducible interactive sliver of the Scroll Area port
// (prolog/ui/scroll_area.pl). Plain ES module, no build step -- served
// through the importmap under the bare specifier "components/
// scroll_area" (adr/0025), imported once from assets/js/app.js.
//
// prolog/ui/scroll_area.pl's own header has the full "platform vs JS"
// writeup; the short version, load-bearing for what follows: the REAL
// scrolling and the REAL visible scrollbar are both already native
// (Viewport is a plain `overflow: auto` div, styled directly by
// `assets/css/ui.css` with `scrollbar-width`/`scrollbar-color` and
// `::-webkit-scrollbar*` -- no scrollbar is ever hand-drawn). The
// decorative Scrollbar/Thumb/Corner parts prolog/ui/scroll_area.pl
// renders are never painted (`display: none`) -- their only job is
// carrying the `data-orientation`/`data-state` attributes the analysis
// doc's contract requires, and `assets/css/ui.css` keys the REAL
// scrollbar's color off that same `data-state` via a `:has()`
// selector. Two of the four `type`s (`always`/`auto`) need that
// `data-state` to be static, decided once, server-side -- this element
// does nothing at all for those two (see `connectedCallback` below,
// the early return). The other two (`hover`/`scroll`) need it to
// change live in response to pointer/scroll activity with no
// server round-trip -- THAT is this element's entire job, and nothing
// more: no ResizeObserver (no script-computed thumb size -- there is
// no script-drawn thumb), no requestAnimationFrame polling loop (no
// script-synced thumb position -- the real scrollbar already tracks
// scrollTop/scrollLeft itself), no pointer-capture drag math (the real
// scrollbar's thumb is already natively draggable).
//
//   - `type="hover"`: Root `pointerenter` -> every decorative Scrollbar
//     part's `data-state` -> "visible"; Root `pointerleave` -> back to
//     "hidden". No delay, no timer -- matches upstream's own hover
//     variant, which is likewise instant (pointerenter/pointerleave on
//     the root), not delay-gated the way HoverCard/Tooltip are.
//   - `type="scroll"`: Viewport `scroll` -> every decorative Scrollbar
//     part's `data-state` -> "visible" immediately, cancelling any
//     pending hide timer, then a fresh `data-scroll-hide-delay`-driven
//     (600ms default, Radix's own `scrollHideDelay` default) timer is
//     armed to flip back to "hidden" once scrolling has been idle that
//     long -- the same shape as upstream's own small `scroll` state
//     machine, minus the parts (thumb resize/position) that only exist
//     because upstream draws its own thumb.
//
// State lives entirely on the decorative Scrollbar parts' own
// `data-state` attribute -- never a parallel JS store (adr/0026 rule
// 4) -- so a later server re-render of the same markup can never
// desync from what this element last wrote.
//
// Without JS, `<px-scroll-area>` never upgrades: the browser treats it
// as an unknown inline element and simply renders its light-DOM
// children in place -- already a fully working, fully scrollable
// native region (keyboard, wheel, and scrollbar-drag scrolling all
// keep working with zero JS); the only thing lost is `type="hover"`/
// `type="scroll"`'s live show/hide -- `data-state` just stays at
// whichever value the server rendered (`"hidden"` for both, per
// prolog/ui/scroll_area.pl's `default_scrollbar_state/2`), which means
// the real scrollbar simply renders in its always-transparent
// (invisible) color -- a graceful, if maximally conservative, no-JS
// fallback: the area is still fully usable, just with an unstyled/
// invisible native scrollbar until JS loads.

const ROOT_SELECTOR = ".px-scroll-area";
const VIEWPORT_SELECTOR = ".px-scroll-area-viewport";
const SCROLLBAR_SELECTOR = ".px-scroll-area-scrollbar";

class PxScrollArea extends HTMLElement {
  connectedCallback() {
    this._root = this.querySelector(ROOT_SELECTOR);
    this._viewport = this.querySelector(VIEWPORT_SELECTOR);
    this._scrollbars = Array.from(this.querySelectorAll(SCROLLBAR_SELECTOR));
    if (!this._root || !this._viewport || this._scrollbars.length === 0) return;

    this._type = this._root.getAttribute("data-type") || "auto";
    // Irrelevant for "auto"/"always" -- data-state is static for both
    // (see prolog/ui/scroll_area.pl's module header); nothing below
    // ever runs for them.
    if (this._type !== "hover" && this._type !== "scroll") return;

    this._hideDelayMs = this._readHideDelay();
    this._hideTimer = null;

    if (this._type === "hover") {
      this._onPointerEnter = () => this._setVisible(true);
      this._onPointerLeave = () => this._setVisible(false);
      this._root.addEventListener("pointerenter", this._onPointerEnter);
      this._root.addEventListener("pointerleave", this._onPointerLeave);
    } else {
      // type === "scroll"
      this._onScroll = () => {
        this._setVisible(true);
        this._scheduleHide();
      };
      this._viewport.addEventListener("scroll", this._onScroll, { passive: true });
    }
  }

  disconnectedCallback() {
    if (this._onPointerEnter) {
      this._root.removeEventListener("pointerenter", this._onPointerEnter);
      this._root.removeEventListener("pointerleave", this._onPointerLeave);
    }
    if (this._onScroll) {
      this._viewport.removeEventListener("scroll", this._onScroll);
    }
    this._clearHideTimer();
  }

  _setVisible(visible) {
    // "visible" (hover entering, or any scroll tick) always wins
    // outright over a pending hide -- cancel it. "hidden" (hover
    // leaving) is applied immediately too; only the scroll-idle path
    // goes through _scheduleHide's timer.
    this._clearHideTimer();
    const state = visible ? "visible" : "hidden";
    this._scrollbars.forEach((sb) => sb.setAttribute("data-state", state));
  }

  _scheduleHide() {
    this._clearHideTimer();
    this._hideTimer = setTimeout(() => {
      this._hideTimer = null;
      this._scrollbars.forEach((sb) => sb.setAttribute("data-state", "hidden"));
    }, this._hideDelayMs);
  }

  _clearHideTimer() {
    if (this._hideTimer) {
      clearTimeout(this._hideTimer);
      this._hideTimer = null;
    }
  }

  _readHideDelay() {
    const raw = this._root.getAttribute("data-scroll-hide-delay");
    const n = Number(raw);
    return Number.isFinite(n) && raw !== null ? n : 600;
  }
}

customElements.define("px-scroll-area", PxScrollArea);
