// assets/js/lib/roving-focus.js -- shared roving-tabindex machinery
// (adr/0026 rule 5). Plain ES module, no build step -- served through
// the importmap under the bare specifier "lib/roving-focus" (adr/0025,
// the same automatic "js/lib/roving-focus.js" -> "lib/roving-focus"
// mapping px_assets.pl's javascript_importmap_tags/1 already gives
// every file under assets/js/).
//
// Ports the CONCEPT of Radix's react-roving-focus (docs/radix-port-
// analysis.md, "Shared machinery" -> "roving-focus" entry): "single-
// tab-stop keyboard navigation: only one item in a group has
// tabIndex=0; Arrow keys (orientation- and RTL-aware...) move both
// focus and the tab-stop, Home/End/PageUp/PageDown jump to first/
// last, optional loop... No native replacement whatsoever." None of
// React's collection/context/ref machinery carries over (there is no
// hydration-matching or ref-composition problem in vanilla JS); what
// carries over is the state machine: exactly one item is ever a Tab
// stop, arrow keys move it, and the platform gives zero of this for
// free on a group of plain buttons/links/divs.
//
// ---------------------------------------------------------------------
// THE CONTRACT (read this before importing from a component element):
// ---------------------------------------------------------------------
//
//   import { installRovingFocus } from "lib/roving-focus";
//
//   const uninstall = installRovingFocus(container, {
//     itemSelector: ".px-toggle-group-item",  // CSS selector, relative
//                                              // to `container`, matching
//                                              // every candidate item.
//                                              // Default: "[data-roving-item]".
//     orientation: "horizontal",              // "horizontal" | "vertical" | "both".
//                                              // horizontal: ArrowLeft/Right move.
//                                              // vertical:   ArrowUp/Down move.
//                                              // both:       all four arrows move
//                                              //             (single 1-D sequence --
//                                              //             for grid/menubar-shaped
//                                              //             consumers later).
//                                              // Default: "horizontal".
//     loop: false,                            // wrap at the first/last item instead
//                                              // of stopping there. Default: false.
//     dir: null,                              // "ltr" | "rtl", or null to read
//                                              // `getComputedStyle(container).direction`
//                                              // at every keydown (so a later dir
//                                              // change, e.g. an app-level language
//                                              // switch, is honoured without
//                                              // reinstalling). Only affects
//                                              // ArrowLeft/ArrowRight in "horizontal"/
//                                              // "both" orientation, same as Radix's
//                                              // own direction-flipped key->intent map.
//   });
//
//   // later, e.g. in disconnectedCallback():
//   uninstall();
//
// Behaviour installRovingFocus manages, entirely by mutating `tabindex`
// and calling `.focus()` on the matched items -- NEVER a parallel JS
// store (adr/0026 rule 4): every bit of state this module cares about
// (which item is the current tab stop) IS the `tabindex="0"` attribute
// on that item, so a later server re-render/Turbo morph that changes
// which item has `tabindex="0"` is picked up automatically, no
// reconciliation needed.
//
//   - One-tabbable-item-at-a-time: on install, and after every mutation
//     of the item collection, exactly one non-disabled item has
//     `tabindex="0"` and every other item has `tabindex="-1"`. The
//     initial choice is whichever item the SERVER already marked
//     `tabindex="0"` (so a component's Prolog template can pick the
//     semantically "active" item -- e.g. Toggle Group's pressed item --
//     and this module just honours it); if none is marked, or the
//     marked one is disabled, the first non-disabled item wins.
//   - Arrow keys move focus AND the tab stop together (Radix's "focus-
//     follows-arrows"): pressing an arrow key while focus is inside an
//     item calls `.focus()` on the target item, which updates
//     `tabindex` via the same `focusin` handler that also handles
//     plain Tab/click-driven focus moves -- so keyboard nav and
//     pointer/Tab nav can never disagree about which item is current.
//   - Home/PageUp jump to the first non-disabled item; End/PageDown
//     jump to the last (matches the analysis doc's own key list for
//     the Toggle Group entry, which names all four).
//   - `loop`: at the first/last item, Arrow-key movement wraps around
//     instead of stopping (Radix's own `loop` prop, default `false`).
//   - Disabled items (`.disabled` property true, `aria-disabled="true"`,
//     or a `data-disabled` attribute present -- the three conventions
//     already used across this library, e.g. ui/toggle.pl's
//     `data-disabled=""`) are skipped entirely: never a tab stop, never
//     an arrow-key landing target.
//   - "Remembering the last focused item when tabbing back in" needs NO
//     separate memory here: because the roving item's own `tabindex="0"`
//     attribute IS that memory (never reset by this module once set),
//     tabbing out and back in naturally lands on whichever item was
//     current -- the browser's own Tab-stop behaviour does the
//     remembering, for free, as long as nothing else resets the
//     attribute in between.
//   - A `MutationObserver` (childList + subtree + the three disabled-
//     signalling attributes) keeps the "exactly one tab stop" invariant
//     true as items are added/removed/disabled by whatever else is
//     mutating the DOM (a later Turbo morph/stream, a sibling
//     component's own click handler, ...) -- ported concept of
//     react-collection's "ordered registry... updated as [items]
//     connect/disconnect", ~querySelectorAll-based since DOM order
//     already IS registration order outside React (the analysis doc's
//     own note).
//
// Consumers so far: ui/toggle_group.pl's <px-toggle-group>
// (assets/js/components/toggle_group.js). Tabs/Toolbar/Accordion are
// expected to import this same function next (docs/radix-port-
// analysis.md's dependency-ordered "Genuinely reusable" list).

