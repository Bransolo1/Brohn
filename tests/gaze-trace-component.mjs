// Browser inspection of the real R-rendered component, separate from the later
// connected report/worker journey. Input comes from platform-gaze-traces.R.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {chromium} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const folder=path.resolve(process.argv[2]);
assert.ok(path.basename(folder).startsWith('brohn-gaze-traces-'));
const html=path.join(folder,'trace-component.html');await fs.access(html);
const output=path.join(folder,`component-browser-${Date.now()}`);await fs.mkdir(output);
const browser=await chromium.launch({channel:'chrome',headless:true});
const context=await browser.newContext({viewport:{width:1440,height:1000}}),page=await context.newPage();
const checks=[],scans=[],errors=[];page.on('pageerror',e=>errors.push(e.message));
function check(value,label){assert.ok(value,label);checks.push(label);console.log('PASS',label);}
try{
 await page.goto(pathToFileURL(html).href);
 check(await page.locator('svg[data-gaze-trace-profile]').count()===0&&await page.getByRole('img').count()===1,'Dedicated SVG has accessible chart semantics');
 check(await page.locator('svg:visible [data-gaze-invalid]').count()===5&&await page.locator('svg:visible [data-gaze-blink]').count()===1,'Exact excluded source points and single source-label tick are visible');
 check(await page.locator('details[open]').count()===0,'Detailed methods and numerical rows are initially collapsed');
 for(const width of [1440,390]){
  await page.setViewportSize({width,height:1000});
  const violations=(await new AxeBuilder({page}).analyze()).violations;
  const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);
  scans.push({width,violations:violations.length,overflow});
  await fs.writeFile(path.join(output,`trace-${width}-axe.json`),JSON.stringify(violations,null,2));
  await page.screenshot({path:path.join(output,`trace-${width}.png`),fullPage:true});
  check(violations.length===0&&!overflow,`${width}px component has no axe violations or page overflow`);
 }
 const summary=page.locator('summary');await summary.focus();await page.keyboard.press('Enter');
 check(await page.locator('details[open]').count()===1,'Keyboard opens exact numerical alternative');
 check(await page.getByRole('table').locator('tbody tr').count()===22,'Numerical alternative retains every selected row in this fixture');
 check(Number(await page.getByRole('table').locator('tbody tr').nth(14).locator('td').nth(3).textContent())===6+2**-50,'Numerical alternative retains difficult binary64 decimal');
 check((await summary.boundingBox()).height>=44,'Disclosure remains a 44-pixel keyboard target in the component shell');
 check(errors.length===0,'No browser runtime errors');
 await fs.writeFile(path.join(output,'acceptance.json'),JSON.stringify({scope:'Real R-rendered standalone component; connected study/report integration pending',checks,scans,errors},null,2));
 console.log(output);
}finally{await browser.close();}
