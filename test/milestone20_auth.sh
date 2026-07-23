#!/usr/bin/env bash
#
# test/milestone20_auth.sh -- proves adr/0035's px:auth generator end to
# end: `px generate feature px:auth` (prolog/px_gen_auth.pl's generate/0)
# writes app/auth/ and app/shared/auth.pl into a scratch app THROUGH THE
# REAL CLI, the generated code actually gates a protected feature, a real
# user signs in and out over real HTTP, and the "wrong credentials" path
# never leaks whether an email is registered.
#
# Steps:
#   1. Scratch app at /tmp/px_m20_app: `px new`, `px generate feature
#      posts`, `px generate feature px:auth` -- all through bin/px, the
#      same CLI a user would type. (The dispatch is `generate feature
#      px:auth`, not `generate px:auth` -- px:NAME generators are a
#      special case of feature generation, per px_cli.pl's own dispatch;
#      this script uses the command that actually works.)
#   2. Wire the ONE line the generator asks for into app/shared/
#      middleware.pl (sed) -- the scratch app is this test's to edit
#      freely, unlike the framework repo itself.
#   3. Uncomment the CRUD scaffold's own commented authorize/2 block in
#      app/posts/controller.pl (python, exact-block replace) -- the
#      generator's own printed next-steps text matches this block
#      verbatim, so uncommenting it IS following those instructions.
#   4. Create a user via the exact documented console incantation,
#      scripted with `bin/px console`'s stdin toplevel (no shortcuts
#      through undocumented internals).
#   5. Boot the scratch app on port 8171 (never 8090/8091, never the
#      systemd unit) and drive the whole flow with curl: public GET,
#      the denied-hook redirect, the generic-error wrong-password 422
#      with no cookie leaked, a real sign-in with a real set-cookie,
#      the now-authorized GET and a real POST behind it, sign-out with
#      an expiring cookie, and the dead cookie bouncing back to sign-in.
#   6. PASS/FAIL lines for every check, exit code reflects the summary,
#      cleanup by the exact PID this script started -- no pkill, ports
#      8090/8091 and the systemd prologex unit are never touched.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT=8171
APP_DIR=/tmp/px_m20_app

WORKDIR=$(mktemp -d)
SERVER_LOG="$WORKDIR/server.log"
GEN_LOG="$WORKDIR/generate.log"
CONSOLE_LOG="$WORKDIR/console.log"

cleanup() {
  # Best-effort: kill the exact server PID if still running, then remove
  # every /tmp artifact this script created. No pkill -- only the one PID
  # this script itself started.
  if [ -n "${SERVER_PID:-}" ]; then
    kill -0 "$SERVER_PID" 2>/dev/null && kill -KILL "$SERVER_PID" 2>/dev/null
  fi
  rm -rf "$WORKDIR" "$APP_DIR"
}
trap cleanup EXIT

PASS=0
FAIL=0
report() {
  local status="$1" name="$2" detail="${3:-}"
  if [ "$status" = "PASS" ]; then
    PASS=$((PASS + 1))
    printf 'PASS: %s\n' "$name"
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s%s\n' "$name" "${detail:+ -- $detail}"
  fi
}

bail() {
  echo "----"
  echo "Summary: $PASS passed, $FAIL failed ($1)"
  exit 1
}


# === 1. SCAFFOLD, THROUGH THE REAL CLI ===================================

rm -rf "$APP_DIR"
mkdir -p "$(dirname "$APP_DIR")"

(
  cd "$(dirname "$APP_DIR")" &&
  "$REPO/bin/px" new "$(basename "$APP_DIR")"
) > "$GEN_LOG" 2>&1
if [ -d "$APP_DIR" ]; then
  report PASS "bin/px new scaffolds $APP_DIR"
else
  report FAIL "bin/px new scaffolds $APP_DIR" "log follows"
  cat "$GEN_LOG"
  bail "px new failed"
fi

( cd "$APP_DIR" && "$REPO/bin/px" generate feature posts ) >> "$GEN_LOG" 2>&1
if [ -f "$APP_DIR/app/posts/controller.pl" ]; then
  report PASS "bin/px generate feature posts scaffolds app/posts/"
else
  report FAIL "bin/px generate feature posts scaffolds app/posts/" "log follows"
  cat "$GEN_LOG"
  bail "feature scaffold failed"
fi

