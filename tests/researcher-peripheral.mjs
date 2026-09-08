// Actual Chrome -> Shiny -> background source ingestion -> production workers.
// Original synthetic source cells, explicit identity links and independent oracles.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const slowResumeIndex=process.argv.indexOf('--resume-slow');
const resumeSlow=slowResumeIndex>=0;
const resumeIndex=resumeSlow?slowResumeIndex:process.argv.indexOf('--resume-sources');
const resume=resumeIndex>=0;
const folder=resume?path.resolve(process.argv[resumeIndex+1]):await fs.mkdtemp(path.resolve('../../work/test-runs/brohn-peripheral-ui-'));
assert.equal(path.dirname(folder),path.resolve('../../work/test-runs'));assert.match(path.basename(folder),/^brohn-peripheral-ui-/);
const output=path.join(folder,'evidence');await fs.mkdir(output,{recursive:true});
const checkpointPath=path.join(output,resumeSlow?'slow-checkpoint.json':'source-checkpoint.json');
const checkpoint=resume?JSON.parse(await fs.readFile(checkpointPath,'utf8')):null;
if(resume)await fs.rm(path.join(folder,'stop.request'),{force:true});
const r=path.resolve('../../work/native-r/bin/x64/Rscript.exe');
const python=path.resolve('../../work/tooling/methods-venv/Scripts/python.exe');
const env={...process.env,R_LIBS_USER:path.resolve('../../work/r-library-brohn'),R_USER:path.resolve('../../work'),LC_ALL:'C'};
function helper(mode){const child=spawnSync(r,['--vanilla','tests/fixtures/researcher-peripheral.R',mode,folder],{env,encoding:'utf8',windowsHide:true});assert.equal(child.status,0,child.stderr);}
if(!resume)helper('create');let fixture=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
const app=spawn(r,['--vanilla','tests/fixtures/researcher-peripheral.R','serve',folder],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});
let log='';for(const stream of [app.stdout,app.stderr])stream.on('data',b=>log+=b);
const browser=await chromium.launch({channel:'chrome',headless:true});
let context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage();
const checks=checkpoint?.checks||[],scans=checkpoint?.scans||[],errors=[],records=checkpoint?.records||{};
const watch=p=>p.on('pageerror',e=>errors.push(e.message));watch(page);
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log(`PASS ${label}`);};
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const stage=name=>page.getByRole('button',{name,exact:true}).click();
async function select(id,label){const input=page.locator(`#${id}-selectized`);await input.click();await input.fill(label);const exact=page.locator('.selectize-dropdown:visible').getByRole('option',{name:label,exact:true});if(await exact.count())await exact.click();else await page.locator('.selectize-dropdown:visible .option').filter({hasText:label}).click();}
async function inspect(){helper('inspect');return JSON.parse(await fs.readFile(path.join(folder,'snapshot.json'),'utf8'));}
async function idle(){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&![...document.querySelectorAll('.recalculating')].some(e=>e.getClientRects().length));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);}
async function axe(label,narrow=false){
  await page.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});await idle();
  const violations=(await new AxeBuilder({page}).analyze()).violations;scans.push({label,count:violations.length});
  await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(violations,null,2));
  await page.screenshot({path:path.join(output,`${label}.png`),fullPage:true});
  check(violations.length===0,`${label}: no automated accessibility violations`);
  check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`${label}: no page overflow`);
  await page.setViewportSize({width:1440,height:1080});
}
async function download(label,name){const link=page.getByRole('link',{name:label,exact:true});await expect(link).toHaveAttribute('href',/session\/.*download\//);const pending=page.waitForEvent('download');await link.click();const item=await pending;assert.equal(await item.failure(),null);const file=path.join(output,name);await item.saveAs(file);return file;}
async function json(label,name){return JSON.parse(await fs.readFile(await download(label,name),'utf8'));}
function csv(file){const child=spawnSync(python,['-c',"import sys,csv,json;print(json.dumps(list(csv.DictReader(open(sys.argv[1],encoding='utf-8',newline='')))))",file],{encoding:'utf8',windowsHide:true});assert.equal(child.status,0,child.stderr);return JSON.parse(child.stdout);}
async function openStudy(){await stage('Studies');await page.getByLabel('Search studies',{exact:true}).fill(fixture.title);await page.locator(`[data-brohn-event="brohn_open_study"][data-brohn-value='"${fixture.study_id}"']`).click();await page.getByLabel('Study name',{exact:true}).waitFor();}
async function openDataset(dataset){await stage('Data library');await page.getByLabel('Search datasets',{exact:true}).fill(dataset.body.title);await page.locator(`[data-brohn-event="open_dataset"][data-brohn-value='"${dataset.id}"']`).click();await expect(page.locator('#dataset_form_identity')).toHaveValue(new RegExp(`^${dataset.id}:`));}
async function upload(key,title,family){
  const before=await inspect();
  await stage('Data library');await page.getByLabel('Dataset name',{exact:true}).fill(title);
  await select('dataset_origin','Synthetic example');await select('dataset_modality',family);
  await page.locator('#dataset_upload').setInputFiles(fixture.files[key].path);
  await page.getByRole('button',{name:'Import this file',exact:true}).waitFor();
  await page.waitForFunction(()=>{const field=document.getElementById('ingestion_upload_review_identity');return field?.value&&field.value===Shiny.shinyapp.$inputValues.ingestion_upload_review_identity;});
  await expect(page.locator('body')).toContainText(path.basename(fixture.files[key].path));
  const transferred=await inspect();assert.equal(transferred.ingestions.length,before.ingestions.length);assert.equal(transferred.datasets.length,before.datasets.length);
  await page.getByRole('button',{name:'Import this file',exact:true}).click();
  await expect(page.getByRole('heading',{name:title,exact:true})).toBeVisible({timeout:120000});
  await page.locator('#dataset_form_identity').waitFor({state:'attached'});await idle();
  const snapshot=await inspect(),dataset=snapshot.datasets.find(d=>d.body.title===title);
  assert.ok(dataset);assert.equal(dataset.source_sha256,fixture.files[key].sha256);
  const ingestion=snapshot.ingestions.find(i=>i.body.review.title===title);
  assert.ok(ingestion,'Actual upload must use a durable background ingestion');
  assert.equal(ingestion.body.review.study_id,null);assert.equal(ingestion.body.review.origin,'sample');
  const job=snapshot.jobs.find(j=>j.operation==='ingest_source'&&j.result?.dataset_id===dataset.id);
  assert.ok(job&&job.status==='succeeded',JSON.stringify(snapshot.jobs));
  check(true,`${key}: actual background import retains original bytes and opens its prepared mapping`);
  return dataset;
}
const notes='Original generated research QA values only. Prefixes temp-, motion- and like- identify sources; 001 through004 and V1/V2 identify four fictional people and five visits. No person, device, measurement accuracy or physiological interpretation is claimed.';
async function mapBase(){await select('map_study',fixture.title);await page.locator('#map_study_revision-selectized').waitFor();await select('map_study_revision',`Revision ${fixture.study_revision}`);await page.locator('#map_origin').fill(notes);}
async function mapPeripheral(modality,{conditions=true}={}){
  await mapBase();await select('map_time_unit','Seconds');await page.locator('#map_sampling_rate').fill('1');
  await page.locator('#map_peripheral_site').fill('Original synthetic right-hand sensor frame; no actual skin or hardware.');
  await page.locator('#map_peripheral_calibration').fill('Original numerical generator supplies physical units directly; no empirical calibration performed.');
  await page.locator('#map_peripheral_filters').fill('None; original generated source values.');
  if(modality==='temperature'){
    await select('map_values','degrees_f');await select('map_unit','Degrees Fahrenheit');
    if(conditions)await page.locator('#map_peripheral_conditions').fill('Original synthetic environment; ambient temperature and settling time were not measured. These conditions are explicitly unknown.');
    await page.locator('#map_peripheral_threshold').check();await select('map_peripheral_threshold_metric','Temperature in degrees Celsius');
    await select('map_peripheral_threshold_direction','Above the threshold');
    for(const[id,value]of Object.entries({on:'35',off:'34',duration:'1'}))await page.locator(`#map_peripheral_threshold_${id}`).fill(value);
    await page.locator('#map_peripheral_threshold_source').fill('Original numerical excursion example: entry at or above35C, strict recovery below34C, minimum observed span1second. This is not a physiological response threshold.');
  }else{
    for(const channel of ['ax','ay','az'])await select('map_values',channel);
    await select('map_unit','Standard gravity (g)');
    for(const[axis,label]of Object.entries({x:'+X right',y:'+Y forward',z:'+Z upward'}))await page.locator(`#map_peripheral_axis_${axis}`).fill(label);
    await select('map_peripheral_gravity','Source includes gravity');await select('map_peripheral_enmo','Set negative values to zero');
  }
}
async function waitReport(dataset){
  const open=page.locator('#dataset_reports').getByRole('button',{name:'Open report',exact:true}).first();
  await expect.poll(async()=>{
    if(await open.count())return true;
    const mappingError=page.locator('#platform_error');if(await mappingError.isVisible()&&await mappingError.innerText())throw new Error(await mappingError.innerText());
    if(await page.locator('#dataset_reports .brohn-badge').filter({hasText:/^failed$/}).count())throw new Error(await page.locator('#dataset_reports').innerText());
    return false;
  },{timeout:180000,intervals:[500,1000,2000]}).toBe(true);
  await open.click();await page.getByRole('link',{name:'JSON + provenance',exact:true}).waitFor();
  const report=await json('JSON + provenance',`${dataset.id}-report.json`);
  const snapshot=await inspect(),saved=snapshot.reports.find(r=>r.id===report.id);
  assert.deepEqual(report,saved.body);assert.equal(report.dataset_id,dataset.id);
  assert.equal(report.provenance.source.hash,dataset.source_sha256);
  assert.ok(snapshot.report_integrity.find(i=>i.id===report.id)?.envelope_matches,'Catalog must exactly match publication envelope');
  assert.ok(snapshot.report_integrity.find(i=>i.id===report.id)?.object_hash_matches);
  check(true,`${dataset.body.modality}: automatic worker publishes exact immutable report and source provenance`);
  return report;
}
async function artifacts(report,kind,prefix){
  await select('report_artifact_kind',kind.replaceAll('-',' '));
  const bytes=await fs.readFile(await download('Download complete artifact',`${prefix}-${kind}.jsonl`));
  const artifact=report.analysis.artifacts.find(a=>a.kind===kind);assert.equal(hash(bytes),artifact.hash);
  const lines=bytes.toString('utf8').trim().split(/\r?\n/).map(JSON.parse);assert.equal(lines[0].type,'header');assert.equal(lines.at(-1).type,'complete');
  const tables=new Map(),rows=[];for(const line of lines){if(line.type==='table')tables.set(line.table_id,line);if(line.type==='rows'){const table=tables.get(line.table_id);rows.push(...line.rows.map(row=>({table,values:Object.fromEntries(table.columns.map((column,i)=>[column.name,row[i]]))})));}}
  assert.equal(rows.length,artifact.rows);check(true,`${prefix} ${kind}: full typed download matches its immutable hash and row count`);return{lines,tables,rows};
}
async function reportExports(report,prefix){
  const data=csv(await download('Download observations',`${prefix}-features.csv`));assert.equal(data.length,report.analysis.features.length);
  const file=await download('Download report',`${prefix}-report.html`),html=await fs.readFile(file,'utf8');assert.ok(html.includes(report.id)&&/<head[\s>]/i.test(html));
  const offline=await context.newPage();await offline.goto(`file:///${file.replaceAll('\\','/')}`);await expect(offline.locator('h1')).toBeVisible();await offline.close();
  check(true,`${prefix}: complete feature CSV and standalone HTML are usable exports`);
}
try{
  await expect.poll(async()=>{if(app.exitCode!==null)throw new Error(log);try{return(await fetch(`http://127.0.0.1:${fixture.port}/`)).status===200;}catch{return false;}},{timeout:60000,intervals:[250,500,1000]}).toBe(true);
  await page.goto(`http://127.0.0.1:${fixture.port}/`);
  let temperatureDataset,temperature,movementDataset,movement;
  if(resume){
    ({temperatureDataset,temperature,movementDataset,movement}=checkpoint);
    const retained=await inspect();
    for(const report of checkpoint.completedReports||[temperature,movement]){assert.deepEqual(retained.reports.find(r=>r.id===report.id)?.body,report);assert.ok(retained.report_integrity.find(r=>r.id===report.id)?.envelope_matches);assert.ok(retained.report_integrity.find(r=>r.id===report.id)?.object_hash_matches);}
    assert.equal(retained.datasets.find(d=>d.id===temperatureDataset.id).source_sha256,fixture.files.temperature.sha256);
    assert.equal(retained.datasets.find(d=>d.id===movementDataset.id).source_sha256,fixture.files.movement.sha256);
    if(!resumeSlow){await openDataset(movementDataset);await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${movement.id}"']`).click();
    await page.getByRole('link',{name:'JSON + provenance',exact:true}).waitFor();}
    check(true,'Saved-source continuation independently verifies original hashes and exact prior reports before resuming the remaining UI');
  }else{
  await stage('Create a study');
  const dialog=page.getByRole('dialog');await dialog.getByLabel('Study name',{exact:true}).fill(fixture.title);
  await dialog.getByLabel('Controlled concept comparison',{exact:true}).check();await dialog.getByRole('button',{name:'Create study',exact:true}).click();
  await page.getByLabel('Study name',{exact:true}).waitFor();await page.locator('#condition_label_1').fill('Standard refill pack');await page.locator('#condition_label_2').fill('Easy-grip refill pack');
  await page.locator('#stimulus_title_1').fill('Standard refill package');await page.locator('#stimulus_title_2').fill('Easy-grip refill package');
  await page.locator('#stimulus_text_1').fill('Original standard refill pack with a smooth cylindrical grip.');await page.locator('#stimulus_text_2').fill('Original refill pack with a textured easy-grip panel.');
  await page.getByLabel('Temperature',{exact:true}).check();await page.getByLabel('Movement',{exact:true}).check();await page.getByLabel('Eye tracking',{exact:true}).uncheck();await stage('Save');
  await stage('Questions');await page.locator('#q_prompt_1').fill('How much do you like this refill package?');await stage('Save');await stage('Plan');
  helper('sources');fixture=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));records.study_id=fixture.study_id;
  assert.deepEqual(fixture.design.conditions.map(c=>c.role),['control','test']);assert.equal(fixture.design.baseline_ms,0);
  assert.deepEqual([...fixture.design.measures].sort(),['movement','questionnaire','temperature']);
  check(true,'Actual study authoring saves original control/test materials and liking without calling a control a baseline');

  const bad=await upload('bad_clock','Original temperature with duplicated clock','Temperature');await mapPeripheral('temperature');await stage('Confirm mapping and analyse');
  await expect(page.locator('#dataset_reports')).toContainText(/duplicated|reversed|Time is duplicated/,{timeout:180000});
  let snapshot=await inspect();assert.ok(snapshot.jobs.some(j=>j.request?.dataset_id===bad.id&&j.status==='failed'));assert.ok(!snapshot.reports.some(r=>r.body.dataset_id===bad.id));
  assert.equal(snapshot.datasets.find(d=>d.id===bad.id).source_sha256,fixture.files.bad_clock.sha256);
  check(true,'Duplicated source clocks fail with an actionable reason, retained bytes and no fabricated report');

  temperatureDataset=await upload('temperature','Original calibrated package temperature','Temperature');records.temperature_dataset=temperatureDataset.id;
  await mapPeripheral('temperature',{conditions:false});await stage('Confirm mapping and analyse');await expect(page.locator('#platform_error')).toContainText(/recording conditions|settling/i);
  snapshot=await inspect();assert.ok(!snapshot.jobs.some(j=>j.request?.dataset_id===temperatureDataset.id&&j.operation==='analyse_dataset'));
  await page.locator('#map_peripheral_conditions').fill('Original synthetic environment; ambient temperature and settling time were not measured. These conditions are explicitly unknown.');
  check(true,'Required temperature context is explained before queueing and can explicitly record unknown conditions');
  await axe('temperature-mapping');await axe('temperature-mapping-narrow',true);await stage('Confirm mapping and analyse');
  temperature=await waitReport(temperatureDataset);records.temperature_report=temperature.id;const tq=temperature.analysis.quality;
  assert.equal(tq.source_rows,30);assert.equal(tq.usable_samples,27);assert.equal(tq.invalid_samples,3);assert.equal(tq.supported_observed_span_s,18);assert.equal(tq.event_count,3);
  assert.equal(temperature.analysis.parameters.mapping.unit,'degF');assert.match(temperature.analysis.parameters.mapping.recording_conditions,/unknown/);
  const means=temperature.analysis.features.filter(f=>f.name==='temperature_mean');assert.equal(means.length,9);
  const expected=[30,32,30,36,30,38,30,42,30];means.forEach((f,i)=>assert.ok(Math.abs(f.value-expected[i])<1e-10));
  assert.ok(temperature.analysis.segments.some(s=>s.group.participant_id==='temp-004'&&s.status==='unavailable'));
  check(true,'Temperature report matches nine separate Celsius means,27 usable samples,18 observed seconds and3 protocol excursions; missing test remains unavailable');
  const temperatureSeries=await artifacts(temperature,'physiology-series','temperature');assert.equal(temperatureSeries.rows.length,30);assert.equal(temperatureSeries.rows.filter(r=>r.values.retained).length,27);
  const temperatureEvents=await artifacts(temperature,'physiology-events','temperature');assert.equal(temperatureEvents.rows.length,3);assert.ok(temperatureEvents.rows.every(r=>r.values.left_censored&&r.values.right_censored&&r.values.observed_span_s===2));
  await reportExports(temperature,'temperature');await axe('temperature-report-narrow',true);

  movementDataset=await upload('movement','Original calibrated package acceleration','Calibrated acceleration');records.movement_dataset=movementDataset.id;await mapPeripheral('movement');
  await select('map_peripheral_gravity','Acquisition already removed gravity');await stage('Confirm mapping and analyse');await expect(page.locator('#platform_error')).toContainText(/gravity-included|gravity/i);
  snapshot=await inspect();assert.ok(!snapshot.jobs.some(j=>j.request?.dataset_id===movementDataset.id&&j.operation==='analyse_dataset'));
  await select('map_peripheral_gravity','Source includes gravity');
  assert.deepEqual(await page.locator('#map_values option:checked').evaluateAll(options=>options.map(o=>o.value)),['ax','ay','az']);
  check(true,'ENMO refuses gravity-removed input; correcting the declaration preserves exact ordered source axes');
  await axe('acceleration-mapping-narrow',true);await stage('Confirm mapping and analyse');movement=await waitReport(movementDataset);records.movement_report=movement.id;
  assert.equal(movement.analysis.quality.source_rows,31);assert.equal(movement.analysis.quality.usable_samples,28);assert.equal(movement.analysis.quality.time_gap_count,1);
  assert.deepEqual(movement.analysis.parameters.mapping.value_columns,['ax','ay','az']);assert.equal(movement.analysis.parameters.recipe.enmo,'zero_truncated');
  assert.ok(movement.analysis.features.filter(f=>f.name==='acceleration_vector_derivative_rms').every(f=>f.value===0));
  assert.equal(movement.analysis.features.filter(f=>f.name==='acceleration_magnitude_mean').length,10);
  check(true,'Acceleration processing retains the extra separated control interval and missing axes; constant vectors have zero within-interval derivative');
  const movementSeries=await artifacts(movement,'physiology-series','movement');assert.equal(movementSeries.rows.length,31);assert.equal(movementSeries.rows.filter(r=>r.values.retained).length,28);
  await reportExports(movement,'acceleration');
  await fs.writeFile(checkpointPath,JSON.stringify({checks,scans,records,temperatureDataset,temperature,movementDataset,movement},null,2));
  }
  if(!resumeSlow){
  await stage('Explore signal traces and spectra');await page.getByRole('heading',{name:'Choose a signal view',exact:true}).waitFor({timeout:120000});
  await select('signal_table','recording-1-samples');await select('signal_measure','magnitude');await stage('Show signal');await expect(page.locator('#signal_plot')).toContainText('4 eligible values in this window',{timeout:120000});
  const full=await json('Download view + provenance','acceleration-gapped-view.json');assert.deepEqual(full.view.fragments.map(f=>[f.first_x,f.last_x]),[[0,1],[10,11]]);assert.ok(full.view.envelopes.flatMap(e=>e.points).every(p=>Math.abs(p.y-9.80665)<1e-12));
  assert.equal(full.artifact_hash,movement.analysis.artifacts.find(a=>a.kind==='physiology-series').hash);
  check(true,'Actual queued signal explorer shows two measured acceleration fragments and preserves the ten-second gap');
  await page.getByLabel('Show the complete recorded range',{exact:true}).uncheck();await page.locator('#signal_range_start').fill('1');await page.locator('#signal_range_end').fill('10');await stage('Show signal');
  await expect(page.locator('#signal_plot')).toContainText('2 eligible values in this window',{timeout:120000});await page.waitForTimeout(2400);
  await expect(page.locator('#signal_range_start')).toHaveValue('1');await expect(page.locator('#signal_range_end')).toHaveValue('10');await expect(page.locator('#signal_measure')).toHaveValue('vector_magnitude_ms2');
  const window=await json('Download view + provenance','acceleration-window.json');assert.equal(window.view.selected_range.eligible_value_rows,2);assert.equal(window.view.fragments.length,2);
  const svg=await fs.readFile(await download('Download chart','acceleration-window.svg'),'utf8');assert.ok(svg.includes('m/s2')&&svg.includes('Time (s)'));
  await axe('acceleration-window-narrow',true);assert.deepEqual(await json('JSON + provenance','acceleration-source-after-plots.json'),movement);
  check(true,'Inclusive range selection, canonical units and source report survive job publication and narrow-screen exploration');

  const likingDataset=await upload('liking','Original explicit package liking','Questionnaire');records.liking_dataset=likingDataset.id;await mapBase();await select('map_values','value');await stage('Confirm mapping and analyse');
  const liking=await waitReport(likingDataset);records.liking_report=liking.id;assert.equal(liking.analysis.observations.length,10);assert.equal(liking.analysis.contrasts[0].estimate,2.25);
  check(true,'Actual liking import keeps ten explicit ratings and the independent2.25-point equal-person contrast');

  await openStudy();await stage('Results');await stage('Combine measures');
  for(const report of [temperature,movement,liking])await select('mm_reports',report.id.slice(-6));await select('mm_origin','Sample');await stage('Review participants and measures');
  await page.getByRole('heading',{name:'Review how these measures belong together',exact:true}).waitFor();await select('mm_identity_mode','Upload a reviewed mapping');
  const template=await json('Download mapping template','peripheral-identity-template.json');assert.equal(template.length,15);
  const crosswalk=template.map(row=>({...row,participant_id:row.source_participant_id.replace(/^(temp|motion|like)-/,''),session_id:row.source_session_id.replace(/^(temp|motion|like)-/,'')}));
  assert.equal(new Set(crosswalk.map(r=>r.participant_id)).size,4);const file=path.join(output,'reviewed-person-links.json');await fs.writeFile(file,JSON.stringify(crosswalk,null,2));await page.locator('#mm_crosswalk_file').setInputFiles(file);
  await expect(page.locator('#mm_mapping_status')).toContainText('15 source identities');await page.getByLabel('I checked that shared person and session codes refer to the same people and visits',{exact:true}).check();
  await page.getByLabel('Evidence for these participant links',{exact:true}).fill(notes);
  for(const metric of ['TEMPERATURE temperature mean','MOVEMENT acceleration magnitude mean','QUESTIONNAIRE explicit rating']){await select('mm_metric',metric);await stage('Add comparison');}
  await expect(page.getByRole('button',{name:'Remove comparison',exact:true})).toHaveCount(3);await axe('peripheral-comparison-review-narrow',true);await stage('Save combined report');await page.getByRole('heading',{name:'Activity',exact:true}).waitFor();
  const combinedCard=page.locator('.brohn-card').filter({has:page.getByRole('heading',{name:'analyse multimodal',exact:true})}).first();await combinedCard.getByRole('button',{name:'Open result',exact:true}).waitFor({timeout:180000});await combinedCard.getByRole('button',{name:'Open result',exact:true}).click();
  const combined=await json('JSON + provenance','combined-peripheral-liking-report.json');records.combined_report=combined.id;
  const contrasts=combined.analysis.contrasts,t=contrasts.find(c=>c.modality==='temperature'),m=contrasts.find(c=>c.modality==='movement'),q=contrasts.find(c=>c.modality==='questionnaire');
  assert.ok(Math.abs(t.estimate-8)<1e-10);assert.equal(t.participant_count,3);assert.equal(t.paired_session_count,4);assert.equal(q.estimate,2.25);assert.equal(q.participant_count,4);assert.equal(q.paired_session_count,5);
  assert.equal(m.estimate,null);assert.equal(m.reason,'duplicate_or_ambiguous_observation_identity');assert.ok(contrasts.every(c=>c.multiplicity.family_size===3&&c.multiplicity.method==='holm'));
  check(true,'Combined report matches8C across3 people/4 visits and2.25 liking points across4 people/5 visits; fragmented same-exposure acceleration stays unavailable in the3-test family');
  assert.equal(combined.analysis.quality.cross_modal_complete_case_filter,false);
  assert.ok(combined.analysis.observations.filter(o=>o.modality==='movement').every(o=>JSON.stringify(o.definition.mapping.value_columns)==='["ax","ay","az"]'));
  for(const row of combined.analysis.observations)assert.equal(row.origin,'sample');
  check(true,'Combined output retains ordered source axes, explicit leading-zero people and source-specific missingness without inventing complete cases');
  const combinedCSV=csv(await download('Download observations','combined-peripheral-observations.csv'));assert.equal(combinedCSV.length,combined.analysis.observations.length);
  const combinedHTML=await fs.readFile(await download('Download report','combined-peripheral-report.html'),'utf8');assert.ok(combinedHTML.includes(combined.id));await axe('peripheral-combined-report');await axe('peripheral-combined-report-narrow',true);

  await context.close();context=await browser.newContext({viewport:{width:1440,height:1080}});page=await context.newPage();watch(page);await page.goto(`http://127.0.0.1:${fixture.port}/`);
  await openDataset(temperatureDataset);await expect(page.locator('#map_unit')).toHaveValue('degF');await expect(page.locator('#map_peripheral_conditions')).toHaveValue(/explicitly unknown/);
  const original=await fs.readFile(await download('Download original source','temperature-original-reopened.csv'));assert.equal(hash(original),fixture.files.temperature.sha256);
  await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${temperature.id}"']`).click();assert.deepEqual(await json('JSON + provenance','temperature-reopened-report.json'),temperature);
  check(true,'Fresh researcher session reopens the exact temperature mapping, source bytes and saved report');
  }
  helper('slow-source');fixture=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
  const slowDataset=resumeSlow?checkpoint.slowDataset:await upload('slow','Original slow calibrated temperature','Calibrated temperature');
  if(resumeSlow){await openDataset(slowDataset);const retained=await inspect();assert.equal(retained.datasets.find(d=>d.id===slowDataset.id).source_sha256,fixture.files.slow.sha256);assert.ok(!retained.jobs.some(j=>j.request?.dataset_id===slowDataset.id));}
  else{const retained=await inspect();await fs.writeFile(path.join(output,'slow-checkpoint.json'),JSON.stringify({checks,scans,records,temperatureDataset,temperature,movementDataset,movement,slowDataset,completedReports:retained.reports.map(r=>r.body)},null,2));}
  await mapPeripheral('temperature');
  await page.locator('#map_peripheral_threshold').uncheck();await page.locator('#map_sampling_rate').fill('0.1');await expect(page.locator('#map_peripheral_min_duration')).toHaveValue('');
  await fs.writeFile(path.join(output,'slow-mapping-bound-inputs.json'),JSON.stringify(await page.evaluate(()=>({values:Object.fromEntries(Object.entries(Shiny.shinyapp.$inputValues).filter(([key])=>/map_sampling_rate|map_peripheral_min_duration|map_peripheral_threshold(:|$)/.test(key))),duration:document.getElementById('map_peripheral_min_duration').value})),null,2));
  await stage('Confirm mapping and analyse');const slow=await waitReport(slowDataset);records.slow_report=slow.id;
  assert.equal(slow.analysis.parameters.recipe.minimum_duration_s,10);assert.equal(slow.analysis.quality.usable_samples,3);
  assert.equal(slow.analysis.quality.supported_observed_span_s,20);assert.ok(Math.abs(slow.analysis.features.find(f=>f.name==='temperature_mean').value-21)<1e-10);
  assert.equal(slow.analysis.quality.event_detection_requested,false);assert.equal(slow.analysis.quality.event_count,null);
  check(true,'First-time0.1Hz mapping uses the automatic10-second support minimum and computes21C without a manual duration correction');
  await openDataset(slowDataset);await expect(page.locator('#map_sampling_rate')).toHaveValue('0.1');await expect(page.locator('#map_peripheral_min_duration')).toHaveValue('10');
  const slowOriginal=await fs.readFile(await download('Download original source','slow-original-reopened.csv'));assert.equal(hash(slowOriginal),fixture.files.slow.sha256);
  check(true,'Reopened slow mapping displays its frozen10-second support choice and the unchanged original source');
  const finalSnapshot=await inspect();assert.equal(finalSnapshot.reports.length,5);assert.ok(finalSnapshot.report_integrity.every(i=>i.envelope_matches&&i.object_hash_matches));assert.ok(finalSnapshot.jobs.every(j=>!['queued','running'].includes(j.status)));
  check(true,'Every successful catalog body still matches its retained publication envelope after the slow-source extension');
  check(errors.length===0&&scans.every(s=>s.count===0),'No browser exceptions, visible Shiny errors or automated accessibility violations');
  await fs.writeFile(path.join(output,'results.json'),JSON.stringify({origin:'original_synthetic',resumed_sources:resume,resumed_slow_mapping:resumeSlow,checks,scans,records,fixture:folder,jobs:finalSnapshot.jobs.map(j=>({id:j.id,operation:j.operation,status:j.status})),report_integrity:finalSnapshot.report_integrity},null,2));
  console.log(JSON.stringify({checks:checks.length,scans:scans.length,output}));
}catch(error){await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,scans,errors,log,text:await page.locator('body').innerText().catch(()=>'(closed)')},null,2));throw error;
}finally{
  await browser.close();if(app.exitCode===null){await fs.writeFile(path.join(folder,'stop.request'),'Stop the owned peripheral QA runtime after this browser journey.');await expect.poll(()=>app.exitCode!==null,{timeout:30000,intervals:[100,500]}).toBe(true);}
  await fs.writeFile(path.join(output,'researcher.log'),log);
}
