/* Inactive local observation and exact operation journal. No network, current
 * server authority, camera storage or questionnaire navigation is owned here. */
import {encodeParticipantRequest} from './request-bytes.mjs';
import {admitParticipantOperationResult} from './operation-result.mjs';

const DATABASE = 'brohn-assigned-participant', VERSION = 2;
const LIMIT = 10000000, PAGE = 100, PAGE_BYTES = 4 * 1024 * 1024;
const plain = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const integer = (value, minimum = 0, maximum = LIMIT) => Number.isSafeInteger(value) && value >= minimum && value <= maximum;
const hash = value => typeof value === 'string' && value.length === 64 && /^[a-f0-9]{64}$/.test(value);
const key = (value, prefix) => typeof value === 'string' && value.length === 68 && value.startsWith(prefix + '-') && hash(value.slice(4));
const text = (value, maximum) => typeof value === 'string' && value.trim().length > 0 && [...value].length <= maximum;
function refuse(code, message) { const error = new Error(message); error.code = code; error.retained = true; throw error; }
function require(ok, code, message) { if (!ok) refuse(code, message); }
function fields(value, names, label) {
  require(plain(value) && Object.keys(value).length === names.length && names.every(name => Object.hasOwn(value, name)),
    'journal_shape', `${label} has unsupported fields.`);
}
function bindingValue(value) {
  fields(value, ['schema', 'run_id', 'source_protocol_hash', 'renderer_identity', 'view_codec', 'view_bytes', 'view_hash'], 'Run binding');
  const r = value.renderer_identity;
  fields(r, ['schema', 'id', 'manifest_hash'], 'Renderer identity');
  require(value.schema === 'participant-view-binding/0.1' && key(value.run_id, 'pvu') && hash(value.source_protocol_hash) &&
    value.view_codec === 'brohn-participant-json-bytes/0.1' && integer(value.view_bytes, 1, 16 * 1024 * 1024) && hash(value.view_hash) &&
    r.schema === 'participant-renderer-identity/0.1' && text(r.id, 120) && r.id.match(/^[a-z][a-z0-9./-]*$/)?.[0] === r.id && hash(r.manifest_hash),
    'journal_binding', 'The saved study presentation binding is invalid.');
  // Object member order is not an identity field in the public binding. Preserve
  // every field value while using one explicit local comparison representation.
  return {schema: value.schema, run_id: value.run_id, source_protocol_hash: value.source_protocol_hash,
    renderer_identity: {schema: r.schema, id: r.id, manifest_hash: r.manifest_hash},
    view_codec: value.view_codec, view_bytes: value.view_bytes, view_hash: value.view_hash};
}
function observationValue(value, binding, sending = false) {
  fields(value, ['view_hash', 'event'], 'Observed event');
  fields(value.event, ['id', 'type', 'step_key', 'phase', 'clock', 'payload'], 'Public event');
  const e = value.event;
  // Historical reads retain v1's accepted text domain as well as the corrected
  // R-compatible domain. Only new collection/sending uses the latter alone.
  const eventText = sending ? boundedText : (value, maximum) => text(value, maximum) || boundedText(value, maximum);
  require(value.view_hash === binding.view_hash && eventText(e.id, 128) && eventText(e.type, 40) && eventText(e.phase, 96) &&
    (e.step_key === null || key(e.step_key, 'pvs')) && plain(e.clock) && plain(e.payload),
    'journal_observation', 'This observation differs from the assigned study presentation.');
  if (sending) {
    const c = e.clock;
    fields(c, ['id', 'unit', 'value', 'instance_id', 'time_origin_ms'], 'Observed page clock');
    const decimal = x => boundedText(x, 64) && /^[0-9]+([.][0-9]+)?$/.exec(x)?.[0] === x && Number.isFinite(Number(x));
    require(c.id === 'browser-monotonic' && c.unit === 'ms' && decimal(c.value) && decimal(c.time_origin_ms) &&
      Number(c.value) <= 1e12 && boundedText(c.instance_id, 128), 'journal_clock', 'Keep the explicit original page monotonic clock.');
  }
  return value;
}
function storedObservation(row) {
  fields(row, ['run_id', 'sequence', 'event_id', 'codec', 'json', 'bytes', 'sha256'], 'Saved observation');
  require(typeof row.json === 'string' && row.json.length <= 4 * 1024 * 1024 && integer(row.bytes, 1, 4 * 1024 * 1024) &&
    hash(row.sha256) && new TextEncoder().encode(row.json).byteLength === row.bytes,
    'journal_integrity', 'Saved observation metadata is invalid.');
  return row;
}

