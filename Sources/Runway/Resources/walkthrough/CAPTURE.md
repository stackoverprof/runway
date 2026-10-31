# Capturing evidence while the work happens

Read by any session that is verifying something, not by `/walkthrough` itself.
`/walkthrough` packages what this produces.

## Why capture up front

The interesting state is the broken one, and it is the one that disappears
first. On 13271 the empty extras group was deleted the night it was found, so
the dead Add to Cart button could not be photographed afterwards at all. Taking
the shot while already looking at the screen costs one tool call. Recreating the
state later costs an afternoon, or is impossible.

## The three moments

Capture at these, and only these. Continuous capture just makes a pile nobody
curates.

1. **The problem, reproducing.** Before any fix. This is the shot that cannot be
   retaken, so if only one gets taken, take this one.
2. **The same view, fixed.** Same page, same viewport, same data where possible.
   A pair only reads as a pair if nothing else moved between the two.
3. **Anything surprising found on the way.** A second bug, a wrong number, a
   thing that turned out to be fine. One shot, not a sequence.

A fourth shot needs a reason. Say what it is in the manifest row.

## Where it goes

```
~/Developer/walkthrough/.work/captures/<YYYY-MM-DD>/
  <issue>-<slug>-<moment>.png      e.g. 13271-empty-extras-before.png
  manifest.md
```

The `.work/` parent is deliberate: `~/Developer/walkthrough/` itself stays nothing but
issue folders, because Erbin drags slides out of it into Slack.

`<moment>` is `before`, `after`, or a short word for a surprise (`gap`,
`overcharge`). `<issue>` is digits only, or `unfiled` when nothing is filed yet.

## Mobile captures

On the iOS Simulator or the Android emulator, take evidence with the `drive`
skill's `shot.sh`, never with the Maestro MCP screenshot:

```bash
<monorepo>/.claude/skills/drive/scripts/shot.sh android ~/Developer/walkthrough/.work/captures/<date>/<issue>-<slug>-before.png
```

It writes native resolution with a fixed 9:41 status bar, so the before and
the after only differ where the app does. Note the device in the manifest row
(`shows` can end with "Pixel 8, Android 16 emulator").

## Recording a step (only when Erbin asks for a GIF)

When the request names a step as a GIF (`/walkthrough (gif the payment step)`), record that step **while doing it**, the same way the before shot is taken while looking at it. Everything else stays a screenshot. Never record unasked.

- Use `~/.claude/skills/walkthrough/gif/recorder.mjs` (usage in its header): a real Chrome window off-screen, streaming every frame the page paints (about 20 a second) to `.work/captures/<date>/<issue>-<slug>-<moment>/frames/` plus `frames.json`. Not the Chrome extension's `gif_creator`: it keeps one frame per action and stamps click circles and a watermark on top.
- Drive the step from a short script in the session scratchpad: get the page to just before the step, `start()`, do the step with pauses (`waitForTimeout` 1 to 2 s on each state the reader must see), `stop()`.
- Headless Chrome is answered with a Cloudflare 403 on the brand sites, which is why the recorder uses real Chrome. Never fake the user agent to get around a bot rule.
- One manifest row for the recording, with the folder as `file` and the states it passes through in `shows` ("3.390 → 3.890 → 3.390 kr as Tígrisrækjur is ticked then unticked").

## The manifest row

One row per shot, appended as it is taken. Without this the folder is a wall of
PNGs and the reason for each is lost with the session.

```markdown
| file | issue | shows | provenance |
| --- | --- | --- | --- |
| 13271-empty-extras-before.png | 13271 | Add to Cart greyed out, no reason given, cart empty | PREVIEW |
| 13271-empty-extras-after.png | 13271 | same product, same cart, button live | PREVIEW |
```

**`shows` states what is visible in the image**, not what the code does. If the
sentence cannot be checked against the picture, rewrite it.

**`provenance` is one of `LIVE PRODUCTION`, `PREVIEW`, `SIMULATED RESPONSE`**,
and it must be true. It is carried straight onto the slide footer, so a wrong
value here becomes a false claim on something dragged into Slack. Anything
stubbed or injected is `SIMULATED RESPONSE`, no matter how real it renders.

## Rules

- **Never delete or repair the broken state before shot 1 exists.** If someone
  else is about to fix it, say so and take the shot first.
- **Crop at capture time** to the thing being shown. A full-chrome screenshot
  wastes most of a square slide and is unreadable at Slack thumbnail size.
- **Match the pair.** Same URL, viewport and data for before and after, or the
  difference reads as something else having changed.
- **A capture is not a claim.** The manifest records what was seen. Deciding
  which shots become slides is `/walkthrough`'s job, later.
