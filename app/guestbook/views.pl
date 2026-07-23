:- module(guestbook_views, []).

/** <module> Guestbook templates (adr/0029): pure, model in, markup
out; they never see the env.
*/

:- use_module(library(prologex)).

guestbook_view(guestbook(Comments, Values, Errors)) ~>
    layout("Guestbook — prologex",
      [ p(class(back), link_to("← all decisions", home_path)),
        h1("Guestbook"),
        turbo_frame(comments, each(Comments, comment_card)),
        h2("Sign the guestbook"),
        form_for(sign, guestbook_path, Values, Errors)
      ]).

comment_card(comment(Author, Body, CreatedAt)) ~>
    article(class(card),
      [ p(strong(Author)),
        p(Body),
        p(small(CreatedAt))
      ]).
