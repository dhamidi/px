// assets/js/components/otp_field.js -- <px-otp-field> (adr/0026): the
// irreducible interactive sliver of the One-Time Password Field port
// (prolog/ui/otp_field.pl). Plain ES module, no build step -- served
// through the importmap under the bare specifier "components/otp_field"
// (adr/0025), imported once from assets/js/app.js.
//
// prolog/ui/otp_field.pl already renders every cell's correct initial
// state on every request (aria-label, maxlength/autocomplete per
// cell, data-disabled/disabled, the hidden input's initial value) --
// reload, Turbo visit, or a Turbo-stream replace (adr/0024) all
// reproduce it with zero JS; without JS, the field is still N real,
// individually Tab-reachable, individually labelled text inputs plus
// one hidden input that submits whatever was last typed into cell 1
// alone (no auto-advance, no paste-splitting, no live hidden-input
// sync -- adr/0026 rule 4's progressive-enhancement bar).
//
// This element hand-rolls its own keyboard/paste state machine rather
// than importing "lib/roving-focus" -- see prolog/ui/otp_field.pl's
// module header for why that shared module's shape (single tab-stop
// roving-tabindex) does not fit an OTP field (every cell stays in the
// normal Tab order; there is no single "current item" to rove).
//
// State lives entirely on each cell <input>'s own `.value` and the
// HiddenInput's own `value` attribute -- there is nothing else to
// reconcile: every mutation re-joins all cell values into the hidden
// input, never a parallel JS store (adr/0026 rule 4).

const CELL_SELECTOR = ".px-otp-field-input";
const HIDDEN_SELECTOR = ".px-otp-field-hidden-input";

class PxOtpField extends HTMLElement {
  connectedCallback() {
    this._root = this.querySelector('[role="group"]');
    if (!this._root) return;

    this._numeric = this._root.hasAttribute("data-numeric");
    this._autoSubmit = this._root.hasAttribute("data-auto-submit");

    this._onInput = this._onInput.bind(this);
    this._onKeyDown = this._onKeyDown.bind(this);
    this._onPaste = this._onPaste.bind(this);
    this._onFocusIn = this._onFocusIn.bind(this);

    this._root.addEventListener("input", this._onInput);
    this._root.addEventListener("keydown", this._onKeyDown);
    this._root.addEventListener("paste", this._onPaste);
    this._root.addEventListener("focusin", this._onFocusIn);

    this._syncHidden();
  }

  disconnectedCallback() {
    if (!this._root) return;
    this._root.removeEventListener("input", this._onInput);
    this._root.removeEventListener("keydown", this._onKeyDown);
    this._root.removeEventListener("paste", this._onPaste);
    this._root.removeEventListener("focusin", this._onFocusIn);
  }

  _cells() {
    return Array.from(this._root.querySelectorAll(CELL_SELECTOR));
  }

  _hidden() {
    return this._root.querySelector(HIDDEN_SELECTOR);
  }

  // Digits only when numeric (default); otherwise any non-whitespace
  // visible character. Mirrors the analysis doc's "filters through
  // the configured validation pattern" behavior -- see the module's
  // Prolog header for why this is a plain boolean here, not a full
  // pattern language.
  _sanitize(text) {
    const stripped = text.replace(/\s+/g, "");
    return this._numeric ? stripped.replace(/[^0-9]/g, "") : stripped;
  }

  _firstEmptyIndex(cells) {
    const idx = cells.findIndex((c) => c.value === "");
    return idx === -1 ? cells.length - 1 : idx;
  }

  // Distribute Chars across cells starting at StartIndex, clearing
  // every cell from StartIndex onward first (a paste/autofill of a
  // full code REPLACES whatever was there, matching "paste ...
  // updates every box synchronously"). Returns the index of the last
  // cell that received a character (for focusing), or -1 if none did.
  _distribute(cells, startIndex, chars) {
    let lastFilled = -1;
    for (let i = startIndex; i < cells.length; i++) {
      const ch = chars[i - startIndex];
      if (ch !== undefined) {
        cells[i].value = ch;
        lastFilled = i;
      } else {
        cells[i].value = "";
      }
      this._reflectFilled(cells[i]);
    }
    return lastFilled;
  }

