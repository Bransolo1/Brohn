// Actual researcher opt-in, participant answer revision and final analysis.
// Wait for the coordinated source-freeze signal before launching this harness.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn, spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chromium, expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const folder = await fs.mkdtemp(path.resolve('../../work/test-runs/brohn-question-revision-ui-'));
const output = path.join(folder, 'evidence'); await fs.mkdir(output);
const r = path.resolve('../../work/native-r/bin/x64/Rscript.exe');
const python = path.resolve('../../work/tooling/methods-venv/Scripts/python.exe');
const env = {...process.env, R_LIBS_USER:path.resolve('../../work/r-library-brohn'), R_USER:path.resolve('../../work'), LC_ALL:'C'};
function helper(mode) {
  const result = spawnSync(r, ['--vanilla', 'tests/fixtures/researcher-question-revision.R', mode, folder], {env, windowsHide:true, encoding:'utf8'});
  assert.equal(result.status, 0, result.stderr);
}
helper('create');
const fixture = JSON.parse(await fs.readFile(path.join(folder, 'fixture.json'), 'utf8'));
const app = spawn(r, ['--vanilla', 'tests/fixtures/researcher-question-revision.R', 'serve', folder], {env, windowsHide:true, stdio:['ignore','pipe','pipe']});
let log = ''; for (const stream of [app.stdout, app.stderr]) stream.on('data', bytes => log += bytes);
const browser = await chromium.launch({channel:'chrome', headless:true});
const context = await browser.newContext({viewport:{width:1440,height:1080}});
const page = await context.newPage(); let active = page, design, participantContext;
const checks = [], scans = [], errors = [];
const watch = p => p.on('pageerror', e => errors.push(e.message)); watch(page);
const check = (ok, label) => {assert.ok(ok, label); checks.push(label); console.log(`PASS ${label}`);};
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
async function snapshot() {helper('inspect'); return JSON.parse(await fs.readFile(path.join(folder,'snapshot.json'),'utf8'));}
async function stage(name) {
  await page.getByRole('button',{name,exact:true}).click();
  if (['Plan','Questions','Collect','Results','Review','History'].includes(name)) await page.waitForFunction(stage => {
    const f = document.getElementById('study_form_identity');
    return f?.value.endsWith(`:${stage}`) && f.value === Shiny.shinyapp.$inputValues.study_form_identity;
  }, name);
}
async function select(id, value) {
  const label = await page.locator(`#${id}`).evaluate((el,value) => el.selectize.options[value][el.selectize.settings.labelField], value);
  const input = page.locator(`#${id}-selectized`); await input.click(); await input.fill(label);
  await page.locator('.selectize-dropdown:visible').getByRole('option',{name:label,exact:true}).click();
}
async function openStudy() {
  await stage('Studies'); await page.getByLabel('Search studies',{exact:true}).fill(fixture.title);
  await page.locator(`[data-brohn-event="brohn_open_study"][data-brohn-value='"${fixture.study_id}"']`).click();
  await expect(page.getByLabel('Study name',{exact:true})).toHaveValue(fixture.title);
}
async function download(label, name) {
  const link = page.getByRole('link',{name:label,exact:true}); await expect(link).toHaveAttribute('href',/session\/.*download\//);
  const pending = page.waitForEvent('download'); await link.click(); const item = await pending;
  assert.equal(await item.failure(),null); const file = path.join(output,name); await item.saveAs(file); return file;
}
function portable(file) {
  const result=spawnSync(python,['-c',"import sys,zipfile;print(zipfile.ZipFile(sys.argv[1]).read('design.json').decode('utf-8'))",file],{windowsHide:true,encoding:'utf8'});
  assert.equal(result.status,0,result.stderr);return JSON.parse(result.stdout);
}
function csv(file) {
  const result=spawnSync(python,['-c',"import sys,csv,json;print(json.dumps(list(csv.DictReader(open(sys.argv[1],encoding='utf-8-sig',newline='')))))",file],{windowsHide:true,encoding:'utf8'});
  assert.equal(result.status,0,result.stderr);return JSON.parse(result.stdout);
}
async function axe(label, narrow = false, p = page) {
  await p.setViewportSize(narrow ? {width:390,height:844} : {width:1440,height:1080});
  if (p === page) {
    await page.waitForFunction(() => !document.documentElement.classList.contains('shiny-busy') && ![...document.querySelectorAll('.recalculating')].some(e => e.getClientRects().length));
    await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);
  }
  const violations=(await new AxeBuilder({page:p}).analyze()).violations;scans.push({label,count:violations.length});
  await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(violations,null,2));
  await p.screenshot({path:path.join(output,`${label}.png`),fullPage:false});
  check(!violations.length,`${label}: no automated accessibility violations`);
  check(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`${label}: no page overflow`);
  await p.setViewportSize({width:1440,height:1080});
}
async function startParticipant(url, alias) {
  const pc=await browser.newContext({viewport:{width:1440,height:1080}}),p=await pc.newPage();watch(p);active=p;
  await p.goto(url);await p.getByLabel('Participant alias (required)',{exact:true}).fill(alias);
  await p.getByLabel('I have read the study information and agree to take part.',{exact:true}).check();
  const received=p.waitForResponse(r=>r.url().includes('/api/start/')&&r.request().method()==='POST');
  await p.getByRole('button',{name:'Start study',exact:true}).click();const start=await(await received).json();
  assert.ok(start.run_id,JSON.stringify(start));return {pc,p,start};
}
const question = id => design.questions.find(q=>q.id===id);
async function answer(p,id,value) {
  const q=question(id);await p.getByRole('heading',{name:q.prompt,exact:true}).waitFor();
  if(q.type==='single_choice') await p.getByRole('radio',{name:q.options.find(o=>Object.is(o.value,value)).label,exact:true}).check();
  else if(q.type==='rating') await p.getByRole('radio',{name:String(value),exact:true}).check();
  else if(q.type==='number') await p.getByRole('spinbutton',{name:'Your answer',exact:true}).fill(String(value));
  else if(q.type==='text'&&value!==null) await p.getByRole('textbox',{name:'Your answer',exact:true}).fill(value);
  await p.getByRole('button',{name:'Continue',exact:true}).click();
}
async function review(p) {await p.getByRole('heading',{name:'Review your answers',exact:true}).waitFor();}
async function edit(p,id) {await review(p);await p.getByRole('button',{name:`Edit: ${question(id).prompt}`,exact:true}).click();await p.getByRole('heading',{name:question(id).prompt,exact:true}).waitFor();}
async function finishBefore(p,stillValue,tryBack=false) {
  await answer(p,'q-review-still-visible',stillValue);
  if(tryBack){await p.getByRole('heading',{name:question('q-review-independent').prompt,exact:true}).waitFor();await p.getByRole('button',{name:'Back',exact:true}).click();await p.getByRole('heading',{name:question('q-review-still-visible').prompt,exact:true}).waitFor();await expect(p.getByRole('spinbutton',{name:'Your answer',exact:true})).toHaveValue(String(stillValue));await answer(p,'q-review-still-visible',stillValue);}
  await answer(p,'q-review-independent',4);
  await answer(p,'q-review-optional',null);await answer(p,'q-review-information',null);await review(p);
}
async function noPriorBack(p) {
  const back=p.getByRole('button',{name:'Back',exact:true});if(await back.count())await expect(back).toBeDisabled();
}
const row = (projection,id) => projection.effective_records.find(r=>r.question_id===id);

