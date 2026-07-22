:- module(ui_toast, []).

%   No predicates are exported: toast/2, toast_viewport/2, toast_root/2,
%   toast_title/2, toast_description/2, toast_action/2 and
%   toast_close/2 are never called module-qualified -- they are term
%   SHAPES that px_template's bare-call dispatch resolves via the
%   multifile tmpl/2 / render_helper/2 tables (adr/0019), the same
%   pattern prolog/ui/dialog.pl uses.

/** <module> Toast (adr/0026): auto-dismissing notifications stacked in
a fixed-position viewport, dismissible early via a Close button,
paused while hovered/focused, with an F8 hotkey to reach the viewport
by keyboard.

Ported from Radix UI's Toast primitive (docs/radix-port-analysis.md,
"Toast" entry, port difficulty L). Upstream anatomy is `Provider` (no
DOM -- context only), `Viewport`, `Root`, `Title`, `Description`,
`Action`, `Close`.

**Provider is not ported (no template of its own), matching
prolog/ui/tooltip.pl's precedent.** Upstream's Provider exists to hand
every descendant Root/Viewport shared config (`duration`,
`swipeDirection`, `label`) through React context. There is no
client-side context here -- `toast_root/2`'s `duration(Ms)` and
`toast_viewport/2`'s `label(Label)` are just ordinary Opts with
sensible defaults (5000ms, "Notifications"), the same "Provider's job
is just defaults threaded through Opts" collapse tooltip.pl already
documents for its own missing Provider.

**Anatomy (this module's public template surface, six parts):**
`Viewport` (`toast_viewport/2`, the `<px-toast-viewport>` custom-element
wrapper around an `<ol>`), `Root` (`toast_root/2`, the `<px-toast>`
custom-element wrapper around an `<li>`), `Title` (`toast_title/2`, a
`<div>`), `Description` (`toast_description/2`, a `<div>`), `Action`
(`toast_action/2`, a `<button>`, requires `alt_text/1`), `Close`
(`toast_close/2`, a `<button>`). `toast/2` is the rule-1 top-level
convenience assembling one Root from optional Title/Description/Action
parts plus a default accessible Close, mirroring `dialog/2`'s division
of labour (this module's own `take_kids/4`/`take_close_kids/2` are
copied from that file almost verbatim).

**DOM/ARIA contract emitted** (docs/radix-port-analysis.md's "Toast"
entry, adr/0026 rule 2 -- sacred except where noted below):

    Viewport <ol id aria-label="{label} (F8)" role="region" tabindex="-1">
    Root     <li id role="status" tabindex="0" data-state="open|closed"
                  data-swipe-direction="up|down|left|right">
    Title       <div>
    Description <div>
    Action      <button>                (altText required, see below)
    Close       <button>

Three documented deviations from the analysis doc, all additive-only
simplifications made against the "irreducible behaviour only" bar
(adr/0026 rule 3), not oversights:

  1. **The live region is collapsed onto Viewport itself, with a fixed
     `aria-live="polite"`, instead of upstream's separate,
     freshly-created-per-announcement `document.body`-portaled node**
     (the analysis doc's own words: "a *separate*, freshly-created
     announce node... populated by walking the toast's DOM into an
     array of text strings... rendered after a double-
     `requestAnimationFrame` delay... a deliberate workaround for AT
     engines failing to announce updates to an already-populated live
     region"). That per-announcement-fresh-node dance exists to work
     around specific Safari/VoiceOver/NVDA bugs with STATIC live
     regions -- which is exactly what `toast_viewport/2`'s always-
     present `aria-live="polite"` region is. This is an honest,
     documented fidelity gap, not a claim of parity: on the affected
     AT engines a toast may occasionally go unannounced or announce
     late. Porting the real workaround (a timed node inserted and torn
     down per toast, off the visible DOM) is future work if a
     production app hits the bug; it is out of scope for one L-difficulty
     component port under adr/0026 rule 3's "irreducible only" bar.
  2. **`type(foreground|background)` is accepted on `toast_root/2` but
     does not vary `aria-live` or `role`** (upstream: `foreground` ->
     `assertive`, `background` -> `polite`; role is always `status`
     either way, upstream's own explicit choice -- "Radix explicitly
     avoids `role="alert"` ... citing SR stuttering issues," kept
     as-is here, always `role="status"`, never `role="alert"`, matching
     the analysis doc exactly). Because deviation 1 already fixes the
     live region at the viewport level, there is nowhere left for a
     per-toast `assertive` override to attach without a second,
     independent live region per urgent toast -- not implemented here.
     `type/1` is still surfaced (emitted as `data-type`) because it is
     a legitimate, real Opts key even without the aria-live payoff:
     a caller's own CSS can key visual severity (info/error/etc.) off
     `[data-type]`, and keeping the option means a later live-region
     fix only has to change this module, not every call site.
  3. **Swipe-to-dismiss is NOT implemented.** `data-swipe-direction`
     is emitted (static, from the `swipe_direction/1` Opts key,
     default `right`) exactly as the analysis doc's contract requires,
     but no pointer-capture drag math backs it -- `data-swipe` (the
     `start|move|cancel|end` gesture-progress attribute) and the
     swipe-offset CSS custom properties are never written, because
     nothing ever starts a swipe. This is a deliberate, documented
     deferral (adr/0026 rule 3's own bar: "a custom element is only
     justified for behavior the platform cannot express" -- true here,
     but the corollary this module leans on is "and an honest deferral
     note beats a half-working gesture reimplementation shipped under
     time pressure"). The Close button and F8-reachable viewport are
     the keyboard/non-pointer dismiss paths that remain fully
     functional regardless; nothing about swipe's absence blocks any
     other documented behaviour.

**Interactivity class: CUSTOM-ELEMENT (two coordinating pieces --
`assets/js/components/toast.js`'s `<px-toast-viewport>` and
`<px-toast>`, docs/radix-port-analysis.md's own verdict).**
`toast_viewport/2` and `toast_root/2` already render the full, correct
static contract with zero JS -- an `<ol>` region and `<li>` items with
every ARIA/data attribute above. What the two custom elements add
(see that file's own header for the exact mechanism of each):

  1. `<px-toast-viewport>`: the F8 hotkey (focuses the `<ol>`, toggles
     back to the previously-focused element on a second press --
     upstream's own behaviour).
  2. `<px-toast>`: the `duration`-driven auto-dismiss timer (read off
     `data-duration`, in ms; `0` means "never auto-dismiss" -- an
     additive, documented convention replacing upstream's `Infinity`,
     which has no clean HTML attribute encoding), pause-on-hover/focus
     with elapsed-time-subtraction resume (not a hard reset -- matches
     the analysis doc's own "recompute remaining time by elapsed-time
     subtraction" description), the Close button, and DOM removal
     after the `data-state="closed"` exit transition.

**Dependencies**: none from this library -- no roving-focus, no
popper, no menu engine. `visually_hidden/2` (prolog/ui/visually_hidden.pl)
for the default Close button's accessible name, same as `dialog/2`.

**The prologex-native angle -- zero-machinery server-driven toasts.**
Because a toast is nothing but a server-rendered `<li>` inside a
viewport with a well-known DOM id, any handler anywhere in an app can
show one with a single Turbo Stream `prepend` action (adr/0024) --
no client-side store, no fetch call, no separate "toast API": the
exact same `render/2` templates this module already defines. This is
why `toast_viewport/2` defaults its `id(Id)` to the literal atom
`toast_viewport` (rendered as `id="toast_viewport"`) rather than a
gensym -- a predictable, well-known id is the whole point, exactly
mirroring adr/0024's own frame-id-serialization convention (an atom
serializes as itself). A handler wanting to flash a notification after
any other response simply adds one action:

    create(Env0, Env) :-
        ..., % do the real work
        turbo_stream(Env0,
            [ prepend(toast_viewport,
                      toast([duration(4000)],
                            [ toast_title([], "Saved"),
                              toast_description([], "Your changes were saved.")
                            ]))
            ], Env).

Turbo prepends the rendered `<li>` into `<ol id="toast_viewport">`; the
moment it lands in the DOM, `<px-toast>`'s `connectedCallback` runs
(custom elements upgrade on connection regardless of how they arrived
-- Turbo stream, a page load, or client-side `Node.cloneNode`/`append`
alike) and the duration timer, pause-on-hover and Close button all work
immediately, with no extra wiring. `px_ui:demo(toast, ...)` below
demonstrates both the click-triggered client-side path (a "Show toast"
button and a `<template>` clone, no server round-trip at all) and this
exact server pattern (prose plus the code snippet above, verbatim).

Options (a plain list, adr/0026 rule 1):

  `toast_viewport/2` Opts:
    id(Id)          default the atom `toast_viewport` (see "prologex-
                    native angle" above -- deliberately NOT gensym'd;
                    override only if an app legitimately needs more
                    than one viewport).
    label(Label)    default `"Notifications"`. Feeds `aria-label`,
                    rendered as `"{Label} (F8)"` -- upstream's own
                    convention of naming the hotkey in the accessible
                    name.
    class(C), anything else  merged/passed through onto the `<ol>`,
                    same convention as every other part in this
                    library.

  `toast_root/2` Opts:
    id(Id)          default a fresh gensym'd `px-toast-N`.
    open(Bool)      default `true` -- unlike Dialog's Trigger-driven
                    default-closed, a toast being rendered at all
                    already means "show it"; drives `data-state`
                    (open|closed).
    duration(Ms)    default `5000` (Radix's own default). `0` disables
                    auto-dismiss (see "Interactivity class" above for
                    why `0`, not `Infinity`). Emitted as `data-duration`
                    for `assets/js/components/toast.js` to read; purely
                    inert without that element loaded (a toast with no
                    JS just stays visible until removed by hand or a
                    future re-render, the honest no-JS degrade).
    type(Type)      default `foreground`. `oneof([foreground,
                    background])`. Emitted as `data-type` (see
                    deviation 2 above for what it does NOT do).
    swipe_direction(Dir)  default `right`. `oneof([up,down,left,right])`.
                    Emitted as `data-swipe-direction` (see deviation 3
                    -- static only, no gesture behind it).
    class(C), anything else  merged/passed through onto the `<li>`.

  `toast_title/2` / `toast_description/2` Opts:
    class(C), anything else  merged/passed through -- no computed
                    attributes, matching the analysis doc's "plain
                    divs".

  `toast_action/2` Opts:
    alt_text(Text)  REQUIRED -- an `existence_error(option, alt_text)`
                    is thrown if absent, turning upstream's dev-time
                    console warning ("Missing `altText` prop") into a
                    hard contract violation, the same "Prolog favours
                    explicit over silently-degraded" posture
                    `require_opt/4` already enforces for `tabs.pl`'s
                    `value(_)` and `accordion.pl`'s `type(_)`. Emitted
                    as `data-alt-text` -- captured for a future
                    announce-mechanism fix (deviation 1 above) but not
                    yet read by anything; still required now so every
                    call site is already compliant the day that lands.
    class(C), anything else  merged/passed through onto the `<button>`.

  `toast_close/2` Opts:
    class(C), anything else  merged/passed through. `data-toast-close`
                    (additive JS-hook marker, `assets/js/components/
                    toast.js`'s click-to-close query target, same
                    rationale as `dialog_close/2`'s `data-dialog-close`)
                    is always emitted.

  `toast/2` Opts:
    title(Kids)     optional; renders a `toast_title/2`.
    description(Kids)  optional; renders a `toast_description/2`.
    action(AltText-Kids)  optional; a `Key-Value`-shaped pair (the same
                    shape adr/0016's env-relations already use for
                    header pairs) -- `action("Undo the change" -
                    "Undo")` renders `toast_action([alt_text("Undo the
                    change")], "Undo")`.
    close(Kids)     optional, opt-OUT like `dialog/2`'s: default is an
                    accessible "x" glyph + `visually_hidden([],
                    "Close")` pair; `close(none)` suppresses the button
                    entirely; any other `Kids` overrides its content.
    id(Id), open(Bool), duration(Ms), type(Type), swipe_direction(Dir),
    class(C), anything else  forwarded to `toast_root/2` verbatim.

  `toast/2` second argument: BodyChildren -- arbitrary extra template
                    children rendered after Close/Title/Description/
                    Action, same "flat convenience, compose the parts
                    by hand for anything richer" contract as `dialog/2`.

Every part and `toast/2` are registered as `px_template:render_helper/2`
hooks (adr/0019), same reason `dialog.pl`/`tabs.pl` register theirs the
same way.
*/

