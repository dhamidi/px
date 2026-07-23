:- module(px_template,
          [ render/2,               % +Stream, +Term
            render_to_string/2,     % +Term, -String   (TESTS ONLY)
            render_tag/4,           % +Stream, +Name, +Attrs, +Children
            tmpl/2,                 % ?Head, ?Body     (multifile target of ~>)
            render_helper/2,        % ?Goal, +Stream   (multifile extension hook)
            eval_attr_value/2,      % ?Term, -String   (multifile extension hook)
            op(1100, xfx, ~>)
          ]).

:- use_module(markdown/parser).     % md_parser:markdown_to_ast/2
:- use_module(markdown/html).       % md_html:ast_to_html_string/2

/** <module> Streaming templates (adr/0019): `~>` renders terms straight
    to the wire.

`Head ~> Body` clauses -- in any module that imports this one (the op is
in the export list) -- are term-expanded into clauses of the multifile
px_template:tmpl/2:

    px_template:tmpl(Head, T) :- T = Body.

The body is deliberately `T = Body` rather than a fact: SWI-Prolog's
normal goal expansion of that unification, run in the *defining* module
at load time, rewrites dict functional notation (`Post.title`) into
render-time `.`/3 (get_dict) lookups.  So dict field access works
anywhere in a template body with zero support code here, and a missing
key errors at the offending template clause.

render/2 walks a body term and writes to Stream as it goes -- open tags
are on the wire before their children are evaluated; there is no token
list and no output buffer anywhere (adr/0019 section 4).  The term
language:

    - string / atom / number      -> HTML-escaped text node
    - raw(S)                      -> unescaped, the only unescaped door
    - El(Children)                -> <el>...</el>, El in the HTML5
    - El(Attrs, Children)            element whitelist; underscores in
                                     El become dashes (data_x -> data-x
                                     in attributes too); void elements
                                     take attributes only
    - any other compound          -> a bare call: first a template
                                     (tmpl/2), then a helper
                                     (render_helper/2 hook), else an
                                     error (catches typos)
    - \Goal                       -> explicit escape: same
                                     template-then-helper resolution,
                                     skipping the element check

Bare calls are the user-facing surface -- layout("T", [...]),
each(Posts, post_card), turbo_frame(post(7), [...]) -- no sigil.
Element names win the resolution, which is why templates and helpers
may not be named after whitelisted elements (rejected at expansion,
below); \Goal remains as an explicit, always-unambiguous escape.

Extension hooks (both multifile and dynamic, so this module loads and
runs standalone):

    - render_helper(Goal, Stream): called for a bare call (or \Goal
      escape) when no tmpl/2 clause matches.  Subsystems (forms,
      turbo, ...) plug their helpers in here.  The built-ins each/2,
      text/1, link_to/2 and markdown/1 are ordinary clauses of this
      hook.

    - eval_attr_value(Term, String): called for a compound attribute
      value (href(post_path(7)) and friends) AND for an atom attribute
      value (href(comments_path), a zero-arity path helper written as
      a bare atom -- there is no other term shape for that call).  The
      router registers path-term evaluation here (adr/0018).  If no
      clause resolves the term it is written back literally, escaped
      (standard operator notation for a compound, as-is for an atom).
      A STRING attribute value is never offered to this hook -- it is
      always a literal, by contract (see write_attr_value/2 below).
*/

%   dynamic as well as multifile: px_page:ensure_layout/0 (adr/0027
%   decision 5) asserts the default-layout clause at boot when the
%   loaded app defined no layout/2 template of its own.
:- multifile tmpl/2.
:- dynamic   tmpl/2.
:- multifile render_helper/2.
:- dynamic   render_helper/2.
:- multifile eval_attr_value/2.
:- dynamic   eval_attr_value/2.

		 /*******************************
		 *      ~>  TERM EXPANSION      *
		 *******************************/

:- multifile user:term_expansion/2.

user:term_expansion((Head ~> Body), Clause) :-
    px_template:expand_template(Head, Body, Clause).
user:term_expansion(Clause, _) :-
    % Only ever calls into px_template for a clause that IS a
    % px_template:render_helper/2 registration (matched inline, so
    % this hook is inert while px_template itself compiles).
    nonvar(Clause),
    (   Clause = (Head :- _)
    ->  true
    ;   Head = Clause
    ),
    nonvar(Head),
    Head = px_template:render_helper(Goal, _),
    callable(Goal),
    px_template:reject_element_named_helper(Goal).

%!  expand_template(+Head, +Body, -Clause) is det.
%
%   `Head ~> Body`  ==>  `px_template:tmpl(Head, T) :- T = Body.`
%
%   The clause is returned to the compiler *unexpanded*; the system's
%   subsequent body expansion of `T = Body` (in the defining module)
%   rewrites dict dot-expressions.  A template may not be named after a
%   whitelisted HTML5 element -- element names win bare-call
%   resolution, so such a template could never be called (adr/0019
%   section 3).  This load-time rule is what makes bare calls safe
%   without a sigil.

