#!/usr/bin/env bash
# Several players in one region at once, for a long while: a local region
# server with a grown neighbor, three desktop players (one doing the
# region's work on one core, like the browser) and, when a web export is
# given, one player in Chromium. Each joins a little after the last,
# builds a town, then keeps adding streets while the towns sync. At the
# end soak_check.py compares every town's own count with the server's copy
# and with what the other players see.
#
# Run: tools/playtest/soak.sh GODOT OUT_DIR [seconds] [web export dir]
set -u
GODOT=$1
OUT=$(realpath -m "$2")
SECONDS_RUN=${3:-1500}
WEB=${4:-}
PORT=9098
URL="ws://localhost:$PORT/PLAYT1"
mkdir -p "$OUT"
cd "$(dirname "$0")/../.."

"$GODOT" --headless -s tools/playtest/make_region.gd -- "$OUT/region.json" 1 small </dev/null 2>&1 | grep -a people
"$GODOT" --headless -s scripts/net/server_main.gd -- --port $PORT --data "$OUT/region.json" </dev/null >"$OUT/server.log" 2>&1 &
SERVER=$!
sleep 5

BOTS=()
# The browser player first: it loads slowest.
if [ -n "$WEB" ]; then
	node tools/playtest/web_playtest.mjs "$WEB" "$SECONDS_RUN" "$OUT/Dana.json" "$URL" Dana >"$OUT/Dana.log" 2>&1 &
	BOTS+=($!)
	sleep 20
fi
i=0
for name in Alice Bob Cara; do
	extra=""
	[ $i = 2 ] && extra="--playtest-inline"
	# Each player has a computer of its own: its own profile and saves.
	mkdir -p "$OUT/home-$name"
	XDG_DATA_HOME="$OUT/home-$name" "$GODOT" --headless -- --playtest="$SECONDS_RUN" $extra --playtest-region="$URL" \
		--playtest-name=$name --playtest-out="$OUT/$name.json" </dev/null >"$OUT/$name.log" 2>&1 &
	BOTS+=($!)
	i=$((i + 1))
	sleep 20
done
for b in "${BOTS[@]}"; do wait $b; done
sleep 3
kill $SERVER 2>/dev/null
wait $SERVER 2>/dev/null
python3 tools/playtest/soak_check.py "$OUT"
