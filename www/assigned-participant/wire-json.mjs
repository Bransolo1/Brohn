/* Inactive generic byte verifier. No run/source authentication or view schema. */
export const PARTICIPANT_JSON_CODEC = "brohn-participant-json-bytes/0.1";
const BYTE_LIMIT = 16 * 1024 * 1024;
const NODE_LIMIT = 2000000;
const fail = message => { throw new Error(message); };
const require = (condition, message) => { if (!condition) fail(message); };

function record(value, keys, label) {
  require(value !== null && typeof value === "object" && !Array.isArray(value) &&
    [Object.prototype, null].includes(Object.getPrototypeOf(value)), `${label} must be a plain object.`);
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const own = Reflect.ownKeys(descriptors);
  require(own.length === keys.length && keys.every(key => own.includes(key)) &&
    own.every(key => typeof key === "string" && Object.hasOwn(descriptors[key], "value")), `${label} has unsupported fields or accessors.`);
  return Object.fromEntries(keys.map(key => [key, descriptors[key].value]));
}

// TextEncoder silently replaces isolated UTF-16 surrogates. Reject them first,
// and count bytes before allocating the UTF-8 result. No Unicode normalization.
function utf8Length(text, maximum = BYTE_LIMIT) {
  require(typeof text === "string", "Participant JSON text must be a string.");
  let bytes = 0;
  for (let i = 0; i < text.length; i++) {
    const unit = text.charCodeAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const low = text.charCodeAt(++i);
      require(low >= 0xdc00 && low <= 0xdfff, "Participant JSON contains an unpaired surrogate.");
      bytes += 4;
    } else {
      require(unit < 0xdc00 || unit > 0xdfff, "Participant JSON contains an unpaired surrogate.");
      bytes += unit < 0x80 ? 1 : unit < 0x800 ? 2 : 3;
    }
    require(bytes <= maximum, "Participant JSON exceeds its byte limit.");
  }
  return bytes;
}

function scanJson(text, maximumNodes) {
  let at = 0, nodes = 0;
  const white = () => { while (at < text.length && " \t\r\n".includes(text[at])) at++; };
  const string = keep => {
    require(text[at++] === '"', "Participant JSON string was expected.");
    let decoded = "", start = at, high = false;
    const unit = code => {
      if (high) { require(code >= 0xdc00 && code <= 0xdfff, "Participant JSON string has an unpaired surrogate."); high = false; }
      else if (code >= 0xd800 && code <= 0xdbff) high = true;
      else require(code < 0xdc00 || code > 0xdfff, "Participant JSON string has an unpaired surrogate.");
    };
    while (at < text.length) {
      const index = at, code = text.charCodeAt(at++);
      if (code === 0x22) {
        require(!high, "Participant JSON string has an unpaired surrogate.");
        if (keep) decoded += text.slice(start, index);
        return decoded;
      }
      require(code >= 0x20, "Participant JSON string contains a raw control character.");
      if (code !== 0x5c) { unit(code); continue; }
      if (keep) decoded += text.slice(start, index);
      const escape = text[at++]; let value;
      if (escape === "u") {
        const digits = text.slice(at, at + 4);
        require(/^[0-9a-fA-F]{4}$/.test(digits), "Participant JSON has an invalid Unicode escape.");
        value = parseInt(digits, 16); at += 4;
      } else {
        const escapes = {'"': 0x22, "\\": 0x5c, "/": 0x2f, b: 8, f: 12, n: 10, r: 13, t: 9};
        require(Object.hasOwn(escapes, escape), "Participant JSON has an invalid escape.");
        value = escapes[escape];
      }
      unit(value);
      if (keep) decoded += String.fromCharCode(value);
      start = at;
    }
    fail("Participant JSON string is unterminated.");
  };
  const number = /-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/y;
  const value = depth => {
    require(depth < 64 && ++nodes <= maximumNodes, "Participant JSON exceeds its traversal limit.");
    white(); const token = text[at];
    if (token === '"') { string(false); return; }
    if (token === "{" || token === "[") {
      const object = token === "{", close = object ? "}" : "]", names = new Set(); at++; white();
      if (text[at] === close) { at++; return; }
      while (true) {
        if (object) {
          white(); const key = string(true);
          require(key.length > 0 && !names.has(key), "Participant JSON object keys must be nonempty and unique.");
          names.add(key); white(); require(text[at++] === ":", "Participant JSON object needs a colon.");
        }
        value(depth + 1); white();
        if (text[at] === close) { at++; return; }
        require(text[at++] === ",", "Participant JSON container needs a comma or closing delimiter.");
      }
    }
    for (const literal of ["true", "false", "null"]) {
      if (text.startsWith(literal, at)) { at += literal.length; return; }
    }
    number.lastIndex = at;
    const numeric = number.exec(text);
    require(numeric !== null, "Participant JSON has an invalid value or number.");
    at = number.lastIndex;
  };
  value(0); white(); require(at === text.length, "Participant JSON has trailing or malformed input.");
  return nodes;
}

