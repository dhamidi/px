:- module(px_form,
          [ form_validate/3,        % +FormName, +ParamsDict, -Result
            form_result/3           % +FormName, +Env, -Result
          ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(error)).
:- use_module(library(pcre)).
:- use_module(px_template).

/** <module> Forms (adr/0023): declared once, validated purely,
    re-rendered from the same declaration.

A form is declared with a directive in any module that has this one
loaded:

    :- form(post_form,
         [ field(title, text,     [required, max_length(120)]),
           field(body,  textarea, [required])
         ]).

The directive is term-expanded (like `~>` in px_template) into a fact
of the multifile px_form:form_definition/3, capturing the *declaring
module* (adr/0016 rule 7) so that check/1,2 predicates and
select-options goals are later called there without any manual
qualification.

Widgets (closed vocabulary; a widget decides rendering and casting):
text, textarea, email, password, number, checkbox,
select(OptionsGoalOrList), hidden.

Constraints (closed vocabulary): required, max_length(N),
min_length(N), numeric, range(Lo, Hi), format(Regex), in(List),
check(Pred), check(Pred, Message).

Validation is the pure form_validate/3 over a params dict (atom keys,
string values, adr/0017); form_result/3 merely reads Env.params.
Result is one of

    ok(Values)              typed casts, declared fields only
    invalid(Values, Errors) raw input preserved, error(Field, Msg) list

Evaluation rules (adr/0023 section 1): constraints run in declaration
order and the FIRST failing constraint yields the field's single
error; a blank non-required field skips its remaining constraints; a
`number` widget implies `numeric`; an absent checkbox is `false`, and
`required` on a checkbox means "must be checked"; a select carries an
implicit in(OptionValues) check.

Rendering plugs into px_template's render_helper/2 hook (adr/0019),
called bare like any other helper (\Goal stays as the explicit escape):

    form_for(FormName, ActionPathTerm, Values, Errors)
    field_input(FormName, FieldName, Values, Errors)

Both build ordinary px_template element terms and hand them to
px_template:render/2 (the link_to pattern), so bytes stream and all
refilled values ride through the standard escaping.  Password widgets
never emit a value attribute.  patch(P)/put(P)/delete(P) action terms
render method="post" plus the adr/0018 `_method` override hidden
input.  Action path terms are resolved through the px_env:
eval_path_term/2 multifile hook the router registers (adr/0018).
*/

%   form_definition(Name, Module, Fields): one fact per :- form/2
%   directive, produced by term expansion below.  Multifile so the
%   expansion can return the clause into this module from anywhere.
:- multifile form_definition/3.
:- dynamic form_definition/3.

%   The reversible-router hook (adr/0018), declared here so form_for
%   can resolve action path terms even when px_env is not loaded
%   (tests register stand-in clauses exactly like the router would).
:- multifile px_env:eval_path_term/2.
:- dynamic px_env:eval_path_term/2.


		 /*******************************
		 *    :- form/2 EXPANSION       *
		 *******************************/

:- multifile user:term_expansion/2.

user:term_expansion((:- form(Name, Fields)), Clauses) :-
    prolog_load_context(module, Module),
    px_form:expand_form(Name, Fields, Module, Clauses).

%!  expand_form(+Name, +Fields, +Module, -Clauses) is det.
%
%   `:- form(Name, Fields)` ==> `px_form:form_definition(Name, Module,
%   Fields).`  The whole declaration is vocabulary-checked at
%   expansion time so a typo'd widget or constraint fails the load,
%   not the first request.

expand_form(Name, Fields, Module,
            [px_form:form_definition(Name, Module, Fields)]) :-
    must_be(atom, Name),
    must_be(list, Fields),
    maplist(check_field_decl, Fields).

check_field_decl(field(FName, Widget, Constraints)) :-
    !,
    must_be(atom, FName),
    check_widget_decl(Widget),
    must_be(list, Constraints),
    maplist(check_constraint_decl, Constraints).
check_field_decl(F) :-
    throw(error(domain_error(px_form_field, F),
                context(px_form:form/2,
                        'fields are field(Name, Widget, Constraints) terms'))).

check_widget_decl(W) :-
    (   widget_decl(W)
    ->  true
    ;   throw(error(domain_error(px_form_widget, W),
                    context(px_form:form/2,
                            'widgets: text, textarea, email, password, number, checkbox, select(OptionsGoalOrList), hidden')))
    ).

widget_decl(text).
widget_decl(textarea).
widget_decl(email).
widget_decl(password).
widget_decl(number).
widget_decl(checkbox).
widget_decl(hidden).
widget_decl(select(Spec)) :-
    (   is_list(Spec)
    ->  true
    ;   atom(Spec)
    ).

check_constraint_decl(C) :-
    (   constraint_decl(C)
    ->  true
    ;   throw(error(domain_error(px_form_constraint, C),
                    context(px_form:form/2,
                            'constraints: required, max_length(N), min_length(N), numeric, range(Lo, Hi), format(Regex), in(List), check(Pred), check(Pred, Message)')))
    ).

constraint_decl(required).
constraint_decl(max_length(N)) :- integer(N).
constraint_decl(min_length(N)) :- integer(N).
constraint_decl(numeric).
constraint_decl(range(Lo, Hi)) :- number(Lo), number(Hi).
constraint_decl(format(Re)) :- ( string(Re) ; atom(Re) ), !.
constraint_decl(in(L)) :- is_list(L).
constraint_decl(check(P)) :- atom(P).
constraint_decl(check(P, Msg)) :- atom(P), ( string(Msg) ; atom(Msg) ), !.


		 /*******************************
		 *          VALIDATION          *
		 *******************************/

%!  form_result(+FormName, +Env, -Result) is det.
%
%   form_validate/3 over Env.params (adr/0017).  Reads the env, does
%   not thread or modify it.

form_result(FormName, Env, Result) :-
    get_dict(params, Env, Params),
    form_validate(FormName, Params, Result).

%!  form_validate(+FormName, +ParamsDict, -Result) is det.
%
%   The pure core: params dict in, `ok(Values)` (typed, declared
%   fields only) or `invalid(Values, Errors)` (raw input preserved,
%   errors in field declaration order) out.

form_validate(FormName, Params, Result) :-
    must_be(dict, Params),
    form_lookup(FormName, Module, Fields),
    validate_fields(Fields, Module, Params, RawPairs, TypedPairs, Errors),
    (   Errors == []
    ->  dict_pairs(Values, _, TypedPairs),
        Result = ok(Values)
    ;   dict_pairs(Values, _, RawPairs),
        Result = invalid(Values, Errors)
    ).

form_lookup(Name, Module, Fields) :-
    (   form_definition(Name, Module, Fields)
    ->  true
    ;   throw(error(existence_error(px_form_form, Name),
                    context(px_form:form_lookup/3,
                            'no :- form(Name, Fields) declaration')))
    ).

validate_fields([], _, _, [], [], []).
validate_fields([field(F, Widget, Cs)|Fields], Module, Params,
                [F-Raw|Raws], Typed, Errors) :-
    field_raw(Widget, F, Params, Raw),
    effective_constraints(Widget, Module, Cs, ECs),
    check_field(ECs, Raw, Module, Status),
    (   Status == ok
    ->  cast_value(Widget, Raw, V),
        Typed = [F-V|Typed1],
        Errors = Errors1
    ;   Status = field_error(Msg),
        Typed = Typed1,
        Errors = [error(F, Msg)|Errors1]
    ),
    validate_fields(Fields, Module, Params, Raws, Typed1, Errors1).

%   The raw value used for both checking and (on invalid) re-render:
%   the param string as typed, "" when absent; checkboxes are the
%   booleans true/false (an unchecked box is simply absent).

field_raw(checkbox, F, Params, Raw) :-
    !,
    (   get_dict(F, Params, V),
        \+ checkbox_off(V)
    ->  Raw = true
    ;   Raw = false
    ).
field_raw(_, F, Params, Raw) :-
    (   get_dict(F, Params, V)
    ->  to_string(V, Raw)
    ;   Raw = ""
    ).

checkbox_off("").
checkbox_off(false).

%   number widgets imply numeric (inserted after required so required
%   still reports first on a blank field); selects carry an implicit
%   in(OptionValues) check after the declared constraints.

effective_constraints(number, _, Cs0, Cs) :-
    !,
    (   memberchk(numeric, Cs0)
    ->  Cs = Cs0
    ;   append(Before, [required|After], Cs0)
    ->  append(Before, [required, numeric|After], Cs)
    ;   Cs = [numeric|Cs0]
    ).
effective_constraints(select(Spec), Module, Cs0, Cs) :-
    !,
    select_options(Spec, Module, Pairs),
    findall(VS, ( member(V-_, Pairs), to_string(V, VS) ), OptionValues),
    append(Cs0, [in(OptionValues)], Cs).
effective_constraints(_, _, Cs, Cs).

%!  check_field(+Constraints, +Raw, +Module, -Status) is det.
%
%   Status = ok | field_error(Message).  First failing constraint (in
%   declaration order) wins; blank non-required fields skip the rest.

check_field(Cs, Raw, Module, Status) :-
    (   blank(Raw)
    ->  (   memberchk(required, Cs)
        ->  constraint_message(required, Msg),
            Status = field_error(Msg)
        ;   Status = ok
        )
    ;   first_failure(Cs, Raw, Module, Status)
    ).

blank("").
blank(false).

first_failure([], _, _, ok).
first_failure([C|Cs], Raw, Module, Status) :-
    (   constraint_ok(C, Raw, Module)
    ->  first_failure(Cs, Raw, Module, Status)
    ;   constraint_message(C, Msg),
        Status = field_error(Msg)
    ).

constraint_ok(required, Raw, _) :- \+ blank(Raw).
constraint_ok(max_length(N), Raw, _) :- string_length(Raw, L), L =< N.
constraint_ok(min_length(N), Raw, _) :- string_length(Raw, L), L >= N.
constraint_ok(numeric, Raw, _) :- parse_number(Raw, _).
constraint_ok(range(Lo, Hi), Raw, _) :-
    parse_number(Raw, V),
    Lo =< V, V =< Hi.
constraint_ok(format(Re), Raw, _) :- re_match(Re, Raw).
constraint_ok(in(List), Raw, _) :-
    member(X, List),
    to_string(X, XS),
    XS == Raw,
    !.
constraint_ok(check(Pred), Raw, Module) :- call(Module:Pred, Raw).
constraint_ok(check(Pred, _), Raw, Module) :- call(Module:Pred, Raw).

%   Default English messages (adr/0023 constraint table).

constraint_message(required, "is required").
constraint_message(max_length(N), Msg) :-
    format(string(Msg), "must be at most ~w characters", [N]).
constraint_message(min_length(N), Msg) :-
    format(string(Msg), "must be at least ~w characters", [N]).
constraint_message(numeric, "must be a number").
constraint_message(range(Lo, Hi), Msg) :-
    format(string(Msg), "must be between ~w and ~w", [Lo, Hi]).
constraint_message(format(_), "is not in the expected format").
constraint_message(in(_), "is not a valid choice").
constraint_message(check(_), "is invalid").
constraint_message(check(_, Msg0), Msg) :- to_string(Msg0, Msg).

%   Casts on ok: numbers become Prolog numbers, checkboxes booleans,
%   everything else stays the string.  A blank optional number stays
%   "" (nothing was typed; there is no number to make of it).

cast_value(number, Raw, V) :-
    !,
    (   blank(Raw)
    ->  V = Raw
    ;   parse_number(Raw, V)
    ).
cast_value(_, Raw, Raw).

parse_number(S, N) :-
    string(S),
    catch(number_string(N, S), _, fail).


		 /*******************************
		 *      TEMPLATE HELPERS        *
		 *******************************/

%   Registered on px_template's extension hook (adr/0019), same shape
%   as the built-in link_to: build element terms, hand them to
%   render/2, let the streaming walker do the writing and escaping.

:- multifile px_template:render_helper/2.

px_template:render_helper(form_for(FormName, Action, Values, Errors), S) :-
    px_form:render_form_for(FormName, Action, Values, Errors, S).
px_template:render_helper(field_input(FormName, FieldName, Values, Errors), S) :-
    px_form:render_field_input(FormName, FieldName, Values, Errors, S).
px_template:render_helper(button_to(Label, MsgName, Action), S) :-
    px_form:render_button_to(Label, MsgName, Action, S).

%!  render_form_for(+FormName, +ActionTerm, +Values, +Errors, +S)
%
%   The whole form: open tag with resolved action and method="post",
%   the `_method` override input for patch/put/delete action terms,
%   one labelled field block per declared field (in order), a submit
%   button.

render_form_for(FormName, ActionTerm, Values, Errors, S) :-
    form_lookup(FormName, Module, Fields),
    action_method(ActionTerm, PathTerm, OverrideEls),
    resolve_action(PathTerm, ActionPath),
    findall(El,
            ( member(Field, Fields),
              field_element(FormName, Module, Field, Values, Errors, El)
            ),
            FieldEls),
    %   The form's name is its message name (adr/0027 decision 3):
    %   px_page's default decoder reads it back from params._msg.
    %   The submit label is the humanized form name -- create_article
    %   renders "Create article", never a generic "Submit".
    MsgInput = input([type(hidden), name('_msg'), value(FormName)]),
    humanize(FormName, SubmitLabel),
    append([[MsgInput], OverrideEls, FieldEls,
            [button(type(submit), SubmitLabel)]],
           Children),
    px_template:render(S,
                       form([action(ActionPath), method(post)], Children)).

%   HTML forms speak only GET and POST: every verb renders as
%   method="post"; patch/put/delete add the adr/0018 override input.

action_method(patch(P), P, [Override]) :- !, override_input(patch, Override).
action_method(put(P), P, [Override]) :- !, override_input(put, Override).
action_method(delete(P), P, [Override]) :- !, override_input(delete, Override).
action_method(P, P, []).

override_input(Verb, input([type(hidden), name('_method'), value(Verb)])).

resolve_action(PathTerm, Path) :-
    (   px_env:eval_path_term(PathTerm, Path0)
    ->  Path = Path0
    ;   ( atom(PathTerm) ; string(PathTerm) )
    ->  Path = PathTerm
    ;   throw(error(type_error(path_term, PathTerm),
                    context(px_form:form_for/4,
                            'no px_env:eval_path_term/2 clause applies and the term is not a literal path')))
    ).

%!  render_button_to(+Label, +MsgName, +ActionTerm, +S)
%
%   Rails' button_to: a single button that IS a form -- for actions
%   that carry no data beyond their intent (delete this, archive
%   that). Renders an inline form.button-to holding only the hidden
%   `_msg` (naming the message; a fieldless `:- form(MsgName, [])`
%   receives it validated as MsgName(ok(_))), the `_method` override
%   when the action term asks for one, and the labelled button. The
%   button-to class strips the panel styling a real form gets, so
%   this sits inline next to links.

render_button_to(Label, MsgName, ActionTerm, S) :-
    action_method(ActionTerm, PathTerm, OverrideEls),
    resolve_action(PathTerm, ActionPath),
    MsgInput = input([type(hidden), name('_msg'), value(MsgName)]),
    append([[MsgInput], OverrideEls, [button(type(submit), Label)]],
           Children),
    px_template:render(S,
                       form([class("button-to"), action(ActionPath),
                             method(post)],
                            Children)).

%!  render_field_input(+FormName, +FieldName, +Values, +Errors, +S)
%
%   The escape hatch: just the input element (correct widget, name,
%   id, refilled value) plus its adjacent error message if any.  The
%   surrounding form, label and wrappers are the template's own.

render_field_input(FormName, FieldName, Values, Errors, S) :-
    form_lookup(FormName, Module, Fields),
    (   memberchk(field(FieldName, Widget, _), Fields)
    ->  true
    ;   throw(error(existence_error(px_form_field, FormName:FieldName),
                    context(px_form:field_input/4,
                            'field not declared in this form')))
    ),
    field_dom_id(FormName, FieldName, Id),
    field_value(Widget, FieldName, Values, V),
    widget_input(Widget, Module, FieldName, Id, V, Input),
    field_error_els(FieldName, Errors, ErrEls, _Class),
    px_template:render(S, [Input|ErrEls]).

%   One field block: div.field (div.field.field-error when errored)
%   holding label, input, and the adjacent p.error.  Hidden widgets
%   render as the bare input -- no label, no wrapper.

field_element(FormName, Module, field(F, Widget, _Cs), Values, Errors, El) :-
    field_dom_id(FormName, F, Id),
    field_value(Widget, F, Values, V),
    widget_input(Widget, Module, F, Id, V, Input),
    (   Widget == hidden
    ->  El = Input
    ;   field_error_els(F, Errors, ErrEls, Class),
        humanize(F, Label),
        El = div(class(Class), [label(for(Id), Label), Input|ErrEls])
    ).

field_error_els(F, Errors, [p(class(error), Msg)], "field field-error") :-
    memberchk(error(F, Msg), Errors),
    !.
field_error_els(_, _, [], "field").

%   The current value for refilling, from the Values dict the handler
%   passed (raw on 422, typed after ok, empty dict on GET-new).

field_value(checkbox, F, Values, V) :-
    !,
    (   is_dict(Values),
        get_dict(F, Values, V0),
        \+ checkbox_off(V0)
    ->  V = true
    ;   V = false
    ).
field_value(_, F, Values, V) :-
    (   is_dict(Values),
        get_dict(F, Values, V0)
    ->  V = V0
    ;   V = ""
    ).

%!  widget_input(+Widget, +Module, +FieldName, +Id, +Value, -Element)
%
%   The widget-appropriate element term.  Passwords never carry a
%   value attribute (adr/0023 section 3); empty values omit it.

widget_input(text, _, F, Id, V, input([type(text), name(F), id(Id)|VA])) :-
    value_attr(V, VA).
widget_input(email, _, F, Id, V, input([type(email), name(F), id(Id)|VA])) :-
    value_attr(V, VA).
widget_input(number, _, F, Id, V, input([type(number), name(F), id(Id)|VA])) :-
    value_attr(V, VA).
widget_input(hidden, _, F, Id, V, input([type(hidden), name(F), id(Id)|VA])) :-
    value_attr(V, VA).
widget_input(password, _, F, Id, _, input([type(password), name(F), id(Id)])).
widget_input(textarea, _, F, Id, V, textarea([name(F), id(Id)], Text)) :-
    (   blankish(V)
    ->  Text = ""
    ;   Text = V
    ).
widget_input(checkbox, _, F, Id, V, input(Attrs)) :-
    (   V == true
    ->  Extra = [checked]
    ;   Extra = []
    ),
    Attrs = [type(checkbox), name(F), id(Id), value(on)|Extra].
widget_input(select(Spec), Module, F, Id, V, select([name(F), id(Id)], Opts)) :-
    select_options(Spec, Module, Pairs),
    (   blankish(V)
    ->  VS = ""
    ;   to_string(V, VS)
    ),
    maplist(option_element(VS), Pairs, Opts).

option_element(VS, OV-Label, option(Attrs, Label)) :-
    to_string(OV, OVS),
    (   OVS == VS
    ->  Attrs = [value(OV), selected]
    ;   Attrs = [value(OV)]
    ).

value_attr(V, []) :- blankish(V), !.
value_attr(V, [value(V)]).

blankish(V) :- V == "".
blankish(V) :- V == ''.
blankish(V) :- V == false.

%   select/1 options: a literal list of Value or Value-Label terms, or
%   the name of a predicate called as Goal(Options) in the declaring
%   module (adr/0023 section 1).

select_options(Spec, _, Pairs) :-
    is_list(Spec),
    !,
    maplist(normalize_option, Spec, Pairs).
select_options(Goal, Module, Pairs) :-
    atom(Goal),
    call(Module:Goal, Options),
    maplist(normalize_option, Options, Pairs).

normalize_option(V-L, V-L) :- !.
normalize_option(V, V-V).


		 /*******************************
		 *          SMALL BITS          *
		 *******************************/

%   name="title", id="post_form_title", label "Title" (adr/0023
%   naming conventions).

field_dom_id(FormName, F, Id) :-
    atomic_list_concat([FormName, '_', F], Id).

humanize(F, Label) :-
    atomic_list_concat(Parts, '_', F),
    atomic_list_concat(Parts, ' ', Spaced),
    atom_string(Spaced, S),
    (   sub_string(S, 0, 1, _, First),
        sub_string(S, 1, _, 0, Rest)
    ->  string_upper(First, Up),
        string_concat(Up, Rest, Label)
    ;   Label = S
    ).

to_string(T, S) :- string(T), !, S = T.
to_string(T, S) :- atom(T), !, atom_string(T, S).
to_string(T, S) :- number(T), !, number_string(T, S).
to_string(T, S) :- term_string(S, T).
