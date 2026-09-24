// Inspect the actual saved-report layout; no processing jobs or real studies.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn, spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chromium, expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const folder = path.resolve(process.argv[2]);
const diagnostic = process.argv.includes('--diagnostic');
assert.ok(path.basename(folder).startsWith('brohn-derived-access-'));
const config = JSON.parse(await fs.readFile(path.join(folder, 'fixture.json'), 'utf8'));
const output = path.join(folder, `layout-${Date.now()}`);
await fs.mkdir(output);
const rscript = path.resolve('../../work/native-r/bin/Rscript.exe');
const env = {...process.env, LC_ALL:'C', R_LIBS_USER:path.resolve('../../work/r-library-brohn-restore'),
  BROHN_PUBLICATION_PYTHON:path.resolve('../../work/tooling/methods-venv/Scripts/python.exe'),
  BROHN_PUBLICATION_NATIVE_MANIFEST:path.resolve('../../work/tooling/brohn-native/publication-guard.json')};
const files = ['R/platform-app.R', 'R/platform-data-views.R', 'R/platform-signal-value-views.R', 'R/platform-report-coverage.R', 'www/brohn.css', 'www/platform-ui.js'];
const hashes = async () => Object.fromEntries(await Promise.all(files.map(async file =>
  [file, createHash('sha256').update(await fs.readFile(file)).digest('hex')])));
