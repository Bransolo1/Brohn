/* Private, durable finish-operation custody. This module does not decide that
 * a study is complete: the authenticated R finish route remains authoritative. */
import {encodeParticipantRequest, PARTICIPANT_REQUEST_CODEC} from './request-bytes.mjs';
import {verifyParticipantJsonBytes, PARTICIPANT_JSON_CODEC} from './wire-json.mjs';
import {binding as checkBinding, fields, same, freeze, hash, text, integer, digest} from './current-structure.mjs';

const DATABASE = 'brohn-assigned-finishes', VERSION = 1, MAX = 4 * 1024 * 1024, END = 10000000;
const U8 = Uint8Array, typed = Object.getPrototypeOf(U8.prototype);
const lengthOf = Object.getOwnPropertyDescriptor(typed, 'byteLength').get;
const bufferOf = Object.getOwnPropertyDescriptor(typed, 'buffer').get;
const abLength = Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'byteLength').get;
const set = U8.prototype.set;
const failure = (code, message, cause) => Object.assign(new Error(message), {code, retained: true, ...(cause ? {cause} : {})});
const need = (ok, code, message) => {if (!ok) throw failure(code, message);};
const outcomes = ['completed', 'interrupted', 'withdrawn'];

function capture(raw) {
  need(raw && Object.getPrototypeOf(raw) === U8.prototype, 'finish_response', 'The original finish response bytes are required.');
  const bytes = Reflect.apply(lengthOf, raw, []), buffer = Reflect.apply(bufferOf, raw, []);
  Reflect.apply(abLength, buffer, []);
  need(Object.getPrototypeOf(buffer) === ArrayBuffer.prototype && integer(bytes, 1, MAX),
    'finish_response', 'The finish response exceeds its supported size.');
  const copy = new U8(bytes); Reflect.apply(set, copy, [raw]); return copy;
}
function documentShape(doc, codec) {
  fields(doc, ['codec', 'json', 'bytes', 'sha256']);
  need(doc.codec === codec && typeof doc.json === 'string' && doc.json.length <= MAX &&
    integer(doc.bytes, 1, MAX) && hash(doc.sha256), 'finish_integrity', 'The saved finish document is damaged.');
}
function intentShape(intent) {
  fields(intent, ['outcome', 'finalSequence']);
  need(outcomes.includes(intent.outcome) && integer(intent.finalSequence, 0, END),
    'finish_intent', 'Keep the original ending and the final saved response sequence.');
}
function requestShape(request, binding) {
  fields(request, ['schema', 'view_hash', 'request']);
  fields(request.request, ['outcome', 'final_sequence', 'operation_id']);
  need(request.schema === 'participant-view-finish/0.1' && request.view_hash === binding.view_hash &&
    outcomes.includes(request.request.outcome) && integer(request.request.final_sequence, 0, END) &&
    text(request.request.operation_id, 128), 'finish_integrity', 'The saved finish request differs from the original session.');
}
async function responseDocument(raw, binding, request) {
  need(!(raw[0] === 239 && raw[1] === 187 && raw[2] === 191), 'finish_response', 'The finish response has an unsupported byte marker.');
  const json = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(raw);
  const descriptor = {codec: PARTICIPANT_JSON_CODEC, json, bytes: raw.byteLength, sha256: await digest(raw)};
  const value = (await verifyParticipantJsonBytes(json, {codec: descriptor.codec, bytes: descriptor.bytes, sha256: descriptor.sha256}, {maximumBytes: MAX})).value;
  fields(value, ['schema', 'binding', 'operation_id', 'receipt']); fields(value.receipt, ['status', 'outcome']);
  need(value.schema === 'participant-view-finish-result/0.1' && same(value.binding, binding) &&
    value.operation_id === request.request.operation_id && value.receipt.status === 'saved' &&
    value.receipt.outcome === request.request.outcome, 'finish_response', 'The finish confirmation does not match the original saved ending.');
  return freeze(descriptor);
}
function lockFinish(runId) {
  need(globalThis.navigator?.locks && globalThis.indexedDB && globalThis.crypto?.subtle && globalThis.crypto?.randomUUID,
    'finish_storage', 'Allow secure browser storage to save this study ending.');
  return new Promise((resolve, reject) => {
    const lifetime = navigator.locks.request(`brohn-assigned-finish:${runId}`, {mode: 'exclusive', ifAvailable: true}, lock => {
      if (!lock) {reject(failure('finish_busy', 'This study ending is already open in another tab.')); return;}
      return new Promise(release => resolve({release, lifetime: () => lifetime}));
    });
    lifetime.catch(reject);
  });
}
function database() {
  return new Promise((resolve, reject) => {
    let refused = false, original = null;
    const request = indexedDB.open(DATABASE, VERSION);
    request.onupgradeneeded = () => {
      if (refused) {request.transaction.abort(); return;}
      try {request.result.createObjectStore('finishes', {keyPath: 'run_id'});}
      catch (error) {original = error; request.transaction.abort();}
    };
    request.onerror = () => reject(failure('finish_storage', 'The saved study ending could not be opened.', original || request.error));
    request.onblocked = () => {refused = true; reject(failure('finish_blocked', 'Close other study tabs before reopening the saved ending.'));};
    request.onsuccess = () => {if (refused) request.result.close(); else resolve(request.result);};
  });
}
function transaction(db, mode, action) {
  return new Promise((resolve, reject) => {
    let tx, result, original = null;
    try {tx = mode === 'readwrite' ? db.transaction('finishes', mode, {durability: 'strict'}) : db.transaction('finishes', mode);}
    catch (error) {reject(error); return;}
    const guard = fn => (...args) => {
      try {fn(...args);} catch (error) {original ||= error; try {tx.abort();} catch (_) {}}
    };
    tx.oncomplete = () => resolve(result);
    tx.onabort = () => reject(original || failure('finish_storage', 'The ending was not confirmed saved. Keep the original study progress.', tx.error));
    tx.onerror = () => {};
    guard(() => {
      need(mode !== 'readwrite' || tx.durability === 'strict', 'finish_storage', 'This browser cannot confirm the required durable finish save.');
      action(tx.objectStore('finishes'), guard, value => {result = value;});
    })();
  });
}

