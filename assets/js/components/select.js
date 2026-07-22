// assets/js/components/select.js -- <px-select> (adr/0026): the port's
// finale (33/33). Plain ES module, no build step -- served through the
// importmap under the bare specifier "components/select" (adr/0025),
// imported once from assets/js/app.js.
//
// prolog/ui/select.pl already renders BOTH halves of this component with
// ZERO JS: a real, fully-functional native `<select>` (form-submittable,
// `required`/`disabled` native, a synthesized placeholder `<option>`)
// AND the custom trigger+listbox markup, derived from the exact same
// Items list so the two can never drift apart -- see that module's
// header, "No-JS fallback". `assets/css/ui.css` keeps the custom half
// invisible by default (`px-select:defined .px-select-trigger { ... }`)
// so a page without this element loaded shows only the plain, working
// native `<select>`.
//
// This element's job, once it upgrades an instance:
//
//   1. Hide the native `<select>` visually (a clip-rect technique, same
//      shape as prolog/ui/visually_hidden.pl's CSS) and drop it from the
//      tab order (`tabindex="-1"`) -- the custom Trigger becomes the
//      focusable control. The native element STAYS in the DOM and keeps
//      its `name`/`value` -- it never stops being the real form control.
//   2. Open/close the listbox (`showPopover()`/`hidePopover()` on
//      Content -- there is no native `popovertarget` wiring here, unlike
//      Popover/Dropdown Menu: the module header's "No-JS fallback"
//      decision is that the custom UI is fully inert without this
//      element, by design), positioning it via `lib/popper.js`'s
//      `position`/`autoUpdate` pair -- side="bottom" ALWAYS (prolog/ui/
//      select.pl's own "Positioning" decision: popper mode only, no
//      item-aligned mode), width pinned to the Trigger's own width via
//      the `--px-select-trigger-width` CSS custom property this element
//      writes on every position pass.
//   3. Roving highlight IS DOM focus, moved directly onto option
//      elements inside Content -- no `aria-activedescendant` anywhere,
//      matching docs/radix-port-analysis.md's own "Select moves real DOM
//      focus onto option elements... rather than the combobox-
//      activedescendant pattern." `[data-highlighted]` mirrors it, same
//      convention `lib/menu.js` already established (that module's own
//      per-level item-collection trick is NOT reused here, though --
//      Select has no nested submenu levels, so a plain
//      `contentEl.querySelectorAll('[role="option"]')` is already
//      correct with no scoping gymnastics needed).
//   4. Two-mode typeahead, per docs/radix-port-analysis.md's own
//      keyboard map: CLOSED-trigger printable keys direct-jump SELECT
//      (like native `<select>`, no popover ever opens); OPEN-content
//      printable keys only move the highlight (Enter/Space commits).
//      Both share one 1s-reset buffer + same-character-repeat-cycles
//      normalization, `lib/menu.js`'s own algorithm, re-implemented here
//      against this element's own (unnested) item collection rather than
//      imported -- see prolog/ui/select.pl's header, "Why Trigger/
//      Content aren't standalone templates" for the analogous "shared
//      IDEA, not shared CODE" call on the Prolog side; the ARIA shape
//      (listbox/option, not menu/menuitem) and the closed-trigger direct-
//      jump mode (menus have no closed-trigger keyboard surface at all)
//      are different enough that importing `lib/menu.js` would mean
//      fighting its menu-shaped assumptions more than reusing them.
//   5. `aria-selected` refinement: prolog/ui/select.pl's server-rendered
//      `aria-selected` is plain selection truth (module header's
//      documented simplification); this element additionally couples it
//      to focus the moment the listbox opens and highlight starts
//      moving (`isSelected && isHighlighted`), per
//      docs/radix-port-analysis.md's own VoiceOver-stutter rationale.
//   6. Selection sync: on every `selectItem`, writes the new value onto
//      the native `<select>` via its OWN property-setter descriptor
//      (`Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype,
//      'value').set`, bypassing any instance-level override) and
//      dispatches a real, bubbling `change` event -- exactly the
//      technique docs/radix-port-analysis.md's own "Select" entry flags
//      as `SelectBubbleInput`'s reusable core (this port's module header
//      quotes it verbatim), applied to the fallback element itself
//      rather than a separate hidden shadow input.
//
// State lives entirely in DOM attributes this element reads and writes
// (`data-state`, `data-highlighted`, `aria-selected`, `aria-expanded`,
// the native `<select>`'s own `value`) -- never a parallel JS store
// (adr/0026 rule 4).

