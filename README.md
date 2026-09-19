<div align="center">
  <img src="https://raw.githubusercontent.com/stackoverprof/runway/main/Resources/AppIcon.png?runway-v2" width="112" alt="Runway app icon">
  <h1>Runway</h1>
  <p><strong>Your GitHub issues, coding agents, and terminals in one native macOS workspace.</strong></p>

  <p>
    <a href="https://github.com/stackoverprof/runway/releases/latest"><img src="https://img.shields.io/github/v/release/stackoverprof/runway?style=flat-square" alt="Latest release"></a>
    <img src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple" alt="macOS 14 or newer">
    <img src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6">
    <a href="LICENSE"><img src="https://img.shields.io/github/license/stackoverprof/runway?style=flat-square" alt="MIT license"></a>
  </p>

  <p>
    <a href="https://github.com/stackoverprof/runway/releases/latest"><strong>Download</strong></a>
    · <a href="#what-you-get">Features</a>
    · <a href="#agent-native-by-design">Agent integration</a>
    · <a href="#developing-runway">Build locally</a>
  </p>
</div>

Runway is a native cockpit for people who work with several coding agents at
once. It connects assigned GitHub issues, persistent GPU terminals, repository
activity, and pull request progress in one focused workspace.


## Install in a minute

1. Download **`Runway-2.2.1-arm64.dmg`** from
   [GitHub Releases](https://github.com/stackoverprof/runway/releases/latest).
2. Open the DMG and drag **Runway.app** onto **Applications**.
3. Launch Runway.

Runway is currently ad-hoc signed and not notarized. If macOS reports that the
app is damaged or unverified, clear the download quarantine once:

```sh
xattr -dr com.apple.quarantine /Applications/Runway.app
```

Requirements:

- Apple Silicon Mac running macOS 14 or newer
- [GitHub CLI](https://cli.github.com) authenticated with `gh auth login` for
  issues, feeds, people, repositories, and pull requests

The terminal workspace still works without GitHub CLI. GitHub-backed views need
an authenticated session.

## What you get

| | Capability | Why it matters |
| --- | --- | --- |
| 🖥️ | **Persistent GPU terminals** | Run Claude Code, Codex, Gemini, custom agents, or a normal shell in fast libghostty-backed cards. |
| 📡 | **Live GitHub activity** | See pushes, pull requests, reviews, issues, branch activity, and who has been active recently. |
| ⚡ | **Quick terminal** | Toggle a persistent overlay with `⌘⌥Q`. Its agent conversation is kept across app restarts until you ask for a new one. |
| 🧭 | **Issue-driven Focus board** | Drag assigned GitHub issues into Focus to create matching terminals automatically. |
| 🟢 | **Agent-aware status** | Cards report `running`, `needs-action`, or `idle` the moment the agent changes state, plus their current task and description. |
| 🔔 | **Notifications that land** | macOS alerts, in-app alerts for agents waiting in another repository, and a click that focuses the agent that raised it. |
| 💾 | **Local-first workspace cache** | Issues, Focus terminals, ordering, working directories, and pane position appear immediately after relaunch. |
| 🎨 | **Custom branding** | Replace the Activity heading with your own text or a persistent SVG, PNG, JPEG, or other macOS-supported image. |
| 📊 | **Pull request overview** | Compare open and merged pull requests by developer across practical timeframes. |
| 👥 | **People profiles** | Edit local usernames, full names, and avatars consistently across Runway. |

### The activity side

Runway discovers cloned GitHub repositories on your Mac, then polls the selected
repository through your existing authenticated `gh` session. There is no
separate token setup and no personal access token stored by the app. Cached
Feeds, issues, Pulls, and local repository choices render immediately, then
revalidate in the background. Identical requests are coalesced across windows,
reads are concurrency-limited, failures back off automatically, and routine
polling pauses while Runway is inactive.

- A presence strip shows who has been active recently.
- The timeline groups meaningful pushes, PR activity, reviews, issues, and
  branch changes.
- **Runway**, **Feeds**, and **Pulls** tabs separate focused work, repo motion,
  and pull request activity. Feeds includes an optional merge-only filter.
- The Pulls view groups pull requests by developer, sorts developers by merged PRs,
  and supports 1d, 7d, 30d, MTD, and YTD timeframes. Timeframes use creation
  time for open PRs, merge time for merged PRs, and close time for closed PRs.
- The Runway board shows assigned Open and Closed issues, supports local
  ordering, and can close or reopen issues on GitHub through drag and drop.
  Dragging a card against the top or bottom edge auto-scrolls the list.
- Feeds, Runway, and Pulls revalidate on one shared clock, and all three
  refresh when the window becomes active, so no tab lags the others.
- Click **On today's missions** to smoothly collapse or expand the Focus board
  while keeping the Open and Closed issue backlog visible.
- `⌘F` opens tab-specific search for issues, feed events, or pull requests.
- Picking the tab you are already on returns it to the top of its list and
  refetches it. On Feeds the tagline retypes itself so the refresh is visible
  even when nothing new arrived.
- Pulls opens on the month in progress; every launch starts on MTD.
- The searchable repo switcher shows only GitHub repositories cloned on this
  Mac, ordered by the repositories whose Focus boards moved most recently, then
  by the last one selected, then alphabetically. Opening it refreshes the local
  clone list.
- Pull to refresh, infinite history loading, and skeleton states keep the feed
  responsive.

> GitHub's events API is not real time. Events may lag by a minute or two and
> only cover recent history, so presence is a useful signal rather than an
> attendance system.

### The terminal side

The Focus board is the source of truth for the right pane. Each focused issue
creates a terminal with the issue title, stable shell session, and the selected
repository's local clone as its starting directory. For example,
`VISKA-IO/monorepo` starts in `~/Developer/monorepo` when that is its local clone.

- **Accordion layout** always fits every focused terminal into the available
  window height and gives the active terminal more space. `⌘⌥L` rotates the
  same weighted accordion into side-by-side columns for wide monitors.
- Focus terminal headers are issue-owned and read-only. The right-side `#1234`
  reference copies the issue number when clicked. Renaming the GitHub issue
  updates its terminal header without restarting the running session.
- **Focus mode** expands the active terminal to fill the pane.
- **Quick terminal** stays alive behind its bottom-left overlay, and keeps one
  agent conversation: quit Runway, reopen it, and the quick agent resumes the
  session it was in. The `+` button in its header is the only thing that starts
  a new one. Settings → Terminal → Quick terminal picks the folder its shell
  starts in, `~/Developer` included; left empty, it reopens wherever the last
  shell was.
- Right-click any terminal header to copy its agent resume command
  (`claude --resume <id>` or `codex resume <id>`) or the bare session id, so the same conversation can
  be reopened in any other terminal.
- Switching repositories keeps each repository's Focus terminals and running
  agent sessions alive, then restores them when that repository is selected again.
- **Conversation binding** gives each Focus issue a stable agent conversation, so
  a terminal resumes after a Runway relaunch or after the issue leaves and returns
  to Focus. If you stop Claude and run Codex in the same terminal, Runway captures
  Codex's exact session and makes Codex that issue's preferred provider until you
  switch again. On by default, and switchable in Settings → Agents. Removing an
  issue or quitting Runway still stops its process.
- **Terminal font** is set in Settings → Terminal: pick a family from
  the coding faces installed on this Mac, type any other family by hand, and set
  the size. Changes reach every open terminal immediately, without restarting a
  single session. Your own `~/.config/ghostty` is never modified.
- Double-click the top window edge or blank left-header space to fill the screen;
  double-click it again to restore the previous window size and position.
- File drops insert shell-escaped paths directly into the target terminal.
  Images dragged from disk are typed in place; only fileless drags (an image
  dragged out of a web page) are written, into Runway's own drops folder,
  never into `~/Downloads`.
- Agent commands can start as Claude, Codex, Agent, a custom command, or a
  plain shell.
- **Attention is immediate.** A Claude agent reports `needs-action` the instant
  it stops working and hands the turn back, and every state write appends a byte
  to a pulse file Runway watches, so the amber dot lands at once instead of on
  the next poll. `idle` now means the session itself ended.
- An agent needing you in a repository that is not on screen raises an in-app
  alert in the top-right corner. Clicking it switches to that repository and
  focuses that agent; clicking a macOS banner does the same.

## Agent-native by design

Every Runway terminal receives a small local control API. Any agent or script
can update its card without a plugin or network service:

```sh
# Rename the card and describe the current task
echo '{"name":"checkout-fix","description":"running integration tests"}' > "$RUNWAY_CONTROL"

# Update the status dot
echo '{"state":"running"}' > "$RUNWAY_CONTROL"
echo '{"state":"needs-action"}' > "$RUNWAY_CONTROL"
echo '{"state":"idle"}' > "$RUNWAY_CONTROL"
```

Focus terminal titles and issue references are owned by their GitHub issues and
remain read-only. `name` and `description` updates apply only to non-Focus agent
cards; state updates continue to work for Focus terminals.

Run this inside any card to discover everything an agent can do:

```sh
runway-help
```

Every issue entering or leaving the Focus board is appended to the machine-readable
JSONL journal at `$RUNWAY_FOCUS_LOG`. Agents can filter it by timestamp to reconstruct
what was in Focus during a time range, then enrich that history with git or session data.
`runway-focus-log` prints the journal from any Runway terminal.

Agents can manage the issue boards through the same local API:

```sh
runway-issue list
runway-issue focus 123
runway-issue open 123
runway-issue closed 123
runway-issue move 123 --to focus --before 456
```

Wrap any command-line agent for automatic running and idle status:

```sh
runway-agent codex
runway-agent gemini
runway-agent my-custom-agent --flag
```

Claude Code gets richer automatic attention hooks when launched normally as
`claude`. The guide and helper commands live inside Runway's Application Support
directory. Runway does not edit your shell or agent configuration files.

## Keyboard map

| Move | Shortcut | Action |
| --- | --- | --- |
| Focus | `⌘⌥↑` / `⌘⌥↓`, or `⌘⌥←` / `⌘⌥→` in the horizontal layout | Move between agents |
| Reorder | `⌘⌥⇧` with any arrow | Move the focused agent along the stack or row |
| Quick terminal focus | `⌘⌥←` / `⌘⌥→` | Jump to the open quick terminal and back. In the horizontal layout it is the cell left of the first agent, so `⌘⌥←` crosses over from that agent |
| Jump | `⌘1` through `⌘9` | Focus a specific agent |
| Focus mode | `⌘⌥⏎` | Expand or restore the active terminal |
| Quick terminal | `⌘⌥Q` | Show or hide the quick terminal |
| Close window | `⌘⇧W` | Close the current window |
| Find | `⌘F` | Search the active Runway, Feeds, or Pulls tab |
| Change tab | `⌘⌥1` through `⌘⌥3` | Open Runway, Feeds, or Pulls |
| Cycle tabs | `⌘⌥[` / `⌘⌥]` (also `⌘⇧[` / `⌘⇧]`) | Step through Runway, Feeds, and Pulls |
| Change subtab | `⌘⌥,` / `⌘⌥.` | Step through the current tab's own options |
| Jump to subtab | `⌘⌥⇧1` through `⌘⌥⇧5` | Open / Closed, the feed filter, or a Pulls timeframe |
| Switch repository | `⌘R` | Open the repo picker; type to filter, `↑↓` + `⏎` to pick |
| Layout | `⌘⌥L` | Toggle the horizontal terminal accordion |
| Settings | `⌘,` | Open settings and people profiles |

Shortcuts can be customized from **Runway → Settings → Shortcuts**.

## Privacy and local state

- GitHub requests run through your local authenticated `gh` CLI.
- Agent control files, workspace state, cached feed and issue data, and helper
  scripts stay under `~/Library/Application Support/Runway`.
- Runway does not install skills into Claude, Codex, Gemini, or other agent
  configuration directories.
- Runway does not modify `.zshrc`, `.claude`, or equivalent user configuration
  files.

## Developing Runway

Runway is a Swift Package and does not require an Xcode project.

```sh
./run.sh                 # debug build, install, and relaunch the app bundle
./watch.sh               # rebuild and relaunch after Swift source changes
./build-app.sh debug     # assemble dist/Runway.app
./build-app.sh release   # optimized app-bundle build
./package-dmg.sh         # create the drag-to-install release DMG
```

`build-app.sh` bundles the libghostty framework and signs the complete app
bundle ad hoc. `relaunch.sh` replaces `/Applications/Runway.app` and opens it
through the macOS GUI session.

<details>
<summary><strong>Project map</strong></summary>

```text
Sources/Runway/
  Core/         App lifecycle, windows, keyboard monitors, notifications
  Models/       Agent cards, workspace persistence, people profiles
  Services/     GitHub data, Focus history, caching, local control API
  Terminal/     Ghostty host, terminal sessions, quick terminal, theme
  Utils/        Key bindings, pointer behavior, inline editing
  Views/        Activity feed, terminal cards, settings, profiles
```

GhosttyKit is pinned to a known commit in `Package.swift` because libghostty's C
API is still evolving.

</details>

## License

Runway is available under the [MIT License](LICENSE).
