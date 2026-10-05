/* Inactive already-held questionnaire orchestration. Original entry/start,
 * camera and other scientific renderers are owned by higher orchestration. */
import './view-question.js';
import {createParticipantOperationSender} from './operation-sender.mjs';
import {createParticipantQuestionnairePages} from './questionnaire-pages.mjs';
import {openParticipantQuestionnaireDrafts} from './questionnaire-drafts.mjs';
import {createParticipantEventOrder} from './event-order.mjs';
import {createQuestionnaireSubmitBridge} from './question-submit.mjs';
import {encodeParticipantRequest} from './request-bytes.mjs';
import {captureParticipantObservation} from './observation-journal.mjs';
import {freeze, same, text} from './current-structure.mjs';

const owners = new WeakSet();
const failure = (code, message) => Object.assign(new Error(message), {code, retained: true});
const need = (ok, code, message) => {if (!ok) throw failure(code, message);};
const errorSummary = e => ({code: typeof e?.code === 'string' ? e.code : 'questionnaire_controller', message: e?.message || 'Progress could not be confirmed.'});
const decimal = value => typeof value === 'string' && value.length <= 64 && /^[0-9]+([.][0-9]+)?$/.exec(value)?.[0] === value && Number.isFinite(Number(value));

export function createHeldParticipantQuestionnaireController({container, binding, viewJson, accessToken, pageClock,
  observeClock, newEventId, newVisitId, prepareIllustration, onState = null, onHandoff = null,
  maximumPacketBytes = 64 * 1024 * 1024}) {
  need(container?.nodeType === 1 && !owners.has(container), 'questionnaire_container', 'Use a fresh owned questionnaire container.');
  need([observeClock, newEventId, newVisitId].every(fn => typeof fn === 'function') &&
    (onState === null || typeof onState === 'function') && (onHandoff === null || typeof onHandoff === 'function'),
  'questionnaire_callbacks', 'Questionnaire observation and lifecycle callbacks are required.');
  // Capture declarations before any caller can mutate them during a digest.
  const heldInput = encodeParticipantRequest({binding, pageClock}).then(value => ({value}), error => ({error}));
  owners.add(container);
  const document = container.ownerDocument, window = document.defaultView;
  let phase = 'idle', problem = null, closed = false, closing = null, flight = null, flightKind = null, automatic = null;
  let loaded = null, drafts = null, draftWriter = null, component = null, displayedStep = null;
  let configured = null, busy = false, pendingIntents = 0, capturing = false, observerFailed = false;
  let failedHead = null, draftWrites = 0, draftProblem = null;
  let submittedContinuation = null, pendingHandoff = null, notifiedHandoff = null;
  const inFlightWrites = new Set(), retries = new WeakMap(), order = createParticipantEventOrder();
  const root = document.createElement('section'), status = document.createElement('p');
  const recovery = document.createElement('button'), actions = document.createElement('nav'), body = document.createElement('div');
  root.className = 'brohn-held-questionnaire'; status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite');
  recovery.type = 'button'; recovery.textContent = 'Retry recovery'; recovery.hidden = true;
  actions.setAttribute('aria-label', 'Questionnaire navigation'); root.append(status, recovery, body, actions); container.append(root);
  let sender = null;
  const senderState = () => sender?.state() ?? null;
  const active = () => need(!closed && !closing, 'questionnaire_closed', 'This questionnaire controller is closed or closing.');
  const fence = origin => {
    need(!closed && sender.currentDocument() === origin && origin.current_generation === loaded?.origin.current_generation,
      'questionnaire_current_changed', 'Current progress changed. Keep drafts and refresh before continuing.');
  };
  function cleanStorage(s) {
    // A failed post-commit diagnostic sets the count to null. A later successful
    // current/open count of zero is fresh evidence; an older diagnostic message
    // is retained in the public storage snapshot but is not an unsaved write.
    return s?.storage.phase === 'open' && s.storage.unconfirmed_writes === 0 && s.storage.unresolved_writes === 0 &&
      s.storage.durable_pending_count === 0;
  }
  function transportReady() {
    const s = senderState();
    return !!s?.collection_transport_ready && s.phase === 'ready' && s.current?.completion_status === 'in_progress' &&
      s.current.researcher_resolution === null && cleanStorage(s);
  }
  function currentUsable() {
    return !closed && !closing && !busy && !!loaded && sender.currentDocument() === loaded.origin && transportReady() &&
      order.state().pending === 0 && pendingIntents === 0;
  }
  function sameClock(visit) {return !!visit && !!configured && visit.instance_id === configured.pageClock.instance_id && visit.time_origin_ms === configured.pageClock.time_origin_ms;}
  function snapshot() {
    const s = senderState();
    return freeze({schema: 'participant-held-questionnaire-controller/0.1', phase, error: problem,
      current_generation: loaded?.origin.current_generation ?? null, acknowledged_sequence: s?.acknowledged_sequence ?? null,
      records_complete: loaded?.model.snapshot().records_complete ?? false,
      editing_ready: currentUsable() && !!component && sameClock(loaded.model.snapshot().packet.latest_occurrence?.visit),
      ordering: order.state(), draft_writes: draftWrites, draft_error: draftProblem,
      storage: s?.storage ?? null, transport_phase: s?.phase ?? 'idle', observer_failed: observerFailed});
  }
  function publish() {
    if (closed) phase = 'closed';
    body.inert = !currentUsable(); actions.inert = !currentUsable();
    const s = senderState();
    status.textContent = problem?.message || (draftWrites ? 'Saving changes in this browser…' :
      order.state().pending ? 'Saving the original observed response…' : busy ? 'Recovering current progress…' :
      s?.phase === 'closed_by_server' ? 'This session is closed. Saved local evidence is retained.' :
      s?.storage.unresolved_writes ? 'An observed response is not confirmed saved. Retry its original capture.' :
      s?.storage.durable_pending_count ? 'Responses are saved in this browser and waiting for server confirmation.' :
      phase === 'ready' ? 'Current progress is ready.' : phase === 'closed' ? 'This questionnaire is closed.' : 'Waiting for current progress.');
    recovery.hidden = closed || busy || !problem && !failedHead && !['needs_attention', 'closed_by_server'].includes(s?.phase);
    recovery.disabled = !!closing;
    if (onState) {try {onState(snapshot());} catch (_) {observerFailed = true;}}
  }
  function observeSender() {publish();}
  let pages;
  try {
    sender = createParticipantOperationSender({binding, viewJson, accessToken, onState: observeSender});
    pages = createParticipantQuestionnairePages({sender, accessToken, maximumPacketBytes});
  } catch (error) {owners.delete(container); root.remove(); void sender?.close(); throw error;}

  async function declarations() {
    if (configured) return;
    const result = await heldInput; if (result.error) throw result.error;
    const value = JSON.parse(result.value.json), clock = value.pageClock;
    need(clock && Object.keys(clock).length === 2 && Object.hasOwn(clock, 'instance_id') && Object.hasOwn(clock, 'time_origin_ms') &&
      text(clock.instance_id, 128) &&
      decimal(clock.time_origin_ms), 'questionnaire_clock', 'Supply the original page clock identity.');
    configured = freeze(value);
  }
  function scheduleSync() {
    if (closed || closing || automatic !== null) return;
    automatic = window.setTimeout(() => {
      automatic = null;
      if (!closed && !closing && !flight && order.state().pending === 0 && pendingIntents === 0)
        synchronize().catch(() => {});
    }, 0);
  }
  function tracked(promise, retry) {
    inFlightWrites.add(promise);
    promise.then(() => {
      inFlightWrites.delete(promise); if (failedHead?.retry === retry) failedHead = null;
      publish(); scheduleSync();
    }, error => {
      inFlightWrites.delete(promise); failedHead ||= {error, retry}; problem = errorSummary(error); phase = 'needs_attention'; publish();
    });
    return promise;
  }
  function writeObservation(observation) {
    // The shared order invokes this same callback on retry. Reuse the sender's
    // immutable retained capture instead of reading or retiming caller input.
    const retry = retries.get(observation);
    const promise = retry ? retry.retry() : sender.retainObservation(observation);
    return promise.then(result => {retries.delete(observation); return result;}, error => {
      if (error.retry_handle) retries.set(observation, error.retry_handle); throw error;
    });
  }
  function ordered(observation, captured) {
    const ticket = order.reserve(); let attempt = null;
    // Shape/clock capture began synchronously before reservation. Hash completion
    // can wait; the original captured document and callback cannot be replaced.
    let retained = null;
    const write = async () => {if (!retained) retained = JSON.parse((await captured).json); return writeObservation(retained);};
    const retry = () => {attempt = tracked(order.retry(ticket), retry); return attempt;};
    attempt = tracked(order.fill(ticket, write), retry); publish(); return attempt;
  }
  // The accepted bridge performs the exact plain-data snapshot and visit clock
  // check. Do not read clock getters before that boundary.
  function capturedClock() {return observeClock();}
  function visibility() {
    if (closed || closing || !displayedStep || !configured || !sender.currentDocument()) return;
    try {
      need(!capturing, 'questionnaire_reentry', 'Observation capture cannot reenter.'); capturing = true;
      const clock = observeClock();
      need(clock?.instance_id === configured.pageClock.instance_id && clock.time_origin_ms === configured.pageClock.time_origin_ms,
        'questionnaire_clock_changed', 'Keep this page’s original observed clock.');
      const observation = {view_hash: configured.binding.view_hash, event: {id: newEventId(), type: 'visibility',
        step_key: displayedStep.step_key, phase: displayedStep.phase, clock,
        payload: {reason: 'visibilitychange', hidden: document.hidden, focused: document.hasFocus(),
          viewport: {width: window.innerWidth, height: window.innerHeight}, clock_segment_id: clock.instance_id, time_origin_ms: clock.time_origin_ms}}};
      const captured = captureParticipantObservation(observation, configured.binding.view_hash); captured.catch(() => {});
      ordered(observation, captured).catch(() => {});
    } catch (error) {problem = errorSummary(error); phase = 'needs_attention'; publish();}
    finally {capturing = false;}
  }
  document.addEventListener('visibilitychange', visibility);
  function retireComponent() {
    if (component) {component.destroy(); component = null;}
    draftWriter?.close(); draftWriter = null; body.replaceChildren(); actions.replaceChildren();
  }
  function submitWriter(origin) {
    let original = null;
    return observation => {
      if (original === null) {
        original = {origin, observation, sequence: null};
        need(submittedContinuation === null, 'questionnaire_continuation_pending', 'Recover the original submitted response before another submission.');
        submittedContinuation = original;
      } else need(original.observation === observation, 'questionnaire_submission_changed', 'Retry the exact original submission.');
      return writeObservation(observation).then(result => {original.sequence = result.sequence; return result;});
    };
  }
  function continueSubmitted() {
    const intent = submittedContinuation;
    if (intent === null || !currentUsable() || intent.sequence === null) return;
    const model = loaded.model, packet = model.snapshot().packet, latest = packet.latest_occurrence;
    const event = intent.observation.event, payload = event.payload, row = model.record(event.step_key);
    // This process-local intent survives a lost reply, never a page restart.
    // The receipt is not current authority: require the newly installed CURRENT
    // and exact received visit/answer before considering its offered next step.
    if (loaded.origin.current_generation <= intent.origin.current_generation ||
        loaded.origin.acknowledged_sequence < intent.sequence) return;
    const exactVisit = latest && !latest.sealed && latest.occurrence_key === payload.occurrence_key &&
      latest.visit?.id === payload.visit_id && latest.visit.step_key === event.step_key && latest.visit.committed &&
      latest.visit.instance_id === event.clock.instance_id && latest.visit.time_origin_ms === event.clock.time_origin_ms;
    const exactAnswer = payload.kind === 'acknowledge' ? row?.status === 'information_acknowledged' :
      row?.last_answer_event_id === event.id && same(row.value, payload.value);
    submittedContinuation = null;
    if (!exactVisit || !exactAnswer || packet.actions.next_step_key === null) return;
    // Consume once before capture/reservation. Navigation observes its own clock
    // now; the submitted event and its earlier observation time are unchanged.
    try {act('next').catch(error => {problem = errorSummary(error); phase = 'needs_attention'; publish();});}
    catch (error) {problem = errorSummary(error); phase = 'needs_attention';}
  }
  function notifyHandoff() {
    if (!pendingHandoff || notifiedHandoff === pendingHandoff || closed || closing || flight) return;
    notifiedHandoff = pendingHandoff;
    const rejected = error => {
      observerFailed = true; problem = errorSummary(error);
      // A host may have already drained/closed this owner before its next owner
      // failed. Retain the diagnostic, never remount or revive the closed UI.
      if (!closed && !closing) {phase = 'needs_attention'; publish();}
    };
    if (onHandoff) {
      try {Promise.resolve(onHandoff(pendingHandoff)).catch(rejected);}
      catch (error) {rejected(error);}
    }
  }
  async function flushComponent() {
    // Set inert before the component's internal drain guard is installed. The
    // component blocks new capture until all prior queued callbacks settle.
    body.inert = true; actions.inert = true;
    if (component) await component.flushDraft();
  }
  function button(label, action, parent = actions) {
    const element = document.createElement('button'); element.type = 'button'; element.textContent = label;
    element.addEventListener('click', () => {
      const refused = error => {problem = errorSummary(error); phase = 'needs_attention'; publish();};
      // Invoke now: navigation clocks belong to this user action, not a later
      // promise continuation after a storage/network wait.
      try {Promise.resolve(action()).catch(refused);} catch (error) {refused(error);}
    });
    parent.append(element); return element;
  }
  function answerText(question, row) {
    if (question.type === 'information') return row.status === 'information_acknowledged' ? 'Read and acknowledged' : 'Not acknowledged';
    const value = row.value; if (value === null) return 'Not answered';
    const label = key => question.options?.find(option => option.option_key === key)?.label ?? String(key);
    if (Array.isArray(value)) return value.map(label).join(', ');
    if (typeof value === 'object') return Object.entries(value).map(([key, answer]) => {
      if (question.type === 'allocation') return `${question.options.find(item => item.option_key === key).label}: ${answer === null ? 'Not answered' : Object.is(answer, -0) ? '−0' : String(answer)}`;
      return `${question.rows?.find(item => item.row_key === key)?.label ?? key}: ${answer === null ? 'Not answered' : label(answer)}`;
    }).join('; ');
    return typeof value === 'number' && Object.is(value, -0) ? '−0' : typeof value === 'string' ? label(value) : String(value);
  }
  async function install(next) {
    active();
    need(sender.currentDocument() === next.origin, 'questionnaire_current_changed', 'Current progress changed while loading questions.');
    const model = next.model, snapshot = model.snapshot(), latest = snapshot.packet.latest_occurrence, visit = latest?.visit ?? null;
    const step = visit ? model.step(visit.step_key) : null;
    let initial = null, context = null;
    const editable = step?.type === 'question' && !visit.committed && !latest.sealed && sameClock(visit) && transportReady();
    if (editable) {
      if (!drafts) {
        const opened = await openParticipantQuestionnaireDrafts({binding: next.origin.binding});
        if (closed || closing) {await opened.close(); active();}
        drafts = opened;
      }
      active();
      need(sender.currentDocument() === next.origin, 'questionnaire_current_changed', 'Current progress changed while opening drafts.');
      const original = await drafts.read(step.step_key); active();
      need(sender.currentDocument() === next.origin, 'questionnaire_current_changed', 'Current progress changed while reading drafts.');
      const selected = await model.draftValue(step.step_key, original === null ? null : {generation: original.generation, document: original.document}); active();
      need(sender.currentDocument() === next.origin, 'questionnaire_current_changed', 'Current progress changed while admitting the original draft.');
      initial = selected.value; context = selected.next_context;
    }
    retireComponent(); loaded = next; displayedStep = step; draftProblem = null; pendingHandoff = null;
    if (editable) {
      const writer = await drafts.begin({context, question: step.question});
      if (closed || closing) {writer.close(); active();}
      need(sender.currentDocument() === next.origin, 'questionnaire_current_changed', 'Current progress changed while reserving the draft writer.');
      draftWriter = writer;
      const bridge = createQuestionnaireSubmitBridge({binding: model.submissionBinding(step.step_key), order,
        observeClock: capturedClock, newEventId, writeObservation: submitWriter(next.origin)});
      const onDraft = payload => {
        draftWrites++; publish();
        let result;
        try {result = writer.save(payload);} catch (error) {draftWrites--; draftProblem = errorSummary(error); publish(); throw error;}
        return result.then(value => {draftProblem = null; return value;}, error => {draftProblem = errorSummary(error); throw error;})
          .finally(() => {draftWrites--; publish();});
      };
      component = globalThis.BrohnViewQuestion.mount({container: body, stepKey: step.step_key, question: step.question,
        initialDraft: initial, prepareIllustration, onDraft,
        onSubmitIntent(payload) {need(currentUsable() && !capturing, 'questionnaire_not_ready', 'Recover the exact current visit before submitting.');
          capturing = true;
          try {const handle = bridge.onSubmitIntent(payload); pendingIntents++; publish(); return handle;}
          finally {capturing = false;}},
        onDiscardSubmitIntent(notice) {bridge.onDiscardSubmitIntent(notice); pendingIntents--; publish(); scheduleSync();},
        onComplete(payload, notice) {
          const retry = () => tracked(bridge.onComplete(payload, notice), retry);
          const promise = bridge.onComplete(payload, notice); pendingIntents = 0;
          publish(); return tracked(promise, retry);
        }});
    } else if (step?.type === 'questionnaire_review') {
      const heading = document.createElement('h2'); heading.textContent = 'Review your answers'; body.append(heading);
      const list = document.createElement('dl'); body.append(list);
      for (const row of snapshot.records.filter(row => row.occurrence_key === latest.occurrence_key && row.status !== 'not_displayed')) {
        const question = model.step(row.step_key).question, term = document.createElement('dt'), answer = document.createElement('dd');
        term.textContent = question.prompt; answer.textContent = answerText(question, row); list.append(term, answer);
      }
      if (!snapshot.records_complete) {
        const message = document.createElement('p'); message.textContent = `Loaded ${snapshot.records.length} of ${snapshot.packet.resume_page.total_records} saved answers.`;
        body.append(message); button('Load remaining answers', loadReview, body);
      }
    } else {
      const message = document.createElement('p');
      message.textContent = step?.type === 'question' ? visit.committed ? 'This answer is saved. Continue when current progress is ready.' : 'Resume this question on this page before editing.' :
        latest && !latest.sealed ? 'Continue to the current questionnaire question.' : 'This part of the questionnaire has finished.';
      body.append(message);
    }
    const available = snapshot.packet.actions;
    if (visit !== null && !sameClock(visit) && !latest.sealed) button('Resume questionnaire', () => act('resume'));
    else {
      for (const [kind, label] of [['enter', 'Start questions'], ['next', 'Continue'], ['back', 'Back']])
        if (available[`${kind}_step_key`] !== null) button(label, () => act(kind));
      if (step?.type === 'questionnaire_review') {
        for (const key of available.editable_step_keys) button(`Edit: ${model.step(key).question.prompt}`, () => act('edit', key));
        if (available.can_seal && snapshot.records_complete) button('Confirm answers and continue', () => act('seal'));
      }
    }
    if (latest === null || latest.sealed) {
      const nextStep = snapshot.packet.next_step_key ? model.step(snapshot.packet.next_step_key) : null;
      pendingHandoff = Object.freeze({origin: next.origin, step: nextStep, packet: snapshot.packet});
    }
  }
  function run(kind, action) {
    active(); need(!capturing, 'questionnaire_reentry', 'Current recovery cannot interrupt an observation capture.');
    if (flight) {need(flightKind === kind, 'questionnaire_busy', 'Wait for the current controller operation.'); return flight;}
    const next = Promise.resolve().then(action); flight = next; flightKind = kind; busy = true; phase = 'recovering'; problem = null; publish();
    next.then(() => {if (flight === next) {flight = null; flightKind = null; busy = false; phase = senderState()?.phase === 'closed_by_server' ? 'closed_by_server' : 'ready';
      if (phase === 'closed_by_server') submittedContinuation = null;
      else if (kind === 'current') continueSubmitted();
      notifyHandoff(); publish();}},
      error => {if (flight === next) {flight = null; flightKind = null; busy = false; problem = errorSummary(error); phase = 'needs_attention'; publish();}});
    return next;
  }
  function synchronize() {
    return run('current', async () => {
      await declarations();
      active();
      need(order.state().pending === 0 && pendingIntents === 0, 'questionnaire_observation_pending', 'Save or retry the original observed response before refreshing.');
      await flushComponent();
      const state = await sender.synchronize(); active();
      need(state.phase === 'ready' || state.phase === 'closed_by_server', state.error?.code || 'questionnaire_recovery',
        state.error?.message || 'Current progress could not be recovered.');
      const origin = sender.currentDocument();
      need(origin !== null && same(origin.binding, configured.binding), 'questionnaire_binding', 'Current progress differs from the held session.');
      if (state.phase === 'closed_by_server') return;
      if (origin.questionnaire_document === null) {
        retireComponent(); loaded = null; displayedStep = null;
        pendingHandoff = Object.freeze({origin, step: null, packet: null}); return;
      }
      await install(await pages.load());
    });
  }
  function loadReview() {
    need(currentUsable(), 'questionnaire_not_ready', 'Reconcile current progress before loading review pages.');
    return run('review', async () => {await flushComponent(); active(); await install(await pages.load({complete: true}));});
  }
  function act(kind, target = null) {
    active(); need(currentUsable() && !capturing, 'questionnaire_not_ready', 'Keep saved, current progress before navigating.');
    need(kind !== 'seal' || loaded.model.snapshot().records_complete, 'questionnaire_review_incomplete', 'Load all received review answers before confirming them.');
    need(!component || draftWrites === 0, 'questionnaire_draft_pending', 'Wait for the current draft to finish saving.');
    const origin = loaded.origin, model = loaded.model; let result;
    capturing = true;
    try {
      // Build the exact action at the user event. No await may retime this clock.
      const clock = observeClock();
      const input = {kind, target_step_key: target, event_id: newEventId(), visit_id: kind === 'seal' ? null : newVisitId(), clock};
      need(input.clock?.instance_id === configured.pageClock.instance_id && input.clock.time_origin_ms === configured.pageClock.time_origin_ms,
        'questionnaire_clock_changed', 'Keep the original page clock for navigation.');
      result = model.action(input); result.catch(() => {});
    } finally {capturing = false;}
    // Reserve immediately so a later visibility event cannot overtake this
    // captured navigation while the draft barrier or digest is settling.
    const ticket = order.reserve(), componentAtCapture = component;
    const promise = (async () => {
      let captured;
      try {
        if (componentAtCapture) await componentAtCapture.flushDraft();
        fence(origin); captured = await result; fence(origin);
      } catch (error) {
        // No durable callback was handed off. Release only this still-reserved
        // position, retain the draft/error, and require a fresh explicit action.
        order.discard(ticket); publish(); scheduleSync(); throw error;
      }
      const write = () => writeObservation(captured.observation);
      const retry = () => tracked(order.retry(ticket), retry);
      return tracked(order.fill(ticket, write), retry);
    })();
    inFlightWrites.add(promise);
    promise.then(() => inFlightWrites.delete(promise), () => inFlightWrites.delete(promise));
    promise.catch(() => {}); publish(); return promise;
  }
  async function retry() {
    active();
    if (flight && flightKind === 'recovery') return flight;
    if (failedHead) {
      const retained = failedHead;
      return run('recovery', async () => {
        // Open CURRENT/storage without installing pages or consuming the
        // blocked original reservation. This flight disables duplicate UI
        // actions and joins programmatic retry while the same recovery runs.
        const recovered = await sender.synchronize();
        need(recovered.storage.phase === 'open', recovered.error?.code || 'questionnaire_storage',
          'The saved-response store could not be reopened. Keep and retry the original capture.');
        await retained.retry();
      });
    }
    return synchronize();
  }
  recovery.addEventListener('click', () => {retry().catch(error => {problem = errorSummary(error); publish();});});
  function close() {
    if (closed) return Promise.resolve(); if (closing) return closing;
    const next = Promise.resolve().then(async () => {
      need(!order.state().failed && failedHead === null, 'questionnaire_unsaved',
        'Retry the original observed response before closing this questionnaire.');
      if (automatic !== null) {window.clearTimeout(automatic); automatic = null;}
      await flushComponent();
      need(!order.state().failed && failedHead === null, 'questionnaire_unsaved',
        'Retry the original observed response before closing this questionnaire.');
      // Destroy releases an unhanded submit intent; already handed writes remain
      // in the shared order and must reach transactioncomplete before close.
      retireComponent();
      while (inFlightWrites.size) await Promise.all(Array.from(inFlightWrites));
      need(order.state().pending === 0 && senderState().storage.unresolved_writes === 0 && senderState().storage.unconfirmed_writes === 0,
        'questionnaire_unsaved', 'An original observation is not confirmed saved. Retry it before closing.');
      await pages.close(); await sender.close(); await Promise.resolve(flight).catch(() => {}); await drafts?.close();
      closed = true; document.removeEventListener('visibilitychange', visibility); owners.delete(container); publish();
    });
    closing = next; publish();
    next.catch(error => {closing = null; problem = errorSummary(error); phase = 'needs_attention'; publish();});
    return next;
  }
  async function releaseForHandoff() {
    need(pendingHandoff !== null && pendingHandoff === notifiedHandoff && flight === null,
      'questionnaire_handoff', 'Wait for the settled received non-questionnaire boundary.');
    const original = pendingHandoff;
    await close();
    // Higher orchestration may open another owner only after this promise:
    // local writes drained, visibility listener removed, journal lock released.
    return original;
  }
  publish();
  return Object.freeze({synchronize, loadReview, act, retry, state: snapshot, close, releaseForHandoff});
}
