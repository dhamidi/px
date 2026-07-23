:- module(px_console,
          [ init_console/0,          % boot: generate the per-boot token
            console_token/1,         % -Token   (dev only)
            console_page/2,          % +Env0, -Env   (GET, the console page)
            console_eval/2           % +Env0, -Env   (POST, the REPL endpoint)
          ]).

/** <module> The development console and rich error page (adr/0038).

Loaded by the facade, but INERT unless boot turns it on: prologex.pl's
enable_dev_console/0 runs only when current_env(development), and it is
the only caller of init_console/0 and the only place the console route
(/__px/console) is registered. In production none of that runs -- the
route is absent (a request to it is an ordinary 404), and a px build
binary (loaded under PROLOGEX_ENV=production) contains no console route
at all. This module's safety rests entirely on that boot gate.

Two capabilities, both development-only:

  - dev_error_render/4 (the px_env multifile hook): turns a terse
    404/500 into a diagnostic page -- the failure classified from the
    request breadcrumb trace (px_env:request_trace/1), the plain-term
    env dumped legibly, the error term for a 500, the route table for
    a 404, and the inline REPL form.

  - console_eval/2: the REPL endpoint. Evaluates a goal string and
    returns its output/bindings. Powerful, hence gated three ways:
    the route only exists in development; a per-boot 128-bit token
    (embedded only in the same-origin error page) is required, so a
    blind cross-site POST cannot reach it; and it is never present in
    a production/binary build.
*/

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(crypto)).
:- use_module(px_env, [respond/4, param/3, params/2, env_get/3,
                       request_trace/1]).
:- use_module(px_template, [render_to_string/2]).

:- dynamic console_token_fact/1.

%!  init_console is det.
%
%   Generate the per-boot random token (adr/0038). Called once by
%   prologex.pl's enable_dev_console/0, development only.
init_console :-
    retractall(console_token_fact(_)),
    crypto_n_random_bytes(16, Bytes),
    hex_bytes(Hex, Bytes),
    atom_string(Hex, Token),
    assertz(console_token_fact(Token)).

console_token(Token) :-
    console_token_fact(Token).


		 /*******************************
		 *      THE REPL ENDPOINT       *
		 *******************************/

%!  console_eval(+Env0, -Env) is det.
%
%   Reachable only in development (the route is mounted only then).
%   Requires the per-boot token; a mismatch is a flat 403 with no
%   detail. On success, evaluate the goal string in module `user`
%   (app predicates are called qualified, e.g.
%   `guestbook_commands:load_comments(Cs)`), capturing output and the
%   first solution's bindings, and answer an HTML fragment.
console_eval(Env0, Env) :-
    (   param(Env0, token, Tok),
        console_token(Expected),
        Tok == Expected
    ->  (   param(Env0, goal, GoalStr)
        ->  eval_goal(GoalStr, Html)
        ;   Html = "<p class=\"px-console-error\">no goal</p>"
        ),
        respond(Env0, raw(Html),
                [ status(200),
                  header("content-type", "text/html; charset=utf-8") ],
                Env)
    ;   respond(Env0, "forbidden", [status(403)], Env)
    ).

eval_goal(GoalStr, Html) :-
    catch(read_term_from_atom(GoalStr, Goal, [variable_names(Vars)]),
          ReadErr,
          ( format(string(Html), "<p class=\"px-console-error\">parse error: ~w</p>",
                   [ReadErr]), Vars = fail )),
    (   Vars == fail
    ->  true                                    % Html already set
    ;   run_goal(Goal, Vars, Html)
    ).

run_goal(Goal, Vars, Html) :-
    (   catch(with_output_to(string(Output), once_result(Goal, Solved)),
              Err, Failed = Err)
    ->  true
    ;   Solved = failed, Output = ""
    ),
    (   nonvar(Failed)
    ->  format(string(Html),
               "<pre class=\"px-console-error\">~w</pre>",
               [Failed])
    ;   Solved == failed
    ->  Html = "<pre class=\"px-console-out\">false.</pre>"
    ;   bindings_html(Vars, BindHtml),
        (   Output == ""
        ->  format(string(Html), "<pre class=\"px-console-out\">~wtrue.</pre>", [BindHtml])
        ;   escape_html(Output, EscOut),
            format(string(Html),
                   "<pre class=\"px-console-out\">~w~wtrue.</pre>",
                   [EscOut, BindHtml])
        )
    ).

once_result(Goal, Solved) :-
    (   call(Goal)
    ->  Solved = solved
    ;   Solved = failed
    ),
    !.

