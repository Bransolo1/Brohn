/* Inactive literal result/association checks. Declarations are not authority.
 * The journal/controller must own the pending request and current run state. */
import {verifyParticipantJsonBytes, PARTICIPANT_JSON_CODEC} from './wire-json.mjs';
import {encodeParticipantRequest} from './request-bytes.mjs';

const MAX = 4 * 1024 * 1024, END = 10000000;
const Uint8 = Uint8Array, uint8Prototype = Uint8.prototype;
const typedPrototype = Object.getPrototypeOf(uint8Prototype);
const byteLengthOf = Object.getOwnPropertyDescriptor(typedPrototype, 'byteLength').get;
const bufferOf = Object.getOwnPropertyDescriptor(typedPrototype, 'buffer').get;
const copyInto = uint8Prototype.set, arrayBufferPrototype = ArrayBuffer.prototype;
const arrayBufferLengthOf = Object.getOwnPropertyDescriptor(arrayBufferPrototype, 'byteLength').get;
const require = (ok, message) => { if (!ok) throw new TypeError(message); };
const object = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const integer = (x, min = 0, max = END) => Number.isSafeInteger(x) && x >= min && x <= max;
const hash = x => typeof x === 'string' && /^[a-f0-9]{64}$/.test(x) && x.length === 64;
const key = (x, prefix, nullable = false) => nullable && x === null || typeof x === 'string' &&
  x.length === 68 && x.startsWith(prefix + '-') && hash(x.slice(4));
