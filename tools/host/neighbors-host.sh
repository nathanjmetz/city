#!/bin/bash
# Keeps the Neighbors region running on the host's Mac, hands-free:
#   - runs the same version of the game as the website (checks every minute,
#     and when a new version goes live, updates and restarts the server; the
#     players' games reconnect on their own and reload the new version)
#   - keeps a free Cloudflare tunnel open so browsers can reach it (wss://)
#   - publishes the tunnel's address to the repo's `region` branch, so the
#     invite link never changes: https://nathanjmetz.github.io/city/?join=CODE
#
# Run it once by hand to try it, or let tools/host/install-mac.sh start it at
# login. Settings (environment variables, all optional):
#   NEIGHBORS_REPO  the game's code           (default ~/dev/city)
#   NEIGHBORS_DATA  the region save file      (default ~/neighbors-region.json)
#   NEIGHBORS_HOST  the host's player name    (default Brawn)
#   NEIGHBORS_PORT  local port                (default 9080)
# Needs: godot, cloudflared, git with push access to the repo (gh auth login).

set -u
REPO=${NEIGHBORS_REPO:-$HOME/dev/city}
DATA=${NEIGHBORS_DATA:-$HOME/neighbors-region.json}
HOST=${NEIGHBORS_HOST:-Brawn}
PORT=${NEIGHBORS_PORT:-9080}
STATE=$HOME/.neighbors
mkdir -p "$STATE"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
GODOT=$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)
API=https://api.github.com/repos/nathanjmetz/city
SERVER_PID=""
TUNNEL_PID=""
CURRENT=""
TUNNEL_URL=""

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

# The commit the website is running: the newest successful web build.
live_sha() {
	curl -fsS "$API/actions/workflows/web-preview.yml/runs?status=success&branch=main&per_page=1" 2>/dev/null \
		| grep -m1 '"head_sha"' | sed 's/.*"head_sha": *"\([0-9a-f]*\)".*/\1/'
}

start_server() {
	log "Starting the region server on $(git -C "$REPO" rev-parse --short HEAD)"
	(cd "$REPO" && exec "$GODOT" --headless -s scripts/net/server_main.gd -- \
		--port "$PORT" --host "$HOST" --data "$DATA") >>"$STATE/server.log" 2>&1 &
	SERVER_PID=$!
}

stop_server() {
	if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
		log "Stopping the region server"
		kill "$SERVER_PID"
		# It saves every few seconds; give it a moment to finish.
		for _ in 1 2 3 4 5 6 7 8 9 10; do
			kill -0 "$SERVER_PID" 2>/dev/null || break
			sleep 1
		done
		kill -9 "$SERVER_PID" 2>/dev/null
	fi
	SERVER_PID=""
}

update_to() {
	log "Updating the game to $1"
	git -C "$REPO" fetch -q origin && git -C "$REPO" checkout -q --detach "$1" \
		&& (cd "$REPO" && "$GODOT" --headless --import >/dev/null 2>&1)
}

start_tunnel() {
	: >"$STATE/tunnel.log"
	cloudflared tunnel --no-autoupdate --url "http://localhost:$PORT" >>"$STATE/tunnel.log" 2>&1 &
	TUNNEL_PID=$!
	TUNNEL_URL=""
	for _ in $(seq 1 60); do
		TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$STATE/tunnel.log" | head -1)
		[ -n "$TUNNEL_URL" ] && break
		sleep 1
	done
	if [ -z "$TUNNEL_URL" ]; then
		log "The tunnel didn't give an address; will try again"
		return 1
	fi
	log "Tunnel open at $TUNNEL_URL"
	publish "wss://${TUNNEL_URL#https://}"
}

# Writes {"server": "wss://..."} to the `region` branch, where every
# player's game looks for it.
publish() {
	local dir=$STATE/region-branch
	if [ ! -d "$dir/.git" ]; then
		git clone -q --branch region --single-branch https://github.com/nathanjmetz/city "$dir" 2>/dev/null \
			|| { rm -rf "$dir"; git init -q "$dir" && git -C "$dir" remote add origin https://github.com/nathanjmetz/city \
				&& git -C "$dir" checkout -q --orphan region; }
	fi
	git -C "$dir" pull -q origin region 2>/dev/null
	# The invite code too, so players never type one (the server logs it).
	local code
	code=$(grep -o 'Invite code: [A-Z0-9]*' "$STATE/server.log" 2>/dev/null | tail -1 | sed 's/Invite code: //')
	printf '{"server": "%s", "code": "%s"}\n' "$1" "$code" >"$dir/server.json"
	git -C "$dir" add server.json
	git -C "$dir" -c user.name="Neighbors host" -c user.email="host@neighbors.invalid" \
		commit -q -m "Region address: $1" 2>/dev/null
	if git -C "$dir" push -q origin region 2>>"$STATE/publish.log"; then
		log "Published the region's address"
	else
		log "Couldn't publish the address (run: gh auth login, then gh auth setup-git). Players can still use a link with &server=$1"
	fi
}

trap 'stop_server; [ -n "$TUNNEL_PID" ] && kill "$TUNNEL_PID" 2>/dev/null; exit 0' INT TERM

log "Neighbors host starting"
while true; do
	sha=$(live_sha)
	if [ -n "$sha" ] && [ "$sha" != "$CURRENT" ]; then
		if update_to "$sha"; then
			stop_server
			CURRENT=$sha
		fi
	fi
	if [ -z "$SERVER_PID" ] || ! kill -0 "$SERVER_PID" 2>/dev/null; then
		start_server
	fi
	if [ -z "$TUNNEL_PID" ] || ! kill -0 "$TUNNEL_PID" 2>/dev/null; then
		start_tunnel
	fi
	sleep 60
done
