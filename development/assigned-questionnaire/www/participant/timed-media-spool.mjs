/* Native media evidence custody. No presentation, networking or authority here. */
import {encodeParticipantRequest} from './request-bytes.mjs';
import {verifyParticipantJsonBytes} from './wire-json.mjs';
import {captureParticipantObservation} from './observation-journal.mjs';
import {binding as checkBinding, fields, same, freeze, integer, text} from './current-structure.mjs';

const DB = 'brohn-assigned-timed-media', VERSION = 1, MAX = 4 * 1024 * 1024, ORDER_MAX = Number.MAX_SAFE_INTEGER;
const STORES = ['runs', 'arms', 'records', 'attachments'];
const SCHEMA = 'participant-timed-media-evidence/0.1';
const KINDS = ['play_requested', 'play_resolved', 'play_rejected', 'playing', 'waiting',
  'stalled', 'error', 'pause_requested', 'pause', 'ended', 'seeking', 'seeked', 'ratechange'];
const fail = (code, message) => Object.assign(new Error(message), {code, retained: true});
const need = (value, code, message) => {if (!value) throw fail(code, message);};
const decimal = x => typeof x === 'string' && x.length <= 64 && /^[0-9]+(?:\.[0-9]+)?$/.test(x) && Number.isFinite(Number(x));
const finite = x => typeof x === 'number' && Number.isFinite(x);
const identity = x => text(x, 128);
const clone = value => freeze(structuredClone(value));
const documentKey = value => {
  if (typeof value === 'number') return Object.is(value, -0) ? '-0.0' : String(value);
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(documentKey).join(',') + ']';
  return '{' + Object.keys(value).map(name => JSON.stringify(name) + ':' + documentKey(value[name])).join(',') + '}';
};
function exactSame(left, right) {
  if (typeof left === 'number' || typeof right === 'number') return Object.is(left, right);
  if (left === right) return true;
  if (!left || !right || typeof left !== 'object' || typeof right !== 'object' || Array.isArray(left) !== Array.isArray(right)) return false;
  const keys = Object.keys(left);
  return keys.length === Object.keys(right).length && keys.every(name => Object.hasOwn(right, name) && exactSame(left[name], right[name]));
}
function compareDecimal(left, right) {
  const parts = value => {const [whole, fraction = ''] = value.split('.'); return [whole.replace(/^0+(?=\d)/, ''), fraction.replace(/0+$/, '')];};
  const [a, af] = parts(left), [b, bf] = parts(right);
  if (a.length !== b.length) return a.length < b.length ? -1 : 1;
  if (a !== b) return a < b ? -1 : 1;
  const length = Math.max(af.length, bf.length), aa = af.padEnd(length, '0'), bb = bf.padEnd(length, '0');
  return aa === bb ? 0 : aa < bb ? -1 : 1;
}
function clock(value) {
  fields(value, ['id', 'unit', 'value', 'instance_id', 'time_origin_ms']);
  need(value.id === 'browser-monotonic' && value.unit === 'ms' && decimal(value.value) && compareDecimal(value.value, '1000000000000') <= 0 &&
    text(value.instance_id, 128) && decimal(value.time_origin_ms), 'media_clock', 'Retain the original native media clock.');
}
function openDatabase() {
  return new Promise((resolve, reject) => {
    let refused = false; const req = indexedDB.open(DB, VERSION);
    req.onupgradeneeded = event => {
      if (refused || event.oldVersion !== 0) {req.transaction.abort(); return;}
      const db = req.result;
      db.createObjectStore('runs', {keyPath: 'run_id'});
      db.createObjectStore('arms', {keyPath: ['run_id', 'arm_id']});
      const records = db.createObjectStore('records', {keyPath: ['run_id', 'id']});
      records.createIndex('order', ['run_id', 'order'], {unique: true});
      records.createIndex('pending', ['run_id', 'status']);
      db.createObjectStore('attachments', {keyPath: ['run_id', 'event_id']});
    };
    req.onblocked = () => {refused = true; reject(fail('media_storage_blocked', 'Close other study tabs before recovering media records.'));};
    req.onerror = () => reject(fail(req.error?.name === 'VersionError' ? 'media_storage_newer' : 'media_storage',
      'The original media records could not be opened. Keep browser data and retry recovery.'));
    req.onsuccess = () => {if (refused) req.result.close(); else resolve(req.result);};
  });
}
function acquire(runId) {
  need(navigator.locks && globalThis.indexedDB, 'media_storage', 'Secure durable browser storage is required for media.');
  return new Promise((resolve, reject) => {
    const lifetime = navigator.locks.request(`brohn-assigned-timed-media:${runId}`, {mode: 'exclusive', ifAvailable: true}, held => {
      if (!held) {reject(fail('media_busy', 'This study already has a media-record owner.')); return;}
      return new Promise(release => resolve({release, lifetime: () => lifetime}));
    });
    lifetime.catch(reject);
  });
}
function transaction(db, mode, action) {
  return new Promise((resolve, reject) => {
    let tx, result, original;
    try {tx = db.transaction(STORES, mode, ...(mode === 'readwrite' ? [{durability: 'strict'}] : []));}
    catch (error) {reject(error); return;}
    const guard = fn => (...args) => {try {fn(...args);} catch (error) {original ||= error; try {tx.abort();} catch (_) {}}};
    tx.oncomplete = () => resolve(result);
    tx.onabort = () => reject(original || fail('media_storage', 'Media evidence is not confirmed saved. Retry its original records.'));
    tx.onerror = () => {};
    guard(() => {
      need(mode !== 'readwrite' || tx.durability === 'strict', 'media_storage', 'This browser cannot confirm durable media storage.');
      action(Object.fromEntries(STORES.map(name => [name, tx.objectStore(name)])), guard, value => {result = value;});
    })();
  });
}

