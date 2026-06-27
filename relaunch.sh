#!/usr/bin/env bash
# Rebuild and relaunch Runway as a proper .app (no stray terminal windows).
# Agents must invoke via: osascript -e 'do shell script "/path/to/relaunch.sh"'
set -euo pipefail
cd "$(dirname "$0")"

APP="/Applications/Runway.app"

echo "▸ building…"
if ! ./build-app.sh debug 2>&1 | tail -5; then
  echo "✗ build failed"
  exit 1
fi

pkill -x Runway 2>/dev/null || true
ditto dist/Runway.app "$APP"
open "$APP"
sleep 2

if pgrep -x Runway >/dev/null; then
  echo "▸ relaunched Runway ($(date +%H:%M:%S))"
  osascript -e 'tell application "System Events" to tell (first process whose name is "Runway") to set frontmost to true' 2>/dev/null || true
else
  echo "✗ Runway failed to start"
  exit 1
fi