import { position, autoUpdate } from "lib/popper";

const NATIVE_SELECTOR = ".px-select-native";
const TRIGGER_SELECTOR = ".px-select-trigger";
const VALUE_SELECTOR = ".px-select-value";
const CONTENT_SELECTOR = ".px-select-content";
const ITEM_SELECTOR = '[role="option"]';
const TYPEAHEAD_RESET_MS = 1000;

const nativeValueSetter = (() => {
  if (typeof window === "undefined" || !window.HTMLSelectElement) return null;
  const d = Object.getOwnPropertyDescriptor(window.HTMLSelectElement.prototype, "value");
  return d && d.set;
})();

class PxSelect extends HTMLElement {
  connectedCallback() {
    this._native = this.querySelector(NATIVE_SELECTOR);
    this._trigger = this.querySelector(TRIGGER_SELECTOR);
    this._value = this.querySelector(VALUE_SELECTOR);
    this._content = this.querySelector(CONTENT_SELECTOR);
    if (!this._native || !this._trigger || !this._content || !this._value) return;

    // -- Hide the native control, keep it as the value store (module
    //    header, step 1). --------------------------------------------
    this._native.setAttribute("tabindex", "-1");
    this._native.setAttribute("aria-hidden", "true");

    this._stopAutoUpdate = null;
    this._typeaheadBuffer = "";
    this._typeaheadLastAt = 0;

    this._onTriggerClick = this._onTriggerClick.bind(this);
    this._onTriggerKeyDown = this._onTriggerKeyDown.bind(this);
    this._onContentKeyDown = this._onContentKeyDown.bind(this);
    this._onContentClick = this._onContentClick.bind(this);
    this._onContentPointerMove = this._onContentPointerMove.bind(this);
    this._onBeforeToggle = this._onBeforeToggle.bind(this);
    this._onToggle = this._onToggle.bind(this);
    this._onWindowBlur = this._onWindowBlur.bind(this);

    this._trigger.addEventListener("click", this._onTriggerClick);
    this._trigger.addEventListener("keydown", this._onTriggerKeyDown);
    this._content.addEventListener("keydown", this._onContentKeyDown);
    this._content.addEventListener("click", this._onContentClick);
    this._content.addEventListener("pointermove", this._onContentPointerMove);
    this._content.addEventListener("beforetoggle", this._onBeforeToggle);
    this._content.addEventListener("toggle", this._onToggle);
    window.addEventListener("blur", this._onWindowBlur);

    // Same native-`popover`-has-no-static-open-attribute gap
    // popover.js/`_menu.pl`'s own Content document: reconcile an
    // already-`data-state="open"` server render by actually opening it.
    if (this._content.getAttribute("data-state") === "open" && !this._content.matches(":popover-open")) {
      this._content.showPopover();
    }
  }

  disconnectedCallback() {
    if (this._trigger) {
      this._trigger.removeEventListener("click", this._onTriggerClick);
      this._trigger.removeEventListener("keydown", this._onTriggerKeyDown);
    }
    if (this._content) {
      this._content.removeEventListener("keydown", this._onContentKeyDown);
      this._content.removeEventListener("click", this._onContentClick);
      this._content.removeEventListener("pointermove", this._onContentPointerMove);
      this._content.removeEventListener("beforetoggle", this._onBeforeToggle);
      this._content.removeEventListener("toggle", this._onToggle);
    }
    window.removeEventListener("blur", this._onWindowBlur);
    this._stopPositioning();
  }

  // -- Item collection (no nesting -- module header, step 3). ---------

  items() {
    return Array.from(this._content.querySelectorAll(ITEM_SELECTOR));
  }

  isDisabled(item) {
    return item.hasAttribute("data-disabled") || item.getAttribute("aria-disabled") === "true";
  }

  enabledItems() {
    return this.items().filter((item) => !this.isDisabled(item));
  }

