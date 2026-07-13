#!/usr/bin/env bash
# Poor-man's hot reload (no Xcode needed): on any Swift file save, rebuild and
# relaunch the app. ~3s per cycle. State resets each reload.
# Usage: ./watch.sh        (Ctrl-C to stop)
set -uo pipefail
cd "$(dirname "$0")"

sig() { find Sources -name '*.swift' -exec stat -f '%m %N' {} + | sort; }

reload() {
  if osascript - "$PWD/relaunch.sh" <<'APPLESCRIPT'
on run argv
  do shell script quoted form of (item 1 of argv)
end run
APPLESCRIPT
  then
    echo "▸ app bundle rebuilt and relaunched $(date +%H:%M:%S)"
  else
    echo "✗ build failed — fix and save again (app left running)"
  fi
}

trap 'exit 0' INT TERM

reload
last="$(sig)"
echo "▸ watching Sources/ … (Ctrl-C to stop)"
while true; do
  sleep 1
  now="$(sig)"
  [ "$now" != "$last" ] && { last="$now"; reload; }
done
