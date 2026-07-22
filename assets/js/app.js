// assets/js/app.js -- the application's JS entrypoint (adr/0025).
//
// Loaded as a <script type="module"> by javascript_importmap_tags via the
// import map, so "turbo" below resolves to the content-hashed
// /assets/js/turbo-<hash>.js URL -- no bundler, no build step, exactly
// Rails 8's importmap-rails model.
import "turbo";
// px_ui components (adr/0026): each ships its own custom element,
// registered on import here. <px-toggle> is ui/toggle.pl's.
import "components/toggle";
// <px-avatar> is ui/avatar.pl's (adr/0026): watches its <img> for
// load/error and reflects the result onto its own data-state attribute.
import "components/avatar";
// <px-switch> is ui/switch.pl's (adr/0026): keeps aria-checked/data-state
// live on click -- the platform already handles the toggle itself.
import "components/switch";
// <px-checkbox> is ui/checkbox.pl's (adr/0026): only wraps the
// indeterminate case -- sets the JS-only .indeterminate property and
// keeps aria-checked/data-state live once a click resolves it away.
import "components/checkbox";
// <px-toggle-group> is ui/toggle_group.pl's (adr/0026): the library's
// first roving-focus consumer (assets/js/lib/roving-focus.js) --
// arrow-key/Home/End navigation across Items, plus instant click-flip
// of aria-pressed/aria-checked/data-state (type=single also enforces
// radio-like exclusivity across siblings).
import "components/toggle_group";
// <px-tabs> is ui/tabs.pl's (adr/0026): the library's second
// roving-focus consumer -- arrow-key/Home/End navigation across
// Triggers, plus automatic (focus-driven) activation switching
// aria-selected/data-state/hidden across Triggers/Content.
import "components/tabs";