( cd "$APP_DIR" && "$REPO/bin/px" generate feature px:auth ) >> "$GEN_LOG" 2>&1
GEN_STATUS=$?
if [ "$GEN_STATUS" -eq 0 ] && [ -f "$APP_DIR/app/auth/controller.pl" ] \
   && [ -f "$APP_DIR/app/auth/commands.pl" ] && [ -f "$APP_DIR/app/auth/model.pl" ] \
   && [ -f "$APP_DIR/app/auth/messages.pl" ] && [ -f "$APP_DIR/app/auth/views.pl" ] \
   && [ -f "$APP_DIR/app/shared/auth.pl" ]; then
  report PASS "bin/px generate feature px:auth writes all six files"
else
  report FAIL "bin/px generate feature px:auth writes all six files" \
    "status $GEN_STATUS -- log follows"
  cat "$GEN_LOG"
  bail "px:auth generator failed"
fi

if grep -q "auth:authenticate" "$GEN_LOG" && grep -q "auth_commands:create_user" "$GEN_LOG" \
   && grep -q "authorize(_,     Env) :- require_user(Env)." "$GEN_LOG"; then
  report PASS "generator prints the three next steps (pipeline, console, authorize)"
else
  report FAIL "generator prints the three next steps (pipeline, console, authorize)" \
    "expected text not found in log"
fi

# Refuses to overwrite an existing app/auth.
( cd "$APP_DIR" && "$REPO/bin/px" generate feature px:auth ) > "$WORKDIR/regen.log" 2>&1
REGEN_STATUS=$?
if [ "$REGEN_STATUS" -ne 0 ] && grep -qi "already exists" "$WORKDIR/regen.log"; then
  report PASS "generator refuses to overwrite an existing app/auth"
else
  report FAIL "generator refuses to overwrite an existing app/auth" \
    "status $REGEN_STATUS -- log follows"
  cat "$WORKDIR/regen.log"
fi


# === 2. WIRE THE PIPELINE (the scratch app is ours to edit) ==============

sed -i 's/:- pipeline(\[ log_requests,/:- pipeline([ log_requests,\n              auth:authenticate,/' \
  "$APP_DIR/app/shared/middleware.pl"

if grep -q "auth:authenticate" "$APP_DIR/app/shared/middleware.pl"; then
  report PASS "authenticate wired into app/shared/middleware.pl"
else
  report FAIL "authenticate wired into app/shared/middleware.pl"
  bail "pipeline edit failed"
fi


# === 3. PROTECT THE POSTS FEATURE (uncomment the scaffold's own block) ===

python3 - "$APP_DIR/app/posts/controller.pl" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    s = f.read()

commented = """%   :- use_module(app(shared/auth), [require_user/1]).
%
%   authorize(index, _Env).                        %% anyone
%   authorize(show,  _Env).                        %% anyone
%   authorize(_,     Env) :- require_user(Env).    %% new/edit + every write"""

uncommented = """:- use_module(app(shared/auth), [require_user/1]).

authorize(index, _Env).                        %% anyone
authorize(show,  _Env).                        %% anyone
authorize(_,     Env) :- require_user(Env).    %% new/edit + every write"""

if commented not in s:
    print("BLOCK NOT FOUND", file=sys.stderr)
    sys.exit(1)

with open(path, "w") as f:
    f.write(s.replace(commented, uncommented))
PYEOF
PATCH_STATUS=$?

if [ "$PATCH_STATUS" -eq 0 ] && grep -q "authorize(_,     Env) :- require_user(Env)." \
     "$APP_DIR/app/posts/controller.pl"; then
  report PASS "authorize/2 uncommented in app/posts/controller.pl"
else
  report FAIL "authorize/2 uncommented in app/posts/controller.pl"
  bail "authorize edit failed"
fi


# === 4. CREATE A USER, THE DOCUMENTED CONSOLE WAY =========================

( cd "$APP_DIR" &&
  echo 'auth_commands:create_user("you@example.com", "secret"), format("USER_CREATED~n"), halt.' \
    | timeout 20 "$REPO/bin/px" console
) > "$CONSOLE_LOG" 2>&1

if grep -q "USER_CREATED" "$CONSOLE_LOG"; then
  report PASS "auth_commands:create_user/2 works from bin/px console with no extra step"
