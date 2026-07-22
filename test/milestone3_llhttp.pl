/* Milestone 3 (adr/0002, adr/0003, adr/0007, adr/0008): proves the llhttp
   1:1 FFI end to end -- a parser blob is created, callbacks are wired to
   plain Prolog predicates, and a hand-written HTTP/1.1 GET request is fed
   in as three separate chunks whose split points deliberately land mid
   header-name and mid-body. If llhttp_execute/3 is genuinely incremental
   (adr/0007), the header-field and body callbacks must fire more than
   once for the values that straddle a chunk boundary, and the bytes
   delivered across those calls must reassemble exactly, byte for byte,
   into the original values. That is what this test checks, not just
   that callbacks fire at all. */

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../prolog/uv_dispatch'], Dispatch),
   atomic_list_concat([Dir, '/../prolog/llhttp_swi'], Lib),
   use_module(Dispatch),
   use_module(Lib).

:- dynamic(seen/1).

on_url(Data) :-
    format("[cb] on_url:            ~q~n", [Data]),
    assertz(seen(url(Data))).

on_header_field(Data) :-
    format("[cb] on_header_field:   ~q~n", [Data]),
    assertz(seen(header_field(Data))).

on_header_value(Data) :-
    format("[cb] on_header_value:   ~q~n", [Data]),
    assertz(seen(header_value(Data))).

on_headers_complete :-
    format("[cb] on_headers_complete~n"),
    assertz(seen(headers_complete)).

on_body(Data) :-
    format("[cb] on_body:           ~q~n", [Data]),
    assertz(seen(body(Data))).

on_message_complete :-
    format("[cb] on_message_complete~n"),
    assertz(seen(message_complete)).

%!  concat_tagged(+Tag, -Concated) is det.
%
%   Concatenate, in call order, the data of every seen(Tag(Data)) fact.
%   Used to check that bytes delivered across several callback firings
%   (because a chunk boundary landed inside a token) reassemble to
%   exactly the right value -- the actual proof of incremental parsing,
%   not just that *a* callback fired.
concat_tagged(Tag, Concated) :-
    findall(D, ( T =.. [Tag, D], seen(T) ), Ds),
    atomic_list_concat(Ds, Concated).

count_tagged(Tag, N) :-
    findall(x, seen(Tag), L),
    length(L, N).

run_execute(Parser, Label, Chunk) :-
    string_length(Chunk, Len),
    format("~n=== ~w (~w bytes) ===~n~q~n", [Label, Len, Chunk]),
    llhttp_execute(Parser, Chunk, Result),
    format("llhttp_execute result: ~w~n", [Result]),
    ( Result == ok
    -> true
    ;  throw(error(unexpected_llhttp_result(Label, Result), _))
    ).

main :-
    llhttp_parser_new(Parser),

    % Registering closures module-qualified (user:...) is required -- see
    % llhttp_swi.pl's module doc: uv_invoke/2 strip_module/3's the
    % closure at call time, so an unqualified atom would resolve in
    % whatever module happens to be current when llhttp_execute/3 fires
    % it, not necessarily this one.
    llhttp_on_url(Parser, user:on_url),
    llhttp_on_header_field(Parser, user:on_header_field),
    llhttp_on_header_value(Parser, user:on_header_value),
    llhttp_on_headers_complete(Parser, user:on_headers_complete),
    llhttp_on_body(Parser, user:on_body),
    llhttp_on_message_complete(Parser, user:on_message_complete),

    % Three hand-written chunks of one HTTP/1.1 GET request. Concatenated
    % together they are exactly:
    %
    %   GET /foo/bar?x=1 HTTP/1.1\r\n
    %   Host: example.com\r\n
    %   X-Test: hello\r\n
    %   Content-Length: 11\r\n
    %   \r\n
    %   hello world
    %
    % Chunk 1 ends mid header-name ("X-Te"|"st"), chunk 2 ends mid body
    % ("hello"|" world") -- both split points chosen so a single logical
    % value is only reassembled correctly if llhttp_execute/3 really is
    % incremental across separate calls, per adr/0007.
    Chunk1 = "GET /foo/bar?x=1 HTTP/1.1\r\nHost: example.com\r\nX-Te",
    Chunk2 = "st: hello\r\nContent-Length: 11\r\n\r\nhello",
    Chunk3 = " world",

    run_execute(Parser, "chunk 1 (mid header-name split)", Chunk1),
    run_execute(Parser, "chunk 2 (headers complete, body starts, mid-body split)", Chunk2),
    run_execute(Parser, "chunk 3 (rest of body)", Chunk3),

    llhttp_method_name(Parser, Method),
    format("~nparsed method: ~w~n", [Method]),

    format("~n--- assertions ---~n"),

    concat_tagged(url, Url),
    format("reassembled url:          ~q~n", [Url]),
    assertion(Url == '/foo/bar?x=1'),

    concat_tagged(header_field, Fields),
    format("reassembled header names: ~q~n", [Fields]),
    assertion(Fields == 'HostX-TestContent-Length'),

    concat_tagged(header_value, Values),
    format("reassembled header vals:  ~q~n", [Values]),
    assertion(Values == 'example.comhello11'),

    concat_tagged(body, Body),
    format("reassembled body:         ~q~n", [Body]),
    assertion(Body == 'hello world'),

    count_tagged(headers_complete, HCCount),
    assertion(HCCount == 1),

    count_tagged(message_complete, MCCount),
    assertion(MCCount == 1),

    assertion(Method == 'GET'),

    % The whole point of the split: prove more than one callback firing
    % actually happened for the tokens that straddled a chunk boundary.
    findall(D, seen(header_field(D)), FieldPieces),
    length(FieldPieces, NFieldPieces),
    format("header_field fired ~w times (expect > 3: proves the split mid ~q produced two separate firings for that field)~n",
           [NFieldPieces, 'X-Test']),
    assertion(NFieldPieces > 3),

    findall(D, seen(body(D)), BodyPieces),
    length(BodyPieces, NBodyPieces),
    format("on_body fired ~w times (expect >= 2: proves the mid-body split produced separate firings instead of one buffered call)~n",
           [NBodyPieces]),
    assertion(NBodyPieces >= 2),

    format("~nSMOKE TEST PASSED~n").

:- initialization(main, main).
