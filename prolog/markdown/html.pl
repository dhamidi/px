:- module(md_html, [ast_to_html_string/2]).

:- use_module(library(http/html_write)).
:- use_module(library(lists)).

/** <module> Render a markdown AST (see parser.pl) to an HTML string.

Per adr/0011 this module reuses SWI-Prolog's own library(http/html_write)
--  its html//1 DCG combinators -- to actually produce HTML tags, rather
than hand-rolling string concatenation or a second templating layer next
to the markdown parser. That is a deliberate, scoped exception to this
project's usual "build it ourselves" stance: html_write is exactly the
kind of thing that ships with swipl and is worth leaning on, and it
earns its place further by escaping text correctly by construction --
every piece of text pulled out of the AST (paragraph text, code span
contents, link text, image alt text, ...) is passed to html//1 as a
plain Prolog string, which html_write escapes for us, instead of going
through a hand-rolled escaper.

ast_to_html_string/2 is the only entry point the rest of the pipeline
needs. Internally, block_term/2 and inline_html_term/2 walk the AST
terms documented in parser.pl and build the corresponding html_write DSL
term (the Spec argument html//1 takes, e.g. `p(["some text"])`) --
recursively, so a nested list or blockquote just becomes a nested
html_write term, e.g. `ul([li([...]), li([...ul([...])])])`. Only once
the whole document has been turned into one such term is html//1 itself
invoked, via phrase/2, to turn it into HTML tokens, which print_html/1
then renders to a string.
*/

%!  ast_to_html_string(+AST:list, -HtmlString:string) is det.
%
%   Render a list of block-level AST terms (see parser.pl) to an HTML
%   string.

ast_to_html_string(AST, HtmlString) :-
    maplist(block_term, AST, Terms),
    phrase(html(Terms), Tokens),
    with_output_to(string(HtmlString), print_html(Tokens)).

%!  block_term(+Block, -HtmlTerm) is det.
%
%   Translate one block-level AST term (see parser.pl) into an
%   html_write DSL term.

block_term(heading(Level, Spans), HeadingTerm) :-
    inline_html_terms(Spans, Content),
    heading_tag(Level, Tag),
    HeadingTerm =.. [Tag, Content].
block_term(paragraph(Spans), p(Content)) :-
    inline_html_terms(Spans, Content).
block_term(code_block(Lang, Text), Term) :-
    code_block_html(Lang, Text, Term).
block_term(list(ordered, Items), ol(ItemTerms)) :-
    maplist(item_term, Items, ItemTerms).
block_term(list(unordered, Items), ul(ItemTerms)) :-
    maplist(item_term, Items, ItemTerms).
block_term(blockquote(Blocks), blockquote(Terms)) :-
    maplist(block_term, Blocks, Terms).
block_term(hr, hr([])).

heading_tag(1, h1).
heading_tag(2, h2).
heading_tag(3, h3).
heading_tag(4, h4).
heading_tag(5, h5).
heading_tag(6, h6).

code_block_html(none, Text, pre([code([Text])])).
code_block_html(Lang, Text, pre([code([class=Class], [Text])])) :-
    Lang \== none,
    string_concat("language-", Lang, Class).

item_term(BlockList, li(Terms)) :-
    maplist(block_term, BlockList, Terms).

%!  inline_html_terms(+Spans:list, -Terms:list) is det.
%
%   Translate a list of inline-level AST terms (see parser.pl) into a
%   list of html_write DSL terms/strings suitable to appear as the
%   content argument of an html//1 element.

inline_html_terms(Spans, Terms) :-
    maplist(inline_html_term, Spans, Terms).

inline_html_term(text(S), S).
inline_html_term(emph(Spans), em(Content)) :-
    inline_html_terms(Spans, Content).
inline_html_term(strong(Spans), strong(Content)) :-
    inline_html_terms(Spans, Content).
inline_html_term(code(S), code([S])).
inline_html_term(link(Spans, Url), a([href=Url], Content)) :-
    inline_html_terms(Spans, Content).
inline_html_term(image(Alt, Url), img([src=Url, alt=Alt])).
inline_html_term(linebreak, br([])).
