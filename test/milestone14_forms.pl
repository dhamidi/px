/* Milestone 14 (adr/0023): forms, prolog/px_form.pl, standalone --
   no server, no sockets.

   Declares a form exercising the vocabulary: text (required +
   max_length), number (range -- implied numeric), checkbox, select
   with literal options, select with goal-computed options, password,
   and a custom check/2 (proving the declaring module was captured).

   Asserts:
     - valid params -> ok(Values) with typed casts (number is a
       Prolog number, checkbox true/false), declared fields only
       (undeclared params dropped);
     - a two-error invalid case: first failing constraint per field,
       raw input preserved exactly (including the "12x" that failed
       the numeric cast), absent fields as "" / checkbox false,
       errors in declaration order;
     - blank non-required fields skip their remaining constraints;
     - required, max_length, range, tampered-select ("is not a valid
       choice") and check/2 messages;
     - rendering via px_template:render_to_string of a BARE
       form_for(..., patch(post_path(7)), Values, Errors) call:
       input value refilled AND escaped, error p adjacent to its own
       field, select options with the selected attr, `_method`
       override hidden input, ids/names per convention
       (name="title", id="gadget_form_title"), labels humanized,
       password never refilled, submit button;
     - bare field_input/4 emits just input + adjacent error, no label.

   Run:  swipl test/milestone14_forms.pl
*/

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../prolog/px_form'], PxFormLib),
   atomic_list_concat([Dir, '/../prolog/px_template'], PxTemplateLib),
   use_module(PxFormLib),
   use_module(PxTemplateLib).

:- discontiguous test/1.

:- initialization(main, main).

% ---------------------------------------------------------------------
% Stand-in for the adr/0018 router's path-term evaluation (the same
% multifile hook px_env:redirect/3 consults).
% ---------------------------------------------------------------------

:- multifile px_env:eval_path_term/2.
px_env:eval_path_term(posts_path, "/posts").
px_env:eval_path_term(post_path(Id), S) :-
    format(string(S), "/posts/~w", [Id]).

% ---------------------------------------------------------------------
% The form under test.
% ---------------------------------------------------------------------

:- form(gadget_form,
     [ field(title,    text,                        [required, max_length(20)]),
       field(quantity, number,                      [range(1, 10)]),
       field(featured, checkbox,                    []),
       field(color,    select([red-"Red", blue-"Blue"]), [required]),
       field(size,     select(size_options),        []),
       field(sku,      text,                        [check(sku_ok, "must start with G-")]),
       field(secret,   password,                    [])
     ]).

% Called as sku_ok(Value) in THIS module; failure = invalid.
sku_ok(Sku) :-
    sub_string(Sku, 0, 2, _, "G-").

% Called as size_options(Options) in THIS module.
size_options([s-"Small", m-"Medium", l-"Large"]).

% ---------------------------------------------------------------------
% Harness (milestone11 style).
% ---------------------------------------------------------------------

main :-
    Tests = [ valid_params_typed_ok,
              two_errors_preserve_raw,
              blank_non_required_skips,
              first_failing_constraint_wins,
              tampered_select_rejected,
              checkbox_required_means_checked,
              form_for_rendering,
              field_input_escape_hatch
            ],
    run_tests(Tests, 0, Failed),
    length(Tests, N),
    (   Failed =:= 0
    ->  format("milestone14_forms: all ~w tests passed~n", [N]),
        halt(0)
    ;   format(user_error, "milestone14_forms: ~w of ~w test(s) FAILED~n",
               [Failed, N]),
        halt(1)
    ).

run_tests([], F, F).
run_tests([T|Ts], F0, F) :-
    (   catch(test(T), E,
              ( format(user_error, "    exception: ~q~n", [E]), fail ))
    ->  format("  ok: ~w~n", [T]),
        F1 = F0
    ;   format(user_error, "  FAILED: ~w~n", [T]),
        F1 is F0 + 1
    ),
    run_tests(Ts, F1, F).

expect(Goal) :-
    (   call(Goal)
    ->  true
    ;   format(user_error, "    expected to succeed: ~q~n", [Goal]),
        fail
    ).

