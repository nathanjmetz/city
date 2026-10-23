#!/bin/bash
# Sets up the host's Mac to keep the Neighbors region running on its own,
# from login on, with the Mac kept awake. Run once, in Terminal (this works
# whatever branch the copy of the game was left on):
#   cd ~/dev/city && git fetch origin && git checkout -f --detach origin/main && bash tools/host/install-mac.sh
# It takes over a region already started by hand (same save, so the same
# towns and invite code), and signs in to GitHub in the browser so the
# invite link never changes.
# To stop it for good: launchctl unload ~/Library/LaunchAgents/com.neighbors.host.plist

set -e
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
mkdir -p "$HOME/.neighbors" "$HOME/Library/LaunchAgents"
# A copy outside the repo, so updating the game never changes the script mid-run.
cp "$here/neighbors-host.sh" "$HOME/.neighbors/neighbors-host.sh"
chmod +x "$HOME/.neighbors/neighbors-host.sh"

for tool in cloudflared git gh; do
	command -v "$tool" >/dev/null || { echo "Installing $tool"; brew install "$tool"; }
done
command -v godot >/dev/null || [ -x /Applications/Godot.app/Contents/MacOS/Godot ] \
	|| { echo "Installing Godot"; brew install --cask godot; }

# A region already running by hand: keep its save, then stop it and its
# tunnel so the new one can take over.
data=${NEIGHBORS_DATA:-}
appdata="$HOME/Library/Application Support/Godot/app_userdata/$(sed -n 's/^config\/name="\(.*\)"/\1/p' "$repo/project.godot")"
for pid in $(pgrep -f "scripts/net/server_main.gd" || true); do
	args=$(ps -o args= -p "$pid" || true)
	file=$(echo "$args" | sed -n 's/.*--data \([^ ]*\).*/\1/p')
	cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)
	case "$file" in
		"") file="$appdata/region.json" ;;
		user://*) file="$appdata/${file#user://}" ;;
		/*) ;;
		*) file="$cwd/$file" ;;
	esac
	if [ -z "$data" ] && [ -f "$file" ]; then
		data=$file
	fi
	echo "Stopping the region started by hand (its save: $file)"
	kill "$pid" 2>/dev/null || true
done
pkill -f "cloudflared tunnel.*localhost:9080" 2>/dev/null || true
sleep 3
if [ -z "$data" ]; then
	if [ -f "$HOME/neighbors-region.json" ]; then
		data="$HOME/neighbors-region.json"
	elif [ -f "$appdata/region.json" ]; then
		data="$appdata/region.json"
	else
		data="$HOME/neighbors-region.json"
	fi
fi
echo "The region's save: $data"

plist="$HOME/Library/LaunchAgents/com.neighbors.host.plist"
cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>com.neighbors.host</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/caffeinate</string>
		<string>-i</string>
		<string>/bin/bash</string>
		<string>$HOME/.neighbors/neighbors-host.sh</string>
	</array>
	<key>EnvironmentVariables</key>
	<dict>
		<key>NEIGHBORS_REPO</key><string>${NEIGHBORS_REPO:-$repo}</string>
		<key>NEIGHBORS_DATA</key><string>$data</string>
	</dict>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><true/>
	<key>StandardOutPath</key><string>$HOME/.neighbors/host.log</string>
	<key>StandardErrorPath</key><string>$HOME/.neighbors/host.log</string>
</dict>
</plist>
EOF

# Sign in to GitHub in the browser, so the host can publish the region's
# address and the invite link never changes.
if ! gh auth status >/dev/null 2>&1; then
	echo
	echo "Signing in to GitHub so the invite link never changes."
	echo "Copy the one-time code it shows, press Enter, and approve in the browser."
	gh auth login --hostname github.com --git-protocol https --web || echo "GitHub sign-in skipped; run this script again to finish it."
fi
gh auth status >/dev/null 2>&1 && gh auth setup-git

launchctl unload "$plist" 2>/dev/null || true
launchctl load "$plist"
echo
echo "All set: the Neighbors region now runs on its own and keeps itself up to date."
echo "Log: ~/.neighbors/host.log"
echo "Players open: https://nathanjmetz.github.io/city/?join=YOUR-INVITE-CODE"
