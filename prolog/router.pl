:- module(router,
          [ add_route/4,          % +Name, +Method, +PathTemplate, :Handler
            match_route/4,        % +Method, +Path, -HandlerGoal, -Params
            path_for/3,           % +Name, +Params, -Path
            match_path/3,         % ?Segments, ?PathSegments, ?Params
            path_template//1,     % ?Segments (list of path-segment strings)
            clear_routes/0
          ]).

:- use_module(library(lists)).

/** <module> Route registration and reversible route matching. See
    adr/0009.

Routes are stored as route/4 facts:

    route(Name, Method, Segments, Handler)

Name     - atom, used for reverse lookup via path_for/3
Method   - lowercase atom, e.g. get, post
Segments - the path template already parsed (at registration time, via
           path_template//1) into a list of segment terms:
             - an atom  -- a literal path segment, e.g. adr
             - param(Name) -- a `:name` parameter segment, Name an atom
             - splat(Name) -- a `*name` segment, Name an atom. MUST be
               the last segment in a template; matches ONE OR MORE
               remaining path segments, joined with "/" into a single
               atom value (adr/0036: this is what lets development's
               unhashed asset route, "/assets/" + "*file", capture a
               nested logical name like "css/app.css" as one param).
               Forward direction only (match_route/4's use) -- unlike
               param(Name), there is no reverse/path_for/3 support;
               nothing in this codebase builds a splat path from
               Params, so match_path/3's splat clause below only
               handles PathSegments bound.
Handler  - the goal registered by the caller (module-qualified)

Path strings on the wire look like "/adr/1" (already split off any
query string by the caller -- see app.pl, which uses library(uri)'s
uri_query_components/2 for that split before calling match_route/4).

Params, wherever this module produces or consumes it, is a list of
Name=Value pairs, Name an atom and Value an atom. This module is
consistent about that shape whether it is filling Params in from a
concrete path (match_route/4) or consuming a Params list to produce a
path (path_for/3).

THE core relation is match_path/3, which relates a parsed route
template (Segments) to a list of path-segment atoms (PathSegments) and
a Params list. It is written with no cuts and no built-in calls that
assume a particular argument is bound, so it runs in both directions:

  - match_route/4 calls it with PathSegments bound (split from an
    incoming request's path) and Params unbound: ordinary Express-
    style "decompose a path" matching.
  - path_for/3 calls it with PathSegments unbound and Params bound:
    generating a concrete path from a route name and parameter values,
    by running the exact same relation the other way.

This double duty -- one relation, two calling modes, no separate
"path builder" code path to keep in sync -- is the entire point of
adr/0009, and is proven for real by the round-trip test in
test/milestone7_framework.pl (match_route to get Params from a path,
then path_for with those Params reproduces the original path).

path_template//1 is a separate, smaller DCG: it turns the raw template
*string* an application author writes (e.g. "/adr/:id") into the
Segments list stored in route/4, once, at add_route/4 time. Turning a
string into that structure is inherently a text-parsing job (there is
no meaningful "run it backwards from Segments to reconstruct the
exact original string" requirement the way there is for match_path/3
-- adr/0009's reversibility promise is specifically about match_path/3
and is not repeated here), but the DCG itself still contains no cuts:
its two segment-token clauses (literal vs `:name`) are already
disjoint by the leading-colon test built into the grammar, so no cut
is needed to keep it deterministic.
*/

:- dynamic route/4.

:- meta_predicate add_route(+, +, +, :).

%!  add_route(+Name, +Method, +PathTemplate, :Handler) is det.
%
%   Registers a route. PathTemplate is a raw string such as
%   "/adr/:id"; it is parsed into segment-term form once, here, at
%   registration time -- not re-parsed per request.
add_route(Name, Method, PathTemplate, Handler) :-
    must_be(atom, Name),
    must_be(atom, Method),
    parse_template(PathTemplate, Segments),
    strip_module(Handler, M, G),
    retractall(route(Name, _, _, _)),
    assertz(route(Name, Method, Segments, M:G)).

%!  clear_routes is det.
%
%   Removes all registered routes. Handy for tests.
clear_routes :-
    retractall(route(_, _, _, _)).

%!  parse_template(+PathTemplate, -Segments) is semidet.
%
%   Parses a raw template string/atom, e.g. "/adr/:id", into a
%   segment-term list, e.g. [adr, param(id)], via path_template//1.
parse_template(PathTemplate, Segments) :-
    split_path_string(PathTemplate, Tokens),
    phrase(path_template(Segments), Tokens).

%!  path_template(-Segments)// is det.
%
%   DCG relating a list of raw path-segment token strings (e.g.
%   ["adr", ":id"]) to a list of segment terms (e.g.
%   [adr, param(id)]). Each token is classified by segment_token//1.
path_template([]) -->
    [].
