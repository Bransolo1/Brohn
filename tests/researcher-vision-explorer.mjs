// Genuine saved-model reports -> connected explorer, recorded pixels and exact exports.
// Four static reference frames per family; no population/hardware/capacity claim.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {spawn,spawnSync} from 'node:child_process';
import {chromium,expect as baseExpect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const expect=baseExpect.configure({timeout:30000});
const folder=path.resolve(process.argv[2]),reference=path.resolve(process.argv[3]);
assert.ok(path.basename(folder).startsWith('brohn-vision-browser-'));
await fs.mkdir(folder,{recursive:true});const output=path.join(folder,`browser-${Date.now()}`),finishIndex=process.argv.indexOf('--finish-inspection');if(finishIndex<0)await fs.mkdir(output);
const r=path.resolve('../../work/native-r/bin/Rscript.exe'),python=path.resolve('../../work/tooling/methods-venv/Scripts/python.exe'),helper='tests/fixtures/researcher-vision-explorer.R';
const env={...process.env,R_LIBS_USER:path.resolve('../../work/r-library-brohn-restore'),LC_ALL:'C',BROHN_PUBLICATION_PYTHON:python,BROHN_QA_PORT:'3885'};
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
function runR(mode){const p=spawnSync(r,['--vanilla',helper,mode,folder,reference],{env,windowsHide:true,encoding:'utf8',timeout:300000});assert.equal(p.status,0,p.stderr||p.stdout);}
function py(code,...args){const p=spawnSync(python,['-B','-c',code,...args],{env,windowsHide:true,encoding:'utf8',timeout:120000,maxBuffer:16*1024*1024});assert.equal(p.status,0,p.stderr||p.stdout);return JSON.parse(p.stdout);}
if(!process.argv.includes('--reuse-fixture'))runR('setup');
await fs.rm(path.join(folder,'stop.request'),{force:true});await fs.rm(path.join(folder,'worker.pause'),{force:true});
const config=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
runR('inspect');const attemptBaselineJobs=JSON.parse(await fs.readFile(path.join(folder,'inspection.json'),'utf8')).jobs.map(j=>j.id);
const sourceFiles=['R/platform-load.R','R/platform-app.R','R/platform-data-views.R','R/platform-vision-explorer-views.R','R/platform-vision-explorer.R','R/platform-vision-frame.R','R/platform-jobs.R','scripts/analysis-worker.R','scripts/workers/vision.py','scripts/workers/vision_frame.py','scripts/workers/vision_explorer.py','www/vision-explorer-ui.js'];
const hashFiles=async()=>Object.fromEntries(await Promise.all(sourceFiles.map(async file=>[file,hash(await fs.readFile(file))])));
const sourceHashes=await hashFiles(),oracles={};
if(finishIndex>=0){
  // Finish only the saved-record inspection after the complete browser path.
  // Preserve its original failure receipt; never relabel it an uninterrupted run.
  const attempt=path.resolve(process.argv[finishIndex+1]);assert.equal(path.dirname(attempt),folder);assert.ok(path.basename(attempt).startsWith('browser-'));
  const failurePath=path.join(attempt,'failure.json'),failureBytes=await fs.readFile(failurePath),failure=JSON.parse(failureBytes),end=(await fs.stat(failurePath)).mtimeMs,start=Number(path.basename(attempt).slice(8));
  assert.ok(failure.error.includes("reading 'source_pts_s'"));assert.equal(failure.checks.length,39);assert.equal(failure.scans.length,7);assert.equal(failure.selections.length,3);assert.deepEqual(failure.errors,[]);
  runR('inspect');const inspection=JSON.parse(await fs.readFile(path.join(folder,'inspection.json'),'utf8')),newJobs=inspection.jobs.filter(j=>Date.parse(j.created_at)>=start&&Date.parse(j.created_at)<=end),independentChecks=[],retainedHashes={};
  for(const scan of failure.scans){assert.equal(scan.violations,0);assert.equal(scan.overflow,false);assert.deepEqual(scan.small,[]);assert.deepEqual(JSON.parse(await fs.readFile(path.join(attempt,scan.label+'-axe.json'),'utf8')),[]);}
  independentChecks.push('All seven retained axe/layout records agree with the completed browser checks');
  for(const [family,c] of Object.entries(config.cases)){
    const actual=inspection.reports[family];assert.equal(actual.hash,c.report_hash);assert.equal(actual.artifact_hash,c.artifact.hash);assert.equal(actual.original_source_hash,c.source.hash);
    const chosen=failure.selections.find(x=>x.family===family),frames=inspection.frames.filter(x=>x.body.request.report_id===c.report_id&&x.body.frame.image.hash===chosen.png_sha256&&x.body.frame.frame.frame_index===3&&x.body.frame.frame.source_pts_s==='2.600000');assert.ok(frames.length);
    for(const [file,digest] of Object.entries(frames[0].body.processing.code_hashes))assert.equal(hash(await fs.readFile(file)),digest,file);
    const source=py("import json,sys;print(json.dumps([{'original_json':line,'row':json.loads(line,parse_int=str,parse_float=str)} for line in open(sys.argv[1],encoding='utf-8',newline='')]))",c.artifact_path);
    assert.equal(await fs.readFile(path.join(attempt,family+'-frame3.json'),'utf8'),source[3].original_json);assert.equal(hash(await fs.readFile(path.join(attempt,family+'-frame3.png'))),chosen.png_sha256);
    const pixels=py("import hashlib,json,subprocess,sys;from PIL import Image;p=subprocess.run(['ffmpeg','-v','error','-nostdin','-noautorotate','-i',sys.argv[1],'-map','0:v:0','-vf','select=eq(n\\,3)','-frames:v','1','-fps_mode','passthrough','-pix_fmt','rgb24','-f','rawvideo','pipe:1'],capture_output=True,check=True);im=Image.open(sys.argv[2]).convert('RGB');raw=im.tobytes();print(json.dumps({'equal':raw==p.stdout,'sha256':hashlib.sha256(raw).hexdigest(),'size':list(im.size)}))",c.source_path,path.join(attempt,family+'-frame3.png'));
    assert.equal(pixels.equal,true);assert.equal(pixels.sha256,chosen.rgb_sha256);assert.deepEqual(pixels.size,[c.parameters.width,c.parameters.height]);independentChecks.push(family+': original source/report/JSONL unchanged; downloaded frame identity, dimensions and independent original RGB bytes agree');
    for(const indices of [[0,1,2,3],[2,3]]){
      const csvPath=path.join(attempt,`${family}-${indices.length}-values.csv`),manifest=JSON.parse(await fs.readFile(path.join(attempt,`${family}-${indices.length}-manifest.json`),'utf8'));
      assert.equal(hash(await fs.readFile(csvPath)),manifest.csv.sha256);assert.equal(manifest.source.report_id,c.report_id);assert.equal(manifest.source.original_source.hash,c.source.hash);assert.equal(manifest.source.artifact.sha256,c.artifact.hash);assert.equal(manifest.metric.id,chosen.metric);assert.ok(manifest.metric.unit);
      const rows=py("import csv,json,sys;print(json.dumps(list(csv.DictReader(open(sys.argv[1],encoding='utf-8',newline='')))))",csvPath);assert.equal(rows.length,indices.length);
      rows.forEach((row,i)=>{const native=source[indices[i]].row;assert.equal(row.frame_index,native.frame_index);assert.equal(row.source_pts_s,native.source_pts_s);assert.equal(row.model_timestamp_ms,native.model_timestamp_ms);assert.equal(row.value,metricValue(native,chosen.metric));});
    }
    independentChecks.push(family+': both retained complete/range CSVs and manifests preserve every original token, clock and source identity');
    const figure=await fs.readFile(path.join(attempt,family+'-figure.html'),'utf8');assert.ok(figure.includes(c.report_id)&&figure.includes('metric_valid_time_s_text')&&figure.includes('displayed_points'));
    independentChecks.push(family+': retained figure preserves report identity and explicit display/support policy');
  }
  const cancelled=newJobs.filter(j=>j.status==='cancelled');assert.equal(cancelled.length,2);assert.deepEqual(cancelled.map(j=>j.operation).sort(),['vision_frame','vision_index']);
  for(const old of cancelled){const retry=inspection.retries.find(x=>x.body.source_job_id===old.id);assert.ok(retry);assert.equal(newJobs.find(j=>j.id===retry.body.new_job_id)?.status,'succeeded');}
  assert.ok(inspection.jobs.every(j=>['cancelled','succeeded'].includes(j.status)));independentChecks.push('Both cancelled browser jobs have explicit successful replacement jobs; no processing remains pending');
  for(const entry of await fs.readdir(attempt)){if(entry==='continuation-inspection.json')continue;const file=path.join(attempt,entry);if((await fs.stat(file)).isFile())retainedHashes[entry]=hash(await fs.readFile(file));}
  assert.equal(hash(await fs.readFile(failurePath)),hash(failureBytes));
  const receipt={schema:'brohn-video-browser-inspection-continuation/1.0',status:'completed_with_separate_inspection',browserAttempt:attempt,originalFailureSha256:hash(failureBytes),originalFailurePreserved:true,browserChecks:failure.checks,scans:failure.scans,selections:failure.selections,independentInspectionChecks:independentChecks,currentSourceHashes:sourceHashes,workerSourceIdentity:'Every retained selected-frame worker code hash matched the current source',browserStartHashSnapshotAvailable:false,browserHashScope:'Current UI source hashes are recorded at continuation; do not claim a retained browser-start hash snapshot or uninterrupted run',originalFixtureJobs:config.baseline_jobs,newJobsDuringBrowserAttempt:newJobs,laterJobsExcluded:inspection.jobs.filter(j=>Date.parse(j.created_at)>end),retainedHashes,reports:inspection.reports,scope:'Four actual pinned-model static-reference frames per family. Browser path and separate closed-store inspection are joined transparently; no human/scientific/hardware, natural-motion or >2000-frame browser qualification.'};
  const destination=path.join(attempt,'continuation-inspection.json');await fs.writeFile(destination,JSON.stringify(receipt,null,2));console.log(JSON.stringify({browserChecks:failure.checks.length,inspectionChecks:independentChecks.length,scans:failure.scans.length,newJobs:newJobs.length,receipt:destination,sha256:hash(await fs.readFile(destination))}));process.exit(0);
}
await fs.writeFile(path.join(output,'start.json'),JSON.stringify({sourceHashes,attemptBaselineJobs,originalFixtureJobs:config.baseline_jobs,fixture:config.workspace},null,2));
for(const [family,c] of Object.entries(config.cases)){
  assert.equal(hash(await fs.readFile(c.artifact_path)),c.artifact.hash);
  oracles[family]=py("import json,sys;rows=[{'original_json':line,'row':json.loads(line,parse_int=str,parse_float=str)} for line in open(sys.argv[1],encoding='utf-8',newline='')];print(json.dumps(rows,ensure_ascii=True))",c.artifact_path);
}
const checks=[],scans=[],children=[],errors=[],selections=[];let log='';
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log('PASS',label);};
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1080},acceptDownloads:true}),page=await context.newPage();
page.on('pageerror',e=>errors.push(e.message));
async function idle(){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&![...document.querySelectorAll('.recalculating')].some(e=>e.getClientRects().length),null,{timeout:120000});await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);}
async function open(family){const c=config.cases[family];await page.getByRole('button',{name:'Data library',exact:true}).click();await page.getByLabel('Search datasets',{exact:true}).fill(c.title);await page.locator(`[data-brohn-event="open_dataset"][data-brohn-value='"${c.dataset_id}"']`).click();await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${c.report_id}"']`).click();await idle();await page.getByRole('button',{name:'Explore video measurements',exact:true}).click();await expect(page.locator('#vision_controls')).toContainText('4 complete analysed frames',{timeout:180000});await expect(page.locator('#vision-explorer')).toHaveAttribute('data-source',new RegExp(c.report_id));await expect(page.locator('#vision_geometry')).toContainText('No recorded frame shown');await idle();}
async function apply(){await page.getByRole('button',{name:'Apply video view',exact:true}).click();await idle();}
async function openFaceLandmarks(){const summary=page.getByText('Exact native landmark values: 478 saved points',{exact:true});if(!await summary.evaluate(e=>e.parentElement.open))await summary.click();}
async function download(label,name){const pending=page.waitForEvent('download',{timeout:180000});await page.getByRole('link',{name:label,exact:true}).click();const d=await pending;assert.equal(await d.failure(),null);const file=path.join(output,name);await d.saveAs(file);return file;}
async function json(label,name){return JSON.parse(await fs.readFile(await download(label,name),'utf8'));}
async function scan(label,narrow,target){await page.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});await idle();await target.scrollIntoViewIfNeeded();await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  const violations=(await new AxeBuilder({page}).analyze()).violations;
  const layout=await page.evaluate(()=>({overflow:document.documentElement.scrollWidth>innerWidth+1,small:[...document.querySelectorAll('#vision-explorer button,#vision-explorer select,#vision-explorer a,#vision-explorer summary')].filter(e=>{const b=e.getBoundingClientRect();return b.width&&b.height&&(b.width<43||b.height<43);}).map(e=>e.textContent)}));
  await fs.writeFile(path.join(output,label+'-axe.json'),JSON.stringify(violations,null,2));const visual=target.locator('svg').first();await visual.scrollIntoViewIfNeeded();await page.screenshot({path:path.join(output,label+'.png')});await visual.screenshot({path:path.join(output,label+'-component.png')});
  scans.push({label,violations:violations.length,...layout});check(!violations.length&&!layout.overflow&&!layout.small.length,label+': accessibility, reflow and44px actions');
}
function nativePoints(row,family){if(family==='hands')return row.hands.hands.flatMap(h=>h.landmarks);return row[family].landmarks;}
function metricValue(row,metric){const [family,part,key]=metric.split('.');if(family==='face')return part==='blendshape'?row.face.blendshapes[key]:row.face.geometry[part];if(family==='pose')return row.pose.geometry[part];return row.hands.hands.find(h=>h.handedness===part).geometry[key];}
async function exportCsv(family,metric,expectedIndices){await page.getByRole('button',{name:'Prepare every selected numeric row',exact:true}).click();await page.getByRole('link',{name:'Download complete selected CSV',exact:true}).waitFor({timeout:180000});const url=new URL(await page.getByRole('link',{name:'Download complete selected CSV',exact:true}).getAttribute('href'),page.url()).href;
  const file=await download('Download complete selected CSV',`${family}-${expectedIndices.length}-values.csv`),manifest=await json('Download CSV source and units manifest',`${family}-${expectedIndices.length}-manifest.json`);
  const rows=py("import csv,json,sys;print(json.dumps(list(csv.DictReader(open(sys.argv[1],encoding='utf-8',newline='')))))",file);
  assert.equal(rows.length,expectedIndices.length);assert.equal(manifest.csv.rows,rows.length);assert.equal(manifest.csv.sha256,hash(await fs.readFile(file)));assert.equal(manifest.source.report_id,config.cases[family].report_id);assert.equal(manifest.metric.id,metric);assert.ok(manifest.metric.unit);
  rows.forEach((x,n)=>{const source=oracles[family][expectedIndices[n]].row;assert.equal(x.frame_index,source.frame_index);assert.equal(x.source_pts_s,source.source_pts_s);assert.equal(x.value,metricValue(source,metric));assert.equal(x.model_timestamp_ms,source.model_timestamp_ms);});
  check(true,`${family}: all ${rows.length} selected CSV rows retain original numeric tokens, PTS, units and source hash`);return url;
}
try{
  for(const mode of ['serve','worker']){const child=spawn(r,['--vanilla',helper,mode,folder],{env,windowsHide:true});children.push(child);child.stdout.on('data',x=>log+=`${mode}: ${x}`);child.stderr.on('data',x=>log+=`${mode}: ${x}`);}
  await expect.poll(async()=>{if(children.some(c=>c.exitCode!==null))throw Error(log);try{return(await fetch(`http://127.0.0.1:${config.port}/`)).status===200;}catch{return false;}},{timeout:60000}).toBe(true);await page.goto(`http://127.0.0.1:${config.port}/`);
  for(const family of ['face','pose','hands']){
    await open(family);
    if(family==='face'){
      await fs.writeFile(path.join(folder,'worker.pause'),'pause');await page.getByRole('button',{name:'Rebuild derived video index',exact:true}).click();
      await page.getByRole('button',{name:'Cancel video job',exact:true}).click();await page.getByRole('button',{name:'Retry video job',exact:true}).waitFor();await page.getByRole('button',{name:'Retry video job',exact:true}).click();await fs.rm(path.join(folder,'worker.pause'),{force:true});
      await expect(page.locator('#vision_controls')).toContainText('4 complete analysed frames',{timeout:180000});await idle();check(true,'Cancelled derived index retry adopts its new completed job and opens current saved observations');
    }
    const c=config.cases[family],metric=await page.locator('#vision_metric').inputValue();check(metric.startsWith(family+'.'),`${family}: complete saved index opens through the actual report entry point`);
    await page.getByLabel('Original frame number (zero-based)',{exact:true}).fill('3');await page.getByRole('button',{name:'Show exact frame',exact:true}).click();await expect(page.locator('#vision_detail')).toContainText('Source PTS 2.600000 s');
    const exact=await fs.readFile(await download('Download exact original frame JSON',family+'-frame3.json'),'utf8');assert.equal(exact,oracles[family][3].original_json);
    const native=nativePoints(oracles[family][3].row,family).filter(p=>Number(p.x)>=0&&Number(p.x)<=1&&Number(p.y)>=0&&Number(p.y)<=1);
    const dots=await page.locator('#vision_geometry svg circle').evaluateAll(elements=>elements.map(e=>({x:Number(e.getAttribute('cx')),y:Number(e.getAttribute('cy'))})));
    assert.equal(dots.length,native.length);dots.forEach((p,i)=>{assert.ok(Math.abs(p.x-Number(native[i].x)*c.parameters.width)<1e-6);assert.ok(Math.abs(p.y-Number(native[i].y)*c.parameters.height)<1e-6);});
    check(true,`${family}: original frame JSON is byte-exact and every overlay point matches its native saved coordinate`);
    if(family==='face'){
      await openFaceLandmarks();const region=page.getByRole('region',{name:'Exact native video landmark tokens; scroll horizontally for more columns',exact:true});
      await expect(region).toContainText(oracles.face[3].row.face.landmarks[0].x);await page.getByRole('button',{name:'Next landmark page',exact:true}).focus();await page.keyboard.press('Enter');await expect(region).toContainText(oracles.face[3].row.face.landmarks[100].x);
      await expect(page.getByRole('button',{name:'Next landmark page',exact:true})).toBeFocused();
      for(let i=0;i<3;i++){await page.getByRole('button',{name:'Next landmark page',exact:true}).click();await expect(page.locator('[data-vision-point-start]')).toHaveAttribute('data-vision-point-start',String(200+i*100));}
      await expect(region).toContainText(oracles.face[3].row.face.landmarks[477].x);await expect(page.getByRole('button',{name:'Next landmark page',exact:true})).toHaveAttribute('aria-disabled','true');await expect(page.locator('#vision_point_page')).toContainText('Showing 78 points beginning at 400');
      await page.getByRole('button',{name:'Previous landmark page',exact:true}).focus();await page.keyboard.press('Enter');await expect(page.locator('[data-vision-point-start]')).toHaveAttribute('data-vision-point-start','300');await expect(page.getByRole('button',{name:'Previous landmark page',exact:true})).toBeFocused();
      check(true,'Keyboard landmark paging retains focus, reaches final point 477 with a disabled end boundary, and returns to page 300');
      await fs.writeFile(path.join(folder,'worker.pause'),'pause');
    }
    await page.getByRole('button',{name:'Prepare exact recorded frame',exact:true}).click();
    if(family==='face'){
      await page.getByRole('button',{name:'Cancel video job',exact:true}).click();await page.getByRole('button',{name:'Retry video job',exact:true}).waitFor();await page.getByRole('button',{name:'Retry video job',exact:true}).click();await fs.rm(path.join(folder,'worker.pause'),{force:true});check(true,'Queued exact frame can be cancelled and retried through current report controls');
    }
    await expect(page.locator('#vision_geometry image')).toHaveCount(1,{timeout:180000});await expect(page.locator('#vision_geometry')).toContainText('Exact recorded frame with saved model landmarks');
    const imageUrl=new URL(await page.locator('#vision_geometry image').getAttribute('href'),page.url()).href,response=await context.request.get(imageUrl);assert.equal(response.status(),200);assert.equal(response.headers()['cache-control'],'no-store');const imageBytes=await response.body();assert.equal(imageBytes.readUInt32BE(16),c.parameters.width);assert.equal(imageBytes.readUInt32BE(20),c.parameters.height);
    const png=await download('Download original frame PNG',family+'-frame3.png');assert.equal(hash(await fs.readFile(png)),hash(imageBytes));
    const pixels=py("import hashlib,json,subprocess,sys;from PIL import Image;source,png=sys.argv[1:];p=subprocess.run(['ffmpeg','-v','error','-nostdin','-noautorotate','-i',source,'-map','0:v:0','-vf','select=eq(n\\,3)','-frames:v','1','-fps_mode','passthrough','-pix_fmt','rgb24','-f','rawvideo','pipe:1'],capture_output=True,check=True);im=Image.open(png).convert('RGB');a=im.tobytes();print(json.dumps({'equal':a==p.stdout,'rgb_sha256':hashlib.sha256(a).hexdigest()}))",c.source_path,png);check(pixels.equal,`${family}: delivered PNG pixels equal independent original-frame3 decode, with original dimensions and no-store delivery`);
    await page.getByLabel('Show saved native landmarks',{exact:true}).uncheck();await expect(page.locator('#vision_geometry svg circle')).toHaveCount(0);await expect(page.locator('#vision_geometry image')).toHaveCount(1);await page.getByLabel('Show saved native landmarks',{exact:true}).check();await expect(page.locator('#vision_geometry svg circle')).toHaveCount(native.length);
    await scan(family+'-image-desktop',false,page.locator('#vision_geometry'));await scan(family+'-image-390',true,page.locator('#vision_geometry'));
    if(family==='face'){await openFaceLandmarks();const region=page.getByRole('region',{name:'Exact native video landmark tokens; scroll horizontally for more columns',exact:true});await region.focus();await page.keyboard.press('ArrowRight');await expect.poll(()=>region.evaluate(e=>e.scrollLeft)).toBeGreaterThan(0);check(true,'Narrow native-landmark table scrolls with keyboard without page overflow');}
    await page.setViewportSize({width:1440,height:1080});const csvUrl=await exportCsv(family,metric,[0,1,2,3]);
    const html=await fs.readFile(await download('Download labelled figure (HTML)',family+'-figure.html'),'utf8');check(html.includes(c.report_id)&&html.includes('Recording-relative time')&&html.includes('metric_valid_time_s_text')&&html.includes('displayed_points'),`${family}: exported accessible figure retains report identity, source units and display/support policy`);
    await page.getByLabel('First recording-relative second (included)',{exact:true}).fill('0.2000000000000000001');await page.getByLabel('Last recording-relative second (included)',{exact:true}).fill('0.6');await apply();await expect(page.locator('#vision_page')).toContainText('2 rows on this page from 2');await expect(page.locator('#vision_detail')).toContainText('Original frame 2');
    assert.equal((await context.request.get(imageUrl)).status(),404);assert.equal((await context.request.get(csvUrl)).status(),404);check(true,`${family}: exact decimal range excludes frame1 and revokes earlier image/CSV URLs`);await exportCsv(family,metric,[2,3]);
    await page.getByLabel('Saved measurement',{exact:true}).selectOption('');await apply();await expect(page.locator('#vision_plot')).toContainText('Frame states only');await expect(page.getByRole('button',{name:'Prepare every selected numeric row',exact:true})).toHaveCount(0);check(true,`${family}: state-only display exposes saved support without a fabricated numeric series`);
    await page.getByLabel('First recording-relative second (included)',{exact:true}).fill('2');await page.getByLabel('Last recording-relative second (included)',{exact:true}).fill('3');await apply();await expect(page.locator('#vision_page')).toContainText('0 rows on this page from 0');await expect(page.locator('#vision_detail')).toBeEmpty();await expect(page.locator('#vision_plot')).toContainText('No analysed frames');check(true,`${family}: empty selected range clears frame/overlay and states no analysed observations`);
    selections.push({family,report_id:c.report_id,frame:3,source_pts_s:'2.600000',png_sha256:hash(imageBytes),rgb_sha256:pixels.rgb_sha256,metric});
  }
  await open('face');await expect(page.locator('#vision_page')).toContainText('4 rows on this page from 4');await expect(page.locator('#vision_geometry image')).toHaveCount(0);check(true,'Navigation/reopen restores the exact original report with new current controls and no stale image');
  await scan('face-plot-390',true,page.locator('#vision_plot'));runR('inspect');const inspection=JSON.parse(await fs.readFile(path.join(folder,'inspection.json'),'utf8'));
  for(const [family,c] of Object.entries(config.cases)){assert.equal(inspection.reports[family].hash,c.report_hash);assert.equal(inspection.reports[family].artifact_hash,c.artifact.hash);assert.equal(inspection.reports[family].original_source_hash,c.source.hash);const selected=selections.find(s=>s.family===family);assert.ok(inspection.frames.some(f=>f.body.frame.image.hash===selected.png_sha256&&f.body.frame.frame.frame_index===3&&f.body.frame.frame.source_pts_s==='2.600000'));}
  assert.deepEqual(await hashFiles(),sourceHashes);assert.ok(inspection.jobs.every(j=>['succeeded','cancelled'].includes(j.status)));
  const newJobs=inspection.jobs.filter(j=>!attemptBaselineJobs.includes(j.id)),cancelled=newJobs.filter(j=>j.status==='cancelled');assert.equal(cancelled.length,2);assert.deepEqual(cancelled.map(j=>j.operation).sort(),['vision_frame','vision_index']);
  for(const job of cancelled){const retry=inspection.retries.find(x=>x.body.source_job_id===job.id);assert.ok(retry);assert.equal(inspection.jobs.find(j=>j.id===retry.body.new_job_id)?.status,'succeeded');}
  check(!errors.length,'Cancelled index and frame have explicit successful retries; all jobs closed, original reports/observations/videos unchanged and no source drift or browser exceptions');
  await fs.writeFile(path.join(output,'results.json'),JSON.stringify({checks,scans,selections,sourceHashes,jobs:inspection.jobs,newJobs,attemptBaselineJobs,originalFixtureJobs:config.baseline_jobs,reports:inspection.reports,scope:'Actual pinned-model static reference reports with four analysed frames per family; connected renderer/recorded pixels/export and native-landmark paging. No human usability, natural-motion accuracy, detector validation, >2000-frame browser or hardware qualification.'},null,2));console.log(JSON.stringify({checks:checks.length,scans:scans.length,output}));
}catch(error){await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,scans,selections,errors,log},null,2));await fs.writeFile(path.join(output,'failure.html'),await page.content());await page.screenshot({path:path.join(output,'failure.png')});throw error;}
finally{await fs.writeFile(path.join(folder,'stop.request'),'stop');await fs.writeFile(path.join(output,'services.log'),log);await browser.close();for(const child of children){if(child.exitCode===null)await Promise.race([new Promise(resolve=>child.once('exit',resolve)),new Promise(resolve=>setTimeout(resolve,10000))]);if(child.exitCode===null)child.kill();}}
