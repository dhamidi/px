:- module(md_parser, [markdown_to_ast/2]).

:- use_module(library(dcg/basics)).
:- use_module(library(lists)).

/** <module> Markdown to AST parser (a real subset of CommonMark). See
    adr/0011.

markdown_to_ast/2 is the only entry point the rest of the pipeline needs.
Everything else in this file is the DCG that gets it there: a block-level
grammar that consumes the document one *line* at a time (the document is
split on "\n" before parsing starts, so the block grammar's terminals are
whole lines, not characters), and an inline-level grammar, built on top
of library(dcg/basics), that consumes the *characters* of a single piece
of run-together text to find emphasis, code spans, links, images, and so
on.

Block-level constructs that span several lines (fenced code, blockquotes,
list items) are parsed by having the block DCG consume a run of raw
lines, then recursively re-invoking the block grammar (via phrase/2) on
that inner slice of lines -- once dedented, in the case of list items and
blockquotes. This is what makes nesting (a list inside a list, a
blockquote inside a blockquote) fall out of the grammar for free instead
of needing bespoke recursion-depth-tracking code.

## AST term shapes

Block-level terms (a document is a plain list of these):

  * heading(+Level:integer, +Spans:list)        -- ATX heading, Level 1-6
  * paragraph(+Spans:list)
  * code_block(+Lang, +Text:string)             -- Lang is a string (the
    fence info-string's first word) or the atom `none`; Text is the
    literal code text (no trailing newline), one string with embedded
    "\n" separating lines
  * list(+Kind, +Items:list)                    -- Kind is `ordered` or
    `unordered`; each element of Items is itself a list of block-level
    terms (the item's own content, recursively parsed -- this is how a
    nested sub-list ends up as a list(...) term inside an Item)
  * blockquote(+Blocks:list)                    -- Blocks is a list of
    block-level terms (recursively parsed; nested blockquotes show up as
    a blockquote(...) term inside Blocks)
  * hr                                          -- thematic break

Inline-level terms (Spans lists above are lists of these):

  * text(+String)                               -- plain run of text
  * emph(+Spans:list)                           -- *x* or _x_
  * strong(+Spans:list)                         -- **x** or __x__
  * code(+String)                                -- `code`, string taken
    verbatim (no nested inline parsing inside a code span)
  * link(+Spans:list, +Url:string)              -- [text](url), text is
    itself recursively parsed for nested emphasis etc.
  * image(+Alt:string, +Url:string)             -- ![alt](url), alt text
    is plain text, not further parsed
  * linebreak                                   -- hard line break (line
    ended in "\\" or two-or-more trailing spaces)

html.pl pattern-matches on exactly these term shapes, so any change here
must be made in both files.
*/

%!  markdown_to_ast(+MarkdownString, -AST:list) is det.
%
%   Parse MarkdownString (an atom or string) into a list of block-level
%   AST terms, per the shapes documented above.

markdown_to_ast(MarkdownString, AST) :-
    normalize_newlines(MarkdownString, Normalized),
    split_string(Normalized, "\n", "", Lines),
    phrase(blocks(AST), Lines).

normalize_newlines(In, Out) :-
    ( string(In) -> S0 = In ; atom_string(In, S0) ),
    split_string(S0, "", "", [S1]),          % coerce to a plain string
    split_string(S1, "\r\n", "", Parts0),    % swallow CRLF pairs first
    ( Parts0 = [_] -> Out = S1
    ; atomics_to_string_joined(Parts0, "\n", Out)
    ).

atomics_to_string_joined([X], _, X) :- !.
atomics_to_string_joined([X|Xs], Sep, Out) :-
    atomics_to_string_joined(Xs, Sep, Rest),
    string_concat(X, Sep, T0),
    string_concat(T0, Rest, Out).

%!  peek_rest(-Rest, +S0, ?S) is det.
%
%   DCG helper: unify Rest with the list of terminals not yet consumed,
%   without consuming anything. Lets block//1 look ahead at the raw
%   remaining lines, decide (in ordinary Prolog) how many of them belong
%   to the construct starting here, and then consume exactly that many
%   via consume_n//1.

peek_rest(L, L, L).

consume_n(0) --> [].
consume_n(N) --> [_], { integer(N), N > 0, N1 is N - 1 }, consume_n(N1).

% ---------------------------------------------------------------------
% Block grammar
% ---------------------------------------------------------------------

blocks(Bs) -->
    [L], { is_blank(L) }, !, blocks(Bs).
