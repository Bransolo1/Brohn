/* Original-link bootstrap. A durable start handoff is not permission to collect;
 * the participant controller must obtain fresh CURRENT through its sender. */
import {openParticipantStartSession} from './start-session.mjs';
import {encodeParticipantRequest} from './request-bytes.mjs';
import {verifyParticipantJsonBytes, PARTICIPANT_JSON_CODEC} from './wire-json.mjs';
import {fields, same, freeze, hash, text, integer} from './current-structure.mjs';

const MAX = 4 * 1024 * 1024, REQUEST_MS = 60000, PASS_MS = 125000, ATTEMPTS = 2;
const networkFetch = globalThis.fetch.bind(globalThis);
const failure = (code, message, retryable = false) => Object.assign(new Error(message), {code, retryable, retained: true});
const need = (ok, code, message) => {if (!ok) throw failure(code, message);};
const cancel = async body => {try {await body?.cancel();} catch (_) {}};
const digest = async raw => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', raw)), x => x.toString(16).padStart(2, '0')).join('');
const optionalText = (value, limit) => value === '' || text(value, limit) ||
  typeof value === 'string' && value.length <= limit && /^[ \t\r\n]+$/.exec(value)?.[0] === value;

function entryShape(value, settings) {
  fields(value, ['schema', 'title', 'origin', 'release_status', 'workspace_paused', 'alias_required', 'consent', 'appearance', 'welcome', 'renderer_identity']);
  need(value.schema === 'participant-view-entry/0.1' && text(value.title, 240) && text(value.origin, 32) &&
    text(value.release_status, 32) && typeof value.workspace_paused === 'boolean' && typeof value.alias_required === 'boolean',
  'start_entry', 'The study opening is not supported by this software.');
  need(same(value.renderer_identity, settings.rendererIdentity), 'start_renderer', 'Open this study with its original study software.');
  fields(value.consent, ['title', 'text', 'required']);
  need(text(value.consent.title, 240) && text(value.consent.text, 40000) && typeof value.consent.required === 'boolean',
    'start_entry', 'The original consent information is incomplete.');
  fields(value.appearance, ['background', 'foreground']);
  for (const colour of Object.values(value.appearance))
    need(typeof colour === 'string' && /^#[0-9a-fA-F]{6}$/.exec(colour)?.[0] === colour, 'start_entry', 'The study appearance is invalid.');
  if (value.welcome !== null) {
    const w = value.welcome; fields(w, ['schema', 'title', 'text', 'image_alt', 'image']);
    need(w.schema === 'participant-welcome/0.1' && text(w.title, 240) && optionalText(w.text, 20000) && optionalText(w.image_alt, 2000),
      'start_entry', 'The welcome information is invalid.');
    if (w.image !== null) {
      fields(w.image, ['url', 'media_type', 'width', 'height']);
      need(w.image.url === `/api/view/welcome/${settings.releaseToken}` && w.image.media_type === 'image/png' &&
        integer(w.image.width, 1, 4096) && integer(w.image.height, 1, 4096) && w.image.width * w.image.height <= 8000000 && text(w.image_alt, 2000),
      'start_entry', 'The welcome image must belong to this study link.');
    }
  }
  return freeze(value);
}

export function createParticipantStartController({releaseToken, rendererIdentity, onState = null}) {
  if (onState !== null && typeof onState !== 'function') throw new TypeError('onState must be a function.');
  // The request encoder captures plain data immediately, before the first wait.
  const prepared = encodeParticipantRequest({releaseToken, rendererIdentity})
    .then(value => ({value}), error => ({error}));
  let settings = null, store = null, opening = null, flight = null, closing = null;
  let closed = false, abortRequest = null, cancelDelay = null, observerFailed = false;
  let state = {schema: 'participant-start-controller-state/0.1', phase: 'idle', attempt: 0,
    request_saved: false, session_saved: false, error: null, observer_failed: false};
  const snapshot = () => freeze({...state, error: state.error ? {...state.error} : null});
  const active = () => need(!closed, 'start_closed', 'Reopen the original study link to continue.');
  function publish(update) {
    state = {...state, ...update, observer_failed: observerFailed};
    if (onState) try {onState(snapshot());} catch (_) {observerFailed = true; state = {...state, observer_failed: true};}
  }
  async function local() {
    active();
    if (!opening) opening = (async () => {
      const input = await prepared; active(); if (input.error) throw input.error;
      settings = JSON.parse(input.value.json);
      need(hash(settings.releaseToken), 'start_link', 'Use the original study link.');
      store = await openParticipantStartSession(settings); active(); return store;
    })();
    return opening;
  }
  async function custody() {
    const value = await (await local()).state(); active();
    publish({request_saved: value.request_saved, session_saved: value.session_saved}); return value;
  }
  function perform(action) {
    active(); need(!flight, 'start_busy', 'Wait for the current start or recovery request.');
    const task = Promise.resolve().then(action).catch(error => {
      if (!closed) publish({phase: 'attention', attempt: 0, error: {
        code: typeof error.code === 'string' && /^[a-z0-9_]+$/.test(error.code) ? error.code : 'start_failed',
        message: 'The study could not be opened. Your existing saved start is retained.', retryable: error.retryable === true}});
      throw error;
    });
    flight = task; task.then(() => {if (flight === task) flight = null;}, () => {if (flight === task) flight = null;});
    return task;
  }
  function delay() {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {cancelDelay = null; resolve();}, 250);
      cancelDelay = () => {clearTimeout(timer); cancelDelay = null; reject(failure('start_closed', 'Start recovery was stopped. Saved progress remains.'));};
    });
  }
  async function bytes(response) {
    const size = response.headers.get('Content-Length');
    if (size !== null && (!/^[0-9]+$/.test(size) || !Number.isSafeInteger(Number(size)) || Number(size) > MAX)) {
      await cancel(response.body); throw failure('start_response_size', 'The study response exceeds its supported size.');
    }
    need(response.body, 'start_response', 'The study returned no response body.');
    const reader = response.body.getReader(), parts = []; let length = 0;
    try {
      while (true) {
        active(); const part = await reader.read(); active(); if (part.done) break;
        length += part.value.byteLength; need(length <= MAX, 'start_response_size', 'The study response exceeds its supported size.');
        parts.push(part.value);
      }
      need(length > 0, 'start_response', 'The study returned an empty response.');
      const raw = new Uint8Array(length); let at = 0;
      for (const part of parts) {raw.set(part, at); at += part.byteLength;}
      return raw;
    } finally {try {await reader.cancel();} catch (_) {} finally {reader.releaseLock();}}
  }
  async function request(kind, document = null) {
    const deadline = performance.now() + PASS_MS;
    for (let attempt = 1; attempt <= ATTEMPTS; attempt++) {
      active(); const remaining = deadline - performance.now();
      need(remaining > 0, 'start_timeout', 'Reopen the original study link to retry its saved start.');
      publish({phase: kind === 'entry' ? 'loading' : 'starting', attempt, error: null}); active();
      const abort = new AbortController(); abortRequest = abort;
      const timer = setTimeout(() => abort.abort(), Math.min(REQUEST_MS, remaining));
      let problem;
      try {
        const url = new URL(`/api/view/${kind}/${settings.releaseToken}`, location.origin);
        const headers = {Accept: 'application/json'};
        if (document) headers['Content-Type'] = 'application/json; charset=utf-8';
        const response = await networkFetch(url.href, {method: document ? 'POST' : 'GET', headers,
          body: document ? new TextEncoder().encode(document.json) : undefined,
          mode: 'same-origin', redirect: 'error', credentials: 'omit', cache: 'no-store', signal: abort.signal});
        active();
        if (response.status !== 200) {
          await cancel(response.body);
          throw failure(`start_http_${response.status}`, 'The study server could not accept this request. Keep the original link and saved start.',
            response.status === 408 || response.status === 429 || response.status >= 500);
        }
        if (!/^application\/json(?:\s*;|$)/i.test(response.headers.get('Content-Type') || '')) {
          await cancel(response.body); throw failure('start_content_type', 'The study returned an unsupported response.');
        }
        return await bytes(response);
      } catch (error) {
        active(); problem = typeof error.code === 'string' ? error : failure('start_network', 'Connection interrupted. Retry the original saved start.', true);
      } finally {clearTimeout(timer); if (abortRequest === abort) abortRequest = null;}
      if (!problem.retryable || attempt === ATTEMPTS) throw problem;
      publish({phase: 'retrying', error: {code: problem.code, message: problem.message, retryable: true}}); active(); await delay();
    }
  }
  async function openingPage() {
    await local(); active(); const raw = await request('entry'); active();
    need(!(raw[0] === 239 && raw[1] === 187 && raw[2] === 191), 'start_entry', 'The study opening has an unsupported byte marker.');
    const json = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(raw);
    const value = await verifyParticipantJsonBytes(json, {codec: PARTICIPANT_JSON_CODEC, bytes: raw.byteLength, sha256: await digest(raw)}, {maximumBytes: MAX});
    active(); const page = entryShape(value.value, settings); publish({phase: 'opening', attempt: 0, error: null}); return page;
  }
  async function recover() {
    await custody(); const held = await store.handoff(); active();
    if (held) {publish({phase: 'saved', attempt: 0, error: null}); return held;}
    const original = await store.pendingRequest(); active();
    need(original !== null, 'start_missing', 'Read the study information and make your consent choice before starting.');
    const raw = await request('start', original); active(); publish({phase: 'saving', attempt: 0}); active();
    const result = await store.acceptResponse(raw); active(); await custody(); active();
    publish({phase: 'saved', error: null}); return result;
  }
  async function close() {
    if (!closing) {
      closed = true; abortRequest?.abort(); cancelDelay?.();
      closing = (async () => {
        try {await flight;} catch (_) {}
        try {await opening;} catch (_) {}
        if (store) await store.close();
        publish({phase: 'closed', attempt: 0, error: null});
      })();
    }
    return closing;
  }
  return Object.freeze({
    state: snapshot, close,
    inspect: () => perform(async () => {const value = await custody(); publish({phase: value.phase, error: null}); return value;}),
    entry: () => perform(openingPage),
    resume: () => perform(recover),
    begin(choice) {
      const captured = encodeParticipantRequest(choice).then(value => ({value}), error => ({error}));
      return perform(async () => {
        const input = await captured; if (input.error) throw input.error;
        const c = JSON.parse(input.value.json);
        fields(c, Object.hasOwn(c, 'participantAlias') ? ['consented', 'participantAlias'] : ['consented']);
        need(typeof c.consented === 'boolean' && (!Object.hasOwn(c, 'participantAlias') || typeof c.participantAlias === 'string' &&
          new TextEncoder().encode(c.participantAlias).byteLength <= 200), 'start_choice', 'Choose consent explicitly and keep the participant alias short.');
        const existing = await custody();
        if (existing.phase === 'empty') {
          const page = await openingPage(); active();
          need(page.release_status === 'open' && !page.workspace_paused, 'start_unavailable', 'This study is not accepting new participants.');
          need(!page.consent.required || c.consented, 'start_consent', 'Read the study information and agree before starting.');
          need(!page.alias_required || typeof c.participantAlias === 'string' && /[^ \t\r\n]/.test(c.participantAlias),
            'start_alias', 'Enter the participant alias supplied by your researcher.');
        }
        await store.prepare(c); active(); await custody(); active(); return recover();
      });
    }
  });
}
