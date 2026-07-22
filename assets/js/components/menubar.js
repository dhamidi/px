// assets/js/components/menubar.js -- <px-menubar> (adr/0026): the
// coordination layer of the Menubar port (prolog/ui/menubar.pl),
// composed ENTIRELY out of the two shared engines this task requires
// reused, unmodified: assets/js/lib/menu.js (one instance per
// top-level menu's Content, exactly like assets/js/components/
// dropdown_menu.js already installs one per Dropdown Menu) and
// assets/js/lib/roving-focus.js (one instance over the whole trigger
// row, exactly like assets/js/components/toolbar.js already installs
// one over a toolbar's whole item row). Plain ES module, no build
// step -- served through the importmap under the bare specifier
// "components/menubar" (adr/0025), imported once from assets/js/app.js.
//
// prolog/ui/menubar.pl already renders, per menu, a real, focusable
// <button role="menuitem"> Trigger (aria-haspopup="menu"
// aria-expanded="false" data-state="closed" tabindex="0" on exactly
// ONE trigger across the whole bar, PLUS a native `popovertarget`
// pointing at its own Content's id) and a native `popover="auto"`
// Content (role="menu", data-state="closed") -- without this element
// ever loading, clicking any Trigger still opens/closes its own
// Content independently (native popovertarget) and Escape/outside-
// click still dismiss it (native popover light-dismiss), with zero
// JS; nothing inside any Content is interactive yet, and there is no
// hover-switch or cross-menu arrow nav -- the documented no-JS story
// (adr/0026 rule 4's progressive-enhancement bar), same shape as
// every other Content-behind-a-custom-element port in this library.
//
// ---------------------------------------------------------------------
// WHY THIS FILE NEEDS NO CHANGES TO lib/menu.js OR lib/roving-focus.js
// ---------------------------------------------------------------------
//
// The task this element solves has exactly two novel pieces, both of
// which turn out to be pure coordination, addable at the menubar level
// with event listeners alone -- never touching either shared module's
// own source:
//
//   1. HOVER-SWITCH, BUT ONLY WHILE SOMETHING IS ALREADY OPEN. A
//      `pointerenter` (mouse only) on a Trigger whose own Content isn't
//      already open, while a DIFFERENT menu's Content currently IS open
//      (`:popover-open`), calls `showPopover()` on this Trigger's
//      Content. That single call is enough: per the native Popover
//      light-dismiss algorithm (the same one prolog/ui/_menu.pl's own
//      header leans on for submenu stacking), showing a new "auto"
//      popover whose invoking element is NOT contained within any
//      currently-open "auto" popover automatically closes those other
//      "auto" popovers first -- so the previously-open menu's own
//      `beforetoggle`/`toggle` "closed" events fire, and every state
//      sync this file already wires for that Content (below) runs
//      exactly as if the user had clicked to close it. No manual
//      "close the old one" call is needed or written here. Before
//      anything is open, `pointerenter` deliberately does nothing --
//      hover alone never opens the FIRST menu, matching native OS menu
//      bars and the task's own "open-on-hover-when-open, not before".
//
//   2. ArrowLeft/ArrowRight BRIDGING "move between top-level triggers"
//      (free -- `installRovingFocus`'s own job, unmodified, exactly
//      like components/toolbar.js's usage of it) and "move between
//      adjacent menubar menus from inside an open Content" (new code
//      below). The bridge is a single `keydown` listener on
//      `<px-menubar>` itself (bubble phase, so it runs AFTER every
//      listener `installMenu` attached directly to a Content element,
//      at any nesting depth, per normal DOM event order) that:
//        a. Ignores the event entirely unless `event.target` has a
//           `.px-menu-content` ancestor -- i.e., the key press
//           originated INSIDE some open menu's items, not on a Trigger
//           button. Trigger-to-trigger nav is `installRovingFocus`'s
//           job alone; this listener never touches it (their guards
//           are mutually exclusive, so double-handling is structurally
//           impossible, not just avoided by convention).
//        b. Ignores it unless that `.px-menu-content` ancestor is
//           literally one of THIS menubar's own top-level Contents
//           (not a nested submenu's Content) -- ArrowRight/ArrowLeft
//           pressed while deep inside a submenu is a no-op at the
//           cross-menu level, matching native menu behaviour (you
//           don't jump top-level menus mid-submenu).
//        c. Checks `event.defaultPrevented`. lib/menu.js's own
//           `onKeyDown` (installed on every Content, including this
//           top-level one) calls `event.preventDefault()` in exactly
//           two cases that must WIN over this bridge: ArrowRight on a
//           highlighted SubTrigger (opens that submenu instead of
//           jumping menus) and ArrowLeft while `isSub: true` (closes
//           one submenu level instead of jumping menus -- moot at the
//           top level, since top-level Content is always installed
//           with `isSub: false`, but the same `defaultPrevented` check
//           handles both cases uniformly with zero special-casing
//           here). Because `contentEl.addEventListener("keydown", ...)`
//           runs synchronously, in DOM order, strictly before this
//           bubble-phase listener on the ancestor `<px-menubar>` even
//           starts, `event.defaultPrevented` is already fully resolved
//           by the time this listener reads it -- no timing hazard.
//        d. Otherwise, calls `.focus()` on the adjacent enabled
//           Trigger (which `installRovingFocus`'s own `focusin`
//           listener -- already attached to the very same `<px-menubar>`
//           by step (a)'s sibling install call -- picks up and uses to
//           update the roving tabindex bookkeeping, so a later Tab out
//           and back in still lands on the right trigger; see
//           lib/roving-focus.js's own header, "Arrow keys move focus
//           AND the tab stop together") and then `showPopover()`s that
//           trigger's own Content -- which, being a DIFFERENT menu's
//           Content than the one that's currently open, again benefits
//           from the same native light-dismiss auto-close described in
//           (1), so the old menu closes for free here too.
//
// Every other Menubar behaviour named in the analysis doc (typeahead,
// submenu hover/keyboard, checkbox/radio toggling, close-on-select,
// Escape-closes-one-level, Tab-swallowed, window-blur-closes-tree) is
// ALREADY provided by `installMenu` per Content, unchanged -- this file
// adds nothing for any of it, per the task's REUSE constraint.
//
// State lives entirely on DOM attributes (`data-state`, `aria-expanded`,
// `tabindex`) mutated by lib/menu.js, lib/roving-focus.js, and this
// file's own `beforetoggle`/`toggle` sync handlers -- never a parallel
// JS store (adr/0026 rule 4).