const META = ['schema', 'run_id', 'binding_json', 'baseline_sequence', 'acked_sequence', 'next_sequence'];
const DOCUMENT = ['codec', 'json', 'bytes', 'sha256'];
const OPERATION = ['schema', 'run_id', 'operation_id', 'state', 'request', 'sequence', 'observations', 'result', 'model', 'receipt'];
const freeze = value => {
  if (value !== null && typeof value === 'object') {Object.values(value).forEach(freeze); Object.freeze(value);}
  return value;
};
function same(a, b) {
  if (Object.is(a, b)) return true;
  if (!a || !b || typeof a !== 'object' || typeof b !== 'object' || Array.isArray(a) !== Array.isArray(b)) return false;
  const aa = Object.keys(a), bb = Object.keys(b);
  return aa.length === bb.length && aa.every(k => Object.hasOwn(b, k) && same(a[k], b[k]));
}
function boundedText(id, maximum) {
  if (typeof id !== 'string' || !id.replace(/^[ \t\r\n]+|[ \t\r\n]+$/g, '').length) return false;
  let size = 0;
  for (let i = 0; i < id.length; i++) {
    const c = id.charCodeAt(i);
    if (c === 0) return false;
    if (c >= 0xd800 && c <= 0xdbff) {
      const low = id.charCodeAt(++i); if (!(low >= 0xdc00 && low <= 0xdfff)) return false; size += 4;
    } else {if (c >= 0xdc00 && c <= 0xdfff) return false; size += c < 0x80 ? 1 : c < 0x800 ? 2 : 3;}
    if (size > maximum) return false;
  }
  return true;
}
const operationId = id => boundedText(id, 128);
function documentShape(doc, codec) {
  fields(doc, DOCUMENT, 'Saved operation document');
  require(doc.codec === codec && typeof doc.json === 'string' && doc.json.length <= PAGE_BYTES &&
    integer(doc.bytes, 1, PAGE_BYTES) && hash(doc.sha256) && new TextEncoder().encode(doc.json).byteLength === doc.bytes,
    'journal_integrity', 'Saved operation document metadata is invalid.');
}
function operationShape(row, runId) {
  fields(row, OPERATION, 'Saved operation');
  require(row.schema === 'participant-journal-operation/0.1' && row.run_id === runId && operationId(row.operation_id) &&
    ['pending', 'accepted'].includes(row.state), 'journal_integrity', 'Saved operation identity is invalid.');
  documentShape(row.request, 'brohn-participant-request-json/0.1');
  const s = row.sequence; fields(s, ['first', 'last', 'count', 'prior_ack', 'committed_ack'], 'Saved operation interval');
  require(integer(s.prior_ack, 0, LIMIT - 1) && integer(s.first, s.prior_ack + 1, s.prior_ack + 1) &&
    integer(s.count, 1, PAGE) && integer(s.last, s.first) && s.last - s.first + 1 === s.count && s.committed_ack === s.last &&
    Array.isArray(row.observations) && row.observations.length === s.count, 'journal_integrity', 'Saved operation interval is invalid.');
  row.observations.forEach((r, i) => {
    fields(r, ['sequence', 'event_id', 'codec', 'bytes', 'sha256'], 'Operation observation reference');
    require(r.sequence === s.first + i && boundedText(r.event_id, 128) && r.codec === 'brohn-participant-request-json/0.1' &&
      integer(r.bytes, 1, PAGE_BYTES) && hash(r.sha256), 'journal_integrity', 'Saved operation observation reference is invalid.');
  });
  if (row.state === 'pending') require(row.result === null && row.model === null && row.receipt === null,
    'journal_integrity', 'Pending operation already contains an uncommitted result.');
  else {
    documentShape(row.result, 'brohn-participant-json-bytes/0.1'); documentShape(row.model, 'brohn-participant-json-bytes/0.1');
    require(plain(row.receipt), 'journal_integrity', 'Accepted operation has no retained receipt.');
  }
  return row;
}
const Uint8 = Uint8Array, uint8Prototype = Uint8.prototype, typedPrototype = Object.getPrototypeOf(uint8Prototype);
const byteLengthOf = Object.getOwnPropertyDescriptor(typedPrototype, 'byteLength').get;
const bufferOf = Object.getOwnPropertyDescriptor(typedPrototype, 'buffer').get;
const copyInto = uint8Prototype.set, arrayBufferPrototype = ArrayBuffer.prototype;
const arrayBufferLengthOf = Object.getOwnPropertyDescriptor(arrayBufferPrototype, 'byteLength').get;
function captureResultBytes(value) {
  require(value && Object.getPrototypeOf(value) === uint8Prototype, 'journal_result', 'An actual result byte array is required.');
  const length = Reflect.apply(byteLengthOf, value, []), buffer = Reflect.apply(bufferOf, value, []);
  Reflect.apply(arrayBufferLengthOf, buffer, []);
  require(Object.getPrototypeOf(buffer) === arrayBufferPrototype && integer(length, 1, PAGE_BYTES),
    'journal_result', 'A bounded nonshared result byte array is required.');
  const raw = new Uint8(length); Reflect.apply(copyInto, raw, [value]); return raw;
}

