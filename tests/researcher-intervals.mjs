// Actual researcher UI + supervised worker; six independently known numbers.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const folder=path.resolve(process.argv[2]);assert.ok(path.basename(folder).startsWith('brohn-intervals-'));
await fs.mkdir(folder,{recursive:true});const output=path.join(folder,`browser-${Date.now()}`);await fs.mkdir(output);
const r=path.resolve('../../work/native-r/bin/Rscript.exe');
const env={...process.env,R_LIBS_USER:path.resolve('../../work/r-library-brohn-restore'),LC_ALL:'C',
 BROHN_PUBLICATION_PYTHON:path.resolve('../../work/tooling/methods-venv/Scripts/python.exe'),BROHN_PUBLICATION_MANIFEST:path.resolve('../../work/tooling/brohn-native/publication-guard.json')};
function helper(mode){const result=spawnSync(r,['--vanilla','tests/fixtures/researcher-intervals.R',mode,folder],{env,windowsHide:true,encoding:'utf8',maxBuffer:16*1024**2});assert.equal(result.status,0,result.stderr);}
helper('setup');const config=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
const children=[],checks=[],scans=[],errors=[];let log='';
for(const mode of ['serve','worker']){const child=spawn(r,['--vanilla','tests/fixtures/researcher-intervals.R',mode,folder],{env,windowsHide:true});children.push(child);child.stdout.on('data',x=>log+=`${mode}: ${x}`);child.stderr.on('data',x=>log+=`${mode}: ${x}`);}
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage();
page.on('pageerror',e=>errors.push(e.message));const button=name=>page.getByRole('button',{name,exact:true});
function check(ok,label){assert.ok(ok,label);checks.push(label);console.log('PASS',label);}
async function idle(){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&![...document.querySelectorAll('.recalculating')].some(e=>e.getClientRects().length));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);}
async function scan(label,narrow=false){await page.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});await idle();
 const failures=(await new AxeBuilder({page}).analyze()).violations,overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);
 const small=await page.locator('#signal_annotation_editor button:visible,#signal_annotation_editor input:not([hidden]):visible,#signal_annotation_editor select:visible,#signal_annotation_editor summary:visible,#signal_annotation_summary a:visible').evaluateAll(es=>es.filter(e=>e.getBoundingClientRect().height<44).map(e=>({id:e.id,h:e.getBoundingClientRect().height})));
 scans.push({label,violations:failures.length,overflow,small});await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(failures,null,2));
 await page.locator('#signal_annotation_editor').scrollIntoViewIfNeeded();await page.screenshot({path:path.join(output,`${label}.png`),fullPage:true});
 if(await page.locator('#signal_annotation_chart svg').count())await page.locator('#signal_annotation_chart [role="region"]').screenshot({path:path.join(output,`${label}-chart.png`)});
 check(!failures.length&&!overflow&&!small.length,`${label}: accessibility, page reflow and 44px controls`);await page.setViewportSize({width:1440,height:1080});}
