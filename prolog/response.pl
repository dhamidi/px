:- module(response,
          [ reply_status/3,        % +Stream, +Code, +Reason
            reply_header/3,        % +Stream, +Name, +Value
            reply_body/3,          % +Stream, +ContentType, +Body
            reply_html/3,          % +Stream, +Code, +HtmlString
            reply_not_found/1,     % +Stream
            reply_error/3          % +Stream, +Code, +Message
          ]).

/** <module> Small ergonomic helpers over the raw response IOSTREAM.

ResponseStream (see http_stream.pl / adr/0007) is a genuine SWI-Prolog
output stream that writes straight through to the socket -- these
predicates are convenience wrappers around format/write on that stream,
not a hidden abstraction layer. Callers can always drop down to
format(Stream, ...) directly; nothing here stops that.

Every response written through this module is Connection: close, since
http_stream.pl closes the connection right after RequestGoal returns
(no keep-alive in this version -- see http_stream.pl's header comment).
*/

%!  reply_status(+Stream, +Code, +Reason) is det.
%
%   Writes the HTTP/1.1 status line, e.g.
%   reply_status(Stream, 200, "OK") writes "HTTP/1.1 200 OK\r\n".
reply_status(Stream, Code, Reason) :-
    format(Stream, "HTTP/1.1 ~w ~w\r\n", [Code, Reason]).

%!  reply_header(+Stream, +Name, +Value) is det.
%
%   Writes one header line.
reply_header(Stream, Name, Value) :-
    format(Stream, "~w: ~w\r\n", [Name, Value]).

%!  reply_body(+Stream, +ContentType, +Body) is det.
%
%   Convenience for the common case: writes Content-Type,
%   Content-Length (computed from Body, a string) and a
%   Connection: close header, then the blank line, then Body.
%   Assumes reply_status/3 was already called.
%
%   Content-Length MUST be a byte count, not a character count --
%   Stream is UTF-8 (see c/http_stream_swi.c), so any multi-byte
%   character (anything outside ASCII) makes string_length/2 (which
%   counts characters) undercount the real length. A client that
%   trusts Content-Length then stops reading before the true end of
%   the body, silently truncating it -- this was hit for real serving
%   a page whose title contained a literal em dash.
reply_body(Stream, ContentType, Body) :-
    utf8_byte_length(Body, Len),
    reply_header(Stream, 'Content-Type', ContentType),
    reply_header(Stream, 'Content-Length', Len),
    reply_header(Stream, 'Connection', close),
    format(Stream, "\r\n", []),
    write(Stream, Body).

%!  utf8_byte_length(+Text, -Bytes) is det.
%
%   Number of bytes Text encodes to as UTF-8, not its character count.
utf8_byte_length(Text, Bytes) :-
    string_codes(Text, Codes),
    foldl(add_utf8_width_, Codes, 0, Bytes).

add_utf8_width_(Code, Acc0, Acc) :-
    ( Code =< 0x7F   -> W = 1
    ; Code =< 0x7FF  -> W = 2
    ; Code =< 0xFFFF -> W = 3
    ; W = 4
    ),
    Acc is Acc0 + W.

%!  reply_html(+Stream, +Code, +HtmlString) is det.
%
%   Convenience combining a status line (Code, or 200 if Code is left
%   as the atom `200`/unbound-by-caller-default -- callers pass the
%   code explicitly) with Content-Type: text/html; charset=utf-8 and
%   the given HtmlString as body. This is what the markdown-rendering
%   demo app mostly uses, per the milestone 7 spec.
reply_html(Stream, Code, HtmlString) :-
    reply_status(Stream, Code, "OK"),
    reply_body(Stream, "text/html; charset=utf-8", HtmlString).

%!  reply_not_found(+Stream) is det.
%
%   A basic 404 response.
reply_not_found(Stream) :-
    reply_status(Stream, 404, "Not Found"),
    reply_body(Stream, "text/plain; charset=utf-8", "404 Not Found").

%!  reply_error(+Stream, +Code, +Message) is det.
%
%   A basic error response (e.g. used by app:dispatch/2 to turn a
%   caught handler exception into a real HTTP 500 instead of a
%   silently-dropped connection).
reply_error(Stream, Code, Message) :-
    format(string(Reason), "~w", [Message]),
    reply_status(Stream, Code, "Internal Server Error"),
    reply_body(Stream, "text/plain; charset=utf-8", Reason).
