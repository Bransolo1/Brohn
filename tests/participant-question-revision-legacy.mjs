// Existing legacy typed questionnaire journey against a separate actual service.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import {spawn} from 'node:child_process';
import {expect} from '@playwright/test';
const repo=path.resolve(import.meta.dirname,'..'),work=path.resolve(repo,'../../work');
const folder=await fs.mkdtemp(path.join(work,'test-runs/brohn-question-revision-delivery-legacy-'));
const rscript=process.env.BROHN_RSCRIPT||path.join(work,'native-r/bin/x64/Rscript.exe');
const port=await new Promise(resolve=>{const server=net.createServer();server.listen(0,'127.0.0.1',()=>{const port=server.address().port;server.close(()=>resolve(port));});});
const env={...process.env,R_LIBS_USER:path.join(work,'r-library-brohn-restore'),R_USER:work,LC_ALL:'C',LANG:'C',
  BROHN_TEST_OUTPUT:path.join(folder,'evidence'),BROHN_TEST_WORKSPACE:path.join(folder,'workspace'),BROHN_PARTICIPANT_URL:`http://127.0.0.1:${port}`,BROHN_RSCRIPT:rscript,BROHN_TEST_NO_WORKER:'1'};
let log='';const service=spawn(rscript,['--vanilla','tests/fixtures/participant-question-revision.R','serve','--folder',folder,'--root',env.BROHN_TEST_WORKSPACE,'--port',String(port)],{cwd:repo,env,windowsHide:true,stdio:['ignore','pipe','pipe']});
service.stdout.on('data',x=>log+=x);service.stderr.on('data',x=>log+=x);
try {
  await expect.poll(async()=>{if(service.exitCode!==null)throw new Error(log);try{return(await fetch(`${env.BROHN_PARTICIPANT_URL}/api/health`)).ok;}catch{return false;}},{timeout:30000}).toBe(true);
  const test=spawn(process.execPath,['tests/participant-logic.mjs'],{cwd:repo,env,windowsHide:true,stdio:'inherit'});
  assert.equal(await new Promise(resolve=>test.on('exit',resolve)),0,'Existing typed-logic browser journey');
  console.log(JSON.stringify({scope:'legacy_typed_branching_after_revision_sync_change',folder}));
}finally{
  if(service.exitCode===null){await fs.writeFile(path.join(folder,'stop.request'),'Stop the owned legacy regression service.');await expect.poll(()=>service.exitCode!==null,{timeout:15000}).toBe(true);}
  await fs.writeFile(path.join(folder,'server.log'),log);assert.equal(service.exitCode,0,log);
}