:- use_module(library(lists)).
:- use_module(library(gensym)).
:- use_module('../px_template').
:- use_module(visually_hidden, []).

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

		 /*******************************
		 *        OPTION HELPERS        *
		 *******************************/

%!  take_bool(+Name, +Default, +Opts0, -Value, -Rest) is det.
%
%   Same shape as dialog.pl's own take_bool/5.
take_bool(Name, Default, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Rest)
    ->  ( V0 == true -> Value = true ; Value = false )
    ;   Value = Default, Rest = Opts0
    ).

%!  merge_class(+Opts0, +Default, -ClassVal, -Rest) is det.
%
%   Same helper as every other port in this library.
merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

state_atom(true,  open)   :- !.
state_atom(false, closed).

%!  require_opt(+Opts, +Key, +Context, -Value) is det.
%
%   Same helper as tabs.pl's/toggle_group.pl's/accordion.pl's own
%   require_opt/4: reads Key(Value) out of Opts, or throws a clear
%   existence_error naming both the missing option and the template
%   that needed it.
require_opt(Opts, Key, Context, Value) :-
    Probe =.. [Key, Value],
    (   memberchk(Probe, Opts)
    ->  true
    ;   throw(error(existence_error(option, Key), context(Context, _)))
    ).

%!  take_id(+Default, +Opts0, -Id, -Rest) is det.
take_id(Default, Opts0, Id, Rest) :-
    (   selectchk(id(Id0), Opts0, Rest)
    ->  Id = Id0
    ;   Id = Default, Rest = Opts0
    ).

