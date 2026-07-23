:- module(px_gen_auth, [generate/0]).

/** <module> `px generate px:auth` (adr/0035): a framework generator
that writes an ordinary `app/auth/` feature plus one shared middleware
file into the app in cwd -- sqlite-backed, session-per-row, following
the same feature shape (adr/0029) as everything `px generate feature`
produces. Once written, the code is the app's own: this module never
runs again at request time, and the app can edit every line.

Per adr/0032's scaffold rules (loaded here, not restated in the
templates below): generated files are SELF-DOCUMENTING WORKING code,
comments teach conventions in plain language, and generated output
never references ADRs or any framework-internal document -- only this
module's OWN comments (for framework contributors) get to do that.

Loaded on demand by px_cli's `px generate px:NAME` dispatch, run with
cwd already the app root; exposes generate/0.
*/

:- use_module(library(filesex)).

%!  generate is det.
%
%   Refuse to run over an existing app/auth or app/shared/auth.pl (a
%   previous generate, or an app that already rolled its own), write
%   the six files, print the three manual steps exactly once.

generate :-
    (   exists_directory('app/auth')
    ->  format(user_error,
               "px: app/auth already exists -- remove it first if you really want to regenerate~n", []),
        halt(1)
    ;   exists_file('app/shared/auth.pl')
    ->  format(user_error,
               "px: app/shared/auth.pl already exists -- remove it first if you really want to regenerate~n", []),
        halt(1)
    ;   true
    ),
    make_directory_path('app/auth'),
    forall(auth_file(Rel, TemplateGoal),
           ( call(TemplateGoal, Content),
             directory_file_path('app/auth', Rel, Path),
             write_file(Path, Content),
             format("  create app/auth/~w~n", [Rel])
           )),
    tpl_shared_auth(SharedContent),
    write_file('app/shared/auth.pl', SharedContent),
    format("  create app/shared/auth.pl~n", []),
    print_next_steps.

write_file(Path, Content) :-
    setup_call_cleanup(open(Path, write, S),
                       write(S, Content),
                       close(S)).

auth_file('commands.pl',  tpl_auth_commands).
auth_file('model.pl',     tpl_auth_model).
auth_file('messages.pl',  tpl_auth_messages).
auth_file('views.pl',     tpl_auth_views).
auth_file('controller.pl', tpl_auth_controller).


		 /*******************************
		 *        NEXT STEPS            *
		 *******************************/

%   generate/0's whole manual-step contract (adr/0035 decision 2):
%   print the ONE thing this generator cannot safely do for the app
%   (edit a file the app owns) plus the two things every app needs to
%   do next -- create a user, and protect something.

print_next_steps :-
    format("~n px:auth generated -- three things left, all manual on purpose:~n~n", []),
    format("1. Wire it into the request pipeline. Open app/shared/middleware.pl~n", []),
    format("   and add auth:authenticate between log_requests and route_dispatch:~n~n", []),
    format("       :- pipeline([ log_requests,~n", []),
    format("                     auth:authenticate,~n", []),
    format("                     method_override,~n", []),
    format("                     route_dispatch,~n", []),
    format("                     turbo_frames~n", []),
    format("                   ]).~n~n", []),
    format("   Every page's Env now carries Env.user -- a users row when the~n", []),
    format("   request's px_session cookie names a live session, or `none`.~n~n", []),
    format("2. Create a user. The database opens lazily on first use, and~n", []),
    format("   create_user/2 opens it itself, so this works straight from the~n", []),
    format("   console with no extra step:~n~n", []),
    format("       bin/px console~n", []),
    format("       ?- auth_commands:create_user(\"you@example.com\", \"secret\").~n~n", []),
    format("3. Protect a feature by defining authorize/2 in its controller.~n", []),
    format("   authorize/2, once defined AT ALL, gates EVERY action in that~n", []),
    format("   controller -- give every action a clause, even a catch-all one~n", []),
    format("   for the actions that stay public, or they will be denied~n", []),
    format("   instead. A CRUD feature scaffolded with `px generate feature`~n", []),
    format("   already carries this exact block, commented out, ready to~n", []),
    format("   uncomment once px:auth exists:~n~n", []),
    format("       :- use_module(app(shared/auth), [require_user/1]).~n~n", []),
    format("       authorize(index, _Env).                        %% anyone~n", []),
    format("       authorize(show,  _Env).                        %% anyone~n", []),
    format("       authorize(_,     Env) :- require_user(Env).    %% new/edit + all writes~n~n", []),
    format("   Pages authorize by ACTION (an atom); messages authorize by~n", []),
    format("   their decoded MESSAGE TERM (a compound) -- writes post to~n", []),
    format("   public pages' paths, so the catch-all guarding both shapes is~n", []),
    format("   what actually protects them. Open one message to everyone by~n", []),
    format("   shape: authorize(create_comment(_), _Env).~n~n", []),
    format("   A denied request redirects to the sign-in page (app/shared/~n", []),
    format("   auth.pl's px_controller:denied/2 override) instead of the~n", []),
    format("   framework's default 403.~n", []).


		 /*******************************
		 *          TEMPLATES           *
		 *******************************/

