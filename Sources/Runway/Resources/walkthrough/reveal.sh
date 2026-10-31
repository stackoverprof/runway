#!/bin/bash
# Open the issue's slide folder in Finder with the slides selected, ready to
# drag into Slack. Runway says where that folder is.
#   reveal.sh <issue>            every slide in the folder
#   reveal.sh <issue> 4          only slide 4
#   reveal.sh <issue> 3 4        slides 3 and 4
#
# Slack attaches dropped files in the order Finder hands them over, which is the
# window's display order. An icon view with free placement (or "select every file")
# gives an arbitrary order, so the window is forced to list view sorted by name
# (Finder sorts naturally: 2 before 10), and the files are selected in slide order.
set -euo pipefail

issue="${1:?usage: reveal.sh <issue> [slide ...]}"
shift
dir="${RUNWAY_WALKTHROUGH_OUT:-$HOME/Developer/walkthrough}/$issue"
[ -d "$dir" ] || { echo "no folder: $dir" >&2; exit 1; }

files=()
while IFS= read -r p; do
  name=$(basename "$p")
  n=$(grep -oE -- '-[0-9]+-' <<<"$name" | head -1 | tr -d -)
  if [ $# -eq 0 ]; then
    files+=("$name")
  else
    for want in "$@"; do [ "$n" = "$want" ] && files+=("$name"); done
  fi
done < <(find "$dir" -maxdepth 1 -type f \( -name '*.png' -o -name '*.gif' \) | sort -V)

[ ${#files[@]} -gt 0 ] || { echo "no matching slides in $dir" >&2; exit 1; }

list=""
for f in "${files[@]}"; do
  list+="${list:+, }file \"$f\" of f"
done

osascript <<EOF
tell application "Finder"
  set f to POSIX file "$dir" as alias
  open f
  set w to Finder window 1
  set current view of w to list view
  tell list view options of w
    set sort column to column id name column
    set sort direction of column id name column to normal
  end tell
  select {$list}
  activate
end tell
EOF

printf 'selected in order:\n'; printf '  %s\n' "${files[@]}"