expand_template(Head, Body, (px_template:tmpl(Head, T) :- T = Body)) :-
    (   callable(Head)
    ->  true
    ;   throw(error(type_error(callable, Head),
                    context(px_template:(~>)/2, 'template head')))
    ),
    functor(Head, Name, _),
    (   html_element(Name)
    ->  throw(error(permission_error(define, template, Name),
                    context(px_template:(~>)/2,
                            'template may not be named after a whitelisted HTML5 element: bare calls resolve element-first, so it could never be called')))
    ;   true
    ).

%!  reject_element_named_helper(+Goal) is failure.
%
%   The same element-shadowing rule for registered helpers: a
%   px_template:render_helper/2 clause whose Goal functor is a
%   whitelisted element is rejected when the registering file loads.
%   Throws on collision; FAILS otherwise, so term expansion leaves the
%   clause untouched.

reject_element_named_helper(Goal) :-
    functor(Goal, Name, _),
    html_element(Name),
    throw(error(permission_error(define, render_helper, Name),
                context(px_template:render_helper/2,
                        'helper may not be named after a whitelisted HTML5 element: bare calls resolve element-first, so it could never be called'))).

		 /*******************************
		 *           RENDERING          *
		 *******************************/

%!  render(+Stream, +Term) is det.
%
%   Render a template body term to Stream, writing as it goes.  No
%   output is buffered: an element's open tag is written before its
%   first child is even looked at.

render(_, Var) :-
    var(Var),
    !,
    instantiation_error(Var).
render(S, \Goal) :-
    !,
    render_call(S, Goal).
render(S, raw(Text)) :-
    !,
    write(S, Text).
render(S, Text) :-
    text_node(Text),
    !,
    write_escaped(S, Text).
render(_, []) :-
    !.
render(S, [X|Xs]) :-
    !,
    render(S, X),
    render(S, Xs).
render(S, Term) :-
    compound(Term),
    !,
    compound_name_arity(Term, Name, Arity),
    % NB: the dot-term case is matched structurally (never written as a
    % literal '.'(_,_) term here, which SWI's own dict expansion would
    % rewrite).  It is a safety net for dot-terms constructed at
    % runtime; load-time template bodies are already rewritten by the
    % system's dict expansion of `T = Body`.
    (   Name == '.', Arity == 2, arg(1, Term, Dict), is_dict(Dict)
    ->  arg(2, Term, Key),
        get_dict(Key, Dict, Value),
        render(S, Value)
    ;   html_element(Name)
    ->  render_element(S, Name, Arity, Term)
    ;   tmpl(Term, Body)
    ->  render(S, Body)
    ;   render_helper(Term, S)
    ->  true
    ;   throw(error(domain_error(px_template_element, Term),
                    context(px_template:render/2,
                            'neither a whitelisted HTML5 element, a ~> template, nor a registered render_helper/2 helper')))
    ).
render(_, Term) :-
    throw(error(type_error(px_template_body, Term),
                context(px_template:render/2, 'cannot render term'))).

text_node(T) :- string(T), !.
text_node(T) :- atom(T), !.
text_node(T) :- number(T).

%!  render_call(+Stream, +Goal) is det.
%
%   The \Goal explicit escape (bare compound dispatch in render/2 uses
%   the same order, after the element check): first a template (tmpl/2,
%   first matching clause wins -- ordinary clause selection), then the
%   render_helper/2 hook, else an existence error naming the missing
%   template.

render_call(S, Goal) :-
    (   tmpl(Goal, Body)
    ->  render(S, Body)
    ;   render_helper(Goal, S)
    ->  true
    ;   throw(error(existence_error(px_template_template, Goal),
                    context(px_template:render/2,
                            'no ~> template clause and no render_helper/2 clause matches')))
    ).

		 /*******************************
		 *           ELEMENTS           *
		 *******************************/

render_element(S, Name, 1, Term) :-
    void_element(Name),
    !,
    arg(1, Term, Attrs),
    open_tag(S, Name, Attrs).
render_element(_, Name, _, Term) :-
    void_element(Name),
    !,
    throw(error(domain_error(void_element, Term),
                context(px_template:render/2,
                        'void element takes attributes only, no children'))).
render_element(S, Name, 1, Term) :-
    !,
    arg(1, Term, Children),
    open_tag(S, Name, []),
    render(S, Children),
    close_tag(S, Name).
render_element(S, Name, 2, Term) :-
    !,
    arg(1, Term, Attrs),
    arg(2, Term, Children),
    open_tag(S, Name, Attrs),
    render(S, Children),
    close_tag(S, Name).
