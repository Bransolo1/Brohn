/* Inactive, local typed questionnaire drafts. A draft is neither an answer nor
 * current permission to edit. No observation, ACK, network or run bootstrap. */
import {encodeParticipantRequest, PARTICIPANT_REQUEST_CODEC} from './request-bytes.mjs';
import {verifyParticipantJsonBytes, PARTICIPANT_JSON_CODEC} from './wire-json.mjs';
import {binding as bindingShape, fields, same, freeze, integer, key, text, hash} from './current-structure.mjs';
import {questionShape, answerShape} from './question-domain.mjs';

const DATABASE = 'brohn-assigned-questionnaire-drafts', VERSION = 1;
const LIMIT = 10000000, BYTES = 4 * 1024 * 1024;
function fail(code, message) { throw Object.assign(new Error(message), {code, durable: false}); }
function need(ok, code, message) { if (!ok) fail(code, message); }
function contextShape(c) {
  fields(c, ['step_key', 'question_key', 'occurrence_key', 'visit_id', 'state_version', 'last_answer_event_id', 'dependency_generation']);
  need(key(c.step_key, 'pvs') && key(c.question_key, 'pvq') && key(c.occurrence_key, 'pvo') && text(c.visit_id, 128) &&
    integer(c.state_version) && integer(c.dependency_generation) && (c.last_answer_event_id === null || text(c.last_answer_event_id, 128)),
  'draft_context', 'Keep the complete original public draft context.');
}
function valueShape(value) {
  fields(value, ['schema', 'context', 'question', 'draft']);
  need(value.schema === 'participant-questionnaire-draft/0.1', 'draft_schema', 'Unsupported local draft schema.');
  contextShape(value.context); questionShape(value.question);
  const d = value.draft;
  fields(d, ['step_key', 'question_key', 'draft_revision', 'value']);
  need(d.step_key === value.context.step_key && d.question_key === value.context.question_key &&
    d.question_key === value.question.question_key && integer(d.draft_revision, 1, Number.MAX_SAFE_INTEGER),
  'draft_context', 'The draft differs from its original question, step or revision.');
  answerShape(value.question, d.value);
}
function documentShape(d) {
  fields(d, ['codec', 'json', 'bytes', 'sha256']);
  need(d.codec === PARTICIPANT_REQUEST_CODEC && typeof d.json === 'string' && d.json.length <= BYTES &&
    integer(d.bytes, 1, BYTES) && hash(d.sha256), 'draft_integrity', 'Invalid saved draft byte descriptor.');
}
async function documentValue(d) {
  documentShape(d);
  // The literal verifier checks bytes/hash and strict JSON before materializing.
  // The declared source codec remains the request codec; no identity is inferred
  // from this parser adapter or from a hypothetical reserialization.
  const parsed = await verifyParticipantJsonBytes(d.json, {codec: PARTICIPANT_JSON_CODEC, bytes: d.bytes, sha256: d.sha256}, {maximumBytes: BYTES});
  valueShape(parsed.value);
  const encoded = await encodeParticipantRequest(parsed.value);
  need(same(encoded, d), 'draft_integrity', 'Saved draft is not its exact admitted local encoding.');
  return parsed.value;
}
function lock(runId) {
  need(globalThis.navigator?.locks && globalThis.indexedDB, 'draft_unavailable', 'Secure browser draft storage is required.');
  return new Promise((resolve, reject) => {
    const lifetime = navigator.locks.request(`brohn-assigned-drafts:${runId}`, {mode: 'exclusive', ifAvailable: true}, held => {
      if (!held) { reject(Object.assign(new Error('These study drafts are already open in another tab.'), {code: 'draft_busy'})); return; }
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
      if (refused) { request.transaction.abort(); return; }
      try {
        const db = request.result;
        db.createObjectStore('runs', {keyPath: 'run_id'});
        db.createObjectStore('writers', {keyPath: ['run_id', 'step_key']});
        db.createObjectStore('drafts', {keyPath: ['run_id', 'step_key', 'generation']});
      } catch (error) { original = error; request.transaction.abort(); }
    };
    request.onblocked = () => { refused = true; reject(Object.assign(new Error('Close other draft tabs before continuing.'), {code: 'draft_blocked'})); };
    request.onerror = () => reject(original || request.error);
    request.onsuccess = () => { if (refused) request.result.close(); else resolve(request.result); };
  });
}
function transact(db, mode, action) {
  return new Promise((resolve, reject) => {
    let tx, result, original = null;
    try { tx = mode === 'readwrite' ? db.transaction(['runs', 'writers', 'drafts'], mode, {durability: 'strict'}) :
      db.transaction(['runs', 'writers', 'drafts'], mode); } catch (error) { reject(error); return; }
    const guard = fn => (...args) => {
      try { fn(...args); } catch (error) { original ||= error; try { tx.abort(); } catch (_) { /* Native settlement remains definitive. */ } }
    };
    tx.oncomplete = () => resolve(result);
    tx.onabort = () => reject(original || Object.assign(new Error('This draft was not saved. Previously saved drafts remain.'), {code: 'draft_storage', durable: false, cause: tx.error}));
    tx.onerror = () => {};
    guard(() => {
      need(mode !== 'readwrite' || tx.durability === 'strict', 'draft_durability', 'Strict draft transactions are required.');
      action({runs: tx.objectStore('runs'), writers: tx.objectStore('writers'), drafts: tx.objectStore('drafts'), guard, done: x => { result = x; }});
    })();
  });
}

export async function openParticipantQuestionnaireDrafts(input) {
  // Capture all caller values before the first digest await; accessors and
  // classed/reference values are refused by the accepted request encoder.
  const captured = await encodeParticipantRequest(input);
  const supplied = JSON.parse(captured.json); fields(supplied, ['binding']); bindingShape(supplied.binding);
  need(/^[a-z][a-z0-9./-]*$/.exec(supplied.binding.renderer_identity.id)?.[0] === supplied.binding.renderer_identity.id,
    'draft_binding', 'Renderer identity must retain its complete registered spelling.');
  const binding = freeze(supplied.binding), runId = binding.run_id;
  const held = await lock(runId);
  let db, accepting = true, tail = Promise.resolve(), closing = null;
  function inspectRun(row) {
    fields(row, ['schema', 'run_id', 'binding']);
    need(row.schema === 'participant-draft-run/0.1' && row.run_id === runId && same(row.binding, binding),
      'draft_binding', 'Saved drafts belong to a different original presentation.');
    return row;
  }
  function inspectWriter(row, step) {
    if (row === undefined) return null;
    fields(row, ['run_id', 'step_key', 'generation', 'saved_generation']);
    need(row.run_id === runId && row.step_key === step && integer(row.generation, 1) &&
      (row.saved_generation === null || integer(row.saved_generation, 1, row.generation)), 'draft_integrity', 'Saved draft writer is invalid.');
    return row;
  }
  function inspectRow(row, step, generation) {
    fields(row, ['schema', 'run_id', 'step_key', 'generation', 'revision', 'document']);
    need(row.schema === 'participant-draft-row/0.1' && row.run_id === runId && row.step_key === step && row.generation === generation &&
      integer(row.generation, 1) && integer(row.revision, 1, Number.MAX_SAFE_INTEGER), 'draft_integrity', 'Saved draft row identity differs.');
    documentShape(row.document); return row;
  }
  async function verifiedRow(row, step, generation) {
    inspectRow(row, step, generation);
    const value = await documentValue(row.document);
    need(value.context.step_key === step && value.draft.draft_revision === row.revision, 'draft_integrity', 'Saved draft payload differs from its row.');
    return freeze({generation, context: value.context, question: value.question, draft: value.draft, document: row.document});
  }
  function enqueue(action) {
    need(accepting, 'draft_closed', 'Draft storage is closed.');
    const next = tail.then(action); tail = next.catch(() => {}); return next;
  }
  function close() {
    if (closing) return closing;
    accepting = false;
    closing = (async () => { try { await tail; } finally { if (db) db.close(); held.release(); await held.lifetime(); } })();
    return closing;
  }
  const withRun = (stores, callback) => {
    const get = stores.runs.get(runId);
    get.onsuccess = stores.guard(() => { inspectRun(get.result); callback(); });
  };
  try {
    db = await database();
    db.onversionchange = () => { void close(); };
    db.onclose = () => { void close(); };
    const init = transact(db, 'readwrite', ({runs, guard, done}) => {
      const get = runs.get(runId);
      get.onsuccess = guard(() => {
        if (get.result) { inspectRun(get.result); done(); return; }
        runs.add({schema: 'participant-draft-run/0.1', run_id: runId, binding}); done();
      });
    });
    tail = init.catch(() => {}); await init;
    need(accepting, 'draft_closed', 'Draft storage changed while opening.');
  } catch (error) { await close(); throw error; }

  function begin(input) {
    need(accepting, 'draft_closed', 'Draft storage is closed.');
    const capture = encodeParticipantRequest(input); capture.catch(() => {});
    return enqueue(async () => {
      const value = JSON.parse((await capture).json); fields(value, ['context', 'question']);
      contextShape(value.context); questionShape(value.question);
      need(value.context.question_key === value.question.question_key, 'draft_context', 'The draft question differs from its context.');
      freeze(value); const step = value.context.step_key;
      const generation = await transact(db, 'readwrite', stores => withRun(stores, () => {
        const get = stores.writers.get([runId, step]);
        get.onsuccess = stores.guard(() => {
          const before = inspectWriter(get.result, step), generation = before ? before.generation + 1 : 1;
          need(generation <= LIMIT, 'draft_limit', 'This step has reached its local writer limit.');
          stores.writers.put({run_id: runId, step_key: step, generation, saved_generation: before?.saved_generation ?? null});
          stores.done(generation);
        });
      }));
      let writerOpen = true;
      function save(draft) {
        need(accepting && writerOpen, 'draft_closed', 'This draft writer is closed.');
        const capture = encodeParticipantRequest({schema: 'participant-questionnaire-draft/0.1', context: value.context, question: value.question, draft});
        capture.catch(() => {});
        return enqueue(async () => {
          const document = await capture, decoded = JSON.parse(document.json); valueShape(decoded);
          const row = {schema: 'participant-draft-row/0.1', run_id: runId, step_key: step, generation, revision: decoded.draft.draft_revision, document};
          const before = await transact(db, 'readonly', stores => withRun(stores, () => {
            const get = stores.drafts.get([runId, step, generation]); get.onsuccess = stores.guard(() => stores.done(get.result ?? null));
          }));
          if (before !== null) {
            await verifiedRow(before, step, generation);
            need(row.revision > before.revision || row.revision === before.revision && same(document, before.document),
              'draft_revision', 'This draft revision is older or has conflicting content.');
          }
          await transact(db, 'readwrite', stores => withRun(stores, () => {
            const get = stores.writers.get([runId, step]);
            get.onsuccess = stores.guard(() => {
              const writer = inspectWriter(get.result, step);
              need(writer?.generation === generation, 'draft_superseded', 'A newer question view owns draft editing.');
              const original = stores.drafts.get([runId, step, generation]);
              original.onsuccess = stores.guard(() => {
                need(same(original.result ?? null, before), 'draft_changed', 'The saved draft changed before this write.');
                stores.drafts.put(row); stores.writers.put({...writer, saved_generation: generation}); stores.done();
              });
            });
          }));
          return freeze({generation, draft_revision: row.revision, document});
        });
      }
      return Object.freeze({generation, save, close: () => { writerOpen = false; }});
    });
  }
  function read(step) {
    need(key(step, 'pvs'), 'draft_step', 'A public step key is required.');
    return enqueue(async () => {
      const snapshot = await transact(db, 'readonly', stores => withRun(stores, () => {
        const get = stores.writers.get([runId, step]);
        get.onsuccess = stores.guard(() => {
          const writer = inspectWriter(get.result, step);
          if (!writer || writer.saved_generation === null) { stores.done(null); return; }
          const row = stores.drafts.get([runId, step, writer.saved_generation]);
          row.onsuccess = stores.guard(() => { need(row.result !== undefined, 'draft_integrity', 'The saved draft row is missing.'); stores.done(row.result); });
        });
      }));
      return snapshot === null ? null : verifiedRow(snapshot, step, snapshot.generation);
    });
  }
  return Object.freeze({begin, read, close});
}
