// Explicit runtime request on stdin; isolated fresh store, real UI and complete
// named procedure. No seeded studies, short procedure, responses or reports.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import {spawn, spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {sha256, overlaps, validateDestination, runtimeEnvironment, pinnedTools, sourceHashes} from './fixtures/connected-smoke-support.mjs';
import {profile, aliases, responsePlan, assertJournal, expectedCells, assertScore} from './researcher-gnat-oracle.mjs';

let input = '';
for await (const chunk of process.stdin) {input += chunk; assert.ok(Buffer.byteLength(input) <= 1048576);}
const request = JSON.parse(input.replace(/^\uFEFF/, ''));
assert.equal(request.schema, 'brohn-researcher-gnat-request/1.0');
const project = await fs.realpath(path.resolve(import.meta.dirname, '..'));
assert.equal(await fs.realpath(request.project), project);
const configurationStart = sha256(await fs.readFile(request.configuration_path));
assert.equal(configurationStart, request.configuration_sha256);
const folder = await validateDestination(request); await fs.mkdir(folder);
const env = runtimeEnvironment(request, folder); await fs.mkdir(env.R_USER);
const checks = [], scans = [], errors = [], cycles = [], journey = {runs: {}, native_reports: {}, imports: {}};
const title = 'Original Aster GNAT researcher journey', started = new Date().toISOString();
let browser, context, page, active, child, cycle = 0, log = '', failure, deadline, tools, expect, ports, startHashes, inherited = null;
const ownFiles = ['tests/researcher-gnat.mjs', 'tests/researcher-gnat-oracle.mjs', 'tests/fixtures/researcher-gnat.R'];
const hashes = async () => ({...await sourceHashes(project), ...Object.fromEntries(await Promise.all(ownFiles.map(async file => [file, sha256(await fs.readFile(path.join(project, file)))])))});
const write = (file, value) => fs.writeFile(path.join(folder, file), JSON.stringify(value, null, 2));
const save = () => write('journey.json', journey);
const check = (label, ok = true) => {assert.ok(ok, label); checks.push(label); console.log('PASS', label);};
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function treeHashes(directory) {
  const result = {};
  async function walk(relative) {
    for (const entry of await fs.readdir(path.join(directory, relative), {withFileTypes: true})) {
      const member = path.join(relative, entry.name); assert.ok(!entry.isSymbolicLink(), 'QA recovery cannot follow workspace links');
      if (entry.isDirectory()) await walk(member);
      else {const bytes = await fs.readFile(path.join(directory, member)); result[member.replaceAll('\\', '/')] = sha256(bytes);}
    }
  }
  await walk(''); return result;
}
async function recoverStoppedCopy() {
  if (!request.resume_from) return;
  const root = await fs.realpath(request.resume_from);
  assert.ok(!overlaps(root, folder) && !overlaps(root, request.forbidden_workspace) && !overlaps(root, project));
  const previousBytes = await fs.readFile(path.join(root, 'results.json'));
  const previous = JSON.parse(previousBytes);
  assert.equal(previous.schema, 'brohn-researcher-gnat-result/1.0'); assert.equal(previous.status, 'failed');
  assert.ok(previous.cycles.length && previous.cycles.every(c => c.exit_code === 0 && !c.forced_cleanup), 'Resume only a stopped synthetic QA store');
  const marker = JSON.parse(await fs.readFile(path.join(root, 'gnat-marker.json'), 'utf8'));
  assert.equal(marker.schema, 'brohn-researcher-gnat/1.0'); assert.equal(marker.origin, 'original_synthetic');
  const originalSources = JSON.parse(await fs.readFile(path.join(root, 'source-start.json'), 'utf8'));
  assert.deepEqual(JSON.parse(await fs.readFile(path.join(root, 'source-end.json'), 'utf8')), originalSources);
  for (const [file, value] of Object.entries(originalSources)) if (!file.startsWith('tests/'))
    assert.equal(startHashes[file], value, 'Recovery holds the same production source: ' + file);
  const originalWorkspace = path.join(root, 'workspace'), originalHashes = await treeHashes(originalWorkspace);
  await fs.cp(originalWorkspace, path.join(folder, 'workspace'), {recursive: true, errorOnExist: true, force: false});
  assert.deepEqual(await treeHashes(path.join(folder, 'workspace')), originalHashes);
  assert.deepEqual(await treeHashes(originalWorkspace), originalHashes);
  Object.assign(journey, JSON.parse(await fs.readFile(path.join(root, 'journey.json'), 'utf8')));
  inherited = {source: root, original_workspace: originalWorkspace, original_hashes: originalHashes,
    result_sha256: sha256(previousBytes), production_sources: Object.fromEntries(Object.entries(originalSources).filter(([p]) => !p.startsWith('tests/'))),
    inherited_run_ids: Object.values(journey.runs), inherited_report_ids: Object.values(journey.native_reports), prior_checks: previous.checks, prior_scans: previous.scans};
  inherited.carried_artifacts = {};
  for (const name of await fs.readdir(root)) if (/^ORIGINAL-GNAT-\d+-(assigned|browser|independent-oracle|feedback)\.json$/.test(name)) {
    const bytes = await fs.readFile(path.join(root, name)); await fs.writeFile(path.join(folder, name), bytes);
    inherited.carried_artifacts[name] = {source: path.join(root, name), sha256: sha256(bytes)};
  }
  await write('inherited-phase.json', inherited);
  check('Fresh recovery workspace exactly copies a stopped synthetic source with unchanged original files and production code');
}
async function reuseVerifiedNativeUi(alias, record) {
  if (!inherited || !request.verified_native_ui_from || !inherited.inherited_run_ids.includes(journey.runs[alias])) return false;
  const supplied = typeof request.verified_native_ui_from === 'string' ? request.verified_native_ui_from : request.verified_native_ui_from[alias];
  const root = await fs.realpath(supplied);
  assert.ok(!overlaps(root, folder) && !overlaps(root, request.forbidden_workspace) && !overlaps(root, project));
  const bytes = await fs.readFile(path.join(root, 'results.json')), result = JSON.parse(bytes);
  assert.equal(result.schema, 'brohn-researcher-gnat-result/1.0');
  assert.ok(result.cycles.length && result.cycles.every(c => c.exit_code === 0 && !c.forced_cleanup));
  assert.ok(result.checks.includes(alias + ': complete saved native plots and numerical exports retain 384 trials'));
  assert.ok(result.scans.some(s => s.label === alias + '-plot-390' && s.violations === 0 && !s.overflow));
  assert.equal(result.journey.native_reports[alias], record.id);
  const sources = JSON.parse(await fs.readFile(path.join(root, 'source-start.json')));
  assert.deepEqual(JSON.parse(await fs.readFile(path.join(root, 'source-end.json'))), sources);
  for (const [file, hash] of Object.entries(sources)) if (!file.startsWith('tests/')) assert.equal(startHashes[file], hash);
  const saved = await fs.readFile(path.join(root, alias + '-native-report.json'));
  assert.deepEqual(JSON.parse(saved), record.body);
  await fs.writeFile(path.join(folder, alias + '-native-report.json'), saved);
  await write(alias + '-inherited-ui.json', {source: root, result_sha256: sha256(bytes), report_sha256: sha256(saved),
    report_id: record.id, scope: 'Prior exact-production-source completed native report/384-row plot/export/mobile checks; not rerun in this continuation.'});
  check(alias + ': previously passed exact-source native UI and export phase retained explicitly without repeating it'); return true;
}
async function until(fn, timeout = 60000, label = 'Condition timed out') {
  const end = Date.now() + timeout;
  for (;;) {if (failure) throw failure; if (await fn()) return; assert.ok(Date.now() < end, label); await sleep(300);}
}
async function runR(args, name, timeout = 120000) {
  const result = spawnSync(request.rscript, ['--vanilla', ...args], {cwd: project, env, windowsHide: true,
    encoding: 'utf8', maxBuffer: 16 * 1024 ** 2, timeout});
  await fs.writeFile(path.join(folder, name), `${result.stdout || ''}\n${result.stderr || ''}`);
  assert.equal(result.status, 0, `${name}: ${result.error?.message || result.stderr || result.signal}`); return result.stdout;
}
async function snapshot() {await runR(['tests/fixtures/researcher-gnat.R', 'inspect', folder], 'inspection.log');
  return JSON.parse(await fs.readFile(path.join(folder, 'snapshot.json'), 'utf8'));}
