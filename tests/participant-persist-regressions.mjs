// Reuse the existing typed-branch and camera cancellation/decline journeys with
// test-only isolation settings. No Shiny process or scientific worker is run.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import {createHash} from 'node:crypto';
import {spawn,spawnSync} from 'node:child_process';
import {expect} from '@playwright/test';
const root=path.resolve(import.meta.dirname,'..'),work=path.resolve(root,'../../work');
const folder=await fs.mkdtemp(path.join(work,'test-runs/brohn-maxdiff-delivery-regressions-')),workspace=path.join(folder,'workspace');
const rscript=process.env.BROHN_RSCRIPT||path.join(work,'native-r/bin/x64/Rscript.exe');
const env={...process.env,R_LIBS_USER:path.join(work,'r-library-brohn-restore'),BROHN_RSCRIPT:rscript,R_USER:work,LC_ALL:'C',LANG:'C',BROHN_TEST_WORKSPACE:workspace,BROHN_TEST_NO_WORKER:'1'};
const port=await new Promise(resolve=>{const server=net.createServer();server.listen(0,'127.0.0.1',()=>{const p=server.address().port;server.close(()=>resolve(p));});});
env.BROHN_PARTICIPANT_URL=`http://127.0.0.1:${port}`;
const width=320,height=240,chunks=[Buffer.from(`YUV4MPEG2 W${width} H${height} F15:1 Ip A1:1 C420jpeg\n`)];
for(let frame=0;frame<30;frame++){chunks.push(Buffer.from('FRAME\n'),Buffer.alloc(width*height,32+frame*4),Buffer.alloc(width*height/4,100),Buffer.alloc(width*height/4,150));}
await fs.writeFile(path.join(folder,'original-persistence-camera-320x240.y4m'),Buffer.concat(chunks));
const prepared=spawnSync(rscript,['--vanilla','tests/fixtures/participant-maxdiff-delivery.R','prepare_regressions','--folder',folder,'--root',workspace,'--port',String(port)],{cwd:root,env,windowsHide:true,encoding:'utf8',timeout:30000});assert.equal(prepared.status,0,prepared.stderr||prepared.stdout);
let service,log='';const results=[];
async function journey(file,extra={}){
  const output=path.join(folder,path.basename(file,'.mjs'));await fs.mkdir(output,{recursive:true});let text='';
  const child=spawn(process.execPath,[file],{cwd:root,env:{...env,BROHN_TEST_OUTPUT:output,...extra},windowsHide:true,stdio:['ignore','pipe','pipe']});
  for(const stream of[child.stdout,child.stderr])stream.on('data',data=>{text+=data;process.stdout.write(data);});
  const code=await new Promise((resolve,reject)=>{child.on('error',reject);child.on('exit',resolve);});await fs.writeFile(path.join(output,'harness.log'),text);assert.equal(code,0,text);
  const result=JSON.parse(await fs.readFile(path.join(output,'results.json'),'utf8'));assert.equal(result.mode,'isolated_real_receiver_no_worker');results.push({test:file,result});
}
try{
  service=spawn(rscript,['--vanilla','tests/fixtures/participant-maxdiff-delivery.R','serve','--folder',folder,'--root',workspace,'--port',String(port)],{cwd:root,env,windowsHide:true,stdio:['ignore','pipe','pipe']});
  service.stdout.on('data',data=>log+=data);service.stderr.on('data',data=>log+=data);
  await expect.poll(async()=>{if(service.exitCode!==null)throw new Error(log);try{return(await fetch(`${env.BROHN_PARTICIPANT_URL}/api/health`)).ok;}catch{return false;}},{timeout:30000,intervals:[100,250]}).toBe(true);
  await journey('tests/participant-logic.mjs');
  await journey('tests/participant-camera-races.mjs',{BROHN_CAMERA_REGRESSION_CONFIG:path.join(folder,'camera-regression.json')});
  const runnerHash=createHash('sha256').update(await fs.readFile('www/participant/runner.js')).digest('hex');
  await fs.writeFile(path.join(folder,'results.json'),JSON.stringify({scope:'existing_actual_browser_journeys_with_test_only_isolation',mode:'isolated_real_receiver_no_worker',runner_sha256:runnerHash,results,
    limitations:['Camera input is an original generated fake-device stream; recording is never started.','Completed runs are verified with expected jobs queued, not with a scientific report.','Main workspace and services are not used or changed.']},null,2));
  console.log(JSON.stringify({tests:results.map(r=>({name:r.test,checks:r.result.checks.length})),folder}));
}finally{
  if(service&&service.exitCode===null){await fs.writeFile(path.join(folder,'stop.request'),'Stop the owned participant persistence regression service.');await expect.poll(()=>service.exitCode!==null,{timeout:15000,intervals:[100,250]}).toBe(true);}
  await fs.writeFile(path.join(folder,'server.log'),log);if(service)assert.equal(service.exitCode,0,log);
}
