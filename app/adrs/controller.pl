:- module(adrs_controller, []).

/** <module> The decision-log boundary (adr/0029): two read-only
actions over the same feature. An unknown slug fails model/3, which
IS the 404 (adr/0027 decision 2).
*/

:- use_module(library(prologex)).
:- use_module(app(adrs/commands)).
:- use_module(app(adrs/views), []).

:- page(index, "/",        [as(home)]).       % helper: home_path
:- page(show,  "/adr/:id", [as(adr)]).        % helper: adr_path(Id)

model(index, _Env, adr_index(Slugs)) :-
    adr_slugs(Slugs).
model(show, Env, adr_page(Slug, Markdown)) :-
    param(Env, id, Slug),                     % slug, not numeric: param/3
    adr_markdown(Slug, Markdown).

view(index, M, home_view(M)).
view(show,  M, adr_view(M)).
