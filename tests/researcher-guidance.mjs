// Real researcher app; original synthetic materials only. Does not collect or
// score data. Supply a fresh, dedicated QA directory starting brohn-guidance-.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

assert.ok(process.argv[2]);
const folder=path.resolve(process.argv[2]);assert.ok(path.basename(folder).startsWith('brohn-guidance-'));
await fs.mkdir(folder,{recursive:true});
const output=path.join(folder,`browser-evidence-${Date.now()}`);await fs.mkdir(output);
const r=path.resolve('../../work/native-r/bin/Rscript.exe');
const env={...process.env,R_LIBS_USER:path.resolve('../../work/r-library-brohn-restore'),R_USER:path.resolve('../../work'),LC_ALL:'C'};
const checks=[],scans=[],errors=[];let log='';
function helper(mode){const p=spawnSync(r,['--vanilla','tests/fixtures/researcher-guidance.R',mode,folder],{env,windowsHide:true,encoding:'utf8',maxBuffer:8*1024**2});assert.equal(p.status,0,p.stderr);}
try{await fs.access(path.join(folder,'fixture.json'));}catch{helper('setup');}
const config=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
const snapshot=async()=>{helper('inspect');return JSON.parse(await fs.readFile(path.join(folder,'snapshot.json'),'utf8'));};
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log(`PASS ${label}`);};
await fs.unlink(path.join(folder,'stop.request')).catch(e=>{if(e.code!=='ENOENT')throw e;});
const app=spawn(r,['--vanilla','tests/fixtures/researcher-guidance.R','serve',folder],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});
for(const s of[app.stdout,app.stderr])s.on('data',b=>log+=b);
const browser=await chromium.launch({channel:'chrome',headless:true});
const context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage();
page.on('pageerror',e=>errors.push(e.message));
const button=name=>page.getByRole('button',{name,exact:true});
async function idle(){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&![...document.querySelectorAll('.recalculating')].some(e=>e.getClientRects().length));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);await expect(page.locator('#platform_error [role="alert"]')).toHaveCount(0);}
async function stage(name){await button(name).click();await page.waitForFunction(stage=>{const f=document.getElementById('study_form_identity');return f?.value.endsWith(`:${stage}`)&&Shiny.shinyapp.$inputValues.study_form_identity===f.value;},name);await idle();}
async function scan(label,narrow=false,modal=false){
  await page.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});await idle();
  const scope=page.locator(modal?'.modal-content':'.brohn-guidance').first();
  await scope.evaluate(e=>e.scrollIntoView({block:'start',behavior:'instant'}));
  const violations=(await new AxeBuilder({page}).analyze()).violations;
  const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);
  const smallTargets=await scope.locator('button:visible,summary:visible,input:not([type="radio"]):visible,select:visible').evaluateAll(es=>es.filter(e=>e.getBoundingClientRect().height<44).map(e=>({id:e.id,text:e.textContent,height:e.getBoundingClientRect().height})));
  const imageFailures=await scope.locator('img').evaluateAll(es=>es.filter(e=>!e.complete||e.naturalWidth<1).map(e=>e.alt));
  scans.push({label,violations:violations.length,overflow,smallTargets,imageFailures});
  await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(violations,null,2));
  // axe can leave the offscreen bypass link focused after its keyboard checks.
  // Preserve normal screenshots separately from explicit interaction assertions.
  await page.evaluate(()=>document.activeElement?.blur());
  if(!modal)await page.evaluate(()=>window.scrollTo({top:0,behavior:'instant'}));
  await page.screenshot({path:path.join(output,`${label}.png`),fullPage:!modal});
  console.log(`SCAN ${label}: ${violations.length} axe violations, overflow=${overflow}, small=${smallTargets.length}`);
  await page.setViewportSize({width:1440,height:1080});
}
async function create(title,type='comparison'){
  await button('Home').click();await button('Start my study').click();await page.getByLabel('Study name',{exact:true}).fill(title);
  await page.locator(`input[name="new_template"][value="${type}"]`).check();await button('Create study').click();
  await expect(page.locator('#study_title')).toHaveValue(title);await idle();
}
try{
  await expect.poll(async()=>{if(app.exitCode!==null)throw Error(log);try{return(await fetch(`http://127.0.0.1:${config.port}/`)).status===200;}catch{return false;}},{timeout:60000,intervals:[250,500,1000]}).toBe(true);
  await page.goto(`http://127.0.0.1:${config.port}/`);await button('Create a practice study').waitFor();await idle();
  if(process.argv.includes('--screenshots')){
    // Capture final layouts without replaying mutations in the completed fixture.
    await scan('saved-home-desktop');await scan('saved-home-390',true);
    const sample=(await snapshot()).studies.find(s=>s.body.lineage?.operation==='original_sample_design');assert.ok(sample);
    await button('Studies').click();await page.getByLabel('Search studies',{exact:true}).fill(sample.body.title);
    await page.locator(`[data-brohn-event="brohn_open_study"][data-brohn-value='"${sample.id}"']`).click();
    await button('Preview participant sequence').waitFor();await scan('saved-overview-desktop');await scan('saved-overview-390',true);
    await button('Preview participant sequence').click();await expect(page.getByRole('dialog')).toContainText('Example allocation 1');await scan('saved-preview-390',true,true);
    assert.ok(scans.every(s=>!s.violations&&!s.overflow&&!s.smallTargets.length&&!s.imageFailures.length));
    await fs.writeFile(path.join(output,'visual-results.json'),JSON.stringify({passed:true,scans},null,2));
    console.log(JSON.stringify({visuals:true,scans:scans.length,output}));
  }else{
  assert.equal((await snapshot()).studies.length,0);
  await scan('home-desktop');await scan('home-390',true);
  check(true,'Empty Home exposes a real original design preview and creates no saved work by viewing');
  await button('Create a practice study').focus();await page.keyboard.press('Enter');
  await button('Preview participant sequence').waitFor();await idle();
  const sample=(await snapshot()).studies[0];assert.equal(sample.body.lineage.operation,'original_sample_design');
  await expect(page.locator('.brohn-guidance')).toContainText(/0\s+Participant sessions/);
  await scan('practice-overview-desktop');await scan('practice-overview-390',true);
  await button('Preview participant sequence').click();const dialog=page.getByRole('dialog');
  await expect(dialog).toContainText('Example allocation 1');await expect(dialog).toContainText('This preview creates no participant session');
  await expect(dialog).toContainText('View each fictional packaging design');await expect(dialog).toContainText('How much do you like this concept?');
  await scan('practice-preview-390',true,true);
  await button('Close preview').click();await expect(page.locator('#guidance-preview-open')).toBeFocused();
  assert.equal((await snapshot()).runs,0);
  check(true,'Keyboard-created practice study opens its saved overview and exact read-only source sequence; closing restores the launch control');
  await button('Prepare collection').click();await expect(page.locator('#release_origin')).toHaveValue('sample');
  check(true,'Practice collection defaults to sample without opening recruitment');
  await button('Home').click();await button('Start my study').click();
  await scan('create-390',true,true);await button('Cancel').click();
  await create('Original comparison journey');
  await expect(page.locator('.brohn-guidance-plan-intro')).toContainText('Your design is saved');
  await page.locator('#study_description').fill('Does placing the benefit first improve comprehension?');
  await stage('Overview');await button('Add study materials').click();await expect(page.locator('#stimulus_text_1')).toBeFocused();
  await page.locator('#stimulus_text_1').fill('Concept A: Benefit first.');await page.locator('#stimulus_text_2').fill('Concept B: Features first.');
  await stage('Overview');await button('Preview participant sequence').waitFor();
  await expect(page.locator('.brohn-guidance')).toContainText('Does placing the benefit first improve comprehension?');
  await button('Preview participant sequence').click();await expect(dialog).toContainText('Concept A: Benefit first.');await expect(dialog).toContainText('Concept B: Features first.');await button('Close preview').click();
  check(true,'Comparison creation stays in Plan, direct material correction focuses the missing field, and saved content enters the actual compiled preview');
  await create('Original questionnaire journey','survey');
  await button('View study overview').click();await button('Add your first question').click();await expect(page.locator('#question_type')).toBeFocused();
  await button('Add question').click();await page.locator('#q_prompt_1').fill('Which message is clearer? <script>literal source</script>');
  await stage('Overview');await button('Preview participant sequence').click();await expect(dialog).toContainText('Which message is clearer? <script>literal source</script>');
  assert.equal(await page.evaluate(()=>window.literalSource),undefined);await button('Close preview').click();
  check(true,'Questionnaire creation points to the first question and displays saved literal prompt text safely');
  await button('Save as template').click();await idle();
  await button('Home').click();await button('Browse design library').click();await button('Use this design').first().click();
  await expect(page.locator('#study_title')).toBeVisible();
  const afterReuse=await snapshot(),fromTemplate=afterReuse.studies.find(s=>s.body.lineage?.operation==='use_template');
  assert.ok(fromTemplate);assert.equal(fromTemplate.body.questions[0].prompt,'Which message is clearer? <script>literal source</script>');assert.equal(afterReuse.runs,0);
  check(true,'Guided reuse opens the existing template library, creates a separate draft and retains design wording without participant observations');
  helper('seed-long');await button('Studies').click();await page.getByLabel('Search studies',{exact:true}).fill('Original sixty-question preparation fixture');
  await page.locator('[data-brohn-event="brohn_open_study"][data-brohn-value=\'"study-guidance-long"\']').click();
  await button('Preview participant sequence').click();await expect(dialog.locator('.brohn-guidance-preview > li')).toHaveCount(25);
  await button('Next study steps').click();await expect(dialog).toContainText('Showing 26');await expect(page.locator('#guidance-preview-page-title')).toBeFocused();
  await button('Next study steps').click();await expect(dialog).toContainText('Original source question 60');
  await scan('long-preview-390',true,true);await button('Previous study steps').click();await expect(dialog).toContainText('Showing 26');await button('Close preview').click();
  check(true,'Long saved protocol is inspectable beyond fifty source steps with bounded pages and page-heading focus');
  await button('Home').click();await scan('return-home-desktop');
  const final=await snapshot();assert.equal(final.runs,0);assert.equal(final.reports,0);assert.equal(final.datasets,0);assert.equal(errors.length,0);
  check(scans.every(s=>!s.violations&&!s.overflow&&!s.smallTargets.length&&!s.imageFailures.length),'Desktop and 390px scans have no axe violations, overflow, undersized native controls or broken original images');
  await fs.writeFile(path.join(output,'results.json'),JSON.stringify({passed:true,checks,scans,source:config,final_counts:{studies:final.studies.length,runs:final.runs,reports:final.reports,datasets:final.datasets},limits:['Original synthetic designs, automated local Windows Chrome journeys. No human usability, participant timing, hardware or scientific qualification.']},null,2));
  console.log(JSON.stringify({checks:checks.length,scans:scans.length,output}));
  }
}catch(error){await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.html'),await page.content().catch(()=>'(closed)'));await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,scans,errors,log,text:await page.locator('body').innerText().catch(()=>'(closed)')},null,2));throw error;
}finally{
  await browser.close();
  if(app.exitCode===null){await fs.writeFile(path.join(folder,'stop.request'),'Stop owned Brohn guided-study fixture.');await expect.poll(()=>app.exitCode!==null,{timeout:20000,intervals:[100,250]}).toBe(true);}
  await fs.writeFile(path.join(output,'researcher.log'),log);
}
