// Scoped responsiveness regression using a copy of a retained recorded-data fixture.
// No measurement or source artifact is synthesized or changed by this journey.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { chromium, expect as baseExpect } from '@playwright/test';
const expect = baseExpect.configure({ timeout: 120000 });
const reference = path.resolve(process.argv[2]), folder = path.resolve(process.argv[3]);
assert.ok(path.basename(folder).startsWith('brohn-signal-values-browser-responsive-'));
await fs.mkdir(folder, { recursive: true });
const output = path.join(folder, `browser-${Date.now()}`); await fs.mkdir(output);
const config = JSON.parse(await fs.readFile(path.join(reference, 'fixture.json'), 'utf8'));
assert.ok(config.reports.ecg && config.reports.ppg);
const workspace = path.join(folder, 'workspace');
await fs.cp(config.workspace, workspace, { recursive: true, errorOnExist: true, force: false });
config.workspace = workspace.replaceAll('\\', '/'); config.port = Number(process.env.BROHN_QA_PORT || 3893);
await fs.writeFile(path.join(folder, 'fixture.json'), JSON.stringify(config));
const files = ['R/platform-signal-values.R', 'R/platform-signal-value-views.R'];
const hashes = async () => Object.fromEntries(await Promise.all(files.map(async p => [p, createHash('sha256').update(await fs.readFile(p)).digest('hex')])));
const sourceHashes = await hashes(), checks = [], navigation = [], busySamples = [], children = [], errors = [];
const check = (condition, label) => { assert.ok(condition, label); checks.push(label); console.log('PASS', label); };
const r = path.resolve('../../work/native-r/bin/Rscript.exe'), helper = 'tests/fixtures/researcher-signal-values.R';
const env = { ...process.env, LC_ALL: 'C', R_LIBS_USER: path.resolve('../../work/r-library-brohn-restore'), BROHN_PUBLICATION_PYTHON: path.resolve('../../work/tooling/methods-venv/Scripts/python.exe') };
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 1080 } });
page.on('pageerror', e => errors.push(e.message)); let log = '';
async function idle() {
  await page.waitForFunction(() => !document.documentElement.classList.contains('shiny-busy') && ![...document.querySelectorAll('.recalculating')].some(e => e.getClientRects().length), null, { timeout: 120000 });
  await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);
}
async function openEcg() {
  const record = config.reports.ecg;
  await page.getByRole('button', { name: 'Data library', exact: true }).click();
  await page.getByLabel('Search datasets', { exact: true }).fill(record.title);
  await page.locator(`[data-brohn-event="open_dataset"][data-brohn-value='"${record.dataset_id}"']`).click();
  await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${record.report_id}"']`).click();
  await idle();
  await page.getByRole('button', { name: 'Explore signal traces and spectra', exact: true }).click();
  await expect(page.locator('#signal_form_identity')).toHaveValue(new RegExp('^' + record.report_id + ':'));
  await page.getByRole('button', { name: 'Show exact values', exact: true }).waitFor(); await idle();
  if (await page.locator('#signal_measure').inputValue() !== 'raw') {
    await page.locator('#signal_measure-selectized').fill('Saved input waveform');
    await page.locator('.selectize-dropdown:visible .option[data-value="raw"]').click();
    await expect(page.locator('#signal_measure')).toHaveValue('raw'); await idle();
  }
  await page.getByLabel('Rows per value page', { exact: true }).selectOption('25');
  await page.getByRole('button', { name: 'Show exact values', exact: true }).click();
  await expect(page.locator('#signal-exact-values')).toBeVisible({ timeout: 240000 }); await idle();
}
try {
  for (const mode of ['serve', 'worker']) {
    const child = spawn(r, ['--vanilla', helper, mode, folder], { env, windowsHide: true }); children.push(child);
    child.stdout.on('data', x => log += `${mode}: ${x}`); child.stderr.on('data', x => log += `${mode}: ${x}`);
  }
  await expect.poll(async () => { if (children.some(c => c.exitCode !== null)) throw Error(log); try { return (await fetch(`http://127.0.0.1:${config.port}/`)).status === 200; } catch { return false; } }).toBe(true);
  await page.goto(`http://127.0.0.1:${config.port}/`); await openEcg();
  check((await page.locator('#signal-exact-values').textContent()).includes('selected source rows'), 'Recorded ECG complete-source page opens in the integrated application');
  // Observe the real Shiny busy indicator across eight timer polls. This is a
  // regression bound for this fixture and host, not a platform-wide latency SLA.
  const sample = await page.evaluate(() => new Promise(resolve => {
    const start = performance.now(), samples = [];
    const timer = setInterval(() => {
      samples.push({ t: performance.now() - start, busy: document.documentElement.classList.contains('shiny-busy') });
      if (performance.now() - start >= 8000) { clearInterval(timer); resolve(samples); }
    }, 50);
  }));
  busySamples.push(...sample);
  const fraction = sample.filter(s => s.busy).length / sample.length;
  check(fraction < 0.5, 'Ready exact-value polling leaves the browser idle for most observed samples');
  await page.screenshot({ path: path.join(output, 'recorded-ecg-ready.png') });
  for (let i = 0; i < 3; i++) {
    if (i) await openEcg();
    const start = performance.now();
    await page.getByRole('button', { name: 'Data library', exact: true }).click();
    await expect(page.getByLabel('Search datasets', { exact: true })).toBeVisible(); await idle();
    const elapsed = performance.now() - start; navigation.push(elapsed);
    check(elapsed < 5000, `Data library becomes ready within five seconds after active exact-value view (${i + 1})`);
    await page.getByLabel('Search datasets', { exact: true }).fill(config.reports.ppg.title);
    await expect(page.locator(`[data-brohn-event="open_dataset"][data-brohn-value='"${config.reports.ppg.dataset_id}"']`)).toBeVisible();
    check(true, `Library search responds after leaving recorded ECG (${i + 1})`);
  }
  const inspection = spawnSync(r, ['--vanilla', helper, 'inspect', folder], { env, windowsHide: true, encoding: 'utf8', timeout: 120000 });
  assert.equal(inspection.status, 0, inspection.stderr || inspection.stdout);
  const saved = JSON.parse(await fs.readFile(path.join(folder, 'inspection.json'), 'utf8'));
  for (const [name, report] of Object.entries(config.reports)) assert.equal(saved.reports[name].hash, report.report_hash);
  check(true, 'Original cardiac and schema reports remain byte-identical');
  const jobs = saved.jobs.filter(j => j.operation.startsWith('signal_values_'));
  check(jobs.every(j => ['succeeded', 'cancelled'].includes(j.status)), 'All exact-value work is complete or retains its prior explicit cancellation');
  assert.deepEqual(await hashes(), sourceHashes); check(!errors.length, 'No browser errors or source drift during the journey');
  await fs.writeFile(path.join(output, 'results.json'), JSON.stringify({ checks, errors, navigation_ms: navigation, busy_fraction: fraction, busy_samples: busySamples, sourceHashes, sourceReports: saved.reports, jobs, scope: 'Recorded ECG on this Windows host; scoped UI responsiveness, not accuracy or a general latency guarantee.' }, null, 2));
  console.log(JSON.stringify({ output, checks: checks.length, navigation_ms: navigation, busy_fraction: fraction }));
} catch (e) {
  await fs.writeFile(path.join(output, 'failure.json'), JSON.stringify({ error: e.stack, checks, errors, log }, null, 2));
  await page.screenshot({ path: path.join(output, 'failure.png') }); throw e;
} finally {
  await fs.writeFile(path.join(folder, 'stop.request'), 'stop'); await fs.writeFile(path.join(output, 'services.log'), log);
  await browser.close();
  for (const child of children) { if (child.exitCode === null) await Promise.race([new Promise(resolve => child.once('exit', resolve)), new Promise(resolve => setTimeout(resolve, 10000))]); if (child.exitCode === null) child.kill(); }
}
