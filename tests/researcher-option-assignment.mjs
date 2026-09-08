// Real researcher + participant route; original typed codes and preserved old release.
// No scientific worker is launched; queued analysis is explicitly cancelled at cleanup.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const r=path.resolve('../../work/native-r/bin/x64/Rscript.exe');
const python=path.resolve('../../work/tooling/methods-venv/Scripts/python.exe');
const env={...process.env,R_LIBS_USER:path.resolve('../../work/r-library-brohn'),R_USER:path.resolve('../../work'),LC_ALL:'C'};
const resumeIndex=process.argv.indexOf('--resume-review'),resume=resumeIndex>=0;
const folder=resume?path.resolve(process.argv[resumeIndex+1]):await fs.mkdtemp(path.resolve('../../work/test-runs/brohn-option-assignment-ui-'));
assert.equal(path.dirname(folder),path.resolve('../../work/test-runs'));assert.match(path.basename(folder),/^brohn-option-assignment-ui-/);
const output=path.join(folder,'evidence');await fs.mkdir(output,{recursive:true});
const checkpoint=resume?JSON.parse(await fs.readFile(path.join(output,'review-checkpoint.json'),'utf8')):null;
if(resume)await fs.rm(path.join(folder,'stop.request'),{force:true});
function helper(mode){const child=spawnSync(r,['--vanilla','tests/fixtures/researcher-option-assignment.R',mode,folder],{env,windowsHide:true,encoding:'utf8'});assert.equal(child.status,0,child.stderr);}
if(!resume)helper('create');const fixture=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
const logs={},children=[];
function service(name,args){const child=spawn(r,['--vanilla',...args],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});logs[name]='';for(const stream of[child.stdout,child.stderr])stream.on('data',bytes=>logs[name]+=bytes);children.push(child);return child;}
const app=service('researcher',['tests/fixtures/researcher-option-assignment.R','serve',folder]);
const receiver=service('participant',['scripts/run-participant.R','--root',fixture.workspace,'--port',String(fixture.participant_port)]);
const browser=await chromium.launch({channel:'chrome',headless:true});
let context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage(),activePage=page;
const checks=checkpoint?.checks||[],scans=checkpoint?.scans||[],errors=[],sessions=checkpoint?.sessions||[];let design=checkpoint?.design,originalFile=checkpoint?.originalFile;
const watch=p=>p.on('pageerror',e=>errors.push(e.message));watch(page);
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log(`PASS ${label}`);};
async function stage(name){await page.getByRole('button',{name,exact:true}).click();if(['Plan','Questions','Tasks','Collect','Review','Results','History'].includes(name))await page.waitForFunction(stage=>{const field=document.getElementById('study_form_identity');return field?.value.endsWith(`:${stage}`)&&field.value===Shiny.shinyapp.$inputValues.study_form_identity;},name);}
async function snapshot(){helper('inspect');return JSON.parse(await fs.readFile(path.join(folder,'snapshot.json'),'utf8'));}
async function idle(){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&![...document.querySelectorAll('.recalculating')].some(e=>e.getClientRects().length));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);}
async function select(id,label){const field=page.locator(`#${id}-selectized`);await field.click();await field.fill(label);await page.locator('.selectize-dropdown:visible').getByRole('option',{name:label,exact:true}).click();}
async function openStudy(){await stage('Studies');await page.getByLabel('Search studies',{exact:true}).fill(fixture.title);await page.locator(`[data-brohn-event="brohn_open_study"][data-brohn-value='"${fixture.study_id}"']`).click();await expect(page.getByLabel('Study name',{exact:true})).toHaveValue(fixture.title);}
async function download(label,name){const target=page.getByRole('link',{name:label,exact:true});await expect(target).toHaveAttribute('href',/session\/.*download\//);const pending=page.waitForEvent('download');await target.click();const item=await pending;assert.equal(await item.failure(),null);const file=path.join(output,name);await item.saveAs(file);return file;}
function portable(file){const child=spawnSync(python,['-c',"import sys,zipfile;print(zipfile.ZipFile(sys.argv[1]).read('design.json').decode('utf-8'))",file],{windowsHide:true,encoding:'utf8'});assert.equal(child.status,0,child.stderr);return JSON.parse(child.stdout);}
async function axe(label,narrow=false,p=page){await p.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});if(p===page)await idle();const violations=(await new AxeBuilder({page:p}).analyze()).violations;scans.push({label,count:violations.length});await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(violations,null,2));await p.screenshot({path:path.join(output,`${label}.png`),fullPage:true});check(!violations.length,`${label}: no automated accessibility violations`);check(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`${label}: no page overflow`);await p.setViewportSize({width:1440,height:1080});}
const questions=p=>p.timeline.filter(step=>step.type==='question');
const choiceOrder=p=>questions(p).map(step=>({id:step.question.id,stimulus:step.stimulus_id,options:step.question.options}));
function typedGraph(d){return d.questions.map(q=>({prompt:q.prompt,type:q.type,scope:q.scope,randomize_options:q.randomize_options,option_assignment:q.option_assignment,options:q.options.map(o=>({label:o.label,value:o.value}))}));}
async function participant(url,number,{legacy=false,resume=false}={}){
  const pc=await browser.newContext({viewport:{width:1440,height:1080}}),p=await pc.newPage();activePage=p;watch(p);
  await p.goto(url);await p.getByLabel('Participant alias (required)',{exact:true}).fill(`${legacy?'OLD':'NEW'}-ORIGINAL-${number}`);
  await p.getByLabel('I have read the study information and agree to take part.',{exact:true}).check();
  const starting=p.waitForResponse(res=>res.url().includes('/api/start/')&&res.request().method()==='POST');await p.getByRole('button',{name:'Start study',exact:true}).click();
  const start=await(await starting).json();assert.ok(start.run_id,JSON.stringify(start));sessions.push({run_id:start.run_id,protocol:start.protocol,legacy,number});
  await fs.writeFile(path.join(output,`${legacy?'old':'new'}-${number}-start-protocol.json`),JSON.stringify(start.protocol,null,2));
  if(legacy)assert.deepEqual(start.protocol,fixture.legacy_protocols[number-1]);else assert.deepEqual(start.protocol.design,design);
  await p.getByRole('button',{name:'Begin',exact:true}).click();
  for(const [index,step]of questions(start.protocol).entries()){
    await p.getByRole('heading',{name:step.question.prompt,exact:true}).waitFor();
    await expect(p.locator('#study-progress')).toHaveText(`Part ${start.protocol.timeline.indexOf(step)+1} of ${start.protocol.timeline.length}`);
    const ids=await p.getByRole('radio').evaluateAll(radios=>radios.map(r=>r.value));assert.deepEqual(ids,step.question.options.map(o=>o.id));
    for(const option of step.question.options)await expect(p.getByRole('radio',{name:option.label,exact:true})).toHaveValue(option.id);
    const selected=step.question.options.find(o=>Object.is(o.value,fixture.values[(number-1)%6]));assert.ok(selected);
    if(resume&&index===0){
      await axe('assigned-options-participant-narrow',true,p);await p.getByRole('radio',{name:selected.label,exact:true}).check();
      await p.reload();await p.getByRole('button',{name:'Resume this participant session',exact:true}).click();await p.getByRole('heading',{name:step.question.prompt,exact:true}).waitFor();
      assert.deepEqual(await p.getByRole('radio').evaluateAll(radios=>radios.map(r=>r.value)),ids);await expect(p.getByRole('radio',{name:selected.label,exact:true})).toBeChecked();
      check(true,'Untimed reload preserves this participant’s exact offered order and typed draft answer');
    }
    await p.getByRole('radio',{name:selected.label,exact:true}).check();await p.getByRole('button',{name:'Continue',exact:true}).click();
  }
  await p.getByRole('heading',{name:'Thank you. Your responses are saved.',exact:true}).waitFor({timeout:45000});
  await pc.close();activePage=page;
  const saved=(await snapshot()).runs.find(run=>run.id===start.run_id);assert.equal(saved.completion_status,'completed');assert.equal(saved.transfer_status,'saved');assert.deepEqual(saved.protocol,start.protocol);
  const answers=saved.events.filter(event=>event.type==='response');assert.equal(answers.length,4);assert.ok(answers.every(event=>Object.is(event.payload.value,fixture.values[(number-1)%6])));
  check(true,`${legacy?'Historical':'Upgraded'} allocation ${number}: actual ordered controls and four saved typed responses match the frozen protocol`);
  return start;
}
try{
  for(const[child,url]of[[app,`http://127.0.0.1:${fixture.port}/`],[receiver,`http://127.0.0.1:${fixture.participant_port}/api/health`]])await expect.poll(async()=>{if(child.exitCode!==null)throw new Error(JSON.stringify(logs));try{return(await fetch(url)).status===200;}catch{return false;}},{timeout:60000,intervals:[250,500,1000]}).toBe(true);
  await page.goto(`http://127.0.0.1:${fixture.port}/`);
  let state,release;
  if(resume){state=await snapshot();assert.equal(state.runs.length,8);assert.deepEqual(state.study.body,design);assert.deepEqual(state.legacy_release_design,fixture.legacy_design);for(const session of sessions)assert.deepEqual(state.runs.find(r=>r.id===session.run_id).protocol,session.protocol);release=checkpoint.release;check(true,'Review continuation rechecks all eight saved protocols, upgraded design and old release before using retained evidence');}
  else{
  await openStudy();await stage('Questions');
  await expect(page.getByText('This older draft uses the same shuffled option order for every participant.',{exact:true})).toHaveCount(2);await stage('Save');
  assert.deepEqual((await snapshot()).study.body,fixture.legacy_design);check(true,'Opening and ordinarily saving a legacy randomized draft does not silently change assignment or mixed option types');
  await axe('legacy-assignment-authoring');await axe('legacy-assignment-authoring-narrow',true);
  const oldUrl=`http://127.0.0.1:${fixture.participant_port}/participant/?token=${fixture.legacy_release.token}`;
  await participant(oldUrl,1,{legacy:true});
  const upgrade=page.locator('[data-brohn-event="question_assignment_upgrade"]').first(),stale=JSON.parse(await upgrade.getAttribute('data-brohn-value'));
  await upgrade.click();await expect(page.locator('#platform_status')).toContainText('Participant-specific option order saved');
  state=await snapshot();assert.equal(state.study.body.questions[0].option_assignment,'participant-sha256/1.0');assert.ok(!Object.hasOwn(state.study.body.questions[1],'option_assignment'));assert.deepEqual(state.legacy_release_design,fixture.legacy_design);
  check(true,'Explicit per-question upgrade changes only the selected draft question and preserves the old release');
  await page.evaluate(value=>Shiny.setInputValue('question_assignment_upgrade',value,{priority:'event'}),stale);await expect(page.locator('#platform_error')).toContainText('The question changed');
  assert.deepEqual((await snapshot()).study.body,state.study.body);check(true,'Stale upgrade controls cannot revise an already changed question');
  await page.locator('[data-brohn-event="question_assignment_upgrade"]').click();await expect(page.getByRole('button',{name:'Use participant-specific order',exact:true})).toHaveCount(0);
  await page.locator('#q_random_3').check();await stage('Save');state=await snapshot();design=state.study.body;
  assert.ok(design.questions.every(q=>q.randomize_options&&q.option_assignment==='participant-sha256/1.0'));
  for(const [index,q]of design.questions.entries())assert.deepEqual(q.options,fixture.legacy_design.questions[index].options);
  check(true,'Explicit FALSE→TRUE randomization opts the formerly fixed question into the new policy without coercing its codes');
  originalFile=await download('Export design','upgraded-original.brohn-study.zip');assert.deepEqual(portable(originalFile),design);await axe('participant-assignment-authoring-narrow',true);
  await stage('Collect');await select('release_origin','Example walkthrough (sample)');await page.getByLabel('Require a researcher-issued participant code to link repeat sessions',{exact:true}).check();await stage('Release participant study');
  state=await snapshot();release=state.deployments.find(d=>d.id!==fixture.legacy_release.id);assert.ok(release);assert.equal(release.design_hash,state.study_hash);
  const newUrl=`http://127.0.0.1:${fixture.participant_port}/participant/?token=${release.token}`;
  await expect(page.getByRole('link',{name:'Open participant study',exact:true})).toHaveCount(2);
  for(let i=1;i<=6;i++)await participant(newUrl,i,{resume:i===1});
  const newRuns=sessions.filter(s=>!s.legacy);assert.ok(new Set(newRuns.map(s=>JSON.stringify(choiceOrder(s.protocol)[0].options.map(o=>o.id)))).size>1);
  check(true,'Six prespecified new allocations receive varied before-question orders while every context keeps exact offered option identities');
  await participant(oldUrl,2,{legacy:true});assert.deepEqual(choiceOrder(sessions.find(s=>s.legacy&&s.number===1).protocol),choiceOrder(sessions.find(s=>s.legacy&&s.number===2).protocol));
  check(true,'The pre-upgrade release still enrolls a later participant under its original assignment contract');
  await fs.writeFile(path.join(output,'review-checkpoint.json'),JSON.stringify({checks,scans,sessions,design,originalFile,release},null,2));
  }
  const newRuns=sessions.filter(s=>!s.legacy);
  await openStudy();await stage('Collect');await axe('assigned-session-review-narrow',true);
  for(const [i,session]of[sessions.find(s=>s.legacy),newRuns[0]].entries()){
    const button=page.locator('[data-brohn-event="view_run_protocol"]').filter({hasText:'View assigned protocol'});
    const all=await button.count();let target;
    for(let j=0;j<all;j++)if(JSON.parse(await button.nth(j).getAttribute('data-brohn-value')).run_id===session.run_id)target=button.nth(j);
    assert.ok(target);await target.click();const modal=page.getByRole('dialog',{name:'Assigned participant protocol',exact:true});await modal.waitFor();
    await expect(modal).toContainText('assignment alone does not establish what was viewed or completed');
    const saved=(await snapshot()).runs.find(run=>run.id===session.run_id);await expect(page.locator('#run_protocol_identity')).toHaveValue(`${session.run_id}:${saved.protocol_hash}`);
    const rows=modal.getByRole('region',{name:'Assigned participant steps',exact:true}).locator('tbody tr');await expect(rows).toHaveCount(session.protocol.timeline.length);
    for(const step of questions(session.protocol)){
      const row=rows.nth(session.protocol.timeline.indexOf(step));const offered=await row.locator('ol li').evaluateAll(items=>items.map(item=>({label:item.textContent.split('(code:')[0].trim(),code:item.querySelector('code').textContent.trim()})));
      assert.deepEqual(offered,step.question.options.map(option=>({label:option.label,code:JSON.stringify(option.value)})));
    }
    const bytes=await fs.readFile(await download('Download assigned protocol JSON',`${i?'new':'old'}-assigned-protocol-download.json`));
    assert.equal(createHash('sha256').update(bytes).digest('hex'),saved.protocol_hash);assert.deepEqual(JSON.parse(bytes),session.protocol);
    assert.ok(!/"(?:access_token|resume_token|client_id)"\s*:/.test(bytes.toString('utf8')));
    if(i===1)await axe('assigned-protocol-modal-narrow',true);
    await stage('Close protocol');await expect(modal).toHaveCount(0);
  }
  check(true,'Researcher review preserves old/new displayed typed option orders and downloads both original assigned protocols byte-exactly without credentials');
  await stage('Save as template');await expect(page.locator('#platform_status')).toContainText('Design saved');state=await snapshot();const template=state.templates.find(t=>t.body.source_study_id===design.id||t.body.design?.id===design.id);assert.ok(template);
  await stage('Design library');await page.locator(`[data-brohn-event="brohn_use_template"][data-brohn-value='"${template.id}"']`).click();await page.getByLabel('Study name',{exact:true}).waitFor();
  const fromTemplate=portable(await download('Export design','template-assignment.zip'));assert.notEqual(fromTemplate.id,design.id);assert.deepEqual(typedGraph(fromTemplate),typedGraph(design));
  await openStudy();await stage('Clone design');await page.getByLabel('Name for the new study',{exact:true}).fill(`${fixture.title} clone`);await stage('Create clone');await expect(page.getByLabel('Study name',{exact:true})).toHaveValue(`${fixture.title} clone`);
  const clone=portable(await download('Export design','cloned-assignment.zip'));assert.notEqual(clone.id,design.id);assert.deepEqual(typedGraph(clone),typedGraph(design));
  await stage('Design library');await page.locator('#import_design_file').setInputFiles(originalFile);await page.getByLabel('Study name',{exact:true}).waitFor();const imported=portable(await download('Export design','reimported-assignment.zip'));assert.notEqual(imported.id,design.id);assert.deepEqual(typedGraph(imported),typedGraph(design));
  for(const copy of[fromTemplate,clone,imported])assert.ok(copy.questions.every(q=>!design.questions.some(original=>original.id===q.id)));
  check(true,'Template, clone and portable reimport retain the explicit policy and exact typed options under fresh design/question identities');
  await context.close();context=await browser.newContext({viewport:{width:1440,height:1080}});page=await context.newPage();activePage=page;watch(page);await page.goto(`http://127.0.0.1:${fixture.port}/`);await openStudy();await stage('Questions');
  await expect(page.getByRole('button',{name:'Use participant-specific order',exact:true})).toHaveCount(0);assert.deepEqual(portable(await download('Export design','reopened-assignment.zip')),design);
  state=await snapshot();assert.deepEqual(state.legacy_release_design,fixture.legacy_design);assert.equal(state.runs.length,8);assert.equal(state.reports.length,0);for(const session of sessions)assert.deepEqual(state.runs.find(r=>r.id===session.run_id).protocol,session.protocol);
  check(true,'Fresh researcher reopening preserves the upgraded design, old release and all eight complete assigned protocols');
  helper('cancel-queued');state=await snapshot();assert.ok(state.jobs.every(j=>j.status==='cancelled'));assert.ok(state.jobs.every(j=>j.attempts===0||j.attempt===0));
  check(errors.length===0&&scans.every(scan=>scan.count===0),'No browser exceptions, visible Shiny failures or automated accessibility violations');
  await fs.writeFile(path.join(output,'results.json'),JSON.stringify({origin:'original_synthetic',scope:'actual_researcher_and_participant_no_scientific_worker',resumed_review:resume,checks,scans,fixture:folder,study_id:design.id,legacy_release_id:fixture.legacy_release.id,new_release_id:release.id,runs:sessions.map(s=>({run_id:s.run_id,legacy:s.legacy,allocation_index:s.protocol.allocation_index})),reused_studies:[fromTemplate.id,clone.id,imported.id]},null,2));console.log(JSON.stringify({checks:checks.length,scans:scans.length,output}));
}catch(error){await activePage.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,scans,errors,text:await activePage.locator('body').innerText().catch(()=>'(closed)'),logs},null,2));throw error;
}finally{await browser.close();if(app.exitCode===null){await fs.writeFile(path.join(folder,'stop.request'),'Stop this owned original option-assignment QA application.');await expect.poll(()=>app.exitCode!==null,{timeout:15000,intervals:[100,250]}).toBe(true);}if(receiver.exitCode===null&&receiver.signalCode===null){receiver.kill();await expect.poll(()=>receiver.exitCode!==null||receiver.signalCode!==null,{timeout:10000,intervals:[100,250]}).toBe(true);}helper('cancel-queued');for(const[name,log]of Object.entries(logs))await fs.writeFile(path.join(output,`${name}.log`),log);}
