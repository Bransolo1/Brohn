// Prepared externally; launch only after all original fixture services are terminal
// and the parent announces the merged-source freeze. No scientific worker runs.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {spawn,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const requestPath=path.resolve(process.argv[2]||'');
const requestBytes=await fs.readFile(requestPath);
const request=JSON.parse(requestBytes.toString('utf8').replace(/^\uFEFF/,''));
assert.equal(request.schema,'brohn-report-results-first-request/1.0');
const absolute=(value,label)=>{assert.equal(typeof value,'string',label);assert.ok(path.isAbsolute(value),`${label} must be absolute`);return path.resolve(value);};
const project=absolute(request.project,'project');
assert.equal(await fs.realpath(path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..')),await fs.realpath(project),'Run the harness installed in the declared project tests directory');
process.chdir(project);
const require=createRequire(path.join(project,'package.json'));
const {chromium,expect}=require('@playwright/test');
const AxeBuilder=require('@axe-core/playwright').default;
const output=absolute(request.output,'output');
assert.ok(path.basename(output).startsWith('brohn-results-first-'));
const sourceGnat=absolute(request.references.gnat,'GNAT reference');
const sourceAudio=absolute(request.references.audio,'audio reference');
const sourceLong=absolute(request.references.combined,'combined reference');
const overlap=(a,b)=>{const x=a.toLowerCase(),y=b.toLowerCase();return x===y||x.startsWith(y+path.sep)||y.startsWith(x+path.sep);};
for(const source of[project,sourceGnat,sourceAudio,sourceLong])assert.ok(!overlap(output,source),'Output must not overlap project or original source');
const port=request.port;assert.ok(Number.isInteger(port)&&port>=1024&&port<65535);
const rscript=absolute(request.runtime.rscript,'Rscript');
const fixture=path.join(project,'tests/fixtures/researcher-report-results-first.R');
const env={...process.env,LC_ALL:'C',R_LIBS_USER:absolute(request.runtime.r_library,'R library'),
 BROHN_PUBLICATION_PYTHON:absolute(request.runtime.publication_python,'publication Python'),
 BROHN_PUBLICATION_NATIVE_MANIFEST:absolute(request.runtime.publication_native_manifest,'publication native manifest')};
const chrome=absolute(request.runtime.chrome,'Chrome');
for(const file of[rscript,fixture,env.BROHN_PUBLICATION_PYTHON,env.BROHN_PUBLICATION_NATIVE_MANIFEST,chrome])assert.ok((await fs.stat(file)).isFile(),file);
assert.ok((await fs.stat(env.R_LIBS_USER)).isDirectory());
await fs.mkdir(output,{recursive:false});
const hash=b=>createHash('sha256').update(b).digest('hex');
async function sourceHashes(){const result={};for(const root of['R','www'])for(const name of await fs.readdir(root,{recursive:true})){
 const file=path.join(root,name);if((await fs.stat(file)).isFile())result[file.replaceAll('\\','/')]=hash(await fs.readFile(file));}return result;}
const startHashes=await sourceHashes();
let continuation=null;
if(request.continue_from){const folder=absolute(request.continue_from,'continuation');
 const receipt=await fs.readFile(path.join(folder,'failure.json'));const prior=JSON.parse(receipt);
 assert.equal(prior.checks.length,75);assert.equal(prior.scans.length,10);assert.match(prior.error,/combined-initial-mobile: readable first numeric result/);
 const delta=Object.keys(startHashes).filter(k=>startHashes[k]!==prior.source_hashes[k]);assert.deepEqual(delta,['R/platform-data-views.R']);
 for(const kind of['gnat','audio']){const verified=JSON.parse(await fs.readFile(path.join(folder,`brohn-results-first-${kind}`,'verified.json'),'utf8'));assert.equal(verified.passed,true);assert.equal(verified.new_jobs,0);}
 continuation={folder,receipt_sha256:hash(receipt),prior_checks:prior.checks,prior_scans:prior.scans,source_delta:delta,
  scope:'Joined continuation after metadata-only report layout change. Prior GNAT/audio detailed explorer, download revocation and cold restart evidence retained; current first screens, anchors and exact exports repeated. Combined route completed here.'};}
const checks=[],scans=[],errors=[],processes=[],cases=[],timings=[];
const write=(name,value)=>fs.writeFile(path.join(output,name),JSON.stringify(value,null,2));
await write('source-start.json',startHashes);
await write('configured-request.json',{...request,request_file_sha256:hash(requestBytes)});
await write('harness-source.json',Object.fromEntries(await Promise.all([fileURLToPath(import.meta.url),fixture].map(async file=>[file,hash(await fs.readFile(file))]))));
if(continuation)await write('continuation.json',continuation);
await write('prerequisites.json',{scope:'Reopen original saved reports on copied terminal workspaces; no new scientific source/report/job.',
 required:['Parent confirms original GNAT07 and all reference services terminal before launch.','Parent merges Results/Explore/Evidence R and CSS plus both saved-history candidates, then freezes source.',
 'Installed Chrome, restored R library, native publication guard, existing npm Playwright and axe dependencies.'],sources:{sourceGnat,sourceAudio,sourceLong},port,
 pending:'This file alone does not establish fulfilled prerequisites or a completed browser journey.'});
function helper(mode,folder,...rest){const p=spawnSync(rscript,['--vanilla',fixture,mode,folder,...rest],{env,windowsHide:true,encoding:'utf8',maxBuffer:8*1024**2});
 assert.equal(p.status,0,p.stderr||p.stdout);return p.stdout;}
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log('PASS',label);};
let browser,context,page,current;
async function startCase(kind,source){const folder=path.join(output,`brohn-results-first-${kind}`);helper('prepare',folder,source,kind,String(port));
 const config=JSON.parse(await fs.readFile(path.join(folder,'fixture.json'),'utf8'));
 const entry={kind,folder,config,log:'',child:null};cases.push(entry);current=entry;
 await startServer(entry);return entry;}
async function startServer(entry){await fs.rm(path.join(entry.folder,'stop.request'),{force:true});
 const child=spawn(rscript,['--vanilla',fixture,'serve',entry.folder],{env,windowsHide:true});entry.child=child;processes.push(entry);
 child.stdout.on('data',b=>entry.log+=b);child.stderr.on('data',b=>entry.log+=b);
 await expect.poll(async()=>{if(child.exitCode!==null)throw Error(entry.log);try{return(await fetch(`http://127.0.0.1:${port}/`)).ok;}catch{return false;}},{timeout:60000}).toBe(true);}
async function stopServer(entry){if(entry.child?.exitCode===null){await fs.writeFile(path.join(entry.folder,'stop.request'),'Stop only this owned report-presentation service.');
 await expect.poll(()=>entry.child.exitCode!==null,{timeout:30000}).toBe(true);}await fs.writeFile(path.join(entry.folder,'researcher.log'),entry.log);}
async function idle(){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&![...document.querySelectorAll('.recalculating')].some(e=>e.getClientRects().length));
 await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);}