%!  take_id_gensym(+Prefix, +Opts0, -Id, -Rest) is det.
take_id_gensym(Prefix, Opts0, Id, Rest) :-
    (   selectchk(id(Id0), Opts0, Rest)
    ->  Id = Id0
    ;   Rest = Opts0, gensym(Prefix, Id)
    ).

valid_type(foreground).
valid_type(background).

%!  take_type(+Opts0, -Type, -Rest) is det.
take_type(Opts0, Type, Rest) :-
    (   selectchk(type(Type0), Opts0, Rest)
    ->  ( valid_type(Type0)
        -> Type = Type0
        ;  throw(error(domain_error(toast_type, Type0), context(take_type/3, _)))
        )
    ;   Type = foreground, Rest = Opts0
    ).

valid_swipe_direction(up).
valid_swipe_direction(down).
valid_swipe_direction(left).
valid_swipe_direction(right).

%!  take_swipe_direction(+Opts0, -Dir, -Rest) is det.
take_swipe_direction(Opts0, Dir, Rest) :-
    (   selectchk(swipe_direction(Dir0), Opts0, Rest)
    ->  ( valid_swipe_direction(Dir0)
        -> Dir = Dir0
        ;  throw(error(domain_error(toast_swipe_direction, Dir0),
                        context(take_swipe_direction/3, _)))
        )
    ;   Dir = right, Rest = Opts0
    ).

