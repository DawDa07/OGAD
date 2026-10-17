#!/bin/bash
# Removes league-limit. Asks you to type a phrase first, as a little friction against impulse uninstalls.
set -euo pipefail

LABEL="com.leaguelimit.watcher"
PHRASE="i am choosing to play more league today"

echo "To uninstall, type exactly: $PHRASE"
read -r answer
if [ "$answer" != "$PHRASE" ]; then
  echo "Didn't match. Still installed."
  exit 1
fi

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
echo "league-limit uninstalled. Your play history is kept in ~/Library/Application Support/league-limit."
