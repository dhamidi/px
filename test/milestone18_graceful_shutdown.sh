#!/usr/bin/env bash
#
# test/milestone18_graceful_shutdown.sh -- proves adr/0031's graceful
# SIGTERM shutdown (worker:install_shutdown_handler/0 + bridge.pl's
# rewritten on_shutdown_async/2), the fix for the gap deploy/prologex.service
# used to paper over with KillSignal=SIGKILL + TimeoutStopSec=5.
#
# Boots its own throwaway 2-worker server on a side port (8131, NOT the
# real service's 8090 -- this script never touches that port or the
# systemd prologex unit) with a minimal inline Prolog boot script (worker
# + http_stream + response directly -- prologex_run/0 is intentionally
# not involved, per the constraint that prolog/prologex.pl is off limits
# to this change; see the ADR for the one-line call that wires this into
# prologex_run/0 for real).
#
# Proves, against the exact swipl PID this script itself started:
#   (a) the server actually serves before shutdown (GET /ping -> 200)
#   (b) sending it SIGTERM makes it exit within 10s
#   (c) with exit status 0 (not systemd's SIGKILL escalation)
#   (d) the listening port is released afterwards
#   (e) bonus: a slow, still-in-flight request (curl --limit-rate against
#       a multi-megabyte body built from this repo's own real adr/*.md
#       files, repeated past this VM's ~4MB TCP send-buffer autotune
#       ceiling so the response genuinely cannot be handed to the kernel
#       in one shot -- see the ADR for why that matters) started just
#       before SIGTERM still completes byte-for-byte, proving shutdown
#       lets in-flight responses finish instead of cutting them off.
#
# Test hygiene (see adr/0031): server, curl, and kill all run from this
# one bash process against explicit PIDs it captured itself; no pkill
# anywhere (that would kill the sandbox shell, not just this test's
# processes); every wait is bounded (`timeout`, or an explicit watchdog
# that SIGKILLs the exact PID as a last resort so this script itself
# cannot hang forever if the mechanism regresses).

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT=8131
BIG_THRESHOLD_BYTES=6000000   # comfortably past this VM's ~4MB tcp_wmem
                               # autotune ceiling (see adr/0031) -- forces
                               # real backpressure, not an instant in-kernel
                               # copy that would prove nothing about
                               # in-flight draining.

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

BOOT_PL="$WORKDIR/boot.pl"
SERVER_LOG="$WORKDIR/server.log"
BIG_OUT="$WORKDIR/big.out"
BIG_RESULT="$WORKDIR/big.result"
BIG_CURL_ERR="$WORKDIR/big_curl.err"

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

# --- Boot script: worker + http_stream + response directly, no app/,
#     no prologex.pl -- exactly the mechanism under test, isolated from
#     everything currently being edited in parallel. ---------------------

cat > "$BOOT_PL" <<PLEOF
:- initialization(main, main).
:- dynamic big_body/1.

main :-
    use_module('$REPO/prolog/worker'),
    use_module('$REPO/prolog/http_stream'),
    use_module('$REPO/prolog/response'),
    build_big_body('$REPO/adr', $BIG_THRESHOLD_BYTES, Body, Bytes),
    assertz(big_body(Body)),
    format(user_error, "BIG_BODY_BYTES ~w~n", [Bytes]),
    worker:start_workers($PORT, 2, user:on_conn),
    install_shutdown_handler,
    format(user_error, "READY~n", []),
    thread_get_message(_).

% Real content, not synthetic filler -- this repo's own ADRs, repeated
% until past the backpressure-forcing threshold.
read_all_adrs(Dir, Text) :-
    atom_concat(Dir, '/*.md', Pattern),
    expand_file_name(Pattern, Files0),
    msort(Files0, Files),
    findall(S, ( member(F, Files), read_file_to_string(F, S, []) ), Strings),
    atomic_list_concat(Strings, '\n----\n', Text).

