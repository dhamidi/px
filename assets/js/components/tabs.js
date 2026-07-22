// assets/js/components/tabs.js -- <px-tabs> (adr/0026): the irreducible
// interactive sliver of the Tabs port (prolog/ui/tabs.pl). Plain ES
// module, no build step -- served through the importmap under the bare
// specifier "components/tabs" (adr/0025), imported once from
// assets/js/app.js.
//
// prolog/ui/tabs.pl already renders every part's correct initial state
// on every request (`aria-selected`/`data-state` on every Trigger,
// `hidden`/`data-state` on every Content, and exactly one Trigger's
// `tabindex="0"` -- the one matching Root's `value(_)`) -- reload, Turbo
// visit, or a Turbo-stream replace (adr/0024) all reproduce it with zero
// JS; without JS, the tablist is still a fully labelled, plain
// Tab-through set of real <button>s landing on whichever trigger the
// server marked selected, with its matching panel already the only one
// visible (adr/0026 rule 4's progressive-enhancement bar) -- just
// without arrow-key roving nav or automatic focus-driven activation.
//
// This element's entire job is the two things the platform genuinely
// cannot give for free (the analysis doc's own verdict on Tabs --
// "CUSTOM-ELEMENT: real state-machine work: roving-tabindex + activation
// modes"):
//
//   1. Arrow-key roving-tabindex navigation across Triggers -- delegated
//      wholesale to assets/js/lib/roving-focus.js's
//      installRovingFocus/2 (adr/0026 rule 5), the same shared machinery
//      assets/js/components/toggle_group.js is the first consumer of.
//      Orientation and loop are read straight off the server-rendered
//      `aria-orientation`/`data-loop` attributes on the tablist, so a
//      later server re-render that changes either is picked up on the
//      next connectedCallback with no separate sync code needed.
//   2. Automatic activation -- Radix's own default `activationMode`:
//      selecting a tab the instant it receives focus (by arrow-key nav
//      OR by click OR by a plain Tab keypress landing on it), no
//      separate Enter/Space press required. Implemented as one
//      `focusin` listener on the tablist (roving-focus's own `focusin`
//      listener, installed on the same container, always runs first and
//      already updated `tabindex` by the time this one sees the event --
//      the two listeners never race over who currently has
//      `tabindex="0"`) plus a `click` listener as a fallback for pointer
//      activation on an already-focused-but-not-yet-selected trigger
//      (e.g. right after a page load with no prior focus in the
//      tablist). Selecting a tab rewrites `aria-selected`/`data-state`
//      on every Trigger and `data-state`/`hidden` on every Content --
//      purely by rewriting siblings' own attributes -- never a parallel
//      JS store (adr/0026 rule 4), so a later server re-render can never
//      desync from what this element last wrote.
//
// State lives entirely on each Trigger/Content's own attributes -- there
// is nothing to reconcile, because there is no second source of truth.
// The Trigger<->Content link this element walks at activation time is
// exactly the `aria-controls`/`id` pair prolog/ui/tabs.pl's `tabs/2`
// wired up server-side.

import { installRovingFocus } from "lib/roving-focus";

const TRIGGER_SELECTOR = '[role="tab"]';
const PANEL_SELECTOR = '[role="tabpanel"]';

class PxTabs extends HTMLElement {
  connectedCallback() {
    this._list = this.querySelector('[role="tablist"]');
    if (!this._list) return;

    this._onFocusIn = this._onFocusIn.bind(this);
    this._onClick = this._onClick.bind(this);
    this._list.addEventListener("focusin", this._onFocusIn);
    this._list.addEventListener("click", this._onClick);

    const orientation =
      this._list.getAttribute("aria-orientation") === "vertical"
        ? "vertical"
        : "horizontal";
    const loop = this._list.hasAttribute("data-loop");

    this._uninstallRovingFocus = installRovingFocus(this._list, {
      itemSelector: TRIGGER_SELECTOR,
      orientation,
      loop,
    });
  }

  disconnectedCallback() {
    if (this._list) {
      this._list.removeEventListener("focusin", this._onFocusIn);
      this._list.removeEventListener("click", this._onClick);
    }
    if (this._uninstallRovingFocus) this._uninstallRovingFocus();
  }

  _onFocusIn(event) {
    this._activateFromEvent(event);
  }

  _onClick(event) {
    // Left-click only (guards against a ctrl/meta-click meant for
    // something else, e.g. opening in a new tab if a Trigger were ever
    // an <a> -- mirrors the analysis doc's own "guards against
    // ctrl-click" note), and only on a real pointer click, not a
    // click() synthesized by keyboard activation (already handled by
    // _onFocusIn).
    if (event.button !== 0 || event.ctrlKey || event.metaKey) return;
    this._activateFromEvent(event);
  }

  _activateFromEvent(event) {
    const trigger = event.target.closest(TRIGGER_SELECTOR);
    if (!trigger || !this._list.contains(trigger) || trigger.disabled) return;
    this._activate(trigger);
  }

  _activate(trigger) {
    if (trigger.getAttribute("aria-selected") === "true") return;

    this._triggers().forEach((t) => {
      const selected = t === trigger;
      t.setAttribute("aria-selected", String(selected));
      t.setAttribute("data-state", selected ? "active" : "inactive");
    });

    const activeId = trigger.id;
    this._panels().forEach((panel) => {
      const selected = panel.getAttribute("aria-labelledby") === activeId;
      panel.setAttribute("data-state", selected ? "active" : "inactive");
      if (selected) panel.removeAttribute("hidden");
      else panel.setAttribute("hidden", "");
    });
  }

  _triggers() {
    return Array.from(this._list.querySelectorAll(TRIGGER_SELECTOR));
  }

  _panels() {
    return Array.from(this.querySelectorAll(PANEL_SELECTOR));
  }
}

customElements.define("px-tabs", PxTabs);
