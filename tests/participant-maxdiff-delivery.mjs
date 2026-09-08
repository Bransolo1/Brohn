// Actual Chrome -> real participant launcher -> durable SQLite receipts.
// Only the deliberately lost/held HTTP acknowledgements are intercepted; every
// accepted event is verified by the real receiver. No analysis worker is run.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import {randomUUID} from 'node:crypto';
import {spawn,spawnSync} from 'node:child_process';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const repo=path.resolve(import.meta.dirname,'..'),work=path.resolve(repo,'../../work');
const rscript=process.env.BROHN_RSCRIPT||path.join(work,'native-r/bin/x64/Rscript.exe');
const env={...process.env,R_LIBS_USER:path.join(work,'r-library-brohn-restore'),R_USER:work,LC_ALL:'C',LANG:'C'};
const folder=await fs.mkdtemp(path.join(work,'test-runs/brohn-maxdiff-delivery-')),workspace=path.join(folder,'workspace');
const checks=[],errors=[],traffic=[],scans=[];let child,browser,log='',lastPage;
const check=(value,label)=>{assert.ok(value,label);checks.push(label);console.log(`PASS ${label}`);};
function r(mode){const result=spawnSync(rscript,['--vanilla','tests/fixtures/participant-maxdiff-delivery.R',mode,'--folder',folder,'--root',workspace],{cwd:repo,env,windowsHide:true,encoding:'utf8',timeout:30000});assert.equal(result.status,0,result.stderr||result.stdout);}
async function inspect(){r('inspect');return JSON.parse(await fs.readFile(path.join(folder,'inspection.json'),'utf8'));}
async function journal(page){return page.evaluate(()=>new Promise((resolve,reject)=>{const request=indexedDB.open('brohn-participant',1);request.onerror=()=>reject(request.error);request.onsuccess=()=>{const db=request.result,get=db.transaction('sessions').objectStore('sessions').getAll();get.onerror=()=>{db.close();reject(get.error);};get.onsuccess=()=>{db.close();resolve(get.result);};};}));}
async function record(page,id){return(await journal(page)).find(r=>r.run_id===id);}
async function waitStep(page,run,step){await expect.poll(async()=>{const r=await record(page,run.run_id);return r?.current_step===step.id;},{timeout:20000}).toBe(true);
  if(step.type==='maxdiff'){await expect(page.locator('.brohn-maxdiff')).toHaveCount(1);await expect(page.getByRole('group',{name:step.choice.best_label,exact:true})).toBeVisible();}
  else await page.getByRole('heading',{name:step.question.prompt,exact:true}).waitFor();}
async function scan(page,name){const found=(await new AxeBuilder({page}).analyze()).violations;scans.push({name,violations:found});await fs.writeFile(path.join(folder,`${name}-axe.json`),JSON.stringify(found,null,2));await page.screenshot({path:path.join(folder,`${name}.png`),fullPage:true});check(found.length===0,`${name}: actual participant page has zero axe violations`);check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`${name}: no horizontal page overflow`);}
try{
  r('prepare');const config=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
  const port=await new Promise(resolve=>{const socket=net.createServer();socket.listen(0,'127.0.0.1',()=>{const p=socket.address().port;socket.close(()=>resolve(p));});});const base=`http://127.0.0.1:${port}`;
  child=spawn(rscript,['--vanilla','tests/fixtures/participant-maxdiff-delivery.R','serve','--folder',folder,'--root',workspace,'--port',String(port)],{cwd:repo,env,windowsHide:true,stdio:['ignore','pipe','pipe']});
  child.stdout.on('data',chunk=>log+=chunk);child.stderr.on('data',chunk=>log+=chunk);
  await expect.poll(async()=>{if(child.exitCode!==null)throw new Error(log);try{return(await fetch(`${base}/api/health`)).ok;}catch{return false;}},{timeout:30000,intervals:[100,250,500]}).toBe(true);
  browser=await chromium.launch({channel:'chrome',headless:true});
  async function start(setup){const context=await browser.newContext({viewport:{width:1280,height:900}}),page=await context.newPage();lastPage=page;
    page.on('pageerror',error=>errors.push(error.message));page.on('dialog',dialog=>dialog.accept());
    page.on('response',response=>{if(response.url().includes('/api/')&&response.status()>=400)traffic.push({path:new URL(response.url()).pathname,status:response.status()});});
    if(setup)await setup(page);await page.goto(`${base}/participant/?token=${config.release.token}`);
    await page.getByLabel('I have read the study information and agree to take part.',{exact:true}).check();
    const started=page.waitForResponse(response=>response.url().includes('/api/start/')&&response.request().method()==='POST');await page.getByRole('button',{name:'Start study',exact:true}).click();const run=await(await started).json();
    await page.getByRole('button',{name:'Begin',exact:true}).click();const steps=run.protocol.timeline.filter(step=>step.type==='maxdiff');await waitStep(page,run,steps[0]);return{context,page,run,steps};}

  let lostBody=null,lostCommitted=false,completedRequest=null;const retries=[];
  const main=await start(async page=>{page.on('request',request=>{if(request.url().includes('/api/finish/'))completedRequest=request.postDataJSON();});await page.route('**/api/events/**',async route=>{
    const body=route.request().postDataJSON();if(lostBody&&body.operation_id===lostBody.operation_id)retries.push(body);
    if(!lostBody&&body.events.some(event=>event.type==='response'&&event.phase==='explicit_choice')){
      lostBody=body;retries.push(body);const accepted=await route.fetch();assert.equal(accepted.status(),200);lostCommitted=true;
      await route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({error:{message:'Original fixture: receiver committed, first acknowledgement intentionally lost.'}})});return;
    }await route.continue();
  });});
  const {page,run,steps}=main;
  check(steps.length===3&&new Set(steps.map(step=>step.choice.exercise_id)).size===2&&steps.every(step=>/^[a-f0-9]{64}$/.test(step.choice.design_hash)), 'Real release retains two separate source-hashed exercises as three dedicated choice steps');
  // Exact checks below compare each frozen exercise hash with read-only R
  // verification; source item ordering must be byte-for-byte unchanged here.
  check(steps.length===3&&steps.every(step=>step.phase==='explicit_choice'&&step.choice.item_order.every((id,i)=>step.choice.items[i].id===id)),'Every real offered set has its exact frozen typed item order and explicit-choice phase');
  await scan(page,'initial-choice-desktop');
  const first=steps[0],selected=first.choice.item_order[0];
  await page.getByRole('group',{name:first.choice.best_label,exact:true}).locator(`input[value="${selected}"]`).check();
  await expect.poll(async()=>(await record(page,run.run_id))?.drafts?.[first.id]?.best_id).toBe(selected);
  const oldClock=(await record(page,run.run_id)).events.find(e=>e.type==='step_started'&&e.step_id===first.id).clock.instance_id;
  await page.reload();await page.getByRole('button',{name:'Resume this participant session',exact:true}).click();await waitStep(page,run,first);
  check(await page.getByRole('group',{name:first.choice.best_label,exact:true}).locator(`input[value="${selected}"]`).isChecked(),'Actual reload restores the selected draft within the same frozen choice set');
  check(await page.locator('.brohn-maxdiff input:checked').count()===1,'Recovery preserves the partial pair without inferring a worst item');
  await page.setViewportSize({width:390,height:844});await scan(page,'resumed-choice-narrow');
  for(const [index,step]of steps.entries()){
    await waitStep(page,run,step);const choice=step.choice;
    assert.deepEqual(await page.getByRole('group',{name:choice.best_label,exact:true}).getByRole('radio').evaluateAll(inputs=>inputs.map(input=>input.value)),choice.item_order);
    if(choice.required){if(index!==0)await page.getByRole('group',{name:choice.best_label,exact:true}).locator(`input[value="${choice.item_order[0]}"]`).check();
      await page.getByRole('group',{name:choice.worst_label,exact:true}).locator(`input[value="${choice.item_order[1]}"]`).check();await page.getByRole('button',{name:'Continue',exact:true}).click();
    }else{await page.getByRole('group',{name:choice.best_label,exact:true}).getByRole('radio').first().check();await page.getByRole('button',{name:'Clear choices and skip this set',exact:true}).click();}
  }
  const liking=run.protocol.timeline.find(step=>step.type==='question');await waitStep(page,run,liking);await page.getByLabel('Your answer',{exact:true}).fill('6');await page.getByRole('button',{name:'Continue',exact:true}).click();
  await page.getByRole('heading',{name:'Thank you. Your responses are saved.',exact:true}).waitFor({timeout:30000});
  check(lostCommitted&&retries.length===2,'A genuinely committed but lost first acknowledgement causes exactly one retained batch retry');assert.deepEqual(retries[0],retries[1]);check(true,'Lost-ack retry preserves the exact operation, event IDs, sequences, clocks and payload bytes');
  const completed=(await inspect()).runs.find(r=>r.id===run.run_id),choiceResponses=completed.events.filter(e=>e.type==='response'&&e.phase==='explicit_choice');
  check(completed.completion==='completed'&&completed.transfer==='saved'&&completed.replay.run_finished,'Complete required + optional choices and questionnaire have a durable final receipt');
  check(choiceResponses.length===3&&new Set(completed.events.map(e=>e.id)).size===completed.events.length&&completed.events.every((e,i)=>e.sequence===i+1),'Receiver retains one choice per offered set with a contiguous, duplicate-free event ledger');
  assert.deepEqual(completed.protocol,run.protocol);check(completed.verified_design_hash===config.design_hash,'Read-only reopening preserves the exact released study and protocol');
  check(completed.verified_choice_hashes.length===3&&completed.verified_choice_hashes.every(row=>row.source_hash===row.frozen_hash),'Read-only R verification matches every frozen set to its exact source exercise hash');
  const resumed=choiceResponses.find(e=>e.step_id===first.id),onsets=completed.events.filter(e=>e.type==='step_started'&&e.step_id===first.id);
  check(onsets.length===2&&onsets[0].clock.instance_id===oldClock&&onsets[1].clock.instance_id!==oldClock&&resumed.payload.resumed===true&&resumed.payload.response_time_ms===null,'Resumed choice retains both page onsets and does not claim uninterrupted response time');
  check(resumed.payload.active_segment_response_ms>=0&&Math.abs(resumed.payload.active_segment_response_ms-(Number(resumed.clock.value)-Number(onsets[1].clock.value)))<.01,'Saved active-segment response time agrees with the actual browser clocks');
  check(choiceResponses.find(e=>e.step_id===steps[2].id).payload.value===null,'Explicit optional clear-and-skip is a retained null response, not an inferred preference');
  check(completed.events.some(e=>e.question_id==='original-liking'&&e.type==='response'&&e.payload.value===6),'Explicit numeric liking remains a typed questionnaire answer alongside choices');
  check(completed.alias_supplied===false&&completed.origin==='sample','Anonymous enrollment is kept unlinked and original material remains sample origin');
  check(completed.jobs.length===1&&completed.jobs[0].operation==='analyse_run'&&completed.jobs[0].status==='queued','Exactly one real analysis job is enqueued after closure without running a scientific worker');
  const repeatedReceipt=await fetch(`${base}/api/finish/${run.run_id}`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${run.access_token}`},body:JSON.stringify(completedRequest)});
  assert.equal(repeatedReceipt.status,200);check((await inspect()).runs.find(r=>r.id===run.run_id).jobs.length===1,'Replayed final receipt keeps the same single queued analysis job');
  check((await journal(page)).length===0,'Final receipt removes the prior participant journal from this browser');await main.context.close();

  // Abort a real IndexedDB readwrite transaction after its response put has
  // been issued. The runtime must roll back both disk and its private cursor;
  // replacing only the UI button state would duplicate the later answer.
  const storage=await start(),storageStep=storage.steps[0];
  await storage.page.getByRole('group',{name:storageStep.choice.best_label,exact:true}).getByRole('radio').first().check();
  await storage.page.getByRole('group',{name:storageStep.choice.worst_label,exact:true}).getByRole('radio').nth(1).check();
  await expect.poll(async()=>{const r=await record(storage.page,storage.run.run_id);return r?.drafts?.[storageStep.id]?.worst_id===storageStep.choice.item_order[1]&&r.acked_sequence===r.next_sequence-1;}).toBe(true);
  const beforeFault=await record(storage.page,storage.run.run_id);
  await storage.page.evaluate(({runId,stepId})=>{
    const original=IDBObjectStore.prototype.put;window.maxdiffStorageFault={aborts:0,failedEventIds:[]};
    IDBObjectStore.prototype.put=function(value,...rest){
      const request=original.call(this,value,...rest);
      if(this.name==='sessions'&&value.run_id===runId&&maxdiffStorageFault.aborts===0&&value.events.some(e=>e.type==='response'&&e.step_id===stepId)){
        maxdiffStorageFault.aborts++;maxdiffStorageFault.failedEventIds=value.events.filter(e=>e.step_id===stepId&&['response','step_finished'].includes(e.type)).map(e=>e.id);
        this.transaction.abort();IDBObjectStore.prototype.put=original;
      }
      return request;
    };
  },{runId:storage.run.run_id,stepId:storageStep.id});
  await storage.page.getByRole('button',{name:'Continue',exact:true}).click();await expect(storage.page.locator('#error')).toContainText('could not safely save');
  await expect(storage.page.getByRole('button',{name:'Continue',exact:true})).toBeEnabled();
  const failedJournal=await record(storage.page,storage.run.run_id);
  check(await storage.page.evaluate(()=>maxdiffStorageFault.aborts===1)&&failedJournal.index===beforeFault.index&&failedJournal.current_step===storageStep.id&&failedJournal.next_sequence===beforeFault.next_sequence,
    'A real aborted response transaction keeps the same saved choice cursor and next sequence');
  check(failedJournal.events.every(e=>e.type!=='response'||e.step_id!==storageStep.id)&&await storage.page.locator('.brohn-maxdiff input:checked').count()===2,
    'Failed browser storage retains both explicit picks on the same screen without a committed answer');
  await storage.page.getByRole('button',{name:'Continue',exact:true}).click();
  for(const step of storage.steps.slice(1)){
    await waitStep(storage.page,storage.run,step);
    if(step.choice.required){await storage.page.getByRole('group',{name:step.choice.best_label,exact:true}).getByRole('radio').first().check();await storage.page.getByRole('group',{name:step.choice.worst_label,exact:true}).getByRole('radio').nth(1).check();await storage.page.getByRole('button',{name:'Continue',exact:true}).click();}
    else await storage.page.getByRole('button',{name:'Skip this set',exact:true}).click();
  }
  const storageQuestion=storage.run.protocol.timeline.find(s=>s.type==='question');await waitStep(storage.page,storage.run,storageQuestion);await storage.page.getByLabel('Your answer',{exact:true}).fill('5');await storage.page.getByRole('button',{name:'Continue',exact:true}).click();
  await storage.page.getByRole('heading',{name:'Thank you. Your responses are saved.',exact:true}).waitFor({timeout:30000});
  const recovered=(await inspect()).runs.find(r=>r.id===storage.run.run_id),discardedIds=await storage.page.evaluate(()=>maxdiffStorageFault.failedEventIds);
  check(recovered.completion==='completed'&&recovered.transfer==='saved'&&recovered.events.filter(e=>e.step_id===storageStep.id&&e.type==='response').length===1&&
    recovered.events.filter(e=>e.step_id===storageStep.id&&e.type==='step_finished').length===1&&recovered.events.every((e,i)=>e.sequence===i+1&&!discardedIds.includes(e.id)),
    'Storage recovery completes with exactly one eventual response/finish and no leaked aborted event identities');
  check(recovered.jobs.length===1&&recovered.jobs[0].status==='queued','Recovered browser storage leads to one actual queued analysis job');await storage.context.close();

  const selectedStop=await start();const stopStep=selectedStop.steps[0];await selectedStop.page.getByRole('group',{name:stopStep.choice.best_label,exact:true}).getByRole('radio').first().check();
  await selectedStop.page.getByRole('button',{name:'Stop study',exact:true}).click();await selectedStop.page.getByRole('heading',{name:'You have stopped the study.',exact:true}).waitFor({timeout:30000});
  const withdrawn=(await inspect()).runs.find(r=>r.id===selectedStop.run.run_id);
  check(withdrawn.completion==='withdrawn'&&withdrawn.transfer==='saved'&&withdrawn.replay.withdrawn,'Withdrawal with a selected partial pair has a durable withdrawn receipt');
  check(!withdrawn.events.some(e=>e.phase==='explicit_choice'&&['response','step_finished'].includes(e.type))&&withdrawn.jobs.length===0,'Unsubmitted selected choices do not become a completed pair or an analysis job');await selectedStop.context.close();

  let held=false,releaseHold;const heldPromise=new Promise(resolve=>{releaseHold=resolve;});
  const pendingStop=await start(async p=>p.route('**/api/events/**',async route=>{const body=route.request().postDataJSON();if(!held&&body.events.some(e=>e.type==='response'&&e.phase==='explicit_choice')){held=true;await heldPromise;}await route.continue();}));
  const pendingFirst=pendingStop.steps[0];await pendingStop.page.getByRole('group',{name:pendingFirst.choice.best_label,exact:true}).getByRole('radio').first().check();await pendingStop.page.getByRole('group',{name:pendingFirst.choice.worst_label,exact:true}).getByRole('radio').nth(1).check();await pendingStop.page.getByRole('button',{name:'Continue',exact:true}).click();
  await waitStep(pendingStop.page,pendingStop.run,pendingStop.steps[1]);await expect.poll(()=>held).toBe(true);await pendingStop.page.getByRole('group',{name:pendingStop.steps[1].choice.best_label,exact:true}).getByRole('radio').first().check();await pendingStop.page.getByRole('button',{name:'Stop study',exact:true}).click();
  await pendingStop.page.getByRole('heading',{name:'Saving your partial session',exact:true}).waitFor();check(await pendingStop.page.getByRole('heading',{name:'Thank you. Your responses are saved.',exact:true}).count()===0,'Withdrawal while prior answer delivery is pending never displays completed-study confirmation');
  releaseHold();await pendingStop.page.getByRole('heading',{name:'You have stopped the study.',exact:true}).waitFor({timeout:30000});const pendingSaved=(await inspect()).runs.find(r=>r.id===pendingStop.run.run_id);
  check(pendingSaved.completion==='withdrawn'&&pendingSaved.transfer==='saved'&&pendingSaved.events.filter(e=>e.phase==='explicit_choice'&&e.type==='response').length===1&&pendingSaved.jobs.length===0,'Pending prior answer is retained once, while the later selected pair remains unsubmitted and the run withdrawn');await pendingStop.context.close();

  // Negative direct HTTP contracts use declared original synthetic clock
  // fixtures. They are not represented as browser-measured response times.
  const request=async(pathname,body,token)=>{const response=await fetch(base+pathname,{method:'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},body:JSON.stringify(body)});return{status:response.status,body:await response.json()};};
  const begun=await request(`/api/start/${config.direct.token}`,{consented:true,client_id:randomUUID(),operation_id:randomUUID()});assert.equal(begun.status,200);const apiRun=begun.body,apiStep=apiRun.protocol.timeline[0];assert.equal(apiStep.type,'maxdiff');
  const event=(sequence,type,payload,clock='original-negative-fixture',time=sequence)=>({sequence,id:`event-${randomUUID()}`,type,step_id:apiStep.id,stimulus_id:null,condition_id:null,question_id:null,phase:apiStep.phase,
    clock:{id:'browser-monotonic',unit:'ms',value:String(time),instance_id:clock,time_origin_ms:'1'},payload});
  const post=body=>request(`/api/events/${apiRun.run_id}`,body,apiRun.access_token),batch=e=>({events:[e],operation_id:randomUUID()});
  assert.equal((await post(batch(event(1,'step_started',{resumed:false})))).status,200);
  const ids=apiStep.choice.item_order,payload=value=>({value,response_time_ms:1,active_segment_response_ms:1,resumed:false});
  const invalid=[['same best and worst',event(2,'response',payload({best_id:ids[0],worst_id:ids[0]}))],['foreign offered item',event(2,'response',payload({best_id:'not-offered',worst_id:ids[1]}))],
    ['numeric identity coercion',event(2,'response',payload({best_id:1,worst_id:ids[1]}))],['required null omission',event(2,'response',payload(null))],
    ['invented uninterrupted time',event(2,'response',{...payload({best_id:ids[0],worst_id:ids[1]}),response_time_ms:99})],['unrecorded recovery flag',event(2,'response',{...payload({best_id:ids[0],worst_id:ids[1]}),resumed:true,response_time_ms:null})],
    ['foreign page clock',event(2,'response',payload({best_id:ids[0],worst_id:ids[1]}),'foreign-page')],['completion without a response',event(2,'step_finished',{elapsed_ms:1,resumed:false})]];
  for(const[label,e]of invalid){const response=await post(batch(e));check(response.status>=400&&response.status<500,`Real receiver rejects ${label} without accepting another sequence`);}
  const valid=batch(event(2,'response',payload({best_id:ids[0],worst_id:ids[1]})));assert.equal((await post(valid)).status,200);assert.equal((await post(valid)).status,200);
  const duplicate=await post(batch(event(3,'response',{value:{best_id:ids[1],worst_id:ids[0]},response_time_ms:2,active_segment_response_ms:2,resumed:false})));check(duplicate.status===409,'A new response identity cannot overwrite an acknowledged pair');
  const stop=event(3,'withdrawal',{outcome:'withdrawn',reason:'original_negative_fixture_finished'});assert.equal((await post(batch(stop))).status,200);
  const receipt=await request(`/api/finish/${apiRun.run_id}`,{outcome:'withdrawn',final_sequence:3,operation_id:randomUUID()},apiRun.access_token);assert.equal(receipt.status,200);
  const apiSaved=(await inspect()).runs.find(r=>r.id===apiRun.run_id);check(apiSaved.events.length===3&&apiSaved.events[1].id===valid.events[0].id&&apiSaved.completion==='withdrawn','Rejected direct events leave no retained rows and exact duplicate acknowledgement leaves one pair');
  check(errors.length===0,`No actual browser exceptions: ${errors.join('; ')}`);
  check(traffic.every(row=>row.status===503)&&traffic.length===1,'Only the deliberately lost acknowledgement produced failed browser traffic');
  await fs.writeFile(path.join(folder,'results.json'),JSON.stringify({scope:'actual_browser_real_participant_launcher_and_receiver',origin:'original_synthetic_sample',checks,scans,traffic,completed_run_id:run.run_id,
    limitations:['No scientific job was run; the real completed-study analysis job was verified as queued.','No physical device or human participant was used.','Negative direct HTTP cases used declared synthetic clocks; main and withdrawal visits used actual browser clocks.']},null,2));
  console.log(JSON.stringify({checks:checks.length,axe_scans:scans.length,folder}));
}catch(error){await lastPage?.screenshot({path:path.join(folder,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(folder,'failure.json'),JSON.stringify({error:error.stack,checks,errors,traffic,log,text:await lastPage?.locator('body').innerText().catch(()=>'(closed)')},null,2));throw error;}
finally{
  if(browser)await browser.close();
  if(child&&child.exitCode===null){await fs.writeFile(path.join(folder,'stop.request'),'Stop the owned original MaxDiff participant fixture.');await expect.poll(()=>child.exitCode!==null,{timeout:15000,intervals:[100,250]}).toBe(true);}
  await fs.writeFile(path.join(folder,'server.log'),log);
  if(child)assert.equal(child.exitCode,0,log);
}
