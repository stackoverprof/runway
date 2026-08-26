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
- `RUNWAY_CLAUDE_SESSION_ID` / `RUNWAY_GEMINI_SESSION_ID`: Stable provider conversation IDs. Focus terminals expose them while Focus conversation binding is enabled in Settings (on by default); the quick terminal always carries its own kept conversation, rotated only by the `+` button in its header. Runway's scoped wrappers use them to create or resume the bound conversation. This is tested with Claude only; other agents and models are untested.

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
