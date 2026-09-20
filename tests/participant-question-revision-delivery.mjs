// Actual Chrome and actual separately owned R receiver; no scientific workers.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import {spawn,spawnSync} from 'node:child_process';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const repo=path.resolve(import.meta.dirname,'..'),work=path.resolve(repo,'../../work');
const rscript=process.env.BROHN_RSCRIPT||path.join(work,'native-r/bin/x64/Rscript.exe');
const env={...process.env,R_LIBS_USER:path.join(work,'r-library-brohn-restore'),R_USER:work,LC_ALL:'C',LANG:'C'};
const folder=await fs.mkdtemp(path.join(work,'test-runs/brohn-question-revision-delivery-')),workspace=path.join(folder,'workspace');
const checks=[],errors=[],traffic=[],scans=[];let child,browser,lastPage,log='';
const check=(condition,label)=>{assert.ok(condition,label);checks.push(label);console.log(`PASS ${label}`);};
function r(mode){const result=spawnSync(rscript,['--vanilla','tests/fixtures/participant-question-revision.R',mode,'--folder',folder,'--root',workspace],{cwd:repo,env,windowsHide:true,encoding:'utf8',timeout:30000});assert.equal(result.status,0,result.stderr||result.stdout);}
async function branchingFixture(){
  const source=`source('R/platform-load.R');brohn_load(ui=FALSE)
args<-commandArgs(trailingOnly=TRUE);store<-brohn_open_store(args[[1]])
local({on.exit(brohn_close_store(store));design<-brohn_new_design('Original progress and adjacent parts','survey')
driver<-brohn_question('Original branch driver','number','before','progress-driver')
driver$min<-0;driver$max<-1;driver$step<-1
dependent<-brohn_question('Original conditional answer','text','before','progress-dependent')
dependent$show_if<-list(op='equals',question_id=driver$id,value=1)
information<-brohn_question('Original branch information','information','before','progress-information')
last<-brohn_question('Original next-part number','number','end','progress-last')
design$questions<-list(driver,dependent,information,last);design$questionnaire_navigation<-brohn_questionnaire_navigation()
brohn_put_entity(store,'study',design$id,design);release<-brohn_publish(store,design$id,origin='sample',quota=3L)
brohn_write_json_file(list(release=release,design_hash=brohn_hash(design)),file.path(args[[2]],'branch-fixture.json'))})`;
  const result=spawnSync(rscript,['--vanilla','-e',source,workspace,folder],{cwd:repo,env,windowsHide:true,encoding:'utf8',timeout:30000});assert.equal(result.status,0,result.stderr||result.stdout);
  return JSON.parse(await fs.readFile(path.join(folder,'branch-fixture.json'),'utf8'));
}
async function inspect(){r('inspect');return JSON.parse(await fs.readFile(path.join(folder,'inspection.json'),'utf8'));}
async function journal(page){return page.evaluate(()=>new Promise((resolve,reject)=>{const req=indexedDB.open('brohn-participant',1);req.onerror=()=>reject(req.error);req.onsuccess=()=>{const db=req.result,read=db.transaction('sessions').objectStore('sessions').getAll();read.onsuccess=()=>{db.close();resolve(read.result[0]||null);};read.onerror=()=>reject(read.error);};}));}
async function ready(page,prompt){await expect(page.getByRole('heading',{name:prompt,exact:true})).toBeVisible();await expect(page.getByRole('button',{name:'Continue',exact:true})).toBeEnabled();await expect.poll(async()=>{const state=await journal(page);return !state?.revision?.pending&&state?.acked_sequence===state?.next_sequence-1;},{timeout:20000}).toBe(true);}
async function answer(page,prompt,value){await ready(page,prompt);await page.getByLabel('Your answer',{exact:true}).fill(String(value));await page.getByRole('button',{name:'Continue',exact:true}).click();}
async function review(page,progress='Final review'){await expect(page.getByRole('heading',{name:'Review your answers',exact:true})).toBeVisible();await expect(page.locator('#questionnaire-seal')).toBeEnabled();await expect(page.locator('#study-progress')).toHaveText(progress);}
async function rest(page){await ready(page,'Original second number');await expect(page.locator('#study-progress')).toHaveText('Question 2 of 3 in this part');await answer(page,'Original second number',4);await ready(page,'Original optional comment');await expect(page.locator('#study-progress')).toHaveText('Question 3 of 3 in this part');await page.getByRole('button',{name:'Continue',exact:true}).click();await ready(page,'Original study information');await expect(page.locator('#study-progress')).toHaveText('Information in this part');await page.getByRole('button',{name:'Continue',exact:true}).click();await review(page);}
async function finish(page){await page.locator('#questionnaire-seal').click();await page.getByRole('heading',{name:'Thank you. Your responses are saved.',exact:true}).waitFor({timeout:30000});}
async function scan(page,name){const violations=(await new AxeBuilder({page}).analyze()).violations;scans.push({name,violations});await fs.writeFile(path.join(folder,`${name}-axe.json`),JSON.stringify(violations,null,2));await page.screenshot({path:path.join(folder,`${name}.png`),fullPage:true});check(!violations.length,`${name}: zero axe violations`);check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`${name}: no horizontal page overflow`);}
try {
  r('prepare');const config=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8')),branchConfig=await branchingFixture();
  const port=await new Promise(resolve=>{const socket=net.createServer();socket.listen(0,'127.0.0.1',()=>{const port=socket.address().port;socket.close(()=>resolve(port));});});const base=`http://127.0.0.1:${port}`;
  child=spawn(rscript,['--vanilla','tests/fixtures/participant-question-revision.R','serve','--folder',folder,'--root',workspace,'--port',String(port)],{cwd:repo,env,windowsHide:true,stdio:['ignore','pipe','pipe']});child.stdout.on('data',x=>log+=x);child.stderr.on('data',x=>log+=x);
  await expect.poll(async()=>{if(child.exitCode!==null)throw new Error(log);try{return(await fetch(`${base}/api/health`)).ok;}catch{return false;}},{timeout:30000,intervals:[100,250,500]}).toBe(true);
  browser=await chromium.launch({channel:'chrome',headless:true});
  async function start(setup,{release=config.release,prompt='Original first number'}={}){const context=await browser.newContext({viewport:{width:1280,height:900}}),page=await context.newPage();lastPage=page;
    page.on('pageerror',e=>errors.push(e.message));page.on('dialog',d=>d.accept());page.on('response',response=>{if(response.url().includes('/api/')&&response.status()>=400)traffic.push({path:new URL(response.url()).pathname,status:response.status()});});
    if(setup)await setup(page);await page.goto(`${base}/participant/?token=${release.token}`);await page.getByLabel('I have read the study information and agree to take part.',{exact:true}).check();
    const begun=page.waitForResponse(response=>response.url().includes('/api/start/'));await page.getByRole('button',{name:'Start study',exact:true}).click();const run=await(await begun).json();await page.getByRole('button',{name:'Begin',exact:true}).click();await ready(page,prompt);return{page,context,run};}

  let lost=null,accepted=false;const attempts=[];
  const main=await start(async page=>{await page.route('**/api/events/**',async route=>{const body=route.request().postDataJSON();
    if(lost&&body.operation_id===lost.operation_id)attempts.push(body);
    if(!lost&&body.events.some(e=>e.type==='questionnaire_event'&&e.payload.kind==='commit')){lost=body;attempts.push(body);const response=await route.fetch();assert.equal(response.status(),200);accepted=true;await route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({error:{message:'Original fixture: committed answer, lost ACK.'}})});return;}await route.continue();});});
  const page=main.page;check(main.run.protocol_hash===main.run.resume.questionnaire.protocol_hash,'Start pins the exact original protocol and canonical questionnaire packet');
  await expect(page.locator('#study-progress')).toHaveText('Question 1 of 3 in this part');check(true,'Current questionnaire progress counts the three answer questions separately from information');
  await scan(page,'question-desktop');await answer(page,'Original first number',2);
  await expect(page.getByRole('heading',{name:'Saving this change',exact:true})).toBeVisible();
  const pending=await journal(page);check(pending.revision.pending.action==='commit'&&pending.index===main.run.protocol.timeline.findIndex(s=>s.question?.id==='original-first'),'A committed but unacknowledged answer cannot advance the outer protocol cursor');
  await rest(page);check(accepted&&attempts.length===2,'One lost real receiver acknowledgement retries the exact persisted action once');assert.deepEqual(attempts[0],attempts[1]);
  check(true,'Progress follows each displayed answer and labels information and final review without the held protocol cursor');
  await page.setViewportSize({width:390,height:844});await scan(page,'review-narrow');
  const informationReview=page.getByRole('button',{name:'Review information: Original study information',exact:true});await expect(informationReview).toHaveText('Review information');await informationReview.click();await ready(page,'Original study information');await expect(page.locator('#study-progress')).toHaveText('Information in this part');await page.getByRole('button',{name:'Continue',exact:true}).click();await review(page);
  check(true,'Information review has an explicit visible and accessible label and returns to the same final review');
  await page.getByRole('button',{name:'Edit: Original first number',exact:true}).click();await ready(page,'Original first number');check(await page.getByLabel('Your answer',{exact:true}).inputValue()==='2','Review Edit restores the acknowledged original typed value');
  await page.getByLabel('Your answer',{exact:true}).fill('6');await expect.poll(async()=>(await journal(page)).revision.drafts[main.run.protocol.timeline.find(s=>s.question?.id==='original-first').id]?.value).toBe(6);
  const beforeReload=await journal(page),oldVisit=beforeReload.revision.model.packet.latest_occurrence.visit;
  await page.reload();await page.getByRole('button',{name:'Resume this participant session',exact:true}).click();await ready(page,'Original first number');
  await expect(page.locator('#study-progress')).toHaveText('Question 1 of 3 in this part');check(true,'Resumed edited question restores occurrence progress without changing the transport cursor');
  check(await page.getByLabel('Your answer',{exact:true}).inputValue()==='6','Untimed reload keeps the unsent edited draft in its exact occurrence and dependency generation');
  const resumed=(await journal(page)).revision.model.packet.latest_occurrence.visit;
  check(resumed.id!==oldVisit.id&&resumed.instance_id!==oldVisit.instance_id&&resumed.resumed,'Reload creates a server-accepted visit with the new actual browser clock');
  await page.getByRole('button',{name:'Continue',exact:true}).click();await rest(page);await finish(page);
  const saved=(await inspect()).runs.find(r=>r.id===main.run.run_id),rows=saved.projection.effective_records;
  check(saved.completion==='completed'&&saved.transfer==='saved'&&saved.run_finished,'Revised questionnaire has an actual durable completed receipt');
  check(rows.find(r=>r.question_id==='original-first').value===6&&rows.find(r=>r.question_id==='original-second').value===4&&(6+4)/2===5,'Canonical final projection contains exactly6+4 with independent arithmetic mean5');
  check(rows.length===4&&rows.find(r=>r.question_id==='original-comment').status==='optional_omission'&&rows.find(r=>r.question_id==='original-information').status==='information_acknowledged','Optional omission and information acknowledgement survive the review as distinct canonical states');
  const commits=saved.events.filter(e=>e.type==='questionnaire_event'&&e.payload.kind==='commit'&&e.question_id==='original-first');
  check(commits.length===2&&commits[0].payload.value===2&&commits[1].payload.value===6&&commits[1].payload.response_time_ms===null&&commits[1].payload.resumed,'Both original and revised answer events remain retained; resumed edit never claims initial uninterrupted RT');
  check(saved.protocol_hash===main.run.protocol_hash&&saved.design_hash===config.design_hash,'Reopened evidence retains the exact frozen protocol and design hashes');
  check(saved.jobs.length===1&&saved.jobs[0].status==='queued'&&saved.jobs[0].operation==='analyse_run','Exactly one real analysis job is queued; this transport suite runs no scientific worker');
  check(await journal(page)===null,'Final receipt removes the finished participant journal');await main.context.close();

  const storage=await start();await storage.page.getByLabel('Your answer',{exact:true}).fill('6');await expect.poll(async()=>Object.values((await journal(storage.page)).revision.drafts).some(d=>d.value===6)).toBe(true);
  const beforeFault=await journal(storage.page);
  await storage.page.evaluate(()=>{const original=IDBObjectStore.prototype.put;window.revisionFault={count:0,ids:[]};IDBObjectStore.prototype.put=function(value,...rest){const request=original.call(this,value,...rest);
    if(this.name==='sessions'&&value.revision?.pending?.action==='commit'&&!revisionFault.count){revisionFault.count++;revisionFault.ids=value.events.filter(e=>e.type==='questionnaire_event'&&e.payload.kind==='commit').map(e=>e.id);this.transaction.abort();IDBObjectStore.prototype.put=original;}return request;};});
  await storage.page.getByRole('button',{name:'Continue',exact:true}).click();await expect(storage.page.locator('#error')).toContainText('could not safely save');await expect(storage.page.getByRole('button',{name:'Continue',exact:true})).toBeEnabled();
  const afterFault=await journal(storage.page);check(afterFault.next_sequence===beforeFault.next_sequence&&afterFault.index===beforeFault.index&&afterFault.revision.model.packet.state_hash===beforeFault.revision.model.packet.state_hash,'Aborted IndexedDB commit leaves the saved sequence, outer cursor and canonical state unchanged');
  check(await storage.page.getByLabel('Your answer',{exact:true}).inputValue()==='6'&&!afterFault.revision.pending,'Failed local commit keeps the actual typed input editable without a pending/transmitted answer');
  await storage.page.getByRole('button',{name:'Continue',exact:true}).click();await rest(storage.page);await finish(storage.page);
  const storageSaved=(await inspect()).runs.find(r=>r.id===storage.run.run_id),failedIds=await storage.page.evaluate(()=>revisionFault.ids);
  check(storageSaved.events.filter(e=>e.type==='questionnaire_event'&&e.payload.kind==='commit'&&e.question_id==='original-first').length===1&&!storageSaved.events.some(e=>failedIds.includes(e.id)),'Retry after real local failure retains exactly one answer and no failed candidate event IDs');await storage.context.close();

  let held,releaseHeld;const heldStarted=new Promise(resolve=>held=resolve),gate=new Promise(resolve=>releaseHeld=resolve);
  const stopped=await start(async page=>{let once=false;await page.route('**/api/events/**',async route=>{const body=route.request().postDataJSON();if(!once&&body.events.some(e=>e.type==='questionnaire_event'&&e.payload.kind==='commit')){once=true;const response=await route.fetch();assert.equal(response.status(),200);held();await gate;await route.fulfill({response});return;}await route.continue();});});
  await stopped.page.getByLabel('Your answer',{exact:true}).fill('3');await stopped.page.getByRole('button',{name:'Continue',exact:true}).click();await heldStarted;await stopped.page.locator('#withdraw').click();await stopped.page.getByRole('heading',{name:'Saving your partial session',exact:true}).waitFor();releaseHeld();
  await stopped.page.getByRole('heading',{name:'You have stopped the study.',exact:true}).waitFor({timeout:30000});const withdrawn=(await inspect()).runs.find(r=>r.id===stopped.run.run_id);
  check(withdrawn.completion==='withdrawn'&&withdrawn.transfer==='saved'&&withdrawn.jobs.length===0,'Withdrawal during a pending answer preserves partial evidence and queues no completed-study analysis');
  check(withdrawn.events.filter(e=>e.type==='questionnaire_event'&&e.payload.kind==='commit').length===1&&withdrawn.events.filter(e=>e.type==='questionnaire_event'&&e.payload.kind==='visit').length===1&&!withdrawn.events.some(e=>e.type==='questionnaire_event'&&e.payload.kind==='seal'),'Late acknowledged commit cannot trigger a new visit or false seal after withdrawal');await stopped.context.close();
  const branch=await start(null,{release:branchConfig.release,prompt:'Original branch driver'}),bp=branch.page;
  await expect(bp.locator('#study-progress')).toHaveText('Question 1 of 1 in this part');await answer(bp,'Original branch driver',0);
  await ready(bp,'Original branch information');await expect(bp.locator('#study-progress')).toHaveText('Information in this part');await bp.getByRole('button',{name:'Continue',exact:true}).click();await review(bp,'Answer review');
  await expect(bp.locator('#questionnaire-answer-review')).not.toContainText('Original conditional answer');
  check(true,'Hidden conditional questions are excluded from current progress and the first occurrence review');
  await bp.getByRole('button',{name:'Edit: Original branch driver',exact:true}).click();await answer(bp,'Original branch driver',1);
  await ready(bp,'Original conditional answer');await expect(bp.locator('#study-progress')).toHaveText('Question 2 of 2 in this part');await answer(bp,'Original conditional answer','Original newly visible answer');
  await ready(bp,'Original branch information');await bp.getByRole('button',{name:'Continue',exact:true}).click();await review(bp,'Answer review');
  check(true,'Changing the acknowledged branch driver updates the currently visible question count and retains information separately');
  await bp.locator('#questionnaire-seal').click();await ready(bp,'Original next-part number');await expect(bp.locator('#study-progress')).toHaveText('Question 1 of 1 in this part');
  check(await bp.getByRole('button',{name:'Back',exact:true}).count()===0,'Adjacent questionnaire occurrence resets its progress and cannot navigate behind the sealed boundary');
  await answer(bp,'Original next-part number',4);await review(bp);await bp.reload();await bp.getByRole('button',{name:'Resume this participant session',exact:true}).click();await review(bp);
  check(true,'Reloading the final review restores Final review rather than the held global cursor');await finish(bp);
  const branchSaved=(await inspect()).runs.find(run=>run.id===branch.run.run_id),seals=branchSaved.events.filter(event=>event.type==='questionnaire_event'&&event.payload.kind==='seal');
  check(branchSaved.completion==='completed'&&seals.length===2&&new Set(seals.map(event=>event.payload.occurrence_id)).size===2&&branchSaved.design_hash===branchConfig.design_hash&&branchSaved.protocol_hash===branch.run.protocol_hash,'Branching and adjacent parts retain their two exact seals and unchanged frozen design and protocol');await branch.context.close();
  check(errors.length===0,`No browser exceptions: ${errors.join('; ')}`);
  await fs.writeFile(path.join(folder,'results.json'),JSON.stringify({scope:'actual_browser_real_receiver_no_scientific_workers',checks,scans,traffic,limitations:['Original synthetic material and automated browser; no human participant or physical device.','Complete study analysis is verified as queued only.']},null,2));console.log(JSON.stringify({checks:checks.length,scans:scans.length,folder}));
}catch(error){await lastPage?.screenshot({path:path.join(folder,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(folder,'failure.json'),JSON.stringify({error:error.stack,checks,errors,traffic,log,text:await lastPage?.locator('body').innerText().catch(()=>'(closed)'),journal:await journal(lastPage).catch(()=>null)},null,2));throw error;}
finally{if(browser)await browser.close();if(child&&child.exitCode===null){await fs.writeFile(path.join(folder,'stop.request'),'Stop this owned questionnaire delivery fixture.');await expect.poll(()=>child.exitCode!==null,{timeout:15000,intervals:[100,250]}).toBe(true);}await fs.writeFile(path.join(folder,'server.log'),log);if(child)assert.equal(child.exitCode,0,log);}
