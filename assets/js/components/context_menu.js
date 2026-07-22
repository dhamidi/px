// assets/js/components/context_menu.js -- <px-context-menu> (adr/0026):
// the irreducible interactive sliver of the Context Menu port
// (prolog/ui/context_menu.pl), and "lib/menu"'s second consumer after
// <px-dropdown-menu> (assets/js/components/dropdown_menu.js) -- read
// that file's header first, it documents the parts this element shares
// verbatim (installMenu wiring, beforetoggle/toggle-driven data-state
// sync, popper.js autoUpdate). Only the deltas are documented at
// length here: HOW Content opens (there is no popovertarget-equivalent
// for a native contextmenu/long-press gesture) and WHERE it opens
// (anchored to the pointer, not to Trigger).
//
// prolog/ui/context_menu.pl already renders a `<span>` Trigger
// (data-state="closed", PLUS data-disabled when disabled(true) -- see
// that module's header for why it carries no aria-haspopup/
// aria-expanded/aria-controls/popovertarget at all) and a native
// `popover="auto"` Content (role="menu", data-state="closed",
// data-side="right" data-align="start" data-side-offset="2") --
// WITHOUT this element ever loading, right-clicking (or long-pressing)
// Trigger opens NOTHING: only the browser's own native OS context menu
// appears, exactly as if this component were never mounted (a strictly
// narrower no-JS story than every sibling port -- documented in
// prolog/ui/context_menu.pl's own "Platform choice" section, a direct
// consequence of `contextmenu`/long-press having no click-equivalent
// platform primitive to hang a declarative open on).
//
// ---------------------------------------------------------------------
// VIRTUAL-POINT ANCHORING -- the actual substance of this element.
// ---------------------------------------------------------------------
//
// assets/js/lib/popper.js's `position(anchorEl, floatingEl, options)`
// calls exactly ONE method on `anchorEl`, ever:
// `anchorEl.getBoundingClientRect()` (verified by reading that file --
// no `.closest`, no `.contains`, no DOM-membership check anywhere in
// `position()`/`autoUpdate()`). That single-method duck-typed contract
// is satisfied by a plain JS object just as well as by a real Element
// -- exactly Radix's own upstream `VirtualElement` API
// (`react-popper`'s `virtualElement` prop), independently required
// here by the same constraint. `virtualAnchor(x, y)` below returns
// `{ getBoundingClientRect() }` returning a zero-size rect at the
// captured point -- chosen over the analysis doc's other documented
// option, "a synthesized 0x0 positioned DOM shim... an extra step the
// Dropdown Menu case doesn't need" -- specifically BECAUSE it needs no
// insertion/removal lifecycle, causes no extra paint, and can never
// itself become an accidental click/focus/hit-test target. Recreated
// fresh on every open (`_openAt`, below) -- never reused across opens
// -- so right-clicking (or long-pressing) a new spot always re-anchors
// to the new point, matching the analysis doc's own "recreated on
// every reopen" requirement. `autoUpdate`'s rAF/scroll/resize loop
// still runs while open (kept live purely for viewport-clamp
// correctness on resize -- the anchor point itself never moves once
// captured, since `clientX`/`clientY` are already viewport-relative,
// exactly matching Content's own `position: fixed` strategy).
//
// ---------------------------------------------------------------------
// OPENING: native contextmenu (mouse) + a best-effort long-press
// (touch/pen)
// ---------------------------------------------------------------------
//
//   - `contextmenu` on Trigger: `disabled` (data-disabled present) is
//     the documented escape hatch straight back to the analysis doc's
//     "explicit escape hatch back to the OS context menu" -- this
//     handler returns without calling preventDefault() at all when
//     disabled, letting the native menu through untouched. Otherwise:
//     preventDefault() (required in 2026 exactly as in 2020 -- there is
//     no platform replacement, per the analysis doc), then open at
//     `{clientX, clientY}`.
//   - `pointerdown` on Trigger, touch/pen only (`pointerType !==
//     "mouse"`): arms a 700ms timer (the analysis doc's own figure).
//     `pointermove` beyond a small tolerance, or `pointerup`/
//     `pointercancel`, cancels it -- "must be held stationary to
//     trigger." On fire, opens at the pointerdown's captured point.
//     Documented simplification (adr/0026 rule 2): this does NOT
//     additionally suppress native text-selection/scrolling during the
//     hold the way upstream Radix's own long-press guard does -- cheap
//     per this component's own task brief, not a full gesture-guard
//     port.
//   - `_openAt(x, y)`: builds a fresh virtual anchor at the point, then
//     either `showPopover()`s Content (first open) or, if Content is
//     ALREADY open (right-clicking a new spot while a context menu is
//     already showing), just repositions it in place at the new point
//     without a hide/show cycle -- avoids an unnecessary close/reopen
//     flicker for what upstream treats as "re-anchor," not "reopen."
//
// ---------------------------------------------------------------------
// Everything else -- installing "lib/menu" onto Content once at
// connect time, auto-focusing the first item on open (mirroring
// <px-dropdown-menu>'s own choice -- keeps this component keyboard-
// operable immediately after a pointer-driven open), and mirroring
// data-state off the native beforetoggle/toggle events -- is the exact
// same shape as <px-dropdown-menu>; see that file's header for the
// full rationale, not repeated here.
//
// Escape and outside-click dismissal need no code here: Content is
// `popover="auto"` (prolog/ui/_menu.pl's `menu_content/2`, via
// prolog/ui/context_menu.pl's `context_menu_content/2`), so the
// browser's own light-dismiss algorithm handles both.
//
// State lives entirely on the Trigger's and Content's own DOM
// attributes -- never a parallel JS store (adr/0026 rule 4).

