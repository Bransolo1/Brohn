// Portable connected release smoke. Called by run-connected-smoke.ps1 with
// runtime-only JSON on stdin; no installed workspace, saved QA store or Git needed.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import {spawn, spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {sha256, validateDestination, runtimeEnvironment, pinnedTools, sourceHashes} from './fixtures/connected-smoke-support.mjs';

let input = '';
for await (const chunk of process.stdin) {input += chunk; assert.ok(Buffer.byteLength(input) <= 1048576, 'Smoke request exceeds 1 MiB');}
const request = JSON.parse(input.replace(/^\uFEFF/, ''));
assert.equal(request.schema, 'brohn-connected-smoke-request/1.0');
const project = await fs.realpath(path.resolve(import.meta.dirname, '..'));
assert.equal(await fs.realpath(request.project), project, 'Launch the harness in the selected checkout');
const configurationStart = sha256(await fs.readFile(request.configuration_path));
assert.equal(configurationStart, request.configuration_sha256, 'Installation configuration changed during launch');
const folder = await validateDestination(request); await fs.mkdir(folder);
const env = runtimeEnvironment(request, folder); await fs.mkdir(env.R_USER);
const checks = [], scans = [], errors = [], cycles = []; let browser, context, page, activePage, child, cycle = 0, log = '', failure;
let tools, sourceStart, ports, deadline;
const started = new Date().toISOString();
const questions = [
  {type: 'rating', prompt: 'How clear is this original concept?', required: true, answer: 4},
  {type: 'text', prompt: 'Optional original comment', required: false, answer: null},
  {type: 'text', prompt: 'Optional whitespace comment', required: false, answer: null, input: '   '},
  {type: 'text', prompt: 'Original exact text', required: false, answer: '  Caf\u00e9 + original concept  ', input: '  Caf\u00e9 + original concept  '},
  {type: 'rating', prompt: 'Optional second rating', required: false, answer: null}
];
const check = (ok, label) => {assert.ok(ok, label); checks.push(label); console.log('PASS', label);};
const write = (file, data) => fs.writeFile(path.join(folder, file), JSON.stringify(data, null, 2));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(callback, timeout = 60000, label = 'Condition timed out') {
  const end = Date.now() + timeout;
  for (;;) {if (await callback()) return; assert.ok(Date.now() < end, label); await sleep(250);}
}
function runR(args, name, timeout = 120000) {
  const result = spawnSync(request.rscript, ['--vanilla', ...args], {cwd: project, env, windowsHide: true,
    encoding: 'utf8', maxBuffer: 8 * 1024 ** 2, timeout});
  return fs.writeFile(path.join(folder, name), `${result.stdout || ''}\n${result.stderr || ''}`).then(() => {
    assert.equal(result.status, 0, `${name}: R command failed; inspect the retained log (${result.error?.message || result.stderr || result.signal})`);
    return result.stdout;
  });
}
async function inspect() {
  await runR(['tests/fixtures/connected-smoke.R', 'inspect', folder], 'inspection.log');
  return JSON.parse(await fs.readFile(path.join(folder, 'inspection.json'), 'utf8'));
}
async function choosePorts() {
  const listeners = [];
  try {
    for (let i = 0; i < 2; i++) {
      const server = net.createServer(); listeners.push(server);
      await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});
    }
    return {researcher: listeners[0].address().port, participant: listeners[1].address().port};
  } finally {await Promise.all(listeners.map(server => new Promise(resolve => server.close(resolve))));}
}
async function start() {
  await fs.rm(path.join(folder, 'stop.request'), {force: true});
  cycle++; log = '';
  child = spawn(request.rscript, ['--vanilla', 'tests/fixtures/connected-smoke.R', 'serve', folder],
    {cwd: project, env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe']});
  let spawnError; child.once('error', error => {spawnError = error;});
  for (const stream of [child.stdout, child.stderr]) stream.on('data', bytes => {log += bytes;});
  await until(async () => {
    if (spawnError) throw spawnError;
    assert.equal(child.exitCode, null, `Connected launcher stopped before readiness: ${log}`);
    try {return (await fetch(`http://127.0.0.1:${ports.researcher}/`, {signal: AbortSignal.timeout(1500)})).ok;}
    catch {return false;}
  }, 90000, 'Actual integrated launcher did not become ready');
  const health = await (await fetch(`http://127.0.0.1:${ports.participant}/api/health`)).json();
  assert.equal(health.service, 'brohn-participant');
  cycles.push({cycle, supervisor_pid: child.pid, workspace_id: health.workspace_id, ports});
}
async function stop() {
  if (!child) return;
  const owned = child; await fs.writeFile(path.join(folder, 'stop.request'), 'Stop this owned smoke supervisor.');
  let forced = false;
  if (owned.exitCode === null) {
    try {await until(() => owned.exitCode !== null, 35000, 'Owned supervisor did not stop normally');}
    catch {
      forced = true;
      // Exact child PID only; never look up a process by a user's port or name.
      spawnSync('taskkill', ['/PID', String(owned.pid), '/T', '/F'], {windowsHide: true});
      await until(() => owned.exitCode !== null || owned.signalCode !== null, 10000, 'Owned process tree remains alive');
    }
  }
  await fs.writeFile(path.join(folder, `services-${cycle}.log`), log);
  Object.assign(cycles[cycles.length - 1] || {}, {exit_code: owned.exitCode, forced_cleanup: forced});
  child = null;
  check(!forced && owned.exitCode === 0 && log.includes('connected_smoke_owned_shutdown: TRUE'), `Service cycle ${cycle}: supervisor confirms all owned services stopped`);
}
async function scan(target, name, narrow = false) {
  await target.setViewportSize(narrow ? {width: 390, height: 844} : {width: 1440, height: 1080});
  const violations = (await new tools.AxeBuilder({page: target}).analyze()).violations;
  scans.push({name, violations: violations.length}); await write(name + '-axe.json', violations);
  await target.screenshot({path: path.join(folder, name + '.png'), fullPage: false});
  check(!violations.length, name + ': no automated accessibility violations');
  check(await target.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), name + ': no horizontal overflow');
}

try {
  sourceStart = await sourceHashes(project); await write('source-start.json', sourceStart);
  tools = await pinnedTools(request);
  const doctor = await runR(['scripts/doctor.R', '--library', request.r_library, '--profiles', 'none', '--required-profiles', 'none', '--require-portability', '--json'], 'doctor.json');
  const readiness = JSON.parse(doctor); assert.equal(readiness.status, 'ready');
  check(readiness.core.r_matches && readiness.publication.ready, 'Explicit pinned R library and protected report publication are ready');
  // A real launch verifies that the specified installed executable can speak
  // Playwright's protocol. It installs no browser or packages.
  browser = await tools.playwright.chromium.launch({executablePath: request.browser_executable, headless: true});
  const prerequisite = {node: process.version, tools: tools.versions, browser_version: browser.version(),
    browser_sha256: tools.browser_sha256, configuration_sha256: configurationStart,
    r_version: readiness.core.r_version, lock_sha256: sha256(await fs.readFile(path.join(project, 'renv.lock'))),
    publication_manifest_sha256: sha256(await fs.readFile(request.publication_manifest)),
    scope: 'Configured runtime checks on an existing Windows host. No installation, clean-OS, device, TLS or OIDC qualification.'};
  await write('prerequisites.json', prerequisite);
  check(true, 'Explicit installed browser and exact pinned Playwright/axe tools are usable');
  if (!request.check_only) {
    await write('smoke-marker.json', {schema: 'brohn-connected-smoke/1.0', origin: 'original_synthetic', started});
    ports = await choosePorts(); env.RESEARCH_PLATFORM_PORT = String(ports.researcher); env.BROHN_PARTICIPANT_PORT = String(ports.participant);
    const expect = tools.playwright.expect.configure({timeout: 60000});
    deadline = setTimeout(() => {failure = new Error('Connected smoke exceeded its 15 minute safety budget');
      browser?.close().catch(() => {}); fs.writeFile(path.join(folder, 'stop.request'), 'Smoke time budget reached.').catch(() => {});}, 15 * 60000);
    context = await browser.newContext({viewport: {width: 1440, height: 1080}});
    page = await context.newPage(); activePage = page;
    page.on('pageerror', error => errors.push(error.message));
    const idle = async () => {
      await page.waitForFunction(() => !document.documentElement.classList.contains('shiny-busy') &&
        ![...document.querySelectorAll('.recalculating')].some(e => e.getClientRects().length));
      await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);
    };
    const stage = async name => {
      await page.getByRole('button', {name, exact: true}).click();
      await page.waitForFunction(name => {const field = document.getElementById('study_form_identity');
        return field?.value.endsWith(':' + name) && Shiny.shinyapp.$inputValues.study_form_identity === field.value;}, name);
      await idle();
    };
    const select = async (id, value) => {
      const label = await page.locator('#' + id).evaluate((el, key) => el.selectize.options[key][el.selectize.settings.labelField], value);
      await page.locator('#' + id + '-selectized').fill(label);
      await page.locator(`.selectize-dropdown:visible [data-value="${value}"]`).click();
    };
    await start(); const home = `http://127.0.0.1:${ports.researcher}/`;
    await page.goto(home); await page.getByRole('button', {name: 'Start my study', exact: true}).click();
    await page.getByLabel('Study name', {exact: true}).fill('Original portable release smoke');
    await page.locator('input[name="new_template"][value="survey"]').check();
    await page.getByRole('button', {name: 'Create study', exact: true}).click(); await idle();
    await stage('Questions');
    for (const [index, question] of questions.entries()) {
      await page.locator('#question_type').selectOption(question.type);
      await page.getByRole('button', {name: 'Add question', exact: true}).click();
      await page.locator('#q_prompt_' + (index + 1)).fill(question.prompt);
      if (!question.required) await page.locator('#q_required_' + (index + 1)).uncheck();
    }
    await stage('Plan');
    await page.getByLabel('Instructions after consent', {exact: true}).fill('Rate this original concept, then answer or omit each optional question as instructed by the original test.');
    await stage('Collect'); await select('release_origin', 'sample'); await page.getByLabel('Maximum participant starts', {exact: true}).fill('1');
    await page.getByRole('button', {name: 'Release participant study', exact: true}).click();
    const releaseLink = page.getByRole('link', {name: 'Open participant study', exact: true}); await expect(releaseLink).toHaveCount(1);
    const releaseUrl = await releaseLink.getAttribute('href');
    const before = await inspect(); assert.equal(before.study.body.questions.length, questions.length); assert.equal(before.deployments.length, 1);
    assert.equal(before.runs.length, 0); assert.equal(before.reports.length, 0);
    check(before.study.body.questions[1].required === false && before.deployments[0].origin === 'sample', 'Actual researcher controls save and release the original survey with explicit sample origin and optional omission');
    await scan(page, 'researcher-release');
    const participantContext = await browser.newContext({viewport: {width: 390, height: 844}});
    const participant = await participantContext.newPage(); activePage = participant;
    participant.on('pageerror', error => errors.push(error.message));
    await participant.goto(releaseUrl);
    check(participant.url().includes('/api/runtime/'), 'Actual participant link redirects to the release-preserved runtime');
    await participant.getByLabel('I have read the study information and agree to take part.', {exact: true}).check();
    await participant.getByRole('button', {name: 'Start study', exact: true}).click();
    await participant.getByRole('button', {name: 'Begin', exact: true}).click();
    for (const [index, question] of questions.entries()) {
      await participant.getByRole('heading', {name: question.prompt, exact: true}).waitFor();
      if (index === 0) {
        await participant.getByRole('button', {name: 'Continue', exact: true}).click();
        await expect(participant.locator('body')).toContainText('Please answer this question before continuing.');
        await expect(participant.getByRole('heading', {name: question.prompt, exact: true})).toBeVisible();
        check(true, 'Required unanswered rating is refused in the actual participant form');
      }
      if (question.type === 'rating' && question.answer !== null) await participant.getByRole('radio', {name: String(question.answer), exact: true}).check();
      if (question.input !== undefined) await participant.getByRole('textbox', {name: 'Your answer', exact: true}).fill(question.input);
      await participant.getByRole('button', {name: 'Continue', exact: true}).click();
    }
    await participant.getByRole('heading', {name: 'Thank you. Your responses are saved.', exact: true}).waitFor();
    await scan(participant, 'participant-completed-390', true); await participantContext.close(); activePage = page;
    let saved;
    await until(async () => {
      saved = await inspect(); const jobs = saved.jobs.filter(job => job.operation === 'analyse_run');
      assert.ok(jobs.every(job => !['failed', 'cancelled'].includes(job.status)), 'Automatic analysis failed: ' + JSON.stringify(jobs.map(j => j.error)));
      return jobs.length === 1 && jobs[0].status === 'succeeded' && saved.reports.length === 1;
    }, 180000, 'One automatic saved report did not become available');
    await write('saved-checkpoint.json', saved);
    const run = saved.runs[0], report = saved.reports[0], body = report.body, observations = body.analysis.observations;
    assert.equal(saved.runs.length, 1); assert.equal(run.status, 'completed'); assert.equal(run.transfer_status, 'saved'); assert.equal(run.origin, 'sample');
    const committed = run.events.filter(e => e.type === 'response'); assert.equal(committed.length, questions.length);
    assert.deepEqual(committed.map(e => e.payload.value), questions.map(q => q.answer));
    assert.deepEqual(run.events.map(e => e.sequence), Array.from({length: run.events.length}, (_, i) => i + 1));
    assert.equal(run.events.at(-1).type, 'run_finished'); assert.equal(run.acked_sequence, run.events.length);
    check(true, 'Actual receiver commits the complete journal: numeric 4, blank/whitespace/unselected omissions and exact nonblank text with original spacing');
    assert.equal(observations.length, questions.length);
    assert.deepEqual(observations.map(o => o.value), questions.map(q => q.answer));
    assert.ok(observations.every(o => o.session_id === run.id && o.origin === 'sample' && o.participant_id === 'unlinked:' + run.id));
    for (const row of observations) {const event = committed.find(e => e.sequence === row.sequence);
      assert.ok(event); assert.deepEqual(event.payload.value, row.value); assert.equal(event.step_id, row.exposure_id);}
    assert.equal(body.analysis.features.length, questions.length);
    for (const [index, question] of questions.entries()) {
      const feature = body.analysis.features[index], row = observations[index], omitted = question.answer === null;
      assert.equal(row.prompt, question.prompt); assert.equal(feature.prompt, question.prompt);
      assert.equal(row.missing_reason, omitted ? 'optional_omission' : null);
      assert.equal(feature.numeric_response_mean, typeof question.answer === 'number' ? question.answer : null);
      assert.equal(feature.response_count, 1); assert.equal(feature.answered_count, omitted ? 0 : 1); assert.equal(feature.missing_count, omitted ? 1 : 0);
      assert.deepEqual(feature.counts.map(x => [x.value, x.count]), omitted ? [] : [[question.answer, 1]]);
    }
    assert.equal(body.analysis.quality.participant_count, null); assert.equal(body.analysis.quality.unlinked_session_count, 1); assert.equal(body.analysis.quality.missing_response_count, 3);
    assert.deepEqual(body.analysis.contrasts, []);
    check(true, 'Saved worker output matches independent value/count/missingness expectations and does not invent unique people or inferential contrasts');
    const analysisJob = saved.jobs.find(j => j.operation === 'analyse_run'); assert.equal(analysisJob.attempt, 1);
    assert.equal(analysisJob.result.report_id, report.id); assert.equal(body.processing.job_id, analysisJob.id);
    assert.equal(body.processing.publication.native_seal, true); assert.equal(body.provenance.runs[0].events_hash, run.events_hash);
    assert.equal(saved.runtime_assignments.length, 1); assert.equal(saved.runtime_assignments[0].run_id, run.id);
    check(Object.keys(body.processing.code_hashes).length > 0, 'One supervised analysis attempt publishes the source-bound report with native protection and preserved runtime assignment');
    const openReport = async () => {
      await page.getByRole('button', {name: 'Studies', exact: true}).click();
      await page.getByLabel('Search studies', {exact: true}).fill('Original portable release smoke');
      await page.locator(`[data-brohn-event="brohn_open_study"][data-brohn-value='"${saved.study.id}"']`).click();
      await stage('Results'); await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${report.id}"']`).click();
      await page.getByRole('link', {name: 'JSON + provenance', exact: true}).waitFor(); await idle();
    };
    const download = async (label, filename) => {
      const link = page.getByRole('link', {name: label, exact: true}); await expect(link).toHaveAttribute('href', /session\/.*download\//);
      const pending = page.waitForEvent('download'); await link.click(); const item = await pending;
      assert.equal(await item.failure(), null); const file = path.join(folder, filename); await item.saveAs(file); return file;
    };
    await openReport(); await scan(page, 'saved-report-390', true); await page.setViewportSize({width: 1440, height: 1080});
    const jsonFile = await download('JSON + provenance', 'report.json'), jsonBytes = await fs.readFile(jsonFile);
    assert.deepEqual(JSON.parse(jsonBytes), body);
    const csvFile = await download('Download observations', 'observations.csv');
    const parsed = spawnSync(request.portability_python, ['-c', 'import csv,json,sys; print(json.dumps(list(csv.DictReader(open(sys.argv[1],encoding="utf-8-sig",newline="")))))', csvFile],
      {windowsHide: true, env, encoding: 'utf8', timeout: 15000});
    assert.equal(parsed.status, 0, parsed.stderr); const rows = JSON.parse(parsed.stdout);
    assert.deepEqual(rows.map(row => JSON.parse(row.response_record_json)), observations);
    assert.equal(rows[0].value, '4'); assert.equal(rows[1].value, ''); assert.equal(rows[1].missing_reason, 'optional_omission');
    assert.equal(rows[3].value, questions[3].answer);
    check(true, 'Actual JSON equals the retained report and CSV independently reconstructs all five typed response records, preserving nonblank text spacing');
    const htmlFile = await download('Download report', 'report.html'); const offline = await context.newPage(); activePage = offline;
    await offline.goto(pathToFileURL(htmlFile).href);
    for (const question of questions) await expect(offline.locator('body')).toContainText(question.prompt);
    await scan(offline, 'offline-report-390', true); await offline.close(); activePage = page;
    await context.close(); await stop(); await start();
    context = await browser.newContext({viewport: {width: 1440, height: 1080}}); page = await context.newPage(); activePage = page;
    page.on('pageerror', error => errors.push(error.message)); await page.goto(home); await openReport();
    const reopened = await fs.readFile(await download('JSON + provenance', 'report-reopened.json'));
    assert.equal(sha256(reopened), sha256(jsonBytes)); const after = await inspect();
    assert.deepEqual(after.study, saved.study); assert.deepEqual(after.reports, saved.reports); assert.deepEqual(after.runs, saved.runs);
    assert.deepEqual(after.runtime_assignments, saved.runtime_assignments);
    assert.equal(after.jobs.filter(j => j.operation === 'analyse_run').length, 1);
    check(true, 'Complete supervisor restart and fresh researcher session reopen byte-identical report, unchanged design/journal/runtime assignment and no duplicate automatic analysis');
    check(!errors.length, 'No uncaught participant or researcher browser exceptions');
    await context.close(); await stop();
    await write('downloads.json', Object.fromEntries(await Promise.all(['report.json', 'observations.csv', 'report.html', 'report-reopened.json'].map(async file =>
      [file, {sha256: sha256(await fs.readFile(path.join(folder, file))), bytes: (await fs.stat(path.join(folder, file))).size}]))));
  }
} catch (error) {
  failure ||= error;
  await activePage?.screenshot({path: path.join(folder, 'failure.png'), fullPage: true}).catch(() => {});
  await write('failure.json', {error: failure.stack, checks, errors, scans, text: await activePage?.locator('body').innerText().catch(() => '(closed)')});
} finally {
  clearTimeout(deadline);
  try {await browser?.close();} catch (error) {failure ||= error;}
  try {await stop();} catch (error) {failure ||= error;}
  try {
    const sourceEnd = await sourceHashes(project); await write('source-end.json', sourceEnd);
    assert.deepEqual(sourceEnd, sourceStart, 'Source changed during smoke qualification');
    assert.equal(sha256(await fs.readFile(request.configuration_path)), configurationStart, 'Installation configuration changed');
    check(true, 'Runtime/test sources and supplied installation configuration retain their original bytes');
  } catch (error) {failure ||= error;}
  await write('results.json', {schema: 'brohn-connected-smoke-result/1.0', status: failure ? 'failed' : 'passed', started,
    finished: new Date().toISOString(), mode: request.check_only ? 'readiness_only' : 'connected_browser', checks, scans, errors, cycles,
    configuration_sha256: configurationStart, failure: failure?.stack || null,
    limits: ['Original synthetic responses on loopback; no live people or scientific validation.',
      'Existing configured Windows host and external runtimes, not a clean-OS installation.',
      'Core questionnaire release/report/persistence only; no device, media, hosted TLS/OIDC, large-cohort or full-product acceptance.']});
}
if (failure) {console.error(failure.message); process.exitCode = 1;}
console.log(JSON.stringify({status: failure ? 'failed' : 'passed', checks: checks.length, scans: scans.length, folder}));