function text(x, max) {
  // Match R brohn_text's UTF-8 byte ceiling and default trimws character set.
  if (typeof x !== 'string' || !x.replace(/^[ \t\r\n]+|[ \t\r\n]+$/g, '').length) return false;
  let bytes = 0;
  for (let i = 0; i < x.length; i++) {
    const c = x.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff) { bytes += 4; i++; }
    else bytes += c < 0x80 ? 1 : c < 0x800 ? 2 : 3;
    if (bytes > max) return false;
  }
  return true;
}
const bool = x => typeof x === 'boolean';
const freeze = x => { if (x !== null && typeof x === 'object') { Object.values(x).forEach(freeze); Object.freeze(x); } return x; };
function fields(x, names) {
  require(object(x) && Object.keys(x).length === names.length && names.every(n => Object.hasOwn(x, n)), 'Unsupported operation result fields.');
}
function same(a, b) {
  if (Object.is(a, b)) return true;
  if (!a || !b || typeof a !== 'object' || typeof b !== 'object' || Array.isArray(a) !== Array.isArray(b)) return false;
  const aa = Object.keys(a), bb = Object.keys(b);
  return aa.length === bb.length && aa.every(k => Object.hasOwn(b, k) && same(a[k], b[k]));
}
function noNul(value) {
  if (typeof value === 'string') { require(!value.includes('\u0000'), 'Operation model text cannot contain NUL.'); return; }
  if (value !== null && typeof value === 'object') {
    for (const name of Object.keys(value)) { noNul(name); noNul(value[name]); }
  }
}
function binding(x) {
  fields(x, ['schema', 'run_id', 'source_protocol_hash', 'renderer_identity', 'view_codec', 'view_bytes', 'view_hash']);
  const r = x.renderer_identity; fields(r, ['schema', 'id', 'manifest_hash']);
  require(x.schema === 'participant-view-binding/0.1' && key(x.run_id, 'pvu') && hash(x.source_protocol_hash) && hash(x.view_hash) &&
    x.view_codec === PARTICIPANT_JSON_CODEC && integer(x.view_bytes, 1, 16 * 1024 * 1024) &&
    r.schema === 'participant-renderer-identity/0.1' && text(r.id, 120) && /^[a-z][a-z0-9./-]*$/.test(r.id) && hash(r.manifest_hash),
  'Invalid held presentation binding.');
}
function descriptor(x, codec) {
  fields(x, ['codec', 'bytes', 'sha256']);
  require(x.codec === codec && integer(x.bytes, 1, MAX) && hash(x.sha256), 'Invalid operation byte descriptor.');
}
function sequence(s) {
  fields(s, ['first', 'last', 'count', 'prior_ack', 'committed_ack']);
  require(integer(s.prior_ack, 0, END - 1) && integer(s.count, 1, 1000) && integer(s.first, s.prior_ack + 1, s.prior_ack + 1) &&
    integer(s.last, s.first) && s.last - s.first + 1 === s.count && s.committed_ack === s.last, 'Invalid committed operation interval.');
}
function keys(x, prefix) {
  require(Array.isArray(x) && x.length <= 20000 && x.every(k => key(k, prefix)) && new Set(x).size === x.length, 'Invalid projected key array.');
}
function visit(v) {
  if (v === null) return;
  fields(v, ['id', 'step_key', 'instance_id', 'time_origin_ms', 'onset_ms', 'resumed', 'committed']);
  const decimal = x => text(x, 64) && /^[0-9]+([.][0-9]+)?$/.test(x);
  require(text(v.id, 128) && key(v.step_key, 'pvs') && text(v.instance_id, 128) && decimal(v.time_origin_ms) && decimal(v.onset_ms) &&
    bool(v.resumed) && bool(v.committed), 'Invalid projected visit.');
}
function record(r) {
  fields(r, ['step_key', 'occurrence_key', 'question_key', 'stimulus_key', 'scope', 'information', 'status', 'value',
    'ever_visited', 'dependency_generation', 'last_answer_event_id', 'answer_version', 'revision_count']);
  require(key(r.step_key, 'pvs') && key(r.occurrence_key, 'pvo') && key(r.question_key, 'pvq') && key(r.stimulus_key, 'pvi', true) &&
    ['before', 'after_each', 'end'].includes(r.scope) && bool(r.information) && bool(r.ever_visited) &&
    ['not_displayed', 'information_acknowledged', 'information_unacknowledged', 'optional_omission', 'answered', 'invalidated_unanswered', 'not_submitted'].includes(r.status) &&
    (r.last_answer_event_id === null || text(r.last_answer_event_id, 128)) &&
    ['dependency_generation', 'answer_version', 'revision_count'].every(k => integer(r[k])), 'Invalid projected questionnaire record.');
}
function packet(p, held, ack) {
  fields(p, ['schema', 'view_hash', 'acknowledged_sequence', 'cursor', 'next_step_key', 'packet_state_token', 'latest_occurrence',
    'last_transition', 'actions', 'resume_page']);
  require(p.schema === 'participant-questionnaire-packet/0.1' && p.view_hash === held.view_hash && p.acknowledged_sequence === ack &&
    integer(p.cursor, 1, 20001) && key(p.next_step_key, 'pvs', true) && hash(p.packet_state_token), 'Packet differs from the committed view or ACK.');
  const l = p.latest_occurrence;
  if (l !== null) {
    fields(l, ['occurrence_key', 'state_version', 'sealed', 'review_step_key', 'projection_token', 'visit']);
    require(key(l.occurrence_key, 'pvo') && integer(l.state_version) && bool(l.sealed) && key(l.review_step_key, 'pvs') && hash(l.projection_token), 'Invalid latest occurrence.');
    visit(l.visit);
  }
  const t = p.last_transition;
  if (t !== null) {
    fields(t, ['occurrence_key', 'kind', 'state_version', 'sealed', 'projection_token']);
    require(key(t.occurrence_key, 'pvo') && ['visit', 'commit', 'acknowledge', 'seal'].includes(t.kind) && integer(t.state_version) &&
      bool(t.sealed) && (t.projection_token === null || hash(t.projection_token)), 'Invalid questionnaire transition.');
  }
  const a = p.actions;
  fields(a, ['enter_step_key', 'next_step_key', 'back_step_key', 'editable_step_keys', 'can_seal']);
  require(['enter_step_key', 'next_step_key', 'back_step_key'].every(k => key(a[k], 'pvs', true)) && bool(a.can_seal), 'Invalid questionnaire actions.');
  keys(a.editable_step_keys, 'pvs');
  const q = p.resume_page;
  fields(q, ['schema', 'view_hash', 'resume_state_token', 'active_occurrence_key', 'state_version', 'visit', 'visible_step_keys', 'records',
    'total_records', 'offset', 'next_offset']);
  require(q.schema === 'participant-questionnaire-resume/0.1' && q.view_hash === held.view_hash && hash(q.resume_state_token) &&
    key(q.active_occurrence_key, 'pvo', true) && (q.state_version === null || integer(q.state_version)) && Array.isArray(q.records) &&
    integer(q.total_records, 0, 20000) && integer(q.offset, 0, q.total_records) && q.records.length <= q.total_records - q.offset, 'Invalid questionnaire page.');
  visit(q.visit); keys(q.visible_step_keys, 'pvs');
  require(q.active_occurrence_key === null ? q.state_version === null && q.visit === null && q.visible_step_keys.length === 0 :
    q.state_version !== null, 'Invalid active questionnaire page.');
  const end = q.offset + q.records.length;
  require(end === q.total_records ? q.next_offset === null : end > q.offset && q.next_offset === end, 'Invalid whole-record continuation.');
  q.records.forEach(record);
  require(new Set(q.records.map(r => r.step_key)).size === q.records.length, 'Duplicate projected questionnaire records.');
}
function resume(r, held, ack) {
  fields(r, ['schema', 'view_hash', 'next_step_key', 'completed_step_keys', 'active_step_key', 'active_clock_instance_id', 'answers', 'questionnaire']);
  require(r.schema === 'participant-forward-resume/0.1' && r.view_hash === held.view_hash && key(r.next_step_key, 'pvs', true) &&
    key(r.active_step_key, 'pvs', true) && (r.active_step_key === null ? r.active_clock_instance_id === null : text(r.active_clock_instance_id, 128)),
  'Invalid committed resume.');
  keys(r.completed_step_keys, 'pvs'); fields(r.answers, ['before', 'after_each', 'end']);
  const scope = x => require(object(x) && Object.keys(x).every(k => key(k, 'pvq')), 'Invalid projected answer keys.');
  scope(r.answers.before); scope(r.answers.end);
  require(object(r.answers.after_each) && Object.keys(r.answers.after_each).every(k => key(k, 'pvi')), 'Invalid stimulus answer keys.');
  Object.values(r.answers.after_each).forEach(scope);
  if (r.questionnaire !== null) {
    packet(r.questionnaire, held, ack);
    require(r.questionnaire.next_step_key === r.next_step_key, 'Packet and forward cursors disagree.');
  }
}

