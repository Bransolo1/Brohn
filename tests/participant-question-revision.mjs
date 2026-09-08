// Original pure browser contract fixtures. Actual R/browser delivery is separate.
import assert from 'node:assert/strict';
await import('../www/participant/question-revision.js');
const {create,equal}=globalThis.BrohnQuestionRevision,hash='a'.repeat(64),opaque='b'.repeat(64);
let checks=0;const check=(condition,label)=>{assert.ok(condition,label);checks++;};
const rejects=(fn,label)=>{assert.throws(fn);checks++;};
const question=(id)=>({id,type:'question',questionnaire_occurrence_id:'occurrence',stimulus_id:null,condition_id:null,
  phase:'active_response',question:{id:`q-${id}`,scope:'before',type:'number',prompt:id,required:true}});
const protocol={design:{questionnaire_navigation:{schema:'brohn-questionnaire-navigation/1.0',profile:'within-occurrence-revision/1.0',
  dependent_answers:'clear-transitive-on-change',seal:'explicit-review'}},timeline:[question('one'),question('two'),
  {id:'review',type:'questionnaire_review',questionnaire_occurrence_id:'occurrence',stimulus_id:null,condition_id:null,phase:'active_response'},
  {id:'stimulus',type:'stimulus',phase:'stimulus'}],questionnaire_occurrences:[{id:'occurrence',review_step_id:'review',question_step_ids:['one','two']}]};
const row=id=>({step_id:id,question_id:`q-${id}`,occurrence_id:'occurrence',stimulus_id:null,condition_id:null,scope:'before',
  dependency_generation:0,answer_version:0,revision_count:0,information:false,ever_visited:false,status:'not_submitted',value:null,last_answer_event_id:null});
const packet={schema:'brohn-questionnaire-packet/1.0',acknowledged_sequence:1,protocol_hash:hash,protocol_cursor:1,next_step_id:'one',state_hash:opaque,
  latest_occurrence:{id:'occurrence',state_version:1,sealed:false,review_step_id:'review',projection_hash:'c'.repeat(64),visit:{id:'visit-one',step_id:'one',
    instance_id:'clock-one',time_origin_ms:'100.000',onset_ms:'20.000000',resumed:false,committed:false}},
  actions:{enter_step_id:null,next_step_id:null,back_step_id:null,editable_step_ids:[],can_seal:false},last_transition:null,
  resume_page:{schema:'brohn-questionnaire-revision-resume/1.0',protocol_hash:hash,state_hash:'d'.repeat(64),offset:0,total_records:2,next_offset:null,records:[row('one'),row('two')]}};
