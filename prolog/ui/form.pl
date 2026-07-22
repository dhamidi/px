:- module(ui_form, []).

%   No predicates are exported: form_root/2, form_field/2, form_label/2,
%   form_control/1,2, form_message/2, form_submit/2 are never called
%   module-qualified -- bare-call dispatch through px_template's
%   tmpl/2 / render_helper/2 tables (adr/0019) resolves them, the same
%   pattern every other prolog/ui/*.pl module uses.

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module('../px_template').

/** <module> Form (adr/0026): Field/Label/Control/Message anatomy
    surfacing the native Constraint Validation API (`ValidityState`) as
    a declarative, styleable data-attribute contract.

Ported from Radix UI's Form primitive (docs/radix-port-analysis.md,
"Form" entry). Upstream anatomy: `Root` (`<form>`), `Field` (context:
name/id/serverInvalid), `Label` (wraps the Label primitive), `Control`
(`<input>` by default), `Message` (a `<span>`), `ValidityState`
(render-prop only, no DOM), `Submit`.

**Interactivity class: NATIVE-dominant** -- the analysis doc's own
verdict, "by far the thinnest JS layer in the complex-widget batch":
`required`, `pattern`, `type=email`, `min`/`max`, `element.validity`
and the rest of the Constraint Validation API do the overwhelming
majority of the work with zero JS; the only genuinely needed JS is
re-validating on blur/submit, toggling `data-valid`/`data-invalid`,
and maintaining `aria-describedby` as messages become relevant --
`assets/js/components/form.js`'s entire job.

**Relationship to prolog/px_form.pl (adr/0023) -- READ THIS FIRST.**
prologex already ships a *server-side* forms subsystem: `:- form/2`
declares fields/widgets/constraints once, `form_validate/3` runs pure
declaration -> validation -> `ok(Values)` | `invalid(Values, Errors)`,
and `form_for/4` / `field_input/4` (px_template render_helper/2 hooks,
same mechanism this module uses) render the whole round trip --
declare, validate, 422-re-render-with-errors. This module does NOT
replace, wrap, or modify any of that (px_form.pl is untouched by this
port). Instead it is the *client-side complement*: where px_form's
answer to invalidity is "the next full page the server sends back",
ui/form's answer is "surface the browser's own `ValidityState` to the
user *before* that round trip even happens" -- pre-submit, zero
network, using the exact same native constraint attributes
(`required`, `type=email`, `pattern`, `minlength`, ...) px_form's own
`widget_input/6` already writes on every field it renders. The two are
designed to compose, not choose between:

  - **Hand-written forms** use ui/form's parts directly, the way this
    module's own kitchen-sink demo does: `form_root` wraps a plain
    `<form>`, `form_field` groups one `form_label` + `form_control` +
    zero or more `form_message`s per field, `form_submit` closes it.
    No px_form declaration involved at all.

  - **px_form-rendered forms** can opt into ui/form's client-side
    messaging around the SAME markup px_form emits, because every part
    here accepts pass-through options: give `form_field` the same
    `id(Id)` px_form's own `field_dom_id/3` would generate
    (`atomic_list_concat([FormName, '_', Field], Id)`) and its
    `form_control` accepts a `value(V)` the way px_form's
    `field_value/4` already computes one; give `form_field` an
    `invalid(true)` opt when `Errors` (px_form's `invalid(Values,
    Errors)` result) carries an `error(Field, Msg)` for it, and put
    that very `Msg` inside a `form_message([forced(true)], Msg)` --
    the server truth from a 422 response, rendered immediately, no JS
    required, and (per the `forced` contract below) never touched by
    the client-side matcher loop that governs every other Message.
    This module never reads `px_form:form_definition/3` or calls
    `form_validate/3` itself -- the composition is at the markup
    level, by design, so ui/form has zero coupling to px_form's
    declaration/validation internals and stays equally usable without
    them.

DOM/ARIA contract emitted (the analysis doc's "Form" entry, followed
exactly except where noted):

    Field, Label, Control:  `data-valid` / `data-invalid` -- present-
              or-omitted (never `"false"`), computed identically on
              all three from one shared tri-state per field: `none`
              (no `invalid(_)` opt given at render time -- deferred
              entirely to the client, so a freshly-rendered,
              not-yet-interacted-with field shows neither attribute,
              matching the CDP acceptance criterion "submit empty ->
              messages/data-invalid appear", i.e. NOT already present
              before that first interaction), or the boolean truth of
              an explicit `invalid(Bool)` opt (px_form's 422 escape
              hatch). `assets/js/components/form.js` extends this same
              two-attribute toggle to genuine client-side/native
              invalidity after the first blur or submit.
    Control only:  `aria-invalid="true"`, and ONLY when the field's
              `invalid(_)` opt is `true` -- **local/native invalidity
              is deliberately NOT mirrored to `aria-invalid`, only
              server-side invalidity is**, exactly the analysis doc's
              own line ("aria-invalid={serverInvalid || undefined}").
              `assets/js/components/form.js` therefore never touches
              `aria-invalid` at all; it is pure server truth, sticky
              until the next server render. Also: `title=""`,
              explicitly disabling the native validation-bubble
              tooltip (Control's default title is always the empty
              string unless a caller supplies its own).
    Control only:  `aria-describedby` -- every Message id declared
              under the same Field, space-joined, deduplicated against
              any caller-supplied `aria_describedby(_)` value. Built
              at render time (`form_field/2` scans its own Children
              for `form_message(_,_)` terms before rendering any of
              them -- same "inspect a concrete Prolog list before
              rendering" technique prolog/ui/checkbox.pl's
              `checkbox_render/2` uses for Presence-gating).
    Message:  `data-match` (kebab-case: "value-missing", "type-
              mismatch", ... -- one per native `ValidityState` boolean
              key, see `match_key/2`), absent when no `match(_)` opt is
              given (matches ANY invalidity, Radix's own no-`match`
              default). `hidden` (the native boolean attribute) is
              present at render time UNLESS `forced(true)` was given --
              this is this port's DELIBERATE, DOCUMENTED substitution
              for Radix's real behavior (a Message that fails to match
              is simply never mounted in the React tree at all): a
              `hidden` element is excluded from the accessibility tree
              exactly like an unmounted one, so `aria-describedby`
              pointing at a `hidden` Message is already inert -- the
              same effect, achieved with a platform primitive instead
              of a client-side mount/unmount decision, so the initial
              HTML for a Field with messages is fully present (crawl/
              no-JS-friendly) without any of them being visible. NO
              `role="alert"` anywhere (upstream's own choice, kept
              verbatim) -- accessibility relies purely on
              `aria-describedby`, never live-region announcement.
              `data-forced=""` is ADDITIVE (not in the analysis text):
              marks a `forced(true)` Message so
              assets/js/components/form.js's blur/submit loop skips it
              outright, leaving the server's own error text
              undisturbed by any client-side (re)validation outcome --
              without this marker a field that happens to pass native
              constraint validation (e.g. a syntactically well-formed
              but server-side-taken username) would have its own JS
              silently hide the real error the moment the user blurs
              the control, which is worse than not validating at all.

**`Root` renders `<form novalidate>` -- deviation from upstream, per
this port's explicit brief, documented here as instructed.** Radix's
own `Root` does NOT set `novalidate`; it leaves native interactive
validation switched on and relies on the native `invalid` event firing
per control at submit time (suppressing each one's default bubble UI
with `preventDefault()` in an `onInvalid` handler) as its trigger to
re-validate. This port instead sets `novalidate` unconditionally and
lets `assets/js/components/form.js` own validation outright by calling
`control.checkValidity()` directly -- on blur (`focusout`, which
bubbles; native `blur` does not) and again over every control on
`submit`, `preventDefault()`-ing the submission itself when any
control fails. This is simpler (no per-control `invalid` listener
wiring, no fighting the native bubble UI method by method) and,
because `checkValidity()`/`element.validity` are plain, always-
callable JS methods regardless of `novalidate`, loses nothing: the
same native `ValidityState` is still the single source of truth,
`novalidate` only turns off the browser's own *automatic* trigger for
consulting it. The one real cost, also documented here rather than
silently absorbed: **without JS, `novalidate` means NO client-side
validation happens at all** -- an empty required field submits
straight through, with no native bubble either (which `novalidate`
suppresses regardless of whether this element's own JS ever loads).
That is an accepted, deliberate trade for this codebase specifically,
because prolog/px_form.pl (adr/0023) is always the real safety net --
every field this module can render already carries the native
constraint attributes (`required`, `type=email`, ...) px_form's own
widgets emit, so server-side validation never depended on the client
running JS correctly in the first place; ui/form's JS is a pure
progressive enhancement of the pre-submit UX, never the last line of
defense.

**`ValidityState` is intentionally NOT ported.** Upstream's is a
render-prop with no DOM output at all -- a pure React mechanism for
handing a live `ValidityState` object down to arbitrary consumer JSX.
There is no server-render analog for "hand a live JS object to
whatever markup a caller writes next": this port's state already lives
entirely in DOM attributes (`data-valid`/`data-invalid` on Field/
Label/Control, `hidden`/`data-match` on Message), mutated in place by
assets/js/components/form.js -- adr/0026 rule 4's "state lives in DOM
attributes ... never a parallel JS store" -- so there is nothing left
for a separate render-prop part to expose that the data-attribute
contract does not already surface declaratively. Skipped, not
forgotten.

Naming (deviation from adr/0026 rule 1, noted per that rule, same
shadowing prolog/ui/label.pl's header documents): `form` is itself a
whitelisted HTML5 element functor (prolog/px_template.pl's
`html_element/1`), so a top-level convenience template literally named
`form/2` is impossible -- `expand_template/3` resolves bare calls
element-first and throws a permission_error rather than let a template
shadow an element name. Exactly like Label, Form's Root part therefore
doubles as the module's only top-level entry point: `form_root/2` IS
what a caller reaches for, there is no separate `form(Opts, Parts)`.
(`field` is NOT a reserved element name, so `form_field/2` needed no
such workaround.)

Every part below is registered as a px_template:render_helper/2 hook
(adr/0019) rather than a plain `~>` clause -- the Opts-list defaults/
merge/id-generation/Children-rewriting logic is genuine computation, a
`~>` body being pure unification-built data (px_template.pl's
expand_template/3) that cannot express it, same reasoning
prolog/ui/checkbox.pl's and prolog/ui/radio_group.pl's headers give
for their own render_helper registrations.

Options, part by part:

    form_root(Opts, Children)
        Opts: any native `<form>` attribute (`action(_)`, `method(_)`,
        `id(_)`, ...) plus `class(C)` (merged with the fixed
        `"px-form"` hook class, never replacing it). Always wrapped in
        `<px-form>` (assets/js/components/form.js) -- unlike
        prolog/ui/checkbox.pl's conditional wrap, EVERY form benefits
        from the blur/submit validation-surfacing this module exists
        to provide, so there is no bare-native-only path here the way
        there is for a plain checked/unchecked Checkbox.

    form_field(Opts, Parts)
        Opts: `name(N)` (REQUIRED -- the one piece of context every
        Part below needs and has no sane default for, same class of
        requirement as radio_group.pl's `value`/`name` on Item);
        `id(Id)` (default `"px-form-field-<N>"`; override this to
        line up with a px_form field id, e.g.
        `id('post_form_title')`, when composing over px_form-rendered
        markup -- see the module header); `invalid(Bool)` (the
        server-side truth, px_form's 422 escape hatch; absent by
        default, meaning "unknown yet, deferred to the client",
        distinct from `false`); `class(C)` (merged with
        `"px-form-field"`). Parts: a list, normally one `form_label`,
        one `form_control`, and zero or more `form_message`s (any
        other term -- e.g. hand-authored helper-text markup -- passes
        through completely unmodified, no id/name/invalid injection
        attempted on it, same permissiveness as
        prolog/ui/radio_group.pl's `inject_name/3` for a
        non-`radio_group_item` element interleaved in its list).
        `form_field/2` is the ONLY part that computes anything across
        siblings: before rendering, it scans Parts once for
        `form_message(_,_)` terms to synthesize their ids
        (`"<Id>-message-<N>"`, in list order), then rewrites Parts
        in a second pass -- `form_label` gets `for(Id)` (unless it
        already has its own), `form_control` gets `id(Id)`,
        `name(N)`, `invalid(Bool)` and `describedby(MessageIds)`
        (each only if not already explicit), each `form_message` gets
        its precomputed `id(_)`. Called directly (bare `form_label` /
        `form_control` / `form_message`, no enclosing `form_field`),
        every one of those injected options is instead the caller's
        job to supply explicitly -- exactly the "usable to hand-write
        forms" half of this module's brief.

    form_label(Opts, Children)
        Opts: `for(Id)` (native Label/Control association -- normally
        injected by `form_field`); `invalid(Bool)` (drives
        `data-valid`/`data-invalid`, same tri-state as Field);
        `class(C)`. Delegates to prolog/ui/label.pl's `label_root/2`
        for the actual `<label>` (literally "wraps the Label
        primitive", the analysis doc's own words) -- `label_root`'s
        own class-merge logic runs on top of this module's, so the
        final class is always `"px-label px-form-label <caller's, if
        any>"`, meaning `.px-label`'s existing CSS (the double-click
        text-selection guard, prolog/ui/label.pl's header) applies to
        every Form Label for free.

    form_control(Opts) / form_control(Opts, Children)
        Opts: `as(Tag)` (`input` (default) | `textarea` | `select` --
        this port's answer to "Control (`<input>` by default)": ONE
        part covers all three native control shapes rather than a
        separate template per widget, closed set, unlike px_form's own
        wider widget vocabulary since ui/form only needs the ones with
        genuine `ValidityState` participation); `type(T)` (native
        `<input>` type, default `text`; ignored for `textarea`/
        `select`, neither of which has a `type` attribute at all);
        `id(Id)`, `name(N)` (both pass through verbatim; normally
        injected by `form_field`); `invalid(Bool)` (tri-state, drives
        `data-valid`/`data-invalid` AND, only when `true`,
        `aria-invalid` -- see the module header); `describedby(Ids)`
        (a list, normally injected by `form_field`; merged,
        deduplicated, with any caller-supplied `aria_describedby(_)`
        pass-through value); `class(C)`; `title(_)` (default `""`,
        override to opt back into the native tooltip). Anything else
        (`required`, `pattern(_)`, `minlength(_)`, `placeholder(_)`,
        `value(_)`, `checked`, `disabled`, `rows(_)`, `step(_)`,
        `min(_)`/`max(_)`, ...) passes straight through, appended
        after the computed attributes, same last-wins spread order
        every other component in this library uses. `Children` is
        used only for `as(textarea)` (the text content) and
        `as(select)` (a list of `option(...)` element terms, plain
        px_template markup, not this module's concern); `input` is
        void, so `form_control/1` is the common shorthand and
        `form_control/2` with `Children = []` behaves identically.

    form_message(Opts, Children)
        Opts: `match(MatchTerm)` -- one of the native `ValidityState`
        boolean keys, spelled the way this codebase spells every
        other multi-word option atom (snake_case): `value_missing`,
        `type_mismatch`, `pattern_mismatch`, `too_long`, `too_short`,
        `range_underflow`, `range_overflow`, `step_mismatch`,
        `bad_input` -- exactly Radix's own built-in matcher set
        (`valueMissing`, `typeMismatch`, ...), minus `badInput`'s
        awkward casing, which `match_key/2` maps to the kebab-case
        `data-match` value assets/js/components/form.js reads back via
        its own `MATCH_TO_VALIDITY_KEY` table. Omitted `match(_)` means
        "show on ANY invalidity", Radix's own no-`match` default.
        `forced(Bool)` (default `false`) -- THIS port's name for
        Radix's `forceMatch` prop, chosen to match this task's brief
        and to read naturally next to px_form's own vocabulary
        ("forced by the server", not "force-matched"): when `true`,
        renders visible (no `hidden`) and carries `data-forced=""`, so
        it is never toggled by the client-side loop -- the px_form
        422-error rendering path (module header). `id(Id)` (normally
        injected by `form_field`). `class(C)`. Custom sync/async
        matcher functions (upstream also supports these) are NOT
        ported -- no equivalent concept exists without a JS-side
        validator registry, and the analysis doc lists them as
        optional beyond the built-in matcher set.

    form_submit(Opts, Children)
        Opts: any native `<button>` attribute, `class(C)` (merged with
        `"px-form-submit"`). Plain `<button type="submit">` -- no
        auto-disable-while-invalid (not part of upstream's contract
        either; `assets/js/components/form.js` only ever intercepts
        `submit`, never disables the button itself).
*/

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

		 /*******************************
		 *        OPTION HELPERS        *
		 *******************************/

