// Actual saved-answer researcher journey against an explicitly supplied,
// independently prepared synthetic QA workspace. No scoring or participant app.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

assert.ok(process.argv[2],'Supply the prepared irp-questionnaire-explorer QA folder.');
const folder=path.resolve(process.argv[2]);
assert.ok(path.basename(folder).startsWith('irp-questionnaire-explorer-'));
const output=path.join(folder,`browser-evidence-${Date.now()}`);await fs.mkdir(output);
const fixture=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
const r=path.resolve('../../work/native-r/bin/Rscript.exe');
const env={...process.env,R_LIBS_USER:path.resolve('../../work/r-library-brohn-restore'),R_USER:path.resolve('../../work'),LC_ALL:'C'};
const logs={researcher:'',worker:''},checks=[],scans=[],errors=[],latencies=[];
let worker=null,workerCount=0;
function helper(mode){const p=spawnSync(r,['--vanilla','tests/fixtures/researcher-questionnaire-explorer.R',mode,folder],{env,windowsHide:true,encoding:'utf8',maxBuffer:8*1024**2});assert.equal(p.status,0,p.stderr);}
async function snapshot(){helper('inspect');return JSON.parse(await fs.readFile(path.join(folder,'snapshot.json'),'utf8'));}
const sha=text=>createHash('sha256').update(text).digest('hex');
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log(`PASS ${label}`);};
await fs.unlink(path.join(folder,'stop.request')).catch(e=>{if(e.code!=='ENOENT')throw e;});
const app=spawn(r,['--vanilla','tests/fixtures/researcher-questionnaire-explorer.R','serve',folder],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});
for(const stream of[app.stdout,app.stderr])stream.on('data',b=>logs.researcher+=b);
const browser=await chromium.launch({channel:'chrome',headless:true});
const context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage();
page.on('pageerror',e=>errors.push(e.message));
const root=page.locator('#qx-root'),detail=page.locator('#qx_detail');
const action=(collection,name)=>page.locator(`#qx_${collection}`).getByRole('button',{name,exact:true});
async function idle(){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&![...document.querySelectorAll('.recalculating')].some(e=>e.getClientRects().length));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);}
async function report(source){
  await page.getByRole('button',{name:'Studies',exact:true}).click();
  await page.getByLabel('Search studies',{exact:true}).fill(source.study_title);
  await page.locator(`[data-brohn-event="brohn_open_study"][data-brohn-value='"${source.study_id}"']`).click();
  await expect(page.getByLabel('Study name',{exact:true})).toHaveValue(source.study_title);
  await page.getByRole('button',{name:'Results',exact:true}).click();
  await page.waitForFunction(()=>{const f=document.getElementById('study_form_identity');return f?.value.endsWith(':Results')&&Shiny.shinyapp.$inputValues.study_form_identity===f.value;});
  await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${source.report_id}"']`).click();
  await page.getByRole('link',{name:'JSON + provenance',exact:true}).waitFor();await idle();
}
async function tab(name){await root.getByRole('tab',{name,exact:true}).click();await idle();}
async function filters(collection,values={}){
  const form=page.locator(`[data-qx-form="${collection}"]`);
  for(const field of await form.locator('input[data-qx-field]').all())await field.fill(values[await field.getAttribute('data-qx-field')]??'');
  if(collection==='answers')await form.locator('[data-qx-field="status"]').selectOption(values.status??'');
  await form.getByRole('button',{name:'Apply filters',exact:true}).click();await idle();
}
async function openRow(collection,ordinal){const start=performance.now();await page.locator(`#qx-row-${collection}-${ordinal}`).click();await expect(detail.locator('#qx-detail-heading')).toBeVisible();await idle();latencies.push({action:'detail',collection,milliseconds:performance.now()-start});}
async function closeDetail(ordinal,collection='answers'){await detail.getByRole('button',{name:'Close detail',exact:true}).click();await expect(detail.locator('#qx-detail-heading')).toHaveCount(0);if(ordinal)await expect(page.locator(`#qx-row-${collection}-${ordinal}`)).toBeFocused();}
async function allValue(source=false){const label=source?'Complete source text chunk':'Complete value text chunk';const parts=[];for(;;){await idle();parts.push(await detail.getByRole('region',{name:label,exact:true}).textContent());const next=detail.getByRole('button',{name:'Next text chunk',exact:true});if(!await next.count())break;const prior=await next.getAttribute('data-qx-action');await next.click();await expect.poll(async()=>{const n=detail.getByRole('button',{name:'Next text chunk',exact:true});return await n.count()?await n.getAttribute('data-qx-action'):null;}).not.toBe(prior);}return parts.join('');}
async function download(label,name){const pending=page.waitForEvent('download',{timeout:120000});await page.getByRole('link',{name:label,exact:true}).click();const d=await pending;assert.equal(await d.failure(),null);const file=path.join(output,name);await d.saveAs(file);return file;}
async function axe(label,narrow=false){
  await page.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});await idle();
  const violations=(await new AxeBuilder({page}).analyze()).violations;
  const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);
  const smallTargets=narrow?await root.locator('button:visible,input:visible,select:visible,summary:visible,[role="tab"]:visible').evaluateAll(es=>es.filter(e=>e.getBoundingClientRect().height<44).map(e=>e.id||e.textContent)):[];
  const wrappedCaptions=narrow?await root.locator('caption').evaluateAll(es=>es.filter(e=>e.getBoundingClientRect().height>44).map(e=>e.textContent)):[];
  scans.push({label,count:violations.length,overflow,smallTargets,wrappedCaptions});
  const visibleFocus=await detail.locator('#qx-detail-heading').count()?detail.locator('#qx-detail-heading'):page.locator('#qx_answers_search');
  await visibleFocus.evaluate(e=>e.scrollIntoView({block:'start',behavior:'instant'}));
  await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(violations,null,2));await page.screenshot({path:path.join(output,`${label}.png`),fullPage:false});
  console.log(`SCAN ${label}: ${violations.length} axe violations, overflow=${overflow}, small targets=${smallTargets.length}, wrapped captions=${wrappedCaptions.length}`);
  await page.setViewportSize({width:1440,height:1080});
}
function processOne(){workerCount++;worker=spawn(r,['--vanilla','scripts/run-worker.R','--root',fixture.workspace,'--once'],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});for(const stream of[worker.stdout,worker.stderr])stream.on('data',b=>logs.worker+=b);return new Promise((resolve,reject)=>{worker.on('error',reject);worker.on('exit',(code,signal)=>code===0?resolve():reject(new Error(`Worker ${code}/${signal}: ${logs.worker}`)));});}

