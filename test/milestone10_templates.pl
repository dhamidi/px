/* Milestone 10 (adr/0019): streaming templates, prolog/px_template.pl.
   A plain swipl script -- no server, no networking -- exercising the
   whole template surface:

     - `~>` clauses with clause selection (status_badge/1 pattern from
       the ADR: two clauses, one per status atom);
     - dict field access (Post.title from a literal dict), proving the
       term-expansion trick resolves SWI's dot notation in bodies;
     - composition via BARE template/helper calls (layout("T",...),
       each over a list, link_to, markdown -- no sigil), plus the
       explicit \Goal escape still working;
     - attributes: single term and list forms, data_* underscore->dash
       mapping, render_tag/4 literal-tag name dashing, value escaping
       (including double quotes), and the eval_attr_value/2 hook (a
       fake post_path/1 resolver standing in for the router);
     - text escaping (a "<script>" + "&" payload must come out as
       &lt;script&gt; and &amp;), raw/1 passthrough, void elements;
     - markdown bridging the v1 markdown engine;
     - errors: unknown bare compound at render (neither element,
       template nor helper), unknown \Goal template, children handed
       to a void element, element-named template head and helper
       rejected at expansion;
     - THE STREAMING PROOF: a template whose first child is a helper
       that records character_count/2 of the output stream at the
       moment it runs.  If the recorded position equals the length of
       the parent's open tag, the open tag was fully on the stream
       before the first child was evaluated -- adr/0019 section 4,
       observed rather than assumed.
*/

:- use_module('../prolog/px_template.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Hook registrations (multifile, from outside px_template -- this is
% exactly how the router / other subsystems will plug in).
% ---------------------------------------------------------------------

% Stand-in for the adr/0018 router's path-term evaluation.
:- multifile px_template:eval_attr_value/2.
px_template:eval_attr_value(post_path(Id), S) :-
    format(string(S), "/posts/~w", [Id]).

% Streaming-proof probe: record how many characters are already on the
% output stream at the moment this helper (a child node) executes.
:- multifile px_template:render_helper/2.
px_template:render_helper(probe_position, S) :-
    flush_output(S),
    character_count(S, C),
    nb_setval(probe_at, C).

% ---------------------------------------------------------------------
% Templates under test.
% ---------------------------------------------------------------------

% Clause selection: unification picks the clause, no if/case (ADR ex.).
status_badge(draft)     ~> span(class('badge badge-muted'), "Draft").
status_badge(published) ~> span(class('badge badge-live'), "Published").

% Dict field access + bare nesting + attrs + hook-resolved href.
post_card(Post) ~>
    article(class(card),
      [ h2(link_to(Post.title, post_path(Post.id))),
        status_badge(Post.status),
        p(Post.summary)
      ]).

% layout/2 is just another template (adr/0019 section 5).
layout(Title, Content) ~>
    html(
      [ head(title(Title)),
        body(
          [ header(nav("top")),
            main(Content),
            footer(p("served by prologex"))
          ])
      ]).

% Composition: bare layout + each over a list of dicts.
post_index(Posts) ~>
    layout("Posts",
      [ h1("All posts"),
        div(id(posts), each(Posts, post_card))
      ]).

% Attribute forms: data_* dashing, boolean attr, quote escaping.
attr_demo ~>
    div([ data_turbo_frame(comments),
          aria_label('say "hi" & <go>'),
          hidden
        ],
        "x").

% render_tag/4: a literal non-whitelisted tag, name dashed
% (turbo_frame -> <turbo-frame>) -- what px_turbo's helpers use.

% Escaping and the raw/1 door.
escape_demo ~> p("<script>alert('pwn')</script> & fish").
raw_demo    ~> div([raw("<b>verbatim</b>"), " & escaped"]).

% Void elements: attributes only, no closing tag.
void_demo ~> div([img([src('/x.png'), alt("a pic")]), br([]), hr([])]).

% Markdown bridge (v1 engine via raw).
md_demo ~> div(class(md), markdown("# Title\n\nSome *emphasis* & a <tag>.")).

% Render-time typo: dvi is not an element and not escaped.
typo_demo ~> dvi(class(oops), "y").

% Streaming proof: the probe is the FIRST child; its recorded stream
% position must equal the open tag's length.
stream_demo ~> div(class(probe), [\probe_position, "tail"]).

% ---------------------------------------------------------------------
% Harness.
% ---------------------------------------------------------------------

:- dynamic failed_count/1.
failed_count(0).

bump :-
    retract(failed_count(N)),
    N1 is N + 1,
    assertz(failed_count(N1)).

check(Name, Goal) :-
    (   catch(Goal, E,
              ( format("      unexpected error: ~q~n", [E]), fail ))
    ->  format("PASS  ~w~n", [Name])
    ;   format("FAIL  ~w~n", [Name]),
        bump
    ).

contains(Haystack, Needle) :-
    sub_string(Haystack, _, _, _, Needle).