%!  take_duration(+Opts0, -Ms, -Rest) is det.
%
%   `0` disables auto-dismiss (see module header, deviation/Opts docs
%   for why not `Infinity`).
take_duration(Opts0, Ms, Rest) :-
    (   selectchk(duration(Ms0), Opts0, Rest)
    ->  must_be(nonneg, Ms0), Ms = Ms0
    ;   Ms = 5000, Rest = Opts0
    ).

%!  take_label(+Opts0, -Label, -Rest) is det.
take_label(Opts0, Label, Rest) :-
    (   selectchk(label(Label0), Opts0, Rest)
    ->  Label = Label0
    ;   Label = "Notifications", Rest = Opts0
    ).

%!  take_kids(+Name, +Opts0, -Opt, -Rest) is det.
%
%   Same helper as dialog.pl's own take_kids/4.
take_kids(Name, Opts0, Opt, Rest) :-
    Probe =.. [Name, Kids],
    (   selectchk(Probe, Opts0, Rest)
    ->  Opt =.. [Name, Kids]
    ;   Opt = none, Rest = Opts0
    ).

%!  take_action_kids(+Opts0, -ActionOpt, -Rest) is det.
%
%   `action(AltText-Kids)` -- see module header's `toast/2` Opts docs.
take_action_kids(Opts0, ActionOpt, Rest) :-
    (   selectchk(action(AltText-Kids), Opts0, Rest)
    ->  ActionOpt = action(AltText, Kids)
    ;   ActionOpt = none, Rest = Opts0
    ).

