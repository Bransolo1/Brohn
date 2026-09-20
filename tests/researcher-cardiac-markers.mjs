// Exact marker display: independent fixture renders and actual recorded-data app.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawn,spawnSync} from 'node:child_process';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const folder=path.resolve(process.argv[2]),reference=path.resolve(process.argv[3]);
const renderOnly=process.argv.includes('--render-only');
assert.ok(path.basename(folder).startsWith('brohn-cardiac-marker-ui-'));
const proof=JSON.parse(await fs.readFile(path.join(folder,'renderer-results.json'),'utf8'));assert.ok(proof.checks>=24);
const output=path.join(folder,`browser-${Date.now()}`);await fs.mkdir(output);
const r=path.resolve('../../work/native-r/bin/Rscript.exe'),helper='tests/fixtures/researcher-cardiac-markers.R';
const env={...process.env,R_LIBS_USER:path.resolve('../../work/r-library-brohn-restore'),LC_ALL:'C',
 BROHN_PUBLICATION_PYTHON:path.resolve('../../work/tooling/methods-venv/Scripts/python.exe'),BROHN_PUBLICATION_MANIFEST:path.resolve('../../work/tooling/brohn-native/publication-guard.json')};
if(!renderOnly){const setup=spawnSync(r,['--vanilla',helper,'setup',folder,reference],{env,windowsHide:true,encoding:'utf8'});assert.equal(setup.status,0,setup.stderr);}
const config=renderOnly?null:JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
const children=[],checks=[],scans=[],errors=[];let log='';
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage();
page.on('pageerror',e=>errors.push(e.message));
function check(ok,label){assert.ok(ok,label);checks.push(label);console.log('PASS',label);}
async function scan(label,narrow=false){await page.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});
 const chart=page.locator('.brohn-signal-wide svg:visible,.brohn-signal-compact svg:visible').first();if(await chart.count())await chart.scrollIntoViewIfNeeded();
 const violations=(await new AxeBuilder({page}).analyze()).violations;
 const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);
 const escaped=await chart.count()?await chart.evaluate(svg=>{const b=svg.getBoundingClientRect();return[...svg.querySelectorAll('text')].filter(t=>{const r=t.getBoundingClientRect();return r.left<b.left-1||r.right>b.right+1||r.top<b.top-1||r.bottom>b.bottom+1;}).map(t=>t.textContent);}):[];
 scans.push({label,violations:violations.length,overflow,escaped});await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(violations,null,2));
 await page.screenshot({path:path.join(output,`${label}.png`),fullPage:true});if(await chart.count())await chart.screenshot({path:path.join(output,`${label}-chart.png`)});
 check(!violations.length&&!overflow&&!escaped.length,`${label}: clear accessibility, page reflow and SVG labels`);await page.setViewportSize({width:1440,height:1080});}
