// Actual researcher views of two retained public recordings; no accuracy claim.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const folder=path.resolve(process.argv[2]),reference=path.resolve(process.argv[3]);
assert.ok(path.basename(folder).startsWith('brohn-cardiac-input-ui-'));
await fs.mkdir(folder,{recursive:true});
const output=path.join(folder,`browser-${Date.now()}`);await fs.mkdir(output);
const r=path.resolve('../../work/native-r/bin/Rscript.exe'),helper='tests/fixtures/researcher-cardiac-input.R';
const env={...process.env,R_LIBS_USER:path.resolve('../../work/r-library-brohn-restore'),LC_ALL:'C',
 BROHN_PUBLICATION_PYTHON:path.resolve('../../work/tooling/methods-venv/Scripts/python.exe'),BROHN_PUBLICATION_NATIVE_MANIFEST:path.resolve('../../work/tooling/brohn-native/publication-guard.json')};
if(!process.argv.includes('--reuse-fixture')){const setup=spawnSync(r,['--vanilla',helper,'setup',folder,reference],{env,windowsHide:true,encoding:'utf8'});assert.equal(setup.status,0,setup.stderr);}
await fs.rm(path.join(folder,'stop.request'),{force:true});
const config=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
const children=[],checks=[],scans=[],errors=[];let log='';
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage();
page.on('pageerror',e=>errors.push(e.message));
function check(ok,label){assert.ok(ok,label);checks.push(label);console.log('PASS',label);}
async function idle(){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&![...document.querySelectorAll('.recalculating')].some(e=>e.getClientRects().length));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);}
async function download(label,name){const link=page.getByRole('link',{name:label,exact:true});await expect(link).toHaveAttribute('href',/session\/.*download\//);const pending=page.waitForEvent('download');await link.click();const d=await pending;assert.equal(await d.failure(),null);const target=path.join(output,name);await d.saveAs(target);return target;}
async function json(label,name){return JSON.parse(await fs.readFile(await download(label,name),'utf8'));}
async function open(modality){const record=config.reports[modality];await page.getByRole('button',{name:'Data library',exact:true}).click();await page.getByLabel('Search datasets',{exact:true}).fill(record.title);
 await page.locator(`[data-brohn-event="open_dataset"][data-brohn-value='"${record.dataset_id}"']`).click();await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${record.report_id}"']`).click();await idle();}
async function selectMeasure(value){await page.locator('#signal_measure').evaluate((e,v)=>{e.selectize.setValue(v);},value);await idle();}
async function show(value){await page.getByRole('button',{name:'Show signal',exact:true}).click();const title=value==='raw'?'Saved input waveform (before cleaning)':'Saved cleaned waveform';
 await expect(page.locator('#signal_plot svg:visible > title')).toContainText(title,{timeout:90000});await idle();}
async function scan(label,narrow){await page.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});
 const chart=page.locator('#signal_plot svg:visible');await chart.scrollIntoViewIfNeeded();
 const violations=(await new AxeBuilder({page}).analyze()).violations;
 const layout=await page.evaluate(()=>({overflow:document.documentElement.scrollWidth>innerWidth+1,small:[...document.querySelectorAll('#signal_plot a,#signal_plot button,#signal_plot summary')].filter(e=>{const b=e.getBoundingClientRect();return b.width&&b.height&&(b.width<43||b.height<43);}).map(e=>e.textContent)}));
 const escaped=await chart.evaluate(svg=>{const b=svg.getBoundingClientRect();return[...svg.querySelectorAll('text')].filter(t=>{const r=t.getBoundingClientRect();return r.left<b.left-1||r.right>b.right+1||r.top<b.top-1||r.bottom>b.bottom+1;}).map(t=>t.textContent);});
 scans.push({label,violations:violations.length,...layout,escaped});await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(violations,null,2));
 await page.screenshot({path:path.join(output,`${label}.png`),fullPage:true});await chart.screenshot({path:path.join(output,`${label}-chart.png`)});
 check(!violations.length&&!layout.overflow&&!layout.small.length&&!escaped.length,`${label}: clear accessibility, reflow, controls and chart labels`);await page.setViewportSize({width:1440,height:1080});}