function python(code, args = [], data = undefined) {
  const result = spawnSync(request.portability_python, ['-c', code, ...args], {env, windowsHide: true,
    encoding: 'utf8', input: data, maxBuffer: 32 * 1024 ** 2, timeout: 30000});
  assert.equal(result.status, 0, result.stderr); return JSON.parse(result.stdout);
}
function jobRows() {
  return python("import sqlite3,json,pathlib,sys;c=sqlite3.connect(pathlib.Path(sys.argv[1]).resolve().as_uri()+'?mode=ro',uri=True);c.row_factory=sqlite3.Row;r=[dict(x) for x in c.execute('SELECT id,operation,status,attempt,request_json,error_json FROM jobs ORDER BY created_at,id')];[x.update(request=json.loads(x.pop('request_json'))) for x in r];print(json.dumps(r));c.close()", [path.join(folder, 'workspace/catalog.sqlite')]);
}
async function drain() {
  await until(() => {const rows = jobRows(); assert.deepEqual(rows.filter(j => ['failed', 'cancelled'].includes(j.status)), []);
    return !rows.some(j => ['queued', 'running', 'cancelling'].includes(j.status));}, 240000, 'Actual automatic workers did not reach successful terminal state');
  return snapshot();
}
async function choosePorts() {
  const listeners = [];
  try {for (let i = 0; i < 2; i++) {const server = net.createServer(); listeners.push(server);
    await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});}
    return {researcher: listeners[0].address().port, participant: listeners[1].address().port};
  } finally {await Promise.all(listeners.map(server => new Promise(resolve => server.close(resolve))));}
}
async function start() {
  await fs.rm(path.join(folder, 'stop.request'), {force: true}); cycle++; log = '';
  child = spawn(request.rscript, ['--vanilla', 'tests/fixtures/researcher-gnat.R', 'serve', folder],
    {cwd: project, env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe']});
  let error; child.once('error', value => {error = value;});
  for (const stream of [child.stdout, child.stderr]) stream.on('data', bytes => {log += bytes;});
  cycles.push({cycle, supervisor_pid: child.pid, ports});
  await until(async () => {if (error) throw error; assert.equal(child.exitCode, null, log);
    try {return (await fetch(`http://127.0.0.1:${ports.researcher}/`, {signal: AbortSignal.timeout(1500)})).ok;} catch {return false;}
  }, 90000, 'Owned integrated supervisor did not start');
  const health = await (await fetch(`http://127.0.0.1:${ports.participant}/api/health`)).json();
  assert.equal(health.service, 'brohn-participant'); cycles.at(-1).workspace_id = health.workspace_id;
}
async function stop() {
  if (!child) return; const owned = child;
  await fs.writeFile(path.join(folder, 'stop.request'), 'Stop this owned original GNAT supervisor.');
  let forced = false;
  if (owned.exitCode === null) {
    const limit = Date.now() + 35000;
    while (owned.exitCode === null && Date.now() < limit) await sleep(250);
    if (owned.exitCode === null) {forced = true; spawnSync('taskkill', ['/PID', String(owned.pid), '/T', '/F'], {windowsHide: true});
      const end = Date.now() + 10000; while (owned.exitCode === null && owned.signalCode === null && Date.now() < end) await sleep(100);}
  }
  await fs.writeFile(path.join(folder, `services-${cycle}.log`), log);
  Object.assign(cycles.at(-1), {exit_code: owned.exitCode, forced_cleanup: forced}); child = null;
  check(`Service cycle ${cycle}: complete owned-process shutdown`, !forced && owned.exitCode === 0 && log.includes('researcher_gnat_owned_shutdown: TRUE'));
}
const button = name => page.getByRole('button', {name, exact: true});
async function idle() {
  await page.waitForFunction(() => !document.documentElement.classList.contains('shiny-busy') &&
    ![...document.querySelectorAll('.recalculating')].some(e => e.getClientRects().length));
  await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);
}
async function stage(name) {
  await button(name).click();
  if (['Plan', 'Questions', 'Tasks', 'Collect', 'Results'].includes(name)) await page.waitForFunction(n => {
    const field = document.getElementById('study_form_identity');
    return field?.value.endsWith(':' + n) && Shiny.shinyapp.$inputValues.study_form_identity === field.value;
  }, name);
  await idle();
}
async function selectValue(id, value) {
  const field = page.locator('#' + id);
  const label = await field.evaluate((node, key) => node.selectize?.options[key]?.[node.selectize.settings.labelField] ?? [...node.options].find(o => o.value === key)?.textContent, value);
  assert.ok(label, `Available ${id} option ${value}`);
  if (await field.evaluate(node => !!node.selectize)) {await page.locator('#' + id + '-selectized').fill(label);
    await page.locator(`.selectize-dropdown:visible [data-value="${value}"]`).click();}
  else await field.selectOption(value);
}
async function openStudy() {
  await stage('Studies'); await page.getByLabel('Search studies', {exact: true}).fill(title);
  await page.locator(`[data-brohn-event="brohn_open_study"][data-brohn-value='"${journey.study_id}"']`).click(); await idle();
}
async function download(label, filename) {
  const link = page.getByRole('link', {name: label, exact: true}); await expect(link).toHaveAttribute('href', /session\/.*download\//);
  const pending = page.waitForEvent('download'); await link.click(); const item = await pending;
  assert.equal(await item.failure(), null); const file = path.join(folder, filename); await item.saveAs(file); return file;
}
async function scan(label, narrow = false, target = page, anchor = null) {
  await target.setViewportSize(narrow ? {width: 390, height: 844} : {width: 1440, height: 1080});
  if (target === page) await idle();
  if (anchor) await target.locator(anchor).first().scrollIntoViewIfNeeded();
  const violations = (await new tools.AxeBuilder({page: target}).withTags(['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa']).analyze()).violations;
  const overflow = await target.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1);
  scans.push({label, violations: violations.length, overflow}); await write(label + '-axe.json', violations);
  await target.screenshot({path: path.join(folder, label + '.png')});
  check(label + ': automated accessibility and no page overflow', !violations.length && !overflow);
  await target.setViewportSize({width: 1440, height: 1080});
}
async function journal(target) {
  return target.evaluate(() => new Promise((resolve, reject) => {const open = indexedDB.open('brohn-participant', 1);
    open.onerror = () => reject(open.error); open.onsuccess = () => {const db = open.result;
      const request = db.transaction('sessions').objectStore('sessions').getAll();
      request.onsuccess = () => {resolve(request.result); db.close();}; request.onerror = () => reject(request.error);
    };}));
}
async function installStimulusObserver(target) {
  // Passive DOM observation only. This does not patch clocks, the renderer,
  // persistence, keyboard events or scientific evidence.
  await target.addInitScript(() => {
    const seen = new WeakSet(), observed = {onsets: [], current: null};
    window.__brohnGnatQaObservation = observed;
    new MutationObserver(() => {
      const material = document.querySelector('.brohn-gnat .gnat-material');
      if (!material) {observed.current = null; return;}
      if (seen.has(material)) return;
      seen.add(material); const item = {position: observed.onsets.length + 1, text: material.textContent, observed_ms: performance.now()};
      observed.onsets.push(item); observed.current = item;
    }).observe(document, {childList: true, subtree: true});
  });
}
async function currentStimulus(target, position, entry) {
  const ready = await target.waitForFunction(position => {
    const state = window.__brohnGnatQaObservation;
    if (state?.onsets.length > position) return {late: true, latest: state.onsets.length};
    return state?.current?.position === position ? state.current : false;
  }, position, {timeout: 15000});
  const onset = await ready.jsonValue(); await ready.dispose();
  assert.equal(onset.late, undefined, 'Automation must not press a later stimulus'); assert.equal(onset.text, entry.material.content);
  // The product commits this exact trial checkpoint before showing its word.
  // Read it once inside the page and return only identity plus small DOM state,
  // never serialize the growing journal through the automation protocol.
  const identity = await target.evaluate(() => new Promise((resolve, reject) => {
    const open = indexedDB.open('brohn-participant', 1); open.onerror = () => reject(open.error);
    open.onsuccess = () => {const db = open.result, token = new URL(location.href).searchParams.get('token');
      const read = db.transaction('sessions').objectStore('sessions').get(token);
      read.onerror = () => reject(read.error); read.onsuccess = () => {
        resolve({checkpoint: read.result?.task_checkpoint, current: window.__brohnGnatQaObservation.current, now: performance.now()}); db.close();
      };
    };
  }));
  assert.equal(identity.checkpoint.step_id, entry.id, 'Visible word must have its actual durable trial identity');
  assert.equal(identity.checkpoint.task_id, entry.task_id);
  assert.equal(identity.checkpoint.phase, 'timed'); assert.equal(identity.current?.position, position, 'Exact stimulus remains live');
  assert.equal(identity.current.text, entry.material.content);
  assert.ok(identity.now - onset.observed_ms < entry.timeout_ms - 150, 'Automation must retain a response dispatch margin before the unchanged deadline');
  return identity;
}
function zipDesign(file) {return python("import json,zipfile,sys;print(zipfile.ZipFile(sys.argv[1]).read('design.json').decode('utf-8'))", [file]);}
async function importSource(file) {
  await page.locator('#dataset_upload').setInputFiles(file);
  await expect(page.locator('#ingestion_upload_review')).toContainText(`Ready to import: ${path.basename(file)}`);
  await page.waitForFunction(() => {const field = document.getElementById('ingestion_upload_review_identity');
    return field?.classList.contains('shiny-bound-input') && !document.getElementById('ingestion_upload_review')?.classList.contains('recalculating') &&
      Shiny.shinyapp.$inputValues.ingestion_upload_review_identity === field.value;});
  await page.locator('#start_source_import').click();
  await expect(page.locator('#dataset_form_identity')).toHaveValue(/^dataset-[^:]+:[1-9][0-9]*$/, {timeout: 180000});
  return (await page.locator('#dataset_form_identity').inputValue()).split(':')[0];
}
async function openReport(id) {
  await openStudy(); await stage('Results');
  await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${id}"']`).click(); await idle();
  await expect(page.getByRole('link', {name: 'JSON + provenance', exact: true})).toHaveAttribute('href', /session\/.*download\//);
}
async function plotReport(prefix, expectedRows) {
  await button('Open task plots').click();
  await page.waitForFunction(() => {const field = document.getElementById('task_plot_catalog_identity');
    return field && Shiny.shinyapp.$inputValues.task_plot_catalog_identity === field.value;});
  await button('Show complete saved source').click(); await expect(page.locator('#task_plot_view h2')).toBeVisible();
  const complete = JSON.parse(await fs.readFile(await download('Download all task values + provenance', `${prefix}-plot.json`), 'utf8'));
  assert.equal(complete.selected_rows.length, expectedRows);
  const csv = await download('Download every selected row CSV', `${prefix}-plot.csv`);
  const exportedRows = python('import csv,json,sys;print(json.dumps([json.loads(r["exact_record_json"]) for r in csv.DictReader(open(sys.argv[1],encoding="utf-8-sig",newline=""))]))', [csv]);
  assert.deepEqual(exportedRows, complete.selected_rows);
  await download(expectedRows === 2 ? 'Download person outcomes SVG' : 'Download chronology SVG', `${prefix}-plot.svg`);
  if (expectedRows === 384) {
    assert.equal(complete.complete_source.profile, profile);
    assert.equal(complete.complete_source.evidence_level, prefix.endsWith('-imported') ? 'declared_trial_summary' : 'brohn_journal_replayed');
    assert.equal(complete.complete_source.timing.definition_known, true);
    await expect(page.locator('#task_plot_view .brohn-alert')).toHaveCount(0);
    const withheld = complete.selected_rows.filter(row => ['miss', 'correct_rejection'].includes(row.outcome));
    assert.equal(complete.withholding_without_latency, withheld.length);
    assert.ok(withheld.every(row => row.response_ms === null && row.first_response_ms === null && row.withholding_observed === true));
    assert.ok(complete.selected_rows.every(row => row.correct === ['hit', 'correct_rejection'].includes(row.outcome)));
    assert.equal(complete.outcome_counts.reduce((n, row) => n + row.count, 0), 384);
    assert.equal(complete.distribution_bins.reduce((n, bin) => n + bin.count, 0), 384 - withheld.length);
    const svg = await download('Download Go/No-Go outcomes SVG', `${prefix}-outcomes.svg`);
    const offline = await context.newPage(); await offline.goto(pathToFileURL(svg).href);
    assert.equal(await offline.locator('svg circle').count(), 384);
    assert.ok(await offline.locator('svg desc').textContent().then(text => text.includes('384 selected positions')));
    await offline.close();
    await selectValue('task_plot_scope', 'scored'); await idle();
    const scored = JSON.parse(await fs.readFile(await download('Download all task values + provenance', `${prefix}-test-only.json`), 'utf8'));
    assert.equal(scored.selected_rows.length, 240); assert.ok(scored.selected_rows.every(row => row.phase === 'test'));
    assert.deepEqual(scored.selected_rows, complete.selected_rows.filter(row => row.profile_scored));
    await selectValue('task_plot_scope', 'all'); await idle();
    await page.locator('#task_plot_page').fill('8'); await page.locator('#task_plot_page').press('Tab'); await idle();
    await expect(page.locator('#task_plot_view')).toContainText(complete.selected_rows[383].trial_id);
    await page.locator('#task_plot_page').fill('1'); await page.locator('#task_plot_page').press('Tab'); await idle();
    await expect(page.locator('#task_plot_view')).toContainText('Page 1 of 8 | 384 selected rows.');
    await expect(page.locator('#task_plot_view')).toContainText(complete.selected_rows[0].trial_id);
    check(prefix + ': all384/test240 selection, exact CSV rows and categorical SVG preserve observed withholding separately from missing data');
  }
  await scan(prefix + '-plot-390', true, page, '#task_plot_view .brohn-task-figure'); return complete;
}

try {
  startHashes = await hashes(); await write('source-start.json', startHashes);
  await fs.mkdir(path.join(folder, 'executed-tests'));
  for (const file of ownFiles) await fs.copyFile(path.join(project, file), path.join(folder, 'executed-tests', path.basename(file)));
  await recoverStoppedCopy();
  tools = await pinnedTools(request); expect = tools.playwright.expect.configure({timeout: 60000});
  const readiness = JSON.parse(await runR(['scripts/doctor.R', '--library', request.r_library, '--profiles', 'none', '--required-profiles', 'none', '--require-portability', '--json'], 'doctor.json'));
  assert.equal(readiness.status, 'ready'); assert.ok(readiness.publication.ready);
  browser = await tools.playwright.chromium.launch({executablePath: request.browser_executable, headless: true});
  await write('prerequisites.json', {node: process.version, tools: tools.versions, browser: browser.version(), browser_sha256: tools.browser_sha256,
    configuration_sha256: configurationStart, publication_manifest_sha256: sha256(await fs.readFile(request.publication_manifest))});
  check('Explicit configured R/native publication/Python and pinned external browser tools are ready');
  await write('gnat-marker.json', {schema: 'brohn-researcher-gnat/1.0', origin: 'original_synthetic', started});
  ports = await choosePorts(); env.RESEARCH_PLATFORM_PORT = String(ports.researcher); env.BROHN_PARTICIPANT_PORT = String(ports.participant);
  deadline = setTimeout(() => {failure = new Error('GNAT journey exceeded its 40 minute safety budget'); browser?.close().catch(() => {});
    fs.writeFile(path.join(folder, 'stop.request'), 'Safety budget reached.').catch(() => {});}, 40 * 60000);
  await start(); const home = `http://127.0.0.1:${ports.researcher}/`;
  context = await browser.newContext({viewport: {width: 1440, height: 1080}}); page = await context.newPage(); active = page;
  page.on('pageerror', error => errors.push(error.message)); await page.goto(home);
  let snap;
  if (!journey.study_id) {
  await button('Start my study').click(); await page.getByLabel('Study name', {exact: true}).fill(title);
  await page.locator('input[name="new_template"][value="blank"]').check(); await button('Create study').click(); await idle();
  await page.locator('#study_description').fill('Original synthetic consumer walkthrough: one fictional Aster concept, declared context and positive/negative attribute pairings.');
  await page.locator('#study_instructions').fill('Classify the original words using Space or withholding, then give a separate liking response. Automated software acceptance only.');
  await page.locator('#consent_text').fill('Original voluntary synthetic software walkthrough. No camera or audio recording. These automated inputs are not research observations.');
  await page.locator('#debrief_text').fill('Software walkthrough complete. No individual preference interpretation or scientific validation is claimed.');
  await stage('Tasks'); await selectValue('task_profile', profile); await button('Add procedure').click();
  await expect(page.locator('#task_title_1')).toBeVisible();
  await page.locator('#task_title_1').fill('Original Aster Go/No-Go association');
  await selectValue('task_origin_1', 'researcher_supplied');
  await page.locator('#task_control_1').fill('A fictional Aster target is contrasted across pleasant and unpleasant pairings against declared unrelated objects. No causal control or preference category is implied.');
  await page.locator('#task_rights_1').fill('Original fictional words authored for automated software acceptance; no vendor materials.');
  const materials = [
    ['Aster concept', ['Aster package', 'Aster display', 'Aster bottle', 'Aster label', 'Aster design']],
    ['Unrelated objects', ['Ladder', 'Blanket', 'Scooter']],
    ['Pleasant', ['Delightful', 'Welcoming', 'Wonderful', 'Kind']],
    ['Unpleasant', ['Awful', 'Cruel', 'Grim', 'Nasty']]
  ];
  for (const [index, [label, words]] of materials.entries()) {
    await page.locator('#task_category_1_' + (index + 1)).fill(label);
    await page.locator('#task_gnat_words_1_' + (index + 1)).fill(words.join('\n'));
  }
  await selectValue('task_gnat_context_kind_1', 'generic');
  await page.locator('#task_gnat_context_rationale_1').fill('Unrelated original objects form an explicit mixed context; they are not assumed neutral or validated.');
  await page.locator('#task_gnat_language_1').fill('English');
  await scan('gnat-authoring-desktop'); await scan('gnat-authoring-390', true);
  await stage('Questions'); await page.locator('#question_type').selectOption('rating'); await button('Add question').click();
  await page.locator('#q_prompt_1').fill('How much do you like the original Aster concept?'); await stage('Plan');
  await expect(page.locator('input[name="study_measures"][value="gnat"]')).toBeChecked();
  const designFile = await download('Export design', 'original-gnat.brohn-study.zip'), design = zipDesign(designFile);
  journey.study_id = design.id; journey.task_id = design.blocks[0].id;
  assert.equal(design.blocks[0].profile, profile); assert.equal(design.blocks[0].categories.length, 4);
  assert.equal(design.blocks[0].origin, 'researcher_supplied');
  for (const [index, [, words]] of materials.entries()) assert.deepEqual(design.blocks[0].materials.filter(m => m.category_id === design.blocks[0].categories[index].id).map(m => m.content), words);
  assert.equal(design.questions.length, 1); assert.equal(design.blocks[0].settings.language, 'English');
  await button('Save as template').click(); await idle(); await button('Clone design').click();
  await page.getByLabel('Name for the new study', {exact: true}).fill(title + ' clone'); await button('Create clone').click(); await idle();
  const clone = zipDesign(await download('Export design', 'cloned-gnat.brohn-study.zip')); journey.clone_id = clone.id;
  assert.notEqual(clone.blocks[0].id, design.blocks[0].id); assert.deepEqual(clone.blocks[0].settings, design.blocks[0].settings);
  await stage('Design library'); await page.locator('#import_design_file').setInputFiles(designFile); await page.locator('#study_title').waitFor();
  const portable = zipDesign(await download('Export design', 'reimported-gnat.brohn-study.zip')); journey.portable_id = portable.id;
  assert.notEqual(portable.id, design.id); assert.deepEqual(portable.blocks[0].settings, design.blocks[0].settings);
  assert.deepEqual(portable.blocks[0].materials.map(m => m.content), design.blocks[0].materials.map(m => m.content));
  snap = await snapshot(); assert.equal(snap.sessions.length, 0); assert.equal(snap.reports.length, 0); assert.ok(snap.templates.length);
  check('Actual researcher authors, saves, templates, clones and reimports the complete original GNAT design without copied observations'); await save();
  await openStudy(); await stage('Collect'); await selectValue('release_origin', 'sample'); await page.locator('#release_alias').check();
  await page.locator('#release_quota').fill('2'); await button('Release participant study').click();
  journey.participant_url = await page.getByRole('link', {name: 'Open participant study', exact: true}).getAttribute('href'); await save();
  } else {
    snap = await snapshot(); await write('inherited-store-baseline.json', snap);
    assert.ok(snap.jobs.every(j => j.status === 'succeeded'), 'No inherited pending job may be silently restarted');
    assert.ok(snap.sessions.every(s => s.run.completion_status === 'completed' && s.run.transfer_status === 'saved'), 'Never resume or replace a partial timed administration');
    const moved = new URL(journey.participant_url); moved.port = String(ports.participant); journey.participant_url = moved.href; await save();
  }

  if (!request.restart_only) {
  for (const [person, alias] of aliases.entries()) {
    if (!journey.runs[alias]) {
    const participantContext = await browser.newContext({viewport: {width: 1280, height: 900}}), target = await participantContext.newPage(); active = target;
    await installStimulusObserver(target);
    target.on('pageerror', error => errors.push(error.message));
    const traffic = [], requests = new Map();
    target.on('request', req => {try {if (req.url().includes('/api/events/') && req.method() === 'POST') {const body = req.postDataJSON(), bytes = req.postData();
      if (requests.has(body.operation_id)) assert.equal(requests.get(body.operation_id), bytes); requests.set(body.operation_id, bytes);
      traffic.push({operation_id: body.operation_id, first: body.events[0].sequence, last: body.events.at(-1).sequence, sha256: sha256(bytes)});}}
      catch (error) {failure ||= error; errors.push(error.message);}});
    await target.goto(journey.participant_url); assert.ok(target.url().includes('/api/runtime/'));
    await target.getByLabel('Participant alias (required)', {exact: true}).fill(alias); await target.locator('#consent').check();
    const admission = target.waitForResponse(r => r.url().includes('/api/start/') && r.request().method() === 'POST');
    await target.getByRole('button', {name: 'Start study', exact: true}).click(); const payload = await (await admission).json();
    assert.ok(payload.run_id); const compiled = payload.protocol.timeline.find(step => step.type === 'task').task;
    const plan = responsePlan(compiled, person); await write(alias + '-assigned.json', {payload, plan});
    if (payload.protocol.equipment?.required_codes?.length) {await target.getByRole('heading', {name: 'Check your task keys', exact: true}).waitFor();
      for (const code of payload.protocol.equipment.required_codes) await target.keyboard.press(code);}
    await target.getByRole('button', {name: 'Begin', exact: true}).click(); let count = 0, materialCaptured = false, feedbackCaptured = false;
    const capturePresentation = person === 0; // One administration supplies visual evidence; never interrupt the second for capture.
    for (const entry of compiled.timeline) {
      if (failure) throw failure;
      if (entry.type === 'task_instructions') {await target.getByRole('button', {name: entry.phase === 'test' ? 'Begin test phase' : 'Begin practice phase', exact: true}).click(); continue;}
      const expected = plan[count++];
      await currentStimulus(target, count, entry);
      // Begin observing before the actual Space. A withheld first trial may
      // spend its entire 100ms feedback during a material screenshot, so never
      // wait for that transient element after the screenshot has completed.
      const feedbackPending = capturePresentation && expected.respond && !feedbackCaptured ? target.waitForFunction(() => {
        const marker = document.querySelector('.gnat-feedback strong');
        return marker?.getClientRects().length ? marker.parentElement.textContent : false;
      }, undefined, {polling: 'raf', timeout: 1500}) : null;
      if (expected.respond) await target.keyboard.press('Space');
      if (capturePresentation && !expected.respond && !materialCaptured) {
        await target.locator('.gnat-material').waitFor({state: 'visible'});
        await target.screenshot({path: path.join(folder, alias + '-actual-material.png')}); materialCaptured = true;
      }
      if (feedbackPending) {
        // The screenshot uses the live, unmodified procedure clock. DOM capture
        // evidence is retained even if the 100ms feedback ends during encoding.
        const receipt = await feedbackPending, text = await receipt.jsonValue(); await receipt.dispose();
        await target.screenshot({path: path.join(folder, alias + '-actual-feedback.png')});
        await write(alias + '-feedback.json', {trial_id: entry.id, text, clock_unchanged: true}); feedbackCaptured = true;
      }
      if (count % 48 === 0) console.log(alias + ': ' + count + '/384 original trial onsets observed');
    }
    await target.getByRole('heading', {name: 'How much do you like the original Aster concept?', exact: true}).waitFor();
    const beforeFinish = await journal(target); assertJournal(compiled, beforeFinish[0].events, plan);
    const observed = await target.evaluate(() => window.__brohnGnatQaObservation.onsets);
    assert.equal(observed.length, 384); assert.deepEqual(observed.map(o => o.text), compiled.timeline.filter(t => t.type === 'task_trial').map(t => t.material.content));
    await target.getByRole('radio', {name: String(person + 4), exact: true}).check(); await target.getByRole('button', {name: 'Continue', exact: true}).click();
    await target.getByRole('heading', {name: 'Thank you. Your responses are saved.', exact: true}).waitFor();
    assert.deepEqual(await journal(target), []); journey.runs[alias] = payload.run_id; await save();
    await write(alias + '-browser.json', {run_id: payload.run_id, before_finish: beforeFinish, observed, traffic});
    await scan(alias + '-complete-390', true, target); await participantContext.close(); active = page;
    snap = await drain(); const session = snap.sessions.find(s => s.run.id === payload.run_id);
    assert.equal(session.run.completion_status, 'completed'); assert.equal(session.run.transfer_status, 'saved');
    assert.deepEqual(session.events.map(e => e.sequence), Array.from({length: session.events.length}, (_, i) => i + 1));
    assertJournal(compiled, session.events, plan);
    const native = snap.reports.find(r => r.body.provenance?.runs?.some(run => run.run_id === payload.run_id)); assert.ok(native);
    assert.equal(native.body.analysis.observations.length, 1); assert.equal(native.body.analysis.observations[0].value, person + 4);
    assert.equal(native.body.analysis.observations[0].session_id, payload.run_id);
    const numeric = python('import sys,json,statistics;v=json.load(sys.stdin);n=statistics.NormalDist();\nfor c in v:\n h=n.inv_cdf(c["hits"]/30); f=n.inv_cdf(c["false_alarms"]/30);c.update(d_prime=h-f,criterion=-(h+f)/2)\nprint(json.dumps(v))', [], JSON.stringify(expectedCells(person)));
    await write(alias + '-independent-oracle.json', numeric); assertScore(native.body.analysis.task_scores[0], person, numeric);
    journey.native_reports[alias] = native.id; await save();
    check(alias + ': all 384 trusted-key/withheld trials and explicit liking reach one real automatic report with independent count/d-prime/criterion expectations');
    } else {
      snap = await snapshot(); const retained = snap.sessions.find(s => s.run.id === journey.runs[alias]);
      assert.ok(retained && retained.run.completion_status === 'completed');
      const compiled = retained.run.protocol.timeline.find(step => step.type === 'task').task;
      assertJournal(compiled, retained.events, responsePlan(compiled, person));
      const original = JSON.parse(await fs.readFile(path.join(inherited.source, alias + '-native-report.json'), 'utf8'));
      assert.deepEqual(snap.reports.find(r => r.id === journey.native_reports[alias]).body, original);
      assertScore(original.analysis.task_scores[0], person, JSON.parse(await fs.readFile(path.join(inherited.source, alias + '-independent-oracle.json'), 'utf8')));
      check(alias + ': inherited complete original administration and saved numerical report remain exact; no new participant or scoring job');
    }
    const native = snap.reports.find(r => r.id === journey.native_reports[alias]);
    if (await reuseVerifiedNativeUi(alias, native)) continue;
    await openReport(native.id); await expect(page.locator('#brohn-main')).toContainText('Go/No-Go association results');
    assert.deepEqual(JSON.parse(await fs.readFile(await download('JSON + provenance', alias + '-native-report.json'), 'utf8')), native.body);
    await download('Download task scores CSV', alias + '-scores.csv'); await download('Download report', alias + '-report.html');
    await scan(alias + '-score-390', true);
    await scan(alias + '-gnat-results-390', true, page, '#brohn-main h3:text-is("Go/No-Go association results")');
    const full = await plotReport(alias, 384);
    check(alias + ': complete saved native plots and numerical exports retain 384 trials', full.selected_rows.length === 384);
  }

  for (const [person, alias] of aliases.entries()) {
    if (inherited && journey.imports[alias]) {
      const saved = snap.reports.find(r => r.id === journey.imports[alias].report_id);
      const bytes = await fs.readFile(path.join(inherited.source, alias + '-imported-report.json'));
      assert.deepEqual(saved.body, JSON.parse(bytes)); assert.equal(saved.body.dataset_id, journey.imports[alias].dataset_id);
      assert.ok(inherited.prior_checks.includes(alias + ': actual CSV/registry intake preserves all rows and exact arithmetic while explicitly retaining declared-summary evidence'));
      assert.ok(inherited.prior_scans.some(s => s.label === alias + '-imported-plot-390' && s.violations === 0 && !s.overflow));
      await fs.writeFile(path.join(folder, alias + '-imported-report.json'), bytes);
      await write(alias + '-inherited-import.json', {source: inherited.source, result_sha256: inherited.result_sha256,
        report_id: saved.id, report_sha256: sha256(bytes), dataset_id: saved.body.dataset_id,
        scope: 'Previously accepted real CSV/registry import and complete plot/export phase, exact saved result retained; no new import or analysis.'});
      check(alias + ': exact prior actual import/export/plot phase retained without duplicate dataset or scoring'); continue;
    }
    const runId = journey.runs[alias]; await openStudy(); await stage('Collect');
    const buttons = page.locator('[data-brohn-event="view_run_protocol"]');
    const index = await buttons.evaluateAll((nodes, id) => nodes.findIndex(node => JSON.parse(node.getAttribute('data-brohn-value')).run_id === id), runId); assert.ok(index >= 0); await buttons.nth(index).click();
    await page.getByRole('dialog', {name: 'Assigned participant protocol', exact: true}).waitFor(); await page.getByText('Export original task trials', {exact: true}).click();
    const binding = JSON.parse(await page.locator('#run_task_selection').inputValue()); assert.equal(binding.run_id, runId); assert.equal(binding.task_id, journey.task_id);
    const trials = await download('Download task trials CSV', alias + '-trials.csv');
    const registry = await download('Download task registry JSON', alias + '-registry.json');
    const notes = JSON.parse(await fs.readFile(await download('Download task export notes JSON', alias + '-notes.json'), 'utf8'));
    const rows = python('import csv,json,sys;print(json.dumps(list(csv.DictReader(open(sys.argv[1],encoding="utf-8-sig",newline="")))))', [trials]);
    assert.equal(rows.length, 384); assert.ok(rows.filter(row => ['miss', 'correct_rejection'].includes(row.outcome)).every(row => row.response_code === '' && row.response_ms === ''));
    snap = await snapshot();
    const nativeSession = snap.sessions.find(s => s.run.id === runId);
    const terminal = nativeSession.events.filter(e => e.type === 'task_event' && e.payload.kind === 'task_trial_finished').map(e => e.payload.data);
    const assigned = nativeSession.run.protocol.timeline.find(step => step.type === 'task').task.timeline.filter(t => t.type === 'task_trial');
    for (const [index, row] of rows.entries()) {
      const raw = terminal[index], trial = assigned[index]; assert.equal(row.trial_id, raw.trial_id);
      assert.equal(row.presentation_index, String(index + 1)); assert.equal(row.presented, 'true');
      assert.equal(row.participant_id, alias); assert.equal(row.session_id, runId);
      for (const field of ['phase', 'round_id', 'cell_id', 'expected_action']) assert.equal(row[field], trial[field] ?? '');
      for (const field of ['outcome', 'response_outcome', 'response_code']) assert.equal(row[field], raw[field] ?? '');
      assert.equal(row.correct, String(raw.correct));
      assert.equal(row.response_ms === '' ? null : Number(row.response_ms), raw.response_ms);
    }
    assert.equal(notes.declarations.source_rt_definition, 'space_ms_from_onset_no_rt_for_withholding');
    assert.equal(notes.declarations.terminal_response_rule, 'space_or_visible_deadline');
    await button('Close protocol').click();
    await stage('Data library'); await page.getByLabel('Dataset name', {exact: true}).fill(alias + ' native GNAT summaries');
    await selectValue('dataset_modality', 'implicit'); await selectValue('dataset_origin', 'sample'); const datasetId = await importSource(trials);
    await page.locator('#map_study-selectized').fill(title);
    await page.locator(`.selectize-dropdown:visible [data-value="${journey.study_id}"]`).click();
    await page.locator('#map_study_revision-selectized').waitFor();
    snap = await snapshot(); const session = snap.sessions.find(s => s.run.id === runId);
    await selectValue('map_study_revision', String(snap.releases.find(d => d.id === session.run.deployment_id).design_revision));
    await page.locator('#map_task_source_collection_id').fill(notes.source_collection_id);
    await page.locator('#map_task_origin_statement').fill('Original synthetic full browser journals exported as trial summaries. Two separate contexts and aliases represent two software administrations, not human research observations.');
    await page.locator('#task_registry_upload').setInputFiles(registry); await expect(page.locator('#task_mapping_registry .progress-bar')).toHaveText('Upload complete');
    await button('Use this protocol file').click(); await page.waitForFunction(() => document.getElementById('task_registry_identity')?.value === Shiny.shinyapp.$inputValues.task_registry_identity);
    await selectValue('map_task_source_rt_definition', notes.declarations.source_rt_definition); await selectValue('map_task_terminal_response_rule', notes.declarations.terminal_response_rule);
    await scan(alias + '-mapping-390', true); await button('Confirm mapping and analyse').click();
    await until(() => jobRows().some(j => j.operation === 'analyse_dataset' && j.request.dataset_id === datasetId)); snap = await drain();
    const imported = snap.reports.find(r => r.body.dataset_id === datasetId), native = snap.reports.find(r => r.id === journey.native_reports[alias]); assert.ok(imported);
    const attempt = imported.body.analysis.task_attempts[0]; assert.equal(attempt.evidence_level, 'declared_trial_summary'); assert.equal(attempt.timing_quality.journal_replayed, false);
    assert.equal(attempt.responses.length, 384); assert.equal(attempt.trial_audit.length, 384); assert.equal(attempt.participant_id, alias);
    assert.deepEqual(attempt.score.metrics, native.body.analysis.task_scores[0].metrics);
    assert.deepEqual(attempt.score.scoring_audit.cells, native.body.analysis.task_scores[0].scoring_audit.cells);
    journey.imports[alias] = {dataset_id: datasetId, report_id: imported.id}; await save();
    await openReport(imported.id); await download('JSON + provenance', alias + '-imported-report.json'); await plotReport(alias + '-imported', 384);
    check(alias + ': actual CSV/registry intake preserves all rows and exact arithmetic while explicitly retaining declared-summary evidence');
  }
  await openStudy(); await stage('Results'); await button('Review task participants').click();
  await page.getByRole('dialog', {name: 'Summarise task participants', exact: true}).waitFor(); await idle();
  const selectId = await page.getByLabel('Saved task reports', {exact: true}).getAttribute('id');
  await page.waitForFunction(id => {const el = document.getElementById(id.replace(/-selectized$/, '')); return el?.selectize && typeof el.selectize.settings.load === 'function' && Object.hasOwn(Shiny.shinyapp.$inputValues, el.id);}, selectId);
  for (const alias of aliases) {const id = journey.imports[alias].report_id; await page.locator(`[id="${selectId}"]`).fill(id);
    await expect(page.locator(`.selectize-dropdown:visible [data-value="${id}"].active`)).toBeVisible();
    await page.locator(`[id="${selectId}"]`).press('Enter');
    await page.waitForFunction(({selectId,id}) => document.getElementById(selectId.replace(/-selectized$/, ''))?.selectize?.getValue().includes(id), {selectId,id});}
  await button('Review administrations').click(); await page.getByRole('dialog', {name: 'Review task membership and people', exact: true}).waitFor();
  await page.getByLabel("I reviewed these person and visit links against the study's participant records", {exact: true}).check();
  await page.getByLabel('Identity evidence and notes (required when linking originally unlinked codes)', {exact: true}).fill('Two independently driven original browser contexts and distinct synthetic aliases. Each source appears once; no exported copy is treated as an extra person. Software QA only.');
  await page.getByLabel('Name this selection and repeat plan', {exact: true}).fill('Original two-person GNAT software comparison');
  await button('Save task participant report').click(); await until(() => jobRows().some(j => j.operation === 'analyse_task_cohort')); snap = await drain();
  const cohort = snap.reports.find(r => r.body.analysis.schema === 'brohn-task-cohort/1.0'); assert.ok(cohort); journey.cohort_id = cohort.id; await save();
  assert.equal(cohort.body.analysis.summaries.length, 10); assert.equal(cohort.body.analysis.per_person.length, 20);
  assert.equal(cohort.body.analysis.quality.selected_person_count, 2); assert.equal(cohort.body.analysis.quality.fully_linked, true);
  assert.deepEqual(cohort.body.analysis.contrasts, []); assert.equal(cohort.body.analysis.quality.inference_performed, false);
  for (const summary of cohort.body.analysis.summaries) {
    const values = aliases.map(alias => snap.reports.find(r => r.id === journey.native_reports[alias]).body.analysis.task_scores[0].metrics.find(m => m.name === summary.metric).value);
    assert.equal(summary.selected_person_count, 2); assert.equal(summary.contributing_person_count, 2);
    assert.equal(summary.selected_attempt_count, 2); assert.equal(summary.contributing_session_count, 2);
    assert.ok(Math.abs(summary.mean - (values[0] + values[1]) / 2) < 1e-12);
    assert.ok(Math.abs(summary.between_person_sd - Math.abs(values[0] - values[1]) / Math.sqrt(2)) < 1e-12);
    assert.deepEqual(cohort.body.analysis.per_person.filter(p => p.metric === summary.metric).map(p => p.value).sort((a,b) => a-b), values.toSorted((a,b) => a-b));
  }
  await openReport(cohort.id); await download('JSON + provenance', 'cohort-report.json');
  const people = await plotReport('cohort', 2); assert.equal(people.selected_rows.length, 2);
  for (const metric of ['GNAT_r1_target_positive_contrast', 'GNAT_r2_target_positive_contrast']) {
    await selectValue('task_plot_source', 'metric:' + metric); await button('Show complete saved source').click(); await idle();
    const plotted = JSON.parse(await fs.readFile(await download('Download all task values + provenance', metric + '-people.json'), 'utf8'));
    assert.equal(plotted.selection.measure, metric); assert.equal(plotted.selected_rows.length, 2);
    assert.deepEqual(plotted.selected_rows.map(p => p.value).sort((a,b) => a-b), cohort.body.analysis.per_person.filter(p => p.metric === metric).map(p => p.value).sort((a,b) => a-b));
  }
  check('Reviewed two-person selection produces complete person-value plots without counting native/import copies twice');
  } else {
    assert.ok(inherited, 'Restart-only qualification requires a verified stopped synthetic predecessor');
    assert.ok(inherited.prior_checks.includes('Reviewed two-person selection produces complete person-value plots without counting native/import copies twice'));
    assert.equal(snap.sessions.length, 2); assert.equal(snap.reports.length, 5); assert.equal(snap.jobs.length, 7);
    assert.ok(snap.jobs.every(j => j.status === 'succeeded' && j.attempt === 1));
    assert.ok(snap.reports.some(r => r.id === journey.cohort_id));
    for (const alias of aliases) {
      const bytes = await fs.readFile(path.join(inherited.source, alias + '-native-report.json'));
      assert.deepEqual(JSON.parse(bytes), snap.reports.find(r => r.id === journey.native_reports[alias]).body);
      await fs.writeFile(path.join(folder, alias + '-native-report.json'), bytes);
    }
    check('Restart-only phase retains the accepted two complete administrations, two imports and reviewed cohort without new work');
  }
  snap = await snapshot(); await write('before-restart.json', snap);
  await context.close(); await stop(); await start();
  context = await browser.newContext({viewport: {width: 1440, height: 1080}}); page = await context.newPage(); active = page;
  page.on('pageerror', error => errors.push(error.message)); await page.goto(home); await openReport(journey.native_reports[aliases[0]]);
  const reopened = await fs.readFile(await download('JSON + provenance', 'reopened-native-report.json'));
  assert.equal(sha256(reopened), sha256(await fs.readFile(path.join(folder, aliases[0] + '-native-report.json'))));
  await openStudy(); await stage('Plan'); await expect(page.locator('input[name="study_measures"][value="gnat"]')).toBeChecked();
  const final = await snapshot(); for (const key of ['sessions', 'reports', 'runtime_assignments', 'jobs']) assert.deepEqual(final[key], snap[key]);
  assert.equal(final.sessions.length, 2); assert.equal(final.jobs.filter(j => j.operation === 'analyse_run').length, 2);
  assert.ok(final.report_integrity.every(row => row.exact)); assert.deepEqual(errors, []); await write('final-snapshot.json', final);
  if (inherited) {
    const original = JSON.parse(await fs.readFile(path.join(folder, 'inherited-store-baseline.json'), 'utf8'));
    for (const key of ['sessions', 'reports', 'jobs']) for (const row of original[key]) {
      const id = key === 'sessions' ? row.run.id : row.id;
      assert.deepEqual(final[key].find(x => (key === 'sessions' ? x.run.id : x.id) === id), row);
    }
    await write('inherited-versus-new.json', {inherited_jobs: original.jobs.map(j => ({id: j.id, operation: j.operation, result: j.result})),
      new_jobs: final.jobs.filter(j => !original.jobs.some(o => o.id === j.id)).map(j => ({id: j.id, operation: j.operation, status: j.status, attempt: j.attempt})),
      inherited_objects: original.report_integrity, final_objects: final.report_integrity});
    check('Inherited job identities, original report objects and completed sessions remain exact while only remaining work produces new jobs');
  }
  check('Full restart reopens identical reports with unchanged native journals, runtime bindings and job count');
  await context.close(); await stop();
} catch (error) {
  failure ||= error; await active?.screenshot({path: path.join(folder, 'failure.png'), fullPage: true}).catch(() => {});
  if (active?.url().startsWith(`http://127.0.0.1:${ports?.participant}/`)) await write('failure-journal.json', await journal(active).catch(() => []));
  await write('failure.json', {error: failure.stack, checks, scans, journey, errors, text: await active?.locator('body').innerText().catch(() => '(closed)')});
} finally {
  clearTimeout(deadline); try {await browser?.close();} catch (error) {failure ||= error;}
  try {await stop();} catch (error) {failure ||= error;}
  try {const end = await hashes(); await write('source-end.json', end); assert.deepEqual(end, startHashes);
    assert.equal(sha256(await fs.readFile(request.configuration_path)), configurationStart); check('Selected source and supplied configuration byte hashes remain unchanged');
    if (inherited) {assert.deepEqual(await treeHashes(inherited.original_workspace), inherited.original_hashes); check('Original stopped source workspace retains every byte after copy-based recovery');}
  } catch (error) {failure ||= error;}
  await write('results.json', {schema: 'brohn-researcher-gnat-result/1.0', status: failure ? 'failed' : 'passed', started, finished: new Date().toISOString(),
    checks, scans, errors, cycles, journey, failure: failure?.stack || null,
    limits: ['Original synthetic automated keyboards and loopback services; no human, construct-validity or physical timing evidence.',
      'Named Brohn adaptation; no original/vendor GNAT equivalence.', 'Existing configured Windows runtimes; no clean-OS, device or hosted TLS/OIDC qualification.']});
}
if (failure) {console.error(failure.stack); process.exitCode = 1;}
console.log(JSON.stringify({status: failure ? 'failed' : 'passed', checks: checks.length, scans: scans.length, folder}));