  selectedItem() {
    const value = this._native.value;
    return this.items().find((item) => item.getAttribute("data-value") === value) || null;
  }

  highlightedItem() {
    const active = document.activeElement;
    return active && this.items().includes(active) ? active : null;
  }

  textOf(item) {
    return item.getAttribute("data-text-value") || item.textContent.trim();
  }

  // -- Highlight (== focus). -------------------------------------------

  highlight(item) {
    if (!item) return;
    this.items().forEach((el) => el.removeAttribute("data-highlighted"));
    item.setAttribute("data-highlighted", "");
    item.focus({ preventScroll: false });
    this._syncAriaSelected();
  }

  _syncAriaSelected() {
    const selectedValue = this._native.value;
    this.items().forEach((item) => {
      const isSelected = item.getAttribute("data-value") === selectedValue;
      const isHighlighted = item.hasAttribute("data-highlighted");
      item.setAttribute("aria-selected", String(isSelected && isHighlighted));
    });
  }

  highlightFirst() {
    const items = this.enabledItems();
    if (items.length) this.highlight(items[0]);
  }

  highlightLast() {
    const items = this.enabledItems();
    if (items.length) this.highlight(items[items.length - 1]);
  }

  moveHighlight(delta) {
    const items = this.enabledItems();
    if (items.length === 0) return;
    const current = this.highlightedItem();
    let idx = current ? items.indexOf(current) : -1;
    idx = idx === -1 ? (delta > 0 ? 0 : items.length - 1) : (idx + delta + items.length) % items.length;
    this.highlight(items[idx]);
  }

  // -- Typeahead (module header, step 4). ------------------------------

  matchTypeahead(char, fromIndex, items) {
    const now = Date.now();
    if (now - this._typeaheadLastAt > TYPEAHEAD_RESET_MS) this._typeaheadBuffer = "";
    this._typeaheadLastAt = now;
    this._typeaheadBuffer += char.toLowerCase();

    let search = this._typeaheadBuffer;
    const isSingleCharRepeat = search.length > 1 && [...search].every((c) => c === search[0]);
    if (isSingleCharRepeat) search = search[0];

    const ordered = items.slice(fromIndex + 1).concat(items.slice(0, fromIndex + 1));
    return ordered.find((item) => this.textOf(item).toLowerCase().startsWith(search)) || null;
  }

  typeaheadClosed(char) {
    const items = this.enabledItems();
    if (items.length === 0) return;
    const current = this.selectedItem();
    const currentIdx = current ? items.indexOf(current) : -1;
    const match = this.matchTypeahead(char, currentIdx, items);
    if (match) this.selectItem(match, { close: false });
  }

  typeaheadOpen(char) {
    const items = this.enabledItems();
    if (items.length === 0) return;
    const current = this.highlightedItem();
    const currentIdx = current ? items.indexOf(current) : -1;
    const match = this.matchTypeahead(char, currentIdx, items);
    if (match) this.highlight(match);
  }

  // -- Selection / open / close. ---------------------------------------

  selectItem(item, { close }) {
    if (!item || this.isDisabled(item)) return;
    const value = item.getAttribute("data-value");
    this._setNativeValue(value);
    this._syncTriggerValue(item);
    this._syncItemStates(item);
    if (close) this.close(true);
  }

  _setNativeValue(value) {
    if (nativeValueSetter) {
      nativeValueSetter.call(this._native, value);
    } else {
      this._native.value = value;
    }
    this._native.dispatchEvent(new Event("change", { bubbles: true }));
  }

  _syncTriggerValue(item) {
    this._value.textContent = this.textOf(item);
    this._value.removeAttribute("data-placeholder");
    this._trigger.removeAttribute("data-placeholder");
  }

  _syncItemStates(selectedItem) {
    this.items().forEach((item) => {
      const isSelected = item === selectedItem;
      item.setAttribute("data-state", isSelected ? "checked" : "unchecked");
      const indicator = item.querySelector(":scope > .px-select-item-indicator");
      if (indicator) indicator.setAttribute("data-state", isSelected ? "checked" : "unchecked");
    });
    this._syncAriaSelected();
  }

