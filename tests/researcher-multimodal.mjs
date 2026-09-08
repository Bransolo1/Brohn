// Two independently specified source datasets are analysed by actual workers.
// All synthesis setup here uses the researcher UI, with no mocked endpoints.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {chromium,expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const output=path.resolve('../../work/test-runs/brohn-multimodal-ui-evidence');
const fixture=JSON.parse(await fs.readFile(path.join(output,'fixture.json'),'utf8'));
const browser=await chromium.launch({channel:'chrome',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage();
const checks=[],errors=[],violations=[];page.on('pageerror',e=>errors.push(e.message));
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log(`PASS ${label}`);};
async function select(id,label){const input=page.locator(`#${id}-selectized`);await input.click();await input.fill(label);await input.press('Enter');}
async function download(label,name){const link=page.getByRole('link',{name:label,exact:true});await expect(link).toHaveAttribute('href',/session\/.*download\//);const pending=page.waitForEvent('download');await link.click();const d=await pending;assert.equal(await d.failure(),null);const file=path.join(output,name);await d.saveAs(file);return file;}
async function axe(label,narrow=false){await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&!document.querySelector('.recalculating'));await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);await page.setViewportSize(narrow?{width:390,height:844}:{width:1440,height:1080});const a=(await new AxeBuilder({page}).analyze()).violations;await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(a,null,2));await page.screenshot({path:path.join(output,`${label}.png`),fullPage:true});if(a.length)violations.push({label,rules:a.map(v=>v.id)});else check(true,`${label}: no automated accessibility violations`);check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`${label}: no page overflow`);await page.setViewportSize({width:1440,height:1080});}
try{
 await page.goto('http://127.0.0.1:3851/');await page.getByRole('button',{name:'Studies',exact:true}).click();await page.getByLabel('Search studies',{exact:true}).fill(fixture.title);
 await page.locator(`[data-brohn-event="brohn_open_study"][data-brohn-value='"${fixture.study_id}"']`).click();await page.getByRole('button',{name:'Results',exact:true}).click();
 await page.getByRole('button',{name:'Combine measures',exact:true}).click();await page.getByRole('heading',{name:'Combine study measures',exact:true}).waitFor();
 for(const source of Object.values(fixture.reports))await select('mm_reports',source.id.slice(-6));
 const selected=await page.locator('#mm_reports option:checked').evaluateAll(options=>options.map(o=>o.value));
 check(selected.length===2&&Object.values(fixture.reports).every(r=>selected.includes(r.id)),'The actual source selector retains both intended immutable report identities');
 await axe('source-selection');await axe('source-selection-narrow',true);
 await page.getByRole('button',{name:'Review participants and measures',exact:true}).click();await expect(page.locator('#platform_error')).toContainText('same declared origin');
 check(await page.getByRole('heading',{name:'Combine study measures',exact:true}).isVisible(),'Incorrect default origin is explained without losing the report selection');
 await select('mm_origin','Sample');await page.getByRole('button',{name:'Review participants and measures',exact:true}).click();await page.getByRole('heading',{name:'Review how these measures belong together',exact:true}).waitFor();
 await page.getByRole('button',{name:'Save combined report',exact:true}).click();await expect(page.locator('#platform_error')).toContainText('Confirm your review');
 check(true,'The combined report cannot be queued before explicit identity review');
 await select('mm_identity_mode','Upload a reviewed mapping');
 const template=JSON.parse(await fs.readFile(await download('Download mapping template','identity-template.json'),'utf8'));
 check(template.length===10&&template.every(r=>r.participant_id===''&&r.session_id===''),'Downloaded crosswalk template exposes ten source visits with blank target identities');
 const crosswalk=template.map(row=>({...row,participant_id:row.source_participant_id.replace(/^(gaze|liking)-/,''),session_id:row.source_session_id.replace(/^(gaze|liking)-/,'')}));
 check(new Set(crosswalk.map(r=>r.participant_id)).size===4&&new Set(crosswalk.map(r=>`${r.participant_id}/${r.session_id}`)).size===5,'Original reviewed mapping links four fictional people and five visits across differently named sources');
 const invalid=crosswalk.map(r=>({...r}));invalid[0].source_participant_id='absent-source-person';const invalidPath=path.join(output,'invalid-crosswalk.json');await fs.writeFile(invalidPath,JSON.stringify(invalid));
 await page.locator('#mm_crosswalk_file').setInputFiles(invalidPath);await expect(page.locator('#platform_error')).toContainText('absent from the selected reports');check(true,'An unknown source identity is rejected before synthesis');
 const crosswalkPath=path.join(output,'reviewed-crosswalk.json');await fs.writeFile(crosswalkPath,JSON.stringify(crosswalk,null,2));await page.locator('#mm_crosswalk_file').setInputFiles(crosswalkPath);
 await expect(page.locator('#mm_mapping_status')).toContainText('10 source identities');
 await page.getByLabel('I checked that shared person and session codes refer to the same people and visits',{exact:true}).check();
 await page.getByRole('button',{name:'Save combined report',exact:true}).click();await expect(page.locator('#platform_error')).toContainText('Document the evidence');check(true,'Checked identities still require a written provenance statement');
 await page.getByLabel('Evidence for these participant links',{exact:true}).fill('Original synthetic QA register: prefixes gaze- and liking- identify the data source, while P01–P04 and their five visits are the same fictional identities. No participant observations.');
 await select('mm_metric','GAZE valid gaze share');await page.getByRole('button',{name:'Add comparison',exact:true}).click();await expect(page.getByRole('button',{name:'Remove comparison',exact:true})).toHaveCount(1);
 await page.getByRole('button',{name:'Add comparison',exact:true}).click();await expect(page.locator('#platform_error')).toContainText('hypotheses must be distinct');check(await page.getByRole('button',{name:'Remove comparison',exact:true}).count()===1,'Duplicate hypotheses are rejected instead of inflating the test family');
 await select('mm_metric','QUESTIONNAIRE explicit rating');await page.getByRole('button',{name:'Add comparison',exact:true}).click();await expect(page.getByRole('button',{name:'Remove comparison',exact:true})).toHaveCount(2);
 await axe('identity-and-comparisons');await axe('identity-and-comparisons-narrow',true);
 await page.getByRole('button',{name:'Save combined report',exact:true}).click();await page.getByRole('heading',{name:'Activity',exact:true}).waitFor();
 const job=page.locator('.brohn-card').filter({has:page.getByRole('heading',{name:'analyse multimodal',exact:true})}).first();
 await job.getByRole('button',{name:'Open result',exact:true}).waitFor({timeout:90000});await job.getByRole('button',{name:'Open result',exact:true}).click();
 const report=JSON.parse(await fs.readFile(await download('JSON + provenance','combined-report.json'),'utf8'));
 check(report.analysis.kind==='multimodal'&&report.provenance.crosswalk.length===10,'Actual queued synthesis retains the explicit ten-row crosswalk in immutable provenance');
 const gaze=report.analysis.contrasts.find(c=>c.modality==='gaze'),liking=report.analysis.contrasts.find(c=>c.modality==='questionnaire');
 check(Math.abs(gaze.estimate-10.833333333333334)<1e-9&&gaze.participant_count===3&&gaze.paired_session_count===4,'Combined gaze preserves the independent10.833333pp equal-person estimate with its own3-person/4-visit denominator');
 check(Math.abs(liking.estimate-1.375)<1e-9&&liking.participant_count===4&&liking.paired_session_count===5,'Combined liking preserves1.375 with all4 people/5 visits despite the missing gaze pair');
 check(report.analysis.quality.cross_modal_complete_case_filter===false&&report.analysis.quality.available_report_count===2,'Missing gaze does not create a cross-modal complete-case exclusion');
 check(report.analysis.contrasts.length===2&&report.analysis.contrasts.every(c=>c.multiplicity.family_size===2&&c.multiplicity.method==='holm'),'Both declared hypotheses remain in the explicit Holm family');
 check(report.analysis.observations.every(r=>/^P0[1-4]$/.test(r.participant_id)&&r.source_report_hash===Object.values(fixture.reports).find(s=>s.id===r.source_report_id).hash),'Rows use reviewed shared people while retaining each immutable source report hash');
 const html=await fs.readFile(await download('Download report','combined-report.html'),'utf8'),csv=await fs.readFile(await download('Download observations','combined-observations.csv'),'utf8');
 check(html.includes(report.id)&&csv.includes('source_report_hash')&&csv.split(/\r?\n/).filter(Boolean).length>2,'Combined HTML and observation CSV are actual readable exports with provenance columns');
 await axe('combined-report');await axe('combined-report-narrow',true);
 check(errors.length===0,`No browser exceptions: ${errors.join(';')}`);check(violations.length===0,`All combined-measure accessibility scans clear: ${JSON.stringify(violations)}`);
 await fs.writeFile(path.join(output,'results.json'),JSON.stringify({origin:'original_synthetic',checks,study_id:fixture.study_id,report_id:report.id},null,2));console.log(JSON.stringify({checks:checks.length,output}));
}catch(error){await page.screenshot({path:path.join(output,'failure.png'),fullPage:true}).catch(()=>{});await fs.writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,errors,violations,text:await page.locator('body').innerText()},null,2));throw error;}finally{await browser.close();}
