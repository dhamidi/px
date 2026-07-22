# 0017. A Rack-style environment dict threaded relationally

Status: Accepted

## Context

Rack's great idea was an interface, not a library: an application is
any callable that takes an env hash and returns a response. Because
every server, router, and middleware in the Ruby world speaks that one
shape, they all compose — a middleware is just an app that wraps
another app. Rails itself is "merely" a very large Rack app.

Version 1 of prologex has no such interface. The transport hands
`http_stream.pl`'s request dict to `app:dispatch/2`, which calls route
handlers under a four-argument convention:

```prolog
call(Handler, Request, ResponseStream, PathParams, QueryParams)
```

Handlers receive a live output stream and are required to write a
complete response — status line, headers, body — before returning
(`prolog/app.pl`). Middleware (adr/0010) threads a different state
than handlers see, path and query parameters travel as two separate
positional lists, and nothing downstream can inspect or modify a
response once a handler has written it, because it is already bytes
on a buffered stream. adr/0016 declared this convention retired and
fixed the replacement shape: one env, threaded relationally. This ADR
specifies that env.

The Prolog translation of Rack is strictly better than the original,
because the language already has what Rack had to invent conventions
for:

- **An app is a relation, not a callable.** `App(Env0, Env)` relates
  the environment before to the environment after. Rack's app
  *returns* its response; ours *is* a pair of environments.
- **Composition is conjunction.** Two middleware compose as
  `mw_a(E0, E1), mw_b(E1, E)`. No wrapping, no `call(next)`.
- **A middleware chain is a fold.** `foldl`-style threading over a
  goal list, exactly adr/0010's model, now over env dicts.
- **"Did not handle" is failure.** Rack needs status-code conventions
  (`X-Cascade: pass`, 404-means-decline) to express "not me, try the
  next one". Prolog spells it with its own control construct: the
  goal fails, and the caller tries the next alternative.

## Decision

### The env dict

Every request is represented by a single SWI-Prolog dict with tag
`env`. Handlers and middleware are relations `Goal(Env0, Env)` over
it — adr/0016 rule 1. A freshly built env for
`GET /posts/7?utm=news` looks like this:

```prolog
env{
  method:   get,
  path:     "/posts/7",
  raw_path: "/posts/7?utm=news",
  headers:  ["host"-"example.org", "accept"-"text/html"],
  params:   _{id: "7", utm: "news"},
  body:     <stream>(0x55f3...),
  worker:   2,
  config:   ConfigSnapshot,
  response: _{status: 200, headers: [], body: none}
}
```

The standardized keys, their types, and who sets them:

- `method` — lowercase atom (`get`, `post`, `patch`, ...). Set by the
  transport edge from llhttp's method, downcased once so route
  matching never repeats v1's per-request `downcase_atom/2`.
- `path` — string, the decoded request path without the query string
  (`"/posts/7"`). Set by the transport edge via `library(uri)`.
- `raw_path` — string, the request target exactly as received,
  query string included (`"/posts/7?utm=news"`). Set by the transport
  edge. Useful for logging and for redirect-back-after-login.
- `headers` — list of `Name-Value` pairs, both strings, names
  lowercased, in wire order. Set by the transport edge from the
  llhttp header events.
- `params` — a dict merging, Rails-style, three sources into one
  place: path parameters, query-string parameters, and the parsed
  form body (when the request is form-encoded; adr/0023). Query
  parameters are merged in by the transport edge, form parameters by
  the framework's form machinery (which consumes `body` through
  adr/0007's convenience layer), and path parameters by the router
  when a route matches. **Precedence on key collision: path params
  win over query params, which win over form params.** A route
  declared as `"/posts/:id"` therefore guarantees that
  `Env.params.id` is the path segment, no matter what a query string
  or form field claims. Keys are atoms, values strings.
- `body` — the request body input stream, per adr/0007. Handlers
  that want raw or truly streaming access (uploads straight to disk,
  proxying) read this stream directly; everyone else ignores it and
  uses `params`. Set by the transport edge.
- `worker` — the id of the worker serving this request (adr/0005).
  Set by the transport edge; intended for logging and diagnostics.
- `config` — a snapshot accessor over the app's configuration
  (adr/0022), taken at request start so a request sees one consistent
  configuration. Queried as `call(Env.config, Key, Value)`. Set by
  the transport edge.
