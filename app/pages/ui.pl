:- module(ui, []).

/** <module> GET /ui -- the px_ui kitchen sink (adr/0026). The
component library is framework surface; this page is the two-line
model/view over its demo registry.
*/

:- use_module(library(prologex)).

:- page("/ui").

model(_Env, m{names: Names}) :-
    findall(Order-Name, px_ui:demo(Name, Order, _), Pairs0),
    sort(Pairs0, Pairs),
    findall(N, member(_-N, Pairs), Names).

view(M, ui_index_view(M.names)).
