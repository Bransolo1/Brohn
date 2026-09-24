// Connected original report -> exact source trace window -> immutable downloads.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawn,spawnSync} from 'node:child_process';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const folder=path.resolve(process.argv[2]),reference=path.resolve(process.argv[3]);
assert.ok(path.basename(folder).startsWith('brohn-gaze-browser-'));
await fs.mkdir(folder,{recursive:true});const output=path.join(folder,`browser-${Date.now()}`);await fs.mkdir(output);
const env={...process.env,R_LIBS_USER:process.env.R_LIBS_USER||path.resolve('../../work/r-library-brohn-restore'),LC_ALL:'C',
 BROHN_PUBLICATION_PYTHON:process.env.BROHN_PUBLICATION_PYTHON||path.resolve('../../work/tooling/methods-venv/Scripts/python.exe'),
 BROHN_PUBLICATION_NATIVE_MANIFEST:process.env.BROHN_PUBLICATION_NATIVE_MANIFEST||path.resolve('../../work/tooling/brohn-native/publication-guard.json')};
const r=process.env.BROHN_RSCRIPT||path.resolve('../../work/native-r/bin/Rscript.exe');
function helper(mode){const proc=spawnSync(r,['--vanilla','tests/fixtures/researcher-gaze-traces.R',mode,folder,reference],{env,windowsHide:true,encoding:'utf8',maxBuffer:16*1024**2});assert.equal(proc.status,0,proc.stderr+proc.stdout);}
helper('setup');const config=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
const checks=[],scans=[],errors=[],processes=[];let log='',children=[];
function start(){children=['serve','worker'].map(mode=>{const child=spawn(r,['--vanilla','tests/fixtures/researcher-gaze-traces.R',mode,folder],{env,windowsHide:true});processes.push({mode,pid:child.pid});child.stdout.on('data',x=>log+=`${mode}: ${x}`);child.stderr.on('data',x=>log+=`${mode}: ${x}`);return child;});}
async function stop(){await fs.writeFile(path.join(folder,'stop.request'),'owned test shutdown');await Promise.all(children.map(async child=>{if(child.exitCode===null)await Promise.race([new Promise(resolve=>child.once('exit',resolve)),new Promise(resolve=>setTimeout(resolve,12000))]);if(child.exitCode===null){child.kill();await expect.poll(()=>child.exitCode!==null||child.signalCode!==null,{timeout:10000}).toBe(true);}}));}
start();
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage();
page.on('pageerror',e=>errors.push(e.message));
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log('PASS',label);};
const button=name=>page.getByRole('button',{name,exact:true});
async function idle(){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy'));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);}
async function ready(rows){await expect(page.locator('#gaze_trace_plot')).toContainText(`${rows} source rows in this window`,{timeout:90000});await expect(page.locator('#gaze_trace_downloads a')).toHaveCount(3,{timeout:30000});await idle();}
async function available(){await expect.poll(async()=>{if(children.some(c=>c.exitCode!==null))throw Error(log);try{return(await fetch(`http://127.0.0.1:${config.port}/`)).status===200;}catch{return false;}},{timeout:60000}).toBe(true);}
async function openReport(){await page.goto(`http://127.0.0.1:${config.port}/`);await button('Studies').click();await page.locator(`[data-brohn-event="brohn_open_study"][data-brohn-value='"${config.study_id}"']`).click();await button('Results').click();await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${config.report_id}"']`).click();}
async function selectPerson(person){await expect(page.locator('#gaze_report_exposure')).toBeAttached({timeout:30000});await page.locator('#gaze_report_exposure + .selectize-control .selectize-input').click();await page.locator('#gaze_report_exposure + .selectize-control .option').filter({hasText:person}).click();await idle();}
async function download(label,filename){const wait=page.waitForEvent('download');await page.getByRole('link',{name:label,exact:true}).click();const item=await wait;assert.equal(await item.failure(),null);const target=path.join(output,filename);await item.saveAs(target);return target;}
async function windowData(filename){return JSON.parse(await fs.readFile(await download('Download exact window and support',filename),'utf8'));}
async function scan(label,width){await page.setViewportSize({width,height:1080});await idle();await page.locator('#gaze_trace_plot h2').click();const violations=(await new AxeBuilder({page}).analyze()).violations;
 const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);
 const small=await page.locator('.brohn-gaze-trace-controls button:visible,.brohn-gaze-trace-controls input:not([type=checkbox]):visible,.brohn-gaze-trace-controls select:visible,.brohn-gaze-trace summary:visible,.brohn-gaze-trace a:visible').evaluateAll(es=>es.filter(e=>e.getBoundingClientRect().height<44).map(e=>({id:e.id,h:e.getBoundingClientRect().height})));
 scans.push({label,width,violations:violations.length,overflow,small});await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(violations,null,2));await page.screenshot({path:path.join(output,`${label}.png`),fullPage:true});await page.locator('#gaze_trace_plot > section').screenshot({path:path.join(output,`${label}-plot.png`)});
 check(!violations.length&&!overflow&&!small.length,`${label}: accessible, responsive trace and 44px controls`);}
