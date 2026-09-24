import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
let raw='';for await(const chunk of process.stdin)raw+=chunk;
const request=JSON.parse(raw.replace(/^\uFEFF/,''));assert.equal(request.schema,'brohn-linked-history-browser-request/1.0');
const project=await fs.realpath(request.project);
const {sha256,validateDestination,runtimeEnvironment,pinnedTools,sourceHashes,overlaps}=await import(pathToFileURL(path.join(project,'tests/fixtures/connected-smoke-support.mjs')));
const folder=await validateDestination(request),original=await fs.realpath(request.original_workspace);
assert.ok(!overlaps(folder,original)&&!overlaps(original,request.forbidden_workspace));await fs.mkdir(folder);
const env={...runtimeEnvironment(request,folder),BROHN_PYTHON_METHODS:request.portability_python,BROHN_PYTHON_ACQUISITION:request.portability_python,
  RESEARCH_PLATFORM_PORT:'3973',BROHN_PARTICIPANT_PORT:'3974'};await fs.mkdir(env.R_USER);
const checks=[],scans=[],cycles=[],errors=[],write=(name,value)=>fs.writeFile(path.join(folder,name),JSON.stringify(value,null,2));
const check=(label,ok=true)=>{assert.ok(ok,label);checks.push(label);console.log('PASS',label);};
const configurationHash=sha256(await fs.readFile(request.configuration_path));assert.equal(configurationHash,request.configuration_sha256);
const sourceStart=await sourceHashes(project);await write('source-start.json',sourceStart);
const ownHashes=Object.fromEntries(await Promise.all([import.meta.filename,request.fixture_path].map(async f=>[f,sha256(await fs.readFile(f))])));await write('harness-sources.json',ownHashes);
async function tree(root){const result={};async function walk(relative){for(const entry of await fs.readdir(path.join(root,relative),{withFileTypes:true})){
  assert.ok(!entry.isSymbolicLink());const member=path.join(relative,entry.name);if(entry.isDirectory())await walk(member);else result[member.replaceAll('\\','/')]=sha256(await fs.readFile(path.join(root,member)));}}
  await walk('');return result;}
const originalHashes=await tree(original);await write('original-workspace.json',{path:original,hashes:originalHashes});
await fs.cp(original,path.join(folder,'workspace'),{recursive:true,errorOnExist:true,force:false});assert.deepEqual(await tree(path.join(folder,'workspace')),originalHashes);
const tools=await pinnedTools(request),expect=tools.playwright.expect.configure({timeout:45000});
let child,log='',browser,context,page,fixture,failure,cycle=0;
function helper(mode){const p=spawnSync(request.rscript,['--vanilla',request.fixture_path,mode,folder],{cwd:project,env,windowsHide:true,encoding:'utf8',maxBuffer:16*1024**2,timeout:120000});
  assert.equal(p.status,0,p.stderr||p.stdout);return p;}
async function snapshot(){helper('inspect');return JSON.parse(await fs.readFile(path.join(folder,'snapshot.json')));}
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn,timeout=60000){const end=Date.now()+timeout;while(!await fn()){assert.ok(Date.now()<end,'Expected state did not arrive');await sleep(200);}}
async function start(){await fs.rm(path.join(folder,'stop.request'),{force:true});cycle++;log='';child=spawn(request.rscript,['--vanilla',request.fixture_path,'serve',folder],{cwd:project,env,windowsHide:true,stdio:['ignore','pipe','pipe']});
  for(const stream of[child.stdout,child.stderr])stream.on('data',b=>log+=b);cycles.push({cycle,pid:child.pid,researcher_port:3973,participant_port:3974});
  await until(async()=>{assert.equal(child.exitCode,null,log);try{return(await fetch('http://127.0.0.1:3973/',{signal:AbortSignal.timeout(1500)})).ok;}catch{return false;}},90000);}
