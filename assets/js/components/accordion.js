// assets/js/components/accordion.js -- <px-accordion> (adr/0026): the
// irreducible interactive sliver of the Accordion port
// (prolog/ui/accordion.pl). Plain ES module, no build step -- served
// through the importmap under the bare specifier "components/accordion"
// (adr/0025), imported once from assets/js/app.js.
//
// prolog/ui/accordion.pl already renders every Item's correct initial
// state on every request (`open` / `data-state` / `aria-expanded` /
// `aria-controls` per Trigger, `role="region"`/`aria-labelledby` per
// Content, and -- when type=single -- a shared native `name` grouping
// that makes the browser enforce "at most one open" with ZERO JS).
// Without this element ever loading:
//   - type=single, collapsible=true   -- fully correct, native <details
//     name> grouping handles opening-exclusivity by itself.
//   - type=multiple                   -- fully correct, every item
//     independent; just no arrow-key roving nav (plain sequential
//     Tab-through over every trigger still works).
//   - type=single, collapsible=false  -- degrades to collapsible=true
//     behaviour (the mandatory-open guarantee is not enforced without
//     JS; nothing breaks, documented in prolog/ui/accordion.pl's
//     header).
//
// This element's entire job is the things the platform genuinely
// cannot give for free:
//
//   1. Arrow-key roving-tabindex navigation between triggers --
//      delegated wholesale to assets/js/lib/roving-focus.js's
//      installRovingFocus/2 (adr/0026 rule 5), the same shared module
//      components/toggle_group.js already proved out. Vertical
//      orientation is Accordion's own default (read off Root's
//      data-orientation so a server-side orientation("horizontal")
//      override is honoured too).
//
//   2. Blocking the close of the ONE mandatory-open item when
//      type=single and collapsible=false -- native <details name>
//      grouping already gives opening-exclusivity for free (switching
//      which item is open needs no JS at all), but it has no concept
//      of "refuse to close". This uses the modern `beforetoggle` event
//      (`ToggleEvent.newState`) to cancel exactly that one case, while
//      still letting the SAME event fire uncancelled on whichever
//      sibling is being auto-closed by name-group exclusivity when a
//      *different* item is opened (distinguished via a `click`
//      listener that records which trigger the user actually
//      activated -- see _onClick/_onBeforeToggle below).
//
//   3. Re-syncing every OTHER attribute this component's Prolog
//      template computed once, server-side, after ANY native `toggle`
//      -- exactly collapsible.pl's own documented gap #2
//      ("no controlled-state sync after native interaction"), closed
//      here for Accordion: data-state (Item, Header, Trigger, Content),
//      aria-expanded and aria-controls (Trigger, "only while open" per
//      the upstream quirk this port keeps), and -- type=single,
//      collapsible=false only -- which trigger currently carries
//      aria-disabled="true" (recomputed from scratch after every
//      toggle, not tracked incrementally, so it can never drift).
//
// State lives entirely on each Item's own DOM attributes -- never a
// parallel JS store (adr/0026 rule 4), so a later server re-render or
// Turbo morph/stream (adr/0024) can't desync from what this element
// last wrote.

import { installRovingFocus } from "lib/roving-focus";

const ITEM_SELECTOR = ".px-accordion-item";
const TRIGGER_SELECTOR = ".px-accordion-trigger";
const HEADER_SELECTOR = ".px-accordion-header";
const CONTENT_SELECTOR = '[role="region"]';

class PxAccordion extends HTMLElement {
  connectedCallback() {
    this._root = this.querySelector("[data-type]");
    if (!this._root) return;

    this._type = this._root.getAttribute("data-type") === "single" ? "single" : "multiple";
    this._collapsible = this._root.hasAttribute("data-collapsible");
    this._activatedItem = null;

    const orientation = this._root.getAttribute("data-orientation") === "horizontal"
      ? "horizontal"
      : "vertical";

    this._uninstallRovingFocus = installRovingFocus(this._root, {
      itemSelector: TRIGGER_SELECTOR,
      orientation,
      loop: false,
    });

    this._onClick = this._onClick.bind(this);
    this._onBeforeToggle = this._onBeforeToggle.bind(this);
    this._onToggle = this._onToggle.bind(this);

    this._root.addEventListener("click", this._onClick);
    this._items().forEach((item) => {
      item.addEventListener("beforetoggle", this._onBeforeToggle);
      item.addEventListener("toggle", this._onToggle);
    });

    this._syncAll();
  }

  disconnectedCallback() {
    if (!this._root) return;
    this._root.removeEventListener("click", this._onClick);
    this._items().forEach((item) => {
      item.removeEventListener("beforetoggle", this._onBeforeToggle);
      item.removeEventListener("toggle", this._onToggle);
    });
    if (this._uninstallRovingFocus) this._uninstallRovingFocus();
  }

  _items() {
    return Array.from(this._root.querySelectorAll(ITEM_SELECTOR));
  }

  // Records which Item the user actually activated (click OR
  // Space/Enter -- both dispatch a "click" as part of <summary>'s
  // native activation behaviour) BEFORE the browser's own toggle
  // machinery runs its default action. beforetoggle fires
  // synchronously as part of that same default action, so by the time
  // it fires this is already up to date.
  _onClick(event) {
    const trigger = event.target.closest(TRIGGER_SELECTOR);
    if (!trigger || !this._root.contains(trigger)) return;
    this._activatedItem = trigger.closest(ITEM_SELECTOR);
  }

  // Cancels closing the ONE mandatory-open item (type=single,
  // collapsible=false) -- but only when the user is directly toggling
  // THAT item off, never when it's being auto-closed as the side
  // effect of a *different* item being opened (native <details name>
  // grouping's own job, which must be allowed to proceed).
  _onBeforeToggle(event) {
    if (this._type !== "single" || this._collapsible) return;
    if (event.newState !== "closed") return;
    const details = event.currentTarget;
    if (!details.open) return;
    if (details !== this._activatedItem) return;
    event.preventDefault();
  }

  // Native interaction (this item's own click, OR the browser force-
  // closing a sibling for name-group exclusivity, which also fires
  // `toggle`) already flipped <details>.open -- mirror it onto every
  // attribute prolog/ui/accordion.pl computed statically at render
  // time.
  _onToggle() {
    this._syncAll();
  }

  _syncAll() {
    const items = this._items();
    let mandatoryOpenTrigger = null;

    items.forEach((details) => {
      const open = details.open;
      const state = open ? "open" : "closed";
      const trigger = details.querySelector(TRIGGER_SELECTOR);
      const header = details.querySelector(HEADER_SELECTOR);
      const content = details.querySelector(CONTENT_SELECTOR);

      details.setAttribute("data-state", state);
      if (header) header.setAttribute("data-state", state);
      if (content) content.setAttribute("data-state", state);

      if (trigger) {
        trigger.setAttribute("data-state", state);
        trigger.setAttribute("aria-expanded", String(open));

        const contentId = content ? content.id : null;
        if (open && contentId) {
          trigger.setAttribute("aria-controls", contentId);
        } else {
          trigger.removeAttribute("aria-controls");
        }

        if (open && this._type === "single" && !this._collapsible && !trigger.hasAttribute("data-disabled")) {
          mandatoryOpenTrigger = trigger;
        } else {
          trigger.removeAttribute("aria-disabled");
        }
      }
    });

    if (mandatoryOpenTrigger) mandatoryOpenTrigger.setAttribute("aria-disabled", "true");
  }
}

customElements.define("px-accordion", PxAccordion);
