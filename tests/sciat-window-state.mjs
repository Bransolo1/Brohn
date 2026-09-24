// Pure state-machine probes with original synthetic clocks. Not browser timing qualification.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const root=path.resolve(import.meta.dirname,'..'),folder=path.resolve(process.argv[2]);
await import(pathToFileURL(path.join(root,'www/participant/sciat-window-core.js')));
const core=globalThis.BrohnSciatWindowCore,compiled=JSON.parse(await fs.readFile(path.join(folder,'compiled.json'),'utf8'));
const trial=compiled.A.timeline.find(t=>t.type==='task_trial'),checks=[],cases=[];
const check=(name,ok)=>{assert.ok(ok,name);checks.push(name);console.log(`PASS ${name}`);};
const wrong=trial.correct_code==='KeyE'?'KeyI':'KeyE';
function key(s,code,at,{now=at,type='down',repeat=false,trusted=true,modifiers=false}={}){
  return core.transition(s,{type:'key',keyType:type,now,event_ms:at,code,repeat,trusted,modifiers});
}
function finish(s,seal=null){
  const close=seal??Math.max(s.last_observed_ms,s.first?s.first.observed_ms:s.deadline_ms+16);
  s=core.transition(s,{type:'seal',now:close});s=core.transition(s,{type:'feedback_start',now:close+16});
  s=core.transition(s,{type:'feedback_end',now:s.feedback_start_ms+(s.first?150:500)});
  return core.transition(s,{type:'blank_end',now:s.feedback_end_ms+250});
}
function retain(name,s,held=[]){cases.push({name,held,trial_id:trial.id,result:core.result(s)});return core.result(s);}
let s=core.create(trial,2000);s=key(s,trial.correct_code,2400,{now:2500});
let r=retain('event_timestamp_not_handler',finish(s));
check('First response uses event timestamp400ms despite handler500ms',r.response_ms===400&&r.correct===true);
s=core.create(trial,2000);s=key(s,wrong,2400);s=key(s,wrong,2402,{type:'up'});s=key(s,trial.correct_code,2450);
r=retain('first_error_no_correction',finish(s));
check('First error is terminal and a second correct key cannot replace it',r.correct===false&&r.response_ms===400&&r.keys.filter(k=>k.accepted).length===1&&r.keys.at(-1).ignored_reason==='after_first_response');
s=core.create(trial,2000);r=retain('explicit_omission',finish(s));
check('Omission has500ms feedback then250ms blank without invented RT',r.outcome==='omission'&&r.response_ms===null&&r.correct===null&&r.feedback_end_ms-r.feedback_start_ms===500&&r.blank_end_ms-r.feedback_end_ms===250);
for(const order of ['key_first','timer_first']){
  s=core.create(trial,2000);
  if(order==='timer_first')s=core.transition(s,{type:'deadline',now:3500});
  s=key(s,trial.correct_code,3500,{now:3510});r=retain(`deadline_${order}`,finish(s,3516));
  check(`Exact1500ms key wins before sealing with ${order}`,r.outcome==='response'&&r.response_ms===1500&&r.keys[0].accepted);
}
s=core.create(trial,2000);s=key(s,trial.correct_code,3500.000001);r=retain('after_deadline',finish(s));
check('One microsecond after deadline is omitted without tolerance widening',r.outcome==='omission'&&r.keys[0].ignored_reason==='after_deadline');
s=core.create(trial,2000,[trial.correct_code]);s=key(s,trial.correct_code,2400);s=key(s,trial.correct_code,2500,{type:'up'});s=key(s,trial.correct_code,2650);
r=retain('held_release_then_response',finish(s),[trial.correct_code]);
check('Held-at-onset key is ignored until an actual release and new press',r.response_ms===650&&r.keys[0].ignored_reason==='key_held_from_previous_phase');
s=core.create(trial,2000,[trial.correct_code]);s=key(s,trial.correct_code,2100,{type:'up',modifiers:true});s=key(s,trial.correct_code,2400);
r=retain('modified_release',finish(s),[trial.correct_code]);check('Trusted modifier-key release clears held state without becoming a response',r.response_ms===400&&r.keys[0].ignored_reason==='modified_key');
for(const [name,options,reason] of [['repeat',{repeat:true},'key_repeat'],['synthetic',{trusted:false},'synthetic_key_event'],['modified',{modifiers:true},'modified_key']]){
  s=core.create(trial,2000);s=key(s,trial.correct_code,2400,options);s=key(s,trial.correct_code,2450,{type:'up'});s=key(s,trial.correct_code,2600);
  r=retain(name,finish(s));check(`${name} key cannot become a response`,r.response_ms===600&&r.keys[0].ignored_reason===reason);
}
s=core.create(trial,2000);s=key(s,trial.correct_code,1999,{now:2010});s=key(s,trial.correct_code,2020,{type:'up'});s=key(s,trial.correct_code,2400);
r=retain('anticipatory_dispatch',finish(s));check('Delayed pre-onset key remains anticipatory',r.response_ms===400&&r.keys[0].ignored_reason==='anticipatory');
s=core.create(trial,2000);s=core.transition(s,{type:'seal',now:3516});s=core.transition(s,{type:'feedback_start',now:3532});s=key(s,trial.correct_code,3500,{now:3550});
r=retain('eligible_key_after_seal',s);check('Eligible event discovered after sealed omission interrupts instead of creating a false completed omission',r.outcome==='interrupted'&&r.interruption_reason==='eligible_key_after_seal'&&r.blank_end_ms===null);
s=core.create(trial,2000);s=key(s,trial.correct_code,2500);s=key(s,trial.correct_code,2400,{now:2510,type:'up'});
r=retain('event_clock_reversed',s);check('Reversed physical event timestamps interrupt',r.outcome==='interrupted'&&r.interruption_reason==='event_clock_reversed');
for(const where of ['response','feedback','blank']){
  s=core.create(trial,2000);
  if(where!=='response'){s=key(s,trial.correct_code,2400);s=core.transition(s,{type:'seal',now:2400});s=core.transition(s,{type:'feedback_start',now:2416});}
  if(where==='blank')s=core.transition(s,{type:'feedback_end',now:2566});
  s=core.transition(s,{type:'interrupt',now:s.last_observed_ms+10,reason:'window_focus_lost_during_trial'});r=retain(`focus_${where}`,s);
  check(`Focus loss in ${where} preserves partial evidence without inventing remaining phase ends`,r.outcome==='interrupted'&&r.blank_end_ms===null&&(where!=='response'||r.response_ms===null));
}
check('Terminal trial rejects a duplicate transition',assert.throws(()=>core.transition(s,{type:'seal',now:9999}))===undefined);
check('Premature deadline is rejected',assert.throws(()=>core.transition(core.create(trial,2000),{type:'deadline',now:3499}))===undefined);
check('Shortened feedback is rejected',assert.throws(()=>{let x=key(core.create(trial,2000),trial.correct_code,2400);x=core.transition(x,{type:'seal',now:2400});x=core.transition(x,{type:'feedback_start',now:2416});core.transition(x,{type:'feedback_end',now:2565});})===undefined);
const full={};
for(const name of ['A','B']){
  let at=2000;const rows=[];
  for(const t of compiled[name].timeline.filter(t=>t.type==='task_trial')){
    let x=core.create(t,at);const ordinal=rows.length+1;
    if(ordinal!==3)x=key(x,ordinal===1?(t.correct_code==='KeyE'?'KeyI':'KeyE'):t.correct_code,at+(ordinal===2?1500:400+(ordinal%11)*17));
    x=finish(x);rows.push({trial_id:t.id,held:[],result:core.result(x)});at=x.last_observed_ms+16;
  }
  full[name]=rows;check(`${name}: every one of192 frozen trials completes in the pure state machine`,rows.length===192&&rows.filter(x=>x.result.outcome==='omission').length===1&&rows.every(x=>x.result.blank_end_ms!==null));
}
await fs.writeFile(path.join(folder,'state-cases.json'),JSON.stringify({origin:'original_synthetic_component_clocks',cases,full},null,2));
await fs.writeFile(path.join(folder,'state-results.json'),JSON.stringify({passed:true,checks,complete_browser_or_session_qualification:false},null,2));
console.log(JSON.stringify({passed:true,checks:checks.length,folder}));
