#!/usr/bin/env bash
# Plays the game twice without a window (scripts/perf/playtest.gd): alone,
# and joined to a local test region with two grown neighbor towns, doing
# the region's work on one core like the browser does. Writes alone.json
# and region.json into OUT_DIR.
#
# Run: tools/playtest/run_desktop.sh GODOT OUT_DIR [seconds]
set -u
GODOT=$1
OUT=$2
SECONDS_RUN=${3:-300}
PORT=9099
mkdir -p "$OUT"
cd "$(dirname "$0")/../.."

"$GODOT" --headless -- --playtest="$SECONDS_RUN" --playtest-out="$OUT/alone.json" </dev/null >"$OUT/alone.log" 2>&1
grep -a '^Playtest' "$OUT/alone.log"

"$GODOT" --headless -s tools/playtest/make_region.gd -- "$OUT/test-region.json" 2 small </dev/null 2>&1 | grep -a people
"$GODOT" --headless -s scripts/net/server_main.gd -- --port $PORT --data "$OUT/test-region.json" </dev/null >"$OUT/server.log" 2>&1 &
SERVER=$!
sleep 5
"$GODOT" --headless -- --playtest="$SECONDS_RUN" --playtest-inline --playtest-region="ws://localhost:$PORT/PLAYT1" --playtest-pin=500001 \
	--playtest-out="$OUT/region.json" </dev/null >"$OUT/region.log" 2>&1
grep -a '^Playtest' "$OUT/region.log"
kill $SERVER 2>/dev/null
wait $SERVER 2>/dev/null
# Results are judged by tools/playtest/check.py; a crash at exit doesn't count.
exit 0
