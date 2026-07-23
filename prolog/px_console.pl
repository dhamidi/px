:- module(px_console,
          [ init_console/0,          % boot: generate the per-boot token
            console_token/1,         % -Token   (dev only)
            console_page/2,          % +Env0, -Env   (GET, the console page)
            console_eval/2           % +Env0, -Env   (POST, the REPL endpoint)
          ]).

/** <module> The development console and rich error page (adr/0038).

Loaded by the facade, but INERT unless boot turns it on: prologex.pl's
enable_dev_console/0 runs only when current_env(development), and it is
the only caller of init_console/0 and the only place the console routes
(GET + POST /__px/console) are registered. In production none of that
runs -- the routes are absent (a request is an ordinary 404), and a
px build binary (loaded under PROLOGEX_ENV=production) contains no
console at all. This module's safety rests entirely on that boot gate.

Three capabilities, all development-only:

  - console_page/2 (GET): a standalone, browsable REPL page hosting the
    <px-console> custom element -- a terminal-style scrollback with
    command history and multi-line input.
  - dev_error_render/4 (the px_env multifile hook): turns a terse
    404/500 into a diagnostic page -- the failure classified from the
    request breadcrumb trace, the plain-term env dumped legibly, the
    route table, and the same <px-console> REPL inline.
  - console_eval/2 (POST): the eval endpoint. Reads a goal, evaluates
    it once, and returns JSON (bindings / output / true / false /
    error). Powerful, hence gated three ways: the routes exist only in
    development; a per-boot 128-bit token (embedded only in the
    same-origin page the element reads it from) is required, so a blind
    cross-site POST cannot reach it; and none of it is present in a
    production/binary build.
*/

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(crypto)).
:- use_module(library(http/json)).
:- use_module(px_env, [respond/4, param/3, params/2, env_get/3,
                       request_trace/1]).

:- dynamic console_token_fact/1.

%!  init_console is det.
init_console :-
    retractall(console_token_fact(_)),
    crypto_n_random_bytes(16, Bytes),
    hex_bytes(Hex, Bytes),
    atom_string(Hex, Token),
    assertz(console_token_fact(Token)),
    import_repl_api.

console_token(Token) :-
    console_token_fact(Token).

%   Bring the app-facing API (row/2, config/2, field/3, param/3, ...)
%   into `user` so the REPL -- which evaluates in user -- can call them
%   unqualified, e.g. `row(q(comments, []), R)`. Development only, so
%   this never touches a production process.
import_repl_api :-
    catch(user:use_module(library(prologex)), _, true).

%   Data the console page hands the <px-console> element for
%   discoverability: a few always-safe example goals to click-and-run,
%   and the app's own exported predicates to click-and-insert.
example_goals([ "current_prolog_flag(version, V)",
                "X is 2 + 3 * 4",
                "atom_length(prologex, N)",
                "config(port, Port)",
                "aggregate_all(count, row(q(comments, []), _), N)" ]).

app_pred_strings(Preds) :-
    findall(S,
            ( app_module(M),
              module_property(M, exports(Exports)),
              member(Name/Arity, Exports),
              Arity > 0,
              format(string(S), "~w:~w/~w", [M, Name, Arity]) ),
            Ss),
    sort(Ss, Preds).

%   Modules whose defining file lives under the application directory
%   (the `app` search path). atom(Dir) skips SWI 10's compound built-in
%   file_search_path(app, swi(app)), same as px_reload.
app_module(M) :-
    current_module(M),
    module_property(M, file(F)),
    app_root_dir(Dir),
    sub_atom(F, 0, _, _, Dir).

app_root_dir(Dir) :-
    user:file_search_path(app, Dir),
    atom(Dir),
    !.

console_data_json(JsonStr) :-
    example_goals(Runs),
    ( app_pred_strings(Preds) -> true ; Preds = [] ),
    with_output_to(string(JsonStr),
                   json_write(current_output, json([run=Runs, preds=Preds]),
                              [width(0)])).


		 /*******************************
		 *      THE EVAL ENDPOINT       *
		 *******************************/

