// Launch the actual integrated R entry point from a newly checked installation.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { chromium, expect as baseExpect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const expect=baseExpect.configure({timeout:60000});
const configuration=path.resolve(process.argv[2]),folder=path.resolve(process.argv[3]);
assert.ok(path.basename(folder).startsWith('brohn-installed-runtime-'));
await fs.mkdir(folder,{recursive:false});
const config=JSON.parse(await fs.readFile(configuration,'utf8'));
assert.equal(config.schema,'brohn-local-installation/1.0');
await assert.rejects(fs.access(path.join(config.workspace,'catalog.sqlite')),'Use a newly configured test workspace only');
const stopFile=path.join(folder,'stop.request'),wrapper=path.join(folder,'launch.R');
await fs.writeFile(wrapper,`poll_stop <- function() { if(file.exists(Sys.getenv('BROHN_QA_STOP_FILE'))) shiny::stopApp() else later::later(poll_stop,.1) }
later::later(poll_stop,.1)
source('scripts/run-brohn.R',encoding='UTF-8')
state<-getOption('brohn.services')
cat('qa_clean_exit:',isTRUE(state$stopped)&&all(vapply(state$owned,function(p)!p$is_alive(),logical(1))),'\\n')
`);
const env={...process.env,R_LIBS_USER:config.r_library,LC_ALL:'C',BROHN_PUBLICATION_PYTHON:config.publication_python,BROHN_PUBLICATION_NATIVE_MANIFEST:config.publication_manifest,BROHN_PYTHON:config.portability_python,
  BROHN_WORKSPACE:config.workspace,RESEARCH_PLATFORM_PORT:String(config.ports.researcher),BROHN_PARTICIPANT_PORT:String(config.ports.participant),BROHN_QA_STOP_FILE:stopFile};
for(const name of ['METHODS','ACQUISITION','VISION_AUDIO','SEGMENTATION'])delete env['BROHN_PYTHON_'+name];
for(const [name,value] of Object.entries(config.scientific))env['BROHN_PYTHON_'+name.toUpperCase().replaceAll('-','_')]=value;
const url=`http://127.0.0.1:${config.ports.researcher}/`,checks=[],errors=[],scans=[];
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log('PASS',label);};
const browser=await chromium.launch({channel:'chrome',headless:true});
const context=await browser.newContext({viewport:{width:1440,height:1080}});
const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
let child=null,logs='',cycle=0;
async function start(){await fs.rm(stopFile,{force:true});cycle++;logs='';child=spawn(config.rscript,['--vanilla',wrapper],{env,windowsHide:true});child.stdout.on('data',x=>logs+=String(x));child.stderr.on('data',x=>logs+=String(x));
  await expect.poll(async()=>{if(child.exitCode!==null)throw Error(logs);try{return(await fetch(url)).status===200;}catch{return false;}}).toBe(true);}
async function stop(){if(!child)return;await fs.writeFile(stopFile,'stop');if(child.exitCode===null)await Promise.race([new Promise(r=>child.once('exit',r)),new Promise(r=>setTimeout(r,30000))]);
  await fs.writeFile(path.join(folder,`services-${cycle}.log`),logs);
  if(child.exitCode===null){spawnSync('taskkill',['/PID',String(child.pid),'/T','/F'],{windowsHide:true});throw Error('Owned launcher did not stop normally');}
  check(child.exitCode===0&&logs.includes('qa_clean_exit: TRUE'),`Integrated launcher stopped all owned services normally (${cycle})`);child=null;}
async function idle(){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy'));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);}
async function scan(name){await idle();const violations=(await new AxeBuilder({page}).analyze()).violations;await fs.writeFile(path.join(folder,name+'-axe.json'),JSON.stringify(violations,null,2));await page.screenshot({path:path.join(folder,name+'.png')});scans.push({name,violations:violations.length});check(!violations.length,name+' accessible automated scan');}
try{
  await start();await page.goto(url);await page.getByRole('button',{name:'Start my study',exact:true}).waitFor();await scan('fresh-install-home');
  check((await fetch(`http://127.0.0.1:${config.ports.participant}/api/health`)).status===200,'Separate participant service answers using the new installation');
  await page.getByRole('button',{name:'Start my study',exact:true}).click();await page.getByLabel('Study name',{exact:true}).fill('Installed runtime persistence example');await page.locator('input[name="new_template"][value="comparison"]').check();await page.getByRole('button',{name:'Create study',exact:true}).click();await idle();
  await page.getByRole('button',{name:'Studies',exact:true}).click();await expect(page.getByText('Installed runtime persistence example',{exact:true})).toBeVisible();check(true,'Researcher creates and reopens an actual controlled-study draft');
  const serviceLogs=await fs.readdir(path.join(config.workspace,'logs'));const workerLogs=await Promise.all(serviceLogs.filter(x=>/^worker-.*stdout[.]txt$/.test(x)).map(x=>fs.readFile(path.join(config.workspace,'logs',x),'utf8')));
  check(workerLogs.some(x=>x.includes('Brohn analysis worker ready')),'Integrated launcher starts the real supervised analysis service');
  await stop();await start();await page.goto(url);await page.getByRole('button',{name:'Studies',exact:true}).click();await expect(page.getByText('Installed runtime persistence example',{exact:true})).toBeVisible();check(true,'Saved study survives a complete service restart');
  await page.setViewportSize({width:390,height:844});await scan('installed-library-390');
  check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Installed library fits the narrow viewport');
  check(!errors.length,'No browser exceptions using the separate installed runtime');await stop();
  await fs.writeFile(path.join(folder,'results.json'),JSON.stringify({checks,scans,errors,configuration,scope:'Fresh separate R library on this existing Windows host; actual integrated launcher, researcher authoring, participant health, analysis service, persistence and owned shutdown. Not a clean-machine or scientific qualification.'},null,2));
}catch(e){await fs.writeFile(path.join(folder,'failure.json'),JSON.stringify({error:e.stack,checks,errors,logs},null,2));await page.screenshot({path:path.join(folder,'failure.png')});throw e;}
finally{if(child)await stop();await browser.close();}