// Only called after strict complete JSON admission. Select the actual raw span;
// do not use JSON.stringify, which changes R's finite-number spelling and -0.
function memberSpan(source, path) {
  let at = 0;
  const white = () => { while (' \t\r\n'.includes(source[at]) && at < source.length) at++; };
  function string() {
    const start = at++;
    while (at < source.length) { const c = source[at++]; if (c === '\\') at++; else if (c === '"') return [start, at]; }
    throw new TypeError('Missing admitted string span.');
  }
  function value(route) {
    white(); const start = at, c = source[at];
    if (!route.length) { skip(); return [start, at]; }
    require(c === '{', 'Missing admitted object path.'); at++; white();
    while (source[at] !== '}') {
      const span = string(), name = JSON.parse(source.slice(...span)); white(); at++; white();
      if (name === route[0]) return value(route.slice(1));
      skip(); white(); if (source[at] === ',') { at++; white(); } else break;
    }
    throw new TypeError('Missing admitted member span.');
  }
  function skip() {
    white(); const c = source[at];
    if (c === '"') { string(); return; }
    if (c === '{' || c === '[') {
      const close = c === '{' ? '}' : ']'; at++; white();
      while (source[at] !== close) {
        if (c === '{') { string(); white(); at++; }
        skip(); white(); if (source[at] === ',') { at++; white(); } else break;
      }
      require(source[at++] === close, 'Invalid admitted container span.'); return;
    }
    while (at < source.length && !' \t\r\n,}]'.includes(source[at])) at++;
  }
  return value(path);
}
async function digest(bytes) {
  require(globalThis.crypto?.subtle, 'WebCrypto is required to retain result bytes.');
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
}

