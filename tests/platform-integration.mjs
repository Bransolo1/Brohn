// Actual Chrome -> loopback R/httpuv -> SQLite participant journey.
// All studies/answers are original synthetic QA data; no mocked API routes.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import net from 'node:net';
import { spawn, spawnSync } from 'node:child_process';
import { setTimeout as delay } from 'node:timers/promises';
import { chromium } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const root = path.resolve(import.meta.dirname, '..');
const work = path.resolve(root, '../../work');
const rscript = process.env.BROHN_RSCRIPT || path.join(work, 'native-r/bin/Rscript.exe');
const env = {...process.env, R_LIBS_USER: path.join(work, 'r-library-brohn'), R_USER: work, LC_ALL: 'C', LANG: 'C'};
const temporary = await fs.mkdtemp(path.join(os.tmpdir(), 'brohn-browser-integration-'));
const workspace = path.join(temporary, 'workspace');
const configPath = path.join(temporary, 'fixture.json');
const inspectPath = path.join(temporary, 'inspection.json');
const resultDirectory = path.join(root, 'test-results/platform-integration');
await fs.mkdir(resultDirectory, {recursive: true});
let server, browser, serverOutput = '', failure;
let assertions = 0;
const checks = [], pageErrors = [], apiFailures = [], mediaResponses = [];
const check = (name, condition) => {assert.ok(condition, name); assertions++; checks.push(name);};
function runR(action, output) {
  const result = spawnSync(rscript, ['--vanilla', 'tests/fixtures/platform-integration.R', action, workspace, output],
    {cwd: root, env, windowsHide: true, encoding: 'utf8', timeout: 30000});
  assert.equal(result.status, 0, `R ${action} fixture failed: ${result.stderr || result.error || result.stdout}`);
}
async function availablePort() {
  for (let port = 3855; port < 3870; port++) {
    const free = await new Promise(resolve => {
      const probe = net.createServer();
      probe.once('error', () => resolve(false));
      probe.listen(port, '127.0.0.1', () => probe.close(() => resolve(true)));
    });
    if (free) return port;
  }
  throw new Error('No unused QA port from 3855 to 3869.');
}
async function poll(fn, description, timeout = 12000) {
  const until = Date.now() + timeout;
  let latest;
  while (Date.now() < until) {
    try {const value = await fn(); if (value) return value;} catch (error) {latest = error;}
    await delay(60);
  }
  throw new Error(`Timed out: ${description}${latest ? ` (${latest.message})` : ''}`);
}
async function inspect() {runR('inspect', inspectPath); return JSON.parse(await fs.readFile(inspectPath, 'utf8'));}
async function heading(page, text) {await page.getByRole('heading', {name: text, exact: true}).waitFor({timeout: 12000});}
async function next(page) {await page.getByRole('button', {name: 'Continue', exact: true}).click();}
async function newPage(viewport = {width: 1280, height: 900}) {
  const context = await browser.newContext({viewport});
  const page = await context.newPage();
  page.on('dialog', dialog => dialog.accept());
  page.on('pageerror', error => pageErrors.push(error.message));
  page.on('response', response => {
    if (response.url().includes('/api/assets/')) mediaResponses.push(response.status());
    if (response.url().includes('/api/') && response.status() >= 400)
      apiFailures.push({path: new URL(response.url()).pathname.split('/').slice(0, 3).join('/'), status: response.status()});
  });
  return {page, context};
}
async function checkAxe(page, label) {
  const result = await new AxeBuilder({page}).withTags(['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa']).analyze();
  await fs.writeFile(path.join(resultDirectory, `${label}-axe.json`), JSON.stringify({violations: result.violations}, null, 2));
  check(`${label}: automated accessibility has no WCAG A/AA violations`, result.violations.length === 0);
}

