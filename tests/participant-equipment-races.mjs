// Real participant UI + original fake camera/audio + real R receiver. No physical-device claim.
import assert from 'node:assert/strict';import fs from 'node:fs/promises';import path from 'node:path';import net from 'node:net';
import {spawn,spawnSync} from 'node:child_process';import {createHash} from 'node:crypto';import {chromium,expect} from '@playwright/test';
const root=path.resolve(import.meta.dirname,'..'),work=path.resolve(root,'../../work'),parent=path.resolve(process.env.BROHN_TEST_OUTPUT||path.join(work,'equipment-race-evidence'));
await fs.mkdir(parent,{recursive:true});const folder=await fs.mkdtemp(path.join(parent,'brohn-participant-equipment-')),workspace=path.join(folder,'workspace');
const rscript=path.join(work,'native-r/bin/Rscript.exe'),env={...process.env,R_LIBS_USER:path.join(work,'r-library-brohn-restore'),R_USER:work,LC_ALL:'C',BROHN_PUBLICATION_PYTHON:path.join(work,'tooling/methods-venv/Scripts/python.exe')};
const port=await new Promise(resolve=>{const s=net.createServer();s.listen(0,'127.0.0.1',()=>{const p=s.address().port;s.close(()=>resolve(p));});}),base=`http://127.0.0.1:${port}`;
const rArgs=mode=>['--vanilla','tests/fixtures/participant-equipment.R',mode,'--folder',folder,'--root',workspace,'--port',String(port)];
const runR=mode=>{const r=spawnSync(rscript,rArgs(mode),{cwd:root,env,windowsHide:true,encoding:'utf8',timeout:300000});assert.equal(r.status,0,r.stderr||r.stdout);};
const movie=path.join(folder,'original-static-pattern.y4m'),chunks=[Buffer.from('YUV4MPEG2 W320 H240 F15:1 Ip A1:1 C420jpeg\n')];
for(let n=0;n<60;n++)chunks.push(Buffer.from('FRAME\n'),Buffer.alloc(320*240,90),Buffer.alloc(320*240/4,110),Buffer.alloc(320*240/4,140));await fs.writeFile(movie,Buffer.concat(chunks));
const wav=Buffer.alloc(44+48000*2*2);wav.write('RIFF',0);wav.writeUInt32LE(wav.length-8,4);wav.write('WAVEfmt ',8);wav.writeUInt32LE(16,16);wav.writeUInt16LE(1,20);wav.writeUInt16LE(1,22);wav.writeUInt32LE(48000,24);wav.writeUInt32LE(96000,28);wav.writeUInt16LE(2,32);wav.writeUInt16LE(16,34);wav.write('data',36);wav.writeUInt32LE(wav.length-44,40);for(let i=0;i<96000;i++)wav.writeInt16LE(Math.round(8000*Math.sin(2*Math.PI*440*i/48000)),44+2*i);const sound=path.join(folder,'original-440hz.wav');await fs.writeFile(sound,wav);
runR('prepare');const fixture=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8')),checks=[],errors=[],scans=[];let server,browser,log='',active;
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log(`PASS ${label}`);};
const inspect=async()=>{runR('inspect');return JSON.parse(await fs.readFile(path.join(folder,'inspection.json'),'utf8'));};
async function start(name){const c=await browser.newContext({viewport:{width:1280,height:900},permissions:['camera','microphone']}),p=await c.newPage();active=p;p.on('pageerror',e=>errors.push(e.message));p.on('dialog',d=>d.accept());
 await p.addInitScript(()=>{window.permissionCalls=[];const gum=navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);navigator.mediaDevices.getUserMedia=async options=>{permissionCalls.push(options);const stream=await gum(options);window.originalTracks=stream.getTracks();return stream;};window.recorderCount=0;const M=window.MediaRecorder;window.MediaRecorder=new Proxy(M,{construct(t,args){recorderCount++;return new t(...args);}});});
 const calls={events:[],chunks:[],starts:[]};p.on('request',r=>{if(r.method()!=='POST')return;if(r.url().includes('/api/events/'))calls.events.push(...r.postDataJSON().events);if(r.url().includes('/api/camera_chunk/'))calls.chunks.push(r.postDataJSON());if(r.url().includes('/api/camera_start/'))calls.starts.push(r.postDataJSON());});
 await p.goto(`${base}/participant/?token=${fixture[name].token}`);await p.getByLabel('Participant alias (required)',{exact:true}).fill(`ORIGINAL-${name}-${Date.now()}`);await p.getByLabel('I have read the study information and agree to take part.',{exact:true}).check();const response=p.waitForResponse(r=>r.url().includes('/api/start/')&&r.request().method()==='POST');await p.getByRole('button',{name:'Start study',exact:true}).click();const run=await(await response).json();return{c,p,calls,run};}
