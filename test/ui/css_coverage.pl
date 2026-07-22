/* test/ui/css_coverage.pl (adr/0026 rule 7(d)): the static
   cross-check docs/ui-visual-audit.md ran by hand, promoted to a
   permanent, automated test-suite step.

   Loads every component module under prolog/ui/ (via prolog/px_ui.pl,
   the same auto-loader the live app uses), renders EVERY registered
   `px_ui:demo/3` kitchen-sink template to a string exactly the way
   prolog/px_ui.pl's `ui_show_view` embeds it (`div(class("ui-demo"),
   Call)`), and extracts every `.px-[a-z0-9_-]+` class *selector* out
   of assets/css/ui.css. Every one of those selectors must appear as
   an actual class *token* (not just a substring match -- see
   `html_class_tokens/2` below) on at least one element across all the
   rendered demo HTML; otherwise the rule the CSS was written against
   is structurally unreachable, exactly `radio_group`'s
   `.px-radio-group-input` defect (docs/ui-visual-audit.md,
   prolog/ui/radio_group.pl's now-fixed `item_attrs/3`).

   This test is required to FAIL against the pre-fix radio_group.pl
   (no `.px-radio-group-input` anywhere in the rendered demo) and PASS
   after the fix -- verified by hand at fix time; see the commit this
   file ships in.
*/

:- use_module(library(pcre)).
:- use_module(library(readutil)).
:- use_module(library(lists)).
:- use_module('../../prolog/px_template.pl').
:- use_module('../../prolog/px_ui.pl').

:- initialization(main, main).

% ---------------------------------------------------------------------
% Whitelist: CSS selectors intentionally exempt from the "must appear
% in some rendered demo" rule, with a one-line justification each.
% Empty for now (adr/0026 rule 7(d)) -- every `.px-*` selector in
% ui.css as of this writing is reachable from some demo's rendered
% markup. Add entries here only with a real justification (e.g. a
% class only ever added by client-side JS after an event, never
% present in the server-rendered initial markup) -- NOT to silence a
% real coverage gap.
% ---------------------------------------------------------------------

whitelisted_class(_) :- fail.

% ---------------------------------------------------------------------
% Harness (test/ui/radio_group.pl's / test/ui/progress.pl's pattern).
% ---------------------------------------------------------------------

:- dynamic failed_count/1.
failed_count(0).

:- dynamic here_dir/1.

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

main :-
    tests,
    failed_count(N),
    (   N =:= 0
    ->  format("~nAll ui/css_coverage checks passed.~n"),
        halt(0)
    ;   format("~n~w check(s) FAILED.~n", [N]),
        halt(1)
    ).

% ---------------------------------------------------------------------
% Extraction helpers.
% ---------------------------------------------------------------------

%   prolog_load_context/2 only reports meaningful info while THIS file
%   is actively being compiled -- captured here, at load time, into a
%   fact, rather than (wrongly) called later at runtime from inside
%   css_file/1, which would just fail once loading has finished.
:- prolog_load_context(directory, Here),
   assertz(here_dir(Here)).

%!  css_file(-Path) is det.
%
%   Located relative to this test file, same convention as the
%   render tests' '../../prolog/...' module paths.
css_file(Path) :-
    here_dir(Here),
    atomic_list_concat([Here, '/../../assets/css/ui.css'], Path).

%!  css_class_selectors(+File, -Classes) is det.
%
%   Classes is the sorted list of unique class names (no leading
%   `.`) referenced by any `.px-<name>` selector anywhere in File --
%   regardless of what pseudo-class/combinator/attribute-selector
%   follows (`.px-radio-group-input::before`,
%   `.px-radio-group-input:checked`, and a bare
%   `.px-radio-group-input` all yield the same class name
%   `px-radio-group-input`).
css_class_selectors(File, Classes) :-
    read_file_to_string(File, Css, []),
    re_foldl([Dict,L0,L1]>>( get_dict(0, Dict, M), L1 = [M|L0] ),
             "\\.px-[a-z0-9_-]+", Css, [], MatchesRaw, []),
    findall(C,
            ( member(MRaw, MatchesRaw),
              sub_string(MRaw, 1, _, 0, C)  % strip the leading "."
            ),
            Cs0),
    sort(Cs0, Classes).

