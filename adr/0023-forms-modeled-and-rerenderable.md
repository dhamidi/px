# 0023. Forms: modeled once, validated purely, re-rendered from the same declaration

Status: Accepted

## Context

Version 1 of prologex had no form support at all. The demo ADR-browser
app was read-only: every request was a GET, every response was rendered
from data already on disk. The moment an app accepts a POST, three
problems appear at once and are traditionally solved in three different
places:

1. **Parsing and casting** — form bodies arrive as strings; the app
   wants numbers and booleans.
2. **Validation** — some inputs are wrong, and the app must say which
   and why.
3. **Re-rendering** — an invalid submission must come back as the same
   form, refilled with exactly what the user typed, with error messages
   next to the offending fields.

Rails solves this with `form_with` plus ActiveModel validations: the
model object carries typed attributes, error state, and enough metadata
for the form builder to render from. We want the same ergonomics without
the object. In prologex a form is a **declaration**, validation is a
**pure function over params**, and re-rendering **falls out of the same
declaration** — three problems, one term.

This ADR is bound by adr/0016 (the syntax north star): declarations are
directives, lookups are relations (rule 3); the directive captures the
declaring module so app code never writes `mymodule:pred` (rule 7). The
worked example in adr/0016 — `:- form(post_form, ...)`, the `create`
handler, `\form_for(post_form, posts_path, Values, Errors)` — is the
contract this ADR fills in. It builds on adr/0017 (`Env.params`),
adr/0018 (path helper terms and the `_method` override), and adr/0019
(`~>` templates and `\Helper` escapes). adr/0024 (Turbo) consumes the
422 flow specified here.

## Decision

### 1. Declaration: `:- form(Name, Fields)`

A form is declared with a directive. Each field is a
`field(FieldName, Widget, Constraints)` term:

```prolog
:- form(post_form,
     [ field(title, text,     [required, max_length(120)]),
       field(body,  textarea, [required])
     ]).
```

A larger declaration exercising the whole vocabulary:

```prolog
:- form(signup_form,
     [ field(name,     text,               [required, min_length(2), max_length(80)]),
       field(email,    email,              [required, format("^[^@\\s]+@[^@\\s]+$")]),
       field(password, password,           [required, min_length(12)]),
       field(age,      number,             [numeric, range(13, 130)]),
       field(plan,     select([free-"Free", pro-"Pro ($9)"]), [required]),
       field(country,  select(country_options), []),
       field(referrer, hidden,             []),
       field(handle,   text,               [required,
                                            check(handle_free, "is already taken")]),
       field(tos,      checkbox,           [required])
     ]).

% Called as handle_free(Value) in THIS module; failure = invalid.
handle_free(Handle) :-
    \+ row(q(users, [where(handle == Handle)]), _).

% Called as country_options(Options) in THIS module.
country_options(Options) :-
    findall(Code-Name, row(q(countries, [order_by(name)]), country{code: Code, name: Name}), Options).
```

**Widgets** (the closed vocabulary; widgets decide rendering and
casting):

| Widget | Renders as | Cast on `ok` |
|---|---|---|
| `text` | `<input type="text">` | string |
| `textarea` | `<textarea>` | string |
| `email` | `<input type="email">` | string |
| `password` | `<input type="password">` | string (never refilled — see §3) |
| `number` | `<input type="number">` | number |
| `checkbox` | `<input type="checkbox">` | `true` / `false` |
| `select(OptionsGoalOrList)` | `<select>` with `<option>`s | string (one of the option values) |
| `hidden` | `<input type="hidden">` | string |

`select/1` takes either a literal list — of `Value` atoms/strings or
`Value-Label` pairs — or the name of a predicate, called as
`Goal(Options)` in the declaring module, for options that come from the
database. In both cases the submitted value must be one of the option
values; a select carries an implicit `in(OptionValues)` check, so a
tampered `<option>` is a validation error, not an insert.

**Constraints** (the closed vocabulary):

