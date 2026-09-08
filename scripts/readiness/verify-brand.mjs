import { chromium } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { createServer } from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const out = path.join(root, 'docs/brand');
const tokens = JSON.parse(await readFile(path.join(root, 'www/brand/tokens.json'), 'utf8'));
const luminance = hex => {
  const c = hex.match(/[\da-f]{2}/gi).map(v => parseInt(v, 16) / 255).map(v => v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4);
  return c[0] * .2126 + c[1] * .7152 + c[2] * .0722;
};
const contrast = (a, b) => {
  const [light, dark] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (light + .05) / (dark + .05);
};
const pairs = [];
for (const background of ['canvas', 'surface', 'raised']) {
  for (const foreground of ['text', 'secondary', 'muted', 'accent', 'lavender', 'blue', 'amber', 'rose']) {
    pairs.push({ foreground, background, minimum: 4.5 });
  }
  pairs.push({ foreground: 'control-border', background, minimum: 3 });
  pairs.push({ foreground: 'focus', background, minimum: 3 });
}
pairs.push({ foreground: 'accent-ink', background: 'accent', minimum: 4.5 });
for (const pair of pairs) {
  pair.ratio = contrast(tokens.colours[pair.foreground], tokens.colours[pair.background]);
  pair.passed = pair.ratio >= pair.minimum;
}
const mime = { '.html': 'text/html', '.css': 'text/css', '.svg': 'image/svg+xml', '.ttf': 'font/ttf', '.png': 'image/png', '.md': 'text/plain' };
const server = createServer(async (req, res) => {
  try {
    const requested = decodeURIComponent(new URL(req.url, 'http://127.0.0.1').pathname);
    const file = path.resolve(root, '.' + requested);
    if (!file.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
    const bytes = await readFile(file);
    res.writeHead(200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream' });
    res.end(bytes);
  } catch { res.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const url = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const failures = [];
const views = [];
try {
  const context = await browser.newContext({ viewport: { width: 1400, height: 1000 }, deviceScaleFactor: 1 });
  const page = await context.newPage();
  page.on('pageerror', error => failures.push(error.message));
  await page.goto(url + '/docs/brand/preview.html', { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: path.join(out, 'brand-board.png'), fullPage: true });
  await page.locator('#interface').screenshot({ path: path.join(out, 'interface-direction.png') });
  const desktop = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa']).analyze();
  views.push({ viewport: '1400px', violations: desktop.violations.map(v => ({ id: v.id, impact: v.impact, nodes: v.nodes.map(n => n.target) })) });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: path.join(out, 'brand-board-narrow.png'), fullPage: true });
  const narrow = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa']).analyze();
  views.push({ viewport: '390px', violations: narrow.violations.map(v => ({ id: v.id, impact: v.impact, nodes: v.nodes.map(n => n.target) })) });
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
  if (overflow) failures.push('Narrow layout has horizontal overflow');
  await page.emulateMedia({ reducedMotion: 'reduce' });
  const reducedMotion = await page.evaluate(() => getComputedStyle(document.documentElement).scrollBehavior === 'auto');
  if (!reducedMotion) failures.push('Reduced-motion scroll behavior');
  await page.setViewportSize({ width: 256, height: 256 });
  await page.goto(url + '/www/brand/brohn-app-icon.svg');
  await page.screenshot({ path: path.join(root, 'www/brand/brohn-app-icon-256.png'), omitBackground: true });
  const report = { schema: 'brohn-brand-verification/0.1.0', browser: browser.version(),
    status: pairs.every(p => p.passed) && views.every(v => v.violations.length === 0) && failures.length === 0 ? 'passed' : 'needs_correction',
    colour_pairs: pairs, views, failures, reduced_motion_checked: reducedMotion,
    limitations: ['Contrast pairs and automated checks cover this design preview, not the future whole application.', 'Keyboard/screen-reader research workflows and undergraduate usability still require the planned acceptance journeys.'] };
  await mkdir(out, { recursive: true });
  await writeFile(path.join(out, 'verification.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({ status: report.status, contrast_pairs: pairs.length, failed_pairs: pairs.filter(p => !p.passed), views, failures }));
  if (report.status !== 'passed') process.exitCode = 1;
} finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }
