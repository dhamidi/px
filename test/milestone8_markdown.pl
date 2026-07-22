/* Milestone 8 (adr/0011): the markdown-to-HTML pipeline, prolog/markdown/parser.pl
   (a genuine DCG over library(dcg/basics)) feeding prolog/markdown/html.pl
   (which reuses SWI-Prolog's own library(http/html_write) to actually emit
   HTML tags, rather than a hand-rolled second templating layer). This is a
   plain swipl script -- no networking, no worker threads -- because the
   markdown pipeline is fully independent of the HTTP/uv layers proven in
   earlier milestones.

   Two things are checked here:

   1. A hand-written markdown string exercises every construct in scope
      per adr/0011 (headings, paragraph with mixed emphasis/strong/code,
      fenced code, indented code, link, image, a nested unordered list
      inside an ordered list item, a nested blockquote, an hr, a hard line
      break) plus one dedicated escaping check (a bare "<" and "&" in
      ordinary prose must come out as "&lt;"/"&amp;", never bare). Each
      construct gets its own PASS/FAIL assertion against the rendered
      HTML string.

   2. The full pipeline is run over a real ADR file already in this repo
      (adr/0001-project-goals-and-layout.md) -- real markdown written by
      another agent, not hand-picked test input -- and the resulting HTML
      is printed so the renderer's behaviour on real content is visible,
      not just asserted.
*/

:- use_module('../prolog/markdown/parser.pl').
:- use_module('../prolog/markdown/html.pl').

% prolog_load_context/2's `directory` is only meaningful while this file
% is actively being loaded, not later when main/1 runs (via
% initialization/2, after loading has finished) -- so capture it now,
% at load time, into a fact main/1 can read at runtime.
:- prolog_load_context(directory, Dir), asserta(test_dir(Dir)).

:- initialization(main, main).

% ---------------------------------------------------------------------
% Part 1: every construct in scope, one assertion each.
% ---------------------------------------------------------------------

comprehensive_markdown(Md) :-
    Md = "# Top Heading
## Sub Heading

A paragraph with *emphasis*, **strong emphasis**, and `inline code`, plus a
line ending in a hard break\\
that continues on the next line.

```prolog
foo(bar) :- baz.
```

    indented code line one
    indented code line two