async function complete(v){await v.p.getByRole('button',{name:'Begin',exact:true}).click();await v.p.getByRole('heading',{name:'Original final equipment rating',exact:true}).waitFor();await v.p.getByRole('radio',{name:'4',exact:true}).check();await v.p.getByRole('button',{name:'Continue',exact:true}).click();await v.p.getByRole('heading',{name:'Thank you. Your responses are saved.',exact:true}).waitFor({timeout:30000});}

const reviewedFiles=['R/platform-participant-equipment.R','R/platform-delivery.R','R/platform-core.R','R/platform-run-evidence.R','www/participant/runner.js','www/participant/camera.js','www/participant/equipment.js','www/participant/audio-worklet.js'];
const sourceHashes=Object.fromEntries(await Promise.all(reviewedFiles.map(async f=>[f,createHash('sha256').update(await fs.readFile(path.join(root,f))).digest('hex')])));
await fs.writeFile(path.join(folder,'source-hashes-at-start.json'),JSON.stringify(sourceHashes,null,2));const findings=[];
try{
 server=spawn(rscript,rArgs('serve'),{cwd:root,env,windowsHide:true,stdio:['ignore','pipe','pipe']});for(const s of[server.stdout,server.stderr])s.on('data',d=>log+=d);
 await expect.poll(async()=>{if(server.exitCode!==null)throw new Error(log);try{return(await fetch(`${base}/api/health`)).ok;}catch{return false;}},{timeout:30000}).toBe(true);
 browser=await chromium.launch({channel:'chrome',headless:true,args:['--use-fake-device-for-media-stream',`--use-file-for-fake-video-capture=${movie}`,`--use-file-for-fake-audio-capture=${sound}`]});
 const delayed=await start('camera');
 await delayed.p.getByLabel('I agree to the camera recording described above.',{exact:true}).check();await delayed.p.getByRole('button',{name:'Enable camera',exact:true}).click();await expect(delayed.p.getByRole('region',{name:'Camera and microphone observations'})).toContainText('Current frames observed.');
 let held=false;
 await delayed.p.route('**/api/events/**',async route=>{
   const data=route.request().postDataJSON();
   if(!held && data.events.some(e=>e.type==='equipment_event'&&e.payload.kind==='camera')){
      held=true;const response=await route.fetch();await delayed.p.evaluate(()=>{for(const t of originalTracks)t.enabled=false;});
      await new Promise(resolve=>setTimeout(resolve,2500));await route.fulfill({response});
   }else await route.continue();
 });
 await delayed.p.getByRole('button',{name:'Start recording and continue',exact:true}).click();
 await expect.poll(()=>held).toBe(true);await new Promise(resolve=>setTimeout(resolve,4000));
 const first={probe:'disabled track during delayed equipment receipt',entered:await delayed.p.getByRole('button',{name:'Begin',exact:true}).isVisible(),text:await delayed.p.locator('body').innerText(),events:delayed.calls.events,tracks:await delayed.p.evaluate(()=>originalTracks.map(t=>({kind:t.kind,enabled:t.enabled,readyState:t.readyState}))),run_id:delayed.run.run_id};
 findings.push(first);await delayed.p.screenshot({path:path.join(folder,'delayed-receipt.png'),fullPage:true});
 console.log(JSON.stringify({probe:first.probe,entered:first.entered,tracks:first.tracks}));
 check(!first.entered,'Delayed equipment receipt cannot enter with disabled camera');
 await delayed.p.evaluate(()=>{for(const t of originalTracks)t.enabled=true;});
 await delayed.p.getByRole('button',{name:'Retry recording check',exact:true}).click();await delayed.p.getByRole('button',{name:'Begin',exact:true}).waitFor();
 check(await delayed.p.evaluate(()=>recorderCount)===1,'Retry current-input check keeps the same recorder');
 check(await delayed.p.evaluate(()=>permissionCalls.every(call=>call.audio===false)),'Camera-only check does not request microphone permission');await complete(delayed);await delayed.c.close();
 const reload=await start('camera');
 await reload.p.getByLabel('I agree to the camera recording described above.',{exact:true}).check();await reload.p.getByRole('button',{name:'Enable camera',exact:true}).click();await expect(reload.p.getByRole('region',{name:'Camera and microphone observations'})).toContainText('Current frames observed.');
 let blocked=false;const rejected=[];
 await reload.p.route('**/api/events/**',async route=>{
   if(route.request().postDataJSON().events.some(e=>e.type==='equipment_event'&&e.payload.kind==='camera')){blocked=true;await route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({error:{message:'Peer probe unreceived event'}})});}else await route.continue();
 });
 await reload.p.getByRole('button',{name:'Start recording and continue',exact:true}).click();
 await expect.poll(()=>blocked).toBe(true);await reload.p.getByRole('button',{name:'Retry recording check',exact:true}).waitFor();
 await reload.p.unroute('**/api/events/**');reload.p.on('response',async response=>{if(response.url().includes('/api/events/')&&response.status()>=400)rejected.push({status:response.status(),body:await response.text()});});
 await reload.p.reload();await new Promise(resolve=>setTimeout(resolve,7000));
 const second={original_event:reload.calls.events.find(e=>e.type==='equipment_event'&&e.payload.kind==='camera'),probe:'reload with unreceived camera equipment event',rejected,text:await reload.p.locator('body').innerText(),run_id:reload.run.run_id};findings.push(second);
 await reload.p.screenshot({path:path.join(folder,'reload-pending.png'),fullPage:true});console.log(JSON.stringify(second));
 check(!second.rejected.length,'Reload accepts historical pending check after interrupted capture receipt');
 check(second.text.includes('The study was interrupted.')&&second.text.includes('Final receipt confirmed'),'Reload reaches actual interrupted final receipt');
 await reload.c.close();
 const inspection=await inspect();const recovered=inspection.runs.find(r=>r.run.id===reload.run.run_id);const original=reload.calls.events.find(e=>e.type==='equipment_event'&&e.payload.kind==='camera');
 check(recovered.run.transfer_status==='saved'&&recovered.run.completion_status==='interrupted','Receiver retains reload as saved interrupted session');
 check(recovered.equipment.checks.length===1&&(assert.deepEqual(recovered.equipment.checks[0],original),true),'Recovery retains exact original equipment event without regenerated observation');
 check(!errors.length,'No browser runtime errors during either recovery');
 check((await Promise.all(Object.entries(sourceHashes).map(async([f,hash])=>hash===createHash('sha256').update(await fs.readFile(path.join(root,f))).digest('hex')))).every(Boolean),'Sources unchanged during narrow browser acceptance');await fs.writeFile(path.join(folder,'peer-findings.json'),JSON.stringify({folder,origin:'original_fake_camera_software_observations',sourceHashes,findings,errors,checks},null,2));console.log(JSON.stringify({folder}));
}catch(e){await active?.screenshot({path:path.join(folder,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(folder,'failure.json'),JSON.stringify({error:e.stack,findings,errors,checks,sourceHashes},null,2));throw e;}finally{await browser?.close();if(server&&server.exitCode===null){await fs.writeFile(path.join(folder,'stop.request'),'Stop owned independent peer equipment service.');await expect.poll(()=>server.exitCode!==null,{timeout:15000}).toBe(true);}await fs.writeFile(path.join(folder,'server.log'),log);}