main :-
    tests,
    failed_count(N),
    (   N =:= 0
    ->  format("~nAll milestone 10 template checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

tests :-
    % -- clause selection, BARE call (the user-facing surface) --------
    check(clause_selection_draft_bare,
          ( render_to_string(status_badge(draft), S1),
            S1 == "<span class=\"badge badge-muted\">Draft</span>" )),
    check(clause_selection_published_bare,
          ( render_to_string(status_badge(published), S2),
            S2 == "<span class=\"badge badge-live\">Published</span>" )),

    % -- \Goal remains as the explicit escape -------------------------
    check(explicit_escape_still_works,
          ( render_to_string(\status_badge(draft), SEsc),
            SEsc == "<span class=\"badge badge-muted\">Draft</span>" )),

    % -- dict field access + nesting + attr-value hook ----------------
    Post = _{id: 7, title: "Hello, Dicts", status: draft,
             summary: "Terms > strings"},
    check(dict_access_and_nesting,
          ( render_to_string(post_card(Post), S3),
            S3 == "<article class=\"card\"><h2><a href=\"/posts/7\">Hello, Dicts</a></h2><span class=\"badge badge-muted\">Draft</span><p>Terms &gt; strings</p></article>" )),

    % -- each + layout/2 composition ----------------------------------
    Posts = [ _{id: 1, title: "One", status: draft,     summary: "first"},
              _{id: 2, title: "Two", status: published, summary: "second"} ],
    check(each_and_layout,
          ( render_to_string(post_index(Posts), S4),
            contains(S4, "<html><head><title>Posts</title></head><body>"),
            contains(S4, "<main><h1>All posts</h1><div id=\"posts\">"),
            contains(S4, "<a href=\"/posts/1\">One</a>"),
            contains(S4, "badge-live\">Published</span><p>second</p>"),
            contains(S4, "<footer><p>served by prologex</p></footer></body></html>"),
            % order: post 1's card fully before post 2's
            sub_string(S4, B1, _, _, "One"), sub_string(S4, B2, _, _, "Two"),
            B1 < B2 )),

    % NB: the arity-0 demo templates below are ATOMS -- a bare atom is
    % a text node, so they are called via the explicit \ escape.

    % -- attributes: data_* dashing, quote escaping, boolean ----------
    check(attr_dash_and_escape,
          ( render_to_string(\attr_demo, S5),
            S5 == "<div data-turbo-frame=\"comments\" aria-label=\"say &quot;hi&quot; &amp; &lt;go&gt;\" hidden>x</div>" )),

    % -- render_tag/4: literal tag, name dashing ----------------------
    check(render_tag_literal_dashed,
          ( with_output_to(string(S6),
                           ( current_output(Out6),
                             px_template:render_tag(Out6, turbo_frame,
                                                    [id(post_7)],
                                                    p("inside")) )),
            S6 == "<turbo-frame id=\"post_7\"><p>inside</p></turbo-frame>" )),

    % -- escaping ------------------------------------------------------
    check(script_and_amp_escaped,
          ( render_to_string(\escape_demo, S7),
            contains(S7, "&lt;script&gt;"),
            contains(S7, "&amp; fish"),
            \+ contains(S7, "<script>") )),

    % -- raw/1 passthrough --------------------------------------------
    check(raw_passthrough,
          ( render_to_string(\raw_demo, S8),
            S8 == "<div><b>verbatim</b> &amp; escaped</div>" )),

    % -- void elements -------------------------------------------------
    check(void_elements,
          ( render_to_string(\void_demo, S9),
            S9 == "<div><img src=\"/x.png\" alt=\"a pic\"><br><hr></div>" )),

    % -- markdown bridge ----------------------------------------------
    check(markdown_bridge,
          ( render_to_string(\md_demo, S10),
            contains(S10, "<div class=\"md\">"),
            contains(S10, "<h1>Title</h1>"),
            contains(S10, "<em>emphasis</em>"),
            contains(S10, "&amp;"),
            contains(S10, "&lt;tag&gt;") )),

    % -- errors --------------------------------------------------------
    check(unknown_element_throws,
          catch(( render_to_string(\typo_demo, _), fail ),
                error(domain_error(px_template_element, dvi(_, _)), _),
                true)),
    check(unknown_template_throws,
          catch(( render_to_string(\no_such_template(1), _), fail ),
                error(existence_error(px_template_template,
                                      no_such_template(1)), _),
                true)),
    check(void_children_throw,
          catch(( render_to_string(br([], "kids"), _), fail ),
                error(domain_error(void_element, _), _),
                true)),
    check(element_named_template_rejected_at_expansion,
          catch(( px_template:expand_template(section(x), div("y"), _), fail ),
                error(permission_error(define, template, section), _),
                true)),
    check(element_named_helper_rejected_at_expansion,
          catch(( px_template:reject_element_named_helper(div(x)),
                  fail ),
                error(permission_error(define, render_helper, div), _),
                true)),

    % -- THE STREAMING PROOF ------------------------------------------
    nb_setval(probe_at, -1),
    check(open_tag_streams_before_children,
          ( render_to_string(\stream_demo, S11),
            S11 == "<div class=\"probe\">tail</div>",
            nb_getval(probe_at, At),
            string_length("<div class=\"probe\">", OpenLen),
            At =:= OpenLen,          % open tag fully written BEFORE 1st child ran
            sub_string(S11, 0, OpenLen, _, "<div class=\"probe\">") )),

    % show some real output for the record
    render_to_string(post_index(Posts), Full),
    format("~n--- rendered post_index ---~n~w~n---------------------------~n", [Full]).
