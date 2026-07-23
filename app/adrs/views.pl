:- module(adrs_views, []).

/** <module> Decision-log templates (adr/0029): pure, model in,
markup out.
*/

:- use_module(library(prologex)).

home_view(adr_index(Slugs)) ~>
    layout("prologex — design decisions",
      [ h1("prologex — design decisions"),
        p("An experimental SWI-Prolog HTTP framework: llhttp and libuv bound via SWI's C FFI, a Rails-flavoured layer built on top in pure Prolog, and this page itself — rendered from the markdown decision log below by the framework's own markdown engine."),
        p([ link_to("Sign the guestbook →", guestbook_path),
            " · ",
            link_to("Component library →", ui_path)
          ]),
        ul(class("adr-list"), each(Slugs, adr_item))
      ]).

adr_item(Slug) ~>
    li(link_to(Slug, adr_path(Slug))).

adr_view(adr_page(Slug, Markdown)) ~>
    layout(Slug,
      [ p(class(back), link_to("← all decisions", home_path)),
        markdown(Markdown)
      ]).
