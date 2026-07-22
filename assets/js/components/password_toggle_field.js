// assets/js/components/password_toggle_field.js -- <px-password-toggle-field>
// (adr/0026): the irreducible interactive sliver of the Password
// Toggle Field port (prolog/ui/password_toggle_field.pl). Plain ES
// module, no build step -- served through the importmap under the
// bare specifier "components/password_toggle_field" (adr/0025),
// imported once from assets/js/app.js.
//
// prolog/ui/password_toggle_field.pl already renders a real, fully
// usable native <input type=password> on every request -- typing,
// focus, native browser password-manager integration, and <form>
// submission all work with ZERO JS. What the platform genuinely
// cannot give for free (docs/radix-port-analysis.md's own verdict:
// "there is no native 'reveal password' control exposed to page
// authors") is flipping that input's `type` between "password"/"text"
// on demand -- that is this element's entire job, plus the small set
// of upstream nuances the analysis doc calls out: keep focus (and,
// best-effort, the text selection) on the input across the type swap,
// and auto-hide on the ancestor <form>'s native submit/reset events so
// the browser never remembers a revealed plaintext value.
//
// Pre-hydration, the Toggle button is rendered aria-hidden="true"
// tabindex="-1" by the server (prolog/ui/password_toggle_field.pl's
// own documented pattern, lifted straight from the analysis doc) --
// deliberately inert, since a pre-JS click on it could not do
// anything anyway (no native type-swap mechanism exists). Upgrading
// removes both attributes, exactly the "render inert, then flip both
// attributes on custom-element upgrade" mapping the analysis doc
// suggests.
//
// State lives entirely on the wrapped elements' own attributes/
// properties -- never a parallel JS store (adr/0026 rule 4): the
// input's own `type` IS the visibility state, `data-visible` on the
// Toggle mirrors it for CSS (assets/css/ui.css shows exactly one of
// the eye/eye-off icon spans, keyed off it), and the hidden
// accessible-name span's `textContent` mirrors it for assistive tech.
// A later server re-render can never desync from what this element
// last wrote, because there is nothing to reconcile against -- no
// second source of truth.
//
// Upstream nuance this port DROPS, noted here rather than in the .pl
// module header since it is purely a client-side behavioral choice:
// Radix disambiguates real pointer clicks (which need focus restored
// to the input) from keyboard-driven button activation (Tab'd to the
// button directly, no restoration expected) via a pointerdown flag
// with a fallback idle-callback timer. This element always restores
// focus to the input after a toggle, regardless of activation method.
// The simplification is safe here because there is nowhere else
// useful for focus to land after a toggle click in this component's
// narrow scope (one input, one button, no surrounding widget) --
// unlike, say, a roving-focus menu, "focus goes back to the field you
// were just editing" is the unambiguously correct outcome either way.
//
// Without JS, <px-password-toggle-field> never upgrades: the browser
// treats it as an unknown inline element and renders its light-DOM
// children (the div, input, and inert button) in place -- already a
// real, focusable, keyboard-operable password field; the reveal
// button just cannot do anything yet, and says so to AT/keyboard by
// staying inert (aria-hidden + tabindex=-1) until this module loads.

class PxPasswordToggleField extends HTMLElement {
  connectedCallback() {
    this._input = this.querySelector(
      'input[type="password"], input[type="text"]',
    );
    this._toggle = this.querySelector(
      ".px-password-toggle-field-toggle",
    );
    if (!this._input || !this._toggle) return;

    this._label = this._toggle.querySelector(".px-visually-hidden");

    // Upgrade: the button is now genuinely interactive, so drop the
    // pre-hydration inert markers (module header, "render inert, then
    // flip on upgrade").
    this._toggle.removeAttribute("aria-hidden");
    this._toggle.removeAttribute("tabindex");

    this._onToggleClick = this._onToggleClick.bind(this);
    this._toggle.addEventListener("click", this._onToggleClick);

    // Auto-hide on the ancestor <form>'s native submit/reset (analysis
    // doc's own note: "the only auto-hide is on the ancestor <form>'s
    // native reset/submit events, to prevent the browser from
    // remembering the revealed value") -- prevents accidental
    // plaintext persistence across a submit/reset round-trip.
    this._form = this._input.form;
    if (this._form) {
      this._onFormReset = this._resetToHidden.bind(this);
      this._form.addEventListener("submit", this._onFormReset);
      this._form.addEventListener("reset", this._onFormReset);
    }
  }

  disconnectedCallback() {
    if (this._toggle) {
      this._toggle.removeEventListener("click", this._onToggleClick);
    }
    if (this._form) {
      this._form.removeEventListener("submit", this._onFormReset);
      this._form.removeEventListener("reset", this._onFormReset);
    }
  }

  _onToggleClick() {
    const input = this._input;
    const nowVisible = input.type === "password";

    // Best-effort selection capture -- selectionStart/End throw
    // (InvalidStateError) on some browsers for type=password, so this
    // is guarded and simply skipped if unsupported, same fallback
    // shape as every other progressive-enhancement sliver in this
    // library.
    let start = null;
    let end = null;
    try {
      start = input.selectionStart;
      end = input.selectionEnd;
    } catch {
      // Selection API unsupported for the current type -- fine, we
      // just won't restore it below.
    }

    input.type = nowVisible ? "text" : "password";
    this._setVisible(nowVisible);

    // Restore focus (module header: always, a safe simplification of
    // upstream's pointer-vs-keyboard flag in this component's narrow
    // scope) and, best-effort, the selection -- deferred to the next
    // frame since changing `type` resets native selection state
    // synchronously, same "let the type swap settle first" reasoning
    // the analysis doc attributes to upstream's own
    // requestAnimationFrame.
    requestAnimationFrame(() => {
      input.focus();
      if (start !== null && end !== null) {
        try {
          input.setSelectionRange(start, end);
        } catch {
          // Still unsupported for the new type -- nothing to do.
        }
      }
    });
  }

  _resetToHidden() {
    if (this._input.type !== "password") {
      this._input.type = "password";
      this._setVisible(false);
    }
  }

  _setVisible(visible) {
    this._toggle.setAttribute("data-visible", String(visible));
    if (this._label) {
      this._label.textContent = visible ? "Hide password" : "Show password";
    }
  }
}

customElements.define("px-password-toggle-field", PxPasswordToggleField);
