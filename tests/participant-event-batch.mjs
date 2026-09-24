// Pure envelope contract; receiver canonical JSON validation is qualified separately.
import assert from 'node:assert/strict';
await import('../www/participant/event-batch.js');
const {select, MAX_BYTES, MAX_EVENTS} = globalThis.BrohnEventBatch;
let checks = 0;
const check = (label, run) => {run(); checks++; console.log('PASS', label);};
const event = (sequence, value = '') => ({sequence, type: 'response', payload: {value}});
const wire = (operation_id, events) => JSON.stringify({operation_id, events});
const bytes = text => Buffer.byteLength(text, 'utf8');
const base = (events, extra = {}) => ({events, ackedSequence: 0, operationId: 'original-operation', ...extra});
const rejects = (fn, code) => assert.throws(fn, e => e.code === code && e.permanent === true && e.retained === true && /retained/.test(e.message));
const freeze = object => {if (object && typeof object === 'object') {Object.values(object).forEach(freeze); Object.freeze(object);} return object;};
function padded(sequence, size, prior = [], operationId = 'original-operation', suffix = '') {
  const empty = event(sequence, suffix), overhead = bytes(wire(operationId, [...prior, empty]));
  assert.ok(size >= overhead);
  return event(sequence, 'x'.repeat(size - overhead) + suffix);
}
check('Receiver constants and empty acknowledged journals', () => {
  assert.equal(MAX_BYTES, 4194304); assert.equal(MAX_EVENTS, 100);
  assert.equal(select(base([])), null);
  assert.equal(select(base([event(1)], {ackedSequence: 1})), null);
});
check('Maximum 100 complete ordered events, with later rows retained', () => {
  const events = Array.from({length: 103}, (_, i) => event(i + 1, i));
  const result = select(base(events));
  assert.equal(result.payload.events.length, 100);
  assert.deepEqual(result.batch, {operation_id: 'original-operation', first: 1, last: 100});
  assert.equal(events.length, 103); assert.equal(result.bytes, bytes(wire('original-operation', events.slice(0, 100))));
});
check('Acknowledged prefix excluded, next exact contiguous suffix selected', () => {
  const events = [event(4), event(5), event(6), event(7)];
  const result = select(base(events, {ackedSequence: 5}));
  assert.deepEqual(result.payload.events, events.slice(2));
  assert.equal(result.batch.first, 6); assert.equal(result.batch.last, 7);
});
check('Exactly 4 MiB wire body fits; entire following event remains pending', () => {
  const events = [padded(1, MAX_BYTES), event(2)];
  const result = select(base(events));
  assert.equal(result.bytes, MAX_BYTES); assert.equal(bytes(result.json), MAX_BYTES);
  assert.deepEqual(result.payload.events, events.slice(0, 1));
  assert.equal(result.json, wire('original-operation', result.payload.events));
});
check('One byte over single-event limit refuses without truncation', () => {
  const events = freeze([padded(1, MAX_BYTES + 1)]), original = wire('original-operation', events);
  rejects(() => select(base(events)), 'single_event_oversize');
  assert.equal(wire('original-operation', events), original);
});
check('Largest two-event prefix includes comma, envelope and escaped operation', () => {
  const operationId = 'op-"\\\n', first = event(1, 'prefix');
  const events = [first, padded(2, MAX_BYTES, [first], operationId), event(3)];
  const result = select(base(events, {operationId}));
  assert.equal(result.bytes, MAX_BYTES); assert.equal(result.payload.events.length, 2);
  assert.ok(bytes(wire(operationId, events)) > MAX_BYTES);
});
check('Multibyte text, astral characters, escapes and lone surrogates use actual UTF-8 JSON bytes', () => {
  const text = 'é漢🧠\n\t"\\\ud800', events = [event(1, text.repeat(2000)), event(2, text)];
  const result = select(base(events, {operationId: '研究🧠'}));
  assert.equal(result.bytes, bytes(wire('研究🧠', events)));
  assert.equal(result.json, wire('研究🧠', events)); assert.deepEqual(result.payload.events, events);
});
check('Multibyte exact-boundary selection never uses JS string length', () => {
  const empty = bytes(wire('original-operation', [event(1)]));
  const remaining = MAX_BYTES - empty;
  const value = 'é'.repeat(Math.floor(remaining / 2)) + 'x'.repeat(remaining % 2);
  const events = [event(1, value), event(2)];
  const result = select(base(events));
  assert.equal(result.bytes, MAX_BYTES); assert.equal(result.payload.events.length, 1);
  assert.ok(result.json.length < result.bytes);
});
check('Persisted operation preserves original id and exact bounds despite a replacement id', () => {
  const events = [event(1), event(2), event(3)], batch = freeze({operation_id: 'original-op', first: 1, last: 2});
  const result = select(base(events, {batch, operationId: 'never-used'}));
  assert.equal(result.reused, true); assert.deepEqual(result.batch, batch);
  assert.equal(result.json, wire('original-op', events.slice(0, 2)));
});
check('Persisted oversized operation refuses, never shrinks or silently changes identity', () => {
  const events = freeze([padded(1, MAX_BYTES), event(2)]);
  const batch = freeze({operation_id: 'original-operation', first: 1, last: 2});
  rejects(() => select(base(events, {batch})), 'persisted_batch_oversize');
  assert.equal(batch.last, 2); assert.equal(events[0].payload.value.length, MAX_BYTES - bytes(wire('original-operation', [event(1)])));
});
check('Gap at first unacknowledged event refuses rather than skipping', () => {
  rejects(() => select(base([event(2)])), 'event_sequence_gap');
});
check('Gap inside candidate prefix refuses rather than fabricating a contiguous batch', () => {
  rejects(() => select(base([event(1), event(3)])), 'event_sequence_gap');
});
check('Persisted missing last event or changed acknowledgement refuses exact reconstruction', () => {
  const batch = {operation_id: 'op', first: 1, last: 2};
  rejects(() => select(base([event(1)], {batch})), 'event_sequence_gap');
  rejects(() => select(base([event(1), event(2)], {batch, ackedSequence: 1})), 'persisted_batch_invalid');
});
check('Duplicate and reordered journal sequences are not sorted or deduplicated', () => {
  rejects(() => select(base([event(1), event(1)])), 'event_sequence_invalid');
  rejects(() => select(base([event(2), event(1)])), 'event_sequence_invalid');
});
check('Gap beyond the capped prefix is retained and refused on its own subsequent selection', () => {
  const events = [...Array.from({length: 100}, (_, i) => event(i + 1)), event(102)];
  assert.equal(select(base(events)).batch.last, 100);
  rejects(() => select(base(events, {ackedSequence: 100})), 'event_sequence_gap');
});
check('Saved journal and batch remain deeply unchanged on success and output mutation', () => {
  const events = freeze([event(1, {nested: ['complete', 0, false, null]})]), before = JSON.stringify(events);
  const result = select(base(events)); result.payload.events[0].payload.value.nested.push('caller-only');
  assert.equal(JSON.stringify(events), before); assert.equal(JSON.parse(result.json).events[0].payload.value.nested.length, 4);
});
check('Nonfinite, undefined and cyclic observations are refused instead of lossy JSON conversion', () => {
  for (const value of [NaN, Infinity, undefined, BigInt(1)]) rejects(() => select(base([event(1, {value})])), 'event_not_json');
  const cyclic = {}; cyclic.self = cyclic; rejects(() => select(base([event(1, cyclic)])), 'event_not_json');
});
check('Invalid journal, acknowledgements, operation ids and persisted bounds have explicit retained-data errors', () => {
  rejects(() => select(base({}, {})), 'event_journal_invalid');
  rejects(() => select(base([], {ackedSequence: -1})), 'event_journal_invalid');
  rejects(() => select(base([event(1)], {operationId: ''})), 'event_operation_invalid');
  rejects(() => select(base([event(1)], {batch: {operation_id: 'op', first: 1, last: 101}})), 'persisted_batch_invalid');
});
check('Optional smaller new-batch envelope selects exact prefix at its own byte boundary', () => {
  const first = event(1, 'first'), second = event(2, 'second'), maxBytes = bytes(wire('original-operation', [first, second]));
  const result = select(base([first, second, event(3)], {maxBytes}));
  assert.equal(result.bytes, maxBytes); assert.equal(result.batch.last, 2);
  rejects(() => select(base([first], {maxBytes: 1})), 'single_event_oversize');
});
check('Reduced new-operation budget does not split a persisted operation that fits receiver limit', () => {
  const events = [padded(1, MAX_BYTES)], batch = {operation_id: 'original-operation', first: 1, last: 1};
  const result = select(base(events, {maxBytes: 3 * 1024 * 1024, batch}));
  assert.equal(result.bytes, MAX_BYTES); assert.deepEqual(result.batch, batch);
});
check('Optional limit is an integer from one byte through 4 MiB', () => {
  for (const maxBytes of [0, -1, 1.5, NaN, Infinity, MAX_BYTES + 1, '100'])
    rejects(() => select(base([event(1)], {maxBytes})), 'event_limit_invalid');
});
check('Large implicit-task journals retain every key observation and select maximal complete events', () => {
  const observations = Array.from({length: 5000}, (_, index) => ({key: index % 2 ? 'ArrowLeft' : 'ArrowRight', time_ms: index / 3, observed: true}));
  const events = Array.from({length: 30}, (_, index) => event(index + 1, {key_observations: observations}));
  const result = select(base(events, {maxBytes: 3 * 1024 * 1024}));
  assert.ok(result.batch.last > 1 && result.batch.last < 30);
  assert.ok(bytes(wire('original-operation', events.slice(0, result.batch.last))) <= 3 * 1024 * 1024);
  assert.ok(bytes(wire('original-operation', events.slice(0, result.batch.last + 1))) > 3 * 1024 * 1024);
  result.payload.events.forEach(row => assert.deepEqual(row.payload.value.key_observations, observations));
  assert.equal(events.length, 30); assert.equal(observations.length, 5000);
});
const preferredBytes=1572864,hard=3*1024*1024;
check('Preferred prefix includes exact boundary while preserving complete next event',()=>{
  const events=freeze([event(1,'first'),padded(2,preferredBytes,[event(1,'first')]),event(3)]);
  const result=select(base(events,{maxBytes:hard,preferredBytes}));
  assert.equal(result.bytes,preferredBytes);assert.equal(result.batch.last,2);assert.equal(events.length,3);
});
check('Indivisible first event one byte above preference is sent whole and alone',()=>{
  const events=freeze([padded(1,preferredBytes+1),event(2)]),before=JSON.stringify(events);
  const result=select(base(events,{maxBytes:hard,preferredBytes}));
  assert.equal(result.bytes,preferredBytes+1);assert.equal(result.batch.last,1);assert.equal(JSON.stringify(events),before);
});
check('Whole first-event fallback reaches unchanged exact3MiB hard limit',()=>{
  const events=freeze([padded(1,hard),event(2)]);
  const result=select(base(events,{maxBytes:hard,preferredBytes}));
  assert.equal(result.bytes,hard);assert.equal(result.batch.last,1);assert.deepEqual(result.payload.events,events.slice(0,1));
  rejects(()=>select(base([padded(1,hard+1)],{maxBytes:hard,preferredBytes})),'single_event_oversize');
});
check('A later large indivisible event waits without truncation then becomes its own fallback',()=>{
  const events=freeze([event(1,'short'),padded(2,hard),event(3)]);
  const first=select(base(events,{maxBytes:hard,preferredBytes}));assert.equal(first.batch.last,1);
  const second=select(base(events,{ackedSequence:1,maxBytes:hard,preferredBytes}));
  assert.equal(second.batch.first,2);assert.equal(second.batch.last,2);assert.equal(second.bytes,hard);
});
check('Persisted operation keeps exact4MiB identity and bytes under1.5MiB preference and3MiB new hard limit',()=>{
  const events=freeze([padded(1,MAX_BYTES)]),batch=freeze({operation_id:'original-operation',first:1,last:1});
  const result=select(base(events,{batch,maxBytes:hard,preferredBytes,operationId:'never-used'}));
  assert.deepEqual(result.batch,batch);assert.equal(result.bytes,MAX_BYTES);assert.equal(result.json,wire(batch.operation_id,events));
});
check('Preferred UTF-8 exact boundary counts multibyte and escaped operation bytes',()=>{
  const operationId='研究🧠"',first=event(1,'é漢🧠'),second=event(2,'complete'),target=bytes(wire(operationId,[first,second]));
  const result=select(base(freeze([first,second,event(3)]),{operationId,maxBytes:hard,preferredBytes:target}));
  assert.equal(result.bytes,target);assert.equal(result.batch.last,2);assert.equal(result.json,wire(operationId,[first,second]));
});
check('Preference accepts only integer1throughhardlimit',()=>{
  for(const preferredBytes of [0,-1,1.5,NaN,Infinity,hard+1,'100'])
    rejects(()=>select(base([event(1)],{maxBytes:hard,preferredBytes})),'event_preference_invalid');
});
check('Default hard-limit selection retains independently specified exact envelope fields', () => {
  const events = freeze([event(1, 'plain'), event(2, 'é')]);
  const json = wire('original-operation', events);
  const result = select(base(events, {maxBytes: hard}));
  assert.deepEqual(result, {batch: {operation_id: 'original-operation', first: 1, last: 2},
    payload: {operation_id: 'original-operation', events}, json, bytes: bytes(json), reused: false});
  assert.notEqual(result.payload.events, events);
});
check('Default exact-hard-boundary retains refusal of a following sequence gap', () => {
  rejects(() => select(base(freeze([padded(1, MAX_BYTES), event(3)]))), 'event_sequence_gap');
});
console.log(JSON.stringify({passed: checks, scope: 'Production pure exact UTF-8 wire envelope selection; receiver and browser acceptance are qualified separately.'}));
