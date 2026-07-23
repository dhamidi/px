:- module(layout, []).

/** <module> The application layout (adr/0027 decision 5): every page
here and in px_ui's demos renders through layout/2. Defining it takes
ownership of the whole document -- so the viewport meta tag making
pages usable on phones lives here, not in a handler.
*/

:- use_module(library(prologex)).

layout(Title, Content) ~>
    [ raw("<!DOCTYPE html>\n"),
      html(
        [ head(
            [ meta(charset("utf-8")),
              meta([name(viewport), content("width=device-width, initial-scale=1")]),
              title(Title),
              stylesheet_tag("css/app.css"),
              stylesheet_tag("css/ui.css"),
              \javascript_importmap_tags
            ]),
          body(div(class(page), Content))
        ])
    ].