render_element(_, _, _, Term) :-
    throw(error(domain_error(element_arity, Term),
                context(px_template:render/2,
                        'elements take (Children) or (Attrs, Children)'))).

%!  render_tag(+Stream, +Name, +Attrs, +Children) is det.
%
%   Render a literal tag that is NOT on the element whitelist: open
%   tag with attributes on the wire, children rendered, close tag.
%   Same streaming discipline and underscore->dash name mapping as
%   whitelisted elements.  For helpers (px_turbo's turbo_frame /
%   turbo_stream) that own a custom tag without claiming its functor
%   in the render-dispatch namespace.

render_tag(S, Name, Attrs, Children) :-
    open_tag(S, Name, Attrs),
    render(S, Children),
    close_tag(S, Name).

open_tag(S, Name, Attrs) :-
    tag_name(Name, Tag),
    format(S, "<~w", [Tag]),
    render_attrs(S, Attrs),
    write(S, ">").                  % on the wire NOW, children not yet touched

close_tag(S, Name) :-
    tag_name(Name, Tag),
    format(S, "</~w>", [Tag]).

%!  tag_name(+Functor, -Tag) is det.
%
%   Element (and attribute) functors map to names with underscores
%   rewritten to dashes: turbo_frame -> turbo-frame.

tag_name(Name, Tag) :-
    (   sub_atom(Name, _, _, _, '_')
    ->  atomic_list_concat(Parts, '_', Name),
        atomic_list_concat(Parts, -, Tag)
    ;   Tag = Name
    ).

		 /*******************************
		 *          ATTRIBUTES          *
		 *******************************/

render_attrs(_, []) :- !.
render_attrs(S, [A|As]) :-
    !,
    render_attr(S, A),
    render_attrs(S, As).
render_attrs(S, A) :-
    render_attr(S, A).

render_attr(S, A) :-
    atom(A),                        % boolean attribute: required, disabled
    !,
    tag_name(A, Attr),
    format(S, " ~w", [Attr]).
render_attr(S, A) :-
    compound(A),
    compound_name_arity(A, Name, 1),
    !,
    arg(1, A, Value),
    tag_name(Name, Attr),
    format(S, " ~w=\"", [Attr]),
    write_attr_value(S, Value),
    write(S, "\"").
render_attr(_, A) :-
    throw(error(domain_error(attribute, A),
                context(px_template:render/2,
                        'attributes are name(Value) terms or bare atoms'))).

%!  write_attr_value(+Stream, +Value) is det.
%
%   Compound values are offered to the eval_attr_value/2 hook first --
%   that is where the router resolves path terms like post_path(7).  An
%   unresolved compound is written back in standard operator notation
%   (id(post-7) emits id="post-7").
%
%   An ATOM is also offered to the hook, because a zero-arity path
%   helper (comments_path, new_widget_path, ...) is written by app
%   code as a bare atom -- there is no other term shape for "call this
%   0-arity helper".  If the hook does not resolve it (it is not a
%   registered helper name), the atom is emitted literally, same as
%   always.  A STRING is NEVER offered to the hook and never will be:
%   atom = maybe a helper name, string = always a literal value. That
%   is the only distinction between the two text types this predicate
%   sees, and it is deliberate -- app code that wants a literal path
%   writes a string ("/posts") precisely to opt out of resolution.
%
%   Everything is escaped, including double quotes.

write_attr_value(S, V) :-
    compound(V),
    !,
    (   eval_attr_value(V, Resolved)
    ->  write_escaped(S, Resolved)
    ;   term_string(Str, V),
        write_escaped(S, Str)
    ).
write_attr_value(S, V) :-
    atom(V),
    !,
    (   eval_attr_value(V, Resolved)
    ->  write_escaped(S, Resolved)
    ;   write_escaped(S, V)
    ).
write_attr_value(S, V) :-
    write_escaped(S, V).

		 /*******************************
		 *           ESCAPING           *
		 *******************************/

%!  write_escaped(+Stream, +Text) is det.
%
%   Write Text (string, atom or number) HTML-escaped: & < > " become
%   entities.  Works over the code list in runs -- unescaped spans are
%   written with one format/3 call each -- so no escaped copy of the
%   whole text is ever built.

write_escaped(S, Text) :-
    text_codes(Text, Codes),
    write_escaped_codes(Codes, S).

text_codes(T, Codes) :- string(T), !, string_codes(T, Codes).
text_codes(T, Codes) :- atom(T),   !, atom_codes(T, Codes).
text_codes(T, Codes) :- number(T), !, number_codes(T, Codes).
text_codes(T, _) :-
    throw(error(type_error(text, T),
                context(px_template:render/2, 'text node'))).