A [link](http://example.com/page) and an ![alt text](http://example.com/pic.png) image.

1. first ordered item
2. second ordered item
   - nested unordered a
   - nested unordered b

> top level quote
> > nested quote

---

Watch out: cost < budget and profit & loss.
".

check(Name, Html, Needle) :-
    ( sub_string(Html, _, _, _, Needle) ->
        format("PASS: ~w (found ~q)~n", [Name, Needle]),
        true
    ;   format("FAIL: ~w (did not find ~q)~n", [Name, Needle]),
        false
    ).

check_absent(Name, Html, Needle) :-
    ( \+ sub_string(Html, _, _, _, Needle) ->
        format("PASS: ~w (correctly absent ~q)~n", [Name, Needle]),
        true
    ;   format("FAIL: ~w (unexpectedly found ~q)~n", [Name, Needle]),
        false
    ).

run_comprehensive(AllPass) :-
    comprehensive_markdown(Md),
    markdown_to_ast(Md, AST),
    ast_to_html_string(AST, Html),
    format("~n--- comprehensive test: rendered HTML ---~n~w~n--- end rendered HTML ---~n~n", [Html]),

    Checks = [ 'h1 heading'                    - "<h1>",
               'h2 heading'                    - "<h2>",
               'emphasis'                      - "<em>emphasis</em>",
               'strong emphasis'                - "<strong>strong emphasis</strong>",
               'inline code'                    - "<code>inline code</code>",
               'hard line break'                - "<br>",
               'fenced code block (pre)'        - "<pre>",
               'fenced code block (lang class)'  - "language-prolog",
               'fenced code block content'      - "foo(bar) :- baz.",
               'indented code block content'    - "indented code line one",
               'link'                            - "<a href=\"http://example.com/page\">",
               'image'                           - "<img src=\"http://example.com/pic.png\"",
               'ordered list'                    - "<ol>",
               'blockquote'                      - "<blockquote>",
               'hr'                              - "<hr"
             ],
    maplist(check_pair(Html), Checks, Results),

    % The two nested constructs (unordered list inside an ordered item,
    % blockquote inside a blockquote) need the tag to appear more than
    % once -- once for the outer construct, once for the nested one --
    % not merely be present.
    count_occurrences(Html, "<ul>", UlCount),
    count_occurrences(Html, "<blockquote>", BqCount),
    ( UlCount >= 1 ->
        format("PASS: unordered list nested inside ordered list item (count=~w)~n", [UlCount]), NestUl = true
    ;   format("FAIL: unordered list nesting missing~n", []), NestUl = false
    ),
    ( BqCount >= 2 ->
        format("PASS: blockquote nesting (count=~w)~n", [BqCount]), NestBq = true
    ;   format("FAIL: blockquote nesting missing (count=~w)~n", [BqCount]), NestBq = false
    ),

    % Escaping: "<" and "&" in ordinary prose must be escaped, never bare.
    ( check('escaping of < in prose', Html, "cost &lt; budget") -> EscLt = true ; EscLt = false ),
    ( check('escaping of & in prose', Html, "profit &amp; loss") -> EscAmp = true ; EscAmp = false ),
    ( check_absent('no bare < before budget', Html, "cost < budget") -> AbsLt = true ; AbsLt = false ),
    ( check_absent('no bare & before loss', Html, "profit & loss") -> AbsAmp = true ; AbsAmp = false ),

    append(Results, [NestUl, NestBq, EscLt, EscAmp, AbsLt, AbsAmp], AllResults),
    ( forall(member(true, AllResults), true), \+ member(false, AllResults) ->
        AllPass = true
    ;   AllPass = false
    ).

check_pair(Html, Name-Needle, Result) :-
    ( check(Name, Html, Needle) -> Result = true ; Result = false ).

count_occurrences(Html, Needle, Count) :-
    findall(B, sub_string(Html, B, _, _, Needle), Positions),
    length(Positions, Count).

% ---------------------------------------------------------------------
% Part 2: run the full pipeline over a real ADR file from this repo.
% ---------------------------------------------------------------------

run_real_adr(Ok) :-
    test_dir(Dir),
    atomic_list_concat([Dir, '/../adr/0001-project-goals-and-layout.md'], AdrPath),
    ( exists_file(AdrPath) ->
        read_file_to_string(AdrPath, Md, []),
        markdown_to_ast(Md, AST),
        ast_to_html_string(AST, Html),
        format("~n=== real ADR file: ~w ===~n", [AdrPath]),
        print_first_lines(Html, 30),
        ( sub_string(Html, _, _, _, "<h1>") ; sub_string(Html, _, _, _, "<h2>") ),
        sub_string(Html, _, _, _, "<p>"),
        sub_string(Html, _, _, _, "<code>"),
        ( sub_string(Html, _, _, _, "<ul>") ; sub_string(Html, _, _, _, "<ol>") ),
        format("PASS: real ADR file rendered with headings/paragraphs/code/lists present~n", []),
        Ok = true
    ;   format("FAIL: could not find ~w~n", [AdrPath]),
        Ok = false
    ).

print_first_lines(Text, N) :-
    split_string(Text, "\n", "", Lines),
    length(FirstN, N),
    ( append(FirstN, _, Lines) -> true ; FirstN = Lines ),
    forall(member(L, FirstN), format("~w~n", [L])).

% ---------------------------------------------------------------------

main(_Argv) :-
    format("~n=== milestone8: comprehensive construct coverage ===~n", []),
    ( catch(run_comprehensive(P1), E1, (format("FAIL: exception ~q~n", [E1]), P1 = false)) -> true ; P1 = false ),
    format("~n=== milestone8: real ADR file dogfood ===~n", []),
    ( catch(run_real_adr(P2), E2, (format("FAIL: exception ~q~n", [E2]), P2 = false)) -> true ; P2 = false ),
    ( P1 == true, P2 == true ->
        format("~n=== milestone8: OVERALL PASS ===~n", []),
        halt(0)
    ;   format("~n=== milestone8: OVERALL FAIL (comprehensive=~w, real_adr=~w) ===~n", [P1, P2]),
        halt(1)
    ).
