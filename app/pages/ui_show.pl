:- module(ui_show, []).

/** <module> GET /ui/:name -- one px_ui component demo. The page is
named ui_show so px_ui's index template keeps resolving
path_for(ui_show, [name=N]) against this route.
*/

:- use_module(library(prologex)).

:- page("/ui/:name").

model(Env, m{name: Name, call: Call}) :-
    atom_string(Name, Env.params.name),
    px_ui:demo(Name, _, Call).

view(M, ui_show_view(M.name, M.call)).
