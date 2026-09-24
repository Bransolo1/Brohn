// Real Chrome + actual R HTTP receiver. Hosted transport identity is an explicit
// local fixture adapter, not a TLS/OIDC deployment or physical-device claim.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import crypto from 'node:crypto';
import {spawn, spawnSync} from 'node:child_process';
import {chromium, expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const repo = path.resolve(import.meta.dirname, '..'), work = path.resolve(repo, '../../work');
const rscript = process.env.BROHN_RSCRIPT || path.join(work, 'native-r/bin/Rscript.exe');
const env = {...process.env, R_LIBS_USER: path.join(work, 'r-library-brohn-restore'), R_USER: work, LC_ALL: 'C', LANG: 'C',
  BROHN_PUBLICATION_PYTHON: path.join(work, 'tooling/methods-venv/Scripts/python.exe'),
  BROHN_PUBLICATION_NATIVE_MANIFEST: path.join(work, 'tooling/brohn-native/publication-guard.json')};
const folder = await fs.mkdtemp(path.join(work, 'test-runs/brohn-runtime-browser-'));
const checks = [], errors = [], cases = [], scans = [], assets = [], gates = [], services = [];
let browser, page, prepared = false, config, port;
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const sourceFiles = ['R/platform-core.R', 'R/platform-store.R', 'R/platform-load.R', 'R/platform-delivery.R',
  'R/platform-runner-assets.R', 'R/platform-backup.R', 'R/platform-hosted-profile.R',
  'tests/fixtures/runtime-preservation-browser.R', 'tests/participant-runtime-preservation.mjs',
  ...(await fs.readdir(path.join(repo, 'www/participant'))).filter(x => /\.(js|css|html)$/.test(x)).map(x => `www/participant/${x}`),
  'www/brand/brohn-app-icon.svg'];
const hashes = async () => Object.fromEntries(await Promise.all(sourceFiles.map(async file => [file, sha(await fs.readFile(path.join(repo, file)))])));
const sourceStart = await hashes();
await fs.writeFile(path.join(folder, 'source-start.json'), JSON.stringify(sourceStart, null, 2));
const check = (condition, label) => {assert.ok(condition, label); checks.push(label); console.log('PASS', label);};
const deferred = () => {let resolve, reject; const promise = new Promise((a, b) => {resolve = a; reject = b;});
  promise.catch(() => {}); return {promise, resolve, reject};};
const within = (promise, timeout, label) => {let timer; return Promise.race([promise, new Promise((_, reject) => {
  timer = setTimeout(() => reject(new Error(label)), timeout);
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
async function inspect(restored = false) {
  r('cancel', restored ? ['--restored', 'yes'] : []);
  return JSON.parse(await fs.readFile(path.join(folder, restored ? 'restored-inspection.json' : 'inspection.json'), 'utf8'));
}
async function startService({restored = false, absent = false} = {}) {
  const number = services.length + 1, stop = `stop.${number}`;
  const child = spawn(rscript, ['--vanilla', 'tests/fixtures/runtime-preservation-browser.R', 'serve', '--folder', folder,
    '--port', String(port), '--stop', stop, ...(restored ? ['--restored', 'yes'] : []), ...(absent ? ['--absent', 'yes'] : [])],
    {cwd: repo, env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe']});
  const service = {child, stop, log: '', restored, absent}; services.push(service);
  child.stdout.on('data', x => service.log += x); child.stderr.on('data', x => service.log += x);
  await expect.poll(async () => {if (child.exitCode !== null) throw new Error(service.log);
    try {return (await fetch(`http://127.0.0.1:${port}/api/health`)).ok;} catch {return false;}
  }, {timeout: 30000, intervals: [100, 250, 500]}).toBe(true);
}
async function stopService() {
  const service = services.at(-1);
  if (service?.child.exitCode === null) {
    await fs.writeFile(path.join(folder, service.stop), 'Stop only this owned runtime fixture service.');
    await expect.poll(() => service.child.exitCode !== null, {timeout: 15000, intervals: [100, 250]}).toBe(true);
    assert.equal(service.child.exitCode, 0, service.log);
  }
}
async function openCase(kind, release = config.releases[kind]) {
  const context = await browser.newContext({viewport: {width: 1280, height: 900}}), target = await context.newPage(); page = target;
  target.on('pageerror', error => errors.push({kind, message: error.message})); target.on('dialog', dialog => dialog.accept());
  target.on('response', response => {
    const pathname = new URL(response.url()).pathname;
    if (/\.(js|css|html|svg)$/.test(pathname)) assets.push((async () => ({kind, pathname, status: response.status(), hash: sha(await response.body())}))());
  });
  await target.goto(`http://127.0.0.1:${port}/participant/?token=${release.token}`);
  return {context, target, release, kind};
}
async function scan(target, name) {
  await target.setViewportSize({width: 390, height: 844});
  const violations = (await new AxeBuilder({page: target}).analyze()).violations;
  await target.screenshot({path: path.join(folder, `${name}.png`), fullPage: true});
  scans.push({name, violations}); check(!violations.length, `${name}: no axe violations`);
  check(await target.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${name}: no horizontal overflow`);
}
async function consent(target) {
  await target.getByLabel('I have read the study information and agree to take part.', {exact: true}).check();
  await target.getByRole('button', {name: 'Start study', exact: true}).click();
}
async function loseOnce(target, operation, {commit = true} = {}) {
  const accepted = deferred(), release = deferred(); gates.push(release);
  const state = {attempts: [], accepted, release, retrying: false, first: null};
  await target.route(`**/api/${operation}/**`, async route => {
    try {
    const wire = route.request().postData(), body = JSON.parse(wire), headers = route.request().headers();
    state.attempts.push({wire, sha256: sha(wire), headers});
    if (!state.first) {
      state.first = {wire, body, headers};
      if (commit) {
        const response = await route.fetch({timeout: 60000});
        assert.equal(response.status(), 200, await response.text()); state.result = await response.json();
      }
      accepted.resolve(state.result); await release.promise; await route.abort('failed').catch(() => {}); return;
    }
    if (!state.retrying) {await route.abort('failed').catch(() => {}); return;}
    await route.continue();
    } catch (error) {
      state.error = error; accepted.reject(error); release.resolve(); await route.abort('failed').catch(() => {});
    }
  });
  return state;
}
async function replayAfterReload(target, loss) {
  loss.retrying = true; loss.release.resolve(); await target.reload();
}
const unchangedRetry = (loss, label) => check(loss.attempts.length >= 2 && loss.attempts.every(x => x.sha256 === sha(loss.first.wire)), label);
async function completeSurvey(target, answer) {
  await target.getByRole('button', {name: 'Begin', exact: true}).click();
  await target.locator('#answer').fill(answer);
  await target.getByRole('button', {name: 'Continue', exact: true}).click();
}
async function expectedRun(id, kind) {
  const row = (await inspect()).runs.find(x => x.run.id === id); assert.ok(row);
  const runtime = config.runtimes[kind];
  check(row.assignment.length === (kind === 'legacy' ? 0 : 1), `${kind}: exact separate runtime assignment count`);
  if (kind !== 'legacy') check(row.assignment[0].manifest_hash === runtime.manifest_hash && row.assignment[0].deployment_id === config.releases[kind].id,
    `${kind}: immutable run assignment matches its original release`);
  return row;
}

try {
  r('prepare'); prepared = true; config = JSON.parse(await fs.readFile(path.join(folder, 'fixture.json'), 'utf8'));
  check(config.runtimes.committed_revoked.manifest_hash !== config.runtimes.newer.manifest_hash,
    'External distribution update creates a distinct new runtime while original releases remain pinned');
  check(config.runtimes.legacy.status === 'legacy_unpinned', 'Explicit simulated pre-feature release remains unpinned');
  port = await new Promise(resolve => {const server = net.createServer(); server.listen(0, '127.0.0.1', () => {
    const value = server.address().port; server.close(() => resolve(value));});});
  const base = `http://127.0.0.1:${port}`;
  await startService(); browser = await chromium.launch({channel: 'chrome', headless: true});
  for (const kind of ['committed_revoked', 'committed_expired', 'uncommitted_revoked']) {
    const {context, target, release} = await openCase(kind);
    check(new URL(target.url()).pathname === `/api/runtime/${release.token}/${config.runtimes[kind].manifest_hash}/participant/index.html`,
      `${kind}: original public study link redirects to exact preserved entry`);
    const startLoss = await loseOnce(target, 'start', {commit: kind !== 'uncommitted_revoked'});
    await consent(target); await within(startLoss.accepted.promise, 30000, 'Start request was not intercepted.');
    const pending = await record(target, release.token);
    assert.deepEqual(pending.pending_start, startLoss.first.body);
    check(startLoss.first.headers['x-brohn-participant-runtime'] === config.runtimes[kind].manifest_hash,
      `${kind}: actual browser start carries exact page runtime header without a JSON field`);
    check(!Object.hasOwn(startLoss.first.body, 'participant_runtime') && !Object.hasOwn(startLoss.first.body, 'runtime_hash'),
      `${kind}: durable start operation body retains its original schema`);
    r('policy', ['--case', kind, '--policy', kind === 'committed_expired' ? 'release_expired' : 'release_revoked']);
    await replayAfterReload(target, startLoss);
    await target.getByRole('button', {name: 'Continue session setup', exact: true}).waitFor();
    assert.deepEqual((await record(target, release.token)).pending_start, pending.pending_start);
    const startReply = target.waitForResponse(x => x.url().includes('/api/start/') && x.request().method() === 'POST');
    let eventLoss, finishLoss;
    if (kind === 'committed_revoked') {eventLoss = await loseOnce(target, 'events'); finishLoss = await loseOnce(target, 'finish');}
    await target.getByRole('button', {name: 'Continue session setup', exact: true}).click();
    const reply = await startReply;
    unchangedRetry(startLoss, `${kind}: retry uses byte-identical uncertain setup body and identity`);
    if (kind === 'uncommitted_revoked') {
      check(reply.status() === 403, 'Uncommitted saved setup cannot enroll after release revocation');
      assert.deepEqual((await record(target, release.token)).pending_start, pending.pending_start);
      check(!(await inspect()).runs.some(x => x.run.deployment_id === release.id), 'Refused new setup consumes no run or allocation');
      await scan(target, 'uncommitted-retained'); cases.push({kind, refused: true}); await context.close(); continue;
    }
    const session = await reply.json();
    check(reply.status() === 200 && session.run_id === startLoss.result.run_id && session.access_token === startLoss.result.access_token,
      `${kind}: admitted setup recovers exact existing session despite unavailable study entry`);
    await target.getByRole('button', {name: 'Begin', exact: true}).waitFor();
    check(await target.title() === 'Original runtime recovery survey | Brohn study', `${kind}: recovered display uses frozen study metadata`);
    if (eventLoss) {
      await within(eventLoss.accepted.promise, 30000, 'Committed event operation was not observed.');
      const uncertain = await record(target, release.token);
      check(uncertain.batch.operation_id === eventLoss.first.body.operation_id && uncertain.acked_sequence === 0,
        'Pinned page retains server-committed but unacknowledged event operation');
      await replayAfterReload(target, eventLoss);
      await target.getByRole('button', {name: 'Resume this participant session', exact: true}).click();
      await target.getByRole('button', {name: 'Begin', exact: true}).waitFor();
      await expect.poll(() => eventLoss.attempts.length, {timeout: 30000}).toBeGreaterThanOrEqual(2);
      const originalOp = eventLoss.first.body.operation_id;
      check(eventLoss.attempts.filter(x => JSON.parse(x.wire).operation_id === originalOp).every(x => x.wire === eventLoss.first.wire),
        'Pinned reload reconciles the exact prior event body without replacing its operation');
      // Real worklet module loading, without recording or physical-device claims.
      const loaded = await within(target.evaluate(async () => {const audio = new AudioContext();
        try {await audio.audioWorklet.addModule('audio-worklet.js'); return true;}
        finally {void audio.close().catch(() => {});}
      }), 15000, 'Native worklet module probe did not complete within its fixture budget.');
      // Chromium does not expose this worklet fetch as a Playwright page response.
      // Independently retain the actual receiver's returned bytes and native load result.
      const worklet = (await fs.readFile(path.join(folder, 'worklet-responses.jsonl'), 'utf8')).trim().split('\n').map(x => JSON.parse(x)).at(-1);
      check(loaded && worklet.status === 200 && worklet.path === `/api/runtime/${release.token}/${config.runtimes[kind].manifest_hash}/participant/audio-worklet.js` &&
        worklet.hash === config.expected_a['participant/audio-worklet.js'],
        'Relative AudioWorklet module loads exact original bytes after installation update and release revocation');
      const icon = await target.request.get(new URL('../brand/brohn-app-icon.svg', target.url()).href);
      check(icon.status() === 200 && sha(await icon.body()) === config.expected_a['brand/brohn-app-icon.svg'], 'Relative icon remains the exact preserved asset');
    }
    const answer = `Original answer for ${kind}`;
    await completeSurvey(target, answer);
    let expectedEvents;
    if (finishLoss) {
      await within(finishLoss.accepted.promise, 30000, 'Committed final receipt was not intercepted.');
      const pendingFinish = await record(target, release.token); expectedEvents = pendingFinish.events;
      assert.deepEqual(pendingFinish.finish, finishLoss.first.body);
      check(pendingFinish.acked_sequence === pendingFinish.events.length, 'Final receipt loss retains all acknowledged original events locally');
      await target.screenshot({path: path.join(folder, 'pinned-final-receipt-pending.png'), fullPage: true});
      await replayAfterReload(target, finishLoss);
    }
    await target.getByRole('heading', {name: 'Thank you. Your responses are saved.', exact: true}).waitFor({timeout: 30000});
    if (finishLoss) unchangedRetry(finishLoss, 'Pinned reload retries the exact final receipt operation');
    check(await record(target, release.token) === null, `${kind}: local journal clears only after final receipt`);
    const saved = await expectedRun(session.run_id, kind);
    check(saved.run.completion_status === 'completed' && saved.run.transfer_status === 'saved', `${kind}: actual saved run completes`);
    if (expectedEvents) assert.deepEqual(saved.events, expectedEvents);
    check(saved.events.filter(x => x.type === 'response' && x.payload?.value === answer).length === 1,
      `${kind}: original answer is received exactly once`);
    check(saved.jobs.length === 1 && saved.jobs[0].attempt === 0 && saved.jobs[0].status === 'cancelled', `${kind}: one automatic job cancelled before execution`);
    if (kind === 'committed_revoked') await scan(target, 'pinned-completed-narrow');
    cases.push({kind, run_id: session.run_id, events: saved.events.length, assignment: saved.assignment,
      start_requests: startLoss.attempts.map(x => ({sha256: x.sha256, runtime: x.headers['x-brohn-participant-runtime']})),
      event_requests: eventLoss?.attempts.map(x => ({sha256: x.sha256, operation_id: JSON.parse(x.wire).operation_id})),
      finish_requests: finishLoss?.attempts.map(x => ({sha256: x.sha256}))});
    await context.close();
  }
  for (const kind of ['run_revoked', 'run_expired', 'newer', 'legacy']) {
    const {context, target, release} = await openCase(kind);
    const started = target.waitForResponse(x => x.url().includes('/api/start/') && x.request().method() === 'POST');
    await consent(target); const response = await started; assert.equal(response.status(), 200, await response.text());
    const session = await response.json(); await target.getByRole('button', {name: 'Begin', exact: true}).waitFor();
    if (kind.startsWith('run_')) {
      await target.getByRole('button', {name: 'Begin', exact: true}).click();
      await target.locator('#answer').fill(`Retained draft ${kind}`);
      await expect.poll(async () => JSON.stringify((await record(target, release.token)).drafts), {timeout: 10000}).toContain(`Retained draft ${kind}`);
      const original = await record(target, release.token);
      r('policy', ['--case', kind, '--policy', kind]); await target.reload();
      await target.getByRole('heading', {name: 'This session can no longer send data', exact: true}).waitFor();
      const retained = await record(target, release.token);
      assert.deepEqual(retained.events, original.events); assert.deepEqual(retained.drafts, original.drafts);
      check(retained.hosted_access.code === (kind === 'run_revoked' ? 'run_revoked' : 'upload_expired'), `${kind}: actual run authority remains enforced by preserved code`);
      const saved = await expectedRun(session.run_id, kind);
      check(saved.run.completion_status === 'in_progress' && !saved.jobs.length, `${kind}: refusal does not invent an ending or analysis job`);
      if (kind === 'run_revoked') await scan(target, 'revoked-run-retained-narrow');
      cases.push({kind, run_id: session.run_id, local_events_retained: retained.events.length});
    } else {
      check(new URL(target.url()).pathname === (kind === 'legacy' ? '/participant/' : `/api/runtime/${release.token}/${config.runtimes[kind].manifest_hash}/participant/index.html`),
        `${kind}: correct pinned or explicitly legacy route`);
      check((response.request().headers()['x-brohn-participant-runtime'] || null) === (kind === 'legacy' ? null : config.runtimes[kind].manifest_hash),
        `${kind}: start header does not fabricate historical identity`);
      await completeSurvey(target, `Original answer for ${kind}`);
      await target.getByRole('heading', {name: 'Thank you. Your responses are saved.', exact: true}).waitFor({timeout: 30000});
      const saved = await expectedRun(session.run_id, kind);
      check(saved.run.completion_status === 'completed', `${kind}: actual study remains usable`);
      cases.push({kind, run_id: session.run_id, assignment: saved.assignment});
    }
    await context.close();
  }
  const captured = await Promise.all(assets);
  for (const kind of ['committed_revoked', 'newer', 'legacy']) {
    const expected = kind === 'committed_revoked' ? config.expected_a : config.expected_b;
    const actual = captured.filter(x => x.kind === kind && x.pathname.endsWith('/participant/runner.js'));
    check(actual.length > 0 && actual.every(x => x.status === 200 && x.hash === expected['participant/runner.js']), `${kind}: loaded runner bytes match its actual assigned distribution`);
  }
  await stopService(); await startService({absent: true});
  const released = config.releases.committed_revoked, hash = config.runtimes.committed_revoked.manifest_hash;
  const preserved = await fetch(`${base}/api/runtime/${released.token}/${hash}/participant/runner.js`);
  check(preserved.ok && sha(Buffer.from(await preserved.arrayBuffer())) === config.expected_a['participant/runner.js'], 'Restart with absent static distribution serves original preserved bytes');
  check((await fetch(`${base}/participant/runner.js`)).status === 503, 'Absent legacy distribution cannot silently substitute preserved or current bytes');
  await stopService(); r('backup'); const restored = JSON.parse(await fs.readFile(path.join(folder, 'restored.json'), 'utf8'));
  check(restored.paused && restored.workspace_id !== restored.original_workspace_id && restored.releases.every(x => x.status === 'closed'), 'Restore preserves closed releases, rotated workspace identity and execution pause');
  await startService({restored: true, absent: true});
  check((await fetch(`${base}/api/runtime/${released.token}/${hash}/participant/runner.js`)).status === 404, 'Restored old release capability cannot access code');
  const rotated = restored.releases.find(x => x.id === released.id);
  check(rotated.token !== released.token, 'Restore rotates the release capability');
  const restoredCode = await fetch(`${base}/api/runtime/${rotated.token}/${hash}/participant/runner.js`);
  check(restoredCode.ok && sha(Buffer.from(await restoredCode.arrayBuffer())) === config.expected_a['participant/runner.js'], 'Restored new capability reads unchanged exact runtime bytes without static files');
  const denied = await fetch(`${base}/api/start/${rotated.token}`, {method: 'POST', headers: {'Content-Type': 'application/json', 'X-Brohn-Participant-Runtime': hash},
    body: JSON.stringify({consented: true, client_id: 'original-restored-new-client', operation_id: 'original-restored-new-start'})});
  check(denied.status === 409 && (await denied.json()).error.code === 'workspace_paused', 'Preserved code access does not resume paused restored execution');
  const restoredInspection = await inspect(true), originalInspection = await inspect();
  assert.deepEqual(restoredInspection.runtimes, originalInspection.runtimes);
  for (const original of originalInspection.runs) {
    const copy = restoredInspection.runs.find(x => x.run.id === original.run.id);
    assert.deepEqual(copy.events, original.events); assert.deepEqual(copy.assignment, original.assignment);
  }
  check(true, 'Backup/restore retains every event and separate immutable runtime assignment');
  check(!errors.length, `No browser exceptions: ${JSON.stringify(errors)}`);
  assert.deepEqual(await hashes(), sourceStart); check(true, 'All tested product source and fixture bytes remain unchanged');
  await fs.writeFile(path.join(folder, 'results.json'), JSON.stringify({passed: true, checks, scans, cases, assets: captured, source_hashes: sourceStart,
    limits: ['Synthetic trusted-edge adapter; no TLS/OIDC deployment qualification.', 'Small original text survey; no device recording or scientific worker execution.',
      'Legacy release explicitly simulates pre-feature metadata; no historical execution is inferred.']}, null, 2));
  console.log(JSON.stringify({passed: true, checks: checks.length, scans: scans.length, folder}));
} catch (error) {
  await page?.screenshot({path: path.join(folder, 'failure.png'), fullPage: true}).catch(() => {});
  await fs.writeFile(path.join(folder, 'failure.json'), JSON.stringify({error: error.stack, checks, cases, errors, url: page?.url(),
    text: await page?.locator('body').innerText().catch(() => '(closed)')}, null, 2)); throw error;
} finally {
  gates.forEach(gate => gate.resolve()); if (browser) await browser.close(); await stopService();
  if (prepared) r('cancel');
  for (let i = 0; i < services.length; i++) await fs.writeFile(path.join(folder, `service-${i + 1}.log`), services[i].log);
}
