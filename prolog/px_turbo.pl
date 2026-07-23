:- module(px_turbo,
          [ dom_id/2,               % +IdTerm, -IdString
            turbo_frames/2,         % +Env0, -Env       (pipeline middleware)
            turbo_stream/3,         % +Env0, +Actions, -Env  (responder)
            turbo_or_redirect/4     % +Env0, +PathTerm, +Actions, -Env
          ]).

/** <module> Hotwire Turbo support, per adr/0024.

Four pieces on top of adr/0017's env and adr/0019's template surface
(Turbo Drive needs nothing here beyond the vendored apps/static/turbo.js
in the layout):

  1. dom_id/2 -- the frame-id serialization rule.  Terms are the DSL
     (adr/0016 rule 4); DOM ids are strings.  An atom serializes as
     itself, a compound as its functor then each argument recursively,
     joined with '_'; numbers and strings as their canonical text:

         posts                  -> "posts"
         post(7)                -> "post_7"
         comment(post(7), 3)    -> "comment_post_7_3"

     Deterministic and total over route-helper-style terms; never
     parsed back.  The SAME rule names frames and stream targets, so
     turbo_frame(post(7), ...) and replace(post(7), ...) are
     guaranteed to address the same element.

  2. Frames.  THE app-facing shape is the bare helper call

         turbo_frame(IdTerm, Content)

     i.e. the north-star's turbo_frame(post(Post.id), [...]) exactly
     as written -- no sigil.  turbo_frame is NOT on px_template's
     element whitelist; the bare compound resolves through the
     render-dispatch to the render_helper/2 clause below, which emits
     the literal tag via px_template:render_tag/4:

         <turbo-frame id="post_7">...Content...</turbo-frame>

     (\turbo_frame(IdTerm, Content), the explicit template escape,
     keeps working -- same helper, adr/0019.)

     A lazy frame is declared with src/1 in the content position:

         turbo_frame(recent_comments, src(comments_path))

         <turbo-frame id="recent_comments" src="/comments"
                      loading="lazy"></turbo-frame>

     where the path term resolves through px_template's
     eval_attr_value/2 hook (the reversible router registers it,
     adr/0018), same as any compound attribute value.

  3. turbo_frames/2 -- the pruning middleware, sitting after
     apply_layout in the pipeline.  When the request carries a
     `turbo-frame` header (Turbo navigating within a frame), the
     response body TERM is pruned to the matching
     turbo_frame(IdTerm, _) subtree (bare or legacy \-escaped) before
     a single byte renders, and `vary: Turbo-Frame` is added.  No
     header, or no matching frame: the middleware FAILS, i.e. declines
     (adr/0017), the full page goes out and Turbo copes client-side.
     Handlers never know.

  4. turbo_stream/3 + turbo_or_redirect/4 -- the stream responder and
     the content-negotiation helper (progressive enhancement in one
     predicate).  Actions is a list over the closed vocabulary

         append(Target, Template)   prepend(Target, Template)
         replace(Target, Template)  update(Target, Template)
         before(Target, Template)   after(Target, Template)
         remove(Target)

     with Target a dom_id/2 term and Template any adr/0019 template
     term.  The response body stays the term turbo_stream(Actions)
     (the ADR's own shape -- turbo_stream is not an element, so the
     bare term resolves to the helper) until the transport edge; a
     render_helper/2 clause below emits one literal <turbo-stream>
     tag per action via px_template:render_tag/4 --

         <turbo-stream action="append" target="post_7">
           <template>...rendered Template...</template>
         </turbo-stream>

     (remove/1: empty element, no template) -- and streams it, no
     string building anywhere.
*/

:- use_module(px_env, [respond/4, redirect/3, header/3, env_get/3, put_env/4]).
:- use_module(px_template, []).

:- use_module(library(apply)).
:- use_module(library(error)).
:- use_module(library(lists)).


		 /*******************************
		 *      DOM-ID SERIALIZATION    *
		 *******************************/

%!  dom_id(+Term, -Id) is det.
%
%   Serialize an id term to a DOM id string per adr/0024: atom as
%   itself; compound as functor, then arguments each by the same rule,
%   joined with '_' (nesting flattens); numbers and strings as their
%   canonical text.  Anything else (vars, dicts) is a type error.