try{
  await expect.poll(async()=>{if(app.exitCode!==null)throw new Error(logs.researcher);try{return(await fetch(`http://127.0.0.1:${fixture.port}/`)).status===200;}catch{return false;}},{timeout:60000,intervals:[250,500,1000]}).toBe(true);
  await page.goto(`http://127.0.0.1:${fixture.port}/`);const initial=await snapshot();
  await report(fixture.original);await page.getByRole('button',{name:'Explore all answers',exact:true}).click();
  await expect.poll(async()=>await root.count()>0||await page.getByRole('button',{name:'Retry saved source',exact:true}).count()>0,{timeout:60000}).toBe(true);await idle();
  if(await page.getByRole('button',{name:'Retry saved source',exact:true}).count()){
    await page.getByRole('button',{name:'Retry saved source',exact:true}).click();
    await page.getByRole('heading',{name:'Preparing saved answers',exact:true}).waitFor();
    await expect(page.getByRole('progressbar',{name:'Preparing saved answers',exact:true})).not.toHaveAttribute('value',/.+/);
    await page.getByRole('button',{name:'Cancel preparation',exact:true}).click();
    await page.getByRole('button',{name:'Retry saved source',exact:true}).waitFor();
    await expect(page.getByRole('link',{name:'JSON + provenance',exact:true})).toBeVisible();
    check(true,'Queued preparation cancellation preserves the report and full downloads with honest indeterminate progress');
    await page.getByRole('button',{name:'Retry saved source',exact:true}).click();
    await page.getByRole('heading',{name:'Preparing saved answers',exact:true}).waitFor();
    const pending=processOne();pending.catch(()=>{});await expect(root).toBeVisible({timeout:180000});await pending;
    check(true,'Retrying the same saved source completes a real supervised index worker and opens the ready explorer');
  }
  await expect(root).toBeVisible({timeout:60000});await idle();
  await expect(page.locator('#qx_questions')).toContainText('Showing 1–12 of 12 matching records; 12 records in this saved source.');
  await openRow('questions',12);await expect(detail).toContainText('Saved mean: Unavailable in saved summary');
  await expect(detail.getByRole('table',{name:'Saved distribution',exact:true}).locator('tbody tr')).toHaveCount(50);
  await detail.getByRole('button',{name:'Next page',exact:true}).click();await expect(detail).toContainText('Distinct saved value 60');
  await expect(detail).toContainText('Showing 51–60 of 60 matching records; 60 records in this saved source.');
  check(true,'The twelfth saved question opens all sixty independently specified distribution entries beyond both previews');
  await detail.getByRole('button',{name:'See answers',exact:true}).click();
  await expect(page.locator('#qx_answers_question_id')).toHaveValue('q-original-12');
  await expect(page.locator('#qx_answers_condition_id')).toHaveValue('whole-study');
  await expect(page.locator('#qx_answers')).toContainText('of 60 matching records; 720 records in this saved source.');
  await filters('answers');await expect(page.locator('#qx_answers')).toContainText('Showing 1–50 of 720 matching records; 720 records in this saved source.');
  const ordinals=[];
  for(;;){ordinals.push(...await page.locator('#qx_answers [id^="qx-row-answers-"]').evaluateAll(es=>es.map(e=>Number(e.id.split('-').at(-1)))));const next=action('answers','Next page');if(!await next.count())break;const start=performance.now(),old=await next.getAttribute('data-qx-action');await next.click();await expect.poll(async()=>{const n=action('answers','Next page');return await n.count()?await n.getAttribute('data-qx-action'):null;}).not.toBe(old);latencies.push({action:'page',milliseconds:performance.now()-start});}
  assert.deepEqual(ordinals,Array.from({length:720},(_,i)=>i+1));check(true,'All 720 original saved answers are reachable exactly once in source order across fifteen real browser pages');
  await action('answers','Previous page').focus();await page.keyboard.press('Enter');await expect(page.locator('#qx_answers')).toContainText('Showing 651–700 of 720');
  check(true,'Keyboard pagination returns to the exact preceding source page');
  await filters('answers',{question_id:'q-original-1'});await expect(page.locator('#qx_answers')).toContainText('of 60 matching records; 720 records in this saved source.');
  await filters('answers');await expect(page.locator('#qx_answers')).toContainText('Showing 1–50 of 720 matching records; 720 records in this saved source.');
  const cases=[[1,'number','0'],[2,'boolean','false'],[3,'text','0'],[4,'null','null'],[5,'text',''],[6,'structured','[0,false,null]'],[7,'text','<script>window.IRP_UNSAFE=true</script>'],[8,'text','=1+1']];
  for(const[ordinal,kind,value]of cases){await openRow('answers',ordinal);await expect(detail).toContainText(`native type: ${kind}`);assert.equal(await allValue(),value);await closeDetail(ordinal);}
  assert.equal(await page.evaluate(()=>window.IRP_UNSAFE),undefined);
  check(true,'Native numeric zero, false, text zero, null omission, empty text, structured values, formula text and HTML-like text stay distinct and safely escaped');
  await openRow('answers',9);const complete=await allValue();
  assert.equal(sha(Buffer.from(complete)),fixture.original.long_value_hash);assert.equal(complete,'é漢🔒\n'.repeat(20000)+'END OF ORIGINAL COMPLETE ANSWER');assert.equal(Buffer.byteLength(complete),200031);assert.equal(Array.from(complete).length,80031);
  await detail.getByRole('button',{name:'Previous text chunk',exact:true}).click();await detail.getByRole('button',{name:'Next text chunk',exact:true}).waitFor();
  await axe('explorer-long-value-desktop');await axe('explorer-long-value-390',true);await closeDetail(9);
  check(true,'Every long UTF-8 chunk rejoins to the independent 200031-byte source hash without dropping emoji, newlines or the final answer');
  await openRow('answers',1);await detail.getByRole('button',{name:'Changes',exact:true}).click();await expect(detail).toContainText('No edit history was retained for this source.');await closeDetail(1);
  await filters('answers',{question_id:'q-original-12',participant_id:'alias:repeat-code',session_id:'visit-b'});
  await expect(page.locator('#qx_answers')).toContainText('Showing 1–30 of 30 matching records; 720 records in this saved source.');
  check(true,'Exact question, participant code and session filters preserve repeated visits and expose complete matching counts');
  await filters('answers',{search:'%_ OR 1=1 --'});await expect(page.locator('#qx_answers')).toContainText('No records match these filters.');
  await filters('answers');const search=page.locator('#qx_answers_search');
  await search.fill('Original question 12');await search.press('Enter');await expect(page.locator('#qx_answers')).toContainText('of 60 matching records; 720 records in this saved source.');
  await search.fill('original question 12');await search.press('Enter');await expect(page.locator('#qx_answers')).toContainText('No records match these filters.');
  await filters('answers');await page.locator('#qx_answers_session_id').fill('visit-b');await action('answers','Next page').click();
  await expect(page.locator('#qx_answers')).toContainText('Showing 1–50 of 360 matching records; 720 records in this saved source.');await expect(page.locator('#qx-row-answers-361')).toBeVisible();
  check(true,'Immediate type-Enter and filter-Next actions use current form values; search is literal UTF-8 and explicitly case sensitive');
  await page.evaluate(()=>{window.irpFilterNode=document.getElementById('qx_answers_session_id');});
  await openRow('answers',361);await closeDetail(361);await tab('Questions');await expect(page.locator('#qx_questions')).toContainText('Responses 60');await tab('Answers');
  await expect(page.locator('#qx_answers_session_id')).toHaveValue('visit-b');
  await expect.poll(()=>page.evaluate(()=>window.irpFilterNode===document.getElementById('qx_answers_session_id')),{timeout:4000,intervals:[1000]}).toBe(true);
  check(true,'Closing detail restores row focus, switching views preserves filters and page, and saved summary denominators remain unchanged');
  await axe('explorer-filtered-390',true);
  const jsonBytes=await fs.readFile(await download('JSON + provenance','original-complete-report.json')),full=JSON.parse(jsonBytes);
  assert.equal(full.export.saved_report_hash,fixture.original.report_hash);assert.equal(full.analysis.observations.length,720);assert.equal(sha(Buffer.from(full.analysis.observations[8].value)),fixture.original.long_value_hash);
  const csvFile=await download('Download observations','original-complete-observations.csv');assert.ok((await fs.stat(csvFile)).size>200000);
  const artifactFile=await download('Download complete artifact','original-complete-artifact.jsonl');assert.ok((await fs.stat(artifactFile)).size>200000);
  check(true,'Complete JSON, observation CSV and typed artifact downloads remain usable after paged browsing and preserve the original complete source');
  if(fixture.revision){
    const oldIdentity=await root.getAttribute('data-qx-identity');await report(fixture.revision);await expect(root).toHaveCount(0);
    await page.getByRole('button',{name:'Explore all answers',exact:true}).click();await expect(root).toBeVisible({timeout:60000});
    assert.notEqual(await root.getAttribute('data-qx-identity'),oldIdentity);await tab('Answers');
    await expect(page.locator('#qx_answers')).toContainText('Showing 1–50 of 200 matching records; 200 records in this saved source.');
    await expect(page.locator('#qx_answers_session_id')).toHaveValue('');
    await filters('answers',{question_id:'boundary-q-200'});await expect(page.locator('#qx_answers')).toContainText('Showing 1–1 of 1 matching records; 200 records in this saved source.');
    await openRow('answers',200);assert.equal(await allValue(),`${'a'.repeat(19000)} 2 200`);await expect(detail).toContainText('Original response time: Unavailable in retained source');
    await detail.getByText('Source',{exact:true}).click();await expect(detail).toContainText('Saved session link unavailable:');
    await expect(detail.getByRole('link',{name:'Open saved session',exact:true})).toHaveCount(0);
    await detail.getByRole('button',{name:'Changes',exact:true}).click();
    const history=detail.getByRole('table',{name:'Saved history',exact:true});await expect(history.locator('tbody tr')).toHaveCount(4);
    const commits=history.locator('tbody tr').filter({hasText:/commit/});await expect(commits).toHaveCount(2);
    await commits.first().getByRole('button',{name:'Open record',exact:true}).click();assert.equal(await allValue(),`${'a'.repeat(19000)} 1 200`);
    await detail.getByRole('button',{name:'Complete source record',exact:true}).click();const retainedEvent=JSON.parse(await allValue(true));assert.equal(retainedEvent.payload.kind,'commit');assert.equal(retainedEvent.question_id,'boundary-q-200');assert.equal(typeof retainedEvent.clock.time_origin_ms,'string');
    await detail.getByRole('button',{name:'Return to parent record',exact:true}).click();assert.equal(await allValue(),`${'a'.repeat(19000)} 2 200`);
    await detail.getByRole('button',{name:'Changes',exact:true}).click();await axe('explorer-retained-history-desktop');await axe('explorer-retained-history-390',true);
    check(true,'The retained receiver report exposes the exact current answer and original acknowledged edit history, keeps revised timing unavailable and honestly omits an unavailable saved-session link');
    const retainedBytes=await fs.readFile(await download('JSON + provenance','revision-complete-report.json')),retained=JSON.parse(retainedBytes);
    assert.equal(retained.export.saved_report_hash,fixture.revision.report_hash);assert.equal(retained.analysis.questionnaire_revision.runs[0].history_events.length,803);assert.equal(retained.analysis.questionnaire_revision.runs[0].effective_records.length,200);
    check(true,'Switching reports clears the former source context, and the retained full download still contains all 200 final records and 803 acknowledged events');
  }
  const final=await snapshot();assert.equal(final.source_hash,fixture.original.report_hash);assert.equal(errors.length,0);assert.ok(scans.every(s=>s.count===0&&!s.overflow&&!s.smallTargets.length&&!s.wrappedCaptions.length),JSON.stringify(scans));
  const newJobs=final.jobs.filter(j=>!initial.jobs.some(old=>old.id===j.id));assert.ok(newJobs.every(j=>j.operation==='questionnaire_index'));
  check(true,'Browsing preserves source hashes, queues no scientific analysis and completes without browser exceptions or visible R errors');
  await fs.writeFile(path.join(output,'results.json'),JSON.stringify({passed:true,origin:'original_synthetic',checks,scans,latencies,source:fixture,worker_processes_this_invocation:workerCount,resources:final.resources,
    limits:['Automated desktop and 390px researcher interaction, synthetic typed records and previously retained synthetic receiver events; no human usability or hardware qualification.','Measured fixture evidence is not an unlimited-size or transient-memory guarantee.']},null,2));
  console.log(JSON.stringify({checks:checks.length,scans:scans.length,folder,output}));
}catch(error){await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.html'),await page.content().catch(()=>'(closed)'));await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,scans,errors,logs,text:await page.locator('body').innerText().catch(()=>'(closed)')},null,2));throw error;
}finally{
  await browser.close();
  if(worker&&worker.exitCode===null){if(process.platform==='win32')spawnSync('taskkill',['/PID',String(worker.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});else worker.kill();await new Promise(resolve=>worker.exitCode!==null?resolve():worker.once('exit',resolve));}
  if(app.exitCode===null){await fs.writeFile(path.join(folder,'stop.request'),'Stop owned IRP explorer researcher fixture.');await expect.poll(()=>app.exitCode!==null,{timeout:20000,intervals:[100,250]}).toBe(true);}
  for(const[name,text]of Object.entries(logs))await fs.writeFile(path.join(output,`${name}.log`),text);
}
