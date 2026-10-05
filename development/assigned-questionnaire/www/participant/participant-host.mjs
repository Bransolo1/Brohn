/* Inactive public-view host. Exactly one collection/finalization owner runs at
 * a time. The legacy private-protocol runner is deliberately not an adapter. */
import {mountParticipantEntry} from './entry-screen.mjs';
import {createParticipantOperationSender} from './operation-sender.mjs';
import {createHeldParticipantQuestionnaireController} from './questionnaire-controller.mjs';
import {createAssignedIllustrations} from './assigned-illustrations.mjs';
import {createParticipantFinishController} from './finish-controller.mjs';
import {openParticipantHostEnding} from './host-ending.mjs';
import {captureParticipantObservation} from './observation-journal.mjs';
import {createParticipantEventOrder} from './event-order.mjs';
import {encodeParticipantRequest} from './request-bytes.mjs';
import {freeze, same, key, text} from './current-structure.mjs';

const owners = new WeakSet();
const fail = (code, message) => Object.assign(new Error(message), {code, retained: true});
const need = (ok, code, message) => {if (!ok) throw fail(code, message);};

export function mountParticipantHost({container, releaseToken, rendererIdentity, onState = null}) {
  need(container?.nodeType === 1 && !owners.has(container) && (onState === null || typeof onState === 'function'),
    'host_container', 'Use one owned study container and an optional state observer.');
  const document = container.ownerDocument, window = document.defaultView;
  need(window?.performance && window.crypto?.randomUUID && window === globalThis.window,
    'host_environment', 'Open the study in its original secure browser page.');
  const now = window.performance.now.bind(window.performance), id = prefix => `${prefix}-${window.crypto.randomUUID()}`;
  const originNumber = window.performance.timeOrigin;
  need(Number.isFinite(originNumber) && originNumber >= 0, 'host_clock', 'The original page clock is unavailable.');
  const pageClock = freeze({instance_id: id('page'), time_origin_ms: originNumber.toFixed(3)});
  const observeClock = () => {
    const value = now();
    need(Number.isFinite(value) && value >= 0 && value <= 1e12 && window.performance.timeOrigin === originNumber,
      'host_clock', 'The original page clock changed. Keep saved progress and reopen the study link.');
    return freeze({id: 'browser-monotonic', unit: 'ms', value: value.toFixed(6), ...pageClock});
  };
  const root = document.createElement('section'), entryBox = document.createElement('div'), session = document.createElement('section');
  const title = document.createElement('h1'), status = document.createElement('p'), error = document.createElement('p');
  const body = document.createElement('div'), actions = document.createElement('nav');
  root.className = 'brohn-participant-host'; session.hidden = true; title.tabIndex = -1;
  status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite');
  error.setAttribute('role', 'alert'); error.hidden = true; error.tabIndex = -1;
  actions.setAttribute('aria-label', 'Study controls'); session.append(title, status, error, body, actions);
  root.append(entryBox, session); container.append(root); owners.add(container);
  let entry, held = null, view = null, steps = null, ending = null, illustrations = null;
  let sender = null, questionnaire = null, finish = null, current = null;
  let phase = 'entry', problem = null, observerFailed = false, closed = false, closing = null;
  let tail = Promise.resolve(), jobs = 0, visibilityStep = null, visit = null, failedHead = null;
  let endingCapture = null, endingDurable = null, ownerKind = 'entry';
  const order = createParticipantEventOrder(), writes = new Set();
  const active = () => need(!closed, 'host_closed', 'This study page is closed. Reopen its original link to recover progress.');
  const summary = () => freeze({schema: 'participant-host-state/0.1', phase, owner: ownerKind,
    busy: jobs > 0 || !!closing, error: problem, observer_failed: observerFailed,
    acknowledged_sequence: sender?.state().acknowledged_sequence ?? finish?.state().acknowledged_sequence ?? null,
    pending_observations: order.state().pending, ending_captured: endingCapture !== null});
  function publish() {
    root.setAttribute('aria-busy', String(jobs > 0 || !!closing));
    actions.inert = jobs > 0 || !!closing || closed;
    for (const button of actions.querySelectorAll('button')) button.disabled = jobs > 0 || !!closing || closed;
    error.hidden = problem === null; error.textContent = problem?.message || '';
    status.textContent = problem ? (endingCapture || ownerKind === 'finish' ? 'The study ending is not yet confirmed.' : 'Your saved progress is retained. Review the message below.') :
      ({entry: '', opening: 'Recovering your current study progress…', instructions: 'Read the instructions, then continue.',
        resume: 'Continue from the saved instruction screen.', questionnaire: '', unsupported: 'This study needs another presentation component.',
        ending: 'Save your responses to finish this study.', saving: 'Saving your study ending…', finished: 'Your study ending is confirmed.',
        resolved: 'The researcher has closed this session.', closed: 'This study page is closed.'})[phase] || 'Recovering saved progress…';
    if (onState) try {onState(summary());} catch (_) {observerFailed = true;}
  }
  function report(errorValue) {
    problem = {code: typeof errorValue?.code === 'string' ? errorValue.code : 'host_failed',
      message: errorValue?.message || 'The study could not continue. Keep browser storage and retry.'};
    if (held && ending && !closed) {
      if (endingCapture || ownerKind === 'finish') endingScreen(true);
      else {actions.replaceChildren(); button('Retry recovery', retry, true);}
    }
    publish(); error.focus({preventScroll: true});
  }
  function enqueue(action) {
    active(); need(!closing, 'host_closing', 'Wait for this study page to close.'); jobs++; publish();
    const task = tail.then(() => {active(); return action();}); tail = task.catch(() => {});
    task.then(() => {jobs--; publish();}, value => {jobs--; report(value);}); return task;
  }
  function button(label, action, primary = false) {
    const node = document.createElement('button'); node.type = 'button'; node.textContent = label;
    if (primary) node.className = 'brohn-host-primary';
    node.addEventListener('click', () => {
      if (jobs || closing || closed) return;
      try {Promise.resolve(action()).catch(report);} catch (errorValue) {report(errorValue);}
    }); actions.append(node); return node;
  }
  function screen(heading, copy = '') {
    body.replaceChildren(); actions.replaceChildren(); title.textContent = heading;
    if (copy) {const p = document.createElement('p'); p.textContent = copy; p.className = 'brohn-host-copy'; body.append(p);}
    title.focus({preventScroll: true});
  }
  function endingScreen(recovering = false) {
    screen(recovering ? 'Your study ending needs another try' : 'Saving your study ending', recovering ?
      'Your original finish action is kept on this page. Retry saving to confirm that same ending. Keep this page open until it is confirmed.' :
      'Please keep this page open while your original study ending is saved and confirmed.');
    if (recovering) button('Retry saving', retry, true);
  }
  const clean = value => value?.phase === 'ready' && value.collection_transport_ready &&
    value.current?.completion_status === 'in_progress' && value.current.researcher_resolution === null &&
    value.storage.phase === 'open' && value.storage.unresolved_writes === 0 && value.storage.unconfirmed_writes === 0 &&
    value.storage.durable_pending_count === 0;
  function observed(type, step, payload, clock = observeClock()) {
    return {view_hash: held.binding.view_hash, event: {id: id('event'), type, step_key: step?.step_key ?? null,
      phase: step?.phase ?? 'session', clock, payload: {...payload, clock_segment_id: clock.instance_id, time_origin_ms: clock.time_origin_ms}}};
  }
  function retainCaptured(observation) {
    // Capture and reserve synchronously in the originating UI/visibility event.
    const captured = captureParticipantObservation(observation, held.binding.view_hash); captured.catch(() => {});
    const ticket = order.reserve(); let original = null, retryHandle = null;
    const write = async () => {
      if (!original) original = JSON.parse((await captured).json);
      try {const result = await (retryHandle ? retryHandle.retry() : sender.retainObservation(original)); retryHandle = null; return result;}
      catch (errorValue) {if (errorValue.retry_handle) retryHandle = errorValue.retry_handle; throw errorValue;}
    };
    const track = promise => {
      writes.add(promise);
      promise.then(() => {writes.delete(promise); if (failedHead?.ticket === ticket) failedHead = null; publish();},
        errorValue => {writes.delete(promise); failedHead ||= {ticket, retry}; report(errorValue);});
      promise.catch(() => {}); return promise;
    };
    const retry = () => track(order.retry(ticket));
    return track(order.fill(ticket, write));
  }
  function visibility() {
    if (closed || closing || !visibilityStep || !sender || endingCapture) return;
    try {
      retainCaptured(observed('visibility', visibilityStep, {reason: 'visibilitychange', hidden: document.hidden,
        focused: document.hasFocus(), viewport: {width: window.innerWidth, height: window.innerHeight}})).then(() => {
        if (!closed && !closing && sender && visibilityStep && !endingCapture)
          enqueue(async () => {if (sender && visibilityStep && !endingCapture) await freshCurrent();}).catch(() => {});
      }, () => {});
    } catch (errorValue) {report(errorValue);}
  }
  document.addEventListener('visibilitychange', visibility);
  async function drain() {
    // A failed head blocks later reservations. Never wait forever for followers
    // that cannot run until the participant explicitly retries that original.
    need(!order.state().failed, 'host_unsaved', 'Retry the original saved action before continuing or closing.');
    while (writes.size) await Promise.all(Array.from(writes));
    need(order.state().pending === 0, 'host_unsaved', 'An original observation is not confirmed saved.');
  }
  async function closeSender() {visibilityStep = null; await drain(); if (sender) {await sender.close(); sender = null;} current = null;}
  async function freshCurrent() {
    active(); await drain();
    if (!sender) {ownerKind = 'ordinary'; sender = createParticipantOperationSender({...held, onState: publish});}
    const value = await sender.synchronize(); active();
    need(['ready', 'closed_by_server'].includes(value.phase), value.error?.code || 'host_current',
      value.error?.message || 'Current progress could not be recovered.');
    current = value; return value;
  }
  function installView(value) {
    const nextView = JSON.parse(value.current.view_json);
    need(Array.isArray(nextView.steps) && nextView.steps.every(s => key(s.step_key, 'pvs') && text(s.type, 64)) &&
      new Set(nextView.steps.map(s => s.step_key)).size === nextView.steps.length, 'host_view', 'The assigned timeline is incomplete.');
    const nextSteps = new Map(nextView.steps.map(s => [s.step_key, s]));
    const appearance = nextView.presentation.appearance;
    need(/^#[0-9a-f]{6}$/i.test(appearance?.background) && /^#[0-9a-f]{6}$/i.test(appearance?.foreground),
      'host_appearance', 'The study appearance is incomplete.');
    const nextIllustrations = illustrations || createAssignedIllustrations({...held, document});
    // Commit installed state only after all synchronous validation/preparation.
    view = nextView; steps = nextSteps; illustrations = nextIllustrations;
    root.style.setProperty('--participant-bg', appearance.background); root.style.setProperty('--participant-fg', appearance.foreground);
  }
  async function showFinish(savedIntent = null) {
    await closeSender(); ownerKind = 'finish'; phase = 'saving'; endingScreen(); publish();
    if (!finish) finish = createParticipantFinishController({...held, onState: publish});
    const saved = await finish.inspect(); active();
    const result = saved.request_saved ? await finish.retry() : await finish.complete({outcome: savedIntent.outcome, finalSequence: savedIntent.sequence});
    active(); phase = result.phase === 'resolved' ? 'resolved' : 'finished';
    screen(phase === 'resolved' ? 'This session has been closed' : 'Thank you', phase === 'resolved' ?
      'The researcher has closed this session. Keep this browser’s saved progress until they confirm it is no longer needed.' :
      result.outcome === 'completed' ? view.presentation.debrief || 'Your responses have been saved.' : 'Your partial session has been saved.');
    publish();
  }
  async function recoverEnding() {
    phase = 'saving'; endingScreen(); publish();
    const saved = endingCapture ? await ending.prepare(endingCapture) : await ending.read();
    need(saved !== null, 'host_ending_missing', 'An actual ending must be saved before finalization.');
    endingCapture = saved.observation; endingDurable = saved.document; visibilityStep = null; phase = 'saving'; publish();
    if (!sender) await freshCurrent();
    need(clean(sender.state()), 'host_ending_current', 'Recover the original session before saving its ending.');
    // Repeating the same original ID/document recovers its actual sequence even
    // after a crash between journal transactioncomplete and sequence custody.
    const result = await retainCaptured(saved.observation);
    const retained = await ending.rememberSequence(result.sequence);
    const value = await freshCurrent();
    need(clean(value) && value.acknowledged_sequence === retained.sequence,
      'host_ending_ack', 'Confirm the original ending and every preceding response before finalization.');
    await showFinish(retained);
  }
  function finishClick() {
    need(clean(sender?.state()) && current?.current.resume.next_step_key === null && !endingCapture,
      'host_ending_not_ready', 'Recover the actual completed study boundary first.');
    // This participant activation is the terminal observation. Null cursor only
    // offers the action; it never silently creates a terminal event or outcome.
    endingCapture = observed('run_finished', null, {outcome: 'completed', reason: null});
    visibilityStep = null; phase = 'saving'; endingScreen();
    return enqueue(recoverEnding);
  }
  function instructionAction(resume) {
    need(clean(sender?.state()) && visit?.step && !visit.started, 'host_instructions', 'Recover these instructions before starting them.');
    const clock = observeClock(); visit = {...visit, started: true, resumed: resume, onset: clock.value};
    const saved = retainCaptured(observed('step_started', visit.step, {resumed: resume}, clock));
    visibilityStep = visit.step;
    return enqueue(async () => {await saved; await route();});
  }
  function continueInstructions() {
    need(clean(sender?.state()) && visit?.started && order.state().pending === 0,
      'host_instructions', 'Wait until the original instruction start is confirmed.');
    const clock = observeClock(), original = visit;
    const elapsed = original.resumed ? null : Number(clock.value) - Number(original.onset);
    need(elapsed === null || elapsed >= 0, 'host_clock', 'The original instruction clock moved backwards.');
    visibilityStep = null;
    const saved = retainCaptured(observed('step_finished', original.step, {elapsed_ms: elapsed, resumed: original.resumed}, clock));
    return enqueue(async () => {await saved; await route();});
  }
  async function route() {
    problem = null; const value = await freshCurrent(); active();
    if (!view || !steps) installView(value);
    if (value.phase === 'closed_by_server') {
      visibilityStep = null; phase = value.current.researcher_resolution ? 'resolved' : 'finished';
      screen('This session has ended', 'Keep this browser’s saved data. The current study status is confirmed by the study service.'); publish(); return;
    }
    if (view.presentation.camera !== null || view.presentation.equipment !== null) {
      visibilityStep = null; phase = 'unsupported';
      screen('Equipment setup is required',
        'This study requires an equipment or camera setup component that is not connected in this version. Your session is saved; contact your researcher.');
      await closeSender(); publish(); return;
    }
    const savedEnding = await ending.read();
    if (savedEnding || endingCapture) {await recoverEnding(); return;}
    const nextKey = value.current.resume.next_step_key;
    if (nextKey === null) {
      visibilityStep = null; visit = null; phase = 'ending';
      screen('Ready to finish', 'Your saved responses are ready. Select Finish study to confirm the ending.');
      button('Finish study', finishClick, true); publish(); return;
    }
    const step = steps.get(nextKey);
    need(step, 'host_step', 'The received next screen is not part of this assigned study.');
    if (['question', 'questionnaire_review'].includes(step.type)) {
      need(value.current.resume.questionnaire !== null, 'host_questionnaire', 'This questionnaire needs its original navigation packet.');
      await closeSender(); visit = null; phase = 'questionnaire'; ownerKind = 'questionnaire'; screen(view.presentation.title);
      questionnaire = createHeldParticipantQuestionnaireController({container: body, ...held, pageClock, observeClock,
        newEventId: () => id('event'), newVisitId: () => id('visit'), prepareIllustration: illustrations.prepareIllustration,
        onState: publish, onHandoff() {
          const prior = questionnaire;
          return enqueue(async () => {
            need(prior && prior === questionnaire, 'host_owner', 'The questionnaire owner changed before handoff.');
            await prior.releaseForHandoff(); questionnaire = null;
            // The boundary callback is not current authority. Reopen only after
            // its journal, draft writer and visibility owner have been released.
            await route();
          });
        }});
      await questionnaire.synchronize(); active(); publish(); return;
    }
    if (step.type !== 'instructions') {
      visibilityStep = null; visit = null; phase = 'unsupported';
      screen('This study needs another presentation component',
        'Your progress is saved. This version cannot present the next study screen yet. Contact your researcher; no screen has been skipped.');
      publish(); return;
    }
    need(typeof step.text === 'string' && text(step.phase, 96), 'host_instructions', 'The assigned instructions are incomplete.');
    const activeKey = value.current.resume.active_step_key;
    need(activeKey === null || activeKey === step.step_key, 'host_resume', 'The saved instruction cursor does not match the active screen.');
    if (!visit || visit.step.step_key !== step.step_key) visit = {step, started: false, resumed: false, onset: null};
    screen('Before you begin', step.text);
    if (activeKey === step.step_key && (!visit.started || value.current.resume.active_clock_instance_id !== pageClock.instance_id)) {
      visit = {step, started: false, resumed: true, onset: null}; phase = 'resume'; visibilityStep = null;
      actions.replaceChildren();
      button('Resume instructions', () => instructionAction(true), true); publish(); return;
    }
    if (!visit.started) {
      // Actual mounting starts this ordinary screen. Capture before storage or
      // network can delay the observed onset. No timed-exposure claim is made.
      const clock = observeClock(); visit = {step, started: true, resumed: false, onset: clock.value};
      const saved = retainCaptured(observed('step_started', step, {resumed: false}, clock)); visibilityStep = step;
      await saved; const admitted = await freshCurrent();
      need(clean(admitted) && admitted.current.resume.active_step_key === step.step_key &&
        admitted.current.resume.active_clock_instance_id === pageClock.instance_id, 'host_instructions', 'The original instruction start is not confirmed.');
    }
    phase = 'instructions'; visibilityStep = step; actions.replaceChildren(); button('Continue', continueInstructions, true); publish();
  }
  function retry() {
    need(held !== null && ending !== null, 'host_session', 'Open the original study invitation before recovering its session.');
    return enqueue(async () => {
      problem = null;
      if (endingCapture || ownerKind === 'finish') {endingScreen(); publish();}
      // Reopen ending custody under its existing lifetime lock. This remains
      // possible even while an original terminal capture is only in memory.
      if (ending) await ending.recover();
      if (failedHead) {
        // Reopen CURRENT/journal without draining or replacing the blocked
        // original reservation. A failed journal reopen cannot be healed by
        // replaying its retry_handle against the same missing/closed handle.
        const recovered = await sender.synchronize();
        need(recovered.storage.phase === 'open', recovered.error?.code || 'host_storage',
          'The saved-response store could not be reopened. Keep and retry the original capture.');
        await failedHead.retry();
      }
      if (questionnaire) {await questionnaire.retry(); return;}
      if (finish) {
        // An initial failed open is cached by finish-controller. Drain/release
        // that owner before constructing a fresh one; durable intent remains.
        await finish.close(); finish = null;
        finish = createParticipantFinishController({...held, onState: publish});
        const saved = await finish.inspect();
        if (saved.request_saved) {await showFinish(); return;}
        await finish.close(); finish = null;
      }
      await route();
    });
  }
  async function open(assigned, {signal}) {
    const input = encodeParticipantRequest({binding: assigned.binding, accessToken: assigned.accessToken});
    const viewJson = assigned.viewJson;
    await enqueue(async () => {
      need(!signal.aborted && held === null, 'host_session', 'This page already owns a study session.');
      held = freeze({...JSON.parse((await input).json), viewJson}); phase = 'opening'; publish();
      try {
        ending = await openParticipantHostEnding({binding: held.binding});
        finish = createParticipantFinishController({...held, onState: publish});
        const final = await finish.inspect();
        if (final.request_saved) {
          // A cold saved finish is recovered before any collection owner opens.
          view = JSON.parse(held.viewJson); session.hidden = false; entryBox.hidden = true;
          await showFinish(); return;
        }
        await finish.close(); finish = null;
        const value = await freshCurrent(); need(!signal.aborted, 'host_open_cancelled', 'Study opening was cancelled. Saved progress is retained.');
        installView(value);
        session.hidden = false; entryBox.hidden = true;
        await route();
      } catch (errorValue) {
        if (ending) {
          // The host has acquired durable session ownership. Keep original
          // failed captures/visits alive and expose its recovery action instead
          // of asking entry to create a second concurrent collection owner.
          session.hidden = false; entryBox.hidden = true;
          if (!title.textContent) title.textContent = 'Recover your study';
          report(errorValue); return;
        }
        await sender?.close(); sender = null; await finish?.close(); finish = null;
        await ending?.close(); ending = null; held = null;
        throw errorValue;
      }
    });
  }
  function close() {
    if (closing) return closing; if (closed) return Promise.resolve();
    visibilityStep = null;
    const task = tail.then(async () => {
      if (endingCapture && !endingDurable) {
        // The terminal UI activation can exist before any journal reservation.
        // Empty event order is therefore not proof that this capture is saved.
        const saved = await ending.read();
        const original = await captureParticipantObservation(endingCapture, held.binding.view_hash);
        need(saved !== null && same(saved.document, original), 'host_ending_unsaved',
          'The original study ending is not confirmed saved. Retry it before closing this page.');
        endingDurable = saved.document;
      }
      await drain(); await questionnaire?.close(); questionnaire = null;
      await closeSender(); await finish?.close(); finish = null;
      await illustrations?.close(); await ending?.close(); await entry?.close();
      closed = true; phase = 'closed'; document.removeEventListener('visibilitychange', visibility); owners.delete(container); root.remove();
    });
    closing = task; publish();
    task.catch(errorValue => {closing = null; report(errorValue);}); return task;
  }
  try {entry = mountParticipantEntry({container: entryBox, releaseToken, rendererIdentity, onSession: open});}
  catch (errorValue) {
    document.removeEventListener('visibilitychange', visibility); owners.delete(container); root.remove();
    throw errorValue;
  }
  const ready = entry.ready; publish();
  return Object.freeze({ready, retry, close, state: summary});
}