import { position, autoUpdate } from "lib/popper";
import { installMenu } from "lib/menu";

const TRIGGER_SELECTOR = ".px-context-menu-trigger";
const CONTENT_SELECTOR = ".px-menu-content";
const LONG_PRESS_MS = 700;
const LONG_PRESS_MOVE_TOLERANCE = 10;

// A plain object satisfying assets/js/lib/popper.js's entire anchorEl
// contract (one method: getBoundingClientRect()) -- see the module
// header's "VIRTUAL-POINT ANCHORING" section.
function virtualAnchor(x, y) {
  return {
    getBoundingClientRect() {
      return { x, y, top: y, left: x, right: x, bottom: y, width: 0, height: 0 };
    },
  };
}

class PxContextMenu extends HTMLElement {
  connectedCallback() {
    this._trigger = this.querySelector(TRIGGER_SELECTOR);
    this._content = this.querySelector(CONTENT_SELECTOR);
    if (!this._trigger || !this._content) return;

    this._anchor = virtualAnchor(0, 0);
    this._stopAutoUpdate = null;
    this._longPressTimer = null;
    this._longPressStart = null;
    this._menu = installMenu(this._content, { isSub: false });

    this._onContextMenu = this._onContextMenu.bind(this);
    this._onPointerDown = this._onPointerDown.bind(this);
    this._onPointerMove = this._onPointerMove.bind(this);
    this._onPointerEnd = this._onPointerEnd.bind(this);
    this._onBeforeToggle = this._onBeforeToggle.bind(this);
    this._onToggle = this._onToggle.bind(this);

    this._trigger.addEventListener("contextmenu", this._onContextMenu);
    this._trigger.addEventListener("pointerdown", this._onPointerDown);
    this._trigger.addEventListener("pointermove", this._onPointerMove);
    this._trigger.addEventListener("pointerup", this._onPointerEnd);
    this._trigger.addEventListener("pointercancel", this._onPointerEnd);
    this._content.addEventListener("beforetoggle", this._onBeforeToggle);
    this._content.addEventListener("toggle", this._onToggle);

    if (this._content.getAttribute("data-state") === "open" && !this._content.matches(":popover-open")) {
      this._content.showPopover();
    }
  }