| Constraint | Passes when | Default message |
|---|---|---|
| `required` | value present and non-empty (checkbox: checked) | `"is required"` |
| `max_length(N)` | at most N characters | `"must be at most N characters"` |
| `min_length(N)` | at least N characters | `"must be at least N characters"` |
| `numeric` | parses as a number | `"must be a number"` |
| `range(Lo, Hi)` | number, and `Lo =< V =< Hi` | `"must be between Lo and Hi"` |
| `format(Regex)` | value matches Regex (library(pcre); anchor it yourself) | `"is not in the expected format"` |
| `in(List)` | value is a member of List | `"is not a valid choice"` |
| `check(PredName)` | `PredName(Value)` succeeds | `"is invalid"` |
| `check(PredName, Message)` | `PredName(Value)` succeeds | `Message` |

`check/1,2` is the escape hatch into full Prolog: `PredName(Value)` is
called **in the declaring module**, captured at directive-expansion time
exactly as adr/0018 captures route handlers (north-star rule 7). Goal
failure means the field is invalid; `check/2` supplies the message shown
next to the field.

Evaluation rules, so error behavior is predictable:

- Constraints run in declaration order; the **first** failing constraint
  produces that field's single error. Multiple fields can each
  contribute one error.
- If a field is blank and not `required`, its remaining constraints are
  skipped (an optional `age` left empty is not "must be a number").
- `number` widgets imply `numeric`; a failed cast preserves the raw
  string in `Values` (so the user sees what they typed) and reports the
  `numeric` message.
- An unchecked checkbox is simply absent from the request (browsers omit
  it); it validates as `false`. `required` on a checkbox therefore means
  "must be checked" — the terms-of-service case.
- The `email` widget affects rendering and casting only; server-side
  address checking is whatever `format/1` or `check/1` you declare. The
  widget does not smuggle in an undocumented validator.

### 2. Validation is a pure function

Two predicates, one pure core:

```prolog
form_result(FormName, Env, Result)        % reads Env.params (adr/0017)
form_validate(FormName, ParamsDict, Result)  % the pure core
```

`form_result/3` is nothing but `form_validate(FormName, Env.params,
Result)` — it reads the env, it does not thread or modify it.
`form_validate/3` is a pure function from a params dict (atom keys,
string values, per adr/0017) to a result term, which makes every form
unit-testable without an HTTP request, a socket, or a running server:

```prolog
Result = ok(Values)
       | invalid(Values, Errors)
```

- In `ok(Values)`, `Values` is a dict of **typed, cast** values:
  `number` fields are Prolog numbers, checkboxes are `true`/`false`,
  everything else is a string. It contains **only declared fields** —
  undeclared params are dropped, so `Values` is safe to hand straight to
  `insert/3` (adr/0020). Strong-parameter filtering is not a separate
  API; it is what the declaration means.
- In `invalid(Values, Errors)`, `Values` preserves **exactly what the
  user typed** — raw strings, including the `"12x"` that failed the
  numeric cast — because its only job is re-rendering the form.
  Declared fields absent from the params appear as `""` (checkboxes as
  `false`). `Errors` is a list of `error(Field, Message)` terms in field
  declaration order.

A validation example with two errors:

```prolog
?- form_validate(post_form,
                 _{ title: "",
                    body:  "A post with no title and, sadly, no luck." },
                 R).
R = invalid(_{ title: "",
               body:  "A post with no title and, sadly, no luck." },
            [ error(title, "is required") ]).

?- form_validate(signup_form,
                 _{ name: "D", email: "dario@example.com",
                    password: "correct horse battery staple",
                    age: "12x", plan: "pro", handle: "dario", tos: "on" },
                 R).
R = invalid(_{ name: "D", email: "dario@example.com",
               password: "correct horse battery staple",
               age: "12x", plan: "pro", country: "",
               referrer: "", handle: "dario", tos: true },
            [ error(name, "must be at least 2 characters"),
              error(age,  "must be a number") ]).
```

And the happy path, showing the casts:

