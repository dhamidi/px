:- module(ui_avatar, []).

:- use_module(library(lists)).
:- use_module('../px_template').

/** <module> ui/avatar -- Radix Avatar port (adr/0026, docs/radix-port-
    analysis.md "Avatar" entry).

Purpose: a user/entity avatar that shows a fallback (initials, an icon,
...) while its image loads or if it fails to load.

**Anatomy** (three parts, per the analysis doc): `Root` (`avatar_root/1,2`,
a `<px-avatar>` custom element -- see "Interactivity class" below),
`Image` (`avatar_image/1`, an `<img>`), `Fallback` (`avatar_fallback/1,2`,
a `<span>`). `avatar/4` is the rule-1 top-level convenience assembling
the common case. Radix's `Root` is plain context (scoping only,
mentioned in the analysis doc's Dependencies line) -- trivially replaced
here by rendering Image and Fallback as ordinary siblings under Root, no
context object needed.

**DOM/ARIA contract** (exactly the analysis doc's "Avatar" entry): none.
No `role`, no `aria-*`, anywhere. Upstream Radix does not even expose
`data-state` for this component ("unlike Progress ... load status is
purely internal").

**Contract note (rule 2 deviation, sanctioned by the analysis doc
itself).** This port DOES put `data-state="loading|loaded|error"` on
`Root` -- not because Radix exposes it (it explicitly doesn't), but
because the analysis doc's own "Interactivity class" paragraph
prescribes exactly this as the right-sized port: "a minimal custom
element ... toggling a `data-state="loading|loaded|error"` attribute
for CSS to key off is the right-sized port." `data-state` here is
therefore this port's chosen mechanism, not a literal transcription of
an upstream attribute -- assets/css/ui.css keys off it to hide the
Image on error and hide the Fallback once loaded.

**Interactivity class: CUSTOM-ELEMENT (small)**, per the analysis doc:
"no CSS-only equivalent exists -- there is no `:error`/`:broken`
pseudo-class and `:has()` cannot observe a failed image decode." The
server (this module) renders BOTH `Image` and `Fallback` unconditionally
(there is no way to know, at render time, whether the image will load);
`assets/js/components/avatar.js`'s `<px-avatar>` element watches the
real, already-in-DOM `<img>` for `load`/`error` and reflects the result
onto Root's `data-state`. Without JS, `Image` and `Fallback` are stacked
in the same CSS grid cell (assets/css/ui.css) with `Image` painted last
-- so for the common case (the image loads fine), the layering already
looks correct with zero JS: the opaque, successfully-decoded image
simply covers the fallback beneath it by paint order alone. JS is only
what additionally hides a BROKEN image's placeholder icon (the case
plain CSS genuinely cannot detect) and hides the fallback outright once
`data-state="loaded"` is confirmed (belt-and-braces for a
transparent/translucent avatar image, where the paint-order trick alone
would let the fallback show through).

**`delayMs` nuance** (analysis doc: "`Fallback` also supports a
`delayMs` to avoid flashing on fast loads"): `avatar_fallback/1,2`
accepts `delay_ms(N)` and renders it as `data-delay-ms="N"` on the
`<span>`; the custom element reads it and, ONLY when present, holds the
fallback `hidden` for `N` milliseconds after connecting (removed
regardless of outcome -- if the image already won by then,
`data-state="loaded"`'s CSS rule keeps the fallback hidden anyway). No
`delay_ms(_)` (the common case) means no JS-driven hold at all: the
fallback is visible from first paint, exactly the paint-order default
described above.

Options (a plain list, adr/0026 rule 1):

  avatar_root/1,2   state(loading|loaded|error)  initial data-state,
                     default `loading` (a caller with server-side
                     knowledge -- e.g. a previously-verified image URL
                     -- may start at `loaded` directly).
                     class(C)   merged with "px-avatar", default first.
                     anything else (id(...), data_*(...), ...) passed
                     through verbatim, appended after computed
                     attributes.

  avatar_image/1     class(C)   merged with "px-avatar-image".
                     anything else (src(...), alt(...), referrerpolicy(...),
                     loading(...), ...) passed straight through -- this
                     is close to a raw `<img>` attribute list.

  avatar_fallback/1,2  delay_ms(N)  -> data-delay-ms="N" (see above);
                        OMITTED entirely when absent or invalid (not a
                        non-negative integer) -- never leaks a raw
                        `delay_ms` attribute onto the `<span>`.
                        class(C)   merged with "px-avatar-fallback".
                        anything else passed through verbatim.

`avatar/4` (Opts, ImageOpts, FallbackOpts, FallbackChildren): the
top-level convenience. Four arguments, not the usual two, because
Avatar genuinely has two independently-configured child parts (Image's
`src`/`alt`/... vs Fallback's `delay_ms`/children) with nothing in
common to thread through automatically the way Progress threads
`value`/`max` to both its parts -- same reasoning aspect_ratio.pl and
progress.pl each give for their own convenience arity. `avatar_root/2`
and `avatar_fallback/1,2` remain directly callable for compositions that
don't fit the four-slot shape (e.g. a fallback-only avatar, which never
calls `avatar_image/1` at all -- see the demo below).
*/

                 /*******************************
                 *        OPTION HELPERS        *
                 *******************************/

