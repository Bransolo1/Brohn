// Actual researcher author/reuse -> full participant procedures -> native saved reports.
// Original synthetic materials and automated keyboard input; no human/physical timing claims.
import assert from 'node:assert/strict';import fs from 'node:fs/promises';import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';import {createHash} from 'node:crypto';
import {chromium,expect as baseExpect} from '@playwright/test';import AxeBuilder from '@axe-core/playwright';
import {importTransferredSource} from './helpers/source-import.mjs';
const folder=path.resolve(process.argv[2]);assert.ok(path.basename(folder).startsWith('brohn-researcher-sciat-window-'));
const config=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8')),output=path.join(folder,`browser-${Date.now()}`);await fs.mkdir(output);
await fs.copyFile('tests/researcher-sciat-window.mjs',path.join(output,'executed-harness.mjs'));
const aliases=['ORIGINAL-SCIAT-001','ORIGINAL-SCIAT-002','ORIGINAL-SCIAT-EDGE','ORIGINAL-SCIAT-FAST'];
const expect=baseExpect.configure({timeout:30000}),r=path.resolve('../../work/native-r/bin/Rscript.exe'),python=path.resolve('../../work/tooling/methods-venv/Scripts/python.exe');
const env={...process.env,R_LIBS_USER:path.resolve('../../work/r-library-brohn-restore'),LC_ALL:'C',BROHN_PUBLICATION_PYTHON:python,BROHN_PUBLICATION_NATIVE_MANIFEST:path.resolve('../../work/tooling/brohn-native/publication-guard.json')};
const hash=b=>createHash('sha256').update(b).digest('hex'),checks=[],scans=[],errors=[],logs={researcher:'',participant:'',workers:[]};
const sourcePaths=['R/platform-sciat-window.R','R/platform-sciat-window-delivery.R','R/platform-sciat-window-score.R','R/platform-sciat-window-views.R','R/platform-sciat-window-candidate.R',
 'R/platform-core.R','R/platform-methods.R','R/platform-collection-routes.R','R/platform-task-evidence.R','R/platform-task-import.R','R/platform-task-plots.R','R/platform-task-plot-views.R','R/platform-task-cohort.R',
 'R/platform-load.R','R/platform-app.R','R/platform-jobs.R','R/platform-delivery.R','scripts/analysis-worker.R','www/participant/runner.js','www/participant/sciat-window-core.js','www/participant/sciat-window.js'];
const hashes=async()=>Object.fromEntries(await Promise.all(sourcePaths.map(async p=>[p,hash(await fs.readFile(p))]))),startHashes=await hashes();
await fs.writeFile(path.join(output,'source-hashes.json'),JSON.stringify(startHashes,null,2));
let services=[],worker=null,active,journey={};try{journey=JSON.parse(await fs.readFile(path.join(folder,'journey.json'),'utf8'));}catch(e){if(e.code!=='ENOENT')throw e;}
const save=()=>fs.writeFile(path.join(folder,'journey.json'),JSON.stringify(journey,null,2));
const check=(name,ok)=>{assert.ok(ok,name);checks.push(name);console.log(`PASS ${name}`);};
function helper(mode){const p=spawnSync(r,['--vanilla','tests/fixtures/researcher-sciat-window.R',mode,folder],{env,windowsHide:true,encoding:'utf8',maxBuffer:32*1024**2});assert.equal(p.status,0,p.stderr||p.stdout);}
async function snapshot(){helper('inspect');return JSON.parse(await fs.readFile(path.join(folder,'snapshot.json'),'utf8'));}
function jobRows(){const p=spawnSync(python,['-c',"import sqlite3,json,pathlib,sys;s=sqlite3.connect(pathlib.Path(sys.argv[1]).resolve().as_uri()+'?mode=ro',uri=True);s.row_factory=sqlite3.Row;rows=[dict(r) for r in s.execute('SELECT id,operation,status,attempt,request_json FROM jobs ORDER BY created_at,id')];[r.update(request=json.loads(r.pop('request_json'))) for r in rows];print(json.dumps(rows));s.close()",path.join(config.workspace,'catalog.sqlite')],{windowsHide:true,encoding:'utf8',maxBuffer:8*1024**2});assert.equal(p.status,0,p.stderr);return JSON.parse(p.stdout);}
async function start(){for(const role of['participant','researcher']){await fs.unlink(path.join(folder,`stop.${role}`)).catch(e=>{if(e.code!=='ENOENT')throw e;});
 const p=spawn(r,['--vanilla','tests/fixtures/researcher-sciat-window.R',role,folder],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});for(const s of[p.stdout,p.stderr])s.on('data',b=>logs[role]+=b);services.push({role,p});}
 for(const port of[config.participant_port,config.researcher_port])await expect.poll(async()=>{for(const s of services)if(s.p.exitCode!==null)throw Error(logs[s.role]);try{return(await fetch(`http://127.0.0.1:${port}/`)).status<500;}catch{return false;}},{timeout:90000,intervals:[300,700,1000]}).toBe(true);}
