// Actual researcher author/reuse -> full participant procedures -> native saved reports.
// Original synthetic materials and automated keyboard input; no human/physical timing claims.
import assert from 'node:assert/strict';import fs from 'node:fs/promises';import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';import {createHash} from 'node:crypto';
import {chromium,expect as baseExpect} from '@playwright/test';import AxeBuilder from '@axe-core/playwright';
import {importTransferredSource} from './helpers/source-import.mjs';
const folder=path.resolve(process.argv[2]);assert.ok(path.basename(folder).startsWith('brohn-researcher-sciat-window-'));
const config=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8')),output=path.join(folder,`browser-${Date.now()}`);await fs.mkdir(output);
await fs.copyFile('tests/researcher-sciat-window-review.mjs',path.join(output,'executed-harness.mjs'));
const aliases=['ORIGINAL-SCIAT-001','ORIGINAL-SCIAT-002','ORIGINAL-SCIAT-EDGE','ORIGINAL-SCIAT-FAST'];
const expect=baseExpect.configure({timeout:30000}),r=path.resolve('../../work/native-r/bin/Rscript.exe'),python=path.resolve('../../work/tooling/methods-venv/Scripts/python.exe');
const env={...process.env,R_LIBS_USER:path.resolve('../../work/r-library-brohn-restore'),LC_ALL:'C',BROHN_PUBLICATION_PYTHON:python,BROHN_PUBLICATION_NATIVE_MANIFEST:path.resolve('../../work/tooling/brohn-native/publication-guard.json')};
const hash=b=>createHash('sha256').update(b).digest('hex'),checks=[],scans=[],errors=[],logs={researcher:'',participant:'',workers:[]};
const sourcePaths=['R/platform-sciat-window.R','R/platform-sciat-window-delivery.R','R/platform-sciat-window-score.R','R/platform-sciat-window-views.R','R/platform-sciat-window-candidate.R',
 'R/platform-core.R','R/platform-methods.R','R/platform-collection-routes.R','R/platform-task-evidence.R','R/platform-task-import.R','R/platform-task-plots.R','R/platform-task-plot-views.R','R/platform-task-cohort.R',
 'R/platform-load.R','R/platform-app.R','R/platform-jobs.R','R/platform-delivery.R','scripts/analysis-worker.R','www/participant/sciat-window-core.js','www/participant/sciat-window.js'];
const hashes=async()=>Object.fromEntries(await Promise.all(sourcePaths.map(async p=>[p,hash(await fs.readFile(p))]))),startHashes=await hashes();
await fs.writeFile(path.join(output,'source-hashes.json'),JSON.stringify(startHashes,null,2));
let services=[],worker=null,active,journey={};try{journey=JSON.parse(await fs.readFile(path.join(folder,'journey.json'),'utf8'));}catch(e){if(e.code!=='ENOENT')throw e;}
const save=()=>fs.writeFile(path.join(folder,'journey.json'),JSON.stringify(journey,null,2));
const check=(name,ok)=>{assert.ok(ok,name);checks.push(name);console.log(`PASS ${name}`);};
function helper(mode){const p=spawnSync(r,['--vanilla','tests/fixtures/researcher-sciat-window.R',mode,folder],{env,windowsHide:true,encoding:'utf8',maxBuffer:32*1024**2});assert.equal(p.status,0,p.stderr||p.stdout);}
async function snapshot(){helper('inspect');return JSON.parse(await fs.readFile(path.join(folder,'snapshot.json'),'utf8'));}
function jobRows(){const p=spawnSync(python,['-c',"import sqlite3,json,pathlib,sys;s=sqlite3.connect(pathlib.Path(sys.argv[1]).resolve().as_uri()+'?mode=ro',uri=True);s.row_factory=sqlite3.Row;rows=[dict(r) for r in s.execute('SELECT id,operation,status,attempt,request_json FROM jobs ORDER BY created_at,id')];[r.update(request=json.loads(r.pop('request_json'))) for r in rows];print(json.dumps(rows));s.close()",path.join(config.workspace,'catalog.sqlite')],{windowsHide:true,encoding:'utf8',maxBuffer:8*1024**2});assert.equal(p.status,0,p.stderr);return JSON.parse(p.stdout);}
async function start(){for(const role of['researcher']){await fs.unlink(path.join(folder,`stop.${role}`)).catch(e=>{if(e.code!=='ENOENT')throw e;});
 const p=spawn(r,['--vanilla','tests/fixtures/researcher-sciat-window.R',role,folder],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});for(const s of[p.stdout,p.stderr])s.on('data',b=>logs[role]+=b);services.push({role,p});}
 for(const port of[config.researcher_port])await expect.poll(async()=>{for(const s of services)if(s.p.exitCode!==null)throw Error(logs[s.role]);try{return(await fetch(`http://127.0.0.1:${port}/`)).status<500;}catch{return false;}},{timeout:90000,intervals:[300,700,1000]}).toBe(true);}
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