const sourceHashes = await hashes(), checks = [], scans = [], errors = [];
let log = '';
const helper = mode => {
  const result = spawnSync(rscript, ['--vanilla', 'tests/fixtures/researcher-derived-access.R', mode, folder],
    {env, windowsHide:true, encoding:'utf8'});
  assert.equal(result.status, 0, result.stderr || result.stdout);
};
const check = label => {checks.push(label); console.log('PASS', label);};
await fs.rm(path.join(folder, 'stop.researcher'), {force:true});
const server = spawn(rscript, ['--vanilla', 'tests/fixtures/researcher-derived-access.R', 'researcher', folder], {env, windowsHide:true});
server.stdout.on('data', chunk => log += chunk);
server.stderr.on('data', chunk => log += chunk);
const browser = await chromium.launch({channel:'chrome', headless:true});
const context = await browser.newContext({viewport:{width:1440, height:1080}});
const page = await context.newPage();
page.on('pageerror', error => errors.push(error.message));
const base = 'http://127.0.0.1:3935/';
const button = name => page.getByRole('button', {name, exact:true});
async function openReport() {
  await button('Data library').click();
  await page.getByLabel('Search datasets', {exact:true}).fill(config.dataset_title);
  await page.locator(`[data-brohn-event="open_dataset"][data-brohn-value='"${config.dataset_id}"']`).click();
  await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${config.report_id}"']`).click();
  await expect(page.locator('#report_download')).toHaveAttribute('href', /session\//, {timeout:20000});
  await page.waitForFunction(() => !document.documentElement.classList.contains('shiny-busy'));
}
async function inspect(label) {
  await page.evaluate(() => window.scrollTo({top:0, behavior:'instant'}));
  const layout = await page.locator('.brohn-page').evaluate(root => {
    const flatten = node => getComputedStyle(node).display === 'contents' ? [...node.children].flatMap(flatten) : [node];
    const visible = [...root.children].flatMap(flatten).filter(node => node.getBoundingClientRect().height > 1);
    return visible.map((node, index) => ({
      id:node.id, title:node.querySelector('h1,h2,h3')?.textContent || node.textContent.slice(0, 60),
      height:node.getBoundingClientRect().height,
      gap:index ? node.getBoundingClientRect().top - visible[index - 1].getBoundingClientRect().bottom : 0
    }));
  });
  const violations = (await new AxeBuilder({page}).analyze()).violations;
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1);
  await fs.writeFile(path.join(output, label + '.json'), JSON.stringify({layout, violations, overflow}, null, 2));
  await fs.writeFile(path.join(output, label + '.html'), await page.content());
  await page.screenshot({path:path.join(output, label + '.png'), fullPage:true});
  scans.push({label, maximum_gap:Math.max(...layout.map(row => row.gap)), violations:violations.length, overflow});
  assert.equal(violations.length, 0);
  assert.equal(overflow, false);
  if (!diagnostic && await page.locator('.brohn-report-page').count())
    assert.ok(layout.every((row, index) => row.gap >= (index ? 15 : 0) && row.gap <= 40), JSON.stringify(layout));
}
try {
  await expect.poll(async () => {if(server.exitCode !== null) throw Error(log);
    try{return (await fetch(base)).ok;}catch{return false;}}, {timeout:60000}).toBe(true);
  await page.goto(base);
  await openReport();
  await inspect('unopened-desktop');
  if (!diagnostic) {
    check('Unopened report has compact spacing between visible cards, without empty-output gaps');
    const coverage = page.locator('.brohn-card').filter({has:page.getByRole('heading', {name:'What this result covers', exact:true})});
    await expect(coverage).toContainText('1 channel segment has processed results; 0 could not be processed');
    await expect(coverage).toContainText('298 of 298 acoustic frame rows');
    await expect(coverage.locator('table')).toBeHidden();
    await coverage.getByText('Inspect complete coverage details', {exact:true}).click();
    await expect(coverage.locator('table')).toBeVisible();
    await expect(coverage.locator('table')).toContainText('requires research review');
    await coverage.getByText('Inspect complete coverage details', {exact:true}).click();
    const htmlLink = new URL(await page.locator('#report_html').getAttribute('href'), base).href;
    const exported = await context.request.get(htmlLink);
    assert.equal(exported.status(), 200);
    assert.ok((await exported.text()).includes('298 of 298 acoustic frame rows'));
    check('Plain-language coverage retains exact saved counts and expandable complete fields in the page and HTML export');
    await button('Review original audio').click();
    await expect(button('Apply audio window')).toBeVisible({timeout:30000});
    await inspect('opened-desktop');
    check('Previously empty Shiny output renders usable audio controls on demand');
    await page.setViewportSize({width:390, height:844});
    await inspect('opened-mobile');
    check('Opened report reflows with compact spacing and no horizontal overflow');
    const link = new URL(await page.locator('#report_download').getAttribute('href'), base).href;
    helper('revoke');
    for (let i = 0; i < 3; i++) assert.ok((await context.request.get(link)).status() >= 400);
    await expect(page.getByRole('button', {name:'Dismiss notification', exact:true})).toHaveCount(1);
    await expect(page.getByRole('heading', {name:'Welcome back to your research.', exact:true})).toBeVisible();
    await inspect('single-error-mobile');
    const dismiss = page.getByRole('button', {name:'Dismiss notification', exact:true});
    const closeBounds = await dismiss.boundingBox();
    assert.ok(closeBounds.width >= 44 && closeBounds.height >= 44);
    await dismiss.focus(); await page.keyboard.press('Space');
    await expect(dismiss).toHaveCount(0);
    await expect(page.locator('#brohn-main')).toBeFocused();
    check('Repeated refused downloads update one keyboard-dismissible notification');
    helper('restore');
    await openReport();
    await expect(button('Apply audio window')).toHaveCount(0);
    await button('Review original audio').click();
    await expect(button('Apply audio window')).toBeVisible({timeout:30000});
    check('Navigation resets and reopens dynamic controls without a hidden-output deadlock');
  }
  helper('verify');
  assert.deepEqual(await hashes(), sourceHashes);
  assert.deepEqual(errors, []);
  await fs.writeFile(path.join(output, 'results.json'), JSON.stringify({passed:!diagnostic, diagnostic, checks, scans, source_hashes:sourceHashes, new_jobs:0}, null, 2));
  console.log(JSON.stringify({output, diagnostic, checks:checks.length, scans}));
} catch(error) {
  await page.screenshot({path:path.join(output, 'failure.png'), fullPage:true}).catch(() => {});
  await fs.writeFile(path.join(output, 'failure.json'), JSON.stringify({error:error.stack, checks, scans, errors, source_hashes:sourceHashes}, null, 2));
  throw error;
} finally {
  helper('restore');
  await browser.close();
  await fs.writeFile(path.join(folder, 'stop.researcher'), 'Stop only this owned QA researcher service.');
  await expect.poll(() => server.exitCode !== null, {timeout:30000}).toBe(true);
  await fs.writeFile(path.join(output, 'researcher.log'), log);
}