```prolog
?- form_validate(signup_form,
                 _{ name: "Dario", email: "dario@example.com",
                    password: "correct horse battery staple",
                    age: "38", plan: "pro", handle: "dario", tos: "on" },
                 R).
R = ok(_{ name: "Dario", email: "dario@example.com",
          password: "correct horse battery staple",
          age: 38, plan: "pro", country: "",
          referrer: "", handle: "dario", tos: true }).
```

Note `age: 38` (a number, not `"38"`) and `tos: true`.

### 3. Rendering from the same declaration

The template helper (adr/0019 `\Goal` escape):

```prolog
\form_for(FormName, ActionPathTerm, Values, Errors)
```

walks the declared fields in order and streams the complete form:
`<form>` open tag, then per field a label, the widget-appropriate input
with its value **refilled from `Values`**, and that field's error
message (if any) adjacent to it; then a submit button and the closing
tag. One declaration, and both the empty GET form and the errored 422
form come out of it.

**Action and method.** `ActionPathTerm` is a path-helper term from
adr/0018 — `posts_path`, `post_path(Id)` — never a string literal. A
bare path term means `method="post"`. To use another verb, wrap the
path term in the method:

```prolog
\form_for(post_form, posts_path, Values, Errors)            % POST /posts
\form_for(post_form, patch(post_path(Id)), Values, Errors)  % PATCH via override
```

Since HTML forms speak only GET and POST, `patch/1`, `put/1`, and
`delete/1` render as `method="post"` plus the adr/0018 method-override
hidden input:

```html
<input type="hidden" name="_method" value="patch">
```

**Naming conventions.** The input `name` is the bare field name; the
`id` is the form name and field name joined with `_`; the label's `for`
matches the id; the label text is the field name humanized (underscores
to spaces, first letter capitalized):

```
name="title"    id="post_form_title"    <label for="post_form_title">Title</label>
```

The bare `name` is what makes `Env.params.title` and the
`form_validate/3` params dict line up with no mapping layer.

**Rendered sketch** — the `title` field after a too-long submission:

```html
<div class="field field-error">
  <label for="post_form_title">Title</label>
  <input type="text" name="title" id="post_form_title"
         value="An exhaustive, complete, and frankly excessive history of …">
  <p class="error">must be at most 120 characters</p>
</div>
```

Fields without an error render the same minus the `field-error` class
and the `<p>`. Refilled values pass through adr/0019's auto-escaping
like any other string, so a user typing `"><script>` gets their text
back, inert. Exception: **`password` widgets are never refilled** — the
value stays in `Values` for validation, but `\form_for` and
`\field_input` do not emit a `value` attribute for them.

**The escape hatch.** `\form_for` is the 80% path. When the layout,
label text, or field grouping must be custom, hand-write the form and
use the per-field helper:

```prolog
\field_input(FormName, FieldName, Values, Errors)
```

which emits only the input element for that field — correct widget,
`name`, `id`, refilled value — followed by its adjacent error message
if `Errors` contains one. The surrounding `<form>` tag, labels,
wrappers, and submit button are yours (the fixed id convention means a
hand-written `label(for(post_form_title), ...)` always matches):

```prolog
post_form_view(Values, Errors) ~>
    form([method(post), action(posts_path)],
      [ fieldset(
          [ label(for(post_form_title), "Headline"),
            \field_input(post_form, title, Values, Errors)
          ]),
        fieldset(
          [ label(for(post_form_body), "Your story"),
            \field_input(post_form, body, Values, Errors)
          ]),
        button(type(submit), "Publish")
      ]).
```

Same declaration, same validation, same refill and error placement —
only the markup around the inputs changed.

### 4. The full loop

The north star's handlers, spelled out end to end. One template serves
both states — the empty form and the errored re-render:

