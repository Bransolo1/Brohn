/* Prospective timed-sequence custody. An arm is never an observed exposure.
 * The host owns fresh authority, the journal and the order of actual captures. */
import {encodeParticipantRequest, PARTICIPANT_REQUEST_CODEC} from './request-bytes.mjs';
import {verifyParticipantJsonBytes} from './wire-json.mjs';
import {captureParticipantObservation} from './observation-journal.mjs';
import {binding as checkBinding, fields, same, freeze, integer, key, hash, text} from './current-structure.mjs';

const DATABASE = 'brohn-assigned-timed-arms', VERSION = 1, END = 10000000;
const STORES = ['state', 'arms', 'captures'];
const fail = (code, message) => Object.assign(new Error(message), {code, retained: true});
const need = (ok, code, message) => {if (!ok) throw fail(code, message);};
const timed = step => ['baseline', 'fixation', 'stimulus'].includes(step?.type);
const decimal = x => typeof x === 'string' && /^[0-9]+(?:\.[0-9]+)?$/.test(x) && x.length <= 64 && Number.isFinite(Number(x));

function acquire(runId) {
  need(globalThis.navigator?.locks && globalThis.indexedDB, 'arm_storage', 'Secure browser storage is required before timed presentation.');
  return new Promise((resolve, reject) => {
    const lifetime = navigator.locks.request(`brohn-assigned-timed-arm:${runId}`, {mode: 'exclusive', ifAvailable: true}, held => {
      if (!held) {reject(fail('arm_busy', 'This study already has an open timed presentation owner.')); return;}
      return new Promise(release => resolve({release, lifetime: () => lifetime}));
    });
    lifetime.catch(reject);
  });
}
function database() {
  return new Promise((resolve, reject) => {
    let refused = false;
    const request = indexedDB.open(DATABASE, VERSION);
    request.onupgradeneeded = event => {
      if (refused || event.oldVersion !== 0) {request.transaction.abort(); return;}
      const db = request.result;
      db.createObjectStore('state', {keyPath: 'run_id'});
      const arms = db.createObjectStore('arms', {keyPath: ['run_id', 'arm_id']});
      arms.createIndex('first_step', ['run_id', 'first_step_key'], {unique: true});
      const captures = db.createObjectStore('captures', {keyPath: ['run_id', 'arm_id', 'event_id']});
      captures.createIndex('sequence', ['run_id', 'sequence'], {unique: true});
    };
    request.onerror = () => reject(fail(request.error?.name === 'VersionError' ? 'arm_storage_newer' : 'arm_storage',
      'The original timed-presentation record could not be opened. Keep saved browser data and retry recovery.'));
    request.onblocked = () => {refused = true; reject(fail('arm_storage', 'Close other study tabs before recovering timed presentation.'));};
    request.onsuccess = () => {if (refused) request.result.close(); else resolve(request.result);};
  });
}
function transaction(db, mode, action) {
  return new Promise((resolve, reject) => {
    let tx, result, original = null;
    try {tx = mode === 'readwrite' ? db.transaction(STORES, mode, {durability: 'strict'}) : db.transaction(STORES, mode);}
    catch (error) {reject(error); return;}
    const guard = fn => (...args) => {try {fn(...args);} catch (error) {original ||= error; try {tx.abort();} catch (_) {}}};
    tx.oncomplete = () => resolve(result);
    tx.onabort = () => reject(original || fail('arm_storage', 'The timed-presentation record is not confirmed saved. Retry its original action.'));
    tx.onerror = () => {};
    guard(() => {
      need(mode !== 'readwrite' || tx.durability === 'strict', 'arm_storage', 'This browser cannot confirm durable timed-presentation storage.');
      action(Object.fromEntries(STORES.map(name => [name, tx.objectStore(name)])), guard, value => {result = value;});
    })();
  });
}