export async function openParticipantFinishSession(input) {
  const settings = JSON.parse((await encodeParticipantRequest(input)).json);
  fields(settings, ['binding']); checkBinding(settings.binding);
  const binding = freeze(settings.binding), runId = binding.run_id, lock = await lockFinish(runId);
  let db, accepting = true, closing = null, tail = Promise.resolve();
  const active = () => need(accepting, 'finish_closed', 'Reopen this study to recover its saved ending.');
  const queue = action => {active(); const p = tail.then(action); tail = p.catch(() => {}); return p;};
  function close() {
    if (!closing) {accepting = false; closing = tail.then(() => {db?.close(); lock.release(); return lock.lifetime();});}
    return closing;
  }
  function rowShape(row) {
    if (row === undefined) return;
    fields(row, ['schema', 'run_id', 'binding', 'revision', 'request', 'response']);
    need(row.schema === 'participant-finish-custody/0.1' && row.run_id === runId && same(row.binding, binding) &&
      [1, 2].includes(row.revision), 'finish_integrity', 'The saved ending belongs to a different original study.');
    documentShape(row.request, PARTICIPANT_REQUEST_CODEC);
    need((row.revision === 1) === (row.response === null), 'finish_integrity', 'The saved finish progress is inconsistent.');
    if (row.response !== null) documentShape(row.response, PARTICIPANT_JSON_CODEC);
  }
  async function inspect(row) {
    rowShape(row); if (row === undefined) return null;
    const request = JSON.parse(row.request.json); requestShape(request, binding);
    need(same(await encodeParticipantRequest(request), row.request), 'finish_integrity', 'The original finish request failed its byte check.');
    if (row.response !== null) {
      const received = await responseDocument(new TextEncoder().encode(row.response.json), binding, request);
      need(same(received, row.response), 'finish_integrity', 'The saved finish confirmation failed its byte check.');
    }
    return {row, request};
  }
  const read = () => transaction(db, 'readonly', (store, guard, done) => {
    const get = store.get(runId); get.onsuccess = guard(() => done(get.result));
  });
  const compare = (oldRow, nextRow) => transaction(db, 'readwrite', (store, guard, done) => {
    const get = store.get(runId); get.onsuccess = guard(() => {
      rowShape(get.result);
      need(same(get.result, oldRow), 'finish_changed', 'The saved ending changed. Reopen the same study without replacing it.');
      const put = oldRow === undefined ? store.add(nextRow) : store.put(nextRow);
      put.onsuccess = guard(() => done(nextRow));
    });
  });
  try {
    db = await database(); db.onversionchange = () => {void close();}; db.onclose = () => {void close();};
    const initialization = read().then(inspect); tail = initialization.catch(() => {});
    await initialization; active();
  } catch (error) {await close(); throw error;}
  return Object.freeze({
    close,
    state() {return queue(async () => {const original = await inspect(await read());
      return freeze({schema: 'participant-finish-state/0.1', phase: !original ? 'empty' : original.row.response ? 'saved' : 'pending',
        request_saved: !!original, receipt_saved: !!original?.row.response,
        outcome: original?.request.request.outcome ?? null, final_sequence: original?.request.request.final_sequence ?? null});});},
    prepare(intent) {
      // Copy the explicit decision before a storage wait. This API never reads
      // a clock, recreates a terminal event, or changes an existing operation.
      const input = encodeParticipantRequest(intent).then(value => ({value}), error => ({error}));
      return queue(async () => {
        const captured = await input; if (captured.error) throw captured.error;
        const choice = JSON.parse(captured.value.json); intentShape(choice);
        const original = await inspect(await read());
        if (original) {
          need(original.request.request.outcome === choice.outcome && original.request.request.final_sequence === choice.finalSequence,
            'finish_conflict', 'An ending is already saved. Retry it without changing its outcome or final response sequence.');
          return freeze(original.row.request);
        }
        const request = await encodeParticipantRequest({schema: 'participant-view-finish/0.1', view_hash: binding.view_hash,
          request: {outcome: choice.outcome, final_sequence: choice.finalSequence, operation_id: `finish-${crypto.randomUUID()}`}});
        requestShape(JSON.parse(request.json), binding);
        const row = {schema: 'participant-finish-custody/0.1', run_id: runId, binding, revision: 1, request, response: null};
        rowShape(row); await compare(undefined, row); return freeze(request);
      });
    },
    pendingRequest() {return queue(async () => {const value = await inspect(await read()); return value ? freeze(value.row.request) : null;});},
    savedReceipt() {return queue(async () => {const value = await inspect(await read()); return value?.row.response ? freeze(value.row.response) : null;});},
    acceptResponse(bytes) {
      const raw = capture(bytes);
      return queue(async () => {
        const original = await inspect(await read());
        need(original !== null, 'finish_missing', 'Save the original finish request before accepting its confirmation.');
        const received = await responseDocument(raw, binding, original.request);
        if (original.row.response !== null) {
          need(same(original.row.response, received), 'finish_conflict', 'The retry returned a different finish confirmation. The original is retained.');
          return freeze(original.row.response);
        }
        const row = {...original.row, revision: 2, response: received};
        rowShape(row); await compare(original.row, row); return received;
      });
    }
  });
}
