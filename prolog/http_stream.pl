:- module(http_stream,
          [ handle_connection/4,        % :RequestGoal, +WorkerId, +Loop, +Client
            ignore_write_result/1,
            ignore_close_result/0
          ]).

/** <module> Bridge from a raw accepted connection to a request/response
    pair the framework layer (router.pl, app.pl) can work with.
    See adr/0007.

Wires an llhttp parser to a connection's reads. As header/body events
arrive -- possibly split across several C callback firings per field,
per adr/0007's proof in test/milestone3_llhttp.pl -- they're
accumulated into a small per-connection state box. Once
on_message_complete fires, a request dict is built and RequestGoal is
called as call(RequestGoal, Request, ResponseStream), where
ResponseStream is a genuine output IOSTREAM (c/http_stream_swi.c)
writing straight to the connection -- not a buffer built up first and
handed over in one shot.

The accumulator uses nb_setval/nb_getval keyed by the connection's own
printed representation (unique per handle, since c/uv_swi.c's blob
`write` callback prints the underlying pointer) rather than a proper
immutable Prolog data structure threaded through the calls, because the
data arrives via C callbacks over time, not as one DCG parse. This is a
deliberate, scoped use of a mutable global, not a general framework
pattern -- see adr/0007 for why the *streaming* parts of this module
avoid buffering, and note this accumulator is explicitly not that: it
exists because header/body sizes here are small and bounded (page
requests, not uploads), not because buffering the whole message is
the design's default.
*/

:- use_module(uv_swi).
:- use_module(llhttp_swi).
:- use_module(http_stream_swi).
:- use_module(uv_dispatch).

ignore_write_result(_).
ignore_close_result.

%!  handle_connection(:RequestGoal, +WorkerId, +Loop, +Client) is det.
%
%   Registered as the ConnectionGoal passed to worker:start_workers/3,
%   with RequestGoal pre-bound, e.g.
%   start_workers(Port, N, http_stream:handle_connection(my_app:route)) --
%   worker.pl's on_connection/5 then appends (WorkerId, Loop, Client).
handle_connection(RequestGoal, _WorkerId, _Loop, Client) :-
    llhttp_parser_new(Parser),
    conn_key(Client, Key),
    nb_setval(Key, acc("", [], "", "", field, "")),
    llhttp_on_url(Parser, http_stream:on_url(Key)),
    llhttp_on_header_field(Parser, http_stream:on_header_field(Key)),
    llhttp_on_header_value(Parser, http_stream:on_header_value(Key)),
    llhttp_on_headers_complete(Parser, http_stream:on_headers_complete(Key)),
    llhttp_on_body(Parser, http_stream:on_body(Key)),
    llhttp_on_message_complete(Parser,
        http_stream:on_message_complete(Key, Parser, Client, RequestGoal)),
    uv_read_start(Client, http_stream:on_read(Key, Parser)).

conn_key(Client, Key) :-
    format(atom(Key), 'http_stream_conn_~p', [Client]).

on_read(_Key, _Parser, _Client, end_of_file) :- !.
on_read(_Key, Parser, Client, Data) :-
    llhttp_execute(Parser, Data, Result),
    ( Result == ok
    -> true
    ;  format(user_error,
              "http_stream: parse error ~w on connection ~p, closing~n",
              [Result, Client]),
       uv_close(Client, http_stream:ignore_close_result)
    ).

on_url(Key, Chunk) :-
    nb_getval(Key, acc(Url, Headers, F, V, Phase, Body)),
    string_concat(Url, Chunk, Url1),
    nb_setval(Key, acc(Url1, Headers, F, V, Phase, Body)).

on_header_field(Key, Chunk) :-
    nb_getval(Key, acc(Url, Headers, F, V, Phase, Body)),
    ( Phase == value
    -> Headers1 = [F-V|Headers], F1 = Chunk
    ;  Headers1 = Headers, string_concat(F, Chunk, F1)
    ),
    nb_setval(Key, acc(Url, Headers1, F1, "", field, Body)).

on_header_value(Key, Chunk) :-
    nb_getval(Key, acc(Url, Headers, F, V, _Phase, Body)),
    string_concat(V, Chunk, V1),
    nb_setval(Key, acc(Url, Headers, F, V1, value, Body)).

on_headers_complete(Key) :-
    nb_getval(Key, acc(Url, Headers, F, V, Phase, Body)),
    ( Phase == value, F \== ""
    -> Headers1 = [F-V|Headers]
    ;  Headers1 = Headers
    ),
    nb_setval(Key, acc(Url, Headers1, "", "", field, Body)).

on_body(Key, Chunk) :-
    nb_getval(Key, acc(Url, Headers, F, V, Phase, Body)),
    string_concat(Body, Chunk, Body1),
    nb_setval(Key, acc(Url, Headers, F, V, Phase, Body1)).

% No keep-alive in this version: one request per connection, closed
% right after the response is written. A future iteration could inspect
% the request's Connection header and reuse the parser/connection
% instead -- tracked as a known limitation, not attempted here.
on_message_complete(Key, Parser, Client, RequestGoal) :-
    nb_getval(Key, acc(Url, HeadersRev, _F, _V, _Phase, Body)),
    nb_delete(Key),
    reverse(HeadersRev, Headers),
    llhttp_method_name(Parser, Method),
    Request = _{method: Method, url: Url, headers: Headers, body: Body},
    uv_response_stream(Client, ResponseStream),
    call(RequestGoal, Request, ResponseStream),
    uv_close(Client, http_stream:ignore_close_result).
