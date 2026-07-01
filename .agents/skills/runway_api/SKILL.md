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
- `RUNWAY_FEED`: Absolute path to the timeline feed inbox JSONL file.
- `RUNWAY_CWD_FILE`: Absolute path to the file tracking the terminal's current directory.

---

## 1. Post to the Activity Feed

You can post markdown updates, build reports, deployment logs, or daily recaps directly to the **Posts** tab using the built-in shell helper `runway-post`.

### Usage
```bash
# Post a simple note (author defaults to "agent")
runway-post "Auth migration complete"

# Post with a custom author name
runway-post "deploy-bot" "Production deployed successfully! :rocket:"

# Post with custom author and title
runway-post "linter" "Found 2 warning highlights" "Style Check"

# Post a multiline markdown document from standard input
runway-post "analyzer" "Security Audit" - <<'EOF'
## Shipped Checks
- Code injection check: **Passed**
- Dependency audit: *0 vulnerabilities*

Check logs for details.
EOF
```

---

## 2. Update Card Status and Metadata

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
echo '{"description":"Building release 1.0.0-beta..."}' > "$RUNWAY_CONTROL"

# Update state, name, and description in one go
echo '{"state":"running", "name":"Linter", "description":"Checking types..."}' > "$RUNWAY_CONTROL"
```
Updates written to `$RUNWAY_CONTROL` are processed **instantly** by the app.
