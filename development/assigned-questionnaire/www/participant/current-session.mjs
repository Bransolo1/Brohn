/* Inactive literal current-session admission. HTTP authority is sender-owned. */
import {verifyParticipantJsonBytes, PARTICIPANT_JSON_CODEC} from './wire-json.mjs';
import {encodeParticipantRequest} from './request-bytes.mjs';
import {MAX, END, require, fields, same, noNul, binding, resume, memberSpan, digest, freeze, integer, key, text, bool} from './current-structure.mjs';
const U8 = Uint8Array, typed = Object.getPrototypeOf(U8.prototype);
const lengthOf = Object.getOwnPropertyDescriptor(typed, 'byteLength').get;
const bufferOf = Object.getOwnPropertyDescriptor(typed, 'buffer').get;
const abLength = Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'byteLength').get;
const set = U8.prototype.set;
function capture(value) {
  require(value && Object.getPrototypeOf(value) === U8.prototype, 'Actual current response bytes are required.');
  const size = Reflect.apply(lengthOf, value, []), buffer = Reflect.apply(bufferOf, value, []);
  Reflect.apply(abLength, buffer, []);
  require(Object.getPrototypeOf(buffer) === ArrayBuffer.prototype && integer(size, 1, MAX), 'Current response exceeds its byte domain.');
  const raw = new U8(size); Reflect.apply(set, raw, [value]); return raw;
}
export async function admitParticipantCurrentSession({currentBytes, binding: supplied, viewJson, accessToken}) {
  const raw = capture(currentBytes);
  const declarations = encodeParticipantRequest({binding: supplied, viewJson, accessToken});
  const held = JSON.parse((await declarations).json); binding(held.binding);
  require(typeof held.accessToken === 'string' && held.accessToken.length === 64 && /^[a-f0-9]{64}$/.test(held.accessToken), 'An exact held run credential is required.');
  require(!(raw[0] === 239 && raw[1] === 187 && raw[2] === 191), 'Current response cannot contain a BOM.');
  const json = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(raw);
  const document = {codec: PARTICIPANT_JSON_CODEC, bytes: raw.byteLength, sha256: await digest(raw)};
  const session = (await verifyParticipantJsonBytes(json, document, {maximumBytes: MAX})).value;
  noNul(session);
  fields(session, ['schema','run_id','access_token','view_json','binding','resources','expected_sequence','completion_status','resume','origin','release_status','researcher_resolution']);
  require(session.schema === 'participant-view-session/0.1' && same(session.binding, held.binding) &&
    session.run_id === held.binding.run_id && session.access_token === held.accessToken && session.view_json === held.viewJson,
  'Current response belongs to a different held presentation or credential.');
  const view = (await verifyParticipantJsonBytes(session.view_json, {codec: held.binding.view_codec,
    bytes: held.binding.view_bytes, sha256: held.binding.view_hash})).value;
  noNul(view);
  require(view.schema === 'brohn-participant-view/0.1' && view.run_id === held.binding.run_id &&
    view.source_protocol_hash === held.binding.source_protocol_hash && same(view.renderer_identity, held.binding.renderer_identity), 'Current view identity differs.');
  require(integer(session.expected_sequence, 1, END + 1) && ['in_progress','completed','withdrawn','interrupted'].includes(session.completion_status) &&
    ['sample','pilot','live'].includes(session.origin) && ['open','paused','closed'].includes(session.release_status), 'Invalid current session progress.');
  const ack = session.expected_sequence - 1;
  resume(session.resume, held.binding, ack);
  if (session.resume.questionnaire !== null) {
    const span = memberSpan(json, ['resume','questionnaire']);
    require(new TextEncoder().encode(json.slice(...span)).byteLength <= 3 * 1024 * 1024, 'Current questionnaire packet exceeds its exact byte limit.');
  }
  const resources = view.presentation?.resources;
  require(Array.isArray(resources) && resources.every(x => x && key(x.resource_key, 'pvr')) &&
    new Set(resources.map(x => x.resource_key)).size === resources.length, 'Held resource registry is invalid.');
  fields(session.resources, resources.map(x => x.resource_key));
  for (const resource of resources) require(session.resources[resource.resource_key] ===
    `/api/view/resources/${held.binding.run_id}/${resource.resource_key}`, 'Current resource route differs from the exact assigned registry.');
  const resolution = session.researcher_resolution;
  if (resolution !== null) {
    fields(resolution, ['schema','resolved','effective_resolution','participant_ending','acknowledged_sequence','received_camera_bytes','final_receipt_missing','message']);
    require(resolution.schema === 'brohn-participant-resolution/1.0' && resolution.resolved === true &&
      ['researcher_interrupted','received_completion_confirmed','participant_ending_preserved'].includes(resolution.effective_resolution) &&
      (resolution.participant_ending === null || ['completed','withdrawn','interrupted'].includes(resolution.participant_ending)) &&
      resolution.acknowledged_sequence === ack && integer(resolution.received_camera_bytes, 0, Number.MAX_SAFE_INTEGER) &&
      bool(resolution.final_receipt_missing) && text(resolution.message, 4096), 'Invalid current researcher resolution.');
  }
  // Deliberately omit the credential and whole current JSON from public state.
  const {access_token, ...publicSession} = session;
  return freeze({document, session: publicSession, acknowledged_sequence: ack});
}
