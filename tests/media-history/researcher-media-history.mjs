// Prepared connected caller. Invoke only after root announces source stability:
// node <this-file> <prepared-folder> --run-after-freeze
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {appendFileSync} from 'node:fs';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {exerciseMediaHistory} from './researcher-media-history-extension.mjs';
assert.equal(process.argv[3],'--run-after-freeze','Prepared only: await the coordinated source-stable window.');
const folder=path.resolve(process.argv[2]);assert.ok(path.basename(folder).startsWith('brohn-media-history-browser-'));
const runtime=JSON.parse(await fs.readFile(path.join(folder,'runtime.json'),'utf8'));
process.chdir(runtime.app_root);
const require=createRequire(path.join(runtime.app_root,'package.json'));
const {chromium,expect}=require('@playwright/test');
const candidate=path.dirname(fileURLToPath(import.meta.url));
const config=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
const population=JSON.parse(await fs.readFile(path.join(folder,'population-results.json'),'utf8'));
assert.equal(population.passed,true);assert.equal(population.new_scientific_jobs,0);assert.equal(population.new_media_jobs.length,42);
const output=path.join(folder,`browser-${Date.now()}`);await fs.mkdir(output);
const rscript=runtime.rscript,fixture=path.join(candidate,'researcher-media-history-fixture.R');
const env={...process.env,R_LIBS_USER:runtime.r_libs,LC_ALL:'C',
  BROHN_PUBLICATION_PYTHON:runtime.publication_python,
  BROHN_PUBLICATION_NATIVE_MANIFEST:runtime.publication_manifest};
const sourceFiles=['R/platform-media-history.R','R/platform-media-review.R','R/platform-media-review-views.R',
  'R/platform-audio-review.R','R/platform-audio-review-views.R','R/platform-audio-extraction.R',
  'R/platform-app.R','R/platform-load.R','R/platform-data-views.R','R/platform-jobs.R','R/platform-analysis.R',
  'R/platform-hosted-profile.R','scripts/analysis-worker.R','scripts/workers/media_review.py','scripts/workers/media_pixels.py',
  'www/brohn.css','www/platform-ui.js'];
const hash=b=>createHash('sha256').update(b).digest('hex');
const hashes=async()=>Object.fromEntries(await Promise.all(sourceFiles.map(async p=>[p,hash(await fs.readFile(p))])));
const sourceHashes=await hashes(),errors=[],openTimings=[];let service=null,serviceLog='',browser=null,page=null;
function helper(mode){const result=spawnSync(rscript,['--vanilla',fixture,mode,folder],{env,windowsHide:true,encoding:'utf8',maxBuffer:16*1024**2});assert.equal(result.status,0,result.stderr||result.stdout);}
async function snapshot(){helper('inspect');return JSON.parse(await fs.readFile(path.join(folder,'snapshot.json'),'utf8'));}
async function start(){
  await fs.rm(path.join(folder,'stop.researcher'),{force:true});service=spawn(rscript,['--vanilla',fixture,'researcher',folder],{env,windowsHide:true});
  const log=b=>{serviceLog+=b;appendFileSync(path.join(output,'researcher-live.log'),b);};service.stdout.on('data',log);service.stderr.on('data',log);
  await expect.poll(async()=>{if(service.exitCode!==null)throw Error(serviceLog);try{return(await fetch(`http://127.0.0.1:${config.researcher_port}/`)).ok;}catch{return false;}},{timeout:60000}).toBe(true);
}
async function stop(){if(service&&service.exitCode===null){await fs.writeFile(path.join(folder,'stop.researcher'),'Stop only this owned media-history fixture.');await expect.poll(()=>service.exitCode!==null,{timeout:60000}).toBe(true);}}
async function idle(){
  await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&
    ![...document.querySelectorAll('.recalculating')].some(x=>x.getClientRects().length),{},{timeout:60000});
  await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
}
const button=name=>page.getByRole('button',{name,exact:true});
async function openMedia(record){
  await page.goto(`http://127.0.0.1:${config.researcher_port}/`);await button('Data library').click();await idle();
  await page.locator(`[data-brohn-event="open_dataset"][data-brohn-value='"${record.report.body.dataset_id}"']`).click();await idle();
  await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${record.report.id}"']`).click();await idle();
  const audioStart=performance.now();await button('Review original audio').click();
  const summary=page.getByText('Saved audio windows',{exact:true});await expect(summary).toBeVisible({timeout:60000});
  openTimings.push({action:'inline-audio-history-visible',report_id:record.report.id,milliseconds:performance.now()-audioStart});
  if(await summary.locator('..').getAttribute('open')===null)await summary.click();
  await page.locator(`[data-brohn-event="audio_review_reopen"][data-brohn-value='"${record.audio.id}"']`).click();
  await expect(page.getByRole('heading',{name:'Saved audio source review',exact:true})).toBeVisible({timeout:60000});await idle();
  const mediaStart=performance.now();await button('Review video with this audio window').click();await expect(page.getByRole('dialog',{name:'Video and original audio',exact:true})).toBeVisible({timeout:60000});
  await expect(page.locator('#media_review_seconds')).toBeVisible({timeout:60000});await idle();
  openTimings.push({action:'media-modal-controls-settled',report_id:record.report.id,milliseconds:performance.now()-mediaStart});
  await fs.writeFile(path.join(output,'open-timings.json'),JSON.stringify(openTimings,null,2));
}
async function referenceBytes(media,kind){
  const original=media.id===config.original.regular.media.id?config.original.regular:config.original.gap;
  const descriptor=kind==='samples'?original.audio.body.csv_objects.find(x=>x.kind==='audio-source-samples'):
    media.body.artifacts.find(x=>x.kind==='recorded-video-frame');assert.ok(descriptor);
  const value=await fs.readFile(path.join(config.workspace,'objects','sha256',descriptor.hash.slice(0,2),descriptor.hash));
  assert.equal(hash(value),descriptor.hash);return value;
}
try{
  await start();browser=await chromium.launch({channel:runtime.chrome_channel,headless:true});const context=await browser.newContext({viewport:{width:1440,height:1080}});
  page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
  const accepted=await exerciseMediaHistory({page,context,output,regular:config.original.regular,gap:config.original.gap,
    openMedia,restart:async()=>{await stop();await start();},snapshot,referenceBytes});
  const final=await snapshot();assert.deepEqual(await hashes(),sourceHashes);assert.deepEqual(errors,[]);
  await fs.writeFile(path.join(output,'results.json'),JSON.stringify({passed:true,...accepted,sourceHashes,openTimings,
    inherited_jobs:config.inherited_jobs.map(j=>({id:j.id,operation:j.operation,status:j.status,attempt:j.attempt})),
    preparation_jobs:population.new_media_jobs.map(j=>({id:j.id,operation:j.operation,status:j.status,attempt:j.attempt})),
    final_jobs:final.jobs.map(j=>({id:j.id,operation:j.operation,status:j.status,attempt:j.attempt})),
    limits:['Source/generated synthetic video and audio; no hardware synchronization or scientific validity qualification.','This connected corpus is sized for history navigation; arbitrary large-catalog performance is not claimed.']},null,2));
  console.log(JSON.stringify({passed:true,output,checks:accepted.checks.length}));
}catch(error){
  if(page)await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});
  await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,sourceHashes,errors,serviceLog,openTimings,
    body:page?await page.locator('body').innerText().catch(()=>'(closed)'):'(not started)'},null,2));throw error;
}finally{if(browser)await browser.close();await stop();await fs.writeFile(path.join(output,'researcher.log'),serviceLog);}
