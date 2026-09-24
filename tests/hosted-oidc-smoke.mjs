// Diagnostic upstream proof of actual established OIDC/edge configuration.
// This intentionally does not qualify the Brohn application or research path.
import assert from 'node:assert/strict';import fs from 'node:fs/promises';import path from 'node:path';import http from 'node:http';
import {chromium,expect} from '@playwright/test';import {makeFixture,services,sha} from './fixtures/hosted-oidc/services.mjs';
const folder=path.resolve(process.argv[2]);assert.ok(path.basename(folder).startsWith('brohn-hosted-browser-'));
const f=await makeFixture(folder),s=services(f),checks=[];
const diagnostic=http.createServer((req,res)=>{res.setHeader('Content-Type','application/json');res.end(JSON.stringify({subject:req.headers['x-forwarded-user'],groups:req.headers['x-forwarded-groups'],edge:req.headers['x-brohn-edge']===f.secret.edge,proto:req.headers['x-forwarded-proto'],host:req.headers.host}));});
await new Promise(resolve=>diagnostic.listen(3914,'127.0.0.1',resolve));
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({ignoreHTTPSErrors:true}),page=await context.newPage();
const login=async(p,user)=>{await p.goto('https://localhost:3911/');await p.getByLabel('Username or email',{exact:true}).fill(user);await p.getByLabel('Password',{exact:true}).fill(f.secret.password);await p.getByRole('button',{name:'Sign In',exact:true}).click();};
try{
 await s.startIdentity();await s.startEdge();await s.wait(async()=>{try{return(await context.request.get('https://localhost:3911/',{maxRedirects:0})).status()===302;}catch{return false;}});
 const spoof=await context.request.get('https://localhost:3911/session/forged/download/report',{maxRedirects:0,headers:{'X-Forwarded-User':'11111111-1111-4111-8111-111111111111','X-Forwarded-Groups':'researchers','X-Brohn-Edge':'forged'}});assert.equal(spoof.status(),302);checks.push('Anonymous spoofed identity cannot access researcher downloads');
 await login(page,'researcher');await expect(page).toHaveURL('https://localhost:3911/');const actual=JSON.parse(await page.locator('body').innerText());assert.deepEqual(actual,{subject:'11111111-1111-4111-8111-111111111111',groups:'researchers',edge:true,proto:'https',host:'localhost:3911'});checks.push('Actual Keycloak OIDC sign-in forwards verified subject/group through Caddy and preserves internal proof');
 const other=await browser.newContext({ignoreHTTPSErrors:true}),op=await other.newPage();await login(op,'outside');await expect(op.locator('body')).toContainText('403');checks.push('Actual authenticated non-member is refused');await other.close();
 await fs.writeFile(path.join(folder,'oidc-smoke-results.json'),JSON.stringify({passed:true,checks,tooling_lock_sha256:f.tooling.lock_sha256,limits:['Diagnostic upstream only; Brohn connected application proof remains separate.','Local fixture uses an untrusted local TLS CA in the test browser and loopback development IdP; no production authentication deployment.']},null,2));
 console.log(JSON.stringify({passed:true,checks:checks.length,folder}));
}catch(error){await page.screenshot({path:path.join(folder,'oidc-smoke-failure.png')}).catch(()=>{});await fs.writeFile(path.join(folder,'oidc-smoke-failure.json'),JSON.stringify({error:error.stack,checks,text:await page.locator('body').innerText().catch(()=>''),logs:Object.fromEntries(Object.entries(s.logs).map(([k,v])=>[k,Object.values(f.secret).reduce((s,x)=>s.replaceAll(x,'[redacted]'),v)]))},null,2));throw error;
}finally{await browser.close();await new Promise(resolve=>diagnostic.close(resolve));await s.stop();}
