import assert from "node:assert/strict";
import http from "node:http";
import fs from "node:fs/promises";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {chromium} from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const appearance = {background: "#FFFFFF", foreground: "#111111"};
const options = [{id: "no", label: "No", value: false}, {id: "yes", label: "Yes", value: true}];
const question = (id, type, extra = {}) => ({id, type, prompt: `Question ${id}`, required: true,
  scope: "before", options, rows: [], min: 0, max: 100, step: 1, show_if: null, randomize_options: false, ...extra});
const makeTimeline = (mode) => {
  if (mode === "scoped") return [
    {type: "instructions", phase: "instructions", text: "Compare both concepts."},
    ...["a", "b"].flatMap(letter => [
      {type: "stimulus", phase: "passive_viewing", stimulus_id: `stimulus-${letter}`, condition_id: letter, duration_ms: 100,
        stimulus: {id: `stimulus-${letter}`, type: "text", content: `Concept ${letter}`}},
      {type: "question", phase: "active_response", stimulus_id: `stimulus-${letter}`, condition_id: letter,
        question: question("same", "single_choice", {scope: "after_each"})},
      {type: "question", phase: "active_response", stimulus_id: `stimulus-${letter}`, condition_id: letter,
        question: question("followup", "text", {scope: "after_each", show_if: {op: "equals", question_id: "same", value: false}})}
    ])
  ].map((step, index) => ({...step, id: `step-${index + 1}`}));
  const questions = mode === "all" ? [
    question("single", "single_choice"), question("multi", "multiple_choice"),
    question("dropdown", "dropdown"), question("text", "text"), question("long", "long_text"),
    question("number", "number"), question("slider", "slider"),
    question("matrix", "matrix", {rows: [{id: "row-a", label: "First row"}, {id: "row-b", label: "Second row"}]}),
    question("rank", "ranking"), question("allocation", "allocation"), question("information", "information"),
    question("rating", "rating"),
    question("hidden", "text", {show_if: {op: "equals", question_id: "single", value: true}})
  ] : [question("text", "text"), question("number", "number")];
  const steps = [{type: "instructions", phase: "instructions", text: "Read this instruction."},
    ...(mode === "all" || mode === "interrupt" ? [{type: "stimulus", phase: "passive_viewing", stimulus_id: "stimulus-a", condition_id: "control", duration_ms: mode === "interrupt" ? 5000 : 100,
      stimulus: {id: "stimulus-a", type: "text", content: "A neutral concept"}}] : []),
    ...questions.map(q => ({type: "question", phase: "active_response", question: q, stimulus_id: null, condition_id: null}))];
  return steps.map((step, index) => ({...step, id: `step-${index + 1}`}));
};
const runs = new Map(), tokens = new Map();
const tokenFor = mode => { const token = `${mode}-${"x".repeat(24)}`; tokens.set(token, {mode, starts: new Map(), origin: "pilot"}); return token; };
const json = (response, status, data) => { response.writeHead(status, {"Content-Type": "application/json", "Cache-Control": "no-store"}); response.end(JSON.stringify(data)); };
const body = async request => { let text = ""; for await (const chunk of request) text += chunk; return JSON.parse(text); };
const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url, "http://localhost"), parts = url.pathname.split("/").filter(Boolean);
    if (parts[0] === "api") {
      const [, operation, key] = parts;
      if (operation === "entry") return json(response, 200, {deployment: {id: key, title: "Participant QA study", origin: "pilot", status: "open"},
        consent: {title: "Study consent", text: "You can stop at any time.", required: true}, appearance, supported: true});
      if (operation === "start") {
        const input = await body(request), config = tokens.get(key);
        if (config.starts.has(input.operation_id)) return json(response, 200, config.starts.get(input.operation_id));
        const id = `run-${runs.size + 1}`, protocol = {design_hash: "f".repeat(64), design: {title: "Participant QA", appearance, debrief: "Thank you for the study."}, timeline: makeTimeline(config.mode)};
        const result = {run_id: id, access_token: `secret-${id}`, protocol, expected_sequence: 1};
        config.starts.set(input.operation_id, result);
        runs.set(id, {token: key, events: [], operations: new Map(), finishes: [], dropReceipt: config.mode === "retry", block: false});
        return json(response, 200, result);
      }
      const run = runs.get(key);
      if (request.headers.authorization !== `Bearer secret-${key}`) return json(response, 401, {error: "Invalid access."});
      const input = await body(request);
      if (operation === "events") {
        if (run.block) return json(response, 503, {error: "Temporary test outage."});
        if (run.operations.has(input.operation_id)) {
          assert.deepEqual(input.events, run.operations.get(input.operation_id));
        } else {
          for (const event of input.events) {
            assert.equal(event.sequence, run.events.length + 1);
            assert.match(event.clock.value, /^\d+\.\d+$/); assert.ok(event.clock.instance_id);
            run.events.push(event);
          }
          run.operations.set(input.operation_id, input.events);
        }
        if (run.dropReceipt) { run.dropReceipt = false; return json(response, 503, {error: "Receipt lost after persistence."}); }
        return json(response, 200, {acked_sequence: run.events.length});
      }
      if (operation === "finish") {
        assert.equal(input.final_sequence, run.events.length);
        run.finishes.push(input); return json(response, 200, {status: "saved", outcome: input.outcome});
      }
    }
    const relative = url.pathname === "/participant/" ? "participant/index.html" : url.pathname.slice(1);
    const filename = path.resolve(root, "www", relative);
    if (!filename.startsWith(path.join(root, "www") + path.sep)) return json(response, 404, {});
    const data = await fs.readFile(filename);
    response.writeHead(200, {"Content-Type": filename.endsWith(".html") ? "text/html" : filename.endsWith(".css") ? "text/css" : filename.endsWith(".js") ? "application/javascript" : "image/svg+xml"}); response.end(data);
  } catch (error) { console.error(error); json(response, 500, {error: error.message}); }
});
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({executablePath: "C:/Program Files/Google/Chrome/Application/chrome.exe", headless: true});
const checks = [];
const check = (name, fn) => { fn(); checks.push(name); };
const newPage = async mode => {
  const context = await browser.newContext(), page = await context.newPage();
  page.on("dialog", dialog => dialog.accept());
  const errors = []; page.on("pageerror", error => errors.push(error.message));
  await page.goto(`${origin}/participant/?token=${tokenFor(mode)}`);
  await page.getByRole("heading", {name: "Study consent"}).waitFor();
  return {context, page, errors};
};
const start = async page => {
  await page.getByLabel("I have read the study information and agree to take part.").check();
  await page.getByRole("button", {name: "Start study", exact: true}).click();
  await page.getByRole("button", {name: "Begin", exact: true}).click();
};
const continueButton = page => page.getByRole("button", {name: "Continue", exact: true}).click();
try {
  const all = await newPage("all");
  await all.page.getByRole("button", {name: "Start study", exact: true}).click();
  await all.page.getByRole("alert").filter({hasText: "Please confirm"}).waitFor();
  check("Consent gates session allocation", () => assert.equal(runs.size, 0));
  const consentAxe = await new AxeBuilder({page: all.page}).withTags(["wcag2a", "wcag2aa", "wcag21aa"]).analyze();
  check("Consent screen automated accessibility", () => assert.deepEqual(consentAxe.violations, []));
  await all.page.setViewportSize({width: 390, height: 844});
  const narrowAxe = await new AxeBuilder({page: all.page}).withTags(["wcag2a", "wcag2aa", "wcag21aa"]).analyze();
  const narrowOverflow = await all.page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
  check("Narrow participant screen reflows and passes automated accessibility", () => { assert.deepEqual(narrowAxe.violations, []); assert.equal(narrowOverflow, false); });
  await all.page.setViewportSize({width: 1280, height: 800});
  const duplicate = await all.context.newPage(); await duplicate.goto(all.page.url());
  await duplicate.getByRole("alert").filter({hasText: "already open in another tab"}).waitFor();
  check("Concurrent tab cannot open a second active journal", () => assert.equal(runs.size, 0));
  await duplicate.close(); await all.page.bringToFront();
  await start(all.page);
  await all.page.getByRole("heading", {name: "Question single", exact: true}).waitFor();
  const ruleChecks = await all.page.evaluate(() => {
    const r = window.BrohnParticipantRules;
    return [r.matches({op: "equals", question_id: "x", value: false}, {x: false}),
      r.matches({op: "answered", question_id: "x"}, {x: 0}),
      !r.matches({op: "not_equals", question_id: "x", value: true}, {}),
      r.matches({op: "and", rules: [{op: "greater", question_id: "x", value: 1}, {op: "not", rule: {op: "equals", question_id: "y", value: true}}]}, {x: 2, y: false})];
  });
  check("Conditional rules preserve zero, false, missing and nested logic", () => assert.ok(ruleChecks.every(Boolean)));
  await continueButton(all.page);
  await all.page.getByRole("alert").filter({hasText: "Please answer"}).waitFor();
  await all.page.getByLabel("No", {exact: true}).check(); await continueButton(all.page);
  await all.page.getByRole("heading", {name: "Question multi", exact: true}).waitFor();
  await all.page.getByLabel("Yes", {exact: true}).check(); await continueButton(all.page);
  await all.page.getByLabel("Choose an answer").selectOption("no"); await continueButton(all.page);
  await all.page.getByRole("heading", {name: "Question text", exact: true}).waitFor();
  await all.page.getByLabel("Your answer").fill("<script>not markup</script>"); await continueButton(all.page);
  await all.page.getByRole("heading", {name: "Question long", exact: true}).waitFor();
  await all.page.getByLabel("Your answer").fill("A considered explanation."); await continueButton(all.page);
  await all.page.getByRole("heading", {name: "Question number", exact: true}).waitFor();
  await all.page.getByLabel("Your answer").fill("0"); await continueButton(all.page);
  await all.page.getByRole("button", {name: "Confirm slider value"}).click(); await continueButton(all.page);
  await all.page.getByRole("group", {name: "First row"}).getByLabel("No", {exact: true}).check();
  await all.page.getByRole("group", {name: "Second row"}).getByLabel("Yes", {exact: true}).check();
  const matrixAxe = await new AxeBuilder({page: all.page}).withTags(["wcag2a", "wcag2aa", "wcag21aa"]).analyze();
  check("Matrix screen automated accessibility", () => assert.deepEqual(matrixAxe.violations, []));
  await continueButton(all.page);
  await all.page.getByRole("button", {name: "Move up: Yes", exact: true}).click();
  await all.page.getByRole("button", {name: "Confirm this order"}).click(); await continueButton(all.page);
  await all.page.getByLabel("No", {exact: true}).fill("0"); await all.page.getByLabel("Yes", {exact: true}).fill("99"); await continueButton(all.page);
  await all.page.getByRole("alert").filter({hasText: "Allocate exactly"}).waitFor();
  await all.page.getByLabel("Yes", {exact: true}).fill("100"); await continueButton(all.page);
  await continueButton(all.page);
  await all.page.getByLabel("No", {exact: true}).check(); await continueButton(all.page);
  await all.page.getByRole("heading", {name: "Thank you. Your responses are saved."}).waitFor();
  const allRun = [...runs.values()].find(run => run.token.startsWith("all-"));
  const responses = Object.fromEntries(allRun.events.filter(event => event.type === "response").map(event => [event.question_id, event.payload.value]));
  check("Twelve question types complete with typed values and safe text", () => assert.deepEqual(responses, {
    single: false, multi: [true], dropdown: false, text: "<script>not markup</script>", long: "A considered explanation.",
    number: 0, slider: 0, matrix: {"row-a": false, "row-b": true}, rank: ["yes", "no"], allocation: {no: 0, yes: 100}, rating: false}));
  check("Hidden question creates an explicit skipped step without a response", () => assert.equal(allRun.events.filter(event => event.payload.skipped && event.question_id === "hidden").length, 1));
  check("Timed exposure records browser duration, frame and clock evidence", () => {
    const exposure = allRun.events.find(event => event.type === "step_finished" && event.phase === "passive_viewing");
    assert.ok(exposure.payload.observed_duration_ms >= 100); assert.ok(exposure.payload.frames > 0);
  });
  check("Successful completion clears private session state", () => assert.equal(allRun.finishes[0].outcome, "completed"));
  assert.equal(await all.page.evaluate(() => new Promise(resolve => { const open = indexedDB.open("brohn-participant", 1); open.onsuccess = () => { const req = open.result.transaction("sessions").objectStore("sessions").count(); req.onsuccess = () => resolve(req.result); }; })), 0);
  await all.context.close();

  const resumed = await newPage("resume"); await start(resumed.page);
  await resumed.page.getByLabel("Your answer").fill("A retained draft");
  await resumed.page.waitForTimeout(100);
  await resumed.page.reload(); await resumed.page.getByRole("button", {name: "Resume this participant session"}).click();
  check("Untimed reload restores the answer draft", () => {});
  assert.equal(await resumed.page.getByLabel("Your answer").inputValue(), "A retained draft");
  await continueButton(resumed.page); await resumed.page.getByRole("heading", {name: "Question number", exact: true}).waitFor();
  await resumed.page.getByLabel("Your answer").fill("5"); await continueButton(resumed.page);
  await resumed.page.getByRole("heading", {name: "Thank you. Your responses are saved."}).waitFor();
  const resumedRun = [...runs.values()].find(run => run.token.startsWith("resume-"));
  check("Resumed response does not fabricate continuous response time", () => {
    const response = resumedRun.events.find(event => event.type === "response"); assert.equal(response.payload.response_time_ms, null); assert.equal(response.payload.resumed, true);
    assert.ok(new Set(resumedRun.events.map(event => event.clock.instance_id)).size >= 2);
  }); await resumed.context.close();

  const retry = await newPage("retry"); await start(retry.page);
  await retry.page.getByLabel("Your answer").fill("Delivery retry"); await continueButton(retry.page);
  await retry.page.getByRole("heading", {name: "Question number", exact: true}).waitFor();
  await retry.page.getByLabel("Your answer").fill("10"); await continueButton(retry.page);
  await retry.page.getByRole("heading", {name: "Thank you. Your responses are saved."}).waitFor({timeout: 15000});
  const retryRun = [...runs.values()].find(run => run.token.startsWith("retry-"));
  check("Lost acknowledgement retries the same batch without duplicate responses", () => { assert.equal(retryRun.events.filter(event => event.type === "response").length, 2); assert.equal(retryRun.events.length, retryRun.events.at(-1).sequence); });
  await retry.context.close();

  const interrupted = await newPage("interrupt"); await start(interrupted.page);
  await interrupted.page.locator("body.timed").waitFor();
  await interrupted.page.reload();
  await interrupted.page.getByRole("heading", {name: "The study was interrupted."}).waitFor();
  const interruptedRun = [...runs.values()].find(run => run.token.startsWith("interrupt-"));
  check("Timed reload terminates without replay or fabricated completion", () => { assert.equal(interruptedRun.finishes[0].outcome, "interrupted"); assert.equal(interruptedRun.events.filter(event => event.type === "step_started" && event.phase === "passive_viewing").length, 1); assert.equal(interruptedRun.events.filter(event => event.type === "response").length, 0); });
  await interrupted.context.close();

  const scoped = await newPage("scoped"); await start(scoped.page);
  await scoped.page.getByRole("heading", {name: "Question same", exact: true}).waitFor();
  await scoped.page.getByLabel("No", {exact: true}).check(); await continueButton(scoped.page);
  await scoped.page.getByRole("heading", {name: "Question followup", exact: true}).waitFor();
  await scoped.page.getByLabel("Your answer").fill("Only concept A"); await continueButton(scoped.page);
  await scoped.page.getByRole("heading", {name: "Question same", exact: true}).waitFor();
  await scoped.page.getByLabel("Yes", {exact: true}).check(); await continueButton(scoped.page);
  await scoped.page.getByRole("heading", {name: "Thank you. Your responses are saved."}).waitFor();
  const scopedRun = [...runs.values()].find(run => run.token.startsWith("scoped-"));
  check("Repeated questionnaires preserve stimulus linkage and scoped branching", () => {
    const values = scopedRun.events.filter(event => event.type === "response").map(event => [event.question_id, event.stimulus_id, event.payload.value]);
    assert.deepEqual(values, [["same", "stimulus-a", false], ["followup", "stimulus-a", "Only concept A"], ["same", "stimulus-b", true]]);
    assert.equal(scopedRun.events.filter(event => event.payload.skipped && event.stimulus_id === "stimulus-b").length, 1);
  }); await scoped.context.close();
  check("No uncaught browser errors", () => assert.deepEqual([all.errors, resumed.errors, retry.errors, interrupted.errors, scoped.errors].flat(), []));
  console.log(JSON.stringify({status: "passed", checks: checks.length, names: checks}, null, 2));
} finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }
