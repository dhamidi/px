// assets/js/components/switch.js -- <px-switch> (adr/0026): the
// irreducible interactive sliver of the Switch port
// (prolog/ui/switch.pl). Plain ES module, no build step -- served
// through the importmap under the bare specifier "components/switch"
// (adr/0025), imported once from assets/js/app.js.
//
// prolog/ui/switch.pl already renders the wrapped <input
// type=checkbox role=switch>'s correct initial state on every request
// (`aria-checked`/`data-state`, mirrored onto the enclosing <label>
// and the decorative thumb <span>, plus `data-disabled`/`disabled`
// when disabled) -- reload, Turbo visit, or a Turbo-stream replace
// (adr/0024) all reproduce it with zero JS. The platform ALSO already
// gives real, working toggle behavior for free with zero JS: a native
// checkbox flips its own `checked` property on click/Space, and the
// wrapping <label> (this port's Root) forwards clicks anywhere inside
// it -- including the thumb -- to that checkbox, no JS required.
//
// What the platform cannot give for free is keeping the EXPLICIT
// `aria-checked`/`data-state` *attributes* this contract writes in
// sync with that native `checked` *property* after the fact: nothing
// re-runs server-side markup just because the user clicked, so those
// attributes go stale the instant a plain, JS-free click flips the
// underlying checkbox. That staleness is not merely cosmetic --
// `aria-checked`, once present as an explicit attribute, is what
// assistive tech reads for a `role="switch"` element, so leaving it
// stale would be a real regression, not just a missed animation.
// Fixing it is this element's entire job: listen for the wrapped
// input's native `change` event and, on every toggle, rewrite
// `aria-checked`/`data-state` on the input and `data-state` (the
// track/thumb styling hook, assets/css/ui.css) on the label and thumb
// to match -- a same-tick attribute sync, nothing more.
//
// State lives entirely on the wrapped elements' own attributes --
// never a parallel JS store (adr/0026 rule 4) -- so a later server
// re-render of the same markup can never desync from what this
// element last wrote: there is nothing to reconcile, because there is
// no second source of truth.
//
// Without JS, `<px-switch>` never upgrades: the browser treats it as
// an unknown inline element and simply renders its light-DOM children
// (the label, input and thumb) in place, already correct at load time
// and already a fully working checkbox -- native focus, native
// keyboard activation, native <form> submission -- it just does not
// keep `aria-checked`/`data-state` live after a click until the next
// server render (adr/0026 rule 4's progressive-enhancement bar).

class PxSwitch extends HTMLElement {
  connectedCallback() {
    this._label = this.querySelector("label");
    this._input = this.querySelector('input[type="checkbox"]');
    this._thumb = this.querySelector(".px-switch-thumb");
    if (!this._input) return;
    this._onChange = this._onChange.bind(this);
    this._input.addEventListener("change", this._onChange);
  }

  disconnectedCallback() {
    if (this._input) {
      this._input.removeEventListener("change", this._onChange);
    }
  }

  _onChange() {
    const state = this._input.checked ? "checked" : "unchecked";
    this._input.setAttribute("aria-checked", String(this._input.checked));
    this._input.setAttribute("data-state", state);
    if (this._label) this._label.setAttribute("data-state", state);
    if (this._thumb) this._thumb.setAttribute("data-state", state);
  }
}

customElements.define("px-switch", PxSwitch);
