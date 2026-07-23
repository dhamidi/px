#!/usr/bin/env bash
#
# test/milestone19_build.sh -- proves adr/0033 end to end: `px build`
# (prolog/px_build.pl's build/1) turns this repo's demo app into ONE
# executable that a different directory, with none of this repo's files
# reachable relatively, can run standalone.
#
# Steps (adr/0033's own milestone19 description):
#   1. Build: call px_build:build([out(...)]) from the repo root (loads
#      the demo app -- config, routes, forms, adr_doc/2 facts, compiled
#      and hashed assets). The build IS a smoke test: it cannot succeed
#      unless the app fully loads and qsave_program/2 can embed every
#      foreign library the load pulled in (adr/0033 discovery 1).
#   2. Move it: copy the binary to a directory with none of this repo's
#      files reachable by relative path, cd there, run it against a
#      brand-new PORT and a brand-new data/ directory it must create
#      itself (prologex_serve/0's ensure_parent_dir + lazy db open).
#   3. Serve: exercise a baked content page (adrs feature), the ui demo
#      registry, a baked asset blob (public/assets/ does not exist next
#      to the moved binary at all -- px_assets:serve_asset/2's blob
#      fallback, adr/0033 decision 2), gzip negotiation against that
#      same blob, and a real POST through px_form + sqlite (adr/0020,
#      adr/0023) -- proving pcre and the sqlite amalgamation both work
#      from inside the saved state.
#   4. SIGTERM the exact PID the script itself started: graceful exit
#      within 10s, status 0 (adr/0031 -- unchanged by being a saved
#      state; worker:install_shutdown_handler/0 rides into the binary
#      like everything else).
#   5. Clean up every /tmp artifact this script created.
#
# Test hygiene (same as milestone18): server, curl and kill all run from
# this one bash process against explicit PIDs it captured itself; no
# pkill; this script never touches port 8090 or the systemd prologex
# unit -- PORT 8141 here is a throwaway side port, matching milestone18's
# own 8131 choice one port over.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT=8141

BUILD_OUT=/tmp/px_m19_bin
MOVED_DIR=/tmp/px_m19_moved
MOVED_BIN="$MOVED_DIR/app_bin"

WORKDIR=$(mktemp -d)
BUILD_LOG="$WORKDIR/build.log"
SERVER_LOG="$MOVED_DIR/server.log"