%!  console_eval(+Env0, -Env) is det.
%
%   POST /__px/console (development only). Requires the per-boot token;
%   a mismatch is a 403. On success, evaluate the goal string once in
%   module `user` (app predicates called qualified), capturing output
%   and the first solution's bindings, and answer JSON the <px-console>
%   element renders.
console_eval(Env0, Env) :-
    (   param(Env0, token, Tok),
        console_token(Expected),
        Tok == Expected
    ->  (   param(Env0, goal, GoalStr)
        ->  eval_json(GoalStr, Json)
        ;   Json = json([ok= @(false), error="no goal given"])
        ),
        json_response(Env0, 200, Json, Env)
    ;   json_response(Env0, 403, json([ok= @(false), error="forbidden"]), Env)
    ).

json_response(Env0, Status, JsonTerm, Env) :-
    with_output_to(string(S), json_write(current_output, JsonTerm, [width(0)])),
    respond(Env0, raw(S),
            [ status(Status),
              header("content-type", "application/json; charset=utf-8") ],
            Env).

%!  eval_json(+GoalStr, -JsonTerm) is det.
eval_json(GoalStr, JsonTerm) :-
    catch(
        ( read_term_from_atom(GoalStr, Goal, [variable_names(Vars)]),
          run_json(Goal, Vars, JsonTerm) ),
        Err,
        ( message_to_string(Err, M),
          JsonTerm = json([ok= @(false), error=M]) )).

run_json(Goal, Vars, JsonTerm) :-
    (   catch(with_output_to(string(Output), solve(Goal, Solved)),
              GErr, GCaught = GErr)
    ->  true
    ;   Solved = false, Output = ""
    ),
    (   nonvar(GCaught)
    ->  message_to_string(GCaught, EM),
        JsonTerm = json([ok= @(false), error=EM])
    ;   bindings_json(Vars, BJson),
        JsonTerm = json([ ok= @(true),
                          solved= @(Solved),
                          output=Output,
                          bindings=BJson ])
    ).

%   Evaluate in `user`, not px_console: unqualified goals resolve
%   against user's imports (library preds, and app predicates called
%   qualified), and an error reads `user:foo/1`, not the framework's
%   internals.
solve(Goal, Solved) :-
    (   call(user:Goal)
    ->  Solved = true
    ;   Solved = false
    ),
    !.

bindings_json([], []).
bindings_json([Name=Value|T], [json([name=NameS, value=VS])|R]) :-
    to_str(Name, NameS),
    format(string(VS), "~p", [Value]),
    bindings_json(T, R).


		 /*******************************
		 *      THE CONSOLE PAGE        *
		 *******************************/

%!  console_page(+Env0, -Env) is det.
%
%   GET /__px/console (development only): the REPL as a standalone,
%   browsable page.
console_page(Env0, Env) :-
    Intro = "<p class=\"pxd-hint\">Evaluate goals against the running application. \
Call app predicates qualified, e.g. <code>guestbook_commands:load_comments(Cs)</code>.</p>",
    render_page("Console", "Development console", Intro, Env0, Html),
    respond(Env0, raw(Html),
            [ status(200), header("content-type", "text/html; charset=utf-8") ],
            Env).


		 /*******************************
		 *     THE RICH ERROR PAGE      *
		 *******************************/

:- multifile px_env:dev_error_render/4.

px_env:dev_error_render(Env0, Diag, Status, raw(Html)) :-
    px_console:error_page(Env0, Diag, Status, Html).

error_page(Env0, Diag, Status, Html) :-
    request_trace(Trace),
    classify(Diag, Status, Trace, Env0, Headline, Detail),
    render_page(Status, Headline, Detail, Env0, Html).


		 /*******************************
		 *        THE PAGE SHELL        *
		 *******************************/

