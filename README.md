<div align="center">
  <img src="https://raw.githubusercontent.com/stackoverprof/runway/main/Resources/AppIcon.png?runway-v3" width="112" alt="Runway app icon">
  <h1>Runway</h1>
  <p><strong>A native macOS cockpit for a team of coding agents: a controller above every flight, a pilot flying one issue, a crew on each of its parts.</strong></p>
  <p>
    <a href="https://github.com/stackoverprof/runway/releases/latest"><strong>Download the latest release</strong></a>
  </p>
</div>

You are one person with a team of Claude Code agents. Runway gives that team a
shape borrowed from aviation, binds it to GitHub so everyone can see it, and
puts every agent in a real terminal in one window.

Runway 3 is the current Runway. Versions 1 and 2 are archived.

## Install

1. Download `Runway-<version>-arm64.dmg` from the [latest release](https://github.com/stackoverprof/runway/releases/latest).
2. Open it and drag Runway into Applications.
3. Runway is ad-hoc signed and not notarized. If macOS blocks it, run:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Runway.app
   ```

You need Apple Silicon, macOS 14 or newer, the [GitHub CLI](https://cli.github.com)
signed in (`gh auth login`), and [Claude Code](https://claude.com/claude-code)
on your PATH.

## The idea

| Rank | What it is | What it answers for |
| --- | --- | --- |
| **Air Traffic Controller** | one agent, above every flight | anything, anywhere: it makes flights and gives orders |
| **Pilot** (and an optional **Copilot**) | one agent per flight | one issue: its order of work, what it waits on, when it is done |
| **Crew** | one agent per sub-issue | that sub-issue, in its own git worktree |

A **flight is a GitHub issue**. Its **crews are that issue's sub-issues**, and
its **transits are the steps** in the issue's `## Progress` checklist. Nothing
lives in a private board: GitHub's own parent and sub-issues hold the
hierarchy, so a teammate without Runway sees the same thing you do.

## The window

Three panes, left to right.

**Flights.** Your open and landed flights as tickets, pinned ones on top, each
with its priority class and how far along it is. An amber dot on a card's
corner means one of its agents is waiting on you. Next to it, the repository's
activity feed and its pull requests by developer, each tagged with the flight
it belongs to.

**The flight.** A departures-board header with the route and the plane where
the work is now. The pilot's terminal, and under it four tabs:

- **Issue**: the transits as a board (landed, boarding, scheduled), opened at
  the step in play, with the issue's Acceptance as remarks.
- **Pulls**: every pull request of the flight and its crews.
- **Walkthrough**: the evidence slides its agents made.
- **Thread**: the Slack conversation the issue lives in, newest first.

**The crew.** One box per crew. A crew that is up is its own Claude session;
stood down, it is a card, and bringing it back resumes the conversation.

## Keeping the Mac light

- A flight whose agents have all gone quiet stops by itself (after 5 minutes,
  or 15 for a pinned flight; both are settings). Conversations are kept, and
  opening the flight brings the pilot back where it left off.
- The copilot only starts when you click it.
- **Settings > Monitor** shows the Mac's memory and CPU, how much of it Runway
  takes, and where: each Claude session, its MCP servers, every flight by seat
  and process. You can stop a flight from there, and see what agents left
  running after their terminal closed (an emulator, a dev server) with a Quit
  button for each.

## Everything shows at once

GitHub's list and search lag a write by up to a minute. Runway does not wait:
when an agent closes an issue, adopts a crew, reorders steps or retitles a pull
request, through the `runway` command or plain `gh`, the board shows it within
a second and settles once GitHub agrees.

## What an agent can do

Every session Runway starts gets the `runway` command and a role card telling
it who it is, what it answers for, who it reports to, and this Runway's house
rules (Settings > House rules, never committed to a repository).

```sh
runway whoami                      # your rank, your flight, your rules
runway list                        # the flights assigned to you, crews under each
runway show 26                     # one flight and its crews
runway flight create --title "Saffran" --crew "Web" --crew "App"
runway crew add --title "Catering" --flight 26
runway crew adopt 16176            # take an existing issue as a crew
runway close 27                    # land it (or reopen)
```

So "read Slack, make a flight called Saffran, crews are web and app" is
something the controller can simply do.

## Keyboard

| Keys | Does |
| --- | --- |
| ⌘K | Search flights, crews, pull request numbers and commands |
| ⌘F | Search the list on screen |
| ⌘1 to ⌘9 | Open the nth flight |
| ⌘⌃1 to ⌘⌃9 | Read the nth crew |
| ⌘⌥↑ / ⌘⌥↓ | Previous or next flight |
| ⌘⌥← / ⌘⌥→ | Previous or next tab of the flight |
| ⌘⌥↩ | Stand the crew you are reading up or down |
| ⌘⌥Q | Show or hide the ATC panel |
| ⌘R | Switch repository |

Every chord can be changed in Settings > Shortcuts.

## Building from source

```sh
./relaunch.sh       # debug build, installed to /Applications/Runway.app and relaunched
./build-app.sh      # release build in dist/
./package-dmg.sh    # release build packaged as dist/Runway-<version>-arm64.dmg
```

Runway is a Swift package (SwiftUI and AppKit) with terminals rendered by
[libghostty](https://ghostty.org). Its state lives in
`~/Library/Application Support/Runway3`.

## License

[MIT](LICENSE)
