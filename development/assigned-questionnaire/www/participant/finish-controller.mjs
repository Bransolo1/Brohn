/* Owns only finalization. The previous collection owner must drain and close
 * before this controller opens its event journal. No observations are invented. */
import {openParticipantFinishSession} from './finish-session.mjs';
import {createParticipantOperationSender} from './operation-sender.mjs';
import {encodeParticipantRequest} from './request-bytes.mjs';
import {binding as checkBinding, fields, freeze, hash, integer} from './current-structure.mjs';

const MAX = 4 * 1024 * 1024, REQUEST_MS = 60000, PASS_MS = 125000, ATTEMPTS = 2;
const networkFetch = globalThis.fetch.bind(globalThis);
const failure = (code, message, retryable = false) => Object.assign(new Error(message), {code, retryable, retained: true});
const need = (ok, code, message) => {if (!ok) throw failure(code, message);};
const cancelBody = async body => {try {await body?.cancel();} catch (_) {}};

export function createParticipantFinishController({binding, viewJson, accessToken, onState = null}) {
  if (onState !== null && typeof onState !== 'function') throw new TypeError('onState must be a function.');
  const prepared = encodeParticipantRequest({binding, accessToken}).then(value => ({value}), error => ({error}));
  // Strings are immutable; keep the exact literal outside the small declaration
  // encoder. The accepted operation sender performs full CURRENT/view admission.
  const originalView = viewJson;
  let held = null, store = null, sender = null, opening = null, flight = null, closing = null;
  let closed = false, requestAbort = null, cancelDelay = null, observerFailed = false;
  let state = {schema: 'participant-finish-controller-state/0.1', phase: 'idle', request_saved: false, receipt_saved: false,
    outcome: null, final_sequence: null, acknowledged_sequence: null, completion_status: null,
    researcher_resolution: null, attempt: 0, error: null, observer_failed: false};
  const snapshot = () => freeze(structuredClone(state));
  const active = () => need(!closed, 'finish_closed', 'Reopen the original study link to recover its saved ending.');
  function publish(update) {
    state = {...state, ...update, observer_failed: observerFailed};
    if (onState) try {onState(snapshot());} catch (_) {observerFailed = true; state = {...state, observer_failed: true};}
  }
  async function local() {
    active();
    if (!opening) opening = (async () => {
      const input = await prepared; active(); if (input.error) throw input.error;
      held = JSON.parse(input.value.json); checkBinding(held.binding);
      need(hash(held.accessToken) && typeof originalView === 'string', 'finish_session', 'Use the original saved session and participant credential.');
      store = await openParticipantFinishSession({binding: held.binding}); active();
      sender = createParticipantOperationSender({binding: held.binding, viewJson: originalView, accessToken: held.accessToken});
      return store;
    })();
    return opening;
  }
  async function custody() {
    const saved = await (await local()).state(); active();
    publish({request_saved: saved.request_saved, receipt_saved: saved.receipt_saved, outcome: saved.outcome, final_sequence: saved.final_sequence});
    active(); return saved;
  }
  function perform(action) {
    active(); need(!flight, 'finish_busy', 'Wait for the current finish or recovery attempt.');
    const task = Promise.resolve().then(action).catch(error => {
      if (!closed) publish({phase: 'attention', attempt: 0, error: {
        code: typeof error.code === 'string' && /^[a-z0-9_]+$/.test(error.code) ? error.code : 'finish_failed',
        message: 'The study ending could not be confirmed. Keep this browser’s saved progress and retry.', retryable: error.retryable === true}});
      throw error;
    });
    flight = task; task.then(() => {if (flight === task) flight = null;}, () => {if (flight === task) flight = null;});
    return task;
  }
  async function current() {
    publish({phase: 'checking', attempt: 0}); active();
    const observed = await sender.synchronize(); active();
    need(['ready', 'closed_by_server'].includes(observed.phase) && observed.current !== null,
      observed.error?.code || 'finish_current', 'Current study progress could not be verified. Your original finish remains saved.');
    publish({acknowledged_sequence: observed.acknowledged_sequence, completion_status: observed.current.completion_status,
      researcher_resolution: observed.current.researcher_resolution}); active();
    return observed;
  }
  function delay() {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {cancelDelay = null; resolve();}, 250);
      cancelDelay = () => {clearTimeout(timer); cancelDelay = null; reject(failure('finish_closed', 'Finish recovery was stopped. Saved progress remains.'));};
    });
  }
  async function responseBytes(response) {
    const size = response.headers.get('Content-Length');
    if (size !== null && (!/^[0-9]+$/.test(size) || !Number.isSafeInteger(Number(size)) || Number(size) > MAX)) {
      await cancelBody(response.body); throw failure('finish_response_size', 'The finish response exceeds its supported size.');
    }
    need(response.body, 'finish_response', 'The finish response has no body.');
    const reader = response.body.getReader(), parts = []; let length = 0;
    try {
      while (true) {
        active(); const part = await reader.read(); active(); if (part.done) break;
        length += part.value.byteLength; need(length <= MAX, 'finish_response_size', 'The finish response exceeds its supported size.');
        parts.push(part.value);
      }
      need(length > 0 && (size === null || Number(size) === length), 'finish_response_size', 'The finish response is incomplete.');
      const raw = new Uint8Array(length); let at = 0;
      for (const part of parts) {raw.set(part, at); at += part.byteLength;}
      return raw;
    } finally {try {await reader.cancel();} catch (_) {} finally {reader.releaseLock();}}
  }
  async function send(document) {
    const deadline = performance.now() + PASS_MS;
    for (let attempt = 1; attempt <= ATTEMPTS; attempt++) {
      active(); const remaining = deadline - performance.now();
      need(remaining > 0, 'finish_timeout', 'Retry the original saved study ending.');
      publish({phase: 'sending', attempt, error: null}); active();
      const abort = new AbortController(); requestAbort = abort;
      const timer = setTimeout(() => abort.abort(), Math.min(REQUEST_MS, remaining));
      let problem;
      try {
        const url = new URL(`/api/view/finish/${held.binding.run_id}`, location.origin);
        const response = await networkFetch(url.href, {method: 'POST', headers: {Authorization: `Bearer ${held.accessToken}`,
          Accept: 'application/json', 'Content-Type': 'application/json; charset=utf-8'}, body: new TextEncoder().encode(document.json),
          mode: 'same-origin', redirect: 'error', credentials: 'omit', cache: 'no-store', signal: abort.signal});
        active();
        if (response.status !== 200) {
          await cancelBody(response.body);
          throw failure(`finish_http_${response.status}`, 'The study server could not confirm the saved ending.',
            response.status === 408 || response.status === 429 || response.status >= 500);
        }
        if (!/^application\/json(?:\s*;|$)/i.test(response.headers.get('Content-Type') || '')) {
          await cancelBody(response.body); throw failure('finish_content_type', 'The study returned an unsupported finish response.');
        }
        return await responseBytes(response);
      } catch (error) {
        active(); problem = typeof error.code === 'string' ? error : failure('finish_network', 'Connection interrupted. Retry the same saved ending.', true);
      } finally {clearTimeout(timer); if (requestAbort === abort) requestAbort = null;}
      if (!problem.retryable || attempt === ATTEMPTS) throw problem;
      publish({phase: 'retrying', error: {code: problem.code, message: problem.message, retryable: true}}); active(); await delay();
    }
  }
  async function recover() {
    const saved = await custody(), document = await store.pendingRequest(); active();
    need(document !== null, 'finish_missing', 'Save an explicit study ending before retrying it.');
    if (!saved.receipt_saved) {
      // On recovery, the server may already have committed the ending. Replay
      // the exact durable operation without replacing it from a new CURRENT.
      const raw = await send(document); active(); publish({phase: 'saving'}); active();
      await store.acceptResponse(raw); active(); await custody();
    }
    const observed = await current();
    need(observed.acknowledged_sequence >= saved.final_sequence, 'finish_ack', 'Current progress is behind the saved finish confirmation.');
    if (observed.current.researcher_resolution !== null) publish({phase: 'resolved', attempt: 0, error: null});
    else {
      need(observed.phase === 'closed_by_server' && observed.current.completion_status === saved.outcome,
        'finish_outcome', 'The saved finish confirmation and current study status differ. Keep both for researcher review.');
      publish({phase: 'finished', attempt: 0, error: null});
    }
    return snapshot();
  }
  function close() {
    if (!closing) {
      closed = true; requestAbort?.abort(); cancelDelay?.();
      const stopping = sender?.close();
      closing = (async () => {
        try {await flight;} catch (_) {}
        try {await opening;} catch (_) {}
        try {await stopping;} catch (_) {}
        await sender?.close(); await store?.close(); publish({phase: 'closed', attempt: 0});
      })();
    }
    return closing;
  }
  return Object.freeze({
    state: snapshot, close,
    inspect: () => perform(async () => {const saved = await custody(); publish({phase: saved.phase, error: null}); return snapshot();}),
    retry: () => perform(recover),
    complete(intent) {
      const copied = encodeParticipantRequest(intent).then(value => ({value}), error => ({error}));
      return perform(async () => {
        const input = await copied; active(); if (input.error) throw input.error;
        const choice = JSON.parse(input.value.json); fields(choice, ['outcome', 'finalSequence']);
        need(['completed', 'interrupted', 'withdrawn'].includes(choice.outcome) && integer(choice.finalSequence, 0, 10000000),
          'finish_intent', 'Keep the original ending and final response sequence.');
        const saved = await custody();
        if (!saved.request_saved) {
          const observed = await current(), storage = observed.storage;
          need(observed.phase === 'ready' && observed.collection_transport_ready &&
            observed.current.completion_status === 'in_progress' && observed.current.researcher_resolution === null &&
            storage.phase === 'open' && storage.unconfirmed_writes === 0 && storage.unresolved_writes === 0 &&
            storage.durable_pending_count === 0 && observed.acknowledged_sequence === choice.finalSequence,
            'finish_pending', 'Confirm every original response and stop collection before saving the study ending.');
        }
        publish({phase: 'saving'}); active(); await store.prepare(choice); active(); await custody();
        return recover();
      });
    }
  });
}