%!  take_close_kids(+Opts0, -CloseOpt, -Rest) is det.
%
%   Same opt-OUT default as dialog.pl's own take_close_kids/3.
take_close_kids(Opts0, CloseOpt, Rest) :-
    (   selectchk(close(Kids), Opts0, Rest)
    ->  ( Kids == none -> CloseOpt = none ; CloseOpt = close(Kids) )
    ;   Rest = Opts0,
        CloseOpt = close([ span([aria_hidden(true)], "×"),
                            visually_hidden([], "Close")
                          ])
    ).

		 /*******************************
		 *           VIEWPORT           *
		 *******************************/

%!  toast_viewport(+Opts, +Children) is det.
%
%   Bare-call template surface: `toast_viewport([], [ToastA, ToastB])`.
%   Renders the `<px-toast-viewport>` custom-element wrapper (adr/0026
%   rule 4) around a plain `<ol>` -- without `assets/js/components/
%   toast.js` loaded, every already-rendered toast is fully visible and
%   its Close button works (a plain `<button>`, no JS needed for
%   dismiss-by-removal-from-DOM... except DOM removal itself IS this
%   element's job -- see that file's header); only F8-focus and
%   auto-dismiss timers are inert without JS, the documented no-JS
%   degrade.
px_template:render_helper(toast_viewport(Opts, Children), S) :-
    viewport_attrs(Opts, Attrs),
    px_template:render_tag(S, px_toast_viewport, [], [ol(Attrs, Children)]).

viewport_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_id(toast_viewport, Opts0, Id, Opts1),
    take_label(Opts1, Label, Opts2),
    merge_class(Opts2, "px-toast-viewport", ClassVal, Opts3),
    format(atom(AriaLabel), '~w (F8)', [Label]),
    append([ [ id(Id), role(region), aria_label(AriaLabel),
               aria_live(polite), tabindex(-1), class(ClassVal)
             ],
             Opts3
           ], Attrs).

		 /*******************************
		 *             ROOT             *
		 *******************************/

%!  toast_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `toast_root([duration(4000)], [...])`.
px_template:render_helper(toast_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_toast, [], [li(Attrs, Children)]).

root_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_id_gensym('px-toast-', Opts0, Id, Opts1),
    take_bool(open, true, Opts1, Open, Opts2),
    take_duration(Opts2, Duration, Opts3),
    take_type(Opts3, Type, Opts4),
    take_swipe_direction(Opts4, SwipeDir, Opts5),
    merge_class(Opts5, "px-toast", ClassVal, Opts6),
    state_atom(Open, State),
    append([ [ id(Id), role(status), tabindex(0),
               data_state(State), data_swipe_direction(SwipeDir),
               data_type(Type), data_duration(Duration),
               class(ClassVal)
             ],
             Opts6
           ], Attrs).

		 /*******************************
		 *             TITLE            *
		 *******************************/

%!  toast_title(+Opts, +Children) is det.
px_template:render_helper(toast_title(Opts, Children), S) :-
    must_be(list, Opts),
    merge_class(Opts, "px-toast-title", ClassVal, Opts1),
    append([class(ClassVal)], Opts1, Attrs),
    px_template:render(S, div(Attrs, Children)).

		 /*******************************
		 *          DESCRIPTION         *
		 *******************************/

%!  toast_description(+Opts, +Children) is det.
px_template:render_helper(toast_description(Opts, Children), S) :-
    must_be(list, Opts),
    merge_class(Opts, "px-toast-description", ClassVal, Opts1),
    append([class(ClassVal)], Opts1, Attrs),
    px_template:render(S, div(Attrs, Children)).

		 /*******************************
		 *             ACTION           *
		 *******************************/

