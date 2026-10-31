// Records a real browser session as timestamped frames (CDP screencast), for a GIF slide.
// Import it from a throwaway flow script in the session scratchpad:
//
//   import { openRecorder } from '/Users/angkasa/.claude/skills/walkthrough/gif/recorder.mjs';
//   const { page, start, stop, close } = await openRecorder({ url, viewport: { width: 430, height: 760 } });
//   // ...get the page to the moment just before the step...
//   await start(outDir);
//   // ...the step itself, with waitForTimeout pauses so each state is readable...
//   await stop();          // writes <outDir>/frames/*.jpg and <outDir>/frames.json
//   await close();
//
// Real Chrome (channel 'chrome'), not headless: the brand sites' Cloudflare bot rule answers
// HeadlessChrome with a 403. The window opens off-screen so it does not take over the display.
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

const require = createRequire('/Users/angkasa/Developer/monorepo/main/apps/customers-e2e/package.json');
const { chromium } = require('@playwright/test');

export async function openRecorder({ url, viewport = { width: 430, height: 760 }, deviceScaleFactor = 2, cookies = [] }) {
  const browser = await chromium.launch({ channel: 'chrome', headless: false, args: ['--window-position=3000,3000'] });
  const context = await browser.newContext({ viewport, deviceScaleFactor });
  if (cookies.length) await context.addCookies(cookies);
  const page = await context.newPage();
  if (url) await page.goto(url, { waitUntil: 'networkidle' });

  const session = await context.newCDPSession(page);
  let frames = [];
  let outDir = null;
  session.on('Page.screencastFrame', async ({ data, metadata, sessionId }) => {
    if (outDir) {
      const file = path.join(outDir, 'frames', `${String(frames.length).padStart(4, '0')}.jpg`);
      fs.writeFileSync(file, Buffer.from(data, 'base64'));
      frames.push({ file, t: metadata.timestamp });
    }
    await session.send('Page.screencastFrameAck', { sessionId }).catch(() => {});
  });

  return {
    page,
    async start(dir) {
      outDir = dir;
      frames = [];
      fs.mkdirSync(path.join(dir, 'frames'), { recursive: true });
      await session.send('Page.startScreencast', { format: 'jpeg', quality: 92, everyNthFrame: 1 });
    },
    async stop() {
      await session.send('Page.stopScreencast');
      await page.waitForTimeout(300);
      fs.writeFileSync(path.join(outDir, 'frames.json'), JSON.stringify({ viewport, deviceScaleFactor, frames }, null, 1));
      return frames.length;
    },
    close: () => browser.close(),
  };
}
