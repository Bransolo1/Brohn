// Real participant service and durable journal; no mocked routes or clocks.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {chromium,expect} from '@playwright/test';
const output=path.resolve(process.env.BROHN_TEST_OUTPUT||'../../work/test-runs/brohn-exact-logic-evidence');await fs.mkdir(output,{recursive:true});
const configFile=path.join(output,'fixture.json'),workspace=path.resolve(process.env.BROHN_TEST_WORKSPACE||'../../work/test-runs/brohn-connected-02');
const participantBase=process.env.BROHN_PARTICIPANT_URL||'http://127.0.0.1:3852',noWorker=process.env.BROHN_TEST_NO_WORKER==='1';
const rscript=path.resolve(process.env.BROHN_RSCRIPT||'../../work/native-r/bin/Rscript.exe'),env={...process.env,R_LIBS_USER:process.env.R_LIBS_USER||path.resolve('../../work/r-library-brohn'),R_USER:path.resolve('../../work'),LC_ALL:'C'};
function r(action){const result=spawnSync(rscript,['--vanilla','tests/fixtures/participant-logic.R',action,workspace,configFile],{encoding:'utf8',env,windowsHide:true});assert.equal(result.status,0,result.stderr||result.stdout);}
r('prepare');const config=JSON.parse(await fs.readFile(configFile,'utf8')),checks=[],errors=[];
const browser=await chromium.launch({channel:'chrome',headless:true});
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log(`PASS ${label}`);};
try{
 const visits=[{number:'Near one',values:['Number one','Boolean false'],expected:['qa-not-one','qa-number','qa-false']},{number:'Exactly one',values:['Text one','Number zero'],expected:['qa-equal-one','qa-text','qa-zero']}];
 for(const[index,visit]of visits.entries()){
   const context=await browser.newContext(),page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));await page.goto(`${participantBase}/participant/?token=${config.deployment.token}`);await page.getByLabel('Participant alias (required)',{exact:true}).fill(`ORIGINAL-TYPED-${index+1}`);
   const pending=page.waitForResponse(r=>r.url().includes('/api/start/')&&r.request().method()==='POST');await page.getByRole('button',{name:'Start study',exact:true}).click();const session=await(await pending).json();await page.getByRole('button',{name:'Begin',exact:true}).click();
   for(const step of session.protocol.timeline.filter(s=>s.type==='question')){
     if(!['qa-exact','qa-mixed',...visit.expected].includes(step.question.id))continue;
     await page.getByRole('heading',{name:step.question.prompt,exact:true}).waitFor();
     if(step.question.id==='qa-exact')await page.getByRole('radio',{name:visit.number,exact:true}).check();
     else if(step.question.id==='qa-mixed')for(const value of visit.values)await page.getByRole('checkbox',{name:value,exact:true}).check();
     await page.getByRole('button',{name:'Continue',exact:true}).click();
   }
   await page.getByRole('heading',{name:'Thank you. Your responses are saved.',exact:true}).waitFor();check(true,`Actual visit${index+1} displays only its expected exact/type-specific branches`);visit.run_id=session.run_id;await context.close();
 }
 r('inspect');const inspected=JSON.parse(await fs.readFile(configFile,'utf8'));
 for(const[index,visit]of visits.entries()){
   const run=inspected.runs.find(r=>r.id===visit.run_id),answers=run.events.filter(e=>e.type==='response'),numeric=answers.find(e=>e.question_id==='qa-exact').payload.value,mixed=answers.find(e=>e.question_id==='qa-mixed').payload.value;
   check(run.status==='completed'&&run.transfer==='saved',`Visit${index+1} has a completed durable receipt`);
   if(noWorker)check(run.jobs.length===1&&run.jobs[0].operation==='analyse_run'&&run.jobs[0].status==='queued',`Visit${index+1} leaves exactly one expected analysis job queued without a worker`);
   check(numeric===(index===0?1+1e-10:1),`Visit${index+1} retains the exact original numeric option code`);
   assert.deepEqual(mixed,index===0?[1,false]:['1',0]);check(true,`Visit${index+1} preserves numeric/text/boolean collection members separately`);
   const branchIds=['qa-equal-one','qa-not-one','qa-number','qa-text','qa-false','qa-zero'];
   for(const id of branchIds){const skipped=run.events.some(e=>e.question_id===id&&e.payload.skipped===true);assert.equal(skipped,!visit.expected.includes(id),`Wrong saved skip for${id}`);}
   check(true,`Visit${index+1} journal confirms all six branch decisions without coercion`);
 }
 check(errors.length===0,`No browser exceptions: ${errors.join(';')}`);await fs.writeFile(path.join(output,'results.json'),JSON.stringify({origin:'original_synthetic',mode:noWorker?'isolated_real_receiver_no_worker':'existing_connected_workspace',participant_base:participantBase,checks,study_id:config.study_id},null,2));console.log(JSON.stringify({checks:checks.length,output}));
}finally{await browser.close();}