%!  toast_action(+Opts, +Children) is det.
%
%   `alt_text(Text)` is REQUIRED -- see module header. Bare-call
%   template surface: `toast_action([alt_text("Undo the change")],
%   "Undo")`.
px_template:render_helper(toast_action(Opts0, Children), S) :-
    must_be(list, Opts0),
    require_opt(Opts0, alt_text, toast_action/2, AltText),
    selectchk(alt_text(AltText), Opts0, Opts1),
    merge_class(Opts1, "px-toast-action", ClassVal, Opts2),
    append([ [type(button), data_alt_text(AltText), class(ClassVal)], Opts2 ],
           Attrs),
    px_template:render(S, button(Attrs, Children)).

		 /*******************************
		 *             CLOSE            *
		 *******************************/

%!  toast_close(+Opts, +Children) is det.
px_template:render_helper(toast_close(Opts, Children), S) :-
    must_be(list, Opts),
    merge_class(Opts, "px-toast-close", ClassVal, Opts1),
    append([ [type(button), data_toast_close(""), class(ClassVal)], Opts1 ],
           Attrs),
    px_template:render(S, button(Attrs, Children)).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  toast(+Opts, +BodyChildren) is det.
%
%   The common case: one Root assembled from an optional Title/
%   Description/Action plus a default accessible Close, plus
%   BodyChildren. See the module header for the full Opts list.
toast(Opts, BodyChildren) ~> \toast_render(Opts, BodyChildren).

px_template:render_helper(toast_render(Opts0, BodyChildren), S) :-
    must_be(list, Opts0),
    take_kids(title, Opts0, TitleOpt, Opts1),
    take_kids(description, Opts1, DescriptionOpt, Opts2),
    take_action_kids(Opts2, ActionOpt, Opts3),
    take_close_kids(Opts3, CloseOpt, RootOpts),

    ( TitleOpt = title(TitleKids)
    ->  TitleCall = [toast_title([], TitleKids)]
    ;   TitleCall = []
    ),
    ( DescriptionOpt = description(DescKids)
    ->  DescCall = [toast_description([], DescKids)]
    ;   DescCall = []
    ),
    ( ActionOpt = action(AltText, ActionKids)
    ->  ActionCall = [toast_action([alt_text(AltText)], ActionKids)]
    ;   ActionCall = []
    ),
    ( CloseOpt = close(CloseKids)
    ->  CloseCall = [toast_close([], CloseKids)]
    ;   CloseCall = []
    ),

    RootChildren = [CloseCall, TitleCall, DescCall, ActionCall, BodyChildren],
    px_template:render(S, toast_root(RootOpts, RootChildren)).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%!  turbo_stream_snippet_text(-S) is det.
%
%   The verbatim turbo_stream/3 code sample quoted in the module
%   header's "prologex-native angle" section -- built via
%   atomics_to_string/3 (one line per list element) rather than a
%   single string literal with `\<newline>` continuations, which
%   SWI-Prolog deprecates when mixed with an explicit `\n`.
turbo_stream_snippet_text(S) :-
    atomics_to_string(
        [ "create(Env0, Env) :-",
          "    ..., % do the real work",
          "    turbo_stream(Env0,",
          "        [ prepend(toast_viewport,",
          "                  toast([duration(4000)],",
          "                        [ toast_title([], \"Saved\"),",
          "                          toast_description([], \"Your changes were saved.\")",
          "                        ]))",
          "        ], Env)."
        ], "\n", S).