```prolog
:- resources(posts).   % defines new_post_path, posts_path, ... (adr/0018)

:- form(post_form,
     [ field(title, text,     [required, max_length(120)]),
       field(body,  textarea, [required])
     ]).

post_form_view(Values, Errors) ~>
    \form_for(post_form, posts_path, Values, Errors).

%% GET /posts/new — the empty form: empty values, no errors.
new(Env0, Env) :-
    respond(Env0, view(post_form_view(_{}, [])), Env).

%% POST /posts — the create handler from adr/0016, verbatim.
create(Env0, Env) :-
    form_result(post_form, Env0, Result),
    (   Result = ok(Values)
    ->  insert(posts, Values, Id),
        turbo_or_redirect(Env0, post_path(Id),
            [ prepend(posts, post_card(Values.put(id, Id))) ], Env)
    ;   Result = invalid(Values, Errors)
    ->  respond(Env0, view(post_form_view(Values, Errors)),
                [status(422)], Env)
    ).
```

The two branches:

- **`ok(Values)`** — `Values` is typed and contains only declared
  fields, so it goes straight into `insert/3`. The success response is a
  redirect to the new resource; a redirect after a POST is **303 See
  Other**, so the browser re-fetches with GET and a reload never
  re-submits the form. (`turbo_or_redirect/4` degrades to exactly this
  303 for non-Turbo clients; adr/0024.)
- **`invalid(Values, Errors)`** — respond **422 Unprocessable Content**
  and re-render `post_form_view/2` — the **same view the GET used** —
  with the user's raw values and the error list. No separate "error
  page", no session flash, no redirect-with-repopulation dance: the
  declaration that parsed the params renders them back.

This 422-plus-re-render is also precisely the shape Turbo expects for a
failed form submission: when the form lives inside a `turbo_frame`, the
422 response's re-rendered form replaces just that frame in place,
errors and all, with no full page load. The frame mechanics belong to
adr/0024; this ADR's only obligation to Turbo is already met by
returning 422 with the re-rendered view, which we do for plain HTML
reasons anyway.

### 5. CSRF: future work, stated plainly

This ADR does **not** ship CSRF protection, and it does not pretend to.
Real protection means same-origin, cookie-based session CSRF tokens — a
token minted into the session, embedded by `\form_for` as a hidden
input, and verified before `form_result/3` runs — and prologex has no
session layer yet to hang that on. Designing the token scheme before the
session scheme would be designing in the dark, so we decline to fake it.

What bounds the exposure today: the demo runs behind exe.dev's
authenticated HTTPS proxy (adr/0012), so unauthenticated third-party
pages cannot reach the app's endpoints at all. That is a deployment
accident, not a security design, and it does not protect a prologex app
deployed anywhere else. Until the session ADR lands and `\form_for`
grows its token input, **do not put a prologex form on the open
internet**. The forward-compatible note: the token will be one more
hidden input emitted by `\form_for` and one more check inside
`form_result/3` — the API surface in this ADR will not change.

## Consequences

- **One declaration, four jobs.** The `:- form/2` term is the single
  source of truth for parsing, casting, validating, and rendering.
  Adding `field(summary, text, [max_length(200)])` to `post_form` is a
  one-line change that simultaneously adds the input to the rendered
  form, the param to the accepted set, the constraint to validation,
  and the key to `ok(Values)`. In v1 there was nothing to change — the
  demo app was read-only because every one of those four jobs would
  have been hand-written.
- **Mass-assignment safety by construction.** `ok(Values)` contains
  only declared fields; there is no `permit`/strong-parameters ritual
  to forget.
- **Testability.** `form_validate/3` is pure — forms are tested with
  plain queries over dicts, no HTTP in sight.
- **One template, both states.** GET-new and POST-422 render the same
  view; there is no drift between "the form" and "the form with
  errors", and the 422 body is Turbo-ready for free (adr/0024).
- **The vocabularies are closed but extensible through `check/1,2`.**
  No `file`, `date`, or multi-select widgets yet, no nested or array
  fields; when they are needed they extend these shapes (new widget
  terms, new constraint terms) rather than a parallel API — north-star
  rule for every subsystem.
- **One error per field.** First failing constraint wins; users fix
  fields one message at a time. Cheap, predictable, revisitable if it
  ever grates.
- **CSRF is a known, flagged gap** (§5), acceptable only behind the
  authenticated proxy, blocking for any public deployment.
