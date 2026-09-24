/* Pure journal envelope selection. No storage, network, acknowledgement or data deletion. */
(() => {
  'use strict';
  const MAX_BYTES = 4 * 1024 * 1024, MAX_EVENTS = 100;
  const utf8 = new TextEncoder();
  function refuse(code, message, details = {}) {
    const error = new Error(`${message} Your local responses have been retained.`);
    Object.assign(error, {code, permanent: true, retained: true}, details);
    throw error;
  }
  const integer = (n, minimum = 0) => Number.isSafeInteger(n) && n >= minimum;
  function encode(event) {
    try {
      return JSON.stringify(event, (_key, value) => {
        if (value === undefined || typeof value === 'function' || typeof value === 'symbol' ||
            typeof value === 'bigint' || typeof value === 'number' && !Number.isFinite(value)) {
          throw new Error('The event contains a value that cannot be sent without changing it.');
        }
        return value;
      });
    } catch (_) {
      refuse('event_not_json', 'A saved event cannot be represented as complete JSON.');
    }
  }
  function select({events, ackedSequence, operationId, batch = null, maxBytes = MAX_BYTES, preferredBytes = maxBytes} = {}) {
    if (!Array.isArray(events) || !integer(ackedSequence))
      refuse('event_journal_invalid', 'The saved event journal or acknowledgement is inconsistent.');
    if (!integer(maxBytes, 1) || maxBytes > MAX_BYTES)
      refuse('event_limit_invalid', 'The event envelope limit must be an integer from 1 through 4 MiB.');
    if (!integer(preferredBytes, 1) || preferredBytes > maxBytes)
      refuse('event_preference_invalid', 'The preferred envelope size must be an integer from 1 through the hard limit.');
    let previous = 0, start = events.length;
    for (let i = 0; i < events.length; i++) {
      const event = events[i];
      if (!event || typeof event !== 'object' || Array.isArray(event) || !integer(event.sequence, 1) || event.sequence <= previous)
        refuse('event_sequence_invalid', 'Saved events are missing their original ascending sequence.');
      previous = event.sequence;
      if (start === events.length && event.sequence > ackedSequence) start = i;
    }
    const reused = batch !== null;
    if (!reused && start === events.length) return null;
    if (reused) {
      if (!batch || typeof batch !== 'object' || Array.isArray(batch) ||
          Object.keys(batch).sort().join(',') !== 'first,last,operation_id' ||
          !integer(batch.first, 1) || !integer(batch.last, batch.first) ||
          batch.last - batch.first + 1 > MAX_EVENTS || batch.first !== ackedSequence + 1)
        refuse('persisted_batch_invalid', 'The saved delivery operation or its exact sequence bounds need reconciliation.');
      operationId = batch.operation_id;
    }
    if (typeof operationId !== 'string' || !operationId.trim() || operationId.length > 128)
      refuse('event_operation_invalid', 'The saved delivery operation identity is unavailable.');
    // A reduced new-batch budget never rewrites or shrinks a persisted operation.
    const limit = reused ? MAX_BYTES : maxBytes;
    const prefix = `{"operation_id":${JSON.stringify(operationId)},"events":[`, suffix = ']}';
    let bytes = utf8.encode(prefix + suffix).byteLength;
    const encoded = [];
    const count = reused ? batch.last - batch.first + 1 : Math.min(MAX_EVENTS, events.length - start);
    for (let i = 0; i < count; i++) {
      const event = events[start + i], expected = ackedSequence + i + 1;
      if (!event || event.sequence !== expected)
        refuse('event_sequence_gap', 'A complete contiguous delivery operation cannot be reconstructed from the saved journal.', {sequence: expected});
      const json = encode(event), next = bytes + (i ? 1 : 0) + utf8.encode(json).byteLength;
      if (next > limit) {
        if (reused) refuse('persisted_batch_oversize',
          'The previously saved delivery operation exceeds the receiver limit. Its receipt must be reconciled before changing or splitting it.',
          {operation_id: operationId, first: batch.first, last: batch.last, maximum_bytes: limit});
        if (!i) refuse('single_event_oversize',
          'One complete saved event exceeds the configured upload limit and cannot be sent within it without changing the event. Contact the researcher for recovery.',
          {sequence: event.sequence, bytes: next, maximum_bytes: limit});
        break;
      }
      // A preference never refuses or cuts an indivisible first event.
      if (!reused && i && next > preferredBytes) break;
      encoded.push(json); bytes = next;
      if (!reused && bytes > preferredBytes) break;
    }
    const json = prefix + encoded.join(',') + suffix;
    // A detached JSON payload prevents callers from mutating the original journal.
    const payload = JSON.parse(json);
    const selected = {operation_id: operationId, first: payload.events[0].sequence, last: payload.events.at(-1).sequence};
    return {batch: selected, payload, json, bytes, reused};
  }
  globalThis.BrohnEventBatch = Object.freeze({select, MAX_BYTES, MAX_EVENTS});
})();
