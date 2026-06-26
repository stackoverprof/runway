# Runway

A native macOS cockpit for running a fleet of coding agents next to a live
GitHub activity feed for your team's repo. Built in SwiftUI (macOS 14+, Swift 6).

```
┌─────────────────────────┬──────────────────────────────────┐
│  Activity        [repo▾]│  ┌────────────────────────────┐  │
│  RECENTLY IN THE OFFICE │  │ ● agent1                ✎  │  │
│   ● alice    active now │  │  …live terminal…           │  │
│   ● bob      idle 4h    │  └────────────────────────────┘  │
│                         │  ┌────────────────────────────┐  │
│  ● pushed  feature/…    │  │ ● agent2                ✎  │  │
│  ● opened PR #1234 …    │  │  …live terminal…           │  │
│  ● merged  #1230 → main │  └────────────────────────────┘  │
│  …                      │              [ + ]               │
└─────────────────────────┴──────────────────────────────────┘
   GitHub activity feed         Agent terminal cards
```

## The two panes

### Left — GitHub activity feed

A custom feed for one repo, polled every 45s through your own `gh` CLI (no PAT,
no token setup — it reuses your existing `gh auth`).

- **Presence** ("RECENTLY IN THE OFFICE") — teammates active in the last ~6h,
  each shown as *active now* / *🔥 on a roll* / *idle Nh*, with real GitHub
  avatars.
- **Timeline** of pushes, PRs (opened / merged), branch creates, reviews, and
  issue open/close — color-coded by intent: **green** = creation,
  **blue** = push / progress, **purple** = closure / merge.
- **Searchable repo switcher** in the header, **overscroll-to-refresh**, and
  **load skeletons** so the pane never jumps from empty to full.

> Note: the feed reads GitHub's *events* API, which lags by a minute or two and
> only covers recent activity (roughly the last 300 events / 90 days). So
> presence is a good "who's around" signal, not real-time precision, and very
> quiet collaborators may not appear.

### Right — agent terminal cards

A scrollable column of resizable cards, each a real GPU terminal
([libghostty](https://github.com/ghostty-org/ghostty) via GhosttyKit) — run
Claude Code, Codex, or any shell, one agent per card.

- Add / close / rename / describe cards (or let the running agent label
  itself — see below); focus glow on the active one.
- **Accordion** and **solo** layouts; drag the bottom edge to resize; drag a
  file in to drop its path.
- A persistent **quick terminal** overlay (⌘⌥Q) that keeps running in the
  background.
- Layout (cards, names, sizes, mode) **persists** across relaunches.

### Agent status & self-labeling

Every card exposes a control channel at `$RUNWAY_CONTROL` (a file path unique to
that card, set in its shell environment). **Anything running inside a card can
update that card live** by writing JSON to it — so a session can proactively
present itself however it likes:

```sh
# A running agent renaming + describing its own card to reflect current work:
echo '{"name":"refactor-auth","description":"running the test suite"}' > "$RUNWAY_CONTROL"

# State drives the header dot:
echo '{"state":"running"}' > "$RUNWAY_CONTROL"
```

- `name` / `description` — the card header text (each capped at 40 chars). A
  session can rename itself as it moves between tasks, so you can tell your
  agents apart at a glance instead of staring at four identical `agentN` boxes.
- `state` — the header dot: `idle`, `running`, or `needs-action`.

For **Claude Code**, `state` is reported automatically with zero setup: Runway
points each card's shell at a private `ZDOTDIR` that sources your real zsh config
and wraps `claude` to inject state-reporting hooks. Your `~/.claude` and
`~/.zshrc` are never modified. (You can have the agent set its own `name` /
`description` the same way — just ask it to write to `$RUNWAY_CONTROL`.)

## Keyboard

| Shortcut | Action |
| --- | --- |
| `⌘N` / `⌘W` | new card / close focused card |
| `⌘⌥↑` / `⌘⌥↓` | move focus between cards |
| `⌘⌥⇧↑` / `⌘⌥⇧↓` | reorder the focused card |
| `⌘1`–`⌘9` | jump to a card |
| `⌘⌥A` | accordion layout |
| `⌘⌥⏎` | solo / zoom the focused card |
| `⌘⌥Q` | toggle the quick terminal |
| `⌘` + scroll | scroll the card list (it's otherwise locked) |

## Install

Grab the latest [**release**](https://github.com/stackoverprof/runway/releases/latest)
(`Runway-v…-arm64.zip`), then:

1. Unzip and move `Runway.app` to `/Applications`.
2. The app is ad-hoc signed, so macOS flags it as "damaged"/unverified on first
   launch. Clear the download quarantine once, then open it normally:
   ```sh
   xattr -dr com.apple.quarantine /Applications/Runway.app
   ```

**Requirements:** an Apple Silicon Mac (the build is arm64-only) and the
[`gh`](https://cli.github.com) CLI authenticated (`brew install gh && gh auth login`),
which the activity feed shells out to.

## Build & run

This machine targets the Command Line Tools toolchain, so Runway builds as a
Swift Package — no Xcode project required.

```sh
./run.sh                 # quick: swift run, launches the window
./build-app.sh           # assemble a self-contained dist/Runway.app
open dist/Runway.app
./watch.sh               # rebuild + relaunch on every save (~3s; state resets)
```

`build-app.sh` bundles the libghostty framework into the `.app` and re-signs it
ad-hoc, so the bundle runs standalone (without the `.build` directory).

Once full Xcode is installed, `open Package.swift` works too.

**Requirements:** macOS 14+, the [`gh`](https://cli.github.com) CLI authenticated
(`gh auth login`) for the activity feed.

## Project layout

```
Sources/Runway/
  RunwayApp.swift        App entry, split layout, right pane, window + key monitors
  LeftPane.swift         Activity feed UI: header, presence, timeline, skeletons
  GitHubFeed.swift       Data layer — polls the `gh` CLI, parses events & presence
  Workspace.swift        App state: cards, focus, accordion/solo, persistence
  AgentControl.swift     Agent status channel + zero-setup Claude Code hooks
  QuickTerminal.swift    The ⌘⌥Q background terminal overlay
  TerminalSurface.swift  Swappable terminal protocol + the GhosttyKit backing
  TerminalTheme.swift    Terminal theme/colors applied to every surface
  InlineField.swift      Inline-editable name/description fields
```

GhosttyKit is pinned to a specific commit in `Package.swift` — libghostty's C
API is still alpha, so we deliberately avoid tracking a moving branch.
