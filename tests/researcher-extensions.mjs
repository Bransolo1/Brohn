// Actual authoring/model-review/task-report UI. Every study and answer is
// original synthetic QA; no model segmentation is treated as validated AOI.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const taskOnly=process.env.BROHN_TEST_ONLY_TASK==='1';
const output=path.resolve(`../../work/test-runs/brohn-extension${taskOnly?'-task':''}-evidence`);await fs.mkdir(output,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage();
const base=process.env.BROHN_TEST_URL||'http://127.0.0.1:3851/',checks=[],errors=[],findings=[];
page.on('pageerror',e=>errors.push(e.message));
const check=(ok,name)=>{assert.ok(ok,name);checks.push(name);console.log(`PASS ${name}`);};
const stage=async name=>page.getByRole('button',{name,exact:true}).click();
async function select(id,text){const input=page.locator(`#${id}-selectized`);await input.click();await input.fill(text);await input.press('Enter');}
async function axe(name,narrow=false){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&!document.querySelector('.recalculating'));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);await page.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});
 const violations=(await new AxeBuilder({page}).analyze()).violations;await fs.writeFile(path.join(output,`${name}-axe.json`),JSON.stringify(violations,null,2));
 await page.screenshot({path:path.join(output,`${name}.png`),fullPage:true});if(violations.length)findings.push({name,violations:violations.map(v=>v.id)});else check(true,`${name}: automated accessibility clear`);
 check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`${name}: no page overflow`);await page.setViewportSize({width:1440,height:1080});}
