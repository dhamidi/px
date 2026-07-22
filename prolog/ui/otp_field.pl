:- module(ui_otp_field, []).

%   No predicates are exported: otp_field/1,2, otp_field_root/2,
%   otp_field_input/1, otp_field_hidden_input/1 are never called
%   module-qualified -- bare-call dispatch through px_template's
%   tmpl/2 / render_helper/2 tables resolves them (adr/0019), the same
%   pattern prolog/ui/toggle_group.pl and prolog/ui/radio_group.pl use.

/** <module> One-Time Password Field (adr/0026): N single-character
    cells with unified keyboard nav and paste-splitting, backed by one
    hidden `<input>` carrying the joined value for form submission.

Ported from Radix UI's One-Time Password Field primitive (docs/radix-
port-analysis.md, "One-Time Password Field" entry). Upstream anatomy:
`Root` (`role="group"`, wraps roving-focus + a collection, handles
paste at the group level), `Input` (one real `<input>` per character
box), `HiddenInput` (`<input type="hidden" readOnly>` -- the actual
form-submittable value). This port keeps exactly that three-part
anatomy: `otp_field_root/2`, `otp_field_input/1` (one cell -- a void
element, so no `/2` children-taking arity: an `<input>` cannot have
children), `otp_field_hidden_input/1` (also `/1` -- same reason).
`otp_field/1,2` is the rule-1 top-level convenience template
assembling the common case: Root around N generated Input cells plus
one generated HiddenInput.

**Interactivity class: CUSTOM-ELEMENT -- genuinely unavoidable, no
native equivalent** (the analysis doc's own verdict: "No native 'OTP
box group' HTML element ... State machine: an ordered box registry, a
single source-of-truth value array, a roving-tabindex focus layer, and
a reducer"). Unlike Toggle Group/Tabs/Toolbar, this port does NOT
reuse `assets/js/lib/roving-focus.js` -- that module implements
single-tab-stop roving-tabindex (Tab skips every item but the current
one), which is the wrong shape here: every OTP cell must stay in the
normal Tab order (typing fills a cell and the *browser's own* Tab
order already matches left-to-right cell order once JS moves focus
forward after each keystroke -- there is nothing to rove). Arrow-
key/Backspace navigation between cells is therefore hand-rolled
directly in `assets/js/components/otp_field.js`, not delegated --
a documented deviation from the analysis doc's "Dependencies: roving-
focus, collection, use-controllable-state, context, direction" list
(rule 2): the *shape* of the shared module does not fit, even though
the underlying concept -- "arrow keys move focus between fixed slots"
-- is conceptually related.

DOM/ARIA contract emitted (the analysis doc's "One-Time Password
Field" entry):

    Root         <div role="group">                                    (wrapped in <px-otp-field>)
    Input (cell) <input type="text" inputmode="numeric" maxlength="1|N"
                        autocomplete="one-time-code|off"
                        aria-label="Character {i} of {N}">
    HiddenInput  <input type="hidden" readonly name="..." value="...">

One documented, deliberate simplification of the autocomplete/maxLength
placement rule (rule 2): upstream moves `autoComplete="one-time-code"`
+ a full-length `maxLength` to whichever box currently holds the tab
stop (a dynamic re-render on every focus change), "to satisfy Safari/
iOS autofill heuristics." This port pins both attributes to the
**first** cell permanently instead -- iOS/Android SMS autofill only
ever needs *one* input in the DOM carrying `autocomplete="one-time-
code"` with room for the whole code; it does not require that input to
also be the currently-focused one, and a static placement avoids a
per-keystroke DOM-attribute rewrite for a purely autofill-heuristic
concern. Every other cell gets `autocomplete="off"` plus four
password-manager-suppression `data-*` attributes (`data-1p-ignore`,
`data-lpignore="true"`, `data-bwignore="true"`, `data-form-type="other"`)
-- named after the analysis doc's own description ("four distinct
password-manager-suppression data-* attributes") but not literally
copied from upstream source (this port has no access to Radix's actual
source strings); the four listed are the well-known real-world
equivalents (1Password/LastPass/Bitwarden/generic).

Two additive-only extensions, noted per rule 2:

  1. `data-numeric=""` on Root (empty-string-when-true, the same
     convention `toggle_group.pl`'s `data-loop` established) -- lets
     `<px-otp-field>` learn, at the group level, whether paste/autofill
     text should be filtered to digits only. Reflects this port's own
     `numeric(Bool)` option (default `true`); the analysis doc
     describes the *behavior* ("filters through the configured
     validation pattern") but names no option, so `numeric/1` is this
     port's own naming choice -- a boolean covers the overwhelmingly
     common OTP case (digits only) without inventing a whole pattern-
     language option that nothing else in this port would exercise.
  2. `data-auto-submit=""` on Root, only when `auto_submit(true)` --
     NOT in the analysis doc's contract at all; this port's own
     addition, mirroring the common real-world "submit the form the
     instant the last digit lands" UX (conceptually close to what a
     consumer would otherwise wire up by hand with Radix's `onComplete`
     callback). `<px-otp-field>` calls the closest `<form>`'s
     `.requestSubmit()` once every cell holds exactly one character.

Keyboard/paste (hand-rolled in `assets/js/components/otp_field.js`,
see that file's header for the full state machine): typing a character
sanitizes it (digits-only when `numeric`), fills the current cell, and
advances focus to the next cell (or re-selects the last cell's content
for easy retyping if already on the last cell). Backspace on an empty
cell moves focus to the previous cell without altering its value;
Backspace on a filled cell clears it (native single-char `<input>`
behavior already does this, mirrored onto the hidden input by the
`input` handler). Cmd/Ctrl+Backspace clears every cell and refocuses
the first. ArrowLeft/ArrowRight move focus one cell at a time (clamped
at the ends). A paste (or an autofill-driven multi-character `input`
event landing in one cell) is sanitized, sliced to the cell count, and
distributes across cells from the start, focusing the last cell that
received a character. Clicking a cell past the first empty one
redirects focus to that first empty cell -- "you cannot focus a future
empty box out of order" (the analysis doc's own line). Every mutation
re-joins all cell values into the hidden input's `value`.

Options (a plain list, adr/0026 rule 1):

  `otp_field_root/2` Opts:
    disabled(Bool)     `true`/`false`, default `false`. `data-disabled=""`
                    on Root ONLY -- deviation, noted per rule 2, same
                    as every other family Root in this library
                    (radio_group.pl, toggle_group.pl): does NOT
                    auto-propagate to Children (there is no context to
                    propagate through when Root is called directly with
                    caller-supplied Children); `otp_field/1,2` threads
                    it onto every generated Input/HiddenInput itself.
    numeric(Bool)      `true`/`false`, default `true`. Emits
                    `data-numeric=""` when `true` (extension 1 above).
    auto_submit(Bool)  `true`/`false`, default `false`. Emits
                    `data-auto-submit=""` when `true` (extension 2
                    above).
    aria_label(L)      default `"One-time password"` -- `role="group"`
                    needs an accessible name; Radix leaves this to the
                    consumer app, but a sane default costs nothing and
                    is always overridable.
    class(C)        merged with the default class, default first
                    ("px-otp-field C").
    anything else (id(...), data_*(...), ...) passed through verbatim,
                    appended AFTER the computed attributes -- same
                    last-wins spread order as every other port in this
                    library.

  `otp_field_input/1` Opts:
    index(I)        REQUIRED. 1-based position of this cell among
                    `total(N)` -- drives `aria-label`, and whether this
                    is the first cell (autocomplete/maxLength/no
                    password-manager `data-*`).
    total(N)        REQUIRED. Total cell count.
    value(Ch)       optional single character pre-filling this cell;
                    absent/blank omits the `value` attribute entirely.
    numeric(Bool)   `true`/`false`, default `true`. Drives
                    `inputmode="numeric"`/`pattern="[0-9]*"` (native
                    numeric-keypad/constraint-validation hints; the
                    real filtering enforcement is client-side JS, per
                    the analysis doc's own "filters through the
                    configured validation pattern" behavior, which no
                    HTML attribute alone can express).
    disabled(Bool)  `true`/`false`, default `false`. Native `disabled`
                    boolean attribute plus `data-disabled=""`.
    class(C)        merged with the default class, default first
                    ("px-otp-field-input C").
    anything else (id(...), aria_describedby(...), ...) passed through
                    verbatim onto the `<input>`.

  `otp_field_hidden_input/1` Opts:
    name(N)         REQUIRED -- the actual form-submittable field name.
    value(V)        default `""` (omitted from the rendered attribute
                    when blank, same `value_attr` convention
                    prolog/px_form.pl's `widget_input/6` uses).
    disabled(Bool)  `true`/`false`, default `false`. Native `disabled`
                    boolean attribute.
    class(C)        merged with the default class, default first
                    ("px-otp-field-hidden-input C").
    anything else passed through verbatim.

  `otp_field/1,2` Opts: everything `otp_field_root/2` takes, PLUS
    length(N)       default `6`. Number of character cells generated.
    name(N)         optional; extracted before building Root and
                    passed to the generated HiddenInput. Defaults to a
                    generated `px-otp-field-N` (`library(gensym)`,
                    same convention as radio_group.pl's group `name`)
                    when absent.
    value(V)        optional initial value (an atom/string); its first
                    `min(length(V), N)` characters pre-fill the first
                    cells left-to-right (`atom`/`string` accepted,
                    normalised via `format/3`); default: every cell
                    starts empty.
    `disabled(Bool)`/`numeric(Bool)` are threaded onto Root AND every
                    generated Input (and, for `disabled`, the
                    HiddenInput too) -- the one piece of context Cells
                    genuinely share, same category as toggle_group.pl
                    threading `type` onto every Item.
  `otp_field/2` second argument: extra child content appended AFTER
                    the generated cells and HiddenInput inside Root
                    (e.g. a validation-error `<span>`) -- `otp_field/1`
                    is the shorthand with no extra content
                    (`otp_field(Opts) \== otp_field(Opts, [])` only in
                    arity, same `/1` delegates to `/2` shape as
                    radio_group.pl's `radio_group_item/1,2`).

Both `otp_field_root/2`, `otp_field_input/1` and
`otp_field_hidden_input/1` are registered as `px_template:render_helper/2`
hooks (adr/0019) -- the Opts-list defaults/merge/validation logic below
is genuine computation, the same reason toggle_group.pl/radio_group.pl
register theirs the same way. `otp_field/1,2`, the rule-1 top-level
convenience template, is ALSO a `render_helper/2` hook rather than a
plain `~>` -- generating N Input cells plus the HiddenInput and
threading options across all of them is genuine cross-part computation,
the same reason radio_group.pl's `radio_group/2` and toggle_group.pl's
`toggle_group/2` are `render_helper/2` hooks too.
*/

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(gensym)).
:- use_module('../px_template').

:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

		 /*******************************
		 *        OPTION HELPERS        *
		 *******************************/

%!  require_opt(+Opts, +Key, +Context, -Value) is det.
%
%   Same helper toggle_group.pl/radio_group.pl each carry their own
%   copy of.
require_opt(Opts, Key, Context, Value) :-
    Probe =.. [Key, Value],
    (   memberchk(Probe, Opts)
    ->  true
    ;   throw(error(existence_error(option, Key), context(Context, _)))
    ).

%!  take_bool(+Name, +Opts0, -Value, -Rest) is det.
%
%   Same helper as toggle_group.pl's -- pulls Name(Value) out of
%   Opts0, default `false` when absent.
take_bool(Name, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Opts1)
    ->  Value = V0
    ;   Value = false, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  take_bool_default(+Name, +Default, +Opts0, -Value, -Rest) is det.
%
%   Same as take_bool/4 but for options whose sane default is `true`
%   (`numeric`) rather than `false`.
take_bool_default(Name, Default, Opts0, Value, Rest) :-
    Probe =.. [Name, V0],
    (   selectchk(Probe, Opts0, Opts1)
    ->  Value = V0
    ;   Value = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  merge_class(+Opts0, +Default, -ClassVal, -Rest) is det.
%
%   Same helper as progress.pl / toggle.pl / toggle_group.pl's.
merge_class(Opts0, Default, ClassVal, Rest) :-
    (   selectchk(class(C), Opts0, Opts1)
    ->  format(string(ClassVal), "~w ~w", [Default, C])
    ;   ClassVal = Default, Opts1 = Opts0
    ),
    Rest = Opts1.

%!  value_attr(+V, -Attrs) is det.
%
%   Attrs is `[value(V)]` unless V is absent/blank, in which case it's
%   `[]` -- same "empty values omit the attribute" convention
%   prolog/px_form.pl's widget_input/6 documents.
value_attr(V, [value(V)]) :-
    nonvar(V),
    V \== '',
    V \== "",
    !.
value_attr(_, []).

		 /*******************************
		 *             ROOT             *
		 *******************************/

%!  otp_field_root(+Opts, +Children) is det.
%
%   Bare-call template surface: `otp_field_root([], Cells)`. Renders
%   the `<px-otp-field>` custom-element wrapper (adr/0026 rule 4)
%   around the server-rendered `<div role="group">` -- the div/inputs
%   inside carry the whole ARIA/data contract and remain a set of
%   real, individually Tab-reachable, individually labelled text
%   inputs (minus auto-advance/paste-splitting -- adr/0026 rule 4's
%   progressive-enhancement bar) if `<px-otp-field>` never upgrades.
px_template:render_helper(otp_field_root(Opts, Children), S) :-
    root_attrs(Opts, Attrs),
    px_template:render_tag(S, px_otp_field, [], [div(Attrs, Children)]).

root_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    take_bool(disabled, Opts0, Disabled, Opts1),
    take_bool_default(numeric, true, Opts1, Numeric, Opts2),
    take_bool(auto_submit, Opts2, AutoSubmit, Opts3),
    aria_label_opt(Opts3, Label, Opts4),
    merge_class(Opts4, "px-otp-field", ClassVal, Opts5),
    exclude(root_reserved_opt, Opts5, Extra),
    numeric_attrs(Numeric, NumAttrs),
    auto_submit_attrs(AutoSubmit, SubmitAttrs),
    disabled_attrs(Disabled, DisAttrs),
    append([ [role(group), aria_label(Label), class(ClassVal)],
             NumAttrs, SubmitAttrs, DisAttrs, Extra
           ], Attrs).

aria_label_opt(Opts0, Label, Opts) :-
    (   selectchk(aria_label(L), Opts0, Opts)
    ->  Label = L
    ;   Label = "One-time password", Opts = Opts0
    ).

numeric_attrs(true, [data_numeric("")]) :- !.
numeric_attrs(_,    []).

auto_submit_attrs(true, [data_auto_submit("")]) :- !.
auto_submit_attrs(_,    []).

disabled_attrs(true, [data_disabled("")]) :- !.
disabled_attrs(_,    []).

root_reserved_opt(disabled(_)).
root_reserved_opt(numeric(_)).
root_reserved_opt(auto_submit(_)).
root_reserved_opt(aria_label(_)).
root_reserved_opt(class(_)).

		 /*******************************
		 *             INPUT            *
		 *******************************/

%!  otp_field_input(+Opts) is det.
%
%   Bare-call template surface: `otp_field_input([index(1), total(6)])`.
%   A void element (`<input>`) -- no `/2` children-taking arity.
px_template:render_helper(otp_field_input(Opts), S) :-
    input_attrs(Opts, Attrs),
    px_template:render(S, input(Attrs)).

input_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    require_opt(Opts0, index, otp_field_input/1, I),
    require_opt(Opts0, total, otp_field_input/1, N),
    selectchk(index(I), Opts0, Opts1a),
    selectchk(total(N), Opts1a, Opts1),
    take_bool_default(numeric, true, Opts1, Numeric, Opts2),
    take_bool(disabled, Opts2, Disabled, Opts3),
    value_opt(Opts3, ValueAttrs, Opts4),
    merge_class(Opts4, "px-otp-field-input", ClassVal, Opts5),
    exclude(input_reserved_opt, Opts5, Extra),
    format(string(Label), "Character ~w of ~w", [I, N]),
    first_cell_attrs(I, N, FirstAttrs),
    numeric_hint_attrs(Numeric, NumAttrs),
    disabled_input_attrs(Disabled, DisAttrs),
    filled_attrs(ValueAttrs, FilledAttrs),
    append([ [type(text)], NumAttrs, FirstAttrs,
             [aria_label(Label), data_index(I), class(ClassVal)],
             ValueAttrs, FilledAttrs, DisAttrs, Extra
           ], Attrs).

%   `data-filled=""` mirrors "this cell has a character in it" as an
%   explicit attribute (additive extension, rule 2) -- assets/css/
%   ui.css's filled-cell visual state keys off it, and
%   assets/js/components/otp_field.js keeps it live on every
%   keystroke/paste/clear, the same "the attribute IS the state, never
%   a parallel store" rule adr/0026 rule 4 asks for. Computed
%   server-side here from whether an initial `value(Ch)` was actually
%   given (a blank/absent value never reaches this point -- see
%   value_opt/3 above).
filled_attrs([], []) :- !.
filled_attrs([_|_], [data_filled("")]).

value_opt(Opts0, Attrs, Opts) :-
    (   selectchk(value(V), Opts0, Opts)
    ->  value_attr(V, Attrs)
    ;   Attrs = [], Opts = Opts0
    ).

%   The first cell alone carries autocomplete="one-time-code" plus a
%   full-length maxlength (so a browser autofilling the whole SMS code
%   into it is accepted) -- the static simplification of upstream's
%   per-focus dynamic placement documented in the module header.
%   Every other cell gets autocomplete="off", maxlength="1", plus four
%   password-manager-suppression data-* attributes.
first_cell_attrs(1, N, [maxlength(N), autocomplete('one-time-code')]) :- !.
first_cell_attrs(_, _, [maxlength(1), autocomplete(off),
                         data_1p_ignore, data_lpignore(true),
                         data_bwignore(true), data_form_type(other)]).

numeric_hint_attrs(true, [inputmode(numeric), pattern("[0-9]*")]) :- !.
numeric_hint_attrs(_,    [inputmode(text)]).

disabled_input_attrs(true, [data_disabled(""), disabled]) :- !.
disabled_input_attrs(_,    []).

input_reserved_opt(index(_)).
input_reserved_opt(total(_)).
input_reserved_opt(value(_)).
input_reserved_opt(numeric(_)).
input_reserved_opt(disabled(_)).
input_reserved_opt(class(_)).

		 /*******************************
		 *          HIDDEN INPUT         *
		 *******************************/

%!  otp_field_hidden_input(+Opts) is det.
%
%   Bare-call template surface: `otp_field_hidden_input([name(otp)])`.
%   A void element -- no `/2` children-taking arity, same reason as
%   otp_field_input/1.
px_template:render_helper(otp_field_hidden_input(Opts), S) :-
    hidden_attrs(Opts, Attrs),
    px_template:render(S, input(Attrs)).

hidden_attrs(Opts0, Attrs) :-
    must_be(list, Opts0),
    require_opt(Opts0, name, otp_field_hidden_input/1, N),
    selectchk(name(N), Opts0, Opts1),
    take_bool(disabled, Opts1, Disabled, Opts2),
    value_opt(Opts2, ValueAttrs, Opts3),
    merge_class(Opts3, "px-otp-field-hidden-input", ClassVal, Opts4),
    exclude(hidden_reserved_opt, Opts4, Extra),
    hidden_disabled_attrs(Disabled, DisAttrs),
    append([ [type(hidden), name(N), readonly, class(ClassVal)],
             ValueAttrs, DisAttrs, Extra
           ], Attrs).

hidden_disabled_attrs(true, [disabled]) :- !.
hidden_disabled_attrs(_,    []).

hidden_reserved_opt(name(_)).
hidden_reserved_opt(value(_)).
hidden_reserved_opt(disabled(_)).
hidden_reserved_opt(class(_)).

		 /*******************************
		 *   CONVENIENCE (adr/0026 #1)  *
		 *******************************/

%!  otp_field(+Opts) is det.
%!  otp_field(+Opts, +ExtraChildren) is det.
%
%   The common case: Root around `length(N)` (default 6) generated
%   Input cells plus one generated HiddenInput carrying `name(N)`
%   (explicit, or a fresh gensym default) -- `disabled`/`numeric`
%   threaded onto Root and every generated Input (and `disabled` onto
%   the HiddenInput too), `value(V)` (if given) sliced across the
%   first cells left-to-right. `otp_field/1` is the no-extra-content
%   shorthand (ExtraChildren = []), same `/1` delegates to `/2` shape
%   as toggle_group.pl's `toggle_group_item/1,2`.
px_template:render_helper(otp_field(Opts), S) :-
    px_template:render_helper(otp_field(Opts, []), S).
px_template:render_helper(otp_field(Opts, ExtraChildren), S) :-
    must_be(list, Opts),
    length_opt(Opts, N, Opts1),
    name_opt(Opts1, Name, Opts2),
    value_opt_convenience(Opts2, N, Cells, Joined, Opts3),
    take_bool(disabled, Opts3, Disabled, Opts4),
    take_bool_default(numeric, true, Opts4, Numeric, RootOpts),
    numrange(1, N, Indexes),
    maplist(build_cell(N, Numeric, Disabled, Cells), Indexes, Inputs),
    hidden_disabled_opt(Disabled, HiddenDisOpts),
    append([name(Name), value(Joined)], HiddenDisOpts, HiddenOpts),
    Hidden = otp_field_hidden_input(HiddenOpts),
    append([disabled(Disabled), numeric(Numeric)], RootOpts, RootOpts1),
    append(Inputs, [Hidden|ExtraChildren], Children),
    px_template:render(S, otp_field_root(RootOpts1, Children)).

length_opt(Opts0, N, Opts) :-
    (   selectchk(length(N0), Opts0, Opts)
    ->  must_be(positive_integer, N0), N = N0
    ;   N = 6, Opts = Opts0
    ).

name_opt(Opts0, Name, Opts) :-
    (   selectchk(name(N0), Opts0, Opts)
    ->  Name = N0
    ;   Opts = Opts0,
        gensym('px-otp-field-', Name)
    ).

%!  value_opt_convenience(+Opts0, +N, -Cells, -Joined, -Opts) is det.
%
%   Cells is a list of N elements, each either a one-character
%   atom/string (from `value(V)`'s first N characters) or the atom
%   `none` for a blank cell. Joined is the plain concatenation of
%   however many leading characters were actually supplied (<= N) --
%   the HiddenInput's own initial `value`.
value_opt_convenience(Opts0, N, Cells, Joined, Opts) :-
    (   selectchk(value(V), Opts0, Opts)
    ->  true
    ;   V = '', Opts = Opts0
    ),
    format(string(VStr), "~w", [V]),
    string_chars(VStr, AllChars),
    length(AllChars, Len),
    (   Len > N
    ->  length(Taken, N), append(Taken, _, AllChars)
    ;   Taken = AllChars
    ),
    length(Taken, TakenLen),
    Pad is N - TakenLen,
    length(Blanks, Pad),
    maplist(=(none), Blanks),
    append(Taken, Blanks, Cells),
    atomic_list_concat(Taken, Joined).

build_cell(N, Numeric, Disabled, Cells, I, otp_field_input(Opts)) :-
    nth1(I, Cells, Ch),
    (   Ch == none
    ->  ValueOpts = []
    ;   ValueOpts = [value(Ch)]
    ),
    append([ [index(I), total(N), numeric(Numeric), disabled(Disabled)],
             ValueOpts
           ], Opts).

hidden_disabled_opt(true, [disabled(true)]) :- !.
hidden_disabled_opt(_,    []).

%!  numrange(+Low, +High, -List) is det.
%
%   List is [Low, Low+1, ..., High] -- `numlist/3` under a name that
%   doesn't shadow anything; kept local rather than pulling in
%   library(lists)' own numlist/3 under a different name for one call
%   site.
numrange(Low, High, List) :-
    numlist(Low, High, List).

		 /*******************************
		 *       KITCHEN-SINK DEMO       *
		 *******************************/

:- multifile px_ui:demo/3.
:- dynamic   px_ui:demo/3.

%   One-Time Password Field is the library's most JS-heavy CUSTOM-
%   ELEMENT port yet (adr/0026 rule 8's porting order places it in the
%   "positioning tier and beyond" -- shipped once its own dependencies,
%   already-ported roving-focus and form conventions, are in place).
%   Order 19 is the next free slot above every Order currently
%   registered (highest so far: 18, shared by context_menu/menubar/
%   navigation_menu -- collisions between components ported by
%   different concurrent agents are tolerated in this codebase, only
%   affecting /ui's cosmetic tie-break order).
px_ui:demo(otp_field, 19, \otp_field_demo).

%   Arity-0, so it is an ATOM -- called via the explicit \ escape, same
%   as every other component's demo template (a bare atom is a text
%   node, not a callable dispatch, in render/2 -- adr/0019). A real
%   `<form>` wrapping a 6-cell numeric field, with the hidden input's
%   live value echoed below it (updated by
%   assets/js/components/otp_field.js on every keystroke/paste) --
%   proves both HiddenInput's form participation AND the live-sync
%   behavior in one demo, plus a second, pre-filled + disabled field
%   for the disabled/value-prefill states.
otp_field_demo ~>
    div(class("px-otp-field-demo"),
      [ h3("6-cell numeric OTP -- autoComplete=\"one-time-code\" on the first cell only"),
        p([ "Type a digit to auto-advance; Backspace on an empty cell moves back; ",
            "paste a full code to fill every cell at once. The hidden input's live ",
            "value is echoed below as you type."
          ]),
        form(id("otp-demo-form"),
          [ otp_field([id("otp-demo"), name("otp"), auto_submit(false)]),
            p(class("px-otp-field-demo-readout"),
              [ "Hidden input value: ",
                code(id("otp-demo-readout"), "(empty)")
              ])
          ]),
        script([type(module)], raw("
document.addEventListener('input', function (event) {
  var hidden = event.target.closest('.px-otp-field-hidden-input');
  if (!hidden) return;
  var readout = document.getElementById('otp-demo-readout');
  if (!readout) return;
  readout.textContent = hidden.value === '' ? '(empty)' : hidden.value;
});
")),

        h3("Pre-filled + disabled"),
        p("value(\"123\") pre-fills the first three cells; disabled(true) marks every cell and the group."),
        otp_field([id("otp-demo-disabled"), name("otp_disabled"),
                   value("123"), disabled(true)])
      ]).
