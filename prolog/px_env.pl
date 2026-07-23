:- module(px_env,
          [ make_env/4,           % +V1Request, +Stream, +WorkerId, -Env
            respond/3,            % +Env0, +Template, -Env
            respond/4,            % +Env0, +Template, +Opts, -Env
            redirect/3,           % +Env0, +PathTerm, -Env
            redirect/4,           % +Env0, +PathTerm, +Opts, -Env
            not_found/2,          % +Env0, -Env
            path_id/3,            % +Env, +Key, -IntegerId (semidet, never throws)
            cookie/3,             % +Env, +Name, -Value (semidet)
            env_merge_params/3,   % +Env0, +Dict, -Env
            set_pipeline/1,       % +Goals
            dispatch_env/2,       % +Env0, -Env
            handle_request/3,     % +V1Request, +Stream, +WorkerId
            write_response/2,     % +Stream, +Env
            eval_path_term/2      % multifile hook: +PathTerm, -PathString
          ]).

/** <module> The Rack-style env layer, per adr/0017 (shapes fixed by
    adr/0016).

Every request is one dict with tag `env`, threaded relationally:
handlers and middleware are relations Goal(Env0, Env). No I/O happens
anywhere in the pipeline -- the helpers here (respond/3,4, redirect/3,
not_found/2) are pure dict puts, and the only code that writes bytes
is the transport edge, write_response/2, after the pipeline finishes.

This is the v2 edge built NEXT TO the v1 layer (app.pl / response.pl /
middleware.pl); v1 keeps working untouched. The v1 transport
(http_stream.pl) hands a request dict
_{method: 'GET', url: "/x?a=1", headers: [Name-Value...], body: Body}
where Body is a string (v1 accumulates it); the env's `body` key keeps
that raw string for now. When the v1 transport is swapped onto this
edge, handle_request/3 is the integration point.

Standardized env keys (adr/0017): method (lowercase atom), path
(string, query stripped, percent-decoded), raw_path (string, as
received), headers (Name-Value string pairs, names lowercased),
params (dict: query-string params merged over form-body params; path
params are merged LATER by the router via env_merge_params/3 and win),
body (raw body string), worker (worker id), config (the atom
`px_config` -- an accessor marker; handlers call px_config:config/2,
the whole config is never snapshotted into the env), response
(_{status, headers, body} with body a template term, never bytes).
*/

:- use_module(library(uri)).
:- use_module(library(apply)).
:- use_module(library(lists)).

%   eval_path_term(+PathTerm, -PathString) is the reversible-router
%   hook (adr/0018): the router registers clauses that evaluate path
%   helper terms like post_path(7) to their path strings. redirect/3
%   consults it; a plain string/atom path passes through as-is when no
%   hook clause applies.
:- multifile eval_path_term/2.
:- dynamic eval_path_term/2.

%   The streaming template renderer (adr/0019) is developed in
%   parallel; load it when its source exists so write_response/2 can
%   call px_template:render/2. When absent, rendering a non-none body
%   raises an existence error -- tests may stub px_template:render/2.
:- (   exists_source(px_template)
   ->  use_module(px_template)
   ;   true
   ).


		 /*******************************
		 *          BUILDING            *
		 *******************************/

%!  make_env(+V1Request, +Stream, +WorkerId, -Env) is det.
%
%   Build the initial env dict from v1 http_stream.pl's request dict.
%   Stream is accepted for signature stability with the transport
%   edge but not stored: v1 hands the body as an accumulated string
%   (not a stream), and all writing goes through write_response/2.
make_env(V1Request, _Stream, WorkerId, Env) :-
    get_dict(method, V1Request, Method0),
    downcase_atom(Method0, Method),
    get_dict(url, V1Request, Url),
    get_dict(headers, V1Request, Headers0),
    get_dict(body, V1Request, Body),
    to_string(Url, RawPath),
    split_request_target(Url, Path, QueryPairs),
    maplist(lowercase_header, Headers0, Headers),
    form_pairs(Headers, Body, FormPairs),
    params_dict(FormPairs, QueryPairs, Params),
    Env = env{ method:   Method,
               path:     Path,
               raw_path: RawPath,
               headers:  Headers,
               params:   Params,
               body:     Body,
               worker:   WorkerId,
               config:   px_config,
               response: _{status: 200, headers: [], body: none}
             }.

