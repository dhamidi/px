/* Milestone 15: Hotwire Turbo support (px_turbo.pl, adr/0024),
   standalone -- no HTTP, no sockets. Fake env dicts (the adr/0017
   shape px_env:make_env/4 builds) go through px_turbo's middleware
   and responders; template output is captured with
   px_template:render_to_string/2.

   Covers:
     - dom_id/2: atom, compound, nested compound, number/string args
     - BARE turbo_frame(IdTerm, Content) calls (the north-star shape,
       no sigil): serialized id attribute; lazy src/1 form with
       loading="lazy" and an empty body; the legacy \turbo_frame
       escape still renders
     - turbo_frames/2 middleware: prunes the response body term to
       the matching turbo_frame subtree (bare or legacy \-escaped)
       through ~> template expansion when the turbo-frame header is
       present, adds vary: Turbo-Frame; DECLINES (fails, body
       untouched) when the header is absent or no frame matches
     - turbo_stream/3: content-type text/vnd.turbo-stream.html; body
       renders <turbo-stream action=... target=...><template>...
       per action, remove/1 with no template; unknown action throws
     - turbo_or_redirect/4: stream branch on the Accept sniff, 303 +
       location otherwise

   Run:  swipl test/milestone15_turbo.pl
*/

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../prolog/px_turbo'], PxTurboLib),
   atomic_list_concat([Dir, '/../prolog/px_template'], PxTemplateLib),
   use_module(PxTurboLib),
   use_module(PxTemplateLib).

:- discontiguous test/1.

:- initialization(main, main).

main :-
    Tests = [ dom_id_atom,
              dom_id_compound,
              dom_id_nested_compound,
              dom_id_number_and_string,
              frame_renders_serialized_id,
              frame_escaped_form_still_renders,
              frame_lazy_src,
              prune_extracts_matching_frame,
              prune_extracts_legacy_escaped_frame,
              prune_declines_without_header,
              prune_declines_unknown_frame,
              stream_response_markup,
              stream_remove_has_no_template,
              stream_rejects_unknown_action,
              negotiate_stream_on_accept,
              negotiate_redirect_without_accept
            ],
    run_tests(Tests, 0, Failed),
    length(Tests, N),
    (   Failed =:= 0
    ->  format("milestone15_turbo: all ~w tests passed~n", [N]),
        halt(0)
    ;   format(user_error, "milestone15_turbo: ~w of ~w test(s) FAILED~n",
               [Failed, N]),
        halt(1)
    ).

run_tests([], Failed, Failed).
run_tests([T|Ts], Failed0, Failed) :-
    (   catch(test(T), Error,
              ( print_message(error, Error), fail ))
    ->  format("  ok: ~w~n", [T]),
        Failed1 = Failed0
    ;   format(user_error, "  FAILED: ~w~n", [T]),
        Failed1 is Failed0 + 1
    ),
    run_tests(Ts, Failed1, Failed).

%   A fake env in the adr/0017 shape, with the request headers given
%   (lowercase Name-Value string pairs) and an empty 200 response.
fake_env(Headers, Env) :-
    Env = env{ method:   get,
               path:     "/x",
               raw_path: "/x",
               headers:  Headers,
               params:   _{},
               body:     "",
               worker:   0,
               config:   px_config,
               response: _{status: 200, headers: [], body: none}
             }.

		 /*******************************
		 *       TEST TEMPLATES         *
		 *******************************/

%   A couple of ~> templates the pruning walk must expand through:
%   page_t -> layout_t -> the frame, two levels of tmpl/2 indirection
%   plus element and list structure around it.

card_t(Name) ~> article([class(card)], h2(Name)).

frame_part_t(Id) ~> turbo_frame(post(Id), [p("post body")]).

layout_t(Title, Content) ~>
    div([h1(Title), Content, p("footer")]).

page_t(Id) ~> layout_t("A page", frame_part_t(Id)).

%   Legacy-escape variants: the \ escape and \turbo_frame must keep
%   working, and the pruning walker must match the escaped frame too.

legacy_frame_part_t(Id) ~> \turbo_frame(post(Id), [p("post body")]).

legacy_page_t(Id) ~> \layout_t("A page", \legacy_frame_part_t(Id)).

		 /*******************************
		 *          dom_id/2            *
		 *******************************/

test(dom_id_atom) :-
    dom_id(posts, Id),
    Id == "posts".

test(dom_id_compound) :-
    dom_id(post(7), Id),
    Id == "post_7".

test(dom_id_nested_compound) :-
    dom_id(comment(post(7), 3), Id),
    Id == "comment_post_7_3".

