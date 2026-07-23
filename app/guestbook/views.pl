:- module(guestbook_views, []).

/** <module> Guestbook templates (adr/0029): pure, model in, markup
out; they never see the env.
*/

:- use_module(library(prologex)).

guestbook_view(M) ~>
    layout("Guestbook — prologex",
      [ p(class(back), link_to("← all decisions", home_path)),
        h1("Guestbook"),
        turbo_frame(comments, each(M.comments, comment_card)),
        h2("Sign the guestbook"),
        form_for(sign, guestbook_path, M.values, M.errors)
      ]).

comment_card(C) ~>
    article(class(card),
      [ p(strong(C.author)),
        p(C.body),
        p(small(C.created_at))
      ]).