export async function admitParticipantOperationResult({resultBytes, binding: suppliedBinding, pending: suppliedPending}) {
  require(resultBytes && Object.getPrototypeOf(resultBytes) === uint8Prototype, 'An actual response byte array is required.');
  const length = Reflect.apply(byteLengthOf, resultBytes, []), buffer = Reflect.apply(bufferOf, resultBytes, []);
  // Brand check also refuses a SharedArrayBuffer with a forged prototype.
  Reflect.apply(arrayBufferLengthOf, buffer, []);
  require(Object.getPrototypeOf(buffer) === arrayBufferPrototype && integer(length, 1, MAX), 'A bounded nonshared response byte array is required.');
  const raw = new Uint8(length);
  // Intrinsics bypass shadowed length/buffer properties and constructor/species.
  Reflect.apply(copyInto, raw, [resultBytes]);
  require(!(raw[0] === 0xef && raw[1] === 0xbb && raw[2] === 0xbf), 'A result cannot start with a UTF-8 BOM.');
  const json = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(raw);
  // This encoder snapshots both declarations synchronously before WebCrypto.
  const declarations = encodeParticipantRequest({binding: suppliedBinding, pending: suppliedPending});
  const captured = JSON.parse((await declarations).json), held = captured.binding, pending = captured.pending;
  binding(held); fields(pending, ['operation_id', 'request', 'sequence']);
  require(text(pending.operation_id, 128), 'A pending operation identity is required.');
  descriptor(pending.request, 'brohn-participant-request-json/0.1'); sequence(pending.sequence);
  const resultDocument = {codec: PARTICIPANT_JSON_CODEC, bytes: raw.byteLength, sha256: await digest(raw)};
  const outer = (await verifyParticipantJsonBytes(json, resultDocument, {maximumBytes: MAX})).value;
  fields(outer, ['schema', 'receipt', 'model_json']);
  require(outer.schema === 'participant-view-events-result/0.1', 'Unsupported operation result schema.');
  const receipt = outer.receipt;
  fields(receipt, ['schema', 'binding', 'operation_id', 'request', 'sequence', 'model']);
  require(receipt.schema === 'participant-view-operation-receipt/0.1' && same(receipt.binding, held) &&
    receipt.operation_id === pending.operation_id && same(receipt.request, pending.request) && same(receipt.sequence, pending.sequence),
  'The result does not confirm this pending operation and presentation.');
  descriptor(receipt.model, PARTICIPANT_JSON_CODEC);
  const model = (await verifyParticipantJsonBytes(outer.model_json, receipt.model, {maximumBytes: MAX})).value;
  noNul(model);
  fields(model, ['schema', 'binding', 'acknowledged_sequence', 'expected_sequence', 'completion_status', 'resume', 'origin', 'release_status', 'researcher_resolution']);
  require(model.schema === 'participant-view-commit-model/0.1' && same(model.binding, held) &&
    model.acknowledged_sequence === pending.sequence.committed_ack && model.expected_sequence === model.acknowledged_sequence + 1 &&
    model.completion_status === 'in_progress' && ['sample', 'pilot', 'live'].includes(model.origin) &&
    ['open', 'paused', 'closed'].includes(model.release_status) && model.researcher_resolution === null, 'Invalid recorded commit-state model.');
  resume(model.resume, held, model.acknowledged_sequence);
  if (model.resume.questionnaire !== null) {
    const span = memberSpan(outer.model_json, ['resume', 'questionnaire']);
    require(new TextEncoder().encode(outer.model_json.slice(...span)).byteLength <= 3 * 1024 * 1024, 'The exact questionnaire packet exceeds its byte limit.');
  }
  return freeze({result: {...resultDocument, json}, model: {...receipt.model, json: outer.model_json}, receipt, value: model});
}
