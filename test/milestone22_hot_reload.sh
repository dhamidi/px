#!/usr/bin/env bash
#
# test/milestone22_hot_reload.sh -- proves adr/0036's hot reload in
# development end to end, against a REAL scaffolded app
# (`bin/px new` + `bin/px generate feature posts`) booted with a REAL
# server process, edited on disk WHILE IT RUNS, with no restart:
#
#   a. a view template edit is visible on the next request
#   b. a commands.pl edit changes observable behaviour
#   c. a NEW route/action added to controller.pl is live -- AND the
#      existing routes are not duplicated by (repeated) reloads,
#      checked against the LIVE process's own route/4 table via a
#      route-count readout the new page itself renders (bin/px routes
#      always re-loads fresh from disk in a separate process, so it
#      cannot prove anything about what the running server did across
#      several reload cycles -- this checks the running process)
#   d. an assets/css/app.css edit is served unhashed, uncompiled, on
#      the very next request
#   e. a syntax error in a view does not crash the worker -- the
#      request gets a plain-text 500 naming the error, and a
#      subsequent request after the fix works normally
#   f. PRODUCTION (PROLOGEX_ENV=production) is byte-identical to
#      today: assets are hashed, and an edited view does NOT take
#      effect without a restart
#
# Test hygiene (adr/0031/milestone18/19 discipline): swipl ignores
# SIGTERM by default (only worker:install_shutdown_handler/0 wires it,
# and this script deliberately does not rely on that for cleanup --
# see the ADR's own warning about `timeout swipl` leaving the process
# alive), so every server this script starts is killed by its own
# exact PID (kill -9), never pkill, and cleanup runs from a trap on
# EXIT so a failing assertion still cleans up. Scratch ports (8410/
# 8411) and a scratch mktemp -d app directory only -- this script
# never touches 8090/8091 or the systemd prologex/blog units.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_PORT=8410
PROD_PORT=8411

WORKDIR=$(mktemp -d)
APP_DIR="$WORKDIR/hotreload_app"
DEV_LOG="$WORKDIR/dev_server.log"
PROD_LOG="$WORKDIR/prod_server.log"

DEV_PID=""
PROD_PID=""

