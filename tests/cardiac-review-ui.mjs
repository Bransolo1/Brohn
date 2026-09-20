// Actual browser input-at-click qualification of the small researcher adapter.
import assert from 'node:assert/strict';
import path from 'node:path';
import {chromium,expect} from '@playwright/test';
const browser=await chromium.launch({channel:'chrome',headless:true});
let checks=0;const check=(ok,label)=>{assert.ok(ok,label);checks++;console.log('PASS '+label);};
try{
  const page=await browser.newPage();
  await page.route('http://127.0.0.1/cardiac-fixture',route=>route.fulfill({contentType:'text/html',body:`<!doctype html><html><body><div id="cardiac-review-ui" data-source="original-report:version2|table1"><div data-cardiac-form="original-review:version3:new"><select id="cardiac_mode"><option value="time">Times</option><option value="samples">Rows</option></select><input id="cardiac_start_time"><input id="cardiac_end_time"><input id="cardiac_start_sample" value="0"><input id="cardiac_end_sample" value="1"><select id="cardiac_reason"><option value="signal_loss">Loss</option></select><textarea id="cardiac_note"></textarea><input id="cardiac_title" value="Original review"><select id="cardiac_choice"><option value="review-original">Original saved review</option></select><input id="cardiac_history_revision" value="2"><button type="button" data-cardiac-action="resolve">Preview exclusion</button><div data-cardiac-current-preview="calculation"><button type="button" data-cardiac-action="recalculate" data-cardiac-payload='{"id":"preview-original"}'>Recalculate</button></div></div></div></body></html>`}));
  await page.goto('http://127.0.0.1/cardiac-fixture');
  await page.evaluate(()=>{window.captured=[];window.Shiny={setInputValue:(name,value)=>captured.push({name,value})};});
  const script=path.resolve('www/cardiac-review-ui.js');await page.addScriptTag({path:script});await page.addScriptTag({path:script});
  // Set DOM values without dispatching any Shiny input event, then click now.
  await page.evaluate(()=>{document.getElementById('cardiac_start_time').value='1700000000.123456789';document.getElementById('cardiac_end_time').value='1700000000.223456789';document.getElementById('cardiac_note').value='Original visible note <literal>';document.querySelector('[data-cardiac-action="resolve"]').click();});
  let events=await page.evaluate(()=>captured);
  check(events.length===1&&events[0].value.fields.start_time==='1700000000.123456789'&&events[0].value.fields.end_time==='1700000000.223456789','Immediate action preserves exact visible decimal strings without debounced inputs');
  check(events[0].value.fields.note==='Original visible note <literal>'&&events[0].value.source==='original-report:version2|table1'&&events[0].value.form==='original-review:version3:new','One action carries the visible note and exact source/form identity');
  check(events[0].value.title==='Original review'&&events[0].value.choice==='review-original'&&events[0].value.history==='2','Create/open/history use the same current DOM snapshot');
  await page.getByRole('button',{name:'Preview exclusion',exact:true}).focus();await page.keyboard.press('Enter');
  events=await page.evaluate(()=>captured);check(events.filter(x=>x.name==='cardiac_ui_action').length===2,'Keyboard button activation submits exactly once despite repeated script inclusion');
  await page.locator('#cardiac_start_time').fill('22.001');
  await expect(page.locator('[data-cardiac-current-preview]')).toBeHidden();
  events=await page.evaluate(()=>captured);const dirty=events.filter(x=>x.name==='cardiac_ui_dirty').at(-1);
  check(dirty.value.fields.start_time==='22.001'&&dirty.value.form==='original-review:version3:new','A visible edit hides stale approval immediately and sends exact dirty form identity');
  await page.evaluate(()=>{document.querySelector('[data-cardiac-form]').dataset.cardiacForm='original-review:version4:new';document.getElementById('cardiac-review-ui').dataset.source='another-report:version1|table2';document.querySelector('[data-cardiac-action="resolve"]').click();});
  events=await page.evaluate(()=>captured);check(events.at(-1).value.form==='original-review:version4:new'&&events.at(-1).value.source==='another-report:version1|table2','Actions bind current replacement source and form rather than a captured old closure');
  check(new Set(events.filter(x=>x.name==='cardiac_ui_action').map(x=>x.value.nonce)).size===3,'Repeated actions retain distinct delivery event identities');
  console.log(JSON.stringify({checks,origin:'original_browser_form_fixture_only'}));
}finally{await browser.close();}