try {
  await expect.poll(async()=>{if(app.exitCode!==null)throw new Error(log);try{return(await fetch(`http://127.0.0.1:${fixture.port}/`)).status===200;}catch{return false;}},{timeout:60000,intervals:[250,500,1000]}).toBe(true);
  await page.goto(`http://127.0.0.1:${fixture.port}/`);await openStudy();await stage('Questions');
  const command=page.getByRole('button',{name:'Enable answer review',exact:true});
  const stale=JSON.parse(await command.getAttribute('data-brohn-value'));await command.click();
  await expect(page.getByRole('button',{name:'Use forward-only',exact:true})).toBeVisible();
  assert.equal((await snapshot()).study.body.questionnaire_navigation.profile,'within-occurrence-revision/1.0');
  await page.evaluate(value=>Shiny.setInputValue('questionnaire_navigation_change',value,{priority:'event'}),stale);
  await expect(page.locator('#platform_error')).toContainText(/changed|current|reopen|stale/i);
  await stage('Use forward-only');assert.equal((await snapshot()).study.body.questionnaire_navigation,undefined);
  await stage('Enable answer review');await expect(page.getByRole('button',{name:'Use forward-only',exact:true})).toBeVisible();
  design=(await snapshot()).study.body;await stage('Save');assert.deepEqual((await snapshot()).study.body,design);
  check(true,'Actual opt-in, explicit forward-only restoration and stale command rejection preserve a deliberate saved navigation policy');
  await axe('answer-review-researcher-narrow',true);
  const packageFile=await download('Export design','original-answer-review.brohn-study.zip');assert.deepEqual(portable(packageFile),design);
  await stage('Collect');await select('release_origin','sample');await page.getByLabel('Require a researcher-issued participant code to link repeat sessions',{exact:true}).check();await stage('Release participant study');
  await expect.poll(async()=>(await snapshot()).releases.length).toBe(2);
  const released=(await snapshot()).releases.find(r=>r.id!==fixture.legacy_release.id);
  const releaseCard=page.getByRole('heading',{name:`Release ${released.id.slice(0,18)}`,exact:true}).locator('xpath=ancestor::*[contains(concat(" ",normalize-space(@class)," ")," brohn-card ")][1]');
  const url=await releaseCard.getByRole('link',{name:'Open participant study',exact:true}).getAttribute('href');
  const legacy=await startParticipant(`http://127.0.0.1:${fixture.participant_port}/participant/?token=${fixture.legacy_release.token}`,'LEGACY-001');
  assert.deepEqual(legacy.start.protocol.design,fixture.original);assert.equal(legacy.start.protocol.questionnaire_occurrences,undefined);
  await legacy.p.getByRole('button',{name:'Begin',exact:true}).click();await legacy.p.getByRole('heading',{name:question('q-review-driver').prompt,exact:true}).waitFor();await expect(legacy.p.getByRole('button',{name:'Back',exact:true})).toHaveCount(0);await legacy.pc.close();active=page;
  check(true,'A new participant on the previously frozen release still receives the exact original forward-only protocol');
  const live=await startParticipant(url,'REVISION-001');participantContext=live.pc;const {p,start}=live;assert.deepEqual(start.protocol.design,design);assert.equal(start.protocol.questionnaire_occurrences.length,4);
  await fs.writeFile(path.join(output,'assigned-review-protocol.json'),JSON.stringify(start.protocol,null,2));
  await p.getByRole('button',{name:'Begin',exact:true}).click();await answer(p,'q-review-driver',false);await answer(p,'q-review-dependent',2);await answer(p,'q-review-transitive',3);await finishBefore(p,4,true);
  let saved=(await snapshot()).runs.find(r=>r.id===start.run_id),initial=saved.projection;
  assert.equal(row(initial,'q-review-driver').value,false);assert.equal(row(initial,'q-review-dependent').value,2);assert.equal(row(initial,'q-review-transitive').value,3);
  assert.equal(row(initial,'q-review-still-visible').answer_version,1);assert.ok(saved.events.some(e=>e.type==='questionnaire_event'&&e.payload.kind==='visit'&&e.payload.reason==='back'));
  check(true,'Actual Back returns within the current questionnaire and unchanged confirmation keeps one original answer version');
  const independentHead=row(initial,'q-review-independent').event_id;
  await edit(p,'q-review-driver');await answer(p,'q-review-driver',0);
  await p.getByRole('heading',{name:question('q-review-still-visible').prompt,exact:true}).waitFor();await expect(p.getByRole('spinbutton',{name:'Your answer',exact:true})).toHaveValue('');
  await expect(p.locator('#questionnaire-changes')).toContainText('3 dependent answers');
  saved=(await snapshot()).runs.find(r=>r.id===start.run_id);for(const id of ['q-review-dependent','q-review-transitive']){assert.equal(row(saved.projection,id).status,'not_displayed');assert.equal(row(saved.projection,id).value,null);}
  assert.equal(row(saved.projection,'q-review-still-visible').status,'invalidated_unanswered');assert.equal(row(saved.projection,'q-review-independent').event_id,independentHead);
  check(true,'Changing native false to numeric zero hides and clears direct/transitive answers, clears a still-visible dependent, and preserves independent evidence');
  await finishBefore(p,4);await edit(p,'q-review-driver');await answer(p,'q-review-driver',false);
  await p.getByRole('heading',{name:question('q-review-dependent').prompt,exact:true}).waitFor();await expect(p.getByRole('spinbutton',{name:'Your answer',exact:true})).toHaveValue('');
  await answer(p,'q-review-dependent',2);await answer(p,'q-review-transitive',3);await finishBefore(p,5);
  await edit(p,'q-review-driver');await answer(p,'q-review-driver',0);await finishBefore(p,6);
  saved=(await snapshot()).runs.find(r=>r.id===start.run_id);assert.equal(row(saved.projection,'q-review-driver').value,0);assert.equal(row(saved.projection,'q-review-independent').answer_version,1);
  assert.equal(row(saved.projection,'q-review-optional').status,'optional_omission');assert.equal(row(saved.projection,'q-review-information').status,'information_acknowledged');
  await expect(p.getByRole('button',{name:`Edit: ${question('q-review-dependent').prompt}`,exact:true})).toHaveCount(0);
  await axe('answer-review-participant-narrow',true,p);
  check(true,'Reappearing branches require fresh answers; final review distinguishes omission from information and excludes hidden historical answers');
  await p.getByRole('button',{name:'Continue to the next part',exact:true}).click();
  for(const [index,value] of [6,4].entries()) {
    await p.getByRole('heading',{name:question('q-review-after').prompt,exact:true}).waitFor();await noPriorBack(p);
    await answer(p,'q-review-after',value);await review(p);
    await expect(p.getByRole('button',{name:`Edit: ${question('q-review-driver').prompt}`,exact:true})).toHaveCount(0);
    saved=(await snapshot()).runs.find(r=>r.id===start.run_id);assert.equal(saved.projection.quality.sealed_occurrence_count,index+1);
    await p.getByRole('button',{name:'Continue to the next part',exact:true}).click();
  }
  await answer(p,'q-review-scale-1',2);await answer(p,'q-review-scale-2',4);await answer(p,'q-review-end-zero',0);await review(p);
  await edit(p,'q-review-scale-1');await answer(p,'q-review-scale-1',6);
  await p.getByRole('heading',{name:question('q-review-scale-2').prompt,exact:true}).waitFor();await expect(p.getByRole('radio',{name:'4',exact:true})).toBeChecked();
  await p.reload();await p.getByRole('button',{name:'Resume this participant session',exact:true}).click();await p.getByRole('heading',{name:question('q-review-scale-2').prompt,exact:true}).waitFor();await expect(p.getByRole('radio',{name:'4',exact:true})).toBeChecked();
  await answer(p,'q-review-scale-2',4);await answer(p,'q-review-end-zero',0);await review(p);await p.getByRole('button',{name:'Finish study',exact:true}).click();
  await p.getByRole('heading',{name:'Thank you. Your responses are saved.',exact:true}).waitFor({timeout:45000});await participantContext.close();participantContext=null;active=page;
  saved=(await snapshot()).runs.find(r=>r.id===start.run_id);assert.equal(saved.completion_status,'completed');assert.deepEqual(saved.protocol,start.protocol);assert.equal(saved.projection.quality.sealed_occurrence_count,4);
  assert.equal(row(saved.projection,'q-review-scale-1').value,6);assert.equal(row(saved.projection,'q-review-scale-1').response_time_ms,null);assert.equal(row(saved.projection,'q-review-scale-2').value,4);assert.equal(row(saved.projection,'q-review-scale-2').answer_version,1);
  assert.equal(saved.projection.effective_records.filter(r=>r.question_id==='q-review-after').length,2);
  check(true,'Untimed reload preserves the assigned question and answer; four sealed occurrences keep stimulus boundaries and one final answer per item');
  let state;await expect.poll(async()=>{state=await snapshot();const bad=state.jobs.find(j=>j.status==='failed');if(bad)throw new Error(JSON.stringify(bad.error));return state.reports.length;},{timeout:180000,intervals:[1000,2000]}).toBe(1);
  const report=state.reports[0],scores=report.body.analysis.scales.observations;assert.equal(scores.length,1);assert.equal(scores[0].value,5);assert.equal(scores[0].answered_items,2);assert.equal(scores[0].scope,'end');assert.equal(scores[0].status,'scored');
  const revisions=report.body.analysis.questionnaire_revision;assert.equal(revisions.schema,'brohn-questionnaire-revision-results/1.0');assert.equal(revisions.runs.length,1);assert.deepEqual(revisions.runs[0],saved.projection);
  assert.equal(revisions.runs[0].effective_records.length,12);assert.equal(report.body.analysis.observations.length,9);
  assert.ok(report.body.analysis.observations.every(o=>!['q-review-dependent','q-review-transitive','q-review-information'].includes(o.question_id)));
  assert.equal(report.body.analysis.observations.find(o=>o.question_id==='q-review-driver').value,0);
  assert.deepEqual(revisions.runs[0].history_events.filter(e=>e.question_id==='q-review-driver'&&e.payload.kind==='commit').map(e=>e.payload.value),[false,0,false,0]);
  for(const event of revisions.runs[0].history_events)assert.deepEqual(event,saved.events.find(e=>e.id===event.id));
  assert.equal(row(revisions.runs[0],'q-review-scale-1').revision_count,1);assert.equal(row(revisions.runs[0],'q-review-scale-2').revision_count,0);
  await openStudy();await stage('Results');await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${report.id}"']`).click();await page.getByRole('heading',{name:'Questionnaire scale scores',exact:true}).waitFor();
  await page.getByRole('heading',{name:'Reviewed questionnaire answers',exact:true}).waitFor();await page.getByText('Review final answers and revision counts',{exact:true}).click();
  assert.deepEqual(JSON.parse(await fs.readFile(await download('JSON + provenance','answer-review-report.json'),'utf8')),report.body);
  const exported=csv(await download('Download scale scores CSV','answer-review-scale.csv'));assert.equal(exported.length,1);assert.deepEqual(JSON.parse(exported[0].score_record_json),scores[0]);
  await axe('answer-review-report-desktop');await axe('answer-review-report-narrow',true);
  check(true,'One automatic scientific report scores the final independent6+4 mean as5 and exports the exact final assessment');
  await openStudy();await stage('Collect');const protocolButton=page.locator('[data-brohn-event="view_run_protocol"]').filter({hasText:'View assigned protocol'});
  await page.waitForFunction(id=>[...document.querySelectorAll('[data-brohn-event="view_run_protocol"]')].some(n=>JSON.parse(n.dataset.brohnValue).run_id===id),start.run_id);
  const selected=await protocolButton.evaluateAll((nodes,id)=>nodes.find(n=>JSON.parse(n.dataset.brohnValue).run_id===id)?.getAttribute('data-brohn-value'),start.run_id);
  assert.ok(selected);await page.locator(`[data-brohn-event="view_run_protocol"][data-brohn-value='${selected}']`).click();await page.getByRole('dialog',{name:'Assigned participant protocol',exact:true}).waitFor();await axe('answer-review-assigned-protocol-narrow',true);
  const bytes=await fs.readFile(await download('Download assigned protocol JSON','reopened-assigned-review-protocol.json'));assert.deepEqual(JSON.parse(bytes),start.protocol);assert.equal(sha(bytes),saved.protocol_hash);await stage('Close protocol');await expect(page.getByRole('dialog')).toHaveCount(0);await expect(page.locator('.modal-backdrop')).toHaveCount(0);
  await stage('Save as template');await expect(page.locator('#platform_status')).toContainText('Design saved');state=await snapshot();const template=state.templates.find(t=>t.body.source_study_id===design.id||t.body.design?.id===design.id);assert.ok(template);
  await stage('Design library');await page.locator(`[data-brohn-event="brohn_use_template"][data-brohn-value='"${template.id}"']`).click();await page.getByLabel('Study name',{exact:true}).waitFor();const copies=[portable(await download('Export design','answer-review-template.zip'))];
  await openStudy();await stage('Clone design');await page.getByLabel('Name for the new study',{exact:true}).fill(`${fixture.title} clone`);await stage('Create clone');await expect(page.getByLabel('Study name',{exact:true})).toHaveValue(`${fixture.title} clone`);copies.push(portable(await download('Export design','answer-review-clone.zip')));
  await stage('Design library');await page.locator('#import_design_file').setInputFiles(packageFile);await page.getByLabel('Study name',{exact:true}).waitFor();copies.push(portable(await download('Export design','answer-review-reimport.zip')));
  for(const copy of copies){assert.notEqual(copy.id,design.id);assert.deepEqual(copy.questionnaire_navigation,design.questionnaire_navigation);assert.notEqual(copy.scales[0].id,design.scales[0].id);assert.ok(copy.questions.every(q=>!design.questions.some(old=>old.id===q.id)));const copiedDriver=copy.questions.find(q=>q.prompt===question('q-review-driver').prompt);assert.deepEqual(copiedDriver.options.map(o=>o.value),[false,0]);assert.equal(copy.questions.find(q=>q.prompt===question('q-review-dependent').prompt).show_if.question_id,copiedDriver.id);}
  await openStudy();assert.deepEqual(portable(await download('Export design','answer-review-reopened.zip')),design);state=await snapshot();assert.equal(state.reports.length,1);assert.ok(state.report_integrity.every(r=>r.hash_matches&&r.exact));assert.equal(state.jobs.length,1);assert.equal(state.jobs[0].status,'succeeded');assert.deepEqual(state.runs.find(r=>r.id===start.run_id).events,saved.events);
  check(true,'Template, clone, portable import and reopening retain the policy and typed references while the original completed journal and report stay exact');
  check(!errors.length&&scans.every(s=>!s.count),'No browser exceptions, visible Shiny errors or automated accessibility violations');
  await fs.writeFile(path.join(output,'results.json'),JSON.stringify({origin:'original_synthetic',execution:'Actual researcher opt-in, browser participant revision and one scientific worker',checks,scans,folder,run_id:start.run_id,legacy_run_id:legacy.start.run_id,report_id:report.id,reused_studies:copies.map(d=>d.id)},null,2));console.log(JSON.stringify({checks:checks.length,scans:scans.length,output}));
} catch(error) {
  await active.screenshot({path:path.join(output,'failure.png'),fullPage:false}).catch(()=>{});
  await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,scans,errors,text:await active.locator('body').innerText().catch(()=>'(closed)'),log},null,2));throw error;
} finally {
  await browser.close();if(app.exitCode===null){await fs.writeFile(path.join(folder,'stop.request'),'Stop owned answer-review QA services.');await expect.poll(()=>app.exitCode!==null,{timeout:30000,intervals:[100,500]}).toBe(true);}await fs.writeFile(path.join(output,'researcher.log'),log);
}