async function stop(){if(!child)return;const owned=child;await fs.writeFile(path.join(folder,'stop.request'),'Stop owned linked history supervisor.');
  await until(()=>owned.exitCode!==null,45000);assert.equal(owned.exitCode,0,log);assert.ok(log.includes('linked_history_owned_shutdown: TRUE'));
  cycles.at(-1).exit_code=owned.exitCode;await fs.writeFile(path.join(folder,`services-${cycle}.log`),log);child=null;check(`Service cycle${cycle} stops all owned processes normally`);}
const button=name=>page.getByRole('button',{name,exact:true});
async function idle(target='#linked_review_entry'){await page.waitForFunction(selector=>{const node=document.querySelector(selector);return node&&!node.classList.contains('recalculating')&&!node.querySelector('.recalculating');},target);await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);}
async function openDataset(){await button('Data library').click();await page.getByLabel('Search datasets',{exact:true}).fill(fixture.dataset.body.title);
  await page.locator(`[data-brohn-event="open_dataset"][data-brohn-value='"${fixture.dataset.id}"']`).click();await expect(page.locator('#linked_import')).toBeVisible();await idle();}
async function history(){const summary=page.getByText('Saved linked reviews',{exact:true});if(!await summary.evaluate(n=>n.parentElement.open))await summary.click();
  await expect(page.locator('#linked_history_summary')).toContainText('saved views.');await idle('#linked_history_rows');}
async function historyIds(){return page.locator('[data-brohn-event="linked_history_open"]').evaluateAll(nodes=>nodes.map(n=>JSON.parse(n.getAttribute('data-brohn-value')).id));}
async function older(){const before=await historyIds();await button('Older saved reviews').focus();await page.keyboard.press('Enter');
  await expect.poll(historyIds).not.toEqual(before);await expect(page.locator('#linked_history_summary')).toBeFocused();await idle('#linked_history_rows');}
async function oldest(){while(!(await page.locator('#linked_history_summary').textContent()).includes('At oldest page.'))await older();}
async function latest(){await button('Show latest reviews').click();await expect(page.locator('#linked_history_summary')).toContainText('Showing 1 to 20');await idle('#linked_history_rows');}
async function restored(saved){const b=saved.body,s=b.request.selection;await expect(page.locator('#linked_import')).toHaveValue(b.request.imported.id);
  for(const[id,value]of Object.entries({linked_start:s.start_s,linked_end:s.end_s,linked_cursor:s.cursor_s,linked_clock_rationale:s.clock_rationale}))await expect(page.locator('#'+id)).toHaveValue(value);
  await expect(page.locator('#linked_confirm')).toBeChecked();
  const wanted=b.request.tracks.map(t=>({stream_id:t.stream.id,channel_id:t.channel_id}));
  await expect.poll(async()=>page.locator('#linked_tracks input:checked').evaluateAll(nodes=>nodes.map(n=>JSON.parse(n.value)))).toEqual(wanted);
  await idle();if(b.result.status==='requires_alignment')await expect(page.locator('#linked_review_result')).toContainText('These tracks require alignment');
  else await expect(page.locator('#linked_review_result')).toContainText('Linked source timeline');
}
async function reopen(saved){await history();await oldest();const command=page.locator(`[data-brohn-event="linked_history_open"][data-brohn-value*="${saved.id}"]`);
  await expect(command).toHaveCount(1);await command.focus();await page.keyboard.press('Enter');await restored(saved);}
async function download(label,name){const link=page.getByRole('link',{name:label,exact:true});await expect(link).toHaveAttribute('href',/session\//);const pending=page.waitForEvent('download');await link.click();const d=await pending;assert.equal(await d.failure(),null);const file=path.join(folder,name);await d.saveAs(file);return fs.readFile(file);}
async function exactExports(saved,prefix){const manifest=JSON.parse(await download('Download linked source manifest',prefix+'.json'));assert.deepEqual(manifest,saved.body);
  if(saved.body.csv_object)assert.equal(sha256(await download('Download complete linked CSV',prefix+'.csv')),saved.body.csv_object.hash);return manifest;}
async function scan(label,anchor,narrow=true){await page.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});await idle();await page.locator(anchor).scrollIntoViewIfNeeded();
  const violations=(await new tools.AxeBuilder({page}).withTags(['wcag2a','wcag2aa','wcag21aa','wcag22aa']).analyze()).violations;
  const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);scans.push({label,violations:violations.length,overflow});await write(label+'-axe.json',violations);
  await page.screenshot({path:path.join(folder,label+'.png')});check(label+': accessible current view without page overflow',!violations.length&&!overflow);
  await page.setViewportSize({width:1440,height:1080});}
