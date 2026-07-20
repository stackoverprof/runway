<div align="center">
  <img src="Resources/AppIcon.png" width="112" alt="Runway app icon">
  <h1>Runway</h1>
  <p><strong>Your coding agents, your team, and your repo in one native macOS workspace.</strong></p>

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
once. It combines persistent GPU terminals with a live GitHub activity feed, so
the work happening in your shells and the work landing in your repo stay in the
same field of view.

```text
┌─────────────────────────────┬────────────────────────────────────┐
│ Activity                    │ Agent terminals                    │
│                             │                                    │
│ RECENTLY IN THE OFFICE      │  ● auth-refactor        running   │
│ ● alice  active now         │  ┌──────────────────────────────┐  │
│ ● bob    idle 24m           │  │ Claude Code, Codex, or shell │  │
│                             │  └──────────────────────────────┘  │
│ pushed feature/live-feed    │                                    │
│ opened PR #1234             │  ● release-check        waiting   │
│ merged PR #1230 into main   │  ┌──────────────────────────────┐  │
│                             │  │ Persistent GPU terminal      │  │
└─────────────────────────────┴────────────────────────────────────┘
```

## Install in a minute

1. Download the latest **`Runway-1.0.1-arm64.dmg`** from
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
  the activity feed

The terminal workspace still works without GitHub CLI. Only the activity feed
needs it.

## What you get

| | Capability | Why it matters |
| --- | --- | --- |
| 🖥️ | **Persistent GPU terminals** | Run Claude Code, Codex, Gemini, custom agents, or a normal shell in fast libghostty-backed cards. |
| 📡 | **Live GitHub activity** | See pushes, pull requests, reviews, issues, branch activity, and who has been active recently. |
| ⚡ | **Quick terminal** | Toggle a persistent overlay with `⌘⌥Q` without losing its session. |
| 🧭 | **Focus-first navigation** | Create, close, jump between, reorder, solo, and accordion agents entirely from the keyboard. |
| 🟢 | **Agent-aware status** | Cards can report `idle`, `running`, or `needs-action`, plus their current task and description. |
| 🔔 | **Native notifications** | Get macOS alerts and configurable sounds when an agent needs attention. |
| 💾 | **Workspace memory** | Card names, sizes, working directories, layout mode, and pane position survive relaunches. |
| 👥 | **People profiles** | Give teammates friendly names and custom avatars in the activity view. |

### The activity side

Runway polls the selected repository through your existing authenticated `gh`
session. There is no separate token setup and no personal access token stored by
the app.

- A presence strip shows who has been active recently.
- The timeline groups meaningful pushes, PR activity, reviews, issues, and
  branch changes.
- Dedicated **Feeds**, **Merge**, and **Posts** tabs separate repo motion from
  agent-authored updates.
- The searchable repo switcher can open any accessible `owner/repo`.
- Pull to refresh, infinite history loading, and skeleton states keep the feed
  responsive.

> GitHub's events API is not real time. Events may lag by a minute or two and
> only cover recent history, so presence is a useful signal rather than an
> attendance system.

### The terminal side

Each agent lives in a resizable card with its own shell session. Cards can be
renamed, described, reordered, focused, or collapsed without restarting the
underlying terminal.

- **Normal mode** gives every card an independently resizable height.
- **Accordion mode** fits every agent into the available window height.
- **Solo mode** expands the focused agent to fill the pane.
- **Quick terminal** stays alive behind its bottom-left overlay.
- File drops insert shell-escaped paths directly into the target terminal.

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

Run this inside any card to discover everything an agent can do:

```sh
runway-help
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

Agents can also post Markdown updates to the **Posts** timeline:

```sh
runway-post "Build passed on macOS 14 and 15"
runway-post "release-bot" "Production deployment complete" "Deploy"
```

## Keyboard map

| Move | Shortcut | Action |
| --- | --- | --- |
| Create | `⌘N` | Add and focus a new agent |
| Close | `⌘W` | Close the focused agent |
| Focus | `⌘⌥↑` / `⌘⌥↓` | Move between agents |
| Jump | `⌘1` through `⌘9` | Focus a specific agent |
| Reorder | `⌘⌥⇧↑` / `⌘⌥⇧↓` | Move the focused card |
| Layout | `⌘⌥A` | Toggle accordion mode |
| Zoom | `⌘⌥⏎` | Toggle solo mode |
| Quick terminal | `⌘⌥Q` | Show or hide the quick terminal |
| Settings | `⌘,` | Open settings and people profiles |
| Scroll cards | `⌘` + scroll | Scroll the agent list |

Shortcuts can be customized from **Runway → Settings → Shortcuts**.

## Privacy and local state

- GitHub requests run through your local authenticated `gh` CLI.
- Agent control files, workspace state, cached feed data, and helper scripts stay
  under `~/Library/Application Support/Runway`.
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
  Services/     GitHub feed, agent posts, local control API
  Terminal/     Ghostty host, terminal sessions, quick terminal, theme
  Utils/        Key bindings, Markdown rendering, inline editing
  Views/        Activity feed, terminal cards, settings, profiles
```

GhosttyKit is pinned to a known commit in `Package.swift` because libghostty's C
API is still evolving.

</details>

## License

Runway is available under the [MIT License](LICENSE).