path_template([Segment|Segments]) -->
    segment_token(Segment),
    path_template(Segments).

%!  segment_token(-Segment)// is det.
%
%   Relates one raw token string to one segment term. The three
%   clauses are disjoint on the token's leading character (":", "*",
%   or neither), so no cut is required to keep this deterministic.
segment_token(param(Name)) -->
    [Token],
    { string_concat(":", Rest, Token) },
    { atom_string(Name, Rest) }.
segment_token(splat(Name)) -->
    [Token],
    { string_concat("*", Rest, Token) },
    { atom_string(Name, Rest) }.
segment_token(Literal) -->
    [Token],
    { \+ string_concat(":", _, Token),
      \+ string_concat("*", _, Token)
    },
    { atom_string(Literal, Token) }.

%!  match_route(+Method, +Path, -HandlerGoal, -Params) is nondet.
%
%   Path is the path portion only (no query string -- see app.pl,
%   which splits that off via library(uri) before calling this).
%   Tries registered routes for Method (a lowercase atom), unifying
%   Params with a list of Name=Value pairs for parameter segments that
%   matched, and binding HandlerGoal to the registered handler.
match_route(Method, Path, HandlerGoal, Params) :-
    split_path_string(Path, Tokens),
    maplist(atom_string, PathSegments, Tokens),
    route(_Name, Method, TemplateSegments, HandlerGoal),
    match_path(TemplateSegments, PathSegments, Params).

%!  path_for(+Name, +Params, -Path) is semidet.
%
%   The reversibility payoff of adr/0009: given a route Name and a
%   Params list (same Name=Value shape match_route/4 produces), runs
%   the identical match_path/3 relation used for matching, but with
%   PathSegments left unbound, to generate a concrete path string.
path_for(Name, Params, Path) :-
    route(Name, _Method, TemplateSegments, _HandlerGoal),
    match_path(TemplateSegments, PathSegments, Params),
    join_path(PathSegments, Path).

%!  match_path(?Segments, ?PathSegments, ?Params) is nondet.
%
%   The relation adr/0009 is built around. Segments is a route
%   template already parsed into segment-term form (literals and
%   param(Name) terms) -- always bound, on both calling paths below.
%   PathSegments is a list of atoms, one per path component. Params is
%   a list of Name=Value pairs, one per param(Name) segment.
%
%   Written as a genuine relation: no cuts that commit to a branch
%   based on which of PathSegments/Params happens to be bound, no
%   auxiliary predicate that assumes PathSegments is instantiated.
%   Called with PathSegments bound and Params unbound by
%   match_route/4 (decompose a concrete path into params), and with
%   PathSegments unbound and Params bound by path_for/3 (generate a
%   concrete path from params).
match_path([], [], []).
match_path([param(Name)|Segments], [Value|PathSegments], [Name=Value|Params]) :-
    match_path(Segments, PathSegments, Params).
match_path([splat(Name)], PathSegments, [Name=Value]) :-
    PathSegments \== [],
    atomic_list_concat(PathSegments, '/', Value).
match_path([Literal|Segments], [PathSegment|PathSegments], Params) :-
    Literal \= param(_),
    Literal \= splat(_),
    literal_matches(Literal, PathSegment),
    match_path(Segments, PathSegments, Params).

%   literal_matches/2 relates a template literal (an atom) to a path
%   segment (an atom), in either direction, without assuming either
%   side is bound -- so match_path/3's third clause works whichever
%   of PathSegments/Params drove the call.
literal_matches(Literal, PathSegment) :-
    ( var(PathSegment)
    -> PathSegment = Literal
    ;  PathSegment == Literal
    ).

%!  split_path_string(+PathOrTemplate, -Tokens) is det.
%
%   Splits a path/template string or atom such as "/adr/1" into
%   ["adr", "1"]. A path of "/" or "" splits to []. Shared by
%   parse_template/2 (templates) and match_route/4 (request paths) so
%   both go through the exact same tokenizer.
split_path_string(PathOrTemplate, Tokens) :-
    ( string(PathOrTemplate) -> Str = PathOrTemplate ; atom_string(PathOrTemplate, Str) ),
    split_string(Str, "/", "", Parts0),
    exclude(==(""), Parts0, Tokens).

%!  join_path(+PathSegments, -Path) is det.
%
%   Joins a list of path-segment atoms back into a leading-slash path
%   string, e.g. [adr, '1'] -> "/adr/1". [] -> "/".
join_path([], "/") :- !.
join_path(PathSegments, Path) :-
    maplist(atom_string, PathSegments, Strings),
    atomic_list_concat(Strings, '/', Joined),
    string_concat("/", Joined, Path).