async function form(){return page.evaluate(()=>({import_id:document.getElementById('linked_import').value,
  tracks:[...document.querySelectorAll('#linked_tracks input:checked')].map(n=>n.value),
  start:document.getElementById('linked_start').value,end:document.getElementById('linked_end').value,cursor:document.getElementById('linked_cursor').value,
  rationale:document.getElementById('linked_clock_rationale').value,confirmed:document.getElementById('linked_confirm').checked}));}
try{
  helper('setup');fixture=JSON.parse(await fs.readFile(path.join(folder,'fixture.json')));const before=JSON.parse(await fs.readFile(path.join(folder,'before.json')));
  check('Only65 explicitly synthetic metadata histories are added to copied original fixture; original actual source/results are retained');
  await start();browser=await tools.playwright.chromium.launch({executablePath:request.browser_executable,headless:true});context=await browser.newContext({viewport:{width:1440,height:1080}});page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
  await page.goto('http://127.0.0.1:3973/');await openDataset();await history();const disclosure=page.getByText('Saved linked reviews',{exact:true});
  await disclosure.evaluate(n=>n.parentElement.setAttribute('data-qa-identity','mounted-history'));
  const seen=[];for(;;){seen.push(...await historyIds());if((await page.locator('#linked_history_summary').textContent()).includes('At oldest page.'))break;await older();}
  assert.equal(seen.length,65+fixture.original_count);assert.equal(new Set(seen).size,seen.length);assert.ok(seen.indexOf(fixture.first.id)>=40);
  assert.equal(await disclosure.evaluate(n=>n.parentElement.getAttribute('data-qa-identity')),'mounted-history');assert.equal(await disclosure.evaluate(n=>n.parentElement.open),true);
  await button('Older saved reviews').focus();await page.keyboard.press('Enter');await expect(page.locator('#linked_history_summary')).toContainText('You are at the oldest');await expect(page.locator('#linked_history_summary')).toBeFocused();
  check('All pages beyond40 retain one mounted open disclosure, unique rows, exact oldest source and keyboard status focus at boundary');
  await scan('oldest-history-390','#linked_history_summary');await scan('oldest-history-desktop','#linked_history_summary',false);
  await reopen(fixture.first);await exactExports(fixture.first,'first-old-view');await scan('old-view-390','#linked_review_result');
  assert.deepEqual((await snapshot()).jobs,before.jobs);check('Original actual78-row view restores exact controls and complete CSV/manifest without processing');
  await reopen(fixture.empty);await exactExports(fixture.empty,'old-empty');await expect(page.locator('#linked_review_result')).toContainText('No observations in this window.');
  await reopen(fixture.unsupported);await expect(page.locator('#linked_review_result svg')).toHaveCount(0);await expect(page.getByRole('link',{name:'Download complete linked CSV',exact:true})).toHaveCount(0);
  check('Historical empty and unsupported reset views preserve their original support state and cannot invent traces');
  await reopen(fixture.wide);await expect(page.locator('#linked_review_result')).toContainText('Showing 101 to 158 of 158');await exactExports(fixture.wide,'old-page2');
  // Keep exact lexemes and an unapplied draft while a genuine importer finishes.
  await page.locator('#linked_start').fill('0.000');await page.locator('#linked_end').fill('7.5000');await page.locator('#linked_cursor').fill('1.250000001');
  await page.locator('#linked_clock_rationale').fill('Original draft retained while another real preservation job arrives; physical synchronization remains unverified.');
  await page.locator('#linked_confirm').uncheck();await page.locator('#linked_tracks input:checked').last().uncheck();
  await expect(page.locator('#linked_review_result')).toContainText('selection changed');const draft=await form();await write('draft-before.json',draft);
  helper('queue-import');const job=JSON.parse(await fs.readFile(path.join(folder,'second-import-job.json')));
  let after;await until(async()=>{after=await snapshot();const j=after.jobs.find(x=>x.id===job.id);assert.ok(!['failed','cancelled'].includes(j.status),JSON.stringify(j.error));return j.status==='succeeded';},180000);
  const added=after.imports.filter(i=>!before.imports.some(old=>old.id===i.id));assert.equal(added.length,1);const second=added[0];
  await expect(page.locator('#linked_import option')).toHaveCount(before.imports.length+1);await idle();assert.deepEqual(await form(),draft);await write('draft-after.json',await form());
  for(const kind of['datasets','imports','streams'])for(const old of before[kind])assert.deepEqual(after[kind].find(x=>x.id===old.id),old);
  assert.equal(after.jobs.length,before.jobs.length+1);assert.equal(second.body.source.hash,fixture.dataset.body.source.hash);
  check('Actual validated importer creates a new preserved import while exact current import/tracks/window/cursor/rationale/confirmation draft survives');
  await page.locator('#linked_import').selectOption(second.id);await expect.poll(async()=>page.locator('#linked_tracks input').evaluateAll(ns=>ns.map(n=>JSON.parse(n.value).stream_id).sort())).toEqual([...second.body.stream_ids].sort());
  await page.locator('#linked_tracks input').nth(0).check();await page.locator('#linked_tracks input').nth(1).check();
  await reopen(fixture.wide);await expect(page.locator('#linked_review_result')).toContainText('Showing 101 to 158 of 158');await exactExports(fixture.wide,'cross-import-restored');
  check('Old historical selection restores its different import, exact channels, decimal window and100-row offset after a genuinely processed second import');
  await scan('cross-import-restored-390','#linked_review_result');const baseline=await snapshot();await write('before-restart.json',baseline);
  await context.close();await stop();await start();context=await browser.newContext({viewport:{width:1440,height:1080}});page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
  await page.goto('http://127.0.0.1:3973/');await openDataset();await reopen(fixture.first);await exactExports(fixture.first,'restarted-old-view');
  const final=await snapshot();assert.deepEqual(final,baseline);assert.deepEqual(errors,[]);await write('final-snapshot.json',final);
  check('Full supervisor/browser restart reopens exact old source and exports with unchanged original records and zero new review/scoring jobs');
}catch(error){failure=error;await page?.screenshot({path:path.join(folder,'failure.png'),fullPage:true}).catch(()=>{});await write('failure.json',{error:error.stack,checks,scans,errors,text:await page?.locator('body').innerText().catch(()=>'(closed)')});}
finally{await browser?.close();await stop().catch(e=>failure??=e);const end=await sourceHashes(project);await write('source-end.json',end);
  try{assert.deepEqual(end,sourceStart);assert.deepEqual(await tree(original),originalHashes);assert.equal(sha256(await fs.readFile(request.configuration_path)),configurationHash);
    for(const[f,h]of Object.entries(ownHashes))assert.equal(sha256(await fs.readFile(f)),h);check('All source/configuration/original fixture bytes and executed harness identity remain unchanged');}catch(e){failure??=e;}
  await write('results.json',{schema:'brohn-linked-history-browser-result/1.0',status:failure?'failed':'passed',checks,scans,cycles,errors,failure:failure?.stack,
    original_workspace:original,ports:{researcher:3973,participant:3974},source_hashes:sourceStart,fixture_scope:'65 synthetic metadata histories; original actual saved views; exactly one fresh normalise_dataset job triggered by QA through existing validated API while editing. No UI upload or new scientific score claimed.'});
  console.log(JSON.stringify({status:failure?'failed':'passed',checks:checks.length,scans:scans.length,folder}));}
if(failure){console.error(failure);process.exitCode=1;}
