// assets/js/components/avatar.js -- <px-avatar> (adr/0026): the
// irreducible interactive sliver of the Avatar port
// (prolog/ui/avatar.pl). Plain ES module, no build step -- served
// through the importmap under the bare specifier "components/avatar"
// (adr/0025), imported once from assets/js/app.js.
//
// docs/radix-port-analysis.md's "Avatar" entry: there is no CSS-only
// way to know whether an <img> actually decoded (no `:error`/`:broken`
// pseudo-class, and `:has()` cannot observe a failed image decode).
// prolog/ui/avatar.pl already server-renders BOTH the image and the
// fallback, stacked in the same CSS grid cell (assets/css/ui.css) with
// the image painted last -- so the common "image loads fine" case
// already looks right with zero JS, from paint order alone. This
// element's only job is watching the real, already-in-DOM <img> for
// load/error and reflecting the result onto its own `data-state`
// attribute ("loading" | "loaded" | "error") for that CSS to key off.
//
// State lives on the DOM attribute the server already wrote (adr/0026
// rule 4) -- never a parallel JS store -- so a later server re-render
// of the same markup (reload, Turbo visit, a Turbo-stream replace,
// adr/0024) can never desync from it: every connectedCallback just
// re-derives state from whatever <img> is present right now.
//
// Deviation from upstream Radix, noted per adr/0026 rule 2: Radix's
// `useImageLoadingStatus` builds a SEPARATE, off-DOM `new Image()` to
// probe load/error, because its <img> only mounts once status is
// already "loaded". This port's <img> is unconditionally in the DOM
// from the server, so it listens on that real element directly instead
// -- same net semantics (`image.complete && image.naturalWidth > 0` is
// the same "loaded but 0x0" guard upstream's hook uses), one fewer
// object.
//
// Without JS, `<px-avatar>` never upgrades: the browser treats it as an
// unknown inline element and simply renders its light-DOM children (the
// stacked <img>/fallback <span>) in place -- already correct-looking
// for the common loaded case via paint order alone (adr/0026 rule 4's
// progressive-enhancement bar).

class PxAvatar extends HTMLElement {
  connectedCallback() {
    const img = this.querySelector(":scope > img.px-avatar-image");

    if (!img) {
      // No Image part at all (a fallback-only avatar): nothing to
      // watch. "error" is the correct resting data-state -- same CSS a
      // real failed decode gets, harmless here since there is no
      // .px-avatar-image to hide, and it leaves the fallback exactly as
      // visible as it already is by default.
      this.dataset.state = "error";
      return;
    }

    const fallback = this.querySelector(":scope > .px-avatar-fallback");
    this.dataset.state = "loading";

    // Radix's Fallback `delayMs` prop: avoid flashing initials before a
    // fast (often cache-warm) image paints. `data-delay-ms` is
    // prolog/ui/avatar.pl's avatar_fallback/1,2 `delay_ms(N)` option.
    // Expressed here as the fallback briefly carrying the native
    // `hidden` attribute -- no extra CSS needed, `[hidden]` is
    // `display: none` in every UA stylesheet already -- removed once
    // the delay elapses regardless of outcome (if the image already won
    // by then, the data-state="loaded" CSS rule keeps the fallback
    // hidden anyway).
    if (fallback && fallback.dataset.delayMs) {
      const delayMs = parseInt(fallback.dataset.delayMs, 10);
      if (Number.isFinite(delayMs) && delayMs > 0) {
        fallback.hidden = true;
        setTimeout(() => {
          fallback.hidden = false;
        }, delayMs);
      }
    }

    const settle = () => {
      // Same guard upstream's hook uses: a `load` event can still fire
      // for a broken image that decoded to 0x0.
      this.dataset.state = img.complete && img.naturalWidth > 0 ? "loaded" : "error";
    };

    if (img.complete) {
      settle();
    } else {
      img.addEventListener("load", settle, { once: true });
      img.addEventListener("error", settle, { once: true });
    }
  }
}

customElements.define("px-avatar", PxAvatar);
