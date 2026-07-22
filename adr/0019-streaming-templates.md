# 0019. Streaming templates: `~>` renders terms straight to the wire

Status: Accepted

## Context

Version 1 produced HTML two ways, and both buffer.

The demo app built pages with `format/3` string templates — the
"format-string spaghetti" that adr/0016 names as a thing to kill.
Escaping was the caller's problem, structure lived inside quoted
strings, and nothing could be composed or traced.

The markdown pipeline (`prolog/markdown/html.pl`, per adr/0011) did
better by reusing SWI-Prolog's `library(http/html_write)`. But look at
what that pipeline actually does:

```prolog
ast_to_html_string(AST, HtmlString) :-
    maplist(block_term, AST, Terms),
    phrase(html(Terms), Tokens),                       % term -> token LIST
    with_output_to(string(HtmlString), print_html(Tokens)).  % list -> STRING
```

`html//1` is a DCG: it materializes the *entire* document as a token
list, then `print_html/1` renders that list, here captured into yet
another in-memory string before a single byte reaches the socket. For
a page built from 10,000 database rows, the whole page exists in
memory — twice — before the client sees anything.

That contradicts the project's founding rule. adr/0007 built the
response side so that `Swrite` on the response `IOSTREAM` triggers
`uv_write` directly on the owning worker's thread — bodies are
streams, never byte buffers. adr/0016 rule 5 extends that rule
explicitly to HTML: *bytes stream; terms may nest*. And rule 2 grants
the template layer this project's entire operator budget: exactly one
new operator, `~>`.