write_escaped_codes([], _).
write_escaped_codes([C|Cs], S) :-
    (   escape_entity(C, Entity)
    ->  write(S, Entity),
        write_escaped_codes(Cs, S)
    ;   plain_run(Cs, Run, Rest),
        format(S, "~s", [[C|Run]]),
        write_escaped_codes(Rest, S)
    ).

plain_run([C|Cs], [C|Run], Rest) :-
    \+ escape_entity(C, _),
    !,
    plain_run(Cs, Run, Rest).
plain_run(Cs, [], Cs).

escape_entity(0'&, '&amp;').
escape_entity(0'<, '&lt;').
escape_entity(0'>, '&gt;').
escape_entity(0'", '&quot;').

		 /*******************************
		 *       BUILT-IN HELPERS       *
		 *******************************/

%   The built-ins of adr/0019 section 3, as ordinary clauses of the
%   extension hook.  form_for/4 belongs to adr/0023 and is registered
%   by the forms subsystem, not here.

%   each(List, Template): render Template(X) for each X, in order.
%   Each element's bytes are written before the next element is even
%   looked at.
render_helper(each(List, Template), S) :-
    must_be(list, List),
    must_be(atom, Template),
    forall(member(X, List),
           ( Goal =.. [Template, X],
             render_call(S, Goal)
           )).

%   text(Term): any term as an escaped text node.
render_helper(text(Term), S) :-
    (   text_node(Term)
    ->  write_escaped(S, Term)
    ;   format(string(Str), "~w", [Term]),
        write_escaped(S, Str)
    ).

%   link_to(Text, PathTerm): an anchor; the href goes through the
%   eval_attr_value/2 hook like any compound attribute value, which is
%   where the router resolves path terms (adr/0018).
render_helper(link_to(Text, PathTerm), S) :-
    render(S, a(href(PathTerm), Text)).

%   markdown(String): bridge to the v1 markdown engine (adr/0011) --
%   parse, render to an (already escaped) HTML string, emit raw.  The
%   one buffered island, accepted by adr/0019.
render_helper(markdown(Text), S) :-
    (   string(Text) -> Str = Text ; text_to_string(Text, Str) ),
    md_parser:markdown_to_ast(Str, AST),
    md_html:ast_to_html_string(AST, Html),
    render(S, raw(Html)).

		 /*******************************
		 *          TEST SUPPORT        *
		 *******************************/

%!  render_to_string(+Term, -String) is det.
%
%   FOR TESTS ONLY.  Captures render/2 output in a string via
%   with_output_to/2 -- exactly the buffering the production path never
%   does (adr/0019 section 4).  The transport edge always calls
%   render/2 on the response IOSTREAM directly.

render_to_string(Term, String) :-
    with_output_to(string(String),
                   ( current_output(S),
                     render(S, Term)
                   )).

		 /*******************************
		 *      ELEMENT WHITELIST       *
		 *******************************/

%!  html_element(?Name) is nondet.
%
%   The fixed HTML5 element whitelist.  Functor names use underscores
%   where the emitted tag has dashes (turbo_frame -> <turbo-frame>).

html_element(E) :- normal_element(E).
html_element(E) :- void_element(E).

normal_element(html).
normal_element(head).
normal_element(body).
normal_element(title).
normal_element(script).
normal_element(style).
normal_element(div).
normal_element(span).
normal_element(p).
normal_element(a).
normal_element(h1).
normal_element(h2).
normal_element(h3).
normal_element(h4).
normal_element(h5).
normal_element(h6).
normal_element(ul).
normal_element(ol).
normal_element(li).
normal_element(dl).
normal_element(dt).
normal_element(dd).
normal_element(article).
normal_element(section).
normal_element(header).
normal_element(footer).
normal_element(nav).
normal_element(main).
normal_element(aside).
normal_element(form).
normal_element(textarea).
normal_element(select).
normal_element(option).
normal_element(label).
normal_element(button).
normal_element(fieldset).
normal_element(legend).
normal_element(table).
normal_element(caption).
normal_element(thead).
normal_element(tbody).
normal_element(tfoot).
normal_element(tr).
normal_element(th).
normal_element(td).
normal_element(pre).
normal_element(code).
normal_element(blockquote).
normal_element(strong).
normal_element(em).
normal_element(small).
normal_element(time).
normal_element(template).
normal_element(details).
normal_element(summary).
normal_element(figure).
normal_element(figcaption).
%   turbo_frame / turbo_stream are NOT elements: they are px_turbo
%   helpers (adr/0024) that emit <turbo-frame>/<turbo-stream> via
%   render_tag/4, so the bare call turbo_frame(post(7), [...])
%   resolves to the helper with its id-term first argument.

%!  void_element(?Name) is nondet.
%
%   Void elements: attributes only, self-contained, no closing tag;
%   handing one children is an error.

void_element(br).
void_element(hr).
void_element(img).
void_element(input).
void_element(meta).
void_element(link).
