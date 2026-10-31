---
name: walkthrough
description: "Turn what Erbin just verified into square slide images (2184x2184 PNGs, a 1092 layout rendered at 2x, under $RUNWAY_WALKTHROUGH_OUT/<issue>/) that he can attach to Slack: one slide per case, each carrying the screenshot, the findings, and a provenance footer. Use whenever he asks for slides, a deck, evidence, proof, screenshots-with-captions, or a walkthrough of a check that was just run. Three slides is the default, not a hard cap: when an issue is too big to fit three, it asks Erbin before going longer. It is an evidence exporter, not a report generator, and it never re-runs the verification itself. Images by default; a slide becomes an animated GIF only when Erbin names the step, e.g. '(gif the payment step)'."
argument-hint: "[n slides, default 3] [--deck to also publish an Artifact]"
allowed-tools: Bash, Read, Write, Edit, Skill, Artifact, mcp__claude-in-chrome__tabs_context_mcp, mcp__claude-in-chrome__tabs_create_mcp, mcp__claude-in-chrome__tabs_close_mcp, mcp__claude-in-chrome__navigate, mcp__claude-in-chrome__computer, mcp__claude-in-chrome__javascript_tool, mcp__claude-in-chrome__find
---

# /walkthrough: verification evidence, as square slides

Take the screenshots and findings **already gathered in this session** and lay them out as square slide images Erbin can drag straight into Slack.

**The job is packaging, not proving.** Never re-run the verification, never go looking for new evidence, and never invent a case that was not actually checked. If there is nothing verified in the session yet, say so and stop.

## Start from the capture log

Before asking what was verified, read `$RUNWAY_WALKTHROUGH_OUT/.work/captures/<date>/manifest.md`. Any session that verified something today should have written rows there while the work happened, and those rows are the candidate slides. Pick from them.

The log is the source because **a before state is usually gone by the time anyone asks for a deck.** On 13271 the empty extras group was deleted the same night it was found, so the dead Add to Cart button could never be photographed again without rebuilding the bug. A shot taken at the moment of diagnosis costs nothing; the same shot a day later costs an afternoon or is simply impossible.

If the log is missing or thin, fall back to whatever the session holds in context and say plainly that the evidence is partial. Never recreate a state just to fill a slide without saying so in the footer.

## Default shape

- **Exactly three slides for the main set.** Always three, whatever the case count, unless Erbin says otherwise. Fewer than three is not allowed without his permission, and so is more than three. Ask in one line before rendering, e.g. "2 slides? only the before/after is verified, the code screen was never saved. or 3 with a re-capture?" Render only after he answers.
  - Never cram a fourth case into slide 3 to stay at three, and never drop a case to reach three without asking.
  - **Follow-up sets are the exception.** When the main set has already been sent and later situation development adds slides, a follow-up set of fewer than three is fine. Mark the follow-up as such in the reply ("follow-up, 1 slide, main set of 3 already sent").
  - If he names a number, that is the answer and no question is needed.
- **Each slide:** mono eyebrow (`EVIDENCE 1 OF 3` + the ticket ref), a short Archivo headline, the screenshot, two or three findings, a provenance footer.
- **Saved on the issue too.** Step 8 puts the same slides in the issue body under `## Walkthrough`, so the evidence lives where the work is tracked, not only in Slack.
- **No Slack post.** Draft only, and only if he asks. Keep any draft to two short paragraphs of plain English.

## Premature protocol: claim the win before the merge lands

When Erbin says **"premature protocol"** (or "claim it done, merging is on the way"), the work is verified in spirit but the last PR has not merged or deployed yet. He wants the done message and its slides out **now**, so the issue stops costing him orchestration attention.

- **Capture now, against whatever already runs the final code:** the PR preview, a local dev server, or production for the parts already live. This is the one case where the skill goes and takes shots itself instead of only packaging earlier ones; take exactly the shots the slides need, nothing more.
- **Still three slides by default** (same ask-first rule if it needs more), one per case, picked for the done message: the thing working, the thing refused or protected, the before/after.
- **Provenance stays true per slide:** `PREVIEW` for a branch preview or localhost, `LIVE PRODUCTION` only for what is really live. Never stamp a preview shot as production because it is about to be.
- **The draft says done, plus one clause that the last PR is merging** (link it), and the next move after it lands. No hedging beyond that clause.
- After the merge, re-check live as usual; reshoot and re-publish only if live differs from the slides.

