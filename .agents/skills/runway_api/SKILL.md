---
name: runway-integration
description: Harness Runway terminal features including feed posting, state indicators, and title/description configuration.
---

# Runway Integration Skill

This skill explains how agents running inside Runway terminal boxes can fully integrate with the app's visual features (the activity timeline, status dots, and card labels) via terminal command-line interfaces.

## Environment Variables

Each Runway terminal box exposes the following environment variables to its shell:
- `RUNWAY_BOX`: The unique UUID of the terminal card.
- `RUNWAY_CONTROL`: Absolute path to a JSON file controlling the card's metadata and state.
- `RUNWAY_FOCUS_LOG`: Append-only JSONL history of issues entering and leaving Focus.
- `RUNWAY_CWD_FILE`: Absolute path to the file tracking the terminal's current directory.
- `RUNWAY_STATE_PULSE`: Append one byte here after writing state (`printf . >> "$RUNWAY_STATE_PULSE"`). Runway watches this single file, so the card updates at once instead of on the next poll.
- `RUNWAY_SESSION_FILE`: Where Runway's scoped wrappers record the conversation id they bound, so the terminal can offer a resume command.
- `RUNWAY_DURABLE_SESSION_FILE`: The issue-owned provider binding that survives terminal-card removal and app relaunches.
- `RUNWAY_ISSUE`, `RUNWAY_ISSUE_NUMBER`, `RUNWAY_ISSUE_TITLE`, `RUNWAY_ISSUE_URL`: The issue a Focus terminal works on (`owner/repo#123`). Claude reads it at session start, so "work on your issue" needs no pasted title.
- `RUNWAY_CLONE`: The clone whose Focus board owns the terminal, by folder name (`monorepo`, `monosentry`). A worktree container (`monorepo/main`) is named by its container.
- `RUNWAY_AGENT_NAME`: `<clone>-<issue>`, e.g. `monorepo-14202`. Runway's Claude wrapper starts the session under this name, so other sessions can address it.
- `RUNWAY_CLAUDE_SESSION_ID` / `RUNWAY_CODEX_SESSION_ID` / `RUNWAY_GEMINI_SESSION_ID`: Provider conversation IDs. Focus terminals expose them while Focus conversation binding is enabled in Settings (on by default); the quick terminal carries its own kept conversation, rotated only by the `+` button in its header. Runway's wrappers create or resume Claude and Gemini IDs, capture Codex's generated UUID, and remember the last provider used.

---

## 1. Update Card Status and Metadata

You can dynamically update the card's **State Dot (color)**, **Title**, and **Description** at any time.

### Updating State
To change the colored dot next to your terminal card, write a JSON payload to `$RUNWAY_CONTROL`:
```bash
# Set status to active/busy (Green dot)
echo '{"state":"running"}' > "$RUNWAY_CONTROL"

# Set status to needs attention (Amber dot, triggers local Toast notification)
echo '{"state":"needs-action"}' > "$RUNWAY_CONTROL"

# Set status back to idle (Grey dot)
echo '{"state":"idle"}' > "$RUNWAY_CONTROL"
```

### Updating Name or Description
Write a JSON payload to `$RUNWAY_CONTROL` containing `name` and/or `description`:
```bash
# Rename the terminal card title
echo '{"name":"Build Runner"}' > "$RUNWAY_CONTROL"

# Update the right-side gray description text
echo '{"description":"Building release 2.0.0..."}' > "$RUNWAY_CONTROL"

# Update state, name, and description in one go
echo '{"state":"running", "name":"Linter", "description":"Checking types..."}' > "$RUNWAY_CONTROL"
```
Updates written to `$RUNWAY_CONTROL` are processed **instantly** by the app.
Focus terminal names and descriptions are issue-owned and read-only. For those
cards, metadata writes are ignored, the description shows the issue reference
such as `#1234`, and clicking it copies that reference. State updates still apply.

---

## 2. Read Focus Work History

Runway appends an immutable JSON object to `$RUNWAY_FOCUS_LOG` whenever an issue
enters or leaves the Focus board. Reordering cards inside Focus is not logged.

```bash
runway-focus-log
jq -c 'select(.timestamp >= "2026-07-29T08:43:00Z" and .timestamp <= "2026-07-30T05:00:00Z")' "$RUNWAY_FOCUS_LOG"
```

Events contain `timestamp`, `timeZone`, `action`, `repository`, `issueNumber`, `issueTitle`,
`issueState`, `fromLane`, `toLane`, and `cause`. Pair `entered_focus` and
`exited_focus` by repository and issue number to reconstruct work sessions.
`cause: "initial_snapshot"` marks a card that was already focused when logging began.

## 3. Manage the Issue Boards

Runway exposes the board state through `runway-issue`. From a Runway terminal,
the repository is inferred from `RUNWAY_REPOSITORY`; outside one, pass `--repo`.

```bash
runway-issue list
runway-issue list --lane focus
runway-issue focus 123
runway-issue open 123
runway-issue closed 123
runway-issue move 123 --to focus --before 456
```

Pass `--clone <name>` to act on a specific clone's board; inside a Focus terminal it
defaults to `RUNWAY_CLONE`. Runway acts on the board on screen and rejects a command for
another clone. Each Focus issue in the JSON carries `agent`, the session name of its
Claude agent (`<clone>-<issue>`). Moving an issue out of Focus closes its terminal and
ends that agent. Move issues between lanes only when the user asks.

Moving between Open and Closed also updates GitHub. Moving into or out of Focus
updates Runway immediately and persists the order. The command waits for Runway
to acknowledge the request and returns JSON for agents to consume.