const controller=create(protocol,hash),model=await controller.pages(packet,()=>assert.fail('No unnecessary page request'));
check(model.records.length===2,'Complete first page requires no extra request');
check(equal(false,false)&&!equal(false,0)&&!equal(0,'0')&&!equal(1,1+1e-10),'Native booleans, numeric codes and close doubles remain distinct');
const entered=structuredClone(packet);entered.latest_occurrence.visit=null;entered.actions.enter_step_id='one';
check(controller.payload({...model,packet:entered},'enter',{visitId:'new'}).step.id==='one','Enter uses the sole server target');
rejects(()=>controller.payload(model,'next',{visitId:'new'}),'No locally inferred next target');
rejects(()=>controller.payload(model,'back',{visitId:'new'}),'No Back across first question');
rejects(()=>controller.payload(model,'edit',{target:'two',visitId:'new'}),'No unoffered Edit target');
rejects(()=>controller.payload(model,'seal'),'No sealing before review');
const clock={value:25.5,instance_id:'clock-one',time_origin_ms:'100.000'};
let submission=controller.payload(model,'commit',{value:0,clock});
check(submission.payload.value===0&&submission.payload.response_time_ms===5.5&&submission.payload.active_segment_response_ms===5.5,'Zero is a typed answer and first response interval uses the observed clock');
submission=controller.payload(model,'commit',{value:false,clock});check(submission.payload.value===false,'False is never converted to an omission');
rejects(()=>controller.payload(model,'commit',{value:2,clock:{...clock,instance_id:'new'}}),'Foreign page cannot submit without a resume');
rejects(()=>controller.payload(model,'commit',{value:2,clock:{...clock,time_origin_ms:'101'}}),'Foreign origin cannot submit');
rejects(()=>controller.payload(model,'commit',{value:2,clock:{...clock,value:19}}),'Negative response interval rejected');
const revised=structuredClone(model);revised.records[0].last_answer_event_id='old-answer';
check(controller.payload(revised,'commit',{value:6,clock}).payload.response_time_ms===null,'An edited answer does not claim first response time');
const resumed=structuredClone(model);resumed.packet.latest_occurrence.visit.resumed=true;
check(controller.payload(resumed,'commit',{value:6,clock}).payload.response_time_ms===null,'A resumed answer does not claim uninterrupted time');
const committed=structuredClone(model);committed.packet.latest_occurrence.visit.committed=true;
rejects(()=>controller.payload(committed,'commit',{value:6,clock}),'A committed visit cannot be submitted twice');
const review=structuredClone(model);review.packet.latest_occurrence.visit.step_id='review';review.packet.actions.can_seal=true;
review.packet.actions.editable_step_ids=['one','two'];review.packet.actions.back_step_id='two';
check(controller.payload(review,'seal').payload.projection_hash==='c'.repeat(64),'Seal echoes the opaque R projection hash without browser recomputation');
check(controller.payload(review,'back',{visitId:'back'}).step.id==='two','Back follows the exact server target');
check(controller.payload(review,'edit',{target:'one',visitId:'edit'}).step.id==='one','Review offers exact reached edit targets');
const draft={step_id:'one',occurrence_id:'occurrence',dependency_generation:0,value:false};
check(controller.draftValue(model,protocol.timeline[0],draft)===false,'Local false draft remains typed');
const heads=structuredClone(model);heads.records[0]={...heads.records[0],status:'answered',value:0,dependency_generation:1};
check(controller.draftValue(heads,protocol.timeline[0],draft)===0,'Changed dependency generation discards stale draft and retains current zero');
check(Object.keys(controller.reconcileDrafts(heads,{one:draft})).length===0,'Invalidated stale draft is removed');
const hidden=structuredClone(model);hidden.records[0].status='not_displayed';
check(Object.keys(controller.reconcileDrafts(hidden,{one:draft})).length===0,'Hidden answer draft is not resurrected');
const wrongDraft={...draft,occurrence_id:'other'};check(controller.draftValue(model,protocol.timeline[0],wrongDraft)===null,'Drafts cannot cross occurrences');
for(const [label,change]of [
  ['foreign protocol',p=>p.protocol_hash='e'.repeat(64)],['foreign cursor',p=>p.protocol_cursor=5],
  ['foreign member',p=>p.resume_page.records[0].step_id='stimulus'],['changed question identity',p=>p.resume_page.records[0].question_id='foreign'],
  ['numeric boolean',p=>p.resume_page.records[0].information=0],['negative generation',p=>p.resume_page.records[0].dependency_generation=-1],
  ['cross-timed action',p=>p.actions.next_step_id='stimulus'],['sealed action',p=>{p.latest_occurrence.visit.step_id='review';p.latest_occurrence.sealed=true;p.actions.can_seal=true;}],
  ['wrong page bound',p=>p.resume_page.next_offset=2],['missing page records',p=>p.resume_page.records.pop()]
]){const candidate=structuredClone(packet);change(candidate);rejects(()=>controller.validate(candidate),label);}
rejects(()=>controller.validate(packet,{acknowledgedSequence:2}),'ACK and projection must share sequence');
rejects(()=>controller.validate(packet,{stateHash:'f'.repeat(64)}),'Pagination uses exact global state hash');
const first=structuredClone(packet);first.resume_page.records=[row('one')];first.resume_page.next_offset=1;
const second=structuredClone(packet);second.resume_page.records=[row('two')];second.resume_page.offset=1;
let requested;const paged=await controller.pages(first,(offset,stateHash)=>{requested={offset,stateHash};return second;});
check(paged.records.length===2&&requested.offset===1&&requested.stateHash===opaque,'Full pages are fetched under the opaque global state identity');
check(paged.packet.resume_page.records.length===1,'Merged rows do not silently rewrite the server first-page packet');
await assert.rejects(controller.pages(first,()=>({...second,state_hash:'f'.repeat(64)})));checks++;
const duplicate=structuredClone(second);duplicate.resume_page.records=[row('one')];await assert.rejects(controller.pages(first,()=>duplicate));checks++;
console.log(`${checks} pure questionnaire browser contract checks passed.`);
