/* Milestone 7: the "express-like" framework layer (router.pl per
   adr/0009, middleware.pl per adr/0010, response.pl, app.pl) wired up
   end to end over a real HTTP round trip -- same transport stack
   milestone6 proved (worker.pl/http_stream.pl), but now dispatch goes
   through app:dispatch/2 -> middleware:run_middleware_chain/3 ->
   router:match_route/4 instead of a single hand-written handler.

   Registers:
     - a static route:        GET /hello
     - a :param route:        GET /adr/:id
     - a deliberately-broken route: GET /boom (always throws)
     - one global middleware: a request logger that always continues

   test/milestone7_run.sh drives this over curl and checks:
     (a) the static route responds correctly
     (b) the :param route responds correctly with the right param value
     (c) an unmatched route gets a real 404
     (d) the /boom route's exception becomes a real 500, not a dropped
         connection
*/

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../prolog/app'], AppLib),
   atomic_list_concat([Dir, '/../prolog/router'], RouterLib),
   atomic_list_concat([Dir, '/../prolog/middleware'], MiddlewareLib),
   atomic_list_concat([Dir, '/../prolog/response'], ResponseLib),
   use_module(AppLib),
   use_module(RouterLib),
   use_module(MiddlewareLib),
   use_module(ResponseLib).

%   Route handlers. Signature per app.pl's documented convention:
%   Handler(Request, ResponseStream, PathParams, QueryParams).

hello_handler(_Request, Stream, _PathParams, QueryParams) :-
    ( memberchk(name=Name, QueryParams) -> true ; Name = "World" ),
    format(string(Body), "Hello, ~w!\n", [Name]),
    response:reply_status(Stream, 200, "OK"),
    response:reply_body(Stream, "text/plain; charset=utf-8", Body).

adr_handler(_Request, Stream, PathParams, _QueryParams) :-
    ( memberchk(id=Id, PathParams) -> true ; Id = missing ),
    format(string(Body), "adr id = ~w\n", [Id]),
    response:reply_status(Stream, 200, "OK"),
    response:reply_body(Stream, "text/plain; charset=utf-8", Body).

boom_handler(_Request, _Stream, _PathParams, _QueryParams) :-
    throw(error(deliberate_boom, context(boom_handler/4, "this route always throws, on purpose"))).

%   Trivial request-logging middleware. Always continues -- proves
%   middleware runs (see stderr output) without affecting routing.
logger_middleware(Request, _ResponseStream, continue) :-
    format(user_error, "[mw] ~w ~w~n", [Request.method, Request.url]).

:- initialization(main, main).

main :-
    current_prolog_flag(argv, [PortAtom]),
    !,
    atom_number(PortAtom, Port),
    run(Port).
main :-
    run(7007).

run(Port) :-
    router:add_route(hello, get, "/hello", user:hello_handler),
    router:add_route(adr_show, get, "/adr/:id", user:adr_handler),
    router:add_route(boom, get, "/boom", user:boom_handler),
    middleware:use_middleware(user:logger_middleware),
    format(user_error, "milestone7: listening on port ~w~n", [Port]),
    app:listen(Port, [workers(1)]),
    thread_get_message(_).