try {
  runR('prepare', configPath);
  const fixture = JSON.parse(await fs.readFile(configPath, 'utf8'));
  const port = await availablePort();
  const base = `http://127.0.0.1:${port}`;
  server = spawn(rscript, ['--vanilla', 'scripts/run-participant.R', '--root', workspace, '--port', String(port)],
    {cwd: root, env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe']});
  for (const stream of [server.stdout, server.stderr]) stream.on('data', chunk => {serverOutput = (serverOutput + chunk.toString()).slice(-12000);});
  await poll(async () => (await fetch(`${base}/participant/`)).ok, 'real R participant server', 20000);
  browser = await chromium.launch({channel: 'chrome', headless: true});
  const url = deployment => `${base}/participant/?token=${deployment.token}`;

  // Complete two real sessions: one includes the false-driven branch and reloads
  // an untimed answer; one skips that branch and receives the opposite order.
  for (const iteration of [1, 2]) {
    const {page, context} = await newPage();
    await page.goto(url(fixture.main));
    await heading(page, 'Taking part in this study');
    check('sample origin visible before participation', (await page.locator('#study-origin').innerText()).includes('pilot'));
    if (iteration === 1) {
      await page.getByRole('button', {name: 'Start study', exact: true}).click();
      check('required consent prevents start and explains action', (await page.locator('#error').innerText()).includes('confirm your agreement'));
      check('no participant created before consent', (await inspect()).runs.length === 0);
      await checkAxe(page, 'consent-desktop');
    }
    await page.getByLabel('I have read the study information and agree to take part.').check();
    if (iteration === 1) await page.getByLabel('Participant alias (optional)', {exact: true}).fill('SYNTHETIC-MAIN-1');
    await page.getByRole('button', {name: 'Start study', exact: true}).click();
    await heading(page, 'Before you begin');
    await page.getByRole('button', {name: 'Begin', exact: true}).click();
    await heading(page, 'Question q-single');
    await page.getByRole('radio', {name: iteration === 1 ? 'No' : 'Yes', exact: true}).check();
    await next(page);
    await heading(page, 'Question q-information'); await next(page);
    if (iteration === 1) {
      await heading(page, 'Question q-text');
      await page.getByLabel('Your answer', {exact: true}).fill('The package is unfamiliar.');
      await next(page);
    }
    await heading(page, 'Question q-number');
    await page.getByLabel('Your answer', {exact: true}).fill('0'); await next(page);
    await heading(page, 'Question q-multiple');
    await page.getByRole('checkbox', {name: 'Not at all', exact: true}).check();
    await page.getByRole('checkbox', {name: '3', exact: true}).check(); await next(page);
    await heading(page, 'Question q-dropdown');
    await page.getByLabel('Choose an answer', {exact: true}).selectOption('option-2'); await next(page);
    await heading(page, 'Question q-slider');
    if (iteration === 1) {
      await next(page);
      check('untouched slider is not fabricated as a response', (await page.locator('#error').innerText()).includes('answer this question'));
    }
    await page.getByRole('button', {name: 'Confirm slider value', exact: true}).click(); await next(page);
    // Wait through actual browser-presented baseline, fixation and stimuli.
    await heading(page, 'Question q-rating');
    await page.getByRole('radio', {name: 'Not at all', exact: true}).check(); await next(page);
    await heading(page, 'Question q-rating');
    await page.getByRole('radio', {name: 'Very much', exact: true}).check(); await next(page);
    await heading(page, 'Question q-long');
    await page.getByLabel('Your answer', {exact: true}).fill('Original synthetic long answer');
    if (iteration === 1) {
      await poll(() => page.evaluate(() => new Promise(resolve => {
        const request = indexedDB.open('brohn-participant', 1);
        request.onsuccess = () => {const db = request.result; const get = db.transaction('sessions').objectStore('sessions').getAll();
          get.onsuccess = () => {resolve(get.result.some(record => Object.values(record.drafts).includes('Original synthetic long answer'))); db.close();};};
      })), 'untimed draft persisted in actual IndexedDB');
      await page.reload();
      await heading(page, 'An unfinished session is saved');
      await page.getByRole('button', {name: 'Resume this participant session', exact: true}).click();
      await heading(page, 'Question q-long');
      check('untimed reload restores original answer draft', await page.getByLabel('Your answer', {exact: true}).inputValue() === 'Original synthetic long answer');
    }
    await next(page);
    await heading(page, 'Question q-matrix');
    await page.getByRole('group', {name: 'Clarity', exact: true}).getByRole('radio', {name: '2', exact: true}).check();
    await page.getByRole('group', {name: 'Appeal', exact: true}).getByRole('radio', {name: '3', exact: true}).check();
    if (iteration === 1) {await checkAxe(page, 'matrix-desktop'); await page.screenshot({path: path.join(resultDirectory, 'matrix-desktop.png'), fullPage: true});}
    await next(page);
    await heading(page, 'Question q-ranking');
    await page.getByRole('button', {name: 'Move up: 3', exact: true}).click();
    await page.getByRole('button', {name: 'Confirm this order', exact: true}).click(); await next(page);
    await heading(page, 'Question q-allocation');
    await page.locator('#allocation-option-1').fill('0');
    await page.locator('#allocation-option-2').fill('100'); await next(page);
    await heading(page, 'Thank you. Your responses are saved.');
    check(`session ${iteration}: final receipt visible`, (await page.locator('#save-status').innerText()).includes('Final receipt confirmed'));
    check(`session ${iteration}: no permanent delivery error`, await page.locator('#error').isHidden());
    await context.close();
  }
  const mainRuns = (await inspect()).runs.filter(run => run.study_id === 'browser-main').sort((a, b) => a.allocation_index - b.allocation_index);
  check('two browser completions persist as two completed pilot runs', mainRuns.length === 2 && mainRuns.every(run => run.outcome === 'completed' && run.origin === 'pilot'));
  check('frozen protocol identity survived browser delivery', mainRuns.every(run => run.design_hash === fixture.main_design_hash));
  check('actual allocation indices determine AB then BA', JSON.stringify(mainRuns[0].order) === JSON.stringify(['stimulus-a', 'stimulus-b']) && JSON.stringify(mainRuns[1].order) === JSON.stringify(['stimulus-b', 'stimulus-a']));
  check('explicit optional alias and generated fallback preserved', mainRuns[0].alias === 'SYNTHETIC-MAIN-1' && mainRuns[1].alias === 'Participant 2');
  const responses = run => run.events.filter(event => event.type === 'response');
  check('all 12 question types traversed without converting information to a scored response', fixture.question_types.length === 12 && new Set(fixture.question_types).size === 12 && responses(mainRuns[0]).length === 12);
  check('boolean false and numeric zero stay typed in R journal', responses(mainRuns[0]).find(e => e.question_id === 'q-single').payload.value === false && responses(mainRuns[0]).find(e => e.question_id === 'q-number').payload.value === 0);
  check('string choice code false remains distinct from boolean false', responses(mainRuns[0]).find(e => e.question_id === 'q-dropdown').payload.value === 'false');
  check('conditional branch skips only its own answer on second run', !responses(mainRuns[1]).some(e => e.question_id === 'q-text') && mainRuns[1].events.some(e => e.question_id === 'q-text' && e.payload.skipped === true));
  const rated = responses(mainRuns[1]).filter(e => e.question_id === 'q-rating');
  check('ratings bind to actual BA presentations', rated[0].stimulus_id === 'stimulus-b' && rated[0].payload.value === 1 && rated[1].stimulus_id === 'stimulus-a' && rated[1].payload.value === 7);
  check('resumed question does not claim uninterrupted response time', responses(mainRuns[0]).find(e => e.question_id === 'q-long').payload.response_time_ms === null && responses(mainRuns[0]).find(e => e.question_id === 'q-long').payload.resumed === true);
  check('event sequences acknowledged once and contiguous', mainRuns.every(run => run.acked === run.events.length && run.events.every((event, i) => event.sequence === i + 1)));
  check('real media endpoint loaded successfully', mediaResponses.length >= 2 && mediaResponses.every(status => status === 200));

  // Required alias is an actual field; optional consent remains optional.
  const aliasContext = await newPage({width: 390, height: 844});
  await aliasContext.page.goto(url(fixture.alias));
  await heading(aliasContext.page, 'Taking part in this study');
  await aliasContext.page.getByRole('button', {name: 'Start study', exact: true}).click();
  check('required alias gives actionable input and focus', (await aliasContext.page.locator('#error').innerText()).includes('participant alias') && await aliasContext.page.locator('#participant-alias').evaluate(el => el === document.activeElement));
  await checkAxe(aliasContext.page, 'consent-narrow');
  check('narrow consent fits viewport without horizontal overflow', await aliasContext.page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  await aliasContext.page.getByLabel('Participant alias (required)', {exact: true}).fill('SYNTHETIC-ALIAS');
  await aliasContext.page.getByRole('button', {name: 'Start study', exact: true}).click();
  await heading(aliasContext.page, 'Before you begin');
  await aliasContext.page.getByRole('button', {name: 'Begin', exact: true}).click();
  await heading(aliasContext.page, 'Question q-alias-answer');
  await aliasContext.page.getByLabel('Your answer', {exact: true}).fill('Optional consent choice exercised.'); await next(aliasContext.page);
  await heading(aliasContext.page, 'Thank you. Your responses are saved.');
  const aliasRun = (await inspect()).runs.find(run => run.study_id === 'browser-alias');
  check('required alias persists and unchecked optional consent permits actual completion', aliasRun?.alias === 'SYNTHETIC-ALIAS' && aliasRun.outcome === 'completed');
  await aliasContext.context.close();

  // A reload during a timed presentation seals a partial run, never replaying it.
  const timedContext = await newPage();
  await timedContext.page.goto(url(fixture.timed));
  await heading(timedContext.page, 'Taking part in this study');
  await timedContext.page.getByLabel('I have read the study information and agree to take part.').check();
  await timedContext.page.getByRole('button', {name: 'Start study', exact: true}).click();
  await heading(timedContext.page, 'Before you begin');
  await timedContext.page.getByRole('button', {name: 'Begin', exact: true}).click();
  await timedContext.page.locator('body.timed .text-stimulus').waitFor();
  await timedContext.page.reload();
  await heading(timedContext.page, 'The study was interrupted.');
  const interruptedRun = (await inspect()).runs.find(run => run.study_id === 'browser-timed');
  check('timed reload persists interrupted outcome instead of completion', interruptedRun?.outcome === 'interrupted');
  check('interrupted timed presentation not silently replayed', interruptedRun.events.filter(e => e.type === 'step_started' && e.phase === 'passive_viewing').length === 1 && !interruptedRun.events.some(e => e.type === 'step_finished' && e.phase === 'passive_viewing'));
  await timedContext.context.close();

  const closedContext = await newPage();
  await closedContext.page.goto(url(fixture.closed));
  await heading(closedContext.page, 'Taking part in this study');
  await closedContext.page.getByRole('button', {name: 'Start study', exact: true}).click();
  await poll(async () => (await closedContext.page.locator('#error').innerText()).includes('not accepting'), 'actual structured server error');
  check('structured R error renders readable message instead of object placeholder', !(await closedContext.page.locator('#error').innerText()).includes('[object Object]'));
  await closedContext.context.close();
  check('no browser JavaScript exceptions during complete lifecycle', pageErrors.length === 0);
  check('only deliberate closed-release API failure occurred', apiFailures.length === 1 && apiFailures[0].status === 409 && apiFailures[0].path === '/api/start');
  const protectedResponse = await fetch(`${base}/api/events/${mainRuns[0].id}`, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: '{}'});
  check('participant data mutation endpoint rejects missing run credential', protectedResponse.status === 401);

  await fs.writeFile(path.join(resultDirectory, 'results.json'), JSON.stringify({status: 'passed', evidence: 'automated_browser_with_real_R_service', original_synthetic: true,
    browser: await browser.version(), assertions, checks, measured_humans: 0, live_devices: 0, api_failures: apiFailures,
    boundaries: ['local loopback only', 'no physical timing qualification', 'no human usability observations', 'researcher app not exercised by this participant harness']}, null, 2));
  console.log(`PASS: ${assertions} real participant browser/service assertions (12 question types, two allocations, reload, alias, 3 axe scans; synthetic only)`);
} catch (error) {
  failure = error;
  await fs.writeFile(path.join(resultDirectory, 'failure.json'), JSON.stringify({status: 'failed', error: error.stack, assertions, checks, pageErrors, apiFailures, serverOutput}, null, 2));
  if (browser) for (const [i, context] of browser.contexts().entries()) for (const [j, page] of context.pages().entries())
    await page.screenshot({path: path.join(resultDirectory, `failure-${i}-${j}.png`), fullPage: true}).catch(() => {});
  console.error(error.stack);
} finally {
  if (browser) await browser.close().catch(() => {});
  if (server && server.exitCode === null) {
    // On Windows the portable Rscript wrapper launches an x64 Rscript child.
    // End only this spawned process tree before touching its SQLite workspace.
    if (process.platform === 'win32') spawnSync('taskkill', ['/PID', String(server.pid), '/T', '/F'], {windowsHide: true, stdio: 'ignore', timeout: 10000});
    else server.kill();
    await new Promise(resolve => {
      if (server.exitCode !== null) {resolve(); return;}
      const timeout = setTimeout(resolve, 4000);
      server.once('exit', () => {clearTimeout(timeout); resolve();});
    });
    server.stdout?.destroy(); server.stderr?.destroy();
  }
  // Verify the exact generated temporary root before recursive cleanup on Windows.
  const resolved = path.resolve(temporary);
  assert.ok(resolved.startsWith(path.resolve(os.tmpdir()) + path.sep) && path.basename(resolved).startsWith('brohn-browser-integration-'));
  await fs.rm(resolved, {recursive: true, force: true, maxRetries: 3, retryDelay: 100});
}
if (failure) process.exitCode = 1;