function holdRun(runId) {
  require(globalThis.navigator?.locks && globalThis.indexedDB && globalThis.IDBKeyRange,
    'journal_unavailable', 'This browser needs secure study storage and single-tab protection before continuing.');
  return new Promise((resolve, reject) => {
    const lifetime = navigator.locks.request(`brohn-assigned-run:${runId}`, {mode: 'exclusive', ifAvailable: true}, lock => {
      if (!lock) { reject(Object.assign(new Error('This study is already open in another tab.'), {code: 'journal_busy', retained: true})); return; }
      return new Promise(release => resolve({release, lifetime: () => lifetime}));
    });
    lifetime.catch(reject);
  });
}
function database() {
  return new Promise((resolve, reject) => {
    let refused = false, upgradeFailure = null;
    const request = indexedDB.open(DATABASE, VERSION);
    request.onupgradeneeded = () => {
      if (refused) { request.transaction.abort(); return; }
      try {
        const db = request.result;
        if (!db.objectStoreNames.contains('runs')) {
          db.createObjectStore('runs', {keyPath: 'run_id'});
          const events = db.createObjectStore('observations', {keyPath: ['run_id', 'sequence']});
          events.createIndex('event_id', ['run_id', 'event_id'], {unique: true});
        }
        if (!db.objectStoreNames.contains('operations')) db.createObjectStore('operations', {keyPath: ['run_id', 'operation_id']});
      } catch (error) { upgradeFailure = error; request.transaction.abort(); }
    };
    request.onerror = () => reject(Object.assign(new Error('Saved progress is unavailable. Allow browser storage before continuing.'),
      {code: 'journal_storage', retained: true, cause: upgradeFailure || request.error}));
    request.onblocked = () => { refused = true; reject(Object.assign(new Error('Close other study tabs before opening saved progress.'),
      {code: 'journal_blocked', retained: true})); };
    request.onsuccess = () => { if (refused) request.result.close(); else resolve(request.result); };
  });
}
function transact(db, mode, action) {
  return new Promise((resolve, reject) => {
    let tx, result, original = null;
    try {
      tx = mode === 'readwrite' ? db.transaction(['runs', 'observations', 'operations'], mode, {durability: 'strict'}) : db.transaction(['runs', 'observations', 'operations'], mode);
    } catch (error) { reject(error); return; }
    const guard = callback => (...args) => {
      try { callback(...args); } catch (error) {
        original ||= error;
        try { tx.abort(); } catch (_) { /* Completion/abort remains the only settlement. */ }
      }
    };
    tx.oncomplete = () => resolve(result);
    tx.onabort = () => reject(original || Object.assign(new Error('Progress could not be saved. Your previously saved responses remain in this browser.'),
      {code: 'journal_storage', retained: true, cause: tx.error}));
    tx.onerror = () => { /* IndexedDB aborts the whole transaction on request errors. */ };
    guard(() => {
      require(mode !== 'readwrite' || tx.durability === 'strict', 'journal_durability', 'This browser cannot use the required saved-progress write mode.');
      action({runs: tx.objectStore('runs'), events: tx.objectStore('observations'), operations: tx.objectStore('operations'), guard, done: value => { result = value; }});
    })();
  });
}

