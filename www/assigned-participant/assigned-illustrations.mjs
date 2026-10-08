/* Assigned question images. Authority stays with each real resource request;
 * a prepared image grants no answer, navigation or collection permission. */
import {encodeParticipantRequest} from './request-bytes.mjs';
import {verifyParticipantJsonBytes} from './wire-json.mjs';
import {binding as admitBinding, same, fields, integer, key} from './current-structure.mjs';

const MAX_BYTES = 5 * 1024 ** 2, MAX_PIXELS = 8000000, ACTIVE_PIXELS = 64000000;
const fail = (code, message) => Object.assign(new Error(message), {code});
const need = (ok, code, message) => {if (!ok) throw fail(code, message);};

export function createAssignedIllustrations({binding, viewJson, accessToken, document = globalThis.document}) {
  need(document?.nodeType === 9 && document.defaultView, 'illustration_document', 'Use the participant document for study images.');
  // Snapshot before a queued request can wait or caller objects can change.
  need(typeof viewJson === 'string', 'illustration_view', 'Keep the original literal study presentation.');
  const literalView = viewJson;
  const input = encodeParticipantRequest({binding, accessToken}).then(value => ({value}), error => ({error}));
  let declarations = null, tail = Promise.resolve(), closed = false, closing = null, pixels = 0;
  const requests = new Set(), handles = new Set();
  const win = document.defaultView;
  const active = signal => need(!closed && !signal.aborted, 'illustration_aborted', 'Image preparation was stopped.');
  async function declared() {
    if (declarations) return declarations;
    const copied = await input; if (copied.error) throw copied.error;
    const value = JSON.parse(copied.value.json); admitBinding(value.binding);
    need(typeof value.accessToken === 'string' && value.accessToken.length === 64 && /^[a-f0-9]{64}$/.test(value.accessToken),
      'illustration_credential', 'The original saved study credential is required.');
    const view = (await verifyParticipantJsonBytes(literalView, {codec: value.binding.view_codec,
      bytes: value.binding.view_bytes, sha256: value.binding.view_hash})).value;
    need(view.schema === 'brohn-participant-view/0.1' && view.run_id === value.binding.run_id &&
      view.source_protocol_hash === value.binding.source_protocol_hash && same(view.renderer_identity, value.binding.renderer_identity),
      'illustration_view', 'The saved image registry belongs to another study presentation.');
    const resources = view.presentation?.resources;
    need(Array.isArray(resources) && resources.every(x => x && key(x.resource_key, 'pvr')) &&
      new Set(resources.map(x => x.resource_key)).size === resources.length,
      'illustration_registry', 'The assigned image registry is invalid.');
    declarations = {binding: value.binding, token: value.accessToken, resources: new Map(resources.map(x => [x.resource_key, x]))};
    return declarations;
  }
  function descriptor(value) {
    need(value, 'illustration_unassigned', 'This image is not assigned to the saved study.');
    fields(value, ['resource_key', 'bytes', 'media_type', 'width', 'height']);
    need(value.media_type === 'image/png' && integer(value.bytes, 33, MAX_BYTES) &&
      integer(value.width, 1, 4096) && integer(value.height, 1, 4096) && value.width * value.height <= MAX_PIXELS,
      'illustration_profile', 'This question image exceeds the supported PNG profile.');
    return value;
  }
  function png(bytes, spec) {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    need(bytes.length === spec.bytes && signature.every((x, i) => bytes[i] === x),
      'illustration_bytes', 'The assigned image bytes are incomplete or unsupported.');
    const header = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    need(header.getUint32(8) === 13 && [73, 72, 68, 82].every((x, i) => bytes[12 + i] === x) &&
      header.getUint32(16) === spec.width && header.getUint32(20) === spec.height,
      'illustration_dimensions', 'The assigned image differs from its saved dimensions.');
  }
  async function bytesFrom(response, spec, signal) {
    try {
      need(response.status === 200 && !response.redirected &&
        response.headers.get('content-type')?.split(';')[0].trim().toLowerCase() === 'image/png',
        'illustration_response', 'The assigned image could not be fetched intact.');
      const length = response.headers.get('content-length');
      need(length === null || /^[0-9]+$/.test(length) && Number(length) === spec.bytes,
        'illustration_size', 'The assigned image has a different declared size.');
      need(response.body, 'illustration_response', 'The assigned image response is empty.');
    } catch (error) {await response.body?.cancel().catch(() => {}); throw error;}
    const reader = response.body.getReader(), bytes = new Uint8Array(spec.bytes); let offset = 0, complete = false;
    try {
      while (true) {
        const part = await reader.read(); active(signal);
        if (part.done) {complete = true; break;}
        need(part.value.byteLength <= spec.bytes - offset, 'illustration_size', 'The image response exceeds its saved size.');
        bytes.set(part.value, offset); offset += part.value.byteLength;
      }
      need(offset === spec.bytes, 'illustration_size', 'The image response ended before all saved bytes arrived.');
      return bytes;
    } finally {
      if (!complete) await reader.cancel().catch(() => {});
      reader.releaseLock();
    }
  }
  function decoded(image, signal) {
    return new Promise((resolve, reject) => {
      let finished = false;
      const done = error => {
        if (finished) return; finished = true; signal.removeEventListener('abort', stop);
        error ? reject(error) : resolve();
      };
      const stop = () => done(fail('illustration_aborted', 'Image preparation was stopped.'));
      signal.addEventListener('abort', stop, {once: true});
      if (signal.aborted) {stop(); return;}
      image.decode().then(() => done(), () => done(fail('illustration_decode', 'The saved PNG could not be decoded.')));
    });
  }
  async function prepare(resourceKey, request) {
    const signal = request.controller.signal; active(signal);
    const held = await declared(); active(signal);
    const spec = descriptor(held.resources.get(resourceKey)), area = spec.width * spec.height;
    need(pixels + area <= ACTIVE_PIXELS, 'illustration_capacity', 'Release earlier question images before preparing more.');
    pixels += area;
    let url = null, image = null, transferred = false, timedOut = false;
    const timer = setTimeout(() => {timedOut = true; request.controller.abort();}, 60000);
    try {
      const address = `/api/view/resources/${held.binding.run_id}/${resourceKey}`;
      const response = await fetch(address, {headers: {Authorization: `Bearer ${held.token}`, Accept: 'image/png'},
        credentials: 'omit', cache: 'no-store', mode: 'same-origin', redirect: 'error', signal});
      active(signal);
      const bytes = await bytesFrom(response, spec, signal); active(signal); png(bytes, spec);
      url = win.URL.createObjectURL(new win.Blob([bytes], {type: 'image/png'}));
      image = document.createElement('img'); image.width = spec.width; image.height = spec.height; image.alt = '';
      image.src = url; await decoded(image, signal); active(signal);
      need(image.complete && image.naturalWidth === spec.width && image.naturalHeight === spec.height &&
        image.currentSrc === url && image.srcset === '', 'illustration_decode', 'The decoded image differs from its saved dimensions.');
      let released = false;
      const handle = Object.freeze({resource_key: resourceKey, image, release() {
        if (released) return; released = true; handles.delete(handle);
        image.remove(); image.removeAttribute('src'); win.URL.revokeObjectURL(url); pixels -= area;
      }});
      handles.add(handle); transferred = true; return handle;
    } catch (error) {
      if (timedOut) throw fail('illustration_timeout', 'Image preparation timed out. Retry the saved illustration.');
      if (closed || signal.aborted) throw fail('illustration_aborted', 'Image preparation was stopped.');
      if (typeof error?.code === 'string' && error.code.startsWith('illustration_')) throw error;
      throw fail('illustration_network', 'The image could not be prepared. Retry the saved illustration.');
    } finally {
      clearTimeout(timer);
      if (!transferred) {image?.removeAttribute('src'); if (url) win.URL.revokeObjectURL(url); pixels -= area;}
    }
  }
  function prepareIllustration(resourceKey, {signal} = {}) {
    need(!closed && key(resourceKey, 'pvr'), 'illustration_key', 'Use an assigned image key while this study is open.');
    need(signal === undefined || signal instanceof AbortSignal, 'illustration_signal', 'Use the image owner’s cancellation signal.');
    const request = {controller: new AbortController()};
    const stop = () => request.controller.abort(); signal?.addEventListener('abort', stop, {once: true});
    if (signal?.aborted) stop(); requests.add(request);
    const result = tail.then(() => prepare(resourceKey, request));
    tail = result.then(() => {}, () => {});
    return result.finally(() => {requests.delete(request); signal?.removeEventListener('abort', stop);});
  }
  function close() {
    if (!closing) {
      closed = true; for (const request of requests) request.controller.abort();
      closing = tail.then(() => {for (const handle of Array.from(handles)) handle.release(); declarations = null;});
    }
    return closing;
  }
  return Object.freeze({prepareIllustration, close});
}