- `response` — a sub-dict `_{status: 200, headers: [], body: none}`,
  initialized by the transport edge and rewritten by handlers and
  middleware via the helpers below. `status` is an integer, `headers`
  a list of `Name-Value` pairs to emit in addition to the framed
  transfer headers, and `body` is a **template term** (adr/0019) —
  `view(post_show(Post))`, `text("pong")`, `none` — never bytes.

That last point is the composition payoff and deserves emphasis.
Because `response.body` stays a term for the whole pipeline,
rendering happens exactly once, at the edge, after the entire
middleware chain has run. Middleware can wrap, replace, or unwrap the
body term — apply a layout, strip it back down to a bare
`turbo_frame` for a Turbo request (adr/0024) — with zero
re-rendering and zero buffering, because nothing has been rendered
yet. A layout middleware is three lines:

```prolog
%% Wrap whatever the handler produced in the site chrome.
%% Runs after the router in the pipeline; by then response.body
%% is a term like view(post_show(Post)).
apply_layout(Env0, Env) :-
    Body0 = Env0.response.body,
    Env = Env0.put(response/body, layout("My blog", Body0)).
```

In v1 this middleware is impossible: the handler already wrote the
bytes. In Rack it is possible but expensive: the inner app's body has
been rendered to strings, so the layout middleware buffers and
re-concatenates them. Here it is a single dict put.

### Extensibility

The key list above is a floor, not a ceiling. Any middleware may add
its own keys via `Env0.put(...)`; dicts make this safe (no positional
arguments to renumber) and cheap (structural sharing), and unknown
keys ride along untouched through every step that does not care about
them. Conventional examples are `session` and `current_user`:

```prolog
%% Auth middleware: attach the current user, or decline the request
%% outright for protected paths.
authenticate(Env0, Env) :-
    (   User = Env0.session.get(user_id),
        once(row(q(users, [where(id == User)]), U))
    ->  Env = Env0.put(current_user, U)
    ;   sub_string(Env0.path, 0, _, _, "/admin")
    ->  redirect(Env0, login_path, Env)
    ;   Env = Env0.put(current_user, guest)
    ).
```

Downstream, any handler simply reads `Env0.current_user` — no
threading of extra arguments, no globals, no request-scoped mutable
state.

### Helpers

Handlers never touch `response` by hand; four helpers cover the
cases. All of them are pure dict-put operations — **no I/O happens in
handlers or middleware, ever**. The only code that writes to the
socket is the transport edge, after the pipeline finishes.

```prolog
%!  respond(+Env0, +Template, -Env) is det.
%!  respond(+Env0, +Template, +Opts, -Env) is det.
%
%   Set the response body to Template (adr/0019 term). Opts:
%     status(Code)     - response status, default 200
%     header(N, V)     - extra response header, may repeat

respond(Env0, Template, Env) :-
    respond(Env0, Template, [], Env).

respond(Env0, Template, Opts, Env) :-
    (   memberchk(status(Code), Opts) -> true ; Code = 200 ),
    findall(N-V, member(header(N, V), Opts), Headers),
    Env = Env0.put(response,
                   _{status: Code, headers: Headers, body: Template}).

%!  redirect(+Env0, +PathTerm, -Env) is det.
%
%   303 See Other to a route-helper term (adr/0018): PathTerm is
%   post_path(Id) or login_path — a term, never a string literal —
%   evaluated to its path string internally by the reversible
%   router. 303 so that redirects after non-GET forms behave under
%   Turbo (adr/0024).

redirect(Env0, PathTerm, Env) :-
    path_for(PathTerm, Path),
    Env = Env0.put(response,
                   _{status: 303,
                     headers: ["location"-Path],
                     body: none}).

%!  not_found(+Env0, -Env) is det.

not_found(Env0, Env) :-
    respond(Env0, view(not_found), [status(404)], Env).
```

Usage, matching adr/0016's worked example exactly:

```prolog
show(Env0, Env) :-
    Id = Env0.params.id,
    once(row(q(posts, [where(id == Id)]), Post)),
    respond(Env0, view(post_show(Post)), Env).

create(Env0, Env) :-
    form_result(post_form, Env0, Result),
    (   Result = ok(Values)
    ->  insert(posts, Values, Id),
        redirect(Env0, post_path(Id), Env)
    ;   Result = invalid(Values, Errors)
    ->  respond(Env0, view(post_form_view(Values, Errors)),
                [status(422)], Env)
    ).
```

