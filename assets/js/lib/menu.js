// assets/js/lib/menu.js -- shared Menu engine (adr/0026 rule 5). Plain
// ES module, no build step -- served through the importmap under the
// bare specifier "lib/menu" (adr/0025, the same automatic
// "js/lib/menu.js" -> "lib/menu" mapping px_assets.pl's
// javascript_importmap_tags/1 gives every file under assets/js/).
//
// Ports the CLIENT half of Radix's internal `menu` package (docs/
// radix-port-analysis.md, "Menu (shared machinery, not a public
// component)" entry -- the SERVER half, the anatomy/ARIA/data
// contract, lives in prolog/ui/_menu.pl; read that module's header
// first for the DOM shape this file assumes, in particular the
// "every Content level is `popover=auto`, DOM-nested inside its
// parent's Content" decision this file leans on throughout).
//
// ---------------------------------------------------------------------
// THE CONTRACT (read this before importing from a component element):
// ---------------------------------------------------------------------
//
//   import { installMenu } from "lib/menu";
//
//   const menu = installMenu(contentEl, {
//     isSub: false,      // true when contentEl is a menu_sub_content --
//                          // gates ArrowLeft-closes-back (a root Content
//                          // has nowhere to "back" to) and refocus-on-
//                          // close. Default false. Wrappers (Dropdown
//                          // Menu, and later Context Menu/Menubar) never
//                          // pass this -- it is set internally when this
//                          // module opens a SUBMENU recursively.
//     trigger: null,      // the element to refocus when contentEl closes
//                          // (only meaningful with isSub: true -- root
//                          // Content's trigger-refocus is the WRAPPER's
//                          // job, e.g. <px-dropdown-menu>'s own
//                          // beforetoggle handler, not this module's).
//   });
//
//   menu.focusFirst();   // highlight + focus this level's first enabled
//                          // item -- call after showing contentEl
//                          // (dropdown_menu.js's own "trigger click/
//                          // ArrowDown opens + focuses first item" job).
//   menu.focusLast();    // same, last enabled item (End/PageDown entry).
//   menu.uninstall();    // remove this level's own listeners. Submenu
//                          // levels opened under it are NOT recursively
//                          // uninstalled (same documented scope limit as
//                          // lib/roving-focus.js's MutationObserver: a
//                          // typical dropdown's lifetime doesn't need
//                          // it, and the whole subtree is GC'd once
//                          // contentEl itself is removed from the DOM).
//
// installMenu is called ONCE PER OPEN CONTENT LEVEL -- once by the
// wrapper for the root Content, and once MORE, RECURSIVELY, by this
// module itself the first time each menu_sub's SubContent opens (lazy,
// on first open only, guarded so re-opening never double-installs).
// A wrapper never touches a submenu's Content directly; everything
// submenu-shaped (hover-delay open/close, the pointer grace bridge,
// ArrowRight/ArrowLeft, positioning) is entirely this module's job,
// invisible to the wrapper -- exactly the analysis doc's own "port
// implication": "one shared vanilla-JS module... parameterized by
// trigger type... with dropdown-menu/context-menu/menubar each
// supplying only trigger-opening semantics on top."
//
// ---------------------------------------------------------------------
// WHY NOT lib/roving-focus.js (a documented deviation, adr/0026 rule 2)
// ---------------------------------------------------------------------
//
// roving-focus.js's `itemSelector` is matched TWO ways -- a plain
// `container.querySelectorAll` for the full collection, and
// `event.target.closest(itemSelector)` for event delegation -- and a
// selector that scopes correctly for one does not scope correctly for
// the other once items live at MULTIPLE NESTED DEPTHS (a submenu's
// items are genuine DOM descendants of the parent Content, per
// _menu.pl's own "platform choice"): a `:scope`-based selector means
// something different depending on which element `:scope` is resolved
// against (the container for querySelectorAll, the event target itself
// for closest), so there is no single selector string that reuses that
// module's public API correctly here. Menu's own item collection is
// instead computed directly (`levelItems/0` below): every
// `[role=menuitem*]` descendant of contentEl, FILTERED to keep only
// the ones whose nearest `.px-menu-content` ancestor (`element.closest
// ('.px-menu-content')`) IS contentEl itself -- correct at any nesting
// depth, using plain DOM traversal, no selector-string gymnastics. The
// concepts roving-focus.js established (single tab stop, focus-follows-
// arrows, loop, Home/End, disabled-skipped) are all still ported below,
// just against this module's own collection function instead of that
// one's. `lib/popper.js`'s `position`/`autoUpdate` pair, by contrast,
// has no such scoping conflict and IS reused verbatim for submenu
// placement (side="right" align="start" by default, per _menu.pl's
// own `menu_sub_content/2` defaults).
//
// ---------------------------------------------------------------------
// TYPEAHEAD
// ---------------------------------------------------------------------
//
// Printable, non-modified single-character keydowns accumulate into a
// buffer, reset after TYPEAHEAD_RESET_MS (1000ms, the analysis doc's
// own figure) of silence. Radix's own "mashing one character cycles
// items" normalization is ported: a buffer that is the SAME character
// repeated collapses to a single character before matching, so typing
// "b" three times in a row searches for "b" three times (cycling
// through every b-item) rather than for the literal string "bbb". The
// candidate list is every enabled item at this level, searched
// starting just AFTER the currently highlighted item and wrapping --
// so repeated presses advance through matches instead of always
// re-landing on the first one. Matching is a plain `startsWith` against
// each item's `data-text-value` (an explicit override, e.g. for an
// icon-only item whose visible text isn't its intended search label)
// or, absent that, its own text, trimmed and lower-cased -- EXCLUDING
// a CheckboxItem/RadioItem's own always-rendered `.px-menu-item-
// indicator` child (its "✓"/"●" glyph precedes the label in DOM order;
// including it would make e.g. "Show hidden files" read as "✓show
// hidden files" and never match a typed "s").
//
// ---------------------------------------------------------------------
// SUBMENUS: hover-delay open/close + the pointer grace bridge
// ---------------------------------------------------------------------
//
// Ported per the analysis doc's own explicit steer: "This is pure,
// portable geometry... [but] SIMPLIFIED per the hover_card precedent"
// (assets/js/components/hover_card.js) rather than Radix's full
// convex-hull point-in-polygon cone -- the same trade this codebase
// already made once for Tooltip/HoverCard's own grace areas. Concretely,
// per SubTrigger/SubContent pair:
//
//   - SubTrigger `pointerenter` (mouse only): cancels any pending close,
//     and -- unless the submenu is already open or an open timer is
//     already pending -- starts a 100ms open timer (the analysis doc's
//     own figure: "mouse-only 100ms timer to open a submenu on
//     pointer-move over its trigger").
//   - SubTrigger `pointerleave` (mouse only): cancels a pending OPEN
//     timer outright; if already open, starts a 300ms close timer
//     (hover_card.js's own closeDelay figure, reused here for the same
//     "give the user time to travel diagonally into the panel" job).
//   - SubContent `pointerenter`: cancels a pending close timer -- the
//     ENTIRE grace mechanism, identical in shape to hover_card.js's own
//     "reaching Content before closeDelay elapses cancels the close,
//     regardless of travel path" -- not a geometric cone, a tolerance
//     window, exactly the simplification the task brief asks for.
//   - SubContent `pointerleave`: starts its own close timer.
//   - ArrowRight on a highlighted SubTrigger, or Enter/Space/click on
//     one, opens IMMEDIATELY (both timers cleared) and focuses the
//     submenu's first enabled item -- keyboard opening is never
//     delayed, matching the analysis doc's "keyboard... opens
//     immediately."
//   - ArrowLeft while `isSub: true` closes THIS level immediately
//     (`hidePopover()`) -- Escape needs no code at all here: every
//     Content level is a native `popover=auto` element, and the
//     browser's own light-dismiss closes exactly the topmost one per
//     Escape press, which IS "close back one level" for free (see
//     _menu.pl's header, point 1).
//   - Moving the KEYBOARD highlight away from an open submenu's trigger
//     (Arrow/Home/End/typeahead landing on a different item) closes
//     that submenu IMMEDIATELY, no grace delay -- matches real menu
//     UX (keyboard nav is decisive) and is intentionally NOT triggered
//     by the pointer-hover highlight-follow path (`pointermove`),
//     which relies purely on the timers above so a diagonal mouse path
//     across a sibling row doesn't kill the submenu it's travelling
//     toward.
//
// ---------------------------------------------------------------------
// CLOSE-ON-SELECT ("closes the entire menu tree, not just the current
// submenu level")
// ---------------------------------------------------------------------
//
// See prolog/ui/_menu.pl's header for the exact default-flip rationale
// (plain Items close unless `data-close-on-select="false"`; Checkbox/
// Radio Items stay open unless `data-close-on-select="true"`) -- this
// module only reads the already-resolved attribute (`shouldClose/1`)
// and, when true, walks from contentEl UP through every ancestor
// `.px-menu-content` (`element.parentElement.closest(...)`, repeated)
// calling `hidePopover()` on each -- correct, and simple, precisely
// BECAUSE every level is a real DOM ancestor of the one below it (no
// portal indirection to reconcile against).
//
// ---------------------------------------------------------------------
// OTHER PORTED EDGE CASES (analysis doc's own "worth carrying forward"
// list)
// ---------------------------------------------------------------------
//
//   - Window blur closes the whole tree: only the ROOT install
//     (`isSub: false`) adds a `window` `blur` listener, calling
//     `hidePopover()` on its own contentEl -- the cascade to every open
//     descendant submenu happens automatically via each level's own
//     `beforetoggle` handler (below), not a second blur listener per
//     level.
//   - Every open Content level's `beforetoggle` handler, on closing
//     for ANY reason (this call, native Escape, native outside-click,
//     a sibling window-blur cascade, ...), immediately `hidePopover()`s
//     every currently-open DESCENDANT `.px-menu-content` and clears
//     every `data-highlighted` in its own subtree -- so a parent level
//     closing never leaves an orphaned open submenu behind.
//   - `Tab` is fully swallowed (`preventDefault()`) while focus is
//     inside a menu -- menus are select-or-Escape-only, never
//     Tab-navigable, matching the analysis doc's own note.
//   - The `event.target === event.currentTarget`-equivalent guard: this
//     module's `keydown` handler only acts when `event.target` is
//     either contentEl itself or one of `levelItems()` -- so a
//     focusable control a caller nests INSIDE an item's own markup
//     (not part of this port's demo, but not precluded by the
//     contract either) never has its own keys swallowed.
//
// State lives entirely on DOM attributes this module reads and writes
// (`data-state`, `data-highlighted`, `aria-checked`, `aria-expanded`)
// -- never a parallel JS store (adr/0026 rule 4) -- with the sole,
// necessary exception of the open/close delay timer handles themselves
// (transient by nature, same accepted exception hover_card.js's own
// header documents).

