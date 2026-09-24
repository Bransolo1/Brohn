// Actual browser transfer/recovery of an independently accepted synthetic journal.
// This does not claim a second trial-presentation or physical-timing experiment.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import crypto from 'node:crypto';
import {spawn,spawnSync} from 'node:child_process';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const repo=path.resolve(import.meta.dirname,'..'),work=path.resolve(repo,'../../work');
const baseline=path.resolve(process.argv[2]||'');
assert.ok(process.argv[2],'Supply the accepted original large-receiver fixture directory.');
const rscript=process.env.BROHN_RSCRIPT||path.join(work,'native-r/bin/Rscript.exe');
const env={...process.env,R_LIBS_USER:path.join(work,'r-library-brohn-restore'),R_USER:work,LC_ALL:'C',LANG:'C',
  BROHN_PUBLICATION_PYTHON:path.join(work,'tooling/methods-venv/Scripts/python.exe'),
  BROHN_PUBLICATION_NATIVE_MANIFEST:path.join(work,'tooling/brohn-native/publication-guard.json')};
const folder=await fs.mkdtemp(path.join(work,'test-runs/brohn-preferred-delivery-')),workspace=path.join(folder,'workspace');
const checks=[],errors=[],scans=[],cases=[],assetResponses=[],pendingGates=[];let child,browser,lastPage,log='',prepared=false;
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const sourceFiles=['R/platform-store.R','R/platform-delivery.R','R/platform-load.R','R/platform-sciat-window-delivery.R',
  'scripts/run-participant.R','www/participant/index.html','www/participant/event-batch.js','www/participant/runner.js',
  'tests/fixtures/participant-preferred-delivery.R','tests/participant-preferred-delivery.mjs'];
if(/["']runner-assets["']|platform-runner-assets\.R/.test(await fs.readFile(path.join(repo,'R/platform-load.R'),'utf8')))
  sourceFiles.push('R/platform-runner-assets.R');
const hashes=async()=>Object.fromEntries(await Promise.all(sourceFiles.map(async f=>[f,sha(await fs.readFile(path.join(repo,f)))])));
const sourceStart=await hashes();await fs.writeFile(path.join(folder,'source-start.json'),JSON.stringify(sourceStart,null,2));
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log('PASS',label);};
function r(mode){const result=spawnSync(rscript,['--vanilla','tests/fixtures/participant-preferred-delivery.R',mode,
  '--folder',folder,'--root',workspace,'--baseline',baseline],{cwd:repo,env,windowsHide:true,encoding:'utf8',timeout:120000});
  assert.equal(result.status,0,result.stderr||result.stdout);}
async function inspect(mode='inspect'){r(mode);return JSON.parse(await fs.readFile(path.join(folder,'inspection.json'),'utf8'));}
async function record(page,token){return page.evaluate(token=>new Promise((resolve,reject)=>{
  const request=indexedDB.open('brohn-participant',1);request.onerror=()=>reject(request.error);request.onsuccess=()=>{
    const db=request.result,get=db.transaction('sessions').objectStore('sessions').get(token);
    get.onerror=()=>{db.close();reject(get.error);};get.onsuccess=()=>{db.close();resolve(get.result||null);};};}),token);}
async function scan(page,name){const violations=(await new AxeBuilder({page}).analyze()).violations;
  scans.push({name,violations});await fs.writeFile(path.join(folder,`${name}-axe.json`),JSON.stringify(violations,null,2));
  await page.screenshot({path:path.join(folder,`${name}.png`),fullPage:true});
  check(!violations.length,`${name}: no axe violations`);check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`${name}: no horizontal page overflow`);}
const deferred=()=>{let resolve;const promise=new Promise(r=>resolve=r);return{promise,resolve};};
const within=(promise,millis,message)=>{let timer;return Promise.race([promise,new Promise((_,reject)=>{
  timer=setTimeout(()=>reject(new Error(message)),millis);})]).finally(()=>clearTimeout(timer));};