cleanup() {
  if [ -n "$DEV_PID" ]; then
    kill -9 "$DEV_PID" 2>/dev/null
  fi
  if [ -n "$PROD_PID" ]; then
    kill -9 "$PROD_PID" 2>/dev/null
  fi
  rm -rf "$WORKDIR"
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

# wait_for_ready LOGFILE PID -- bounded wait for the boot banner.
wait_for_ready() {
  local log="$1" pid="$2"
  for _ in $(seq 1 100); do
    grep -q "worker(s) on port" "$log" 2>/dev/null && return 0
    kill -0 "$pid" 2>/dev/null || return 1
    sleep 0.1
  done
  return 1
}

# wait_for_pattern URL PATTERN -- polls up to ~8s for PATTERN to show
# up in the response body (mtime resolution on some filesystems is
# whole seconds, so the first change is not always visible on the very
# next request).
wait_for_pattern() {
  local url="$1" pattern="$2"
  for _ in $(seq 1 40); do
    curl -s "$url" 2>/dev/null | grep -q -- "$pattern" && return 0
    sleep 0.2
  done
  return 1
}

# =========================================================================
# 0. SCAFFOLD -- exactly the ADR's own worked example: `px new` then
#    `px generate feature posts`, same as a developer would do.
# =========================================================================

if "$REPO/bin/px" new "$APP_DIR" > "$WORKDIR/new.log" 2>&1 \
   && ( cd "$APP_DIR" && "$REPO/bin/px" generate feature posts > "$WORKDIR/generate.log" 2>&1 ); then
  report PASS "scaffolded app + posts feature (px new, px generate feature posts)"
else
  report FAIL "scaffolded app + posts feature" "see $WORKDIR/new.log / generate.log"
  cat "$WORKDIR/new.log" "$WORKDIR/generate.log" 2>/dev/null
  echo "----"; echo "Summary: $PASS passed, $FAIL failed"; exit 1
fi

BASELINE_ROUTE_COUNT=$("$REPO/bin/px" routes 2>/dev/null | tail -n +2 | grep -c .)

# =========================================================================
# 1. BOOT (development -- PROLOGEX_ENV unset is the default, adr/0022)
# =========================================================================

# `exec` inside the subshell replaces the subshell process itself with
# swipl, so $! below is swipl's OWN pid, not a subshell wrapping it
# that `kill -9 $!` would leave orphaned and still running (this is
# exactly the "swipl left alive" hazard the process discipline this
# script follows exists to avoid -- caught by hand: an earlier version
# without `exec` here leaked swipl processes across runs).
( cd "$APP_DIR" && exec env PORT="$DEV_PORT" swipl -g prologex_run "$REPO/prolog/prologex.pl" \
    > "$DEV_LOG" 2>&1 ) &
DEV_PID=$!

if wait_for_ready "$DEV_LOG" "$DEV_PID"; then
  report PASS "dev server booted (PID $DEV_PID) on port $DEV_PORT"
else
  report FAIL "dev server booted" "see $DEV_LOG"
  cat "$DEV_LOG"
  echo "----"; echo "Summary: $PASS passed, $FAIL failed"; exit 1
fi

DEV_URL="http://127.0.0.1:$DEV_PORT"

# Warm the (single, workers:1) worker thread so its first-sighting
# baseline for every tracked file is established before any edit --
# exactly the ordinary "browse, then edit" dev workflow.
curl -s -o /dev/null "$DEV_URL/posts"

# =========================================================================
# (a) view template edit, visible without restart
# =========================================================================

cp "$APP_DIR/app/posts/views.pl" "$WORKDIR/views.pl.orig"
sed -i 's/h1("posts")/h1("posts HOTRELOAD-MARKER-A")/' "$APP_DIR/app/posts/views.pl"

if wait_for_pattern "$DEV_URL/posts" "HOTRELOAD-MARKER-A"; then
  report PASS "(a) view template edit is visible without restart"
else
  report FAIL "(a) view template edit is visible without restart"
fi
cp "$WORKDIR/views.pl.orig" "$APP_DIR/app/posts/views.pl"
wait_for_pattern "$DEV_URL/posts" "posts</h1>" >/dev/null   # settle back before (b)

# =========================================================================
# (b) commands.pl edit changes observable behaviour, without restart
# =========================================================================

# Create a real post via the scaffolded create_post form, then confirm
# it renders on the index.
curl -s -o /dev/null -X POST \
  -d "title=HotreloadPost&body=body&_msg=create_post" \
  "$DEV_URL/posts/new"

if wait_for_pattern "$DEV_URL/posts" "HotreloadPost"; then
  report PASS "(b) setup: post created via the scaffolded form"
else
  report FAIL "(b) setup: post created via the scaffolded form"
fi

cp "$APP_DIR/app/posts/commands.pl" "$WORKDIR/commands.pl.orig"
# Redefine all_posts/1 to always answer [] -- a real behaviour change,
# not a cosmetic one, forcing the index to render its empty state.
sed -i 's/all_posts(Rows) :-/all_posts([]) :- !.\nall_posts(Rows) :-/' \
  "$APP_DIR/app/posts/commands.pl"

if wait_for_pattern "$DEV_URL/posts" "No posts yet"; then
  report PASS "(b) commands.pl edit changes behaviour without restart"
else
  report FAIL "(b) commands.pl edit changes behaviour without restart"
fi

cp "$WORKDIR/commands.pl.orig" "$APP_DIR/app/posts/commands.pl"
if wait_for_pattern "$DEV_URL/posts" "HotreloadPost"; then
  report PASS "(b) reverting commands.pl restores the original behaviour"
else
  report FAIL "(b) reverting commands.pl restores the original behaviour"
fi

# =========================================================================
# (c) a NEW route/action is live, and reloading repeatedly does not
#     duplicate ANY route in the LIVE process's own route table
# =========================================================================

cp "$APP_DIR/app/posts/controller.pl" "$WORKDIR/controller.pl.orig"
python3 - "$APP_DIR/app/posts/controller.pl" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()

# New page BEFORE "/posts/:id" (show) -- same discipline the scaffold's
# own comments call out ("/posts/new must come before /posts/:id").
show_marker = ':- page(show,  "/posts/:id",      [as(post)]).       %% post_path(Id)'
assert show_marker in content
page_decl = ':- page(stats, "/posts/stats", [as(post_stats)]).  %% NEW route, milestone22\n'
content = content.replace(show_marker, page_decl + show_marker, 1)

# model/view for the new action: renders a route-count readout so the
# LIVE process's route/4 table (not a fresh `bin/px routes` reload,
# which cannot see the running server at all) can be checked directly
# after several reload cycles.
model_marker = "model(show, Env, M) :-"
model_stats = (
    "model(stats, _Env, m{info: Info}) :-\n"
    "    aggregate_all(count, router:route(_,_,_,_), Total),\n"
    "    aggregate_all(count, router:route(posts,_,_,_), PostsN),\n"
    "    aggregate_all(count, router:route(post_stats,_,_,_), StatsN),\n"
    "    format(string(Info), \"TOTAL=~w POSTS=~w STATS=~w\", [Total, PostsN, StatsN]).\n"
)
assert model_marker in content
content = content.replace(model_marker, model_stats + model_marker, 1)

view_marker = "view(show,  M, post_show(M))."
view_stats = "view(stats, M, pre(text(M.info))).\n"
assert view_marker in content
content = content.replace(view_marker, view_stats + view_marker, 1)

with open(path, "w") as f:
    f.write(content)
PYEOF

if wait_for_pattern "$DEV_URL/posts/stats" "TOTAL="; then
  report PASS "(c) a new route added to controller.pl is live without restart"
else
  report FAIL "(c) a new route added to controller.pl is live without restart"
fi

BODY1=$(curl -s "$DEV_URL/posts/stats")
STATS_N_1=$(echo "$BODY1" | grep -oE 'STATS=[0-9]+' | grep -oE '[0-9]+')
TOTAL_1=$(echo "$BODY1" | grep -oE 'TOTAL=[0-9]+' | grep -oE '[0-9]+')

OLD_ROUTE_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$DEV_URL/posts")
if [ "$OLD_ROUTE_CODE" = "200" ]; then
  report PASS "(c) pre-existing route (/posts) still 200 after the new route landed"
else
  report FAIL "(c) pre-existing route (/posts) still 200 after the new route landed" "got $OLD_ROUTE_CODE"
fi

# Force several MORE reload cycles of the SAME (already-changed)
# controller.pl by touching it repeatedly, then re-check the live
# route table -- route registration is `retractall(route(Name,...))`
# then `assertz` by name (router:add_route/4), so this must NOT grow.
for _ in 1 2 3; do
  touch "$APP_DIR/app/posts/controller.pl"
  sleep 1.1
  curl -s -o /dev/null "$DEV_URL/posts" >/dev/null
done

BODY2=$(curl -s "$DEV_URL/posts/stats")
STATS_N_2=$(echo "$BODY2" | grep -oE 'STATS=[0-9]+' | grep -oE '[0-9]+')
TOTAL_2=$(echo "$BODY2" | grep -oE 'TOTAL=[0-9]+' | grep -oE '[0-9]+')

if [ -n "$STATS_N_1" ] && [ "$STATS_N_1" = "1" ] \
   && [ -n "$STATS_N_2" ] && [ "$STATS_N_2" = "1" ] \
   && [ -n "$TOTAL_1" ] && [ "$TOTAL_1" = "$TOTAL_2" ]; then
  report PASS "(c) repeated reloads do not duplicate routes (live route/4 count steady: $TOTAL_1, post_stats always 1)"
else
  report FAIL "(c) repeated reloads do not duplicate routes" \
    "stats route count before=$STATS_N_1 after=$STATS_N_2, total before=$TOTAL_1 after=$TOTAL_2"
fi

cp "$WORKDIR/controller.pl.orig" "$APP_DIR/app/posts/controller.pl"
wait_for_pattern "$DEV_URL/posts" "posts</h1>" >/dev/null   # settle back before (d)

# =========================================================================
# (d) assets/css/app.css edit is served unhashed, uncompiled, live
# =========================================================================

BEFORE_CSS=$(curl -s "$DEV_URL/assets/css/app.css")
if echo "$BEFORE_CSS" | grep -q "HOTRELOAD-CSS-MARKER"; then
  report FAIL "(d) setup: css marker not present before edit (test bug)"
else
  report PASS "(d) setup: dev serves assets/css/app.css unhashed at its logical path"
fi

cp "$APP_DIR/assets/css/app.css" "$WORKDIR/app.css.orig"
echo "/* HOTRELOAD-CSS-MARKER */" >> "$APP_DIR/assets/css/app.css"

if wait_for_pattern "$DEV_URL/assets/css/app.css" "HOTRELOAD-CSS-MARKER"; then
  report PASS "(d) assets/css/app.css edit is served live, no recompile/restart"
else
  report FAIL "(d) assets/css/app.css edit is served live, no recompile/restart"
fi

CACHE_HEADER=$(curl -s -D - -o /dev/null "$DEV_URL/assets/css/app.css" | tr -d '\r' | grep -i '^cache-control:')
if echo "$CACHE_HEADER" | grep -qi "no-cache"; then
  report PASS "(d) dev asset response is no-cache (not the production immutable header)"
else
  report FAIL "(d) dev asset response is no-cache" "got: $CACHE_HEADER"
fi

cp "$WORKDIR/app.css.orig" "$APP_DIR/assets/css/app.css"

# =========================================================================
# (e) a syntax error in a view must not crash the worker
# =========================================================================

cp "$APP_DIR/app/posts/views.pl" "$WORKDIR/views.pl.orig2"
python3 - "$APP_DIR/app/posts/views.pl" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    c = f.read()
# Drop a closing paren -- an unambiguous syntax error, not a semantic one.
c = c.replace("post_index(M) ~>", "post_index(M ~>", 1)
with open(path, "w") as f:
    f.write(c)
PYEOF

sleep 1.5
BROKEN_RESPONSE=$(curl -s -w '\nHTTP_CODE:%{http_code}' "$DEV_URL/posts")
BROKEN_CODE=$(echo "$BROKEN_RESPONSE" | grep -oE 'HTTP_CODE:[0-9]+' | grep -oE '[0-9]+')

if kill -0 "$DEV_PID" 2>/dev/null; then
  report PASS "(e) worker process stays up after a syntax error in the edited file"
else
  report FAIL "(e) worker process stays up after a syntax error in the edited file" "PID $DEV_PID is gone"
fi

if [ "$BROKEN_CODE" = "500" ] && echo "$BROKEN_RESPONSE" | grep -qi "syntax error"; then
  report PASS "(e) the broken reload surfaces as a 500 naming the syntax error (not a silent failure)"
else
  report FAIL "(e) the broken reload surfaces as a 500 naming the syntax error" \
    "code=$BROKEN_CODE body follows:
$BROKEN_RESPONSE"
fi

cp "$WORKDIR/views.pl.orig2" "$APP_DIR/app/posts/views.pl"

if wait_for_pattern "$DEV_URL/posts" "posts</h1>"; then
  report PASS "(e) a subsequent good request after fixing the file works normally"
else
  report FAIL "(e) a subsequent good request after fixing the file works normally"
fi

kill -9 "$DEV_PID" 2>/dev/null
wait "$DEV_PID" 2>/dev/null
DEV_PID=""
sleep 0.3
if ss -ltn 2>/dev/null | grep -q ":$DEV_PORT "; then
  report FAIL "dev server port $DEV_PORT released after kill"
else
  report PASS "dev server port $DEV_PORT released after kill"
fi

# =========================================================================
# (f) PRODUCTION unchanged: hashed assets, no hot reload
# =========================================================================

rm -rf "$APP_DIR/public" "$APP_DIR/data"
( cd "$APP_DIR" && exec env PORT="$PROD_PORT" PROLOGEX_ENV=production \
    swipl -g prologex_run "$REPO/prolog/prologex.pl" > "$PROD_LOG" 2>&1 ) &
PROD_PID=$!

if wait_for_ready "$PROD_LOG" "$PROD_PID"; then
  report PASS "production server booted (PID $PROD_PID) on port $PROD_PORT"
else
  report FAIL "production server booted" "see $PROD_LOG"
  cat "$PROD_LOG"
fi

PROD_URL="http://127.0.0.1:$PROD_PORT"
HOME_BODY=$(curl -s "$PROD_URL/")

if echo "$HOME_BODY" | grep -oE '/assets/app-[0-9a-f]{12}\.css' >/dev/null; then
  HASHED=$(echo "$HOME_BODY" | grep -oE '/assets/app-[0-9a-f]{12}\.css' | head -1)
  report PASS "(f) production references a hashed, compiled css asset ($HASHED)"
else
  report FAIL "(f) production references a hashed, compiled css asset" "body: $HOME_BODY"
fi

if [ -d "$APP_DIR/public/assets" ] && ls "$APP_DIR/public/assets"/*.css >/dev/null 2>&1; then
  report PASS "(f) production compiled public/assets/ at boot"
else
  report FAIL "(f) production compiled public/assets/ at boot"
fi

cp "$APP_DIR/app/welcome/controller.pl" "$WORKDIR/welcome.pl.orig"
sed -i 's/Welcome to /HOTRELOAD-PROD-SHOULD-NOT-APPEAR /' "$APP_DIR/app/welcome/controller.pl"
sleep 1.5

if curl -s "$PROD_URL/" | grep -q "HOTRELOAD-PROD-SHOULD-NOT-APPEAR"; then
  report FAIL "(f) production does NOT hot-reload an edited view"
else
  report PASS "(f) production does NOT hot-reload an edited view (restart required, as before this ADR)"
fi
cp "$WORKDIR/welcome.pl.orig" "$APP_DIR/app/welcome/controller.pl"

kill -9 "$PROD_PID" 2>/dev/null
wait "$PROD_PID" 2>/dev/null
PROD_PID=""

# =========================================================================

echo "----"
echo "dev server log:"
cat "$DEV_LOG" 2>/dev/null
echo "----"
echo "production server log:"
cat "$PROD_LOG" 2>/dev/null
echo "----"
echo "Summary: $PASS passed, $FAIL failed"

if [ "$FAIL" -eq 0 ]; then
  exit 0
else
  exit 1
fi