async function idle(){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&![...document.querySelectorAll('.recalculating')].some(e=>e.getClientRects().length));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);}
async function download(label,name){const link=page.getByRole('link',{name:label,exact:true});await expect(link).toHaveAttribute('href',/session\/.*download\//);const pending=page.waitForEvent('download');await link.click();const d=await pending;assert.equal(await d.failure(),null);const target=path.join(output,name);await d.saveAs(target);return target;}
async function json(label,name){return JSON.parse(await fs.readFile(await download(label,name),'utf8'));}
async function show(expected){await page.getByRole('button',{name:'Show signal',exact:true}).click();await expect(page.locator('#signal_plot')).toContainText(expected,{timeout:90000});await idle();}
async function open(){await page.getByRole('button',{name:'Data library',exact:true}).click();await page.getByLabel('Search datasets',{exact:true}).fill('MIT-BIH record 108');
 await page.locator('[data-brohn-event="open_dataset"]').first().click();await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${config.report_id}"']`).click();await idle();}
try{
 for(const name of ['ecg','ppg','reference108','limit','empty']){
  await page.goto(pathToFileURL(path.join(folder,`${name}.html`)).href);await page.addStyleTag({path:'www/brand/tokens.css'});await page.addStyleTag({path:'www/brohn.css'});
  const model=JSON.parse(await fs.readFile(path.join(folder,`${name}-view.json`),'utf8')),m=model.marker_overlay;
  const chart=page.locator('svg:visible');await expect(chart).toHaveCount(1);
  const markers=await chart.locator('.brohn-cardiac-marker').evaluateAll(xs=>xs.map(x=>({sample:Number(x.dataset.sourceSample),eventRow:Number(x.dataset.eventRow),series:x.dataset.seriesTable,event:x.dataset.eventTable,cx:Number(x.getAttribute('cx')),cy:Number(x.getAttribute('cy'))})));
  assert.deepEqual(markers.map(x=>x.sample),m.markers.map(x=>x.source_sample_index));
  check(markers.length===m.markers.length,`${name}: every exact selected marker appears once, with no invented detections`);
  if(m.status==='available'){
   await page.getByText(`Inspect all ${m.markers.length} selected detections`,{exact:true}).click();
   await expect(page.getByRole('region',{name:/Exact saved detection coordinates/}).locator('tbody tr')).toHaveCount(m.markers.length);
   check((await page.locator('.brohn-cardiac-markers').innerText()).includes('before this displayed window'),`${name}: complete numerical alternative explains preceding interval scope`);
  }
  if(m.status==='too_many_markers')check(m.alignment==='not_checked_display_limit_exceeded'&&(await page.locator('.brohn-cardiac-markers').innerText()).includes('waveform positions have not been checked'),'Over-limit event count explicitly leaves sample alignment unchecked');
  await scan(`${name}-390`,true);
 }
 if(!renderOnly){
 for(const mode of ['serve','worker']){const child=spawn(r,['--vanilla',helper,mode,folder],{env,windowsHide:true});children.push(child);child.stdout.on('data',x=>log+=`${mode}: ${x}`);child.stderr.on('data',x=>log+=`${mode}: ${x}`);}
 await expect.poll(async()=>{if(children.some(c=>c.exitCode!==null))throw Error(log);try{return(await fetch(`http://127.0.0.1:${config.port}/`)).status===200;}catch{return false;}},{timeout:60000}).toBe(true);
 await page.goto(`http://127.0.0.1:${config.port}/`);await open();
 const original=await json('JSON + provenance','source-before.json');
 check(original.id===config.report_id&&!original.analysis.quality.scientifically_qualified&&original.origin==='imported','Actual public reference opens as imported and retains unqualified detector result');
 await page.getByRole('button',{name:'Explore signal traces and spectra',exact:true}).click();await page.getByRole('heading',{name:'Choose a signal view',exact:true}).waitFor({timeout:90000});
 await page.getByRole('button',{name:'Show signal',exact:true}).waitFor();await show('273 saved detections');
 const full=await json('Download view + provenance','full-view.json');
 check(full.view.marker_overlay.markers.length===273&&full.view.marker_overlay.event_type==='r_peak','Actual full-window worker preserves all 273 detections from the failing detector');
 await page.getByLabel('Show the complete recorded range',{exact:true}).uncheck();await page.locator('#signal_range_start').fill('18');await page.locator('#signal_range_end').fill('10');
 await page.getByRole('button',{name:'Show signal',exact:true}).click();await expect(page.locator('#platform_error')).toContainText(/increasing/);
 await page.waitForTimeout(2200);await expect(page.locator('#signal_range_start')).toHaveValue('18');await expect(page.locator('#signal_range_end')).toHaveValue('10');
 check(true,'Invalid range remains editable across polling without mutating the saved view');
 await page.locator('#signal_range_start').fill('10');await page.locator('#signal_range_end').fill('18');await show('7 saved detections');
 const selected=await json('Download view + provenance','selected-view.json'),oracle=JSON.parse(await fs.readFile(path.join(reference,'reference108-view.json'),'utf8'));
 assert.deepEqual(selected.view.marker_overlay,oracle.marker_overlay);
 check(selected.view.effective_range.join(',')==='10,18'&&selected.report_id===original.id,'Actual researcher range retains exact recorded failing detections, interval flags and both source identities');
 const svg=await fs.readFile(await download('Download chart','selected-chart.svg'),'utf8');
 check((svg.match(/class="brohn-cardiac-marker"/g)||[]).length===7&&svg.includes('unreviewed algorithm detections')&&svg.includes('Time (s)'),'Actual downloadable SVG preserves all seven detections, units and review status');
 await scan('actual-reference-desktop');await scan('actual-reference-390',true);
 await page.getByText('Inspect all 7 selected detections',{exact:true}).click();await scan('actual-table-390',true);
 await page.waitForTimeout(2200);await expect(page.locator('#signal_range_start')).toHaveValue('10');await expect(page.locator('#signal_range_end')).toHaveValue('18');
 check(await page.locator('.brohn-cardiac-marker-table').evaluate(e=>e.open),'Successful view polling preserves the chosen range and open numerical disclosure');
 await page.locator('#signal_range_start').fill('500');await page.locator('#signal_range_end').fill('501');await show('No eligible observations fall in this window');
 check(await page.locator('#signal_plot svg').count()===0&&(await page.locator('#signal_plot').innerText()).includes('does not imply absent heartbeats'),'Empty actual worker view has no fabricated waveform or absent-heartbeat claim');
 const after=await json('JSON + provenance','source-after.json');assert.deepEqual(after,original);
 check(true,'Full scientific report remains unchanged after range recovery, marker displays and downloads');
 await page.reload();await open();await page.getByRole('button',{name:'Explore signal traces and spectra',exact:true}).click();await page.getByRole('button',{name:'Show signal',exact:true}).waitFor({timeout:90000});
 await page.getByLabel('Show the complete recorded range',{exact:true}).uncheck();await page.locator('#signal_range_start').fill('10');await page.locator('#signal_range_end').fill('18');await show('7 saved detections');
 assert.deepEqual((await json('Download view + provenance','reopened-view.json')).view.marker_overlay,selected.view.marker_overlay);
 check(true,'Fresh researcher session reopens the exact saved unreviewed marker view');
 }
 check(!errors.length,`No browser errors: ${errors.join('; ')}`);
 await fs.writeFile(path.join(output,'results.json'),JSON.stringify({checks,scans,errors,mode:renderOnly?'saved-renderer-only':'actual-app-and-saved-renderer',origin:'published_reference_and_original_independent_synthetic',detector_accuracy_qualified:false,config},null,2));
 console.log(JSON.stringify({checks:checks.length,scans:scans.length,output}));
}catch(error){await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,scans,errors,log,text:await page.locator('body').innerText()},null,2));throw error;}
finally{await browser.close();await fs.writeFile(path.join(folder,'stop.request'),'stop owned fixture');await Promise.all(children.map(c=>new Promise(resolve=>{if(c.exitCode!==null)return resolve();c.once('exit',resolve);setTimeout(()=>{if(c.exitCode===null)c.kill();resolve();},5000).unref();})));await fs.writeFile(path.join(output,'server.log'),log);}