### The pipeline

An app declares its middleware stack, in order, with one directive:

```prolog
:- pipeline([request_logger, session, authenticate, router,
             apply_layout]).
```

Each element is an env-relation `Step(Env0, Env)`. Per adr/0016 rule
7, the directive captures the defining module at expansion time, so
none of these names is module-qualified. The runner is adr/0010's
fold, now over env dicts:

```prolog
run_pipeline([], Env, Env).
run_pipeline([Step|Steps], Env0, Env) :-
    (   call(Step, Env0, Env1)
    ->  true
    ;   Env1 = Env0                 % declined: env passes untouched
    ),
    run_pipeline(Steps, Env1, Env).
```

Failure and exception semantics follow adr/0010, with one place
where failure is doing real routing work:

- An **ordinary middleware** that fails has declined; it is skipped
  and the env flows on unchanged to the next step. It must not use
  failure to mean "error" — that is what exceptions are for.
- **Inside the router** (itself just another pipeline step), failure
  is the routing mechanism: each declared route is tried in turn, and
  a route whose method or path pattern does not unify fails over to
  the next route. When every route has declined, the router calls
  `not_found/2`, so the pipeline as a whole still succeeds with a
  well-formed 404 response.
- **Exceptions** thrown anywhere in the pipeline propagate to the
  single `catch/3` at the transport edge and become a real HTTP 500,
  exactly as v1's `app:dispatch/2` already does (adr/0010).

### The transport edge

`http_stream.pl`'s integration point changes from "call RequestGoal
with a request dict and a live response stream" to "build the initial
env, run the pipeline, render the final env's response". Where v1's
`on_message_complete/4` did

```prolog
Request = _{method: Method, url: Url, headers: Headers, body: Body},
uv_response_stream(Client, ResponseStream),
call(RequestGoal, Request, ResponseStream)
```

the edge now does, in outline:

```prolog
make_env(Method, Url, Headers, BodyStream, WorkerId, Env0),
run_pipeline(Pipeline, Env0, Env),
uv_response_stream(Client, Out),
write_status_and_headers(Out, Env.response),
render(Out, Env.response.body)       % adr/0019: streams the term
```

This is the *single* place bytes are produced. `render/2` walks the
template term writing tags to `Out` as it goes — adr/0016 rule 5, no
output byte buffer — over the same response `IOSTREAM` machinery
adr/0007 established, chunked when the length is unknown. Everything
before this line was pure dict transformation on the worker's own
thread.

## Consequences

The v1 four-argument convention
`Handler(Request, Stream, PathParams, QueryParams)` documented in
`prolog/app.pl` is retired, and with it its costs: handlers doing I/O
mid-logic, two parallel parameter lists instead of one `params` dict,
`Stream` variables in application code (banned by adr/0016), and the
structural impossibility of response-transforming middleware.
`app.pl`, `middleware.pl`, and `response.pl` are reworked onto the
env; `http_stream.pl` keeps its llhttp accumulator and IOSTREAM
plumbing but hands off an env instead of a `(Request, Stream)` pair.

Against Rack itself, the comparison the ADR title invites: Rack
threads one *mutable* hash and returns a `[status, headers, body]`
array whose body must respond to `each` — so wrapping a response
means intercepting an enumerable of already-rendered strings, and
"decline" needs status-code conventions. The prologex env is an
immutable dict threaded through relations: every middleware's input
and output are honest values (a failed step cannot have half-mutated
anything), composition is conjunction, decline is failure, and the
response body is still a term when the last middleware sees it.

Two trade-offs are accepted knowingly. First, because `response.body`
is a template term rather than bytes, the data inside it — a `Posts`
list captured in `view(post_index(Posts))`, a `Post` dict — stays
live from the moment the handler builds it until the edge renders it.
For a large result set that is a real retention window that v1's
write-as-you-go handlers did not have; the mitigation is adr/0016
rule 6 (templates iterating rows via nondeterminism rather than
pre-collected lists) where it matters. Second, handlers lose the
ability to emit bytes early — first-byte time is after the pipeline
completes. That is the price of letting middleware see whole
responses as terms, and adr/0019's streaming render keeps the edge
itself buffer-free once rendering starts.
