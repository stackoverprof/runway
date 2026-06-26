#!/usr/bin/env bash
# Poor-man's hot reload (no Xcode needed): on any Swift file save, rebuild and
# relaunch the app. ~3s per cycle. State resets each reload.
# Usage: ./watch.sh        (Ctrl-C to stop)
set -uo pipefail
cd "$(dirname "$0")"

sig() { find Sources -name '*.swift' -exec stat -f '%m %N' {} + | sort; }

reload() {
  echo "▸ building…"
  if swift build 2>&1 | tail -3; then
    pkill -x Runway 2>/dev/null || true
    "$(swift build --show-bin-path)/Runway" >/dev/null 2>&1 &
    echo "▸ relaunched $(date +%H:%M:%S)"
  else
    echo "✗ build failed — fix and save again (app left running)"
  fi
}

trap 'pkill -x Runway 2>/dev/null; exit 0' INT TERM

reload
last="$(sig)"
echo "▸ watching Sources/ … (Ctrl-C to stop)"
while true; do
  sleep 1
  now="$(sig)"
  [ "$now" != "$last" ] && { last="$now"; reload; }
done
