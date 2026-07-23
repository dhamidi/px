:- module(app_middleware, []).

/** <module> Cross-feature concerns (adr/0029 decision 3): plain env
relations (adr/0017) declared where the filesystem says "cross-app".
Auth, rate limiting, request ids follow the same shape -- an env
relation here, one line in the pipeline; a failing element declines
the request (adr/0017 fold semantics).
*/

:- use_module(library(prologex)).

:- pipeline([ log_requests,
              method_override,
              route_dispatch,
              turbo_frames
            ]).

%   Request logging to stderr (journald under systemd): method and
%   path on the way in, before dispatch.
log_requests(Env, Env) :-
    env_get(Env, method, Method),
    env_get(Env, path, Path),
    format(user_error, "~w ~w~n", [Method, Path]).
