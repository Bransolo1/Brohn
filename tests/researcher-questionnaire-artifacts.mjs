// Actual saved-report UI and full downloads, followed by one real synthesis
// worker. Run only after root releases the scientific-source freeze and supplies
// the newly qualified retained boundary workspace/report. No hardware or people.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const base=path.resolve('../../work/test-runs');
const resume=process.env.BROHN_QUESTIONNAIRE_ARTIFACT_QA;
const folder=resume?path.resolve(resume):await fs.mkdtemp(path.join(base,'brohn-questionnaire-artifact-ui-'));
assert.ok(path.basename(folder).startsWith('brohn-questionnaire-artifact-ui-'));
const output=path.join(folder,`evidence-${Date.now()}`);await fs.mkdir(output);
const r=path.resolve('../../work/native-r/bin/x64/Rscript.exe'),python=path.resolve('../../work/tooling/methods-venv/Scripts/python.exe');
const env={...process.env,R_LIBS_USER:path.resolve('../../work/r-library-brohn'),R_USER:path.resolve('../../work'),LC_ALL:'C'};
function helper(mode,...args){const p=spawnSync(r,['--vanilla','tests/fixtures/researcher-questionnaire-artifacts.R',mode,folder,...args],{env,windowsHide:true,encoding:'utf8'});assert.equal(p.status,0,p.stderr);}
if(!resume){assert.ok(process.argv[2]&&process.argv[3],'Supply the qualified retained workspace and artifact report ID.');helper('setup',path.resolve(process.argv[2]),process.argv[3]);}
await fs.unlink(path.join(folder,'stop.request')).catch(e=>{if(e.code!=='ENOENT')throw e;});
const fixture=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
const logs={researcher:''},app=spawn(r,['--vanilla','tests/fixtures/researcher-questionnaire-artifacts.R','serve',folder],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});
for(const stream of[app.stdout,app.stderr])stream.on('data',b=>logs.researcher+=b);
const browser=await chromium.launch({channel:'chrome',headless:true});let context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage(),active=page;
const checks=[],scans=[],errors=[];let workerCount=0;
const watch=p=>p.on('pageerror',e=>errors.push(e.message));watch(page);
const check=(condition,label)=>{assert.ok(condition,label);checks.push(label);console.log(`PASS ${label}`);};
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const snapshot=async()=>{helper('inspect');return JSON.parse(await fs.readFile(path.join(folder,'snapshot.json'),'utf8'));};
async function idle(p=page){if(p===page){await p.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&![...document.querySelectorAll('.recalculating')].some(e=>e.getClientRects().length));await expect(p.locator('.shiny-output-error:visible')).toHaveCount(0);}}
async function study(source){await page.getByRole('button',{name:'Studies',exact:true}).click();await page.getByLabel('Search studies',{exact:true}).fill(source.study_title);await page.locator(`[data-brohn-event="brohn_open_study"][data-brohn-value='"${source.study_id}"']`).click();await expect(page.getByLabel('Study name',{exact:true})).toHaveValue(source.study_title);}
async function stage(name){await page.getByRole('button',{name,exact:true}).click();await page.waitForFunction(name=>{const field=document.getElementById('study_form_identity');return field?.value.endsWith(`:${name}`)&&Shiny.shinyapp.$inputValues.study_form_identity===field.value;},name);}
async function report(source,id=source.report_id){await study(source);await stage('Results');await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${id}"']`).click();await page.getByRole('link',{name:'JSON + provenance',exact:true}).waitFor();await idle();}
async function select(id,value){const label=await page.locator(`#${id}`).evaluate((el,value)=>el.selectize.options[value]?.[el.selectize.settings.labelField]??null,value);const input=page.locator(`#${id}-selectized`);await input.click();await input.fill(label??value.slice(-6));await page.locator(`.selectize-dropdown:visible [data-value="${value}"]`).click();}
async function selectLabel(id,fragment){const value=await page.locator(`#${id}`).evaluate((el,fragment)=>Object.entries(el.selectize.options).find(([,o])=>String(o[el.selectize.settings.labelField]).includes(fragment))?.[0],fragment);assert.ok(value,`No ${id} option containing ${fragment}`);await select(id,value);}
async function download(label,name){const link=page.getByRole('link',{name:label,exact:true});await expect(link).toHaveAttribute('href',/session\/.*download\//);const pending=page.waitForEvent('download',{timeout:120000});await link.click();const d=await pending;assert.equal(await d.failure(),null);const file=path.join(output,name);await d.saveAs(file);return file;}
function csv(file){const p=spawnSync(python,['-c',"import csv,json,sys;csv.field_size_limit(1000000);print(json.dumps(list(csv.DictReader(open(sys.argv[1],encoding='utf-8-sig',newline='')))))",file],{windowsHide:true,encoding:'utf8',maxBuffer:32*1024**2});assert.equal(p.status,0,p.stderr);return JSON.parse(p.stdout);}
async function axe(label,narrow=false,p=page){active=p;await p.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});await idle(p);const violations=(await new AxeBuilder({page:p}).analyze()).violations;scans.push({label,count:violations.length});await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(violations,null,2));await p.screenshot({path:path.join(output,`${label}.png`),fullPage:false});assert.deepEqual(violations,[],`${label}: accessibility violations`);assert.ok(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`${label}: page overflow`);await p.setViewportSize({width:1440,height:1080});active=page;}
// Independent typed-node reconstruction: no application reader is called.
function typedArtifact(bytes){const lines=bytes.toString('utf8').split('\n');assert.equal(lines.pop(),'');const nodes=lines.map(JSON.parse),header=nodes[0];assert.equal(header.schema,'brohn-questionnaire-analysis-artifact/1.0');assert.equal(header.record_type,'header');assert.equal(nodes.length-1,header.node_count);assert.ok(lines.every(line=>Buffer.byteLength(line)<=256*1024));let cursor=1;
 const next=expectedPath=>{const node=nodes[cursor++];assert.equal(node.record_type,'node');assert.equal(node.sequence,cursor-1);assert.deepEqual(node.path,expectedPath);return node;};
 const decode=(parts=[])=>{const node=next(parts);if(node.type==='value')return node.value;if(node.type==='array')return Array.from({length:node.length},(_,i)=>decode([...parts,{index:i+1}]));if(node.type==='object'){const out={};assert.equal(new Set(node.keys).size,node.keys.length);for(const key of node.keys)Object.defineProperty(out,key,{value:decode([...parts,{key}]),enumerable:true,writable:true,configurable:true});return out;}if(node.type==='string'){let text='';for(let i=1;i<=node.parts;i++){const part=next(parts);assert.equal(part.type,'string_part');assert.equal(part.part,i);text+=part.text;}assert.equal(Buffer.byteLength(text),node.utf8_bytes);assert.equal(sha(Buffer.from(text)),node.utf8_sha256);return text;}assert.fail(`Unknown typed node ${node.type}`);};
 const analysis=decode();assert.equal(cursor,nodes.length);return{analysis,header};}
