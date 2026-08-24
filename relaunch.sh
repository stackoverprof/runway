#!/usr/bin/env bash
# Rebuild and relaunch Runway as a proper .app (no stray terminal windows).
# Agents must invoke via: osascript -e 'do shell script "/path/to/relaunch.sh"'
set -euo pipefail
cd "$(dirname "$0")"

APP="/Applications/Runway.app"

# pgrep and pkill do not see a Runway that was launched outside this shell's
# session: pkill then leaves the old app running, `open` just activates it
# instead of starting the new build, and pgrep reports a launch failure on a
# perfectly good build. ps does see it, so every check here goes through ps.
running() {
  ps -Ao pid=,comm= | awk '/Runway\.app\/Contents\/MacOS\/Runway/ { print $1 }'
}

echo "▸ building…"
if ! ./build-app.sh debug 2>&1 | tail -5; then
  echo "✗ build failed"
  exit 1
fi

for pid in $(running); do kill "$pid" 2>/dev/null || true; done
for _ in $(seq 1 20); do
  [ -z "$(running)" ] && break
  sleep 0.5
done
for pid in $(running); do kill -9 "$pid" 2>/dev/null || true; done
sleep 0.5

ditto dist/Runway.app "$APP"
open "$APP"
sleep 2

if [ -n "$(running)" ]; then
  echo "▸ relaunched Runway ($(date +%H:%M:%S))"
  osascript -e 'tell application "System Events" to tell (first process whose name is "Runway") to set frontmost to true' 2>/dev/null || true
else
  echo "✗ Runway failed to start"
  exit 1
fi
