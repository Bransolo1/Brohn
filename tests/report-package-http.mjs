import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import {spawn} from 'node:child_process';
import {createRequire} from 'node:module';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
const [rscript,sourceArg,outputArg,dependencyArg]=process.argv.slice(2);
if(!rscript||!sourceArg||!outputArg)throw Error('Usage: node report-package-http.mjs <Rscript-executable> <source-root> <fresh-evidence-dir> [dependency-root]');
const root=path.resolve(sourceArg),out=path.resolve(outputArg);
let server=path.join(root,'R/platform-report-package-server.R');
try{await fs.access(server);}catch{server=path.join(root,'platform-report-package-server.R');}
const helper=fileURLToPath(new URL('./report-package-http.R',import.meta.url));
await fs.mkdir(out);
const require=createRequire(path.join(path.resolve(dependencyArg||root),'package.json'));
const {chromium}=require('@playwright/test');
const probe=net.createServer();await new Promise((resolve,reject)=>{probe.once('error',reject);probe.listen(0,'127.0.0.1',resolve);});
const port=probe.address().port;await new Promise(resolve=>probe.close(resolve));
const child=spawn(path.resolve(rscript),[helper,out,String(port),server],{windowsHide:true,env:process.env});
let log='';child.stdout.on('data',d=>log+=d);child.stderr.on('data',d=>log+=d);
let browser;const checks=[],old=[];
const check=(label,ok)=>{assert(ok,label);checks.push(label);};
async function rawPipeline(url){
 const u=new URL(url),chunks=[];let failure=null;
 await new Promise(resolve=>{
  let secondSent=false;
  const socket=net.connect({host:'127.0.0.1',port},()=>socket.write(`HEAD ${u.pathname+u.search} HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nAccept-Encoding: gzip\r\nConnection: keep-alive\r\n\r\n`));
  socket.setTimeout(5000,()=>{failure='timeout';socket.destroy();});
  socket.on('data',d=>{
   chunks.push(d);
   if(!secondSent&&Buffer.concat(chunks).includes('\r\n\r\n')){
    secondSent=true;
    setImmediate(()=>socket.write(`GET ${u.pathname+u.search} HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nAccept-Encoding: gzip\r\nConnection: close\r\n\r\n`));
   }
  });
  socket.on('error',e=>failure=e.message);socket.on('close',resolve);
 });
 const data=Buffer.concat(chunks),end=data.indexOf('\r\n\r\n');
 return {failure,header:data.subarray(0,end).toString('latin1'),nextStartsHTTP:data.subarray(end+4,end+12).toString('latin1')==='HTTP/1.1',afterHeaderHex:data.subarray(end+4,end+40).toString('hex'),raw:data};
}
try{
 for(let i=0;i<100&&!log.includes('Listening on');i++){if(child.exitCode!==null)throw Error(log);await new Promise(r=>setTimeout(r,100));}
 browser=await chromium.launch({channel:'chrome',headless:true});const page=await browser.newPage();await page.goto(`http://127.0.0.1:${port}`);await page.locator('#new-error').waitFor();
 const urls={};for(const name of ['legacy-html','legacy-error','new-html','new-zip','new-error','new-html-100000'])urls[name]=new URL(await page.locator('#'+name).getAttribute('href'),page.url()).href;
 const request=page.request;
 for(const [name,file] of [['new-html','source.html'],['new-zip','source.zip'],['new-html-100000','source-100000.html']]){
  const expected=await fs.readFile(path.join(out,file));
  const head=await request.head(urls[name],{headers:{'Accept-Encoding':'gzip'}});
  check(name+' HEAD200 is empty with exact representation length',head.status()===200&&(await head.body()).length===0&&Number(head.headers()['content-length'])===expected.length);
  check(name+' HEAD retains identity/no-store/nosniff headers',head.headers()['content-encoding']==='identity'&&head.headers()['cache-control']==='no-store'&&head.headers()['x-content-type-options']==='nosniff');
  const get=await request.get(urls[name],{headers:{'Accept-Encoding':'gzip'}});check(name+' GET remains exact bytes',get.status()===200&&(await get.body()).equals(expected));
 }
 const denied=await request.head(urls['new-error'],{headers:{'Accept-Encoding':'gzip'}});check('Refused HEAD404 has zero body',denied.status()===404&&(await denied.body()).length===0);
 const deniedGet=await request.get(urls['new-error'],{headers:{'Accept-Encoding':'gzip'}});check('Refused GET retains its readable error body',deniedGet.status()===404&&(await deniedGet.body()).toString().includes('Reopen'));
 for(const name of ['new-html','new-zip','new-html-100000','new-error']){
  const x=await rawPipeline(urls[name]);await fs.writeFile(path.join(out,name+'-pipeline.bin'),x.raw);delete x.raw;
  check(name+' HEAD-to-GET wire boundary contains no extra body or compression bytes',!x.failure&&x.nextStartsHTTP);
 }
 for(const name of ['legacy-html','legacy-error']){const x=await rawPipeline(urls[name]);await fs.writeFile(path.join(out,name+'-pipeline.bin'),x.raw);delete x.raw;old.push({name,...x});}
 await fs.writeFile(path.join(out,'results.json'),JSON.stringify({passed:true,checks,legacy:old,server_sha256:createHash('sha256').update(await fs.readFile(server)).digest('hex'),scope:'Actual installed Shiny/httpuv and Chrome/Playwright plus raw persistent HTTP transport using synthetic artifacts and the exact response helper. Full controller authority is separately spy-tested; no native store/worker or research data.'},null,2));
 console.log(JSON.stringify({passed:true,checks:checks.length,legacy:old}));
}catch(error){await fs.writeFile(path.join(out,'failure.json'),JSON.stringify({error:String(error),checks,legacy:old},null,2));throw error;}
finally{if(browser)await browser.close();child.kill();await new Promise(resolve=>{if(child.exitCode!==null)resolve();else child.once('exit',resolve);});await fs.writeFile(path.join(out,'server.log'),log);}
