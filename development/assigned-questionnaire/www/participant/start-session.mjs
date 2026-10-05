/* Inactive private start custody. Network authority and current editing belong
 * to the start controller and operation sender, respectively. */
import {encodeParticipantRequest, PARTICIPANT_REQUEST_CODEC} from './request-bytes.mjs';
import {verifyParticipantJsonBytes, PARTICIPANT_JSON_CODEC} from './wire-json.mjs';
import {admitParticipantCurrentSession} from './current-session.mjs';
import {fields, same, freeze, hash, text, integer} from './current-structure.mjs';

const DATABASE = 'brohn-assigned-starts', VERSION = 1, MAX = 4 * 1024 * 1024;
const U8 = Uint8Array, typed = Object.getPrototypeOf(U8.prototype);
const lengthOf = Object.getOwnPropertyDescriptor(typed, 'byteLength').get;
const bufferOf = Object.getOwnPropertyDescriptor(typed, 'buffer').get;
const abLength = Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'byteLength').get;
const set = U8.prototype.set;
const failure = (code, message, cause) => Object.assign(new Error(message), {code, retained: true, ...(cause ? {cause} : {})});
function require(ok, code, message) {if (!ok) throw failure(code, message);}
function renderer(value) {
  fields(value, ['schema', 'id', 'manifest_hash']);
  require(value.schema === 'participant-renderer-identity/0.1' && text(value.id, 120) &&
    /^[a-z][a-z0-9./-]*$/.exec(value.id)?.[0] === value.id && hash(value.manifest_hash), 'start_renderer', 'The original study software identity is required.');
}
function capture(raw) {
  require(raw && Object.getPrototypeOf(raw) === U8.prototype, 'start_response', 'The actual start response bytes are required.');
  const bytes = Reflect.apply(lengthOf, raw, []), buffer = Reflect.apply(bufferOf, raw, []);
  Reflect.apply(abLength, buffer, []);
  require(Object.getPrototypeOf(buffer) === ArrayBuffer.prototype && integer(bytes, 1, MAX), 'start_response', 'The start response exceeds its supported size.');
  const copy = new U8(bytes); Reflect.apply(set, copy, [raw]); return copy;
}
async function digest(raw) {
  return Array.from(new U8(await crypto.subtle.digest('SHA-256', raw)), x => x.toString(16).padStart(2, '0')).join('');
}
function docShape(doc, codec) {
  fields(doc, ['codec', 'json', 'bytes', 'sha256']);
  require(doc.codec === codec && typeof doc.json === 'string' && doc.json.length <= MAX &&
    integer(doc.bytes, 1, MAX) && hash(doc.sha256), 'start_integrity', 'The saved start document is damaged.');
}
async function admittedResponse(raw, expectedRenderer) {
  require(!(raw[0] === 239 && raw[1] === 187 && raw[2] === 191), 'start_response', 'The start response has an unsupported byte marker.');
  const json = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(raw);
  const descriptor = {codec: PARTICIPANT_JSON_CODEC, json, bytes: raw.byteLength, sha256: await digest(raw)};
  const value = (await verifyParticipantJsonBytes(json, {codec: descriptor.codec, bytes: descriptor.bytes, sha256: descriptor.sha256}, {maximumBytes: MAX})).value;
  require(value !== null && typeof value === 'object' && !Array.isArray(value), 'start_response', 'The study returned an invalid session.');
  const admitted = await admitParticipantCurrentSession({currentBytes: raw, binding: value.binding,
    viewJson: value.view_json, accessToken: value.access_token});
  require(same(value.binding.renderer_identity, expectedRenderer), 'start_renderer', 'This session requires its original study software.');
  return {descriptor: freeze(descriptor), held: freeze({binding: value.binding, viewJson: value.view_json, accessToken: value.access_token}),
    publicSession: admitted.session};
}
function lockStart(key) {
  require(globalThis.navigator?.locks && globalThis.indexedDB && globalThis.crypto?.subtle && globalThis.crypto?.randomUUID,
    'start_storage', 'Allow secure browser storage before starting this study.');
  return new Promise((resolve, reject) => {
    const lifetime = navigator.locks.request(`brohn-assigned-start:${key}`, {mode: 'exclusive', ifAvailable: true}, lock => {
      if (!lock) {reject(failure('start_busy', 'This study is already open in another tab.')); return;}
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
      try {request.result.createObjectStore('starts', {keyPath: 'release_token'});}
      catch (error) {original = error; request.transaction.abort();}
    };
    request.onerror = () => reject(failure('start_storage', 'The study start could not be opened in browser storage.', original || request.error));
    request.onblocked = () => {refused = true; reject(failure('start_blocked', 'Close other study tabs before reopening saved progress.'));};
    request.onsuccess = () => {if (refused) request.result.close(); else resolve(request.result);};
  });
}
function transaction(db, mode, action) {
  return new Promise((resolve, reject) => {
    let tx, result, original = null;
    try {tx = mode === 'readwrite' ? db.transaction('starts', mode, {durability: 'strict'}) : db.transaction('starts', mode);}
    catch (error) {reject(error); return;}
    const guard = fn => (...args) => {
      try {fn(...args);} catch (error) {original ||= error; try {tx.abort();} catch (_) {}}
    };
    tx.oncomplete = () => resolve(result);
    tx.onabort = () => reject(original || failure('start_storage', 'The start was not saved. Your existing saved progress is retained.', tx.error));
    tx.onerror = () => {};
    guard(() => {
      require(mode !== 'readwrite' || tx.durability === 'strict', 'start_storage', 'This browser cannot confirm the required durable start save.');
      action(tx.objectStore('starts'), guard, value => {result = value;});
    })();
  });
}

export async function openParticipantStartSession(input) {
  const captured = await encodeParticipantRequest(input), settings = JSON.parse(captured.json);
  fields(settings, ['releaseToken', 'rendererIdentity']); renderer(settings.rendererIdentity);
  require(hash(settings.releaseToken), 'start_link', 'Use the original study link.');
  const releaseToken = settings.releaseToken, rendererIdentity = settings.rendererIdentity;
  const lock = await lockStart(releaseToken);
  let db, accepting = true, closing = null, tail = Promise.resolve();
  const active = () => require(accepting, 'start_closed', 'Reopen this study to continue its saved start.');
  const queue = action => {active(); const p = tail.then(action); tail = p.catch(() => {}); return p;};
  function close() {
    if (!closing) {accepting = false; closing = tail.then(() => {db?.close(); lock.release(); return lock.lifetime();});}
    return closing;
  }
  const rowShape = row => {
    if (row === undefined) return;
    fields(row, ['schema', 'release_token', 'renderer_identity', 'revision', 'request', 'response']);
    require(row.schema === 'participant-start-custody/0.1' && row.release_token === releaseToken &&
      same(row.renderer_identity, rendererIdentity) && [1, 2].includes(row.revision), 'start_integrity', 'Saved start identity differs from the original study.');
    docShape(row.request, PARTICIPANT_REQUEST_CODEC);
    require((row.revision === 1) === (row.response === null), 'start_integrity', 'Saved start progress is inconsistent.');
    if (row.response !== null) docShape(row.response, PARTICIPANT_JSON_CODEC);
  };
  async function inspect(row) {
    rowShape(row); if (row === undefined) return null;
    // Regenerate only our original request codec; received R JSON is never
    // reserialized to establish its identity.
    const request = JSON.parse(row.request.json), canonical = await encodeParticipantRequest(request);
    require(same(canonical, row.request), 'start_integrity', 'The original saved start request failed its byte check.');
    fields(request, Object.hasOwn(request, 'participant_alias') ? ['consented', 'client_id', 'operation_id', 'participant_alias'] : ['consented', 'client_id', 'operation_id']);
    require(typeof request.consented === 'boolean' && text(request.client_id, 128) && text(request.operation_id, 128) &&
      (!Object.hasOwn(request, 'participant_alias') || typeof request.participant_alias === 'string' &&
        new TextEncoder().encode(request.participant_alias).byteLength <= 200), 'start_integrity', 'The original saved start request is invalid.');
    const response = row.response === null ? null : await admittedResponse(new TextEncoder().encode(row.response.json), rendererIdentity);
    require(response === null || same(response.descriptor, row.response), 'start_integrity', 'The saved session failed its byte check.');
    return {row, request, response};
  }
  const readRow = () => transaction(db, 'readonly', (store, guard, done) => {
    const request = store.get(releaseToken); request.onsuccess = guard(() => done(request.result));
  });
  const compare = (oldRow, nextRow) => transaction(db, 'readwrite', (store, guard, done) => {
    const get = store.get(releaseToken); get.onsuccess = guard(() => {
      rowShape(get.result);
      require(same(get.result, oldRow), 'start_changed', 'The saved start changed. Reopen this study without creating a new participant.');
      const put = oldRow === undefined ? store.add(nextRow) : store.put(nextRow);
      put.onsuccess = guard(() => done(nextRow));
    });
  });
  try {
    db = await database(); db.onversionchange = () => {void close();}; db.onclose = () => {void close();};
    const initialization = readRow().then(inspect); tail = initialization.catch(() => {});
    await initialization; active();
  } catch (error) {await close(); throw error;}
  return Object.freeze({
    close,
    state() {return queue(async () => {const value = await inspect(await readRow());
      return freeze({schema: 'participant-start-state/0.1', phase: !value ? 'empty' : value.response ? 'saved' : 'pending',
        request_saved: !!value, session_saved: !!value?.response});});},
    prepare(choice) {
      // Capture before queued work can wait; never read caller getters later.
      const input = encodeParticipantRequest(choice).then(value => ({value}), error => ({error}));
      return queue(async () => {
        const copied = await input; if (copied.error) throw copied.error;
        const c = JSON.parse(copied.value.json);
        fields(c, Object.hasOwn(c, 'participantAlias') ? ['consented', 'participantAlias'] : ['consented']);
        require(typeof c.consented === 'boolean' && (!Object.hasOwn(c, 'participantAlias') || typeof c.participantAlias === 'string' &&
          new TextEncoder().encode(c.participantAlias).byteLength <= 200), 'start_choice', 'Keep an explicit consent choice and a short participant alias.');
        const original = await inspect(await readRow());
        if (original) {
          require(original.request.consented === c.consented &&
            Object.hasOwn(original.request, 'participant_alias') === Object.hasOwn(c, 'participantAlias') &&
            original.request.participant_alias === c.participantAlias, 'start_conflict', 'This browser already has a saved start. Resume it without replacing the consent or alias.');
          return freeze(original.row.request);
        }
        const request = await encodeParticipantRequest({consented: c.consented, client_id: crypto.randomUUID(), operation_id: crypto.randomUUID(),
          ...(Object.hasOwn(c, 'participantAlias') ? {participant_alias: c.participantAlias} : {})});
        const row = {schema: 'participant-start-custody/0.1', release_token: releaseToken,
          renderer_identity: rendererIdentity, revision: 1, request, response: null};
        rowShape(row); await compare(undefined, row); return freeze(request);
      });
    },
    pendingRequest() {return queue(async () => {const value = await inspect(await readRow()); return value ? freeze(value.row.request) : null;});},
    acceptResponse(bytes) {
      const raw = capture(bytes);
      return queue(async () => {
        const original = await inspect(await readRow());
        require(original !== null, 'start_missing', 'Save the original start request before accepting a session.');
        const received = await admittedResponse(raw, rendererIdentity);
        if (original.response) {
          require(same(original.response.held, received.held), 'start_conflict', 'The retry returned a different saved study session. Keep the original start.');
          return original.response.held;
        }
        const row = {...original.row, revision: 2, response: received.descriptor};
        rowShape(row); await compare(original.row, row); return received.held;
      });
    },
    handoff() {return queue(async () => {const value = await inspect(await readRow()); return value?.response?.held ?? null;});}
  });
}
