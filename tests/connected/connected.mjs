// Mutable test candidate. Ordinary authoring, Publish, participant and Results UI.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
const cfg=JSON.parse(await fs.readFile(process.argv[2],'utf8'));
const require=createRequire(cfg.package_json);
const {chromium,expect:baseExpect}=require('@playwright/test');
const expect=baseExpect.configure({timeout:30000});
const result={passed:false,checks:[],errors:[],cleanup_errors:[],requests:[],responses:[],downloads:[]};
await fs.mkdir(cfg.output,{recursive:false});
let browser,context,page,participant;
const pending=[];
const check=(name,ok)=>{assert.ok(ok,name);result.checks.push(name);};
async function idle(){
  await page.waitForFunction(()=>window.Shiny?.shinyapp?.$socket?.readyState===1&&
    !document.documentElement.classList.contains('shiny-busy')&&
    ![...document.querySelectorAll('.recalculating')].some(e=>e.getClientRects().length));
  await expect(page.locator('.shiny-output-error:visible')).toHaveCount(0);
  await expect(page.locator('#platform_error .brohn-alert-error')).toHaveCount(0);
}
async function stage(name){
  await page.getByRole('button',{name,exact:true}).click();await idle();
  if(['Plan','Questions','Collect'].includes(name))await page.waitForFunction(stage=>{
    const form=document.getElementById('study_form_identity');
    return form?.value.endsWith(':'+stage)&&form.value===Shiny.shinyapp.$inputValues.study_form_identity;
  },name);
}
async function selectVisible(id,value){
  const backing=page.locator('#'+id);
  const markup=await backing.evaluate(element=>element.parentElement.outerHTML);
  (result.select_controls??=[]).push({id,value,original_markup:markup});
  if(await backing.isVisible())await backing.selectOption(value);
  else {
    const control=backing.locator('..').locator('.selectize-control');
    await control.locator('.selectize-input').click();
    await control.locator('.selectize-dropdown [data-value="'+value+'"]').click();
  }
  await expect(backing).toHaveValue(value);
}
async function click(name){const button=participant.getByRole('button',{name,exact:true});await expect(button).toBeEnabled();await button.click();}
try{
  browser=await chromium.launch({executablePath:cfg.chrome,headless:true});
  context=await browser.newContext({viewport:{width:1280,height:900},acceptDownloads:true});
  // Installed before the participant popup imports modules that capture fetch.
  // Forward the original call unchanged; retain only original observation times.
  await context.addInitScript(()=>{
    const original=window.fetch.bind(window);window.__connectedFetches=[];
    window.fetch=function(...args){
      const input=args[0];
      window.__connectedFetches.push({at:performance.now(),origin:performance.timeOrigin,
        path:new URL(input instanceof Request?input.url:String(input),location.href).pathname});
      return original(...args);
    };
  });
  // Capture the real first invitation navigation and redirect before popup creation.
  const participantRequest=url=>new URL(url).port===String(cfg.participant_port);
  context.on('request',request=>{
    if(!participantRequest(request.url()))return;
    const raw=request.postDataBuffer();
    const row={url:request.url(),path:new URL(request.url()).pathname,method:request.method(),body:raw?.toString('utf8')??null};
    result.requests.push(row);
    pending.push(request.allHeaders().then(headers=>row.headers=headers,error=>row.headers_error=error.message));
  });
  context.on('response',response=>{
    if(!participantRequest(response.url()))return;
    const row={url:response.url(),path:new URL(response.url()).pathname,status:response.status()};result.responses.push(row);
    pending.push(response.allHeaders().then(headers=>row.headers=headers,error=>row.headers_error=error.message));
    if(response.headers()['content-type']?.startsWith('application/json'))pending.push(response.text().then(text=>row.json=text,error=>row.body_error=error.message));
    if(response.status()===200&&row.path.endsWith('/participant/index.html'))pending.push(response.body().then(bytes=>{row.body_bytes=bytes.length;row.body_sha256=createHash('sha256').update(bytes).digest('hex');},error=>row.body_error=error.message));
  });
  context.on('page',opened=>{
    opened.on('pageerror',error=>{if(participantRequest(opened.url()))result.errors.push('participant: '+error.message);});
    opened.on('console',message=>{if(participantRequest(opened.url())&&message.type()==='error')
      (result.participant_console_errors??=[]).push({text:message.text(),location:message.location()});});
  });
  page=await context.newPage();page.setDefaultTimeout(30000);
  page.on('pageerror',error=>result.errors.push(error.message));
  const deadline=Date.now()+60000;
  while(true){try{await page.goto(cfg.url,{waitUntil:'domcontentloaded',timeout:5000});break;}
    catch(error){if(Date.now()>=deadline)throw error;await new Promise(resolve=>setTimeout(resolve,200));}}
  await idle();await page.locator('#new_study').click();
  await page.locator('#new_title').fill('Connected consumer packaging');
  await page.getByRole('button',{name:'Create study',exact:true}).click();await idle();
  await expect(page.getByLabel('Study name',{exact:true})).toHaveValue('Connected consumer packaging');
  await page.locator('#stimulus_title_1').fill('Shared control');
  await page.locator('#stimulus_text_1').fill('Shared original control wording');
  await page.locator('#stimulus_duration_1').fill('2000');
  await page.locator('#stimulus_title_2').fill('Packaging original');
  await page.locator('#stimulus_text_2').fill('Original packaging wording');
  await page.locator('#stimulus_duration_2').fill('2000');
  await page.getByLabel('Eye tracking',{exact:true}).uncheck();
  await page.getByRole('button',{name:'Set up participant equipment checks',exact:true}).click();
  await expect(page.getByRole('heading',{name:'Participant checks and recording',exact:true})).toBeVisible();
  await expect(page.locator('#camera_policy_enabled')).not.toBeChecked();
  await expect(page.locator('#participant_equipment_enabled')).toBeChecked();
  await page.locator('#participant_equipment_enabled').uncheck();
  await page.getByRole('button',{name:'Save recording settings',exact:true}).click();
  await expect(page.locator('.modal:visible')).toHaveCount(0);await idle();
  await expect(page.getByText('This design does not request camera recording.',{exact:true})).toBeVisible();
  await expect(page.getByText('Participant equipment preflight is not enabled for this design.',{exact:true})).toBeVisible();
  check('researcher explicitly saves a text/questionnaire design without camera or equipment checks',true);
  await selectVisible('study_order','fixed');
  await page.locator('#baseline_ms').fill('1000');await page.locator('#fixation_ms').fill('500');
  await page.locator('#study_instructions').fill('Look at the control and packaging version naturally, then answer the question.');
  await page.locator('[data-brohn-event="duplicate_stimulus"]').nth(1).click();
  await page.locator('#stimulus_version_title').fill('Packaging variant');
  await page.locator('#stimulus_version_condition').selectOption({label:'Test (test)'});
  await page.getByRole('button',{name:'Add version',exact:true}).click();
  await expect(page.locator('.modal:visible')).toHaveCount(0);await idle();
  await page.locator('#stimulus_group_label').fill('Packaging alternatives');
  await page.getByLabel('Packaging original',{exact:true}).check();
  await page.getByLabel('Packaging variant',{exact:true}).check();
  await page.locator('#stimulus_group_selection').selectOption('one');
  await page.getByRole('button',{name:'Save version group',exact:true}).click();await idle();
  await expect(page.getByText('Each participant sees one version in this group.',{exact:true})).toBeVisible();
  await stage('Questions');await selectVisible('q_scope_1','end');
  await page.locator('#q_prompt_1').fill('How much do you like the packaging?');
  await page.getByRole('button',{name:'Enable answer review',exact:true}).click();await idle();
  await stage('Collect');
  result.study_id=(await page.locator('#study_form_identity').inputValue()).split(':')[0];
  await selectVisible('release_origin','sample');
  await page.locator('#release_alias').check();
  await page.getByRole('button',{name:'Release participant study',exact:true}).click();
  await expect(page.locator('#platform_status')).toContainText('Study released for sample participants');await idle();
  const link=page.getByRole('link',{name:'Open participant study',exact:true});await expect(link).toHaveCount(1);
  result.participant_url=await link.getAttribute('href');
  check('normal Release action produced the actual participant service link',new URL(result.participant_url).port===String(cfg.participant_port));
  [participant]=await Promise.all([context.waitForEvent('page'),link.click()]);participant.setDefaultTimeout(30000);
  await participant.setViewportSize({width:390,height:844});
  await expect(participant.getByRole('button',{name:'Start study',exact:true})).toBeVisible();
  await Promise.all(pending);
  const invitation=result.requests.find(row=>row.url===result.participant_url);
  const redirect=result.responses.find(row=>row.url===result.participant_url);
  const document=result.responses.find(row=>row.status===200&&row.path.endsWith('/participant/index.html'));
  check('genuine researcher anchor retains same-site navigation and original redirect',
    invitation?.headers['sec-fetch-site']==='same-site'&&invitation.headers['sec-fetch-mode']==='navigate'&&
    invitation.headers['sec-fetch-dest']==='document'&&redirect?.status===302&&
    new URL(redirect.headers.location,result.participant_url).href===document?.url);
  check('actual assigned document is served with body identity and scoped CSP',document.body_bytes>0&&
    /^[a-f0-9]{64}$/.test(document.body_sha256)&&document.headers['cache-control']==='no-store'&&
    document.headers['content-security-policy'].includes("img-src 'self' data: blob:"));

  await participant.getByRole('checkbox').check();
  await participant.getByRole('textbox',{name:'Participant alias',exact:true}).fill('connected-01');
  await participant.screenshot({path:path.join(cfg.output,'participant-entry.png'),fullPage:true});
  await click('Start study');
  await expect(participant.getByRole('heading',{name:'Before you begin',exact:true})).toBeVisible();
  await expect(participant.getByText('Look at the control and packaging version naturally, then answer the question.',{exact:true})).toBeVisible();
  await click('Continue');
  // No resize, screenshot, focus change or network intervention during exposure.
  await click('Start questions');
  await expect(participant.getByRole('heading',{name:'How much do you like the packaging?',exact:true})).toBeVisible();
  await participant.getByRole('radio',{name:'Very much',exact:true}).check();await click('Save and continue');
  await expect(participant.getByRole('heading',{name:'Review your answers',exact:true})).toBeVisible();
  await click('Confirm answers and continue');await click('Finish study');
  await expect(participant.getByRole('heading',{name:'Thank you',exact:true})).toBeVisible();
  await participant.screenshot({path:path.join(cfg.output,'participant-saved.png'),fullPage:true});
  await Promise.all(pending);
  result.fetches=await participant.evaluate(()=>window.__connectedFetches);
  const events=result.requests.filter(x=>x.path.startsWith('/api/view/events/')).flatMap(x=>JSON.parse(x.body).events);
  const timed=events.filter(x=>['step_started','step_finished'].includes(x.type)&&['baseline','fixation','passive_viewing'].includes(x.phase));
  check('all six baseline fixation and stimulus boundaries retain original observations',timed.length===12);
  check('all original timed observations and fetch records share the actual page clock',timed.every(x=>
    x.clock.instance_id===timed[0].clock.instance_id&&x.clock.time_origin_ms===timed[0].clock.time_origin_ms)&&
    result.fetches.every(x=>x.origin===Number(timed[0].clock.time_origin_ms)));
  for(let i=0;i<timed.length;i+=2){
    assert.equal(timed[i].type,'step_started');assert.equal(timed[i+1].type,'step_finished');
    const duration=[1000,500,2000][(i/2)%3];
    assert(timed[i+1].payload.observed_duration_ms>=duration);
    assert.equal(timed[i+1].payload.resumed,false);
    assert.equal(timed[i+1].payload.observed_duration_ms,Number(timed[i+1].clock.value)-Number(timed[i].clock.value));
    if(i+2<timed.length)assert.deepEqual(timed[i+1].clock,timed[i+2].clock);
  }
  check('fetch observation includes actual original Start CURRENT and events calls',
    ['/api/view/start/','/api/view/current/','/api/view/events/'].every(prefix=>result.fetches.some(x=>x.path.startsWith(prefix))));
  check('participant page makes no HTTP request between original consecutive timed screens',result.fetches.every(x=>x.at<Number(timed[0].clock.value)||x.at>Number(timed.at(-1).clock.value)));
  check('one actual completed terminal and Finish submission',events.filter(x=>x.type==='run_finished').length===1&&
    result.requests.filter(x=>x.path.startsWith('/api/view/finish/')).length===1);
  await page.bringToFront();await stage('Results');
  const report=page.locator('[data-brohn-event="open_report"]');await expect(report).toHaveCount(1,{timeout:60000});
  result.report_id=JSON.parse(await report.getAttribute('data-brohn-value'));await report.click();await idle();
  await expect(page.locator('.brohn-report-page')).toBeVisible();
  const downloaded=page.waitForEvent('download');await page.getByRole('link',{name:'JSON + provenance',exact:true}).click();
  const item=await downloaded;assert.equal(await item.failure(),null);
  const destination=path.join(cfg.output,'complete-report.json');await item.saveAs(destination);result.downloads.push(destination);
  const complete=JSON.parse(await fs.readFile(destination,'utf8'));
  check('continuously running ordinary worker produces the original report',complete.id===result.report_id&&complete.study_id===result.study_id&&
    complete.analysis_profile==='saved-variant-run-analysis/0.1'&&complete.processing.attempt===1&&complete.analysis.observations.length===1&&complete.analysis.observations[0].value===7);
  await page.screenshot({path:path.join(cfg.output,'researcher-result.png'),fullPage:true});
  check('no researcher or participant browser errors',result.errors.length===0);result.passed=true;
}catch(error){
  result.failure={message:error.message,stack:error.stack};
  if(participant){
    result.participant_failure_url=participant.url();
    await participant.screenshot({path:path.join(cfg.output,'participant-failure.png'),fullPage:true}).catch(()=>{});
    await participant.content().then(html=>fs.writeFile(path.join(cfg.output,'participant-failure.html'),html)).catch(()=>{});
  }
  if(page)await page.screenshot({path:path.join(cfg.output,'first-failure.png')}).catch(()=>{});
}
finally{
  for(const [name,owner] of [['context',context],['browser',browser]])if(owner)try{await owner.close();}catch(error){result.cleanup_errors.push({name,message:error.message});result.passed=false;}
  await Promise.allSettled(pending);await fs.writeFile(path.join(cfg.output,'RESULTS.json'),JSON.stringify(result,null,2));
}
process.exitCode=result.passed?0:1;