  disconnectedCallback() {
    this._clearLongPress();
    if (this._trigger) {
      this._trigger.removeEventListener("contextmenu", this._onContextMenu);
      this._trigger.removeEventListener("pointerdown", this._onPointerDown);
      this._trigger.removeEventListener("pointermove", this._onPointerMove);
      this._trigger.removeEventListener("pointerup", this._onPointerEnd);
      this._trigger.removeEventListener("pointercancel", this._onPointerEnd);
    }
    if (this._content) {
      this._content.removeEventListener("beforetoggle", this._onBeforeToggle);
      this._content.removeEventListener("toggle", this._onToggle);
    }
    if (this._menu) this._menu.uninstall();
    this._stopPositioning();
  }

  _isDisabled() {
    return this._trigger.hasAttribute("data-disabled");
  }

  // -- Mouse: native contextmenu -----------------------------------------

  _onContextMenu(event) {
    if (this._isDisabled()) return; // documented escape hatch: native OS menu untouched.
    event.preventDefault();
    this._openAt(event.clientX, event.clientY);
  }

  // -- Touch/pen: long-press (best-effort, see module header) ------------

  _onPointerDown(event) {
    if (event.pointerType === "mouse" || this._isDisabled()) return;
    this._clearLongPress();
    this._longPressStart = { x: event.clientX, y: event.clientY };
    this._longPressTimer = setTimeout(() => {
      this._longPressTimer = null;
      this._openAt(this._longPressStart.x, this._longPressStart.y);
    }, LONG_PRESS_MS);
  }

  _onPointerMove(event) {
    if (!this._longPressTimer || !this._longPressStart) return;
    const dx = event.clientX - this._longPressStart.x;
    const dy = event.clientY - this._longPressStart.y;
    if (Math.hypot(dx, dy) > LONG_PRESS_MOVE_TOLERANCE) this._clearLongPress();
  }

  _onPointerEnd() {
    this._clearLongPress();
  }

  _clearLongPress() {
    if (this._longPressTimer) {
      clearTimeout(this._longPressTimer);
      this._longPressTimer = null;
    }
    this._longPressStart = null;
  }

  // -- Open/reposition at a point ------------------------------------------

  _openAt(x, y) {
    this._anchor = virtualAnchor(x, y);
    if (this._content.matches(":popover-open")) {
      // Already open -- re-anchor in place (right-clicking a new spot
      // while a context menu is showing), no hide/show flicker.
      this._position();
      return;
    }
    this._content.showPopover();
  }

  // -- Native popover state <-> data-state/positioning sync --------------
  // (identical shape to <px-dropdown-menu>'s own split.)

  _onBeforeToggle(event) {
    const opening = event.newState === "open";
    this._syncState(opening);
    if (!opening) this._stopPositioning();
  }

  _onToggle(event) {
    if (event.newState === "open") {
      this._startPositioning();
      this._menu.focusFirst();
    }
  }

  _syncState(open) {
    const state = open ? "open" : "closed";
    this._content.setAttribute("data-state", state);
    this._trigger.setAttribute("data-state", state);
  }

  // -- Positioning (lib/popper.js, anchored to the virtual point) --------

  _position() {
    position(this._anchor, this._content, this._readOptions());
  }

  _startPositioning() {
    this._stopPositioning();
    this._stopAutoUpdate = autoUpdate(this._anchor, this._content, () => this._position());
  }

  _stopPositioning() {
    if (this._stopAutoUpdate) {
      this._stopAutoUpdate();
      this._stopAutoUpdate = null;
    }
  }

  _readOptions() {
    const side = this._content.getAttribute("data-side") || "right";
    const align = this._content.getAttribute("data-align") || "start";
    const sideOffset = Number(this._content.getAttribute("data-side-offset")) || 0;
    const alignOffset = Number(this._content.getAttribute("data-align-offset")) || 0;
    return { side, align, sideOffset, alignOffset, flip: true, boundaryPadding: 8 };
  }
}

customElements.define("px-context-menu", PxContextMenu);