else
  report FAIL "auth_commands:create_user/2 works from bin/px console with no extra step" \
    "log follows"
  cat "$CONSOLE_LOG"
  bail "console user creation failed"
fi


# === 5. BOOT AND DRIVE THE WHOLE FLOW =====================================

( cd "$APP_DIR" && PORT=$PORT "$REPO/bin/px" server ) > "$SERVER_LOG" 2>&1 &
SERVER_PID=$!

READY=0
for _ in $(seq 1 100); do
  if curl -s -o /dev/null -m 1 "http://127.0.0.1:$PORT/posts"; then
    READY=1
    break
  fi
  kill -0 "$SERVER_PID" 2>/dev/null || break
  sleep 0.1
done

if [ "$READY" -ne 1 ]; then
  report FAIL "scratch app boots and starts serving on port $PORT" "never answered -- log follows"
  cat "$SERVER_LOG"
  bail "server did not start"
fi
report PASS "scratch app (PID $SERVER_PID) boots and starts serving on port $PORT"

# --- GET /posts : public --------------------------------------------------

code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/posts" || echo 000)
if [ "$code" = "200" ]; then
  report PASS "GET /posts -> 200 (public)"
else
  report FAIL "GET /posts -> 200 (public)" "got HTTP $code"
fi

# --- GET /posts/new with no cookie : denied hook redirects to sign-in ----

DENY_HDRS="$WORKDIR/deny.headers"
code=$(curl -s -m 5 -D "$DENY_HDRS" -o /dev/null -w '%{http_code}' \
  "http://127.0.0.1:$PORT/posts/new" || echo 000)
if [ "$code" = "303" ] && grep -qi '^location: */session/new' "$DENY_HDRS"; then
  report PASS "GET /posts/new (signed out) -> 303 to /session/new (denied hook)"
else
  report FAIL "GET /posts/new (signed out) -> 303 to /session/new (denied hook)" \
    "got HTTP $code -- headers follow"
  cat "$DENY_HDRS"
fi

# --- GET /session/new : the sign-in page ----------------------------------

code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/session/new" || echo 000)
if [ "$code" = "200" ]; then
  report PASS "GET /session/new -> 200"
else
  report FAIL "GET /session/new -> 200" "got HTTP $code"
fi

# --- POST wrong password : 422, generic error, no cookie ------------------

BAD_HDRS="$WORKDIR/bad.headers"
BAD_BODY="$WORKDIR/bad.body"
code=$(curl -s -m 5 -D "$BAD_HDRS" -o "$BAD_BODY" -w '%{http_code}' -X POST \
  --data-urlencode "_msg=sign_in" \
  --data-urlencode "email=you@example.com" \
  --data-urlencode "password=wrongpassword" \
  "http://127.0.0.1:$PORT/session/new" || echo 000)

if [ "$code" = "422" ]; then
  report PASS "POST wrong password -> 422"
else
  report FAIL "POST wrong password -> 422" "got HTTP $code"
fi

if grep -qi "email or password is incorrect" "$BAD_BODY"; then
  report PASS "POST wrong password -> generic 'email or password is incorrect' error"
else
  report FAIL "POST wrong password -> generic 'email or password is incorrect' error" \
    "body follows"
  cat "$BAD_BODY"
fi

if grep -qi '^set-cookie:' "$BAD_HDRS"; then
  report FAIL "POST wrong password -> NO set-cookie" "a cookie was set -- headers follow"
  cat "$BAD_HDRS"
else
  report PASS "POST wrong password -> NO set-cookie"
fi

# --- POST correct credentials : 303 + set-cookie --------------------------

GOOD_HDRS="$WORKDIR/good.headers"
code=$(curl -s -m 5 -D "$GOOD_HDRS" -o /dev/null -w '%{http_code}' -X POST \
  --data-urlencode "_msg=sign_in" \
  --data-urlencode "email=you@example.com" \
  --data-urlencode "password=secret" \
  "http://127.0.0.1:$PORT/session/new" || echo 000)

COOKIE=$(grep -i '^set-cookie:' "$GOOD_HDRS" | sed -E 's/^[Ss]et-[Cc]ookie: *([^;]+);.*/\1/' | tr -d '\r')

if [ "$code" = "303" ] && [[ "$COOKIE" == px_session=* ]]; then
  report PASS "POST correct credentials -> 303 with set-cookie px_session=... ($COOKIE)"