const button=name=>page.getByRole('button',{name,exact:true});
const section=name=>page.locator(`section.brohn-report-section[id$="-${name}"]`);
async function openReport(cfg){await page.goto(`http://127.0.0.1:${port}/`);
 if(cfg.dataset_id){await button('Data library').click();await page.getByLabel('Search datasets',{exact:true}).fill(cfg.dataset_title);
 await page.locator(`[data-brohn-event="open_dataset"][data-brohn-value='"${cfg.dataset_id}"']`).click();}
 else{await button('Studies').click();await page.getByLabel('Search studies',{exact:true}).fill(cfg.study_title);
 await page.locator(`[data-brohn-event="brohn_open_study"][data-brohn-value='"${cfg.study_id}"']`).click();await expect(page.getByRole('heading',{name:cfg.study_title,exact:true})).toBeVisible();await button('Results').click();}
 await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${cfg.report_id}"']`).click();
 await expect(page.locator('.brohn-report-page > .brohn-page-heading h1')).toHaveText(cfg.report_title,{timeout:30000});await expect(page.locator('#report_download')).toHaveAttribute('href',/session\//);await idle();}
async function dismissReady(){const dismiss=page.getByRole('button',{name:'Dismiss notification',exact:true});if(await dismiss.count()){await dismiss.first().focus();await page.keyboard.press('Space');await expect(dismiss).toHaveCount(0);}}
async function inspect(label,width,requireFirstValue=true){await page.setViewportSize({width,height:width<500?844:1080});await idle();await dismissReady();await page.evaluate(()=>window.scrollTo({top:0,behavior:'instant'}));
 const geometry=await page.locator('.brohn-report-page').evaluate(root=>{
  const visible=n=>{for(let p=n.parentElement;p;p=p.parentElement)if(p.tagName==='DETAILS'&&!p.open&&!p.querySelector(':scope > summary')?.contains(n))return false;
   return n.getBoundingClientRect().height>1&&getComputedStyle(n).visibility!=='hidden'&&n.checkVisibility({checkOpacity:true,checkVisibilityCSS:true});};
  const rect=n=>({tag:n.tagName,id:n.id,class:n.className,title:n.querySelector('h1,h2,h3')?.textContent||n.textContent.slice(0,70),...n.getBoundingClientRect().toJSON()});
  const flatten=n=>getComputedStyle(n).display==='contents'?[...n.children].flatMap(flatten):[n];
  const groups=[{name:'page',nodes:[...root.children].flatMap(flatten).filter(visible)}];
  for(const s of root.querySelectorAll('.brohn-report-section'))groups.push({name:s.id,nodes:[...s.children].flatMap(flatten).filter(visible)});
  const layout=groups.map(g=>({name:g.name,rows:g.nodes.map((n,i)=>({...rect(n),gap:i?n.getBoundingClientRect().top-g.nodes[i-1].getBoundingClientRect().bottom:0}))}));
  const results=root.querySelector('[id$="-results"]'),explore=root.querySelector('[id$="-explore"]'),evidence=root.querySelector('[id$="-evidence"]');
  const prominent=[...results.querySelectorAll('.brohn-result-number')].filter(visible).find(n=>/[0-9]/.test(n.textContent));
  const numeric=prominent||[...results.querySelectorAll('tbody td')].filter(visible).find(n=>/^\s*[+-]?(?:\d|\.\d)/.test(n.textContent));
  return{layout,sections:[results,explore,evidence].map(rect),first_value:numeric?{...rect(numeric),text:numeric.textContent,font_px:parseFloat(getComputedStyle(numeric).fontSize)}:null,
   first_value_in_view:!!numeric&&numeric.getBoundingClientRect().top>=0&&numeric.getBoundingClientRect().bottom<=innerHeight,
   viewport:{width:innerWidth,height:innerHeight},overflow:document.documentElement.scrollWidth>innerWidth+1,
   primary_actions:[...root.querySelectorAll(':scope > .brohn-page-heading .brohn-page-actions a')].map(n=>n.textContent),
   ids:[...root.querySelectorAll('[id]')].map(n=>n.id)};});
 const violations=(await new AxeBuilder({page}).analyze()).violations;
 await write(`${label}-geometry.json`,geometry);await write(`${label}-axe.json`,violations);
 await fs.writeFile(path.join(output,`${label}.html`),await page.content());
 await page.screenshot({path:path.join(output,`${label}-viewport.png`)});await page.screenshot({path:path.join(output,`${label}-full.png`),fullPage:true});
 scans.push({label,width,violations:violations.length,overflow:geometry.overflow,first_value:geometry.first_value,first_value_in_view:geometry.first_value_in_view});
 check(violations.length===0&&!geometry.overflow,`${label}: automated accessibility and page reflow`);
 check(new Set(geometry.ids).size===geometry.ids.length&&geometry.primary_actions.length===1&&geometry.primary_actions[0]==='Download report',`${label}: unique mounted controls and one primary report action`);
 check(geometry.sections[0].top<geometry.sections[1].top&&geometry.sections[1].top<geometry.sections[2].top,`${label}: actual results precede tools and evidence`);
 // Existing minimum/maximum spacing is retained inside the new sections.
 for(const group of geometry.layout)for(const row of group.rows.slice(1))assert.ok(row.gap>=15&&row.gap<=40,`${label} ${group.name} gap ${row.gap} before ${row.title}`);
 check(true,`${label}: populated sibling spacing remains15–40px without empty-output gaps`);
 if(requireFirstValue)check(geometry.first_value_in_view&&geometry.first_value.font_px>=14,`${label}: readable first numeric result is in the initial viewport`);
 return geometry;}
async function anchor(name){const nav=page.getByRole('navigation',{name:'Report sections',exact:true});const target=section(name.toLowerCase());
 const link=nav.getByRole('link',{name,exact:true});await link.focus();await page.keyboard.press('Enter');await expect(target).toBeFocused();
 const expected=await target.evaluate(s=>{const q='a[href],button,input,select,textarea,summary,[tabindex]';
 const n=[...s.querySelectorAll(q)].find(n=>n.tabIndex>=0&&!n.disabled&&n.getAttribute('aria-disabled')!=='true'&&n.getClientRects().length&&getComputedStyle(n).visibility!=='hidden');
 return n?{id:n.id,tag:n.tagName,text:n.textContent,value:n.value}:null;});assert.ok(expected);
 await page.keyboard.press('Tab');const actual=await page.evaluate(()=>{const n=document.activeElement;return{id:n.id,tag:n.tagName,text:n.textContent,value:n.value};});
 assert.deepEqual(actual,expected);check(true,`${current.kind}: native ${name} anchor focuses its labelled section and next Tab reaches its first available control`);}
async function backToResults(from){const origin=section(from);const target=section('results');await origin.getByRole('link',{name:'Back to results',exact:true}).focus();await page.keyboard.press('Enter');await expect(target).toBeFocused();
 check(true,`${current.kind}: Back to results retains native focus and the current report`);}
async function download(id,filename){const link=page.locator('#'+id);await expect(link).toHaveAttribute('href',/session\//);const pending=page.waitForEvent('download');await link.click();const d=await pending;
 assert.equal(await d.failure(),null);const file=path.join(current.folder,filename);await d.saveAs(file);return await fs.readFile(file);}
async function exportOriginal(cfg){await anchor('Evidence');const actualJson=await download('report_download','downloaded-original.json');
 assert.deepEqual(JSON.parse(actualJson),JSON.parse(await fs.readFile(path.join(current.folder,'original-report.json'),'utf8')));
 const collected={report_download:actualJson,report_html:await download('report_html','downloaded-original.html'),report_csv:await download('report_csv','downloaded-observations.csv')};
 assert.equal(hash(collected.report_html),hash(await fs.readFile(path.join(current.folder,'expected-report.html'))));
 assert.equal(hash(collected.report_csv),hash(await fs.readFile(path.join(current.folder,'expected-observations.csv'))));
 if(cfg.kind==='gnat'){collected.report_task_csv=await download('report_task_csv','downloaded-task-scores.csv');assert.equal(hash(collected.report_task_csv),hash(await fs.readFile(path.join(current.folder,'expected-task-scores.csv'))));}
 for(const[id,source]of Object.entries(cfg.prior_exports||{}))assert.equal(hash(collected[id]),hash(await fs.readFile(source)),`${cfg.kind} prior ${id}`);
 check(true,`${cfg.kind}: actual HTML/JSON/CSV downloads preserve exact saved content and retained prior exports`);await backToResults('evidence');return collected;}
async function activate(){await anchor('Explore');const measured={kind:current.kind,started_at:new Date().toISOString(),ceiling_ms:30000};timings.push(measured);const started=performance.now();if(current.kind==='gnat'){
 await button('Open task plots').click();await expect(page.locator('#task_plot_source')).toBeVisible({timeout:30000});
 await page.waitForFunction(()=>{const field=document.getElementById('task_plot_catalog_identity');return field&&Shiny.shinyapp.$inputValues.task_plot_catalog_identity===field.value;});
 measured.catalog_bound_ms=performance.now()-started;const loadStart=performance.now();
 await button('Show complete saved source').click();await expect(page.locator('#task_plot_measure')).toBeVisible({timeout:30000});
 await expect(page.locator('#task_plot_view')).toContainText('384',{timeout:30000});await expect(page.locator('#task_plot_view svg')).toHaveCount(6);measured.complete_source_ms=performance.now()-loadStart;}
 else if(current.kind==='audio'){await button('Review original audio').click();await expect(button('Apply audio window')).toBeVisible({timeout:30000});await expect(page.locator('#audio_review_end')).toHaveValue('3',{timeout:30000});}
 else{const open=page.getByRole('button',{name:'Review paired effects',exact:true});if(await open.count()){await open.click();await expect(page.locator('#paired_plot_controls')).toBeVisible();}}
 await idle();measured.total_ms=performance.now()-started;measured.visible_status=await page.locator('[role="status"],.brohn-alert:visible').allTextContents();await write('readiness-timings.json',timings);
 check(true,`${current.kind}: an originally empty explorer output activates from the unchanged live control`);}
try{
 browser=await chromium.launch({executablePath:chrome,headless:true});context=await browser.newContext({viewport:{width:1440,height:1080},acceptDownloads:true});page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
 for(const[kind,source]of[['gnat',sourceGnat],['audio',sourceAudio],['combined',sourceLong]]){
  const entry=await startCase(kind,source);await openReport(entry.config);await inspect(`${kind}-initial-desktop`,1440);await inspect(`${kind}-initial-mobile`,390);
  if(continuation){await expect(page.locator('.brohn-report-page > .brohn-page-heading')).not.toContainText('Immutable analysis');
   await expect(section('evidence')).toContainText(entry.config.saved_metadata);check(true,`${kind}: original saved metadata is retained exactly in Evidence and removed from the initial heading`);}
  await anchor('Results');await anchor('Explore');await backToResults('explore');await anchor('Evidence');await backToResults('evidence');
  await exportOriginal(entry.config);if(kind!=='combined'&&!continuation){await activate();await inspect(`${kind}-opened-mobile`,390);await inspect(`${kind}-opened-desktop`,1440);}
  if(kind==='audio'&&!continuation){
   const url=new URL(await page.locator('#report_download').getAttribute('href'),page.url()).href;helper('revoke',entry.folder);
   for(let i=0;i<3;i++)assert.ok((await context.request.get(url)).status()>=400);
   const dismiss=page.getByRole('button',{name:'Dismiss notification',exact:true});await expect(dismiss).toHaveCount(1);
   await expect(page.getByRole('heading',{name:'Welcome back to your research.',exact:true})).toBeVisible();const bounds=await dismiss.boundingBox();assert.ok(bounds.width>=44&&bounds.height>=44);
   await dismiss.focus();await page.keyboard.press('Space');await expect(dismiss).toHaveCount(0);await expect(page.locator('#brohn-main')).toBeFocused();
   check(true,'audio: revoked original source refuses old downloads and produces one44px keyboard-dismissible notice');
   helper('restore',entry.folder);await openReport(entry.config);await expect(button('Apply audio window')).toHaveCount(0);await activate();
   check(true,'audio: navigation clears dynamic controls and the original report can reopen after restored fixture authority');
  }
  helper('verify',entry.folder);await stopServer(entry);if(continuation&&kind!=='combined')continue;
  await startServer(entry);await openReport(entry.config);
  assert.deepEqual(JSON.parse(await download('report_download','restart-original.json')),JSON.parse(await fs.readFile(path.join(entry.folder,'original-report.json'),'utf8')));
  check(true,`${kind}: actual cold restart reopens the same immutable report without processing`);helper('verify',entry.folder);await stopServer(entry);
 }
 assert.deepEqual(errors,[]);assert.deepEqual(await sourceHashes(),startHashes);check(true,'All source fingerprints and browser errors remain clean; copied jobs/reports and original fixtures are unchanged');
 await write('results.json',{passed:true,scope:continuation?'Joined source-labelled saved-report acceptance; see continuation for preceding GNAT/audio full-route checks':'Actual current-source saved-report layout/export/focus/restart, no scientific recomputation',continuation,checks,scans,timings,new_jobs:0,source_hashes:startHashes,
 cases:cases.map(c=>({kind:c.kind,folder:c.folder,report_id:c.config.report_id,report_hash:c.config.report_hash})),manual_visual_review:'Required separately; automation measurements and axe are not a visual-review claim.'});
 console.log(JSON.stringify({passed:true,checks:checks.length,scans:scans.length,output}));
}catch(error){await page?.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await write('failure.json',{error:error.stack,checks,scans,timings,errors,visible_status:await page?.locator('[role="status"],.brohn-alert:visible').allTextContents().catch(()=>[]),source_hashes:startHashes});throw error;
}finally{if(current?.config.kind==='audio')helper('restore',current.folder);await browser?.close();for(const entry of cases)await stopServer(entry);}
