:- module(guestbook_model,
          [ empty/1,                % -Model
            loaded/3,               % +Comments, +Model0, -Model
            update/3                % +DomainMsg, +Model0, -Model
          ]).

/** <module> The guestbook's pure core (adr/0029): domain messages
fold over the model. No prologex import, no database, no env --
this module must stay loadable and testable with nothing but SWI.
*/

empty(m{comments: [], values: _{}, errors: []}).

loaded(Comments, M0, M) :-
    M = M0.put(comments, Comments).

update(signed(Comment), M0, M) :-
    M = M0.put(_{comments: [Comment|M0.comments],
                 values: _{}, errors: []}).
update(rejected(Values, Errors), M0, M) :-
    M = M0.put(_{values: Values, errors: Errors}).
