# 0035. px:auth — authentication is generated, not mounted

Status: Accepted

## Context

The blog demo made it obvious: every visitor sees Edit/Delete and
can post them. The framework had no session story at all — no
cookies, no users, no way for a controller to say "not you".

Rails 8 settled the design argument for us: authentication should
not be a mountable engine or a framework module you configure — it
should be a *generator* that writes ordinary application code you
then own, read, and modify (`rails generate authentication`). The
`px:` prefix marks generators that ship with the framework:
`px generate px:auth` — distributed by us, but the result is YOUR
code, in your `app/`, following the same feature shape as everything
else (adr/0029), self-documenting per adr/0032's scaffold rules
(teaching comments, no framework-internal references).

## Decision 1: the small framework surface auth actually needs

Three primitives land in the framework proper — they are transport
concerns, not auth policy:

1. **Cookies**: `px_env:cookie/3` reads a named cookie from the
   request's cookie header; setting one is just the existing
   `header("set-cookie", ...)` response option.
2. **Redirects with headers**: `px_env:redirect/4` (Opts with
   `header(N,V)`), and the effects vocabulary (adr/0027 decision 4)
   gains `header(N, V)` — so an update can answer
   `[redirect(home_path), header("set-cookie", ...)]`. Sign-in and
   sign-out are exactly that shape.
3. **The authorize hook**: a controller MAY define `authorize/2`;
   when defined, failure asks the multifile hook
   `px_controller:denied/2` to answer (403 by default; generated
   auth code overrides it with a redirect to the sign-in page). GET
   pages authorize on the ACTION (an atom); messages authorize on
   the decoded MESSAGE TERM (a compound) — one predicate, clause
   shape selects. The distinction is load-bearing, discovered by a
   real bypass during integration: write messages post to the paths
   of pages that are often public (destroy posts to show, per the
   scaffold's own form-posts-where-it-renders convention), so
   guarding by action alone waves a forged write through a public
   page. A catch-all `authorize(_, Env) :- require_user(Env)`
   guards both dimensions; a public message is opened by shape
   (`authorize(create_comment(_), _).`). No hook defined =
   everything public, exactly as today.

## Decision 2: what px:auth generates

An `app/auth/` feature plus one shared middleware file — sqlite3-
backed, session-per-row like Rails 8 (revocable server-side, no
stateful JWT nonsense):

    app/auth/
      controller.pl   GET /session/new (sign-in page),
                      sign_in/sign_out messages
      messages.pl     the sign_in form (email + password)
      model.pl        pure
      commands.pl     users + sessions tables; create_user/2,
                      verify_user/3 (crypto_password_hash — bcrypt-
                      class, constant-time verify), create_session/2
                      + a 128-bit random token, drop_session/1,
                      session_user/2
      views.pl        sign-in page; sign_out_button partial any
                      layout can embed
    app/shared/auth.pl
      authenticate/2  middleware: cookie -> session row -> user,
                      Env.put(user, ...) or user: none; NEVER fails
                      (resolving identity is not authorization)
      current_user/2, signed_in/1   helpers for models
      px_controller:denied/2        the redirect-to-sign-in override

The generator prints the ONE manual step (add `authenticate` to the
pipeline in app/shared/middleware.pl before route_dispatch) rather
than editing a file the user owns. There is no registration page and
no password reset — Rails 8 ships the same way (users are created
from the console: `auth_commands:create_user(Email, Password)`);
reset needs a mailer story the framework does not have, and a
registration page is app policy, one `px generate feature` away.

## Decision 3: scaffolds and demos gate their admin actions

The CRUD scaffold (adr/0032) ships the guards commented, with exact
uncomment instructions: `authorize/2` keeping index/show public and
everything else signed-in-only, plus the view-gating recipe (the
model copies the signed-in flag, views clause-select on it — admin
actions render only for a signed-in user, and pure views stay
pure). The blog demo runs the full shape live: guards on, admin
links hidden from readers, a seeded user to sign in with.

## Consequences

Auth is one generate away, arrives as readable code in the app's own
style, and the framework's only lasting commitments are cookies,
redirect headers, and one guard hook — primitives any other
authorization scheme (API tokens, OAuth callback) can also build on.
The cost of generate-don't-mount is the known Rails 8 trade: apps
that generated auth long ago won't get fixes by upgrading the
framework. That is the deliberate deal: code you own beats code you
configure.
