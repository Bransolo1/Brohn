// Browser qualification of the production monitoring renderer fed by original
// production-Writer replay evidence. No camera, microphone or physical source.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {chromium} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const folder=path.resolve(process.argv[2]||'../../work/test-runs/brohn-monitoring-replay-20260920');
assert.ok(path.basename(folder).startsWith('brohn-monitoring-replay-'));
const evidence=JSON.parse(await fs.readFile(path.join(folder,'monitoring-models.json'),'utf8'));
assert.equal(Object.keys(evidence.models).length,15);
const browser=await chromium.launch({channel:'chrome',headless:true});
const context=await browser.newContext(),page=await context.newPage();const errors=[],checks=[],scans=[];
page.on('pageerror',error=>errors.push(error.message));
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log(`PASS ${label}`);};
try{
  await page.goto(pathToFileURL(path.join(folder,'monitoring-replay.html')).href);
  await page.addStyleTag({path:'www/brand/tokens.css'});
  await page.addStyleTag({path:'www/brohn.css'});
  check(await page.getByText('Measurement quality: not qualified',{exact:true}).count()===15,'Every replayed measurement keeps quality separate from transport');
  check(await page.locator('svg[role="img"]').count()>=15,'Measurement-specific original waveforms expose accessible labels');
  const gaze=page.getByRole('region',{name:'Equipment and recording checks original-gaze',exact:true});
  check((await gaze.innerText()).includes('Latest gaze position is invalid or unavailable'),'Invalid last gaze sample does not show an earlier valid position');
  check(await gaze.locator('svg circle').count()===0,'Source-invalid gaze never draws an invented eye marker');
  const eeg=page.getByRole('region',{name:'Equipment and recording checks original-eeg',exact:true});
  check((await eeg.innerText()).includes('Latest source observation: 14 kOhm'),'Only the explicitly supplied EEG impedance channel produces an impedance observation');
  check((await page.getByRole('region',{name:'Equipment and recording checks original-camera',exact:true}).innerText()).includes('Camera telemetry'),'Camera telemetry stays distinct from fabricated camera imagery');
  for(const [label,width,height]of[['desktop',1440,1080],['narrow',390,844]]){
    await page.setViewportSize({width,height});
    const violations=(await new AxeBuilder({page}).analyze()).violations;
    const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);
    const smallTargets=await page.locator('summary:visible').evaluateAll(elements=>elements.filter(element=>element.getBoundingClientRect().height<44).map(element=>element.textContent));
    scans.push({label,violations,overflow,smallTargets});
    await fs.writeFile(path.join(folder,`${label}-axe.json`),JSON.stringify(violations,null,2));
    await page.screenshot({path:path.join(folder,`${label}-equipment.png`),fullPage:true});
    check(violations.length===0,`${label}: production monitoring markup passes axe`);
    check(!overflow,`${label}: no page-level horizontal overflow`);
    check(smallTargets.length===0,`${label}: monitoring disclosure controls meet 44px target`);
  }
  check(errors.length===0,'No browser script errors');
  await fs.writeFile(path.join(folder,'browser-results.json'),JSON.stringify({checks,scans,errors,origin:'original_software_replay'},null,2));
  console.log(JSON.stringify({checks:checks.length,folder}));
}finally{await browser.close();}
