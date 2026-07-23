#!/usr/bin/env bash
#
# test/smoke.sh -- smoke-test a running prologex instance.
#
# Usage:
#   test/smoke.sh [BASE_URL]
#
# BASE_URL defaults to http://127.0.0.1:8090 (matching
# adr/0012-deployment-systemd-no-tls.md: the app listens on :8090,
# localhost-only, plain HTTP). Override via the first positional arg, e.g.:
#
#   test/smoke.sh https://cul-de-sac-rocker.exe.xyz
#
# Prints PASS/FAIL per check and exits 0 only if every applicable check
# passed.
#
# NOTE on the /adr/... path check below: the demo app (app/, adr/0027)
# did not exist yet when this script was written, so the exact URL shape
# for an individual ADR page is a guess based on the ADR filename
# convention (adr/0001-project-goals-and-layout.md). If the real router
# uses a different shape -- e.g. /adr/0001 instead of
# /adr/0001-project-goals-and-layout -- update the ADR_PATH variable below;
# that's the only line that should need to change.

set -u

BASE_URL="${1:-${SMOKE_BASE_URL:-http://127.0.0.1:8090}}"

# One-line fix point if the demo app's route shape differs from this guess.
ADR_PATH="/adr/0001-project-goals-and-layout"

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

# --- Check 1: GET / returns 200 and looks like the ADR list -----------

body_file=$(mktemp)
trap 'rm -f "$body_file"' EXIT

code=$(curl -s -o "$body_file" -w '%{http_code}' "$BASE_URL/" || echo "000")
if [ "$code" = "200" ]; then
  if grep -qi 'adr' "$body_file" || grep -qEi '<h1|<title' "$body_file"; then
    report PASS "GET / returns 200 with ADR-list-looking body"
  else
    report FAIL "GET / returns 200 with ADR-list-looking body" \
      "got 200 but body has no 'adr' text and no <h1>/<title>"
  fi
else
  report FAIL "GET / returns 200 with ADR-list-looking body" "got HTTP $code"
fi

# --- Check 2: GET /adr/<slug> returns 200 with rendered HTML -----------

code=$(curl -s -o "$body_file" -w '%{http_code}' "$BASE_URL$ADR_PATH" || echo "000")
if [ "$code" = "200" ]; then
  if grep -qEi '<h1|<body' "$body_file"; then
    report PASS "GET $ADR_PATH returns 200 with rendered HTML"
  else
    report FAIL "GET $ADR_PATH returns 200 with rendered HTML" \
      "got 200 but body has no <h1>/<body> (markdown may not have been rendered)"
  fi
else
  report FAIL "GET $ADR_PATH returns 200 with rendered HTML" "got HTTP $code"
fi

# --- Check 3: GET /this-does-not-exist returns 404 ---------------------

code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/this-does-not-exist" || echo "000")
if [ "$code" = "404" ]; then
  report PASS "GET /this-does-not-exist returns 404"
else
  report FAIL "GET /this-does-not-exist returns 404" "got HTTP $code"
fi

# --- Check 4: streaming-proof request (adr/0007, adr/0008) -------------
#
# adr/0007 and adr/0008 are about the server's ability to stream request
# and response bodies (and apply backpressure) rather than buffering
# everything up front. A real check for that needs an endpoint that
# accepts a request body -- but the ADR browser, per its stated purpose,
# is a read-only markdown browser with no such endpoint. Rather than
# invent a body-accepting request against an app that has nowhere to send
# one (which would just exercise 404/405 handling, not streaming), this
# check is skipped as not applicable to this demo app's surface.
#
# If a future version of the demo app grows a POST/PUT endpoint, replace
# this comment with a real check, e.g. a slow chunked upload via:
#   sh -c 'printf "part1"; sleep 0.5; printf "part2"' | \
#     curl -s -o /dev/null -w '%{http_code}' --data-binary @- "$BASE_URL/some-endpoint"
echo "SKIP: streaming-proof request check -- no body-accepting endpoint on this read-only demo app"

# --- Summary -------------------------------------------------------------

echo "----"
echo "Summary: $PASS passed, $FAIL failed"

if [ "$FAIL" -eq 0 ]; then
  exit 0
else
  exit 1
fi