tpl_auth_commands(C) :-
    C = ':- module(auth_commands,
          [ create_user/2,      % +Email, +Password
            verify_user/3,      % +Email, +Password, -User
            create_session/2,   % +UserId, -Token
            drop_session/1,     % +Token
            session_user/2      % +Token, -User
          ]).

/** <module> Everything auth touches in the database: two tables
(users, sessions) and the verbs that read and write them. This is the
only file in the feature that touches storage; the schema rides with
it and is applied automatically when the database opens.

There is no sign-up page here on purpose: accounts are created from
the console (see the instructions this generator printed). Deciding
who is allowed to have one is a decision your app makes -- a
generator should not make it for you.

Passwords are never stored: crypto_password_hash/2 turns a password
into a salted, deliberately slow hash on the way in, and checks a
password against that hash on the way out -- plain SWI-Prolog, no
extra library to trust for the hashing itself.

Sessions are rows, not tokens carrying their own meaning (no JWTs
here): a session token is 128 random bits, and create_session/2 is
the only place that mints one. Signing out just deletes the row --
which is why a session can be revoked from the server side at all;
a signed token stays valid until it expires no matter what you do.
*/

:- use_module(library(prologex)).
:- use_module(library(crypto)).

:- schema("create table if not exists users (
             id integer primary key,
             email text not null unique,
             password_hash text not null,
             created_at text not null default current_timestamp)").

:- schema("create table if not exists sessions (
             id integer primary key,
             user_id integer not null references users(id),
             token text not null unique,
             created_at text not null default current_timestamp)").

%   A fixed hash to check a submitted password against when the email
%   does not match any user, so a wrong-email attempt costs exactly
%   the same crypto_password_hash/2 call as a wrong-password attempt.
%   Without this, timing alone would tell an attacker "no such user"
%   from "wrong password" -- verify_user/3 below always runs this
%   call, on the real hash when the user exists, on this one when it
%   does not, and only ever succeeds in the first case.
:- dynamic dummy_hash/1.
:- crypto_password_hash("not-a-real-password-only-used-for-timing", DummyHash),
   asserta(dummy_hash(DummyHash)).

%!  create_user(+Email, +Password) is det.
%
%   The only way an account gets made. Meant to be called from the
%   console:
%       bin/px console
%       ?- auth_commands:create_user("you@example.com", "secret").
%   The console has no database connection until something asks for
%   one -- prologex:ensure_db is exactly what a real request does on
%   its first query of each worker, and it is safe to call again even
%   when a connection already exists, so this predicate just asks for
%   its own instead of documenting a separate manual step.
create_user(Email, Password) :-
    prologex:ensure_db,
    crypto_password_hash(Password, Hash),
    insert(users, _{email: Email, password_hash: Hash}, _Id).

%!  verify_user(+Email, +Password, -User) is semidet.
%
%   User is the users row for Email when Password is correct; fails
%   for BOTH "no such email" and "wrong password", so a caller can
%   show one generic error and never leak which one it was.
%
%   crypto_password_hash/2 insists its Hash argument be an ATOM in
%   check mode -- a text column comes back from the database as a
%   STRING (like every other column in this framework), so atom_string/2
%   converts it right here, the one place that needs to know.
verify_user(Email, Password, User) :-
    (   once(row(q(users, [where(email == Email)]), Row))
    ->  atom_string(Hash, Row.password_hash),
        Found = true
    ;   dummy_hash(Hash),
        Found = false
    ),
    crypto_password_hash(Password, Hash),
    Found == true,
    User = Row.

%!  create_session(+UserId, -Token) is det.
%
%   128 random bits as lowercase hex -- enough that guessing one is
%   not a real attack. The row it lands in IS a signed-in session.
create_session(UserId, Token) :-
    crypto_n_random_bytes(16, Bytes),
    hex_bytes(Token, Bytes),
    insert(sessions, _{user_id: UserId, token: Token}, _Id).

