/* Isolated real-Chrome component evidence. No Brohn run or scientific report is created. */
import assert from 'node:assert/strict';import fs from 'node:fs/promises';import path from 'node:path';import http from 'node:http';
import {createRequire} from 'node:module';import {createHash} from 'node:crypto';
const require=createRequire(path.resolve('package.json')),{chromium,expect}=require('@playwright/test'),AxeBuilder=require('@axe-core/playwright').default;
const here=path.resolve(process.argv[2]),output=path.join(here,`evidence-browser-${Date.now()}`);await fs.mkdir(output);
const files={'gnat-core.js':'www/participant/gnat-core.js','gnat.js':'www/participant/gnat.js','compiled-example.json':path.join(here,'compiled.json')};
const sources=Object.fromEntries(await Promise.all(Object.entries(files).map(async([name,file])=>[name,await fs.readFile(file)])));
const sourceHashes=Object.fromEntries(Object.entries(sources).map(([name,b])=>[name,createHash('sha256').update(b).digest('hex')]));
const html=`<!doctype html><html lang="en"><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Original GNAT component rehearsal</title><style>body{margin:0;background:#10191e;color:#eff3f3;padding:24px}main{max-width:1000px;margin:auto}</style><main id="task"></main><script src="/gnat-core.js"></script><script src="/gnat.js"></script><script>
window.events=[];window.steps=[];window.result=null;window.error=null;window.controller=new AbortController();window.ready=false;
window.start=async(options={})=>{const compiled=await(await fetch('/compiled-example.json')).json();window.compiled=compiled;window.current=null;window.events=[];window.result=null;window.error=null;
const origin=performance.timeOrigin.toFixed(3);let sequence=0;
const clock=()=>({id:'browser-monotonic',unit:'ms',value:performance.now().toFixed(6),instance_id:'gnat-browser-'+origin,time_origin_ms:origin});
const emit=async(kind,data)=>{if(options.failOnset&&kind==='task_trial_started')throw Error('Fixture refuses durable onset write');
const event={sequence:++sequence,type:'task_event',clock:clock(),payload:{kind,data}};const copy=structuredClone([...window.events,event]);localStorage.setItem('gnat-events',JSON.stringify(copy));window.events=copy;};
try{window.result=await BrohnGnat.run({container:document.getElementById('task'),compiled,emit,onCheckpoint:async value=>{localStorage.setItem('gnat-checkpoint',JSON.stringify(value));window.current=compiled.timeline.find(t=>t.id===value.step_id);window.steps.push(value);},signal:controller.signal,clockInstanceId:clock().instance_id,checkpoint:options.checkpoint??null});}
catch(e){window.error=e.message;} };window.ready=true;</script></html>`;
const server=http.createServer((req,res)=>{const name=req.url.slice(1);if(sources[name]){res.writeHead(200,{'Content-Type':name.endsWith('.json')?'application/json':'text/javascript'});res.end(sources[name]);}
else{res.writeHead(200,{'Content-Type':'text/html'});res.end(html);}});await new Promise(r=>server.listen(0,'127.0.0.1',r));const url=`http://127.0.0.1:${server.address().port}/`;
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1200,height:900}});let page=await context.newPage();
const checks=[],errors=[],scans=[];const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log('PASS',label);};
const ready=async options=>{await page.goto(url);await page.bringToFront();page.on('pageerror',e=>errors.push(e.message));await page.waitForFunction(()=>window.ready);await page.evaluate(o=>{void window.start(o);},options||{});await expect(page.getByRole('button',{name:'Begin practice phase',exact:true})).toBeVisible();};
const startTrial=async()=>{await page.getByRole('button',{name:'Begin practice phase',exact:true}).click();await page.waitForFunction(()=>window.events.some(e=>e.payload.kind==='task_trial_started'));return page.evaluate(()=>window.events.find(e=>e.payload.kind==='task_trial_started').payload.data);};
const save=async label=>{const evidence=await page.evaluate(()=>({events:window.events,result:window.result,error:window.error,checkpoint:JSON.parse(localStorage.getItem('gnat-checkpoint'))}));await fs.writeFile(path.join(output,`${label}.json`),JSON.stringify(evidence,null,2));return evidence;};
const stop=async()=>{await page.evaluate(()=>window.controller.abort());await page.waitForFunction(()=>window.result||window.error);};
try{
  await ready();await page.setViewportSize({width:390,height:844});const violations=(await new AxeBuilder({page}).analyze()).violations;
  scans.push({scope:'initial self-paced instructions',width:390,violations:violations.length,overflow:await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1)});
  await page.screenshot({path:path.join(output,'instructions-mobile.png')});check(!violations.length&&!scans[0].overflow,'Initial instructions support narrow reflow and keyboard access');await stop();
  await page.setViewportSize({width:1200,height:900});await ready();
  await page.keyboard.down('Space');await page.getByRole('button',{name:'Begin practice phase',exact:true}).click();await expect(page.getByText('Release Space to continue.',{exact:true})).toBeVisible();
  await page.waitForTimeout(150);check(!(await page.evaluate(()=>window.events.some(e=>e.payload.kind==='task_trial_started'))),'Held instruction Space cannot become an onset or response');await page.keyboard.up('Space');
  await page.waitForFunction(()=>window.events.some(e=>e.payload.kind==='task_trial_started'));await page.keyboard.press('Space');await page.waitForFunction(()=>window.events.some(e=>e.payload.kind==='task_trial_finished'));
  await stop();let e=await save('held-and-first-response'),onset=e.events.find(x=>x.payload.kind==='task_trial_started').payload.data,finished=e.events.find(x=>x.payload.kind==='task_trial_finished').payload.data;
  check(onset.release_wait.held_codes.includes('Space')&&onset.release_wait.keys.some(k=>k.type==='up'&&k.code==='Space'&&k.trusted)&&!onset.held_codes.includes('Space'),'Actual key release and full pre-onset wait remain in the onset receipt');
  check(finished.response_code==='Space'&&finished.keys.some(k=>k.accepted&&k.trusted)&&finished.feedback_end_ms-finished.feedback_start_ms>=100&&finished.blank_end_ms-finished.feedback_end_ms>=400,'Trusted first Space uses observed feedback and blank with measured event latency');
  await ready();onset=await startTrial();await page.waitForFunction(()=>window.events.some(e=>e.payload.kind==='task_trial_finished'));e=await page.evaluate(()=>window.events.find(e=>e.payload.kind==='task_trial_finished').payload.data);
  check(e.response_ms===null&&e.response_code===null&&e.deadline_timer_ms>=e.deadline_ms&&e.deadline_frame_ms>=e.deadline_timer_ms,'Actual withholding has no invented RT and retains deadline timer plus subsequent frame');
  const cdp=await context.newCDPSession(page);await cdp.send('Input.dispatchKeyEvent',{type:'keyDown',code:'Space',key:' ',windowsVirtualKeyCode:32,nativeVirtualKeyCode:32,timestamp:(Number(onset.clock.time_origin_ms)+Number(onset.clock.value)+200)/1000});
  await page.waitForFunction(()=>window.result||window.error);e=await save('late-after-seal');
  const stopEvent=e.events.find(x=>x.payload.kind==='task_interrupted');check(e.result?.outcome==='interrupted'&&stopEvent?.payload.data.contradiction?.trial_id===onset.trial_id&&stopEvent.payload.data.contradiction.key.trusted,'Actual trusted delayed timestamp interrupts after sealed withholding while retaining original and contradictory receipts');await cdp.detach();
  await ready();await page.keyboard.down('Space');await page.getByRole('button',{name:'Begin practice phase',exact:true}).click();await expect(page.getByText('Release Space to continue.',{exact:true})).toBeVisible();
  const waitFocus=await context.newCDPSession(page);await waitFocus.send('Emulation.setFocusEmulationEnabled',{enabled:false});const waitOther=await context.newPage();await waitOther.goto('about:blank');await waitOther.bringToFront();
  await page.waitForFunction(()=>window.result||window.error);e=await save('release-wait-interruption');const failedWait=e.events.find(x=>x.payload.kind==='task_interrupted')?.payload.data;
  check(e.result?.outcome==='interrupted'&&!e.events.some(x=>x.payload.kind==='task_trial_started')&&failedWait?.release_wait?.held_codes.includes('Space')&&failedWait.release_wait.visibility.some(v=>!v.focused||!v.visible)&&failedWait.release_wait.end_ms===Number(failedWait.clock.value),'Focus loss during held-key wait preserves typed pre-onset evidence without inventing a trial');
  await waitOther.close();await page.bringToFront();await waitFocus.detach();await page.keyboard.up('Space');
  await ready();await startTrial();const focusSession=await context.newCDPSession(page);await focusSession.send('Emulation.setFocusEmulationEnabled',{enabled:false});
  const other=await context.newPage();await other.goto('about:blank');await other.bringToFront();await page.waitForFunction(()=>window.result||window.error);e=await save('focus-loss');
  check(e.result?.outcome==='interrupted'&&e.events.some(x=>x.payload.kind==='task_trial_finished'&&x.payload.data.outcome==='interrupted'&&x.payload.data.visibility.some(v=>!v.focused||!v.visible)),'Actual browser focus loss interrupts instead of earning correct withholding');await other.close();await page.bringToFront();await focusSession.detach();
  const prior=await page.evaluate(()=>({journal:localStorage.getItem('gnat-events'),checkpoint:JSON.parse(localStorage.getItem('gnat-checkpoint'))}));await page.reload();await page.waitForFunction(()=>window.ready);await page.evaluate(c=>{void window.start({checkpoint:c});},prior.checkpoint);await page.waitForFunction(()=>window.error);
  check((await page.evaluate(()=>window.error)).includes('cannot restart')&&await page.evaluate(()=>localStorage.getItem('gnat-events'))===prior.journal,'Refresh refuses timed restart and preserves the complete original local journal');await save('refresh-refusal');
  await ready({failOnset:true});await page.getByRole('button',{name:'Begin practice phase',exact:true}).click();await page.waitForFunction(()=>window.error);e=await save('durable-write-failure');
  check(e.error.includes('refuses durable onset')&&!e.events.some(x=>x.payload.kind==='task_trial_finished')&&!e.result,'Failed durable onset write cannot manufacture completion or proceed');
  const componentOnly=process.argv.includes('--component-only');let elapsed=null;
  if(!componentOnly){await ready();const begun=Date.now();let acted=null,instructed=null;
  while(!(await page.evaluate(()=>window.result||window.error))){
    if(Date.now()-begun>720000)throw Error('Complete384 component journey exceeded 12 minutes');
    const state=await page.evaluate(()=>({step:window.current,id:window.current?.id,material:!!document.querySelector('.gnat-material'),error:window.error}));
    if(state.step?.type==='task_instructions'&&instructed!==state.id){const b=page.getByRole('button',{name:/^Begin (practice|test) phase$/});if(await b.isVisible()){await b.click();instructed=state.id;}}
    else if(state.step?.type==='task_trial'&&state.material&&acted!==state.id){acted=state.id;if(state.step.expected_action==='go'){await page.waitForTimeout(120);await page.keyboard.press('Space');}}
    await page.waitForTimeout(25);
  }
  e=await save('complete-384');check(e.result?.outcome==='completed'&&e.result.responses.length===384&&e.events.filter(x=>x.payload.kind==='task_trial_started').length===384&&e.events.filter(x=>x.payload.kind==='task_trial_finished').length===384,'Actual full384 frozen trials finish with complete original timing receipts');
  check(e.result.responses.every(r=>r.correct===true&&((r.outcome==='hit'&&r.response_ms!==null)||(r.outcome==='correct_rejection'&&r.response_ms===null))),'All actual Go and genuine No-Go outcomes remain distinct with correct response denominators');
  check(e.events.filter(x=>x.payload.kind==='task_instructions').length===12,'All12 self-paced phase instructions were actually delivered');elapsed=Date.now()-begun;}
  check(errors.length===0,'Browser emitted no uncaught application errors');
  await fs.writeFile(path.join(output,'results.json'),JSON.stringify({passed:true,checks,scans,sourceHashes,component_only:componentOnly,complete_elapsed_ms:elapsed,scope:'Isolated actual Chrome component; no consent, hosted receipt, native scorer, participant device or physical-timing qualification.'},null,2));console.log(JSON.stringify({passed:true,checks:checks.length,output}));
}catch(error){await page.screenshot({path:path.join(output,'failure.png')}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,scans,sourceHashes,errors,evidence:await page.evaluate(()=>({events:window.events,result:window.result,error:window.error})).catch(()=>null)},null,2));throw error;}
finally{await browser.close();await new Promise(r=>server.close(r));}
