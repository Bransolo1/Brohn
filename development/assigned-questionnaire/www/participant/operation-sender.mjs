/* Inactive actual-network coordinator. No start, draft or rendering controller. */
import {openParticipantJournal} from './observation-journal.mjs';
import {encodeParticipantRequest} from './request-bytes.mjs';
import {admitParticipantCurrentSession} from './current-session.mjs';
import {binding as validateBinding, freeze} from './current-structure.mjs';

const MAX_BYTES = 4 * 1024 * 1024, REQUEST_MS = 60000, PASS_MS = 180000;
const ATTEMPTS = 2, MAX_OPERATIONS = 4, RETRY_MS = 250;
const networkFetch = globalThis.fetch.bind(globalThis);
const failure = (code, message, retryable = false) => Object.assign(new Error(message), {code, retryable, retained: true});
const cancelBody = async body => {try {await body?.cancel();} catch (_) {/* Preserve the observed HTTP/read condition. */}};

export function createParticipantOperationSender({binding, viewJson, accessToken, onState = null}) {
  if (onState !== null && typeof onState !== 'function') throw new TypeError('onState must be a function.');
  // Capture supplied plain values synchronously; retain a refusal until start.
  const preparation = encodeParticipantRequest({binding, viewJson, accessToken})
    .then(value => ({value}), error => ({error}));
  let held = null, journal = null, current = null, flight = null, closing = null;
  let closed = false, requestAbort = null, wakeDelay = null, observerFailed = false;
  let state = {schema: 'participant-operation-sender-state/0.1', phase: 'idle', collection_transport_ready: false,
    operation_id: null, attempt: 0, acknowledged_sequence: null, error: null, current: null, observer_failed: false};
  const snapshot = () => freeze(structuredClone(state));
  const active = () => {if (closed) throw failure('sender_closed', 'This saved-response sender is closed.');};
  function publish(next) {
    state = {...state, ...next, observer_failed: observerFailed};
    if (onState) {
      try {onState(snapshot());} catch (_) {
        // Observer failure cannot roll back or relabel a committed observation.
        observerFailed = true; state = {...state, observer_failed: true};
      }
    }
  }
  async function declarations() {
    if (held) return held;
    const prepared = await preparation; active(); if (prepared.error) throw prepared.error;
    const value = JSON.parse(prepared.value.json); validateBinding(value.binding);
    if (typeof value.viewJson !== 'string' || typeof value.accessToken !== 'string' ||
      value.accessToken.length !== 64 || !/^[a-f0-9]{64}$/.test(value.accessToken)) throw failure('sender_binding', 'A held presentation and exact run credential are required.');
    held = freeze(value); return held;
  }
  function delay(deadline) {
    active();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {wakeDelay = null; resolve();}, Math.min(RETRY_MS, Math.max(0, deadline - performance.now())));
      wakeDelay = () => {clearTimeout(timer); wakeDelay = null; reject(failure('sender_closed', 'Recovery was stopped. Saved responses remain.'));};
    });
  }
  async function bytes(response) {
    const declared = response.headers.get('Content-Length');
    if (declared !== null && (!/^[0-9]+$/.test(declared) || Number(declared) > MAX_BYTES)) {
      await cancelBody(response.body); throw failure('sender_response_size', 'The server response exceeds its supported byte limit.');
    }
    if (!response.body) throw failure('sender_response', 'The server returned no response body.');
    const reader = response.body.getReader(), parts = []; let size = 0;
    try {
      while (true) {
        active(); const result = await reader.read(); active(); if (result.done) break;
        size += result.value.byteLength;
        if (size > MAX_BYTES) throw failure('sender_response_size', 'The actual server response exceeds its byte limit.');
        parts.push(result.value);
      }
      if (!size) throw failure('sender_response', 'The server returned an empty response.');
      const raw = new Uint8Array(size); let offset = 0;
      for (const part of parts) {raw.set(part, offset); offset += part.byteLength;}
      return raw;
    } finally {try {await reader.cancel();} catch (_) {/* Cleanup cannot replace the original read refusal. */} finally {reader.releaseLock();}}
  }
  async function request(kind, pending, deadline) {
    for (let attempt = 1; attempt <= ATTEMPTS; attempt++) {
      active();
      const remaining = deadline - performance.now();
      if (remaining <= 0) throw failure('sender_timeout', 'Recovery needs another attempt. Saved responses remain in this browser.');
      publish({phase: kind === 'current' ? 'refreshing' : 'sending', collection_transport_ready: false, attempt,
        operation_id: pending?.operation_id ?? null, error: null});
      active();
      const abort = new AbortController(); requestAbort = abort;
      const timer = setTimeout(() => abort.abort(), Math.min(REQUEST_MS, remaining));
      let problem;
      try {
        const url = new URL(`/api/view/${kind === 'current' ? 'current' : 'events'}/${held.binding.run_id}`, location.origin);
        const headers = {Authorization: `Bearer ${held.accessToken}`, Accept: 'application/json'};
        if (kind !== 'current') headers['Content-Type'] = 'application/json; charset=utf-8';
        const response = await networkFetch(url.href, {method: kind === 'current' ? 'GET' : 'POST', headers,
          body: kind === 'current' ? undefined : new TextEncoder().encode(pending.request.json),
          cache: 'no-store', credentials: 'omit', mode: 'same-origin', redirect: 'error', signal: abort.signal});
        active();
        if (response.status !== 200) {
          await cancelBody(response.body);
          throw failure('sender_http_' + response.status, 'The server did not accept this recovery request. Saved responses remain.',
            response.status === 408 || response.status === 429 || response.status >= 500);
        }
        if (!/^application\/json(?:\s*;|$)/i.test(response.headers.get('Content-Type') || '')) {
          await cancelBody(response.body); throw failure('sender_content_type', 'The response is not the expected JSON document.');
        }
        return await bytes(response);
      } catch (error) {
        active();
        problem = error.code ? error : failure('sender_network', 'Connection interrupted. Retrying the same saved operation is safe.', true);
      } finally {clearTimeout(timer); if (requestAbort === abort) requestAbort = null;}
      if (!problem.retryable || attempt === ATTEMPTS) throw problem;
      publish({phase: 'retrying', collection_transport_ready: false, error: {code: problem.code, message: problem.message}});
      await delay(deadline);
    }
  }
  async function refresh(deadline) {
    const raw = await request('current', null, deadline); active();
    const admitted = await admitParticipantCurrentSession({currentBytes: raw, binding: held.binding,
      viewJson: held.viewJson, accessToken: held.accessToken}); active();
    if (journal) {await journal.close(); journal = null; active();}
    const opened = await openParticipantJournal({binding: held.binding, baselineSequence: admitted.acknowledged_sequence});
    if (closed) {await opened.close(); active();}
    journal = opened; current = admitted;
    publish({current: admitted.session, acknowledged_sequence: admitted.acknowledged_sequence, operation_id: null, attempt: 0});
  }
  async function accept(pending, raw, deadline) {
    for (let attempt = 1; attempt <= ATTEMPTS; attempt++) {
      active(); publish({phase: 'saving_receipt', collection_transport_ready: false, attempt, operation_id: pending.operation_id});
      active();
      try {await journal.acceptResult({operationId: pending.operation_id, resultBytes: raw}); active(); return;}
      catch (error) {
        active(); if (error.code !== 'journal_storage' || attempt === ATTEMPTS) throw error;
        publish({phase: 'retrying', error: {code: 'journal_storage', message: 'Saving the confirmation was interrupted. Retrying the same confirmation.'}});
        await delay(deadline);
      }
    }
  }
  async function work() {
    const deadline = performance.now() + PASS_MS;
    try {
      await declarations(); await refresh(deadline);
      for (let count = 0; ; count++) {
        active();
        const status = await journal.status(), operations = await journal.operationStatus(); active();
        // Existing pending may have committed before the session closed. Only
        // the authenticated server can distinguish it from an uncommitted write.
        if (operations.pending_operation_id === null &&
          (current.session.researcher_resolution !== null || current.session.completion_status !== 'in_progress')) {
          publish({phase: 'closed_by_server', collection_transport_ready: false, operation_id: operations.pending_operation_id,
            error: {code: 'sender_server_closed', message: 'This session is closed. Any unsent local evidence remains in this browser.'}}); return snapshot();
        }
        if (operations.pending_operation_id === null && status.requires_reconciliation)
          throw failure('sender_reconciliation', 'Server and local acknowledgements differ. Local evidence has not been deleted or rebased.');
        if (operations.pending_operation_id === null && status.next_sequence === status.acknowledged_sequence + 1) {
          publish({phase: 'ready', collection_transport_ready: true, operation_id: null, attempt: 0, error: null,
            acknowledged_sequence: status.acknowledged_sequence}); return snapshot();
        }
        if (count >= MAX_OPERATIONS || performance.now() >= deadline)
          throw failure('sender_more_pending', 'More saved responses remain. Continue recovery before collecting another answer.');
        const id = operations.pending_operation_id ?? `op-${crypto.randomUUID()}`;
        const pending = await journal.prepareOperation(id); active();
        if (!pending) throw failure('sender_pending_changed', 'Saved progress changed while preparing recovery.');
        // The exact journal document is already durable; no request reconstruction.
        const raw = await request('events', pending, deadline); active();
        await accept(pending, raw, deadline);
        // A historical receipt is never substituted for a CURRENT response.
        await refresh(deadline);
      }
    } catch (error) {
      if (closed) return snapshot();
      publish({phase: 'needs_attention', collection_transport_ready: false, attempt: 0,
        error: {code: error.code || 'sender_invalid_response', message: error.code ? error.message : 'Current recovery could not be verified. Saved evidence remains.'}});
      return snapshot();
    }
  }
  function synchronize() {
    if (closed) return Promise.reject(failure('sender_closed', 'This sender is closed.'));
    if (flight) return flight;
    // Establish the shared promise before callbacks can reenter synchronize.
    const next = Promise.resolve().then(work); flight = next;
    publish({phase: 'refreshing', collection_transport_ready: false, error: null});
    next.then(() => {if (flight === next) flight = null;}, () => {if (flight === next) flight = null;});
    return next;
  }
  function close() {
    if (!closing) {
      closed = true;
      closing = Promise.resolve(flight).catch(() => {}).then(async () => {if (journal) {await journal.close(); journal = null;}});
      requestAbort?.abort(); wakeDelay?.();
      publish({phase: 'closed', collection_transport_ready: false, error: null});
    }
    return closing;
  }
  return Object.freeze({
    synchronize, state: snapshot, close,
    append(observation) {
      active();
      if (flight || !journal || !state.collection_transport_ready) throw failure('sender_not_ready', 'Reconcile saved responses before collecting more.');
      // The original journal captures immediately and owns sequencing. No clock,
      // ID, payload, or sequence is replaced by network/confirmation time.
      return journal.append(observation);
    }
  });
}