try{
 await available();await openReport();
 await selectPerson('person-b');await button('Explore pupil and blink traces').click();await ready(22);
 check((await page.locator('#gaze_trace_table option:checked').textContent()).includes('person-b'),'Opening trace follows the existing gaze participant/exposure');
 let saved=await windowData('dirty-full-window.json');const originalDirtyWindow=saved;check(saved.result.table.identity.participant_id==='person-b'&&saved.result.selected_rows===22,'Exact saved trace belongs to selected person and includes every exposure row');
 check(saved.result.rows.some(r=>r.pupil_decimal==='-0.0')&&saved.result.rows.some(r=>r.pupil_text===' 6.0000000000000009 '),'Published window preserves signed zero, difficult binary64 and original source text');
 check(await page.locator('#gaze_trace_plot svg:visible [data-gaze-invalid]').count()===5&&await page.locator('#gaze_trace_plot svg:visible [data-gaze-blink]').count()===1,'Visible original trace preserves invalid values and isolated source blink tick');
 const svgFile=await download('Download trace chart','dirty-source-trace.svg');const svg=await fs.readFile(svgFile,'utf8');
 const svgData=await page.evaluate(text=>{const xml=new DOMParser().parseFromString(text,'image/svg+xml');return{errors:xml.querySelectorAll('parsererror').length,metadata:JSON.parse(xml.querySelector('metadata').textContent),invalid:xml.querySelectorAll('[data-gaze-invalid]').length,blinks:xml.querySelectorAll('[data-gaze-blink]').length};},svg);
 check(!svgData.errors&&svgData.metadata.artifact.sha256===config.artifact.sha256&&svgData.metadata.binding.report_hash===config.report_hash&&svgData.metadata.identity.participant_id==='person-b'&&svgData.metadata.selected_rows===22&&svgData.metadata.source_provenance.origin==='sample'&&svgData.metadata.support.pupil_unit==='mm'&&svgData.invalid===5&&svgData.blinks===1,'Downloaded SVG retains exact source/report identity, origin, units, selected denominator and original plot masks');
 const svgPage=await context.newPage();await svgPage.setViewportSize({width:940,height:590});await svgPage.setContent('<!doctype html><html lang="en"><title>Downloaded trace SVG</title><body style="margin:0">'+svg+'</body></html>');await svgPage.locator('svg').screenshot({path:path.join(output,'exported-trace.png')});await svgPage.close();await page.bringToFront();
 await scan('dirty-desktop',1440);await scan('dirty-390',390);
 const detail=page.locator('#gaze_trace_plot summary');await detail.focus();await page.keyboard.press('Enter');
 const region=page.getByRole('region',{name:'Exact pupil and blink values, horizontally scrollable',exact:true});await region.focus();await page.keyboard.press('ArrowRight');
 await expect.poll(()=>region.evaluate(e=>e.scrollLeft)).toBeGreaterThan(0);check(true,'Narrow exact-value table is named and scrollable with the keyboard');
 await scan('dirty-values-390',390);await detail.focus();await page.keyboard.press('Enter');await page.setViewportSize({width:1440,height:1080});
 const initialSvg=await page.getByRole('link',{name:'Download trace chart',exact:true}).getAttribute('href');
 await page.locator('#gaze_trace_start').fill('140');await page.locator('#gaze_trace_end').fill('160');await button('Show pupil and blink window').click();await ready(3);
 saved=await windowData('dirty-exact-window.json');check(saved.result.range.start_ms===140&&saved.result.range.end_ms===160&&saved.result.rows.map(r=>r.analysis_time_ms).join(',')==='140,150,160','Immediate typed window action saves exact visible inclusive bounds');
 check((await context.request.get(new URL(initialSvg,page.url()).href)).status()===404,'Old chart link is revoked when the time range changes');
 const complete=await download('Download complete source trace','complete-source-trace.ndjson');const raw=await fs.readFile(complete);
 check(crypto.createHash('sha256').update(raw).digest('hex')===config.artifact.sha256,'Complete trace download preserves the exact immutable artifact bytes');
 const records=raw.toString('utf8').trimEnd().split('\n').map(JSON.parse);check(records.at(-1).rows===47&&records.at(-1).tables===3,'Complete download includes all original rows and all source exposure groups');
 await fs.writeFile(path.join(folder,'worker.pause'),'owned test pause');
 await page.locator('#gaze_trace_start').fill('111');await page.locator('#gaze_trace_end').fill('199');await button('Show pupil and blink window').click();
 await button('Cancel trace processing').click();await button('Retry trace processing').waitFor();check(true,'Queued exact window can be cancelled without erasing original report');
 await button('Retry trace processing').focus();await page.keyboard.press('Enter');await fs.unlink(path.join(folder,'worker.pause'));await ready(8);
 saved=await windowData('retry-window.json');check(saved.result.range.start_ms===111&&saved.result.range.end_ms===199&&saved.result.selected_rows===8,'Keyboard retry processes the same exact source window');
 const oldDownload=await page.getByRole('link',{name:'Download exact window and support',exact:true}).getAttribute('href');
 const oldSvg=await page.getByRole('link',{name:'Download trace chart',exact:true}).getAttribute('href');
 await selectPerson('person-a');await ready(22);saved=await windowData('clean-window.json');
 check(saved.result.table.identity.participant_id==='person-a'&&saved.result.rows.filter(r=>r.pupil_minus_baseline!==null).every(r=>r.pupil_minus_baseline===2),'Changing existing gaze exposure switches trace to the independent clean 4-to-6 baseline case');
 check((await context.request.get(new URL(oldDownload,page.url()).href)).status()===404,'Old exact-window link is revoked when the selected exposure changes');
 check((await context.request.get(new URL(oldSvg,page.url()).href)).status()===404,'Old chart link is revoked when the selected exposure changes');
 const choices=await page.locator('#gaze_trace_table option').evaluateAll(es=>es.map(e=>({value:e.value,label:e.textContent})));const noView=choices.find(o=>o.label.includes('baseline-only'));assert.ok(noView);
 await page.locator('#gaze_trace_table').selectOption(noView.value);await ready(3);saved=await windowData('no-view-window.json');
 check(saved.result.table.identity.participant_id==='person-c'&&saved.result.table.support.baseline.status==='no_passive_phase'&&saved.result.rows.every(r=>r.pupil_minus_baseline===null),'Explicitly selected no-view source rows remain inspectable without an invented pupil correction');
 await scan('no-view-390',390);await page.setViewportSize({width:1440,height:1080});
 const stale=await page.getByRole('link',{name:'Download complete source trace',exact:true}).getAttribute('href');const staleSvg=await page.getByRole('link',{name:'Download trace chart',exact:true}).getAttribute('href');await button('Studies').click();await idle();
 check((await context.request.get(new URL(stale,page.url()).href)).status()===404,'Leaving the report revokes its complete-trace link');
 check((await context.request.get(new URL(staleSvg,page.url()).href)).status()===404,'Leaving the report revokes its trace-chart link');
 helper('inspect');const inspection=JSON.parse(await fs.readFile(path.join(folder,'inspection.json'),'utf8'));
 check(inspection.original_report_hash===config.report_hash&&inspection.artifact_hash===config.artifact.sha256,'View preparation, windows and retry leave original report and complete source artifact unchanged');
 await fs.writeFile(path.join(output,'before-restart.json'),JSON.stringify(inspection,null,2));
 await stop();await fs.unlink(path.join(folder,'stop.request'));start();await available();await openReport();await selectPerson('person-b');await button('Explore pupil and blink traces').click();await ready(22);
 assert.deepEqual(await windowData('reopened-dirty-window.json'),originalDirtyWindow);check(true,'Restarted researcher service reopens the same exact saved source window and baseline support');
 assert.equal(await fs.readFile(await download('Download trace chart','reopened-source-trace.svg'),'utf8'),svg);check(true,'Restarted service exports byte-identical source-bound trace SVG');
 helper('inspect');const reopened=JSON.parse(await fs.readFile(path.join(folder,'inspection.json'),'utf8'));assert.deepEqual(reopened.jobs,inspection.jobs);assert.deepEqual(reopened.views,inspection.views);check(true,'Reopening reuses saved views without a new analysis or background job');
 await scan('reopened-desktop',1440);
 check(errors.length===0,'Connected researcher journey has no browser runtime errors');
 await fs.writeFile(path.join(output,'acceptance.json'),JSON.stringify({checks,scans,errors,processes,fixture:config,scope:'Original software source; no device or blink-detector qualification'},null,2));console.log(output);
}catch(error){await fs.writeFile(path.join(output,'failure.txt'),String(error.stack||error));await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});throw error;
}finally{
 await browser.close();await stop();
 await fs.writeFile(path.join(output,'server.log'),log);
}
