#!/usr/bin/env bash
# Quick iteration: build and relaunch the real app bundle through the GUI session.
# RUNWAY_FLAVOR=3 ./run.sh drives the side-by-side build instead.
set -euo pipefail
cd "$(dirname "$0")"
FLAVOR="${RUNWAY_FLAVOR:-}"
exec osascript - "RUNWAY_FLAVOR=$(printf %q "$FLAVOR") $(printf %q "$PWD/relaunch.sh")" <<'APPLESCRIPT'
on run argv
  do shell script (item 1 of argv)
end run
APPLESCRIPT
