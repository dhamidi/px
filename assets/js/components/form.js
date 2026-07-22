// assets/js/components/form.js -- <px-form> (adr/0026): the irreducible
// interactive sliver of the Form port (prolog/ui/form.pl). Plain ES
// module, no build step -- served through the importmap under the
// bare specifier "components/form" (adr/0025), imported once from
// assets/js/app.js.
//
// prolog/ui/form.pl already renders `novalidate` on the wrapped
// <form> (see that module's header for the full rationale) -- the
// native Constraint Validation API (`required`, `type=email`,
// `pattern`, `minlength`, ...) still computes a correct
// `element.validity`/`checkValidity()` result with zero JS; what
// `novalidate` switches OFF is only the browser's own *automatic*
// trigger for consulting it at submit time (and the native bubble
// UI). This element's entire job is to be that trigger instead, and
// to reflect the result onto the `data-valid`/`data-invalid` and
// Message `hidden` contract prolog/ui/form.pl's module header
// documents -- nothing here computes validity itself, it only reads
// `control.checkValidity()` / `control.validity` and mirrors it.
//
// Two triggers, matching the module header's "Behavior" note (not
// on every keystroke): native `focusout` (bubbles; native `blur`
// does not, so it cannot be delegated from one listener on this
// element) on any form control, and `submit` on the wrapped <form>,
// where an invalid control also gets `preventDefault()` plus focus
// (Radix's own "focuses the first invalid control on submit").
//
// `aria-invalid` is NEVER touched here -- prolog/ui/form.pl's module
// header is explicit that it mirrors ONLY server-side invalidity
// (px_form's 422 escape hatch, adr/0023), so it is pure server-
// rendered truth this element must leave alone. Likewise, any Message
// carrying `data-forced` (rendered by `form_message([forced(true)],
// ...)`, the real server error text) is skipped outright by
// `_updateMessage` -- a client-side revalidation that happens to pass
// (e.g. a syntactically valid but server-side-taken username) must
// never silently hide a genuine server error.
//
// State lives entirely on the wrapped elements' own attributes --
// never a parallel JS store (adr/0026 rule 4) -- so a later server
// re-render (a fresh page load, or a Turbo visit/stream replace,
// adr/0024) can never desync from what this element last wrote:
// there is nothing to reconcile.
//
// Without JS, <px-form> never upgrades: the browser treats it as an
// unknown inline element and simply renders its light-DOM children
// (the <form> and everything in it) in place. Per prolog/ui/form.pl's
// module header, that means NO client-side validation at all --
// `novalidate` suppresses the native bubble UI regardless of whether
// this module ever loads, and with no JS there is nothing left to
// run `checkValidity()` -- an empty required field submits straight
// through. That is accepted: prolog/px_form.pl (adr/0023) is always
// the real safety net server-side, so this is a pure UX progressive
// enhancement, not a validation backstop.

// Radix's own built-in matcher set, spelled the way
// prolog/ui/form.pl's match_key/2 spells the kebab-case `data-match`
// attribute value -- the inverse of that table, back to the native
// camelCase ValidityState property each one reads.
const MATCH_TO_VALIDITY_KEY = {
  "value-missing": "valueMissing",
  "type-mismatch": "typeMismatch",
  "pattern-mismatch": "patternMismatch",
  "too-long": "tooLong",
  "too-short": "tooShort",
  "range-underflow": "rangeUnderflow",
  "range-overflow": "rangeOverflow",
  "step-mismatch": "stepMismatch",
  "bad-input": "badInput",
};

function isValidatable(el) {
  return !!el && typeof el.checkValidity === "function";
}

class PxForm extends HTMLElement {
  connectedCallback() {
    this._form = this.querySelector("form");
    if (!this._form) return;
    this._onSubmit = this._onSubmit.bind(this);
    this._onFocusOut = this._onFocusOut.bind(this);
    this.addEventListener("submit", this._onSubmit);
    this.addEventListener("focusout", this._onFocusOut);
  }

  disconnectedCallback() {
    this.removeEventListener("submit", this._onSubmit);
    this.removeEventListener("focusout", this._onFocusOut);
  }

  _onFocusOut(event) {
    const control = event.target;
    if (!isValidatable(control)) return;
    this._validateControl(control);
  }

  _onSubmit(event) {
    const controls = Array.from(this._form.elements).filter(isValidatable);
    let firstInvalid = null;
    for (const control of controls) {
      const valid = this._validateControl(control);
      if (!valid && !firstInvalid) firstInvalid = control;
    }
    if (firstInvalid) {
      event.preventDefault();
      firstInvalid.focus();
    }
  }

  // Reads control.checkValidity() (the ONLY validity computation in
  // this file -- everything else is attribute bookkeeping) and mirrors
  // it onto the control itself, its enclosing .px-form-field, that
  // field's .px-form-label, and every .px-form-message inside it.
  // Returns the validity so _onSubmit can find the first invalid
  // control without a second pass.
  _validateControl(control) {
    const valid = control.checkValidity();
    this._toggleValidAttrs(control, valid);

    const field = control.closest(".px-form-field");
    if (field) {
      this._toggleValidAttrs(field, valid);
      const label = field.querySelector(".px-form-label");
      if (label) this._toggleValidAttrs(label, valid);
      field
        .querySelectorAll(".px-form-message")
        .forEach((msg) => this._updateMessage(msg, control, valid));
    }
    return valid;
  }

  // Present-or-omitted, never "false" -- same contract
  // prolog/ui/form.pl's valid_state_attrs/2 renders server-side.
  _toggleValidAttrs(el, valid) {
    if (valid) {
      el.removeAttribute("data-invalid");
      el.setAttribute("data-valid", "");
    } else {
      el.removeAttribute("data-valid");
      el.setAttribute("data-invalid", "");
    }
  }

  _updateMessage(msg, control, valid) {
    // Server truth (px_form's 422 escape hatch) is sticky -- see the
    // module header and prolog/ui/form.pl's form_message/2 header.
    if (msg.hasAttribute("data-forced")) return;

    let show;
    if (valid) {
      show = false;
    } else {
      const matchKey = MATCH_TO_VALIDITY_KEY[msg.dataset.match];
      // No match attribute at all: show on ANY invalidity (Radix's
      // own no-`match` default -- prolog/ui/form.pl's match_attr/2).
      show = matchKey ? control.validity[matchKey] : true;
    }
    msg.hidden = !show;
  }
}

customElements.define("px-form", PxForm);
