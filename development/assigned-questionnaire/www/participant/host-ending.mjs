/* Durable bridge from an actual terminal observation to finish custody. It
 * stores no credential and never infers an ending from a timeline cursor. */
import {encodeParticipantRequest, PARTICIPANT_REQUEST_CODEC} from './request-bytes.mjs';
import {captureParticipantObservation} from './observation-journal.mjs';
import {binding as validateBinding, fields, same, freeze, integer, hash} from './current-structure.mjs';

const DATABASE = 'brohn-assigned-host-endings';
const fail = (code, message) => Object.assign(new Error(message), {code, retained: true});
const need = (ok, code, message) => {if (!ok) throw fail(code, message);};

function lock(runId) {
  need(navigator.locks && indexedDB, 'host_storage', 'Secure browser storage is required to retain study progress.');
  return new Promise((resolve, reject) => {
    const lifetime = navigator.locks.request(`brohn-assigned-host-ending:${runId}`, {mode: 'exclusive', ifAvailable: true}, held => {
      if (!held) {reject(fail('host_busy', 'This study is already open in another tab. Close it before continuing here.')); return;}
      return new Promise(release => resolve({release, lifetime: () => lifetime}));
    });
    lifetime.catch(reject);
  });
}
function database() {
  return new Promise((resolve, reject) => {
    let refused = false;
    const request = indexedDB.open(DATABASE, 1);
    request.onupgradeneeded = () => {
      if (refused) {request.transaction.abort(); return;}
      request.result.createObjectStore('endings', {keyPath: 'run_id'});
    };
    request.onerror = () => reject(request.error?.name === 'VersionError' ?
      fail('host_storage_newer', 'The browser storage format changed. Keep this page open and contact your researcher; an unsaved original action may still be held here.') :
      fail('host_storage', 'The original study ending could not be opened. Keep this page open and retry its original saved action.'));
    request.onblocked = () => {refused = true; reject(fail('host_storage', 'Close other study tabs before reopening this session.'));};
    request.onsuccess = () => {if (refused) request.result.close(); else resolve(request.result);};
  });
}
function transaction(db, mode, action) {
  return new Promise((resolve, reject) => {
    let tx, original = null, result;
    try {tx = mode === 'readwrite' ? db.transaction('endings', mode, {durability: 'strict'}) : db.transaction('endings', mode);}
    catch (error) {reject(error); return;}
    const guard = fn => (...args) => {try {fn(...args);} catch (error) {original ||= error; try {tx.abort();} catch (_) {}}};
    tx.oncomplete = () => resolve(result);
    tx.onabort = () => reject(original || fail('host_storage', 'This ending is not confirmed saved. Retry its original capture.'));
    tx.onerror = () => {};
    guard(() => {
      need(mode !== 'readwrite' || tx.durability === 'strict', 'host_storage', 'This browser cannot confirm a durable ending save.');
      action(tx.objectStore('endings'), guard, value => {result = value;});
    })();
  });
}