function validateParsed(value, maximumNodes) {
  let nodes = 0;
  const visit = (item, depth) => {
    require(depth < 64 && ++nodes <= maximumNodes, "Parsed participant JSON exceeds its traversal limit.");
    if (item === null || typeof item === "boolean") return;
    if (typeof item === "string") { utf8Length(item); return; }
    if (typeof item === "number") { require(Number.isFinite(item), "Parsed participant JSON number must be finite."); return; }
    require(item && typeof item === "object", "Parsed participant JSON is outside the plain domain.");
    const array = Array.isArray(item);
    require(Object.getPrototypeOf(item) === (array ? Array.prototype : Object.prototype), "Parsed participant JSON is not plain.");
    for (const key of Object.keys(item)) {
      if (!array) { require(key.length > 0, "Parsed participant JSON object key is empty."); utf8Length(key); }
      visit(item[key], depth + 1);
    }
  };
  visit(value, 0); return nodes;
}

export async function verifyParticipantJsonBytes(view_json, suppliedBinding, suppliedLimits = {}) {
  const binding = record(suppliedBinding, ["codec", "bytes", "sha256"], "Participant JSON byte binding");
  const limitNames = Object.keys(suppliedLimits);
  require(limitNames.every(key => ["maximumBytes", "maximumNodes"].includes(key)), "Unsupported participant JSON limit.");
  const limits = record(suppliedLimits, limitNames, "Participant JSON limits");
  const maximumBytes = Object.hasOwn(limits, "maximumBytes") ? limits.maximumBytes : BYTE_LIMIT;
  const maximumNodes = Object.hasOwn(limits, "maximumNodes") ? limits.maximumNodes : NODE_LIMIT;
  require(Number.isSafeInteger(maximumBytes) && maximumBytes >= 1 && maximumBytes <= BYTE_LIMIT &&
    Number.isSafeInteger(maximumNodes) && maximumNodes >= 1 && maximumNodes <= NODE_LIMIT, "Invalid participant JSON admission limit.");
  require(binding.codec === PARTICIPANT_JSON_CODEC && Number.isSafeInteger(binding.bytes) && binding.bytes >= 1 && binding.bytes <= maximumBytes &&
    typeof binding.sha256 === "string" && /^[a-f0-9]{64}$/.test(binding.sha256) && binding.sha256.length === 64, "Invalid participant JSON byte binding.");
  require(utf8Length(view_json, maximumBytes) === binding.bytes, "Participant JSON byte length differs.");
  const bytes = new TextEncoder().encode(view_json);
  require(bytes.byteLength === binding.bytes, "Participant JSON encoder length differs.");
  require(globalThis.crypto?.subtle, "WebCrypto is required to verify participant JSON.");
  const digest = new Uint8Array(await globalThis.crypto.subtle.digest("SHA-256", bytes));
  const sha256 = Array.from(digest, byte => byte.toString(16).padStart(2, "0")).join("");
  require(sha256 === binding.sha256, "Participant JSON SHA-256 differs.");
  const nodes = scanJson(view_json, maximumNodes);
  const value = JSON.parse(view_json); // Exactly one whole-document parse, after byte/hash and structural checks.
  require(validateParsed(value, maximumNodes) === nodes, "Participant JSON node accounting differs.");
  return {codec: binding.codec, bytes: binding.bytes, sha256, value};
}
