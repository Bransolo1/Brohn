/* Inactive held-session paging. Exact literal documents, not decoded state,
 * enter the public model. Authentication is this owned HTTP path's concern. */
import {admitParticipantQuestionnaireModel} from './questionnaire-model.mjs';
import {encodeParticipantRequest} from './request-bytes.mjs';
import {PARTICIPANT_JSON_CODEC} from './wire-json.mjs';

const PAGE = 3 * 1024 * 1024, AGGREGATE = 64 * 1024 * 1024;
const REQUEST_MS = 60000, LOAD_MS = 180000;
const networkFetch = globalThis.fetch.bind(globalThis);
const error = (code, message) => Object.assign(new Error(message), {code, retained: true});
const need = (ok, code, message) => {if (!ok) throw error(code, message);};
const cancel = async body => {try {await body?.cancel();} catch (_) {}};
async function digest(raw) {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', raw)), x => x.toString(16).padStart(2, '0')).join('');
}

export function createParticipantQuestionnairePages({sender, accessToken, maximumPacketBytes = AGGREGATE}) {
  need(sender && typeof sender.currentDocument === 'function' && typeof sender.state === 'function',
    'questionnaire_sender', 'An owned literal-current sender is required.');
  need(typeof accessToken === 'string' && accessToken.length === 64 && /^[a-f0-9]{64}$/.test(accessToken),
    'questionnaire_credential', 'The original held run credential is required.');
  need(Number.isSafeInteger(maximumPacketBytes) && maximumPacketBytes >= 1 && maximumPacketBytes <= AGGREGATE,
    'questionnaire_budget', 'Use a supported encoded-packet budget.');
  let closed = false, flight = null, requestedComplete = false, abort = null;
  const active = () => need(!closed, 'questionnaire_pages_closed', 'Questionnaire page loading is closed.');
  function fence(origin) {
    active();
    const current = sender.currentDocument(), state = sender.state();
    need(current === origin && current.current_generation === origin.current_generation &&
      current.acknowledged_sequence === origin.acknowledged_sequence &&
      current.packet_state_token === origin.packet_state_token && current.resume_state_token === origin.resume_state_token &&
      state.collection_transport_ready && state.phase === 'ready',
    'questionnaire_current_changed', 'Current progress changed. Load its fresh questionnaire before continuing.');
  }
  async function body(response, origin) {
    const declared = response.headers.get('Content-Length');
    if (declared !== null && (!/^[0-9]+$/.test(declared) || !Number.isSafeInteger(Number(declared)) || Number(declared) < 1 || Number(declared) > PAGE)) {
      await cancel(response.body); throw error('questionnaire_page_size', 'The questionnaire page has an invalid byte length.');
    }
    const encoding = response.headers.get('Content-Encoding');
    if (encoding !== null && encoding.toLowerCase() !== 'identity') {
      await cancel(response.body); throw error('questionnaire_page_encoding', 'The questionnaire page needs its original uncompressed bytes.');
    }
    need(response.body, 'questionnaire_page_body', 'The server returned no questionnaire page.');
    const reader = response.body.getReader(), parts = []; let size = 0;
    try {
      for (;;) {
        fence(origin); const item = await reader.read(); fence(origin);
        if (item.done) break;
        size += item.value.byteLength;
        need(size <= PAGE, 'questionnaire_page_size', 'The actual questionnaire page exceeds its byte limit.');
        parts.push(item.value);
      }
      need(size > 0 && (declared === null || Number(declared) === size), 'questionnaire_page_size', 'The questionnaire page byte length differs.');
      const raw = new Uint8Array(size); let offset = 0;
      for (const part of parts) {raw.set(part, offset); offset += part.byteLength;}
      return raw;
    } finally {try {await reader.cancel();} catch (_) {} finally {reader.releaseLock();}}
  }
  async function page(request, origin, deadline) {
    fence(origin);
    const document = await encodeParticipantRequest(request); fence(origin);
    const remaining = deadline - performance.now();
    need(remaining > 0, 'questionnaire_page_timeout', 'Questionnaire loading needs another attempt. Saved progress remains.');
    const controller = new AbortController(); abort = controller; let response = null;
    const timer = setTimeout(() => controller.abort(), Math.min(REQUEST_MS, remaining));
    try {
      const url = new URL(`/api/view/questionnaire_state/${origin.binding.run_id}`, location.origin);
      response = await networkFetch(url.href, {method: 'POST',
        headers: {Authorization: `Bearer ${accessToken}`, Accept: 'application/json', 'Content-Type': 'application/json; charset=utf-8'},
        body: new TextEncoder().encode(document.json), cache: 'no-store', credentials: 'omit', mode: 'same-origin', redirect: 'error', signal: controller.signal});
      fence(origin);
      if (response.status !== 200) {await cancel(response.body); throw error('questionnaire_page_http_' + response.status, 'The server did not admit this questionnaire page. Refresh current progress.');}
      if (!/^application\/json(?:\s*;|$)/i.test(response.headers.get('Content-Type') || '')) {
        await cancel(response.body); throw error('questionnaire_page_type', 'The server did not return the expected questionnaire document.');
      }
      const raw = await body(response, origin); fence(origin);
      need(!(raw[0] === 239 && raw[1] === 187 && raw[2] === 191), 'questionnaire_page_bom', 'Questionnaire pages cannot contain a byte marker.');
      let json;
      try {json = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(raw);}
      catch (_) {throw error('questionnaire_page_utf8', 'The questionnaire page has invalid text encoding. Keep saved progress and refresh.');}
      const sha256 = await digest(raw); fence(origin);
      return Object.freeze({codec: PARTICIPANT_JSON_CODEC, json, bytes: raw.byteLength, sha256});
    } catch (problem) {
      fence(origin);
      throw typeof problem.code === 'string' ? problem : error(controller.signal.aborted ? 'questionnaire_page_timeout' : 'questionnaire_page_network',
        'The questionnaire page could not be confirmed. Keep saved progress and retry loading.');
    } finally {clearTimeout(timer); if (abort === controller) abort = null; await cancel(response?.body);}
  }
  async function work(complete) {
    active(); const origin = sender.currentDocument();
    need(origin !== null && origin.questionnaire_document !== null, 'questionnaire_unavailable', 'Current progress has no questionnaire packet.');
    fence(origin);
    const deadline = performance.now() + LOAD_MS, documents = [origin.questionnaire_document];
    for (;;) {
      fence(origin);
      need(performance.now() < deadline, 'questionnaire_page_timeout', 'Questionnaire loading needs another attempt.');
      const model = await admitParticipantQuestionnaireModel({binding: origin.binding, viewDocument: origin.view_document,
        packetDocuments: documents, currentGeneration: origin.current_generation, acknowledgedSequence: origin.acknowledged_sequence,
        maximumPacketBytes});
      fence(origin);
      need(performance.now() < deadline, 'questionnaire_page_timeout', 'Questionnaire loading needs another attempt.');
      const snapshot = model.snapshot(), visit = snapshot.packet.latest_occurrence?.visit ?? null;
      const needsCurrentRow = visit !== null && model.step(visit.step_key)?.type === 'question' && model.record(visit.step_key) === null;
      need(!snapshot.records_complete || !needsCurrentRow, 'questionnaire_page_missing', 'The complete recovery packet omits its current question record.');
      if ((!complete && !needsCurrentRow) || snapshot.records_complete) return Object.freeze({origin, model});
      const request = model.nextPageRequest();
      need(request !== null && documents.length < 20001, 'questionnaire_page_missing', 'The current questionnaire record is unavailable.');
      documents.push(await page(request, origin, deadline)); fence(origin);
    }
  }
  return Object.freeze({
    load({complete = false} = {}) {
      active(); need(typeof complete === 'boolean', 'questionnaire_page_mode', 'Use an explicit complete-review mode.');
      if (flight) {need(requestedComplete === complete, 'questionnaire_pages_busy', 'Wait for the current page load before changing its scope.'); return flight;}
      requestedComplete = complete; const next = Promise.resolve().then(() => work(complete)); flight = next;
      next.then(() => {if (flight === next) flight = null;}, () => {if (flight === next) flight = null;}); return next;
    },
    close() {closed = true; abort?.abort(); return Promise.resolve(flight).catch(() => {});}
  });
}
