import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import {spawn} from 'node:child_process';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const [rscript,sourceArg,outArg,dependencyArg]=process.argv.slice(2);
if(!rscript||!sourceArg||!outArg)throw Error('Usage: node tests/http-routes.mjs <actual-Rscript> <source-root> <fresh-evidence-dir> [dependency-root]');
const root=path.resolve(sourceArg),out=path.resolve(outArg);await fs.mkdir(out);
const require=createRequire(path.join(path.resolve(dependencyArg||root),'package.json'));
const {chromium}=require('@playwright/test');
const socket=net.createServer();await new Promise((r,j)=>{socket.once('error',j);socket.listen(0,'127.0.0.1',r);});const port=socket.address().port;await new Promise(r=>socket.close(r));
const child=spawn(path.resolve(rscript),[fileURLToPath(new URL('./http-routes.R',import.meta.url)),root,out,String(port)],{windowsHide:true,env:process.env});
let log='',browser;const checks=[];child.stdout.on('data',d=>log+=d);child.stderr.on('data',d=>log+=d);
const check=(label,value)=>{assert(value,label);checks.push(label);};
async function boundary(url){
 const u=new URL(url),chunks=[];let error=null;
 await new Promise(resolve=>{let sent=false;const s=net.connect({host:'127.0.0.1',port},()=>s.write(`HEAD ${u.pathname+u.search} HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nAccept-Encoding: gzip\r\nConnection: keep-alive\r\n\r\n`));
  s.setTimeout(5000,()=>{error='timeout';s.destroy();});s.on('data',d=>{chunks.push(d);if(!sent&&Buffer.concat(chunks).includes('\r\n\r\n')){sent=true;setImmediate(()=>s.write(`GET ${u.pathname+u.search} HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nAccept-Encoding: gzip\r\nConnection: close\r\n\r\n`));}});s.on('error',e=>error=e.message);s.on('close',resolve);});
 const bytes=Buffer.concat(chunks),end=bytes.indexOf('\r\n\r\n');return {error,clean:bytes.subarray(end+4,end+12).toString('latin1')==='HTTP/1.1',bytes};
}
try{
 for(let i=0;i<200&&!log.includes('Listening on');i++){if(child.exitCode!==null)throw Error(log);await new Promise(r=>setTimeout(r,100));}
 if(!log.includes('Listening on'))throw Error('Fixture did not start: '+log);
 const fixture=JSON.parse(await fs.readFile(path.join(out,'fixture.json'),'utf8'));
 check('Exactly19 source callback sites extracted with unique bound source hashes',Object.keys(fixture.sites).length===19&&Object.values(fixture.sites).every(s=>/^[a-f0-9]{64}$/.test(s.source_sha256)&&/^[a-f0-9]{64}$/.test(s.callback_sha256)));
 check('All24 declared saved-content variants present',Object.keys(fixture.routes).length===24);
 browser=await chromium.launch({channel:'chrome',headless:true});const page=await browser.newPage();await page.goto(`http://127.0.0.1:${port}`);await page.locator('#fixture-control').waitFor();
 const request=page.request,urls={};for(const key of Object.keys(fixture.routes))urls[key]=new URL(await page.locator('#'+key).getAttribute('href'),page.url()).href;
 const control=new URL(await page.locator('#fixture-control').getAttribute('href'),page.url()).href;
 const command=async(action,site)=>{const u=new URL(control);u.searchParams.set('action',action);if(site)u.searchParams.set('site',site);const r=await request.get(u.href);assert.equal(r.status(),200);return r.json();};
 for(const [key,route] of Object.entries(fixture.routes)){
  const expected=await fs.readFile(path.join(out,route.expected_file));
  const get=await request.get(urls[key],{headers:{'Accept-Encoding':'gzip'}});
  check(key+' current GET200 preserves exact bytes',get.status()===200&&(await get.body()).equals(expected));
  const head=await request.head(urls[key],{headers:{'Accept-Encoding':'gzip'}});
  check(key+' current HEAD200 empty with exact decimal length',head.status()===200&&(await head.body()).length===0&&head.headers()['content-length']===String(expected.length));
  check(key+' current identity and original content-type retained',head.headers()['content-encoding']==='identity'&&head.headers()['content-type']===get.headers()['content-type']);
  const raw=await boundary(urls[key]);await fs.writeFile(path.join(out,key+'-current.bin'),raw.bytes);check(key+' current persistent HEAD-to-GET boundary clean',!raw.error&&raw.clean);
  const bad=new URL(urls[key]);bad.searchParams.set(route.query,'unauthorized-token');
  const badGet=await request.get(bad.href),badHead=await request.head(bad.href);
  check(key+' unauthorized token keeps404 readable GET and empty HEAD',badGet.status()===404&&(await badGet.body()).length>0&&badHead.status()===404&&(await badHead.body()).length===0&&badHead.headers()['content-length']===String((await badGet.body()).length));
  const state=await command('revoke',key),before=state.states[key].authority_calls;
  const goneGet=await request.get(urls[key]),goneHead=await request.head(urls[key]);
  check(key+' revoked current authority keeps404 readable GET and empty HEAD',goneGet.status()===404&&(await goneGet.body()).length>0&&goneHead.status()===404&&(await goneHead.body()).length===0&&goneHead.headers()['content-length']===String((await goneGet.body()).length));
  const after=await command('inspect');check(key+' each refused request actually calls its current authority dependency',after.states[key].authority_calls>=before+2);
  const denied=await boundary(urls[key]);await fs.writeFile(path.join(out,key+'-revoked.bin'),denied.bytes);check(key+' refused persistent HEAD-to-GET boundary clean',!denied.error&&denied.clean);
 }
 const before=await command('inspect');await fs.writeFile(path.join(out,'callback-states.json'),JSON.stringify(before,null,2));
 await command('hosted-revoke');
 const anyUrl=Object.values(urls)[0],forbiddenGet=await request.get(anyUrl),forbiddenHead=await request.head(anyUrl);
 check('Actual hosted guard returns403 GET and empty HEAD before cached callback',forbiddenGet.status()===403&&(await forbiddenGet.body()).toString().includes('Researcher access ended')&&forbiddenHead.status()===403&&(await forbiddenHead.body()).length===0);
 const forbidden=await boundary(anyUrl);await fs.writeFile(path.join(out,'hosted-refusal.bin'),forbidden.bytes);check('Hosted403 persistent HEAD-to-GET boundary clean',!forbidden.error&&forbidden.clean);
 const deniedCounts=JSON.parse(await fs.readFile(path.join(out,'hosted-refusal-counters.json'),'utf8'));check('Hosted403 actually prevents every registered callback from executing',Object.keys(before.states).every(k=>before.states[k].requests===deniedCounts.requests[k]));
 const result={passed:true,checks,site_count:19,variant_count:24,fixture,scope:'Actual unchanged callback ASTs and hosted guard with synthetic closure dependencies on real Shiny/httpuv/Chrome. Native and backend authority calls are explicitly spied, not independently qualified. No scientific reruns.'};
 await fs.writeFile(path.join(out,'results.json'),JSON.stringify(result,null,2));console.log(JSON.stringify({passed:true,checks:checks.length,sites:19,variants:24}));
}catch(e){await fs.writeFile(path.join(out,'failure.json'),JSON.stringify({error:String(e),checks},null,2));throw e;}
finally{if(browser)await browser.close();child.kill();await new Promise(r=>child.exitCode!==null?r():child.once('exit',r));await fs.writeFile(path.join(out,'server.log'),log);}