// This read-only researcher reopen does not serve or exercise participant runner code.
const accepted=path.resolve(process.argv[3]);assert.equal(path.dirname(accepted),folder);
const original=JSON.parse(await fs.readFile(path.join(accepted,'final-snapshot.json'),'utf8'));
try{
 await start();await page.goto(`http://127.0.0.1:${config.researcher_port}/`);await button('Studies').waitFor();
 const jobs=jobRows();assert.equal(jobs.length,13);assert.ok(jobs.every(j=>j.status==='succeeded'&&j.attempt===1));
 for(const [label,id,prior]of (process.argv.includes('--cohort-only')?[]:[['FAST',journey.native_reports['ORIGINAL-SCIAT-FAST'],'ORIGINAL-SCIAT-FAST']]).concat([['cohort',journey.cohort_id,'cohort']])){
  await openStudy();await stage('Results');await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${id}"']`).click();await idle();
  await button('Open task plots').click();await page.waitForFunction(()=>{const f=document.getElementById('task_plot_catalog_identity');return f&&Shiny.shinyapp.$inputValues.task_plot_catalog_identity===f.value;});await button('Show complete saved source').click();await expect(page.locator('#task_plot_view h2')).toBeVisible();
  const data=await download('Download all task values + provenance',`${label}-values.json`);assert.deepEqual(JSON.parse(await fs.readFile(data,'utf8')),JSON.parse(await fs.readFile(path.join(accepted,`${prior}-plot-source.json`),'utf8')));
  const csv=await download('Download every selected row CSV',`${label}-values.csv`);assert.equal(hash(await fs.readFile(csv)),hash(await fs.readFile(path.join(accepted,label==='FAST'?`${prior}-all-trials.csv`:'cohort-people.csv'))));
  const svg=await download(label==='FAST'?'Download chronology SVG':'Download person outcomes SVG',`${label}-chronology.svg`);if(label==='FAST'){const text=await fs.readFile(svg,'utf8');assert.ok(text.includes('Grey = non-scoring position; square = unavailable')&&!text.includes('Grey = non-scoring block'));}
  const heading=page.locator('#task_plot_view').getByRole('heading',{name:label==='FAST'?'Trial chronology':'Individual values',exact:true});
  await page.setViewportSize({width:1440,height:1080});await heading.scrollIntoViewIfNeeded();await scan(`${label}-visible-plot-desktop`);
  await page.setViewportSize({width:390,height:844});await heading.scrollIntoViewIfNeeded();await scan(`${label}-visible-plot-390`,true);
  if(label==='cohort'){
   await page.setViewportSize({width:390,height:844});const region=page.getByRole('region',{name:'Exact person outcomes and metric-specific support; scroll horizontally for more columns',exact:true});await region.scrollIntoViewIfNeeded();await region.getByRole('columnheader',{name:'value',exact:true}).scrollIntoViewIfNeeded();await scan('cohort-visible-numerical-390',true);
   const rows=region.locator('tbody tr');await expect(rows).toHaveCount(2);await region.screenshot({path:path.join(output,'cohort-numerical-region-390.png')});
  }
  check(`${label}: actual visible plot and complete numerical source remain exact after final wording`,true);
 }
 const final=await snapshot();assert.deepEqual(final.sessions,original.sessions);assert.deepEqual(final.reports,original.reports);assert.deepEqual(jobRows(),jobs);assert.deepEqual(await hashes(),startHashes);assert.deepEqual(errors,[]);
 check('Read-only visual reopen adds zero jobs and changes no received session, report or source',true);
 await fs.writeFile(path.join(output,'results.json'),JSON.stringify({passed:true,checks,scans,source_hashes:startHashes,accepted,accepted_receipt_hash:hash(await fs.readFile(path.join(accepted,'results.json'))),jobs_before:jobs,jobs_after:jobRows(),errors},null,2));console.log(JSON.stringify({passed:true,checks:checks.length,scans:scans.length,output}));
}catch(e){await page.screenshot({path:path.join(output,'failure.png')}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:e.stack,checks,scans,errors,text:await page.locator('body').innerText().catch(()=>'(closed)')},null,2));throw e;}
finally{await browser.close();await stop();await fs.writeFile(path.join(output,'logs.json'),JSON.stringify(logs,null,2));}