%   Split the request target "/posts/7?utm=news" into the decoded
%   path string "/posts/7" and the decoded query pairs [utm=news].
split_request_target(Url, Path, QueryPairs) :-
    uri_components(Url, uri_components(_Scheme, _Auth, Path0, Search, _Frag)),
    (   var(Path0) -> Path1 = '/' ; Path1 = Path0 ),
    uri_encoded(path, Decoded, Path1),
    to_string(Decoded, Path),
    (   nonvar(Search)
    ->  catch(uri_query_components(Search, QueryPairs), _, QueryPairs = [])
    ;   QueryPairs = []
    ).

lowercase_header(Name0-Value0, Name-Value) :-
    to_string(Name0, NameS),
    string_lower(NameS, Name),
    to_string(Value0, Value).

%   Form-body params: only when the request is form-encoded and the
%   body is a non-empty string (adr/0023's machinery will take this
%   over; the urlencoded case lives at the edge per adr/0017).
form_pairs(Headers, Body, Pairs) :-
    (   memberchk("content-type"-ContentType, Headers),
        sub_string(ContentType, 0, _, _, "application/x-www-form-urlencoded"),
        string(Body),
        Body \== ""
    ->  catch(uri_query_components(Body, Pairs), _, Pairs = [])
    ;   Pairs = []
    ).

%   Merge params into one dict, query winning over form on collision
%   (path params win over both -- merged later via env_merge_params/3
%   by the router). Keys are atoms, values strings (adr/0017).
params_dict(FormPairs, QueryPairs, Params) :-
    foldl(put_param, FormPairs, _{}, Params0),
    foldl(put_param, QueryPairs, Params0, Params).

put_param(Name0=Value0, Dict0, Dict) :-
    to_atom(Name0, Name),
    to_string(Value0, Value),
    put_dict(Name, Dict0, Value, Dict).

%!  path_id(+Env, +Key, -Id) is semidet.
%
%   The blessed integer-id reader for path params: Env.params.Key as
%   an integer, FAILING (never throwing) when the segment is absent
%   or not a number -- so a model/3 clause using it turns
%   /things/notanumber into the 404 its failure contract promises
%   (adr/0027), with no catch/3 boilerplate. number_string/2 throws
%   on garbage, which is exactly the trap this exists to remove.

path_id(Env, Key, Id) :-
    get_dict(params, Env, Params),
    get_dict(Key, Params, V),
    (   integer(V)
    ->  Id = V
    ;   catch(number_string(Id, V), _, fail),
        integer(Id)
    ).

%!  env_merge_params(+Env0, +Dict, -Env) is det.
%
%   Merge Dict into Env0.params, Dict's entries winning on collision.
%   The router calls this with the path params of a matched route,
%   giving path params highest precedence (adr/0017).
env_merge_params(Env0, Dict, Env) :-
    get_dict(params, Env0, Params0),
    put_dict(Dict, Params0, Params),
    Env = Env0.put(params, Params).


		 /*******************************
		 *          HELPERS            *
		 *******************************/

%!  respond(+Env0, +Template, -Env) is det.
%!  respond(+Env0, +Template, +Opts, -Env) is det.
%
%   Set the response body to Template (a template term per adr/0019
%   -- never bytes). Opts:
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
%!  redirect(+Env0, +PathTerm, +Opts, -Env) is det.
%
%   303 See Other to PathTerm. PathTerm is evaluated through the
%   eval_path_term/2 multifile hook (the reversible router registers
%   it, adr/0018); a plain string or atom passes through as-is. 303 so
%   that redirects after non-GET forms behave under Turbo (adr/0024).
%   Opts: header(N, V), may repeat -- sign-in/out redirects carry
%   their set-cookie here (adr/0035).
redirect(Env0, PathTerm, Env) :-
    redirect(Env0, PathTerm, [], Env).

