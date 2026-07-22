:- module(middleware,
          [ use_middleware/1,          % :Goal
            run_middleware_chain/3,    % +Request, +ResponseStream, -FinalOutcome
            clear_middleware/0
          ]).

/** <module> Middleware as a goal list folded over request/response
    state. See adr/0010.

There is no `next()` continuation parameter. Middleware is a plain
Prolog goal registered via use_middleware/1 and stored, in registration
order, as middleware/1 facts. Each registered Goal is called as

    call(Goal, Request, ResponseStream, Outcome)

Outcome unifies with one of:

  - `continue` -- this middleware declined to handle the request;
    try the next middleware in the chain, or fall through to routing
    if this was the last one.
  - `handled`  -- this middleware fully wrote a response itself (e.g.
    an auth check that short-circuits with a 401). Stop the chain
    here; app:dispatch/2 must NOT also run the router in this case.

A middleware goal that fails outright (rather than unifying Outcome
with continue/handled) is treated exactly like an explicit `continue`
result -- ordinary Prolog failure means "did not apply, move on,"
matching adr/0010's framing of failure as the "decline" case. This is
implemented by wrapping each step so a failed goal falls through to
the next middleware instead of failing run_middleware_chain/3 as a
whole.

A middleware goal that throws aborts the fold immediately; the
exception is caught once, at the top of the chain (here, in
run_middleware_chain/3), and reported back to the caller as
FinalOutcome = error(Ball) rather than propagating further and
crashing the worker.
*/

:- dynamic middleware/1.

:- meta_predicate use_middleware(:).

%!  use_middleware(:Goal) is det.
%
%   Registers Goal as a global middleware, called as
%   call(Goal, Request, ResponseStream, Outcome) for every request, in
%   registration order, ahead of routing.
use_middleware(Goal) :-
    strip_module(Goal, M, G),
    assertz(middleware(M:G)).

%!  clear_middleware is det.
%
%   Removes all registered middleware. Handy for tests.
clear_middleware :-
    retractall(middleware(_)).

%!  run_middleware_chain(+Request, +ResponseStream, -FinalOutcome) is det.
%
%   Folds the registered middleware (registration order) over
%   Request/ResponseStream. FinalOutcome unifies with:
%
%     - `continue`   -- every middleware declined; proceed to routing.
%     - `handled`    -- some middleware fully wrote a response and the
%                       chain stopped there; do not route.
%     - `error(Ball)`-- some middleware threw Ball; the chain stopped
%                       there and the exception was caught, not
%                       propagated.
run_middleware_chain(Request, ResponseStream, FinalOutcome) :-
    findall(M, middleware(M), Middlewares),
    catch(run_chain(Middlewares, Request, ResponseStream, FinalOutcome),
          Ball,
          FinalOutcome = error(Ball)).

run_chain([], _Request, _ResponseStream, continue).
run_chain([Goal|Goals], Request, ResponseStream, FinalOutcome) :-
    ( call(Goal, Request, ResponseStream, Outcome)
    -> true
    ;  Outcome = continue          % failure == decline, per adr/0010
    ),
    ( Outcome == handled
    -> FinalOutcome = handled
    ;  run_chain(Goals, Request, ResponseStream, FinalOutcome)
    ).
