// Actual researcher mapping, unavailable worker result and corrected new report.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import {importTransferredSource} from './helpers/source-import.mjs';
const folder=path.resolve(process.argv[2]);assert.ok(path.basename(folder).startsWith('brohn-neural-map-'));
await fs.mkdir(folder,{recursive:true});const output=path.join(folder,`browser-${Date.now()}`);await fs.mkdir(output);
const r=path.resolve('../../work/native-r/bin/Rscript.exe'),helperFile='tests/fixtures/researcher-neural-baseline-map.R';
const env={...process.env,R_LIBS_USER:path.resolve('../../work/r-library-brohn-restore'),LC_ALL:'C',
 BROHN_PUBLICATION_PYTHON:path.resolve('../../work/tooling/methods-venv/Scripts/python.exe'),BROHN_PUBLICATION_MANIFEST:path.resolve('../../work/tooling/brohn-native/publication-guard.json')};
const setup=spawnSync(r,['--vanilla',helperFile,'setup',folder],{env,windowsHide:true,encoding:'utf8'});assert.equal(setup.status,0,setup.stderr);
const config=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8')),oracle=JSON.parse(await fs.readFile(path.join(folder,'oracle.json'),'utf8'));
const children=[],checks=[],scans=[],errors=[];let log='';
for(const mode of ['serve','worker']){const child=spawn(r,['--vanilla',helperFile,mode,folder],{env,windowsHide:true});children.push(child);child.stdout.on('data',x=>log+=`${mode}: ${x}`);child.stderr.on('data',x=>log+=`${mode}: ${x}`);}
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage();
page.on('pageerror',e=>errors.push(e.message));const button=name=>page.getByRole('button',{name,exact:true});
function check(ok,label){assert.ok(ok,label);checks.push(label);console.log('PASS',label);}
async function idle(){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&![...document.querySelectorAll('.recalculating')].some(e=>e.getClientRects().length));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);}
async function select(id,label){const widget=page.locator(`#${id}-selectized`);if(await widget.count()){await widget.click();await widget.fill(label);await widget.press('Enter');}else await page.locator(`#${id}`).selectOption({label});}
async function fill(fields){for(const[id,value]of Object.entries(fields))await page.locator(`#map_neural_${id}`).fill(String(value));}
async function detail(label){const node=page.locator('summary').filter({hasText:label});if(!await node.evaluate(e=>e.parentElement.open))await node.click();}
async function file(label,name){const link=page.getByRole('link',{name:label,exact:true});await expect(link).toHaveAttribute('href',/session\/.*download\//);const pending=page.waitForEvent('download');await link.click();const d=await pending;assert.equal(await d.failure(),null);const target=path.join(output,name);await d.saveAs(target);return target;}
async function json(label,name){return JSON.parse(await fs.readFile(await file(label,name),'utf8'));}
async function scan(label,narrow=false){await page.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});await idle();const found=(await new AxeBuilder({page}).analyze()).violations;
 const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);scans.push({label,violations:found.length,overflow});await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(found,null,2));
 const map=page.locator('#neural_plot_view svg.brohn-neural-map:visible');let escaped=[];
 if(await map.count()){await map.scrollIntoViewIfNeeded();escaped=await map.evaluate(svg=>{const outer=svg.getBoundingClientRect();return[...svg.querySelectorAll('text')].filter(e=>{const r=e.getBoundingClientRect();return r.x<outer.x-1||r.right>outer.right+1||r.y<outer.y-1||r.bottom>outer.bottom+1;}).map(e=>e.textContent);});await map.screenshot({path:path.join(output,`${label}-map.png`)});}
 scans.at(-1).escaped=escaped;await page.screenshot({path:path.join(output,`${label}.png`),fullPage:true});check(!found.length&&!overflow&&!escaped.length,`${label}: no accessibility violations, page overflow or clipped map labels`);await page.setViewportSize({width:1440,height:1080});}
async function analyse(){const old=await page.locator('#dataset_reports [data-brohn-event="open_report"]').evaluateAll(es=>es.map(e=>e.getAttribute('data-brohn-value')));
 await button('Confirm mapping and analyse').click();await expect.poll(async()=>{await idle();const ids=await page.locator('#dataset_reports [data-brohn-event="open_report"]').evaluateAll(es=>es.map(e=>e.getAttribute('data-brohn-value')));return ids.find(id=>!old.includes(id))||'';},{timeout:120000}).not.toBe('');
 const links=page.locator('#dataset_reports [data-brohn-event="open_report"]');for(const link of await links.all())if(!old.includes(await link.getAttribute('data-brohn-value'))){await link.click();break;}await idle();}
