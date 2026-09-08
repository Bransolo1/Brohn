// Automated synthetic researcher -> actual Shiny -> participant service -> child
// analysis worker. No mocked API, injected study, or human-study qualification.
import {importTransferredSource} from './helpers/source-import.mjs';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {chromium, expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const base=process.env.BROHN_TEST_URL||'http://127.0.0.1:3851/';
const output=path.resolve('../../work/test-runs/brohn-ui-evidence');
const python=process.env.BROHN_PYTHON||path.resolve('../../work/tooling/methods-venv/Scripts/python.exe');
await fs.mkdir(output,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true});
const context=await browser.newContext({viewport:{width:1440,height:1080}});
let page=await context.newPage();
const errors=[],checks=[],accessibilityFailures=[],evidence={origin:'original_synthetic',url:base};
const watch=p=>p.on('pageerror',e=>errors.push(String(e)));watch(page);
const check=(condition,message)=>{assert.ok(condition,message);checks.push(message);console.log(`PASS ${message}`);};
const stage=async name=>{await page.getByRole('button',{name,exact:true}).click();};
const card=title=>page.locator('.brohn-card').filter({has:page.getByRole('heading',{name:title,exact:true})});
async function axe(label,narrow=false){
  await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&!document.querySelector('.recalculating'));
  await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);await page.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});
  const result=await new AxeBuilder({page}).analyze();
  await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(result.violations,null,2));
  await page.screenshot({path:path.join(output,`${label}.png`),fullPage:true});
  if(result.violations.length){accessibilityFailures.push({label,violations:result.violations.map(v=>v.id)});console.log(`FINDING ${label}: ${result.violations.map(v=>v.id)}`);}
  else check(true,`${label}: no automated accessibility violations`);
  if(narrow){
    const overflow=await page.evaluate(()=>({width:document.documentElement.scrollWidth,viewport:innerWidth}));
    if(overflow.width>overflow.viewport+1){accessibilityFailures.push({label,violations:['page-overflow'],...overflow});console.log(`FINDING ${label}: page overflow ${overflow.width}`);}
    else check(true,`${label}: no page overflow`);
  }
  await page.setViewportSize({width:1440,height:1080});
}
async function download(label,filename){
  const link=page.getByRole('link',{name:label,exact:true});
  await expect(link).toHaveAttribute('href',/session\/.*download\//);
  const pending=page.waitForEvent('download');await link.click();
  const item=await pending,failure=await item.failure();check(failure===null,`${filename}: actual download succeeded (${failure||'ok'})`);
  const target=path.join(output,filename);await item.saveAs(target);return target;
}
function readDesign(zip){
  const result=spawnSync(python,['-c',"import sys,zipfile; print(zipfile.ZipFile(sys.argv[1]).read('design.json').decode('utf-8'))",zip],{encoding:'utf8',windowsHide:true});
  assert.equal(result.status,0,result.stderr);return JSON.parse(result.stdout);
}
async function openStudy(title,id=null){
  await stage('Studies');const selected=id?page.locator('.brohn-card').filter({has:page.locator(`[data-brohn-value='"${id}"']`)}):card(title);await selected.getByRole('button',{name:'Open study',exact:true}).click();
  await page.getByLabel('Study name',{exact:true}).waitFor();
}
async function selectChoice(id,label){
  const input=page.locator(`#${id}-selectized`);await input.click();await input.fill(label);await input.press('Enter');
}
async function exportReport(prefix){
  const json=await download('JSON + provenance',`${prefix}.json`);const report=JSON.parse(await fs.readFile(json,'utf8'));
  const html=await download('Download report',`${prefix}.html`);const csv=await download('Download observations',`${prefix}.csv`);
  const markup=await fs.readFile(html,'utf8'),table=await fs.readFile(csv,'utf8');
  check(markup.includes(report.id)&&markup.includes('Interpretation and limitations'),`${prefix}: standalone HTML retains identity and interpretation`);
  check(table.includes('participant_id')&&table.split('\n').length>=3,`${prefix}: observations CSV contains retained records`);return report;
}
try{
  await page.goto(base);await page.getByRole('heading',{name:'Your next discovery starts here.'}).waitFor();await axe('home');
  await page.getByRole('button',{name:'Explore a practice design'}).click();await page.getByLabel('Study name',{exact:true}).waitFor();
  const title=`Researcher lifecycle ${Date.now()}`;evidence.title=title;
  await page.getByLabel('Study name',{exact:true}).fill(title);
  // Shortened transport fixture; these settings are not a physiology protocol.
  for(const id of ['stimulus_duration_1','stimulus_duration_2','baseline_ms','fixation_ms'])await page.locator(`#${id}`).fill('100');
  await stage('Save');await axe('study-plan');await axe('study-plan-narrow',true);
  await page.getByRole('button',{name:'Edit Product label',exact:true}).first().click();
  await page.locator('#brohn-aoi-canvas').waitFor();await page.locator('#brohn-aoi-canvas').focus();
  await page.locator('#brohn-aoi-canvas').press('ArrowRight');await expect(page.locator('#aoi_x')).toHaveValue('0.21');
  check(await page.locator('#aoi_x').inputValue()==='0.21','AOI keyboard movement updates normalized numeric position');
  await stage('Undo region change');await expect(page.locator('#aoi_x')).toHaveValue('0.2');
  check(await page.locator('#aoi_x').inputValue()==='0.2','AOI undo restores original normalized position');
  await axe('aoi-editor');await axe('aoi-editor-narrow',true);await stage('Cancel');
  await stage('Questions');await page.locator('#q_prompt_1').waitFor();
  check((await page.locator('#q_prompt_1').inputValue()).includes('like'),'Scoped liking question is present');
  await axe('questions');await axe('questions-narrow',true);
  await stage('Plan');await expect(page.getByLabel('Study name',{exact:true})).toHaveValue(title);
  check(await page.locator('#stimulus_duration_1').inputValue()==='100','Saved duration survives navigation');
  await stage('Save as template');await expect(page.locator('#platform_status')).toContainText('Design saved');
  const packagePath=await download('Export design','original.brohn-study.zip'),design=readDesign(packagePath);evidence.study_id=design.id;
  check(design.stimuli.length===2&&design.stimuli.every(s=>s.asset.hash&&s.aois.length===1),'Portable design contains both immutable images and defined AOIs');
  check(design.conditions.map(c=>c.role).join(',')==='control,test','Experimental control is retained separately from baseline duration');
  await stage('Collect');await page.getByLabel('Require a researcher-issued participant code to link repeat sessions').check();
  await stage('Release participant study');await page.getByRole('link',{name:'Open participant study'}).first().waitFor();
  const participantUrl=await page.getByRole('link',{name:'Open participant study'}).first().getAttribute('href');
  check(participantUrl.startsWith('http://127.0.0.1:3852/participant/?token='),'Release uses actual separate participant service');await axe('collect');
  const pc=await browser.newContext({viewport:{width:1280,height:900}}),participant=await pc.newPage();watch(participant);
  await participant.goto(participantUrl);
  await participant.getByLabel('Participant alias (required)',{exact:true}).fill('SYNTHETIC-RESEARCHER-01');
  await participant.getByLabel('I have read the study information and agree to take part.').check();
  await participant.getByRole('button',{name:'Start study',exact:true}).click();await participant.getByRole('button',{name:'Begin',exact:true}).click();
  for(const value of ['Not at all','Very much']){
    await participant.getByRole('heading',{name:design.questions[0].prompt,exact:true}).waitFor();
    await participant.getByRole('radio',{name:value,exact:true}).check();await participant.getByRole('button',{name:'Continue',exact:true}).click();
  }
  await participant.getByRole('heading',{name:'Thank you. Your responses are saved.',exact:true}).waitFor();
  check((await participant.locator('#save-status').innerText()).includes('Final receipt confirmed'),'Actual participant completed with durable final receipt');
  await pc.close();await page.bringToFront();await stage('Results');
  await page.getByRole('button',{name:'Open report',exact:true}).first().waitFor({timeout:60000});
  await page.getByRole('button',{name:'Open report',exact:true}).first().click();
  await page.getByRole('link',{name:'JSON + provenance',exact:true}).waitFor();
  const participantReport=await exportReport('participant-report');evidence.participant_report_id=participantReport.id;
  check(participantReport.analysis.observations.map(r=>r.value).sort((a,b)=>a-b).join(',')==='1,7','Automatic report retains exact scoped liking answers 1 and 7');
  check(participantReport.analysis.quality.participant_count===1,'Explicit participant identity is retained in automatic report');
  await axe('report');await axe('report-narrow',true);

  // Original independent oracle, scaled to the 100 ms software fixture. Label
  // AOIs contain (.5,.5), exclude (.95,.5). Active-response gaze must be excluded.
  const oracle=JSON.parse(await fs.readFile('tests/fixtures/researcher-scenarios.json','utf8'));
  const rows=['participant,session,condition,stimulus,exposure,start,end,x,y,valid,phase'];
  for(const session of oracle.sessions)for(const[index,key]of['A','B'].entries()){
    const s=design.stimuli[index],data=session[key],valid=data.valid_gaze_ms/50,inside=data.logo_gaze_ms/50;
    const add=(start,end,x,valid=true,phase='passive_viewing')=>rows.push([session.participant_id,session.session_id,s.condition_id,s.id,`${session.session_id}-${key}`,start,end,x,valid?.5:'',valid,phase].join(','));
    if(inside>0)add(0,inside,.5);if(valid>inside)add(inside,valid,.95);if(valid<100)add(valid,100,'',false);add(100,140,.5,true,'active_response');
  }
  const csvPath=path.join(output,'original-gaze-intervals.csv');await fs.writeFile(csvPath,rows.join('\n'));
  await openStudy(title);await stage('Collect');await page.getByLabel('Dataset name',{exact:true}).fill(`${title} gaze`);
  await page.getByLabel('Dataset name',{exact:true}).press('Tab');
  await importTransferredSource(page,csvPath,{destination:new RegExp(`^Destination: ${title.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')} · saved revision [1-9][0-9]*$`)});await page.getByRole('heading',{name:'Confirm what the columns mean',exact:true}).waitFor();
  await axe('mapping');await axe('mapping-narrow',true);
  await stage('Confirm mapping and analyse');await expect(page.locator('#platform_error')).toContainText('Describe where this recording came from');
  check(await page.getByRole('heading',{name:'Confirm what the columns mean',exact:true}).isVisible(),'Incomplete mapping is explained while the source and form remain available');
  await selectChoice('map_exposure','exposure');await selectChoice('map_time_unit','Milliseconds');
  await selectChoice('map_unit','Stimulus-normalized coordinates (0 to 1)');
  await page.getByLabel('Recording provenance and collection notes').fill('Original synthetic QA intervals; four fictional identities and five sessions; no device or human data. Durations scaled by 1/50 for transport only. Explicit passive phases; active responses must be excluded.');
  await stage('Confirm mapping and analyse');await expect(page.locator('#platform_status')).toContainText('Analysis queued');
  await page.getByRole('button',{name:'Open report',exact:true}).first().waitFor({timeout:60000});
  check(await page.getByRole('heading',{name:'Confirm what the columns mean',exact:true}).isVisible(),'Completed report appears without leaving or losing the mapping form');
  await page.getByRole('button',{name:'Open report',exact:true}).first().click();
  const gazeReport=await exportReport('gaze-report');evidence.gaze_report_id=gazeReport.id;
  check(Math.abs(gazeReport.analysis.contrasts[0].estimate-10.833333333333334)<1e-9,'UI-imported gaze equals independent 10.833333 percentage-point oracle');
  check(gazeReport.analysis.contrasts[0].participant_count===3&&gazeReport.analysis.contrasts[0].paired_session_count===4,'Repeated sessions use equal-person comparison; one missing gaze pair excluded');
  check(gazeReport.analysis.quality.excluded_other_phase_rows===10,'All ten active-response intervals are excluded');
  check(gazeReport.analysis.parameters.input==='prepared_gaze_intervals','Report identifies prepared intervals rather than claiming raw fixation detection');await axe('gaze-report-narrow',true);

  await openStudy(title);await stage('Clone design');await page.getByLabel('Name for the new study').fill(`${title} clone`);await stage('Create clone');
  await expect(page.getByLabel('Study name',{exact:true})).toHaveValue(`${title} clone`);
  const cloned=readDesign(await download('Export design','clone.brohn-study.zip'));
  check(cloned.id!==design.id&&cloned.stimuli.every((s,i)=>s.id!==design.stimuli[i].id&&s.asset.hash===design.stimuli[i].asset.hash),'Clone has new design/stimulus identities and unchanged immutable source images');
  await stage('Collect');await expect(page.locator('#brohn-main')).toContainText('Sessions will appear');check(true,'Clone contains no source participant sessions');
  await stage('Results');await page.getByRole('heading',{name:'Results follow the evidence'}).waitFor();check(true,'Clone contains no source results');
  await stage('Design library');await card(title).getByRole('button',{name:'Use this design',exact:true}).click();
  const reused=readDesign(await download('Export design','template-reuse.brohn-study.zip'));
  check(reused.id!==design.id&&reused.id!==cloned.id&&reused.lineage.operation==='use_template','Saved design is reusable as a distinct study');
  await stage('Collect');await expect(page.locator('#brohn-main')).toContainText('Sessions will appear');check(true,'Template reuse contains no source participant sessions');
  await stage('Design library');await page.locator('#import_design_file').setInputFiles(packagePath);await page.getByLabel('Study name',{exact:true}).waitFor();
  const imported=readDesign(await download('Export design','imported.brohn-study.zip'));
  check(![design.id,cloned.id,reused.id].includes(imported.id)&&imported.lineage.operation==='import_design','Actual downloaded ZIP reimports as a new study');
  check(imported.stimuli.every((s,i)=>s.asset.hash===design.stimuli[i].asset.hash),'Reimport preserves exact immutable stimulus bytes');
  await page.getByLabel('Study name',{exact:true}).fill(`${title} imported`);await stage('Save');
  await stage('Collect');await expect(page.locator('#brohn-main')).toContainText('Sessions will appear');check(true,'Portable import contains no source participant sessions');
  await stage('Design library');await page.getByRole('heading',{name:'Design library',exact:true}).waitFor();await axe('library-narrow',true);

  // New Shiny session reopens durable workspace independently of renderer memory.
  const fresh=await browser.newContext({viewport:{width:1440,height:1080}});page=await fresh.newPage();watch(page);
  await page.goto(base);await page.getByRole('heading',{name:'Your next discovery starts here.'}).waitFor();await stage('Studies');
  const sourceCard=page.locator('.brohn-card').filter({has:page.locator(`[data-brohn-value='"${design.id}"']`)});
  await sourceCard.getByRole('button',{name:'Open study',exact:true}).click();await stage('History');
  await page.getByRole('heading',{name:'A study with a memory'}).waitFor();
  check((await page.locator('#brohn-main').innerText()).includes('Revision 2'),'Saved history survives a new researcher browser session');
  check(await page.getByRole('button',{name:'Open report',exact:true}).count()===2,'Historical study links both automatic and imported-data reports');await axe('history-narrow',true);

  await stage('Inspect revision 2');await page.getByRole('heading',{name:'Design revision 2',exact:true}).waitFor();
  const historical=readDesign(await download('Export this revision','historical-revision-2.brohn-study.zip'));
  check(historical.id===design.id&&historical.title==='Packaging comparison - practice'&&historical.stimuli.every(s=>s.asset?.hash),'Historical export uses the original saved revision, including its earlier title and image assets');
  await stage('Clone this revision');await page.getByLabel('Study name',{exact:true}).waitFor();
  const historicalClone=readDesign(await download('Export design','historical-clone.brohn-study.zip'));
  check(historicalClone.id!==design.id&&historicalClone.lineage.source_revision===2&&historicalClone.stimuli.every((s,i)=>s.asset.hash===historical.stimuli[i].asset.hash),'Clone this revision preserves the selected historical source instead of silently cloning current state');
  await stage('Collect');await expect(page.locator('#brohn-main')).toContainText('Sessions will appear');check(true,'Historical clone contains no source participant sessions');
  await openStudy(title,design.id);await stage('History');await stage('Archive study');
  await expect(page.locator('#platform_error')).toContainText('Close recruitment before archiving');check(true,'Open recruitment blocks archive with an actionable explanation');
  await stage('Collect');await stage('Close recruitment');await expect(page.locator('#brohn-main .brohn-badge').filter({hasText:/^closed$/})).toBeVisible();
  check(await page.getByRole('button',{name:'Close recruitment',exact:true}).count()===0,'Closed recruitment remains closed in the researcher interface');
  const closedContext=await browser.newContext(),closedPage=await closedContext.newPage();watch(closedPage);await closedPage.goto(participantUrl);
  await expect(closedPage.locator('#content')).toContainText(/closed/i);
  check(await closedPage.getByRole('button',{name:'Start study',exact:true}).count()===0,'A new visitor to a closed link sees its status before providing consent or an alias');await closedContext.close();
  await stage('History');await stage('Archive study');await page.getByRole('button',{name:'Restore to active studies',exact:true}).waitFor();
  check(await page.getByRole('button',{name:'Plan',exact:true}).count()===0&&await page.getByRole('button',{name:'Open report',exact:true}).count()===2,'Archived study is read-only and retains both original reports');
  await axe('archived-history-narrow',true);await stage('Restore to active studies');await page.getByRole('button',{name:'Archive study',exact:true}).waitFor();
  await stage('Plan');await expect(page.getByLabel('Study name',{exact:true})).toHaveValue(title);check(true,'Restore returns the original study design to the active workspace');
  await stage('Collect');await expect(page.locator('#brohn-main .brohn-badge').filter({hasText:/^closed$/})).toBeVisible();check(true,'Restoring the study does not reopen its closed recruitment link');

  // Navigate immediately after real input changes; no debounce sleeps. Source IDs
  // disambiguate legitimate same-title designs and isolate their form state.
  const revisedTitle=`${title} revised`,revisedPrompt='Original synthetic revision: how much do you like this package?';
  await stage('Plan');await page.getByLabel('Study name',{exact:true}).fill(revisedTitle);await stage('Questions');
  await page.locator('#q_prompt_1').fill(revisedPrompt);await stage('Tasks');await page.getByRole('heading',{name:'Implicit and reaction-time tasks',exact:true}).waitFor();
  await stage('Plan');await expect(page.getByLabel('Study name',{exact:true})).toHaveValue(revisedTitle);check(true,'Immediate stage navigation preserves title edits before the autosave debounce');
  await stage('Questions');await expect(page.locator('#q_prompt_1')).toHaveValue(revisedPrompt);check(true,'Immediate questionnaire navigation preserves the edited scoped prompt');
  await openStudy(title,cloned.id);await expect(page.getByLabel('Study name',{exact:true})).toHaveValue(`${title} clone`);
  await stage('Questions');await expect(page.locator('#q_prompt_1')).toHaveValue(design.questions[0].prompt);check(true,'Opening another study by ID does not copy the first study title or question edits');
  await stage('Plan');await page.getByLabel('Study name',{exact:true}).fill(`${title} clone revised`);await page.locator('#condition_label_1').fill('Clone-only control');
  await openStudy(title,design.id);await expect(page.getByLabel('Study name',{exact:true})).toHaveValue(revisedTitle);await expect(page.locator('#condition_label_1')).toHaveValue(design.conditions[0].label);
  check(true,'Rapid study switching keeps clone-only title and condition edits out of the source');
  await openStudy(title,cloned.id);await expect(page.getByLabel('Study name',{exact:true})).toHaveValue(`${title} clone revised`);await expect(page.locator('#condition_label_1')).toHaveValue('Clone-only control');
  check(true,'Edits before study navigation are durably saved on the intended clone');
  await openStudy(title,design.id);await stage('History');await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${evidence.gaze_report_id}"']`).click();
  const reopened=JSON.parse(await fs.readFile(await download('JSON + provenance','gaze-report-after-design-edits.json'),'utf8'));
  check(JSON.stringify(reopened)===JSON.stringify(gazeReport),'Earlier gaze report remains exactly unchanged after later title, question and library edits');
  check(errors.length===0,`No browser exceptions: ${errors.join('\n')}`);
  check(accessibilityFailures.length===0,`All page accessibility scans passed: ${JSON.stringify(accessibilityFailures)}`);evidence.checks=checks;
  await fs.writeFile(path.join(output,'results.json'),JSON.stringify(evidence,null,2));console.log(JSON.stringify({checks:checks.length,output,...evidence}));
}catch(error){
  await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});
  await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,errors,accessibilityFailures,evidence,url:page.url(),text:await page.locator('body').innerText().catch(()=> '')},null,2));throw error;
}finally{await browser.close();}
