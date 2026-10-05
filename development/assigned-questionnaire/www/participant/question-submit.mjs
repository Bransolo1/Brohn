/* Synchronous questionnaire observation and ordered handoff. The caller owns
 * current server state, durable storage, sequence allocation and reconciliation. */
const require = (ok, message) => { if (!ok) throw new TypeError(message); };
const object = value => value !== null && typeof value === 'object' &&
  (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
const text = (value, maximum = 128) => typeof value === 'string' && value.length > 0 && [...value].length <= maximum;
const key = (value, prefix) => typeof value === 'string' && value.length === 68 && new RegExp('^' + prefix + '-[a-f0-9]{64}$').test(value);
const integer = value => Number.isSafeInteger(value) && value >= 0 && value <= 10000000;
const decimal = value => typeof value === 'string' && value.length <= 64 && value.match(/^[0-9]+(\.[0-9]+)?$/)?.[0] === value && Number.isFinite(Number(value));
function validText(value) {
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    require(code !== 0, 'Submission text cannot contain NUL.');
    if (code >= 0xd800 && code <= 0xdbff) {
      const low = value.charCodeAt(++i);
      require(low >= 0xdc00 && low <= 0xdfff, 'Submission text has invalid Unicode.');
    } else require(code < 0xdc00 || code > 0xdfff, 'Submission text has invalid Unicode.');
  }
}

// Snapshot data only; accessors, prototypes and malformed text are never invoked
// or silently normalized. Preserve -0 and absent versus explicit null fields.
function snapshot(input) {
  const seen = new Set(); let nodes = 0;
  function copy(value, depth = 0) {
    require(++nodes <= 2000000 && depth < 64, 'Submission data exceeds its traversal limit.');
    if (value === null || typeof value === 'boolean') return value;
    if (typeof value === 'number') { require(Number.isFinite(value), 'Submission numbers must be finite.'); return value; }
    if (typeof value === 'string') {
      validText(value);
      return value;
    }
    const array = Array.isArray(value);
    require(array ? Object.getPrototypeOf(value) === Array.prototype : object(value), 'Submission data must be plain JSON.');
    require(!seen.has(value), 'Submission data cannot contain cycles.'); seen.add(value);
    const names = Reflect.ownKeys(value), result = array ? [] : {};
    if (array) require(names.length === value.length + 1 && names.includes('length'), 'Submission arrays must be dense.');
    for (const name of names) {
      if (array && name === 'length') continue;
      require(typeof name === 'string' && name.length > 0, 'Submission fields must be named JSON fields.');
      if (array) require(/^(0|[1-9][0-9]*)$/.test(name) && Number(name) < value.length, 'Submission array has an extra field.');
      const descriptor = Object.getOwnPropertyDescriptor(value, name);
      require(descriptor.enumerable && Object.hasOwn(descriptor, 'value'), 'Submission fields cannot be hidden or computed.');
      // Validate names without counting them as JSON value nodes.
      validText(name);
      Object.defineProperty(result, name, {value: copy(descriptor.value, depth + 1), enumerable: true});
    }
    seen.delete(value); return Object.freeze(result);
  }
  return copy(input);
}
function fields(value, expected, label) {
  require(object(value) && Object.keys(value).length === expected.length && expected.every(name => Object.hasOwn(value, name)), label + ' has unsupported fields.');
}

