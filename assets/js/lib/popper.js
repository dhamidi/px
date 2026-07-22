// assets/js/lib/popper.js -- shared floating-element positioning
// (adr/0026 rule 5). Plain ES module, no build step -- served through
// the importmap under the bare specifier "lib/popper" (adr/0025, the
// same automatic "js/lib/popper.js" -> "lib/popper" mapping
// px_assets.pl's javascript_importmap_tags/1 gives every file under
// assets/js/).
//
// Ports the CONCEPT of Radix's react-popper (docs/radix-port-
// analysis.md, "Shared machinery" -> "popper" entry): "floating-
// element positioning: side/align, offset, collision-aware flip/
// shift, arrow placement... Now a thin wrapper around @floating-ui/
// react-dom; own logic is anchor context..., transform-origin
// computation, and strategy: 'fixed' + autoUpdate." None of react-
// popper's own code carries over (it is a React-context wrapper
// around @floating-ui); what this module ports is the same slice
// @floating-ui itself implements: side/align placement math,
// viewport-collision flip, shift-into-view, and a fixed-position
// autoUpdate loop -- the analysis doc's own verdict on why this can't
// be CSS-only: "CSS anchor positioning... covers static placement and
// simple flip-fallback declaratively, but not shift/limitShift
// (partial-overlap sliding), the size middleware..., or the hide
// middleware... and cross-browser anchor-positioning support is still
// uneven as of 2026." This module is that JS fallback -- the one
// every anchored primitive (Popover first, then Tooltip/HoverCard/
// Menu/Select) is built against.
//
// ---------------------------------------------------------------------
// THE CONTRACT (read this before importing from a component element):
// ---------------------------------------------------------------------
//
//   import { position, autoUpdate } from "lib/popper";
//
//   const result = position(anchorEl, floatingEl, {
//     side: "bottom",       // "top" | "right" | "bottom" | "left".
//                            // Default: "bottom".
//     align: "center",      // "start" | "center" | "end", along the
//                            // axis perpendicular to `side`.
//                            // Default: "center".
//     sideOffset: 0,         // px gap between anchor and floating
//                            // element, along the `side` axis.
//                            // Default: 0.
//     alignOffset: 0,        // px shift along the align axis (from
//                            // the `align`-computed position).
//                            // Default: 0.
//     flip: true,            // when the preferred `side` would overflow
//                            // the viewport and the opposite side has
//                            // more room, flip to the opposite side.
//                            // Default: true.
//     boundaryPadding: 0,    // px inset applied to the viewport before
//                            // collision/shift math -- keeps the
//                            // floating element (and its flip/shift
//                            // decisions) this far from the viewport
//                            // edge. Default: 0.
//   });
//   // result = { side, align, x, y } -- the FINAL computed placement
//   // (side may differ from the requested one if `flip` fired; align
//   // is always the requested value -- shifting slides the box into
//   // view without changing which edge it's nominally aligned to,
//   // same as Radix's own data-align semantics). x/y are the fixed-
//   // position viewport coordinates that were written to
//   // floatingEl.style.{left,top}.
//
//   const stop = autoUpdate(anchorEl, floatingEl, () => {
//     position(anchorEl, floatingEl, { side: "bottom" });
//   });
//   // later, e.g. when the floating element closes:
//   stop();
//
// position/3 is a single synchronous positioning pass:
//   - Reads both elements' current `getBoundingClientRect()` (viewport-
//     relative -- pairs with the `fixed` strategy below, so scroll
//     offsets never enter the math).
//   - Picks the final `side`: the requested one, unless `flip` is true
//     AND that side overflows the (padded) viewport AND the opposite
//     side has room -- a single flip to the exact opposite side, not
//     Radix's full 8-direction fallback list (documented reduction: a
//     future consumer needing the full fallback list can layer it on
//     top of this primitive without changing the contract).
//   - Computes the align offset along the cross axis (start/center/end
//     + alignOffset), same as Radix's own align math.
//   - Shifts (clamps) the cross-axis coordinate so the floating element
//     stays within the padded viewport -- Radix's `shift`/`limitShift`
//     middleware's core behaviour -- WITHOUT touching the main-axis
//     coordinate (shifting never makes the floating element overlap
//     the anchor).
//   - Sets `floatingEl.style.position = "fixed"` plus `left`/`top` in
//     px (Radix's own `strategy: 'fixed'`), and `data-side`/
//     `data-align` on floatingEl -- Radix's styling contract: consumer
//     CSS keys arrow direction and enter/exit animation off these two
//     attributes, e.g. `[data-side="top"] { ... }`.
//   - Pure and synchronous: no ResizeObserver, no caching -- callers
//     needing live repositioning wrap it in autoUpdate (below) or their
//     own scheduler.
//
// autoUpdate/3 keeps a floating element correctly positioned for as
// long as it stays open, the way Radix's popper leans on @floating-
// ui's own `autoUpdate` for: window `scroll` (capture phase, so
// scrolling ANY ancestor scroll container fires it, not just window)
// and `resize` listeners call `applyFn` immediately on change, PLUS a
// `requestAnimationFrame` loop calling `applyFn` every frame as a
// catch-all for everything neither event covers (an anchor moving via
// CSS transform/transition, layout shifted by unrelated page content,
// a scroll container that doesn't bubble a `scroll` event to
// `window`...). `applyFn` is caller-supplied (typically a closure over
// `position(anchorEl, floatingEl, opts)`) rather than baked in here,
// so a consumer can add its own side effects (re-measuring an arrow,
// toggling a `data-hidden` attribute when the anchor scrolls fully out
// of view) in the same callback. Returns a `stop()` cleanup that
// removes both listeners and cancels the rAF loop -- always call it
// when the floating element closes/disconnects, mirroring
// roving-focus.js's own `uninstall()` contract.
//
// Consumers: prolog/ui/popover.pl's <px-popover>
// (assets/js/components/popover.js), this module's proving consumer.
// Tooltip/HoverCard/Menu are expected to import the same `position`/
// `autoUpdate` pair next (docs/radix-port-analysis.md's dependency-
// ordered "popper" consumer list) -- the signature above is the one to
// build against; extend via new `options` keys, never by breaking an
// existing one.

