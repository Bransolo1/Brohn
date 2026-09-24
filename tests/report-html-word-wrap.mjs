// Focused offline layout check. Candidate mode injects CSS into the page only;
// current mode checks a new real export without altering its styles or content.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {sha256, overlaps, pinnedTools} from './fixtures/connected-smoke-support.mjs';
const args = process.argv.slice(2), options = {};
for (let i = 0; i < args.length; i += 2) {
  assert.ok(['--html', '--output', '--node-tools-root', '--browser', '--mode'].includes(args[i]) && args[i + 1] && !options[args[i]], 'Supply each named option exactly once');
  options[args[i]] = args[i + 1];
}
for (const key of ['--html', '--output', '--node-tools-root', '--browser']) assert.ok(options[key], `Missing ${key}`);
const mode = options['--mode'] || 'current'; assert.ok(['candidate', 'current'].includes(mode));
const project = path.resolve(import.meta.dirname, '..'), html = await fs.realpath(options['--html']);
const folder = path.resolve(options['--output']);
assert.ok(!overlaps(folder, project) && !overlaps(folder, html), 'Use new external evidence outside source and input report');
await fs.mkdir(folder);
const original = await fs.readFile(html), originalHash = sha256(original);
const css = 'td,th{overflow-wrap:normal;word-break:normal}';
const checks = [], views = [], errors = [];
const check = (value, label) => {assert.ok(value, label); checks.push(label); console.log('PASS', label);};
const tools = await pinnedTools({project, node_tools_root: path.resolve(options['--node-tools-root']), browser_executable: path.resolve(options['--browser'])});
const browser = await tools.playwright.chromium.launch({executablePath: path.resolve(options['--browser']), headless: true});
const expect = tools.playwright.expect.configure({timeout: 5000}); let page, failure;
const words = region => region.evaluate(element => {
  const find = word => {
    const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT), boxes = []; let node;
    while ((node = walker.nextNode())) {
      const regex = new RegExp('\\b' + word + '\\b', 'g'); let match;
      while ((match = regex.exec(node.textContent))) {
        const range = document.createRange(); range.setStart(node, match.index); range.setEnd(node, match.index + word.length);
        boxes.push({word, lines: [...new Set([...range.getClientRects()].map(box => box.top.toFixed(2)))].length});
      }
    }
    return boxes;
  };
  return [...find('participant'), ...find('Unavailable')];
});
async function keyboardScroll(region, label) {
  await expect(region).toHaveAttribute('tabindex', '0'); await expect(region).toHaveAttribute('role', 'region');
  await expect(region).toHaveAttribute('aria-label', /scroll horizontally/i);
  const dimensions = await region.evaluate(el => ({client: el.clientWidth, scroll: el.scrollWidth}));
  assert.ok(dimensions.scroll > dimensions.client, 'The original table should need horizontal scrolling at this width');
  // Focus is reached with the actual Tab key; arrow keys then scroll the region.
  for (let i = 0; i < 10 && !await region.evaluate(el => el === document.activeElement); i++) await page.keyboard.press('Tab');
  await expect(region).toBeFocused();
  const before = await region.evaluate(el => el.scrollLeft);
  for (let i = 0; i < 4; i++) await page.keyboard.press('ArrowRight');
  await expect.poll(() => region.evaluate(el => el.scrollLeft)).toBeGreaterThan(before);
  const right = await region.evaluate(el => el.scrollLeft);
  for (let i = 0; i < 4; i++) await page.keyboard.press('ArrowLeft');
  await expect.poll(() => region.evaluate(el => el.scrollLeft)).toBeLessThan(right);
  check(true, label + ': native Tab focus and arrow keys scroll in both directions');
  return dimensions;
}
try {
  for (const width of [320, 390]) {
    const context = await browser.newContext({viewport: {width, height: 844}}); page = await context.newPage();
    page.on('pageerror', error => errors.push(error.message)); await page.goto(pathToFileURL(html).href);
    const quality = page.getByRole('region', {name: 'Coverage and eligibility; scroll horizontally for more columns', exact: true});
    const text = await page.locator('table').allTextContents(), before = await words(quality);
    if (mode === 'candidate') {await page.screenshot({path: path.join(folder, `original-${width}.png`)}); await page.addStyleTag({content: css});}
    const after = await words(quality);
    check(after.length >= 2 && after.every(item => item.lines === 1), `${width}px: participant and Unavailable remain complete words`);
    check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), `${width}px: quality table does not widen the page`);
    const qualitySize = await keyboardScroll(quality, `${width}px quality`);
    await quality.evaluate(el => {el.scrollLeft = 0;}); await page.screenshot({path: path.join(folder, `${mode}-quality-${width}.png`)});
    await page.getByText('Inspect retained observations (5 rows)', {exact: true}).click();
    const observations = page.getByRole('region', {name: 'Retained observations; scroll horizontally for more columns', exact: true});
    await observations.scrollIntoViewIfNeeded();
    const contained = await observations.evaluate(el => {
      const rect = el.getBoundingClientRect(), table = el.querySelector('table');
      const tokens = [...table.querySelectorAll('td')].flatMap(cell => cell.textContent.match(/[a-f0-9]{32}/g) || []);
      return {left: rect.left, right: rect.right, client: el.clientWidth, scroll: el.scrollWidth,
        overflow: getComputedStyle(el).overflowX, identifier_tokens: tokens.length, pageWidth: document.documentElement.scrollWidth};
    });
    check(contained.identifier_tokens >= 5 && contained.overflow === 'auto' && contained.left >= 0 && contained.right <= width && contained.pageWidth <= width + 1,
      `${width}px: actual long source identifiers stay inside the labelled horizontal-scroll region`);
    // The click focused its summary; Tab reaches this original table's wrapper.
    const observationSize = await keyboardScroll(observations, `${width}px observations`);
    await page.screenshot({path: path.join(folder, `${mode}-observations-${width}.png`)});
    const identifiers = await observations.evaluate(el => {
      const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT), tokens = []; let node, first;
      while ((node = walker.nextNode())) {
        for (const match of node.textContent.matchAll(/[a-f0-9]{32}/g)) {
          const range = document.createRange(); range.setStart(node, match.index); range.setEnd(node, match.index + match[0].length);
          tokens.push([...new Set([...range.getClientRects()].map(rect => rect.top.toFixed(2)))].length);
          first ||= node.parentElement;
        }
      }
      if (first) el.scrollLeft += first.getBoundingClientRect().left - el.getBoundingClientRect().left;
      return tokens;
    });
    check(identifiers.length >= 5 && identifiers.every(lines => lines === 1), `${width}px: exact original identifier tokens remain unfragmented`);
    await page.screenshot({path: path.join(folder, `${mode}-identifiers-${width}.png`)});
    const violations = (await new tools.AxeBuilder({page}).analyze()).violations;
    await fs.writeFile(path.join(folder, `axe-${width}.json`), JSON.stringify(violations, null, 2));
    check(!violations.length, `${width}px: expanded original report has no axe violations`);
    assert.deepEqual(await page.locator('table').allTextContents(), text);
    check(true, `${width}px: table text and all original values remain unchanged`);
    views.push({width, before, after, qualitySize, observationSize, contained, axe_violations: violations.length});
    await context.close();
  }
  check(!errors.length, 'No offline browser exceptions');
} catch (error) {failure = error; await page?.screenshot({path: path.join(folder, 'failure.png'), fullPage: true}).catch(() => {});}
finally {
  await browser.close();
  try {assert.equal(sha256(await fs.readFile(html)), originalHash); check(true, 'Original downloaded HTML bytes remain unchanged');}
  catch (error) {failure ||= error;}
  await fs.writeFile(path.join(folder, 'results.json'), JSON.stringify({schema: 'brohn-offline-report-wrap-check/1.0', status: failure ? 'failed' : 'passed',
    mode, css: mode === 'candidate' ? css : null, original_sha256: originalHash, checks, views, errors, failure: failure?.stack,
    test_sha256: sha256(await fs.readFile(import.meta.filename)), tools: tools.versions,
    scope: mode === 'candidate' ? 'CSS injected into the original downloaded report in memory only; no product/export modification.' : 'Actual supplied export with no injected CSS or altered report content.'}, null, 2));
}
if (failure) {console.error(failure); process.exitCode = 1;}
console.log(JSON.stringify({status: failure ? 'failed' : 'passed', checks: checks.length, folder}));
