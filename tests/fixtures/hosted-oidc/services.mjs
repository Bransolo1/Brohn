// Actual local OIDC tooling; all data/users/secrets synthetic and isolated.
// This module starts only the declared fixture-owned services and cleans them up.
import fs from 'node:fs/promises';import path from 'node:path';import {spawn,spawnSync} from 'node:child_process';
import {randomBytes,createHash} from 'node:crypto';
export const sha=x=>createHash('sha256').update(x).digest('hex');
export async function makeFixture(folder){
 await fs.mkdir(folder,{recursive:false});
 const tooling=JSON.parse(await fs.readFile(path.resolve('../../work/tooling/hosted/tooling-receipt.json'),'utf8'));
 const vendor=Object.fromEntries(tooling.vendors.map(v=>[v.id,v]));
 for(const v of tooling.vendors){if(sha(await fs.readFile(v.executable_path))!==v.executable_sha256)throw Error('Vendor executable identity changed: '+v.id);}
 const secret={edge:randomBytes(32).toString('hex'),client:randomBytes(32).toString('hex'),password:randomBytes(24).toString('hex')};
 await fs.writeFile(path.join(folder,'edge.secret'),secret.edge);await fs.writeFile(path.join(folder,'client.secret'),secret.client);await fs.writeFile(path.join(folder,'cookie.secret'),randomBytes(32));
 await fs.writeFile(path.join(folder,'revocations.json'),JSON.stringify({schema:'brohn-hosted-revocations/1.0',subjects:[],not_before:0}));
 // Use a fresh copy: Keycloak augmentation/database/realm import never modifies
 // the pinned vendor extraction or another fixture's identity/session state.
 const kc=path.join(folder,'keycloak');await fs.cp(path.join(vendor.keycloak.directory,'keycloak-26.7.4'),kc,{recursive:true});
 await fs.mkdir(path.join(kc,'data','import'),{recursive:true});
 const realm={realm:'brohn',enabled:true,sslRequired:'none',registrationAllowed:false,resetPasswordAllowed:false,rememberMe:false,
  groups:[{name:'researchers'},{name:'outside'}],
  users:[{id:'11111111-1111-4111-8111-111111111111',username:'researcher',email:'researcher@brohn.invalid',emailVerified:true,enabled:true,firstName:'Synthetic',lastName:'Researcher',groups:['/researchers'],credentials:[{type:'password',value:secret.password,temporary:false}]},
   {id:'22222222-2222-4222-8222-222222222222',username:'outside',email:'outside@brohn.invalid',emailVerified:true,enabled:true,firstName:'Synthetic',lastName:'Outside',groups:['/outside'],credentials:[{type:'password',value:secret.password,temporary:false}]}],
  clients:[{clientId:'brohn-fixture',enabled:true,protocol:'openid-connect',publicClient:false,secret:secret.client,standardFlowEnabled:true,directAccessGrantsEnabled:false,
    redirectUris:['https://localhost:3911/oauth2/callback'],webOrigins:['https://localhost:3911'],attributes:{'pkce.code.challenge.method':'S256'},
    protocolMappers:[{name:'groups',protocol:'openid-connect',protocolMapper:'oidc-group-membership-mapper',consentRequired:false,config:{'full.path':'false','id.token.claim':'true','access.token.claim':'true','userinfo.token.claim':'true','claim.name':'groups'}}]}]};
 await fs.writeFile(path.join(kc,'data','import','brohn-realm.json'),JSON.stringify(realm));
 const r=path.resolve('../../work/native-r/bin/Rscript.exe'),env={...process.env,R_LIBS_USER:path.resolve('../../work/r-library-brohn-restore'),R_USER:path.resolve('../../work'),LC_ALL:'C',
 BROHN_PUBLICATION_PYTHON:path.resolve('../../work/tooling/methods-venv/Scripts/python.exe'),BROHN_PUBLICATION_NATIVE_MANIFEST:path.resolve('../../work/tooling/brohn-native/publication-guard.json')};
 const helper=mode=>{const result=spawnSync(r,['--vanilla','tests/fixtures/hosted-oidc/workspace.R',mode,folder],{env,windowsHide:true,encoding:'utf8',maxBuffer:8*1024**2});if(result.status!==0)throw Error(result.stderr||result.stdout);};
 helper('setup');
 return {folder,kc,vendor,tooling,secret,r,env,helper};
}
export async function resumeFixture(folder,evidence){
 const tooling=JSON.parse(await fs.readFile(path.resolve('../../work/tooling/hosted/tooling-receipt.json'),'utf8'));
 const vendor=Object.fromEntries(tooling.vendors.map(v=>[v.id,v]));
 for(const v of tooling.vendors)if(sha(await fs.readFile(v.executable_path))!==v.executable_sha256)throw Error('Vendor executable identity changed: '+v.id);
 const kc=path.join(folder,'keycloak'),realm=JSON.parse(await fs.readFile(path.join(kc,'data','import','brohn-realm.json'),'utf8'));
 const secret={edge:await fs.readFile(path.join(folder,'edge.secret'),'utf8'),client:await fs.readFile(path.join(folder,'client.secret'),'utf8'),password:realm.users.find(u=>u.username==='researcher').credentials[0].value};
 const r=path.resolve('../../work/native-r/bin/Rscript.exe'),env={...process.env,R_LIBS_USER:path.resolve('../../work/r-library-brohn-restore'),R_USER:path.resolve('../../work'),LC_ALL:'C',BROHN_PUBLICATION_PYTHON:path.resolve('../../work/tooling/methods-venv/Scripts/python.exe'),BROHN_PUBLICATION_NATIVE_MANIFEST:path.resolve('../../work/tooling/brohn-native/publication-guard.json')};
 const helper=mode=>{const result=spawnSync(r,['--vanilla','tests/fixtures/hosted-oidc/workspace.R',mode,folder],{env,windowsHide:true,encoding:'utf8',maxBuffer:8*1024**2});if(result.status!==0)throw Error(result.stderr||result.stdout);};
 return {folder,evidence,kc,vendor,tooling,secret,r,env,helper};
}
export function services(fixture){
 const {folder,kc,vendor,secret,r,env}=fixture,owned={},logs={};
 const run=(name,exe,args,extra={})=>{logs[name]=(logs[name]||'');const p=spawn(exe,args,{env:{...env,...extra},windowsHide:true,stdio:['ignore','pipe','pipe']});owned[name]=p;for(const s of[p.stdout,p.stderr])s.on('data',b=>logs[name]+=b);return p;};
 const wait=async(test,timeout=60000)=>{const end=Date.now()+timeout;let error;while(Date.now()<end){try{if(await test())return;}catch(e){error=e;}await new Promise(r=>setTimeout(r,200));}throw error||Error('Hosted service readiness timeout');};
 const waitHttp=async(name,url)=>wait(async()=>{if(owned[name]?.exitCode!==null)throw Error(name+' exited: '+logs[name]);return(await fetch(url)).ok;},90000);
 async function startIdentity(){
  const args=['-Xms64m','-Xmx512m','-Dfile.encoding=UTF-8','-Duser.language=en','-Duser.country=US',
   '--add-opens=java.base/java.util=ALL-UNNAMED','--add-opens=java.base/java.util.concurrent=ALL-UNNAMED','--add-opens=java.base/java.security=ALL-UNNAMED','--add-opens=java.base/java.lang=ALL-UNNAMED','--enable-native-access=ALL-UNNAMED',
   '-Djava.util.concurrent.ForkJoinPool.common.threadFactory=io.quarkus.bootstrap.forkjoin.QuarkusForkJoinWorkerThreadFactory','-Dkc.home.dir='+kc,'-Djboss.server.config.dir='+path.join(kc,'conf'),'-Dkeycloak.theme.dir='+path.join(kc,'themes'),
   '-cp',path.join(kc,'lib','quarkus-run.jar'),'io.quarkus.bootstrap.runner.QuarkusEntryPoint','start-dev','--http-host=127.0.0.1','--http-port=3913','--hostname=http://127.0.0.1:3913','--import-realm','--health-enabled=true','--http-management-host=127.0.0.1','--http-management-port=3917'];
  let p=run('keycloak',vendor.temurin.executable_path,args);
  await wait(async()=>{if(p.exitCode===10){p=run('keycloak',vendor.temurin.executable_path,['-Dkc.config.built=true',...args]);return false;}if(p.exitCode!==null)throw Error('Keycloak: '+logs.keycloak);try{return(await fetch('http://127.0.0.1:3913/realms/brohn/.well-known/openid-configuration')).ok;}catch{return false;}},180000);
 }
 async function startBrohn(){for(const name of['researcher','participant']){await fs.rm(path.join(folder,'stop.'+name),{force:true});run(name,r,['--vanilla','tests/fixtures/hosted-oidc/workspace.R',name,folder]);}await waitHttp('researcher','http://127.0.0.1:3914/');await waitHttp('participant','http://127.0.0.1:3915/api/health');}
 async function startEdge(){
  const config=spawnSync(vendor['oauth2-proxy'].executable_path,['--config='+path.join(folder,'oauth2-proxy.cfg'),'--config-test'],{encoding:'utf8',windowsHide:true});if(config.status!==0)throw Error('OAuth configuration: '+config.stderr+config.stdout);
  const ce={BROHN_EDGE_SECRET:secret.edge,XDG_DATA_HOME:path.join(folder,'caddy-data'),XDG_CONFIG_HOME:path.join(folder,'caddy-config')};
  const valid=spawnSync(vendor.caddy.executable_path,['validate','--config',path.join(folder,'Caddyfile')],{env:{...env,...ce},encoding:'utf8',windowsHide:true});if(valid.status!==0)throw Error('Caddy configuration: '+valid.stderr+valid.stdout);
  run('oauth',vendor['oauth2-proxy'].executable_path,['--config='+path.join(folder,'oauth2-proxy.cfg')]);await waitHttp('oauth','http://127.0.0.1:3916/ping');
  run('caddy',vendor.caddy.executable_path,['run','--config',path.join(folder,'Caddyfile')],ce);
 }
 async function stop(names=Object.keys(owned)){
  for(const name of names){const p=owned[name];if(!p||p.exitCode!==null||p.signalCode!==null)continue;if(['researcher','participant'].includes(name)){await fs.writeFile(path.join(folder,'stop.'+name),'Stop owned hosted fixture service');await wait(()=>p.exitCode!==null||p.signalCode!==null,15000);}else{p.kill();await wait(()=>p.exitCode!==null||p.signalCode!==null,15000);}}
  for(const[name,text]of Object.entries(logs)){let safe=text;for(const value of Object.values(secret))safe=safe.replaceAll(value,'[redacted fixture secret]');await fs.writeFile(path.join(fixture.evidence||folder,name+'.log'),safe);}
 }
 return {owned,logs,wait,startIdentity,startBrohn,startEdge,stop};
}