%!  render_page(+Title, +Headline, +DetailHtml, +Env0, -Html) is det.
%
%   The shared shell: title, headline, a detail block (error
%   classification or console intro), the <px-console> element, then
%   the plain-term request env and the route table.
render_page(Title, Headline, Detail, Env0, Html) :-
    ( console_token(Token) -> true ; Token = "" ),
    env_dump(Env0, EnvHtml),
    routes_html(RoutesHtml),
    console_data_json(DataJson),
    shell_css(ShellCss),
    console_js(ConsoleJs),
    format(string(Html),
"<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\">\
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\
<title>~w — prologex (development)</title><style>~w</style></head><body>\
<div class=\"pxd\">\
<h1>~w</h1>~w\
<px-console token=\"~w\"></px-console>\
<details class=\"pxd-more\"><summary>request</summary><pre class=\"pxd-env\">~w</pre></details>\
<details class=\"pxd-more\"><summary>routes</summary>~w</details>\
</div>\
<script type=\"application/json\" id=\"pxc-data\">~w</script>\
<script>~w</script></body></html>",
           [Title, ShellCss, Headline, Detail, Token, EnvHtml, RoutesHtml,
            DataJson, ConsoleJs]).


		 /*******************************
		 *       ERROR CLASSIFY         *
		 *******************************/

classify(error(E), _, _, _, "500 — an exception was thrown", Detail) :-
    !,
    message_to_string(E, Msg),
    ( E = error(_, context(Ctx, _)) -> format(string(CtxS), "~p", [Ctx]) ; CtxS = "" ),
    escape_html(Msg, EMsg),
    format(string(Detail),
           "<pre class=\"pxd-error\">~w</pre><p class=\"pxd-hint\">~w</p>",
           [EMsg, CtxS]).
classify(_, 404, Trace, Env0, Headline, Detail) :-
    env_get(Env0, method, M), env_get(Env0, path, P),
    (   member(model_failed(Mod, Action), Trace)
    ->  Headline = "404 — the model failed",
        format(string(Detail),
               "<p><code>~w ~w</code> reached <code>~w:model(~w, ...)</code>, which <b>failed</b> — and a failing model is the 404 (a failed row lookup, a <code>path_id</code> that didn't parse, a <code>field/3</code> on a missing column). Reproduce it below.</p>",
               [M, P, Mod, Action])
    ;   member(handler(Mod, Action), Trace)
    ->  Headline = "404 — handler ran, produced nothing",
        format(string(Detail),
               "<p><code>~w ~w</code> matched <code>~w:~w</code>, but it declined.</p>",
               [M, P, Mod, Action])
    ;   Headline = "404 — no route matched",
        format(string(Detail),
               "<p>Nothing in the route table matches <code>~w ~w</code>.</p>",
               [M, P])
    ).
classify(_, Status, _, _, Headline, "") :-
    format(string(Headline), "~w", [Status]).

env_dump(Env0, Html) :-
    findall(Line,
            ( member(Key-Value, Env0),
              Key \== config,
              format(string(V0), "~p", [Value]),
              escape_html(V0, V),
              format(string(Line), "~w~t~14|~w\n", [Key, V]) ),
            Lines),
    atomics_to_string(Lines, Html).

routes_html(Html) :-
    findall(Row,
            ( router:route(Name, Method, Segments, _),
              seg_path(Segments, Path),
              format(string(Row), "<tr><td>~w</td><td>~w</td><td>~w</td></tr>",
                     [Method, Path, Name]) ),
            Rows),
    atomics_to_string(Rows, Body),
    format(string(Html),
           "<table class=\"pxd-routes\"><tr><th>method</th><th>path</th><th>name</th></tr>~w</table>",
           [Body]).

seg_path([], "/") :- !.
seg_path(Segs, Path) :-
    maplist(seg_str, Segs, Parts),
    atomic_list_concat([''|Parts], '/', P),
    atom_string(P, Path).