The design inspiration is Phlex (https://www.phlex.fun/): Ruby view
components that *write* HTML progressively as methods execute, rather
than interpolating strings into a document that is assembled and
returned at the end. This ADR is that idea translated into Prolog —
where "component" becomes "clause", "method dispatch" becomes
"unification", and "write to the buffer" becomes "write to the
response stream".

## Decision

### 1. The `~>` operator defines templates as ordinary clauses

```prolog
:- op(1100, xfx, ~>).
```

`Head ~> Body` is term-expanded into a template clause. `Head` is an
ordinary predicate head — which means templates unify and
pattern-match like any Prolog clause. Two clauses of the same template
select on their arguments:

```prolog
status_badge(draft) ~>
    span(class('badge badge-muted'), "Draft").

status_badge(published) ~>
    span(class('badge badge-live'), "Published").
```

Rendering `status_badge(Post.status)` picks the right clause by
clause selection, exactly as `member/2` picks clauses. Phlex needs an
`if`/`case` inside a component method for this; Prolog gets it from
the resolution mechanism it already has. Guards work too, because a
template head is just a head — put the discrimination in the head, or
add a catch-all clause last:

```prolog
comment_count(0) ~> p(class(muted), "No comments yet").
comment_count(1) ~> p("1 comment").
comment_count(N) ~> p([text(N), " comments"]).
```

### 2. The body term language

A template body is a plain Prolog term. Any HTML5 element name is
usable as a functor, in one of two shapes:

```prolog
div(Children)              % children only
div(Attrs, Children)       % attributes, then children
```

**Attributes** are either a single term or a list of terms:

```prolog
article(class(card), ...)
article([class(card), id(post-7), data_turbo_frame(comments)], ...)
```

Attribute functor names map to attribute names with underscores
rewritten to dashes: `data_turbo_frame` emits `data-turbo-frame`,
`aria_label` emits `aria-label`. Attribute values may be atoms,
strings, numbers, compound terms (written back in standard operator
notation, so `id(post-7)` emits `id="post-7"`), or dict field
accesses (`id(Post.slug)`). Values are always escaped.

**Children** may be:

- a list — rendered in order;
- a string, atom, or number — a text node;
- a nested element term;
- a template or helper call — bare, or under the explicit `\Goal`
  escape (section 3).

Text nodes are **always HTML-escaped**. `&` becomes `&amp;`, `<`
becomes `&lt;`, `>` becomes `&gt;`; attribute values additionally
escape `"` as `&quot;`.

```prolog
p("Fish & <chips>")
```

emits

```html
<p>Fish &amp; &lt;chips&gt;</p>
```

There is deliberately **no unescaped-string form** — no
raw-by-default, no "safe string" wrapper type, no escape-toggling
option list. The single exception is an explicit term:

```prolog
raw(HtmlString)      % written verbatim; the only unescaped door
```

`raw/1` exists for one honest reason: the v1 markdown renderer
(`md_html:ast_to_html_string/2`, adr/0011) produces an
*already-escaped HTML string* via `library(http/html_write)`, and its
output has to enter a template somewhere without being escaped a
second time. `markdown/1` (below) is built on it. Anything passed to
`raw/1` is on the wire byte-for-byte, so the rule for app code is: if
you did not get the string from a renderer that escapes by
construction, you do not pass it to `raw/1`.

Void elements (`br`, `hr`, `img`, `meta`, `link`, `input`, ...) are
known to the renderer: their single-argument form is attributes, no
closing tag is emitted, and giving one children is a load-time error.

```prolog
img([src(Post.cover_url), alt(Post.title)])
hr([])
```

### 3. Composition — bare calls, and the built-in helpers

A compound term in a body whose functor is not a whitelisted HTML5
element is a call: it renders another template (a matching `~>`
clause), or invokes a helper (the `render_helper/2` hook) — in that
order, element first, then template, then helper; a term that
resolves to none of the three is an error. This is the Prolog form
of Phlex's component nesting — a template's output appears inside
another template at the point of the call, written to the same
stream, with nothing intermediate materialized. `\Goal` remains as
an explicit escape — the same template-then-helper resolution,
skipping the element check — kept for backward compatibility and as
a disambiguation hatch; it is never wrong and never needed in
ordinary app code.

```prolog
post_card(Post) ~>
    article(class(card),
      [ h2(link_to(Post.title, post_path(Post.id))),
        status_badge(Post.status),
        p(Post.summary)
      ]).
```

The built-in helpers specified by this ADR:

- `each(List, Template)` — call `Template` on each element of
  `List`, in order. `each(Posts, post_card)` renders
  `post_card(P)` for every `P`. Each element's bytes are written
  before the next element is even looked at.
- `link_to(Text, PathTerm)` — an anchor. `PathTerm` is a reversible
  path term per adr/0018 (`post_path(7)`, `new_post_path`), resolved
  through the router — never a path string literal. `Text` is
  escaped like any text node.
- `form_for(Form, PathTerm, Values, Errors)` — renders a declared
  form; specified in adr/0023.
- `markdown(String)` — bridges the v1 markdown engine: parses
  `String` with the CommonMark-subset DCG (adr/0011), renders the AST
  with `md_html`, and emits the result through `raw/1`.
- `text(Term)` — writes `Term` as an escaped text node; useful when
  a number or computed term sits next to literal text in a list.

Dict field access works anywhere a value can appear in a body:
`Post.title` as a text node, `post_path(Post.id)` inside a helper,
`href(Post.url)` as an attribute value. The `~>` expander rewrites
dot-expressions into render-time `get_dict/3` lookups.

Bare calls are the user-facing surface: adr/0016's worked example
writes `layout("Posts", [...])`, `each(Posts, post_card)` and
`turbo_frame(...)` with no sigil anywhere. Because element names win
this resolution, a template or registered helper may not be named
after a whitelisted HTML5 element — it could never be called — and
that shadowing is rejected at load time: expansion rejects
`section(X) ~> ...` and an element-named `render_helper/2`
registration alike. That load-time rule is what makes the sigil
unnecessary.

### 4. Rendering streams — that is the whole point

`render(Stream, Term)` walks the body term and **writes as it goes**.
When rendering `post_card(Post)` above, the bytes
`<article class="card">` are on the wire before `link_to` has been
called, before `Post.title` has been looked up — before the first
child is evaluated at all. Open tag out, children rendered (each one
streaming in turn), close tag out. There is no token list, no output
string, no `with_output_to/2`, anywhere in the pipeline. An `each`
over 10,000 rows writes 10,000 cards' worth of bytes while holding
one card's term at a time; the page never exists in memory because
there is no "the page" — only a term being walked and a socket being
written.

Contrast the two things it replaces:

```prolog
% library(http/html_write) (v1 markdown path): whole-document passes
phrase(html(Spec), Tokens),                 % ALL tokens, in memory
with_output_to(string(S), print_html(Tokens)),  % ALL bytes, in memory
% ... and only now does anything reach the socket.

% v1 demo app: format-string spaghetti
format(Stream, "<article class=\"card\"><h2>~w</h2>", [Title]).
% streams, technically -- but structure is inside a quoted string,
% and ~w just injected unescaped Title into the page.
```

Streaming templates keep the *structure* of the html_write approach
(terms, escaping by construction) and the *delivery* of the format
approach (bytes go out as they are produced), with the flaws of
neither.

**Interaction with adr/0017.** `Env.response.body` holds the
*unrendered term* — `view(post_show(Post))` — all the way through the
middleware chain. Middleware can inspect it, wrap it, or replace it,
because it is still a term. The transport edge calls
`render(Stream, Term)` exactly once, after the chain completes, on
the response `IOSTREAM` from adr/0007. Rendering therefore runs on
the owning worker's thread, where `Swrite` legally drives `uv_write`
on that worker's loop; per adr/0006, a template that blocks (a slow
template call, say) stalls its worker like any other blocking handler code.

