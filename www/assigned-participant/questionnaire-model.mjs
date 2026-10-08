/* Inactive public-key questionnaire model. Literal document identity and local
 * association checks do not authenticate a response or authorize an action. */
import {verifyParticipantJsonBytes, PARTICIPANT_JSON_CODEC} from './wire-json.mjs';
import {encodeParticipantRequest, PARTICIPANT_REQUEST_CODEC} from './request-bytes.mjs';
import {binding as bindingShape, packet as packetShape, fields, same, noNul, freeze, integer, hash, key, text} from './packet-structure.mjs';
import {questionShape, ruleShape, answerShape} from './question-domain.mjs';

const PAGE_BYTES = 3 * 1024 * 1024, MODEL_BYTES = 64 * 1024 * 1024;
function need(ok, message, code = 'questionnaire_model') {
  if (!ok) throw Object.assign(new Error(message), {code});
}
function ownData(value, names) {
  need(value && typeof value === 'object' && !Array.isArray(value) && [Object.prototype, null].includes(Object.getPrototypeOf(value)), 'Expected a plain document descriptor.');
  const keys = Reflect.ownKeys(value);
  need(keys.length === names.length && keys.every(k => typeof k === 'string' && names.includes(k)), 'Unsupported descriptor fields.');
  const out = {};
  for (const name of names) {
    const d = Object.getOwnPropertyDescriptor(value, name);
    need(d && d.enumerable && Object.hasOwn(d, 'value'), 'Descriptors require data properties.');
    Object.defineProperty(out, name, {value: d.value, enumerable: true});
  }
  return out;
}
function document(input, max) {
  const d = ownData(input, ['codec', 'json', 'bytes', 'sha256']);
  need(d.codec === PARTICIPANT_JSON_CODEC && typeof d.json === 'string' && d.json.length <= max && integer(d.bytes, 1, max) && hash(d.sha256), 'Invalid literal questionnaire document.');
  return Object.freeze(d);
}
async function admit(d, max) {
  const result = await verifyParticipantJsonBytes(d.json, {codec: d.codec, bytes: d.bytes, sha256: d.sha256}, {maximumBytes: max});
  noNul(result.value); return result.value;
}
const decimal = x => text(x, 64) && /^[0-9]+([.][0-9]+)?$/.exec(x)?.[0] === x && Number.isFinite(Number(x));
function visit(v) {
  if (v === null) return;
  need(decimal(v.time_origin_ms) && decimal(v.onset_ms) && Number(v.onset_ms) <= 1e12, 'The received visit must keep its complete finite decimal clock.');
}
function clock(c) {
  fields(c, ['id', 'unit', 'value', 'instance_id', 'time_origin_ms']);
  need(c.id === 'browser-monotonic' && c.unit === 'ms' && text(c.instance_id, 128) && decimal(c.value) && decimal(c.time_origin_ms) &&
    Number(c.value) <= 1e12, 'Keep the exact original page clock.');
}
function closed(x, required, optional = []) {
  need(x && typeof x === 'object' && !Array.isArray(x) && required.every(k => Object.hasOwn(x, k)) &&
    Object.keys(x).every(k => required.includes(k) || optional.includes(k)), 'Unsupported public presentation fields.');
}
function viewIndex(view, held) {
  fields(view, ['schema', 'run_id', 'source_protocol_hash', 'renderer_identity', 'presentation', 'steps']);
  need(view.schema === 'brohn-participant-view/0.1' && view.run_id === held.run_id && view.source_protocol_hash === held.source_protocol_hash &&
    same(view.renderer_identity, held.renderer_identity), 'The view belongs to another original run or implementation.');
  fields(view.presentation, ['title', 'appearance', 'consent', 'debrief', 'navigation', 'equipment', 'camera', 'resources']);
  const navigation = view.presentation.navigation;
  fields(navigation, ['schema', 'occurrences']);
  need(navigation.schema === 'participant-navigation/0.1' && Array.isArray(navigation.occurrences) && navigation.occurrences.length <= 20000 &&
    Array.isArray(view.steps) && view.steps.length <= 20000, 'A supported assigned questionnaire navigation manifest is required.');
  const steps = new Map(), occurrences = new Map(), questions = new Map(), scopeQuestions = new Map();
  const resources = new Set();
  need(Array.isArray(view.presentation.resources), 'Missing public resource registry.');
  for (const r of view.presentation.resources) {
    closed(r, ['resource_key', 'bytes', 'media_type'], ['width', 'height']);
    need(key(r.resource_key, 'pvr') && !resources.has(r.resource_key) && integer(r.bytes, 1, 512 * 1024 * 1024) && text(r.media_type, 120), 'Invalid or duplicate public resource.');
    for (const name of ['width', 'height']) if (Object.hasOwn(r, name)) need(integer(r[name], 1, 2147483647), 'Invalid public resource dimension.');
    resources.add(r.resource_key);
  }
  for (const s of view.steps) {
    const base = ['step_key', 'type', 'phase'];
    need(key(s.step_key, 'pvs') && !steps.has(s.step_key) && text(s.phase, 96), 'Duplicate or invalid public step.');
    if (s.type === 'question') {
      closed(s, [...base, 'stimulus_key', 'occurrence_key', 'question', 'question_key'], ['section_label']);
      questionShape(s.question);
      need(s.question_key === s.question.question_key && key(s.stimulus_key, 'pvi', true) && key(s.occurrence_key, 'pvo'), 'Question step associations differ.');
      if (Object.hasOwn(s, 'section_label')) need(text(s.section_label, 2000), 'Invalid questionnaire section label.');
      const prior = questions.get(s.question_key);
      need(!prior || same(prior, s.question), 'Repeated question key has different content.');
      questions.set(s.question_key, s.question);
      if (s.question.illustration) need(resources.has(s.question.illustration.resource_key), 'Question illustration is outside the assigned resource registry.');
    } else if (s.type === 'questionnaire_review') {
      fields(s, [...base, 'stimulus_key', 'occurrence_key']);
      need(key(s.stimulus_key, 'pvi', true) && key(s.occurrence_key, 'pvo'), 'Review associations are invalid.');
    } else {
      const extras = {instructions: ['text'], baseline: ['stimulus_key', 'duration_ms'], fixation: ['stimulus_key', 'duration_ms'],
        stimulus: ['stimulus_key', 'duration_ms', 'material'], maxdiff: ['choice'], task: ['task']}[s.type];
      need(extras, 'Unknown assigned step type.'); fields(s, [...base, ...extras]);
      // Other renderers own their exact material/task/choice profile admission.
      // This model uses only their original positions and public step identities.
    }
    steps.set(s.step_key, s);
  }
  need(questions.size <= 200, 'The assigned view exceeds the original design question limit.');
  const claimed = new Set(), tokenOwners = new Set();
  for (const q of questions.values()) {
    for (const k of [q.question_key, ...(q.options || []).map(o => o.option_key), ...(q.rows || []).map(r => r.row_key)]) {
      need(!tokenOwners.has(k), 'Distinct questions reuse a question/option/row key.'); tokenOwners.add(k);
    }
    if (!scopeQuestions.has(q.scope)) scopeQuestions.set(q.scope, new Map());
    scopeQuestions.get(q.scope).set(q.question_key, q);
  }
  for (const q of questions.values()) {
    // Source rules in after_each/end may also depend on a before answer. Public
    // presentation order is not authored rule order (sections may randomize).
    const allowed = new Map(scopeQuestions.get('before') || []);
    for (const [k, v] of scopeQuestions.get(q.scope) || []) allowed.set(k, v);
    ruleShape(q.rule, allowed);
  }
  for (const o of navigation.occurrences) {
    fields(o, ['occurrence_key', 'scope', 'stimulus_step_key', 'question_step_keys', 'review_step_key']);
    need(key(o.occurrence_key, 'pvo') && !occurrences.has(o.occurrence_key) && ['before', 'after_each', 'end'].includes(o.scope) &&
      Array.isArray(o.question_step_keys) && o.question_step_keys.length <= 200 && new Set(o.question_step_keys).size === o.question_step_keys.length,
    'Invalid or duplicate questionnaire occurrence.');
    const stimulus = o.stimulus_step_key === null ? null : steps.get(o.stimulus_step_key);
    need(o.scope === 'after_each' ? stimulus?.type === 'stimulus' : o.stimulus_step_key === null, 'Occurrence stimulus anchor differs.');
    const stimulusKey = stimulus?.stimulus_key ?? null, memberQuestions = new Set();
    for (const sid of [...o.question_step_keys, o.review_step_key]) {
      const s = steps.get(sid);
      need(s && !claimed.has(sid) && s.occurrence_key === o.occurrence_key && s.stimulus_key === stimulusKey, 'An occurrence crosses an assigned step or stimulus boundary.');
      if (sid === o.review_step_key) need(s.type === 'questionnaire_review', 'Occurrence review key is not a review step.');
      else {
        need(s.type === 'question' && s.question.scope === o.scope && !memberQuestions.has(s.question_key), 'Occurrence repeats or mis-scopes a question.');
        memberQuestions.add(s.question_key);
      }
      claimed.add(sid);
    }
    occurrences.set(o.occurrence_key, o);
  }
  for (const s of steps.values()) if (['question', 'questionnaire_review'].includes(s.type)) need(claimed.has(s.step_key), 'Question/review has no exact occurrence membership.');
  return {steps, occurrences, questions};
}
function packetAssociations(p, held, view, index, ack) {
  packetShape(p, held, ack);
  need(p.cursor <= view.steps.length + 1 && p.next_step_key === (view.steps[p.cursor - 1]?.step_key ?? null), 'Packet cursor differs from the original assigned step order.');
  const l = p.latest_occurrence, a = p.actions, q = p.resume_page;
  if (l === null) need(a.enter_step_key === null && a.next_step_key === null && a.back_step_key === null && !a.editable_step_keys.length && !a.can_seal &&
    q.active_occurrence_key === null, 'An absent occurrence cannot expose an active visit or actions.');
  else {
    const o = index.occurrences.get(l.occurrence_key);
    need(o && l.review_step_key === o.review_step_key, 'Latest occurrence differs from the view.');
    const member = k => k === o.review_step_key || o.question_step_keys.includes(k);
    for (const k of [a.enter_step_key, a.next_step_key, a.back_step_key]) need(k === null || member(k), 'An action crosses its occurrence.');
    need(a.editable_step_keys.every(k => o.question_step_keys.includes(k)), 'An edit action targets a non-question or foreign occurrence.');
    visit(l.visit);
    if (l.visit !== null) need(member(l.visit.step_key), 'Received visit crosses its occurrence.');
    if (l.sealed) need(a.enter_step_key === null && a.next_step_key === null && a.back_step_key === null && !a.editable_step_keys.length && !a.can_seal, 'A sealed occurrence cannot expose editing.');
    need(!a.can_seal || !l.sealed && l.visit?.step_key === o.review_step_key, 'Only the current review can offer sealing.');
    need(a.enter_step_key === null || l.visit === null, 'An existing visit cannot offer another enter action.');
    need(a.next_step_key === null || l.visit?.committed === true && l.visit.step_key !== o.review_step_key, 'Only a committed question visit can offer next.');
    need(!a.editable_step_keys.length || l.visit?.step_key === o.review_step_key, 'Edit actions require the received review visit.');
    if (q.active_occurrence_key !== null) need(q.active_occurrence_key === l.occurrence_key && !l.sealed && q.state_version === l.state_version && same(q.visit, l.visit), 'Active resume and latest occurrence disagree.');
    else need(l.visit === null || l.sealed, 'A received unsealed visit has no active resume.');
  }
  visit(q.visit);
  if (q.active_occurrence_key !== null) {
    const o = index.occurrences.get(q.active_occurrence_key);
    need(o && q.visible_step_keys.every(k => o.question_step_keys.includes(k)), 'Visible questions cross the active occurrence.');
  }
  if (p.last_transition !== null) need(index.occurrences.has(p.last_transition.occurrence_key), 'Transition belongs to another view.');
  for (const r of q.records) {
    const s = index.steps.get(r.step_key), o = index.occurrences.get(r.occurrence_key);
    need(s?.type === 'question' && o && s.occurrence_key === r.occurrence_key && s.question_key === r.question_key &&
      s.stimulus_key === r.stimulus_key && s.question.scope === r.scope && r.information === (s.question.type === 'information'), 'Recovered answer differs from its exact public question association.');
    answerShape(s.question, r.value);
  }
}
const packetHeader = p => { const {resume_page, ...header} = p; return header; };
const resumeHeader = p => { const {records, offset, next_offset, ...header} = p; return header; };

