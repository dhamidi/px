#!/usr/bin/env bash
#
# Milestone 23 (adr/0038): the development console + rich error page,
# and -- the load-bearing assertion -- that it is ABSENT in production.
#
# swipl ignores SIGTERM, so scratch servers are launched with a captured
# PID ($!) and killed by that exact PID only; never by command pattern
# (the live systemd services share the `prologex_run` command line).
set -u

PXHOME=/home/exedev/prologex
APP=/tmp/px_m23_app
DEV_PORT=8231
PROD_PORT=8232
PASS=0
FAIL=0
DEVPID=""
PRODPID=""

cleanup() {
    [ -n "$DEVPID" ] && kill -9 "$DEVPID" 2>/dev/null
    [ -n "$PRODPID" ] && kill -9 "$PRODPID" 2>/dev/null
    rm -rf "$APP" /tmp/px_m23_prod.db* 2>/dev/null
}
trap cleanup EXIT

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# --- scaffold a scratch app with a feature whose show model can fail
rm -rf "$APP"
"$PXHOME/bin/px" new "$APP" >/dev/null 2>&1
( cd "$APP" && "$PXHOME/bin/px" generate feature posts >/dev/null 2>&1 )

# ============ DEVELOPMENT ============
cd "$APP"
PORT=$DEV_PORT swipl -q -g prologex_run "$PXHOME/prolog/prologex.pl" >/tmp/px_m23_dev.log 2>&1 &
DEVPID=$!
cd "$PXHOME"
sleep 7

DEVPAGE=$(curl -s --max-time 6 "http://localhost:$DEV_PORT/posts/999")
DEVCODE=$(curl -s --max-time 6 -o /dev/null -w "%{http_code}" "http://localhost:$DEV_PORT/posts/999")
[ "$DEVCODE" = "404" ] && ok "dev model-fail is 404" || bad "dev model-fail code=$DEVCODE"
echo "$DEVPAGE" | grep -q "px-console" && ok "dev renders the rich diagnostic page" || bad "dev page not rich"
echo "$DEVPAGE" | grep -qi "model failed" && ok "dev classifies the failing stage (model failed)" || bad "dev did not classify"

TOKEN=$(echo "$DEVPAGE" | grep -oE 'token="[a-f0-9]+"' | grep -oE '[a-f0-9]{16,}' | head -1)
[ -n "$TOKEN" ] && ok "dev error page embeds a console token" || bad "no console token"

EVAL=$(curl -s --max-time 6 -d "token=$TOKEN&goal=X is 40 %2B 2" "http://localhost:$DEV_PORT/__px/console")
echo "$EVAL" | grep -q "42" && ok "dev console evaluates a goal" || bad "dev console eval: $EVAL"

NOAUTH=$(curl -s --max-time 6 -o /dev/null -w "%{http_code}" -d "goal=true" "http://localhost:$DEV_PORT/__px/console")
[ "$NOAUTH" = "403" ] && ok "dev console rejects a tokenless POST (403)" || bad "tokenless console code=$NOAUTH"

# The standalone console PAGE (GET) -- browsable, not just on errors.
PAGE=$(curl -s --max-time 6 "http://localhost:$DEV_PORT/__px/console")
echo "$PAGE" | grep -q "Development console" && ok "dev GET /__px/console renders the console page" || bad "dev console page missing"
PTOK=$(echo "$PAGE" | grep -oE 'token="[a-f0-9]+"' | grep -oE '[a-f0-9]{16,}' | head -1)
PEVAL=$(curl -s --max-time 6 -d "token=$PTOK&goal=X is 21 %2B 21" "http://localhost:$DEV_PORT/__px/console")
echo "$PEVAL" | grep -q "42" && ok "the page's own token evaluates a goal" || bad "console page eval: $PEVAL"

kill -9 "$DEVPID" 2>/dev/null; DEVPID=""
sleep 1

# ============ PRODUCTION (the security boundary) ============
cd "$APP"
PORT=$PROD_PORT PROLOGEX_ENV=production DATABASE_PATH=/tmp/px_m23_prod.db \
    swipl -q -g prologex_run "$PXHOME/prolog/prologex.pl" >/tmp/px_m23_prod.log 2>&1 &
PRODPID=$!
cd "$PXHOME"
sleep 7

PRODPAGE=$(curl -s --max-time 6 "http://localhost:$PROD_PORT/posts/999")
echo "$PRODPAGE" | grep -q "px-console" && bad "PRODUCTION LEAKS the diagnostic page" || ok "production serves NO diagnostic page"
echo "$PRODPAGE" | grep -q "404 Not Found" && ok "production serves the terse 404 body" || bad "production 404 body unexpected"

CONSCODE=$(curl -s --max-time 6 -o /dev/null -w "%{http_code}" -d "token=x&goal=true" "http://localhost:$PROD_PORT/__px/console")
[ "$CONSCODE" = "404" ] && ok "production console eval route is ABSENT (404, no attack surface)" || bad "PRODUCTION console eval reachable: code=$CONSCODE"

PAGECODE=$(curl -s --max-time 6 -o /dev/null -w "%{http_code}" "http://localhost:$PROD_PORT/__px/console")
[ "$PAGECODE" = "404" ] && ok "production console PAGE is ABSENT (404)" || bad "PRODUCTION console page reachable: code=$PAGECODE"

kill -9 "$PRODPID" 2>/dev/null; PRODPID=""

echo "----"
echo "Summary: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