%!  merge_class(+Opts0, +Default, -ClassVal, -Rest) is det.
%
%   ClassVal = Default, or "Default Caller" when Opts0 has class(Caller)
%   -- additive, never overwriting (adr/0026 rule 6). Rest is Opts0
%   minus any class(_) term.
merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Rest)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Rest = Opts0
    ).

%!  take_state(+Opts0, -State, -Rest) is det.
%
%   State = the value of state(S) in Opts0 when S is one of
%   loading/loaded/error, else `loading` (this port's default resting
%   state). Rest is Opts0 minus any state(_) term.
take_state(Opts0, State, Rest) :-
    (   selectchk(state(S), Opts0, Rest0),
        valid_state(S)
    ->  State = S, Rest = Rest0
    ;   Rest = Opts0, State = loading
    ).

valid_state(loading).
valid_state(loaded).
valid_state(error).

%!  take_delay_ms(+Opts0, -DelayAttrs, -Rest) is det.
%
%   DelayAttrs = [data_delay_ms(N)] when Opts0 has delay_ms(N) with N a
%   non-negative integer, else []. Rest is Opts0 minus any delay_ms(_)
%   term either way -- an invalid delay_ms(_) is dropped, never leaked
%   onto the rendered <span> as a raw (non-data-) attribute.
take_delay_ms(Opts0, DelayAttrs, Rest) :-
    (   selectchk(delay_ms(N), Opts0, Rest)
    ->  ( integer(N), N >= 0 -> DelayAttrs = [data_delay_ms(N)] ; DelayAttrs = [] )
    ;   Rest = Opts0, DelayAttrs = []
    ).

                 /*******************************
                 *             PARTS            *
                 *******************************/

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

%!  avatar_root(+Children) is det.
%!  avatar_root(+Opts, +Children) is det.
%
%   Bare-call template surface. Renders `<px-avatar ...>Children</px-avatar>`
%   via px_template:render_tag/4 -- `px-avatar` is not a whitelisted
%   HTML5 element (px_template.pl's html_element/1), the same reason
%   px_turbo.pl's turbo_frame/2 renders through render_tag/4 rather than
%   the element dispatch.
px_template:render_helper(avatar_root(Opts), S) :-
    px_template:render_helper(avatar_root(Opts, []), S).
px_template:render_helper(avatar_root(Opts, Children), S) :-
    avatar_root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_avatar, Attrs, Children).

avatar_root_attrs(Opts0, Attrs) :-
    take_state(Opts0, State, Opts1),
    merge_class(Opts1, "px-avatar", ClassVal, Opts2),
    Attrs = [class(ClassVal), data_state(State) | Opts2].

%!  avatar_image(+Opts) is det.
%
%   Bare-call template surface: `avatar_image([src(Url), alt("...")])`.
%   No children -- `<img>` is a void element (px_template.pl's
%   void_element/1).
px_template:render_helper(avatar_image(Opts), S) :-
    avatar_image_attrs(Opts, Attrs),
    px_template:render(S, img(Attrs)).

avatar_image_attrs(Opts0, Attrs) :-
    merge_class(Opts0, "px-avatar-image", ClassVal, Rest),
    Attrs = [class(ClassVal) | Rest].

%!  avatar_fallback(+Children) is det.
%!  avatar_fallback(+Opts, +Children) is det.
%
%   Bare-call template surface: `avatar_fallback([delay_ms(600)], "AB")`.
px_template:render_helper(avatar_fallback(Opts), S) :-
    px_template:render_helper(avatar_fallback(Opts, []), S).