blocks([B|Bs]) -->
    block(B), !, blocks(Bs).
blocks([]) -->
    [].

block(heading(Level, Spans)) -->
    [L], { atx_heading(L, Level, Text) }, !,
    { parse_inline(Text, Spans) }.
block(hr) -->
    [L], { is_hr(L) }, !.
block(code_block(Lang, Text)) -->
    [L], { fence_marker(L, Lang) }, !,
    fenced_lines(RawLines),
    { join_with_nl(RawLines, Text) }.
block(blockquote(Blocks)) -->
    [L], { quote_line(L, C0) }, !,
    quote_rest(Rest),
    { phrase(blocks(Blocks), [C0|Rest]) }.
block(list(Kind, Items)) -->
    peek_rest([L|_]), { list_marker(L, Kind, _, _) }, !,
    list_block(Kind, Items).
block(code_block(none, Text)) -->
    [L], { indent_at_least(L, 4, C0) }, !,
    indented_rest(RestConts),
    { trim_trailing_blank_lines([C0|RestConts], Trimmed),
      join_with_nl(Trimmed, Text)
    }.
block(paragraph(Spans)) -->
    para_lines(Lines), { Lines \= [] },
    { join_lines_for_inline(Lines, Text), parse_inline(Text, Spans) }.

% -- fenced code -------------------------------------------------------

fenced_lines([]) -->
    [L], { fence_marker(L, _) }, !.
fenced_lines([L|Ls]) -->
    [L], fenced_lines(Ls).
fenced_lines([]) -->
    [].

% -- indented code -------------------------------------------------------

indented_rest([C|Cs]) -->
    [L], { indent_at_least(L, 4, C) }, !, indented_rest(Cs).
indented_rest([""|Cs]) -->
    [L], { is_blank(L) }, !, indented_rest(Cs).
indented_rest([]) -->
    [].

% -- blockquote ---------------------------------------------------------

quote_rest([C|Cs]) -->
    [L], { quote_line(L, C) }, !, quote_rest(Cs).
quote_rest([]) -->
    [].

% -- lists ----------------------------------------------------------------

list_block(Kind, [Item|Items]) -->
    list_one_item(Kind, ItemLines), !,
    { phrase(blocks(Item), ItemLines) },
    list_block(Kind, Items).
list_block(_, []) -->
    [].

list_one_item(Kind, [C0|Rest]) -->
    [L0], { list_marker(L0, Kind, Width, C0) }, !,
    item_continuation(Width, Kind, Rest).

item_continuation(Width, Kind, Rest) -->
    peek_rest(Remaining),
    { item_take(Remaining, Width, Kind, Rest, N) },
    consume_n(N).

item_take([], _, _, [], 0) :- !.
item_take([L|Ls], Width, Kind, Contents, N) :-
    ( is_blank(L) ->
        item_take(Ls, Width, Kind, Rest, N1),
        Contents = [""|Rest], N is N1 + 1
    ; indent_at_least(L, Width, Ded) ->
        item_take(Ls, Width, Kind, Rest, N1),
        Contents = [Ded|Rest], N is N1 + 1
    ; list_marker(L, Kind, _, _) ->
        Contents = [], N = 0
    ;   Contents = [], N = 0
    ).

% -- paragraph --------------------------------------------------------------

para_lines([L|Ls]) -->
    [L], { \+ is_blank(L) }, !, para_lines_rest(Ls).
para_lines([]) --> [].

para_lines_rest([L|Ls]) -->
    peek_rest([L|_]),
    { \+ is_blank(L), \+ starts_new_block(L) }, !,
    [_], para_lines_rest(Ls).
para_lines_rest([]) -->
    [].

starts_new_block(L) :- atx_heading(L, _, _), !.
starts_new_block(L) :- is_hr(L), !.
starts_new_block(L) :- fence_marker(L, _), !.
starts_new_block(L) :- quote_line(L, _), !.
starts_new_block(L) :- list_marker(L, _, _, _), !.

