/* Inactive request encoder. Persist the returned immutable JSON string once;
 * retry those exact bytes. This is not the server view codec or an authority. */
export const PARTICIPANT_REQUEST_CODEC = 'brohn-participant-request-json/0.1';
const MAX_BYTES = 4 * 1024 * 1024;
const MAX_NODES = 2000000;
const own = (value, name) => Object.prototype.hasOwnProperty.call(value, name);
const require = (ok, message) => { if (!ok) throw new TypeError(message); };

function utf8Length(text, maximum) {
  let bytes = 0;
  for (let i = 0; i < text.length; i++) {
    const unit = text.charCodeAt(i);
    require(unit !== 0, 'Request text cannot contain an embedded NUL character.');
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const low = text.charCodeAt(++i);
      require(low >= 0xdc00 && low <= 0xdfff, 'Request text has an unpaired surrogate.');
      bytes += 4;
    } else {
      require(unit < 0xdc00 || unit > 0xdfff, 'Request text has an unpaired surrogate.');
      bytes += unit < 0x80 ? 1 : unit < 0x800 ? 2 : 3;
    }
    require(bytes <= maximum, 'The complete request exceeds its byte limit.');
  }
  return bytes;
}

function properties(value, array) {
  const keys = Reflect.ownKeys(value);
  if (array) require(keys.length === value.length + 1 && keys.every((key, i) =>
    i === value.length ? key === 'length' : key === String(i)), 'Request arrays must be dense and contain no extra fields.');
  const rows = [];
  for (const key of keys) {
    if (array && key === 'length') continue;
    const d = Object.getOwnPropertyDescriptor(value, key);
    require(typeof key === 'string' && key.length > 0 && d && d.enumerable && own(d, 'value'),
      'Request fields must be nonempty enumerable data properties.');
    rows.push([key, d.value]);
  }
  return rows;
}

export async function encodeParticipantRequest(value, limits = {}) {
  require(limits && !Array.isArray(limits) && [Object.prototype, null].includes(Object.getPrototypeOf(limits)), 'Request limits must be plain.');
  const options = properties(limits, false);
  require(options.every(([key]) => ['maximumBytes', 'maximumNodes'].includes(key)), 'Unknown request encoding limit.');
  const names = Object.fromEntries(options);
  const maximumBytes = own(names, 'maximumBytes') ? names.maximumBytes : MAX_BYTES;
  const maximumNodes = own(names, 'maximumNodes') ? names.maximumNodes : MAX_NODES;
  require(Number.isSafeInteger(maximumBytes) && maximumBytes >= 1 && maximumBytes <= MAX_BYTES &&
    Number.isSafeInteger(maximumNodes) && maximumNodes >= 1 && maximumNodes <= MAX_NODES, 'Invalid request encoding limit.');
  let bytes = 0, nodes = 0;
  const chunks = [], ancestors = new Set();
  const emit = text => {
    bytes += utf8Length(text, maximumBytes - bytes);
    require(bytes <= maximumBytes, 'The complete request exceeds its byte limit.');
    chunks.push(text);
  };
  const string = text => {
    // Inspect original text before JSON.stringify can escape invalid surrogates.
    utf8Length(text, maximumBytes - bytes);
    emit(JSON.stringify(text));
  };
  const visit = (item, depth) => {
    require(depth < 64 && ++nodes <= maximumNodes, 'The request exceeds its traversal limit.');
    if (item === null) { emit('null'); return; }
    if (typeof item === 'boolean') { emit(item ? 'true' : 'false'); return; }
    if (typeof item === 'string') { string(item); return; }
    if (typeof item === 'number') {
      require(Number.isFinite(item), 'Request observations must be finite numbers.');
      // ECMAScript's finite number spelling roundtrips binary64. Its ordinary
      // JSON zero spelling would erase the sign, so preserve that case explicitly.
      emit(Object.is(item, -0) ? '-0.0' : String(item)); return;
    }
    require(item !== null && typeof item === 'object', 'The request contains a non-JSON value.');
    const array = Array.isArray(item), prototype = Object.getPrototypeOf(item);
    require(array ? prototype === Array.prototype : [Object.prototype, null].includes(prototype), 'Request values must be plain JSON containers.');
    require(!ancestors.has(item), 'The request contains a cycle.');
    ancestors.add(item);
    const rows = properties(item, array);
    emit(array ? '[' : '{');
    for (let i = 0; i < rows.length; i++) {
      if (i) emit(',');
      if (!array) { string(rows[i][0]); emit(':'); }
      visit(rows[i][1], depth + 1);
    }
    emit(array ? ']' : '}'); ancestors.delete(item);
  };
  // Complete the synchronous snapshot before yielding to WebCrypto. Subsequent
  // mutations to caller objects cannot alter this request or its retry bytes.
  visit(value, 0);
  const json = chunks.join(''), raw = new TextEncoder().encode(json);
  require(raw.byteLength === bytes, 'Request UTF-8 byte accounting differs.');
  require(globalThis.crypto?.subtle, 'WebCrypto is required to bind queued request bytes.');
  const digest = new Uint8Array(await globalThis.crypto.subtle.digest('SHA-256', raw));
  const sha256 = Array.from(digest, byte => byte.toString(16).padStart(2, '0')).join('');
  return Object.freeze({codec: PARTICIPANT_REQUEST_CODEC, json, bytes, sha256});
}
