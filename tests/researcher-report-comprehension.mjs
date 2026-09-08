// Re-render an existing saved report; no new sources, sessions, jobs or analyses.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const folder=path.resolve('../../work/test-runs/brohn-peripheral-ui-leyspE'),output=path.join(folder,'presentation-retake');
await fs.mkdir(output,{recursive:true});await fs.rm(path.join(output,'stop.request'),{force:true});
const r=path.resolve('../../work/native-r/bin/x64/Rscript.exe'),env={...process.env,R_LIBS_USER:path.resolve('../../work/r-library-brohn'),R_USER:path.resolve('../../work'),LC_ALL:'C'};
function helper(mode){const p=spawnSync(r,['--vanilla','tests/fixtures/researcher-report-comprehension.R',mode,folder],{env,encoding:'utf8',windowsHide:true});assert.equal(p.status,0,p.stderr);}
helper(await fs.stat(path.join(output,'config.json')).then(()=>false).catch(()=>true)?'prepare':'inspect');
const config=JSON.parse(await fs.readFile(path.join(output,'config.json'),'utf8'));
const before=JSON.parse(await fs.readFile(path.join(output,'snapshot.json'),'utf8'));
assert.equal(before.reports.length,5);assert.ok(before.reports.every(report=>report.envelope_matches&&report.object_hash===report.body.result_object.hash));
const original=JSON.parse(await fs.readFile(path.join(folder,'evidence','results.json'),'utf8'));
const combined=before.reports.find(report=>report.id===original.records.combined_report);assert.ok(combined);
assert.deepEqual(combined.body,JSON.parse(await fs.readFile(path.join(folder,'evidence','combined-peripheral-liking-report.json'),'utf8')));
const app=spawn(r,['--vanilla','tests/fixtures/researcher-report-comprehension.R','serve',folder],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});let log='';for(const stream of[app.stdout,app.stderr])stream.on('data',bytes=>log+=bytes);
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage();
const checks=[],scans=[],errors=[];let activePage=page;const watch=p=>p.on('pageerror',e=>errors.push(e.message));watch(page);
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log(`PASS ${label}`);};
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
async function stage(name){await page.getByRole('button',{name,exact:true}).click();if(['Plan','Results'].includes(name))await page.waitForFunction(stage=>{const field=document.getElementById('study_form_identity');return field?.value.endsWith(`:${stage}`)&&field.value===Shiny.shinyapp.$inputValues.study_form_identity;},name);}
async function openReport(id){await stage('Studies');await page.getByLabel('Search studies',{exact:true}).fill(config.title);await page.locator(`[data-brohn-event="brohn_open_study"][data-brohn-value='"${config.study_id}"']`).click();await expect(page.getByLabel('Study name',{exact:true})).toHaveValue(config.title);await stage('Results');await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${id}"']`).click();await page.getByRole('heading',{name:before.reports.find(report=>report.id===id).body.title,exact:true}).waitFor();}
async function download(label,name){const link=page.getByRole('link',{name:label,exact:true});await expect(link).toHaveAttribute('href',/session\/.*download\//);const pending=page.waitForEvent('download');await link.click();const item=await pending;assert.equal(await item.failure(),null);const file=path.join(output,name);await item.saveAs(file);return file;}
async function axe(p,label,narrow=false){await p.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});if(p===page){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&![...document.querySelectorAll('.recalculating')].some(e=>e.getClientRects().length));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);}const violations=(await new AxeBuilder({page:p}).analyze()).violations;scans.push({label,count:violations.length});await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(violations,null,2));await p.screenshot({path:path.join(output,`${label}.png`),fullPage:true});check(!violations.length,`${label}: no automated accessibility violations`);check(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`${label}: no page overflow`);}
async function content(p){
  const cards=p.locator('.brohn-grid > .brohn-card');await expect(cards).toHaveCount(3);
  await expect(cards.nth(0)).toContainText('Mean temperature');await expect(cards.nth(0)).toContainText('+8 °C');await expect(cards.nth(0)).toContainText('3 eligible people');await expect(cards.nth(0)).toContainText('4 paired sessions');
  await expect(cards.nth(0)).toContainText('95% interval: -1.937 to 17.94 °C');await expect(cards.nth(0)).toContainText('0.1484 across 3 declared comparisons');
  await expect(cards.nth(1)).toContainText('Mean acceleration magnitude');await expect(cards.nth(1)).toContainText('Comparison unavailable');await expect(cards.nth(1)).toContainText('Measure unit: m/s²');
  await expect(cards.nth(1)).toContainText('Multiple records share the same participant, session, condition and exposure identity.');await expect(cards.nth(1)).toContainText('Review the source intervals');
  await expect(cards.nth(2)).toContainText('How much do you like this refill package?');await expect(cards.nth(2)).toContainText('+2.25 rating points');await expect(cards.nth(2)).toContainText('4 eligible people');await expect(cards.nth(2)).toContainText('5 paired sessions');
  const visible=await p.locator('main').innerText();assert.ok(!visible.includes('degrees_f')&&!visible.includes('q-liking')&&!visible.includes('scientifically qualified')&&!visible.includes('No eligible paired observations'));
  await expect(p.locator('main')).toContainText('3 of 3 selected source reports are available.');await expect(p.locator('main')).toContainText('2 of 3 declared comparisons have an uncertainty interval and p-value.');
  await expect(p.getByRole('region',{name:/Complete combined-report coverage and eligibility/})).toBeHidden();
}
try{
  await expect.poll(async()=>{if(app.exitCode!==null)throw new Error(log);try{return(await fetch(`http://127.0.0.1:${config.port}/`)).status===200;}catch{return false;}},{timeout:60000,intervals:[250,500,1000]}).toBe(true);
  await page.goto(`http://127.0.0.1:${config.port}/`);await openReport(combined.id);await content(page);
  check(true,'Saved report displays frozen question wording, named physical measures and canonical units without changing effects, intervals or separate denominators');
  await axe(page,'combined-comprehension-desktop');await axe(page,'combined-comprehension-narrow',true);
  await page.getByText('Inspect complete coverage counts',{exact:true}).click();const coverage=page.getByRole('region',{name:/Complete combined-report coverage and eligibility/});await expect(coverage).toBeVisible();
  await expect(coverage).toContainText('296');await expect(coverage).toContainText('scientifically qualified');await expect(coverage).toContainText('false');
  check(true,'All original coverage counts and booleans remain available in explicitly opened technical details');
  await axe(page,'combined-technical-details-narrow',true);await page.getByText('Inspect complete coverage counts',{exact:true}).click();
  const json=await fs.readFile(await download('JSON + provenance','combined-original-data.json'));assert.deepEqual(JSON.parse(json),combined.body);
  const csv=await fs.readFile(await download('Download observations','combined-original-observations.csv'));assert.equal(digest(csv),digest(await fs.readFile(path.join(folder,'evidence','combined-peripheral-observations.csv'))));
  check(true,'Actual JSON keeps the exact saved report and CSV download bytes match the prior researcher export');
  const html=await download('Download report','combined-readable-report.html');const offline=await context.newPage();activePage=offline;watch(offline);await offline.goto(`file:///${html.replaceAll('\\','/')}`);await content(offline);await axe(offline,'combined-offline-desktop');await axe(offline,'combined-offline-narrow',true);await offline.close();activePage=page;
  check(true,'Standalone HTML uses the same readable cards and coverage while retaining the complete provenance');
  await page.setViewportSize({width:1440,height:1080});
  for(const id of[original.records.temperature_report,original.records.movement_report]){await openReport(id);const bytes=await fs.readFile(await download('JSON + provenance',`${id}-unchanged.json`));assert.deepEqual(JSON.parse(bytes),before.reports.find(report=>report.id===id).body);}
  check(true,'Original individual temperature and acceleration reports remain reopenable with exact saved data');
  helper('inspect');const after=JSON.parse(await fs.readFile(path.join(output,'snapshot.json'),'utf8'));assert.deepEqual(after,before);
  check(true,'All five report envelopes, source hashes, revisions and job histories remain unchanged; no analysis was regenerated');
  check(errors.length===0&&scans.every(scan=>scan.count===0),'No browser exceptions or visible Shiny errors');
  await fs.writeFile(path.join(output,'results.json'),JSON.stringify({scope:'read_only_saved_report_presentation_no_scientific_workers',origin:'original_synthetic',checks,scans,report_id:combined.id,report_hash:combined.hash,retained_report_ids:before.reports.map(report=>report.id),source_dataset_ids:before.sources.map(source=>source.id)},null,2));console.log(JSON.stringify({checks:checks.length,scans:scans.length,output}));
}catch(error){await activePage.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,scans,errors,text:await activePage.locator('body').innerText().catch(()=>'(closed)'),log},null,2));throw error;
}finally{await browser.close();if(app.exitCode===null){await fs.writeFile(path.join(output,'stop.request'),'Stop only this read-only report presentation fixture.');await expect.poll(()=>app.exitCode!==null,{timeout:15000,intervals:[100,250]}).toBe(true);}await fs.writeFile(path.join(output,'researcher.log'),log);}
