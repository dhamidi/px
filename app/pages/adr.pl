:- module(adr, []).

/** <module> GET /adr/:id -- one rendered decision. An unknown slug
fails model/2, which IS the 404 (adr/0027 decision 2).
*/

:- use_module(library(prologex)).
:- use_module(lib(adrs)).

:- page("/adr/:id").

model(Env, m{slug: Slug, markdown: Markdown}) :-
    Slug = Env.params.id,
    adr_markdown(Slug, Markdown).

view(M, layout(M.slug,
  [ p(class(back), link_to("← all decisions", home_path)),
    markdown(M.markdown)
  ])).
