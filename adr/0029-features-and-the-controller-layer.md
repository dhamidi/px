# 0029. App structure v2: features and the controller layer

Status: Accepted (supersedes the layout half of adr/0027; the TEA
cycle, message decoding, and effects vocabulary of adr/0027 stand)

## Context

adr/0027 grouped the app by *role* — `app/pages/`, `app/views/`,
`app/lib/` — which is Rails' weakness inherited faithfully: one
feature's code scatters across three directories, and nothing in the
filesystem names the concepts the architecture is actually made of.
Django groups by feature instead (an "app" per domain), and that is
the right axis: a feature's controller, messages, model, commands
and views belong side by side.

The 0027 page also conflated two things its own ADR kept calling
different names: the *pure* fold of a message over the domain model
(Elm's update), and the *side effects* needed around it (reads to
build the model, writes to persist the outcome). Both lived in one
`update/4` clause. What was missing is the classic imperative-shell/
functional-core split — in Rails terms, a controller layer: the
controller runs side effects and **composes domain messages that the
pure model folds over**. And there was no designated place for
cross-feature concerns (logging, auth) at all.

## Decision 1: group by feature

```
app/
  guestbook/
    controller.pl   the boundary: routes + actions; orchestrates the rest
    messages.pl     HTTP intent vocabulary: form declarations, decoders
    model.pl        the pure domain core: update(DomainMsg, M0, M) — no
                    prologex imports, no db, no env, ever
    commands.pl     every side effect, reads and writes, named as verbs
    views.pl        templates
  adrs/
    controller.pl
    commands.pl     (this feature's side effects are file reads)
    views.pl
  shared/           cross-feature concerns: layout.pl, middleware.pl
config/
  app.pl
```

Only `controller.pl` is required; a feature grows the other files
when it earns them (the `ui` feature is a single controller over
px_ui's demo registry). Module names are `<feature>_<role>`
(`guestbook_model`, `adrs_views`); `app/shared/` modules name
themselves. Boot (adr/0027's conventions otherwise unchanged) loads
`app/shared/` first, then every feature directory; imports between
app files use the `app` alias (adr/0030):

```prolog
:- use_module(app(guestbook/model)).
:- use_module(app(guestbook/commands)).
```

## Decision 2: the controller layer

A controller declares its pages — named actions on paths — and
implements the adr/0027 cycle *per action*:

```prolog
:- module(guestbook_controller, []).
:- use_module(library(prologex)).
:- use_module(app(guestbook/messages), []).   % forms register on load
:- use_module(app(guestbook/model), [empty/1, loaded/3]).
                                              % update/3 stays qualified:
                                              % the DOMAIN fold, distinct
                                              % from px_query's update/3
:- use_module(app(guestbook/commands)).
:- use_module(app(guestbook/views), []).      % templates register on load

:- page(index, "/comments").                  % helper: guestbook_path

model(index, _Env, M) :-                      % side effect: read...
    load_comments(Comments),
    empty(M0),
    loaded(Comments, M0, M).                  % ...folded by the pure core

view(index, M, guestbook_view(M)).

%% The controller's update/4 is the imperative shell: it runs
%% commands (side effects) and composes DOMAIN messages; the pure
%% model folds them. Response effects stay data (adr/0027).
update(sign(ok(Values)), M0, M,
       [ redirect(guestbook_path),
         turbo([prepend(comments, comment_card(Comment))]) ]) :-
    save_comment(Values, Comment),                       % command
    guestbook_model:update(signed(Comment), M0, M).      % pure fold
update(sign(invalid(Values, Errors)), M0, M, [status(422)]) :-
    guestbook_model:update(rejected(Values, Errors), M0, M).
```

The pure core it drives:

```prolog
:- module(guestbook_model, [empty/1, loaded/3, update/3]).
%  No prologex import, no db, no env: loadable with nothing but SWI.

empty(m{comments: [], values: _{}, errors: []}).

loaded(Comments, M0, M) :- M = M0.put(comments, Comments).

update(signed(C), M0, M) :-
    M = M0.put(_{comments: [C|M0.comments], values: _{}, errors: []}).
update(rejected(Values, Errors), M0, M) :-
    M = M0.put(_{values: Values, errors: Errors}).
```

And the commands (the ONLY file that touches the database):

```prolog
:- module(guestbook_commands, [load_comments/1, save_comment/2]).
:- use_module(library(prologex)).

:- schema("create table if not exists comments (...)").

load_comments(Cs) :-
    findall(C, row(q(comments, [order_by(desc(id))]), C), Cs).

save_comment(Values, Comment) :-
    insert(comments, Values, Id),
    once(row(q(comments, [where(id == Id)]), Comment)).
```

The distinction the layering buys: `sign(ok(Values))` is an *HTTP
message* (intent, validated at the edge, adr/0027 decision 3);
`signed(Comment)` is a *domain message* (fact, composed by the
controller after the side effect succeeded). The model never sees
HTTP; the views never see the env; commands never see either.

`:- page(Action, Path)` and `:- page(Action, Path, [as(Name)])`
generalize adr/0027's single-page module: one controller, several
actions, contract predicates keyed by action —

    model(Action, Env, Model)      failure is still the 404
    view(Action, Model, Html)      pure
    update(Msg, Model0, Model, Effects)   messages are self-naming,
                                          so no action key
    msg(Env, Msg)                  optional custom decoder

Route + path-helper naming: `as(Name)` when given (`as(adr)` →
`adr_path/1`); otherwise `<feature>` for the index action and
`<feature>_<action>` for the rest, feature being the module name
minus `_controller`. Message decoding looks for `:- form` decls in
the controller *and* in `<feature>_messages` — the forms live with
the message vocabulary they define.

## Decision 3: shared/ is where cross-cutting lives

`app/shared/` holds what belongs to no feature: the layout
(adr/0027 decision 5 unchanged), and the middleware pipeline —
plain env relations (adr/0017) declared where the filesystem says
"cross-app concern":

```prolog
:- module(app_middleware, []).
:- use_module(library(prologex)).

:- pipeline([log_requests, method_override, route_dispatch,
             turbo_frames]).

log_requests(Env, Env) :-
    format(user_error, "~w ~w~n", [Env.method, Env.path]).
```

Auth, rate limiting, request ids follow the same shape: an env
relation in `shared/`, one line in the pipeline. A failing element
declines the request (adr/0017 fold semantics), which is exactly the
right primitive for auth.

## Consequences

A feature is one directory you can read top to bottom — and delete
in one `git rm`. The pure model is trivially testable (no db, no
env, no framework import to stub). The runtime is a rename of
adr/0027's: `px_controller.pl` replaces `px_page.pl`, the cycle and
effects unchanged, contract arity +1 for the action key. app/pages,
app/views and app/lib are retired; the demo app migrates as the
reference. Cost: five files where one page was — a feature the size
of `ui` rightly stays a lone controller.pl, and the ADR-browser
keeps commands+views+controller only; the full five-file shape is
for features with a real domain, and the guestbook demonstrates it.
