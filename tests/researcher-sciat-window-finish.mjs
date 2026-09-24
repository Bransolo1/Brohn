// Actual researcher author/reuse -> full participant procedures -> native saved reports.
// Original synthetic materials and automated keyboard input; no human/physical timing claims.
import assert from 'node:assert/strict';import fs from 'node:fs/promises';import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';import {createHash} from 'node:crypto';
import {chromium,expect as baseExpect} from '@playwright/test';import AxeBuilder from '@axe-core/playwright';
import {importTransferredSource} from './helpers/source-import.mjs';
const folder=path.resolve(process.argv[2]);assert.ok(path.basename(folder).startsWith('brohn-researcher-sciat-window-'));
const config=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8')),output=path.join(folder,`browser-${Date.now()}`);await fs.mkdir(output);
await fs.copyFile('tests/researcher-sciat-window-finish.mjs',path.join(output,'executed-harness.mjs'));
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

// Exact continuation of previously accepted native/report/import phases. Their
// bytes and source identity remain explicit; they are not claimed as fresh UI.
const priorFolder=path.resolve(process.argv[3]);assert.equal(path.dirname(priorFolder),folder);
const prior=JSON.parse(await fs.readFile(path.join(priorFolder,'failure.json'),'utf8'));
assert.ok(prior.error.includes('reports-selectized-selectized'));
const oldHashes=JSON.parse(await fs.readFile(path.join(priorFolder,'source-hashes.json'),'utf8'));
for(const [file,value]of Object.entries(oldHashes))assert.equal(startHashes[file],value,`Carried source changed: ${file}`);
assert.deepEqual(prior.errors,[]);assert.equal(prior.scans.length,12);assert.ok(prior.scans.every(s=>s.violations===0&&!s.overflow));
const bridge={folder:priorFolder,source_hashes:oldHashes,known_prior_hash_omission:['R/platform-task-plot-views.R'],wording_only_refresh_source:'R/platform-task-plot-views.R',files:{},prior_failure_hash:hash(await fs.readFile(path.join(priorFolder,'failure.json')))};
for(const alias of aliases){
 assert.ok(prior.checks.includes(`${alias}: researcher reviews immutable score, all192 source positions and complete numerical/SVG exports`));
 assert.ok(prior.checks.includes(`${alias}: native trial/registry exports reimport with exact score and explicitly declared-summary evidence`));
 for(const tail of ['report.json','scores.csv','plot-source.json','chronology.svg','all-trials.csv','native-trials.csv','native-registry.json','native-notes.json','imported-report.json','imported-scores.csv']){
  const name=`${alias}-${tail}`,bytes=await fs.readFile(path.join(priorFolder,name));bridge.files[name]=hash(bytes);await fs.writeFile(path.join(output,name),bytes);
 }
}
await fs.writeFile(path.join(output,'carried-evidence.json'),JSON.stringify(bridge,null,2));
try{
 await start();await page.goto(`http://127.0.0.1:${config.researcher_port}/`);await button('Studies').waitFor();
 let snap=await snapshot();const originalJobs=jobRows();assert.equal(originalJobs.length,12);assert.ok(originalJobs.every(j=>j.status==='succeeded'&&j.attempt===1));
 for(const alias of aliases){for(const [kind,id]of [['report',journey.native_reports[alias]],['imported-report',journey.imports[alias].report_id]])assert.deepEqual(JSON.parse(await fs.readFile(path.join(output,`${alias}-${kind}.json`),'utf8')),snap.reports.find(r=>r.id===id).body);}
 check('All carried native and imported report bytes still equal their exact saved sources; twelve existing jobs remain successful at attempt one',true);
 // The shared plot change only clarifies block-colour wording. Reopen the actual
 // FAST source and compare all192 rows and numerical CSV before accepting SVG.
 await openStudy();await stage('Results');await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${journey.native_reports['ORIGINAL-SCIAT-FAST']}"']`).click();await idle();
 await button('Open task plots').click();await page.waitForFunction(()=>{const f=document.getElementById('task_plot_catalog_identity');return f&&Shiny.shinyapp.$inputValues.task_plot_catalog_identity===f.value;});await button('Show complete saved source').click();await expect(page.locator('#task_plot_view h2')).toBeVisible();
 const finalValues=await download('Download all task values + provenance','FAST-final-plot-source.json');assert.deepEqual(JSON.parse(await fs.readFile(finalValues,'utf8')),JSON.parse(await fs.readFile(path.join(output,'ORIGINAL-SCIAT-FAST-plot-source.json'),'utf8')));
 const finalCsv=await download('Download every selected row CSV','FAST-final-all-trials.csv');assert.equal(hash(await fs.readFile(finalCsv)),bridge.files['ORIGINAL-SCIAT-FAST-all-trials.csv']);
 const finalSvg=await download('Download chronology SVG','FAST-final-chronology.svg');const svg=await fs.readFile(finalSvg,'utf8');assert.ok(svg.includes('Grey = non-scoring block; square = unavailable')&&!svg.includes('grey = unscored'));
 await page.locator('#task_plot_view').scrollIntoViewIfNeeded();await scan('FAST-final-plots-desktop');await scan('FAST-final-plots-390',true);assert.equal(jobRows().length,12);
 check('Final wording renders with the same192 raw values and exact numerical CSV; no original analysis reran',true);
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
 assert.deepEqual(errors,[]);await fs.writeFile(path.join(output,'final-snapshot.json'),JSON.stringify(final,null,2));await fs.writeFile(path.join(output,'results.json'),JSON.stringify({passed:true,checks,scans,carried_checks:prior.checks,carried_scans:prior.scans,carried_evidence:bridge,source_hashes:startHashes,journey,errors,scientific_claim:'Software evidence and original synthetic browser inputs; physical timing and construct validity are not established.'},null,2));console.log(JSON.stringify({passed:true,checks:checks.length,output}));
}catch(e){await active?.screenshot({path:path.join(output,'failure.png')}).catch(()=>{});if(active?.url().startsWith(`http://127.0.0.1:${config.participant_port}/`))await fs.writeFile(path.join(output,'failure-browser-journal.json'),JSON.stringify(await journal(active).catch(()=>[]),null,2));await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:e.stack,checks,scans,errors,journey,text:await active?.locator('body').innerText().catch(()=>'(closed)'),logs},null,2));throw e;}
finally{await browser.close();await stop();await fs.writeFile(path.join(output,'logs.json'),JSON.stringify(logs,null,2));}