Erbin named it on 2026-10-21 (#16283, Designer role): one slide of the live page was not enough, the fix PR was waiting on the 20:00 freeze, and he wanted the full three slides from the preview so he could close the loop with Arnar right away.

## GIF slides: only when Erbin asks

**Default is still images.** A slide becomes a GIF only when Erbin names the step in his request, e.g. `/walkthrough (gif the payment step)`. Never turn a slide into a GIF on your own, and only the step he named gets one; the other slides stay PNG.

A GIF slide is the same layout (eyebrow, headline, findings, footer) with the shot area playing the recording. It is **1092x1092** (not 2184: a 2x GIF is several MB for no visible gain in Slack), named `<slug>-N-<case>.gif` next to the PNGs.

The recording has to exist already: this skill never re-runs the flow (see CAPTURE.md, "Recording a step"). If the step was asked for as a GIF but nobody recorded it, say so and ship the PNG instead.

1. **Render the background:** the slide's HTML as usual, but with a solid `#FF00FF` PNG in place of the shot, sized to the crop's aspect ratio. Render it at `--force-device-scale-factor=1`, `--window-size=1092,1092`.
2. **Compose:** `$RUNWAY_WALKTHROUGH/gif/compose.py <bg.png> <frames.json> <out.gif> --crop X Y W H [--start N]`. It finds the magenta area, crops each frame to the evidence (frame pixels are device pixels, so 2x the viewport), pastes it in, keeps the recorded timing, holds the first and last frames, and uses one palette for the whole loop. Pillow goes in a scratchpad venv, never a system install.
3. **Check it:** pull 3 or 4 frames out (start, the change, the end) into a contact sheet and look at them. Aim for under ~2 MB and under ~10 s; trim with `--start`/`--end` rather than speeding it up.

## Examples

`examples.html` (next to this file, images in `examples/`) shows every layout, theme, mark and footer as a real slide, plus a table of which to use when. Open it when choosing a layout, and add a slide to it when a new layout lands.

## Pick a theme per slide

`template.html` carries five themes. Set one on each `<section class="sq" data-theme="...">`, and expect a deck to mix them, because most do: the problem on a storefront, the guard in the dashboard.

| Theme | Use for |
| --- | --- |
| `customer` | the 35 brand sites and the 2 Expo apps |
| `kit` | `@upsell/kit`. Brand-neutral on purpose: a kit slide means every brand |
| `widget` | `upsell-widget`, drawn as an embed on a host page |
| `dashboard` | `upsell-dashboard`, `dashboard-v2` |
| `terminal` | `upsell-api`, `upsell-cli`, workers. Logs, SQL, test output |

**A `customer` slide wears that brand's colors, read from the site, never invented.** React Router sites keep them in `customers/<brand>-web/app/app.css` as `--color-brand` / `--color-paper` / `--color-ink`; Next sites in `customers/<brand>-web/tailwind.config.ts`. Pass them inline on the section. Omit them and it falls back to Upsell green, which is the right answer for a brand you could not find tokens for, and the wrong one for a brand you did not bother to look up.

The screenshot's own surface decides the theme, not the issue's scope tag. A `Kit:` bug photographed on Hraðlestin is still a `kit` slide, because the point is that it hits everyone.

## Phone and tablet shots

Shots from the iOS Simulator or the Android emulator come from the `drive` skill's `shot.sh` (monorepo `.claude/skills/drive/scripts/`): native resolution (about 1200x2600 for a phone) and a clean status bar (9:41, full battery and signal), so a before and an after match. Never use the Maestro MCP `take_screenshot` image as the source; it is a preview, like the Chrome `zoom` capture.

- **Phone LEFT, findings RIGHT** (`.phone` in `template.html`). A portrait phone across the full width wastes two thirds of the square.
- **No device frame, ever.** A full screen goes in `.screen`: the bare screenshot, rounded corners, a hairline and a soft shadow. Erbin dropped frames on 2026-10-21 (#16125): the drawn iPhone rim and drawn Safari bar never looked real, and the frame added nothing the provenance footer does not already say. Never draw a status bar, Dynamic Island, browser bar or bezel.
- **A phone-width web capture** (Playwright or Chrome at 390x844) goes in `.screen` as it is. When the browser itself is part of the point, shoot real Safari on the iOS Simulator (`xcrun simctl openurl booted <url>`, then `shot.sh ios`) instead of drawing one.
- **A crop** of one card or one row uses a plain `.shot` inside `.phone`. Choose by what is at stake: a whole-screen state (empty page, wrong flow, layout) is a full screen; one wrong price or label is a crop.
- **Before and after on one slide** when the pair is the point. Two phones: `.phone.duo` (the `.pair` left at full height, findings right), so the phones stay big. Two wide web shots: a plain `.pair` with findings under. Same device, same screen, same data.
- **Tablet** (POS landscape, Kiosk) is wide enough for the normal `.shot`.
- Theme is still chosen by surface: a brand app is `customer` with that brand's colors (the app's colors live in `customers/<brand>-app`, its theme or tailwind config); POS and Kiosk are `dashboard`.

## Mark the spot

When the point is one spot on the screenshot (a price, a button, a label), mark it so the reader finds it at thumbnail size. In the `render.py` spec, give the shot `"marks": [[x, y, w, h]]` in the source image's pixels; the script places them (by hand: `.hl` + `.mark`, `template.html` "MARK THE SPOT").

- Minimal on purpose: a thin ring with a white edge and a soft halo. No arrows, no dimming, no text on the image.
- **The ring contrasts with the image, never the brand accent.** A red ring vanished on Hamraborg's red header (2026-10-21). The page picks, per slide, the palette color (cobalt, magenta, cyan, yellow, ink) farthest from the pixels around the marks; the numbered dots in the findings use the same color. Override with `"mark": "#hex"` only when the pick is visibly wrong.
- At most three marks. With two or more they are numbered in order; start the matching finding with `{1}`, `{2}`.
- Read the spot's position off the real image (open it, measure), never guess; a ring beside the thing reads as a mistake. Pad the box a little so it does not touch the text.
- A slide whose whole screenshot is the point (a layout, an empty page) gets no mark.

## Provenance is not decoration

The footer states where the screenshot came from, and it must be true:

- `LIVE PRODUCTION` when the shot is from the real deployed system.
- `PREVIEW` when it is a branch preview or a local dev server.
- A simulator or emulator shot names the device after the provenance, e.g. `PREVIEW · iOS SIMULATOR, iPHONE 17 PRO · iOS 26.5` or `PREVIEW · ANDROID 16 EMULATOR, PIXEL 8`. Never let it pass as a real device. A production build on an emulator is `LIVE PRODUCTION` only when it talks to the production backend, and still names the emulator.
- `SIMULATED RESPONSE` when any part of the data was injected or stubbed.

**Never dress an injected response as a real one.** If a preview cannot reach the backend half, say that on the slide rather than quietly showing a stubbed render. When the real thing later becomes reachable, reshoot and replace, do not leave the stub standing.

## Procedure

1. **Collect the cases.** For each: the screenshot path, a headline, two or three findings in plain sentences, and the provenance line. Findings state what the reader can see in the image, not what the code does.
2. **Crop each screenshot** to the evidence first, ending on a clean row boundary: `sips` for a simple cut (see Traps for its offset bug). Take the evidence screenshots themselves at `scale: 1` (the default); a scaled-down source stays soft however the slide is rendered.
3. **Write the spec** (JSON, in the session scratchpad): issue, slug, and per slide the case, theme, brand colors, layout (`shot | split | phone | pair | duo`), headline, shots (with `marks`, `caption`, `after`), findings, provenance, where. The full format is in the header of `render.py`.
4. **Render:** `python3 -I $RUNWAY_WALKTHROUGH/render.py <spec.json>`. It embeds the shots, writes `.work/<issue>/one-N.html`, renders each slide in headless Chrome at 2x, and fails loudly if a slide overflows its square, is not 2184x2184, or two slides are identical. Never upscale a smaller file to hit the size: that is what shipped blurry. Add `--dry` to check without copying.
5. **Read the thumbnail sheet** it prints (`.work/<issue>/thumbs/sheet.png`): every slide at 360px, the size a Slack preview shows. If a headline or the evidence cannot be made out there, crop tighter or add a mark, and render again. Then open one full slide with `Read` and look at the small text.
6. **Copy** happens in step 4 (to `$RUNWAY_WALKTHROUGH_OUT/<issue>/`). Add the folder's row to `.work/INDEX.md` if it is new.
7. **List the paths in the reply.** When the run adds slides to a set that was already sent, say which ones are new ("slide 4 is new"), so the `/draft` that carries them marks only those: `[attach walkthrough #<issue> (slide 4 only)]`.
   A layout the script does not cover yet: write the page from `template.html` by hand, the same way the script does (`:root{--side:1092px !important}`, one slide per file, `--force-device-scale-factor=2 --window-size=1092,1092`), and run the same checks.
8. **Publish them into the issue body**, every time there is an issue to point at (not `unfiled/`):
   ```bash
   $RUNWAY_WALKTHROUGH/publish-to-issue.sh <issue> [repo]   # repo defaults to VISKA-IO/monorepo
   ```
   It commits the issue's slides to the `walkthrough-assets` orphan branch of that repo (git plumbing
   only: no checkout, no worktree, no CI runs on non-`main` pushes) and splices a `## Walkthrough`
   section into the issue body, just before `## References`: one row of side-by-side thumbnails
   (`<img width="32%">` for three, wider for fewer), each linking to its full-size image. Full-width
   slides made the issue one long scroll, so keep them as a row. Re-running replaces both the files and the
   section, so a reshoot updates the issue in place. The repo is private, so these render only for a
   signed-in reader with access, which is everyone who can open the issue. A slide built on a
   SIMULATED RESPONSE still says so on its own footer, so the issue never shows a stub as real.

