// Original synthetic XDF and typed bundles through the actual researcher UI.
import {importTransferredSource} from './helpers/source-import.mjs';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const output=path.resolve('../../work/test-runs/brohn-interchange-ui-evidence');await fs.mkdir(output,{recursive:true});
const generate=spawnSync(path.resolve('../../work/tooling/methods-venv/Scripts/python.exe'),['-c',"import importlib.util,json,copy,sys;from pathlib import Path;s=importlib.util.spec_from_file_location('fixture','tests/workers/interchange.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m);p=Path(sys.argv[1]);raw=m.xdf_fixture();(p/'original.xdf').write_bytes(raw);(p/'truncated.xdf').write_bytes(raw[:-2]);b=m.bundle_fixture();e=copy.deepcopy(b['streams'][1]);e.update(id='empty',name='Declared empty stream',samples=[]);b['streams'].append(e);(p/'original-bundle.json').write_text(json.dumps(b))",output],{encoding:'utf8',windowsHide:true});assert.equal(generate.status,0,generate.stderr);
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1080}});let page=await context.newPage();
const checks=[],errors=[],violations=[],prefix=`Original streams UI ${Date.now()}`;const watch=p=>p.on('pageerror',e=>errors.push(e.message));watch(page);
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log(`PASS ${label}`);};
async function select(id,label){const input=page.locator(`#${id}-selectized`);await input.click();await input.fill(label);await input.press('Enter');}
async function version(revision){const input=page.locator('#multistream_import_id-selectized');await input.click();await input.fill(`Source revision ${revision}`);await page.locator('.selectize-dropdown:visible .option').filter({hasText:new RegExp(`^Source revision ${revision}\\b`)}).click();await expect(page.locator('#multistream_catalog')).toContainText(`source revision ${revision}`);}
async function download(label,name){const link=page.getByRole('link',{name:label,exact:true});await expect(link).toHaveAttribute('href',/session\/.*download\//);const pending=page.waitForEvent('download');await link.click();const d=await pending;assert.equal(await d.failure(),null);const file=path.join(output,name);await d.saveAs(file);return file;}
async function json(label,name){return JSON.parse(await fs.readFile(await download(label,name),'utf8'));}
async function jsonl(label,name){const text=await fs.readFile(await download(label,name),'utf8');return text.split(/\r?\n/).filter(Boolean).map(line=>JSON.parse(line));}
async function axe(label,narrow=false){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&!document.querySelector('.recalculating'));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);await page.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});const a=(await new AxeBuilder({page}).analyze()).violations;await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(a,null,2));await page.screenshot({path:path.join(output,`${label}.png`),fullPage:true});if(a.length)violations.push({label,rules:a.map(v=>v.id)});else check(true,`${label}: no automated accessibility violations`);check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`${label}: no page overflow`);await page.setViewportSize({width:1440,height:1080});}
async function upload(file,title,origin='Synthetic example'){await page.getByRole('button',{name:'Data library',exact:true}).click();await page.getByLabel('Dataset name',{exact:true}).fill(title);await select('dataset_origin',origin);await select('dataset_modality','Multistream recording');await importTransferredSource(page,path.join(output,file));await page.getByRole('heading',{name:'One recording, every source stream',exact:true}).waitFor();}
async function preserve(notes){await page.getByLabel('Where did this recording come from?',{exact:true}).fill(notes);await page.getByLabel('Preserve original clocks and recorded corrections without applying synchronization',{exact:true}).check();await page.getByRole('button',{name:'Preserve streams',exact:true}).click();}
const notes='Original generated QA streams only; no device or participant observations. Retain irregular source time, corrections, sample order, missing states and channel units unchanged.';
try{
 await page.goto('http://127.0.0.1:3851/');await page.getByRole('heading',{name:'Your next discovery starts here.',exact:true}).waitFor();
 await upload('original.xdf',`${prefix} XDF`);await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);check(true,'A newly retained multistream source renders its empty processing state without an R output error');const raw=await fs.readFile(path.join(output,'original.xdf'));
 check(hash(await fs.readFile(await download('Download original recording','downloaded-original.xdf')))===hash(raw),'Original XDF download preserves every source byte before stream extraction');
 await page.getByRole('button',{name:'Preserve streams',exact:true}).click();await expect(page.locator('#platform_error')).toContainText('Confirm the original-clock preservation policy');check(true,'Clock preservation must be explicitly confirmed before extraction');
 await page.getByLabel('Preserve original clocks and recorded corrections without applying synchronization',{exact:true}).check();await page.getByRole('button',{name:'Preserve streams',exact:true}).click();await expect(page.locator('#platform_error')).toContainText(/Describe where this (multistream )?recording came from/);check(true,'Recording provenance is required without discarding the saved raw source');
 await axe('source-declaration');await axe('source-declaration-narrow',true);await preserve(notes);
 await page.getByRole('heading',{name:'Preserved stream catalog',exact:true}).waitFor({timeout:90000});
 const first=await json('Download stream manifest','xdf-manifest.json'),imported=first.stream_import;
 check(imported.stream_count===3&&imported.sample_count===12&&imported.source.hash===hash(raw),'Actual XDF child import retains all3 streams/12rows and the exact original source hash');
 check(imported.manifest.quality.synchronized===false&&imported.manifest.streams.map(s=>s.id).join(',')==='xdf-7,xdf-2,xdf-9','Source stream order is retained without claiming synchronization');
 await select('multistream_stream_id','Original EEG');const eeg=await jsonl('Download complete data (JSONL)','eeg.jsonl');
 check(eeg.map(r=>r.source_timestamp).join(',')==='10.0,10.125,10.25,11.0,5.0,5.125','Actual EEG download preserves original clock reversal and declared timestamp reconstruction');
 check(eeg[3].values.channel_1===null&&eeg[3].value_states.channel_1==='nan'&&eeg[5].value_states.channel_1==='positive_infinity','Missing and nonfinite source samples retain their states without zero substitution');
 const clock=await jsonl('Download clock and metadata evidence','eeg-clock.jsonl'),offsets=clock.filter(r=>r.type==='clock_offset');
 check(offsets.length===3&&offsets[2].offset_s==='6.0'&&offsets.every(r=>r.applied===false),'All three recorded clock corrections are downloadable and explicitly unapplied');
 const csv=await fs.readFile(await download('Download CSV','eeg.csv'),'utf8');check(csv.includes('state_channel_1')&&csv.includes('source_timestamp'),'CSV exposes source time and missing-state columns');await axe('eeg-stream');await axe('eeg-stream-narrow',true);
 await select('multistream_stream_id','Original markers');const markers=await jsonl('Download complete data (JSONL)','markers.jsonl');check(markers.map(r=>r.values.channel_1).join('|')==='control||test|restart','Marker download retains empty text and coincident source order separately from signals');
 await select('multistream_stream_id','Original counter');const counters=await jsonl('Download complete data (JSONL)','counter.jsonl');check(counters.map(r=>r.values.channel_1).join(',')==='9007199254740993,-9007199254740993','Large signed64-bit values survive the full UI download exactly');
 await expect(page.locator('#multistream_stream_detail')).toContainText('No unit was declared');check(true,'Unknown channel units stay visibly uncalibrated');
 check(await page.getByRole('button',{name:'Open report',exact:true}).count()===0,'Preserving recorded streams does not fabricate a scientific report');
 const amended=`${notes} Later provenance clarification.`;await page.getByLabel('Where did this recording come from?',{exact:true}).fill(amended);await page.getByRole('button',{name:'Save notes and preserve streams',exact:true}).click();
 await expect(page.locator('#multistream_progress .brohn-badge').filter({hasText:/^Streams preserved$/})).toHaveCount(2,{timeout:90000});
 await version(imported.dataset_revision+1);const latest=await json('Download stream manifest','xdf-amended-manifest.json');
 check(latest.stream_import.id!==imported.id&&latest.stream_import.source.hash===imported.source.hash&&latest.stream_import.manifest.origin_statement===amended,'Source-note amendment creates a new preserved version with the same original bytes');
 await version(imported.dataset_revision);const earlier=await json('Download stream manifest','xdf-earlier-reopened.json');check(JSON.stringify(earlier)===JSON.stringify(first),'Earlier stream manifest remains exactly unchanged after source-note amendment');

 await upload('original-bundle.json',`${prefix} bundle`,'Live study recording');await preserve(notes);await page.getByRole('heading',{name:'Preserved stream catalog',exact:true}).waitFor({timeout:90000});
 const bundle=(await json('Download stream manifest','bundle-manifest.json')).stream_import;
 check(bundle.origin==='mixed'&&bundle.raw_origin==='live'&&bundle.manifest.streams.every(s=>s.origin==='sample'),'Source-declared sample streams cannot be upgraded by a conflicting live import choice');
 await expect(page.locator('#multistream_catalog')).toContainText('source and import declarations differ');
 await select('multistream_stream_id','Original EDA');const analog=await jsonl('Download complete data (JSONL)','eda.jsonl');
 check(analog[0].source_timestamp==='9007199254740993'&&analog[1].time_since_segment_start_s==='0.100000000'&&analog[1].values.counter==='9007199254740994','Bundle nanosecond clocks, elapsed arithmetic and large counters remain exact');
 check(analog[0].identity.participant_id==='p1'&&analog[3].identity.participant_id==='p2'&&analog[0].segment_id!==analog[3].segment_id,'Source participant/visit boundaries survive preservation rather than merging rows');
 await select('multistream_stream_id','Original typed markers');const typed=await jsonl('Download complete data (JSONL)','typed-markers.jsonl');check(typed[0].values.condition===0&&typed[0].values.answer===false&&typed[1].values.answer===true&&typed[2].values.answer===null,'Typed numeric0, booleanfalse/true and missing markers remain distinct');await axe('typed-markers-narrow',true);
 await select('multistream_stream_id','Declared empty stream');check((await jsonl('Download complete data (JSONL)','empty.jsonl')).length===0,'Declared empty stream has a real zero-row artifact');await expect(page.locator('#multistream_stream_detail')).toContainText('no samples');
 check((await jsonl('Download clock and metadata evidence','empty-evidence.jsonl')).length>0,'Empty stream metadata remains downloadable');

 await upload('truncated.xdf',`${prefix} truncated`);await preserve(notes);await expect(page.locator('#multistream_progress .brohn-badge').filter({hasText:/^failed$/})).toHaveCount(1,{timeout:90000});
 await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);check(await page.getByRole('heading',{name:'Preserved stream catalog',exact:true}).count()===0,'Corrupt XDF fails visibly without publishing a partial stream catalog or R output error');
 check(hash(await fs.readFile(await download('Download original recording','failed-original.xdf')))===hash(await fs.readFile(path.join(output,'truncated.xdf'))),'Failed import retains its exact original source for review');
 await page.getByRole('button',{name:'Retry saved source',exact:true}).first().click();await expect(page.locator('#multistream_progress .brohn-badge').filter({hasText:/^failed$/})).toHaveCount(2,{timeout:90000});await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);check(true,'Retry creates a separate visible attempt and retains the prior failed attempt without an R output error');

 const fresh=await browser.newContext({viewport:{width:1440,height:1080}});page=await fresh.newPage();watch(page);await page.goto('http://127.0.0.1:3851/');await page.getByRole('button',{name:'Data library',exact:true}).click();await page.getByLabel('Search datasets',{exact:true}).fill(`${prefix} XDF`);
 await page.locator(`[data-brohn-event="open_dataset"][data-brohn-value='"${imported.dataset_id}"']`).click();await page.getByRole('heading',{name:'Preserved stream catalog',exact:true}).waitFor();await version(imported.dataset_revision);
 check(JSON.stringify(await json('Download stream manifest','new-session-earlier-manifest.json'))===JSON.stringify(first),'A fresh researcher session reopens exact historical stream evidence');
 await expect(page.getByLabel('Where did this recording come from?',{exact:true})).toHaveValue(amended);check(true,'Latest curation notes persist alongside the older selected stream version');
 check(errors.length===0,`No browser exceptions: ${errors.join(';')}`);check(violations.length===0,`All interchange accessibility checks clear: ${JSON.stringify(violations)}`);
 await fs.writeFile(path.join(output,'results.json'),JSON.stringify({origin:'original_synthetic',checks,dataset_id:imported.dataset_id,import_id:imported.id},null,2));console.log(JSON.stringify({checks:checks.length,output}));
}catch(error){await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,errors,violations,text:await page.locator('body').innerText()},null,2));throw error;}finally{await browser.close();}
