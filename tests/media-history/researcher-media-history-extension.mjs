// Prepared continuation only. Do not launch during another source-frozen journey.
// Caller supplies a copied accepted workspace populated through real media jobs,
// the existing researcher navigation/services, and original artifact bytes.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {appendFileSync} from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
export async function exerciseMediaHistory({page,context,output,regular,gap,openMedia,restart,snapshot,referenceBytes}) {
  const require=createRequire(path.resolve('package.json'));
  const {expect}=require('@playwright/test');
  const AxeBuilder=require('@axe-core/playwright').default;
  const checks=[],scans=[],timings=[];
  const hash=b=>createHash('sha256').update(b).digest('hex');
  const note=value=>appendFileSync(path.join(output,'step-log.jsonl'),JSON.stringify(value)+'\n');
  const check=(value,label)=>{assert.ok(value,label);checks.push(label);note({type:'check',label});};
  const summary=page.locator('#media_review_history_summary');
  const rows=page.locator('#media_review_history [data-brohn-event="media_review_reopen"]');
  const older=page.locator('#media_review_history_older');
  async function idle(){
    await page.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy')&&
      ![...document.querySelectorAll('.recalculating')].some(x=>x.getClientRects().length),{},{timeout:60000});
    await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);
    await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  }
  async function ids(){return rows.evaluateAll(nodes=>nodes.map(n=>JSON.parse(n.dataset.brohnValue).id));}
  async function showHistory(){
    const details=page.locator('#media_review_history').locator('..');
    if(await details.getAttribute('open')===null)await details.locator(':scope > summary').click();
    await expect(summary).toBeVisible();await idle();return details;
  }
  async function olderByKeyboard(){
    const previous=await summary.innerText();await older.focus();const start=performance.now();await page.keyboard.press('Enter');
    await expect(summary).not.toHaveText(previous);await idle();await expect(summary).toBeFocused();
    const timing={action:'older-page-keyboard',milliseconds:performance.now()-start};timings.push(timing);note(timing);
  }
  async function findExact(id){
    await showHistory();let seen=[];
    for(let i=0;i<100;i++){
      const current=await ids();assert.ok(current.length<=20);assert.ok(!current.some(x=>seen.includes(x)));seen.push(...current);
      if(current.includes(id))return {seen,pages:i+1};
      assert.equal(await older.isDisabled(),false,'The exact saved review must remain reachable');await olderByKeyboard();
    }
    throw Error('Fixture exceeds the bounded acceptance journey');
  }
  async function reopenExact(record){
    const route=await findExact(record.id);
    const start=performance.now();
    await page.locator(`[data-brohn-event="media_review_reopen"][data-brohn-value*="${record.id}"]`).click();
    await expect(page.locator('#media_review_seconds')).toHaveValue((record.body.request.selection.cursor_sample/record.body.result.mapping.sampling_rate).toFixed(9),{timeout:60000});
    await expect(page.locator('#media_review_result')).toContainText('Saved media cursor',{timeout:60000});
    await expect(page.locator(`#media_review_result [data-media-cursor-sample="${record.body.request.selection.cursor_sample}"]`)).toHaveCount(2,{timeout:60000});
    await expect(page.getByRole('link',{name:'Download complete video frame ledger',exact:true})).toHaveAttribute('href',/session\//,{timeout:60000});
    await idle();
    const timing={action:'exact-saved-result-reopened',id:record.id,milliseconds:performance.now()-start};timings.push(timing);note(timing);
    return route;
  }
  async function download(label,name){
    const pending=page.waitForEvent('download');await page.getByRole('link',{name:label,exact:true}).click();
    const d=await pending;assert.equal(await d.failure(),null);const file=path.join(output,name);await d.saveAs(file);return fs.readFile(file);
  }
  async function scan(label,width){
    await page.setViewportSize({width,height:width<500?844:1080});await showHistory();await summary.scrollIntoViewIfNeeded();
    await idle();await page.screenshot({path:path.join(output,`${label}.png`),fullPage:false});
    const violations=(await new AxeBuilder({page}).include('#shiny-modal').analyze()).violations;
    const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);
    await fs.writeFile(path.join(output,`${label}-axe.json`),JSON.stringify(violations,null,2));
    scans.push({label,width,violations:violations.length,overflow});check(!violations.length&&!overflow,`${label}: accessible history and reflow`);
  }
  const before=await snapshot();assert.ok(before.media_reviews.filter(r=>r.body.audio_review_id===regular.audio.id).length>40,'Use genuinely published saved reviews, not contract-only metadata clones');
  await openMedia(regular);const details=await showHistory();const first=await ids();
  await olderByKeyboard();check(await details.getAttribute('open')!==null,'Paging preserves expanded history');
  await page.locator('#media_review_history_newer').click();await expect.poll(ids).toEqual(first);await idle();await expect(summary).toBeFocused();
  check(true,'Newer restores exact same saved references without reopening a result');
  await olderByKeyboard();await page.locator('#media_review_history_latest').click();await expect.poll(ids).toEqual(first);await idle();await expect(summary).toBeFocused();
  check(true,'Show latest returns to the newest complete page without creating a review');
  const route=await reopenExact(regular.media);check(route.pages>=3,'Old original saved cursor is reachable beyond40 entries');
  check(route.seen.includes(regular.media.body.request.catalog.id),'Original video inventory remains listed beyond40 entries and was reused by the initial media open');
  const mapping=JSON.parse((await download('Download media mapping and provenance','history-original-mapping.json')).toString());assert.deepEqual(mapping,regular.media.body);
  const samples=await download('Download original selected audio samples','history-original-samples.csv');assert.equal(hash(samples),hash(await referenceBytes(regular.media,'samples')));
  const frame=await download('Download exact recorded frame PNG','history-original-frame.png');assert.equal(hash(frame),hash(await referenceBytes(regular.media,'frame')));
  check(true,'Oldest original mapping, complete samples and frame bytes remain exact');
  const stale=await page.getByRole('link',{name:'Download original selected audio samples',exact:true}).getAttribute('href');
  await scan('history-oldest-desktop',1440);await scan('history-oldest-narrow',390);
  await page.locator('#media_review_seconds').fill('1.25');await page.locator('#media_review_seconds').press('Tab');
  await expect(page.locator('#media_review_result')).toContainText('The cursor or track changed.',{timeout:60000});
  check((await context.request.get(new URL(stale,page.url()).toString())).status()===404,'Changing cursor still revokes old guarded exports');
  await openMedia(gap);await reopenExact(gap.media);
  await expect(page.locator('#media_review_result')).toContainText('The saved cursor uses original container timing.');
  await expect(page.locator('#media_review_result')).not.toContainText('The frame below');await expect(page.locator('#media_review_result img')).toHaveCount(0);
  check(true,'Actual gap has honest cursor copy and no fabricated image');await scan('history-gap-narrow',390);
  await restart();await openMedia(regular);await reopenExact(regular.media);
  assert.deepEqual(JSON.parse((await download('Download media mapping and provenance','history-restarted-mapping.json')).toString()),mapping);
  assert.equal(hash(await download('Download original selected audio samples','history-restarted-samples.csv')),hash(samples));
  const after=await snapshot();assert.deepEqual(after.jobs,before.jobs);assert.deepEqual(after.reports,before.reports);
  check(true,'Fresh process history reopening preserves all jobs and scientific reports');
  return {checks,scans,timings,new_jobs_during_navigation:0,scope:'Copied genuine saved corpus; no new scientific analysis during history navigation.'};
}
