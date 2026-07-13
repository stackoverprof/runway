#!/usr/bin/env bash
# Quick iteration: build and relaunch the real app bundle through the GUI session.
set -euo pipefail
cd "$(dirname "$0")"
exec osascript - "$PWD/relaunch.sh" <<'APPLESCRIPT'
on run argv
  do shell script quoted form of (item 1 of argv)
end run
APPLESCRIPT
