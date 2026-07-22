// assets/js/components/slider.js -- <px-slider> (adr/0026): the
// irreducible interactive sliver of the Slider port
// (prolog/ui/slider.pl). Plain ES module, no build step -- served
// through the importmap under the bare specifier "components/slider"
// (adr/0025), imported once from assets/js/app.js.
//
// prolog/ui/slider.pl already renders the wrapped <input type=range>
// with its correct initial value/min/max/step/data-orientation/
// data-disabled on every request, PLUS a `--slider-value` CSS custom
// property on the outer .px-slider div, computed server-side as a
// percentage of value between min/max -- reload, Turbo visit, or a
// Turbo-stream replace (adr/0024) all reproduce it with zero JS. The
// platform ALSO already gives real, working slider behavior for free
// with zero JS: a native <input type=range> drags, keys (arrows/
// Home/End/PageUp/PageDown), focuses and submits in a <form> with no
// JS involved at all -- that native thumb IS the visible thumb here
// (prolog/ui/slider.pl's module header explains why this port styles
// the real input directly via ::-webkit-slider-thumb/::-moz-range-
// thumb rather than hiding it behind a decorative sibling).
//
// What the platform cannot give for free is keeping the decorative
// `.px-slider-range` fill bar in sync with the thumb *while the user
// is still dragging it*: nothing re-runs server-side markup mid-drag,
// so `--slider-value` (last written at render time) would otherwise
// only catch up once a full page reload happens. Fixing that is this
// element's entire job: listen for the wrapped input's native `input`
// event (fired continuously during drag/keyboard interaction, unlike
// `change`, which only fires once on release/commit) and, on every
// tick, rewrite `--slider-value` on the outer .px-slider div to match
// the input's *live* value -- a same-tick CSS custom property write,
// nothing more.
//
// State lives entirely on the wrapped input's own `value` attribute/
// property and the outer div's `--slider-value` style property --
// never a parallel JS store (adr/0026 rule 4) -- so a later server
// re-render of the same markup can never desync from what this
// element last wrote: there is nothing to reconcile, because there is
// no second source of truth.
//
// Without JS, `<px-slider>` never upgrades: the browser treats it as
// an unknown inline element and simply renders its light-DOM children
// (the div, track, range and input) in place, already correct and
// already a fully working, fully accessible native range slider --
// native focus, keyboard, drag, <form> submission -- it just does not
// keep the decorative accent fill moving smoothly mid-drag until the
// next full render (adr/0026 rule 4's progressive-enhancement bar);
// the fill still ends up correct after that next render either way.

class PxSlider extends HTMLElement {
  connectedCallback() {
    this._root = this.querySelector(".px-slider");
    this._input = this.querySelector('input[type="range"]');
    if (!this._input || !this._root) return;
    this._onInput = this._onInput.bind(this);
    this._input.addEventListener("input", this._onInput);
  }

  disconnectedCallback() {
    if (this._input) {
      this._input.removeEventListener("input", this._onInput);
    }
  }

  _onInput() {
    const min = parseFloat(this._input.min || "0");
    const max = parseFloat(this._input.max || "100");
    const value = parseFloat(this._input.value);
    const pct = max > min ? ((value - min) / (max - min)) * 100 : 0;
    this._root.style.setProperty("--slider-value", String(pct));
  }
}

customElements.define("px-slider", PxSlider);