import { position, autoUpdate } from "lib/popper";

const ITEM_SELECTOR = '[role="menuitem"], [role="menuitemcheckbox"], [role="menuitemradio"]';
const CONTENT_SELECTOR = ".px-menu-content";
const SUB_SELECTOR = ".px-menu-sub";
const TYPEAHEAD_RESET_MS = 1000;
const SUB_OPEN_DELAY_MS = 100;
const SUB_CLOSE_DELAY_MS = 300;

export function installMenu(contentEl, options = {}) {
  const { isSub = false, trigger = null } = options;

  const subControllers = new Map(); // subTrigger -> { open(focusFirst), contentEl }
  let typeaheadBuffer = "";
  let typeaheadLastAt = 0;

  // -- Item collection (this level only -- see the module header's
  //    "WHY NOT lib/roving-focus.js" section for why this is hand-
  //    rolled rather than that module's own collection). -----------

  function levelItems() {
    return Array.from(contentEl.querySelectorAll(ITEM_SELECTOR)).filter(
      (el) => el.closest(CONTENT_SELECTOR) === contentEl
    );
  }

  function isDisabled(item) {
    return item.hasAttribute("data-disabled") || item.getAttribute("aria-disabled") === "true";
  }

  function enabledItems() {
    return levelItems().filter((item) => !isDisabled(item));
  }

  function currentItem() {
    const active = document.activeElement;
    return active && levelItems().includes(active) ? active : null;
  }

  function textValue(item) {
    const explicit = item.getAttribute("data-text-value");
    if (explicit) return explicit.trim().toLowerCase();
    // Plain `textContent` would include the CheckboxItem/RadioItem
    // Indicator's own glyph ("✓"/"●", always rendered -- see _menu.pl's
    // header) PREPENDED to the label, breaking startsWith matching on
    // the label itself (e.g. "Show hidden files" would read as
    // "✓show hidden files", never matching a typed "s"). Concatenate
    // every direct child node's text EXCEPT the Indicator's.
    let text = "";
    item.childNodes.forEach((node) => {
      if (node.nodeType === Node.ELEMENT_NODE && node.classList.contains("px-menu-item-indicator")) return;
      text += node.textContent || "";
    });
    return text.trim().toLowerCase();
  }

  // -- Highlight (== focus, Radix's own roving model: "Arrow keys move
  //    focus AND the tab stop together", ported here as "highlight IS
  //    focus", one non-tab-stop concept, not two). -------------------

  function highlight(item, { focus = true } = {}) {
    if (!item) return;
    levelItems().forEach((el) => el.removeAttribute("data-highlighted"));
    item.setAttribute("data-highlighted", "");
    if (focus) item.focus();
  }

  function closeOpenSiblingSubmenus(exceptItem) {
    subControllers.forEach((controller, subTrigger) => {
      if (subTrigger === exceptItem) return;
      if (controller.contentEl.matches(":popover-open")) controller.contentEl.hidePopover();
    });
  }

  function highlightKeyboard(item) {
    highlight(item);
    closeOpenSiblingSubmenus(item);
  }

  function highlightFirst() {
    const items = enabledItems();
    if (items.length) highlightKeyboard(items[0]);
  }

  function highlightLast() {
    const items = enabledItems();
    if (items.length) highlightKeyboard(items[items.length - 1]);
  }

  function moveHighlight(delta) {
    const items = enabledItems();
    if (items.length === 0) return;
    const current = currentItem();
    let idx = current ? items.indexOf(current) : -1;
    idx = idx === -1 ? (delta > 0 ? 0 : items.length - 1) : (idx + delta + items.length) % items.length;
    highlightKeyboard(items[idx]);
  }

  // -- Typeahead -------------------------------------------------------

  function onTypeahead(char) {
    const now = Date.now();
    if (now - typeaheadLastAt > TYPEAHEAD_RESET_MS) typeaheadBuffer = "";
    typeaheadLastAt = now;
    typeaheadBuffer += char.toLowerCase();

    const items = enabledItems();
    if (items.length === 0) return;

    let search = typeaheadBuffer;
    const isSingleCharRepeat = search.length > 1 && [...search].every((c) => c === search[0]);
    if (isSingleCharRepeat) search = search[0];

    const current = currentItem();
    const currentIdx = current ? items.indexOf(current) : -1;
    const ordered = items.slice(currentIdx + 1).concat(items.slice(0, currentIdx + 1));
    const match = ordered.find((item) => textValue(item).startsWith(search));
    if (match) highlightKeyboard(match);
  }

  // -- Activation (Enter/Space/click -> "click the item") --------------

  function shouldClose(item) {
    const override = item.getAttribute("data-close-on-select");
    if (override === "true") return true;
    if (override === "false") return false;
    return item.getAttribute("role") === "menuitem";
  }

  function setChecked(item, checked) {
    item.setAttribute("aria-checked", String(checked));
    item.setAttribute("data-state", checked ? "checked" : "unchecked");
    const indicator = item.querySelector(":scope > .px-menu-item-indicator");
    if (indicator) indicator.setAttribute("data-state", checked ? "checked" : "unchecked");
  }

  function selectRadio(item) {
    const group = item.closest('[role="group"]') || contentEl;
    group.querySelectorAll('[role="menuitemradio"]').forEach((el) => {
      if (el.closest(CONTENT_SELECTOR) !== contentEl) return; // this level only
      setChecked(el, el === item);
    });
  }

  function closeTree() {
    let level = contentEl;
    while (level) {
      if (level.matches(":popover-open")) level.hidePopover();
      const parent = level.parentElement;
      level = parent ? parent.closest(CONTENT_SELECTOR) : null;
    }
  }

  function activate(item) {
    if (!item || isDisabled(item)) return;
    if (item.getAttribute("aria-haspopup") === "menu") {
      const controller = subControllers.get(item);
      if (controller) controller.open(true);
      return;
    }
    const role = item.getAttribute("role");
    if (role === "menuitemcheckbox") {
      setChecked(item, item.getAttribute("aria-checked") !== "true");
    } else if (role === "menuitemradio") {
      selectRadio(item);
    }
    if (shouldClose(item)) closeTree();
  }

  // -- Submenus ----------------------------------------------------------

  function readPositionOptions(el) {
    const side = el.getAttribute("data-side") || "right";
    const align = el.getAttribute("data-align") || "start";
    const sideOffset = Number(el.getAttribute("data-side-offset")) || 0;
    const alignOffset = Number(el.getAttribute("data-align-offset")) || 0;
    return { side, align, sideOffset, alignOffset, flip: true, boundaryPadding: 8 };
  }

  function wireSub(subEl) {
    const subTrigger = subEl.querySelector(':scope > [role="menuitem"][aria-haspopup="menu"]');
    const subContent = subEl.querySelector(":scope > .px-menu-content");
    if (!subTrigger || !subContent) return;

    let openTimer = null;
    let closeTimer = null;
    let installed = false;
    let stopAutoUpdate = null;

    function clearOpenTimer() {
      if (openTimer) {
        clearTimeout(openTimer);
        openTimer = null;
      }
    }
    function clearCloseTimer() {
      if (closeTimer) {
        clearTimeout(closeTimer);
        closeTimer = null;
      }
    }

    function ensureInstalled() {
      if (installed) return;
      installed = true;
      installMenu(subContent, { isSub: true, trigger: subTrigger });
    }

    function openNow(focusFirstItem) {
      clearOpenTimer();
      clearCloseTimer();
      ensureInstalled();
      if (!subContent.matches(":popover-open")) subContent.showPopover();
      if (focusFirstItem) {
        queueMicrotask(() => {
          const first = Array.from(subContent.querySelectorAll(ITEM_SELECTOR)).filter(
            (el) => el.closest(CONTENT_SELECTOR) === subContent && !isDisabled(el)
          )[0];
          if (first) {
            subContent.querySelectorAll("[data-highlighted]").forEach((el) => el.removeAttribute("data-highlighted"));
            first.setAttribute("data-highlighted", "");
            first.focus();
          }
        });
      }
    }

    function scheduleClose() {
      clearOpenTimer();
      if (closeTimer) return;
      closeTimer = setTimeout(() => {
        closeTimer = null;
        if (subContent.matches(":popover-open")) subContent.hidePopover();
      }, SUB_CLOSE_DELAY_MS);
    }

    subTrigger.addEventListener("pointerenter", (event) => {
      if (event.pointerType !== "mouse" || isDisabled(subTrigger)) return;
      clearCloseTimer();
      if (subContent.matches(":popover-open") || openTimer) return;
      openTimer = setTimeout(() => {
        openTimer = null;
        openNow(false);
      }, SUB_OPEN_DELAY_MS);
    });
    subTrigger.addEventListener("pointerleave", (event) => {
      if (event.pointerType !== "mouse") return;
      clearOpenTimer();
      if (subContent.matches(":popover-open")) scheduleClose();
    });
    subContent.addEventListener("pointerenter", () => clearCloseTimer());
    subContent.addEventListener("pointerleave", () => {
      if (subContent.matches(":popover-open")) scheduleClose();
    });

    subContent.addEventListener("beforetoggle", (event) => {
      const opening = event.newState === "open";
      subContent.setAttribute("data-state", opening ? "open" : "closed");
      subEl.setAttribute("data-state", opening ? "open" : "closed");
      subTrigger.setAttribute("data-state", opening ? "open" : "closed");
      subTrigger.setAttribute("aria-expanded", String(opening));
      if (!opening) {
        clearOpenTimer();
        clearCloseTimer();
        if (stopAutoUpdate) {
          stopAutoUpdate();
          stopAutoUpdate = null;
        }
        subContent.querySelectorAll(`${CONTENT_SELECTOR}:popover-open`).forEach((el) => el.hidePopover());
        subContent.querySelectorAll("[data-highlighted]").forEach((el) => el.removeAttribute("data-highlighted"));
        const active = document.activeElement;
        if (!active || subContent.contains(active) || active === document.body) {
          subTrigger.focus();
        }
      }
    });
    subContent.addEventListener("toggle", (event) => {
      if (event.newState === "open") {
        stopAutoUpdate = autoUpdate(subTrigger, subContent, () => {
          position(subTrigger, subContent, readPositionOptions(subContent));
        });
      }
    });

    subControllers.set(subTrigger, { open: openNow, contentEl: subContent });
  }

  contentEl.querySelectorAll(SUB_SELECTOR).forEach((subEl) => {
    const parentContent = subEl.parentElement ? subEl.parentElement.closest(CONTENT_SELECTOR) : null;
    if (parentContent === contentEl) wireSub(subEl);
  });

  // -- Pointer highlight-follow (grace-tolerant -- see module header) -

  function onPointerMove(event) {
    const item = event.target.closest(ITEM_SELECTOR);
    if (!item || item.closest(CONTENT_SELECTOR) !== contentEl || isDisabled(item)) return;
    if (!item.hasAttribute("data-highlighted")) highlight(item);
  }

  function onClick(event) {
    const item = event.target.closest(ITEM_SELECTOR);
    if (!item || item.closest(CONTENT_SELECTOR) !== contentEl) return;
    if (isDisabled(item)) {
      event.preventDefault();
      return;
    }
    highlight(item, { focus: false });
    activate(item);
  }

  function onKeyDown(event) {
    const target = event.target;
    const isOwnTarget = target === contentEl || levelItems().includes(target);
    if (!isOwnTarget) return;

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        moveHighlight(1);
        break;
      case "ArrowUp":
        event.preventDefault();
        moveHighlight(-1);
        break;
      case "Home":
      case "PageUp":
        event.preventDefault();
        highlightFirst();
        break;
      case "End":
      case "PageDown":
        event.preventDefault();
        highlightLast();
        break;
      case "ArrowRight": {
        const item = currentItem();
        if (item && item.getAttribute("aria-haspopup") === "menu" && !isDisabled(item)) {
          event.preventDefault();
          const controller = subControllers.get(item);
          if (controller) controller.open(true);
        }
        break;
      }
      case "ArrowLeft":
        if (isSub) {
          event.preventDefault();
          contentEl.hidePopover();
        }
        break;
      case "Tab":
        event.preventDefault();
        break;
      case "Enter":
      case " ":
        event.preventDefault();
        activate(currentItem());
        break;
      default:
        if (event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
          onTypeahead(event.key);
        }
    }
  }

  contentEl.addEventListener("pointermove", onPointerMove);
  contentEl.addEventListener("click", onClick);
  contentEl.addEventListener("keydown", onKeyDown);

  // Every level cascades a close to its own open descendants, whatever
  // closed it (closeTree() above, native Escape/outside-dismiss, or a
  // root-level window-blur cascade) -- see the module header.
  contentEl.addEventListener("beforetoggle", (event) => {
    if (event.newState === "closed") {
      contentEl.querySelectorAll(`${CONTENT_SELECTOR}:popover-open`).forEach((el) => el.hidePopover());
      contentEl.querySelectorAll("[data-highlighted]").forEach((el) => el.removeAttribute("data-highlighted"));
    }
  });

  let onBlur = null;
  if (!isSub) {
    onBlur = () => {
      if (contentEl.matches(":popover-open")) contentEl.hidePopover();
    };
    window.addEventListener("blur", onBlur);
  }

  return {
    focusFirst: highlightFirst,
    focusLast: highlightLast,
    uninstall() {
      contentEl.removeEventListener("pointermove", onPointerMove);
      contentEl.removeEventListener("click", onClick);
      contentEl.removeEventListener("keydown", onKeyDown);
      if (onBlur) window.removeEventListener("blur", onBlur);
    },
  };
}