**The honest trade-off.** Streaming means commitment. Once the status
line and the first body bytes are on the wire, they cannot be
unwritten — so an exception raised mid-render *cannot* become a clean
`500 Internal Server Error`. The client gets `200 OK` followed by a
truncated document (and, under chunked encoding, a missing terminal
chunk, which conforming clients do detect as an incomplete response).
This is the price of never buffering, and this ADR documents it
rather than hiding it. Mitigations — for example guarding the header
flush so that the status line is only committed once the outermost
template clause has been resolved, catching the cheap class of errors
(missing template, bad dict key) while they can still become a 500 —
are future work, not part of this decision.

### 5. `layout/2` is just another template

There is no layout subsystem, no yield, no content-block registry. A
layout is a template that takes content as an argument:

```prolog
layout(Title, Content) ~>
    html(
      [ head(
          [ meta(charset('utf-8')),
            title(Title),
            link([rel(stylesheet), href('/app.css')])
          ]),
        body(
          [ header(nav(link_to("Home", root_path))),
            main(Content),
            footer(p("served by prologex"))
          ])
      ]).

post_index(Posts) ~>
    layout("Posts",
      [ h1("All posts"),
        div(id(posts), each(Posts, post_card))
      ]).
```

`Content` is an ordinary child term; `main(Content)` streams it in
place like anything else. Want two layouts? Write two templates.
Want a layout that varies by a flag? Write two clauses of the same
template — clause selection is the feature, again.

### 6. Implementation shape

`~>` is consumed by `term_expansion/2`. Each `Head ~> Body` becomes a
clause of an internal `template_body/2`, with the defining module
captured at expansion time (adr/0016 rule 7 — no user-visible module
qualification):

```prolog
%  status_badge(draft) ~> span(class('badge badge-muted'), "Draft").
%
%  expands to, roughly:
prologex_template:template_body(app:status_badge(draft),
                                span(class('badge badge-muted'), "Draft")).
```

`render/2` is a small dispatcher over the shapes in section 2:

```prolog
render(S, \Goal)     :- !, render_call(S, Goal).          % explicit escape
render(S, raw(Text)) :- !, write(S, Text).                % the only unescaped path
render(S, Text)      :- text_node(Text), !, write_escaped(S, Text).
render(S, Term)      :-
    Term =.. [Name|Args],
    (   html5_element(Name)
    ->  render_element(S, Name, Args)                     % open, children, close
    ;   render_call(S, Term)                              % bare template/helper call
    ).
```

with `render_element/3` doing the open-tag write *before* touching
children — the line that makes rule 5 true:

```prolog
render_element(S, Tag, [Attrs, Children]) :-
    format(S, "<~w", [Tag]),
    render_attrs(S, Attrs),
    write(S, ">"),                 % on the wire NOW
    render(S, Children),
    format(S, "</~w>", [Tag]).
```

Validation happens at expansion time where it can: element arities
(more than two arguments to an element is a load error), children
handed to a void element, attribute functors that are neither known
HTML attributes nor `data_*`/`aria_*` shaped, a template head named
after an HTML5 element, and malformed `\` escapes are all rejected
when the file loads. A typo'd element name (`dvi(...)`) necessarily
parses as a template reference, so it cannot be rejected at the point
of expansion — instead the expander records every referenced template
functor, and `prologex_run` verifies at startup that each one has a
`template_body/2` clause or is a built-in helper. Either way the typo
is caught at load/startup and reported with its source location — not
silently emitted as a bogus tag, and not discovered as a truncated
page in production.

Dict expressions are rewritten by the expander into positions the
renderer evaluates with `get_dict/3` at render time, so `Post.title`
in a body costs one dict lookup when reached, and a missing key is an
error at the offending template clause.

## Consequences

Format-string HTML is dead in app code. The v1 demo app's `format/3`
page-building is rewritten onto `~>` templates as part of the
adr/0016 rework, and the syntax gives user code no string-assembly
path to reach for: structure is terms, text is escaped, and the only
way to emit unescaped bytes is to type `raw` and mean it. That makes
HTML injection an opt-in bug instead of a default one.

`prolog/markdown/html.pl` keeps `library(http/html_write)` internally
for now — adr/0011's reuse decision stands — and its output enters
templates through `markdown/1`, which wraps the rendered string in
`raw/1`. That means one buffered island remains: a markdown document
is materialized as a string before streaming out. Acceptable, because
ADR-sized documents are small; porting `md_html` to emit template
terms (or to stream directly) so the island disappears is noted as
future work, not done here.

Templates are ordinary clauses, so ordinary Prolog tools apply:
`listing(template_body/2)` shows the expanded clauses, `trace/0`
steps through clause selection and rendering, and a failing template
fails like a failing predicate — with a location, not with a
half-interpolated string. There is no separate template debugger
because there is no separate template runtime.

The costs are accepted and stated: the project's one-operator budget
(adr/0016 rule 2) is now spent; element-name resolution reserves the
HTML5 element namespace against template names; and mid-render errors
truncate responses instead of becoming clean 500s, with
header-flush guarding left as future work.