cleanup() {
  # Best-effort: kill the exact server PID if it is somehow still
  # running, then remove every /tmp artifact this script created.
  # No pkill -- only the one PID this script itself started.
  if [ -n "${SERVER_PID:-}" ]; then
    kill -0 "$SERVER_PID" 2>/dev/null && kill -KILL "$SERVER_PID" 2>/dev/null
  fi
  rm -rf "$WORKDIR" "$BUILD_OUT" "$MOVED_DIR"
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


# === 1. BUILD ============================================================

rm -f "$BUILD_OUT"

T0=$(date +%s.%N)
( cd "$REPO" && timeout 120 swipl -q \
    -g "use_module('prolog/px_build'), px_build:build([out('$BUILD_OUT')]), halt" \
    -t "halt(1)" ) > "$BUILD_LOG" 2>&1
BUILD_STATUS=$?
T1=$(date +%s.%N)
BUILD_ELAPSED=$(echo "$T1 - $T0" | bc)

if [ "$BUILD_STATUS" -eq 0 ]; then
  report PASS "px_build:build/1 exits 0 (${BUILD_ELAPSED}s)"
else
  report FAIL "px_build:build/1 exits 0" "status $BUILD_STATUS -- build log follows"
  cat "$BUILD_LOG"
fi

if [ -f "$BUILD_OUT" ]; then
  report PASS "output file exists"
else
  report FAIL "output file exists" "$BUILD_OUT not found"
fi

if [ -x "$BUILD_OUT" ]; then
  report PASS "output file is executable"
else
  report FAIL "output file is executable"
fi

BUILD_SIZE=$(wc -c < "$BUILD_OUT" 2>/dev/null | tr -d ' ')
echo "build log:"
cat "$BUILD_LOG"
echo "binary size: ${BUILD_SIZE:-unknown} bytes"

# Foreign-library warnings would show up as extra stderr noise in the
# build log above; the ADR's failure mode is qsave_program/2 returning
# false outright (already caught by the exit-status check), not a
# silent partial save, so no separate check is needed here.

if [ "$BUILD_STATUS" -ne 0 ] || [ ! -x "$BUILD_OUT" ]; then
  echo "----"
  echo "Summary: $PASS passed, $FAIL failed (build failed -- skipping the rest)"
  exit 1
fi


# === 2. MOVE IT ==========================================================

rm -rf "$MOVED_DIR"
mkdir -p "$MOVED_DIR"
cp "$BUILD_OUT" "$MOVED_BIN"

if [ -x "$MOVED_BIN" ]; then
  report PASS "moved binary is executable at $MOVED_BIN"
else
  report FAIL "moved binary is executable at $MOVED_BIN"
fi

if [ -e "$MOVED_DIR/data" ]; then
  report FAIL "no pre-existing data/ before first run" "unexpected $MOVED_DIR/data already there"
else
  report PASS "no pre-existing data/ before first run"
fi


# === 3. SERVE =============================================================

# Run with cwd = MOVED_DIR so nothing from $REPO is reachable
# relatively -- proves the binary carries its own state, not files
# beside it. PORT is the only override; config(database, ...) stays
# the app's own "data/prologex.db", resolved relative to this cwd by
# prologex_serve/0's ensure_parent_dir/ensure_db (adr/0033, adr/0022).
( cd "$MOVED_DIR" && PORT=$PORT ./app_bin ) > "$SERVER_LOG" 2>&1 &
SERVER_PID=$!

READY=0
for _ in $(seq 1 100); do
  if curl -s -o /dev/null -m 1 "http://127.0.0.1:$PORT/"; then
    READY=1
    break
  fi
  kill -0 "$SERVER_PID" 2>/dev/null || break
  sleep 0.1
done

if [ "$READY" -ne 1 ]; then
  report FAIL "moved binary boots and starts serving" "never answered -- log follows"
  cat "$SERVER_LOG"
  kill -KILL "$SERVER_PID" 2>/dev/null
  echo "----"; echo "Summary: $PASS passed, $FAIL failed"; exit 1
fi
report PASS "moved binary (PID $SERVER_PID) boots and starts serving"

if [ -f "$MOVED_DIR/data/prologex.db" ]; then
  report PASS "fresh data/prologex.db created under the moved cwd"
else
  report FAIL "fresh data/prologex.db created under the moved cwd" "no $MOVED_DIR/data/prologex.db"
fi

# --- GET / : baked adrs home page ---------------------------------------

HOME_BODY="$WORKDIR/home.body"
code=$(curl -s -m 5 -o "$HOME_BODY" -w '%{http_code}' "http://127.0.0.1:$PORT/" || echo 000)
if [ "$code" = "200" ] && grep -q 'design decisions' "$HOME_BODY"; then
  report PASS "GET / -> 200, contains 'design decisions'"
else
  report FAIL "GET / -> 200, contains 'design decisions'" "got HTTP $code"
fi

# --- GET /adr/0033-single-binary-builds : baked adr_doc/2 fact ---------

code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' \
  "http://127.0.0.1:$PORT/adr/0033-single-binary-builds" || echo 000)
if [ "$code" = "200" ]; then
  report PASS "GET /adr/0033-single-binary-builds -> 200 (baked adr_doc/2 facts)"
else
  report FAIL "GET /adr/0033-single-binary-builds -> 200" "got HTTP $code"
fi

# --- GET /ui : component library demo registry --------------------------

code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/ui" || echo 000)
if [ "$code" = "200" ]; then
  report PASS "GET /ui -> 200"
else
  report FAIL "GET /ui -> 200" "got HTTP $code"
fi

# --- the hashed css asset referenced by / : blob fallback ---------------
# public/assets/ does not exist anywhere near $MOVED_DIR -- this can only
# succeed through px_assets:asset_blob/2 (adr/0033 decision 2).

CSS_PATH=$(grep -o '/assets/[A-Za-z0-9._-]*\.css' "$HOME_BODY" | head -1)
if [ -z "$CSS_PATH" ]; then
  report FAIL "GET / references a hashed css asset" "no /assets/*.css found in body"
else
  report PASS "GET / references a hashed css asset ($CSS_PATH)"

  CSS_HDRS="$WORKDIR/css.headers"
  CSS_BODY="$WORKDIR/css.body"
  code=$(curl -s -m 5 -D "$CSS_HDRS" -o "$CSS_BODY" -w '%{http_code}' \
    "http://127.0.0.1:$PORT$CSS_PATH" || echo 000)
  CSS_BYTES=$(wc -c < "$CSS_BODY" 2>/dev/null | tr -d ' ')
  if [ "$code" = "200" ] && grep -qi '^content-type: *text/css' "$CSS_HDRS" \
     && [ -n "$CSS_BYTES" ] && [ "$CSS_BYTES" -gt 0 ]; then
    report PASS "GET $CSS_PATH -> 200, text/css, $CSS_BYTES bytes (blob-served)"
  else
    report FAIL "GET $CSS_PATH -> 200, text/css, nonzero size" \
      "got HTTP $code, $CSS_BYTES bytes -- headers follow"
    cat "$CSS_HDRS"
  fi

  # compile_assets/0 (px_assets.pl) writes a .gz sibling for every asset
  # unconditionally, so the disk build always had one -- Accept-Encoding:
  # gzip must get content-encoding: gzip back from the blob fallback too.
  CSSGZ_HDRS="$WORKDIR/cssgz.headers"
  code=$(curl -s -m 5 -H 'Accept-Encoding: gzip' -D "$CSSGZ_HDRS" -o /dev/null \
    -w '%{http_code}' "http://127.0.0.1:$PORT$CSS_PATH" || echo 000)
  if [ "$code" = "200" ] && grep -qi '^content-encoding: *gzip' "$CSSGZ_HDRS"; then
    report PASS "GET $CSS_PATH with Accept-Encoding: gzip -> content-encoding: gzip"
  else
    report FAIL "GET $CSS_PATH with Accept-Encoding: gzip -> content-encoding: gzip" \
      "got HTTP $code -- headers follow"
    cat "$CSSGZ_HDRS"
  fi
fi

# --- POST /comments : forms + sqlite + pcre autoload, all inside the ----
#     saved state --------------------------------------------------------

code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST \
  --data-urlencode "author=milestone19" \
  --data-urlencode "body=proving forms, sqlite and pcre all work from the saved state" \
  "http://127.0.0.1:$PORT/comments" || echo 000)