%!  merge_class(+Opts0, +Default, -ClassVal, -Rest) is det.
%
%   Same helper as every other component in this library (checkbox.pl,
%   progress.pl, toggle.pl, switch.pl, ...): ClassVal is Default alone,
%   or "Default Caller" when Opts0 carries a class(Caller) -- additive,
%   never overwriting. Rest is Opts0 with any class(_) term removed.
merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  add_missing(+Term, +Opts0, -Opts1) is det.
%
%   Prepends Term (a Functor(_) unary compound) to Opts0 UNLESS Opts0
%   already has a term with the same functor -- explicit caller options
%   always win over injected context, same rule
%   prolog/ui/radio_group.pl's `add_name/3` applies for Item's `name`.
add_missing(Term, Opts0, Opts1) :-
    functor(Term, F, 1),
    functor(Probe, F, 1),
    (   memberchk(Probe, Opts0)
    ->  Opts1 = Opts0
    ;   Opts1 = [Term|Opts0]
    ).

%!  take_invalid(+Opts0, -Invalid, -Rest) is det.
%
%   Invalid is the tri-state this whole module shares: `none` (no
%   invalid(_) opt at all -- deferred entirely to the client),
%   `true`/`false` (the server truth, from an explicit invalid(Bool)
%   opt; any non-`true` value normalises to `false`, same "fall back to
%   the default" guard shape separator.pl's `orientation` option uses).
take_invalid(Opts0, Invalid, Rest) :-
    (   selectchk(invalid(V), Opts0, Opts1)
    ->  ( V == true -> Invalid = true ; Invalid = false )
    ;   Invalid = none, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  add_invalid_opt(+Invalid, +Opts0, -Opts1) is det.
%
%   Injects invalid(Invalid) into Opts0 (add_missing/3 -- caller's own
%   invalid(_), if any, always wins) UNLESS Invalid is the `none`
%   tri-state value, in which case there is nothing to inject at all
%   (an explicit invalid(none) opt would be meaningless).
add_invalid_opt(none, Opts0, Opts0) :- !.
add_invalid_opt(Invalid, Opts0, Opts1) :- add_missing(invalid(Invalid), Opts0, Opts1).

%!  valid_state_attrs(+Invalid, -Attrs) is det.
%
%   Field/Label's shared two-attribute toggle: present-or-omitted,
%   never "false" (the analysis doc's own words). `none` (not yet
%   known -- module header) omits BOTH attributes.
valid_state_attrs(none,  []).
valid_state_attrs(true,  [data_invalid("")]).
valid_state_attrs(false, [data_valid("")]).

%!  valid_state_attrs_control(+Invalid, -Attrs) is det.
%
%   Control's own version: identical data-valid/data-invalid, PLUS
%   aria-invalid="true" -- but ONLY on Invalid == true, never mirroring
%   plain client-side invalidity (module header's "aria-invalid ...
%   NOT ... only server-side" note -- the one place this predicate
%   diverges from valid_state_attrs/2).
valid_state_attrs_control(none,  []).
valid_state_attrs_control(true,  [data_invalid(""), aria_invalid(true)]).
valid_state_attrs_control(false, [data_valid("")]).

		 /*******************************
		 *             ROOT             *
		 *******************************/

%!  form_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `form_root([action("/subscribe")],
%   Fields)`. Always wrapped in <px-form> -- see the module header for
%   why, unlike checkbox.pl's conditional wrap, this component has no
%   JS-free path worth special-casing. `novalidate` is unconditional
%   (module header).
px_template:render_helper(form_root(Opts0, Children), S) :-
    merge_class(Opts0, "px-form", ClassVal, Rest),
    Attrs = [class(ClassVal), novalidate|Rest],
    px_template:render_tag(S, px_form, [], [form(Attrs, Children)]).

		 /*******************************
		 *             FIELD            *
		 *******************************/

%!  form_field(+Opts, +Parts) is det.
%
%   Bare-call template surface: `form_field([name(email)], [form_label(...),
%   form_control(...), form_message(...)])`. The one part that inspects
%   its own Children before rendering -- see the module header for the
%   two-pass id-synthesis/injection this performs.
px_template:render_helper(form_field(Opts0, Parts0), S) :-
    take_field_opts(Opts0, Name, Id, Invalid, Rest0),
    collect_message_ids(Parts0, Id, MessageIds),
    inject_parts(Parts0, Id, Name, Invalid, MessageIds, Parts1),
    merge_class(Rest0, "px-form-field", ClassVal, Rest),
    valid_state_attrs(Invalid, InvalidAttrs),
    append([[class(ClassVal)], InvalidAttrs, Rest], Attrs),
    px_template:render(S, div(Attrs, Parts1)).

take_field_opts(Opts0, Name, Id, Invalid, Rest) :-
    (   selectchk(name(Name0), Opts0, Opts1)
    ->  Name = Name0
    ;   throw(error(existence_error(option, name),
                    context(form_field/2, 'name(FieldName) is required')))
    ),
    (   selectchk(id(Id0), Opts1, Opts2)
    ->  Id = Id0
    ;   format(atom(Id), "px-form-field-~w", [Name0]), Opts2 = Opts1
    ),
    take_invalid(Opts2, Invalid, Rest).

%!  collect_message_ids(+Parts, +FieldId, -MessageIds) is det.
%
%   MessageIds: one synthesized id per form_message(_,_) term in
%   Parts, in list order -- "<FieldId>-message-<N>", 1-based.
collect_message_ids(Parts, FieldId, MessageIds) :-
    collect_message_ids_(Parts, FieldId, 1, MessageIds).

collect_message_ids_([], _, _, []).
collect_message_ids_([form_message(_, _)|T], FieldId, N, [MsgId|Ids]) :-
    !,
    format(atom(MsgId), "~w-message-~w", [FieldId, N]),
    N1 is N + 1,
    collect_message_ids_(T, FieldId, N1, Ids).
collect_message_ids_([_|T], FieldId, N, Ids) :-
    collect_message_ids_(T, FieldId, N, Ids).

%!  inject_parts(+Parts0, +Id, +Name, +Invalid, +MessageIds, -Parts1) is det.
%
%   Second pass: rewrites form_label/form_control/form_message terms
%   in Parts0 with the Field-level context they are each missing (add_missing/3
%   -- explicit caller options always win); everything else passes
%   through unchanged. Message ids are consumed in the SAME order
%   collect_message_ids/3 assigned them, via a running counter.
inject_parts(Parts0, Id, Name, Invalid, MessageIds, Parts1) :-
    inject_parts_(Parts0, Id, Name, Invalid, MessageIds, 1, Parts1).

inject_parts_([], _, _, _, _, _, []).
inject_parts_([H|T], Id, Name, Invalid, MessageIds, N0, [H1|T1]) :-
    rewrite_part(H, Id, Name, Invalid, MessageIds, N0, N1, H1),
    inject_parts_(T, Id, Name, Invalid, MessageIds, N1, T1).

rewrite_part(form_label(LOpts0, LChildren), Id, _Name, Invalid, _MsgIds, N, N,
             form_label(LOpts1, LChildren)) :-
    !,
    add_missing(for(Id), LOpts0, LOpts1a),
    add_invalid_opt(Invalid, LOpts1a, LOpts1).
rewrite_part(form_control(COpts0), Id, Name, Invalid, MsgIds, N, N,
             form_control(COpts1)) :-
    !,
    control_context_opts(Id, Name, Invalid, MsgIds, COpts0, COpts1).
rewrite_part(form_control(COpts0, CChildren), Id, Name, Invalid, MsgIds, N, N,
             form_control(COpts1, CChildren)) :-
    !,
    control_context_opts(Id, Name, Invalid, MsgIds, COpts0, COpts1).
rewrite_part(form_message(MOpts0, MChildren), _Id, _Name, _Invalid, MsgIds, N, N1,
             form_message(MOpts1, MChildren)) :-
    !,
    nth1(N, MsgIds, MsgId),
    add_missing(id(MsgId), MOpts0, MOpts1),
    N1 is N + 1.
rewrite_part(Other, _, _, _, _, N, N, Other).

control_context_opts(Id, Name, Invalid, MsgIds, Opts0, Opts1) :-
    add_missing(id(Id), Opts0, Opts1a),
    add_missing(name(Name), Opts1a, Opts1b),
    add_invalid_opt(Invalid, Opts1b, Opts1c),
    (   MsgIds == []
    ->  Opts1 = Opts1c
    ;   add_missing(describedby(MsgIds), Opts1c, Opts1)
    ).

		 /*******************************
		 *             LABEL            *
		 *******************************/

%!  form_label(+Opts, +Children) is det.
%
%   Bare-call template surface: `form_label([for(Id)], "Email")`.
%   Delegates to prolog/ui/label.pl's label_root/2 -- see the module
%   header.
px_template:render_helper(form_label(Opts0, Children), S) :-
    take_invalid(Opts0, Invalid, Opts1),
    valid_state_attrs(Invalid, ValidAttrs),
    merge_class(Opts1, "px-form-label", ClassVal, Rest),
    append([[class(ClassVal)], ValidAttrs, Rest], LabelOpts),
    px_template:render(S, label_root(LabelOpts, Children)).

		 /*******************************
		 *            CONTROL           *
		 *******************************/

%!  form_control(+Opts) is det.
%!  form_control(+Opts, +Children) is det.
%
%   Bare-call template surface: `form_control([type(email), required])`
%   or `form_control([as(textarea), required], [])`. `form_control/1`
%   is the common (input) shorthand; input is void so Children is
%   always `[]` for it regardless of which arity is used.
px_template:render_helper(form_control(Opts), S) :-
    px_template:render_helper(form_control(Opts, []), S).
px_template:render_helper(form_control(Opts0, Children), S) :-
    take_control_opts(Opts0, As, Type, DescribedBy, Rest0),
    merge_class(Rest0, "px-form-control", ClassVal, Rest1),
    title_attrs(Rest1, TitleAttrs, Rest),
    type_attrs(As, Type, TypeAttrs),
    described_by_attrs(DescribedBy, DescAttrs),
    append([ [class(ClassVal)], TitleAttrs, TypeAttrs, DescAttrs, Rest
           ], Attrs),
    render_control(As, Attrs, Children, S).

take_control_opts(Opts0, As, Type, DescribedBy, Rest) :-
    (   selectchk(as(As0), Opts0, Opts1)
    ->  As = As0
    ;   As = input, Opts1 = Opts0
    ),
    (   selectchk(id(Id0), Opts1, Opts2)
    ->  IdOpt = [id(Id0)]
    ;   IdOpt = [], Opts2 = Opts1
    ),
    (   selectchk(name(N0), Opts2, Opts3)
    ->  NameOpt = [name(N0)]
    ;   NameOpt = [], Opts3 = Opts2
    ),
    take_invalid(Opts3, Invalid, Opts4),
    valid_state_attrs_control(Invalid, ValidAttrs),
    (   selectchk(describedby(D0), Opts4, Opts5)
    ->  Injected = D0
    ;   Injected = [], Opts5 = Opts4
    ),
    merge_described_by(Injected, Opts5, DescribedBy, Opts6),
    (   As == input
    ->  (   selectchk(type(T0), Opts6, Opts7)
        ->  Type = T0
        ;   Type = text, Opts7 = Opts6
        )
    ;   Type = none, Opts7 = Opts6
    ),
    append([IdOpt, NameOpt, ValidAttrs, Opts7], Rest).

%!  merge_described_by(+Injected, +Opts0, -Ids, -Rest) is det.
%
%   Ids: Injected (form_field's synthesized message ids) unioned with
%   any author-supplied aria_describedby(_) pass-through value (split
%   on whitespace), deduplicated, order preserved -- module header's
%   "dedup'd against any author-supplied value". `[]` when there is
%   nothing on either side.
merge_described_by(Injected, Opts0, Ids, Rest) :-
    (   selectchk(aria_describedby(V), Opts0, Rest)
    ->  ( (string(V) ; atom(V)) -> split_string(V, " ", " ", Raw) ; Raw = [] ),
        exclude(==(""), Raw, AuthorStrings)
    ;   Rest = Opts0, AuthorStrings = []
    ),
    ( is_list(Injected) -> InjectedList = Injected ; InjectedList = [Injected] ),
    maplist(to_id_atom, InjectedList, InjectedAtoms1),
    maplist(to_id_atom, AuthorStrings, AuthorAtoms),
    append(InjectedAtoms1, AuthorAtoms, All),
    list_to_set(All, Ids).

to_id_atom(V, A) :- atom(V), !, A = V.
to_id_atom(V, A) :- atom_string(A, V).

described_by_attrs([], []) :- !.
described_by_attrs(Ids, [aria_describedby(Joined)]) :-
    atomic_list_concat(Ids, ' ', Joined).

title_attrs(Opts0, [title("")], Opts0) :- \+ memberchk(title(_), Opts0), !.
title_attrs(Opts0, [], Opts0).

type_attrs(input, Type, [type(Type)]) :- !.
type_attrs(_, _, []).

render_control(input, Attrs, _Children, S) :-
    !,
    px_template:render(S, input(Attrs)).
render_control(textarea, Attrs, Children, S) :-
    !,
    px_template:render(S, textarea(Attrs, Children)).
render_control(select, Attrs, Children, S) :-
    !,
    px_template:render(S, select(Attrs, Children)).
render_control(As, _, _, _) :-
    throw(error(domain_error(px_form_control_as, As),
                context(form_control/2, 'as: input, textarea, select'))).

		 /*******************************
		 *            MESSAGE           *
		 *******************************/

%!  form_message(+Opts, +Children) is det.
%
%   Bare-call template surface: `form_message([match(value_missing)],
%   "Email is required")`.
px_template:render_helper(form_message(Opts0, Children), S) :-
    take_message_opts(Opts0, Match, Forced, Rest0),
    merge_class(Rest0, "px-form-message", ClassVal, Rest),
    match_attr(Match, MatchAttrs),
    forced_attrs(Forced, ForcedAttrs),
    append([[class(ClassVal)], MatchAttrs, ForcedAttrs, Rest], Attrs),
    px_template:render(S, span(Attrs, Children)).

take_message_opts(Opts0, Match, Forced, Rest) :-
    (   selectchk(match(M0), Opts0, Opts1)
    ->  Match = M0
    ;   Match = none, Opts1 = Opts0
    ),
    (   selectchk(forced(F0), Opts1, Opts2)
    ->  ( F0 == true -> Forced = true ; Forced = false )
    ;   Forced = false, Opts2 = Opts1
    ),
    Rest = Opts2.

%!  match_key(?MatchTerm, ?DataMatchValue) is semidet.
%
%   MatchTerm: this port's snake_case spelling of Radix's built-in
%   matcher set. DataMatchValue: the kebab-case `data-match` attribute
%   value assets/js/components/form.js reads back (its own
%   MATCH_TO_VALIDITY_KEY table maps it to the native camelCase
%   ValidityState property).
match_key(value_missing,    "value-missing").
match_key(type_mismatch,    "type-mismatch").
match_key(pattern_mismatch, "pattern-mismatch").
match_key(too_long,         "too-long").
match_key(too_short,        "too-short").
match_key(range_underflow,  "range-underflow").
match_key(range_overflow,   "range-overflow").
match_key(step_mismatch,    "step-mismatch").
match_key(bad_input,        "bad-input").

match_attr(none, []) :- !.
match_attr(M, [data_match(Key)]) :-
    match_key(M, Key),
    !.
match_attr(M, _) :-
    throw(error(domain_error(px_form_message_match, M),
                context(form_message/2,
                        'match: value_missing, type_mismatch, pattern_mismatch, too_long, too_short, range_underflow, range_overflow, step_mismatch, bad_input'))).

%   forced(true): visible immediately (no hidden), plus data-forced --
%   see the module header for why the JS loop must skip these.
%   forced(false) (default): hidden until the client shows it.
forced_attrs(true,  [data_forced("")]) :- !.
forced_attrs(false, [hidden]).

		 /*******************************
		 *             SUBMIT           *
		 *******************************/

%!  form_submit(+Opts, +Children) is det.
%
%   Bare-call template surface: `form_submit([], "Submit")`.
px_template:render_helper(form_submit(Opts0, Children), S) :-
    merge_class(Opts0, "px-form-submit", ClassVal, Rest),
    append([[type(submit), class(ClassVal)], Rest], Attrs),
    px_template:render(S, button(Attrs, Children)).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   Form is docs/radix-port-analysis.md's phase-14 "(S) -- can actually
%   be ported any time after phase 1 ... listed [there] because 'forms
%   work', not because of a dependency chain" -- Order 19 is simply the
%   next free slot after every component landed so far (max in use:
%   18, dropdown_menu/context_menu/menubar/navigation_menu).
px_ui:demo(form, 19, \form_demo).

%   Arity-0, so it is an ATOM -- called via the explicit \ escape, same
%   as every other component's demo template (a bare atom is a text
%   node, not a callable dispatch, in render/2 -- adr/0019).
form_demo ~>
    div(class("ui-demo-form"),
      [ p([ "novalidate on the wrapped <form> hands validation entirely ",
            "to assets/js/components/form.js (<px-form>): it reads each ",
            "control's native ValidityState on blur/submit, toggles ",
            "data-invalid, and shows the matching Message. Try ",
            "submitting empty, then fill both fields in validly."
          ]),
        form_root([id("form-demo-1"), action("#"), method(get)],
          [ form_field([name(email)],
              [ form_label([], "Email"),
                form_control([type(email), required,
                              placeholder("you@example.com")]),
                form_message([match(value_missing)],
                             "Please enter your email address."),
                form_message([match(type_mismatch)],
                             "Please enter a valid email address.")
              ]),
            form_field([name(question)],
              [ form_label([], "Question"),
                form_control([as(textarea), required, rows(3),
                              placeholder("What would you like to ask?")]),
                form_message([match(value_missing)],
                             "Please enter a question.")
              ]),
            form_submit([], "Submit")
          ]),

        h3("px_form integration (adr/0023) -- the server-forced escape hatch"),
        p([ "A field rendered the way a px_form invalid(Values, Errors) ",
            "422 response would hand it to ui/form: invalid(true) on ",
            "the Field (so data-invalid/aria-invalid are already ",
            "present on first paint, no JS needed), and the actual ",
            "error message from px_form's Errors list inside a ",
            "forced(true) Message -- data-forced marks it so the ",
            "client-side blur/submit loop never touches it, so a real ",
            "server error can never be silently hidden by a client-",
            "side revalidation that happens to pass."
          ]),
        form_root([id("form-demo-2"), action("#"), method(get)],
          [ form_field([name(username), invalid(true)],
              [ form_label([], "Username"),
                form_control([value("dario")]),
                form_message([forced(true)],
                             "This username is already taken.")
              ]),
            form_submit([], "Submit")
          ])
      ]).