%!  drop_session(+Token) is det.
%
%   Sign out: delete the row. A Token matching no row (already signed
%   out, or none at all) deletes zero rows -- not an error.
drop_session(Token) :-
    delete(sessions, token == Token).

%!  session_user(+Token, -User) is semidet.
%
%   The signed-in user for a session token, or fail -- an unknown or
%   already-dropped token is simply "not signed in", same as no
%   cookie at all.
session_user(Token, User) :-
    once(row(q(sessions, [where(token == Token)]), Session)),
    once(row(q(users, [where(id == Session.user_id)]), User)).
'.

tpl_auth_model(C) :-
    C = ':- module(auth_model,
          [ empty/1,     % -Model
            update/3     % +DomainMsg, +Model0, -Model
          ]).

/** <module> auth\'s pure core: what the feature KNOWS, no notion of
HTTP or storage. No prologex import, no database, no env, ever -- this
module must load and test with nothing but plain SWI-Prolog, the same
rule every feature\'s model.pl follows.

Only one domain message exists: a rejected sign-in attempt, whether
the form itself was incomplete or the credentials were wrong. Both
land here with the same shape as the CRUD scaffold\'s own
rejected(Values, Errors) -- refill the values, show the errors.
*/

empty(m{values: _{}, errors: []}).

update(rejected(Values, Errors), M0, M) :-
    M = M0.put(_{values: Values, errors: Errors}).
'.

tpl_auth_messages(C) :-
    C = ':- module(auth_messages, []).

/** <module> auth\'s messages: the sign-in form, and a fieldless
sign-out message that exists only so "sign out" arrives as a named
intent, the same way every other write does -- button_to (see
views.pl) renders a fieldless form as a single button.

Widgets: text textarea email password number checkbox select hidden.
Constraint vocabulary: required, max_length(N), min_length(N),
numeric, range(Lo, Hi), format(Regex), in(List), check(Pred).
*/

:- use_module(library(prologex)).

:- form(sign_in,
     [ field(email,    email,    [required]),
       field(password, password, [required])
     ]).

%   Carries no data -- button_to still needs a declared form to name
%   the message and validate it (trivially: no fields, always ok).
:- form(sign_out, []).
'.

tpl_auth_views(C) :-
    C = ':- module(auth_views, []).

/** <module> The sign-in page, and a partial ("sign_out_button") any
other view in the app can embed to show who is signed in and offer a
way to sign out. Templates are pure -- model in, markup out -- so
this file, like every views.pl, never touches the request.
*/

:- use_module(library(prologex)).

sign_in_new(M) ~>
    layout("Sign in",
      [ h1("Sign in"),
        form_for(sign_in, sign_in_path, M.values, M.errors)
      ]).

%   Embed this wherever a signed-in user should see who they are and
%   a way to sign out -- inside your layout, or a page\'s own view:
%       sign_out_button(M.user)
%   Only call it when M.user is a real user, not the atom `none` --
%   guard with signed_in(Env) (app/shared/auth.pl) in the page\'s own
%   model/3 and put the result in the Model, the same way every pure
%   view stays pure: it never checks the env itself.
sign_out_button(User) ~>
    p(class(actions),
      [ "Signed in as ", User.email, " ",
        button_to("Sign out", sign_out, sign_in_path)
      ]).
'.

tpl_auth_controller(C) :-
    C = ':- module(auth_controller, []).

/** <module> Sign-in and sign-out -- one page, two messages. Request
flow is the same cycle every controller uses:

    GET      model(Action, Env, Model) then view(Action, Model, Html)
    non-GET  model(Action, Env, M0)   then update(Msg, M0, M, Effects)

Two things about THIS controller are worth reading closely:

  - model/3 reads the px_session cookie itself, directly -- it needs
    the raw token (to know which session row a sign-out should
    delete), not the resolved user that the shared authenticate
    middleware puts on every Env once you wire it in.
  - "wrong password" and "form left blank" both end up re-rendering
    422 with the exact same generic error, but they are TWO DIFFERENT
    update(sign_in(ok(V)), ...) clauses below, not one clause with an
    if-then-else (there is no if-then-else inside a template, and
    update/4 is not one, but the same one-branch-per-clause habit pays
    off here too): the first clause verifies the credentials and, on
    success, commits with a cut so nothing falls through after it; if
    verify_user/3 fails, that clause\'s body simply fails and Prolog
    tries the next matching clause on its own -- no explicit \\+
    needed. A sign-in page must never reveal whether an email is even
    registered, which is exactly what sharing one error message buys.
*/

