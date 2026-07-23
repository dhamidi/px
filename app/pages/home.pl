:- module(home, []).

/** <module> GET / -- the decision log index (adr/0027 reference page:
model builds everything, view is pure).
*/

:- use_module(library(prologex)).
:- use_module(lib(adrs)).

:- page("/").

model(_Env, m{slugs: Slugs}) :-
    adr_slugs(Slugs).

view(M, layout("prologex — design decisions",
  [ h1("prologex — design decisions"),
    p("An experimental SWI-Prolog HTTP framework: llhttp and libuv bound via SWI's C FFI, a Rails-flavoured layer built on top in pure Prolog, and this page itself — rendered from the markdown decision log below by the framework's own markdown engine."),
    p([ link_to("Sign the guestbook →", guestbook_path),
        " · ",
        link_to("Component library →", "/ui")
      ]),
    ul(class("adr-list"), each(M.slugs, adr_item))
  ])).

adr_item(Slug) ~>
    li(link_to(Slug, adr_path(Slug))).