if [ "$code" = "303" ]; then
  report PASS "POST /comments -> 303 (form validated, comment saved to sqlite)"
else
  report FAIL "POST /comments -> 303" "got HTTP $code"
fi


# === 4. SIGTERM ===========================================================

T0=$(date +%s.%N)
kill -TERM "$SERVER_PID"

( sleep 10; kill -KILL "$SERVER_PID" 2>/dev/null ) &
WATCHDOG_PID=$!
wait "$SERVER_PID"
SERVER_STATUS=$?
kill "$WATCHDOG_PID" 2>/dev/null
wait "$WATCHDOG_PID" 2>/dev/null
T1=$(date +%s.%N)
ELAPSED=$(echo "$T1 - $T0" | bc)

echo "server exit status=$SERVER_STATUS, elapsed=${ELAPSED}s since SIGTERM"

if (( $(echo "$ELAPSED < 10" | bc -l) )); then
  report PASS "process exits within 10s of SIGTERM"
else
  report FAIL "process exits within 10s of SIGTERM" "took ${ELAPSED}s"
fi

if [ "$SERVER_STATUS" -eq 0 ]; then
  report PASS "process exits with status 0"
else
  report FAIL "process exits with status 0" "got status $SERVER_STATUS"
fi

sleep 0.2
if ss -ltn 2>/dev/null | grep -q ":$PORT "; then
  report FAIL "port $PORT released after shutdown" "still bound"
else
  report PASS "port $PORT released after shutdown"
fi

unset SERVER_PID   # already reaped -- cleanup's best-effort kill is now a no-op


# === 5. CLEANUP happens in the EXIT trap ==================================

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