build_big_body(Dir, Threshold, Body, Bytes) :-
    read_all_adrs(Dir, Base),
    string_length(Base, BaseLen),
    Reps is max(1, ceiling(Threshold / BaseLen)),
    length(L, Reps),
    maplist(=(Base), L),
    atomic_list_concat(L, Body),
    response:utf8_byte_length(Body, Bytes).

on_conn(Id, Loop, Client) :-
    http_stream:handle_connection(user:h, Id, Loop, Client).

h(Request, Stream) :-
    ( sub_string(Request.url, 0, _, _, "/big")
    -> big_body(Body)
    ;  Body = "pong"
    ),
    response:reply_status(Stream, 200, "OK"),
    response:reply_body(Stream, "text/plain; charset=utf-8", Body),
    close(Stream).
PLEOF

# --- Boot the server, waiting (bounded) for it to announce READY -------

swipl "$BOOT_PL" > "$SERVER_LOG" 2>&1 &
SERVER_PID=$!

READY=0
for _ in $(seq 1 100); do
  grep -q READY "$SERVER_LOG" 2>/dev/null && { READY=1; break; }
  kill -0 "$SERVER_PID" 2>/dev/null || break
  sleep 0.1
done
if [ "$READY" -ne 1 ]; then
  report FAIL "server booted and started serving" "never printed READY -- log follows"
  cat "$SERVER_LOG"
  kill -KILL "$SERVER_PID" 2>/dev/null
  echo "----"; echo "Summary: $PASS passed, $FAIL failed"; exit 1
fi
report PASS "server booted (PID $SERVER_PID) and started serving"

EXPECTED_BYTES=$(grep BIG_BODY_BYTES "$SERVER_LOG" | awk '{print $2}')

# --- Confirm it actually serves before touching shutdown ---------------

code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/ping" || echo 000)
if [ "$code" = "200" ]; then
  report PASS "GET /ping returns 200 before shutdown"
else
  report FAIL "GET /ping returns 200 before shutdown" "got HTTP $code"
fi

# --- Kick off a slow, still-downloading request, then SIGTERM the exact
#     server PID while it is in flight. ----------------------------------

timeout 20 curl -s --limit-rate 1500k -o "$BIG_OUT" -w '%{http_code} %{size_download}' \
  "http://127.0.0.1:$PORT/big" > "$BIG_RESULT" 2>"$BIG_CURL_ERR" &
CURL_PID=$!
sleep 0.4   # let curl actually connect and start reading before we SIGTERM

T0=$(date +%s.%N)
kill -TERM "$SERVER_PID"

# Bounded wait on the exact PID: a watchdog SIGKILLs it (still an exact
# PID, never pkill) if it somehow doesn't exit within 10s, so this test
# itself cannot hang if the mechanism regresses.
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

# --- The in-flight slow request should still complete intact -----------

wait "$CURL_PID"
CURL_STATUS=$?
ACTUAL_BYTES=$(wc -c < "$BIG_OUT" 2>/dev/null | tr -d ' ')

if [ "$CURL_STATUS" -eq 0 ] && [ -n "$EXPECTED_BYTES" ] && [ "$ACTUAL_BYTES" = "$EXPECTED_BYTES" ]; then
  report PASS "in-flight big request (started before SIGTERM) completed intact" \
    "$ACTUAL_BYTES bytes"
else
  report FAIL "in-flight big request (started before SIGTERM) completed intact" \
    "curl exit=$CURL_STATUS, got $ACTUAL_BYTES bytes, expected $EXPECTED_BYTES"
  cat "$BIG_CURL_ERR" 2>/dev/null
fi

echo "----"
echo "server log:"
cat "$SERVER_LOG"
echo "----"
echo "Summary: $PASS passed, $FAIL failed"

if [ "$FAIL" -eq 0 ]; then
  exit 0
else
  exit 1
fi
