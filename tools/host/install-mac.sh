#!/bin/bash
# Sets up the host's Mac to keep the Neighbors region running on its own,
# from login on, with the Mac kept awake. Run once:
#   bash ~/dev/city/tools/host/install-mac.sh
# To stop it for good: launchctl unload ~/Library/LaunchAgents/com.neighbors.host.plist

set -e
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$HOME/.neighbors" "$HOME/Library/LaunchAgents"
# A copy outside the repo, so updating the game never changes the script mid-run.
cp "$here/neighbors-host.sh" "$HOME/.neighbors/neighbors-host.sh"
chmod +x "$HOME/.neighbors/neighbors-host.sh"

for tool in cloudflared git; do
	command -v "$tool" >/dev/null || { echo "Installing $tool"; brew install "$tool"; }
done
command -v godot >/dev/null || [ -x /Applications/Godot.app/Contents/MacOS/Godot ] \
	|| { echo "Installing Godot"; brew install --cask godot; }

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
		<key>NEIGHBORS_REPO</key><string>${NEIGHBORS_REPO:-$HOME/dev/city}</string>
	</dict>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><true/>
	<key>StandardOutPath</key><string>$HOME/.neighbors/host.log</string>
	<key>StandardErrorPath</key><string>$HOME/.neighbors/host.log</string>
</dict>
</plist>
EOF
launchctl unload "$plist" 2>/dev/null || true
launchctl load "$plist"
echo "The Neighbors region now runs on its own. Log: ~/.neighbors/host.log"
gh auth status >/dev/null 2>&1 || echo "One more step so the invite link never changes: gh auth login, then gh auth setup-git"