async function file(label,name){const link=page.getByRole('link',{name:label,exact:true});await expect(link).toHaveAttribute('href',/session\/.*download\//);const wait=page.waitForEvent('download');await link.click();const d=await wait;assert.equal(await d.failure(),null);const target=path.join(output,name);await d.saveAs(target);return target;}
async function json(label,name){return JSON.parse(await fs.readFile(await file(label,name),'utf8'));}
async function editorVersion(version){await expect(page.locator('#signal_annotation_editor')).toContainText(`Saved version ${version} with`);await page.waitForFunction(()=>{const f=document.getElementById('interval_form_identity');return f&&Shiny.shinyapp.$inputValues.interval_form_identity===f.value;});await idle();}
async function add(label,start,end){await page.getByLabel('Interval label',{exact:true}).fill(label);await page.getByLabel('Start in seconds (included)',{exact:true}).fill(String(start));await page.getByLabel('End in seconds (excluded)',{exact:true}).fill(String(end));await button('Add interval').click();}
async function open(){await button('Studies').click();await page.locator(`[data-brohn-event="brohn_open_study"][data-brohn-value='"${config.study_id}"']`).click();await button('Results').click();await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${config.report_id}"']`).click();await button('Explore signal traces and spectra').click();await button('Create interval set').waitFor({timeout:90000});await idle();}
try{
 await expect.poll(async()=>{if(children.some(c=>c.exitCode!==null))throw Error(log);try{return(await fetch(`http://127.0.0.1:${config.port}/`)).status===200;}catch{return false;}},{timeout:60000}).toBe(true);
 await page.goto(`http://127.0.0.1:${config.port}/`);await open();await page.getByLabel('New interval set name',{exact:true}).fill('Before and during');await button('Create interval set').focus();await page.keyboard.press('Enter');await editorVersion(1);
 await add('Invalid',5,2);await expect(page.locator('#platform_error')).toContainText('start must precede');await expect(page.getByLabel('Interval label',{exact:true})).toHaveValue('Invalid');check(true,'Invalid interval is recoverable without clearing typed fields');
 await add('Before',0,3);await editorVersion(2);await add('During',3,6);await editorVersion(3);
 const intervals=await json('Download saved intervals','intervals-v3.json');check(intervals.intervals.length===2&&intervals.intervals[0].end_s===3&&intervals.intervals[1].start_s===3,'Saved adjacent intervals preserve independently chosen half-open boundaries');
 await button('Calculate interval summaries').click();await page.getByRole('heading',{name:'Saved interval comparison',exact:true}).waitFor({timeout:90000});await idle();
 const summary=await json('Download results + provenance','comparison-v3.json');check(summary.annotation_source.revision===3&&summary.summary.summaries.map(r=>r.mean).join(',')==='4,10'&&summary.summary.summaries.every(r=>r.standard_deviation_sample===2&&r.eligible_rows===3),'Actual queued worker calculates known means4/10, sample SD2, counts3/3 from complete data');
 const csv=await fs.readFile(await file('Download comparison table','comparison-v3.csv'),'utf8'),svg=await fs.readFile(await file('Download comparison chart','comparison-v3.svg'),'utf8');
 check(csv.includes('annotation_hash')&&csv.includes('source_artifact_hash')&&csv.includes('standard_deviation_sample')&&svg.includes('not confidence intervals')&&svg.includes('n = 3'),'Real CSV and standalone SVG exports retain values, source binding, denominator and SD meaning');
 await scan('comparison-desktop');await scan('comparison-390',true);
 const staleCommand=await page.locator('[data-brohn-event="signal_interval_command"]').first().getAttribute('data-brohn-value');
 await button('Edit interval').first().click();await expect(page.getByLabel('Interval label',{exact:true})).toHaveValue('Before');await page.getByLabel('End in seconds (excluded)',{exact:true}).fill('2');await button('Save interval changes').click();await editorVersion(4);
 await expect(page.locator('#signal_annotation_summary')).toContainText('interval version 3');check((await json('Download results + provenance','comparison-after-edit.json')).id===summary.id,'Editing intervals retains and labels the earlier immutable calculated result');
 await page.evaluate(cmd=>Shiny.setInputValue('signal_interval_command',{...JSON.parse(cmd),action:'remove'},{priority:'event'}),staleCommand);await expect(page.locator('#platform_error')).toContainText('earlier interval version');check(true,'Delayed commands cannot remove from a later interval version');
 await button('Remove interval').first().click();await editorVersion(5);await page.getByText('Recover an earlier interval version',{exact:true}).click();await page.getByLabel('Earlier version to review',{exact:true}).fill('3');await button('Review earlier intervals').click();await button('Restore version 3').click();await editorVersion(6);
 check((await json('Download saved intervals','intervals-v6.json')).intervals[0].end_s===3,'Researcher reviews and restores deleted intervals as a new preserved version');
 await fs.writeFile(path.join(folder,'worker.pause'),'pause');await button('Calculate interval summaries').click();await button('Cancel interval calculation').waitFor();await button('Cancel interval calculation').click();await expect(page.locator('#signal_annotation_progress')).toContainText('Calculation cancelled');await fs.unlink(path.join(folder,'worker.pause'));
 await button('Calculate interval summaries').click();await expect(page.locator('#signal_annotation_summary')).toContainText('interval version 6',{timeout:90000});const retried=await json('Download results + provenance','comparison-retried.json');
 check(retried.annotation_source.revision===6&&retried.summary.summaries[1].mean===10,'Cancelled calculation recovers through a new exact-source worker attempt');
 await page.reload();await open();await page.getByLabel('Saved interval sets (up to 100 most recent)',{exact:true}).selectOption(intervals.id);await button('Open interval set').click();await editorVersion(6);await expect(page.locator('#signal_annotation_summary')).toContainText('interval version 6');
 check((await json('Download results + provenance','comparison-reopened.json')).id===retried.id,'Fresh browser session reopens source-bound intervals and the newest completed comparison');
 await scan('reopened-390',true);helper('inspect');const snapshot=JSON.parse(await fs.readFile(path.join(folder,'snapshot.json'),'utf8'));check(snapshot.report.body.id===config.report_id&&snapshot.summaries.length===2&&errors.length===0,'Original report remains available with two immutable results and no browser exceptions');
 await fs.writeFile(path.join(output,'results.json'),JSON.stringify({passed:true,origin:'original-synthetic',checks,scans,errors,config},null,2));console.log(JSON.stringify({checks:checks.length,scans:scans.length,output}));
}catch(error){await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,scans,errors,log,text:await page.locator('body').innerText()},null,2));throw error;}
finally{await browser.close();await fs.writeFile(path.join(folder,'stop.request'),'stop owned fixture');await Promise.all(children.map(c=>new Promise(resolve=>{if(c.exitCode!==null)return resolve();c.once('exit',resolve);setTimeout(()=>{if(c.exitCode===null)c.kill();resolve();},5000).unref();})));await fs.writeFile(path.join(output,'server.log'),log);}
