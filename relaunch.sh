#!/usr/bin/env bash
# Rebuild and relaunch Runway as a proper .app (no stray terminal windows).
# Agents must invoke via: osascript -e 'do shell script "/path/to/relaunch.sh"'
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Runway"
EXEC_NAME="Runway"
APP="/Applications/Runway.app"

# pgrep and pkill do not see a Runway that was launched outside this shell's
# session: pkill then leaves the old app running, `open` just activates it
# instead of starting the new build, and pgrep reports a launch failure on a
# perfectly good build. ps does see it, so every check here goes through ps.
running() {
  # The installed bundle may still contain a legacy Runway3 executable from
  # an earlier side-by-side install. Match any process launched from this app.
  ps -Ao pid=,comm= | awk -v needle="$APP/Contents/MacOS/" \
    'index($0, needle) { print $1 }'
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

# Replace the bundle instead of merging it. A previous side-by-side install
# left a stale Runway3 executable in Runway.app, which LaunchServices could
# continue to launch even after the new Runway binary was copied in.
python3 -c 'import shutil, sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "$APP"
ditto "dist/$APP_NAME.app" "$APP"
open "$APP"
sleep 2

if [ -n "$(running)" ]; then
  echo "▸ relaunched $APP_NAME ($(date +%H:%M:%S))"
  osascript -e "tell application \"System Events\" to tell (first process whose name is \"$EXEC_NAME\") to set frontmost to true" 2>/dev/null || true
else
  echo "✗ $APP_NAME failed to start"
  exit 1
fi