%!  all_demo_html(-Html) is det.
%
%   Html is the concatenation of every registered `px_ui:demo/3`
%   template rendered exactly the way prolog/px_ui.pl's
%   `ui_show_view/2` embeds it in the live app: `Call` (the `\Name`
%   escape term) as the sole Children of a
%   `div(class("ui-demo"), Call)`.
all_demo_html(Html) :-
    findall(Name-Rendered,
            ( px_ui:demo(Name, _Order, Call),
              render_to_string(div(class("ui-demo"), Call), Rendered)
            ),
            Pairs),
    Pairs \== [],  % sanity: the auto-loader actually found components
    findall(R, member(_-R, Pairs), Parts),
    atomics_to_string(Parts, "\n", Html).

%!  html_class_tokens(+Html, -Tokens) is det.
%
%   Tokens is the sorted list of unique class *tokens* (whitespace-
%   split values of every `class="..."` attribute) appearing anywhere
%   in Html -- token-level, not substring, so `.px-switch` does not
%   spuriously "match" an element that only carries
%   `class="px-switch-trigger"`.
html_class_tokens(Html, Tokens) :-
    re_foldl([Dict,L0,L1]>>( get_dict(1, Dict, G), L1 = [G|L0] ),
             "class=\"([^\"]*)\"", Html, [], ClassAttrs, []),
    findall(Tok,
            ( member(Attr, ClassAttrs),
              split_string(Attr, " ", " ", RawToks),
              member(Tok0, RawToks),
              Tok0 \== "",
              atom_string(Tok, Tok0)
            ),
            Toks0),
    sort(Toks0, Tokens).

% ---------------------------------------------------------------------

tests :-
    css_file(CssFile),
    css_class_selectors(CssFile, CssClasses),
    length(CssClasses, NCssClasses),
    format("~w unique .px-* class selectors found in ~w~n",
           [NCssClasses, CssFile]),
    check(found_some_css_classes, NCssClasses > 0),

    all_demo_html(Html),
    string_length(Html, HtmlLen),
    findall(Name, px_ui:demo(Name, _, _), DemoNames0),
    sort(DemoNames0, DemoNames),
    length(DemoNames, NDemos),
    format("~w registered px_ui:demo/3 templates rendered (~w total HTML chars): ~q~n",
           [NDemos, HtmlLen, DemoNames]),
    check(rendered_at_least_one_demo, NDemos > 0),

    html_class_tokens(Html, HtmlTokens),
    length(HtmlTokens, NHtmlTokens),
    format("~w unique class tokens found across all rendered demos~n",
           [NHtmlTokens]),

    % The actual coverage check: every non-whitelisted .px-* CSS
    % selector must appear as a class token somewhere in the
    % concatenated rendered demo HTML.
    findall(Missing,
            ( member(ClassS, CssClasses),
              atom_string(ClassA, ClassS),
              \+ whitelisted_class(ClassA),
              \+ memberchk(ClassA, HtmlTokens),
              Missing = ClassA
            ),
            MissingClasses),
    (   MissingClasses == []
    ->  true
    ;   format("      orphaned CSS selectors (never emitted by any demo): ~q~n",
               [MissingClasses])
    ),
    check(every_css_class_reachable_from_some_demo,
          MissingClasses == []),

    format("~n--- coverage summary ---~ncss selectors: ~w   demos rendered: ~w   html class tokens: ~w   orphaned: ~w~n------------------------~n",
           [NCssClasses, NDemos, NHtmlTokens, MissingClasses]).