const OPPOSITE_SIDE = { top: "bottom", bottom: "top", left: "right", right: "left" };

function clamp(value, min, max) {
  if (max < min) return min; // floating element bigger than the viewport -- pin to the start.
  return Math.min(Math.max(value, min), max);
}

function viewportRect(boundaryPadding) {
  return {
    top: boundaryPadding,
    left: boundaryPadding,
    right: window.innerWidth - boundaryPadding,
    bottom: window.innerHeight - boundaryPadding,
  };
}

// Would placing floatingRect on `side` of anchorRect (with sideOffset)
// overflow the padded viewport along the main axis?
function overflowsSide(side, anchorRect, floatingRect, sideOffset, viewport) {
  switch (side) {
    case "top":
      return anchorRect.top - sideOffset - floatingRect.height < viewport.top;
    case "bottom":
      return anchorRect.bottom + sideOffset + floatingRect.height > viewport.bottom;
    case "left":
      return anchorRect.left - sideOffset - floatingRect.width < viewport.left;
    case "right":
      return anchorRect.right + sideOffset + floatingRect.width > viewport.right;
    default:
      return false;
  }
}

// Main-axis coordinate for `side`; cross-axis coordinate defaults to
// the anchor's own edge (applyAlign overwrites it below).
function sideCoords(side, anchorRect, floatingRect, sideOffset) {
  switch (side) {
    case "top":
      return { x: anchorRect.left, y: anchorRect.top - floatingRect.height - sideOffset };
    case "bottom":
      return { x: anchorRect.left, y: anchorRect.bottom + sideOffset };
    case "left":
      return { x: anchorRect.left - floatingRect.width - sideOffset, y: anchorRect.top };
    case "right":
      return { x: anchorRect.right + sideOffset, y: anchorRect.top };
    default:
      return { x: anchorRect.left, y: anchorRect.bottom };
  }
}

function applyAlign(side, align, anchorRect, floatingRect, alignOffset, coords) {
  const { x, y } = coords;
  if (side === "top" || side === "bottom") {
    switch (align) {
      case "start":
        return { x: anchorRect.left + alignOffset, y };
      case "end":
        return { x: anchorRect.right - floatingRect.width + alignOffset, y };
      default: // "center"
        return {
          x: anchorRect.left + (anchorRect.width - floatingRect.width) / 2 + alignOffset,
          y,
        };
    }
  }
  // side === "left" || side === "right"
  switch (align) {
    case "start":
      return { x, y: anchorRect.top + alignOffset };
    case "end":
      return { x, y: anchorRect.bottom - floatingRect.height + alignOffset };
    default: // "center"
      return {
        x,
        y: anchorRect.top + (anchorRect.height - floatingRect.height) / 2 + alignOffset,
      };
  }
}

// Clamps ONLY the cross-axis coordinate into the padded viewport --
// the main axis (how far the floating element sits from the anchor)
// is never touched by shifting, so it can never end up overlapping the
// anchor.
function shiftIntoView(side, coords, floatingRect, viewport) {
  const { x, y } = coords;
  if (side === "top" || side === "bottom") {
    return { x: clamp(x, viewport.left, viewport.right - floatingRect.width), y };
  }
  return { x, y: clamp(y, viewport.top, viewport.bottom - floatingRect.height) };
}

export function position(anchorEl, floatingEl, options = {}) {
  const {
    side = "bottom",
    align = "center",
    sideOffset = 0,
    alignOffset = 0,
    flip = true,
    boundaryPadding = 0,
  } = options;

  const anchorRect = anchorEl.getBoundingClientRect();
  const floatingRect = floatingEl.getBoundingClientRect();
  const viewport = viewportRect(boundaryPadding);

  let finalSide = side;
  if (flip && overflowsSide(side, anchorRect, floatingRect, sideOffset, viewport)) {
    const opposite = OPPOSITE_SIDE[side];
    if (opposite && !overflowsSide(opposite, anchorRect, floatingRect, sideOffset, viewport)) {
      finalSide = opposite;
    }
  }

  let coords = sideCoords(finalSide, anchorRect, floatingRect, sideOffset);
  coords = applyAlign(finalSide, align, anchorRect, floatingRect, alignOffset, coords);
  coords = shiftIntoView(finalSide, coords, floatingRect, viewport);

  floatingEl.style.position = "fixed";
  floatingEl.style.left = `${coords.x}px`;
  floatingEl.style.top = `${coords.y}px`;
  floatingEl.setAttribute("data-side", finalSide);
  floatingEl.setAttribute("data-align", align);

  return { side: finalSide, align, x: coords.x, y: coords.y };
}

export function autoUpdate(anchorEl, floatingEl, applyFn) {
  applyFn();

  const onScrollOrResize = () => applyFn();
  window.addEventListener("scroll", onScrollOrResize, { capture: true, passive: true });
  window.addEventListener("resize", onScrollOrResize);

  let rafId = requestAnimationFrame(function loop() {
    applyFn();
    rafId = requestAnimationFrame(loop);
  });

  return function stop() {
    window.removeEventListener("scroll", onScrollOrResize, { capture: true });
    window.removeEventListener("resize", onScrollOrResize);
    cancelAnimationFrame(rafId);
  };
}
