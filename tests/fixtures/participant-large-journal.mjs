// Original synthetic whole journal. Never copy a finished trial into another position.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
await import('../../www/participant/event-batch.js');
const folder=path.resolve(process.argv[2]);
const sourcePath=path.join(folder,'original-journal.json');
const original=await fs.readFile(sourcePath,'utf8');
const events=JSON.parse(original), changed=[];
for(const event of events) {
  if(event.type!=='task_event'||event.payload.kind!=='task_trial_finished'||event.payload.data.outcome!=='response'||changed.length===3)continue;
  const data=event.payload.data,first=data.keys[0];
  data.keys=Array.from({length:5000},(_,i)=>{
    const eventMs=first.event_ms+i/10000,type=i%2?'up':'down';
    return {...first,type,event_ms:eventMs,observed_ms:eventMs+.000001,accepted:i===0,
      ignored_reason:i===0?null:type==='up'?'key_release':eventMs>data.deadline_ms?'after_deadline':'after_first_response'};
  });
  assert.equal(data.keys.length,5000);
  assert.ok(data.keys.at(-1).observed_ms<data.response_closed_ms);
  changed.push({sequence:event.sequence,trial_id:data.trial_id,keys:5000,response_ms:data.response_ms});
}
assert.equal(changed.length,3);
const unchanged=JSON.stringify(events),batches=[];
let ackedSequence=0;
while(ackedSequence<events.length) {
  const chosen=BrohnEventBatch.select({events,ackedSequence,operationId:`original-large-http-${ackedSequence+1}`,maxBytes:3*1024*1024});
  const filename=`batch-${String(batches.length+1).padStart(2,'0')}.json`;
  assert.equal(Buffer.byteLength(chosen.json,'utf8'),chosen.bytes);
  await fs.writeFile(path.join(folder,filename),chosen.json);
  batches.push({filename,wire_bytes:chosen.bytes,batch:chosen.batch,
    maximum_key_trials:chosen.payload.events.filter(e=>e.payload?.data?.keys?.length===5000).length});
  ackedSequence=chosen.batch.last;
}
assert.equal(JSON.stringify(events),unchanged);
assert.equal(await fs.readFile(sourcePath,'utf8'),original);
assert.ok(batches.some(b=>b.maximum_key_trials===3));
await fs.writeFile(path.join(folder,'large-journal.json'),JSON.stringify(events));
await fs.writeFile(path.join(folder,'batches.json'),JSON.stringify({events:events.length,changed,batches,source_unchanged:true},null,2));