## Traps, each of which cost a round trip

- **`resize_window` silently keeps a stale viewport (preview only).** It reports success and changes nothing; `innerWidth` stays at the old value even after the real window moves. The only reliable fix: `tabs_close_mcp` every tab so the group is auto-removed, resize the real window with `osascript -e 'tell application "Google Chrome" to set bounds of front window to {0, 33, W, H}'`, then `tabs_context_mcp {createIfEmpty: true}` for a fresh group. Verify with `innerWidth` before capturing.
- **Chrome will not go below ~500px wide.** For a phone-width shot, resize the real window first, then make the fresh tab group, in that order.
- **Full-chrome screenshots waste the square.** Crop to the thing being shown. An uncropped dashboard leaves a third of the slide as dead grey and the point unreadable at Slack thumbnail size.
- **The MCP `zoom` capture is never the deliverable.** Its `scale` argument shrinks the *saved file* too, not just the preview: `scale: 0.3` wrote 328x328 PNGs, which were then stretched to 1092 and shipped blurry to Arnar on 14310 (28 Sep). Even at `scale: 1` the zoom output is bound to the tab's viewport. Use the headless render in step 5.
- **`sips -c H W --cropOffset Y X` ignores the offset on some inputs** and returns a centred crop, so slicing a tall three-slide screenshot gave three copies of the middle slide. Render one slide per file instead of slicing, and check hashes.
- **Every slide size is written at 760 and scaled by `--u`.** Set `--side` (1092 for the headless render) and a new rule must use `calc(<n> * var(--u))` (no unit on the number), never a bare px.
- **A bare px in the slide CSS is a bug.** The capture is 1092px and the stylesheet is written at 760px, so anything not multiplied by `--u` renders ~30% small. The first 13871 deck shipped with 14.5px findings on a 1092px square and was unreadable as a thumbnail.
- **Let the shot take the leftover height.** `.shot` grows and the image is bounded by both axes, so a slide with three short findings puts the slack around the crop instead of leaving a dead band above the footer. If a crop still overflows, the crop is too tall for its findings, not the other way round: check `sq-inner.scrollHeight > clientHeight` before capturing.
- **Crop to a clean row boundary.** A half-cut table row reads as a rendering bug rather than a deliberate crop.
- **Strip both comment kinds from `template.html` before swapping in sections.** HTML comments and the CSS theme notes both quote a literal `<section class="sq" ...>`; a regex that matches the first one lands inside a comment, and the slides render as identical blank squares (hashes match, so step 6 catches it).
- **Patching `XMLHttpRequest.prototype.responseText` globally freezes the page.** If a response must be stubbed to show a render, attach a `readystatechange` listener in a patched `open()` for that one URL and `Object.defineProperty` the value onto **that instance**. Never redefine the prototype getter.
- **Heavy pages block screenshots.** "Script injection timed out" means the renderer is busy, usually rendering thousands of rows. Narrow the date range or filter rather than waiting it out.
- **`javascript_tool` refuses to return URLs and query strings.** Return a hostname or a boolean instead of the full URL.

## Design tokens

Carry these so every walkthrough looks like the same series. Full CSS in `template.html`.

| Role | Value |
| --- | --- |
| Paper | `#F2F6F3` |
| Ink | `#131A17`, muted `#566761`, faint `#7D8F88` |
| Rule | `#D5E1DA`, hard `#B6C8BE` |
| Accent | `#23795A` (the Upsell green, darkened to sit on paper) |
| Screenshot mat | `#DFE8E2` |
| Display | Archivo 600, `-0.024em` |
| Body | Newsreader |
| Mono | JetBrains Mono, for eyebrow, code and footer |

Single light theme on purpose: these are exported images, so they must not depend on the viewer's OS theme.

## `--deck`

Only when asked. Publishes the same cases as a scroll-snap Artifact with the extra context slides (what shipped, the sync, what was deliberately left alone). Load `artifact-design` first. The square PNGs stay the primary output either way.
