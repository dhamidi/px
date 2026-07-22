// assets/js/components/toggle_group.js -- <px-toggle-group> (adr/0026):
// the irreducible interactive sliver of the Toggle Group port
// (prolog/ui/toggle_group.pl). Plain ES module, no build step -- served
// through the importmap under the bare specifier "components/toggle_group"
// (adr/0025), imported once from assets/js/app.js.
//
// prolog/ui/toggle_group.pl already renders every Item's correct
// initial state on every request (`aria-pressed`/`aria-checked`,
// `data-state`, `data-disabled`/`disabled`, and exactly one Item's
// `tabindex="0"`) -- reload, Turbo visit, or a Turbo-stream replace
// (adr/0024) all reproduce it with zero JS; without JS, the group is
// still a fully labelled, plain-Tab-through set of real <button>s (no
// navigation, no form submit, no error -- adr/0026 rule 4's
// progressive-enhancement bar), just without arrow-key roving nav or
// an instant click-flip.
//
// This element's entire job is the two things the platform genuinely
// cannot give for free (the analysis doc's own verdict on Toggle
// Group -- "CUSTOM-ELEMENT, unavoidably"):
//
//   1. Arrow-key roving-tabindex navigation between Items -- delegated
//      wholesale to assets/js/lib/roving-focus.js's
//      installRovingFocus/2 (adr/0026 rule 5), the shared machinery
//      this component is the first consumer of. Orientation and loop
//      are read straight off the server-rendered `data-orientation`/
//      `data-loop` attributes, so a later server re-render that
//      changes either is picked up on the next connectedCallback with
//      no separate sync code needed.
//   2. Instant click-flip of `aria-pressed`/`aria-checked`/`data-state`
//      -- same "snappiness, not correctness" role ui/toggle.pl's own
//      <px-toggle> plays for a single Toggle. `type=single` additionally
//      enforces "at most one pressed Item" by flipping every OTHER
//      Item off on click (Radix's radio-like exclusivity), purely by
//      rewriting sibling Items' own attributes -- never a parallel JS
//      store (adr/0026 rule 4), so a later server re-render can never
//      desync from what this element last wrote.
//
// State lives entirely on each Item <button>'s own attributes -- there
// is nothing to reconcile, because there is no second source of truth.

import { installRovingFocus } from "lib/roving-focus";

const ITEM_SELECTOR = ".px-toggle-group-item";

class PxToggleGroup extends HTMLElement {
  connectedCallback() {
    this._root = this.querySelector('[role="radiogroup"], [role="toolbar"]');
    if (!this._root) return;

    this._type = this._root.getAttribute("role") === "radiogroup" ? "single" : "multiple";

    this._onClick = this._onClick.bind(this);
    this._root.addEventListener("click", this._onClick);

    const orientation = this._root.getAttribute("data-orientation") === "vertical"
      ? "vertical"
      : "horizontal";
    const loop = this._root.hasAttribute("data-loop");

    this._uninstallRovingFocus = installRovingFocus(this._root, {
      itemSelector: ITEM_SELECTOR,
      orientation,
      loop,
    });
  }

  disconnectedCallback() {
    if (this._root) this._root.removeEventListener("click", this._onClick);
    if (this._uninstallRovingFocus) this._uninstallRovingFocus();
  }

  _items() {
    return Array.from(this._root.querySelectorAll(ITEM_SELECTOR));
  }

  _onClick(event) {
    const item = event.target.closest(ITEM_SELECTOR);
    if (!item || !this._root.contains(item) || item.disabled) return;

    if (this._type === "single") {
      // Radio-like exclusivity: this Item becomes (or stays) pressed,
      // every sibling Item is forced off -- mirrors a native
      // <input type=radio> group's own click behaviour.
      this._setPressed(item, true);
      this._items().forEach((other) => {
        if (other !== item) this._setPressed(other, false);
      });
    } else {
      const pressed = item.getAttribute("aria-pressed") === "true";
      this._setPressed(item, !pressed);
    }
  }

  _setPressed(item, pressed) {
    item.setAttribute("data-state", pressed ? "on" : "off");
    if (this._type === "single") {
      item.setAttribute("aria-checked", String(pressed));
    } else {
      item.setAttribute("aria-pressed", String(pressed));
    }
  }
}

customElements.define("px-toggle-group", PxToggleGroup);
