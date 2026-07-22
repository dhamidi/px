// assets/js/components/dialog.js -- <px-dialog> (adr/0026): the
// irreducible interactive sliver of the Dialog port
// (prolog/ui/dialog.pl). Plain ES module, no build step -- served
// through the importmap under the bare specifier "components/dialog"
// (adr/0025), imported once from assets/js/app.js.
//
// prolog/ui/dialog.pl already renders the correct closed-state markup
// on every request: a real, focusable <button> Trigger (aria-haspopup=
// "dialog" aria-expanded="false" data-state="closed") and a native
// <dialog> Content with no `open` attribute -- which the UA stylesheet
// (`dialog:not([open]) { display: none }`) already hides with zero JS.
// Without this element ever loading, the Trigger is inert (nothing
// calls showModal()/show()) but nothing else breaks -- the documented
// no-JS story (adr/0026 rule 4's progressive-enhancement bar; see the
// module header's own "Deliberately NOT ported" / Root doc-comment).
//
// docs/radix-port-analysis.md's own verdict on Dialog: "CUSTOM-ELEMENT,
// substantially platform-assisted -- <dialog> + showModal() gives
// native top-layer stacking, ::backdrop (replacing Overlay), Escape-
// to-close, and a basic focus trap with default focus-return, for
// free... What it does NOT give you: (2) scroll-lock...; (3) <dialog>
// has no light-dismiss... you add a manual ::backdrop/event.target
// click check yourself." This element's entire job is exactly that
// short list, plus keeping the Trigger's own aria-expanded/data-state
// attributes (which <dialog> has no way to reach on its own -- they
// live on a SIBLING element) in sync with Content's:
//
//   1. Trigger click -> showModal() (or show(), see MODAL below).
//   2. Close: any element inside the dialog carrying
//      `data-dialog-close` (prolog/ui/dialog.pl's dialog_close/2
//      marker) -> dialogEl.close(). Escape is NOT separately handled --
//      it is the native `cancel` event a modal <dialog> already fires
//      for free, which the HTML spec's own default action already
//      resolves into a `close()` call; this element only listens for
//      the resulting `close` event (step 4) to do its own sync work,
//      same as every other close path.
//   3. Outside click (modal AND not opted out, see data-no-outside-dismiss
//      below): a `click` listener on the <dialog> element itself. A
//      click that lands in the ::backdrop area dispatches with
//      `event.target === dialogEl` (nothing inside the dialog's content
//      box absorbed it); a click on the dialog's own padding/background
//      *inside* its rendered box ALSO sets target===dialogEl, so
//      `target===dialogEl` alone is not enough -- a
//      `getBoundingClientRect()` bounds check on the pointer
//      coordinates disambiguates "outside the box" (close) from
//      "inside the box, on bare background" (do nothing), exactly the
//      analysis doc's own "event.target === dialogEl with a bounds
//      check" phrasing.
//
//      `data-no-outside-dismiss` (prolog/ui/alert_dialog.pl's opt-out,
//      adr/0026): when present on the <dialog> element, this listener
//      is never attached at all -- Alert Dialog's defining behavior is
//      that outside click must NOT dismiss it (the ARIA alertdialog
//      pattern: only an explicit action closes it; Escape still does,
//      unaffected by this flag, since the `cancel`/`close` event path
//      below is not gated on it). Backward-compatible: absent (every
//      existing Dialog) behaves exactly as before.
//   4. `close` event (fired for EVERY dialog-closing path: Escape,
//      backdrop click, a data-dialog-close button, or a form
//      method="dialog" submission) -> data-state="closed" on Content,
//      aria-expanded="false"/data-state="closed" on the Trigger (if
//      one exists), and scroll-lock release.
//   5. Body scroll-lock: on open, save the current inline
//      `document.body.style.overflow` and set it to "hidden"; on
//      close (step 4), restore the saved value. Documented caveat
//      (analysis doc's own "scroll-lock-with-shards" phrase): this is
//      a single-level lock with no scrollbar-gutter/layout-shift
//      compensation and no stacking ("shard") support for multiple
//      simultaneously-open dialogs -- the last one to close simply
//      restores whatever was saved when IT opened, which is correct
//      for the single-modal-at-a-time common case this port targets
//      but can under- or over-restore with nested/concurrent modals.
//
// MODAL vs non-modal (`data-modal="false"`, prolog/ui/dialog.pl's
// `modal(false)` option): a non-modal dialog is opened with `show()`
// instead of `showModal()`. Per the analysis doc, native `.show()` has
// NO top-layer promotion, NO ::backdrop, NO native Escape-to-close, and
// NO focus trap -- none of which this element hand-rolls (out of scope,
// same "irreducible behavior only" bar the module header documents).
// Concretely, for a non-modal dialog: outside-click dismiss and
// scroll-lock are both SKIPPED (skipping is the intentionally simple,
// documented behavior -- a non-modal surface is not supposed to block
// the rest of the page), and Escape does nothing natively (there is no
// key listener added here to compensate). Trigger sync (step 4) and the
// data-dialog-close button (step 2) still work identically either way.
//
// State lives entirely on the Trigger's and Content's own DOM
// attributes -- never a parallel JS store (adr/0026 rule 4) -- so a
// later server re-render or Turbo morph/stream (adr/0024) can't desync
// from what this element last wrote. The one exception is scroll-lock's
// saved-overflow-value, which is necessarily transient JS state (there
// is no DOM attribute a page reload would need to reproduce -- a fresh
// load always starts unlocked).