test(dom_id_number_and_string) :-
    dom_id(row("abc", 42), Id),
    Id == "row_abc_42".

		 /*******************************
		 *       turbo_frame            *
		 *******************************/

test(frame_renders_serialized_id) :-
    px_template:render_to_string(turbo_frame(post(7), [h1("Hi")]), S),
    S == "<turbo-frame id=\"post_7\"><h1>Hi</h1></turbo-frame>".

test(frame_escaped_form_still_renders) :-
    px_template:render_to_string(\turbo_frame(post(7), [h1("Hi")]), S),
    S == "<turbo-frame id=\"post_7\"><h1>Hi</h1></turbo-frame>".

test(frame_lazy_src) :-
    px_template:render_to_string(turbo_frame(recent_comments, src("/comments")), S),
    S == "<turbo-frame id=\"recent_comments\" src=\"/comments\" loading=\"lazy\"></turbo-frame>".

		 /*******************************
		 *   turbo_frames middleware    *
		 *******************************/

test(prune_extracts_matching_frame) :-
    fake_env(["turbo-frame"-"post_7"], Env0),
    Env1 = Env0.put(response/body, page_t(7)),
    turbo_frames(Env1, Env),
    % body is now just the bare frame subtree, found through two ~> hops
    Env.response.body == turbo_frame(post(7), [p("post body")]),
    memberchk("vary"-"Turbo-Frame", Env.response.headers),
    % and it still renders as the standalone frame
    px_template:render_to_string(Env.response.body, S),
    S == "<turbo-frame id=\"post_7\"><p>post body</p></turbo-frame>".

test(prune_extracts_legacy_escaped_frame) :-
    fake_env(["turbo-frame"-"post_7"], Env0),
    Env1 = Env0.put(response/body, \legacy_page_t(7)),
    turbo_frames(Env1, Env),
    % walker matched the \turbo_frame escape; pruned body is bare
    Env.response.body == turbo_frame(post(7), [p("post body")]),
    px_template:render_to_string(Env.response.body, S),
    S == "<turbo-frame id=\"post_7\"><p>post body</p></turbo-frame>".

test(prune_declines_without_header) :-
    fake_env([], Env0),
    Env1 = Env0.put(response/body, page_t(7)),
    \+ turbo_frames(Env1, _),        % declines: pipeline passes env on
    Env1.response.body == page_t(7).

test(prune_declines_unknown_frame) :-
    fake_env(["turbo-frame"-"post_99"], Env0),
    Env1 = Env0.put(response/body, page_t(7)),
    \+ turbo_frames(Env1, _).

		 /*******************************
		 *        turbo_stream/3        *
		 *******************************/

test(stream_response_markup) :-
    fake_env([], Env0),
    turbo_stream(Env0,
                 [ prepend(posts, card_t("New")),
                   replace(comment(post(7), 3), p("edited"))
                 ],
                 Env),
    Env.response.status == 200,
    memberchk("content-type"-"text/vnd.turbo-stream.html",
              Env.response.headers),
    px_template:render_to_string(Env.response.body, S),
    S == "<turbo-stream action=\"prepend\" target=\"posts\"><template><article class=\"card\"><h2>New</h2></article></template></turbo-stream><turbo-stream action=\"replace\" target=\"comment_post_7_3\"><template><p>edited</p></template></turbo-stream>".

test(stream_remove_has_no_template) :-
    fake_env([], Env0),
    turbo_stream(Env0, [remove(post(7))], Env),
    px_template:render_to_string(Env.response.body, S),
    S == "<turbo-stream action=\"remove\" target=\"post_7\"></turbo-stream>".

test(stream_rejects_unknown_action) :-
    fake_env([], Env0),
    catch(( turbo_stream(Env0, [explode(post(7), p(x))], _),
            fail
          ),
          error(domain_error(turbo_stream_action, _), _),
          true).

		 /*******************************
		 *     turbo_or_redirect/4      *
		 *******************************/

test(negotiate_stream_on_accept) :-
    fake_env(["accept"-"text/vnd.turbo-stream.html, text/html, application/xhtml+xml"],
             Env0),
    turbo_or_redirect(Env0, "/posts/7", [remove(post(7))], Env),
    Env.response.status == 200,
    memberchk("content-type"-"text/vnd.turbo-stream.html",
              Env.response.headers),
    Env.response.body == turbo_stream([remove(post(7))]).

test(negotiate_redirect_without_accept) :-
    fake_env(["accept"-"text/html,application/xhtml+xml"], Env0),
    turbo_or_redirect(Env0, "/posts/7", [remove(post(7))], Env),
    Env.response.status == 303,
    memberchk("location"-"/posts/7", Env.response.headers),
    Env.response.body == none.