% ---------------------------------------------------------------------
% Line classifiers (plain Prolog + small DCGs over a single line's codes)
% ---------------------------------------------------------------------

is_blank(Line) :-
    split_string(Line, "", " \t", [""]).

strip_upto3_leading_spaces(L0, L) :- strip_leading_spaces(L0, 0, L).
strip_leading_spaces(L0, N, L) :-
    N < 3, string_concat(" ", Rest, L0), !,
    N1 is N + 1, strip_leading_spaces(Rest, N1, L).
strip_leading_spaces(L, _, L).

% -- ATX headings ---------------------------------------------------------

atx_heading(Line, Level, Text) :-
    strip_upto3_leading_spaces(Line, L1),
    string_codes(L1, Codes),
    phrase(atx_heading_dcg(Level, TextCodes), Codes),
    string_codes(Text0, TextCodes),
    normalize_space(string(Text), Text0).

atx_heading_dcg(Level, TextCodes) -->
    hashes(Level), { Level >= 1, Level =< 6 },
    ( eos -> { TextCodes = [] }
    ; " ", remainder(TextCodes0), { strip_trailing_hashes(TextCodes0, TextCodes) }
    ).

hashes(N) --> "#", !, hashes(N1), { N is N1 + 1 }.
hashes(0) --> [].

strip_trailing_hashes(Codes, StrippedStr) :-
    string_codes(S, Codes),
    normalize_space(string(S1), S),
    string_chars(S1, Chars),
    reverse(Chars, RevChars),
    drop_leading(RevChars, "#", RevChars1),
    reverse(RevChars1, Chars1),
    string_chars(S2, Chars1),
    normalize_space(string(StrippedStr), S2).

drop_leading([C|Cs], SetStr, Out) :-
    string_chars(SetStr, SetChars), memberchk(C, SetChars), !,
    drop_leading(Cs, SetStr, Out).
drop_leading(Cs, _, Cs).

% -- thematic break (hr) ---------------------------------------------------

is_hr(Line) :-
    string_codes(Line, Codes),
    ( phrase(hr_dcg(0'-), Codes)
    ; phrase(hr_dcg(0'*), Codes)
    ; phrase(hr_dcg(0'_), Codes)
    ), !.

hr_dcg(C) --> blanks, hr_run(C, N), blanks, eos, { N >= 3 }.

hr_run(C, N) --> [C], !, blanks, hr_run(C, N1), { N is N1 + 1 }.
hr_run(_, 0) --> [].

% -- fenced code marker -----------------------------------------------------

fence_marker(Line, Lang) :-
    strip_upto3_leading_spaces(Line, L1),
    ( sub_string(L1, 0, 3, After, "```") ; sub_string(L1, 0, 3, After, "~~~") ),
    !,
    sub_string(L1, 3, After, 0, Info),
    normalize_space(string(Info1), Info),
    ( Info1 == "" -> Lang = none ; first_word(Info1, Lang) ).

first_word(S, W) :-
    split_string(S, " \t", "", [W|_]).

% -- blockquote marker -------------------------------------------------------

quote_line(Line, Content) :-
    strip_upto3_leading_spaces(Line, L1),
    string_concat(">", Rest0, L1), !,
    ( string_concat(" ", Rest, Rest0) -> Content = Rest ; Content = Rest0 ).

% -- list markers -------------------------------------------------------------

list_marker(Line, Kind, Width, Content) :-
    string_codes(Line, Codes),
    ( phrase(list_marker_dcg(unordered, Width, ContentCodes), Codes) -> Kind = unordered
    ; phrase(list_marker_dcg(ordered, Width, ContentCodes), Codes) -> Kind = ordered
    ),
    string_codes(Content, ContentCodes).

list_marker_dcg(unordered, Width, ContentCodes) -->
    leading_spaces(LS), { LS =< 3 },
    ( "-" ; "+" ; "*" ),
    ( eos -> { W2 = 0, ContentCodes = [] }
    ; " ", remainder(ContentCodes), { W2 = 1 }
    ),
    { Width is LS + 1 + W2 }.

list_marker_dcg(ordered, Width, ContentCodes) -->
    leading_spaces(LS), { LS =< 3 },
    digits(DigitsCodes), { DigitsCodes \= [] },
    ( "." ; ")" ),
    ( eos -> { W2 = 0, ContentCodes = [] }
    ; " ", remainder(ContentCodes), { W2 = 1 }
    ),
    { length(DigitsCodes, DL), Width is LS + DL + 1 + W2 }.

leading_spaces(N) --> " ", !, leading_spaces(N1), { N is N1 + 1 }.
leading_spaces(0) --> [].

% -- indentation dedent helper ------------------------------------------------

indent_at_least(Line, Width, Dedented) :-
    Width > 0,
    string_length(Line, Len),
    Len >= Width,
    sub_string(Line, 0, Width, _, Prefix),
    split_string(Prefix, "", " ", [""]),
    sub_string(Line, Width, _, 0, Dedented).

trim_trailing_blank_lines(Lines0, Lines) :-
    reverse(Lines0, R0),
    drop_while_blank(R0, R1),
    reverse(R1, Lines).

drop_while_blank([L|T], R) :- is_blank(L), !, drop_while_blank(T, R).
drop_while_blank(L, L).

join_with_nl([], "") :- !.
join_with_nl([L], L) :- !.
join_with_nl([L|Ls], Text) :-
    join_with_nl(Ls, Rest),
    string_concat(L, "\n", T0),
    string_concat(T0, Rest, Text).

% ---------------------------------------------------------------------
% Joining physical lines of a paragraph/heading into one logical text,
% turning trailing "  " or "\" at a line end into a hard-break marker.
% ---------------------------------------------------------------------

hard_break_sentinel(S) :- string_codes(S, [1]).

join_lines_for_inline([], "") :- !.
join_lines_for_inline([L], Stripped) :-
    !,
    ( string_concat(Prefix, "\\", L) -> Stripped = Prefix
    ; rtrim_spaces(L, Stripped)
    ).
join_lines_for_inline([L1, L2|Rest], Text) :-
    line_break_kind(L1, Kind, L1Stripped),
    join_lines_for_inline([L2|Rest], RestText),
    ( Kind = hard -> hard_break_sentinel(Sep) ; Sep = " " ),
    string_concat(L1Stripped, Sep, T0),
    string_concat(T0, RestText, Text).

line_break_kind(L, hard, Stripped) :-
    string_concat(Prefix, "\\", L), !, Stripped = Prefix.
line_break_kind(L, hard, Stripped) :-
    trailing_space_count(L, Cnt), Cnt >= 2, !,
    string_length(L, Len), Keep is Len - Cnt,
    sub_string(L, 0, Keep, _, Stripped).
line_break_kind(L, soft, Stripped) :-
    rtrim_spaces(L, Stripped).

trailing_space_count(L, N) :-
    string_chars(L, Cs), reverse(Cs, R), count_leading_spaces(R, N).
count_leading_spaces([' '|T], N) :- !, count_leading_spaces(T, N1), N is N1 + 1.
count_leading_spaces(_, 0).

rtrim_spaces(L, Trimmed) :- split_string(L, "", " ", [Trimmed]).

% ---------------------------------------------------------------------
% Inline grammar
% ---------------------------------------------------------------------

%!  parse_inline(+Text:string, -Spans:list) is det.

parse_inline(Text, Spans) :-
    string_codes(Text, Codes),
    phrase(inline_spans(Raw), Codes),
    merge_text_spans(Raw, Spans).

inline_spans([]) --> eos, !.
inline_spans([Span|Spans]) --> inline_span(Span), !, inline_spans(Spans).

inline_span(linebreak) -->
    [1], !.
inline_span(text(S)) -->
    "\\", [C], { escapable_char(C), string_codes(S, [C]) }, !.
inline_span(strong(Spans)) -->
    "**", string_without("*", Codes), "**",
    { string_codes(S, Codes), parse_inline(S, Spans) }.
inline_span(strong(Spans)) -->
    "__", string_without("_", Codes), "__",
    { string_codes(S, Codes), parse_inline(S, Spans) }.
inline_span(emph(Spans)) -->
    "*", string_without("*", Codes), "*",
    { string_codes(S, Codes), parse_inline(S, Spans) }.
inline_span(emph(Spans)) -->
    "_", string_without("_", Codes), "_",
    { string_codes(S, Codes), parse_inline(S, Spans) }.
inline_span(code(Str)) -->
    "`", string_without("`", Codes), "`",
    { string_codes(Str, Codes) }.
inline_span(image(Alt, Url)) -->
    "![", string_without("]", AltCodes), "]", "(", string_without(")", UrlCodes), ")",
    { string_codes(Alt, AltCodes), string_codes(Url, UrlCodes) }.
inline_span(link(Spans, Url)) -->
    "[", string_without("]", TextCodes), "]", "(", string_without(")", UrlCodes), ")",
    { string_codes(TStr, TextCodes), parse_inline(TStr, Spans), string_codes(Url, UrlCodes) }.
inline_span(text(S)) -->
    [C], { string_codes(S, [C]) }.

escapable_char(C) :- \+ code_type(C, alnum).

merge_text_spans([], []).
merge_text_spans([text(A), text(B)|Rest], Merged) :-
    !, string_concat(A, B, AB), merge_text_spans([text(AB)|Rest], Merged).
merge_text_spans([X|Rest], [X|Merged]) :-
    merge_text_spans(Rest, Merged).
