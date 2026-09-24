// Actual acoustic report -> source review -> exact exports and saved reopening.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const folder=path.resolve(process.argv[2]);assert.ok(path.basename(folder).startsWith('brohn-audio-browser-'));
const config=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
const output=path.join(folder,`browser-${Date.now()}`);await fs.mkdir(output);
const r=path.resolve('../../work/native-r/bin/Rscript.exe'),python=path.resolve('../../work/tooling/methods-venv/Scripts/python.exe');
const env={...process.env,R_LIBS_USER:path.resolve('../../work/r-library-brohn-restore'),LC_ALL:'C',BROHN_PUBLICATION_PYTHON:python,
  BROHN_PUBLICATION_NATIVE_MANIFEST:path.resolve('../../work/tooling/brohn-native/publication-guard.json')};
const sourceFiles=['R/platform-audio-review.R','R/platform-audio-review-views.R','scripts/workers/audio_review.py','R/platform-app.R','R/platform-load.R','R/platform-data-views.R','R/platform-jobs.R','scripts/analysis-worker.R'];
const hash=b=>createHash('sha256').update(b).digest('hex');
const hashes=async()=>Object.fromEntries(await Promise.all(sourceFiles.map(async f=>[f,hash(await fs.readFile(f))])));
const startHashes=await hashes(),checks=[],scans=[],errors=[],timings=[],logs={serve:'',worker:''},processes={};
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage();
page.on('pageerror',e=>errors.push(e.message));const button=name=>page.getByRole('button',{name,exact:true});
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log('PASS',label);};
function helper(mode){const p=spawnSync(r,['--vanilla','tests/fixtures/researcher-audio-review.R',mode,folder],{env,windowsHide:true,encoding:'utf8',maxBuffer:8*1024**2});assert.equal(p.status,0,p.stderr||p.stdout);}
async function snapshot(){helper('inspect');return JSON.parse(await fs.readFile(path.join(folder,'snapshot.json'),'utf8'));}
async function start(){for(const mode of['serve','worker']){await fs.rm(path.join(folder,mode==='serve'?'stop.request':'stop.worker'),{force:true});
 const child=spawn(r,['--vanilla','tests/fixtures/researcher-audio-review.R',mode,folder],{env,windowsHide:true});processes[mode]=child;
 child.stdout.on('data',b=>logs[mode]+=b);child.stderr.on('data',b=>logs[mode]+=b);}
 await expect.poll(async()=>{if(processes.serve.exitCode!==null)throw Error(logs.serve);try{return(await fetch(`http://127.0.0.1:${config.port}/`)).status===200;}catch{return false;}},{timeout:60000}).toBe(true);}
async function stop(){for(const[mode,p]of Object.entries(processes)){if(p.exitCode===null){await fs.writeFile(path.join(folder,mode==='serve'?'stop.request':'stop.worker'),'Stop only this owned audio QA service.');
 await expect.poll(()=>p.exitCode!==null,{timeout:30000}).toBe(true);}await fs.writeFile(path.join(output,`${mode}.log`),logs[mode]);}}