bindings_html([], "") :- !.
bindings_html(Vars, Html) :-
    findall(Line,
            ( member(Name=Value, Vars),
              format(string(V0), "~p", [Value]),
              escape_html(V0, V),
              format(string(Line), "~w = ~w\n", [Name, V]) ),
            Lines),
    atomics_to_string(Lines, Html).

atomics_to_string(List, S) :-
    atomic_list_concat(List, Atom),
    atom_string(Atom, S).


		 /*******************************
		 *      THE CONSOLE PAGE        *
		 *******************************/

%!  console_page(+Env0, -Env) is det.
%
%   GET /__px/console -- the REPL as a standalone, browsable page
%   (adr/0038). Registered only in development (prologex.pl's
%   enable_dev_console/0), so it does not exist in production; this
%   handler is never reached there. Same shell as the error page --
%   the request env dumped as a legible plain term, the route table,
%   and the token-guarded REPL -- with a console intro in place of a
%   failure classification.
console_page(Env0, Env) :-
    Intro = "<p class=\"px-hint\">Evaluate goals against the running application. \
Call app predicates qualified, e.g. <code>guestbook_commands:load_comments(Cs)</code>. \
This page exists only in development.</p>",
    ( console_token(Token) -> true ; Token = "" ),
    env_dump(Env0, EnvHtml),
    routes_html(RoutesHtml),
    format(string(Html),
"<!DOCTYPE html><html><head><meta charset=\"utf-8\">\
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\
<title>Console — prologex (development)</title><style>~w</style></head><body>\
<div class=\"px-diag\">\
<h1>Development console</h1>~w\
<form class=\"px-console\" onsubmit=\"return pxEval(event)\">\
<input type=\"hidden\" name=\"token\" value=\"~w\">\
<textarea name=\"goal\" rows=\"3\" placeholder=\"a goal, e.g. some_commands:load(X)\"></textarea>\
<button>Evaluate</button></form>\
<div class=\"px-console-result\" id=\"pxout\"></div>\
<h2>Request</h2><pre class=\"px-env\">~w</pre>\
<h2>Routes</h2>~w\
</div>\
<script>~w</script></body></html>",
           [page_css, Intro, Token, EnvHtml, RoutesHtml, page_js]),
    respond(Env0, raw(Html),
            [ status(200), header("content-type", "text/html; charset=utf-8") ],
            Env).


		 /*******************************
		 *     THE RICH ERROR PAGE      *
		 *******************************/

:- multifile px_env:dev_error_render/4.

%   The hook px_env consults in development for a 404/500 (adr/0038).
px_env:dev_error_render(Env0, Diag, Status, raw(Html)) :-
    px_console:error_page(Env0, Diag, Status, Html).

error_page(Env0, Diag, Status, Html) :-
    request_trace(Trace),
    classify(Diag, Status, Trace, Env0, Headline, Detail),
    env_dump(Env0, EnvHtml),
    trace_html(Trace, TraceHtml),
    routes_html(RoutesHtml),
    ( console_token(Token) -> true ; Token = "" ),
    format(string(Html),
"<!DOCTYPE html><html><head><meta charset=\"utf-8\">\
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\
<title>~w — prologex (development)</title><style>~w</style></head><body>\
<div class=\"px-diag\">\
<h1>~w</h1>~w\
<h2>Request</h2><pre class=\"px-env\">~w</pre>\
<h2>What happened</h2>~w\
<h2>Console</h2>\
<form class=\"px-console\" onsubmit=\"return pxEval(event)\">\
<input type=\"hidden\" name=\"token\" value=\"~w\">\
<textarea name=\"goal\" rows=\"2\" placeholder=\"a goal, e.g. some_commands:load(X)\"></textarea>\
<button>Evaluate</button></form>\
<div class=\"px-console-result\" id=\"pxout\"></div>\
<h2>Routes</h2>~w\
</div>\
<script>~w</script></body></html>",
           [Status, page_css, Headline, Detail, EnvHtml, TraceHtml,
            Token, RoutesHtml, page_js]).

%   Classify the failure from the breadcrumb trace (adr/0038 the
%   headline feature): distinguish a thrown exception, a handler that
%   ran but declined (the silent-404 case), and no route at all.
classify(error(E), _, _, _, "500 — an exception was thrown", Detail) :-
    !,
    message_to_string(E, Msg),
    ( E = error(_, context(Ctx, _)) -> format(string(CtxS), "~p", [Ctx]) ; CtxS = "" ),
    escape_html(Msg, EMsg),
    format(string(Detail),
           "<pre class=\"px-error\">~w</pre><p class=\"px-hint\">~w</p>",
           [EMsg, CtxS]).