px_template:render_helper(avatar_fallback(Opts, Children), S) :-
    avatar_fallback_attrs(Opts, Attrs),
    px_template:render(S, span(Attrs, Children)).

avatar_fallback_attrs(Opts0, Attrs) :-
    take_delay_ms(Opts0, DelayAttrs, Opts1),
    merge_class(Opts1, "px-avatar-fallback", ClassVal, Opts2),
    append([class(ClassVal)], DelayAttrs, Attrs0),
    append(Attrs0, Opts2, Attrs).

                 /*******************************
                 *   CONVENIENCE (adr/0026 #1)  *
                 *******************************/

%!  avatar(+Opts, +ImageOpts, +FallbackOpts, +FallbackChildren) is det.
%
%   The common case: Root wrapping Fallback then Image, in that DOM
%   order -- Fallback FIRST, Image SECOND. This is a deliberate
%   deviation (rule 2) from the analysis doc's anatomy listing order
%   (Image, then Fallback): both parts are always rendered here (unlike
%   upstream, which mounts only one at a time), and Image painting
%   AFTER Fallback in source order is exactly what makes the no-JS
%   grid-stacked layering correct for the common "image loads fine"
%   case (assets/css/ui.css) -- painting order, not `data-state`,
%   covers the fallback the instant the image has real pixels.
avatar(Opts, ImageOpts, FallbackOpts, FallbackChildren) ~>
    avatar_root(Opts,
      [ avatar_fallback(FallbackOpts, FallbackChildren),
        avatar_image(ImageOpts)
      ]).

                 /*******************************
                 *       KITCHEN-SINK DEMO       *
                 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Order 11: the analysis doc's recommended porting order places Avatar
%   in phase 4 ("first small CUSTOM-ELEMENT"), after the phase-1 statics
%   (orders 1-6) and phase-3 native-backed form controls; 11 leaves room
%   ahead for whichever of those lands with a lower number first.
%
%   A tiny (73-byte) solid-colour PNG, inlined as a data: URI, stands in
%   for "a real photo" -- no external asset, no network at render OR
%   demo-view time (adr/0003's vendoring discipline), and it decodes
%   instantly so the "loads fine" case is deterministic to look at.
px_ui:demo(avatar, 11, \avatar_demo).

avatar_demo ~>
    div(class("px-avatar-demo"),
      [ div(class("px-avatar-demo-row"),
          [ avatar([id("avatar-demo-working")],
                   [src("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEElEQVR4nGOI6rkDRwzEcQDTchwhUih1FwAAAABJRU5ErkJggg=="),
                    alt("Ada Lovelace")],
                   [],
                   "AL"),
            p("Working image -- src decodes fine; the custom element sets data-state=\"loaded\" and CSS hides the \"AL\" fallback behind it (already hidden from first paint by grid stacking + paint order alone, even before JS runs).")
          ]),
        div(class("px-avatar-demo-row"),
          [ avatar([id("avatar-demo-broken")],
                   [src("/assets/does-not-exist.png"), alt("Broken avatar")],
                   [],
                   "BS"),
            p("Broken src -- the image 404s; the custom element catches the error event and sets data-state=\"error\", which hides the broken-image icon so the \"BS\" fallback (visible underneath since first paint) is all that shows.")
          ]),
        div(class("px-avatar-demo-row"),
          [ avatar([id("avatar-demo-delay")],
                   [src("/assets/does-not-exist.png"), alt("Delayed fallback")],
                   [delay_ms(600)],
                   "DL"),
            p("Broken src + delay_ms(600) -- the \"DL\" fallback is held hidden for 600ms after connecting (data-delay-ms=\"600\" on the span) before being allowed to show, same as Radix's Fallback delayMs prop.")
          ]),
        div(class("px-avatar-demo-row"),
          [ avatar_root([id("avatar-demo-fallback-only")],
              avatar_fallback([], "FB")),
            p("Fallback-only -- avatar_root/2 wraps just avatar_fallback/2, no avatar_image/1 at all (no photo to show, ever). The custom element finds no <img>, sets data-state=\"error\" immediately, and the fallback (nothing else in the cell) shows by default.")
          ])
      ]).
