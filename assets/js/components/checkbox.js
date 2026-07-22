// assets/js/components/checkbox.js -- <px-checkbox> (adr/0026): the one
// JS-only gap the Checkbox port (prolog/ui/checkbox.pl) cannot close
// natively -- indeterminate. Plain ES module, no build step -- served
// through the importmap under the bare specifier "components/checkbox"
// (adr/0025), imported once from assets/js/app.js.
//
// Unlike Switch (assets/js/components/switch.js), which wraps EVERY
// instance in its own custom element to keep aria-checked/data-state
// live after a click, prolog/ui/checkbox.pl only reaches for
// <px-checkbox> when the initial state is indeterminate --
// docs/radix-port-analysis.md draws that exact line for Checkbox
// ("Interactivity class: NATIVE for 2-state; CUSTOM-ELEMENT for
// indeterminate"), unlike Switch's undivided "NATIVE" verdict. A plain
// checked/unchecked checkbox therefore ships with NO custom element at
// all: the box's background/border still flip instantly on click via
// the native :checked pseudo-class (assets/css/ui.css), zero JS --
// only the Indicator's Presence-gated glyph and the data-state/
// aria-checked *attributes* go stale until the next server render
// without JS, the same progressive-enhancement bar toggle.js/switch.js
// already accept for their own JS-dependent slivers, drawn one native
// limitation further out here because the analysis doc only asks for
// JS in the indeterminate case.
//
// This element's job, for the indeterminate case only, is two-fold:
//
//   1. On connect, set the wrapped input's `.indeterminate` IDL
//      property -- the one piece of this contract with NO HTML
//      attribute at all, so prolog/ui/checkbox.pl cannot write it
//      server-side no matter what (it already writes
//      `aria-checked="mixed"` explicitly server-side, since a native
//      indeterminate checkbox does not report that to assistive tech
//      on its own -- see the analysis doc's Checkbox entry).
//   2. On the wrapped input's `change` event -- fired the moment a user
//      clicks or Space-activates it, which the HTML spec's own
//      pre-click activation steps ALWAYS resolve to a concrete
//      checked/unchecked value, clearing `.indeterminate` to false as a
//      side effect the browser performs on its own -- mirror that
//      resolution onto `data-state`/`aria-checked` (input and Root
//      label) and the Indicator's `data-state`, so the DOM's explicit
//      attributes agree with what the user just saw happen.
//
// State lives entirely on the wrapped elements' own attributes -- never
// a parallel JS store (adr/0026 rule 4) -- so a later server re-render
// can never desync from what this element last wrote.
//
// Without JS, <px-checkbox> never upgrades: the browser treats it as an
// unknown inline element and renders its light-DOM children (the label,
// input and indicator) in place -- already a real, focusable,
// keyboard-operable checkbox; it just paints as an ordinary unchecked
// box (there is no native way to render indeterminate without the
// JS-only `.indeterminate` property this element exists to set) until
// the module loads.

class PxCheckbox extends HTMLElement {
  connectedCallback() {
    this._label = this.querySelector("label");
    this._input = this.querySelector('input[type="checkbox"]');
    this._indicator = this.querySelector(".px-checkbox-indicator");
    if (!this._input) return;
    this._input.indeterminate =
      this._input.getAttribute("data-state") === "indeterminate";
    this._onChange = this._onChange.bind(this);
    this._input.addEventListener("change", this._onChange);
  }

  disconnectedCallback() {
    if (this._input) {
      this._input.removeEventListener("change", this._onChange);
    }
  }

  _onChange() {
    // Native pre-click activation steps already cleared
    // this._input.indeterminate and flipped .checked -- mirror that
    // resolution onto the explicit attributes this contract owns.
    const state = this._input.checked ? "checked" : "unchecked";
    this._input.setAttribute("aria-checked", String(this._input.checked));
    this._input.setAttribute("data-state", state);
    if (this._label) this._label.setAttribute("data-state", state);
    if (this._indicator) this._indicator.setAttribute("data-state", state);
  }
}

customElements.define("px-checkbox", PxCheckbox);
