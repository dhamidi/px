:- module(guestbook, []).

/** <module> The guestbook (adr/0027 reference page for messages):
the sqlite-backed proof of the full stack -- schema and form ride
with the page, `sign` messages arrive pre-validated, effects drive
the Turbo-or-redirect response.
*/

:- use_module(library(prologex)).

:- page("/comments").

%   The table rides with the page that owns it, applied once per
%   worker connection right after the database opens.
:- schema("create table if not exists comments (
             id integer primary key,
             author text not null,
             body text not null,
             created_at text not null default current_timestamp)").

%   The form's name is the message name (adr/0027 decision 3):
%   posting it delivers sign(ok(Values)) or sign(invalid(Values,
%   Errors)) to update/4 below.
:- form(sign,
     [ field(author, text,     [required, max_length(80)]),
       field(body,   textarea, [required, max_length(1000)])
     ]).

model(_Env, m{comments: Comments, values: _{}, errors: []}) :-
    findall(C, row(q(comments, [order_by(desc(id))]), C), Comments).

view(M, layout("Guestbook — prologex",
  [ p(class(back), link_to("← all decisions", home_path)),
    h1("Guestbook"),
    turbo_frame(comments, each(M.comments, comment_card)),
    h2("Sign the guestbook"),
    form_for(sign, guestbook_path, M.values, M.errors)
  ])).

update(sign(ok(Values)), M, M,
       [ redirect(guestbook_path),
         turbo([prepend(comments, comment_card(Comment))]) ]) :-
    insert(comments, Values, Id),
    once(row(q(comments, [where(id == Id)]), Comment)).
update(sign(invalid(Values, Errors)), M0, M, [status(422)]) :-
    M = M0.put(_{values: Values, errors: Errors}).

comment_card(C) ~>
    article(class(card),
      [ p(strong(C.author)),
        p(C.body),
        p(small(C.created_at))
      ]).
