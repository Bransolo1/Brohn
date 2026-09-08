// Actual researcher UI: original EDF/CSV -> explicit recipes -> retained plots.
import {importTransferredSource} from './helpers/source-import.mjs';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const output=path.resolve('../../work/test-runs/brohn-neural-plots-ui-evidence');
await fs.mkdir(output,{recursive:true});
const generated=spawnSync(path.resolve('../../work/tooling/methods-venv/Scripts/python.exe'),['-B','tests/fixtures/researcher-neural-plots.py',output],{encoding:'utf8',windowsHide:true});
assert.equal(generated.status,0,generated.stderr);
const oracle=JSON.parse(await fs.readFile(path.join(output,'oracle.json'),'utf8'));
const events=await fs.readFile(path.join(output,'events.csv'),'utf8');
const browser=await chromium.launch({channel:'chrome',headless:true});
const context=await browser.newContext({viewport:{width:1440,height:1080}});
let page=await context.newPage();
const checks=[],errors=[],violations=[],exportIssues=[],reports={},prefix=`Original neural plots UI ${Date.now()}`;
const base=process.env.BROHN_QA_URL||'http://127.0.0.1:3851/';
const workspace=path.resolve(process.env.BROHN_QA_WORKSPACE||'../../work/test-runs/brohn-connected-02');
page.on('pageerror',e=>errors.push(e.message));
function check(ok,label){assert.ok(ok,label);checks.push(label);console.log(`PASS ${label}`);}
function near(a,b,tolerance=1e-7){return Number.isFinite(a)&&Math.abs(a-b)<=tolerance;}
async function select(id,label){const box=page.locator(`#${id}-selectized`);await box.click();await box.fill(label);await box.press('Enter');}
async function detail(text){const node=page.locator('summary').filter({hasText:text});if(!await node.evaluate(e=>e.parentElement.open))await node.click();}
async function idle(){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&![...document.querySelectorAll('.recalculating')].some(e=>e.getClientRects().length));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);}
async function download(label,name){const link=page.getByRole('link',{name:label,exact:true});await expect(link).toHaveAttribute('href',/session\/.*download\//);const pending=page.waitForEvent('download');await link.click();const received=await pending;assert.equal(await received.failure(),null);const file=path.join(output,name);await received.saveAs(file);return file;}
async function json(label,name){return JSON.parse(await fs.readFile(await download(label,name),'utf8'));}
async function inspect(reportFile,name){const target=path.join(output,`${name}-verified.json`);const result=spawnSync(path.resolve('../../work/native-r/bin/Rscript.exe'),['--vanilla','tests/fixtures/researcher-neural-plots-inspect.R',workspace,reportFile,target],{encoding:'utf8',windowsHide:true,env:{...process.env,R_LIBS_USER:path.resolve('../../work/r-library-brohn-restore'),R_USER:path.resolve('../../work'),LC_ALL:'C'}});assert.equal(result.status,0,result.stderr);return JSON.parse(await fs.readFile(target,'utf8'));}
async function upload(file,title){await page.getByRole('button',{name:'Data library',exact:true}).click();await page.getByLabel('Dataset name',{exact:true}).fill(title);await select('dataset_origin','Synthetic example');await select('dataset_modality','EEG');await importTransferredSource(page,path.join(output,file));await page.getByRole('heading',{name:title,exact:true}).waitFor();await idle();}
async function configure(recipe,native=false){
 if(!native){await select('map_values','Cz');await select('map_values','Pz');await select('map_time_unit','Seconds');await page.locator('#map_sampling_rate').fill('100');await page.locator('#map_unit').fill('uV');}
 await select('map_neural_recipe',recipe);
 await page.locator('#map_neural_event_codes').fill('A = condition-a\nB = condition-absent');
 if(native){await page.locator('#map_neural_native_rate').fill('100');await page.locator('#map_neural_participant').fill('ORIGINAL-P1');await page.locator('#map_neural_session').fill('ORIGINAL-S1');}
 else await select('map_neural_event_mode','Measured event list');
 await page.locator('#map_neural_events').fill(events);
 await page.locator('#map_neural_event_source').fill('Original synthetic exact sample-clock onsets at3,8,13seconds. No browser/device synchronization or physical measurement claim.');
 const erp=recipe.includes('(ERP)');
 for(const[id,value]of Object.entries({epoch_start:erp?-.2:-2,epoch_end:erp?.6:2,minimum_trials:2}))await page.locator(`#map_neural_${id}`).fill(String(value));
 await select('map_neural_voltage_baseline',erp?'Subtract a pre-onset mean':'Keep original voltage offset');
 if(erp){await page.locator('#map_neural_baseline_start').fill('-.2');await page.locator('#map_neural_baseline_end').fill('-.01');}
 await detail('3. Reference, filtering and artifact rules');
 await select('map_neural_reference','Retain acquisition reference');await page.locator('#map_neural_reference_source').fill('Original generated voltages relative to a synthetic zero reference.');
 await select('map_neural_filter','No additional filter');
 await page.locator('#map_neural_reject_start').fill(erp?'-.2':'-2');await page.locator('#map_neural_reject_end').fill(erp?'.6':'2');
 await page.getByLabel('Reject trials with excessive peak-to-peak amplitude',{exact:true}).check();await page.locator('#map_neural_peak_uv').fill('100');
 await page.getByLabel('Reject flat trials',{exact:true}).uncheck();
 await page.locator('#map_neural_settings_source').fill('Original independently specified synthetic QA protocol. Preserve separate channels and absent conditions; minimum2trials, no filter, no amplitude repair or participant-level inference.');
 await page.getByLabel('Recording provenance and collection notes',{exact:true}).fill('Entirely original generated source bytes. The explicit person and visit codes label synthetic fixture rows; preserve this sample origin and original clock.');
}
async function analyse(){await page.getByRole('button',{name:'Confirm mapping and analyse',exact:true}).click();const open=page.locator('#dataset_reports').getByRole('button',{name:'Open report',exact:true}).first();await expect(async()=>{if(await open.count())return;const text=await page.locator('#dataset_reports').innerText();assert.ok(!/\bfailed\b/.test(text),text);assert.ok(await open.count(),text);}).toPass({timeout:120000,intervals:[500,1000,2000]});await open.click();await page.getByRole('heading',{name:'Explore neural responses',exact:true}).waitFor();await expect(page.locator('#neural_plot_view')).toContainText('Showing exact saved samples');await idle();}
async function chooseChannel(channel){await select('neural_plot_cell',`channel ${channel}`);await expect(page.locator('#neural_plot_view')).toContainText(`channel ${channel}`);await idle();}
async function axe(label,narrow=false){
 await page.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});await idle();
 const chart=page.locator('#neural_plot_view svg:visible');if(await chart.count()){
  await chart.scrollIntoViewIfNeeded();const geometry=await chart.evaluate(svg=>{const outer=svg.getBoundingClientRect();return{outer:{x:outer.x,y:outer.y,width:outer.width,height:outer.height},box:svg.getAttribute('viewBox'),text:[...svg.querySelectorAll('text')].map(t=>{const r=t.getBoundingClientRect();return{text:t.textContent,x:r.x,right:r.right,y:r.y,bottom:r.bottom};})};});
  await fs.writeFile(path.join(output,`${label}-geometry.json`),JSON.stringify(geometry,null,2));
  check(geometry.text.every(t=>t.x>=geometry.outer.x-1&&t.right<=geometry.outer.x+geometry.outer.width+1&&t.y>=geometry.outer.y-1&&t.bottom<=geometry.outer.y+geometry.outer.height+1),`${label}: every visible SVG axis label stays inside the actual chart`);
  if(narrow)check(geometry.box==='0 0 320 330',`${label}: actual390px page uses compact neural axes`);
 }
 const found=(await new AxeBuilder({page}).analyze()).violations;await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(found,null,2));await page.screenshot({path:path.join(output,`${label}.png`),fullPage:true});await page.screenshot({path:path.join(output,`${label}-viewport.png`)});
 if(found.length)violations.push({label,rules:found.map(x=>x.id)});check(found.length===0,`${label}: no automated accessibility violations`);check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`${label}: no page overflow`);await page.setViewportSize({width:1440,height:1080});
}
function csvRows(text){const lines=text.trim().split(/\r?\n/);return lines.length-1;}
async function saved(name,file){
 const filename=await download('JSON + provenance',`${name}-report.json`);const report=JSON.parse(await fs.readFile(filename,'utf8'));const verified=await inspect(filename,name);reports[name]=report;
 check(report.analysis.source.sha256===oracle.hashes[file]&&report.provenance.source.hash===oracle.hashes[file]&&Object.values(verified.objects).every(x=>x.actual===x.hash),`${name}: real source/result objects and downloaded report retain verified immutable hashes`);
 check(report.origin==='sample'&&report.analysis.quality.participant_inference_performed===false&&!report.analysis.quality.scientifically_qualified,`${name}: original sample origin and within-recording scope are explicit`);
 const exported=await json('Download series + provenance',`${name}-channel.json`);check(exported.report_hash===verified.report_hash&&exported.source_hash===oracle.hashes[file],`${name}: selected waveform export pins the exact complete report and source`);
 return{report,verified,exported};
}
async function htmlCheck(name,expected){const file=await download('Download report',`${name}.html`),html=await fs.readFile(file,'utf8');check(html.includes('Neural responses in context')&&html.includes(expected)&&!/<script[\s>]/.test(html),`${name}: actual standalone HTML carries the supported neural plot without script`);const offline=await context.newPage();await offline.setViewportSize({width:390,height:844});await offline.goto(`file:///${file.replaceAll('\\','/')}`);const layout={plots:await offline.locator('.brohn-neural-plots svg:visible').count(),...(await offline.evaluate(()=>({width:innerWidth,documentWidth:document.documentElement.scrollWidth,hasHeadStyle:!!document.querySelector('head style')})))};await fs.writeFile(path.join(output,`${name}-offline-summary.json`),JSON.stringify(layout,null,2));if(layout.plots!==1||layout.documentWidth>layout.width+1||!layout.hasHeadStyle)exportIssues.push({name,...layout});else check(true,`${name}: standalone HTML retains its head, one compact plot and reflows at390px`);await offline.close();}
try{
 await page.goto(base);await page.getByRole('heading',{name:'Your next discovery starts here.',exact:true}).waitFor();
 await upload('original-pulse.edf',`${prefix} native ERP`);
 await page.getByRole('button',{name:'Inspect recording header',exact:true}).click();await page.getByRole('heading',{name:'Header ready for review',exact:true}).waitFor({timeout:90000});
 await select('native_header_channels','Cz');await select('native_header_channels','Pz');await page.getByRole('button',{name:'Confirm channels and units',exact:true}).click();await expect(page.locator('#map_sampling_rate')).toHaveValue('100');
 await configure('Event-related response (ERP)',true);await page.locator('#map_neural_amplitude_start').fill('.2');await page.locator('#map_neural_amplitude_end').fill('.39');await select('map_neural_polarity','Positive peak');await analyse();
 const erp=await saved('erp','original-pulse.edf');
 for(const[channel,value]of Object.entries(oracle.erp_uv)){const f=erp.report.analysis.features.find(f=>f.channel===channel&&f.name==='erp_mean_amplitude');check(near(f.value,value)&&f.trial_count===3,`ERP ${channel}: actual native calibration and baseline preserve independent${value}uV evoked pulse`);}
 check(erp.report.analysis.recordings.some(r=>r.condition_id==='condition-absent'&&r.status==='unavailable'&&r.retained_trials===0),'ERP missing condition is an unavailable support outcome, not a zero evoked response');
 await chooseChannel('Pz');let channel=await json('Download series + provenance','erp-pz.json');check(channel.series.channel==='Pz'&&near(Math.max(...channel.series.mean_uv),20)&&channel.series.sem_uv.every(x=>x!==null&&Math.abs(x)<1e-9),'Actual channel selector exposes only Pz with saved20uV and within-trial SEM');
 await page.locator('#neural_plot_start').fill('11');await expect(page.locator('#neural_plot_view')).toContainText('samples 11 to');await page.waitForTimeout(2400);await expect(page.locator('#neural_plot_start')).toHaveValue('11');check((await json('Download series + provenance','erp-pz-window.json')).displayed_window.first_index===11,'ERP channel and exact first index survive background workspace polling');
 const erpCSV=await fs.readFile(await download('Download complete channel series','erp-pz-complete.csv'),'utf8');check(csvRows(erpCSV)===channel.series.time_s.length&&erpCSV.includes('sem_uv'),'Actual full ERP CSV includes every sample beyond the displayed window and explicit SEM');
 const erpSVG=await fs.readFile(await download('Download displayed chart','erp-pz.svg'),'utf8');check(erpSVG.includes(erp.verified.report_hash)&&erpSVG.includes('uV')&&erpSVG.includes('role="img"'),'Actual SVG chart export carries saved report identity, voltage units and accessible description');await axe('erp-pz');await axe('erp-pz-narrow',true);await htmlCheck('erp','within this recording and condition');

 await upload('morlet.csv',`${prefix} Morlet`);await configure('Time-frequency response (Morlet)');
 await page.locator('#map_neural_frequencies').fill('10, 20');await page.locator('#map_neural_cycles').fill('3, 3');await select('map_neural_power','Total trial power');await page.locator('#map_neural_summary_start').fill('0');await page.locator('#map_neural_summary_end').fill('.5');await select('map_neural_power_baseline','Divide by baseline power');await page.locator('#map_neural_power_baseline_start').fill('-1');await page.locator('#map_neural_power_baseline_end').fill('-.5');await page.locator('#map_neural_power_floor').fill('0.00000000000000000001');await analyse();
 const morlet=await saved('morlet','morlet.csv');const mf=morlet.report.analysis.features.find(f=>f.channel==='Cz'&&f.name==='morlet_power_mean'&&f.frequency_hz===10);check(near(mf.value,1)&&mf.unit==='ratio','Actual Morlet source retains independently expected stationary power-baseline ratio near one');
 await select('neural_plot_frequency','20');await select('neural_plot_metric','Inter-trial phase consistency');await page.locator('#neural_plot_start').fill('21');await expect(page.locator('#neural_plot_view')).toContainText('samples 21 to');await page.waitForTimeout(2400);channel=await json('Download series + provenance','morlet-phase20.json');
 check(channel.displayed_window.frequency_hz===20&&channel.displayed_window.metric==='itc'&&channel.displayed_window.first_index===21&&channel.series.frequency_hz.join(',')==='10,20','Frequency, phase measure and window survive polling while complete export retains both original frequencies');
 check(channel.series.array_axes.join(',')==='frequency,time'&&channel.series.itc[1].every(x=>near(x,1,1e-8)),'Actual downloaded Morlet matrix retains correct axes and exact original-signal phase support');
 const morletCSV=await fs.readFile(await download('Download complete channel series','morlet-complete.csv'),'utf8');check(csvRows(morletCSV)===channel.series.time_s.length*2&&morletCSV.includes('transformed_power')&&morletCSV.includes('power_uv2'),'Actual full Morlet CSV includes all frequency/time rows and all saved power/phase arrays');await axe('morlet-phase');await axe('morlet-phase-narrow',true);await htmlCheck('morlet','recorded frequency 10 Hz');
 await page.locator('#neural_plot_start').fill('999999');await expect(page.locator('#neural_plot_view')).toContainText('Choose a saved sample index');await page.waitForTimeout(2400);await expect(page.locator('#neural_plot_start')).toHaveValue('999999');check(true,'Invalid neural window remains actionable and editable across polling');await page.locator('#neural_plot_start').fill('1');await expect(page.locator('#neural_plot_view')).toContainText('Showing exact saved samples');
 await chooseChannel('Pz');await expect(page.locator('#neural_plot_view')).toContainText('no zero-valued response');channel=await json('Download series + provenance','morlet-zero-channel.json');
 check(channel.series.channel==='Pz'&&channel.series.transformed_power.flat().every(x=>x===null)&&channel.series.itc.flat().every(x=>x===null)&&await page.locator('#neural_plot_view svg').count()===0,'Actual zero signal has unavailable ratio/phase and no fabricated zero-line chart');
 await select('neural_plot_metric','Power before the power-baseline transform');await expect(page.locator('#neural_plot_view svg:visible')).toHaveCount(1);check((await json('Download series + provenance','morlet-zero-raw.json')).series.power_uv2.flat().every(x=>x===0),'Raw zero wavelet power remains available separately from its undefined baseline ratio');await axe('morlet-zero-narrow',true);

 await upload('tagging.csv',`${prefix} frequency tagging`);await configure('Frequency-tagged response (SSVEP)');
 await page.locator('#map_neural_spectral_start').fill('0');await page.locator('#map_neural_spectral_end').fill('2');await page.locator('#map_neural_tags').fill('10');await page.locator('#map_neural_harmonics').fill('1');await select('map_neural_taper','Boxcar');await page.locator('#map_neural_neighbors').fill('2');await page.locator('#map_neural_skip_bins').fill('1');await page.locator('#map_neural_bin_tolerance').fill('0');await analyse();
 const tag=await saved('tag','tagging.csv'),feature=name=>tag.report.analysis.features.find(f=>f.channel==='Cz'&&f.name===name);
 check(near(feature('tag_bin_density').value,400)&&near(feature('tag_noise_density').value,4)&&near(feature('tag_snr').value,100),'Actual declared spectral window yields independent target density400, noise4 and SNR100');
 check(tag.report.analysis.series.find(s=>s.channel==='Cz').frequency_hz[20]===10&&feature('tag_bin_density').frequency_bin_width_hz===.5,'Saved target marker is exact10Hz bin with original0.5Hz resolution');await axe('tagging');await axe('tagging-narrow',true);await htmlCheck('tag','Spectral window:');
 await chooseChannel('Pz');check((await json('Download series + provenance','tag-zero.json')).features.find(f=>f.name==='tag_snr').value===null,'Zero-channel tagging retains missing SNR instead of infinity while preserving the zero PSD');
 const featureCSV=await fs.readFile(await download('Download observations','tag-features.csv'),'utf8');check(featureCSV.includes('unavailable_or_zero_noise_denominator'),'Actual feature CSV preserves unavailable SNR denominator evidence');
 for(const[name,report]of Object.entries(reports)){check(report.analysis.artifacts.length===0,`${name}: complete neural arrays are retained in the immutable JSON, without a fabricated external artifact`);}
 assert.deepEqual(await json('JSON + provenance','tag-after-exploration.json'),tag.report);check(true,'Actual plot selection and downloads leave the saved tagging report unchanged');
 const fresh=await browser.newContext({viewport:{width:1440,height:1080}});page=await fresh.newPage();page.on('pageerror',e=>errors.push(e.message));await page.goto(base);await page.getByRole('button',{name:'Data library',exact:true}).click();await page.getByLabel('Search datasets',{exact:true}).fill(`${prefix} native ERP`);await page.locator(`[data-brohn-event="open_dataset"][data-brohn-value='"${erp.report.dataset_id}"']`).click();await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${erp.report.id}"']`).click();await page.getByRole('heading',{name:'Explore neural responses',exact:true}).waitFor();assert.deepEqual(await json('JSON + provenance','erp-fresh-session.json'),erp.report);check(true,'Fresh researcher session reopens the exact historical ERP report and its original arrays');
 check(errors.length===0,`No browser exceptions: ${errors.join(';')}`);check(violations.length===0,'All neural accessibility scans are clear');check(exportIssues.length===0,`All standalone neural exports retain head and reflow: ${JSON.stringify(exportIssues)}`);await fs.writeFile(path.join(output,'results.json'),JSON.stringify({origin:'original_synthetic',checks,report_ids:Object.fromEntries(Object.entries(reports).map(([name,r])=>[name,r.id])),output},null,2));console.log(JSON.stringify({checks:checks.length,output}));
}catch(error){await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,errors,violations,exportIssues,text:await page.locator('body').innerText()},null,2));throw error;}finally{await browser.close();}
