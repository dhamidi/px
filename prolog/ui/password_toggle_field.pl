:- module(ui_password_toggle_field, []).

%   No predicates are exported: password_toggle_field/1,
%   password_toggle_field_root/2, password_toggle_field_input/1,
%   password_toggle_field_toggle/1, password_toggle_field_icon/1 are
%   never called module-qualified -- bare-call dispatch through
%   px_template's tmpl/2 / render_helper/2 tables resolves them
%   (adr/0019), the same pattern prolog/ui/switch.pl and
%   prolog/ui/checkbox.pl use. visually_hidden.pl and
%   accessible_icon.pl are use_module'd for their side effect only
%   (registering their own tmpl/2 clauses, so `accessible_icon/3`
%   below resolves) -- neither exports anything either, per their own
%   headers.

:- prolog_load_context(directory, Here),
   atomic_list_concat([Here, '/../px_template'], TemplateSpec),
   atomic_list_concat([Here, '/accessible_icon'], AccessibleIconSpec),
   use_module(TemplateSpec),
   use_module(AccessibleIconSpec).

:- use_module(library(gensym)).

/** <module> Password Toggle Field (adr/0026): wraps a native password
    `<input>` with a button that toggles its `type` between
    `password`/`text`, so a user can reveal/hide what they typed.

Ported from Radix UI's Password Toggle Field primitive (docs/radix-
port-analysis.md, "Password Toggle Field" entry). Upstream anatomy:
`Root` (context only, no DOM), `Input`, `Toggle` (button), `Slot`
(conditional-render helper, no DOM -- not needed here, this port has
no conditional-slot use case), `Icon` (`<svg aria-hidden>` picking a
visible/hidden glyph).

**Deviation #1, noted per adr/0026 rule 2**: unlike upstream's Root
(no DOM node at all -- pure context), this port's `Root` IS a real
`<div>` wrapping Input and Toggle, the same choice
prolog/ui/switch.pl's and prolog/ui/checkbox.pl's own Root make for
their own structural reasons (something has to be the bordered-field
container the CSS composes input+button into one visual unit --
adr/0026 rule 6's "input+button composed as one bordered field").

**Deviation #2**: upstream's Toggle carries `aria-label` (caller-
provided, or auto-derived from the ABSENCE of inner text content via a
`MutationObserver`). This port instead gives the Toggle a REAL,
always-present accessible-name source: `accessible_icon/3`
(ui/accessible_icon.pl, itself built on ui/visually_hidden.pl) wraps
the eye/eye-off icon pair in an `aria-hidden` span and renders a
`.px-visually-hidden` text sibling holding "Show password"/"Hide
password" -- the exact "auto-derived from inner text content" case
upstream's own MutationObserver falls back to, just made the ONLY
path instead of a fallback, and driven by a plain DOM write
(`assets/js/components/password_toggle_field.js` rewriting the hidden
span's `textContent` on toggle) instead of an observer watching for
it. No `aria-label` attribute is written at all. Analysis doc's other
Toggle ARIA note IS followed literally: `aria-controls={inputId}`,
and **no `aria-pressed` anywhere** -- state is communicated purely via
that dynamic hidden-label text, not the toggle-button ARIA pattern,
exactly as upstream.

**Deviation #3, additive-only (rule 2)**: upstream ships **no
`data-*` attributes anywhere** in this package. This port adds ONE,
`data-visible` on the Toggle button (`"true"`/`"false"`), purely as a
CSS hook so `assets/css/ui.css` can show/hide the eye vs. eye-off
icon halves without JS having to toggle a class -- the JS toggle
(below) already has to touch several attributes on click, and writing
one more alongside them is simpler than maintaining a second `class`-
based mechanism.

DOM/ARIA contract emitted, otherwise exactly the analysis doc's entry:

    Input:    `type` in `password`|`text` (mirrors the `visible(_)`
              option), `autocomplete` (default `"current-password"`),
              `autocapitalize="off"`, `spellcheck="false"` -- plus the
              native `id`/`name`/`value`/`placeholder`/`disabled`/
              `required` attributes that make it a real form control.
    Toggle:   `type="button"`, `aria-controls` = the Input's id,
              `class="px-password-toggle-field-toggle"`,
              `data-visible` (deviation #3, above). **Pre-hydration,
              defaults to `aria-hidden="true"` and `tabindex="-1"`**
              -- exactly the analysis doc's own documented pattern,
              "deliberately inert to AT/keyboard before client JS
              attaches, avoiding both layout shift and exposing a
              non-functional control" (there genuinely is no native
              way to flip an `<input>`'s `type` without JS, so a
              pre-JS click on this button can do nothing at all).
              `assets/js/components/password_toggle_field.js` removes
              both attributes on custom-element upgrade -- the exact
              "render inert, then flip both attributes on
              custom-element upgrade" mapping the analysis doc
              suggests.
    Icon:     two `<span class="px-password-toggle-field-icon ...">`
              siblings (eye / eye-off), both wrapped by
              `accessible_icon/3`'s own `aria-hidden` span (deviation
              #2) -- `assets/css/ui.css` shows exactly one of the pair
              at a time, keyed off the Toggle's `data-visible`.

Keyboard/focus interactions (analysis doc's own note): toggling is
click-only, no keyboard shortcut of its own -- Enter/Space activate
the `<button>` natively, free. Focus is restored to the Input after
every toggle (upstream's own behavior, per the task brief -- upstream
also restores the recorded text selection via a deferred
`requestAnimationFrame`, since changing an `<input>`'s `type` resets
native selection state; this port keeps that restoration but drops
upstream's separate pointer-vs-keyboard-activation flag that decides
WHETHER to restore focus -- see assets/js/components/
password_toggle_field.js's header for why always-restore is a safe
simplification here). **No auto-hide-after-N-seconds and no
auto-hide-on-blur** -- the only auto-hide is on the ancestor
`<form>`'s native `reset`/`submit` events, to prevent the browser
from remembering the revealed value (implemented in the same JS
file).

**Interactivity class: CUSTOM-ELEMENT, narrow scope** (the analysis
doc's own verdict) -- there is no native "reveal password" control a
page author can wire up, so the click handler itself is unavoidable.
Pre-hydration, the field is a perfectly usable native `<input
type=password>`; the toggle button just cannot do anything yet (and
says so to AT/keyboard by being inert, deviation-free per the
analysis doc's own pre-hydration pattern above) until
`<px-password-toggle-field>` (assets/js/components/
password_toggle_field.js, imported from assets/js/app.js via the
importmap, adr/0025) upgrades it.

Options (a plain list, adr/0026 rule 1):

    id(Id)          the Input's id (**not** Root's -- deviation #1's
                     flip side: Root here is a plain non-semantic
                     wrapper div, while the Input is the element an
                     external `<label for=...>` or this component's
                     own `aria-controls` needs to address). Default: a
                     fresh `gensym(px_password_toggle_field_, Id)`.
    visible(Bool)    the INITIAL visibility (`type="text"` vs.
                     `"password"`, and the matching Toggle
                     `data-visible`/hidden-label state). Default
                     `false`. Purely a starting point -- clicking
                     Toggle flips it client-side; there is no
                     server-round-trip re-render involved.
    name(N)          the form field name; ABSENT by default (an
                     unnamed input does not submit, same convention as
                     every other form-integrated component here).
    value(V)         initial value; ABSENT by default.
    placeholder(P)   ABSENT by default.
    disabled(Bool)   default `false`. Mirrored onto BOTH Input and
                     Toggle (additive: the analysis doc does not
                     discuss a disabled state at all, but a disabled
                     field whose reveal button still works would be a
                     strange half-disabled control).
    required(Bool)   default `false`. Input only (Toggle has no
                     `required`-shaped concept).
    autocomplete(A)  default `"current-password"` (the analysis doc's
                     own stated default).
    class(C)         merged with Root's default class, default first
                     ("px-password-toggle-field C") -- same convention
                     as every other component in this library.
    anything else (data_*(...), aria_*(...), ...) passed through
                     verbatim to Root, appended AFTER the computed
                     attributes -- same last-wins spread order as
                     every other component here.

`password_toggle_field_root/2`, `_input/1` and `_toggle/1` are
registered as `px_template:render_helper/2` hooks (adr/0019) -- the
Opts-list defaults/merge/attribute-computation logic below is genuine
computation, so it cannot live in a plain `~>` clause.
`password_toggle_field_icon/1` is likewise a `render_helper` (it emits
two sibling spans, which a `~>` clause CAN express, but keeping every
part the same shape as its siblings in this file is simpler to read).
`password_toggle_field/1`, the rule-1 top-level convenience template,
is ALSO a `render_helper` rather than a plain `~>` (unlike Switch's/
Checkbox's own `switch/1`/`checkbox/1`): it has one genuine piece of
shared-state computation a `~>` clause's pure unification cannot
express -- resolving `id(_)` exactly ONCE and threading it back into
Opts before delegating to Root/Input/Toggle, so Toggle's
`aria-controls` and Input's `id` never disagree (see `resolve_id/2`,
below). That id-consistency requirement is this component's only real
"context" dependency (the analysis doc's own note lists `use-
controllable-state`, `id`, `use-effect-event`, `context`) -- once
resolved, the same Opts list is fed to every part unchanged, same as
Progress's value/max.
*/

