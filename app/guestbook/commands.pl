:- module(guestbook_commands,
          [ load_comments/1,        % -Comments
            save_comment/2          % +Values, -Comment
          ]).

/** <module> Every guestbook side effect, reads and writes, named as
verbs (adr/0029). The only file in the feature that touches the
database; the schema rides with it.
*/

:- use_module(library(prologex)).

:- schema("create table if not exists comments (
             id integer primary key,
             author text not null,
             body text not null,
             created_at text not null default current_timestamp)").

load_comments(Comments) :-
    findall(C,
            ( row(q(comments, [order_by(desc(id))]), R),
              project_comment(R, C) ),
            Comments).

save_comment(Values, Comment) :-
    insert(comments, Values, Id),
    once(row(q(comments, [where(id == Id)]), R)),
    project_comment(R, Comment).

%   A row is a pairs list (adr/0037); project it into a plain
%   comment/3 term so the view destructures named vars, never a row.
project_comment(R, comment(Author, Body, CreatedAt)) :-
    field(R, author, Author),
    field(R, body, Body),
    field(R, created_at, CreatedAt).
