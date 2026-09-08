// Browser wire fixtures use deliberately short synthetic mini-tasks. Full named
// profile counts and scientific scoring are tested in tests/platform-methods.R.
import assert from "node:assert/strict";
import http from "node:http";
import fs from "node:fs/promises";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {chromium} from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"../..");
const source=await fs.readFile(path.join(root,"www/participant/tasks.js"));
const server=http.createServer((request,response)=>{
  if(request.url==="/tasks.js"){response.writeHead(200,{"Content-Type":"application/javascript"});response.end(source);}
  else{response.writeHead(200,{"Content-Type":"text/html"});response.end('<!doctype html><html lang="en"><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Brohn task wire fixture</title></head><body style="background:white;color:#111;font-family:Arial"><main id="task"></main><script src="/tasks.js"></script></body></html>');}
});
await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));
const browser=await chromium.launch({executablePath:"C:/Program Files/Google/Chrome/Application/chrome.exe",headless:true});
const context=await browser.newContext();const page=await context.newPage();const errors=[];page.on("pageerror",error=>errors.push(error.message));
const checks=[];const check=(name,fn)=>{fn();checks.push(name);};
const trial=(id,extra={})=>({id,type:"task_trial",task_id:"fixture",task_profile:"iat-gnb2003-d1/1.0",block_id:"block-1",block_index:1,trial_index:1,
  phase:"practice",mode:"iat",mapping:"A",scored:true,material:{id:"material-1",type:"text",content:"A safe synthetic exemplar"},correct_code:"KeyE",allowed_codes:["KeyE","KeyI"],left_label:"Synthetic A",right_label:"Synthetic B",
  forced_correction:true,foreperiod_ms:0,timeout_ms:3000,intertrial_ms:100,box_count:0,position:1,zoom_duration_ms:0,...extra});
const compiled=(profile,steps)=>({schema_version:"brohn-compiled-task/1.0",id:"fixture",profile,title:"Synthetic task wire fixture",origin:"synthetic",
  timeline:[{id:"instruction-1",type:"task_instructions",block_id:"block-1",text:"Use the shown keys for this synthetic check."},...steps]});
const launch=async task=>{
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  await page.evaluate(task=>{
    window.events=[];window.checkpoints=[];window.done=null;
    window.taskPromise=BrohnTasks.run({container:document.getElementById("task"),compiled:task,
      emit:async(type,payload)=>{await new Promise(resolve=>setTimeout(resolve,10));window.events.push({type,payload});},
      onCheckpoint:async value=>{window.checkpoints.push(value);}}).then(value=>{window.done=value;}).catch(error=>{window.done={error:error.message};});
  },task);
  await page.getByRole("button",{name:"Begin this block"}).waitFor();
};
const waitOnset=async count=>page.waitForFunction(count=>window.events.filter(event=>event.type==="task_trial_started").length>=count,count);
try{
  await launch(compiled("iat-gnb2003-d1/1.0",[trial("trial-1"),trial("trial-2",{correct_code:"KeyI"})]));
  const axe=await new AxeBuilder({page}).withTags(["wcag2a","wcag2aa","wcag21aa"]).analyze();
  check("Task instruction screen passes automated accessibility",()=>assert.deepEqual(axe.violations,[]));
  await page.getByRole("button",{name:"Begin this block"}).click();await waitOnset(1);
  await page.waitForTimeout(80);await page.keyboard.press("i");
  await page.getByText("Incorrect. Press the other key to continue.").waitFor();
  await page.waitForTimeout(120);await page.keyboard.press("e");
  await waitOnset(2);await page.keyboard.press("i");
  await page.waitForFunction(()=>window.done!==null);
  const result=await page.evaluate(()=>({done:window.done,events:window.events,checkpoints:window.checkpoints}));
  check("Forced correction retains first error and final-correct latency",()=>{
    assert.equal(result.done.outcome,"completed");const response=result.done.responses[0];
    assert.equal(response.first_correct,false);assert.equal(response.response_code,"KeyI");assert.equal(response.final_code,"KeyE");
    assert.ok(response.final_correct_ms-response.first_response_ms>=100);assert.equal(response.keypresses.length,2);
  });
  check("Durable onset precedes response and every timed trial has a checkpoint",()=>{
    assert.deepEqual(result.events.map(event=>event.type),["task_instructions","task_trial_started","task_trial_finished","task_trial_started","task_trial_finished"]);
    assert.equal(result.checkpoints.filter(value=>!value.resumable).length,2);
    assert.ok(result.events.filter(event=>event.type==="task_trial_started").every(event=>event.payload.stimulus_rect.width>0));
  });
  await launch(compiled("rt-deary-liewald-simple/1.0",[trial("simple-1",{mode:"simple_rt",material:null,allowed_codes:["KeyB"],correct_code:"KeyB",forced_correction:false,foreperiod_ms:500,box_count:1})]));
  await page.getByRole("button",{name:"Begin this block"}).click();
  await page.keyboard.down("b");await page.keyboard.up("b");await waitOnset(1);await page.keyboard.press("b");
  await page.waitForFunction(()=>window.done!==null);
  const simple=await page.evaluate(()=>({done:window.done,events:window.events}));
  check("Anticipatory key cannot become the target response",()=>{
    const response=simple.done.responses[0];assert.equal(response.anticipatory_count,1);assert.equal(response.first_correct,true);
    assert.equal(response.keypresses[0].rt_ms,null);assert.equal(response.keypresses[0].accepted,false);
    assert.ok(response.observed_foreperiod_ms>=500);assert.ok(simple.events.find(event=>event.type==="task_trial_started").payload.stimulus_rect.width>0);
  });
  await launch(compiled("aat-keyboard-cue-balanced/1.0",[trial("aat-1",{mode:"aat",allowed_codes:["ArrowUp","ArrowDown"],correct_code:"ArrowDown",forced_correction:false,cue:"landscape",action:"approach",zoom_duration_ms:150})]));
  await page.getByRole("button",{name:"Begin this block"}).click();await waitOnset(1);await page.keyboard.press("ArrowDown");
  await page.waitForFunction(()=>window.done!==null);
  const aat=await page.evaluate(()=>window.done);
  check("Keyboard approach cue has observed zoom feedback without movement-time claims",()=>{
    assert.equal(aat.outcome,"completed");assert.equal(aat.responses[0].response_code,"ArrowDown");assert.ok(aat.responses[0].zoom_feedback_observed_ms>=120);
  });
  await launch(compiled("iat-gnb2003-d1/1.0",[trial("blur-1")]));
  await page.getByRole("button",{name:"Begin this block"}).click();await waitOnset(1);
  await page.evaluate(()=>window.dispatchEvent(new Event("blur")));await page.waitForFunction(()=>window.done!==null);
  const interrupted=await page.evaluate(()=>window.done);
  check("Focus-loss path records interruption instead of replay",()=>{
    assert.equal(interrupted.outcome,"interrupted");assert.equal(interrupted.responses[0].outcome,"interrupted");assert.equal(interrupted.responses[0].final_correct_ms,null);
  });
  check("No uncaught task browser errors",()=>assert.deepEqual(errors,[]));
  console.log(JSON.stringify({status:"passed",checks:checks.length,names:checks},null,2));
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