import { position, autoUpdate } from "lib/popper";
import { installMenu } from "lib/menu";
import { installRovingFocus } from "lib/roving-focus";

const TRIGGER_SELECTOR = '[role="menuitem"][aria-haspopup="menu"]';
const CONTENT_SELECTOR = ".px-menu-content";
const MENU_WRAPPER_SELECTOR = ":scope > .px-menubar-menu";

class PxMenubar extends HTMLElement {
  connectedCallback() {
    const root = this.querySelector('[role="menubar"]');
    if (!root) return;
    this._root = root;

    this._menus = Array.from(root.querySelectorAll(MENU_WRAPPER_SELECTOR))
      .map((wrapperEl) => ({
        wrapperEl,
        trigger: wrapperEl.querySelector(`:scope > ${TRIGGER_SELECTOR}`),
        contentEl: wrapperEl.querySelector(`:scope > ${CONTENT_SELECTOR}`),
        menu: null, // lazily installMenu()'d below, one per Content.
        stopAutoUpdate: null,
      }))
      .filter((m) => m.trigger && m.contentEl);
    if (this._menus.length === 0) return;

    this._menus.forEach((m) => {
      m.menu = installMenu(m.contentEl, { isSub: false });

      m.onTriggerKeyDown = (event) => this._onTriggerKeyDown(m, event);
      m.onTriggerPointerEnter = (event) => this._onTriggerPointerEnter(m, event);
      m.onBeforeToggle = (event) => this._onBeforeToggle(m, event);
      m.onToggle = (event) => this._onToggle(m, event);

      m.trigger.addEventListener("keydown", m.onTriggerKeyDown);
      m.trigger.addEventListener("pointerenter", m.onTriggerPointerEnter);
      m.contentEl.addEventListener("beforetoggle", m.onBeforeToggle);
      m.contentEl.addEventListener("toggle", m.onToggle);

      if (m.contentEl.getAttribute("data-state") === "open" && !m.contentEl.matches(":popover-open")) {
        m.contentEl.showPopover();
      }
    });

    // Top-level roving tabindex across the trigger row -- reused
    // verbatim (lib/roving-focus.js, unmodified), same usage shape as
    // components/toolbar.js's own <px-toolbar>. Menubar has no
    // orientation option (always horizontal, per the module header)
    // and defaults `loop: true` -- ArrowRight past the last trigger
    // wraps to the first, matching native OS menu-bar convention.
    this._stopRovingFocus = installRovingFocus(root, {
      itemSelector: TRIGGER_SELECTOR,
      orientation: "horizontal",
      loop: true,
    });

    this._onCrossMenuKeyDown = this._onCrossMenuKeyDown.bind(this);
    this.addEventListener("keydown", this._onCrossMenuKeyDown);
  }

  disconnectedCallback() {
    if (this._stopRovingFocus) this._stopRovingFocus();
    this.removeEventListener("keydown", this._onCrossMenuKeyDown);
    (this._menus || []).forEach((m) => {
      m.trigger.removeEventListener("keydown", m.onTriggerKeyDown);
      m.trigger.removeEventListener("pointerenter", m.onTriggerPointerEnter);
      m.contentEl.removeEventListener("beforetoggle", m.onBeforeToggle);
      m.contentEl.removeEventListener("toggle", m.onToggle);
      if (m.menu) m.menu.uninstall();
      this._stopPositioning(m);
    });
  }

  // -- Trigger: ArrowDown always OPENS (never toggles closed), same
  //    rationale/shape as components/dropdown_menu.js's own
  //    _onTriggerKeyDown -- native popovertarget only TOGGLES, so an
  //    already-open menu must not be re-closed by this. Enter/Space
  //    need no code at all: native <button> + popovertarget activation
  //    already toggles, for free. ------------------------------------