  // Keeps `data-filled=""` -- the CSS filled-cell styling hook -- in
  // sync with `.value`, the same "attribute IS the state" rule every
  // other write in this element already follows (adr/0026 rule 4).
  _reflectFilled(cell) {
    if (cell.value !== "") {
      cell.setAttribute("data-filled", "");
    } else {
      cell.removeAttribute("data-filled");
    }
  }

  _syncHidden() {
    const hidden = this._hidden();
    if (!hidden) return;
    const cells = this._cells();
    const value = cells.map((c) => c.value).join("");
    hidden.setAttribute("value", value);
    hidden.value = value;
    hidden.dispatchEvent(new Event("input", { bubbles: true }));

    if (
      this._autoSubmit &&
      cells.length > 0 &&
      cells.every((c) => c.value.length === 1)
    ) {
      const form = this.closest("form");
      if (form && typeof form.requestSubmit === "function") {
        form.requestSubmit();
      }
    }
  }

  _onFocusIn(event) {
    const cell = event.target.closest(CELL_SELECTOR);
    if (!cell || !this._root.contains(cell)) return;
    const cells = this._cells();
    const index = cells.indexOf(cell);
    const firstEmpty = this._firstEmptyIndex(cells);
    // "Clicking anywhere clamps focus to the first not-yet-fillable
    // position -- you cannot focus a future empty box out of order."
    if (index > firstEmpty) {
      cells[firstEmpty].focus();
    } else {
      cell.select();
    }
  }

  _onInput(event) {
    const cell = event.target.closest(CELL_SELECTOR);
    if (!cell || !this._root.contains(cell)) return;

    const cells = this._cells();
    const index = cells.indexOf(cell);
    const sanitized = this._sanitize(cell.value);

    if (sanitized.length > 1) {
      // A paste or autofill-driven multi-character input event landed
      // directly in this cell (the common case: the first cell, the
      // only one carrying autocomplete="one-time-code"). Distribute
      // from here, same as an explicit paste event.
      const lastFilled = this._distribute(cells, index, sanitized.split(""));
      const focusIndex = lastFilled === -1 ? index : lastFilled;
      cells[focusIndex].focus();
      cells[focusIndex].select();
    } else {
      cell.value = sanitized;
      this._reflectFilled(cell);
      if (sanitized.length === 1 && index < cells.length - 1) {
        cells[index + 1].focus();
      } else if (sanitized.length === 1) {
        // Last cell: re-select for easy retyping instead of leaving
        // the caret after the character.
        cell.select();
      }
    }

    this._syncHidden();
  }

  _onPaste(event) {
    const cell = event.target.closest(CELL_SELECTOR);
    if (!cell || !this._root.contains(cell)) return;
    if (!event.clipboardData) return;

    const text = event.clipboardData.getData("text");
    if (!text) return;
    event.preventDefault();

    const sanitized = this._sanitize(text);
    if (sanitized.length === 0) return;

    const cells = this._cells();
    // A paste always fills from the start -- re-pasting a different
    // code should replace the whole field, not just the cells from
    // wherever the caret happened to be.
    const lastFilled = this._distribute(cells, 0, sanitized.split(""));
    const focusIndex = lastFilled === -1 ? 0 : lastFilled;
    cells[focusIndex].focus();
    cells[focusIndex].select();

    this._syncHidden();
  }

  _onKeyDown(event) {
    const cell = event.target.closest(CELL_SELECTOR);
    if (!cell || !this._root.contains(cell)) return;

    const cells = this._cells();
    const index = cells.indexOf(cell);

    if (event.key === "Backspace" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault();
      cells.forEach((c) => {
        c.value = "";
        this._reflectFilled(c);
      });
      cells[0].focus();
      this._syncHidden();
      return;
    }

    if (event.key === "Backspace" && cell.value === "" && index > 0) {
      event.preventDefault();
      cells[index - 1].focus();
      cells[index - 1].select();
      return;
    }

    if (event.key === "ArrowLeft" && index > 0) {
      event.preventDefault();
      cells[index - 1].focus();
      cells[index - 1].select();
      return;
    }

    if (event.key === "ArrowRight" && index < cells.length - 1) {
      event.preventDefault();
      cells[index + 1].focus();
      cells[index + 1].select();
      return;
    }
  }
}

customElements.define("px-otp-field", PxOtpField);