expect_sub(Text, Sub) :-
    (   sub_string(Text, _, _, _, Sub)
    ->  true
    ;   format(user_error, "    expected ~q in:~n~q~n", [Sub, Text]),
        fail
    ).

expect_no_sub(Text, Sub) :-
    (   sub_string(Text, _, _, _, Sub)
    ->  format(user_error, "    did NOT expect ~q in:~n~q~n", [Sub, Text]),
        fail
    ;   true
    ).

%   Sub1 must occur before Sub2 in Text (adjacency/ordering checks).
expect_before(Text, Sub1, Sub2) :-
    (   sub_string(Text, P1, _, _, Sub1),
        sub_string(Text, P2, _, _, Sub2),
        P1 < P2
    ->  true
    ;   format(user_error, "    expected ~q before ~q in:~n~q~n",
               [Sub1, Sub2, Text]),
        fail
    ).

% ---------------------------------------------------------------------
% Validation tests.
% ---------------------------------------------------------------------

%   Happy path: typed casts (quantity a number, featured a boolean),
%   undeclared params dropped, blank optional select kept as "".
test(valid_params_typed_ok) :-
    form_validate(gadget_form,
                  _{ title: "Widget",
                     quantity: "5",
                     featured: "on",
                     color: "red",
                     sku: "G-42",
                     secret: "hunter2hunter2",
                     hacker_field: "1; DROP TABLE gadgets" },
                  R),
    expect(R = ok(Values)),
    expect(Values.title == "Widget"),
    expect(Values.quantity == 5),          % a number, not "5"
    expect(Values.featured == true),
    expect(Values.color == "red"),
    expect(Values.size == ""),             % blank optional select
    expect(Values.sku == "G-42"),
    expect(Values.secret == "hunter2hunter2"),
    expect(\+ get_dict(hacker_field, Values, _)).   % declared fields only

%   Two errors; raw input preserved exactly (the failed "12x" cast
%   included); absent fields "" / checkbox false; declaration order.
test(two_errors_preserve_raw) :-
    form_validate(gadget_form,
                  _{ title: "",
                     quantity: "12x",
                     color: "red" },
                  R),
    expect(R = invalid(Values, Errors)),
    expect(Errors == [ error(title, "is required"),
                       error(quantity, "must be a number") ]),
    expect(Values.title == ""),
    expect(Values.quantity == "12x"),      % raw, exactly as typed
    expect(Values.featured == false),      % absent checkbox
    expect(Values.color == "red"),
    expect(Values.size == ""),
    expect(Values.sku == "").

%   Blank non-required fields skip remaining constraints: quantity ""
%   is not "must be a number", sku "" skips check/2.
test(blank_non_required_skips) :-
    form_validate(gadget_form,
                  _{ title: "Sprocket", quantity: "", color: "blue", sku: "" },
                  R),
    expect(R = ok(Values)),
    expect(Values.quantity == ""),
    expect(Values.sku == "").

%   First failing constraint per field wins, one error per field:
%   max_length on title, range on quantity, check/2 message on sku.
test(first_failing_constraint_wins) :-
    form_validate(gadget_form,
                  _{ title: "An excessively long gadget title",
                     quantity: "99",
                     color: "red",
                     sku: "X-1" },
                  R),
    expect(R = invalid(_, Errors)),
    expect(Errors == [ error(title, "must be at most 20 characters"),
                       error(quantity, "must be between 1 and 10"),
                       error(sku, "must start with G-") ]).

%   A tampered <option> is a validation error, not an insert: the
%   select's implicit in(OptionValues) check (both literal and
%   goal-computed options).
test(tampered_select_rejected) :-
    form_validate(gadget_form,
                  _{ title: "Widget", color: "green", size: "xxl" },
                  R),
    expect(R = invalid(_, Errors)),
    expect(Errors == [ error(color, "is not a valid choice"),
                       error(size, "is not a valid choice") ]).

%   required on a checkbox means "must be checked" (the ToS case),
%   and form_result/3 is form_validate over Env.params.
:- form(tos_form,
     [ field(tos, checkbox, [required]) ]).

test(checkbox_required_means_checked) :-
    form_validate(tos_form, _{}, R1),
    expect(R1 = invalid(V1, [error(tos, "is required")])),
    expect(V1.tos == false),
    Env = env{ params: _{tos: "on"} },
    form_result(tos_form, Env, R2),
    expect(R2 = ok(V2)),
    expect(V2.tos == true).