const DISABLED_ATTR_CANDIDATES = ["aria-disabled", "data-disabled"];

function isDisabled(item) {
  if (item.disabled === true) return true;
  if (item.getAttribute("aria-disabled") === "true") return true;
  return item.hasAttribute("data-disabled");
}

function firstEnabledIndex(items) {
  return items.findIndex((item) => !isDisabled(item));
}

function lastEnabledIndex(items) {
  for (let i = items.length - 1; i >= 0; i--) {
    if (!isDisabled(items[i])) return i;
  }
  return -1;
}

function stepIndex(items, currentIndex, delta, loop) {
  const n = items.length;
  let idx = currentIndex;
  for (let steps = 0; steps < n; steps++) {
    idx += delta;
    if (idx < 0) {
      if (!loop) return -1;
      idx = n - 1;
    } else if (idx >= n) {
      if (!loop) return -1;
      idx = 0;
    }
    if (!isDisabled(items[idx])) return idx;
  }
  return -1;
}

function keyIntent(key, orientation, rtl) {
  if (key === "Home" || key === "PageUp") return "first";
  if (key === "End" || key === "PageDown") return "last";
  if (orientation === "horizontal" || orientation === "both") {
    if (key === "ArrowLeft") return rtl ? "next" : "prev";
    if (key === "ArrowRight") return rtl ? "prev" : "next";
  }
  if (orientation === "vertical" || orientation === "both") {
    if (key === "ArrowUp") return "prev";
    if (key === "ArrowDown") return "next";
  }
  return null;
}

export function installRovingFocus(container, options = {}) {
  const {
    itemSelector = "[data-roving-item]",
    orientation = "horizontal",
    loop = false,
    dir = null,
  } = options;

  function getItems() {
    return Array.from(container.querySelectorAll(itemSelector));
  }

  function effectiveDir() {
    if (dir === "ltr" || dir === "rtl") return dir;
    return getComputedStyle(container).direction === "rtl" ? "rtl" : "ltr";
  }

  // Exactly one non-disabled item ends up tabindex="0"; every other
  // item (disabled or not) ends up tabindex="-1". Honours a pre-set
  // tabindex="0" from server-rendered markup when it is still valid.
  function refreshTabIndexes() {
    const items = getItems();
    if (items.length === 0) return;
    let idx = items.findIndex(
      (item) => item.getAttribute("tabindex") === "0" && !isDisabled(item)
    );
    if (idx === -1) idx = firstEnabledIndex(items);
    items.forEach((item, i) => {
      item.setAttribute("tabindex", i === idx ? "0" : "-1");
    });
  }

  function setActive(activeItem) {
    getItems().forEach((item) => {
      item.setAttribute("tabindex", item === activeItem ? "0" : "-1");
    });
  }

  function onFocusIn(event) {
    const item = event.target.closest(itemSelector);
    if (!item || !container.contains(item) || isDisabled(item)) return;
    setActive(item);
  }

  function onKeyDown(event) {
    if (event.defaultPrevented) return;
    if (event.altKey || event.ctrlKey || event.metaKey) return;
    const currentItem = event.target.closest(itemSelector);
    if (!currentItem || !container.contains(currentItem)) return;

    const items = getItems();
    const currentIndex = items.indexOf(currentItem);
    if (currentIndex === -1) return;

    const intent = keyIntent(event.key, orientation, effectiveDir() === "rtl");
    if (!intent) return;

    let nextIndex;
    if (intent === "first") nextIndex = firstEnabledIndex(items);
    else if (intent === "last") nextIndex = lastEnabledIndex(items);
    else nextIndex = stepIndex(items, currentIndex, intent === "next" ? 1 : -1, loop);

    if (nextIndex === -1 || nextIndex === currentIndex) return;

    event.preventDefault();
    const nextItem = items[nextIndex];
    setActive(nextItem);
    nextItem.focus();
  }

  container.addEventListener("focusin", onFocusIn);
  container.addEventListener("keydown", onKeyDown);

  // NOTE: "tabindex" is deliberately NOT in attributeFilter -- this
  // module is itself the only thing that ever writes it (setActive/
  // refreshTabIndexes), and DOM attribute mutation records fire on
  // every setAttribute call regardless of whether the value actually
  // changed, so watching it here would make refreshTabIndexes
  // re-trigger its own MutationObserver callback forever.
  const observer = new MutationObserver(refreshTabIndexes);
  observer.observe(container, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["disabled", ...DISABLED_ATTR_CANDIDATES],
  });

  refreshTabIndexes();

  return function uninstall() {
    container.removeEventListener("focusin", onFocusIn);
    container.removeEventListener("keydown", onKeyDown);
    observer.disconnect();
  };
}
