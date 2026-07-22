/* ui/label (adr/0026): the render-contract test required by rule 7a.
   A plain swipl script -- no server, no networking -- loading
   px_template.pl and px_ui.pl (which, per its directory scan, loads
   every module under prolog/ui/) and exercising render_to_string/2
   over label_root/2 and the registered demo, same harness shape as
   test/milestone10_templates.pl and test/ui/separator.pl.

   Covers the contract from prolog/ui/label.pl's module header
   (docs/radix-port-analysis.md "Label"):
     - a bare native <label>, no data-state, no role, no aria-* --
       Label's whole DOM/ARIA contract is "none beyond native for/
       wrapping association"
     - for(Id) renders the native for="Id" association
     - pass-through attrs (id, data_testid, boolean atoms) survive
       untouched
     - a caller class(...) is merged with, not replacing, the default
       px-label styling hook
     - wrapping association: a control nested in Children (no for
       needed) renders inside the label
     - the component registers px_ui:demo(label, _, _), and that demo
       renders both association patterns (for/id, and wrapping)

   Run:  swipl test/ui/label.pl
*/

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../../prolog/px_template'], TemplateSpec),
   atomic_list_concat([Dir, '/../../prolog/px_ui'],       PxUiSpec),
   use_module(TemplateSpec),
   use_module(PxUiSpec).

:- initialization(main, main).

		 /*******************************
		 *            HARNESS           *
		 *******************************/

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
    ->  format("~nAll ui/label checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

		 /*******************************
		 *             TESTS            *
		 *******************************/

tests :-
    % -- for/id association: exact markup, no data-state/role/aria -----
    check(for_association_exact_markup,
          ( render_to_string(label_root([for("email")], "Email address"), S0),
            S0 == "<label class=\"px-label\" for=\"email\">Email address</label>" )),

    % -- no ARIA/role noise anywhere, ever -------------------------------
    check(no_role_or_aria_ever,
          ( render_to_string(label_root([for(x)], "X"), S1),
            \+ contains(S1, "role="),
            \+ contains(S1, "aria-"),
            \+ contains(S1, "data-state") )),

    % -- empty Opts: bare label, still gets the default class -----------
    check(no_opts_still_gets_default_class,
          ( render_to_string(label_root([], "Plain"), S2),
            S2 == "<label class=\"px-label\">Plain</label>" )),

    % -- pass-through attrs survive (id, data_testid, boolean atom) -----
    check(passthrough_id_and_data_attr,
          ( render_to_string(label_root([id(lbl1), data_testid(name_label), for(f1)], "Name"), S3),
            contains(S3, "id=\"lbl1\""),
            contains(S3, "data-testid=\"name_label\""),
            contains(S3, "for=\"f1\"") )),

    % -- class(...) merges with, does not replace, px-label -------------
    check(class_merged_not_replaced,
          ( render_to_string(label_root([class("required")], "Name"), S4),
            contains(S4, "class=\"px-label required\"") )),

    % -- wrapping association: a nested control, no `for` needed --------
    check(wrapping_association_renders_control_inside,
          ( render_to_string(
                label_root([], ["Subscribe ", input([type(checkbox), name(subscribe)])]),
                S5),
            S5 == "<label class=\"px-label\">Subscribe <input type=\"checkbox\" name=\"subscribe\"></label>",
            \+ contains(S5, "for=\"") )),

    % -- text is HTML-escaped like any other template text node ---------
    check(text_escaped,
          ( render_to_string(label_root([], "Terms & <Conditions>"), S6),
            contains(S6, "Terms &amp; &lt;Conditions&gt;"),
            \+ contains(S6, "<Conditions>") )),

    % -- demo registration + render (adr/0026 rule 7b) -------------------
    check(demo_registered,
          px_ui:demo(label, _Order, \label_demo)),

    check(demo_renders_both_association_patterns,
          ( render_to_string(\label_demo, SDemo),
            contains(SDemo, "class=\"px-label\" for=\"label-demo-email\""),
            contains(SDemo, "id=\"label-demo-email\""),
            contains(SDemo, "type=\"checkbox\" name=\"subscribe\"") )),

    % show some real output for the record
    render_to_string(\label_demo, Full),
    format("~n--- rendered label_demo ---~n~w~n---------------------------~n", [Full]).
