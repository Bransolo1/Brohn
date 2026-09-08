// Reopen an actual completed synthetic task and inspect every report export.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {chromium,expect} from '@playwright/test';
const source=path.resolve('../../work/test-runs/brohn-extension-evidence');
const evidence=JSON.parse(await fs.readFile(path.join(source,'results.json'),'utf8'));
const previous=JSON.parse(await fs.readFile(path.join(source,'authored-task-report.json'),'utf8'));
const output=path.resolve('../../work/test-runs/brohn-task-export-evidence');await fs.mkdir(output,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true}),page=await browser.newPage(),checks=[];
const check=(value,label)=>{assert.ok(value,label);checks.push(label);console.log(`PASS ${label}`);};
async function download(label,name){const link=page.getByRole('link',{name:label,exact:true});await expect(link).toHaveAttribute('href',/session\/.*download\//);const pending=page.waitForEvent('download');await link.click();const d=await pending;assert.equal(await d.failure(),null);const file=path.join(output,name);await d.saveAs(file);return file;}
try{
 await page.goto('http://127.0.0.1:3851/');await page.getByRole('button',{name:'Studies',exact:true}).click();
 await page.getByLabel('Search studies',{exact:true}).fill(previous.provenance.design.title);
 await page.locator(`[data-brohn-event="brohn_open_study"][data-brohn-value='"${evidence.study_ids.at(-1)}"']`).click();
 await page.getByRole('button',{name:'Results',exact:true}).click();
 await page.locator(`[data-brohn-event="open_report"][data-brohn-value='"${evidence.task_report_id}"']`).click();
 const report=JSON.parse(await fs.readFile(await download('JSON + provenance','task-report.json'),'utf8'));
 check(JSON.stringify(report)===JSON.stringify(previous),'Existing task report JSON remains unchanged after export improvements');
 const html=await fs.readFile(await download('Download report','task-report.html'),'utf8');
 check(html.includes(report.id)&&html.includes('Original synthetic simple RT')&&html.includes('Mean test response time'),'Standalone task HTML includes report identity and readable task outcome labels');
 const csv=await download('Download observations','task-metrics.csv');
 const decoded=spawnSync(path.resolve('../../work/tooling/methods-venv/Scripts/python.exe'),['-c',"import csv,json,sys;print(json.dumps(list(csv.DictReader(open(sys.argv[1],encoding='utf-8-sig',newline='')))))",csv],{encoding:'utf8',windowsHide:true});assert.equal(decoded.status,0,decoded.stderr);const rows=JSON.parse(decoded.stdout);
 const names=['correct_test_rt_mean','correct_test_rt_median','correct_test_rt_sd','test_first_response_error_rate','test_omission_rate'];
 check(rows.length===5&&rows.map(r=>r.name).sort().join('|')===names.sort().join('|'),'Task-only CSV exports the five declared metric rows, without inventing trial observations');
 check(rows.every(r=>r.participant_id==='alias:SYNTHETIC-AUTHORED-TASK'&&r.session_id===report.analysis.task_scores[0].session_id&&r.task_id===report.analysis.task_scores[0].task_id&&r.profile==='rt-deary-liewald-simple/1.0'&&r.eligible==='true'),'Task metric CSV preserves canonical participant, session, task, profile and eligibility identities');
 check(rows.every(r=>Math.abs(Number(r.value)-report.analysis.task_scores[0].metrics.find(m=>m.name===r.name).value)<1e-9&&r.unit===report.analysis.task_scores[0].metrics.find(m=>m.name===r.name).unit),'CSV metric values and units exactly match immutable JSON scoring');
 await expect(page.getByRole('heading',{name:'Questionnaire coverage',exact:true})).toBeVisible();check(true,'Task report labels questionnaire-only coverage explicitly');
 await page.screenshot({path:path.join(output,'report.png'),fullPage:true});await fs.writeFile(path.join(output,'results.json'),JSON.stringify({origin:'original_synthetic',checks,report_id:report.id},null,2));
}catch(error){await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,text:await page.locator('body').innerText()},null,2));throw error;}finally{await browser.close();}