export async function admitParticipantQuestionnaireModel(input) {
  const args = ownData(input, ['binding', 'viewDocument', 'packetDocuments', 'currentGeneration', 'acknowledgedSequence', 'maximumPacketBytes']);
  need(integer(args.currentGeneration, 1) && integer(args.acknowledgedSequence) && integer(args.maximumPacketBytes, 1, MODEL_BYTES), 'Invalid current generation, ACK or encoded-packet budget.');
  const heldCapture = encodeParticipantRequest(args.binding); heldCapture.catch(() => {});
  const viewDocument = document(args.viewDocument, 16 * 1024 * 1024);
  const sourcePages = args.packetDocuments;
  need(Array.isArray(sourcePages) && Object.getPrototypeOf(sourcePages) === Array.prototype && sourcePages.length >= 1 && sourcePages.length <= 20001, 'Expected a bounded packet-document prefix.');
  const names = Reflect.ownKeys(sourcePages);
  need(names.length === sourcePages.length + 1 && names.every((k, i) => i === sourcePages.length ? k === 'length' : k === String(i)), 'Packet documents must be a dense plain array.');
  let totalBytes = 0;
  const documents = [];
  for (let i = 0; i < sourcePages.length; i++) {
    const d = Object.getOwnPropertyDescriptor(sourcePages, String(i));
    need(d?.enumerable && Object.hasOwn(d, 'value'), 'Packet documents cannot be computed.');
    const captured = document(d.value, PAGE_BYTES); totalBytes += captured.bytes;
    need(totalBytes <= args.maximumPacketBytes, 'Questionnaire model exceeds its encoded-packet memory budget.', 'questionnaire_model_budget');
    documents.push(captured);
  }
  const held = JSON.parse((await heldCapture).json); bindingShape(held);
  need(/^[a-z][a-z0-9./-]*$/.exec(held.renderer_identity.id)?.[0] === held.renderer_identity.id, 'Renderer identity has unsupported trailing text.');
  need(viewDocument.bytes === held.view_bytes && viewDocument.sha256 === held.view_hash && viewDocument.codec === held.view_codec, 'Original view document differs from its held binding.');
  const view = await admit(viewDocument, 16 * 1024 * 1024), index = viewIndex(view, held);
  const packets = [], rows = new Map(), occurrenceOrder = new Map(Array.from(index.occurrences.keys(), (k, i) => [k, i]));
  let first = null, offset = 0, rowOccurrence = null, rowPosition = 0, lastOccurrenceIndex = -1;
  for (const d of documents) {
    const p = await admit(d, PAGE_BYTES); packetAssociations(p, held, view, index, args.acknowledgedSequence);
    need(p.resume_page.offset === offset, 'Packet pages skip, repeat or reorder whole records.');
    if (first === null) first = p;
    else need(same(packetHeader(first), packetHeader(p)) && same(resumeHeader(first.resume_page), resumeHeader(p.resume_page)), 'Packet tokens, actions or recovery context changed between pages.');
    for (const row of p.resume_page.records) {
      need(!rows.has(row.step_key), 'Recovered pages repeat a question record.');
      if (rowOccurrence !== row.occurrence_key) {
        need(rowOccurrence === null || rowPosition === index.occurrences.get(rowOccurrence).question_step_keys.length, 'A record page skips the rest of a started occurrence.');
        const ordinal = occurrenceOrder.get(row.occurrence_key);
        need(ordinal > lastOccurrenceIndex, 'Recovered occurrence order differs from the assigned manifest.');
        rowOccurrence = row.occurrence_key; rowPosition = 0; lastOccurrenceIndex = ordinal;
      }
      need(index.occurrences.get(rowOccurrence).question_step_keys[rowPosition++] === row.step_key, 'Recovered records skip or reorder an assigned question.');
      rows.set(row.step_key, row);
    }
    offset = p.resume_page.next_offset; packets.push(p);
    if (offset === null) need(packets.length === documents.length, 'A complete model has unexpected later pages.');
  }
  const complete = offset === null;
  if (complete) need(rows.size === first.resume_page.total_records &&
    (rowOccurrence === null || rowPosition === index.occurrences.get(rowOccurrence).question_step_keys.length), 'Complete model is missing received records.');
  freeze(view); freeze(held); freeze(packets); freeze(documents);
  const current = first.latest_occurrence, currentVisit = current?.visit ?? null;
  function currentQuestion(stepKey) {
    const s = index.steps.get(stepKey), r = rows.get(stepKey);
    need(current && !current.sealed && currentVisit && !currentVisit.committed && currentVisit.step_key === stepKey && s?.type === 'question' &&
      s.occurrence_key === current.occurrence_key && first.resume_page.visible_step_keys.includes(stepKey), 'Wait for the exact current uncommitted question visit.');
    need(r, 'Load the page containing this current question record before editing.', 'questionnaire_page_required');
    need(r.status !== 'not_displayed', 'This question is not displayed by the current received state.');
    return {s, r};
  }
  function draftContext(stepKey) {
    const {s, r} = currentQuestion(stepKey);
    return freeze({step_key: stepKey, question_key: s.question_key, occurrence_key: current.occurrence_key,
      visit_id: currentVisit.id, state_version: current.state_version, last_answer_event_id: r.last_answer_event_id, dependency_generation: r.dependency_generation});
  }
  function submissionBinding(stepKey) {
    const {s, r} = currentQuestion(stepKey);
    return freeze({view_hash: held.view_hash, step_key: stepKey, question_key: s.question_key, information: s.question.type === 'information',
      occurrence_key: current.occurrence_key, phase: s.phase, state_version: current.state_version, visit: currentVisit,
      record: {step_key: stepKey, occurrence_key: current.occurrence_key, last_answer_event_id: r.last_answer_event_id, dependency_generation: r.dependency_generation}});
  }
  async function draftValue(stepKey, supplied) {
    const {s, r} = currentQuestion(stepKey), now = draftContext(stepKey);
    const fallback = ['answered', 'optional_omission'].includes(r.status) ? r.value : null;
    if (supplied === null) return freeze({applicable: false, reason: 'no_draft', value: fallback, origin_context: null, next_context: now});
    const source = ownData(supplied, ['generation', 'document']);
    const doc = ownData(source.document, ['codec', 'json', 'bytes', 'sha256']);
    need(integer(source.generation, 1) && doc.codec === PARTICIPANT_REQUEST_CODEC && typeof doc.json === 'string' &&
      doc.json.length <= 4 * 1024 * 1024 && integer(doc.bytes, 1, 4 * 1024 * 1024) && hash(doc.sha256), 'Invalid original draft document.');
    const captured = (await verifyParticipantJsonBytes(doc.json, {codec: PARTICIPANT_JSON_CODEC, bytes: doc.bytes, sha256: doc.sha256}, {maximumBytes: 4 * 1024 * 1024})).value;
    noNul(captured); fields(captured, ['schema', 'context', 'question', 'draft']);
    need(captured.schema === 'participant-questionnaire-draft/0.1' && same(await encodeParticipantRequest(captured), doc), 'Saved draft does not retain its exact local typed encoding.');
    const c = captured.context, d = captured.draft;
    fields(c, ['step_key', 'question_key', 'occurrence_key', 'visit_id', 'state_version', 'last_answer_event_id', 'dependency_generation']);
    fields(d, ['step_key', 'question_key', 'draft_revision', 'value']);
    questionShape(captured.question); answerShape(captured.question, d.value);
    need(key(c.step_key, 'pvs') && key(c.question_key, 'pvq') && key(c.occurrence_key, 'pvo') && text(c.visit_id, 128) &&
      integer(c.state_version) && integer(c.dependency_generation) && (c.last_answer_event_id === null || text(c.last_answer_event_id, 128)) &&
      d.step_key === c.step_key && d.question_key === c.question_key && c.question_key === captured.question.question_key &&
      integer(d.draft_revision, 1, Number.MAX_SAFE_INTEGER), 'Saved draft origin/revision is structurally invalid.');
    const applicable = same(captured.question, s.question) && c.step_key === stepKey && c.question_key === s.question_key &&
      c.occurrence_key === current.occurrence_key && c.state_version <= current.state_version &&
      c.dependency_generation === r.dependency_generation && c.last_answer_event_id === r.last_answer_event_id;
    return freeze({applicable, reason: applicable ? 'same_answer_dependency' : 'draft_context_changed', value: applicable ? d.value : fallback, origin_context: c, next_context: now});
  }
  async function action(input) {
    // Supplied observed clock/identities are snapshotted synchronously; no clock
    // is generated, renewed or re-timed while encoding or waiting for storage.
    const capture = encodeParticipantRequest(input);
    const x = JSON.parse((await capture).json);
    fields(x, ['kind', 'target_step_key', 'event_id', 'visit_id', 'clock']); clock(x.clock);
    need(text(x.event_id, 128) && current && !current.sealed, 'A current unsealed occurrence and original event ID are required.');
    if (currentVisit !== null) {
      if (x.kind === 'resume') need(x.clock.instance_id !== currentVisit.instance_id, 'Resume requires a new page clock instance.');
      else need(x.clock.instance_id === currentVisit.instance_id && x.clock.time_origin_ms === currentVisit.time_origin_ms &&
        Number(x.clock.value) >= Number(currentVisit.onset_ms), 'Resume explicitly before using a changed or reversed page clock.');
    }
    const base = {schema: 'participant-questionnaire-event/0.1', occurrence_key: current.occurrence_key, state_version: current.state_version};
    let target, payload;
    if (['enter', 'next', 'back', 'edit', 'resume'].includes(x.kind)) {
      if (x.kind === 'edit') { need(first.actions.editable_step_keys.includes(x.target_step_key), 'This question is not offered for editing.'); target = x.target_step_key; }
      else {
        need(x.target_step_key === null, 'Only an edit action takes an explicit target.');
        target = x.kind === 'resume' ? currentVisit?.step_key ?? null : first.actions[`${x.kind}_step_key`];
        need(target !== null, 'This navigation action is not available.');
      }
      need(text(x.visit_id, 128) && x.visit_id !== currentVisit?.id, 'Supply a fresh original visit identity.');
      payload = {...base, kind: 'visit', visit_id: x.visit_id, reason: x.kind, from_visit_id: currentVisit?.id ?? null};
    } else {
      need(x.kind === 'seal' && x.target_step_key === null && x.visit_id === null && first.actions.can_seal && currentVisit?.step_key === current.review_step_key,
        'Only the current received review may be sealed.');
      target = current.review_step_key; payload = {...base, kind: 'seal', visit_id: currentVisit.id, projection_token: current.projection_token};
    }
    Object.assign(payload, {clock_segment_id: x.clock.instance_id, time_origin_ms: x.clock.time_origin_ms});
    const observation = {view_hash: held.view_hash, event: {id: x.event_id, type: 'questionnaire_event', step_key: target,
      phase: index.steps.get(target).phase, clock: x.clock, payload}};
    const document = await encodeParticipantRequest(observation);
    return freeze({current_generation: args.currentGeneration, packet_state_token: first.packet_state_token, observation, document});
  }
  const snapshot = freeze({schema: 'participant-questionnaire-model/0.1', current_generation: args.currentGeneration,
    binding: held, packet: first, records: Array.from(rows.values()), records_complete: complete, encoded_packet_bytes: totalBytes,
    packet_documents: documents, view_document: viewDocument});
  return Object.freeze({snapshot: () => snapshot,
    step: k => index.steps.get(k) ?? null, occurrence: k => index.occurrences.get(k) ?? null, record: k => rows.get(k) ?? null,
    nextPageRequest: () => offset === null ? null : freeze({schema: 'participant-questionnaire-page-request/0.1', offset,
      packet_state_token: first.packet_state_token, view_hash: held.view_hash, source_protocol_hash: held.source_protocol_hash}),
    draftContext, submissionBinding, draftValue, action});
}