dom_id(Term, Id) :-
    dom_id_parts(Term, Parts, []),
    atomic_list_concat(Parts, '_', Atom),
    atom_string(Atom, Id).

dom_id_parts(V, _, _) :-
    var(V),
    !,
    instantiation_error(V).
dom_id_parts(T, [T|R], R) :- atom(T),   !.
dom_id_parts(T, [T|R], R) :- number(T), !.
dom_id_parts(T, [T|R], R) :- string(T), !.
dom_id_parts(T, Parts, Rest) :-
    compound(T),
    !,
    compound_name_arguments(T, Name, Args),
    Parts = [Name|Parts1],
    foldl(dom_id_parts, Args, Parts1, Rest).
dom_id_parts(T, _, _) :-
    throw(error(type_error(dom_id_term, T),
                context(px_turbo:dom_id/2,
                        'id terms are atoms, numbers, strings and compounds thereof'))).


		 /*******************************
		 *     turbo_frame HELPER       *
		 *******************************/

%   turbo_frame(IdTerm, Content): emit the literal <turbo-frame> tag
%   (px_template:render_tag/4 -- turbo_frame is not a whitelisted
%   element) with the serialized id attribute.  src(PathTerm) content
%   makes a lazy frame -- empty, src resolved through the attr-value
%   hook.  Reached by bare-call dispatch or the explicit \ escape.

px_template:render_helper(turbo_frame(IdTerm, Content), S) :-
    dom_id(IdTerm, Id),
    (   Content = src(PathTerm)
    ->  px_template:render_tag(S, turbo_frame,
                               [id(Id), src(PathTerm), loading(lazy)], [])
    ;   px_template:render_tag(S, turbo_frame, [id(Id)], Content)
    ).


		 /*******************************
		 *     FRAME-PRUNING MIDDLEWARE *
		 *******************************/

%!  turbo_frames(+Env0, -Env) is semidet.
%
%   Pipeline middleware (after apply_layout).  If the request has a
%   `turbo-frame` header (env headers are lowercase Name-Value string
%   pairs), walk the response body term for the turbo_frame(IdTerm,_)
%   subtree (bare or legacy \-escaped) whose serialized IdTerm equals
%   the header value; on a hit, the
%   whole body becomes that subtree and `vary: Turbo-Frame` is added.
%   FAILS (declines) when the header is absent or no frame matches --
%   the body term goes out untouched and Turbo handles the full-page
%   fallback client-side.

turbo_frames(Env0, Env) :-
    header(Env0, "turbo-frame", FrameId),
    env_get(Env0, response, response(Status, RespHeaders, Body0)),
    Body0 \== none,
    frame_subtree(Body0, FrameId, Frame),
    put_env(Env0, response,
            response(Status, ["vary"-"Turbo-Frame"|RespHeaders], Frame),
            Env).

%!  frame_subtree(+Term, +WantedId, -Frame) is semidet.
%
%   First turbo_frame(IdTerm, _) subterm -- BARE or under the legacy
%   \ escape -- of the body term whose dom_id/2 serialization equals
%   WantedId (a string).  Structure traversal only, no rendering:
%   lists and compound arguments are descended, template/helper calls
%   (bare or \-escaped) are expanded through their ~> template clauses
%   (px_template:tmpl/2) and through each/2, runtime dict dot-terms
%   are looked up.  Non-template helpers cannot be walked and are
%   skipped.  The pruned Frame is always the bare turbo_frame/2 term.

frame_subtree(Term, _, _) :-
    var(Term),
    !,
    fail.
frame_subtree(\Goal, Wanted, Frame) :-
    !,
    frame_goal_subtree(Goal, Wanted, Frame).
frame_subtree([X|Xs], Wanted, Frame) :-
    !,
    (   frame_subtree(X, Wanted, Frame)
    ->  true
    ;   frame_subtree(Xs, Wanted, Frame)
    ).
frame_subtree(Term, Wanted, Frame) :-
    compound(Term),
    (   frame_goal_subtree(Term, Wanted, Frame)   % bare frame/each/template
    ->  true
    ;   once(( arg(_, Term, Arg),
               frame_subtree(Arg, Wanted, Frame) ))
    ).

