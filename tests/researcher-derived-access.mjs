// Actual HTTP download revocation; no scientific processing or original edits.
import assert from 'node:assert/strict';import fs from 'node:fs/promises';import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';import {createHash} from 'node:crypto';
import {chromium,expect} from '@playwright/test';import AxeBuilder from '@axe-core/playwright';
const folder=path.resolve(process.argv[2]);assert.ok(path.basename(folder).startsWith('brohn-derived-access-'));
const config=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
const output=path.join(folder,`browser-${Date.now()}`);await fs.mkdir(output);
const rscript=path.resolve('../../work/native-r/bin/Rscript.exe'),env={...process.env,LC_ALL:'C',R_LIBS_USER:path.resolve('../../work/r-library-brohn-restore'),
 BROHN_PUBLICATION_PYTHON:path.resolve('../../work/tooling/methods-venv/Scripts/python.exe'),BROHN_PUBLICATION_NATIVE_MANIFEST:path.resolve('../../work/tooling/brohn-native/publication-guard.json')};
const files=['R/platform-app.R','R/platform-data-views.R','R/platform-library.R','R/platform-signal.R','R/platform-audio-extraction.R','www/platform-ui.js','www/brohn.css'];
const hash=b=>createHash('sha256').update(b).digest('hex');
const hashes=async()=>Object.fromEntries(await Promise.all(files.map(async p=>[p,hash(await fs.readFile(p))])));
const started=await hashes(),checks=[],responses=[],scans=[],errors=[];let log='';
const helper=mode=>{const r=spawnSync(rscript,['--vanilla','tests/fixtures/researcher-derived-access.R',mode,folder],{env,windowsHide:true,encoding:'utf8'});assert.equal(r.status,0,r.stderr||r.stdout);};
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log('PASS',label);};
await fs.rm(path.join(folder,'stop.researcher'),{force:true});
const server=spawn(rscript,['--vanilla','tests/fixtures/researcher-derived-access.R','researcher',folder],{env,windowsHide:true});
server.stdout.on('data',x=>log+=x);server.stderr.on('data',x=>log+=x);
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
const base='http://127.0.0.1:3935/';
const button=name=>page.getByRole('button',{name,exact:true});
async function idle(){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy'));}
async function openDataset(){await button('Data library').click();await page.getByLabel('Search datasets',{exact:true}).fill(config.dataset_title);
 await page.locator(`[data-brohn-event="open_dataset"][data-brohn-value='"${config.dataset_id}"']`).click();await expect(page.getByRole('heading',{name:config.dataset_title,exact:true})).toBeVisible({timeout:20000});await idle();}
async function openReport(){await openDataset();await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${config.report_id}"']`).click();await expect(page.locator('#report_download')).toHaveAttribute('href',/session\//,{timeout:20000});await idle();}
async function url(id){await expect(page.locator('#'+id)).toHaveAttribute('href',/session\//,{timeout:20000});return new URL(await page.locator('#'+id).getAttribute('href'),base).href;}
async function read(id,link){const r=await context.request.get(link);const b=await r.body();responses.push({id,status:r.status(),bytes:b.length,sha256:hash(b)});return {status:r.status(),body:b};}
async function scan(label){await page.evaluate(()=>window.scrollTo({top:0,behavior:'instant'}));const violations=(await new AxeBuilder({page}).analyze()).violations;const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);scans.push({label,violations:violations.length,overflow});await fs.writeFile(path.join(output,label+'-axe.json'),JSON.stringify(violations,null,2));await page.screenshot({path:path.join(output,label+'.png'),fullPage:true});assert.equal(violations.length,0);assert.equal(overflow,false);}
try{
 await expect.poll(async()=>{if(server.exitCode!==null)throw Error(log);try{return(await fetch(base)).ok;}catch{return false;}},{timeout:60000}).toBe(true);
 await page.goto(base);await openReport();
 const ids=['report_html','report_csv','report_download','report_artifact'],links={},before={};
 for(const id of ids){links[id]=await url(id);before[id]=await read(id,links[id]);assert.equal(before[id].status,200);assert.ok(before[id].body.length>0);}
 check(true,'Original HTML, CSV, JSON and full processed artifact are available with current parent authority');
 await scan('authorized-report-desktop');
 helper('revoke');
 for(const id of ids){const r=await read(id,links[id]);assert.ok(r.status>=400);assert.notEqual(hash(r.body),hash(before[id].body));}
 check(true,'Every retained report download URL refuses a subsequently revoked original parent');
 await expect(page.getByRole('heading',{name:'Welcome back to your research.',exact:true})).toBeVisible({timeout:10000});
 await expect(page.locator('#platform_error')).toContainText(/source|report|project|unavailable/i);
 await expect(page.getByRole('heading',{name:config.report_title,exact:true})).toHaveCount(0);
 check(true,'The open report clears with an actionable source-access message');
 helper('restore');await openReport();
 for(const id of ids){const r=await read(id,await url(id));assert.equal(r.status,200);assert.equal(hash(r.body),hash(before[id].body));}
 check(true,'Restoring authority reopens all exact unchanged report exports without rescoring');
 await openDataset();const wavLink=await url('dataset_original_download'),wav=await read('derived-wav',wavLink);assert.equal(wav.status,200);assert.equal(hash(wav.body),config.derived_source_hash);
 check(true,'The dataset download exposes the exact complete derived WAV while authorized');
 helper('revoke');const denied=await read('revoked-derived-wav',wavLink);assert.ok(denied.status>=400);assert.notEqual(hash(denied.body),config.derived_source_hash);
 await expect(page.getByRole('heading',{name:'Welcome back to your research.',exact:true})).toBeVisible({timeout:10000});
 check(true,'Retained derived-WAV URL and its open dataset refuse changed parent access');
 await page.setViewportSize({width:390,height:844});await scan('revoked-home-mobile');
 const dismiss=page.getByRole('button',{name:'Dismiss notification',exact:true});const notifications=await dismiss.count();assert.ok(notifications>0);
 await dismiss.first().focus();await page.keyboard.press('Enter');await expect(dismiss).toHaveCount(notifications-1);
 await expect(page.locator('#brohn-main')).toBeFocused();
 check(true,'Error notifications have a named region and keyboard dismissal returns focus to the workspace');
 helper('restore');helper('verify');check(true,'No new jobs, altered reports, changed original video or changed derived WAV');
 assert.deepEqual(await hashes(),started);assert.deepEqual(errors,[]);
 await fs.writeFile(path.join(output,'results.json'),JSON.stringify({passed:true,checks,responses,scans,source_hashes:started,new_jobs:0,scope:'Actual local researcher HTTP downloads and open-view revocation on copied original synthetic fixtures'},null,2));console.log(JSON.stringify({passed:true,output}));
}catch(e){await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:e.stack,checks,responses,scans,errors,source_hashes:started},null,2));throw e;
}finally{helper('restore');await browser.close();await fs.writeFile(path.join(folder,'stop.researcher'),'Stop only this owned QA researcher service.');await expect.poll(()=>server.exitCode!==null,{timeout:30000}).toBe(true);await fs.writeFile(path.join(output,'researcher.log'),log);}
