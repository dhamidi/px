:- module(ui_controller, []).

/** <module> The px_ui kitchen sink (adr/0026) as an adr/0029
feature: a feature the size of one controller rightly stays one
file -- the views are px_ui's own, the "domain" is its demo
registry.
*/

:- use_module(library(prologex)).

:- page(index, "/ui").                        % route ui, helper ui_path
:- page(show,  "/ui/:name").                  % route ui_show

model(index, _Env, m{names: Names}) :-
    findall(Order-Name, px_ui:demo(Name, Order, _), Pairs0),
    sort(Pairs0, Pairs),
    findall(N, member(_-N, Pairs), Names).
model(show, Env, m{name: Name, call: Call}) :-
    atom_string(Name, Env.params.name),
    px_ui:demo(Name, _, Call).

view(index, M, ui_index_view(M.names)).
view(show,  M, ui_show_view(M.name, M.call)).
