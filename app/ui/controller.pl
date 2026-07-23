:- module(ui_controller, []).

/** <module> The px_ui kitchen sink (adr/0026) as an adr/0029
feature: a feature the size of one controller rightly stays one
file -- the views are px_ui's own, the "domain" is its demo
registry.
*/

:- use_module(library(prologex)).

:- page(index, "/ui").                        % route ui, helper ui_path
:- page(show,  "/ui/:name").                  % route ui_show

model(index, _Env, ui_index(Names)) :-
    findall(Order-Name, px_ui:demo(Name, Order, _), Pairs0),
    sort(Pairs0, Pairs),
    findall(N, member(_-N, Pairs), Names).
model(show, Env, ui_show(Name, Call)) :-
    param(Env, name, NameStr),
    atom_string(Name, NameStr),
    px_ui:demo(Name, _, Call).

view(index, ui_index(Names), ui_index_view(Names)).
view(show,  ui_show(Name, Call), ui_show_view(Name, Call)).
