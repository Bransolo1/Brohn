import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { chromium } from '@playwright/test';
const folder = path.resolve(process.argv[2]);
assert.ok(path.basename(folder).startsWith('brohn-task-plot-wording-'));
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const checks = [];
try {
  for (const width of [320, 680]) {
    const file = path.join(folder, `fast-${width}.svg`), svg = await fs.readFile(file, 'utf8');
    const page = await browser.newPage({ viewport: { width: width + 20, height: 440 } });
    await page.setContent(`<html lang="en"><head><title>Saved task chart layout check</title></head><body style="margin:10px;background:#11171c">${svg}</body></html>`);
    await page.evaluate(() => document.fonts.ready);
    const bounds = await page.locator('svg > text').evaluateAll(nodes => nodes.filter(n => ['353.000', '373.000'].includes(n.getAttribute('y'))).map(n => {
      const b = n.getBBox(); return { text: n.textContent, x: b.x, right: b.x + b.width };
    }));
    assert.equal(bounds.length, 2);
    for (const b of bounds) assert.ok(b.x >= 0 && b.right <= width, JSON.stringify({ width, ...b }));
    assert.ok(bounds.some(b => b.text === 'Grey = non-scoring position; square = unavailable'));
    await page.screenshot({ path: path.join(folder, `fast-${width}.png`) });
    checks.push({ width, bounds, svg_sha256: createHash('sha256').update(svg).digest('hex') });
    await page.close();
  }
  await fs.writeFile(path.join(folder, 'layout-results.json'), JSON.stringify({ passed: true, checks,
    scope: 'Real browser font/layout inspection of both complete saved FAST chart sizes. No new study, inference or changes to plotted values.' }, null, 2));
  console.log('PASS2 actual browser legend layout checks');
} finally { await browser.close(); }
