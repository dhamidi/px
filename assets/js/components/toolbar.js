// assets/js/components/toolbar.js -- <px-toolbar> (adr/0026): the
// irreducible interactive sliver of the Toolbar port
// (prolog/ui/toolbar.pl). Plain ES module, no build step -- served
// through the importmap under the bare specifier "components/toolbar"
// (adr/0025), imported once from assets/js/app.js.
//
// prolog/ui/toolbar.pl already renders every part's correct initial
// state on every request (role="toolbar", data-/aria-orientation,
// every item's tabindex="0|-1" with exactly one chosen across the
// whole toolbar including an embedded Toggle Group's own Items) --
// reload, Turbo visit, or a Turbo-stream replace (adr/0024) all
// reproduce it with zero JS; without JS the toolbar is still a fully
// labelled, plain-Tab-through set of real <button>/<a> elements (no
// navigation, no form submit, no error -- adr/0026 rule 4's
// progressive-enhancement bar), just without arrow-key roving nav.
//
// This element's job is the two things the platform genuinely cannot
// give for free (the analysis doc's own verdict on Toolbar --
// "CUSTOM-ELEMENT, same roving-tabindex justification as Tabs"):
//
//   1. Arrow-key roving-tabindex navigation across EVERY focusable
//      item -- Buttons, Links, and an embedded Toggle Group's own
//      Items, all as ONE flat tab-stop domain -- delegated wholesale
//      to assets/js/lib/roving-focus.js's installRovingFocus/2
//      (adr/0026 rule 5). ITEM_SELECTOR below matches both this
//      component's own item classes and Toggle Group's
//      ".px-toggle-group-item" directly, so querySelectorAll finds an
//      embedded group's Items too, regardless of how deep the
//      <px-toggle-group> wrapper nests them.
//   2. The Link Space-key patch -- the analysis doc's one other
//      toolbar-specific addition: a native <a> only activates on
//      Enter, never Space (a <button> gets Space for free from the
//      platform), so this element patches Space on ".px-toolbar-link"
//      to behave like a click.
//
// ---------------------------------------------------------------------
// THE NESTED TOGGLE GROUP TAB-STOP PROBLEM
// ---------------------------------------------------------------------
// The analysis doc's own callout: "an embedded toggle group must
// expose a 'roving focus disabled' mode so it defers to the parent
// toolbar's single controller instead of running its own." Half of
// that problem is solved on the Prolog/markup side already
// (prolog/ui/toolbar.pl's toolbar/2 forces an explicit active(true)/
// active(false) on every Item of every embedded Toggle Group, which
// unconditionally suppresses toggle_group.pl's own auto-pick -- see
// its module header). The OTHER half is a runtime-JS problem this
// file solves: assets/js/components/toggle_group.js's <px-toggle-group>
// ALWAYS calls installRovingFocus/2 on ITS OWN connectedCallback,
// completely unaware it might be sitting inside a Toolbar -- left
// alone, that installs a SECOND keydown/focusin listener pair on the
// very same buttons this element's own scope already governs (double
// key handling, two independently-maintained "the tab stop" bookkeeping
// systems disagreeing with each other).
//
// The fix needs ZERO changes to toggle_group.pl/toggle_group.js: every
// <px-toggle-group> instance already stores the uninstall callback
// installRovingFocus/2 hands back as `this._uninstallRovingFocus` (a
// plain, if informal, instance property -- there is no other public
// API for it). Once connected, THIS element reaches into every nested
// <px-toggle-group> it finds and calls that callback directly, tearing
// down ONLY that nested roving-focus scope -- the Toggle Group's click-
// to-press behaviour (aria-pressed/aria-checked/data-state flip,
// type=single exclusivity) is a SEPARATE listener on the same element
// and is left completely untouched, so an embedded Toggle Group still
// looks and clicks exactly like a standalone one; only its independent
// keyboard navigation defers to this single outer scope, exactly as
// the analysis doc asks for.
//
// Timing: nested custom elements upgrade AFTER their enclosing one --
// connectedCallback fires in document order, so at the moment THIS
// callback runs, a nested <px-toggle-group> may not be connected yet
// (its own connectedCallback, and so its own installRovingFocus/2
// call, hasn't happened) and reaching in immediately would find nothing
// to uninstall. Deferring the reach-in to a microtask sidesteps this
// entirely: every customElements reaction triggered by the same
// synchronous DOM change (the initial parse, or a later Turbo morph
// inserting a whole toolbar subtree at once) has already run by the
// next microtask checkpoint, whichever order parent/child happened to
// upgrade in.

import { installRovingFocus } from "lib/roving-focus";

const ITEM_SELECTOR = ".px-toolbar-item, .px-toggle-group-item";
const LINK_SELECTOR = "a.px-toolbar-link";
const SPACE_KEYS = [" ", "Spacebar"];

class PxToolbar extends HTMLElement {
  connectedCallback() {
    this._root = this.querySelector('[role="toolbar"]');
    if (!this._root) return;

    const orientation =
      this._root.getAttribute("data-orientation") === "vertical" ? "vertical" : "horizontal";
    const loop = this._root.hasAttribute("data-loop");

    this._onKeyDown = this._onKeyDown.bind(this);
    this._root.addEventListener("keydown", this._onKeyDown);

    this._uninstallRovingFocus = installRovingFocus(this._root, {
      itemSelector: ITEM_SELECTOR,
      orientation,
      loop,
    });

    // See "THE NESTED TOGGLE GROUP TAB-STOP PROBLEM" above.
    queueMicrotask(() => this._disableNestedToggleGroups());
  }

  disconnectedCallback() {
    if (this._root) this._root.removeEventListener("keydown", this._onKeyDown);
    if (this._uninstallRovingFocus) this._uninstallRovingFocus();
  }

  _disableNestedToggleGroups() {
    this.querySelectorAll("px-toggle-group").forEach((el) => {
      if (typeof el._uninstallRovingFocus === "function") {
        el._uninstallRovingFocus();
        el._uninstallRovingFocus = null;
      }
    });
  }

  // The Link Space-key patch -- roving-focus.js itself never intercepts
  // Space/Enter (its own header: "roving-focus only intercepts
  // navigation keys"), so this is purely additive and cannot conflict
  // with arrow/Home/End handling.
  _onKeyDown(event) {
    if (!SPACE_KEYS.includes(event.key)) return;
    const link = event.target.closest(LINK_SELECTOR);
    if (!link || !this._root.contains(link)) return;
    event.preventDefault();
    link.click();
  }
}

customElements.define("px-toolbar", PxToolbar);