frame_goal_subtree(Goal, Wanted, Frame) :-
    (   Goal = turbo_frame(IdTerm, _),
        dom_id(IdTerm, Id),
        Id == Wanted
    ->  Frame = Goal
    ;   Goal = each(List, Template),
        is_list(List),
        atom(Template)
    ->  once(( member(X, List),
               ItemGoal =.. [Template, X],
               frame_goal_subtree(ItemGoal, Wanted, Frame) ))
    ;   px_template:tmpl(Goal, Body)
    ->  frame_subtree(Body, Wanted, Frame)
    ;   fail
    ).


		 /*******************************
		 *      STREAM RESPONDER        *
		 *******************************/

%!  turbo_stream(+Env0, +Actions, -Env) is det.
%
%   Responder alongside respond/3 and redirect/3 -- a pure put_env/4,
%   no I/O.  Content type text/vnd.turbo-stream.html; body the term
%   turbo_stream(Actions) (adr/0024's own shape), rendered at the
%   transport edge by the render_helper below.  Actions are validated
%   eagerly against the closed vocabulary so a typo errors in the
%   handler, not at the wire.

turbo_stream(Env0, Actions, Env) :-
    must_be(list, Actions),
    maplist(valid_stream_action, Actions),
    respond(Env0, turbo_stream(Actions),
            [ header("content-type", "text/vnd.turbo-stream.html") ],
            Env).

valid_stream_action(Action) :-
    (   compound(Action),
        stream_action_shape(Action)
    ->  true
    ;   throw(error(domain_error(turbo_stream_action, Action),
                    context(px_turbo:turbo_stream/3,
                            'actions: append/prepend/replace/update/before/after(Target, Template) or remove(Target)')))
    ).

stream_action_shape(remove(_)).
stream_action_shape(Action) :-
    compound_name_arity(Action, Name, 2),
    template_action(Name).

template_action(append).
template_action(prepend).
template_action(replace).
template_action(update).
template_action(before).
template_action(after).

%   turbo_stream(Actions): one literal <turbo-stream> tag per action
%   (px_template:render_tag/4 -- turbo_stream is not a whitelisted
%   element), each streamed before the next action is looked at -- the
%   wrapper's open tag and <template> hit the wire, then the action's
%   template walks exactly as it would in a page (adr/0019).  remove/1
%   renders an empty element.

px_template:render_helper(turbo_stream(Actions), S) :-
    is_list(Actions),
    forall(member(Action, Actions),
           render_stream_action(S, Action)).

render_stream_action(S, remove(Target)) :-
    !,
    dom_id(Target, Id),
    px_template:render_tag(S, turbo_stream, [action(remove), target(Id)], []).
render_stream_action(S, Action) :-
    compound_name_arity(Action, Name, 2),
    template_action(Name),
    !,
    arg(1, Action, Target),
    arg(2, Action, Template),
    dom_id(Target, Id),
    px_template:render_tag(S, turbo_stream, [action(Name), target(Id)],
                           [template(Template)]).
render_stream_action(_, Action) :-
    throw(error(domain_error(turbo_stream_action, Action),
                context(px_turbo:turbo_stream/3, _))).


		 /*******************************
		 *     CONTENT NEGOTIATION      *
		 *******************************/

%!  turbo_or_redirect(+Env0, +PathTerm, +Actions, -Env) is det.
%
%   Progressive enhancement in one predicate (adr/0024 section 4).
%   Turbo advertises stream support with text/vnd.turbo-stream.html in
%   Accept: respond with the stream Actions.  Anything else (no JS,
%   curl, crawler): 303 See Other to PathTerm via px_env:redirect/3.
%   Same handler, both worlds.

turbo_or_redirect(Env0, PathTerm, Actions, Env) :-
    (   accepts_turbo_stream(Env0)
    ->  turbo_stream(Env0, Actions, Env)
    ;   redirect(Env0, PathTerm, Env)
    ).

%   Substring sniff, not a full negotiator -- matches what Turbo sends
%   and what Rails checks (adr/0024, consequences).

accepts_turbo_stream(Env) :-
    header(Env, "accept", Accept),
    sub_string(Accept, _, _, _, "text/vnd.turbo-stream.html").