seg_str(param(N), S) :- !, format(atom(S), ":~w", [N]).
seg_str(splat(N), S) :- !, format(atom(S), "*~w", [N]).
seg_str(A, A).


		 /*******************************
		 *         SMALL BITS           *
		 *******************************/

escape_html(In, Out) :-
    to_str(In, S),
    replace_all(S, "&", "&amp;", A),
    replace_all(A, "<", "&lt;", B),
    replace_all(B, ">", "&gt;", Out).

replace_all(S, From, To, Out) :-
    split_string(S, From, "", Parts),
    atomic_list_concat(Parts, To, Atom),
    atom_string(Atom, Out).

to_str(X, S) :- ( string(X) -> S = X ; atom(X) -> atom_string(X, S) ; format(string(S), "~w", [X]) ).

atomics_to_string(List, S) :-
    atomic_list_concat(List, Atom),
    atom_string(Atom, S).


		 /*******************************
		 *        STYLE + ELEMENT       *
		 *******************************/

shell_css("*{box-sizing:border-box}body{margin:0;background:#0f1115;color:#e6e8eb;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif;line-height:1.55}.pxd{max-width:920px;margin:0 auto;padding:2rem 1.25rem 4rem}.pxd h1{font-size:1.35rem;margin:.2rem 0 .75rem}.pxd-hint{color:#9aa4b2;margin:.25rem 0 1.25rem}.pxd-error{color:#f87171;background:#161a21;border:1px solid #262b34;border-radius:8px;padding:1rem;white-space:pre-wrap;overflow:auto}code{background:#1c2129;padding:.12em .38em;border-radius:5px;font-family:SF Mono,Consolas,Menlo,monospace;font-size:.92em}.pxd-more{margin-top:1.25rem;border-top:1px solid #262b34;padding-top:.5rem}.pxd-more summary{color:#9aa4b2;cursor:pointer;font-size:.85rem;letter-spacing:.04em;text-transform:uppercase;user-select:none}.pxd-env{background:#161a21;border:1px solid #262b34;border-radius:8px;padding:1rem;color:#849dff;font-family:SF Mono,Consolas,Menlo,monospace;font-size:.82rem;white-space:pre-wrap;overflow:auto;margin-top:.75rem}.pxd-routes{width:100%;border-collapse:collapse;font-size:.82rem;margin-top:.75rem}.pxd-routes td,.pxd-routes th{text-align:left;padding:.3rem .6rem;border-bottom:1px solid #262b34}.pxd-routes th{color:#9aa4b2;font-weight:600}\
px-console{display:block;margin:.5rem 0 1rem}.pxc{background:#0a0c10;border:1px solid #2b313c;border-radius:12px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,.4),inset 0 1px 0 rgba(255,255,255,.03);font-family:SF Mono,Consolas,Menlo,monospace;font-size:13px;line-height:1.55}.pxc-bar{display:flex;align-items:center;gap:.4rem;padding:.5rem .85rem;border-bottom:1px solid #1c2129;background:#0f1216}.pxc-dot{width:11px;height:11px;border-radius:50%}.pxc-dot.r{background:#f87171}.pxc-dot.y{background:#e3b341}.pxc-dot.g{background:#3fb950}.pxc-title{margin-left:.4rem;color:#6b7280;font-size:11px;letter-spacing:.05em}.pxc-scroll{max-height:52vh;overflow-y:auto;padding:.85rem 1rem;scroll-behavior:smooth}.pxc-entry{white-space:pre-wrap;word-break:break-word;margin:0 0 .1rem}.pxc-goal{color:#e6e8eb;margin-top:.35rem}.pxc-eprompt{color:#5472e4;user-select:none}.pxc-result{color:#7ee787}.pxc-output{color:#c9d1d9}.pxc-error{color:#f87171}.pxc-info{color:#6b7280;margin-bottom:.35rem}.pxc-pending{color:#6b7280}.pxc-row{display:flex;align-items:flex-start;gap:.55rem;border-top:1px solid #1c2129;padding:.6rem 1rem;background:#0f1216}.pxc-prompt{color:#5472e4;user-select:none;padding-top:1px}.pxc-input{flex:1;background:transparent;color:#e6e8eb;border:0;outline:0;resize:none;font:inherit;padding:0;overflow:hidden}.pxc-input::placeholder{color:#4b5563}\
.pxc-hints{display:flex;flex-wrap:wrap;gap:.4rem;padding:.5rem 1rem .7rem;background:#0f1216;border-top:1px solid #1c2129}.pxc-chip{background:#161a21;color:#9aa4b2;border:1px solid #262b34;border-radius:999px;padding:.28rem .72rem;font:inherit;font-size:12px;cursor:pointer;white-space:nowrap;max-width:100%;overflow:hidden;text-overflow:ellipsis}.pxc-chip:hover{border-color:#3E63DD;color:#e6e8eb}.pxc-chip.help{color:#849dff;border-color:#33406b}.pxc-help{color:#9aa4b2;background:#0d1014;border:1px solid #1c2129;border-radius:8px;padding:.75rem .9rem;margin:.35rem 0 .2rem}.pxc-help b{color:#e6e8eb;font-weight:600}.pxc-help .h{display:block;color:#9aa4b2;margin:.7rem 0 .25rem;font-size:11px;letter-spacing:.05em;text-transform:uppercase}.pxc-link{color:#849dff;cursor:pointer;border-bottom:1px dotted #3a4664}.pxc-link:hover{color:#a9c0ff;border-bottom-style:solid}").

