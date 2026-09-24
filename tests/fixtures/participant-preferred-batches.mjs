// Candidate-only batching of the unchanged accepted full journal.
import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import path from 'node:path';
import assert from 'node:assert/strict';
await import('./participant-event-batch-preferred-candidate.js');
const source=path.resolve(process.argv[2]),folder=path.resolve(process.argv[3]);
const raw=await fs.readFile(source),events=JSON.parse(raw),hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const before=JSON.stringify(events),batches=[];
let ackedSequence=0;
while(ackedSequence<events.length){
  const result=BrohnEventBatchPreferredCandidate.select({events,ackedSequence,operationId:`candidate-preferred-${ackedSequence+1}`,
    maxBytes:3*1024*1024,preferredBytes:1572864});
  const filename=`batch-${String(batches.length+1).padStart(2,'0')}.json`;
  await fs.writeFile(path.join(folder,filename),result.json);
  batches.push({filename,wire_bytes:result.bytes,batch:result.batch,
    maximum_key_trials:result.payload.events.filter(e=>e.payload?.data?.keys?.length===5000).length});
  ackedSequence=result.batch.last;
}
assert.equal(batches.length,6);assert.equal(JSON.stringify(events),before);
assert.equal(hash(await fs.readFile(source)),hash(raw));
await fs.writeFile(path.join(folder,'batches.json'),JSON.stringify({candidate_only:true,events:events.length,
  source_sha256:hash(raw),source_unchanged:true,preferred_bytes:1572864,new_hard_bytes:3*1024*1024,batches,
  changed:events.filter(e=>e.payload?.data?.keys?.length===5000).map(e=>({sequence:e.sequence,trial_id:e.payload.data.trial_id,keys:5000}))},null,2));
