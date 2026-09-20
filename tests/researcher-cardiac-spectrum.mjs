// Production renderer backed by six real supervised analysis/explorer jobs.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {chromium} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const folder=path.resolve(process.argv[2]||'../../work/test-runs/brohn-cardiac-spectrum-20260920');
const proof=JSON.parse(await fs.readFile(path.join(folder,'worker-results.json'),'utf8'));
assert.ok(proof.checks>=22);assert.equal(proof.physical_validation,false);
const browser=await chromium.launch({channel:'chrome',headless:true});
const context=await browser.newContext(),page=await context.newPage();const errors=[],checks=[],scans=[];
page.on('pageerror',error=>errors.push(error.message));
const check=(value,label)=>{assert.ok(value,label);checks.push(label);console.log(`PASS ${label}`);};
try{
  for(const modality of ['ecg','ppg']){
    await page.goto(pathToFileURL(path.join(folder,`${modality}.html`)).href);
    await page.addStyleTag({path:'www/brand/tokens.css'});await page.addStyleTag({path:'www/brohn.css'});
    const text=await page.locator('main').innerText();
    check(text.includes(modality==='ppg'?'PRV from detected pulse peaks':'RR from detected R peaks'),'Actual '+modality+' spectrum preserves its rhythm basis');
    check(text.includes('LF/HF is not a stress')&&text.includes('ms^2/Hz')&&await page.getByRole('region',{name:/Full spectrum band power/}).count()===1,'Actual '+modality+' chart includes units, exact bands and interpretation boundary');
    for(const [label,width,height]of[['desktop',1440,1080],['narrow',390,844]]){
      await page.setViewportSize({width,height});
      check(await page.locator('svg:visible').count()===1,`${modality} ${label}: single responsive spectrum`);
      const chart=page.locator('svg:visible');
      check(await chart.locator('polyline').count()===1&&await chart.locator('rect').count()===2,`${modality} ${label}: actual spectrum with two declared band regions`);
      const violations=(await new AxeBuilder({page}).analyze()).violations;
      const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);
      const small=await page.locator('summary:visible,a:visible').evaluateAll(xs=>xs.filter(x=>x.getBoundingClientRect().height<44).map(x=>x.textContent));
      scans.push({modality,label,violations,overflow,small});
      await fs.writeFile(path.join(folder,`${modality}-${label}-axe.json`),JSON.stringify(violations,null,2));
      await page.screenshot({path:path.join(folder,`${modality}-${label}.png`),fullPage:true});
      check(violations.length===0,`${modality} ${label}: axe clear`);
      check(!overflow,`${modality} ${label}: no horizontal page overflow`);
      check(small.length===0,`${modality} ${label}: controls meet 44px`);
    }
  }
  check(errors.length===0,'No browser script errors');
  await fs.writeFile(path.join(folder,'browser-results.json'),JSON.stringify({checks,scans,errors},null,2));
  console.log(JSON.stringify({checks:checks.length,folder}));
}finally{await browser.close();}