const TRIGGER_SELECTOR = '[aria-haspopup="dialog"]';
const CLOSE_SELECTOR = "[data-dialog-close]";

class PxDialog extends HTMLElement {
  connectedCallback() {
    this._trigger = this.querySelector(TRIGGER_SELECTOR);
    this._dialog = this.querySelector("dialog");
    if (!this._dialog) return;

    this._modal = this._dialog.getAttribute("data-modal") !== "false";
    this._noOutsideDismiss = this._dialog.hasAttribute("data-no-outside-dismiss");
    this._savedOverflow = null;

    this._onTriggerClick = this._onTriggerClick.bind(this);
    this._onDialogClick = this._onDialogClick.bind(this);
    this._onClose = this._onClose.bind(this);

    if (this._trigger) {
      this._trigger.addEventListener("click", this._onTriggerClick);
    }
    // Delegate close-button clicks (data-dialog-close may appear more
    // than once, or be added dynamically inside caller-supplied body
    // content) rather than binding one listener per button.
    this._dialog.addEventListener("click", this._onCloseButtonClick.bind(this));
    if (this._modal && !this._noOutsideDismiss) {
      this._dialog.addEventListener("click", this._onDialogClick);
    }
    this._dialog.addEventListener("close", this._onClose);
  }

  disconnectedCallback() {
    if (this._trigger) {
      this._trigger.removeEventListener("click", this._onTriggerClick);
    }
    if (this._dialog) {
      this._dialog.removeEventListener("close", this._onClose);
    }
    // Never leave the page scroll-locked behind a removed element.
    this._unlockScroll();
  }

  _onTriggerClick() {
    if (this._dialog.open) return;
    if (this._modal) {
      this._dialog.showModal();
      this._lockScroll();
    } else {
      this._dialog.show();
    }
    this._syncOpen(true);
  }

  _onCloseButtonClick(event) {
    const closeEl = event.target.closest(CLOSE_SELECTOR);
    if (!closeEl || !this._dialog.contains(closeEl)) return;
    this._dialog.close();
  }

  // Outside (backdrop) click -- see the module header's step 3.
  _onDialogClick(event) {
    if (event.target !== this._dialog) return;
    const rect = this._dialog.getBoundingClientRect();
    const inBounds =
      event.clientX >= rect.left &&
      event.clientX <= rect.right &&
      event.clientY >= rect.top &&
      event.clientY <= rect.bottom;
    if (!inBounds) this._dialog.close();
  }

  // Fires for every dialog-closing path (Escape's native `cancel` ->
  // default-actioned close, a data-dialog-close button, backdrop click,
  // or dialogEl.close() called by any other script) -- the one place
  // this element needs to re-sync state, regardless of *why* it closed.
  _onClose() {
    this._unlockScroll();
    this._syncOpen(false);
  }

  _syncOpen(open) {
    const state = open ? "open" : "closed";
    this._dialog.setAttribute("data-state", state);
    if (this._trigger) {
      this._trigger.setAttribute("aria-expanded", String(open));
      this._trigger.setAttribute("data-state", state);
    }
  }

  _lockScroll() {
    if (this._savedOverflow !== null) return; // already locked (shouldn't happen)
    this._savedOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
  }

  _unlockScroll() {
    if (this._savedOverflow === null) return;
    document.body.style.overflow = this._savedOverflow;
    this._savedOverflow = null;
  }
}

customElements.define("px-dialog", PxDialog);