async function download(label,name){const link=page.getByRole('link',{name:label,exact:true});await expect(link).toHaveAttribute('href',/session\/.*download\//);const promise=page.waitForEvent('download');await link.click();const d=await promise;assert.equal(await d.failure(),null);const file=path.join(output,name);await d.saveAs(file);return file;}
function design(file){const r=spawnSync(path.resolve('../../work/tooling/methods-venv/Scripts/python.exe'),['-c',"import sys,zipfile; print(zipfile.ZipFile(sys.argv[1]).read('design.json').decode('utf-8'))",file],{encoding:'utf8',windowsHide:true});assert.equal(r.status,0,r.stderr);return JSON.parse(r.stdout);}
async function localJournal(p){return p.evaluate(()=>new Promise(resolve=>{const open=indexedDB.open('brohn-participant',1);open.onsuccess=()=>{const db=open.result,get=db.transaction('sessions').objectStore('sessions').getAll();get.onsuccess=()=>{resolve(get.result);db.close();};};}));}
async function waitOnset(p,id){const end=Date.now()+8000;while(Date.now()<end){if((await localJournal(p)).some(r=>r.events?.some(e=>e.type==='task_event'&&e.payload.kind==='task_trial_started'&&e.payload.data.trial_id===id)))return;await delay(40);}throw Error(`No observed onset for ${id}`);}
async function waitSuggestion(){const review=page.getByRole('button',{name:'Review suggestion',exact:true}).first(),area=page.locator('.brohn-card').filter({has:page.getByRole('heading',{name:'Suggested areas',exact:true})});const end=Date.now()+180000;while(Date.now()<end){if(await review.isVisible())return;if(await area.count()){const text=await area.innerText();if(/Analysis did not complete/.test(text))throw Error(`Actual suggestion worker failed: ${text}`);}await delay(250);}throw Error('No reviewable suggestion within three minutes');}
let manual=null,authored=null;
try{
 await page.goto(base);await page.getByRole('heading',{name:'Your next discovery starts here.',exact:true}).waitFor();
 if(!taskOnly){
 await page.getByRole('button',{name:'Explore a practice design'}).click();await page.getByLabel('Study name',{exact:true}).waitFor();
 const title=`Researcher AOI ${Date.now()}`;await page.getByLabel('Study name',{exact:true}).fill(title);await stage('Save');
 await page.getByRole('button',{name:'Define area',exact:true}).first().click();await page.locator('#brohn-aoi-canvas').waitFor();
 await expect(page.locator('#shiny-modal')).toHaveClass(/show/);await page.locator('#shiny-modal').evaluate(async element=>{await Promise.all(element.getAnimations({subtree:true}).map(animation=>animation.finished.catch(()=>{})));});
 const points=await page.locator('#brohn-aoi-canvas').evaluate(svg=>{const box=svg.viewBox.baseVal,m=svg.getScreenCTM();const at=(x,y)=>{const p=new DOMPoint(x*box.width,y*box.height).matrixTransform(m);return{x:p.x,y:p.y};};return{start:at(.1,.1),end:at(.3,.3)};});
 await page.mouse.move(points.start.x,points.start.y);await page.mouse.down();await page.mouse.move(points.end.x,points.end.y,{steps:12});await page.mouse.up();
 await expect(page.locator('#aoi_x')).toHaveValue('0.1');await expect(page.locator('#aoi_width')).toHaveValue('0.2');
 const drawn=await Promise.all(['x','y','width','height'].map(async key=>Number(await page.locator(`#aoi_${key}`).inputValue())));
 check(drawn.join(',')==='0.1,0.1,0.2,0.2',`Pointer drag creates the independent .1,.1,.2,.2 rectangle in image coordinates (${drawn})`);
 await page.locator('#brohn-aoi-canvas').focus();await page.locator('#brohn-aoi-canvas').press('ArrowRight');await expect(page.locator('#aoi_x')).toHaveValue('0.11');await stage('Undo region change');await expect(page.locator('#aoi_x')).toHaveValue('0.1');
 await page.getByLabel('Area name',{exact:true}).fill('Original QA region');await axe('drawn-aoi');await axe('drawn-aoi-narrow',true);await stage('Save area');
 await page.getByRole('button',{name:'Edit Original QA region',exact:true}).waitFor();
 manual=design(await download('Export design','manual-aoi.brohn-study.zip'));const added=manual.stimuli[0].aois.find(a=>a.label==='Original QA region');
 check(added&&[added.x,added.y,added.width,added.height].join(',')==='0.1,0.1,0.2,0.2'&&added.asset_hash===manual.stimuli[0].asset.hash,'Saved graphical region has exact geometry and immutable image identity');
 await page.getByRole('button',{name:'Suggest area',exact:true}).first().click();await page.locator('#brohn-aoi-prompt').waitFor();
 await page.locator('#brohn-aoi-prompt').focus();await page.locator('#brohn-aoi-prompt').press('ArrowRight');await expect(page.locator('#aoi_prompt_x')).toHaveValue('0.51');
 check(true,'Suggestion point supports keyboard authoring');await stage('Generate suggestion');
 await waitSuggestion();
 const proposed=design(await download('Export design','before-review.brohn-study.zip'));
 check(proposed.stimuli[0].aois.length===2,'Model proposal does not silently become an analytical AOI');
 await page.getByRole('button',{name:'Review suggestion',exact:true}).first().click();await page.getByLabel('Area name',{exact:true}).waitFor();
 await page.getByText('Inspect the saved model mask',{exact:true}).click();const mask=await download('Download mask','proposal-mask.png');
 check((await fs.readFile(mask)).subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])),'Suggested model mask is a real downloadable PNG artifact');
 await page.getByLabel('Area name',{exact:true}).fill('Reviewed suggestion');
 for(const[id,value]of Object.entries({aoi_x:'.3',aoi_y:'.3',aoi_width:'.2',aoi_height:'.2'}))await page.locator(`#${id}`).fill(value);
 await page.getByLabel('Review note (optional)').fill('Original synthetic QA: explicitly reviewed rectangle; model mask and analysis rectangle are different representations.');await axe('proposal-review');
 await stage('Accept this rectangle');await expect(page.locator('#platform_status')).toContainText('Reviewed rectangle saved');
 const reviewed=design(await download('Export design','reviewed-aoi.brohn-study.zip')),accepted=reviewed.stimuli[0].aois.find(a=>a.label==='Reviewed suggestion');
 check(accepted&&[accepted.x,accepted.y,accepted.width,accepted.height].join(',')==='0.3,0.3,0.2,0.2','Explicitly accepted rectangle uses the researcher-reviewed geometry');
 check(reviewed.stimuli[0].aois.length===3&&reviewed.stimuli[0].asset.hash===manual.stimuli[0].asset.hash,'Suggestion acceptance adds a revision without changing original stimulus bytes');
 }

 await stage('Home');await stage('Create a study');await page.getByLabel('Study name',{exact:true}).fill(`Researcher task ${Date.now()}`);
 await page.getByLabel('Blank design',{exact:true}).check();await stage('Create study');await page.getByLabel('Study name',{exact:true}).waitFor();
 await stage('Tasks');await select('task_profile','Simple reaction time');await stage('Add procedure');await page.locator('#task_title_1').waitFor();
 await page.locator('#task_title_1').fill('Original synthetic simple RT');await stage('Save');await axe('task-authoring');await axe('task-authoring-narrow',true);
 authored=design(await download('Export design','authored-task.brohn-study.zip'));
 check(authored.blocks.length===1&&authored.blocks[0].profile==='rt-deary-liewald-simple/1.0'&&authored.blocks[0].title==='Original synthetic simple RT','Researcher authoring saves the selected named procedure and title');
 await stage('Collect');await page.getByLabel('Require a researcher-issued participant code to link repeat sessions').check();await stage('Release participant study');
 await page.getByRole('link',{name:'Open participant study',exact:true}).first().waitFor();const url=await page.getByRole('link',{name:'Open participant study',exact:true}).first().getAttribute('href');
 const pc=await browser.newContext({viewport:{width:1280,height:900}}),p=await pc.newPage();p.on('pageerror',e=>errors.push(e.message));await p.goto(url);
 await p.getByLabel('Participant alias (required)').fill('SYNTHETIC-AUTHORED-TASK');await p.getByLabel('I have read the study information and agree to take part.').check();
 const response=p.waitForResponse(r=>r.url().includes('/api/start/')&&r.request().method()==='POST');await p.getByRole('button',{name:'Start study',exact:true}).click();const session=await(await response).json();
 for(const main of session.protocol.timeline){
   if(main.type==='instructions')await p.getByRole('button',{name:'Begin',exact:true}).click();
   else if(main.type==='task')for(const trial of main.task.timeline){if(trial.type==='task_instructions')await p.getByRole('button',{name:'Begin this block',exact:true}).click();else{await waitOnset(p,trial.id);await p.keyboard.press(trial.correct_code);}}
   else throw Error(`Unexpected fixture step ${main.type}`);
 }
 await p.getByRole('heading',{name:'Thank you. Your responses are saved.',exact:true}).waitFor({timeout:30000});check(true,'UI-authored procedure completed through the actual participant service');await pc.close();await page.bringToFront();
 await stage('Results');await page.getByRole('button',{name:'Open report',exact:true}).first().waitFor({timeout:120000});await page.getByRole('button',{name:'Open report',exact:true}).first().click();
 const report=JSON.parse(await fs.readFile(await download('JSON + provenance','authored-task-report.json'),'utf8')),score=report.analysis.task_scores[0];
 check(score.eligible===true&&score.counts.retained_correct===20,'Automatic task report scores exactly20 retained test trials, separately from8 practice trials');
 check(score.metrics.find(m=>m.name==='correct_test_rt_mean').value>0,'Task report contains observed RT summary without substituting a norm or preference label');
 await axe('authored-task-report');await axe('authored-task-report-narrow',true);
 check(errors.length===0,`No browser exceptions ${errors.join(';')}`);check(findings.length===0,`All modal/task accessibility checks clear ${JSON.stringify(findings)}`);
 await fs.writeFile(path.join(output,'results.json'),JSON.stringify({origin:'original_synthetic',mode:taskOnly?'task_only':'full',checks,study_ids:[manual?.id,authored.id].filter(Boolean),task_report_id:report.id},null,2));console.log(JSON.stringify({checks:checks.length,output}));
}catch(error){await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,errors,findings,text:await page.locator('body').innerText()},null,2));throw error;}finally{await browser.close();}