:- use_module('../px_template').

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

		 /*******************************
		 *        OPTION HELPERS        *
		 *******************************/

%!  take_bool(+Name, +Opts0, -Value, -Rest) is det.
%
%   Pulls Name(Value) out of Opts0 (default `false` if absent). Same
%   helper as switch.pl's / checkbox.pl's.
take_bool(Name, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Opts1)
    ->  Value = V0
    ;   Value = false, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  merge_class(+Opts0, +Default, -ClassVal, -Rest) is det.
%
%   Same helper as progress.pl / toggle.pl / switch.pl's / checkbox.pl's.
merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  take_pwtf_opts(+Opts0, -Id, -Visible, -Disabled, -Required,
%!                 -AutoComplete, -NameAttrs, -ValueAttrs,
%!                 -PlaceholderAttrs, -Rest) is det.
%
%   Pulls every part-shared option out of Opts0; Rest is everything
%   else, in original relative order (class/data_*/... -- Root's
%   pass-through, same shape as checkbox.pl's take_checkbox_opts/7).
take_pwtf_opts(Opts0, Id, Visible, Disabled, Required, AutoComplete,
               NameAttrs, ValueAttrs, PlaceholderAttrs, Rest) :-
    (   selectchk(id(Id0), Opts0, Opts1)
    ->  Id = Id0
    ;   gensym(px_password_toggle_field_, Id), Opts1 = Opts0
    ),
    take_bool(visible, Opts1, Visible, Opts2),
    take_bool(disabled, Opts2, Disabled, Opts3),
    take_bool(required, Opts3, Required, Opts4),
    (   selectchk(autocomplete(AC0), Opts4, Opts5)
    ->  AutoComplete = AC0
    ;   AutoComplete = "current-password", Opts5 = Opts4
    ),
    (   selectchk(name(N0), Opts5, Opts6)
    ->  NameAttrs = [name(N0)]
    ;   NameAttrs = [], Opts6 = Opts5
    ),
    (   selectchk(value(V0), Opts6, Opts7)
    ->  ValueAttrs = [value(V0)]
    ;   ValueAttrs = [], Opts7 = Opts6
    ),
    (   selectchk(placeholder(P0), Opts7, Opts8)
    ->  PlaceholderAttrs = [placeholder(P0)]
    ;   PlaceholderAttrs = [], Opts8 = Opts7
    ),
    Rest = Opts8.

%!  visible_word(+Visible, -Word) is det.
%
%   Word in true|false, derived the same "fall back to false unless
%   literally true" way as every other boolean opt in this library.
visible_word(true, true) :- !.
visible_word(_,    false).

		 /*******************************
		 *             ICONS            *
		 *******************************/

%   Feather-style outline icons (same "inline raw SVG string" idiom
%   the visually_hidden/accessible_icon demos already use), stroke-
%   based so `color: var(--muted)` (assets/css/ui.css) paints them --
%   no separate fill color to keep in sync with the theme.
eye_svg("<svg viewBox=\"0 0 24 24\" width=\"16\" height=\"16\" aria-hidden=\"true\" focusable=\"false\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8Z\"/><circle cx=\"12\" cy=\"12\" r=\"3\"/></svg>").

eye_off_svg("<svg viewBox=\"0 0 24 24\" width=\"16\" height=\"16\" aria-hidden=\"true\" focusable=\"false\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M17.94 17.94A10.94 10.94 0 0 1 12 20c-7 0-11-8-11-8a21.8 21.8 0 0 1 5.06-6.06\"/><path d=\"M9.9 4.24A10.94 10.94 0 0 1 12 4c7 0 11 8 11 8a21.8 21.8 0 0 1-3.22 4.44\"/><path d=\"M14.12 14.12a3 3 0 1 1-4.24-4.24\"/><line x1=\"1\" y1=\"1\" x2=\"23\" y2=\"23\"/></svg>").

		 /*******************************
		 *             PARTS            *
		 *******************************/

%!  password_toggle_field_root(+Opts, +Children) is det.
%
%   Bare-call template surface:
%   `password_toggle_field_root([id("x")], Kids)`. Renders the
%   `<px-password-toggle-field>` custom-element wrapper (adr/0026 rule
%   4) around a `<div>` (this port's Root -- see the module header,
%   deviation #1, for why a div, not upstream's DOM-less context)
%   carrying Children (typically one Input and one Toggle).
px_template:render_helper(password_toggle_field_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_password_toggle_field, [], [div(Attrs, Children)]).

root_attrs(Opts0, Attrs) :-
    take_pwtf_opts(Opts0, _Id, _Visible, _Disabled, _Required, _AutoComplete,
                    _NameAttrs, _ValueAttrs, _PlaceholderAttrs, Rest0),
    merge_class(Rest0, "px-password-toggle-field", ClassVal, Rest),
    Attrs = [class(ClassVal) | Rest].

%!  password_toggle_field_input(+Opts) is det.
%
%   Bare-call template surface:
%   `password_toggle_field_input([visible(true)])`. No children -- an
%   `<input>` is a void element. Carries the entire ARIA/data contract
%   the analysis doc pins to "Input", plus the native attributes
%   (`id`, `name`, `value`, `placeholder`, `disabled`, `required`)
%   that make it a real, independently-functional form control.
px_template:render_helper(password_toggle_field_input(Opts), S) :-
    input_attrs(Opts, Attrs),
    px_template:render(S, input(Attrs)).

input_attrs(Opts0, Attrs) :-
    take_pwtf_opts(Opts0, Id, Visible, Disabled, Required, AutoComplete,
                    NameAttrs, ValueAttrs, PlaceholderAttrs, _Rest),
    (   Visible == true -> Type = text ; Type = password ),
    (   Disabled == true -> DisabledAttr = [disabled] ; DisabledAttr = [] ),
    (   Required == true -> RequiredAttr = [required] ; RequiredAttr = [] ),
    append([ [type(Type), id(Id)],
             [autocomplete(AutoComplete), autocapitalize(off), spellcheck(false)],
             [class("px-password-toggle-field-input")],
             DisabledAttr, RequiredAttr,
             NameAttrs, ValueAttrs, PlaceholderAttrs
           ], Attrs).

%!  password_toggle_field_toggle(+Opts) is det.
%
%   Bare-call template surface:
%   `password_toggle_field_toggle([id("x")])`. A `<button
%   type=button>` whose only children are the Icon pair, wrapped by
%   `accessible_icon/3` (deviation #2 -- see module header) supplying
%   the accessible name from a hidden text sibling, never
%   `aria-label`.
px_template:render_helper(password_toggle_field_toggle(Opts), S) :-
    toggle_attrs(Opts, Attrs),
    toggle_children(Opts, Children),
    px_template:render(S, button(Attrs, Children)).

toggle_attrs(Opts0, Attrs) :-
    take_pwtf_opts(Opts0, Id, Visible, Disabled, _Required, _AutoComplete,
                    _NameAttrs, _ValueAttrs, _PlaceholderAttrs, _Rest),
    visible_word(Visible, VisibleWord),
    (   Disabled == true -> DisabledAttr = [disabled] ; DisabledAttr = [] ),
    append([ [type(button), aria_controls(Id)],
             % Pre-hydration inert (analysis doc's own pattern -- see
             % module header): assets/js/components/
             % password_toggle_field.js removes both on upgrade.
             [aria_hidden(true), tabindex(-1)],
             [data_visible(VisibleWord)],
             [class("px-password-toggle-field-toggle")],
             DisabledAttr
           ], Attrs).

toggle_children(Opts0, [accessible_icon([], IconGroup, Label)]) :-
    take_pwtf_opts(Opts0, _Id, Visible, _Disabled, _Required, _AutoComplete,
                    _NameAttrs, _ValueAttrs, _PlaceholderAttrs, _Rest),
    (   Visible == true -> Label = "Hide password" ; Label = "Show password" ),
    IconGroup = password_toggle_field_icon([]).

%!  password_toggle_field_icon(+Opts) is det.
%
%   Bare-call template surface: `password_toggle_field_icon([])`. No
%   children of its own -- always renders BOTH the eye and eye-off
%   glyphs as sibling spans; `assets/css/ui.css` shows exactly one at
%   a time, keyed off the Toggle's `data-visible` (deviation #3 --
%   see module header). `Opts` is currently unused (kept for shape
%   symmetry with every other part in this file, and so a future
%   caller-supplied icon override has somewhere to plug in).
px_template:render_helper(password_toggle_field_icon(_Opts), S) :-
    eye_svg(EyeSvg),
    eye_off_svg(EyeOffSvg),
    px_template:render(S,
      [ span(class("px-password-toggle-field-icon px-password-toggle-field-icon-show"),
             raw(EyeSvg)),
        span(class("px-password-toggle-field-icon px-password-toggle-field-icon-hide"),
             raw(EyeOffSvg))
      ]).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  password_toggle_field(+Opts) is det.
%
%   The common case: Root around one Input and one Toggle. UNLIKE
%   switch.pl's `switch/1` (pure structural delegation, no computation
%   needed), this cannot be a plain `~>`: Toggle's `aria-controls` must
%   name the SAME id as Input's `id`, and `take_pwtf_opts/10`'s own
%   per-call `gensym` fallback (used when the individual parts are
%   invoked directly, each independently defaulting an id) would mint
%   a DIFFERENT id for each of the three separate `take_pwtf_opts`
%   calls inside `password_toggle_field_root/2`,
%   `password_toggle_field_input/1` and `password_toggle_field_toggle/1`
%   if Opts carried no explicit `id(_)` at all -- silently breaking
%   `aria-controls` the moment a caller omits `id(_)`. So this
%   convenience resolves the id exactly ONCE (`resolve_id/2`, below)
%   and threads the result back in as an explicit `id(_)` before
%   delegating, guaranteeing every part agrees.
px_template:render_helper(password_toggle_field(Opts0), S) :-
    resolve_id(Opts0, Opts),
    px_template:render(S,
      password_toggle_field_root(Opts,
        [ password_toggle_field_input(Opts),
          password_toggle_field_toggle(Opts)
        ])).

%!  resolve_id(+Opts0, -Opts) is det.
%
%   Opts is Opts0 with `id(_)` pinned to a concrete value: whatever the
%   caller supplied, unchanged, or a fresh `gensym(px_password_toggle_field_, _)`
%   inserted when absent -- computed once, so every part fed the
%   resulting Opts resolves the identical id.
resolve_id(Opts0, [id(Id) | Rest]) :-
    (   selectchk(id(Id0), Opts0, Rest)
    ->  Id = Id0
    ;   gensym(px_password_toggle_field_, Id), Rest = Opts0
    ).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Password Toggle Field is analysis-doc item 16 ("small, isolated,
%   no shared-machinery"); 19 is the next free Order slot in
%   prolog/ui/*.pl's registry (highest currently registered is 18 --
%   context_menu/menubar/navigation_menu). Duplicate Order values are
%   already tolerated elsewhere (checkbox/switch both use 9) -- Order
%   only drives /ui's listing sort, never the contract.
px_ui:demo(password_toggle_field, 19, \password_toggle_field_demo).

%   Arity-0, so it is an ATOM -- called via the explicit \ escape, same
%   as every other component's demo template (a bare atom is a text
%   node, not a callable dispatch, in render/2 -- adr/0019).
password_toggle_field_demo ~>
    div(class("px-password-toggle-field-demo"),
      [ div(class("px-password-toggle-field-row"),
          [ password_toggle_field([id("pwtf-demo-default")]),
            p("visible(false) (default) -- type=\"password\", the eye \
icon shown, hidden accessible name \"Show password\". Click the \
button to reveal the typed text; click again to hide it.")
          ]),
        div(class("px-password-toggle-field-row"),
          [ password_toggle_field([id("pwtf-demo-visible"), visible(true),
                                    value("hunter2")]),
            p("visible(true) -- starts as type=\"text\" with a real \
value, eye-off icon shown, hidden accessible name \"Hide password\".")
          ]),
        div(class("px-password-toggle-field-row"),
          [ password_toggle_field([id("pwtf-demo-disabled"), disabled(true)]),
            p("disabled(true) -- both the input and the reveal button \
are disabled.")
          ]),

        h3("Form participation + auto-reset on submit"),
        p("Real name/value on a real native input, plus the one \
auto-hide behavior this component DOES have (analysis doc's own \
note): reveal it, then submit -- assets/js/components/ \
password_toggle_field.js resets type back to \"password\" on the \
form's native submit/reset events, so the browser never remembers a \
plaintext value."),
        form([method(get), action("/ui/password_toggle_field")],
          [ div(class("px-password-toggle-field-row"),
                [ label([for("pwtf-demo-form")], "Password"),
                  password_toggle_field([id("pwtf-demo-form"),
                                          name("password"), required(true)])
                ]),
            button([type(submit)], "Submit")
          ])
      ]).