export async function openParticipantTimedMedia({binding, viewJson, journal}) {
  const held = JSON.parse((await encodeParticipantRequest(binding)).json); checkBinding(held);
  const view = (await verifyParticipantJsonBytes(viewJson, {codec: held.view_codec, bytes: held.view_bytes, sha256: held.view_hash})).value;
  need(view.schema === 'brohn-participant-view/0.1' && view.run_id === held.run_id &&
    view.source_protocol_hash === held.source_protocol_hash && same(view.renderer_identity, held.renderer_identity) && Array.isArray(view.steps),
    'media_view', 'Keep the original assigned study and renderer.');
  need(journal && ['status', 'read'].every(name => typeof journal[name] === 'function'), 'media_journal', 'Connect the original owned observation journal.');
  const steps = new Map(view.steps.map(step => [step.step_key, step]));
  need(steps.size === view.steps.length, 'media_view', 'Keep unique assigned screen identities.');
  const runId = held.run_id, ownership = await acquire(runId), arms = new Map(), records = new Map(), reservations = new Map();
  // A successor first component covers every possible compound-key suffix,
  // including malformed array/binary IDs that a [run, []] upper bound misses.
  const runRange = () => IDBKeyRange.bound([runId], [runId + '\u0000'], false, true);
  let db, unavailable = false, recovering = false, retrying = null, accepting = true, closing = null, tail = Promise.resolve(), nextOrder = 1, baseline = null;
  let linkedIds = new Set();
  const storageReady = () => need(!unavailable, 'media_storage_changed', 'Recover the original media store before continuing.');
  const ready = () => need(!unavailable && !recovering, 'media_storage_changed', 'Recover the original media store before continuing.');
  function connect(opened) {
    db = opened; const lost = () => {if (db === opened) unavailable = true;};
    opened.onversionchange = () => {lost(); opened.close();}; opened.onclose = lost;
  }
  function queue(action, recovering = false) {
    need(accepting, 'media_closed', 'The media-record owner is closed.');
    const result = tail.then(() => {if (!recovering) ready(); return action();});
    tail = result.catch(() => {}); return result;
  }
  function armValue(arm) {
    fields(arm, ['schema', 'run_id', 'binding', 'arm_id', 'first_step_key', 'step_keys',
      'boundary_step_key', 'page_clock', 'admission', 'resolution']);
    fields(arm.page_clock, ['instance_id', 'time_origin_ms']);
    need(arm?.schema === 'participant-timed-arm/0.1' && arm.run_id === runId && same(arm.binding, held) &&
      identity(arm.arm_id) && Array.isArray(arm.step_keys) && arm.step_keys.length > 0 &&
      new Set(arm.step_keys).size === arm.step_keys.length && arm.step_keys.every(id => steps.has(id)) &&
      text(arm.page_clock?.instance_id, 128) && decimal(arm.page_clock?.time_origin_ms),
      'media_arm', 'Register the original committed timed arm.');
    const first = view.steps.findIndex(step => step.step_key === arm.first_step_key), expected = [];
    let cursor = first;
    while (cursor >= 0 && cursor < view.steps.length && ['baseline', 'fixation', 'stimulus'].includes(view.steps[cursor].type))
      expected.push(view.steps[cursor++].step_key);
    need(expected.length > 0 && same(expected, arm.step_keys) && (view.steps[cursor]?.step_key ?? null) === arm.boundary_step_key &&
      arm.resolution === null, 'media_arm', 'Keep the exact original uncompleted timed sequence.');
    return clone(arm);
  }
  function recordValue(value) {
    fields(value, ['id', 'arm_id', 'step_key', 'kind', 'clock', 'media_current_time', 'playback_rate',
      'ready_state', 'network_state', 'paused', 'ended', 'error_name', 'error_code']);
    const arm = arms.get(value.arm_id), step = steps.get(value.step_key); clock(value.clock);
    need(identity(value.id) && arm && arm.step_keys.includes(value.step_key) && step?.type === 'stimulus' &&
      ['audio', 'video'].includes(step.material?.type) && KINDS.includes(value.kind) &&
      value.clock.instance_id === arm.page_clock.instance_id && value.clock.time_origin_ms === arm.page_clock.time_origin_ms,
      'media_record', 'Keep each media record with its original assigned exposure and page.');
    need((value.media_current_time === null || finite(value.media_current_time) && value.media_current_time >= 0) &&
      (value.playback_rate === null || finite(value.playback_rate)) && integer(value.ready_state, 0, 4) && integer(value.network_state, 0, 3) &&
      typeof value.paused === 'boolean' && typeof value.ended === 'boolean' &&
      (value.error_name === null || typeof value.error_name === 'string' && new TextEncoder().encode(value.error_name).length <= 128) &&
      (value.error_code === null || integer(value.error_code, 1, 4)), 'media_record', 'Keep observed media values and explicit missingness.');
    return clone(value);
  }
  function envelopeValue(body) {
    fields(body, ['schema', 'attachment_clock', 'groups']); clock(body.attachment_clock);
    need(body.schema === SCHEMA && Array.isArray(body.groups) && body.groups.length > 0, 'media_attachment', 'Keep the original grouped media attachment.');
    const ids = new Set(), groups = new Set();
    for (const group of body.groups) {
      fields(group, ['arm_id', 'records']);
      need(identity(group.arm_id) && !groups.has(group.arm_id) && Array.isArray(group.records) && group.records.length > 0,
        'media_attachment', 'Keep nonempty unique media arm groups.'); groups.add(group.arm_id);
      for (const item of group.records) {
        // The envelope carries arm identity once per group.
        const value = recordValue({...item, arm_id: group.arm_id});
        need(!Object.hasOwn(item, 'arm_id') && !ids.has(value.id), 'media_attachment', 'A media record may appear only once.'); ids.add(value.id);
        const c = value.clock, a = body.attachment_clock;
        if (c.instance_id === a.instance_id) need(c.time_origin_ms === a.time_origin_ms && compareDecimal(c.value, a.value) <= 0,
          'media_clock', 'The attachment cannot precede its original observations on the same page.');
      }
    }
    const copy = clone(body);
    need(new TextEncoder().encode(documentKey(copy)).length <= MAX, 'media_attachment_capacity',
      'The original media attachment exceeds the supported request size. Retain it for recovery.');
    return copy;
  }
  const values = body => body.groups.flatMap(group => group.records.map(value => ({...value, arm_id: group.arm_id})));
  const read = (store, id) => transaction(db, 'readonly', (s, guard, done) => {
    const req = s[store].get(id); req.onsuccess = guard(() => done(req.result));
  });
  const readAll = store => transaction(db, 'readonly', (s, guard, done) => {
    const req = s[store].getAll(runRange()); req.onsuccess = guard(() => done(req.result));
  });
  async function storedRecord(row) {
    fields(row, ['schema', 'run_id', 'id', 'order', 'document', 'status', 'link']);
    need(row.schema === 'participant-timed-media-record/0.1' && row.run_id === runId && integer(row.order, 1, ORDER_MAX - 1) &&
      ['pending', 'linked'].includes(row.status), 'media_integrity', 'The original media record metadata is inconsistent.');
    const value = recordValue(JSON.parse(row.document.json));
    need(row.id === value.id && same(await encodeParticipantRequest(value), row.document),
      'media_integrity', 'Saved media evidence failed its original byte check.');
    if (row.status === 'pending') need(row.link === null, 'media_integrity', 'A pending media record cannot have a saved link.');
    else {
      fields(row.link, ['event_id', 'sequence', 'document_sha256']);
      need(text(row.link.event_id, 128) && integer(row.link.sequence, baseline + 1, 10000000) &&
        /^[0-9a-f]{64}$/.test(row.link.document_sha256), 'media_integrity', 'The original media link is incomplete.');
    }
    return value;
  }
  function runValue(row) {
    fields(row, ['schema', 'run_id', 'binding', 'next_order', 'journal_baseline']);
    need(row.schema === 'participant-timed-media-run/0.1' && row.run_id === runId && same(row.binding, held) &&
      integer(row.next_order, 1, ORDER_MAX) && integer(row.journal_baseline, 0, 10000000), 'media_integrity', 'The saved media store differs from its original study.');
    return row;
  }
  async function persist(item) {
    const document = await encodeParticipantRequest(item.value); storageReady();
    await transaction(db, 'readwrite', (s, guard, done) => {
      const get = s.runs.get(runId);
      get.onsuccess = guard(() => {
        const state = runValue(get.result), prior = s.records.get([runId, item.value.id]);
        prior.onsuccess = guard(() => {
          const row = {schema: 'participant-timed-media-record/0.1', run_id: runId, id: item.value.id,
            order: item.order, document, status: 'pending', link: null};
          if (prior.result) need(same(prior.result, row), 'media_conflict', 'The original media observation cannot be replaced.');
          else {
            need(state.next_order === item.order && item.order < ORDER_MAX, 'media_order', 'Retry the original unsaved media head before its followers.');
            s.records.add(row); s.runs.put({...state, next_order: item.order + 1});
          }
          done();
        });
      });
    });
    item.saved = true; item.error = null; return item.value.id;
  }
  async function linkOriginal(observation, sequence) {
    const document = await captureParticipantObservation(observation, held.view_hash), event = JSON.parse(document.json).event;
    need(integer(sequence, baseline + 1, 10000000) && ['step_finished', 'run_finished', 'withdrawal'].includes(event.type),
      'media_link', 'Link only the original committed observation and journal sequence.');
    const body = envelopeValue(event.payload.timed_media), items = values(body), recordRows = [];
    need(body.attachment_clock.instance_id === event.clock.instance_id && body.attachment_clock.time_origin_ms === event.clock.time_origin_ms &&
      compareDecimal(event.clock.value, body.attachment_clock.value) <= 0, 'media_clock', 'The attachment must use its containing event page and actual later snapshot clock.');
    const link = {event_id: event.id, sequence, document_sha256: document.sha256};
    const attachment = {schema: 'participant-timed-media-attachment/0.1', run_id: runId, event_id: event.id, sequence, document};
    for (const value of items) {
      const row = await read('records', [runId, value.id]);
      need(row && exactSame(await storedRecord(row), value), 'media_link', 'A journal attachment must retain its original durable media records.');
      need(row.status === 'pending' && row.link === null || row.status === 'linked' && same(row.link, link),
        'media_link_conflict', 'A media observation cannot be attached to a different source event.'); recordRows.push(row);
    }
    await transaction(db, 'readwrite', (s, guard, done) => {
      const prior = s.attachments.get([runId, event.id]);
      prior.onsuccess = guard(() => {
        if (prior.result) need(same(prior.result, attachment), 'media_link_conflict', 'Retain the original journal attachment bytes.');
        let left = recordRows.length;
        for (const row of recordRows) {
          const req = s.records.get([runId, row.id]);
          req.onsuccess = guard(() => {
            need(same(req.result, row), 'media_conflict', 'Original media storage changed during linkage.');
            s.records.put({...row, status: 'linked', link});
            if (--left === 0) {if (!prior.result) s.attachments.add(attachment); done();}
          });
        }
      });
    });
    for (const row of recordRows) {linkedIds.add(row.id); records.delete(row.id);}
    reservations.delete(documentKey(body)); return freeze(link);
  }
  async function reconcile() {
    const before = await journal.status();
    need(before.run_id === runId && before.baseline_sequence === baseline, 'media_journal', 'Recover the same original journal range.');
    const priorAttachments = await readAll('attachments'), observed = new Map();
    let after = baseline;
    while (after < before.next_sequence - 1) {
      const page = await journal.read({after, limit: 100});
      need(page.through_sequence > after && page.next_sequence === before.next_sequence, 'media_journal', 'Keep journal collection stopped during media recovery.');
      for (const item of page.events) if (item.observation.event.payload?.timed_media) {
        const link = await linkOriginal(item.observation, item.sequence); observed.set(item.observation.event.id, link);
      }
      after = page.through_sequence;
    }
    const end = await journal.status();
    need(end.next_sequence === before.next_sequence && end.baseline_sequence === baseline, 'media_journal', 'The journal changed while reconciling media.');
    need(priorAttachments.every(row => observed.has(row.event_id)), 'media_journal', 'A saved media attachment is missing from the original journal.');
    await auditRecordHistory(observed);
    return before;
  }
  async function auditRecordHistory(journalLinks) {
    let after = 0; const cache = new Map(), auditedLinkedIds = new Set();
    for (;;) {
      const page = await transaction(db, 'readonly', (s, guard, done) => {
        const rows = [], req = s.records.index('order').openCursor(IDBKeyRange.bound([runId, after], [runId, ORDER_MAX], true));
        req.onsuccess = guard(() => {
          const cursor = req.result;
          if (!cursor || rows.length === 100) {done(rows); return;}
          rows.push(cursor.value); cursor.continue();
        });
      });
      if (!page.length) break;
      for (const row of page) {
        const value = await storedRecord(row);
        need(row.order === after + 1, 'media_integrity', 'The original media capture history has a missing or changed order.');
        after = row.order;
        if (row.status !== 'linked') continue;
        auditedLinkedIds.add(row.id);
        const id = row.link.event_id;
        need(same(journalLinks.get(id), row.link), 'media_integrity', 'A linked media record lacks its original journal attachment.');
        let attached = cache.get(id);
        if (!attached) {
          const attachment = await read('attachments', [runId, id]);
          need(attachment, 'media_integrity', 'The original media attachment is missing.');
          const original = JSON.parse(attachment.document.json);
          need(same(await captureParticipantObservation(original, held.view_hash), attachment.document),
            'media_integrity', 'Original attachment bytes changed during recovery.');
          attached = values(envelopeValue(original.event.payload.timed_media));
          if (cache.size >= 100) cache.clear(); cache.set(id, attached);
        }
        need(attached.some(item => item.id === row.id && exactSame(item, value)),
          'media_integrity', 'A linked record is absent or different in its original source attachment.');
      }
    }
    const state = runValue(await read('runs', runId));
    need(state.next_order === after + 1, 'media_integrity', 'The saved media order counter differs from complete retained history.');
    const total = await transaction(db, 'readonly', (s, guard, done) => {
      const req = s.records.count(runRange()); req.onsuccess = guard(() => done(req.result));
    });
    need(total === after, 'media_integrity', 'Media history contains a record outside the valid original order index.');
    linkedIds = auditedLinkedIds;
  }
  async function load() {
    const status = await journal.status(); need(status.run_id === runId, 'media_journal', 'Use the original run journal.');
    const state = await read('runs', runId);
    baseline = state ? runValue(state).journal_baseline : status.baseline_sequence;
    need(baseline === status.baseline_sequence, 'media_journal', 'The original media journal baseline changed.');
    if (!state) await transaction(db, 'readwrite', (s, guard, done) => {
      s.runs.add({schema: 'participant-timed-media-run/0.1', run_id: runId, binding: held, next_order: 1, journal_baseline: baseline}); done();
    });
    const saved = await transaction(db, 'readonly', (s, guard, done) => {
      const arm = s.arms.getAll(runRange());
      arm.onsuccess = guard(() => {
        const pending = s.records.index('pending').getAll(IDBKeyRange.only([runId, 'pending']));
        pending.onsuccess = guard(() => done({arms: arm.result, records: pending.result}));
      });
    });
    for (const row of saved.arms) {
      fields(row, ['run_id', 'arm_id', 'arm']);
      need(row.run_id === runId && row.arm_id === row.arm?.arm_id, 'media_integrity', 'The saved media arm is inconsistent.');
      arms.set(row.arm_id, armValue(row.arm));
    }
    nextOrder = state?.next_order ?? 1;
    for (const row of saved.records.sort((a, b) => a.order - b.order)) {
      const value = await storedRecord(row);
      need(integer(row.order, 1, nextOrder - 1) && row.status === 'pending', 'media_integrity', 'The saved pending media order is inconsistent.');
      records.set(row.id, {value, order: row.order, saved: true, reservation: null, promise: Promise.resolve(value.id), error: null});
    }
    await reconcile();
  }
  try {connect(await openDatabase()); await load(); ready();}
  catch (error) {db?.close(); ownership.release(); await ownership.lifetime(); throw error;}
  return Object.freeze({
    registerArm(arm) {
      ready(); const original = armValue(arm);
      return queue(async () => {
        const prior = await read('arms', [runId, original.arm_id]);
        const row = {run_id: runId, arm_id: original.arm_id, arm: original};
        if (prior) need(same(prior, row), 'media_arm_conflict', 'Keep the original committed arm.');
        else await transaction(db, 'readwrite', (s, guard, done) => {s.arms.add(row); done();});
        arms.set(original.arm_id, original); return original;
      });
    },
    capture(record) {
      need(accepting, 'media_closed', 'The media-record owner is closed.'); ready();
      const value = recordValue(record), old = records.get(value.id);
      if (old) {need(exactSame(old.value, value), 'media_conflict', 'Keep the original media record identity.'); return Object.freeze({id: value.id, durability: old.promise});}
      if (linkedIds.has(value.id)) {
        const durability = queue(async () => {
          const row = await read('records', [runId, value.id]);
          need(row?.status === 'linked' && exactSame(await storedRecord(row), value),
            'media_conflict', 'Keep the original linked media observation.');
          return value.id;
        });
        return Object.freeze({id: value.id, durability});
      }
      need(integer(nextOrder, 1, ORDER_MAX - 1), 'media_order_capacity', 'The media store cannot represent another exact capture order. Retain the original study.');
      const item = {value, order: nextOrder++, saved: false, reservation: null, promise: null, error: null};
      records.set(value.id, item);
      item.promise = queue(() => persist(item)); item.promise.catch(error => {item.error = error;});
      return Object.freeze({id: value.id, durability: item.promise});
    },
    snapshot({arm_id = null, attachment_clock}) {
      need(accepting, 'media_closed', 'The media-record owner is closed.'); ready(); clock(attachment_clock);
      need(arm_id === null || arms.has(arm_id), 'media_arm', 'Snapshot the original registered arm.');
      const selected = Array.from(records.values()).filter(item => !item.reservation && (arm_id === null || item.value.arm_id === arm_id));
      if (!selected.length) return null;
      const groups = new Map();
      for (const item of selected) {
        const {arm_id: id, ...record} = item.value;
        if (!groups.has(id)) groups.set(id, []); groups.get(id).push(record);
      }
      const body = envelopeValue({schema: SCHEMA, attachment_clock, groups: Array.from(groups, ([arm_id, records]) => ({arm_id, records}))});
      const reservation = documentKey(body); reservations.set(reservation, body);
      for (const item of selected) item.reservation = reservation;
      return body;
    },
    drainAttachment(body) {
      ready(); const original = envelopeValue(body), reservation = documentKey(original);
      need(reservations.has(reservation), 'media_attachment', 'Use the original reserved attachment.');
      const captured = values(original).map(value => {
        const item = records.get(value.id);
        need(item && exactSame(item.value, value) && item.reservation === reservation, 'media_attachment', 'Original media attachment custody changed.');
        return item.promise;
      });
      return Promise.all(captured).then(value => {ready(); return value;});
    },
    link({observation, sequence}) {
      // Snapshot before queueing; host calls only after journal transactioncomplete.
      const preparation = captureParticipantObservation(observation, held.view_hash).then(value => ({value}), error => ({error}));
      return queue(async () => {
        const result = await preparation; if (result.error) throw result.error;
        need(integer(sequence, baseline + 1, 10000000), 'media_link', 'Use the actual committed journal sequence.');
        const page = await journal.read({after: sequence - 1, limit: 1});
        const actual = page.events[0];
        need(actual?.sequence === sequence && same(await captureParticipantObservation(actual.observation, held.view_hash), result.value),
          'media_link', 'The original attachment must already exist at this exact journal sequence.');
        return linkOriginal(JSON.parse(result.value.json), sequence);
      });
    },
    retry() {
      if (retrying) return retrying;
      need(accepting, 'media_closed', 'The media-record owner is closed.');
      recovering = true;
      const attempt = queue(async () => {
        try {
          unavailable = true; db?.close(); connect(await openDatabase()); unavailable = false;
          for (const item of records.values()) if (!item.saved) {
            item.promise = persist(item); item.promise.catch(error => {item.error = error;}); await item.promise;
          }
          await reconcile(); storageReady();
          return freeze({pending_records: records.size, reserved_attachments: reservations.size});
        } catch (error) {
          unavailable = true; db?.close(); throw error;
        }
      }, true);
      retrying = attempt.finally(() => {recovering = false; retrying = null;});
      return retrying;
    },
    state: () => freeze({pending_records: records.size, unsaved_records: Array.from(records.values()).filter(item => !item.saved).length,
      reserved_attachments: reservations.size, unavailable: unavailable || recovering, recovering, closed: !accepting}),
    originals: () => freeze(Array.from(records.values(), item => item.value)),
    close() {
      if (closing) return closing;
      need(Array.from(records.values()).every(item => item.saved) && reservations.size === 0,
        'media_unsaved', 'Preserve and recover original media observations before closing.');
      accepting = false; closing = tail.then(() => {db.close(); ownership.release(); return ownership.lifetime();}); return closing;
    }
  });
}