  _onTriggerKeyDown(m, event) {
    if (event.key !== "ArrowDown") return;
    event.preventDefault();
    if (!m.contentEl.matches(":popover-open")) m.contentEl.showPopover();
  }

  // -- Defining behaviour 1: open-on-hover-ONLY-WHEN-something-is-
  //    ALREADY-open. See this file's header for why a single
  //    showPopover() call is sufficient (native light-dismiss closes
  //    the previously-open sibling menu automatically). --------------

  _onTriggerPointerEnter(m, event) {
    if (event.pointerType !== "mouse") return;
    if (m.trigger.hasAttribute("data-disabled") || m.trigger.disabled) return;
    if (m.contentEl.matches(":popover-open")) return; // already this one
    const anotherOpen = this._menus.some(
      (other) => other !== m && other.contentEl.matches(":popover-open")
    );
    if (!anotherOpen) return; // click-only entry: hover alone never opens the FIRST menu
    m.trigger.focus(); // keeps roving-focus's tabindex bookkeeping in sync (see header)
    m.contentEl.showPopover();
  }

  // -- Defining behaviour 2: ArrowRight/ArrowLeft, from inside an open
  //    top-level Content, jump to the adjacent menubar menu -- unless
  //    lib/menu.js already claimed the key (defaultPrevented) for its
  //    own submenu-open/submenu-close handling. See this file's header
  //    for the full mechanism. -----------------------------------------

  _onCrossMenuKeyDown(event) {
    if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;

    const fromContent = event.target.closest ? event.target.closest(CONTENT_SELECTOR) : null;
    if (!fromContent) return; // not inside any menu Content -- roving-focus owns trigger-to-trigger nav

    const idx = this._menus.findIndex((m) => m.contentEl === fromContent);
    if (idx === -1) return; // originated inside a nested SUBmenu, not a top-level Content -- no-op here

    if (event.defaultPrevented) return; // lib/menu.js already handled it (subtrigger open / submenu close-back)

    const dir = event.key === "ArrowRight" ? 1 : -1;
    const total = this._menus.length;
    let nextIdx = idx;
    for (let steps = 0; steps < total; steps++) {
      nextIdx = (nextIdx + dir + total) % total;
      const candidate = this._menus[nextIdx];
      if (!candidate.trigger.disabled && !candidate.trigger.hasAttribute("data-disabled")) break;
    }
    if (nextIdx === idx) return; // only one enabled menu -- nothing to jump to

    event.preventDefault();
    const next = this._menus[nextIdx];
    next.trigger.focus();
    if (!next.contentEl.matches(":popover-open")) next.contentEl.showPopover();
  }

  // -- Per-Content state sync + positioning, same beforetoggle/toggle
  //    split components/dropdown_menu.js's own <px-dropdown-menu>
  //    already established. --------------------------------------------

  _onBeforeToggle(m, event) {
    const opening = event.newState === "open";
    const state = opening ? "open" : "closed";
    m.contentEl.setAttribute("data-state", state);
    m.trigger.setAttribute("aria-expanded", String(opening));
    m.trigger.setAttribute("data-state", state);
    // data-highlighted mirrors "this trigger's menu is the currently-
    // open one" (prolog/ui/menubar.pl's own header: never server-
    // rendered, entirely this element's job) -- native popover
    // light-dismiss guarantees at most one Content is ever open at a
    // time (see this file's header), so this simple set/remove on
    // open/close keeps exactly zero-or-one Trigger highlighted, never
    // more, with no extra bookkeeping needed.
    if (opening) {
      m.trigger.setAttribute("data-highlighted", "");
    } else {
      m.trigger.removeAttribute("data-highlighted");
      this._stopPositioning(m);
    }
  }

  _onToggle(m, event) {
    if (event.newState === "open") {
      this._startPositioning(m);
      // Every open path -- click-via-popovertarget, ArrowDown, hover-
      // switch, or a cross-menu arrow jump -- funnels through this one
      // native `toggle` event, so one call site covers auto-focusing
      // the first item for all of them (same shape as
      // components/dropdown_menu.js's own _onToggle).
      m.menu.focusFirst();
    }
  }

  _startPositioning(m) {
    this._stopPositioning(m);
    const options = this._readOptions(m.contentEl);
    m.stopAutoUpdate = autoUpdate(m.trigger, m.contentEl, () => {
      position(m.trigger, m.contentEl, options);
    });
  }

  _stopPositioning(m) {
    if (m.stopAutoUpdate) {
      m.stopAutoUpdate();
      m.stopAutoUpdate = null;
    }
  }

  _readOptions(contentEl) {
    const side = contentEl.getAttribute("data-side") || "bottom";
    const align = contentEl.getAttribute("data-align") || "start";
    const sideOffset = Number(contentEl.getAttribute("data-side-offset")) || 0;
    const alignOffset = Number(contentEl.getAttribute("data-align-offset")) || 0;
    return { side, align, sideOffset, alignOffset, flip: true, boundaryPadding: 8 };
  }
}

customElements.define("px-menubar", PxMenubar);
