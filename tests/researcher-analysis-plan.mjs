// UI-declared comparison family -> design reuse -> actual repeated visits ->
// planned cohort report. Original synthetic values, not human timing evidence.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const output=path.resolve('../../work/test-runs/brohn-analysis-plan-ui-evidence');await fs.mkdir(output,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage();
const checks=[],errors=[],violations=[],runs=[];page.on('pageerror',e=>errors.push(e.message));
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log(`PASS ${label}`);};
const stage=name=>page.getByRole('button',{name,exact:true}).click();
async function select(id,label){const input=page.locator(`#${id}-selectized`);await input.click();await input.fill(label);await input.press('Enter');}
async function download(label,name){const link=page.getByRole('link',{name:label,exact:true});await expect(link).toHaveAttribute('href',/session\/.*download\//);const pending=page.waitForEvent('download');await link.click();const d=await pending;assert.equal(await d.failure(),null);const file=path.join(output,name);await d.saveAs(file);return file;}
function design(file){const p=spawnSync(path.resolve('../../work/tooling/methods-venv/Scripts/python.exe'),['-c',"import sys,zipfile; print(zipfile.ZipFile(sys.argv[1]).read('design.json').decode('utf-8'))",file],{encoding:'utf8',windowsHide:true});assert.equal(p.status,0,p.stderr);return JSON.parse(p.stdout);}
async function axe(label,narrow=false){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&!document.querySelector('.recalculating'));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);await page.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});const a=(await new AxeBuilder({page}).analyze()).violations;await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(a,null,2));await page.screenshot({path:path.join(output,`${label}.png`),fullPage:true});if(a.length)violations.push({label,rules:a.map(v=>v.id)});else check(true,`${label}: no automated accessibility violations`);check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`${label}: no page overflow`);await page.setViewportSize({width:1440,height:1080});}
function checkPlanReuse(source,copy,label){check(copy.id!==source.id&&copy.analysis_plan.comparisons.every((c,i)=>c.id!==source.analysis_plan.comparisons[i].id&&copy.conditions.some(k=>k.id===c.control_id&&k.role==='control')&&copy.conditions.some(k=>k.id===c.test_id&&k.role==='test'))&&copy.analysis_plan.comparisons.find(c=>c.measure==='questionnaire_numeric').outcome_id===copy.questions[0].id,`${label}: comparison, condition and numeric-question identities remap together`);check(copy.analysis_plan.rationale===source.analysis_plan.rationale&&copy.analysis_plan.multiplicity.alpha===.05&&copy.analysis_plan.comparisons.length===2,`${label}: rationale and complete two-hypothesis family are retained`);}
try{
 await page.goto('http://127.0.0.1:3851/');await stage('Explore a practice design');await page.getByLabel('Study name',{exact:true}).waitFor();const title=`Original planned comparison UI ${Date.now()}`;
 await page.getByLabel('Study name',{exact:true}).fill(title);for(const id of ['stimulus_duration_1','stimulus_duration_2','baseline_ms','fixation_ms'])await page.locator(`#${id}`).fill('100');await stage('Questions');
 await page.getByLabel('Require an answer to question 1',{exact:true}).uncheck();const prompt=await page.locator('#q_prompt_1').inputValue();await stage('Plan');await stage('Set analysis plan');
 await stage('Save analysis plan');await expect(page.locator('#platform_error')).toContainText('Explain the research question');check(true,'A saved plan requires a stated research question and rationale');
 const rationale='Original synthetic packaging QA: compare test versus control on liking and Product label valid gaze share. Define the two-outcome family before these synthetic participant visits; missing gaze must not shrink it.';
 await page.getByLabel('Research question and comparison rationale',{exact:true}).fill(rationale);await select('plan_outcome_id','Product label');await stage('Add planned comparison');
 await select('plan_measure','Numeric questionnaire response');await page.getByText('Numeric question',{exact:true}).waitFor();await select('plan_outcome_id',prompt);await stage('Add planned comparison');await expect(page.getByRole('button',{name:'Remove planned comparison',exact:true})).toHaveCount(2);
 await stage('Add planned comparison');await expect(page.locator('#platform_error')).toContainText('hypotheses must be distinct');check(await page.getByRole('button',{name:'Remove planned comparison',exact:true}).count()===2,'The plan refuses a duplicate hypothesis without changing the saved family');
 await axe('plan-editor');await axe('plan-editor-narrow',true);await stage('Save analysis plan');await page.getByRole('button',{name:'Edit analysis plan',exact:true}).waitFor();
 const original=design(await download('Export design','original-plan.brohn-study.zip'));check(original.analysis_plan.comparisons.length===2&&original.questions[0].required===false,'Actual portable study contains both declared outcomes and the optional scoped rating');
 await stage('Clone design');await page.getByLabel('Name for the new study',{exact:true}).fill(`${title} clone`);await stage('Create clone');await expect(page.getByLabel('Study name',{exact:true})).toHaveValue(`${title} clone`);
 const cloned=design(await download('Export design','cloned-plan.brohn-study.zip'));checkPlanReuse(original,cloned,'Clone');
 await stage('Design library');await page.locator('#import_design_file').setInputFiles(path.join(output,'cloned-plan.brohn-study.zip'));await page.getByLabel('Study name',{exact:true}).waitFor();
 const imported=design(await download('Export design','imported-plan.brohn-study.zip'));checkPlanReuse(cloned,imported,'Portable import');
 await stage('Collect');await expect(page.locator('#brohn-main')).toContainText('Sessions will appear');check(true,'Reused planned study begins without original participant observations');
 await page.getByLabel('Require a researcher-issued participant code to link repeat sessions',{exact:true}).check();await stage('Release participant study');const link=page.getByRole('link',{name:'Open participant study',exact:true}).first();await link.waitFor();const url=await link.getAttribute('href');
 const control=imported.conditions.find(c=>c.role==='control').id;
 const visits=[{alias:'QA-PLANNED-P1',test:4},{alias:'QA-PLANNED-P1',test:6},{alias:'QA-PLANNED-P2',test:3},{alias:'QA-PLANNED-P3',test:null}];
 for(const [index,visit]of visits.entries()){
   const pc=await browser.newContext({viewport:{width:1280,height:900}}),p=await pc.newPage();p.on('pageerror',e=>errors.push(e.message));await p.goto(url);await p.getByLabel('Participant alias (required)',{exact:true}).fill(visit.alias);await p.getByLabel('I have read the study information and agree to take part.',{exact:true}).check();
   const request=p.waitForResponse(r=>r.url().includes('/api/start/')&&r.request().method()==='POST');await p.getByRole('button',{name:'Start study',exact:true}).click();const session=await(await request).json();assert.deepEqual(session.protocol.design.analysis_plan,imported.analysis_plan);await p.getByRole('button',{name:'Begin',exact:true}).click();
   for(const step of session.protocol.timeline.filter(s=>s.type==='question')){
     await p.getByRole('heading',{name:step.question.prompt,exact:true}).waitFor();const value=step.condition_id===control?2:visit.test;
     if(value!==null){const option=step.question.options.find(o=>o.value===value);assert.ok(option);await p.getByRole('radio',{name:option.label,exact:true}).check();}
     await p.getByRole('button',{name:'Continue',exact:true}).click();
   }
   await p.getByRole('heading',{name:'Thank you. Your responses are saved.',exact:true}).waitFor({timeout:30000});runs.push(session.run_id);await pc.close();check(true,`Original synthetic visit${index+1} completes with its frozen plan and scoped responses`);
 }
 await page.bringToFront();await stage('Results');await page.locator('[data-brohn-event="analyse_cohort"]').click();const cohort=page.locator('.brohn-card').filter({has:page.getByRole('heading',{name:'Release cohort responses',exact:true})});await cohort.getByRole('button',{name:'Open report',exact:true}).waitFor({timeout:90000});await cohort.getByRole('button',{name:'Open report',exact:true}).click();
 const report=JSON.parse(await fs.readFile(await download('JSON + provenance','planned-cohort.json'),'utf8')),comparison=report.analysis.contrasts[0],plan=report.analysis.parameters.analysis_plan;
 check(report.provenance.runs.length===4&&report.analysis.observations.length===8&&report.analysis.observations.filter(r=>r.missing_reason==='optional_omission').length===1,'Actual cohort retains four visits/eight responses and the explicit omitted test rating');
 check(comparison.estimate===2&&comparison.participant_count===2&&comparison.paired_session_count===3&&comparison.excluded_session_count===1,'Planned effect equals2 from person means3 and1; repeat visits are not independent people');
 const p=1-2*Math.atan(2)/Math.PI;check(Math.abs(comparison.p_value-p)<1e-12&&Math.abs(comparison.p_adjusted-2*p)<1e-12,'Planned inference matches the independent df1 Cauchy-tail oracle and full-family conservative bound');
 check(comparison.multiplicity.family_size===2&&comparison.multiplicity.method==='bonferroni_incomplete_family'&&report.analysis.contrasts.length===1,'Unavailable gaze remains in the declared family without fabricating a gaze comparison');
 assert.deepEqual(plan.plan,imported.analysis_plan);check(plan.timing_evidence==='plan_frozen_before_these_participant_sessions'&&plan.hash.length===64,'Report pins the reused analysis plan and its actual pre-session timing evidence');
 const html=await fs.readFile(await download('Download report','planned-cohort.html'),'utf8'),csv=await fs.readFile(await download('Download observations','planned-cohort.csv'),'utf8');
 check(/Bonferroni/i.test(html)&&!/Holm-adjusted p-value/.test(html)&&csv.includes('optional_omission'),'Standalone planned report names its actual adjustment and keeps omitted responses in CSV');
 await expect(page.locator('#brohn-main')).toContainText(/Bonferroni/i);check(!(await page.locator('#brohn-main').innerText()).includes('Holm-adjusted p-value'),'Visible planned report labels the applied bound accurately');
 await axe('planned-cohort');await axe('planned-cohort-narrow',true);check(errors.length===0,`No browser exceptions: ${errors.join(';')}`);check(violations.length===0,`All planned-analysis accessibility scans clear: ${JSON.stringify(violations)}`);
 await fs.writeFile(path.join(output,'results.json'),JSON.stringify({origin:'original_synthetic',checks,source_study_id:original.id,collected_study_id:imported.id,run_ids:runs,report_id:report.id},null,2));console.log(JSON.stringify({checks:checks.length,output}));
}catch(error){await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,errors,violations,text:await page.locator('body').innerText()},null,2));throw error;}finally{await browser.close();}