async function stop(){for(const s of services)await fs.writeFile(path.join(folder,`stop.${s.role}`),'Stop owned original SC-IAT QA service.');for(const {p}of services)if(p.exitCode===null)await new Promise(resolve=>{const timer=setTimeout(()=>{p.kill();resolve();},12000);p.once('exit',()=>{clearTimeout(timer);resolve();});});services=[];}
async function work(){let text='';worker=spawn(r,['--vanilla','scripts/run-worker.R','--root',config.workspace,'--once'],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});for(const s of[worker.stdout,worker.stderr])s.on('data',b=>text+=b);
 await new Promise((resolve,reject)=>{worker.once('error',reject);worker.once('exit',code=>code===0?resolve():reject(Error(text)));});logs.workers.push(text);worker=null;}
async function drain(){for(let n=0;n<12;n++){const jobs=jobRows(),failures=jobs.filter(j=>j.status==='failed');assert.deepEqual(failures,[],JSON.stringify(failures));if(!jobs.some(j=>j.status==='queued'||j.status==='running'))return await snapshot();await work();}throw Error('Unexpected unbounded queue in original SC-IAT fixture');}
function zipDesign(file){const p=spawnSync(python,['-c',"import sys,zipfile;print(zipfile.ZipFile(sys.argv[1]).read('design.json').decode('utf-8'))",file],{encoding:'utf8',windowsHide:true});assert.equal(p.status,0,p.stderr);return JSON.parse(p.stdout);}
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage();active=page;page.on('pageerror',e=>errors.push(e.message));
const button=name=>page.getByRole('button',{name,exact:true});
async function idle(){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&![...document.querySelectorAll('.recalculating')].some(e=>e.getClientRects().length));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);}
async function stage(name){await button(name).click();if(['Plan','Questions','Tasks','Collect','Review','Results','History'].includes(name))await page.waitForFunction(n=>{const f=document.getElementById('study_form_identity');return f?.value.endsWith(`:${n}`)&&f.value===Shiny.shinyapp.$inputValues.study_form_identity;},name);await idle();}
async function select(id,label){const node=page.locator(`#${id}-selectized`);await node.click();await node.fill(label);await page.locator('.selectize-dropdown:visible').getByRole('option',{name:label,exact:true}).click();}
async function selectValue(id,value){const label=await page.locator(`#${id}`).evaluate((n,v)=>n.selectize?.options[v]?.[n.selectize.settings.labelField]??[...n.options].find(o=>o.value===v)?.textContent,value);assert.ok(label,`${id}: ${value}`);await select(id,label);}
async function openStudy(id=journey.study_id){await stage('Studies');await page.getByLabel('Search studies',{exact:true}).fill('');await page.locator(`[data-brohn-event="brohn_open_study"][data-brohn-value='"${id}"']`).click();await idle();}
async function download(name,filename){const link=page.getByRole('link',{name,exact:true});await expect(link).toHaveAttribute('href',/session\/.*download\//);const pending=page.waitForEvent('download');await link.click();const d=await pending;assert.equal(await d.failure(),null);const file=path.join(output,filename);await d.saveAs(file);return file;}
async function scan(label,narrow=false,p=page){await p.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});if(p===page)await idle();const violations=(await new AxeBuilder({page:p}).withTags(['wcag2a','wcag2aa','wcag21aa','wcag22aa']).analyze()).violations;
 const overflow=await p.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);scans.push({label,violations:violations.length,overflow});await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(violations,null,2));await p.screenshot({path:path.join(output,`${label}.png`)});assert.deepEqual(violations,[]);assert.equal(overflow,false);await p.setViewportSize({width:1440,height:1080});}
