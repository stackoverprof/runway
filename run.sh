#!/usr/bin/env bash
# Quick iteration: build and relaunch the real app bundle through the GUI session.
# Replaces and relaunches the installed /Applications/Runway.app.
set -euo pipefail
cd "$(dirname "$0")"
exec osascript - "$(printf %q "$PWD/relaunch.sh")" <<'APPLESCRIPT'
on run argv
  do shell script (item 1 of argv)
end run
APPLESCRIPT
