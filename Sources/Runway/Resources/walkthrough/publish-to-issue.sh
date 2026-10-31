#!/usr/bin/env bash
# Publish one issue's walkthrough slides into that issue's body.
#
#   publish-to-issue.sh <issue> [repo]        repo defaults to VISKA-IO/monorepo
#
# 1. Commits ~/Developer/walkthrough/<issue>/*.png|gif onto the orphan branch
#    `walkthrough-assets` of the repo, under <issue>/, with git plumbing only: no checkout,
#    no worktree, nothing staged in the main checkout. Re-running replaces that issue's files.
# 2. Splices a `## Walkthrough` section into the issue body, right before `## References`
#    (or at the end), replacing any earlier one. Every other section stays untouched.
#
# Why a branch in the same repo: the repo is private, so images must live where every
# reader of the issue already has access. GitHub renders a same-repo `blob/...?raw=true`
# image for anyone who can open the issue. No workflow triggers on non-main pushes.
set -euo pipefail

issue="${1:?usage: publish-to-issue.sh <issue> [repo]}"
repo="${2:-VISKA-IO/monorepo}"
branch="walkthrough-assets"
src="$HOME/Developer/walkthrough/$issue"
checkout="$HOME/Developer/${repo#*/}/main"
[ -d "$checkout/.git" ] || [ -f "$checkout/.git" ] || checkout="$HOME/Developer/${repo#*/}"

shopt -s nullglob
files=("$src"/*.png "$src"/*.gif)
[ ${#files[@]} -gt 0 ] || { echo "no slides in $src" >&2; exit 1; }

git_() { git -C "$checkout" "$@"; }

# Current tip of the assets branch, if it exists.
parent=""
if git_ fetch -q origin "+refs/heads/$branch:refs/remotes/origin/$branch" 2>/dev/null; then
  parent=$(git_ rev-parse "refs/remotes/origin/$branch")
fi

# Build the issue's subtree from the slide files.
entries=""
for f in "${files[@]}"; do
  blob=$(git_ hash-object -w "$f")
  entries+="100644 blob $blob	$(basename "$f")"$'\n'
done
subtree=$(printf '%s' "$entries" | git_ mktree)

# Root tree = the old root with <issue>/ replaced by the new subtree.
root_entries=""
if [ -n "$parent" ]; then
  root_entries=$(git_ ls-tree "$parent" | awk -F'\t' -v n="$issue" '$2 != n')
  [ -n "$root_entries" ] && root_entries+=$'\n'
fi
root_entries+="040000 tree $subtree	$issue"$'\n'
root=$(printf '%s' "$root_entries" | git_ mktree)

msg="walkthrough: slides for #$issue"
if [ -n "$parent" ]; then
  if [ "$(git_ rev-parse "$parent^{tree}")" = "$root" ]; then
    commit="$parent"
  else
    commit=$(git_ commit-tree "$root" -p "$parent" -m "$msg")
  fi
else
  commit=$(git_ commit-tree "$root" -m "$msg")
fi
[ "$commit" = "$parent" ] || git_ push -q origin "$commit:refs/heads/$branch"

# Splice the section into the issue body.
tmp=$(mktemp)
gh issue view "$issue" -R "$repo" --json body -q .body > "$tmp"
# One row of thumbnails, each linking to its full-size image. Full-width slides in a body
# made the issue a long scroll; a fixed per-slide width keeps them side by side.
n=${#files[@]}
pct=$(( n >= 3 ? 32 : (n == 2 ? 49 : 60) ))
section=$'## Walkthrough\n\n<p>\n'
for f in "${files[@]}"; do
  name=$(basename "$f")
  label="${name%.*}"
  url="https://github.com/${repo}/blob/${branch}/${issue}/${name}?raw=true"
  section+="<a href=\"${url}\"><img src=\"${url}\" alt=\"${label}\" width=\"${pct}%\"></a>"$'\n'
done
section+=$'</p>\n'
SECTION="$section" python3 - "$tmp" <<'PY'
import os, re, sys
p = sys.argv[1]
body = open(p).read().rstrip("\n") + "\n"
section = os.environ["SECTION"]
# Drop an earlier Walkthrough section (up to the next H2 or the end).
body = re.sub(r"## Walkthrough\n.*?(?=^## |\Z)", "", body, flags=re.S | re.M)
m = re.search(r"^## References", body, flags=re.M)
if m:
    body = body[: m.start()] + section + "\n" + body[m.start():]
else:
    body = body.rstrip("\n") + "\n\n" + section
open(p, "w").write(body)
PY
gh issue edit "$issue" -R "$repo" --body-file "$tmp" >/dev/null
rm -f "$tmp"
echo "published ${#files[@]} slide(s) to #$issue ($repo, branch $branch @ ${commit:0:10})"
