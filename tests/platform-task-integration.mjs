// Real Chrome input -> frozen task renderer -> real R receiver -> SQLite.
// Original synthetic procedure tests; no mocked clocks, routes or score reports.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import {spawn,spawnSync} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
import {chromium} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const root=path.resolve(import.meta.dirname,'..'),work=path.resolve(root,'../../work');
const rscript=process.env.BROHN_RSCRIPT||path.join(work,'native-r/bin/Rscript.exe');
const env={...process.env,R_LIBS_USER:process.env.R_LIBS_USER||path.join(work,'r-library-brohn-restore'),R_USER:work,LC_ALL:'C',LANG:'C'};
const temporary=await fs.mkdtemp(path.join(os.tmpdir(),'brohn-task-integration-')),workspace=path.join(temporary,'workspace');
const output=path.join(root,'test-results/platform-task-integration');await fs.mkdir(output,{recursive:true});
const checks=[],errors=[],failures=[];let server,browser,logs='';
const check=(condition,message)=>{assert.ok(condition,message);checks.push(message);console.log(`PASS ${message}`);};
function runR(action){const file=path.join(temporary,`${action}.json`);const r=spawnSync(rscript,['--vanilla','tests/fixtures/platform-task-integration.R',action,workspace,file],{cwd:root,env,windowsHide:true,encoding:'utf8',timeout:30000});assert.equal(r.status,0,r.stderr||r.stdout);return fs.readFile(file,'utf8').then(JSON.parse);}
async function poll(fn,description,timeout=20000){const end=Date.now()+timeout;while(Date.now()<end){if(await fn())return;await delay(40);}throw Error(`Timed out: ${description}`);}
async function journal(p){return p.evaluate(()=>new Promise(resolve=>{const request=indexedDB.open('brohn-participant',1);request.onsuccess=()=>{const db=request.result,get=db.transaction('sessions').objectStore('sessions').getAll();get.onsuccess=()=>{resolve(get.result);db.close();};};}));}
async function onset(p,id){await poll(async()=>{const records=await journal(p);return records.some(r=>r.events?.some(e=>e.type==='task_event'&&e.payload.kind==='task_trial_started'&&e.payload.data.trial_id===id));},`retained trial onset ${id}`,7000);}
try{
  const fixture=await runR('prepare');let port;
  for(let candidate=3870;candidate<3880;candidate++){const free=await new Promise(resolve=>{const s=net.createServer();s.once('error',()=>resolve(false));s.listen(candidate,'127.0.0.1',()=>s.close(()=>resolve(true)));});if(free){port=candidate;break;}}
  assert.ok(port,'No task QA port available');const base=`http://127.0.0.1:${port}`;
  server=spawn(rscript,['--vanilla','scripts/run-participant.R','--root',workspace,'--port',String(port)],{cwd:root,env,windowsHide:true,stdio:['ignore','pipe','pipe']});
  for(const stream of[server.stdout,server.stderr])stream.on('data',c=>{logs=(logs+c).slice(-16000);});
  await poll(async()=>{try{return(await fetch(`${base}/api/health`)).ok;}catch{return false;}},'real participant service');
  browser=await chromium.launch({channel:'chrome',headless:true});
  async function start(name){
    const c=await browser.newContext({viewport:{width:1280,height:900}}),p=await c.newPage();
    p.on('pageerror',e=>errors.push(e.message));p.on('dialog',d=>d.accept());
    p.on('response',r=>{if(r.url().includes('/api/')&&r.status()>=400)failures.push({url:new URL(r.url()).pathname,status:r.status()});});
    await p.goto(`${base}/participant/?token=${fixture[name].token}`);
    await p.getByLabel('Participant alias (required)').fill(`SYNTHETIC-${name}`);
    await p.getByLabel('I have read the study information and agree to take part.').check();
    const started=p.waitForResponse(r=>r.url().includes('/api/start/')&&r.request().method()==='POST');
    await p.getByRole('button',{name:'Start study',exact:true}).click();const payload=await(await started).json();
    await p.getByRole('button',{name:'Begin this block',exact:true}).waitFor();return{p,c,payload,compiled:payload.protocol.timeline.find(s=>s.type==='task').task};
  }
  for(const name of['simple','iat']){
    const{p,c,payload,compiled}=await start(name);
    const violations=(await new AxeBuilder({page:p}).withTags(['wcag2a','wcag2aa','wcag21aa','wcag22aa']).analyze()).violations;
    check(!violations.length,`${name}: task instruction page automated accessibility`);
    await p.screenshot({path:path.join(output,`${name}-instructions.png`),fullPage:true});
    let instructions=0,trials=0;
    for(const step of compiled.timeline){
      if(step.type==='task_instructions'){await p.getByRole('button',{name:'Begin this block',exact:true}).click();instructions++;console.log(`${name}: block ${instructions}`);}
      else{await onset(p,step.id);if(name==='iat'&&trials===0){const wrong=step.correct_code==='KeyE'?'KeyI':'KeyE';await p.keyboard.press(wrong);await p.getByText('Incorrect. Press the other key to continue.',{exact:true}).waitFor();}
        await p.keyboard.press(step.correct_code);trials++;}
    }
    await p.getByRole('heading',{name:'Thank you. Your responses are saved.',exact:true}).waitFor({timeout:30000});
    const persisted=(await runR('inspect')).find(r=>r.id===payload.run_id),events=persisted.events.filter(e=>e.type==='task_event');
    check(persisted.completion==='completed'&&persisted.transfer==='saved',`${name}: actual entire task completion has durable final receipt`);
    check(events.filter(e=>e.payload.kind==='task_instructions').length===(name==='iat'?7:2),`${name}: every procedure block instruction is retained`);
    check(events.filter(e=>e.payload.kind==='task_trial_finished').length===(name==='iat'?180:28),`${name}: complete frozen trial count is retained`);
    const responses=events.filter(e=>e.payload.kind==='task_trial_finished').map(e=>e.payload.data);
    check(responses.every(r=>r.final_correct_ms>=0&&r.keypresses.some(k=>k.accepted&&k.correct)),`${name}: completion contains accepted observed correct keys`);
    if(name==='iat')check(responses[0].first_correct===false&&responses[0].keypresses.filter(k=>k.accepted).length===2&&responses[0].final_correct_ms>responses[0].first_response_ms,'IAT forced correction retains first error and final-correct times');
    check(persisted.protocol.design_hash===payload.protocol.design_hash,`${name}: transport does not mutate frozen design identity`);
    await fs.writeFile(path.join(output,`${name}-evidence.json`),JSON.stringify({run:persisted,checks:checks.slice()},null,2));await c.close();
  }
  const{p,c,payload}=await start('interruption');await p.reload();
  await p.getByRole('heading',{name:'The study was interrupted.',exact:true}).waitFor({timeout:30000});
  const partial=(await runR('inspect')).find(r=>r.id===payload.run_id);
  check(partial.completion==='interrupted'&&partial.transfer==='saved','Reload during task instructions conservatively retains an interrupted session');
  check(!partial.events.some(e=>e.type==='step_finished'&&e.phase==='implicit_task'),'Reload cannot fabricate a completed implicit task');await c.close();
  const stopped=await start('interruption');await stopped.p.getByRole('button',{name:'Begin this block',exact:true}).click();
  await onset(stopped.p,stopped.compiled.timeline.find(s=>s.type==='task_trial').id);await stopped.p.keyboard.press('Escape');
  await stopped.p.getByRole('heading',{name:'You have stopped the study.',exact:true}).waitFor({timeout:30000});
  const withdrawn=(await runR('inspect')).find(r=>r.id===stopped.payload.run_id);
  check(withdrawn.completion==='withdrawn'&&withdrawn.transfer==='saved','Escape during a live task trial preserves a durable withdrawn outcome');
  check(withdrawn.events.some(e=>e.type==='task_event'&&e.payload.kind==='task_trial_finished'&&e.payload.data.outcome==='interrupted'),'Stopped timed task preserves its partial trial evidence before the ending event');await stopped.c.close();
  const instructionStop=await start('interruption');await instructionStop.p.keyboard.press('Escape');
  await instructionStop.p.getByRole('heading',{name:'You have stopped the study.',exact:true}).waitFor({timeout:30000});
  const instructionPartial=(await runR('inspect')).find(r=>r.id===instructionStop.payload.run_id);
  check(instructionPartial.completion==='withdrawn'&&instructionPartial.transfer==='saved','Escape at block instructions has a durable withdrawn outcome');
  check(instructionPartial.events.some(e=>e.type==='task_event'&&e.payload.kind==='task_interrupted')&&!instructionPartial.events.some(e=>e.type==='task_event'&&e.payload.kind==='task_trial_finished'),'Instruction-only interruption contains no fabricated trial');await instructionStop.c.close();
  check(!errors.length,`No browser exceptions ${errors.join(';')}`);check(!failures.length,`No rejected real task traffic ${JSON.stringify(failures)}`);
  await fs.writeFile(path.join(output,'results.json'),JSON.stringify({origin:'original_synthetic',checks},null,2));console.log(JSON.stringify({checks:checks.length,output}));
}catch(error){await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,errors,failures,logs},null,2));throw error;}
finally{
  if(browser)await browser.close();
  if(server){if(process.platform==='win32')spawnSync('taskkill',['/PID',String(server.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});else server.kill();await delay(250);}
  const resolved=await fs.realpath(temporary);assert.ok(resolved.startsWith(await fs.realpath(os.tmpdir()))&&path.basename(resolved).startsWith('brohn-task-integration-'));
  await fs.rm(resolved,{recursive:true,force:true,maxRetries:6,retryDelay:250});
}
