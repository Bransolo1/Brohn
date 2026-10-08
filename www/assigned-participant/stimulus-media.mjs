/* Assigned ordinary stimulus preparation. All timing/event ownership belongs
 * to the renderer; a prepared element is not permission to present or replay. */
import {encodeParticipantRequest} from './request-bytes.mjs';
import {verifyParticipantJsonBytes} from './wire-json.mjs';
import {binding as checkBinding, fields, same, key, hash, integer} from './current-structure.mjs';

const MAX_BYTES = 512 * 1024 ** 2, PREPARE_MS = 60000;
const TYPES = {
  image: ['image/png', 'image/jpeg', 'image/webp', 'image/gif'],
  audio: ['audio/wav', 'audio/x-wav', 'audio/mpeg', 'audio/ogg', 'audio/webm'],
  video: ['video/mp4', 'video/webm', 'video/ogg']
};
const fail = (code, message) => Object.assign(new Error(message), {code, retained: true});
const need = (ok, code, message) => {if (!ok) throw fail(code, message);};

export function createAssignedStimulusMedia({binding, viewJson, accessToken, document = globalThis.document}) {
  need(document?.nodeType === 9 && document.defaultView && typeof viewJson === 'string',
    'stimulus_document', 'Use the participant document and original saved presentation.');
  const win = document.defaultView, fetchResource = win.fetch.bind(win), literalView = viewJson;
  const input = encodeParticipantRequest({binding, accessToken}).then(value => ({value}), error => ({error}));
  let held = null, declaring = null, closed = false, closing = null, tail = Promise.resolve(), retainedBytes = 0;
  const requests = new Set(), handles = new Set(), prepared = new Map();
  const active = signal => need(!closed && !signal?.aborted, 'stimulus_aborted', 'Study material preparation was stopped.');

  async function loadDeclarations() {
    active();
    const result = await input; if (result.error) throw result.error;
    active();
    const copied = JSON.parse(result.value.json); checkBinding(copied.binding);
    need(hash(copied.accessToken), 'stimulus_credential', 'Use the original saved participant credential.');
    const view = (await verifyParticipantJsonBytes(literalView, {codec: copied.binding.view_codec,
      bytes: copied.binding.view_bytes, sha256: copied.binding.view_hash})).value;
    active();
    need(view.schema === 'brohn-participant-view/0.1' && view.run_id === copied.binding.run_id &&
      view.source_protocol_hash === copied.binding.source_protocol_hash && same(view.renderer_identity, copied.binding.renderer_identity),
      'stimulus_view', 'The material registry differs from the original assigned presentation.');
    need(Array.isArray(view.steps) && view.steps.every(step => step && key(step.step_key, 'pvs')) &&
      new Set(view.steps.map(step => step.step_key)).size === view.steps.length,
      'stimulus_steps', 'The assigned presentation has invalid step identities.');
    const resources = view.presentation?.resources;
    need(Array.isArray(resources) && resources.every(resource => resource && key(resource.resource_key, 'pvr')) &&
      new Set(resources.map(resource => resource.resource_key)).size === resources.length,
      'stimulus_resources', 'The assigned material registry is invalid.');
    held = {binding: copied.binding, token: copied.accessToken, steps: new Map(view.steps.map(step => [step.step_key, step])),
      resources: new Map(resources.map(resource => [resource.resource_key, resource]))};
    return held;
  }
  function declarations() {
    if (!declaring) declaring = loadDeclarations();
    return declaring;
  }
  function specification(step, source) {
    need(step?.type === 'stimulus', 'stimulus_step', 'Prepare only an ordinary stimulus assigned to this study.');
    fields(step, ['step_key', 'type', 'phase', 'stimulus_key', 'duration_ms', 'material']);
    need(key(step.stimulus_key, 'pvi') && step.phase === 'passive_viewing' && integer(step.duration_ms, 100, 3600000),
      'stimulus_step', 'The original stimulus step is invalid.');
    const material = step.material;
    need(material && ['text', 'image', 'audio', 'video'].includes(material.type),
      'stimulus_type', 'This saved stimulus has no supported material profile.');
    if (material.type === 'text') {
      fields(material, ['type', 'content']);
      need(typeof material.content === 'string', 'stimulus_text', 'The saved text stimulus is invalid.');
      return {step, material, bytes: 0, resource: null};
    }
    fields(material, ['type', 'resource_key', ...(Object.hasOwn(material, 'image_alt') ? ['image_alt'] : [])]);
    need(key(material.resource_key, 'pvr') && (!Object.hasOwn(material, 'image_alt') || typeof material.image_alt === 'string'),
      'stimulus_resource', 'The saved stimulus has an invalid resource association.');
    const resource = source.resources.get(material.resource_key);
    need(resource, 'stimulus_unassigned', 'This material is not assigned to the original study.');
    const dimensions = ['width', 'height'].filter(name => Object.hasOwn(resource, name));
    fields(resource, ['resource_key', 'bytes', 'media_type', ...dimensions]);
    need(TYPES[material.type].includes(resource.media_type) && integer(resource.bytes, 1, MAX_BYTES) &&
      dimensions.every(name => integer(resource[name], 1, 2147483647)),
      'stimulus_profile', 'The saved material exceeds its supported delivery profile.');
    return {step, material, resource, bytes: resource.bytes};
  }
  async function bodyBlob(response, spec, signal) {
    try {
      need(response.status === 200 && !response.redirected && response.body &&
        response.headers.get('Content-Type')?.split(';')[0].trim().toLowerCase() === spec.resource.media_type,
        'stimulus_response', 'The assigned material could not be fetched intact.');
      const length = response.headers.get('Content-Length');
      need(length === null || /^[0-9]+$/.test(length) && Number(length) === spec.bytes,
        'stimulus_size', 'The assigned material has a different declared size.');
    } catch (error) {await response.body?.cancel().catch(() => {}); throw error;}
    const reader = response.body.getReader(), parts = []; let count = 0, complete = false;
    try {
      while (true) {
        const part = await reader.read(); active(signal);
        if (part.done) {complete = true; break;}
        need(part.value.byteLength <= spec.bytes - count, 'stimulus_size', 'The material exceeds its original declared size.');
        count += part.value.byteLength; parts.push(part.value);
      }
      need(count === spec.bytes, 'stimulus_size', 'The assigned material was not received completely.');
      return new win.Blob(parts, {type: spec.resource.media_type});
    } finally {if (!complete) await reader.cancel().catch(() => {}); reader.releaseLock();}
  }
  function readyImage(element, signal) {
    return new Promise((resolve, reject) => {
      let settled = false;
      const done = error => {if (settled) return; settled = true; signal.removeEventListener('abort', abort); error ? reject(error) : resolve();};
      const abort = () => done(fail('stimulus_aborted', 'Material preparation was stopped.'));
      signal.addEventListener('abort', abort, {once: true}); if (signal.aborted) {abort(); return;}
      element.decode().then(() => done(), () => done(fail('stimulus_decode', 'This browser could not decode the saved image.')));
    });
  }
  function readyMedia(element, signal) {
    return new Promise((resolve, reject) => {
      let settled = false;
      const done = error => {
        if (settled) return; settled = true;
        element.removeEventListener('canplaythrough', ready); element.removeEventListener('error', bad);
        signal.removeEventListener('abort', abort); error ? reject(error) : resolve();
      };
      const ready = () => {if (element.readyState >= 4) done();};
      const bad = () => done(fail('stimulus_decode', 'This browser could not prepare the saved media format.'));
      const abort = () => done(fail('stimulus_aborted', 'Material preparation was stopped.'));
      element.addEventListener('canplaythrough', ready); element.addEventListener('error', bad);
      signal.addEventListener('abort', abort, {once: true}); if (signal.aborted) {abort(); return;}
      element.load(); ready();
    });
  }
  function dispose(element, url) {
    if (element && ['AUDIO', 'VIDEO'].includes(element.tagName)) element.pause();
    element?.remove(); element?.removeAttribute('src');
    if (element && ['AUDIO', 'VIDEO'].includes(element.tagName)) element.load();
    if (url) win.URL.revokeObjectURL(url);
  }
  async function prepare(stepKey, request) {
    const signal = request.abort.signal; active(signal);
    const source = await declarations(); active(signal);
    const existing = prepared.get(stepKey); if (existing) return existing;
    const spec = specification(source.steps.get(stepKey), source);
    need(retainedBytes + spec.bytes <= MAX_BYTES, 'stimulus_capacity', 'This study exceeds the supported material preload size. Ask the researcher to reduce its media set.');
    retainedBytes += spec.bytes;
    let element = null, url = null, transferred = false, timedOut = false;
    const timer = win.setTimeout(() => {timedOut = true; request.abort.abort();}, PREPARE_MS);
    try {
      if (spec.material.type === 'text') {
        element = document.createElement('div'); element.className = 'assigned-stimulus-text'; element.textContent = spec.material.content;
      } else {
        const address = new URL(`/api/view/resources/${source.binding.run_id}/${spec.resource.resource_key}`, win.location.origin);
        const response = await fetchResource(address.href, {headers: {Authorization: `Bearer ${source.token}`, Accept: spec.resource.media_type},
          credentials: 'omit', cache: 'no-store', mode: 'same-origin', redirect: 'error', signal}); active(signal);
        const blob = await bodyBlob(response, spec, signal); active(signal);
        url = win.URL.createObjectURL(blob);
        element = document.createElement(spec.material.type === 'image' ? 'img' : spec.material.type);
        if (spec.material.type === 'image') {
          element.alt = spec.material.image_alt ?? 'Study image'; element.src = url;
          await readyImage(element, signal); active(signal);
          need(element.complete && element.naturalWidth > 0 && element.naturalHeight > 0 &&
            (!Object.hasOwn(spec.resource, 'width') || element.naturalWidth === spec.resource.width) &&
            (!Object.hasOwn(spec.resource, 'height') || element.naturalHeight === spec.resource.height),
            'stimulus_dimensions', 'The decoded image differs from its saved dimensions.');
        } else {
          need(element.canPlayType(spec.resource.media_type) !== '', 'stimulus_codec', 'This browser does not support the saved media format.');
          element.preload = 'auto'; element.playsInline = true; element.controls = false; element.autoplay = false; element.loop = false;
          element.src = url; await readyMedia(element, signal); active(signal);
          need(element.readyState >= 4 && !element.error, 'stimulus_decode', 'The saved media is not ready for presentation.');
          if (spec.material.type === 'video') need(element.videoWidth > 0 && element.videoHeight > 0 &&
            (!Object.hasOwn(spec.resource, 'width') || element.videoWidth === spec.resource.width) &&
            (!Object.hasOwn(spec.resource, 'height') || element.videoHeight === spec.resource.height),
            'stimulus_dimensions', 'The decoded video differs from its saved dimensions.');
        }
        need(element.src === url && (!('srcset' in element) || element.srcset === ''),
          'stimulus_source', 'The prepared element lost its assigned material source.');
      }
      let released = false;
      const handle = Object.freeze({step_key: stepKey, element, release() {
        if (released) return; released = true; handles.delete(handle); prepared.delete(stepKey);
        retainedBytes -= spec.bytes; dispose(element, url);
      }});
      prepared.set(stepKey, handle); handles.add(handle); transferred = true; return handle;
    } catch (error) {
      if (timedOut) throw fail('stimulus_timeout', 'Material preparation timed out before presentation. Retry the saved study materials.');
      if (closed || signal.aborted) throw fail('stimulus_aborted', 'Material preparation was stopped.');
      if (typeof error?.code === 'string' && error.code.startsWith('stimulus_')) throw error;
      throw fail('stimulus_network', 'The saved study material could not be prepared.');
    } finally {
      win.clearTimeout(timer);
      if (!transferred) {retainedBytes -= spec.bytes; dispose(element, url);}
    }
  }
  function prepareStep(stepKey, {signal} = {}) {
    need(!closed && key(stepKey, 'pvs'), 'stimulus_key', 'Use an assigned stimulus step while the study is open.');
    need(signal === undefined || signal instanceof win.AbortSignal, 'stimulus_signal', 'Use the material owner’s cancellation signal.');
    const request = {abort: new win.AbortController()}, abort = () => request.abort.abort();
    signal?.addEventListener('abort', abort, {once: true}); if (signal?.aborted) abort(); requests.add(request);
    const result = tail.then(() => prepare(stepKey, request)); tail = result.then(() => {}, () => {});
    return result.finally(() => {requests.delete(request); signal?.removeEventListener('abort', abort);});
  }
  async function prepareAll({signal} = {}) {
    need(signal === undefined || signal instanceof win.AbortSignal, 'stimulus_signal', 'Use the material owner’s cancellation signal.');
    active(signal); const source = await declarations(); active(signal);
    const specifications = Array.from(source.steps.values()).filter(step => step.type === 'stimulus').map(step => specification(step, source));
    need(specifications.reduce((sum, spec) => sum + spec.bytes, 0) <= MAX_BYTES,
      'stimulus_capacity', 'This study exceeds the supported material preload size. Ask the researcher to reduce its media set.');
    const result = [];
    for (const spec of specifications) {
      active(signal); const handle = await prepareStep(spec.step.step_key, {signal});
      active(signal); result.push(handle);
    }
    active(signal);
    return Object.freeze(result);
  }
  function close() {
    if (!closing) {
      closed = true; for (const request of requests) request.abort.abort();
      closing = tail.then(async () => {
        // prepareAll may be verifying the original declarations before it has
        // queued a step. Drain that verification too; it cannot install after close.
        if (declaring) await declaring.catch(() => {});
        for (const handle of Array.from(handles)) handle.release(); held = null;
      });
    }
    return closing;
  }
  return Object.freeze({prepareStep, prepareAll, close});
}