%   The <px-console> custom element: a terminal-style REPL with
%   scrollback, command history (up/down), multi-line input
%   (Shift+Enter), and JSON-driven result rendering. Written with
%   single-quoted JS strings and backtick templates to keep escaping
%   in this Prolog string minimal (only \\n and \").
console_js("class PxConsole extends HTMLElement{\
connectedCallback(){\
this.token=this.getAttribute('token')||'';this.history=[];this.hi=-1;\
try{this.data=JSON.parse(document.getElementById('pxc-data').textContent)}catch(x){this.data={run:[],preds:[]}}\
this.innerHTML=`<div class=pxc><div class=pxc-bar><span class='pxc-dot r'></span><span class='pxc-dot y'></span><span class='pxc-dot g'></span><span class=pxc-title>prologex console</span></div><div class=pxc-scroll></div><div class=pxc-row><span class=pxc-prompt>?-</span><textarea class=pxc-input rows=1 autocomplete=off autocapitalize=off spellcheck=false placeholder='a goal, then Enter'></textarea></div><div class=pxc-hints></div></div>`;\
this.scroll=this.querySelector('.pxc-scroll');this.input=this.querySelector('.pxc-input');this.hintbar=this.querySelector('.pxc-hints');\
(this.data.run||[]).slice(0,4).forEach(g=>{const c=document.createElement('button');c.className='pxc-chip';c.textContent=g;c.addEventListener('click',()=>this.set(g,true));this.hintbar.appendChild(c)});\
const hc=document.createElement('button');hc.className='pxc-chip help';hc.textContent='help';hc.addEventListener('click',()=>this.help());this.hintbar.appendChild(hc);\
this.input.addEventListener('keydown',e=>this.onKey(e));\
this.input.addEventListener('input',()=>this.autosize());\
this.scroll.addEventListener('click',e=>{const t=e.target.closest('[data-insert],[data-run]');if(!t)return;const ins=t.getAttribute('data-insert');if(ins!==null)this.set(ins,false);else this.set(t.getAttribute('data-run'),true)});\
this.echo('info','New here? Tap help, or an example below.');\
this.input.focus()}\
set(v,run){this.input.value=v;this.autosize();this.input.focus();const n=v.length;this.input.setSelectionRange(n,n);if(run)this.run()}\
autosize(){this.input.style.height='auto';this.input.style.height=this.input.scrollHeight+'px'}\
onKey(e){\
if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();this.run()}\
else if(e.key==='ArrowUp'&&this.firstLine()){e.preventDefault();this.hPrev()}\
else if(e.key==='ArrowDown'&&this.lastLine()){e.preventDefault();this.hNext()}\
else if(e.key==='l'&&e.ctrlKey){e.preventDefault();this.clear()}}\
firstLine(){return this.input.value.lastIndexOf('\\n',this.input.selectionStart-1)<0}\
lastLine(){return this.input.value.indexOf('\\n',this.input.selectionStart)<0}\
hPrev(){if(!this.history.length)return;if(this.hi<0)this.hi=this.history.length;this.hi=Math.max(0,this.hi-1);this.input.value=this.history[this.hi];this.autosize();this.toEnd()}\
hNext(){if(this.hi<0)return;this.hi++;if(this.hi>=this.history.length){this.hi=-1;this.input.value=''}else this.input.value=this.history[this.hi];this.autosize();this.toEnd()}\
toEnd(){const n=this.input.value.length;requestAnimationFrame(()=>this.input.setSelectionRange(n,n))}\
esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\"/g,'&quot;')}\
insertOf(p){const i=p.lastIndexOf('/');return (i>=0?p.slice(0,i):p)+'('}\
help(){const d=this.data;\
let h='<b>prologex console</b> \\u2014 evaluate a goal against the running app.\\nEnter runs \\u00b7 Shift+Enter newline \\u00b7 \\u2191\\u2193 history \\u00b7 clear resets.';\
h+='<span class=h>framework API (call unqualified)</span>  row(q(Table, Clauses), Row)   config(Key, Value)   field(Row, Col, V)   param(Env, K, V)';\
if(d.preds&&d.preds.length)h+='<span class=h>your app (tap to insert)</span>'+d.preds.map(p=>'  <span class=pxc-link data-insert=\"'+this.esc(this.insertOf(p))+'\">'+this.esc(p)+'</span>').join('\\n');\
h+='<span class=h>examples (tap to run)</span>'+(d.run||[]).map(g=>'  <span class=pxc-link data-run=\"'+this.esc(g)+'\">'+this.esc(g)+'</span>').join('\\n');\
const box=document.createElement('div');box.className='pxc-entry pxc-help';box.innerHTML=h;this.scroll.appendChild(box);this.down()}\
async run(){\
const g=this.input.value.trim();if(!g)return;\
if(g==='clear'){this.input.value='';this.autosize();this.clear();return}\
if(g==='help'){this.input.value='';this.autosize();this.help();return}\
this.history.push(g);this.hi=-1;this.echo('goal',g);this.input.value='';this.autosize();\
const p=this.echo('pending','\\u2026');\
try{const b=new URLSearchParams();b.set('token',this.token);b.set('goal',g);\
const r=await fetch('/__px/console',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:b.toString()});\
const d=await r.json();p.remove();this.render(d)}\
catch(err){p.remove();this.echo('error',String(err))}\
this.down()}\
render(d){\
if(!d.ok){this.echo('error',d.error||'error');return}\
if(d.output)this.echo('output',d.output.replace(/\\n$/,''));\
if(!d.solved){this.echo('result','false.');return}\
if(d.bindings&&d.bindings.length){this.echo('result',d.bindings.map(x=>x.name+' = '+x.value).join('\\n')+'\\ntrue.')}\
else this.echo('result','true.')}\
echo(cls,text){const e=document.createElement('div');e.className='pxc-entry pxc-'+cls;\
if(cls==='goal'){const s=document.createElement('span');s.className='pxc-eprompt';s.textContent='?- ';e.appendChild(s);e.appendChild(document.createTextNode(text))}\
else e.textContent=text;this.scroll.appendChild(e);this.down();return e}\
clear(){this.scroll.innerHTML=''}\
down(){this.scroll.scrollTop=this.scroll.scrollHeight}}\
customElements.define('px-console',PxConsole);").
