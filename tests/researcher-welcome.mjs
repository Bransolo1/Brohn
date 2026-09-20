// Actual researcher + participant services, original synthetic study and media.
import assert from 'node:assert/strict';import fs from 'node:fs/promises';import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';import {createHash} from 'node:crypto';
import {chromium,expect} from '@playwright/test';import AxeBuilder from '@axe-core/playwright';
assert.ok(process.argv[2]);const folder=path.resolve(process.argv[2]);assert.ok(path.basename(folder).startsWith('brohn-welcome-'));
await fs.mkdir(folder,{recursive:true});const output=path.join(folder,`browser-evidence-${Date.now()}`);await fs.mkdir(output);
const r=path.resolve('../../work/native-r/bin/Rscript.exe'),env={...process.env,R_LIBS_USER:path.resolve('../../work/r-library-brohn-restore'),R_USER:path.resolve('../../work'),LC_ALL:'C',
 BROHN_PUBLICATION_PYTHON:path.resolve('../../work/tooling/methods-venv/Scripts/python.exe'),BROHN_PUBLICATION_NATIVE_MANIFEST:path.resolve('../../work/tooling/brohn-native/publication-guard.json')};
const checks=[],scans=[],errors=[],logs={researcher:'',participant:''},processes={};
function helper(mode){const p=spawnSync(r,['--vanilla','tests/fixtures/researcher-welcome.R',mode,folder],{env,windowsHide:true,encoding:'utf8',maxBuffer:8*1024**2});assert.equal(p.status,0,p.stderr);}
helper('setup');const config=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
const snapshot=async()=>{helper('inspect');return JSON.parse(await fs.readFile(path.join(folder,'snapshot.json'),'utf8'));};
for(const mode of['researcher','participant']){
  const p=spawn(r,['--vanilla','tests/fixtures/researcher-welcome.R',mode,folder],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});processes[mode]=p;
  for(const s of[p.stdout,p.stderr])s.on('data',b=>logs[mode]+=b);
}
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage();
page.on('pageerror',e=>errors.push(e.message));
const button=name=>page.getByRole('button',{name,exact:true});const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log(`PASS ${label}`);};
const digest=buffer=>createHash('sha256').update(buffer).digest('hex');
async function idle(allowError=false){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&![...document.querySelectorAll('.recalculating')].some(e=>e.getClientRects().length));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);if(!allowError)await expect(page.locator('#platform_error [role="alert"]')).toHaveCount(0);}
async function stage(name){await button(name).click();await page.waitForFunction(s=>{const f=document.getElementById('study_form_identity');return f?.value.endsWith(`:${s}`)&&Shiny.shinyapp.$inputValues.study_form_identity===f.value;},name);await idle();}
async function scan(target,label,narrow=false,scope='body'){
  await target.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});
  const violations=(await new AxeBuilder({page:target}).analyze()).violations;
  const overflow=await target.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);
  const small=await target.locator(scope).locator('button:visible,input:not([type="checkbox"]):not([type="radio"]):not([type="file"]):visible,summary:visible').evaluateAll(es=>es.filter(e=>e.getBoundingClientRect().height<44).map(e=>e.id||e.textContent));
  await target.evaluate(()=>{document.activeElement?.blur();window.scrollTo({top:0,behavior:'instant'});});
  scans.push({label,violations:violations.length,overflow,small});await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(violations,null,2));
  await target.screenshot({path:path.join(output,`${label}.png`),fullPage:false});console.log(`SCAN ${label}: ${violations.length} axe, overflow=${overflow}, small=${small.length}`);
  await target.setViewportSize({width:1440,height:1080});
}
try{
  for(const mode of['researcher','participant'])await expect.poll(async()=>{if(processes[mode].exitCode!==null)throw Error(logs[mode]);try{return(await fetch(`http://127.0.0.1:${config[`${mode}_port`]}/${mode==='participant'?'api/health':''}`)).status===200;}catch{return false;}},{timeout:60000,intervals:[250,500,1000]}).toBe(true);
  await page.goto(`http://127.0.0.1:${config.researcher_port}/`);await button('Start my study').click();await page.getByLabel('Study name',{exact:true}).fill('Original welcome journey');await page.locator('input[name="new_template"][value="survey"]').check();await button('Create study').click();
  await expect(page.locator('#study_title')).toHaveValue('Original welcome journey');await idle();
  await page.locator('#welcome_enabled').check();await page.locator('#welcome_title').fill('Welcome to the original packaging study');
  const message='Compare an original fictional pack.\n<script>window.WELCOME_UNSAFE=true</script> is literal text.';
  await page.locator('#welcome_text').fill(message);await page.locator('#consent_text').fill('Original study information. Taking part is voluntary.');await page.locator('#study_instructions').fill('Original instructions after consent.');await page.locator('#debrief_text').fill('Original closing thanks and contact information.');
  await button('Add welcome image').click();const modal=page.getByRole('dialog');await modal.locator('input[type="file"]').setInputFiles(path.join(folder,'invalid.png'));await page.locator('#welcome_upload_alt').fill('Original fictional green packaging concept');await button('Attach image').click();
  await expect(modal.locator('[role="alert"]')).toContainText('PNG');
  await modal.locator('input[type="file"]').setInputFiles(path.join(folder,'original-welcome.png'));await button('Attach image').click();await expect(modal).toHaveCount(0);await idle();
  const authored=(await snapshot()).studies.find(s=>s.body.title==='Original welcome journey');assert.equal(authored.body.welcome.asset.hash,config.original_image_hash);
  check(true,'Welcome text and alt text are authored in Plan; invalid image bytes recover in place and exact original PNG is saved');
  await button('Preview saved welcome').click();const frame=page.frameLocator('iframe[title="Saved participant welcome preview"]');
  await expect(frame.getByRole('heading',{name:'Welcome to the original packaging study',exact:true})).toBeVisible();await expect(frame.locator('.welcome-text')).toHaveText(message);
  await expect(frame.getByRole('img',{name:'Original fictional green packaging concept'})).toBeVisible();
  await expect(frame.getByRole('button',{name:'Continue to study information',exact:true})).toBeEnabled();
  assert.equal(await frame.locator('body').evaluate(()=>window.WELCOME_UNSAFE),undefined);assert.equal((await snapshot()).runs.length,0);
  await scan(page,'researcher-welcome-preview-390',true,'.modal-content');
  await frame.getByRole('button',{name:'Continue to study information',exact:true}).click();await expect(frame.locator('body')).toContainText('Original study information. Taking part is voluntary.');await expect(frame.getByRole('button',{name:'Start study',exact:true})).toHaveCount(0);
  await button('Close welcome preview').click();await expect(page.locator('#welcome-preview-open')).toBeFocused();
  check(true,'Sandbox preview uses the participant renderer with exact literal source, saved image and consent information without a participant session');
  await stage('Questions');await page.locator('#question_type').selectOption('text');await button('Add question').click();await page.locator('#q_prompt_1').fill('What did you notice in the original pack?');await stage('Collect');
  await page.getByRole('combobox',{name:'Collection origin',exact:true}).fill('Example');await page.getByRole('combobox',{name:'Collection origin',exact:true}).press('Enter');await expect(page.locator('#release_origin')).toHaveValue('sample');
  await button('Release participant study').click();await page.getByRole('link',{name:'Open participant study',exact:true}).waitFor();await idle();
  const snap=await snapshot(),release=snap.releases.find(r=>r.study_id===authored.id);assert.ok(release);
  const participant=await context.newPage();participant.on('pageerror',e=>errors.push(e.message));let failedImage=false;
  await participant.route('**/api/assets/**',route=>{if(!failedImage){failedImage=true;return route.abort();}return route.continue();});
  const participantURL=`http://127.0.0.1:${config.participant_port}/participant/?token=${release.token}`;
  await participant.goto(participantURL);await expect(participant.getByRole('button',{name:'Retry image',exact:true})).toBeVisible();await expect(participant.getByRole('button',{name:'Continue to study information',exact:true})).toBeDisabled();
  assert.equal((await snapshot()).runs.length,0);await participant.getByRole('button',{name:'Retry image',exact:true}).click();await expect(participant.getByRole('button',{name:'Continue to study information',exact:true})).toBeEnabled();await expect(participant.locator('#error')).toBeHidden();
  await expect(participant.locator('.welcome-text')).toHaveText(message);assert.equal(await participant.evaluate(()=>window.WELCOME_UNSAFE),undefined);
  await scan(participant,'participant-welcome-desktop');await scan(participant,'participant-welcome-390',true);
  const imageBytes=Buffer.from(await(await fetch(`http://127.0.0.1:${config.participant_port}/api/assets/${release.token}/${config.original_image_hash}`)).arrayBuffer());assert.equal(digest(imageBytes),config.original_image_hash);
  check(true,'Actual release serves exact immutable artwork; image-load failure blocks continuation, retry recovers, and no session starts before consent');
  await participant.getByRole('button',{name:'Continue to study information',exact:true}).click();await expect(participant.locator('#content')).toContainText('Original study information. Taking part is voluntary.');
  await participant.getByRole('button',{name:'Back to welcome',exact:true}).click();await expect(participant.getByRole('heading',{name:'Welcome to the original packaging study',exact:true})).toBeVisible();
  await participant.getByRole('button',{name:'Continue to study information',exact:true}).click();await participant.locator('#consent').check();await participant.getByRole('button',{name:'Start study',exact:true}).click();await expect(participant.locator('#content')).toContainText('Original instructions after consent.');
  await participant.getByRole('button',{name:'Begin',exact:true}).click();await participant.getByRole('textbox').fill('Synthetic browser response about the original pack.');await participant.getByRole('button',{name:'Continue',exact:true}).click();
  await expect(participant.locator('#content')).toContainText('Original closing thanks and contact information.',{timeout:30000});await expect.poll(async()=>{const s=await snapshot();return s.runs.length===1&&s.runs[0].completion_status==='completed';},{timeout:30000}).toBe(true);
  check(true,'Welcome → separate consent → original instructions → saved response → debrief completes one explicitly sample session');
  helper('analyse');const analysis=JSON.parse(await fs.readFile(path.join(folder,'welcome-worker-acceptance.json'),'utf8'));assert.equal(analysis.passed,true);
  check(true,'Automatic supervised analysis publishes the exact welcome release, original image and recorded sample response');
  await stage('Plan');await button('Replace welcome image').click();await page.getByRole('dialog').locator('input[type="file"]').setInputFiles(path.join(folder,'replacement-welcome.png'));await page.locator('#welcome_upload_alt').fill('Original fictional orange packaging concept');await button('Attach image').click();await expect(page.getByRole('dialog')).toHaveCount(0);await idle();
  const updated=(await snapshot()).studies.find(s=>s.id===authored.id);assert.equal(updated.body.welcome.asset.hash,config.replacement_image_hash);
  const entry=await(await fetch(`http://127.0.0.1:${config.participant_port}/api/entry/${release.token}`)).json();assert.equal(entry.welcome.asset.hash,config.original_image_hash);
  assert.equal((await fetch(`http://127.0.0.1:${config.participant_port}/api/assets/${release.token}/${config.replacement_image_hash}`)).status,404);
  check(true,'Replacing draft artwork preserves the existing release and refuses unrelated image hashes');
  await button('Save as template').click();await idle();await button('Design library').click();await button('Use this design').first().click();await expect(page.locator('#study_title')).toBeVisible();
  const reused=(await snapshot()).studies.find(s=>s.body.lineage?.operation==='use_template');assert.equal(reused.body.welcome.asset.hash,config.replacement_image_hash);assert.equal(reused.body.welcome.text,message);
  const downloadPromise=page.waitForEvent('download');await page.getByRole('link',{name:'Export design',exact:true}).click();const download=await downloadPromise;assert.equal(await download.failure(),null);await download.saveAs(path.join(output,'original-welcome.brohn-study.zip'));
  check(true,'Design-library reuse preserves authored welcome and replacement image in a separate draft, and its portable package exports successfully');
  helper('legacy');const legacy=JSON.parse(await fs.readFile(path.join(folder,'legacy.json'),'utf8'));const legacyPage=await context.newPage();await legacyPage.goto(`http://127.0.0.1:${config.participant_port}/participant/?token=${legacy.token}`);
  await expect(legacyPage.getByRole('button',{name:'Start study',exact:true})).toBeVisible();await expect(legacyPage.getByRole('button',{name:'Continue to study information',exact:true})).toHaveCount(0);
  check(true,'Legacy release with no optional welcome still opens directly at its original consent page');
  assert.equal(errors.length,0,JSON.stringify(errors));assert.ok(scans.every(s=>!s.violations&&!s.overflow&&!s.small.length),JSON.stringify(scans));
  await fs.writeFile(path.join(output,'results.json'),JSON.stringify({passed:true,checks,scans,source:config,limits:['Original synthetic images and one automated sample response; no actual participant, hardware or timing qualification.']},null,2));console.log(JSON.stringify({checks:checks.length,scans:scans.length,output}));
}catch(error){await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,scans,errors,logs,text:await page.locator('body').innerText().catch(()=>'(closed)')},null,2));throw error;
}finally{
  await browser.close();for(const[mode,p]of Object.entries(processes)){if(p.exitCode===null){await fs.writeFile(path.join(folder,`stop.${mode}`),'Stop owned welcome fixture.');await expect.poll(()=>p.exitCode!==null,{timeout:20000,intervals:[100,250]}).toBe(true);}await fs.writeFile(path.join(output,`${mode}.log`),logs[mode]);}
}