% ---------------------------------------------------------------------
% Rendering tests.
% ---------------------------------------------------------------------

test(form_for_rendering) :-
    Values = _{ title: "A \"quoted\" <gadget>",
                quantity: "12x",
                featured: true,
                color: "blue",
                size: "",
                sku: "G-42",
                secret: "hunter2hunter2" },
    Errors = [ error(title, "is required"),
               error(quantity, "must be a number") ],
    render_to_string(form_for(gadget_form, patch(post_path(7)), Values, Errors),
                     Html),
    % form tag: resolved action path term, method="post"
    expect_sub(Html, "<form action=\"/posts/7\" method=\"post\">"),
    % method override hidden input, before the fields
    expect_sub(Html, "<input type=\"hidden\" name=\"_method\" value=\"patch\">"),
    expect_before(Html, "name=\"_method\"", "name=\"title\""),
    % ids/names per convention + humanized label
    expect_sub(Html, "<label for=\"gadget_form_title\">Title</label>"),
    expect_sub(Html, "name=\"title\" id=\"gadget_form_title\""),
    % value refilled AND escaped
    expect_sub(Html,
        "value=\"A &quot;quoted&quot; &lt;gadget&gt;\""),
    % the failed raw numeric input comes back too
    expect_sub(Html, "name=\"quantity\" id=\"gadget_form_quantity\" value=\"12x\""),
    % each error message adjacent to ITS field: after that field's
    % input, before the next field's input
    expect_before(Html, "id=\"gadget_form_title\"",
                        "<p class=\"error\">is required</p>"),
    expect_before(Html, "<p class=\"error\">is required</p>",
                        "id=\"gadget_form_quantity\""),
    expect_before(Html, "id=\"gadget_form_quantity\"",
                        "<p class=\"error\">must be a number</p>"),
    expect_before(Html, "<p class=\"error\">must be a number</p>",
                        "id=\"gadget_form_featured\""),
    % errored fields carry the field-error class
    expect_sub(Html, "<div class=\"field field-error\">"),
    expect_sub(Html, "<div class=\"field\">"),
    % checkbox checked when true
    expect_sub(Html,
        "<input type=\"checkbox\" name=\"featured\" id=\"gadget_form_featured\" value=\"on\" checked>"),
    % select: options rendered, submitted one selected
    expect_sub(Html, "<select name=\"color\" id=\"gadget_form_color\">"),
    expect_sub(Html, "<option value=\"red\">Red</option>"),
    expect_sub(Html, "<option value=\"blue\" selected>Blue</option>"),
    % goal-computed options rendered, none selected for ""
    expect_sub(Html, "<option value=\"m\">Medium</option>"),
    % password never refilled
    expect_sub(Html, "<input type=\"password\" name=\"secret\" id=\"gadget_form_secret\">"),
    expect_no_sub(Html, "hunter2"),
    % submit button closes the form
    expect_sub(Html, "<button type=\"submit\">Submit</button></form>").

%   Bare (non-wrapped) action term: no override input; empty values
%   render no value attributes.
test(field_input_escape_hatch) :-
    render_to_string(form_for(gadget_form, posts_path, _{}, []), EmptyHtml),
    expect_sub(EmptyHtml, "<form action=\"/posts\" method=\"post\">"),
    expect_no_sub(EmptyHtml, "_method"),
    expect_no_sub(EmptyHtml, "value=\"\""),
    expect_no_sub(EmptyHtml, "checked"),
    expect_no_sub(EmptyHtml, "field-error"),
    % the per-field escape hatch: input + adjacent error, nothing else
    render_to_string(field_input(gadget_form, title,
                                 _{title: "Sprocket"},
                                 [error(title, "is required")]),
                     Html),
    expect(Html ==
        "<input type=\"text\" name=\"title\" id=\"gadget_form_title\" value=\"Sprocket\"><p class=\"error\">is required</p>"),
    render_to_string(field_input(gadget_form, title, _{title: "Ok"}, []),
                     Html2),
    expect_no_sub(Html2, "<label"),
    expect_no_sub(Html2, "error").
