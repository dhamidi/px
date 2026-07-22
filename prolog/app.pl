:- module(app,
          [ listen/2,      % +Port, +Options
            dispatch/2     % +Request, +ResponseStream
          ]).

:- use_module(library(uri)).
:- use_module(worker).
:- use_module(http_stream).
:- use_module(router).
:- use_module(middleware).
:- use_module(response).

/** <module> Framework entrypoint tying worker.pl/http_stream.pl
    (transport, adr/0005-0008) together with router.pl (adr/0009),
    middleware.pl (adr/0010) and response.pl.

## Handler calling convention

Every route handler registered via router:add_route/4 is called, per
request, as:

    call(Handler, Request, ResponseStream, PathParams, QueryParams)

  - Request      - the request dict from http_stream.pl:
                    _{method, url, headers, body}, unmodified.
  - ResponseStream - the real output IOSTREAM from http_stream.pl. The
                    handler MUST write a complete response (status
                    line, headers, blank line, body) to it before
                    returning -- see response.pl for helpers. Nothing
                    else writes a response on the handler's behalf.
  - PathParams   - list of Name=Value pairs extracted from the URL
                    path by router:match_route/4 (Name an atom, Value
                    an atom), e.g. [id='1'] for a route registered as
                    "/adr/:id" matched against "/adr/1".
  - QueryParams  - list of Name=Value pairs (both strings) from the
                    request's query string, via library(uri)'s
                    uri_query_components/2, e.g. [] for a URL with no
                    "?...", or [foo=bar] for "?foo=bar".

This four-argument shape -- always in this order, always all four
arguments present even when empty -- is the one the parallel
markdown-rendering demo app is written against; keep it stable.
*/

%!  listen(+Port, +Options) is det.
%
%   Starts the app. Options currently supports:
%
%     - workers(N) -- number of worker threads/loops/engines to start
%       (adr/0005), each independently bound to Port via SO_REUSEPORT.
%       Default 1 -- see adr/0005/0006 for why one worker is the right
%       default (a single event loop, not blocked, is enough unless a
%       handler genuinely blocks; running more workers is the
%       mitigation for that, not the default posture).
%
%   Never returns (start_workers/3 starts detached background threads;
%   callers that need to block the calling thread afterwards, e.g. a
%   :- initialization(main, main) script, should do so themselves --
%   see test/milestone7_framework.pl).
listen(Port, Options) :-
    ( option_workers(Options, N) -> true ; N = 1 ),
    worker:start_workers(Port, N, http_stream:handle_connection(app:dispatch)).

option_workers(Options, N) :-
    memberchk(workers(N), Options).

%!  dispatch(+Request, +ResponseStream) is det.
%
%   The RequestGoal called by http_stream.pl once a complete request
%   has been parsed. Runs the global middleware chain first
%   (middleware:run_middleware_chain/3); if that chain handles the
%   request or errors out, dispatch/2 stops there -- it does not also
%   run the router. Otherwise splits Request.url into a path and query
%   params (library(uri)), downcases Request.method to match route
%   registration convention (routes are registered with lowercase
%   Method atoms, e.g. get/post), and tries router:match_route/4.
%
%   On a match, calls the Handler per the four-argument convention
%   documented in the module comment above. On no match, writes a 404
%   via response:reply_not_found/1.
%
%   The whole thing is wrapped in catch/3: a handler exception (or any
%   other error during dispatch) becomes a real HTTP 500 response
%   instead of propagating up into http_stream.pl's
%   on_message_complete/4, where an uncaught exception would otherwise
%   be reported to stderr as a callback exception and leave the
%   connection without a real response.
%
%   ResponseStream is opened SIO_FBUF (fully buffered -- see
%   c/http_stream_swi.c) so bytes a handler/response.pl helper writes
%   do not actually reach the socket until the stream is flushed.
%   http_stream.pl does not flush or close ResponseStream itself after
%   RequestGoal returns (closing the Stream is distinct from, and does
%   not trigger, the uv_close/2 it does on the raw connection -- see
%   uv_response_stream/2's doc comment), so dispatch/2 does that here,
%   in a setup_call_cleanup/3 cleanup goal, guaranteeing every request
%   ends with its buffered response actually written to the wire
%   exactly once, whether dispatch_guarded/2 succeeds, fails, or
%   throws.
dispatch(Request, ResponseStream) :-
    setup_call_cleanup(
        true,
        catch(dispatch_guarded(Request, ResponseStream), Error,
              handle_dispatch_error(Error, ResponseStream)),
        catch(close(ResponseStream), _, true)).

dispatch_guarded(Request, ResponseStream) :-
    middleware:run_middleware_chain(Request, ResponseStream, MwOutcome),
    handle_middleware_outcome(MwOutcome, Request, ResponseStream).

handle_middleware_outcome(handled, _Request, _ResponseStream) :- !.
handle_middleware_outcome(error(Ball), _Request, _ResponseStream) :-
    !,
    throw(Ball).
handle_middleware_outcome(continue, Request, ResponseStream) :-
    !,
    route_request(Request, ResponseStream).
handle_middleware_outcome(Other, _Request, _ResponseStream) :-
    throw(error(unexpected_middleware_outcome(Other), _)).

route_request(Request, ResponseStream) :-
    split_url(Request.url, Path, QueryParams),
    downcase_atom(Request.method, Method),
    ( router:match_route(Method, Path, Handler, PathParams)
    -> call(Handler, Request, ResponseStream, PathParams, QueryParams)
    ;  response:reply_not_found(ResponseStream)
    ).

%!  split_url(+Url, -Path, -QueryParams) is det.
%
%   Splits a raw request-target such as "/adr/1?foo=bar" into
%   Path = "/adr/1" and QueryParams = [foo=bar], via library(uri)'s
%   uri_components/5 (path/query split) and uri_query_components/2
%   (query string decoding).
split_url(Url, Path, QueryParams) :-
    uri_components(Url, uri_components(_Scheme, _Auth, Path, Search, _Frag)),
    ( nonvar(Search)
    -> uri_query_components(Search, QueryParams)
    ;  QueryParams = []
    ).

handle_dispatch_error(Error, ResponseStream) :-
    message_to_string(Error, Message),
    format(user_error, "app:dispatch/2: handler error: ~w~n", [Message]),
    catch(response:reply_error(ResponseStream, 500, Message), _, true).
