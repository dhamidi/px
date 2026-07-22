// assets/js/components/dropdown_menu.js -- <px-dropdown-menu> (adr/0026):
// the irreducible interactive sliver of the Dropdown Menu port
// (prolog/ui/dropdown_menu.pl), and lib/menu.js's proving consumer.
// Plain ES module, no build step -- served through the importmap under
// the bare specifier "components/dropdown_menu" (adr/0025), imported
// once from assets/js/app.js.
//
// prolog/ui/dropdown_menu.pl already renders a real, focusable
// <button> Trigger (aria-haspopup="menu" aria-expanded="false"
// data-state="closed", PLUS a native `popovertarget` pointing at
// Content's id) and a native `popover="auto"` Content (role="menu",
// data-state="closed") -- without this element ever loading, clicking
// the Trigger still opens/closes Content (native popovertarget) and
// Escape/outside-click still dismiss it (native popover light-dismiss)
// with zero JS; nothing inside Content is interactive yet (no roving
// highlight, no typeahead, no submenu, no checkbox/radio toggling) --
// the documented no-JS story (adr/0026 rule 4's progressive-enhancement
// bar), same shape as every other Content-behind-a-custom-element port
// in this library.
//
// This element's entire job is exactly the analysis doc's own list of
// what Dropdown Menu adds ON TOP of the shared Menu primitive (see
// prolog/ui/dropdown_menu.pl's header for the full quote):
//
//   1. ArrowDown on the Trigger always OPENS (never toggles closed) --
//      matches native combobox/menu-button convention. Enter/Space
//      toggling needs no code here at all: they are native `<button>`
//      activation, which the Trigger's own `popovertarget` attribute
//      already turns into a show/hide, exactly like a click.
//   2. Auto-focusing the first item on EVERY open path -- click-via-
//      popovertarget and ArrowDown-via-showPopover() alike -- by
//      hooking the native `toggle` event (fired identically regardless
//      of which of those two triggered it) rather than each open path
//      individually.
//   3. Wiring assets/js/lib/menu.js's full engine (roving highlight,
//      typeahead, submenu hover/keyboard/positioning, checkbox/radio
//      toggling, close-on-select) onto Content, ONCE, at connect time
//      -- lib/menu.js's own header is the contract for everything that
//      happens inside Content from here on; this element never
//      duplicates any of it.
//   4. Positioning Content relative to Trigger via lib/popper.js
//      (side/align/offset/flip, read off Content's own `data-side`/
//      `data-align`/`data-side-offset`/`data-align-offset`), kept live
//      via `autoUpdate` while open -- identical technique to
//      assets/js/components/popover.js/tooltip.js/hover_card.js.
//   5. Mirroring `data-state`/`aria-expanded` off the native `toggle`/
//      `beforetoggle` events so they never drift from what the browser
//      actually did -- the same split popover.js/hover_card.js already
//      established (`beforetoggle`: sync state, stop positioning before
//      close; `toggle`: start positioning after open).
//
// Escape and outside-click dismissal need no code here: Content is
// `popover="auto"` (prolog/ui/_menu.pl's `menu_content/2`), so the
// browser's own light-dismiss algorithm handles both, flowing through
// the same `beforetoggle`/`toggle` handlers as every other close path
// (including lib/menu.js's own close-on-select, which closes Content
// by calling `hidePopover()` directly).
//
// State lives entirely on the Trigger's and Content's own DOM
// attributes -- never a parallel JS store (adr/0026 rule 4).

import { position, autoUpdate } from "lib/popper";
import { installMenu } from "lib/menu";

const TRIGGER_SELECTOR = '[aria-haspopup="menu"]';
const CONTENT_SELECTOR = ".px-menu-content";

class PxDropdownMenu extends HTMLElement {
  connectedCallback() {
    this._trigger = this.querySelector(TRIGGER_SELECTOR);
    this._content = this.querySelector(CONTENT_SELECTOR);
    if (!this._trigger || !this._content) return;

    this._stopAutoUpdate = null;
    this._menu = installMenu(this._content, { isSub: false });

    this._onTriggerKeyDown = this._onTriggerKeyDown.bind(this);
    this._onBeforeToggle = this._onBeforeToggle.bind(this);
    this._onToggle = this._onToggle.bind(this);

    this._trigger.addEventListener("keydown", this._onTriggerKeyDown);
    this._content.addEventListener("beforetoggle", this._onBeforeToggle);
    this._content.addEventListener("toggle", this._onToggle);

    if (this._content.getAttribute("data-state") === "open" && !this._content.matches(":popover-open")) {
      this._content.showPopover();
    }
  }

  disconnectedCallback() {
    if (this._trigger) this._trigger.removeEventListener("keydown", this._onTriggerKeyDown);
    if (this._content) {
      this._content.removeEventListener("beforetoggle", this._onBeforeToggle);
      this._content.removeEventListener("toggle", this._onToggle);
    }
    if (this._menu) this._menu.uninstall();
    this._stopPositioning();
  }

  // ArrowDown always opens -- native popovertarget only TOGGLES, so an
  // already-open menu must not be re-closed by this; nothing to do
  // when it's already open (falls through as a no-op showPopover()
  // guard, same pattern popover.js's own connectedCallback uses).
  _onTriggerKeyDown(event) {
    if (event.key !== "ArrowDown") return;
    event.preventDefault();
    if (!this._content.matches(":popover-open")) this._content.showPopover();
  }

  _onBeforeToggle(event) {
    const opening = event.newState === "open";
    this._syncState(opening);
    if (!opening) this._stopPositioning();
  }

  _onToggle(event) {
    if (event.newState === "open") {
      this._startPositioning();
      // Every open path -- click-via-popovertarget or ArrowDown-via-
      // showPopover() -- funnels through this one native `toggle`
      // event, so one call site covers the module header's "focuses
      // first item" requirement for both.
      this._menu.focusFirst();
    }
  }

  _syncState(open) {
    const state = open ? "open" : "closed";
    this._content.setAttribute("data-state", state);
    this._trigger.setAttribute("aria-expanded", String(open));
    this._trigger.setAttribute("data-state", state);
  }

  _startPositioning() {
    this._stopPositioning();
    const options = this._readOptions();
    this._stopAutoUpdate = autoUpdate(this._trigger, this._content, () => {
      position(this._trigger, this._content, options);
    });
  }

  _stopPositioning() {
    if (this._stopAutoUpdate) {
      this._stopAutoUpdate();
      this._stopAutoUpdate = null;
    }
  }

  _readOptions() {
    const side = this._content.getAttribute("data-side") || "bottom";
    const align = this._content.getAttribute("data-align") || "start";
    const sideOffset = Number(this._content.getAttribute("data-side-offset")) || 0;
    const alignOffset = Number(this._content.getAttribute("data-align-offset")) || 0;
    return { side, align, sideOffset, alignOffset, flip: true, boundaryPadding: 8 };
  }
}

customElements.define("px-dropdown-menu", PxDropdownMenu);