%   `\turbo_stream_snippet` (arity-0, adr/0019's escape-call dispatch)
%   inside the demo's `pre(code(...))` below -- the snippet is
%   rendered as ordinary escaped text (NOT raw/1: it is a code SAMPLE,
%   meant to display its own `<`/`>`/quote characters literally in the
%   browser, exactly like every other `<pre><code>` block, not to
%   execute as markup).
px_template:render_helper(turbo_stream_snippet, S) :-
    turbo_stream_snippet_text(Text),
    px_template:render(S, Text).

%   Order 20: past the current highest slot in use (otp_field.pl /
%   password_toggle_field.pl both claim 19) -- adr/0026 rule 8 places
%   Toast independent of the menu/overlay track ("can run in parallel
%   with phases 9-13"), so there is no dependency ordering to respect
%   here, only avoiding a collision with whatever else has landed.
px_ui:demo(toast, 20, \toast_demo).

%   `\toast_demo`, not the bare atom -- adr/0019's arity-0 dispatch
%   rule, same as every other component's demo template.
%
%   Three pieces, in order: (1) two persistent (duration(0)) toasts
%   rendered directly in the viewport at page load -- a static visual
%   baseline plus everything test/ui/css_coverage.pl needs to see
%   reachable; (2) a "Show toast" button plus a hidden <template>,
%   wired by a small inline module script (no server round-trip at
%   all -- demonstrating that ANY DOM insertion, not just a Turbo
%   Stream, upgrades into a fully-live toast the instant it connects);
%   (3) prose plus a verbatim code snippet demonstrating the
%   turbo_stream server pattern from the module header's "prologex-
%   native angle" section.
toast_demo ~>
    div(class("px-toast-demo"),
      [ h3("Viewport -- two persistent toasts (duration(0), never auto-dismiss)"),
        p("A viewport is a fixed-position region (bottom-right here, \
CSS-configurable) holding a stack of <li> toasts. These two are \
rendered directly by the server with duration(0) so they stay put for \
inspection; ordinary toasts default to a 5000ms auto-dismiss timer \
that pauses while hovered or focused (assets/js/components/toast.js) \
and resumes for exactly the remaining time on pointer-leave/blur."),
        toast_viewport([],
          [ toast([id("toast-demo-baseline-1"), duration(0), type(foreground)],
              [ toast_title([], "Update available"),
                toast_description([], "A new version of the app is ready to install.")
              ]),
            toast([id("toast-demo-baseline-2"), duration(0), type(background),
                   action("Undo the password change" - "Undo")],
              [ toast_title([], "Password changed"),
                toast_description([], "Your password was updated successfully.")
              ])
          ]),

        h3("Client-side trigger -- no server round-trip"),
        p("Clicking the button below clones a hidden <template>'s \
toast markup and prepends it straight into the viewport's <ol> with \
plain DOM APIs. The moment the clone lands in the DOM, <px-toast>'s \
own connectedCallback runs -- custom elements upgrade on connection \
regardless of how they arrived -- so its duration timer, pause-on-\
hover/focus, and Close button all work immediately with zero extra \
wiring. Hover it before its timer elapses to see the pause affordance \
(a highlighted border) keep it alive past its nominal duration."),
        button([type(button), class("px-toast-demo-trigger"),
                data_toast_demo_trigger("")],
          "Show toast"),
        template([id("toast-demo-template")],
          toast([duration(4000)],
            [ toast_title([], "Profile updated"),
              toast_description([], "Your changes have been saved.")
            ])),
        script([type(module)], raw("
document.addEventListener('click', function (event) {
  var trigger = event.target.closest('[data-toast-demo-trigger]');
  if (!trigger) return;
  var tpl = document.getElementById('toast-demo-template');
  var viewport = document.getElementById('toast_viewport');
  if (!tpl || !viewport) return;
  viewport.prepend(tpl.content.cloneNode(true));
});
")),

        h3("The prologex-native angle -- server-driven toasts need no client API"),
        p("Because a toast is just a server-rendered <li> inside a \
viewport with a well-known id (\"toast_viewport\" by default), any \
handler anywhere in an app can show one with a single Turbo Stream \
prepend action (adr/0024) -- no client-side store, no fetch call, no \
separate \"toast API\" to learn. This is the same render/2 templates \
this page already used above, reused as a targeted stream delivery:"),
        pre(code(\turbo_stream_snippet)),
        p("Turbo prepends the rendered <li> into <ol id=\"toast_viewport\">; \
<px-toast>'s connectedCallback runs on connection exactly as it did \
for the client-side clone above -- same timer, same pause-on-hover, \
same Close button, zero additional code. This is the framework's own \
flash-message story: no controller-level flash bag, no session-backed \
message queue, just an ordinary handler response.")
      ]).