redirect(Env0, PathTerm, Opts, Env) :-
    resolve_path_term(PathTerm, Path),
    findall(N-V, member(header(N, V), Opts), Extra),
    Env = Env0.put(response,
                   _{status: 303,
                     headers: ["location"-Path|Extra],
                     body: none}).

resolve_path_term(PathTerm, Path) :-
    (   eval_path_term(PathTerm, Path0)
    ->  Path = Path0
    ;   ( atom(PathTerm) ; string(PathTerm) )
    ->  Path = PathTerm
    ;   throw(error(type_error(path_term, PathTerm),
                    context(px_env:redirect/3, 'no eval_path_term/2 clause applies and the term is not a literal path')))
    ).

%!  not_found(+Env0, -Env) is det.
%
%   A 404 with a minimal body term.
not_found(Env0, Env) :-
    respond(Env0, "404 Not Found", [status(404)], Env).

%!  cookie(+Env, +Name, -Value) is semidet.
%
%   Value of the named cookie from the request's cookie header
%   (adr/0035): Name an atom, Value a string. Fails when there is no
%   cookie header or no such cookie -- never throws. Parsing per RFC
%   6265's liberal recipe: split on ";", trim, split each on the
%   first "=".
cookie(Env, Name, Value) :-
    get_dict(headers, Env, Headers),
    memberchk("cookie"-Raw, Headers),
    split_string(Raw, ";", " \t", Pairs),
    member(Pair, Pairs),
    cookie_pair(Pair, Name, Value),
    !.

%   Split one "name=value" on its FIRST "=" (values may contain more).
cookie_pair(Pair, Name, Value) :-
    once(sub_string(Pair, Before, 1, After, "=")),
    sub_string(Pair, 0, Before, _, NameS),
    atom_string(NameA, NameS),
    NameA == Name,
    sub_string(Pair, _, After, 0, Value).


		 /*******************************
		 *          PIPELINE           *
		 *******************************/

:- dynamic pipeline_goals/1.

%!  set_pipeline(+Goals) is det.
%
%   Store the app's middleware pipeline, a list of env-relations
%   Step(Env0, Env), in order. The `:- pipeline([...])` directive
%   sugar (which captures the defining module, adr/0016 rule 7) is
%   the facade's job; until then callers pass module-qualified goals
%   or goals resolvable from px_env.
set_pipeline(Goals) :-
    must_be(list, Goals),
    retractall(pipeline_goals(_)),
    assertz(pipeline_goals(Goals)).

%!  dispatch_env(+Env0, -Env) is det.
%
%   Run the stored pipeline over Env0 as a fold of env-relations
%   (adr/0010 over adr/0017 dicts):
%
%   - a step that FAILS has declined: the env flows on unchanged;
%   - every element runs -- the router is not special-cased by name.
%     If after the full pipeline the response body is still `none`
%     with status 200, nothing handled the request and the env is
%     converted to a 404 via not_found/2;
%   - any exception is caught here and becomes a 500 response env
%     with a simple error body term.
dispatch_env(Env0, Env) :-
    (   pipeline_goals(Goals) -> true ; Goals = [] ),
    catch(run_pipeline(Goals, Env0, Env1),
          Error,
          error_env(Env0, Error, Env1)),
    finalize_env(Env1, Env).

run_pipeline([], Env, Env).
run_pipeline([Step|Steps], Env0, Env) :-
    (   call(Step, Env0, Env1)
    ->  true
    ;   Env1 = Env0                 % declined: env passes untouched
    ),
    run_pipeline(Steps, Env1, Env).

error_env(Env0, Error, Env) :-
    message_to_string(Error, Message),
    format(user_error, "px_env: pipeline error: ~w~n", [Message]),
    format(string(Body), "500 Internal Server Error: ~w", [Message]),
    Env = Env0.put(response, _{status: 500, headers: [], body: Body}).