async function idle(){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&![...document.querySelectorAll('.recalculating')].some(x=>x.getClientRects().length));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);}
async function open(kind){await page.goto(`http://127.0.0.1:${config.port}/`);await button('Data library').click();await page.getByLabel('Search datasets',{exact:true}).fill(`Original audio ${kind}`);
 await page.locator(`[data-brohn-event="open_dataset"][data-brohn-value='"${config.datasets[kind]}"']`).click();
 await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${config.reports[kind].id}"']`).click();await button('Review original audio').click();await page.locator('#audio_review_start').waitFor();await idle();}
async function apply(label){const start=performance.now();await button('Apply audio window').click();await expect(page.getByRole('heading',{name:'Saved audio source review',exact:true})).toBeVisible({timeout:120000});
 await expect(page.getByRole('link',{name:'Download every selected audio sample',exact:true})).toHaveAttribute('href',/session\//);await idle();timings.push({label,elapsed_ms:performance.now()-start});}
async function download(label,filename){const wait=page.waitForEvent('download');await page.getByRole('link',{name:label,exact:true}).click();const d=await wait;assert.equal(await d.failure(),null);const file=path.join(output,filename);await d.saveAs(file);return await fs.readFile(file);}
async function manifest(filename){return JSON.parse((await download('Download audio review provenance',filename)).toString());}
async function scan(label,width){await page.setViewportSize({width,height:width<500?844:1080});await idle();const violations=(await new AxeBuilder({page}).analyze()).violations;
 const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);scans.push({label,width,violations:violations.length,overflow});
 await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(violations,null,2));await page.screenshot({path:path.join(output,`${label}.png`),fullPage:true});
 await page.locator(`#audio_review_result .brohn-signal-${width<500?'compact':'wide'}`).first().screenshot({path:path.join(output,`${label}-waveform.png`)});
 await page.locator(`#audio_review_result .brohn-signal-${width<500?'compact':'wide'}`).last().screenshot({path:path.join(output,`${label}-spectrum.png`)});check(!violations.length&&!overflow,`${label}: automated accessibility and page reflow pass`);}
async function reopen(id){const started=performance.now();await page.getByText('Saved audio windows',{exact:true}).click();await page.locator(`[data-brohn-event="audio_review_reopen"][data-brohn-value='"${id}"']`).click();
 await expect(page.getByRole('heading',{name:'Saved audio source review',exact:true})).toBeVisible({timeout:30000});await expect(page.getByRole('link',{name:'Download every selected audio sample',exact:true})).toHaveAttribute('href',/session\//);await idle();timings.push({label:'saved-window-reopen',elapsed_ms:performance.now()-started});}
try{
 if(process.argv[3]==='--restart-only') {
  const previous=path.resolve(process.argv[4]);assert.equal(path.dirname(previous),folder);assert.ok(path.basename(previous).startsWith('browser-'));
  const first=JSON.parse(await fs.readFile(path.join(previous,'tone-review.json'),'utf8')),csv=await fs.readFile(path.join(previous,'tone-samples.csv'));
  const before=await snapshot();await start();await open('tone');await reopen(first.id);
  assert.deepEqual(await manifest('restarted-review.json'),first);assert.equal(hash(await download('Download every selected audio sample','restarted-samples.csv')),hash(csv));
  const after=await snapshot();check(after.jobs.length===before.jobs.length&&Object.values(after.reports).every(r=>r.unchanged)&&after.jobs.every(j=>j.status==='succeeded'),'Fresh researcher process reopens identical saved result and exact CSV without new jobs or original report changes');
  await page.setViewportSize({width:390,height:844});await idle();
  const mobile=page.locator('#audio_review_result .brohn-signal-compact').first();
  const geometry=await mobile.locator('svg').evaluate(svg=>({viewBox:svg.getAttribute('viewBox'),rectangle:svg.getBoundingClientRect().toJSON(),labels:[...svg.querySelectorAll('text')].map(t=>{const b=t.getBBox();return {text:t.textContent,box:{x:b.x,y:b.y,width:b.width,height:b.height},rectangle:t.getBoundingClientRect().toJSON()};}),svg:svg.outerHTML}));
  check(geometry.viewBox==='0 0 320 310'&&geometry.labels.some(t=>t.text==='Seconds from source start')&&geometry.labels.every(t=>t.box.x>=-1&&t.box.y>=0&&t.box.x+t.box.width<=321&&t.box.y+t.box.height<=310),'Live mobile waveform time ticks and axis title fit the native viewBox without clipping');
  await fs.writeFile(path.join(output,'mobile-waveform-geometry.json'),JSON.stringify(geometry,null,2));await mobile.screenshot({path:path.join(output,'mobile-waveform.png')});
  assert.deepEqual(await hashes(),startHashes);assert.deepEqual(errors,[]);check(true,'Restart proof retains product fingerprints and has no browser exception');
  await page.screenshot({path:path.join(output,'restart.png'),fullPage:true});
  await fs.writeFile(path.join(output,'results.json'),JSON.stringify({passed:true,scope:'Focused cold process restart following retained full journey; no repeat scoring or accessibility scan claim.',prior_evidence:previous,checks,timings,sourceHashes:startHashes,first_review:first.id},null,2));console.log(JSON.stringify({passed:true,checks:checks.length,output}));
 }else {
 await start();await open('tone');check(await page.locator('#audio_review_end').inputValue()==='3','Default source window stays within recorded duration');await apply('three-second-stereo');
 const first=await manifest('tone-review.json');check(first.request.report.hash===config.reports.tone.hash&&first.result.source_hash===config.source_hashes.tone&&first.result.selection.channel_index===1,'Saved view binds exact acoustic report, stereo source and original selected channel');
 const csv=await download('Download every selected audio sample','tone-samples.csv'),lines=csv.toString().trim().split('\n'),source=await fs.readFile(config.sources.tone);
 check(lines.length===24001&&lines.slice(1).every((line,i)=>{const x=line.split(',').map(Number);return x[0]===i&&x[1]===i/8000&&x[2]===1&&x[3]===source.readInt16LE(44+i*4+2)/32768;}),'Every exported selected-channel value/time/index matches original PCM16 bytes independently');
 const spectrum=await download('Download every native spectral cell','tone-spectrum.csv');check(spectrum.toString().trim().split('\n').length===first.result.support.spectral_cells+1&&first.result.support.spectral_frames===298,'Complete spectrum export retains every native frame/bin without display reduction');
 for(const kind of['waveform','spectrum']){const svg=(await download(`Download ${kind} SVG`,`tone-${kind}.svg`)).toString();const result=await page.evaluate(text=>{const d=new DOMParser().parseFromString(text,'image/svg+xml');return {metadata:JSON.parse(d.querySelector('metadata').textContent),errors:d.querySelectorAll('parsererror').length,marks:[...d.querySelectorAll('[data-first-sample],[data-first-frame]')].map(e=>Object.fromEntries([...e.attributes].map(a=>[a.name,a.value])))};},svg);
  check(result.errors===0&&result.metadata.source_hash===config.source_hashes.tone&&result.marks.length>0&&!svg.includes('NaN'),`${kind} standalone SVG is source-bound and has finite actual marks`);
  if(kind==='waveform')check(result.marks.every(m=>Math.abs(Number(m.x1)-(105+Number(m['data-minimum-sample'])/8000/3*(898-105)))<1e-7),'Waveform SVG actual x endpoints preserve original minimum-sample positions');}
 await scan('audio-tone-desktop',1440);await scan('audio-tone-mobile',390);
 await page.getByText('Exact waveform display bins',{exact:true}).click();await page.evaluate(()=>{window.audioFigureBeforePage=document.querySelector('#audio_review_result svg');});
 await button('Next waveform values').focus();await page.keyboard.press('Enter');const values=page.locator('#audio_review_values_content_waveform');
 await expect(values).toBeVisible();await expect(values).toContainText('Showing 51 to 100');await expect(values).toBeFocused();
 await button('Previous waveform values').focus();await page.keyboard.press('Enter');await expect(values).toBeVisible();await expect(values).toContainText('Showing 1 to 50');await expect(values).toBeFocused();
 check(await page.evaluate(()=>window.audioFigureBeforePage===document.querySelector('#audio_review_result svg')),'Numerical paging preserves visible disclosure, keyboard focus and original plot nodes');
 await page.locator('#audio_review_values_waveform details').screenshot({path:path.join(output,'audio-values-mobile.png')});
 await page.setViewportSize({width:1440,height:1080});const oldURL=await page.getByRole('link',{name:'Download every selected audio sample',exact:true}).getAttribute('href');
 const wrongURL=new URL(oldURL,page.url());wrongURL.searchParams.set('key','invalid-token');check((await context.request.get(wrongURL.toString())).status()===404,'Forged audio download token is refused');
 await page.locator('#audio_review_start').fill('0.5');await expect(page.locator('#audio_review_result')).toContainText('interval changed');
 check((await context.request.get(new URL(oldURL,page.url()).toString())).status()===404,'Changing the selected interval immediately revokes its old CSV URL');
 await page.locator('#audio_review_end').fill('1');await apply('half-second-window');const narrowed=await manifest('narrow-review.json');check(narrowed.result.support.first_sample===4000&&narrowed.result.support.stop_sample===8000,'Window selects exact half-open source sample boundaries');
 await page.locator('#audio_review_start').fill('0');await page.locator('#audio_review_end').fill('0.001');await apply('eight-sample-window');const short=await manifest('short-review.json');
 check(short.result.support.selected_samples===8&&short.result.support.spectral_cells===0&&(await download('Download every native spectral cell','short-spectrum.csv')).toString().trim().split('\n').length===1,'Eight-sample window has exact samples and explicit header-only spectrum');await scan('audio-short-mobile',390);
 await open('tone');await reopen(first.id);assert.deepEqual(await manifest('reopened-review.json'),first);check(true,'Saved source window reopens with identical complete result and provenance');
 await button('Inspect saved RMS and spectral centroid').click();await page.locator('#signal_table-selectized').waitFor({timeout:120000});await expect(page.locator('#signal_table')).toContainText('audio');check(true,'Source review opens the same report complete saved RMS and centroid artifact');
 await button('Inspect saved pitch and periodicity').click();await expect.poll(async()=>{const snap=await snapshot();return snap.signals.some(s=>s.body.report_id===config.reports.tone.id&&s.body.artifact_hash&&s.body.view?.tables?.some(t=>t.table_id==='audio-pitch-frames'));},{timeout:120000}).toBe(true);check(true,'Source review reaches original saved pitch/periodicity frames without acoustic rescoring');
 const toneURL=await page.getByRole('link',{name:'Download every selected audio sample',exact:true}).getAttribute('href');await open('silence');check((await context.request.get(new URL(toneURL,page.url()).toString())).status()===404,'Navigation to standalone recording revokes prior source download');await apply('standalone-silence');
 const silence=await manifest('silence-review.json');check(silence.study_id===null&&silence.request.study_id===null&&silence.result.support.exact_silence&&silence.result.spectrogram.every(t=>t.cells.every(c=>c.mean_power_fs2_per_hz===0)),'Standalone Data-library silence remains study-free with finite zero power density');await scan('audio-silence-mobile',390);
 let snap=await snapshot();const beforeRestart=snap.jobs.length;await stop();await start();await open('tone');await reopen(first.id);
 assert.deepEqual(await manifest('restarted-review.json'),first);assert.equal(hash(await download('Download every selected audio sample','restarted-samples.csv')),hash(csv));snap=await snapshot();
 check(snap.jobs.length===beforeRestart&&Object.values(snap.reports).every(r=>r.unchanged)&&snap.jobs.every(j=>j.status==='succeeded'),'Actual process restart preserves saved review and original reports without new jobs');
 assert.deepEqual(await hashes(),startHashes);assert.deepEqual(errors,[]);check(true,'Product source fingerprints and browser exception checks remain clean');
 await fs.writeFile(path.join(output,'results.json'),JSON.stringify({passed:true,checks,scans,timings,sourceHashes:startHashes,first_review:first.id,
  limits:['Original synthetic PCM16 and software workflow evidence; no microphone calibration, human voice recognition, speech/emotion/attention or scientific validity claim.','Linear FS^2/Hz display; exact unaggregated exports remain authoritative.']},null,2));console.log(JSON.stringify({passed:true,checks:checks.length,scans:scans.length,output}));
 }
}catch(error){await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,scans,errors,logs,text:await page.locator('body').innerText().catch(()=>'(closed)')},null,2));throw error;
}finally{await browser.close();await stop();}