  open() {
    if (this._trigger.hasAttribute("disabled")) return;
    if (!this._content.matches(":popover-open")) this._content.showPopover();
    const toHighlight = this.selectedItem() || this.enabledItems()[0];
    if (toHighlight) {
      // Wait a tick so the popover is actually laid out (and thus
      // focusable) before moving focus onto an item inside it -- same
      // "toggle fires after the state change has taken effect" timing
      // popover.js's own header documents.
      queueMicrotask(() => this.highlight(toHighlight));
    }
  }

  close(refocusTrigger) {
    if (this._content.matches(":popover-open")) this._content.hidePopover();
    if (refocusTrigger) this._trigger.focus();
  }

  isOpen() {
    return this._content.matches(":popover-open");
  }

  // -- Trigger event handlers. ------------------------------------------

  _onTriggerClick() {
    if (this.isOpen()) {
      this.close(true);
    } else {
      this.open();
    }
  }

  _onTriggerKeyDown(event) {
    if (this.isOpen()) return;
    switch (event.key) {
      case "ArrowDown":
      case "ArrowUp":
      case "Enter":
      case " ":
        event.preventDefault();
        this.open();
        break;
      default:
        if (event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
          event.preventDefault();
          this.typeaheadClosed(event.key);
        }
    }
  }

  // -- Content (open listbox) event handlers. ---------------------------

  _onContentKeyDown(event) {
    const target = event.target;
    if (target !== this._content && !this.items().includes(target)) return;

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        this.moveHighlight(1);
        break;
      case "ArrowUp":
        event.preventDefault();
        this.moveHighlight(-1);
        break;
      case "Home":
        event.preventDefault();
        this.highlightFirst();
        break;
      case "End":
        event.preventDefault();
        this.highlightLast();
        break;
      case "Tab":
        event.preventDefault();
        break;
      case "Enter":
      case " ":
        event.preventDefault();
        this.selectItem(this.highlightedItem(), { close: true });
        break;
      case "Escape":
        // Native popover light-dismiss already closes Content for
        // Escape; explicitly closing here too keeps the refocus-trigger
        // behaviour consistent regardless of who handles the key first.
        event.preventDefault();
        this.close(true);
        break;
      default:
        if (event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
          this.typeaheadOpen(event.key);
        }
    }
  }

  _onContentClick(event) {
    const item = event.target.closest(ITEM_SELECTOR);
    if (!item || !this._content.contains(item)) return;
    if (this.isDisabled(item)) return;
    this.selectItem(item, { close: true });
  }

  _onContentPointerMove(event) {
    const item = event.target.closest(ITEM_SELECTOR);
    if (!item || !this._content.contains(item) || this.isDisabled(item)) return;
    if (!item.hasAttribute("data-highlighted")) this.highlight(item);
  }

  // -- Native `popover` beforetoggle/toggle -- state mirror + positioning
  //    (module header, step 2 -- same split popover.js's own header
  //    documents). -------------------------------------------------------

  _onBeforeToggle(event) {
    const opening = event.newState === "open";
    const state = opening ? "open" : "closed";
    this._content.setAttribute("data-state", state);
    this._trigger.setAttribute("data-state", state);
    this._trigger.setAttribute("aria-expanded", String(opening));
    if (!opening) {
      this._stopPositioning();
      this.items().forEach((el) => el.removeAttribute("data-highlighted"));
      this._syncAriaSelected();
    }
  }

  _onToggle(event) {
    if (event.newState === "open") this._startPositioning();
  }

  _onWindowBlur() {
    if (this.isOpen()) this.close(false);
  }

  // -- Positioning: popper mode only, side="bottom" always, width
  //    pinned to the Trigger's own width (prolog/ui/select.pl's
  //    "Positioning" decision). -----------------------------------------

  _startPositioning() {
    this._stopPositioning();
    this._stopAutoUpdate = autoUpdate(this._trigger, this._content, () => {
      this._content.style.setProperty("--px-select-trigger-width", `${this._trigger.getBoundingClientRect().width}px`);
      position(this._trigger, this._content, { side: "bottom", align: "start", sideOffset: 4, flip: true, boundaryPadding: 8 });
    });
  }

  _stopPositioning() {
    if (this._stopAutoUpdate) {
      this._stopAutoUpdate();
      this._stopAutoUpdate = null;
    }
  }
}

customElements.define("px-select", PxSelect);
