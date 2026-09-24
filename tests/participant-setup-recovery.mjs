// Focused actual-browser failure injection. Uses original isolated survey and
// synthetic trusted-edge fixture; no production code or request body is mocked.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import crypto from 'node:crypto';
import {spawn, spawnSync} from 'node:child_process';
import {chromium, expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const repo = path.resolve(import.meta.dirname, '..'), work = path.resolve(repo, '../../work');
const folder = await fs.mkdtemp(path.join(work, 'test-runs/brohn-runtime-browser-setup-'));
const rscript = process.env.BROHN_RSCRIPT || path.join(work, 'native-r/bin/Rscript.exe');
const env = {...process.env, R_LIBS_USER: path.join(work, 'r-library-brohn-restore'), R_USER: work, LC_ALL: 'C', LANG: 'C',
  BROHN_PUBLICATION_PYTHON: path.join(work, 'tooling/methods-venv/Scripts/python.exe'),
  BROHN_PUBLICATION_NATIVE_MANIFEST: path.join(work, 'tooling/brohn-native/publication-guard.json')};
const files = ['R/platform-load.R', 'R/platform-store.R', 'R/platform-delivery.R', 'R/platform-runner-assets.R',
  'R/platform-hosted-profile.R', 'www/participant/runner.js', 'tests/fixtures/runtime-preservation-browser.R', 'tests/participant-setup-recovery.mjs'];
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const hashes = async () => Object.fromEntries(await Promise.all(files.map(async file => [file, sha(await fs.readFile(path.join(repo, file)))])));
const sourceStart = await hashes(); await fs.writeFile(path.join(folder, 'source-start.json'), JSON.stringify(sourceStart, null, 2));
const checks = [], scans = [], cases = [], errors = [], gates = []; let browser, page, child, log = '', prepared = false, config, base;
const check = (value, label) => {assert.ok(value, label); checks.push(label); console.log('PASS', label);};
const deferred = () => {let resolve, reject; const promise = new Promise((a, b) => {resolve = a; reject = b;}); promise.catch(() => {}); return {promise, resolve, reject};};
const within = (promise, millis, label) => {let timer; return Promise.race([promise, new Promise((_, reject) => {
  timer = setTimeout(() => reject(new Error(label)), millis);
})]).finally(() => clearTimeout(timer));};
function r(mode, extra = []) {
  const result = spawnSync(rscript, ['--vanilla', 'tests/fixtures/runtime-preservation-browser.R', mode, '--folder', folder, ...extra],
    {cwd: repo, env, windowsHide: true, encoding: 'utf8', timeout: 120000});
  assert.equal(result.status, 0, result.stderr || result.stdout);
}
async function record(target, token) {
  return target.evaluate(token => new Promise((resolve, reject) => {
    const request = indexedDB.open('brohn-participant', 1); request.onerror = () => reject(request.error);
    request.onsuccess = () => {const db = request.result, get = db.transaction('sessions').objectStore('sessions').get(token);
      get.onerror = () => {db.close(); reject(get.error);}; get.onsuccess = () => {db.close(); resolve(get.result || null);};};
  }), token);
}
async function inspect() {r('cancel'); return JSON.parse(await fs.readFile(path.join(folder, 'inspection.json'), 'utf8'));}
async function open(kind, init) {
  const context = await browser.newContext({viewport: {width: 1280, height: 900}});
  if (init) await context.addInitScript(init);
  const target = await context.newPage(); page = target; const starts = [];
  target.on('pageerror', error => errors.push({kind, error: error.message})); target.on('dialog', d => d.accept());
  target.on('request', request => {if (request.method() === 'POST' && request.url().includes('/api/start/')) starts.push(request.postData());});
  await target.goto(`${base}/participant/?token=${config.releases[kind].token}`);
  return {context, target, starts, release: config.releases[kind]};
}
async function consent(target) {
  await target.getByLabel('I have read the study information and agree to take part.', {exact: true}).check();
  await target.getByRole('button', {name: 'Start study', exact: true}).click();
}
async function scan(target, name) {
  await target.setViewportSize({width: 390, height: 844});
  const violations = (await new AxeBuilder({page: target}).analyze()).violations;
  scans.push({name, violations}); await target.screenshot({path: path.join(folder, `${name}.png`), fullPage: true});
  check(!violations.length, `${name}: no axe violations`);
  check(await target.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${name}: no horizontal overflow`);
}
async function complete(target, answer) {
  await target.getByRole('button', {name: 'Begin', exact: true}).click();
  await target.getByRole('textbox', {name: 'Your answer', exact: true}).fill(answer);
  await target.getByRole('button', {name: 'Continue', exact: true}).click();
  await target.getByRole('heading', {name: 'Thank you. Your responses are saved.', exact: true}).waitFor({timeout: 30000});
}
try {
  r('prepare'); prepared = true; config = JSON.parse(await fs.readFile(path.join(folder, 'fixture.json'), 'utf8'));
  const port = await new Promise(resolve => {const s = net.createServer(); s.listen(0, '127.0.0.1', () => {const p = s.address().port; s.close(() => resolve(p));});});
  base = `http://127.0.0.1:${port}`;
  child = spawn(rscript, ['--vanilla', 'tests/fixtures/runtime-preservation-browser.R', 'serve', '--folder', folder, '--port', String(port), '--stop', 'stop.1'],
    {cwd: repo, env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe']});
  child.stdout.on('data', x => log += x); child.stderr.on('data', x => log += x);
  await expect.poll(async () => {if (child.exitCode !== null) throw new Error(log); try {return (await fetch(`${base}/api/health`)).ok;} catch {return false;}},
    {timeout: 30000, intervals: [100, 250, 500]}).toBe(true);
  browser = await chromium.launch({channel: 'chrome', headless: true});

  // First local write fails. Retry must journal the same pending operation before
  // making any network request, including when it already exists only in memory.
  {
    const {context, target, starts, release} = await open('newer', () => {
      const put = IDBObjectStore.prototype.put;
      IDBObjectStore.prototype.put = function(value, ...rest) {
        if (this.name === 'sessions' && value?.pending_start && !sessionStorage.getItem('original-fixture-local-write-failed')) {
          sessionStorage.setItem('original-fixture-local-write-failed', 'yes');
          throw new Error('Original fixture first local write failure');
        }
        return put.call(this, value, ...rest);
      };
    });
    await consent(target); await target.getByRole('heading', {name: 'Session setup needs attention', exact: true}).waitFor();
    check(starts.length === 0 && await record(target, release.token) === null, 'Failed first IndexedDB write sends no request and claims no durable local record');
    const text = await target.locator('body').innerText();
    check(!/saved (?:on|in) this browser|responses.{0,30}retained/i.test(text), 'First-write failure does not claim unsaved data are retained');
    check(!/Please wait while the study service creates/.test(text), 'Setup failure does not leave false in-progress wording');
    await scan(target, 'first-local-write-failure');
    const accepted = deferred(), releaseAck = deferred(); gates.push(releaseAck); const requests = []; let retrying = false, committed;
    await target.route('**/api/start/**', async route => {
      try {
        const wire = route.request().postData(), saved = await record(target, release.token);
        assert.deepEqual(saved?.pending_start, JSON.parse(wire), 'The exact operation must be durable before every start POST.');
        requests.push(wire);
        if (requests.length === 1) {
          const response = await route.fetch(); assert.equal(response.status(), 200, await response.text()); committed = await response.json();
          accepted.resolve(); await releaseAck.promise; await route.abort('failed').catch(() => {}); return;
        }
        if (!retrying) {await route.abort('failed').catch(() => {}); return;} await route.continue();
      } catch (error) {accepted.reject(error); releaseAck.resolve(); await route.abort('failed').catch(() => {});}
    });
    await target.getByRole('button', {name: 'Retry session setup', exact: true}).click();
    await within(accepted.promise, 30000, 'Durable retry commit was not observed.');
    const uncertain = await record(target, release.token);
    check(!uncertain.run_id && JSON.stringify(uncertain.pending_start) === requests[0], 'Lost start acknowledgement retains exact durably retried operation');
    retrying = true; releaseAck.resolve(); await target.reload();
    await target.getByRole('button', {name: 'Continue session setup', exact: true}).click();
    await target.getByRole('button', {name: 'Begin', exact: true}).waitFor();
    const resumed = await record(target, release.token);
    check(resumed.run_id === committed.run_id && requests.length >= 2 && requests.every(wire => wire === requests[0]), 'Reload recovers one exact server session after first-write failure and lost acknowledgement');
    await complete(target, 'Original first-write recovery answer');
    const rows = (await inspect()).runs.filter(x => x.run.deployment_id === release.id);
    check(rows.length === 1 && rows[0].run.completion_status === 'completed' && rows[0].jobs.length === 1 && rows[0].jobs[0].attempt === 0,
      'First-write retry creates one run and one cancelled unexecuted analysis job');
    cases.push({kind: 'first_local_write_failure', run_id: resumed.run_id, request_hashes: requests.map(sha)}); await context.close();
  }

  // A one-shot UI failure happens after the run record is durably persisted.
  // Recovery must boot that run, never call start with a newly generated client.
  {
    const {context, target, starts, release} = await open('committed_expired', () => {
      const descriptor = Object.getOwnPropertyDescriptor(Document.prototype, 'title'); let matching = 0;
      Object.defineProperty(document, 'title', {configurable: true, get() {return descriptor.get.call(this);}, set(value) {
        if (value === 'Original runtime recovery survey | Brohn study' && ++matching === 2) {
          window.__originalFixtureDisplayFailure = true; throw new Error('Original fixture display failure after durable session');
        }
        descriptor.set.call(this, value);
      }});
    });
    await consent(target);
    await expect.poll(() => target.evaluate(() => window.__originalFixtureDisplayFailure === true)).toBe(true);
    const recover = target.getByRole('button', {name: /(?:reload|recover).*session/i}); await recover.waitFor();
    const original = await record(target, release.token);
    check(Boolean(original.run_id) && !original.pending_start && starts.length === 1, 'Injected post-persist display failure retains its single admitted session');
    check(await target.getByRole('button', {name: 'Retry session setup', exact: true}).count() === 0, 'An admitted session is never offered a new start operation');
    await scan(target, 'admitted-session-recovery');
    await recover.click();
    await target.getByRole('button', {name: 'Resume this participant session', exact: true}).waitFor();
    const restored = await record(target, release.token);
    check(restored.run_id === original.run_id && restored.access_token === original.access_token && starts.length === 1,
      'Recovery reload reuses the exact admitted run and credential without another start POST');
    assert.deepEqual(restored.protocol, original.protocol);
    await target.getByRole('button', {name: 'Resume this participant session', exact: true}).click();
    await complete(target, 'Original admitted-session recovery answer');
    const rows = (await inspect()).runs.filter(x => x.run.deployment_id === release.id);
    check(rows.length === 1 && rows[0].run.id === original.run_id && rows[0].run.completion_status === 'completed' && rows[0].jobs.length === 1,
      'Post-persist display recovery never duplicates a run, allocation or analysis job');
    cases.push({kind: 'post_persist_display_failure', run_id: original.run_id, start_requests: starts.length}); await context.close();
  }

  {
    const {context, target, starts, release} = await open('uncommitted_revoked'); let block = true;
    await target.route('**/api/start/**', route => block ? route.fulfill({status: 503, contentType: 'application/json',
      body: JSON.stringify({error: {code: 'original_fixture_uncommitted', message: 'Original fixture interrupted before enrollment'}})}) : route.continue());
    await consent(target); await target.getByRole('heading', {name: 'Session setup needs attention', exact: true}).waitFor();
    const pending = await record(target, release.token); assert.deepEqual(pending.pending_start, JSON.parse(starts[0]));
    r('policy', ['--case', 'uncommitted_revoked', '--policy', 'release_revoked']); block = false; await target.reload();
    await target.getByRole('button', {name: 'Continue session setup', exact: true}).click();
    await target.getByRole('heading', {name: 'Session setup needs attention', exact: true}).waitFor();
    await expect(target.getByRole('alert')).toContainText('revoked');
    check(!/Preparing your session|Please wait while/.test(await target.locator('main').innerText()), 'Permanent revoked setup clearly reports attention instead of ongoing preparation');
    assert.deepEqual((await record(target, release.token)).pending_start, pending.pending_start);
    check(starts.length === 2 && starts[0] === starts[1] && !(await inspect()).runs.some(x => x.run.deployment_id === release.id),
      'Refused exact pending setup retains its body and consumes no participant allocation');
    await scan(target, 'revoked-setup-needs-attention'); cases.push({kind: 'uncommitted_revoked', request_hashes: starts.map(sha)}); await context.close();
  }
  check(errors.length === 0, `No unhandled browser exceptions: ${JSON.stringify(errors)}`);
  assert.deepEqual(await hashes(), sourceStart); check(true, 'All tested source and fixture identities remain unchanged');
  await fs.writeFile(path.join(folder, 'results.json'), JSON.stringify({passed: true, checks, scans, cases, source_hashes: sourceStart,
    limits: ['Original synthetic text survey with explicit local failure injection.', 'Actual R HTTP with synthetic trusted-edge transport, not TLS/OIDC qualification.',
      'No scientific worker or physical device run.']}, null, 2));
  console.log(JSON.stringify({passed: true, checks: checks.length, scans: scans.length, folder}));
} catch (error) {
  await page?.screenshot({path: path.join(folder, 'failure.png'), fullPage: true}).catch(() => {});
  await fs.writeFile(path.join(folder, 'failure.json'), JSON.stringify({error: error.stack, checks, cases, errors,
    text: await page?.locator('body').innerText().catch(() => '(closed)')}, null, 2)); throw error;
} finally {
  gates.forEach(x => x.resolve()); if (browser) await browser.close();
  if (child?.exitCode === null) {await fs.writeFile(path.join(folder, 'stop.1'), 'Stop this owned setup recovery receiver.');
    await expect.poll(() => child.exitCode !== null, {timeout: 15000, intervals: [100, 250]}).toBe(true); assert.equal(child.exitCode, 0, log);}
  if (prepared) r('cancel'); await fs.writeFile(path.join(folder, 'service.log'), log);
}