else
  report FAIL "POST correct credentials -> 303 with set-cookie px_session=..." \
    "got HTTP $code -- headers follow"
  cat "$GOOD_HDRS"
fi

# --- GET /posts/new WITH the cookie : now authorized ----------------------

if [ -n "$COOKIE" ]; then
  code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' -H "Cookie: $COOKIE" \
    "http://127.0.0.1:$PORT/posts/new" || echo 000)
  if [ "$code" = "200" ]; then
    report PASS "GET /posts/new WITH the session cookie -> 200"
  else
    report FAIL "GET /posts/new WITH the session cookie -> 200" "got HTTP $code"
  fi
else
  report FAIL "GET /posts/new WITH the session cookie -> 200" "no cookie captured"
fi

# --- POST create article WITH the cookie -----------------------------------

if [ -n "$COOKIE" ]; then
  code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' -H "Cookie: $COOKIE" -X POST \
    --data-urlencode "_msg=create_post" \
    --data-urlencode "title=milestone20 article" \
    --data-urlencode "body=proving px:auth end to end" \
    "http://127.0.0.1:$PORT/posts/new" || echo 000)
  if [ "$code" = "303" ]; then
    report PASS "POST create article WITH the session cookie -> 303"
  else
    report FAIL "POST create article WITH the session cookie -> 303" "got HTTP $code"
  fi
else
  report FAIL "POST create article WITH the session cookie -> 303" "no cookie captured"
fi

# --- POST sign_out WITH the cookie : 303 + expiring cookie -----------------

SIGNOUT_HDRS="$WORKDIR/signout.headers"
if [ -n "$COOKIE" ]; then
  code=$(curl -s -m 5 -D "$SIGNOUT_HDRS" -o /dev/null -w '%{http_code}' -H "Cookie: $COOKIE" -X POST \
    --data-urlencode "_msg=sign_out" \
    "http://127.0.0.1:$PORT/session/new" || echo 000)
  if [ "$code" = "303" ] && grep -qi '^set-cookie:.*Max-Age=0' "$SIGNOUT_HDRS"; then
    report PASS "POST sign_out WITH the cookie -> 303 with an expiring set-cookie"
  else
    report FAIL "POST sign_out WITH the cookie -> 303 with an expiring set-cookie" \
      "got HTTP $code -- headers follow"
    cat "$SIGNOUT_HDRS"
  fi
else
  report FAIL "POST sign_out WITH the cookie -> 303 with an expiring set-cookie" "no cookie captured"
fi

# --- GET /posts/new with the now-dead cookie : denied again ----------------

if [ -n "$COOKIE" ]; then
  DEAD_HDRS="$WORKDIR/dead.headers"
  code=$(curl -s -m 5 -D "$DEAD_HDRS" -o /dev/null -w '%{http_code}' -H "Cookie: $COOKIE" \
    "http://127.0.0.1:$PORT/posts/new" || echo 000)
  if [ "$code" = "303" ] && grep -qi '^location: */session/new' "$DEAD_HDRS"; then
    report PASS "GET /posts/new with the dead cookie -> 303 to sign-in again"
  else
    report FAIL "GET /posts/new with the dead cookie -> 303 to sign-in again" \
      "got HTTP $code -- headers follow"
    cat "$DEAD_HDRS"
  fi
else
  report FAIL "GET /posts/new with the dead cookie -> 303 to sign-in again" "no cookie captured"
fi


# === 6. SHUTDOWN AND CLEANUP (best-effort; exact PID only) ================

kill -TERM "$SERVER_PID" 2>/dev/null
( sleep 10; kill -KILL "$SERVER_PID" 2>/dev/null ) &
WATCHDOG_PID=$!
wait "$SERVER_PID" 2>/dev/null
kill "$WATCHDOG_PID" 2>/dev/null
wait "$WATCHDOG_PID" 2>/dev/null
unset SERVER_PID   # already reaped -- cleanup's best-effort kill is now a no-op

sleep 0.2
if ss -ltn 2>/dev/null | grep -q ":$PORT "; then
  report FAIL "port $PORT released after shutdown"
else
  report PASS "port $PORT released after shutdown"
fi

echo "----"
echo "server log:"
cat "$SERVER_LOG" 2>/dev/null
echo "----"
echo "Summary: $PASS passed, $FAIL failed"

if [ "$FAIL" -eq 0 ]; then
  exit 0
else
  exit 1
fi
