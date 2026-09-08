// Real Chrome component and keyboard/accessibility checks with caller hooks.
// This does not substitute for the real R receiver and persisted study journey.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {chromium, expect} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
const output=path.resolve('../../work/test-runs/brohn-maxdiff-component-evidence');await fs.mkdir(output,{recursive:true});
const source=await fs.readFile('www/participant/maxdiff.js','utf8'),css=await fs.readFile('www/participant/maxdiff.css'),runnerCSS=await fs.readFile('www/participant/runner.css');
const server=http.createServer((req,res)=>{
  if(req.url==='/maxdiff.js'){res.setHeader('Content-Type','application/javascript');res.end(source);return;}
  if(req.url==='/maxdiff.css'||req.url==='/runner.css'){res.setHeader('Content-Type','text/css');res.end(req.url==='/maxdiff.css'?css:runnerCSS);return;}
  if(req.url==='/'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Original best-worst component fixture</title><link rel="stylesheet" href="/runner.css"><link rel="stylesheet" href="/maxdiff.css"><script src="/maxdiff.js"></script></head><body><main id="participant-app"><div id="content"></div></main></body></html>');return;}
  res.writeHead(204);res.end();
});await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await chromium.launch({channel:'chrome',headless:true}),checks=[],errors=[],axeResults=[];
const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);console.log(`PASS ${label}`);};
try{
  const context=await browser.newContext({viewport:{width:1280,height:900}}),page=await context.newPage();page.on('pageerror',error=>errors.push(error.message));await page.goto(`http://127.0.0.1:${server.address().port}`);
  await page.evaluate(()=>{
    window.make=(options={})=>{
      window.component?.dispose();window.drafts=[];window.submissions=[];window.reported=[];window.attempts=0;window.mode=options.mode||'success';window.holdDraft=!!options.holdDraft;window.failDraft=!!options.failDraft;
      window.choice={exercise_id:'original-exercise',design_hash:'a'.repeat(64),set_id:'original-set',trial_id:'original-trial',position:2,item_order:['id-c','id-a','id-b'],
        items:[{id:'id-c',label:'Original convenience feature'},{id:'id-a',label:'<script>Original text, never executable</script>'},{id:'id-b',label:'Original battery feature'}],
        prompt:'Which original feature would you prefer most and least?',best_label:'Most preferred',worst_label:'Least preferred',required:true,...options.choice};
      window.component=BrohnMaxDiff.create({container:document.getElementById('content'),choice,draft:options.draft,
        onDraft:async value=>{drafts.push(value);if(failDraft){failDraft=false;throw new Error('Original draft write failed. Retry this choice.');}if(holdDraft){holdDraft=false;await new Promise(resolve=>{window.releaseDraft=resolve;});}},
        onSubmit:async value=>{submissions.push(value);attempts++;if(mode==='pending')await new Promise((resolve,reject)=>{window.resolveSubmit=resolve;window.rejectSubmit=reject;});
          else if(mode==='failonce'&&attempts===1)throw new Error('Original lost receipt. Retry the saved pair.');},
        onError:error=>reported.push(error.message)});
    };
  });
  const mount=options=>page.evaluate(options=>make(options),options);
  const best=()=>page.getByRole('group',{name:'Most preferred',exact:true}),worst=()=>page.getByRole('group',{name:'Least preferred',exact:true});
  const continueButton=()=>page.getByRole('button',{name:'Continue',exact:true});
  const scan=async name=>{const violations=(await new AxeBuilder({page}).analyze()).violations;axeResults.push({name,violations});assert.deepEqual(violations,[]);check(true,`${name}: actual page has zero axe violations`);await page.screenshot({path:path.join(output,`${name}.png`),fullPage:true});};
  await mount();
  check(await best().getByRole('radio').evaluateAll(elements=>elements.map(e=>e.value).join(','))==='id-c,id-a,id-b','Both groups preserve the exact source item order rather than label or identity sorting');
  check(await page.locator('.brohn-maxdiff script').count()===0&&(await page.locator('.brohn-maxdiff').textContent()).includes('<script>Original text, never executable</script>'),'Original markup-like material is rendered as safe literal text');
  await continueButton().click();
  check((await page.getByRole('alert').textContent()).includes('Choose both')&&await page.evaluate(()=>submissions.length===0),'Required blank pair cannot submit an invented answer');
  await best().getByRole('radio').first().focus();await page.keyboard.press('Space');await page.keyboard.press('ArrowDown');
  check(await best().getByRole('radio').nth(1).isChecked(),'Native keyboard arrows select the next item in the preserved order');
  check(await worst().getByRole('radio').nth(1).isDisabled(),'The same item cannot simultaneously become best and worst');
  await continueButton().click();check(await page.evaluate(()=>submissions.length===0),'A partial required pair stays visible until completed');
  await worst().getByRole('radio').nth(2).check();await scan('required-desktop');
  await continueButton().click();await expect(continueButton()).toBeDisabled();
  check(await page.evaluate(()=>JSON.stringify(submissions)==='[{"best_id":"id-a","worst_id":"id-b"}]'),'Caller receives exactly the explicit distinct item IDs');
  check(await page.locator('.brohn-maxdiff input:enabled,.brohn-maxdiff button:enabled').count()===0,'Successful submission stays locked until the caller changes the screen');

  await mount({mode:'pending',draft:{best_id:'id-c',worst_id:'id-b'}});
  check(await best().getByRole('radio').first().isChecked()&&await worst().getByRole('radio').nth(2).isChecked(),'A valid exact offered pair restores without reordering or another response');
  await continueButton().click();await expect.poll(()=>page.evaluate(()=>submissions.length)).toBe(1);
  check(await page.locator('.brohn-maxdiff input:enabled,.brohn-maxdiff button:enabled').count()===0&&await page.locator('.brohn-maxdiff').getAttribute('aria-busy')==='true','All choices freeze while the caller waits for a receipt');
  await page.evaluate(()=>rejectSubmit(new Error('Original lost receipt. Retry the saved pair.')));await expect(continueButton()).toBeEnabled();
  check(await best().getByRole('radio').first().isChecked()&&await worst().getByRole('radio').nth(2).isChecked()&&await page.evaluate(()=>reported.length===1),'Submission failure restores the unchanged pair and reports the actual error');
  await page.evaluate(()=>mode='success');await continueButton().click();await expect.poll(()=>page.evaluate(()=>submissions.length)).toBe(2);
  check(await page.evaluate(()=>JSON.stringify(submissions[0])===JSON.stringify(submissions[1])),'A retry submits the same explicit pair without inference');

  await mount({choice:{required:false},draft:{best_id:'id-c',worst_id:null}});
  await continueButton().click();check(await page.evaluate(()=>submissions.length===0),'Optional partial choice does not silently become a missing response');
  await page.getByRole('button',{name:'Clear choices and skip this set',exact:true}).click();await expect.poll(()=>page.evaluate(()=>submissions.length)).toBe(1);
  check(await page.evaluate(()=>submissions[0]===null&&drafts.at(-1).best_id===null&&drafts.at(-1).worst_id===null),'Explicit clear-and-skip persists a blank pair before submitting null');
  await mount({choice:{required:false}});await page.getByRole('button',{name:'Skip this set',exact:true}).click();
  await expect.poll(()=>page.evaluate(()=>submissions.length)).toBe(1);check(await page.evaluate(()=>submissions[0]===null),'An entirely blank optional set has an explicit skip path');

  await mount({draft:{best_id:null,worst_id:'id-b'}});await page.getByRole('button',{name:'Clear choices',exact:true}).click();
  check(await page.getByRole('radio',{checked:true}).count()===0&&await page.evaluate(()=>document.activeElement.value==='id-c'),'Explicit Clear resets only the choice draft and returns keyboard focus');
  await mount({holdDraft:true});await best().getByRole('radio').first().check();await worst().getByRole('radio').nth(2).check();await continueButton().click();
  check(await page.evaluate(()=>submissions.length===0),'Submission waits for the caller-owned draft persistence queue');
  await page.evaluate(()=>releaseDraft());await expect.poll(()=>page.evaluate(()=>submissions.length)).toBe(1);
  check(await page.evaluate(()=>drafts[0].worst_id===null&&drafts.at(-1).best_id==='id-c'&&drafts.at(-1).worst_id==='id-b'),'Rapid draft changes persist in order and the complete latest pair is submitted');
  await mount({failDraft:true,draft:{best_id:'id-c',worst_id:'id-b'}});await continueButton().click();await expect(continueButton()).toBeEnabled();
  check(await page.evaluate(()=>submissions.length===0&&reported.length===1),'A failed draft write prevents the submission hook and exposes retry');
  await continueButton().click();await expect.poll(()=>page.evaluate(()=>submissions.length)).toBe(1);check(true,'Retry can persist the exact draft after a transient draft-write failure');

  const invalid=await page.evaluate(()=>{
    const cases=[{draft:{best_id:'not-offered',worst_id:null}},{draft:{best_id:1,worst_id:null}},{draft:{best_id:'id-c',worst_id:'id-c'}},
      {choice:{...choice,item_order:['id-a','id-b','id-c']}},{choice:{...choice,required:'false'}},{choice:{...choice,best_label:choice.worst_label}}];
    return cases.map(options=>{const before=document.querySelectorAll('.brohn-maxdiff').length;try{BrohnMaxDiff.create({container:document.getElementById('content'),choice:options.choice||choice,draft:options.draft,onDraft:()=>{},onSubmit:()=>{},onError:()=>{}});return false;}
      catch(error){return error instanceof Error&&document.querySelectorAll('.brohn-maxdiff').length===before;}});
  });check(invalid.every(Boolean),'Foreign, coerced or duplicate draft IDs and malformed frozen contracts fail before mounting');
  await page.setViewportSize({width:390,height:844});const long='Original declared feature with a long accessible description and exact characters '+ 'abcdefghij'.repeat(12);
  await mount({choice:{required:false,item_order:Array.from({length:8},(_,i)=>`original-${i}`),items:Array.from({length:8},(_,i)=>({id:`original-${i}`,label:`${i+1}: ${long}`}))}});
  await scan('optional-eight-items-narrow');
  const bounds=await page.evaluate(()=>({viewport:innerWidth,document:document.documentElement.scrollWidth,labels:[...document.querySelectorAll('.maxdiff-choice')].map(e=>{const r=e.getBoundingClientRect();return{x:r.x,right:r.right,height:r.height};})}));
  check(bounds.document===390&&bounds.labels.every(r=>r.x>=0&&r.right<=390&&r.height>=48),'Actual 390px eight-item screen has no horizontal overflow and retains 48px choice targets');
  await page.emulateMedia({reducedMotion:'reduce'});await scan('optional-reduced-motion-narrow');
  check(!/\b(fetch|XMLHttpRequest|performance|Date)\b/.test(source),'Component contains no network or timing ownership');
  await mount({mode:'pending',draft:{best_id:'id-c',worst_id:'id-b'}});await continueButton().click();await expect.poll(()=>page.evaluate(()=>submissions.length)).toBe(1);
  await page.evaluate(()=>{const sibling=document.createElement('p');sibling.id='caller-content';sibling.textContent='Caller owns this separate screen';document.getElementById('content').append(sibling);component.dispose();rejectSubmit(new Error('Disposed screen receipt'));});
  check(await page.locator('.brohn-maxdiff').count()===0&&await page.locator('#caller-content').count()===1&&await page.evaluate(()=>reported.length===0),'Dispose removes only the component and ignores a late rejected callback');
  check(errors.length===0,`No browser exceptions: ${errors.join('; ')}`);
  await fs.writeFile(path.join(output,'results.json'),JSON.stringify({scope:'original_synthetic_browser_component_with_caller_hooks',checks,axe:axeResults,bounds,
    limitations:['No R receiver, deployment, real participant or durable network delivery is exercised by this component test.','The caller must preserve the exact frozen protocol and record its own onset and receipt evidence.']},null,2));
  console.log(JSON.stringify({checks:checks.length,axe_scans:axeResults.length,output}));
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
