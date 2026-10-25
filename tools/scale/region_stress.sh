#!/usr/bin/env bash
# Shared-region stress test: a local region server, several bots each playing
# a big town (tools/playtest, headless, top speed, adding streets as they go),
# and late joiners, with everything measured from outside the game:
#   server CPU and memory over time        region_stress_monitor.py
#   bytes per second, per player           region_stress_proxy.py (a counting go-between)
#   sync lag, welcome size and wait        region_stress_proxy.py
#   how long the server is away from the network   region_stress_probe.py
#   each bot's frames, freezes, drops      the bots' own playtest results
# Then region_stress_report.py joins them into region_stress.json and summary.md.
#
# Make the region first (one big grown town per player):
#   godot --headless -s tools/scale/region_stress_region.gd -- region.json 4 20 2
#
# Run: tools/scale/region_stress.sh GODOT OUT_DIR REGION.json SECONDS [LATE_AT[,LATE_AT]]
#   SECONDS   how long each of the first bots plays at top speed after its set-up
#   LATE_AT   seconds after the start when a late joiner (Late1, Late2) comes in
#
# Only processes this script starts are stopped, by their own PIDs.
set -u
GODOT=$1
mkdir -p "$2"
OUT=$(cd "$2" && pwd)
REGION=$(cd "$(dirname "$3")" && pwd)/$(basename "$3")
SECONDS_RUN=${4:-1200}
LATE_AT=${5:-}
SERVER_PORT=${STRESS_SERVER_PORT:-9098}
PROXY_BASE=${STRESS_PROXY_BASE:-9200}
STAGGER=${STRESS_STAGGER:-20}
CODE=STRESS
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/../.."
cp "$REGION" "$OUT/region.json"
cp "$REGION.players" "$OUT/roster.json"

PIDS=()
cleanup() {
	for p in ${PIDS[@]+"${PIDS[@]}"}; do kill "$p" 2>/dev/null; done
	wait 2>/dev/null
}
trap cleanup EXIT INT TERM

# Names and PINs: Bot1.. (they have towns already) and Late1.. (they don't).
read -r -a BOTS < <(python3 -c "import json,sys;print(' '.join(p['name']+':'+p['pin'] for p in json.load(open('$OUT/roster.json')) if p['city']))")
read -r -a LATES < <(python3 -c "import json,sys;print(' '.join(p['name']+':'+p['pin'] for p in json.load(open('$OUT/roster.json')) if not p['city']))")
ALL_NAMES=$(python3 -c "import json;print(','.join(p['name'] for p in json.load(open('$OUT/roster.json'))))")
START=$(date +%s)

perl -e 'alarm 7200; exec @ARGV' "$GODOT" --headless -s scripts/net/server_main.gd -- --port "$SERVER_PORT" \
	--data "$OUT/region.json" </dev/null >"$OUT/server.log" 2>&1 &
SERVER=$!
PIDS+=($SERVER)
echo "server pid $SERVER"
# A region of big towns takes a while to load: wait until it says it is running.
for _ in $(seq 1 120); do grep -qa "Region running" "$OUT/server.log" && break; sleep 3; done
python3 tools/scale/region_stress_proxy.py --names "$ALL_NAMES" --base-port "$PROXY_BASE" --target "$SERVER_PORT" --out "$OUT" \
	>"$OUT/proxy.log" 2>&1 &
PROXY=$!
PIDS+=($PROXY)
python3 tools/scale/region_stress_probe.py --port "$SERVER_PORT" --seconds $((SECONDS_RUN + 3600)) --out "$OUT/probe.json" \
	>"$OUT/probe.log" 2>&1 &
PROBE=$!
PIDS+=($PROBE)
python3 tools/scale/region_stress_monitor.py --pids "server=$SERVER" --out "$OUT/procs-server.jsonl" >/dev/null 2>&1 &
PIDS+=($!)
sleep 2

BOT_PIDS=()
BOT_NAMES=()
launch_bot() { # name pin port seconds extra
	local name=$1 pin=$2 port=$3 secs=$4 extra=${5:-}
	# Each player has a computer of its own: its own home, profile and saves.
	mkdir -p "$OUT/home-$name"
	HOME="$OUT/home-$name" XDG_DATA_HOME="$OUT/home-$name" perl -e 'alarm 7200; exec @ARGV' "$GODOT" --headless -- \
		--playtest="$secs" $extra --playtest-region="ws://localhost:$port/$CODE" --playtest-name="$name" \
		--playtest-pin="$pin" --playtest-out="$OUT/$name.json" </dev/null >"$OUT/$name.log" 2>&1 &
	local pid=$!
	PIDS+=($pid)
	BOT_PIDS+=($pid)
	BOT_NAMES+=("$name")
	python3 tools/scale/region_stress_monitor.py --pids "$name=$pid" --out "$OUT/procs-$name.jsonl" >/dev/null 2>&1 &
	PIDS+=($!)
	echo "$name pid $pid ($((($(date +%s) - START))) s)"
}

i=0
n=${#BOTS[@]}
for b in "${BOTS[@]}"; do
	name=${b%%:*}
	pin=${b##*:}
	extra=""
	[ $((i + 1)) = "$n" ] && extra="--playtest-inline"  # one on a single core, like the browser
	launch_bot "$name" "$pin" $((PROXY_BASE + i)) "$SECONDS_RUN" "$extra"
	i=$((i + 1))
	[ $i -lt "$n" ] && sleep "$STAGGER"
done

# Late joiners: they come in while the others are well under way.
if [ -n "$LATE_AT" ]; then
	j=0
	IFS=',' read -r -a LATE_TIMES <<<"$LATE_AT"
	for t in "${LATE_TIMES[@]}"; do
		late=${LATES[$j]:-}
		[ -z "$late" ] && break
		wait_s=$((t - ($(date +%s) - START)))
		[ $wait_s -gt 0 ] && sleep $wait_s
		launch_bot "${late%%:*}" "${late##*:}" $((PROXY_BASE + n + j)) 120 ""
		j=$((j + 1))
	done
fi

for p in ${BOT_PIDS[@]+"${BOT_PIDS[@]}"}; do wait "$p"; done
sleep 3
END=$(date +%s)
echo "$((END - START))" >"$OUT/duration_s.txt"
kill -TERM $PROBE 2>/dev/null
kill -TERM $PROXY 2>/dev/null
sleep 2
kill "$SERVER" 2>/dev/null
wait 2>/dev/null
PIDS=()
python3 tools/scale/region_stress_report.py "$OUT"