export async function openParticipantTimedArms({binding, viewJson}) {
  const held = JSON.parse((await encodeParticipantRequest(binding)).json); checkBinding(held);
  const view = (await verifyParticipantJsonBytes(viewJson, {codec: held.view_codec, bytes: held.view_bytes, sha256: held.view_hash})).value;
  need(view.schema === 'brohn-participant-view/0.1' && view.run_id === held.run_id &&
    view.source_protocol_hash === held.source_protocol_hash && same(view.renderer_identity, held.renderer_identity) &&
    Array.isArray(view.steps) && view.steps.length <= 20000 && view.steps.every(s => key(s?.step_key, 'pvs')) &&
    new Set(view.steps.map(s => s.step_key)).size === view.steps.length, 'arm_view', 'Keep the original assigned study order.');
  const runId = held.run_id, ownership = await acquire(runId), stepMap = new Map(view.steps.map(s => [s.step_key, s]));
  let db = null, unavailable = false, accepting = true, tail = Promise.resolve(), closing = null;
  const ready = () => need(!unavailable, 'arm_storage_changed', 'Timed-presentation storage changed. Recover the original record before continuing.');
  function queue(action, recovering = false) {
    need(accepting, 'arm_closed', 'The timed-presentation owner is closed.');
    if (!recovering) ready();
    const result = tail.then(() => {if (!recovering) ready(); return action();}); tail = result.catch(() => {}); return result;
  }
  function connect(opened) {
    db = opened; let lost = false;
    const changed = () => {lost = true; if (db === opened) unavailable = true;};
    opened.onversionchange = () => {changed(); opened.close();}; opened.onclose = changed;
    return () => !lost;
  }
  function sequence(firstKey) {
    const index = view.steps.findIndex(s => s.step_key === firstKey);
    need(index >= 0 && timed(view.steps[index]), 'arm_sequence', 'Arm the original next timed screen.');
    const result = []; let i = index;
    while (i < view.steps.length && timed(view.steps[i])) {
      const step = view.steps[i++];
      need(key(step.stimulus_key, 'pvi') && step.phase === (step.type === 'stimulus' ? 'passive_viewing' : step.type) &&
        integer(step.duration_ms, step.type === 'stimulus' ? 100 : 1, step.type === 'stimulus' ? 3600000 : 600000),
      'arm_sequence', 'Keep the assigned timed duration, phase and stimulus.');
      result.push(step.step_key);
    }
    return {step_keys: result, boundary_step_key: view.steps[i]?.step_key ?? null};
  }
  function page(value) {
    fields(value, ['instance_id', 'time_origin_ms']);
    need(text(value.instance_id, 128) && decimal(value.time_origin_ms), 'arm_clock', 'Keep the original page identity and time origin.');
  }
  function descriptor(value) {
    fields(value, ['codec', 'bytes', 'sha256']);
    need(value.codec === held.view_codec && integer(value.bytes, 1, 16 * 1024 * 1024) && hash(value.sha256),
      'arm_current', 'Keep the descriptor of the authenticated current response.');
  }
  function admission(value) {
    fields(value, ['acknowledged_sequence', 'next_step_key', 'active_step_key', 'current_document']);
    need(integer(value.acknowledged_sequence, 0, END) && key(value.next_step_key, 'pvs', true) &&
      value.active_step_key === null, 'arm_current', 'A timed sequence needs a fresh inactive start boundary.');
    descriptor(value.current_document);
  }
  function armRow(row) {
    fields(row, ['schema', 'run_id', 'binding', 'arm_id', 'first_step_key', 'step_keys', 'boundary_step_key', 'page_clock', 'admission', 'resolution']);
    need(row.schema === 'participant-timed-arm/0.1' && row.run_id === runId && same(row.binding, held) && text(row.arm_id, 128),
      'arm_integrity', 'The saved timed sequence belongs to another study.');
    const expected = sequence(row.first_step_key);
    need(same(expected.step_keys, row.step_keys) && expected.boundary_step_key === row.boundary_step_key,
      'arm_integrity', 'The saved timed order differs from its original presentation.');
    page(row.page_clock); admission(row.admission);
    need(row.admission.next_step_key === row.first_step_key, 'arm_integrity', 'The original admission does not match this sequence.');
    if (row.resolution !== null) {
      fields(row.resolution, ['schema', 'acknowledged_sequence', 'boundary_step_key', 'current_document', 'events']);
      need(row.resolution.schema === 'participant-timed-boundary/0.1' &&
        row.resolution.boundary_step_key === row.boundary_step_key && integer(row.resolution.acknowledged_sequence, row.admission.acknowledged_sequence + 1, END) &&
        Array.isArray(row.resolution.events) && row.resolution.events.length === row.step_keys.length * 2,
      'arm_integrity', 'The saved boundary proof is incomplete.');
      descriptor(row.resolution.current_document);
      for (const event of row.resolution.events) {
        fields(event, ['event_id', 'sequence', 'sha256']);
        need(text(event.event_id, 128) && integer(event.sequence, row.admission.acknowledged_sequence + 1, row.resolution.acknowledged_sequence) && hash(event.sha256),
          'arm_integrity', 'The saved boundary has an invalid observation reference.');
      }
    }
    return row;
  }
  function stateRow(row) {
    if (row === undefined) return null;
    fields(row, ['schema', 'run_id', 'binding', 'active_arm_id']);
    need(row.schema === 'participant-timed-arm-state/0.1' && row.run_id === runId && same(row.binding, held) &&
      (row.active_arm_id === null || text(row.active_arm_id, 128)), 'arm_integrity', 'The timed-presentation ownership record is inconsistent.');
    return row;
  }
  function read(armId = null) {
    return transaction(db, 'readonly', (stores, guard, done) => {
      const request = stores.state.get(runId);
      request.onsuccess = guard(() => {
        const state = stateRow(request.result), id = armId ?? state?.active_arm_id;
        if (!id) {done({state, row: null}); return;}
        const arm = stores.arms.get([runId, id]);
        arm.onsuccess = guard(() => {
          need(arm.result !== undefined, 'arm_integrity', 'The original timed arm is missing.');
          const row = armRow(arm.result);
          need(state !== null && (row.resolution !== null || state.active_arm_id === row.arm_id),
            'arm_integrity', 'An unresolved timed arm lost its owner.');
          need(state.active_arm_id !== row.arm_id || row.resolution === null,
            'arm_integrity', 'A resolved timed arm cannot remain active.');
          done({state, row});
        });
      });
    });
  }
  function compare(stores, prior, guard, action) {
    const request = stores.state.get(runId);
    request.onsuccess = guard(() => {
      need(same(request.result ?? null, prior.state), 'arm_conflict', 'Timed ownership changed. Preserve the original arm.');
      const arm = stores.arms.get([runId, prior.row.arm_id]);
      arm.onsuccess = guard(() => {
        need(same(arm.result, prior.row), 'arm_conflict', 'The original timed arm changed.'); action();
      });
    });
  }
  async function captureRow(row, arm) {
    fields(row, ['schema', 'run_id', 'arm_id', 'event_id', 'sequence', 'document']);
    need(row.schema === 'participant-timed-capture/0.1' && row.run_id === runId && row.arm_id === arm.arm_id &&
      integer(row.sequence, arm.admission.acknowledged_sequence + 1, END), 'arm_capture', 'Retain the original journal sequence.');
    const doc = row.document; fields(doc, ['codec', 'json', 'bytes', 'sha256']);
    need(doc.codec === PARTICIPANT_REQUEST_CODEC && typeof doc.json === 'string' && doc.json.length <= 4 * 1024 * 1024 &&
      integer(doc.bytes, 1, 4 * 1024 * 1024) && hash(doc.sha256),
      'arm_capture', 'The timed observation document is incomplete.');
    const value = JSON.parse(doc.json), checked = await captureParticipantObservation(value, held.view_hash), e = value.event;
    need(same(doc, checked) && row.event_id === e.id && arm.step_keys.includes(e.step_key) &&
      ['step_started', 'step_finished'].includes(e.type) && e.phase === stepMap.get(e.step_key).phase &&
      e.clock.instance_id === arm.page_clock.instance_id && e.clock.time_origin_ms === arm.page_clock.time_origin_ms &&
      e.payload.clock_segment_id === e.clock.instance_id && e.payload.time_origin_ms === e.clock.time_origin_ms,
    'arm_capture', 'Keep the original timed boundary event and page clock.');
    return {row, value};
  }
  function captureRows(armId) {
    return transaction(db, 'readonly', (stores, guard, done) => {
      const request = stores.captures.getAll(IDBKeyRange.bound([runId, armId], [runId, armId, []]));
      request.onsuccess = guard(() => done(request.result));
    });
  }
  function close() {
    if (!closing) {accepting = false; closing = tail.then(() => {db?.close(); ownership.release(); return ownership.lifetime();});}
    return closing;
  }
  try {
    const healthy = connect(await database()); await read();
    need(healthy(), 'arm_storage_changed', 'Storage changed while opening the original timed arm.');
  } catch (error) {await close(); throw error;}
  return Object.freeze({
    close,
    inspect: () => queue(async () => freeze((await read()).row)),
    recover: () => queue(async () => {
      unavailable = true; db?.close(); const healthy = connect(await database());
      try {
        const saved = await read(); need(healthy(), 'arm_storage_changed', 'Storage changed during timed-arm recovery.');
        unavailable = false; return freeze(saved.row);
      } catch (error) {db.close(); throw error;}
    }, true),
    arm(input) {
      const captured = encodeParticipantRequest(input).then(value => ({value}), error => ({error}));
      return queue(async () => {
        const snapshot = await captured; if (snapshot.error) throw snapshot.error;
        const value = JSON.parse(snapshot.value.json);
        fields(value, ['arm_id', 'first_step_key', 'page_clock', 'admission']);
        const row = armRow({schema: 'participant-timed-arm/0.1', run_id: runId, binding: held,
          ...value, ...sequence(value.first_step_key), resolution: null});
        const prior = await read();
        if (prior.row) {need(same(prior.row, row), 'arm_unresolved', 'Recover the original exposure; do not replay or replace an armed sequence.'); return freeze(prior.row);}
        await transaction(db, 'readwrite', (stores, guard, done) => {
          const request = stores.state.get(runId);
          request.onsuccess = guard(() => {
            need(same(request.result ?? null, prior.state), 'arm_conflict', 'Timed ownership changed before arming.');
            // add + unique first-step index retains tombstones and forbids replay.
            stores.arms.add(row);
            stores.state.put({schema: 'participant-timed-arm-state/0.1', run_id: runId, binding: held, active_arm_id: row.arm_id}); done();
          });
        });
        return freeze(row);
      });
    },
    remember({armId, observation, sequence: journalSequence}) {
      need(text(armId, 128) && integer(journalSequence, 1, END), 'arm_capture', 'Use the original arm and actual journal sequence.');
      // Called with the actual journal result, never before its transactioncomplete.
      const captured = captureParticipantObservation(observation, held.view_hash).then(value => ({value}), error => ({error}));
      return queue(async () => {
        const snapshot = await captured; if (snapshot.error) throw snapshot.error;
        const prior = await read(armId);
        need(prior.row.resolution === null, 'arm_resolved', 'This sequence already has its original boundary proof.');
        const row = {schema: 'participant-timed-capture/0.1', run_id: runId, arm_id: armId,
          event_id: JSON.parse(snapshot.value.json).event.id, sequence: journalSequence, document: snapshot.value};
        await captureRow(row, prior.row); ready();
        await transaction(db, 'readwrite', (stores, guard, done) => compare(stores, prior, guard, () => {
          const request = stores.captures.get([runId, armId, row.event_id]);
          request.onsuccess = guard(() => {
            if (request.result !== undefined) need(same(request.result, row), 'arm_conflict', 'The original timed observation cannot be replaced.');
            else stores.captures.add(row);
            done();
          });
        }));
        return freeze({event_id: row.event_id, sequence: row.sequence, sha256: row.document.sha256});
      });
    },
    settle({armId, admission: currentAdmission}) {
      need(text(armId, 128), 'arm_boundary', 'Use the original timed arm.');
      const captured = encodeParticipantRequest(currentAdmission).then(value => ({value}), error => ({error}));
      return queue(async () => {
        const snapshot = await captured; if (snapshot.error) throw snapshot.error;
        const current = JSON.parse(snapshot.value.json); admission(current);
        const prior = await read(armId), arm = prior.row;
        need(current.next_step_key === arm.boundary_step_key, 'arm_boundary', 'Recover the original sequence through its next interactive boundary.');
        const saved = await captureRows(armId), checked = [];
        for (const row of saved) checked.push(await captureRow(row, arm));
        checked.sort((a, b) => a.row.sequence - b.row.sequence);
        need(checked.length === arm.step_keys.length * 2 && new Set(checked.map(x => x.row.sequence)).size === checked.length,
          'arm_incomplete', 'Some original exposure boundaries are missing. Preserve them and end this session as interrupted; do not replay.');
        let previous = null;
        for (let i = 0; i < checked.length; i++) {
          const {row, value: {event}} = checked[i], step = stepMap.get(arm.step_keys[Math.floor(i / 2)]);
          need(event.step_key === step.step_key && event.type === (i % 2 ? 'step_finished' : 'step_started') &&
            row.sequence <= current.acknowledged_sequence && (previous === null || Number(event.clock.value) >= previous),
          'arm_incomplete', 'The acknowledged original exposure order is incomplete.');
          if (i > 0 && i % 2 === 0) need(same(event.clock, checked[i - 1].value.event.clock),
            'arm_capture', 'Adjacent timed screens must retain their one original shared frame boundary.');
          need(event.payload.scheduled_duration_ms === step.duration_ms, 'arm_capture', 'Keep each assigned exposure duration.');
          if (i % 2) {
            const start = checked[i - 1].value.event;
            const elapsed = Number(event.clock.value) - Number(start.clock.value);
            need(event.payload.resumed === false && elapsed >= step.duration_ms && event.payload.elapsed_ms === elapsed &&
              event.payload.observed_duration_ms === elapsed, 'arm_capture', 'Keep the actual uninterrupted exposure duration.');
          } else need(event.payload.timing_reference === 'requestAnimationFrame_before_paint', 'arm_capture', 'Keep the original browser timing reference.');
          previous = Number(event.clock.value);
        }
        const resolution = {schema: 'participant-timed-boundary/0.1', acknowledged_sequence: current.acknowledged_sequence,
          boundary_step_key: arm.boundary_step_key, current_document: current.current_document,
          events: checked.map(x => ({event_id: x.row.event_id, sequence: x.row.sequence, sha256: x.row.document.sha256}))};
        if (arm.resolution) {
          need(same(arm.resolution.events, resolution.events) && current.acknowledged_sequence >= arm.resolution.acknowledged_sequence,
            'arm_conflict', 'The original boundary proof cannot be replaced.'); return freeze(arm);
        }
        const next = armRow({...arm, resolution}); ready();
        await transaction(db, 'readwrite', (stores, guard, done) => compare(stores, prior, guard, () => {
          stores.arms.put(next); stores.state.put({...prior.state, active_arm_id: null}); done();
        }));
        return freeze(next);
      });
    }
  });
}