export async function openParticipantHostEnding({binding}) {
  const held = JSON.parse((await encodeParticipantRequest(binding)).json); validateBinding(held);
  const runId = held.run_id, ownership = await lock(runId);
  let db, unavailable = false, accepting = true, tail = Promise.resolve(), closing = null;
  const storageReady = () => need(!unavailable, 'host_storage_changed',
    'Browser storage changed. Keep this page open and retry recovery so the original action can be saved.');
  const queue = (action, recovering = false) => {
    need(accepting, 'host_closed', 'Reopen the original study link to recover the saved ending.');
    if (!recovering) storageReady();
    const next = tail.then(() => {if (!recovering) storageReady(); return action();}); tail = next.catch(() => {}); return next;
  };
  function connect(opened) {
    db = opened; let lost = false;
    opened.onversionchange = () => {lost = true; if (db === opened) unavailable = true; opened.close();};
    opened.onclose = () => {lost = true; if (db === opened) unavailable = true;};
    return () => !lost;
  }
  const readRow = () => transaction(db, 'readonly', (store, guard, done) => {
    const read = store.get(runId); read.onsuccess = guard(() => done(read.result));
  });
  async function inspect(row) {
    if (row === undefined) return null;
    fields(row, ['schema', 'run_id', 'binding', 'observation', 'sequence']);
    need(row.schema === 'participant-host-ending/0.1' && row.run_id === runId && same(row.binding, held) &&
      (row.sequence === null || integer(row.sequence, 1, 10000000)), 'host_ending_integrity', 'The original ending record is inconsistent.');
    const doc = row.observation;
    fields(doc, ['codec', 'json', 'bytes', 'sha256']);
    need(doc.codec === PARTICIPANT_REQUEST_CODEC && typeof doc.json === 'string' && doc.json.length <= 4 * 1024 * 1024 &&
      integer(doc.bytes, 1, 4 * 1024 * 1024) && hash(doc.sha256), 'host_ending_integrity', 'The original ending document is damaged.');
    const value = JSON.parse(doc.json), checked = await captureParticipantObservation(value, held.view_hash);
    need(same(doc, checked), 'host_ending_integrity', 'The original ending bytes failed their integrity check.');
    const event = value.event, payload = event.payload;
    fields(payload, ['outcome', 'reason', 'clock_segment_id', 'time_origin_ms']);
    need(event.step_key === null && event.phase === 'session' &&
      ['completed', 'interrupted', 'withdrawn'].includes(payload.outcome) &&
      event.type === (payload.outcome === 'withdrawn' ? 'withdrawal' : 'run_finished') &&
      (payload.reason === null || typeof payload.reason === 'string') &&
      payload.clock_segment_id === event.clock.instance_id && payload.time_origin_ms === event.clock.time_origin_ms,
    'host_ending_integrity', 'The original ending observation is inconsistent.');
    return freeze({observation: value, document: doc, sequence: row.sequence, outcome: payload.outcome});
  }
  const replace = (prior, next) => transaction(db, 'readwrite', (store, guard, done) => {
    const read = store.get(runId);
    read.onsuccess = guard(() => {
      need(same(read.result, prior), 'host_ending_conflict', 'The saved ending changed. Keep the original record.');
      store.put(next); done();
    });
  });
  function close() {
    if (!closing) {accepting = false; closing = tail.then(() => {db?.close(); ownership.release(); return ownership.lifetime();});}
    return closing;
  }
  try {
    const healthy = connect(await database());
    await inspect(await readRow());
    need(healthy(), 'host_storage_changed', 'Browser storage changed while opening. Keep this page open and retry recovery.');
  }
  catch (error) {await close(); throw error;}
  return Object.freeze({
    close,
    recover: () => queue(async () => {
      // Keep the same lifetime lock while reopening the supported database
      // version and validating the exact original binding/document. A newer
      // schema is an explicit refusal, never an implicit compatible upgrade.
      unavailable = true; db?.close();
      const healthy = connect(await database());
      try {
        const saved = await inspect(await readRow());
        need(healthy(), 'host_storage_changed', 'Browser storage changed during recovery. Keep the original action and retry.');
        unavailable = false; return saved;
      } catch (error) {db.close(); unavailable = true; throw error;}
    }, true),
    read: () => queue(async () => inspect(await readRow())),
    prepare(observation) {
      // Snapshot now; storage scheduling must not recapture a later clock/value.
      const captured = captureParticipantObservation(observation, held.view_hash).then(value => ({value}), error => ({error}));
      return queue(async () => {
        const prepared = await captured; if (prepared.error) throw prepared.error;
        const prior = await readRow(), old = await inspect(prior);
        if (old) {need(same(old.document, prepared.value), 'host_ending_conflict', 'Recover the original ending before choosing another.'); return old;}
        const row = {schema: 'participant-host-ending/0.1', run_id: runId, binding: held, observation: prepared.value, sequence: null};
        const checked = await inspect(row); await replace(prior, row); return checked;
      });
    },
    rememberSequence(sequence) {
      need(integer(sequence, 1, 10000000), 'host_ending_sequence', 'Keep the original journal sequence.');
      return queue(async () => {
        const prior = await readRow(), old = await inspect(prior);
        need(old !== null, 'host_ending_missing', 'Retain the actual ending before its journal sequence.');
        if (old.sequence !== null) {need(old.sequence === sequence, 'host_ending_conflict', 'The original ending has a different journal sequence.'); return old;}
        const row = {...prior, sequence}; await replace(prior, row); return inspect(row);
      });
    }
  });
}