try{
  r('prepare');prepared=true;const config=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
  const sourceRaw=await fs.readFile(config.source_path),journal=JSON.parse(sourceRaw),oldEnvelope=JSON.parse(await fs.readFile(config.original_batch_path,'utf8'));
  check(sha(sourceRaw)===config.source_sha256&&journal.length===394,'Original complete394event journal is read without rewriting its source');
  const port=await new Promise(resolve=>{const server=net.createServer();server.listen(0,'127.0.0.1',()=>{const port=server.address().port;server.close(()=>resolve(port));});});
  const base=`http://127.0.0.1:${port}`;
  child=spawn(rscript,['--vanilla','tests/fixtures/participant-preferred-delivery.R','serve','--folder',folder,'--root',workspace,'--port',String(port)],
    {cwd:repo,env,windowsHide:true,stdio:['ignore','pipe','pipe']});child.stdout.on('data',x=>log+=x);child.stderr.on('data',x=>log+=x);
  await expect.poll(async()=>{if(child.exitCode!==null)throw new Error(log);try{return(await fetch(`${base}/api/health`)).ok;}catch{return false;}},
    {timeout:30000,intervals:[100,250,500]}).toBe(true);
  browser=await chromium.launch({channel:'chrome',headless:true});
  for(const kind of ['preferred','persisted']){
    const release=config.releases[kind],context=await browser.newContext({viewport:{width:1280,height:900}}),page=await context.newPage();lastPage=page;
    page.on('pageerror',e=>errors.push(e.message));page.on('dialog',d=>d.accept());
    page.on('response',response=>{if(/\/(runner|event-batch)\.js$/.test(new URL(response.url()).pathname))assetResponses.push((async()=>({
      case:kind,url:new URL(response.url()).pathname,hash:sha(await response.body()),status:response.status()}))());});
    await page.goto(`${base}/participant/?token=${release.token}`);
    await page.getByLabel('I have read the study information and agree to take part.',{exact:true}).check();
    const started=page.waitForResponse(x=>x.url().includes('/api/start/')&&x.request().method()==='POST');
    await page.getByRole('button',{name:'Start study',exact:true}).click();const startResponse=await started;
    check(startResponse.status()===200,`${kind}: real consent/start creates the original assigned sample session`);
    const run=await startResponse.json();await expect.poll(async()=>(await record(page,release.token))?.run_id,{timeout:20000}).toBe(run.run_id);
    // Stop the presentation page before loading the intentionally synthetic complete local journal.
    await page.goto(`${base}/api/health`);const initial=await record(page,release.token);
    check(initial.acked_sequence===0&&initial.events.length===0,`${kind}: no actual timed trial or key evidence is replaced by the transfer fixture`);
    assert.deepEqual(run.protocol.timeline,initial.protocol.timeline);
    const saved={...initial,events:structuredClone(journal),acked_sequence:0,next_sequence:395,index:run.protocol.timeline.length,
      step_state:'finishing',current_step:null,batch:kind==='persisted'?{operation_id:oldEnvelope.operation_id,first:1,last:100}:null,
      finish:{operation_id:`original-preferred-finish-${kind}`,outcome:'completed',final_sequence:394},delivery_blocked:false,delivery_error:null};
    await page.evaluate(saved=>new Promise((resolve,reject)=>{const request=indexedDB.open('brohn-participant',1);request.onerror=()=>reject(request.error);
      request.onsuccess=()=>{const db=request.result,tx=db.transaction('sessions','readwrite');tx.objectStore('sessions').put(saved);
        tx.oncomplete=()=>{db.close();resolve();};tx.onerror=()=>{db.close();reject(tx.error);};};}),saved);
    const accepted=deferred(),releaseLost=deferred(),finishAccepted=deferred(),releaseFinish=deferred(),attempts=[],finishes=[];
    pendingGates.push(releaseLost,releaseFinish);
    let firstWire=null,firstOperation=null,lost=false,finishLost=false,reloading=false,finishReloading=false;
    await page.route('**/api/events/**',async route=>{
      const wire=route.request().postData(),body=JSON.parse(wire),then=performance.now();
      attempts.push({operation_id:body.operation_id,first:body.events[0].sequence,last:body.events.at(-1).sequence,bytes:Buffer.byteLength(wire),sha256:sha(wire),reloading});
      if(!lost){lost=true;firstWire=wire;firstOperation=body.operation_id;const response=await route.fetch({timeout:180000});
        assert.equal(response.status(),200,await response.text());attempts.at(-1).server_elapsed_s=(performance.now()-then)/1000;
        accepted.resolve(await response.json());await releaseLost.promise;await route.abort('failed').catch(()=>{});return;}
      if(!reloading&&body.operation_id===firstOperation){await route.abort('failed').catch(()=>{});return;}
      await route.continue();
    });
    if(kind==='preferred')await page.route('**/api/finish/**',async route=>{
      const wire=route.request().postData();finishes.push({sha256:sha(wire),body:JSON.parse(wire),reloading:finishReloading});
      if(!finishLost){finishLost=true;const response=await route.fetch({timeout:180000});assert.equal(response.status(),200,await response.text());
        finishAccepted.resolve(await response.json());await releaseFinish.promise;await route.abort('failed').catch(()=>{});return;}
      if(!finishReloading){await route.abort('failed').catch(()=>{});return;}await route.continue();
    });
    await page.goto(`${base}/participant/?token=${release.token}`);
    await page.getByRole('heading',{name:'Your final receipt is pending',exact:true}).waitFor({timeout:30000});
    const serverReceipt=await within(accepted.promise,60000,'First committed event request was not observed.');
    const uncertain=await record(page,release.token);assert.deepEqual(uncertain.events,journal);
    check(uncertain.acked_sequence===0&&uncertain.batch.operation_id===firstOperation&&uncertain.batch.last===serverReceipt.acked_sequence,
      `${kind}: server commit without browser ACK leaves exact operation and complete local evidence pending`);
    if(kind==='persisted'){
      check(attempts[0].bytes>1572864&&attempts[0].last===100, 'Persisted3MiB operation above preference is reconstructed whole');
      assert.equal(firstWire,await fs.readFile(config.original_batch_path,'utf8'));
      check(true,'Persisted operation retains exact original envelope bytes, identity and sequence bounds');
    }else check(attempts[0].bytes<=1572864&&attempts[0].last===8,'Production runner applies the preferred prefix to a new operation');
    await page.screenshot({path:path.join(folder,`${kind}-uncertain-event.png`),fullPage:true});
    reloading=true;releaseLost.resolve();await page.reload();
    if(kind==='preferred'){
      await within(finishAccepted.promise,120000,'Committed finish not observed.');
      const finalPending=await record(page,release.token);
      check(finalPending.acked_sequence===394&&JSON.stringify(finalPending.finish)===JSON.stringify(saved.finish),
        'Committed but unacknowledged finish retains its exact operation and all394local events');
      assert.deepEqual(finalPending.events,journal);await page.screenshot({path:path.join(folder,'preferred-uncertain-finish.png'),fullPage:true});
      finishReloading=true;releaseFinish.resolve();await page.reload();
    }
    await page.getByRole('heading',{name:'Thank you. Your responses are saved.',exact:true}).waitFor({timeout:120000});
    const repeated=attempts.filter(x=>x.operation_id===firstOperation);
    check(repeated.length>=2&&repeated.some(x=>x.reloading)&&repeated.every(x=>x.sha256===sha(firstWire)),
      `${kind}: reload retries the exact uncertain operation without splitting, renaming or mutating it`);
    if(kind==='preferred')check(finishes.length>=2&&finishes.every(x=>x.sha256===finishes[0].sha256)&&finishes.some(x=>x.reloading),
      'Lost final acknowledgement reload resends the exact original finish request');
    check(await record(page,release.token)===null,`${kind}: local journal is deleted only after the real final receipt`);
    const received=(await inspect('cancel')).runs.find(x=>x.id===run.run_id);
    check(received.completion==='completed'&&received.transfer==='saved'&&received.acked_sequence===394&&received.source_equal&&received.timeline_equal&&received.design_equal,
      `${kind}: read-only reopened evidence retains the complete original journal and frozen design/timeline`);
    assert.deepEqual(received.events,journal);
    check(received.jobs.length===1&&received.jobs[0].operation==='analyse_run'&&received.jobs[0].status==='cancelled'&&received.jobs[0].attempt===0,
      `${kind}: exact retries produce one analysis job, cancelled before scientific execution`);
    const distinct=[...new Map(attempts.map(x=>[x.operation_id,x])).values()];
    check(distinct.every(x=>kind==='persisted'&&x.operation_id===oldEnvelope.operation_id||x.bytes<=1572864),
      `${kind}: subsequent new operations respect preference without rewriting the existing operation`);
    check(distinct.every((x,i)=>x.first===(i?distinct[i-1].last+1:1))&&distinct.at(-1).last===394,
      `${kind}: all accepted operation bounds cover the entire journal once in contiguous order`);
    await page.setViewportSize({width:390,height:844});await scan(page,`${kind}-saved-narrow`);
    cases.push({kind,run_id:run.run_id,attempts,finishes,events_hash:received.events_hash,jobs:received.jobs,receipt_count:received.receipt_count});
    await context.close();
  }
  const assets=await Promise.all(assetResponses);
  check(assets.length>=4&&assets.every(x=>x.status===200&&x.hash===sourceStart[`www/participant/${path.basename(x.url)}`]),
    'Actual pages load the exact frozen production runner and batch-helper bytes');
  assert.deepEqual(await hashes(),sourceStart);check(sha(await fs.readFile(config.source_path))===config.source_sha256,'All tested source files and original journal bytes stay unchanged');
  check(errors.length===0,`No browser exceptions: ${errors.join('; ')}`);
  await fs.writeFile(path.join(folder,'results.json'),JSON.stringify({passed:true,scope:'actual_browser_transfer_recovery_of_original_synthetic_journal_no_new_trial_presentation',
    checks,scans,cases,assets,source_hashes:sourceStart,source_journal_sha256:config.source_sha256,limits:['Synthetic prefilled journal; original native trial replay was independently checked.','No physical stimulus/input timing or new scientific worker qualification.','Normal production15s browser timeout is unchanged.']},null,2));
  console.log(JSON.stringify({passed:true,checks:checks.length,scans:scans.length,folder}));
}catch(error){await lastPage?.screenshot({path:path.join(folder,'failure.png'),fullPage:true}).catch(()=>{});
  await fs.writeFile(path.join(folder,'failure.json'),JSON.stringify({error:error.stack,checks,errors,cases,log,text:await lastPage?.locator('body').innerText().catch(()=>'(closed)')},null,2));throw error;
}finally{
  for(const gate of pendingGates)gate.resolve();
  if(browser)await browser.close();
  if(child&&child.exitCode===null){await fs.writeFile(path.join(folder,'stop.request'),'Stop this owned preferred-batching receiver.');await expect.poll(()=>child.exitCode!==null,{timeout:15000,intervals:[100,250]}).toBe(true);}
  if(prepared)r('cancel');await fs.writeFile(path.join(folder,'server.log'),log);if(child)assert.equal(child.exitCode,0,log);
}