classify(_, 404, Trace, Env0, Headline, Detail) :-
    env_get(Env0, method, M), env_get(Env0, path, P),
    (   member(model_failed(Mod, Action), Trace)
    ->  Headline = "404 — the model failed",
        format(string(Detail),
               "<p><code>~w ~w</code> reached <code>~w:model(~w, ...)</code>, which <b>failed</b> — and a failing model is the 404 (adr/0027). The usual causes: a <code>row/2</code> lookup with no match, a <code>path_id</code> that didn't parse, or a <code>field/3</code> on a column that isn't there. Reproduce it in the console below.</p>",
               [M, P, Mod, Action])
    ;   member(handler(Mod, Action), Trace)
    ->  Headline = "404 — handler ran, produced nothing",
        format(string(Detail),
               "<p><code>~w ~w</code> matched <code>~w:~w</code>, but it declined (authorization, or an update with no matching clause). See the console.</p>",
               [M, P, Mod, Action])
    ;   Headline = "404 — no route matched",
        format(string(Detail),
               "<p>Nothing in the route table matches <code>~w ~w</code>. The full table is at the bottom.</p>",
               [M, P])
    ).
classify(_, Status, _, _, Headline, "") :-
    format(string(Headline), "~w", [Status]).

%   The env as a legible aligned dump -- the payoff of the plain-term
%   representation (adr/0037): it just prints.
env_dump(Env0, Html) :-
    findall(Line,
            ( member(Key-Value, Env0),
              Key \== config,
              format(string(V0), "~p", [Value]),
              escape_html(V0, V),
              format(string(Line), "~w~t~14|~w\n", [Key, V]) ),
            Lines),
    atomics_to_string(Lines, Html).

trace_html([], "<p class=\"px-hint\">(no breadcrumbs)</p>") :- !.
trace_html(_, "") .   % detail already carries the story; keep the section lean

routes_html(Html) :-
    findall(Row,
            ( router:route(Name, Method, Segments, _),
              seg_path(Segments, Path),
              format(string(Row), "<tr><td>~w</td><td>~w</td><td>~w</td></tr>",
                     [Method, Path, Name]) ),
            Rows),
    atomics_to_string(Rows, Body),
    format(string(Html), "<table class=\"px-routes\"><tr><th>method</th><th>path</th><th>name</th></tr>~w</table>", [Body]).

seg_path([], "/") :- !.
seg_path(Segs, Path) :-
    maplist(seg_str, Segs, Parts),
    atomic_list_concat([''|Parts], '/', P),
    atom_string(P, Path).
seg_str(param(N), S) :- !, format(atom(S), ":~w", [N]).
seg_str(splat(N), S) :- !, format(atom(S), "*~w", [N]).
seg_str(A, A).

escape_html(In, Out) :-
    to_str(In, S),
    replace_all(S, "&", "&amp;", A),
    replace_all(A, "<", "&lt;", B),
    replace_all(B, ">", "&gt;", Out).

%   Split on the single-char From and rejoin with To.
replace_all(S, From, To, Out) :-
    split_string(S, From, "", Parts),
    atomic_list_concat(Parts, To, Atom),
    atom_string(Atom, Out).

to_str(X, S) :- ( string(X) -> S = X ; atom(X) -> atom_string(X, S) ; format(string(S), "~w", [X]) ).

page_css("body{margin:0;background:#0f1115;color:#e6e8eb;font-family:-apple-system,Segoe UI,sans-serif}.px-diag{max-width:900px;margin:0 auto;padding:2rem 1.25rem}h1{font-size:1.4rem;color:#f87171}h2{font-size:1rem;color:#9aa4b2;border-bottom:1px solid #262b34;padding-bottom:.3rem;margin-top:2rem}code{background:#1c2129;padding:.1em .35em;border-radius:4px}pre{background:#161a21;border:1px solid #262b34;border-radius:8px;padding:1rem;overflow:auto;white-space:pre-wrap}.px-env{color:#849dff}.px-error{color:#f87171}.px-hint{color:#9aa4b2}.px-console textarea{width:100%;background:#0f1115;color:#e6e8eb;border:1px solid #262b34;border-radius:8px;padding:.6rem;font-family:SF Mono,Consolas,monospace}.px-console button{margin-top:.5rem;background:#3E63DD;color:#fff;border:none;border-radius:8px;padding:.5rem 1.25rem;font-weight:600;cursor:pointer}.px-routes{width:100%;border-collapse:collapse;font-size:.85rem}.px-routes td,.px-routes th{text-align:left;padding:.3rem .6rem;border-bottom:1px solid #262b34}").

page_js("function pxEval(e){e.preventDefault();var f=e.target;var b=new URLSearchParams();b.set('token',f.token.value);b.set('goal',f.goal.value);fetch('/__px/console',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:b.toString()}).then(r=>r.text()).then(t=>{document.getElementById('pxout').innerHTML=t});return false}").