export function createQuestionnaireSubmitBridge({binding: supplied, order, observeClock, newEventId, writeObservation}) {
  require(order && ['reserve', 'fill', 'discard', 'retry'].every(name => typeof order[name] === 'function') &&
    [observeClock, newEventId, writeObservation].every(fn => typeof fn === 'function'), 'Question submission needs its shared order, clock and durable caller.');
  const binding = snapshot(supplied);
  fields(binding, ['view_hash', 'step_key', 'question_key', 'information', 'occurrence_key', 'phase', 'state_version', 'visit', 'record'], 'Question submission binding');
  require(typeof binding.view_hash === 'string' && binding.view_hash.length === 64 && /^[a-f0-9]{64}$/.test(binding.view_hash) && key(binding.step_key, 'pvs') && key(binding.question_key, 'pvq') &&
    key(binding.occurrence_key, 'pvo') && text(binding.phase, 64) && typeof binding.information === 'boolean' && integer(binding.state_version),
    'Question submission requires its exact assigned view and occurrence.');
  const visit = binding.visit, row = binding.record;
  fields(visit, ['id', 'step_key', 'instance_id', 'time_origin_ms', 'onset_ms', 'resumed', 'committed'], 'Question visit');
  require(text(visit.id) && visit.step_key === binding.step_key && text(visit.instance_id) && decimal(visit.time_origin_ms) &&
    decimal(visit.onset_ms) && Number(visit.onset_ms) <= 1e12 && typeof visit.resumed === 'boolean' && visit.committed === false,
    'Wait for an uncommitted received visit before submitting this question.');
  fields(row, ['step_key', 'occurrence_key', 'last_answer_event_id', 'dependency_generation'], 'Question record');
  require(row.step_key === binding.step_key && row.occurrence_key === binding.occurrence_key &&
    (row.last_answer_event_id === null || text(row.last_answer_event_id)) && integer(row.dependency_generation),
    'Question submission needs its exact saved answer generation.');
  const handles = new WeakMap(); let current = null, capturing = false;
  const locate = handle => {
    require(handle !== null && typeof handle === 'object' && handles.has(handle), 'Unknown question submission intent.');
    return handles.get(handle);
  };
  function observe(payload) {
    require(!capturing, 'Question submission capture cannot reenter.');
    capturing = true;
    try { return capture(payload); } finally { capturing = false; }
  }
  function capture(payload) {
    require(!current || current.phase === 'discarded', 'This received question visit already has a pending submission.');
    const value = snapshot(payload);
    fields(value, binding.information ? ['kind', 'step_key', 'question_key', 'draft_revision'] :
      ['kind', 'step_key', 'question_key', 'draft_revision', 'value'], 'Question completion');
    require(value.kind === (binding.information ? 'acknowledge' : 'answer') && value.step_key === binding.step_key &&
      value.question_key === binding.question_key && Number.isSafeInteger(value.draft_revision) && value.draft_revision >= 0,
      'Completion differs from this exact question.');
    // Called once during the valid synchronous submit intent, never after a draft
    // wait or retry. Decimal strings remain exact; duration uses the same binary64
    // subtraction as the original source revision handler.
    const clock = snapshot(observeClock());
    fields(clock, ['id', 'unit', 'value', 'instance_id', 'time_origin_ms'], 'Question observation clock');
    require(clock.id === 'browser-monotonic' && clock.unit === 'ms' && decimal(clock.value) && Number(clock.value) <= 1e12 &&
      clock.instance_id === visit.instance_id && clock.time_origin_ms === visit.time_origin_ms && Number(clock.value) >= Number(visit.onset_ms),
      'Resume this question before submitting from a changed or reversed page clock.');
    const id = newEventId(); require(text(id), 'Question submission requires a fresh event identity.');
    const elapsed = Number(clock.value) - Number(visit.onset_ms);
    const transition = {schema: 'participant-questionnaire-event/0.1', kind: binding.information ? 'acknowledge' : 'commit',
      occurrence_key: binding.occurrence_key, state_version: binding.state_version, visit_id: visit.id};
    if (!binding.information) Object.assign(transition, {previous_answer_event_id: row.last_answer_event_id,
      dependency_generation: row.dependency_generation, value: value.value,
      response_time_ms: row.last_answer_event_id === null && !visit.resumed ? elapsed : null,
      active_segment_response_ms: elapsed, resumed: visit.resumed});
    Object.assign(transition, {clock_segment_id: clock.instance_id, time_origin_ms: clock.time_origin_ms});
    const observation = snapshot({view_hash: binding.view_hash, event: {id, type: 'questionnaire_event',
      step_key: binding.step_key, phase: binding.phase, clock, payload: transition}});
    // All potentially refusing data construction precedes reserve. No thrown
    // validator can leave an unfilled queue position behind.
    const ticket = order.reserve(), handle = Object.freeze(Object.create(null));
    const item = {payload, observation, ticket, phase: 'captured', promise: null, write: null};
    item.write = () => writeObservation(item.observation);
    handles.set(handle, item); current = item; return handle;
  }
  function complete(payload, context) {
    require(context && Object.keys(context).length === 1 && Object.hasOwn(context, 'submitIntent'), 'Completion requires its original submit intent.');
    const item = locate(context.submitIntent);
    require(item.payload === payload && item.phase !== 'discarded', 'A captured submission cannot be replaced.');
    if (item.phase === 'writing' || item.phase === 'committed') return item.promise;
    const retry = item.phase === 'failed';
    require(retry || item.phase === 'captured', 'Question submission has an invalid lifecycle.');
    item.phase = 'writing';
    try { item.promise = retry ? order.retry(item.ticket) : order.fill(item.ticket, item.write); }
    catch (problem) { item.phase = retry ? 'failed' : 'captured'; throw problem; }
    item.promise.then(() => { item.phase = 'committed'; }, () => { item.phase = 'failed'; });
    return item.promise;
  }
  function discard(notice) {
    require(notice && Object.keys(notice).length === 2 && Object.hasOwn(notice, 'submitIntent') &&
      ['draft_failure', 'destroy'].includes(notice.reason), 'Use the exact pre-handoff discard notification.');
    const item = locate(notice.submitIntent);
    require(item.phase === 'captured', 'A handed-off question submission cannot be discarded.');
    order.discard(item.ticket); item.phase = 'discarded';
  }
  return Object.freeze({onSubmitIntent: observe, onDiscardSubmitIntent: discard, onComplete: complete});
}
