:- module(guestbook_controller, []).

/** <module> The guestbook boundary (adr/0029 reference feature):
runs commands (side effects) and composes domain messages the pure
model folds over; response effects stay data.
*/

:- use_module(library(prologex)).
:- use_module(app(guestbook/messages), []).   % forms register on load
:- use_module(app(guestbook/model), [empty/1, loaded/3]).
                                              % update/3 stays qualified:
                                              % the DOMAIN fold, distinct
                                              % from px_query's update/3
:- use_module(app(guestbook/commands)).
:- use_module(app(guestbook/views), []).      % templates register on load

:- page(index, "/comments").                  % helper: guestbook_path

model(index, _Env, M) :-
    load_comments(Comments),
    guestbook_model:empty(M0),
    guestbook_model:loaded(Comments, M0, M).

view(index, M, guestbook_view(M)).

%   sign(ok(Values)) is HTTP intent (validated at the edge);
%   signed(Comment) is the domain fact the command established.
update(sign(ok(Values)), M0, M,
       [ redirect(guestbook_path),
         turbo([prepend(comments, comment_card(Comment))]) ]) :-
    save_comment(Values, Comment),                       % command
    guestbook_model:update(signed(Comment), M0, M).      % pure fold
update(sign(invalid(Values, Errors)), M0, M, [status(422)]) :-
    guestbook_model:update(rejected(Values, Errors), M0, M).