try{
 for(const mode of ['serve','worker']){const child=spawn(r,['--vanilla',helper,mode,folder],{env,windowsHide:true});children.push(child);child.stdout.on('data',x=>log+=`${mode}: ${x}`);child.stderr.on('data',x=>log+=`${mode}: ${x}`);}
 await expect.poll(async()=>{if(children.some(c=>c.exitCode!==null))throw Error(log);try{return(await fetch(`http://127.0.0.1:${config.port}/`)).status===200;}catch{return false;}},{timeout:60000}).toBe(true);
 await page.goto(`http://127.0.0.1:${config.port}/`);
 for(const modality of ['ecg','ppg']){
  await open(modality);const original=await json('JSON + provenance',`${modality}-report-before.json`);
  await page.getByRole('button',{name:'Explore signal traces and spectra',exact:true}).click();await page.getByRole('button',{name:'Show signal',exact:true}).waitFor({timeout:90000});
  await expect(page.locator('#signal_measure')).toHaveValue('clean');
  check(true,`${modality}: cleaned view remains the default and input is an explicit choice`);
  await page.getByLabel('Show the complete recorded range',{exact:true}).uncheck();
  const range=modality==='ecg'?[10,18]:[220,235];
  await page.locator('#signal_range_start').fill(String(range[0]));await page.locator('#signal_range_end').fill(String(range[1]));await show('clean');
  const clean=await json('Download view + provenance',`${modality}-clean.json`);assert.deepEqual(clean.view.effective_range,range);
  check(true,`${modality}: displayed range uses the exact visible bounds`);
  await selectMeasure('raw');await page.getByRole('button',{name:'Show signal',exact:true}).focus();await page.keyboard.press('Enter');
  await expect(page.locator('#signal_plot svg:visible > title')).toContainText('Saved input waveform (before cleaning)',{timeout:90000});await idle();
  const raw=await json('Download view + provenance',`${modality}-input.json`),oracle=JSON.parse(await fs.readFile(path.join(reference,`${modality}-raw-view.json`),'utf8'));
  assert.deepEqual(raw.view.marker_overlay,oracle.marker_overlay);
  const identities=m=>m.markers.map(({value,...rest})=>rest);assert.deepEqual(identities(raw.view.marker_overlay),identities(clean.view.marker_overlay));
  check(raw.view.axis.value_column==='raw'&&raw.view.marker_overlay.detection_basis==='saved_cleaned_waveform',`${modality}: actual input view preserves exact prior detections and its processing basis`);
  const table=page.locator('.brohn-cardiac-marker-table');await table.locator('summary').focus();await page.keyboard.press('Enter');
  await expect(table).toHaveAttribute('open','');await expect(table).toContainText('Input value');await expect(table).toContainText('unit conversion');
  await expect(table.locator('tbody tr')).toHaveCount(raw.view.marker_overlay.markers.length);
  check(true,`${modality}: keyboard opens the complete exact-value table with input interpretation`);
  const svg=await fs.readFile(await download('Download chart',`${modality}-input.svg`),'utf8');
  check((svg.match(/class="brohn-cardiac-marker"/g)||[]).length===raw.view.marker_overlay.markers.length&&svg.includes('input waveform before cleaning')&&svg.includes('calculated from the cleaned signal'),`${modality}: standalone SVG keeps input and detection semantics`);
  await scan(`${modality}-input-desktop`,false);await scan(`${modality}-input-390`,true);
  await selectMeasure('clean');await show('clean');const again=await json('Download view + provenance',`${modality}-clean-again.json`);assert.deepEqual(again.view.marker_overlay,clean.view.marker_overlay);
  check(true,`${modality}: switching back retains cleaned values and unchanged events`);
  assert.deepEqual(await json('JSON + provenance',`${modality}-report-after.json`),original);
  check(true,`${modality}: view changes and downloads leave scientific report unchanged`);
  await page.reload();await open(modality);await page.getByRole('button',{name:'Explore signal traces and spectra',exact:true}).click();await page.getByRole('button',{name:'Show signal',exact:true}).waitFor({timeout:90000});
  await page.getByLabel('Show the complete recorded range',{exact:true}).uncheck();await page.locator('#signal_range_start').fill(String(range[0]));await page.locator('#signal_range_end').fill(String(range[1]));await selectMeasure('raw');await show('raw');
  const reopened=await json('Download view + provenance',`${modality}-reopened.json`);assert.deepEqual(reopened.view.marker_overlay,raw.view.marker_overlay);
  check(true,`${modality}: fresh researcher page reopens exact saved input view`);
 }
 check(!errors.length,`No browser script errors: ${errors.join('; ')}`);
 await fs.writeFile(path.join(output,'results.json'),JSON.stringify({checks,scans,errors,config,origin:'public_reference_display_regression',accuracy_qualified:false},null,2));
 console.log(JSON.stringify({checks:checks.length,scans:scans.length,output}));
}catch(error){await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,scans,errors,log,text:await page.locator('body').innerText()},null,2));throw error;}
finally{await browser.close();await fs.writeFile(path.join(folder,'stop.request'),'stop owned fixture');await Promise.all(children.map(c=>new Promise(resolve=>{if(c.exitCode!==null)return resolve();c.once('exit',resolve);setTimeout(()=>{if(c.exitCode===null)c.kill();resolve();},5000).unref();})));await fs.writeFile(path.join(output,'server.log'),log);}
