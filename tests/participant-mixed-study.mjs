// One complete mixed release, using actual browser inputs, receiver and workers.
// The generated camera frames and sample answers are software fixtures only.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn, spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chromium, expect as baseExpect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const expect=baseExpect.configure({timeout:30000});
const folder=path.resolve(process.argv[2]);
assert.ok(path.basename(folder).startsWith('brohn-mixed-study-'));
await fs.mkdir(folder,{recursive:true});
const root=process.cwd(),work=path.resolve('../../work'),r=path.join(work,'native-r/bin/Rscript.exe');
const env={...process.env,R_LIBS_USER:path.join(work,'r-library-brohn-restore'),LC_ALL:'C',
  BROHN_PUBLICATION_PYTHON:path.join(work,'tooling/methods-venv/Scripts/python.exe'),
  BROHN_PUBLICATION_NATIVE_MANIFEST:path.join(work,'tooling/brohn-native/publication-guard.json')};
const args=mode=>['--vanilla','tests/fixtures/participant-mixed-study.R',mode,folder];
const helper=mode=>{const out=spawnSync(r,args(mode),{env,windowsHide:true,encoding:'utf8',timeout:600000,maxBuffer:8*1024**2});assert.equal(out.status,0,out.stderr||out.stdout);};
helper('setup');
const config=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
const base=`http://127.0.0.1:${config.port}`;
const movie=path.join(folder,'original-flat-colour.y4m');
const frames=[Buffer.from('YUV4MPEG2 W320 H240 F15:1 Ip A1:1 C420jpeg\n')];
for(let i=0;i<45;i++)frames.push(Buffer.from('FRAME\n'),Buffer.alloc(320*240,80),Buffer.alloc(320*240/4,110),Buffer.alloc(320*240/4,145));
await fs.writeFile(movie,Buffer.concat(frames));
const files=['www/participant/runner.js','www/participant/camera.js','www/participant/equipment.js','www/participant/illustrations.js','www/participant/maxdiff.js'];
const hashes=async()=>Object.fromEntries(await Promise.all(files.map(async f=>[f,createHash('sha256').update(await fs.readFile(path.join(root,f))).digest('hex')])));
const before=await hashes(),checks=[],scans=[],errors=[],posts=[];
const check=(ok,name)=>{assert.ok(ok,name);checks.push(name);console.log('PASS',name);};
let server,browser,page,log='';
async function scan(name){const violations=(await new AxeBuilder({page}).analyze()).violations;
  const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);
  await page.screenshot({path:path.join(folder,`${name}.png`)});
  scans.push({name,violations:violations.length,overflow});check(!violations.length&&!overflow,`${name}: accessibility and reflow`);}
async function retained(){return page.evaluate(()=>new Promise((resolve,reject)=>{const open=indexedDB.open('brohn-participant',1);open.onerror=()=>reject(open.error);open.onsuccess=()=>{const db=open.result;
  const request=db.transaction('sessions').objectStore('sessions').getAll();request.onsuccess=()=>{resolve(request.result);db.close();};request.onerror=()=>{reject(request.error);db.close();};};}));}
