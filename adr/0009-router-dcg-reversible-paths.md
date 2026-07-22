# 0009. Router: DCG-parsed, reversible paths

Status: Accepted

## Context

Express-style routers match an incoming request path against a set of
route templates such as `/users/:id/posts/:post_id` and extract named
parameters from the parts that varied. In most frameworks, including
Express, that matching only runs one way: a template consumes a concrete
path string and produces parameters. It cannot run in reverse to produce
a path string from a route name and a set of parameter values. Frameworks
that want that capability, such as Rails, bolt on a separate named-route
or URL-helper system that duplicates the template logic in the opposite
direction.

Prolog does not have that asymmetry built in. Unification lets the same
relation run forwards or backwards for free, as long as it is written as
a genuine relation rather than as procedural string-matching code. A
route template and an incoming path are both, at bottom, lists of
segments; matching one against the other is unification, and unification
does not care which side is already bound.

## Decision

Route path templates are parsed into a list-of-segment-terms
representation using a DCG: each segment becomes either a literal atom
segment or a `:name` parameter segment. Matching an incoming request path
against a template is plain unification against that same
list-of-segments representation, not a regular expression or an ad hoc
string-splitting matcher.

Routes are stored as `route/4` facts: method, path template, handler,
and an options term (for future concerns such as route-level middleware
or constraints). The path template is stored already parsed into
segment-term form, not as a raw string, so both matching and generation
operate on the same representation.

The core relation, `match_path/3`, is written to work in both directions:

- `match_path(Template, Path, Params)` — given a concrete `Path` (as
  parsed from an incoming request), decompose it against `Template` and
  unify `Params` with the extracted parameter bindings. This is the
  familiar Express-style direction.
- `path_for(RouteName, Params, Path)` — given a route name and a set of
  parameter bindings, look up the matching `route/4` fact and run the
  identical `match_path/3` relation with `Path` left unbound, producing a
  concrete path string by unification.

Reversibility is not implemented as two functions that happen to agree;
it falls out of `match_path/3` being written as one relation and called
with different arguments bound.

This has a direct implementation constraint: `match_path/3` and the DCG
it is built on must stay true relations. No cuts that commit to a branch
based on which arguments happen to be bound, no side effects, no
auxiliary predicates that assume `Path` is instantiated (e.g. calling
`atom_length/2` on it, or using `string_concat/3` in a mode that only
works forwards). Writing DCG syntax that only ever gets called in one
direction — a disguised imperative parser — is an easy trap to fall into
and defeats the point of this decision. Every predicate in the router's
match path is reviewed against both calling modes, not just the forward
one, before it is considered done.

## Consequences

The framework gets reverse routing and URL generation — the feature Rails
and Express-with-named-routes bolt on as separate machinery — for free,
as a direct consequence of how the matcher is written. This is a
concrete, working example of leaning on Prolog's strengths rather than a
claim made in the abstract: the same handful of clauses power both
directions, and there is no second code path to keep in sync when a
route template changes.

The cost is discipline. Ordinary imperative habits (early cuts, mode
assumptions, string operations that only work one way) creep into DCG
code easily and silently break the backward mode without breaking any
forward-direction test. Route matching logic needs modes documented and
tested in both directions, and code review on `prolog/router.pl` treats a
cut or a one-directional built-in as a defect unless it is justified.

Storing route templates pre-parsed as segment terms in `route/4` means
route registration does the DCG parse once, at startup, rather than on
every request; per-request cost is unification against an already-parsed
list, not repeated parsing.

Because parameter segments are just atoms prefixed with `:` in the
template and arbitrary path components in practice, there is no built-in
type constraint or validation on parameter values from the router itself
— a numeric-looking `:id` still unifies with any path segment. Type
coercion and validation of extracted parameters is left to handler code
or middleware, not the router.
