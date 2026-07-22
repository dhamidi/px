# 0011. Markdown: DCG parsing scope, and reusing html_write for output

Status: Accepted

## Context

The demo app's whole job is to turn this project's own ADR markdown files
into HTML and serve them. That splits into two separable questions.
First, how much of Markdown to actually parse — CommonMark is a large
spec, and ADR-0001 already commits the demo to dogfooding whatever subset
gets chosen on every file in `adr/`, including this one. Second, once a
markdown file has been parsed into some in-memory representation, how to
turn that representation into HTML bytes: write a renderer by hand, or
reach for something already in SWI-Prolog.

The project's general stance, laid out in ADR-0002 and ADR-0004, is to
build the framework itself from scratch — routing, middleware, HTTP
transport, streaming, and now markdown parsing all get bespoke Prolog
because building them is the point of the experiment. HTML generation
does not obviously belong on that list. It is worth asking, separately
from the parsing question, whether emitting HTML is something this
project is actually trying to demonstrate, or just a step it has to get
through.

## Decision

**Scope of the markdown parser.** `prolog/markdown/parser.pl` implements
a DCG that parses a real subset of CommonMark, not the full spec and not
a toy flattened one. In scope: headings, paragraphs, emphasis and strong
emphasis, inline code spans, fenced and indented code blocks, links,
images, ordered and unordered lists including nesting, blockquotes
including nesting, horizontal rules, and hard line breaks. The DCG
produces an AST of Prolog terms/dicts describing document structure —
`heading(1, [...])`, `list(ordered, [Item, ...])`, and so on — not HTML
or any other output format.

Explicitly out of scope: tables, footnotes, regex-based bare-URL
autolinking, and raw HTML passthrough. These are GFM extensions layered
*on top of* CommonMark, not part of the CommonMark spec this project
targets, so leaving them out is a scope line drawn deliberately, not a
shortcut taken because they were hard. If ADR content ever needs them,
that is a decision to revisit, not an oversight to patch around.

**HTML generation.** `prolog/markdown/html.pl` walks the AST and emits
HTML using SWI-Prolog's own `library(http/html_write)` — its `html//1`
DCG combinators — rather than hand-rolled string concatenation or a
second bespoke templating layer built alongside the markdown parser.

This is a deliberate, scoped exception to building the framework from
scratch. Routing, HTTP transport, and markdown parsing are what this
project exists to demonstrate; turning an already-parsed AST into HTML
tags is not. `library(http/html_write)` is exactly the kind of library
that ships with `swipl` and that this project is supposed to lean on
instead of reinventing, and it earns its place further by handling
HTML-escaping correctly by construction — text pulled out of code spans,
link titles, and image alt text goes through `html_write`'s own escaping
instead of a hand-rolled escaper that is one missed character class away
from an HTML injection bug.

## Consequences

The AST produced by `parser.pl` is shaped around document structure —
headings, paragraphs, lists, emphasis — with no HTML in it anywhere. It
was designed independently of `html_write` or any other particular
output target, so retargeting to a different renderer later, or adding a
second output format, would mean writing a new AST-to-X module without
touching the parser at all.

The CommonMark-subset boundary is a real limitation, not just a stated
one: any ADR that ever needs a table will render wrong, since tables are
not parsed at all. That is acceptable today because no ADR in this
project uses one, but it means table syntax must stay off the table (so
to speak) for as long as `parser.pl` doesn't support it, and any future
ADR author needs to know that boundary exists before reaching for GFM
syntax out of habit.

Depending on `library(http/html_write)` means the project's from-scratch
claim applies to HTTP transport, routing, and markdown parsing, and
explicitly not to HTML generation — a distinction worth keeping straight
when describing what this project demonstrates. It also means
`html.pl`'s correctness is partly borrowed from a well-exercised standard
library module rather than fully owned by this codebase, which is the
intended trade: one less hand-rolled escaper is one less place for a
security bug to hide.
