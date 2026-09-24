// Original SC-IAT-shaped decimal observations; writes no credentials or real data.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
await import('../../www/participant/event-batch.js');
const folder=path.resolve(process.argv[2]);
const source=JSON.parse(await fs.readFile(path.join(folder,'envelope-source-event.json'),'utf8'));
const first=source.payload.data.keys[0], start=first.event_ms;
source.payload.data.keys=Array.from({length:5000},(_,i)=>({...first,type:i%2?'up':'down',event_ms:start+i/10000,
  observed_ms:start+i/10000+.000001,accepted:i===0,ignored_reason:i===0?null:i%2?'key_release':'after_first_response'}));
const events=Array.from({length:100},(_,i)=>({...structuredClone(source),sequence:i+1,id:`original-large-event-${i+1}`}));
const before=JSON.stringify(events),chosen=BrohnEventBatch.select({events,ackedSequence:0,operationId:'original-large-envelope',maxBytes:3*1024*1024});
assert.equal(before,JSON.stringify(events));assert.ok(chosen.batch.last>0&&chosen.batch.last<100);
assert.ok(Buffer.byteLength(JSON.stringify({operation_id:chosen.batch.operation_id,events:events.slice(0,chosen.batch.last+1)}),'utf8')>3*1024*1024);
assert.equal(chosen.bytes,Buffer.byteLength(chosen.json,'utf8'));
await fs.writeFile(path.join(folder,'selected-envelope.json'),chosen.json);
await fs.writeFile(path.join(folder,'envelope-selection.json'),JSON.stringify({wire_bytes:chosen.bytes,batch:chosen.batch,keys_per_event:5000,
  original_events:events.length,original_unchanged:true,scope:'Maximum-key original synthetic decimal journal shape; no participant or physical timing claim.'},null,2));
