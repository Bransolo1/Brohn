// Actual Chrome component renderer, original compiled 192-trial procedures.
// This fixture deliberately does NOT claim consent/service/scoring integration.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import crypto from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {chromium} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const root=path.resolve(import.meta.dirname,'..'),source=path.resolve(process.argv[2]),quick=process.argv.includes('--quick');
const folder=path.join(source,`browser-${Date.now()}`);await fs.mkdir(folder,{recursive:true});
const compiled=JSON.parse(await fs.readFile(path.join(source,'compiled.json'),'utf8')),checks=[],scans=[],journals={},errors=[];
const continuationIndex=process.argv.indexOf('--continue-full'),continuation=continuationIndex<0?null:path.resolve(process.argv[continuationIndex+1]);
const sourceReceipt=JSON.parse(await fs.readFile(path.join(source,'results.json'),'utf8'));
for(const item of sourceReceipt.source)assert.equal(crypto.createHash('sha256').update(await fs.readFile(path.join(root,item.path))).digest('hex'),item.sha256,`Source changed: ${item.path}`);
if(continuation){
  const previous=JSON.parse(await fs.readFile(path.join(continuation,'failure.json'),'utf8'));
  for(const name of ['A','B']){assert.equal(previous.journals[name].result.outcome,'completed');assert.equal(previous.journals[name].result.responses.length,192);journals[name]=previous.journals[name];}
  checks.push(...previous.checks);scans.push(...previous.scans);
}
const check=(name,ok)=>{assert.ok(ok,name);checks.push(name);console.log(`PASS ${name}`);};
const html=`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Brohn SC-IAT component qualification</title></head><body style="margin:24px;color:#151820;background:#f5f6f8"><main id="task"></main><script src="/sciat-window-core.js"></script><script src="/sciat-window.js"></script><script>
const q=new URLSearchParams(location.search);window.qa={events:[],checkpoints:[],focus_events:[],prior_events:JSON.parse(sessionStorage.getItem('original-sciat-qa-events')||'[]'),result:null,error:null,transport_pending:q.get('mode')==='lost-ack'};
window.addEventListener('blur',e=>qa.focus_events.push({trusted:e.isTrusted,at:performance.now()}));
const clock=n=>({id:'browser-monotonic',unit:'ms',value:n.toFixed(6),instance_id:'qa-page-'+performance.timeOrigin,time_origin_ms:performance.timeOrigin.toFixed(3)});
window.controller=new AbortController();
fetch('/compiled.json').then(r=>r.json()).then(c=>{window.compiled=c[q.get('order')||'A'];return BrohnSciatWindow.run({container:document.getElementById('task'),compiled:window.compiled,
clockInstanceId:'qa-page-'+performance.timeOrigin,signal:controller.signal,checkpoint:q.get('mode')==='refresh'?{phase:'timed'}:q.get('mode')==='reload'?JSON.parse(sessionStorage.getItem('original-sciat-qa-checkpoint')||'null'):null,
onCheckpoint:async p=>{qa.checkpoints.push(structuredClone(p));if(q.get('mode')==='reload')sessionStorage.setItem('original-sciat-qa-checkpoint',JSON.stringify(p));if(q.get('mode')==='checkpoint-failure'&&p.phase==='timed')throw Error('original fixture journal unavailable');},
emit:async(kind,data)=>{if(q.get('mode')==='journal-failure'&&kind==='task_trial_started')throw Error('original fixture journal unavailable');qa.events.push({type:'task_event',clock:clock(performance.now()),payload:{kind,data:structuredClone(data)}});if(q.get('mode')==='reload')sessionStorage.setItem('original-sciat-qa-events',JSON.stringify(qa.events));}
});}).then(r=>{qa.result=r;document.getElementById('task').append(Object.assign(document.createElement('h2'),{textContent:r.outcome==='completed'?'Component task completed':'Component task interrupted'}));}).catch(e=>{qa.error=e.message;});
</script></body></html>`;
const server=http.createServer(async(req,res)=>{try{const url=new URL(req.url,'http://127.0.0.1');
  if(url.pathname==='/compiled.json'){res.setHeader('Content-Type','application/json');res.end(JSON.stringify(compiled));}
  else if(['/sciat-window.js','/sciat-window-core.js'].includes(url.pathname)){res.setHeader('Content-Type','text/javascript');res.end(await fs.readFile(path.join(root,'www/participant',url.pathname.slice(1))));}
  else {res.setHeader('Content-Type','text/html');res.end(html);}}catch(e){res.statusCode=500;res.end(e.message);}});
