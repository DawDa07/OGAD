#!/bin/bash
# Installs league-limit as a LaunchAgent that starts at login and restarts if killed.
set -euo pipefail

LABEL="com.leaguelimit.watcher"
APP_DIR="$HOME/Library/Application Support/league-limit"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
PYTHON="$(command -v python3)"
SRC="$(cd "$(dirname "$0")" && pwd)/league_limit.py"

mkdir -p "$APP_DIR" "$HOME/Library/LaunchAgents"
cp "$SRC" "$APP_DIR/league_limit.py"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PYTHON</string>
    <string>$APP_DIR/league_limit.py</string>
    <string>watch</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$APP_DIR/watcher.log</string>
  <key>StandardErrorPath</key><string>$APP_DIR/watcher.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
for _ in $(seq 1 20); do
  launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || break
  sleep 0.5
done
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "league-limit installed and running."
echo "Check usage with: python3 \"$APP_DIR/league_limit.py\" status"