async function journal(p){return p.evaluate(()=>new Promise((resolve,reject)=>{const o=indexedDB.open('brohn-participant',1);o.onerror=()=>reject(o.error);o.onsuccess=()=>{const db=o.result,r=db.transaction('sessions').objectStore('sessions').getAll();r.onsuccess=()=>{resolve(r.result);db.close();};r.onerror=()=>reject(r.error);};}));}
async function participant(alias,{offline=false,lostAck=false}={}){
 const c=await browser.newContext({viewport:{width:1280,height:900}}),p=await c.newPage();active=p;p.on('pageerror',e=>errors.push(e.message));const traffic=[],requests=new Map();let dropped=false;
 await p.route('**/api/events/**',async route=>{const body=route.request().postDataJSON(),encoded=JSON.stringify(body),old=requests.get(body.operation_id);if(old!==undefined)assert.equal(encoded,old,'Exact event retry must preserve operation payload');requests.set(body.operation_id,encoded);
   traffic.push({operation_id:body.operation_id,first:body.events[0].sequence,last:body.events.at(-1).sequence,hash:hash(encoded)});
   if(lostAck&&!dropped&&body.events.some(e=>e.type==='task_event')){const response=await route.fetch();assert.equal(response.status(),200);dropped=true;await route.abort('failed');}else await route.continue();});
 await p.goto(journey.participant_url);await p.getByLabel('Participant alias (required)',{exact:true}).fill(alias);await p.locator('#consent').check();
 const response=p.waitForResponse(r=>r.url().includes('/api/start/')&&r.request().method()==='POST');await p.getByRole('button',{name:'Start study',exact:true}).click();const payload=await(await response).json();
 if(payload.protocol.equipment?.required_codes?.length){await p.getByRole('heading',{name:'Check your task keys',exact:true}).waitFor();for(const code of payload.protocol.equipment.required_codes)await p.keyboard.press(code);}
 await p.getByRole('button',{name:'Begin',exact:true}).click();const compiled=payload.protocol.timeline.find(s=>s.type==='task').task;
 return{c,p,payload,compiled,traffic,getDropped:()=>dropped};
}
try{
 await start();await page.goto(`http://127.0.0.1:${config.researcher_port}/`);await button('Studies').waitFor();
 if(!journey.study_id){
   await button('Start my study').click();await page.getByLabel('Study name',{exact:true}).fill(config.title);await page.locator('input[name="new_template"][value="blank"]').check();await button('Create study').click();await page.waitForFunction(()=>{const f=document.getElementById('study_form_identity');return f?.value.endsWith(':Plan')&&f.value===Shiny.shinyapp.$inputValues.study_form_identity;});await idle();
   await page.locator('#study_description').fill('Original synthetic consumer QA: one fictional Aster product, two attribute pairings, and separate explicit liking. No observed human participant.');
   await page.locator('#study_instructions').fill('Classify the original fictional product and attribute words. Then give a separate explicit liking response. Automated synthetic acceptance only.');
   await page.locator('#consent_text').fill('Original voluntary software walkthrough. These automated inputs are synthetic. Stop whenever you choose. No camera recording.');await page.locator('#debrief_text').fill('Original software QA complete; no individual preference or scientific validity interpretation.');
   await page.waitForFunction(()=>['study_description','study_instructions','consent_text','debrief_text'].every(id=>Shiny.shinyapp.$inputValues[id]===document.getElementById(id)?.value));
   await stage('Tasks');await select('task_profile','Brohn response-window SC-IAT');await button('Add procedure').click();await expect(page.locator('#task_title_1')).toBeVisible();
   await page.locator('#task_title_1').fill('Original Aster response-window task');await page.locator('#task_control_1').fill('One fictional Aster product contrasted against pleasant and unpleasant attributes. This pairing contrast is not a separate control product or causal comparison.');
   await page.locator('#task_rights_1').fill('Original fictional brand and text materials for automated software acceptance; no vendor materials.');await page.locator('#task_category_1_1').fill('Aster product');
   await page.locator('#task_material_1_1').fill('Aster package');await page.locator('#task_material_1_2').fill('Aster display');await page.locator('#task_sciat_language_1').fill('English');
   await scan('three-role-authoring-desktop');await scan('three-role-authoring-390',true);
   await stage('Questions');await page.locator('#question_type').selectOption('rating');await button('Add question').click();await page.locator('#q_prompt_1').fill('How much do you like the original Aster concept?');await stage('Plan');
   const originalFile=await download('Export design','original-sciat.brohn-study.zip'),design=zipDesign(originalFile);journey.study_id=design.id;journey.task_id=design.blocks[0].id;journey.original_design=design;
   assert.ok(design.description.startsWith('Original synthetic consumer QA:')&&design.instructions.startsWith('Classify the original')&&design.consent.text.startsWith('Original voluntary')&&design.debrief.startsWith('Original software QA complete'));
   check('Researcher authors one target and two attributes with fixed named timing and independent liking',design.blocks[0].profile==='sciat-brohn-response-window-im100/1.0'&&design.blocks[0].categories.length===3&&design.questions.length===1&&design.blocks[0].settings.language==='English');
   await button('Save as template').click();await idle();await button('Clone design').click();await page.getByLabel('Name for the new study',{exact:true}).fill(`${config.title} clone`);await button('Create clone').click();await idle();
   const cloned=zipDesign(await download('Export design','cloned-sciat.brohn-study.zip'));journey.clone_id=cloned.id;
   assert.notEqual(cloned.blocks[0].id,design.blocks[0].id);assert.deepEqual(cloned.blocks[0].settings,design.blocks[0].settings);assert.deepEqual(cloned.blocks[0].categories.map(c=>c.role),design.blocks[0].categories.map(c=>c.role));
   await stage('Design library');await page.locator('#import_design_file').setInputFiles(originalFile);await page.locator('#study_title').waitFor();const imported=zipDesign(await download('Export design','reimported-sciat.brohn-study.zip'));journey.imported_id=imported.id;
   assert.notEqual(imported.id,design.id);assert.deepEqual(imported.blocks[0].settings,design.blocks[0].settings);assert.deepEqual(imported.blocks[0].materials.map(m=>m.content),design.blocks[0].materials.map(m=>m.content));
   const s=await snapshot();assert.equal(s.sessions.length,0);assert.equal(s.reports.length,0);check('Template, clone and portable import preserve procedure/material semantics with new design identities and no copied observations',s.templates.length>0);await save();
 }
 await openStudy();await stage('Collect');if(!journey.participant_url){await select('release_origin','Example walkthrough (sample)');await page.locator('#release_alias').check();await page.locator('#release_quota').fill('10');await button('Release participant study').click();journey.participant_url=await page.getByRole('link',{name:'Open participant study',exact:true}).getAttribute('href');await save();}
 let snap=await snapshot();journey.runs??={};
 journey.browser_evidence??={};for(const [index,alias]of aliases.entries()){
   let prior=snap.sessions.find(s=>s.run.participant_alias===alias);
   if(prior){assert.equal(prior.run.completion_status,'completed','Resume must not create a replacement for a partial original administration');journey.runs[alias]=prior.run.id;
     if(!journey.browser_evidence[alias]){for(const name of (await fs.readdir(folder)).filter(n=>n.startsWith('browser-')).sort()){
       const candidate=path.join(folder,name,`${alias}-browser.json`);try{const evidence=JSON.parse(await fs.readFile(candidate,'utf8'));const record=evidence.records.find(r=>r.run_id===prior.run.id);if(record)assert.deepEqual(record.events,prior.events);const received=new Set(prior.receipts.filter(r=>r.operation==='events').map(r=>r.operation_id));assert.ok(evidence.traffic.length&&evidence.traffic.every(t=>received.has(t.operation_id)));assert.ok(record||evidence.records.length===0);journey.browser_evidence[alias]=candidate;}catch(e){if(e.code!=='ENOENT')throw e;}
     }}assert.ok(journey.browser_evidence[alias]);await save();check(`${alias}: continuation preserves original complete received journal and existing browser evidence`,true);continue;}
   const part=await participant(alias,{lostAck:index===0,offline:index===1}),{p,c,compiled}=part;let n=0;
   assert.equal(compiled.assignment.initial_mapping,part.payload.protocol.allocation_index%2?'A':'B');
   for(const t of compiled.timeline){
     if(t.type==='task_instructions'){await p.getByRole('button',{name:'Begin this block',exact:true}).click();continue;}
     const quick=index===3&&n+1===31;
     if(quick){await p.locator('.sciat-stage .sciat-material').waitFor({state:'visible'});await p.keyboard.press(t.correct_code);}
     else await expect.poll(async()=>{const records=await journal(p);return records.some(x=>x.events.some(e=>e.type==='task_event'&&e.payload.kind==='task_trial_started'&&e.payload.data.trial_id===t.id));},{timeout:15000,intervals:[20,40]}).toBe(true);n++;
     if(index===1&&n===10)await c.setOffline(true);
     if(!quick&&n!==3&&!(index===2&&n===30)){const target=(t.mapping==='A'?400:600)+(t.trial_index%5)*19;const records=await journal(p);const event=records.flatMap(x=>x.events).find(e=>e.type==='task_event'&&e.payload.kind==='task_trial_started'&&e.payload.data.trial_id===t.id);
       await p.waitForFunction(deadline=>performance.now()>=deadline,Number(event.payload.data.clock.value)+target);await p.keyboard.press(n===1||n===29?(t.correct_code==='KeyE'?'KeyI':'KeyE'):t.correct_code);}
     await expect.poll(async()=>{const records=await journal(p);return records.some(x=>x.events.some(e=>e.type==='task_event'&&e.payload.kind==='task_trial_finished'&&e.payload.data.trial_id===t.id));},{timeout:15000,intervals:[20,40]}).toBe(true);
     if(index===1&&n===36)await c.setOffline(false);if(n%24===0)console.log(`${alias}: ${n}/192 actual participant trials`);
   }
   await p.getByRole('heading',{name:'How much do you like the original Aster concept?',exact:true}).waitFor();const beforeFinish=await journal(p);await p.getByRole('radio',{name:index===0?'4':'5',exact:true}).check();await p.getByRole('button',{name:'Continue',exact:true}).click();await p.getByRole('heading',{name:'Thank you. Your responses are saved.',exact:true}).waitFor({timeout:60000});
   const retained=await journal(p);assert.deepEqual(retained,[],'Confirmed saved completion clears its local session journal');await fs.writeFile(path.join(output,`${alias}-browser.json`),JSON.stringify({run_id:part.payload.run_id,before_finish:beforeFinish,records:retained,traffic:part.traffic,lost_ack:part.getDropped()},null,2));
   if(index===0)assert.ok(part.getDropped()&&part.traffic.some((t,i)=>part.traffic.slice(0,i).some(o=>o.operation_id===t.operation_id&&o.hash===t.hash)));
   journey.runs[alias]=part.payload.run_id;journey.browser_evidence[alias]=path.join(output,`${alias}-browser.json`);await save();await c.close();active=page;snap=await snapshot();
   prior=snap.sessions.find(s=>s.run.id===part.payload.run_id);assert.equal(prior.run.completion_status,'completed');assert.equal(prior.run.transfer_status,'saved');assert.equal(prior.events.filter(e=>e.type==='task_event'&&e.payload.kind==='task_trial_finished').length,192);
   if(index===2||index===3){const finished=prior.events.filter(e=>e.type==='task_event'&&e.payload.kind==='task_trial_finished').map(e=>e.payload.data);if(index===2)assert.equal(finished[29].outcome,'omission');else assert.ok(finished[30].response_ms<350);}
   check(`${alias}: full named procedure and liking reach durable completion with ${index===0?'exact lost-ack retry':index===1?'offline journal recovery':index===2?'actual scored omission':'actual scored fast response'}`,true);
 }
 // A separate genuinely interrupted administration preserves its own received evidence.
 snap=await snapshot();if(!snap.sessions.some(s=>s.run.participant_alias==='ORIGINAL-SCIAT-REFRESH')){
   const part=await participant('ORIGINAL-SCIAT-REFRESH'),t=part.compiled.timeline.find(t=>t.type==='task_trial');await part.p.getByRole('button',{name:'Begin this block',exact:true}).click();
   await expect.poll(async()=>{const r=await journal(part.p);return r.some(x=>x.events.some(e=>e.type==='task_event'&&e.payload.kind==='task_trial_started'&&e.payload.data.trial_id===t.id));},{intervals:[20,40]}).toBe(true);
   await part.p.reload();await part.p.getByRole('heading',{name:'The study was interrupted.',exact:true}).waitFor({timeout:60000});await part.c.close();active=page;
 }
 snap=await drain();const partial=snap.sessions.find(s=>s.run.participant_alias==='ORIGINAL-SCIAT-REFRESH');assert.equal(partial.run.completion_status,'interrupted');assert.ok(!partial.events.some(e=>e.type==='step_finished'&&e.phase==='implicit_task'));
 check('Actual refresh retains an interrupted administration without fake completed task or score eligibility',true);
 journey.native_reports={};for(const [alias,id]of Object.entries(journey.runs)){
   snap=await snapshot();const report=snap.reports.find(r=>r.body.provenance?.runs?.some(run=>run.run_id===id));assert.ok(report,`Saved original report for ${id}`);journey.native_reports[alias]=report.id;await save();
   await openStudy();await stage('Results');await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${report.id}"']`).click();await idle();await drain();
   await expect(page.locator('#brohn-main')).toContainText('What supports this SC-IAT score');await scan(`${alias}-report-desktop`);await scan(`${alias}-report-390`,true);
   const reportPath=await download('JSON + provenance',`${alias}-report.json`),scorePath=await download('Download task scores CSV',`${alias}-scores.csv`);assert.deepEqual(JSON.parse(await fs.readFile(reportPath,'utf8')),report.body);
   await button('Open task plots').click();await expect(page.locator('#task_plot_source')).toBeVisible();await page.waitForFunction(()=>{const f=document.getElementById('task_plot_catalog_identity');return f&&Shiny.shinyapp.$inputValues.task_plot_catalog_identity===f.value;});await button('Show complete saved source').click();await expect(page.locator('#task_plot_view h2')).toBeVisible();
   const full=JSON.parse(await fs.readFile(await download('Download all task values + provenance',`${alias}-plot-source.json`),'utf8'));assert.equal(full.selected_rows.length,192);
   await download('Download chronology SVG',`${alias}-chronology.svg`);await download('Download every selected row CSV',`${alias}-all-trials.csv`);await scan(`${alias}-plots-390`,true);
   check(`${alias}: researcher reviews immutable score, all192 source positions and complete numerical/SVG exports`,true);
 }
 // Actual native interchange, reviewed intake and distinct-person aggregation.
 journey.imports??={};for(const [alias,runId]of Object.entries(journey.runs)){
   await openStudy();await stage('Collect');
   const command=page.locator('[data-brohn-event="view_run_protocol"]').filter({visible:true});
   const exact=await command.evaluateAll((nodes,id)=>nodes.findIndex(n=>JSON.parse(n.getAttribute('data-brohn-value')).run_id===id),runId);assert.ok(exact>=0);await command.nth(exact).click();
   await page.getByRole('dialog',{name:'Assigned participant protocol',exact:true}).waitFor();await page.getByText('Export original task trials',{exact:true}).click();
   const binding=JSON.parse(await page.locator('#run_task_selection').inputValue());assert.equal(binding.task_id,journey.task_id);assert.equal(binding.run_id,runId);assert.match(binding.protocol_hash,/^[a-f0-9]{64}$/);
   const trials=await download('Download task trials CSV',`${alias}-native-trials.csv`),registry=await download('Download task registry JSON',`${alias}-native-registry.json`),notesPath=await download('Download task export notes JSON',`${alias}-native-notes.json`),notes=JSON.parse(await fs.readFile(notesPath,'utf8'));
   await button('Close protocol').click();await expect(page.getByRole('dialog')).toHaveCount(0);
   let state=await snapshot(),saved=journey.imports[alias];if(saved&&!saved.report_id){const existing=state.reports.filter(r=>r.body.dataset_id===saved.dataset_id);assert.ok(existing.length<=1,'Original import continuation must identify one exact existing result');if(existing.length){saved.report_id=existing[0].id;await save();}}
   if(!saved){
     await stage('Data library');await page.getByLabel('Dataset name',{exact:true}).fill(`${alias} original native summaries`);await selectValue('dataset_modality','implicit');await selectValue('dataset_origin','sample');
     const intake=await importTransferredSource(page,trials,{onSubmitted:async()=>{await expect.poll(()=>jobRows().some(j=>j.operation==='ingest_source'&&j.status==='queued'),{intervals:[100,300]}).toBe(true);await drain();}});
     saved={dataset_id:intake.dataset_identity.split(':')[0]};journey.imports[alias]=saved;await save();
   }else{
     await stage('Data library');await page.getByLabel('Search datasets',{exact:true}).fill(`${alias} original native summaries`);await page.locator(`[data-brohn-event="open_dataset"][data-brohn-value='"${saved.dataset_id}"']`).click();await expect(page.locator('#dataset_form_identity')).toHaveValue(new RegExp(`^${saved.dataset_id}:`));
   }
   if(!saved.report_id){
     await page.locator('#map_study-selectized').fill(config.title);await page.locator(`.selectize-dropdown:visible [data-value="${journey.study_id}"]`).click();
     const original=state.sessions.find(s=>s.run.id===runId),release=state.releases.find(d=>d.id===original.run.deployment_id);await page.locator('#map_study_revision-selectized').waitFor();await selectValue('map_study_revision',String(release.design_revision));
     await page.locator('#map_task_source_collection_id').fill(notes.source_collection_id);await page.locator('#map_task_origin_statement').fill('Actual original automated browser journal exported as trial summaries. Separate fictional aliases denote two independently driven software administrations, not observed human participants.');
     await page.locator('#task_registry_upload').setInputFiles(registry);await expect(page.locator('#task_mapping_registry .progress-bar')).toHaveText('Upload complete');await button('Use this protocol file').click();
     await page.waitForFunction(()=>document.getElementById('task_registry_identity')?.value===Shiny.shinyapp.$inputValues.task_registry_identity);
     await selectValue('map_task_source_rt_definition',notes.declarations.source_rt_definition);await selectValue('map_task_terminal_response_rule',notes.declarations.terminal_response_rule);await button('Confirm mapping and analyse').click();
     await expect.poll(()=>jobRows().some(j=>j.operation==='analyse_dataset'&&j.request.dataset_id===saved.dataset_id),{intervals:[100,300]}).toBe(true);state=await drain();
     const imported=state.reports.find(r=>r.body.dataset_id===saved.dataset_id);assert.ok(imported);saved.report_id=imported.id;await save();
   }
   state=await snapshot();const imported=state.reports.find(r=>r.id===saved.report_id),native=state.reports.find(r=>r.id===journey.native_reports[alias]);
   const a=imported.body.analysis.task_attempts[0];assert.equal(a.evidence_level,'declared_trial_summary');assert.equal(a.timing_quality.journal_replayed,false);assert.equal(a.responses.length,192);assert.equal(a.trial_audit.length,192);
   assert.equal(a.score.metrics[0].value,native.body.analysis.task_scores[0].metrics[0].value);assert.equal(a.participant_id,alias);
   await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${saved.report_id}"']`).click();await idle();await download('JSON + provenance',`${alias}-imported-report.json`);await download('Download task scores CSV',`${alias}-imported-scores.csv`);
   check(`${alias}: native trial/registry exports reimport with exact score and explicitly declared-summary evidence`,true);
 }
 await openStudy();await stage('Results');if(!journey.cohort_id){
   await button('Review task participants').click();await page.getByRole('dialog',{name:'Summarise task participants',exact:true}).waitFor();await idle();const selectId=await page.getByLabel('Saved task reports',{exact:true}).getAttribute('id');
   await page.waitForFunction(id=>{const e=document.getElementById(id.replace(/-selectized$/,''));return e?.selectize&&typeof e.selectize.settings.load==='function'&&Object.hasOwn(Shiny.shinyapp.$inputValues,e.id);},selectId);
   for(const alias of aliases.slice(0,2)){const saved=journey.imports[alias],field=page.locator(`[id="${selectId}"]`);await field.click();await field.fill(saved.report_id);await expect(field).toHaveValue(saved.report_id);await page.locator(`.selectize-dropdown:visible [data-value="${saved.report_id}"]`).click();await page.waitForFunction(({id,value})=>document.getElementById(id.replace(/-selectized$/,'')).selectize.items.includes(value),{id:selectId,value:saved.report_id});}
   await button('Review administrations').click();await page.getByRole('dialog',{name:'Review task membership and people',exact:true}).waitFor();
   await page.getByLabel("I reviewed these person and visit links against the study's participant records",{exact:true}).check();await page.getByLabel('Identity evidence and notes (required when linking originally unlinked codes)',{exact:true}).fill('Two separately driven original browser contexts with distinct synthetic aliases and native run IDs. No repeated-source copy is treated as an additional person. This is software QA, not research observations.');
   await page.getByLabel('Name this selection and repeat plan',{exact:true}).fill('Original two-administration SC-IAT descriptive comparison');await button('Save task participant report').click();
   await expect.poll(()=>jobRows().some(j=>j.operation==='analyse_task_cohort'),{intervals:[100,300]}).toBe(true);snap=await drain();journey.cohort_id=snap.reports.find(r=>r.body.analysis.schema==='brohn-task-cohort/1.0').id;await save();await openStudy();await stage('Results');
 }
 await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${journey.cohort_id}"']`).click();await idle();await download('JSON + provenance','cohort-report.json');await button('Open task plots').click();await page.waitForFunction(()=>{const f=document.getElementById('task_plot_catalog_identity');return f&&Shiny.shinyapp.$inputValues.task_plot_catalog_identity===f.value;});await button('Show complete saved source').click();await expect(page.locator('#task_plot_view h2')).toBeVisible();
 const people=JSON.parse(await fs.readFile(await download('Download all task values + provenance','cohort-plot-source.json'),'utf8'));assert.equal(people.selected_rows.length,2);await download('Download every selected row CSV','cohort-people.csv');await scan('cohort-person-values-390',true);check('Reviewed source identities produce two equally weighted person records and complete descriptive exports',true);
 snap=await snapshot();await fs.writeFile(path.join(output,'before-reopen.json'),JSON.stringify(snap,null,2));await stop();await start();await page.goto(`http://127.0.0.1:${config.researcher_port}/`);await openStudy();await stage('Results');
 const firstId=Object.values(journey.native_reports)[0];await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${firstId}"']`).click();await idle();const fresh=await download('JSON + provenance','reopened-report.json');assert.deepEqual(JSON.parse(await fs.readFile(fresh,'utf8')),snap.reports.find(r=>r.id===firstId).body);
 const final=await snapshot();assert.deepEqual(final.sessions,snap.sessions);assert.deepEqual(final.reports,snap.reports);assert.ok(final.report_integrity.every(r=>r.exact));assert.deepEqual(await hashes(),startHashes);check('Restart and reopen preserve received evidence and native result bytes',true);
 let beforeFix=null;try{beforeFix=JSON.parse(await fs.readFile(path.join(folder,'first-two-before-null-fix.json'),'utf8'));}catch(e){if(e.code!=='ENOENT')throw e;}if(beforeFix){for(const r of beforeFix.reports)assert.deepEqual(final.reports.find(x=>x.id===r.id),r);for(const s of beforeFix.sessions)assert.deepEqual(final.sessions.find(x=>x.run.id===s.run.id),s);check('Scorer serialization repair leaves all first-phase reports and received sessions unchanged',true);}
 assert.deepEqual(errors,[]);await fs.writeFile(path.join(output,'final-snapshot.json'),JSON.stringify(final,null,2));await fs.writeFile(path.join(output,'results.json'),JSON.stringify({passed:true,checks,scans,source_hashes:startHashes,journey,errors,scientific_claim:'Software evidence and original synthetic browser inputs; physical timing and construct validity are not established.'},null,2));console.log(JSON.stringify({passed:true,checks:checks.length,output}));
}catch(e){await active?.screenshot({path:path.join(output,'failure.png')}).catch(()=>{});if(active?.url().startsWith(`http://127.0.0.1:${config.participant_port}/`))await fs.writeFile(path.join(output,'failure-browser-journal.json'),JSON.stringify(await journal(active).catch(()=>[]),null,2));await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:e.stack,checks,scans,errors,journey,text:await active?.locator('body').innerText().catch(()=>'(closed)'),logs},null,2));throw e;}
finally{await browser.close();await stop();await fs.writeFile(path.join(output,'logs.json'),JSON.stringify(logs,null,2));}
