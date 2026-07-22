:- module(px_ui, [demo/3, ui_index/2, ui_show/2]).

/** <module> px_ui -- the built-in component library (adr/0026).

Loads every component module under prolog/ui/ and hosts the
kitchen-sink demo registry. A component module declares
`px_ui:demo(Name, Order, TemplateCall)` and its demo appears at
/ui/<Name> automatically; /ui lists them all in Order.
*/

:- use_module(px_env, [respond/3, not_found/2]).
:- use_module(px_template).

:- multifile demo/3.
:- dynamic demo/3.

%   Load all component modules. Each is optional: the library grows
%   file by file (adr/0026 rule 1); a missing directory is fine.
:- prolog_load_context(directory, Here),
   atomic_list_concat([Here, '/ui'], UiDir),
   (   exists_directory(UiDir)
   ->  directory_files(UiDir, Files),
       forall(( member(F, Files), file_name_extension(_, pl, F) ),
              ( atomic_list_concat([UiDir, '/', F], Path),
                use_module(Path)
              ))
   ;   true
   ).

%%  Handlers for the kitchen-sink app (routes declared by the app).

ui_index(Env0, Env) :-
    findall(Order-Name, demo(Name, Order, _), Pairs0),
    sort(Pairs0, Pairs),
    findall(N, member(_-N, Pairs), Names),
    respond(Env0, ui_index_view(Names), Env).

ui_show(Env0, Env) :-
    Name = Env0.params.name,
    atom_string(NameA, Name),
    (   demo(NameA, _, Call)
    ->  respond(Env0, ui_show_view(NameA, Call), Env)
    ;   not_found(Env0, Env)
    ).

ui_index_view(Names) ~>
    layout("px_ui — components",
      [ h1("px_ui component library"),
        p("Every component ships with a live demo (adr/0026)."),
        ul(class("adr-list"), each(Names, ui_index_item))
      ]).

ui_index_item(Name) ~>
    li(link_to(Name, path_for(ui_show, [name=Name]))).

ui_show_view(Name, Call) ~>
    layout(Name,
      [ p(class(back), link_to("← all components", "/ui")),
        h1(Name),
        div(class("ui-demo"), Call)
      ]).
