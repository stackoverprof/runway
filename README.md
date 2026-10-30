<div align="center">
  <img src="https://raw.githubusercontent.com/stackoverprof/runway/main/Resources/AppIcon.png?runway-v3" width="112" alt="Runway app icon">
  <h1>Runway 3</h1>
  <p><strong>A cockpit for a team of coding agents: a controller above every flight, a pilot flying one issue, a crew on each of its parts.</strong></p>
</div>

> This is the `v3` branch. It is an experiment, installed beside the Runway
> you work in rather than replacing it. v2 ships from `main`.

## The idea

You are one person with a team of agents. Runway 3 gives that team a shape
borrowed from aviation, and binds it to GitHub so the whole team can see it:

| Rank | What it is | What it answers for |
| --- | --- | --- |
| **Air Traffic Controller** | one agent, above every flight | anything, anywhere: it makes flights and gives orders |
| **Pilot** and **Copilot** | one agent each, per flight | one issue: its order, what it waits on, when it is done |
| **Crew** | one agent per sub-issue | that sub-issue, in its own worktrees |

A **flight is an issue**. Its **crews are that issue's sub-issues**. Nothing
is stored in a private board: GitHub's own parent and sub-issues hold the
hierarchy, so a teammate without Runway sees the same thing you do.

## The window

Three panes, left to right:

- **Activity.** Who is in the office, the issues assigned to you with the
  Open and Closed switch, the repository's feed and its pull requests by dev.
  Clicking an issue puts it in the air.
- **The flight.** Its route, one leg per crew, with the aircraft where it is
  now. A pilot and a copilot terminal above, and under them the issue's own
  Acceptance, the pull requests that name it, the walkthrough slides, and the
  conversation it lives in, with a draft box for a reply only you can send.
- **The crew.** One box per crew, an accordion that never scrolls. Stood down
  it is a card; brought up it is that crew's Claude session, and standing it
  down keeps the conversation for next time.

## What an agent can do

Every session Runway starts gets the `runway` command and a role card telling
it who it is, what it answers for, who it reports to, and this Runway's house
rules, which live in Settings and are never committed to a repository.

```sh
runway whoami                      # your rank, your flight, your rules
runway list                        # the flights assigned to you, crews under each
runway show 26                     # one flight and its crews
runway flight create --title "Saffran" --crew "Web" --crew "App"
runway crew add --title "Catering" --flight 26
runway crew adopt 16176            # take an existing issue as a crew
runway close 27                    # or reopen
```

So "see Slack, make a flight called Saffran, crews are web and app" is
something the controller can simply do.

## Running it beside v2

```sh
RUNWAY_FLAVOR=3 ./run.sh
```

That builds and relaunches **Runway 3.app** only: its own bundle id, its own
state folder, its own `runway3://` scheme. Neither build touches the other's
agents, boards or settings. Plain `./run.sh` on `main` drives v2.

Requirements: Apple Silicon, macOS 14 or newer, [GitHub CLI](https://cli.github.com)
signed in, and Claude Code on your PATH. v3 flies Claude only.
