// Actual Chrome MediaRecorder/IndexedDB against a deliberately small transport stub.
// This checks the browser controller; R authorization/publication has separate tests.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {chromium} from '@playwright/test';
const output=path.resolve('../../work/test-runs/brohn-camera-controller-evidence');await fs.mkdir(output,{recursive:true});
const movie=path.join(output,'original-colour-pattern.y4m'),width=64,height=48,frames=[Buffer.from(`YUV4MPEG2 W${width} H${height} F15:1 Ip A1:1 C420jpeg\n`)];
for(let f=0;f<90;f++){const y=Buffer.alloc(width*height),u=Buffer.alloc(width*height/4,96+f%40),v=Buffer.alloc(width*height/4,160-f%40);for(let i=0;i<y.length;i++)y[i]=32+((i+f*7)%190);frames.push(Buffer.from('FRAME\n'),y,u,v);}await fs.writeFile(movie,Buffer.concat(frames));
const source=await fs.readFile('www/participant/camera.js'),received=new Map(),checks=[],errors=[];let simulateLostAck=true,duplicates=0;
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log(`PASS ${label}`);};
const server=http.createServer(async(req,res)=>{
 try{
  if(req.url==='/camera.js'){res.setHeader('Content-Type','application/javascript');res.end(source);return;}
  if(req.url==='/'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><html lang="en"><meta charset="utf-8"><title>Original camera controller fixture</title><script src="/camera.js"></script><body><h1>Camera controller QA</h1><video id="preview" muted playsinline></video></body></html>');return;}
  if(req.method!=='POST'){res.writeHead(204);res.end();return;}
  const data=[];for await(const chunk of req)data.push(chunk);const body=JSON.parse(Buffer.concat(data)),operation=req.url.split('/')[2];
  let result;
  if(operation==='camera_start'){
   const prior=received.get(body.capture_id);if(prior)assert.deepEqual(prior.start,body);else received.set(body.capture_id,{start:body,chunks:new Map(),finish:null});
   result={capture_id:body.capture_id,status:body.consented?'recording':'declined',next_sequence:1};
  }else if(operation==='camera_chunk'){
   const capture=received.get(body.capture_id);assert.ok(capture);const bytes=Buffer.from(body.data_base64,'base64');assert.ok(bytes.length<=2*1024*1024);assert.equal(createHash('sha256').update(bytes).digest('hex'),body.sha256);
   const old=capture.chunks.get(body.sequence);if(old){assert.deepEqual(old.body,body);duplicates++;}else{assert.equal(body.sequence,capture.chunks.size+1);capture.chunks.set(body.sequence,{body,bytes});}
   if(simulateLostAck){simulateLostAck=false;res.writeHead(503,{'Content-Type':'application/json'});res.end(JSON.stringify({error:{message:'Original deliberate lost-receipt fixture'}}));return;}
   result={acked_sequence:capture.chunks.size};
  }else if(operation==='camera_finish'){
   const capture=received.get(body.capture_id);assert.ok(capture);assert.equal(body.final_sequence,capture.chunks.size);assert.equal(body.total_bytes,[...capture.chunks.values()].reduce((n,c)=>n+c.bytes.length,0));
   if(capture.finish)assert.deepEqual(capture.finish,body);capture.finish=body;result={capture_id:body.capture_id,status:'assembly_queued'};
  }else throw new Error('Unexpected fixture route');
  res.setHeader('Content-Type','application/json');res.end(JSON.stringify(result));
 }catch(error){errors.push(error.message);res.writeHead(400,{'Content-Type':'application/json'});res.end(JSON.stringify({error:{message:error.message}}));}
});await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const url=`http://127.0.0.1:${server.address().port}`;
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--use-fake-device-for-media-stream','--use-fake-ui-for-media-stream',`--use-file-for-fake-video-capture=${movie}`]});
try{
 const context=await browser.newContext(),page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
 await page.goto(url);await page.evaluate(()=>{
  window.permissionCalls=0;const original=navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);navigator.mediaDevices.getUserMedia=(...args)=>{permissionCalls++;return original(...args);};
  window.makeController=runId=>new BrohnCamera({policy:{required:false,audio:false,width:64,height:48,frame_rate:15,max_duration_s:30,max_bytes:128*1024*1024},runId,
   instanceId:'original-controller-page',timeOrigin:performance.timeOrigin,getStep:()=>({id:'original-step',phase:'passive_viewing'}),onFailure:e=>{window.captureError=e.message;},
   api:async(path,body)=>{const response=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}),data=await response.json();if(!response.ok){const e=new Error(data.error.message);e.permanent=response.status<500;throw e;}return data;}});
 });
 await page.evaluate(async()=>{window.declined=makeController('original-decline');await declined.decline();});
 check(await page.evaluate(()=>permissionCalls===0),'Explicit decline never invokes camera permission');
 check([...received.values()].some(c=>c.start.consented===false&&c.chunks.size===0),'Decline has an explicit receipt and no recording chunks');
 await page.evaluate(async()=>{window.camera=makeController('original-recording');await camera.prepare(document.getElementById('preview'));await camera.start();});
 check(await page.evaluate(()=>permissionCalls===1&&camera.recorder.state==='recording'&&camera.settings.audio===false),'Explicit setup starts real Chrome MediaRecorder with audio disabled');
 await page.waitForFunction(()=>camera.segment.next_sequence>=3,{},{timeout:15000});
 await page.evaluate(async()=>{await camera.stop('completed');await camera.flush();await camera.flush();});
 const captured=[...received.values()].find(c=>c.start.consented&&c.finish?.outcome==='completed');
 check(!!captured&&captured.finish.container_complete&&captured.finish.final_sequence>=3,'Normal stop retains final recorder chunk before finishing transport');
 check(duplicates>=1,'Lost first receipt retries identical sequence and bytes without duplicating output');
 const values=[...captured.chunks.values()];check(values.every(c=>c.body.observation.callback_ms&&c.body.observation.frames.every(f=>f.step_id==='original-step'&&f.phase==='passive_viewing')),'Chunk observations preserve browser clock and explicit study-step context');
 check(await page.evaluate(()=>camera.stream===null&&camera.recorder.stream.getTracks().every(t=>t.readyState==='ended')),'Normal stop releases every live camera track');
 check(await page.evaluate(async()=>(await camera.transaction(['chunks'],'readonly',tx=>tx.objectStore('chunks').getAll())).length===0),'Acknowledged camera bytes are removed from local pending storage');
 const recorded=path.join(output,'actual-recording.webm');await fs.writeFile(recorded,Buffer.concat(values.map(c=>c.bytes)));
 const decode=spawnSync(path.resolve('../../work/tooling/vision-audio-venv/Scripts/python.exe'),['-c','import cv2,json,sys; c=cv2.VideoCapture(sys.argv[1]); n=0\nwhile True:\n ok,f=c.read()\n if not ok: break\n n+=1\nc.release(); print(json.dumps({"frames":n})); sys.exit(0 if n>0 else 2)',recorded],{encoding:'utf8',windowsHide:true});assert.equal(decode.status,0,decode.stderr);const decoded=JSON.parse(decode.stdout);
 check(decoded.frames>0,'Concatenated chunks from one completed recorder decode as an actual video');
 await page.evaluate(async()=>{await camera.purge();window.reloadCamera=makeController('original-reload');await reloadCamera.prepare(document.getElementById('preview'));await reloadCamera.start();});
 await page.waitForFunction(()=>reloadCamera.segment.next_sequence>=2,{},{timeout:15000});
 const priorId=await page.evaluate(()=>reloadCamera.segment.capture_id);await page.reload();
 const recovery=await page.evaluate(async()=>{
  const api=async(path,body)=>{const r=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}),d=await r.json();if(!r.ok)throw new Error(d.error.message);return d;};
  window.recovered=new BrohnCamera({policy:{},runId:'original-reload',api,instanceId:'new-original-page',timeOrigin:performance.timeOrigin});return recovered.recover();
 });
 check(recovery.interrupted===true&&received.get(priorId).finish.container_complete===false,'Reload preserves previous chunks and records an unobserved ending as incomplete');
 check(received.get(priorId).finish.clock.instance_id==='original-controller-page','Reload does not invent an ending timestamp in the old browser clock');
 check(errors.length===0,`No controller or transport invariant failures: ${errors.join('; ')}`);
 await fs.writeFile(path.join(output,'results.json'),JSON.stringify({scope:'actual_browser_controller_with_transport_stub',origin:'original_generated_y4m',checks,decoded_frames:decoded.frames,limitations:['R receiver authorization/publication is tested separately.','No physical camera, microphone or human participant was used.']},null,2));
 await context.close();console.log(JSON.stringify({checks:checks.length,output}));
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