await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(3941,'127.0.0.1',resolve);});
let browser;
async function wait(fn,label,ms=10000){const end=Date.now()+ms;while(Date.now()<end){if(await fn())return;await delay(20);}throw Error(`Timed out: ${label}`);}
async function started(p,t){await wait(()=>p.evaluate(id=>qa.events.some(e=>e.payload.kind==='task_trial_started'&&e.payload.data.trial_id===id),t.id),t.id);}
async function launch(mode='',order='A'){
  const ctx=await browser.newContext({viewport:{width:1280,height:900}}),p=await ctx.newPage();p.on('pageerror',e=>errors.push(e.message));
  await p.goto(`http://127.0.0.1:3941/?mode=${mode}&order=${order}`);return {ctx,p};
}
try{
  browser=await chromium.launch({channel:'chrome',headless:true});
  for(const order of continuation?[]:quick?['A']:['A','B']){
    const {ctx,p}=await launch(order==='B'?'lost-ack':'',order);await p.getByRole('button',{name:'Begin this block',exact:true}).waitFor();
    if(order==='A')for(const width of [1280,390]){
      await p.setViewportSize({width,height:900});const violations=(await new AxeBuilder({page:p}).withTags(['wcag2a','wcag2aa','wcag21aa','wcag22aa']).analyze()).violations;
      const overflow=await p.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);scans.push({width,violations,overflow});
      check(`Instruction accessibility ${width}px`,!violations.length&&!overflow);await p.screenshot({path:path.join(folder,`instructions-${width}.png`),fullPage:true});
    }
    await p.setViewportSize({width:1280,height:900});let count=0;
    for(const t of compiled[order].timeline){
      if(t.type==='task_instructions'){await p.getByRole('button',{name:'Begin this block',exact:true}).click();continue;}
      await started(p,t);count++;
      if(count===1){await p.screenshot({path:path.join(folder,`${order}-trial.png`)});await p.keyboard.press(t.correct_code==='KeyE'?'KeyI':'KeyE');}
      else if(count!==3)await p.keyboard.press(t.correct_code);
      await wait(()=>p.evaluate(id=>qa.events.some(e=>e.payload.kind==='task_trial_finished'&&e.payload.data.trial_id===id),t.id),`finished ${t.id}`);
      if(count%24===0)console.log(`${order}: ${count}/192 actual trials`);
      if(quick&&count===3){await p.evaluate(()=>controller.abort());break;}
    }
    await wait(()=>p.evaluate(()=>qa.result!==null||qa.error!==null),'renderer terminal',15000);
    const retained=await p.evaluate(()=>qa);assert.equal(retained.error,null);
    journals[order]=retained;const finished=retained.events.filter(e=>e.payload.kind==='task_trial_finished');
    check(`${order}: first physical wrong key stays incorrect`,finished[0].payload.data.correct===false&&finished[0].payload.data.keys.filter(k=>k.accepted).length===1);
    check(`${order}: actual omission retains feedback and blank without invented response`,finished[2].payload.data.outcome==='omission'&&finished[2].payload.data.response_ms===null&&finished[2].payload.data.feedback_end_ms-finished[2].payload.data.feedback_start_ms>=500);
    if(!quick)check(`${order}: all192 actual renderer trials complete without shortening`,retained.result.outcome==='completed'&&finished.length===192&&retained.events.filter(e=>e.payload.kind==='task_instructions').length===4);
    if(order==='B')check('Caller pending transport acknowledgment does not restart or duplicate renderer trials',retained.transport_pending&&new Set(finished.map(e=>e.payload.data.trial_id)).size===192);
    await ctx.close();
  }
  for(const mode of ['refresh','reload','checkpoint-failure','journal-failure','held-focus']){
    const {ctx,p}=await launch(mode);const t=compiled.A.timeline[1];
    if(mode==='refresh'){
      await wait(()=>p.evaluate(()=>qa.error!==null),'refresh refusal');const q=await p.evaluate(()=>qa);
      check('Received task checkpoint refuses restart before any invented event',q.error.includes('cannot restart')&&q.events.length===0);
    }else{
      await p.getByRole('button',{name:'Begin this block',exact:true}).waitFor();
      if(mode==='held-focus')await p.keyboard.down(t.correct_code);
      await p.getByRole('button',{name:'Begin this block',exact:true}).click();
      if(mode==='reload'){
        await started(p,t);await p.reload();await wait(()=>p.evaluate(()=>qa.error!==null),'actual reload refusal');
        const q=await p.evaluate(()=>qa);journals[mode]=q;
        check('Actual page reload retains caller evidence and refuses new timed events',q.error.includes('cannot restart')&&q.events.length===0&&
          q.prior_events.some(e=>e.payload.kind==='task_trial_started')&&q.prior_events.filter(e=>e.payload.kind==='task_trial_finished').every(e=>e.payload.data.outcome==='interrupted'&&e.payload.data.blank_end_ms===null));
      }else if(mode==='held-focus'){
        await started(p,t);await p.keyboard.down(t.correct_code);await p.keyboard.down('Shift');await p.keyboard.up(t.correct_code);await p.keyboard.up('Shift');await p.keyboard.press(t.correct_code);
        await wait(()=>p.evaluate(()=>qa.events.some(e=>e.payload.kind==='task_trial_finished')),'held-key finish');
        const second=compiled.A.timeline[2];await started(p,second);
        await p.evaluate(()=>{const f=document.createElement('iframe');f.id='focus-away';f.title='Original QA focus destination';f.srcdoc='<input aria-label="Other frame input">';document.body.append(f);});
        await p.frameLocator('#focus-away').getByLabel('Other frame input').focus();
        await wait(()=>p.evaluate(()=>qa.result!==null),'focus terminal');const q=await p.evaluate(()=>qa);journals[mode]=q;
        check('Actual held key is ignored until release and new physical press',q.events.find(e=>e.payload.kind==='task_trial_started').payload.data.held_codes.includes(t.correct_code)&&
          q.events.find(e=>e.payload.kind==='task_trial_finished').payload.data.keys.some(k=>k.ignored_reason==='key_repeat'||k.ignored_reason==='key_held_from_previous_phase'));
        check('Actual Shift-plus-keyup releases the held key for the next unmodified response',q.events.find(e=>e.payload.kind==='task_trial_finished').payload.data.keys.some(k=>k.type==='up'&&k.modifiers)&&
          q.events.find(e=>e.payload.kind==='task_trial_finished').payload.data.correct===true);
        check('Actual browser focus transfer interrupts and retains partial next trial',q.focus_events.some(e=>e.trusted)&&q.result.outcome==='interrupted'&&q.events.some(e=>e.payload.kind==='task_interrupted')&&q.events.filter(e=>e.payload.kind==='task_trial_finished').at(-1).payload.data.outcome==='interrupted');
      }else{
        await wait(()=>p.evaluate(()=>qa.error!==null),mode);const q=await p.evaluate(()=>qa);journals[mode]=q;
        check(`${mode}: failed durable caller never creates completed task`,q.error.includes('journal unavailable')&&q.result===null&&!q.events.some(e=>e.payload.kind==='task_trial_finished'));
      }
    }
    await ctx.close();
  }
  check('No uncaught browser exceptions',errors.length===0);
  await fs.writeFile(path.join(folder,'browser-journals.json'),JSON.stringify(journals,null,2));
  await fs.writeFile(path.join(folder,'results.json'),JSON.stringify({passed:true,scope:quick?'partial_component_debug':'full192_renderer_component_both_orders',continued_from:continuation,source:sourceReceipt.source,checks,scans,errors,
    session_consent_service_scoring_qualification:false,transport_note:'Pending-ack probe exercises renderer/caller separation only; actual existing service exact-retry integration remains required.'},null,2));
  console.log(JSON.stringify({passed:true,checks:checks.length,folder}));
}catch(e){await fs.writeFile(path.join(folder,'failure.json'),JSON.stringify({error:e.stack,checks,scans,errors,journals},null,2));throw e;}
finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
