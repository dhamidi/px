:- module(guestbook_model,
          [ empty/1,                % -Model
            loaded/3,               % +Comments, +Model0, -Model
            update/3                % +DomainMsg, +Model0, -Model
          ]).

/** <module> The guestbook's pure core (adr/0029): domain messages
fold over the model. No prologex import, no database, no env --
this module must stay loadable and testable with nothing but SWI.
*/

%   The model is a plain tagged compound guestbook(Comments, Values,
%   Errors): Comments the projected comment/3 terms, Values the form's
%   pairs list (empty on a clean form), Errors the error/2 list.
empty(guestbook([], [], [])).

loaded(Comments, guestbook(_, V, E), guestbook(Comments, V, E)).

update(signed(Comment), guestbook(Cs, _, _), guestbook([Comment|Cs], [], [])).
update(rejected(Values, Errors), guestbook(Cs, _, _), guestbook(Cs, Values, Errors)).