async function dataset(id){await button('Data library').click();await page.locator(`[data-brohn-event="open_dataset"][data-brohn-value='"${id}"']`).click();await expect(page.locator('#dataset_form_identity')).toHaveValue(new RegExp(`^${id}:`));await idle();}
try {
 await expect.poll(async()=>{if(children.some(c=>c.exitCode!==null))throw Error(log);try{return(await fetch(`http://127.0.0.1:${config.port}/`)).status===200;}catch{return false;}},{timeout:60000}).toBe(true);
 await page.goto(`http://127.0.0.1:${config.port}/`);await button('Data library').click();await page.getByLabel('Dataset name',{exact:true}).fill('Independent Morlet baseline recovery');await select('dataset_origin','Synthetic example');await select('dataset_modality','EEG');
 const receipt=await importTransferredSource(page,path.join(folder,'morlet.csv')),datasetId=receipt.dataset_identity.split(':')[0];
 await select('map_values','Cz');await select('map_values','Pz');await select('map_time_unit','Seconds');await page.locator('#map_sampling_rate').fill('100');await page.locator('#map_unit').fill('uV');
 await select('map_neural_recipe','Time-frequency response (Morlet)');await select('map_neural_event_mode','Measured event list');await page.locator('#map_neural_events').fill(await fs.readFile(path.join(folder,'events.csv'),'utf8'));
 await fill({event_codes:'A = condition-a',event_source:'Independently specified exact sample-clock onsets, synthetic source only.',epoch_start:-2,epoch_end:2,minimum_trials:2});
 await select('map_neural_voltage_baseline','Keep original voltage offset');await detail('3. Reference, filtering and artifact rules');await select('map_neural_reference','Retain acquisition reference');await select('map_neural_filter','No additional filter');
 await fill({reference_source:'Synthetic zero reference',reject_start:-2,reject_end:2,settings_source:'Original stationary 10-Hz sine; expected power ratio one. No device or empirical participant claim.',frequencies:'10, 20',cycles:'3, 3',summary_start:0,summary_end:.5});
 await page.getByLabel('Reject trials with excessive peak-to-peak amplitude',{exact:true}).uncheck();await page.getByLabel('Reject flat trials',{exact:true}).uncheck();
 await select('map_neural_power_baseline','Divide by baseline power');await fill({power_baseline_start:-.02,power_baseline_end:-.01,power_floor:1e-12});
 await page.getByLabel('Recording provenance and collection notes',{exact:true}).fill('Original mathematical two-channel fixture: stationary sine and exact zero. Preserve source; no device qualification.');
 await button('Confirm mapping and analyse').click();await expect(page.locator('#platform_error')).toContainText('Declare a positive minimum baseline duration');
 check(await page.locator('#map_neural_power_baseline_end').inputValue()==='-0.01','Missing duration is actionable and preserves typed baseline controls');
 await fill({baseline_minimum_cycles:.1,baseline_rationale:'Deliberately short onset-contamination boundary test, not a scientific recommendation.'});await scan('reviewed-controls-390',true);await analyse();
 await expect(page.getByText('Power baseline support: unavailable',{exact:true})).toBeVisible();await expect(page.locator('#platform_content')).toContainText('Choose an earlier baseline');
 const unavailable=await json('JSON + provenance','unavailable-report.json');check(unavailable.analysis.status==='insufficient_support'&&unavailable.analysis.series.length===0&&!unavailable.analysis.recordings[0].derived_settings.baseline_support.frequencies[0].strictly_before_event,'Actual worker retains event-reaching baseline as unavailable with its sampled diagnostics');
 await scan('unavailable-390',true);await dataset(datasetId);await fill({power_baseline_start:-1,power_baseline_end:-.5,baseline_minimum_cycles:4,baseline_rationale:'Four cycles for the independent stationary sine test. The actual half-second window supplies five 10-Hz cycles.'});await analyse();
 await expect(page.getByRole('heading',{name:'Explore neural responses',exact:true})).toBeVisible();await expect(page.locator('#neural_plot_view')).toContainText('51 samples');await expect(page.locator('#neural_plot_view')).toContainText('not scientific validation');
 const report=await json('JSON + provenance','corrected-report.json'),support=report.analysis.recordings[0].derived_settings.baseline_support;
 check(report.analysis.parameters['recording-1'].recipe==='eeg-morlet-epochs/1.1'&&support.status==='eligible'&&support.sample_span_s===.5&&support.cycles_at_lowest_frequency===5&&support.frequencies.every(f=>f.strictly_before_event),'Corrected new report retains five observed cycles and pre-event support at every frequency');
 const mean=report.analysis.features.find(f=>f.channel==='Cz'&&f.name==='morlet_power_mean'&&f.frequency_hz===10);
 check(Math.abs(mean.value-1)<1e-7&&report.analysis.source.sha256===oracle.hashes['morlet.csv']&&!report.analysis.quality.scientifically_qualified,'Real corrected worker matches the independent stationary-ratio oracle and original source hash');
 const channel=await json('Download series + provenance','corrected-channel.json'),csv=await fs.readFile(await file('Download complete channel series','corrected-channel.csv'),'utf8');
 check(channel.parameters.power_baseline.adequacy.minimum_cycles===4&&csv.includes('baseline_support_json')&&csv.includes('complete-pre-event-wavelet-support/1.0'),'Actual downloads retain the reviewed baseline recipe and diagnostics');
 const map=page.locator('#neural_plot_view svg.brohn-neural-map:visible');await expect(map).toHaveCount(1);
 const image=map.locator('image'),pngURL=await image.getAttribute('href'),png=Buffer.from(pngURL.split(',')[1],'base64');
 check(png.readUInt32BE(16)===channel.series.time_s.length&&png.readUInt32BE(20)===2&&channel.time_frequency_map.cell_count===channel.series.time_s.length*2,'Visible full map embeds one native pixel per complete saved frequency/time cell');
 check(channel.time_frequency_map.epoch_extent_s[0]===-2.005&&channel.time_frequency_map.excluded_samples_each_edge===23&&channel.time_frequency_map.retained_extent_s[0]===-1.775,'Map preserves exact time support and explicitly masks excluded epoch edges');
 const mapFile=await file('Download time-frequency map','complete-map.svg'),svg=await fs.readFile(mapFile,'utf8');
 check(svg.includes(channel.report_hash)&&svg.includes('data:image/png;base64,')&&svg.includes('baseline support')&&svg.includes('not continuous frequency bands')&&!/href="https?:/.test(svg),'Actual standalone map export retains native cells, units, source identity, discrete frequencies and baseline caveats');
 const htmlFile=await file('Download report','complete-report.html'),offline=await context.newPage();await offline.setViewportSize({width:390,height:844});await offline.goto(`file:///${htmlFile.replaceAll('\\','/')}`);
 check(await offline.locator('svg.brohn-neural-map:visible').count()===1&&await offline.locator('svg.brohn-neural-slice:visible').count()===1&&await offline.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Standalone report retains one complete map and exact slice with 390px reflow');
 await offline.locator('svg.brohn-neural-map:visible').screenshot({path:path.join(output,'offline-390-map.png')});await offline.close();
 await scan('corrected-desktop');await scan('corrected-390',true);
 await select('neural_plot_frequency','20');await page.locator('#neural_plot_start').fill('21');await expect(page.locator('#neural_plot_view')).toContainText('samples 21 to');await page.waitForTimeout(2500);
 const moved=await json('Download series + provenance','frequency20-window21.json');
 check(moved.displayed_window.frequency_hz===20&&moved.displayed_window.first_index===21&&moved.time_frequency_map.cell_count===channel.time_frequency_map.cell_count&&await map.locator('image').getAttribute('href')===pngURL,'Exact frequency/window selection survives polling without truncating or rescaling the complete map');
 await select('neural_plot_metric','Inter-trial phase consistency');const phase=await json('Download series + provenance','phase-map.json');
 check(phase.time_frequency_map.limits.join(',')==='0,1'&&phase.series.itc[1].every(x=>Math.abs(x-1)<1e-8),'Phase map uses the physical zero-to-one scale and exact saved phase cells');
 await select('neural_plot_cell','channel Pz');await expect(page.locator('#neural_plot_view')).toContainText('No available values');
 const empty=await json('Download series + provenance','missing-map.json'),missingPNG=await map.locator('image').getAttribute('href');
 check(empty.time_frequency_map.limits===null&&empty.time_frequency_map.missing_count===empty.time_frequency_map.cell_count&&await page.locator('#neural_plot_view svg.brohn-neural-slice').count()===0,'Zero-channel baseline ratio remains an explicitly missing full map without an invented zero trace');
 await scan('missing-map-390',true);await select('neural_plot_metric','Power before the power-baseline transform');
 const zero=await json('Download series + provenance','zero-power-map.json');
 check(zero.time_frequency_map.missing_count===0&&zero.series.power_uv2.flat().every(x=>x===0)&&await map.locator('image').getAttribute('href')!==missingPNG,'Observed raw zero power has a quantitative colour distinct from the unavailable transform');
 await scan('zero-power-map-390',true);
 await page.locator('#neural_plot_start').fill('999999');await expect(page.locator('#neural_plot_view')).toContainText('Choose a saved sample index');await page.locator('#neural_plot_start').fill('1');await expect(page.locator('#neural_plot_view')).toContainText('51 samples');
 await page.reload();await dataset(datasetId);await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${unavailable.id}"']`).click();assert.deepEqual(await json('JSON + provenance','unavailable-reopened.json'),unavailable);
 await dataset(datasetId);await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${report.id}"']`).click();assert.deepEqual(await json('JSON + provenance','corrected-reopened.json'),report);check(true,'Fresh browser reopens both immutable versions; correction did not replace the earlier unavailable report');
 check(errors.length===0,'No browser exceptions');await fs.writeFile(path.join(output,'results.json'),JSON.stringify({passed:true,origin:'original-synthetic',checks,scans,errors,config,report_ids:[unavailable.id,report.id]},null,2));console.log(JSON.stringify({checks:checks.length,scans:scans.length,output}));
}catch(error){await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,scans,errors,log,text:await page.locator('body').innerText()},null,2));throw error;}
finally{await browser.close();await fs.writeFile(path.join(folder,'stop.request'),'stop owned fixture');await Promise.all(children.map(c=>new Promise(resolve=>{if(c.exitCode!==null)return resolve();c.once('exit',resolve);setTimeout(()=>{if(c.exitCode===null)c.kill();resolve();},5000).unref();})));await fs.writeFile(path.join(output,'server.log'),log);}