async function waitEvent(predicate,description){await expect.poll(async()=>{const sessions=await retained();return sessions.some(s=>s.events.some(predicate));},{timeout:20000,message:description,intervals:[40,80,150]}).toBe(true);}
try {
  server=spawn(r,args('serve'),{env,windowsHide:true,stdio:['ignore','pipe','pipe']});
  for(const s of[server.stdout,server.stderr])s.on('data',x=>log+=x);
  await expect.poll(async()=>{if(server.exitCode!==null)throw Error(log);try{return(await fetch(`${base}/api/health`)).ok;}catch{return false;}},{timeout:30000}).toBe(true);
  browser=await chromium.launch({channel:'chrome',headless:true,args:['--use-fake-device-for-media-stream',`--use-file-for-fake-video-capture=${movie}`]});
  const context=await browser.newContext({viewport:{width:390,height:844},permissions:['camera']});page=await context.newPage();
  page.on('pageerror',e=>errors.push(e.message));page.on('request',request=>{if(request.method()==='POST'&&request.url().includes('/api/'))posts.push({url:request.url(),body:request.postDataJSON()});});
  await page.goto(`${base}/participant/?token=${config.release.token}`);
  await expect(page.getByRole('heading',{name:'Welcome to the original mixed study',exact:true})).toBeVisible();
  await expect(page.getByRole('img',{name:'Original shared welcome picture',exact:true})).toBeVisible();
  check(!posts.length,'Welcome and its exact image appear before allocating a session or recording');await scan('mixed-welcome-390');
  await page.getByRole('button',{name:'Continue to study information',exact:true}).click();
  await page.getByLabel('I have read the study information and agree to take part.',{exact:true}).check();
  await page.getByLabel('Participant alias (required)',{exact:true}).fill('original-mixed-01');
  const start=page.waitForResponse(x=>x.url().includes('/api/start/')&&x.request().method()==='POST');
  await page.getByRole('button',{name:'Start study',exact:true}).click();const run=await(await start).json();
  await expect(page.getByRole('heading',{name:'Check your task keys',exact:true})).toBeVisible();
  for(const code of run.protocol.equipment.required_codes)await page.keyboard.press(code);
  await page.getByRole('button',{name:'Activate practice control',exact:true}).press('Enter');
  await page.getByLabel('I agree to the camera recording described above.',{exact:true}).check();
  await page.getByRole('button',{name:'Enable camera',exact:true}).click();
  await expect(page.getByRole('region',{name:'Camera and microphone observations'})).toContainText('Current frames observed.');
  await scan('mixed-equipment-390');
  await page.getByRole('button',{name:'Start recording and continue',exact:true}).click();
  await page.getByRole('button',{name:'Begin',exact:true}).waitFor();
  const setup=(await retained()).find(s=>s.run_id===run.run_id);
  check(setup.events.filter(e=>e.type==='equipment_event').length===3,'Required keys, response-control practice and actual recording receipt precede the mixed protocol');
  await page.setViewportSize({width:1440,height:1080});
  let questionCount=0,trialCount=0,choiceCount=0;
  for(const step of run.protocol.timeline) {
    if(step.type==='instructions'){await page.getByRole('button',{name:'Begin',exact:true}).click();continue;}
    if(step.type==='question') {
      await waitEvent(e=>e.type==='step_started'&&e.step_id===step.id,`Question ${step.id} has an actual onset`);
      await expect(page.getByRole('heading',{name:step.question.prompt,exact:true})).toBeVisible();
      if(step.question.illustration)await expect(page.getByRole('img',{name:step.question.illustration.image_alt,exact:true})).toBeVisible();
      await page.getByRole('radio',{name:'4',exact:true}).check();await page.getByRole('button',{name:'Continue',exact:true}).click();questionCount++;continue;
    }
    if(step.type==='task') {
      for(const part of step.task.timeline) {
        if(part.type==='task_instructions'){await page.getByRole('button',{name:'Begin this block',exact:true}).click();continue;}
        await waitEvent(e=>e.type==='task_event'&&e.payload.kind==='task_trial_started'&&e.payload.data.trial_id===part.id,`Trial ${part.id} started`);
        await page.keyboard.press(part.correct_code);trialCount++;
      }
      continue;
    }
    if(step.type==='maxdiff') {
      await waitEvent(e=>e.type==='step_started'&&e.step_id===step.id,`Choice ${step.id} started`);
      const best=page.getByRole('group',{name:step.choice.best_label,exact:true}),worst=page.getByRole('group',{name:step.choice.worst_label,exact:true});
      await expect(best).toBeVisible();for(const item of step.choice.items)for(const group of[best,worst])await expect(group.getByRole('img',{name:item.illustration.image_alt,exact:true})).toBeVisible();
      if(!choiceCount){await page.setViewportSize({width:390,height:844});await scan('mixed-choice-390');await page.setViewportSize({width:1440,height:1080});}
      await best.locator(`input[value="${step.choice.item_order[0]}"]`).check();await worst.locator(`input[value="${step.choice.item_order[1]}"]`).check();
      await page.getByRole('button',{name:'Continue',exact:true}).click();choiceCount++;continue;
    }
    await waitEvent(e=>e.type==='step_finished'&&e.step_id===step.id,`Passive step ${step.id} finished`);
  }
  await expect(page.getByRole('heading',{name:'Thank you. Your responses are saved.',exact:true})).toBeVisible();
  await scan('mixed-complete-desktop');
  check(questionCount===4&&trialCount>0&&choiceCount===run.protocol.timeline.filter(s=>s.type==='maxdiff').length,'Every frozen question, passive exposure, timed trial and image choice completes in one session');
  check(posts.filter(p=>p.url.includes('/api/start/')).length===1,'Mixed equipment, materials and tasks preserve one allocated session');
  helper('analyse');const acceptance=JSON.parse(await fs.readFile(path.join(folder,'acceptance.json'),'utf8'));
  check(acceptance.events.filter(e=>e.type==='task_event'&&e.payload.kind==='task_trial_finished').length===trialCount,'Every mixed-session task trial retains its final timing evidence in the actual receiver');
  check(acceptance.passed&&acceptance.run.id===run.run_id,'Actual automatic session report and decoded camera artifact retain the same frozen mixed design and run');
  assert.deepEqual(await hashes(),before);check(!errors.length,'Participant sources stay unchanged and browser raises no exceptions');
  await fs.writeFile(path.join(folder,'browser-results.json'),JSON.stringify({checks,scans,errors,source_hashes:before,run_id:run.run_id,jobs:acceptance.jobs,interpretation:'One original software fixture. No physical camera, participant, motor timing or scientific outcome qualification.'},null,2));
  console.log(JSON.stringify({checks:checks.length,scans:scans.length,folder}));
} catch(error) {
  if(page&&!page.isClosed()){await page.screenshot({path:path.join(folder,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(folder,'failure-text.txt'),await page.locator('body').innerText()).catch(()=>{});}
  await fs.writeFile(path.join(folder,'failure.json'),JSON.stringify({error:error.stack,checks,scans,errors},null,2));throw error;
} finally {
  await browser?.close();
  if(server&&server.exitCode===null){await fs.writeFile(path.join(folder,'stop.request'),'Stop owned mixed-study fixture.');await expect.poll(()=>server.exitCode!==null,{timeout:20000}).toBe(true);}
  await fs.writeFile(path.join(folder,'server.log'),log);
}