finalize_env(Env0, Env) :-
    get_dict(response, Env0, Response),
    (   get_dict(body, Response, none),
        get_dict(status, Response, 200)
    ->  not_found(Env0, Env)
    ;   Env = Env0
    ).


		 /*******************************
		 *      THE TRANSPORT EDGE     *
		 *******************************/

%!  handle_request(+V1Request, +Stream, +WorkerId) is det.
%
%   The v2 integration point for the transport: build the env, run
%   the pipeline, write the final env's response to Stream. This is
%   the single place bytes are produced. Stream flushing is done
%   here; closing it remains the transport wiring's job (v1's
%   dispatch closed the buffered response stream in a cleanup goal --
%   the wave-3 adapter does the same around this call).
handle_request(V1Request, Stream, WorkerId) :-
    make_env(V1Request, Stream, WorkerId, Env0),
    dispatch_env(Env0, Env),
    write_response(Stream, Env).

%!  write_response(+Stream, +Env) is det.
%
%   Write status line + headers, then render the body term. Always
%   adds `connection: close` (v1 transport is close-delimited: one
%   request per connection, http_stream.pl closes right after) and
%   deliberately NO content-length -- the close delimits the body.
%   Content-Type defaults to text/html; charset=utf-8 unless a
%   header set it. Bodies render via px_template:render/2 (adr/0019),
%   streaming the term straight to Stream; `none` writes nothing.
%
%   `raw_bytes(Binary)` is a second escape door, alongside px_template's
%   raw/1, for a body that is genuinely binary (gzip-compressed asset
%   bytes, images, ...) rather than text (adr/0025's asset pipeline is
%   the first caller). Binary MUST be a string produced by
%   read_file_to_string/3 with encoding(iso_latin_1) -- an isomorphic
%   byte<->code mapping -- because the connection stream defaults to
%   UTF-8 (c/http_stream_swi.c): writing such a string on a UTF-8
%   stream would re-encode every code point above 127 into a multi-byte
%   UTF-8 sequence and corrupt the bytes. set_stream/2 switches this
%   one-shot response stream (adr/0012: one request per connection,
%   closed right after) to octet encoding first, so the codes go out
%   one byte each, unchanged.
write_response(Stream, Env) :-
    get_dict(response, Env, Response),
    get_dict(status, Response, Status),
    get_dict(headers, Response, Headers),
    get_dict(body, Response, Body),
    reason_phrase(Status, Reason),
    format(Stream, "HTTP/1.1 ~w ~w\r\n", [Status, Reason]),
    forall(member(Name-Value, Headers),
           format(Stream, "~w: ~w\r\n", [Name, Value])),
    (   Body == none
    ->  true
    ;   has_content_type(Headers)
    ->  true
    ;   format(Stream, "content-type: text/html; charset=utf-8\r\n", [])
    ),
    format(Stream, "connection: close\r\n\r\n", []),
    (   Body == none
    ->  true
    ;   Body = raw_bytes(Binary)
    ->  set_stream(Stream, encoding(octet)),
        write(Stream, Binary)
    ;   px_template:render(Stream, Body)
    ),
    flush_output(Stream).

has_content_type(Headers) :-
    member(Name-_, Headers),
    to_string(Name, NameS),
    string_lower(NameS, "content-type"),
    !.

reason_phrase(Status, Reason) :-
    (   known_reason(Status, Reason0)
    ->  Reason = Reason0
    ;   Reason = "Status"
    ).

known_reason(200, "OK").
known_reason(303, "See Other").
known_reason(404, "Not Found").
known_reason(422, "Unprocessable Content").
known_reason(500, "Internal Server Error").


		 /*******************************
		 *          SMALL BITS         *
		 *******************************/

to_string(Text, String) :-
    text_to_string(Text, String).

to_atom(Text, Atom) :-
    (   atom(Text) -> Atom = Text ; atom_string(Atom, Text) ).