:- use_module(library(prologex)).
:- use_module(app(auth/messages), []).      % the sign_in / sign_out forms
:- use_module(app(auth/model), [empty/1]).  % the pure core; its update/3
                                  % is called qualified below, because
                                  % library(prologex) already provides
                                  % an update/3 (the SQL UPDATE)
:- use_module(app(auth/commands)).          % users + sessions, every read/write
:- use_module(app(auth/views), []).         % the templates

:- page(new, "/session/new", [as(sign_in)]).   %% sign_in_path

model(new, Env, M) :-
    ( px_env:cookie(Env, px_session, Token) -> true ; Token = none ),
    empty(M0),
    M = M0.put(token, Token).

view(new, M, sign_in_new(M)).

%   Correct credentials: start a session, set the cookie, go home.
update(sign_in(ok(V)), M0, M, Effects) :-
    verify_user(V.email, V.password, User),
    !,
    create_session(User.id, Token),
    format(string(Cookie), "px_session=~w; Path=/; HttpOnly; SameSite=Lax", [Token]),
    Effects = [redirect("/"), header("set-cookie", Cookie)],
    M = M0.
%   Wrong email or wrong password: verify_user/3 above failed, so
%   Prolog falls through to here -- same generic message either way.
update(sign_in(ok(V)), M0, M, [status(422)]) :-
    auth_model:update(rejected(V, [error(email, "email or password is incorrect")]), M0, M).

%   A blank email or password never reaches verify_user/3 at all --
%   the form declaration in messages.pl already rejected it, and this
%   is the same rejected/2 domain message with its own errors.
update(sign_in(invalid(V, E)), M0, M, [status(422)]) :-
    auth_model:update(rejected(V, E), M0, M).

%   Sign out: drop the session row (harmless if there was none to
%   drop) and hand back the same cookie name already expired
%   (Max-Age=0) so the browser clears it.
update(sign_out(ok(_)), M0, M0,
       [ redirect("/"),
         header("set-cookie",
                "px_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0")
       ]) :-
    drop_session(M0.token).
'.

tpl_shared_auth(C) :-
    C = ':- module(auth,
          [ authenticate/2,   % +Env0, -Env  (pipeline middleware)
            current_user/2,   % +Env, -User  (semidet)
            signed_in/1,      % +Env         (semidet)
            require_user/1    % +Env         (semidet; call from authorize/2)
          ]).

/** <module> WHO is making this request -- never WHETHER they are
allowed to do what they are asking; that is a different question,
answered per-feature by defining authorize/2 in a controller (see the
instructions this generator printed). Keeping the two separate is the
point of this file: authenticate/2 below NEVER fails, so it is safe to
run on every single request, including ones from nobody in particular.

Add it to the pipeline (app/shared/middleware.pl) and every page\'s Env
carries Env.user from then on: a real users row when the request\'s
px_session cookie names a live session, or the atom `none` otherwise.
*/

:- use_module(library(prologex)).
:- use_module(app(auth/commands), [session_user/2]).

%!  authenticate(+Env0, -Env) is det.
%
%   Cookie -> session row -> user, or `none`. This cannot decline:
%   px_env\'s pipeline treats a failing step as "skip it, Env flows on
%   unchanged" -- fine for a step that adds nothing, wrong for one
%   whose whole job is to guarantee Env.user is always readable by
%   whatever runs after it.
authenticate(Env0, Env) :-
    (   px_env:cookie(Env0, px_session, Token),
        session_user(Token, User)
    ->  Env = Env0.put(user, User)
    ;   Env = Env0.put(user, none)
    ).

%!  current_user(+Env, -User) is semidet.
%
%   Fails when nobody is signed in. User is the full users row --
%   INCLUDING password_hash -- so read only the fields a view needs
%   (User.email, User.id, ...); never render the whole dict.
current_user(Env, User) :-
    get_dict(user, Env, User),
    User \\== none.

%!  signed_in(+Env) is semidet.
signed_in(Env) :- current_user(Env, _).

%!  require_user(+Env) is semidet.
%
%   The one-liner a controller\'s authorize/2 calls: fails (denying
%   the request) exactly when nobody is signed in.
require_user(Env) :- current_user(Env, _).

%   The other half of the deal: when a controller\'s authorize/2
%   fails, px_controller asks this multifile hook to answer instead of
%   its default 403. Send the visitor to sign in.
:- multifile px_controller:denied/2.
px_controller:denied(Env0, Env) :-
    px_env:redirect(Env0, sign_in_path, Env).
'.
