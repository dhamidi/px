// assets/js/components/toggle.js -- <px-toggle> (adr/0026): the
// irreducible interactive sliver of the Toggle port
// (prolog/ui/toggle.pl). Plain ES module, no build step -- served
// through the importmap under the bare specifier "components/toggle"
// (adr/0025), imported once from assets/js/app.js.
//
// prolog/ui/toggle.pl already renders the button's correct initial
// state on every request (`aria-pressed`/`data-state`, plus
// `data-disabled`/`disabled` when disabled) -- reload, Turbo visit, or
// a Turbo-stream replace (adr/0024) all reproduce it with zero JS.
// What the platform cannot give for free is an *instant* flip on click
// without a server round trip; that is the entire job of this element.
//
// State lives on the wrapped <button>'s own attributes -- never a
// parallel JS store (adr/0026 rule 4) -- so a later server re-render of
// the same button can never desync from what this element last wrote:
// there is nothing to reconcile, because there is no second source of
// truth.
//
// Without JS, `<px-toggle>` never upgrades: the browser treats it as an
// unknown inline element and simply renders its light-DOM child (the
// button) in place, which is already correct and inert -- no
// navigation, no form submit, no error (adr/0026 rule 4's
// progressive-enhancement bar).

class PxToggle extends HTMLElement {
  connectedCallback() {
    this._button = this.querySelector("button");
    if (!this._button) return;
    this._onClick = this._onClick.bind(this);
    this._button.addEventListener("click", this._onClick);
  }

  disconnectedCallback() {
    if (this._button) {
      this._button.removeEventListener("click", this._onClick);
    }
  }

  _onClick() {
    if (this._button.disabled) return;
    const pressed = this._button.getAttribute("aria-pressed") === "true";
    const next = !pressed;
    this._button.setAttribute("aria-pressed", String(next));
    this._button.setAttribute("data-state", next ? "on" : "off");
  }
}

customElements.define("px-toggle", PxToggle);