async function processOne(){workerCount++;logs.worker='';const child=spawn(r,['--vanilla','scripts/run-worker.R','--root',fixture.workspace,'--once'],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});for(const s of[child.stdout,child.stderr])s.on('data',b=>logs.worker+=b);await new Promise((resolve,reject)=>{child.on('error',reject);child.on('exit',(code,signal)=>code===0?resolve():reject(new Error(`Worker ${code}/${signal}: ${logs.worker}`)));});return snapshot();}
try{
 await expect.poll(async()=>{if(app.exitCode!==null)throw new Error(logs.researcher);try{return(await fetch(`http://127.0.0.1:${fixture.port}/`)).status===200;}catch{return false;}},{timeout:45000,intervals:[250,500,1000]}).toBe(true);
 await page.goto(`http://127.0.0.1:${fixture.port}/`);let current=await snapshot();const initialJobs=current.jobs.map(j=>j.id);
 assert.equal(current.boundary.hash,fixture.boundary.report_hash);assert.ok(current.boundary.envelope_exact&&current.boundary.artifacts_valid);await report(fixture.boundary);
 const counts=fixture.boundary.counts;await page.getByRole('heading',{name:'Complete questionnaire results',exact:true}).waitFor();
 await expect(page.locator('body')).toContainText(`${counts.observations} response records; ${counts.features} question summaries; ${counts.revision_effective} final questionnaire records; ${counts.revision_history} acknowledged questionnaire events.`);
 const previewCard=page.locator('.brohn-card').filter({has:page.getByRole('heading',{name:'Response preview',exact:true})});
 await expect(previewCard).toContainText(`Showing ${fixture.boundary.preview.observations.length} of ${counts.observations} complete response records`);
 await expect(page.getByRole('region',{name:/^Abbreviated questionnaire responses;/}).locator('tbody tr')).toHaveCount(fixture.boundary.preview.observations.length);
 check(await page.locator('body').innerText().then(text=>text.includes('bounded display previews')&&text.includes('Long text is abbreviated')),'The saved large report identifies full counts, bounded previews and abbreviated text without presenting the preview as complete analysis');
 await axe('questionnaire-artifact-report');await axe('questionnaire-artifact-report-narrow',true);
 const jsonPath=await download('JSON + provenance','complete-questionnaire-report.json'),jsonBytes=await fs.readFile(jsonPath),full=JSON.parse(jsonBytes);
 assert.equal(full.export.schema,'brohn-complete-questionnaire-export/1.0');assert.equal(full.export.saved_report_hash,fixture.boundary.report_hash);assert.equal(full.export.analysis_sha256,fixture.boundary.artifact.analysis_sha256);
 assert.ok(jsonBytes.length>16*1024**2);assert.equal(full.analysis.observations.length,200);assert.equal(full.analysis.questionnaire_revision.runs.length,1);
 const revision=full.analysis.questionnaire_revision.runs[0],commits=revision.history_events.filter(e=>e.payload.kind==='commit');
 assert.equal(revision.effective_records.length,200);assert.equal(commits.length,400);assert.equal(revision.history_events.length,803);assert.equal(counts.revision_history,803);
 for(let i=1;i<=200;i++){const value=`${'a'.repeat(19000)} 2 ${i}`,id=`boundary-q-${i}`;const observed=full.analysis.observations.find(o=>o.question_id===id),final=revision.effective_records.find(o=>o.question_id===id);assert.equal(observed.value,value);assert.equal(final.value,value);assert.equal(final.revision_count,1);assert.equal(final.response_time_ms,null);const versions=commits.filter(e=>e.question_id===id);assert.equal(versions.length,2);assert.equal(versions[0].payload.value,`${'a'.repeat(19000)} 1 ${i}`);assert.equal(versions[1].payload.value,value);}
 check(true,'Full JSON retains all 200 complete final texts, all 400 acknowledged answer versions and null revised-answer timing beyond the display preview');
 const source=fixture.boundary.source_runs[0];assert.equal(source.event_count,804);assert.equal(revision.run_id,source.run_id);for(const expected of source.final_answers){const final=revision.effective_records.find(o=>o.step_id===expected.step_id);assert.ok(final);assert.equal(Buffer.byteLength(final.value),expected.text.utf8_bytes);assert.equal(sha(Buffer.from(final.value)),expected.text.sha256);}
 check(true,'Downloaded final answers match independently hashed original retained commit values and exact run/step identities');
 const rows=csv(await download('Download observations','complete-questionnaire-observations.csv'));assert.equal(rows.length,200);assert.equal(new Set(rows.map(r=>r.question_id)).size,200);
 for(let i=1;i<=200;i++){const row=rows.find(r=>r.question_id===`boundary-q-${i}`);assert.equal(row.value,`${'a'.repeat(19000)} 2 ${i}`);assert.deepEqual(JSON.parse(row.response_record_json),full.analysis.observations.find(r=>r.question_id===`boundary-q-${i}`));}
 check(true,'The actual observation CSV includes every full response exactly once, including rows 11 through 200, unabridged text and exact typed response_record_json');
 const artifactPath=await download('Download complete artifact','questionnaire-analysis.jsonl'),artifactBytes=await fs.readFile(artifactPath);assert.equal(sha(artifactBytes),fixture.boundary.artifact.hash);assert.equal(artifactBytes.length,fixture.boundary.artifact.size);
 const decoded=typedArtifact(artifactBytes);assert.deepEqual(decoded.analysis,full.analysis);assert.deepEqual(decoded.header.counts,counts);assert.equal(decoded.header.analysis_sha256,full.export.analysis_sha256);
 check(true,'The actual typed artifact download has its immutable full-file hash and independently reconstructs the same complete analysis and edit history');
 const htmlPath=await download('Download report','questionnaire-preview-report.html'),offline=await context.newPage();await offline.goto(`file:///${htmlPath.replaceAll('\\','/')}`);await offline.getByRole('heading',{name:'Complete questionnaire results',exact:true}).waitFor();await expect(offline.locator('body')).toContainText('bounded display previews');await axe('questionnaire-artifact-offline',false,offline);await axe('questionnaire-artifact-offline-narrow',true,offline);await offline.close();
 check(true,'Standalone HTML preserves the full-count/preview distinction and renders accessibly at desktop and 390 pixels');
 await context.close();context=await browser.newContext({viewport:{width:1440,height:1080}});page=await context.newPage();active=page;watch(page);await page.goto(`http://127.0.0.1:${fixture.port}/`);await report(fixture.boundary);
 const reopened=await fs.readFile(await download('JSON + provenance','complete-questionnaire-reopened.json'));assert.equal(sha(reopened),sha(jsonBytes));current=await snapshot();assert.equal(current.boundary.hash,fixture.boundary.report_hash);assert.equal(current.boundary_study_hash,fixture.boundary.study_hash);assert.deepEqual(current.source_runs.map(r=>r.row_hashes),fixture.boundary.source_runs.map(r=>r.row_hashes));
 check(true,'A fresh researcher session reopens byte-identical full JSON with unchanged source journal, study, report envelope and artifact');
 // The source fixture is deliberately constructed; only this next synthesis is
 // an actual scientific subprocess. No participant observation is invented.
 await report(fixture.oracle);await expect(page.getByRole('region',{name:/^Abbreviated questionnaire responses;/})).not.toContainText(fixture.oracle.question_prompt);
 await study(fixture.oracle);await stage('Results');await page.getByRole('button',{name:'Combine measures',exact:true}).click();
 await page.getByRole('heading',{name:'Combine study measures',exact:true}).waitFor();await select('mm_reports',fixture.oracle.report_id);await select('mm_origin','sample');await page.getByRole('button',{name:'Review participants and measures',exact:true}).click();
 await page.getByRole('heading',{name:'Review how these measures belong together',exact:true}).waitFor();await selectLabel('mm_metric',fixture.oracle.question_prompt);
 await page.getByText('Source availability and measure definitions',{exact:true}).click();const definitions=page.getByRole('region',{name:/^Available measure definitions;/});await expect(definitions).toContainText('6');
 check(true,'Combine measures discovers the quantitative outcome that is absent from all ten preview rows');
 await page.getByLabel('I checked that shared person and session codes refer to the same people and visits',{exact:true}).check();
 await page.getByLabel('Evidence for these participant links',{exact:true}).fill('Original synthetic fixture register: context-1 through context-12 are separate fictional context responses; person-1 through person-3 each have the exact two condition rows in visit-1. No observed people or real devices.');
 await page.getByRole('button',{name:'Add comparison',exact:true}).click();await axe('questionnaire-artifact-combine');await axe('questionnaire-artifact-combine-narrow',true);
 await page.getByRole('button',{name:'Save combined report',exact:true}).click();await page.getByRole('heading',{name:'Activity',exact:true}).waitFor();current=await snapshot();const queued=current.jobs.filter(j=>!initialJobs.includes(j.id));assert.equal(queued.length,1);assert.equal(queued[0].operation,'analyse_multimodal');assert.equal(queued[0].status,'queued');current=await processOne();const job=current.jobs.find(j=>j.id===queued[0].id);assert.equal(job.status,'succeeded',JSON.stringify(job.error));
 await fs.writeFile(path.join(output,'scientific-checkpoint.json'),JSON.stringify({job,report:current.combined.find(r=>r.id===job.result.report_id),checks,scans},null,2));
 const combined=current.combined.find(r=>r.id===job.result.report_id);assert.ok(combined&&combined.envelope_exact);await report(fixture.oracle,combined.id);const combinedJson=JSON.parse(await fs.readFile(await download('JSON + provenance','combined-complete-evidence.json'),'utf8'));
 const values=combinedJson.analysis.observations.filter(o=>o.outcome_id===fixture.oracle.question_id);assert.equal(values.length,6);assert.deepEqual(values.map(o=>o.source_row),[13,14,15,16,17,18]);assert.ok(values.every(o=>o.source_eligible&&o.source_report_hash===fixture.oracle.report_hash));
 const contrast=combinedJson.analysis.contrasts.find(c=>c.outcome_id===fixture.oracle.question_id);assert.equal(contrast.estimate,4);assert.equal(contrast.participant_count,3);assert.equal(contrast.paired_session_count,3);assert.equal(contrast.multiplicity.family_size,1);
 check(true,'The actual saved synthesis uses all six post-preview numeric rows: independent differences 2, 4 and 6 produce estimate 4 across three people and visits');
 const combinedRows=csv(await download('Download observations','combined-complete-observations.csv'));assert.equal(combinedRows.filter(o=>o.outcome_id===fixture.oracle.question_id).length,6);await axe('questionnaire-artifact-combined-narrow',true);
 current=await snapshot();assert.equal(current.oracle.hash,fixture.oracle.report_hash);assert.equal(current.boundary.hash,fixture.boundary.report_hash);assert.ok(current.boundary.envelope_exact&&current.boundary.artifacts_valid);assert.equal(errors.length,0);assert.ok(scans.every(s=>s.count===0));
 check(true,'Completed synthesis preserves both original source reports; no browser exceptions, visible R errors or automated accessibility violations remain');
 await fs.writeFile(path.join(output,'results.json'),JSON.stringify({origin:'original_synthetic',checks,scans,boundary_report_id:fixture.boundary.report_id,boundary_report_hash:fixture.boundary.report_hash,boundary_artifact_hash:fixture.boundary.artifact.hash,
  complete_json_sha256:sha(jsonBytes),complete_json_bytes:jsonBytes.length,oracle_source_report_id:fixture.oracle.report_id,combined_report_id:combined.id,worker_processes_this_invocation:workerCount,
  source_evidence:fixture.evidence_limits,limits:['Automated researcher browser interaction and generated receiver journals; no human usability or hardware qualification.','Boundary fixture contains no hidden or omitted questions; those distinctions are tested by the separate answer-review journey.','This verifies the retained bounded fixture and one complete-source synthesis; it does not qualify unlimited memory or arbitrarily large cohorts.']},null,2));
 console.log(JSON.stringify({checks:checks.length,scans:scans.length,folder,output}));
}catch(error){await active.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,scans,errors,logs,text:await active.locator('body').innerText().catch(()=>'(closed)')},null,2));throw error;
}finally{await browser.close();if(app.exitCode===null){await fs.writeFile(path.join(folder,'stop.request'),'Stop owned questionnaire-artifact researcher fixture.');await expect.poll(()=>app.exitCode!==null,{timeout:20000,intervals:[100,250]}).toBe(true);}for(const[name,text]of Object.entries(logs))await fs.writeFile(path.join(output,`${name}.log`),text);}