export async function openParticipantJournal({binding: supplied, baselineSequence}) {
  require(integer(baselineSequence), 'journal_baseline', 'Saved progress needs its authenticated server sequence.');
  // Encoder traverses synchronously before WebCrypto; computed/hidden fields and
  // malformed Unicode are refused rather than read or silently repaired.
  const captured = await encodeParticipantRequest(supplied);
  const binding = bindingValue(JSON.parse(captured.json));
  const bindingJSON = JSON.stringify(binding), runId = binding.run_id;
  const lock = await holdRun(runId);
  let db, accepting = true, tail = Promise.resolve(), closing = null, needsCurrentRefresh = false;
  const inspect = meta => {
    fields(meta, [...META, 'pending_operation_id', 'latest_operation_id'], 'Saved progress');
    require(meta.schema === 'participant-observation-journal/0.2' && meta.run_id === runId && meta.binding_json === bindingJSON &&
      integer(meta.baseline_sequence) && integer(meta.acked_sequence, meta.baseline_sequence) &&
      integer(meta.next_sequence, meta.acked_sequence + 1, LIMIT + 1) &&
      [meta.pending_operation_id, meta.latest_operation_id].every(id => id === null || operationId(id)) &&
      (meta.pending_operation_id === null || meta.pending_operation_id !== meta.latest_operation_id),
      'journal_integrity', 'Saved progress does not match this study presentation.');
    return meta;
  };
  const reconciliation = meta => needsCurrentRefresh || baselineSequence !== meta.acked_sequence;
  const queue = action => {
    require(accepting, 'journal_closed', 'This saved-progress handle is closed. Reopen the study before continuing.');
    const next = tail.then(action); tail = next.catch(() => {}); return next;
  };
  function close() {
    if (!closing) {
      accepting = false;
      closing = tail.then(() => { db?.close(); lock.release(); return lock.lifetime(); });
    }
    return closing;
  }
  try {
    db = await database();
    db.onversionchange = () => { void close(); };
    db.onclose = () => { void close(); };
    const initialization = transact(db, 'readwrite', ({runs, guard, done}) => {
      const get = runs.get(runId);
      get.onsuccess = guard(() => {
        if (get.result) {
          let meta = get.result;
          if (meta.schema === 'participant-observation-journal/0.1') {
            fields(meta, META, 'Original saved progress');
            meta = {...meta, schema: 'participant-observation-journal/0.2', pending_operation_id: null, latest_operation_id: null};
            inspect(meta); runs.put(meta);
          }
          done(inspect(meta)); return;
        }
        const value = {schema: 'participant-observation-journal/0.2', run_id: runId, binding_json: bindingJSON,
          baseline_sequence: baselineSequence, acked_sequence: baselineSequence, next_sequence: baselineSequence + 1,
          pending_operation_id: null, latest_operation_id: null};
        inspect(value); runs.add(value); done(value);
      });
    });
    // Version change can arrive while this transaction is pending. Include it
    // in ownership before yielding, so close cannot release the run lock early.
    tail = initialization.catch(() => {});
    const initial = await initialization;
    needsCurrentRefresh = baselineSequence !== initial.acked_sequence;
    require(accepting, 'journal_closed', 'Saved progress changed while opening. Reopen this study before continuing.');
  } catch (error) { await close(); throw error; }

  const observationRef = row => ({sequence: row.sequence, event_id: row.event_id, codec: row.codec, bytes: row.bytes, sha256: row.sha256});
  const operationEnvelope = (id, rows) => ({schema: 'participant-view-events/0.1', view_hash: binding.view_hash,
    operation_id: id, events: rows.map(r => ({sequence: r.row.sequence, ...r.value.event}))});
  async function verifiedObservation(row) {
    storedObservation(row);
    require(row.run_id === runId && integer(row.sequence, 1), 'journal_integrity', 'Saved observation belongs to another sequence or run.');
    const value = observationValue(JSON.parse(row.json), binding, true), encoded = await encodeParticipantRequest(value);
    require(row.event_id === value.event.id && row.codec === encoded.codec && row.json === encoded.json && row.sha256 === encoded.sha256 && row.bytes === encoded.bytes,
      'journal_integrity', 'Saved observation bytes failed their integrity check.');
    return {row, value};
  }
  function metadataSnapshot() {
    return transact(db, 'readonly', ({runs, guard, done}) => {
      const request = runs.get(runId); request.onsuccess = guard(() => done(inspect(request.result)));
    });
  }
  function operationSnapshot(id) {
    return transact(db, 'readonly', ({runs, events, operations, guard, done}) => {
      const get = runs.get(runId);
      get.onsuccess = guard(() => {
        const meta = inspect(get.result), request = operations.get([runId, id]);
        request.onsuccess = guard(() => {
          if (!request.result) {done({meta, operation: null, observations: []}); return;}
          const operation = operationShape(request.result, runId), observations = new Array(operation.sequence.count);
          require(operation.operation_id === id && operation.sequence.first > meta.baseline_sequence && operation.sequence.last < meta.next_sequence,
            'journal_integrity', 'Saved operation falls outside retained local history.');
          require(operation.state === 'pending' ? meta.pending_operation_id === id && operation.sequence.prior_ack === meta.acked_sequence :
            operation.sequence.last <= meta.acked_sequence && meta.pending_operation_id !== id,
            'journal_integrity', 'Saved operation state differs from local progress.');
          let remaining = observations.length;
          operation.observations.forEach((reference, i) => {
            const event = events.get([runId, reference.sequence]);
            event.onsuccess = guard(() => {
              require(event.result, 'journal_gap', 'An operation observation is missing. Existing evidence is retained.');
              storedObservation(event.result);
              require(same(observationRef(event.result), reference) && event.result.run_id === runId,
                'journal_integrity', 'Operation observation references differ from saved evidence.');
              observations[i] = event.result; if (!--remaining) done({meta, operation, observations});
            });
          });
        });
      });
    });
  }
  async function verifyOperationSnapshot(snapshot) {
    const op = snapshot.operation; if (op === null) return snapshot;
    const verified = [];
    for (const row of snapshot.observations) verified.push(await verifiedObservation(row));
    const request = await encodeParticipantRequest(operationEnvelope(op.operation_id, verified));
    require(same(request, op.request), 'journal_integrity', 'Saved pending request does not contain its exact original observations.');
    if (op.state === 'accepted') {
      const admitted = await admitParticipantOperationResult({resultBytes: new TextEncoder().encode(op.result.json), binding,
        pending: {operation_id: op.operation_id, request: {codec: op.request.codec, bytes: op.request.bytes, sha256: op.request.sha256}, sequence: op.sequence}});
      require(same(op.result, admitted.result) && same(op.model, admitted.model) && same(op.receipt, admitted.receipt),
        'journal_integrity', 'Saved accepted result or model differs from its retained receipt.');
    }
    return snapshot;
  }
  function fence(snapshot, id, mode, commit) {
    // Only exact retained-value comparisons and IDB requests belong here.
    // All JSON/domain/encoding/digest work completed before this transaction.
    return transact(db, mode, ({runs, events, operations, guard, done}) => {
      const get = runs.get(runId);
      get.onsuccess = guard(() => {
        require(same(get.result, snapshot.meta), 'journal_stale', 'Saved progress changed before the operation could settle.');
        const request = operations.get([runId, id]);
        request.onsuccess = guard(() => {
          require(snapshot.operation === null ? request.result === undefined : same(request.result, snapshot.operation),
            'journal_stale', 'Saved operation changed before it could settle.');
          let remaining = snapshot.observations.length;
          const finish = () => commit({runs, operations, done});
          if (!remaining) {finish(); return;}
          for (const row of snapshot.observations) {
            const event = events.get([runId, row.sequence]);
            event.onsuccess = guard(() => {
              require(same(event.result, row), 'journal_stale', 'Operation evidence changed before it could settle.');
              if (!--remaining) finish();
            });
          }
        });
      });
    });
  }
  const pendingReturn = (op, repeated) => freeze({operation_id: op.operation_id, request: structuredClone(op.request),
    sequence: structuredClone(op.sequence), repeated});
  async function prepareOperation(id) {
    const meta = await metadataSnapshot();
    if (meta.pending_operation_id !== null) {
      const snapshot = await verifyOperationSnapshot(await operationSnapshot(meta.pending_operation_id));
      require(snapshot.operation?.state === 'pending', 'journal_integrity', 'The pending operation is missing.');
      const result = pendingReturn(snapshot.operation, true);
      return fence(snapshot, snapshot.operation.operation_id, 'readonly', ({done}) => done(result));
    }
    require(!reconciliation(meta), 'journal_reconcile', 'Refresh the current server state before preparing another operation.');
    require(operationId(id), 'journal_operation_id', 'Use one nonblank operation identity of at most128 UTF8 bytes.');
    const prior = await operationSnapshot(id);
    require(prior.operation === null, 'journal_operation_conflict', 'This operation identity already belongs to retained evidence.');
    require(same(meta, prior.meta), 'journal_stale', 'Saved progress changed while preparing an operation.');
    if (meta.acked_sequence === meta.next_sequence - 1) return null;
    const selected = []; let request = null;
    for (let sequence = meta.acked_sequence + 1; sequence < meta.next_sequence && selected.length < PAGE; sequence++) {
      // At most one additional bounded row is materialized beyond the fitting
      // prefix. This avoids loading100 possible4MiB rows into memory at once.
      const row = await transact(db, 'readonly', ({runs, events, guard, done}) => {
        const get = runs.get(runId);
        get.onsuccess = guard(() => {
          require(same(get.result, meta), 'journal_stale', 'Saved progress changed while selecting an operation.');
          const event = events.get([runId, sequence]);
          event.onsuccess = guard(() => {
            require(event.result && event.result.sequence === sequence && event.result.run_id === runId,
              'journal_gap', 'The next unacknowledged observation is missing. Existing evidence is retained.');
            storedObservation(event.result); done(event.result);
          });
        });
      });
      const verified = await verifiedObservation(row), next = [...selected, verified];
      try {request = await encodeParticipantRequest(operationEnvelope(id, next));}
      catch (error) {
        const bytes = error.message === 'The complete request exceeds its byte limit.';
        const traversal = error.message === 'The request exceeds its traversal limit.';
        if (!bytes && !traversal) throw error;
        if (!selected.length) refuse(bytes ? 'journal_event_size' : 'journal_event_limit',
          `Saved event ${sequence} does not fit the complete request ${bytes ? 'byte' : 'traversal'} limit. It remains in this browser.`);
        break;
      }
      selected.push(verified);
    }
    const count = selected.length, first = meta.acked_sequence + 1, last = first + count - 1;
    const operation = {schema: 'participant-journal-operation/0.1', run_id: runId, operation_id: id, state: 'pending', request,
      sequence: {first, last, count, prior_ack: meta.acked_sequence, committed_ack: last},
      observations: selected.map(r => observationRef(r.row)), result: null, model: null, receipt: null};
    operationShape(operation, runId);
    const snapshot = {meta, operation: null, observations: selected.map(r => r.row)};
    const result = pendingReturn(operation, false);
    return fence(snapshot, id, 'readwrite', ({runs, operations, done}) => {
      operations.add(operation); runs.put({...meta, pending_operation_id: id}); done(result);
    });
  }
  async function acceptResult(id, raw) {
    const snapshot = await verifyOperationSnapshot(await operationSnapshot(id)), op = snapshot.operation;
    require(op !== null, 'journal_operation_missing', 'No saved operation matches this result.');
    const admitted = await admitParticipantOperationResult({resultBytes: raw, binding,
      pending: {operation_id: id, request: {codec: op.request.codec, bytes: op.request.bytes, sha256: op.request.sha256}, sequence: op.sequence}});
    if (op.state === 'accepted') {
      require(same(op.result, admitted.result), 'journal_result_conflict', 'Different bytes were received for an already accepted operation.');
      return fence(snapshot, id, 'readonly', ({done}) => done(freeze({operation_id: id, repeated: true,
        committed_sequence: op.sequence.last, acknowledged_sequence: snapshot.meta.acked_sequence,
        needs_current_refresh: reconciliation(snapshot.meta)})));
    }
    const accepted = {...op, state: 'accepted', result: admitted.result, model: admitted.model, receipt: admitted.receipt};
    const settled = await fence(snapshot, id, 'readwrite', ({runs, operations, done}) => {
      operations.put(accepted); runs.put({...snapshot.meta, acked_sequence: op.sequence.last, pending_operation_id: null, latest_operation_id: id});
      done(freeze({operation_id: id, repeated: false, committed_sequence: op.sequence.last,
        acknowledged_sequence: op.sequence.last, needs_current_refresh: true}));
    });
    needsCurrentRefresh = true; return settled;
  }

  return Object.freeze({
    prepareOperation(id) {return queue(() => prepareOperation(id));},
    operation(id) {
      require(operationId(id), 'journal_operation_id', 'Use a retained operation identity.');
      return queue(async () => {
        const snapshot = await verifyOperationSnapshot(await operationSnapshot(id));
        return snapshot.operation === null ? null : freeze(structuredClone(snapshot.operation));
      });
    },
    operationStatus() {
      return queue(async () => {
        const meta = await metadataSnapshot();
        for (const [id, state] of [[meta.pending_operation_id, 'pending'], [meta.latest_operation_id, 'accepted']]) {
          if (id === null) continue;
          const snapshot = await verifyOperationSnapshot(await operationSnapshot(id));
          require(same(snapshot.meta, meta) && snapshot.operation?.state === state &&
            (state !== 'accepted' || snapshot.operation.sequence.last === meta.acked_sequence),
            'journal_integrity', 'Operation references differ from retained progress.');
        }
        return freeze({pending_operation_id: meta.pending_operation_id, latest_operation_id: meta.latest_operation_id,
          needs_current_refresh: reconciliation(meta)});
      });
    },
    acceptResult({operationId: id, resultBytes}) {
      require(accepting, 'journal_closed', 'This saved-progress handle is closed.');
      require(operationId(id), 'journal_operation_id', 'Use a retained operation identity.');
      const raw = captureResultBytes(resultBytes);
      return queue(() => acceptResult(id, raw));
    },
    append(observation) {
      require(accepting, 'journal_closed', 'This saved-progress handle is closed.');
      // Capture now, enqueue now. Waiting for WebCrypto before enqueuing would
      // allow a later observation's faster digest to steal an earlier sequence.
      const preparation = encodeParticipantRequest(observation).then(value => ({value}), error => ({error}));
      return queue(async () => {
        const prepared = await preparation; if (prepared.error) throw prepared.error;
        const encoded = prepared.value, value = observationValue(JSON.parse(encoded.json), binding, true);
        return transact(db, 'readwrite', ({runs, events, guard, done}) => {
          const get = runs.get(runId);
          get.onsuccess = guard(() => {
            const meta = inspect(get.result);
            require(!reconciliation(meta), 'journal_reconcile', 'Reconcile the server confirmation with saved progress before collecting another answer.');
            const prior = events.index('event_id').get([runId, value.event.id]);
            prior.onsuccess = guard(() => {
              const old = prior.result;
              if (old) {
                storedObservation(old);
                require(old.run_id === runId && old.event_id === value.event.id && integer(old.sequence, meta.baseline_sequence + 1, meta.next_sequence - 1) &&
                  old.json === encoded.json && old.sha256 === encoded.sha256 && old.bytes === encoded.bytes && old.codec === encoded.codec,
                  'journal_event_conflict', 'This event identity already belongs to different saved evidence.');
                done({sequence: old.sequence, repeated: true}); return;
              }
              require(meta.next_sequence <= LIMIT, 'journal_sequence_limit', 'This study reached its supported event count. Saved responses are retained.');
              const sequence = meta.next_sequence;
              events.add({run_id: runId, sequence, event_id: value.event.id, ...encoded});
              runs.put({...meta, next_sequence: sequence + 1});
              done({sequence, repeated: false});
            });
          });
        });
      });
    },
    status() {
      return queue(() => transact(db, 'readonly', ({runs, guard, done}) => {
        const get = runs.get(runId);
        get.onsuccess = guard(() => {
          const m = inspect(get.result);
          done({run_id: runId, baseline_sequence: m.baseline_sequence, acknowledged_sequence: m.acked_sequence,
            next_sequence: m.next_sequence, requires_reconciliation: reconciliation(m)});
        });
      }));
    },
    read({after, limit = PAGE}) {
      require(integer(after) && integer(limit, 1, PAGE), 'journal_page', 'Read a bounded saved-event page.');
      return queue(async () => {
        const page = await transact(db, 'readonly', ({runs, events, guard, done}) => {
          const get = runs.get(runId);
          get.onsuccess = guard(() => {
            const m = inspect(get.result);
            require(after >= m.baseline_sequence && after < m.next_sequence, 'journal_page', 'The requested page is outside the retained local event range.');
            if (after === m.next_sequence - 1) { done({rows: [], next_sequence: m.next_sequence}); return; }
            let bytes = 0;
            const rows = [], cursor = events.openCursor(IDBKeyRange.bound([runId, after + 1], [runId, LIMIT]));
            cursor.onsuccess = guard(() => {
              const c = cursor.result;
              if (!c || rows.length === limit) {
                const count = Math.min(limit, m.next_sequence - after - 1);
                require(rows.length === count, 'journal_gap', 'A saved event is missing. Existing responses have been retained.');
                done({rows, next_sequence: m.next_sequence}); return;
              }
              require(c.value.run_id === runId && c.value.sequence === after + rows.length + 1 && c.value.sequence < m.next_sequence,
                'journal_gap', 'Saved observations are not contiguous.');
              storedObservation(c.value);
              if (rows.length && bytes + c.value.bytes > PAGE_BYTES) { done({rows, next_sequence: m.next_sequence}); return; }
              rows.push(c.value);
              bytes += c.value.bytes;
              if (rows.length === limit) { done({rows, next_sequence: m.next_sequence}); return; }
              c.continue();
            });
          });
        });
        const result = [];
        for (const row of page.rows) {
          storedObservation(row);
          const value = observationValue(JSON.parse(row.json), binding);
          const encoded = await encodeParticipantRequest(value);
          require(row.event_id === value.event.id && row.codec === encoded.codec && row.json === encoded.json &&
            row.sha256 === encoded.sha256 && row.bytes === encoded.bytes,
            'journal_integrity', 'Saved observation bytes failed their integrity check.');
          result.push({sequence: row.sequence, observation: value});
        }
        const through = result.length ? result[result.length - 1].sequence : after;
        return {events: result, next_sequence: page.next_sequence, through_sequence: through, has_more: through < page.next_sequence - 1};
      });
    },
    close
  });
}
