/* Inactive public-view host. Exactly one collection/finalization owner runs at
 * a time. The legacy private-protocol runner is deliberately not an adapter. */
import {mountParticipantEntry} from './entry-screen.mjs';
import {createParticipantOperationSender} from './operation-sender.mjs';
import {createHeldParticipantQuestionnaireController} from './questionnaire-controller.mjs';
import {createAssignedIllustrations} from './assigned-illustrations.mjs';
import {createParticipantFinishController} from './finish-controller.mjs';
import {openParticipantHostEnding} from './host-ending.mjs';
import {openParticipantTimedArms} from './timed-arm.mjs';
import {createAssignedStimulusMedia} from './stimulus-media.mjs';
import {createTimedSequence} from './timed-sequence.mjs';
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
  let clockFence = 0;
  const pageValue = value => {
    need(Number.isFinite(value) && value >= 0 && value <= 1e12 && window.performance.timeOrigin === originNumber,
      'host_clock', 'The original page clock changed. Keep saved progress and reopen the study link.');
    return freeze({id: 'browser-monotonic', unit: 'ms', value: value.toFixed(6), ...pageClock});
  };
  const reserveClock = clock => {
    need(clock.id === 'browser-monotonic' && clock.unit === 'ms' && clock.instance_id === pageClock.instance_id &&
      clock.time_origin_ms === pageClock.time_origin_ms && Number.isFinite(Number(clock.value)) && Number(clock.value) >= clockFence,
      'host_clock', 'Keep the original order of observed browser clocks.');
    clockFence = Number(clock.value); return clock;
  };
  const observeClock = () => reserveClock(pageValue(now()));
  const root = document.createElement('section'), entryBox = document.createElement('div'), session = document.createElement('section');
  const title = document.createElement('h1'), status = document.createElement('p'), error = document.createElement('p');
  const body = document.createElement('div'), actions = document.createElement('nav');
  const presentationBox = document.createElement('div');
  root.className = 'brohn-participant-host'; session.hidden = true; title.tabIndex = -1;
  status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite');
  error.setAttribute('role', 'alert'); error.hidden = true; error.tabIndex = -1;
  actions.setAttribute('aria-label', 'Study controls'); session.append(title, status, error, body, actions);
  root.append(entryBox, session, presentationBox); container.append(root); owners.add(container);
  let entry, held = null, view = null, steps = null, ending = null, illustrations = null;
  let sender = null, questionnaire = null, finish = null, current = null;
  let phase = 'entry', problem = null, observerFailed = false, closed = false, closing = null;
  let tail = Promise.resolve(), jobs = 0, visibilityStep = null, visit = null, failedHead = null;
  let endingCapture = null, endingDurable = null, ownerKind = 'entry';
  let arms = null, activeArm = null, timedRenderer = null, stimulusMedia = null, preparedMaterials = null;
  let timedCloseDiagnostic = null, interruptionTask = null, pendingTimedInterruption = null;
  const adoptedBoundaries = new Set();
  const materialAbort = new window.AbortController();
  const order = createParticipantEventOrder(), writes = new Set();
  const active = () => need(!closed, 'host_closed', 'This study page is closed. Reopen its original link to recover progress.');
  const summary = () => freeze({schema: 'participant-host-state/0.1', phase, owner: ownerKind,
    busy: jobs > 0 || !!closing, error: problem, observer_failed: observerFailed,
    acknowledged_sequence: sender?.state().acknowledged_sequence ?? finish?.state().acknowledged_sequence ?? null,
    pending_observations: order.state().pending, ending_captured: endingCapture !== null,
    active_timed_arm: activeArm?.arm_id ?? null, timed_close_diagnostic: timedCloseDiagnostic});
  function participantError() {
    if (!problem) return '';
    const code = problem.code;
    // Technical codes/messages remain in state() for diagnostics. Participant
    // text is deliberately chosen here, never copied from a backend exception.
    if (code === 'host_storage_newer' || code === 'arm_storage_newer')
      return 'This browser’s saved-data format has changed. Keep this page open and contact your researcher.';
    if (code === 'host_ending_integrity' || code === 'host_ending_conflict' ||
        /(?:integrity|conflict|reconciliation|mismatch)$/.test(code))
      return 'We need help checking your saved progress. Keep this page open and contact your researcher.';
    if (/^(?:sender|finish|current)_http_(?:401|403)$/.test(code))
      return 'Access to this session could not be confirmed. Keep this page open and contact your researcher.';
    if (/storage|journal|unsaved|draft/.test(code))
      return 'We couldn’t save your latest action on this device. Keep this page open and retry.';
    if (/network|timeout|_http_/.test(code))
      return 'We couldn’t reach the study service. Keep this page open and retry.';
    if (endingCapture || ownerKind === 'finish')
      return 'The study service could not confirm your submission. Keep this page open and retry.';
    return 'We couldn’t continue this session. Keep this page open and retry, or contact your researcher if this continues.';
  }
  function publish() {
    root.setAttribute('aria-busy', String(jobs > 0 || !!closing));
    actions.inert = jobs > 0 || !!closing || closed;
    for (const button of actions.querySelectorAll('button')) button.disabled = jobs > 0 || !!closing || closed;
    error.hidden = problem === null; error.textContent = participantError();
    status.textContent = problem ? (endingCapture || ownerKind === 'finish' ? 'Your submission still needs confirmation.' : 'Your session needs attention.') :
      ({entry: '', opening: 'Recovering your current study progress…', instructions: 'Read the instructions, then continue.',
        resume: 'Continue from the saved instruction screen.', questionnaire: '', unsupported: 'This study needs another presentation component.',
        preparing: 'Preparing the study materials…', presenting: '', reconciling: 'Saving this part of your study…',
        ending: 'Your responses are ready to submit.', saving: 'Saving…', finished: 'Your responses have been saved.',
        resolved: 'The researcher has closed this session.', closed: 'This study page is closed.'})[phase] ?? 'Recovering saved progress…';
    status.hidden = status.textContent.length === 0;
    if (onState) try {onState(summary());} catch (_) {observerFailed = true;}
  }
  function report(errorValue) {
    // No recovery chrome may replace an active exposure. The renderer halts
    // synchronously before the host samples its original interruption ending.
    if (timedRenderer && ['waiting_frame', 'presenting'].includes(timedRenderer.state().phase))
      timedRenderer.interrupt('timed_host_failure', 'interrupted', errorValue);
    problem = {code: typeof errorValue?.code === 'string' ? errorValue.code : 'host_failed',
      message: errorValue?.message || 'The study could not continue. Keep browser storage and retry.'};
    if (held && ending && !closed) {
      if (endingCapture || ownerKind === 'finish') endingScreen(true);
      else {actions.replaceChildren(); button('Retry', retry, true);}
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
    screen(recovering ? 'We couldn’t confirm your submission' : 'Saving your session', recovering ?
      'We’ll retry the same submission. Please keep this page open.' :
      'Keep this page open until your submission is confirmed.');
    if (recovering) button('Retry', retry, true);
  }
  const clean = value => value?.phase === 'ready' && value.collection_transport_ready &&
    value.current?.completion_status === 'in_progress' && value.current.researcher_resolution === null &&
    value.storage.phase === 'open' && value.storage.unresolved_writes === 0 && value.storage.unconfirmed_writes === 0 &&
    value.storage.durable_pending_count === 0;
  function observed(type, step, payload, clock = observeClock()) {
    reserveClock(clock);
    return freeze({view_hash: held.binding.view_hash, event: {id: id('event'), type, step_key: step?.step_key ?? null,
      phase: step?.phase ?? 'session', clock, payload: {...payload, clock_segment_id: clock.instance_id, time_origin_ms: clock.time_origin_ms}}});
  }
  function retainCaptured(observation, armId = null) {
    // Capture and reserve synchronously in the originating UI/visibility event.
    const ticket = order.reserve(); let captured;
    try {captured = captureParticipantObservation(observation, held.binding.view_hash);}
    catch (errorValue) {captured = Promise.reject(errorValue);}
    captured.catch(() => {});
    let original = null, retryHandle = null, journalResult = null;
    const write = async () => {
      if (!original) {
        // The immutable host-owned event/ID/clock and ticket survive even a
        // synchronous snapshot or later digest failure. Retrying only encodes
        // that same value; it does not sample or reserve a replacement.
        if (!captured) captured = captureParticipantObservation(observation, held.binding.view_hash);
        try {original = JSON.parse((await captured).json);}
        catch (errorValue) {captured = null; throw errorValue;}
      }
      try {
        if (!journalResult) journalResult = await (retryHandle ? retryHandle.retry() : sender.retainObservation(original));
        retryHandle = null;
        // The same ordered reservation covers both actual journal durability
        // and its arm note. On a note failure, retry the original journal result.
        if (armId !== null) await arms.remember({armId, observation: original, sequence: journalResult.sequence});
        return journalResult;
      }
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
    if (closed || closing || timedRenderer || !visibilityStep || !sender || endingCapture) return;
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
    const nextStimulusMedia = stimulusMedia || createAssignedStimulusMedia({...held, document});
    // Commit installed state only after all synchronous validation/preparation.
    view = nextView; steps = nextSteps; illustrations = nextIllustrations; stimulusMedia = nextStimulusMedia;
    root.style.setProperty('--participant-bg', appearance.background); root.style.setProperty('--participant-fg', appearance.foreground);
  }
  const timedStep = step => ['baseline', 'fixation', 'stimulus'].includes(step?.type);
  const rendererActive = () => timedRenderer && ['waiting_frame', 'presenting'].includes(timedRenderer.state().phase);
  function restoreOrdinaryChrome() {session.hidden = false; session.inert = false; entryBox.hidden = true;}
  function timedAdmission(value) {
    const original = sender?.currentDocument();
    need(clean(value) && original && original.acknowledged_sequence === value.acknowledged_sequence &&
      same(original.binding, held.binding) && value.current.resume.active_step_key === null,
      'host_timed_current', 'Recover the original inactive presentation boundary.');
    const document = original.current_document;
    return freeze({acknowledged_sequence: value.acknowledged_sequence,
      next_step_key: value.current.resume.next_step_key, active_step_key: null,
      current_document: {codec: document.codec, bytes: document.bytes, sha256: document.sha256}});
  }
  async function ensureArms() {
    if (!arms) arms = await openParticipantTimedArms({binding: held.binding, viewJson: held.viewJson});
    return arms;
  }
  async function closeTimedRenderer() {
    if (!timedRenderer) return;
    need(!rendererActive(), 'host_timed_active', 'Stop presentation and retain its actual ending before closing.');
    await drain();
    const prior = timedRenderer;
    try {await prior.close();}
    catch (errorValue) {
      // The renderer remembers its first failed promise even after the host
      // retries that exact ordered capture. Host durability is the authority:
      // accept retirement only after its queue drains and renderer close has
      // actually removed ownership with no unowned media or pending writes.
      const state = prior.state();
      need(state.phase === 'closed' && state.pending_writes === 0 && state.capture_bridges === 0 && state.unowned_media_records === 0 &&
        prior.unownedBoundaryRecords().every(record => adoptedBoundaries.has(record)) &&
        order.state().pending === 0 && !order.state().failed,
        'host_timed_unsaved', 'Keep the original presentation observations before closing.');
      timedCloseDiagnostic = {code: errorValue?.code || 'timed_close', message: errorValue?.message || 'Original renderer failure retained.'};
    }
    timedRenderer = null; adoptedBoundaries.clear(); pendingTimedInterruption = null;
    if (ownerKind === 'timed') ownerKind = 'ordinary'; restoreOrdinaryChrome();
  }
  function capturedEnding(outcome, reason) {
    need(!endingCapture && ['completed', 'interrupted', 'withdrawn'].includes(outcome),
      'host_ending_captured', 'Recover the original ending rather than creating another.');
    endingCapture = observed(outcome === 'withdrawn' ? 'withdrawal' : 'run_finished', null, {outcome, reason});
    visibilityStep = null; phase = 'saving'; restoreOrdinaryChrome(); endingScreen();
  }
  function interruptedTimed(value) {
    // Keep the exact stopped renderer's originals reachable even if adopting a
    // pre-custody tuple cannot yet succeed. Do not sample a later terminal first.
    pendingTimedInterruption = value;
    need(activeArm && value.arm_id === activeArm.arm_id && !rendererActive() && value.unowned_media_records.length === 0,
      'host_timed_owner', 'Stop the original presentation before retaining its interruption.');
    if (endingCapture) return interruptionTask || Promise.resolve();
    visibilityStep = null;
    for (const record of value.unowned_boundary_records) {
      if (adoptedBoundaries.has(record)) continue;
      const observation = observed(record.type, record.step, record.payload, record.clock);
      const durability = retainCaptured(observation, activeArm.arm_id);
      adoptedBoundaries.add(record); durability.catch(() => {});
    }
    if (['visibilitychange', 'blur', 'resize', 'pagehide', 'timed_step_without_window_focus', 'timed_step_started_without_window_focus'].includes(value.reason)) {
      retainCaptured(observed('visibility', value.step, {reason: value.reason, hidden: document.hidden,
        focused: document.hasFocus(), viewport: {width: window.innerWidth, height: window.innerHeight}})).catch(() => {});
    }
    // Called only after the renderer's synchronous halt. No old onset/finish
    // is manufactured, including interruption before the first presentation.
    capturedEnding(value.outcome, value.reason);
    interruptionTask = enqueue(recoverEnding); interruptionTask.catch(() => {}); return interruptionTask;
  }
  async function recoverTimedArm(value, saved) {
    activeArm = saved;
    const resume = value.current.resume;
    if (resume.active_step_key === null && resume.next_step_key === saved.boundary_step_key) {
      try {
        await arms.settle({armId: saved.arm_id, admission: timedAdmission(value)});
        activeArm = null; return false;
      } catch (errorValue) {
        if (errorValue?.code !== 'arm_incomplete') throw errorValue;
        // Missing exact ledger evidence is not permission to replay exposure.
      }
    }
    capturedEnding('interrupted', 'timed_sequence_reopened_without_complete_boundary');
    await recoverEnding(); return true;
  }
  async function beginTimed(step) {
    need(!timedRenderer && !activeArm && clean(sender?.state()), 'host_timed_owner', 'Recover the existing presentation before arming another.');
    visibilityStep = null; visit = null; phase = 'preparing';
    screen('Preparing your study', 'Please keep this page open while the study materials load.'); publish();
    if (!preparedMaterials) preparedMaterials = await stimulusMedia.prepareAll({signal: materialAbort.signal});
    active();
    const value = await freshCurrent();
    need(value.current.resume.next_step_key === step.step_key, 'host_timed_current', 'The assigned presentation boundary changed during preparation.');
    const admission = timedAdmission(value);
    await ensureArms();
    need(await arms.inspect() === null, 'host_timed_replay', 'An original armed sequence must be recovered without replay.');
    activeArm = await arms.arm({arm_id: id('arm'), first_step_key: step.step_key, page_clock: pageClock, admission});
    active();
    try {
      const arm = activeArm;
      timedRenderer = createTimedSequence({container: presentationBox,
        sequence: arm.step_keys.map(key => steps.get(key)), preparedHandles: preparedMaterials,
        appearance: view.presentation.appearance, armId: arm.arm_id, pageClock,
        frameClock: raw => pageValue(raw), eventClockFence: () => clockFence,
        observeMediaClock: () => pageValue(now()),
        capture({type, step, payload, clock}) {
          need(activeArm?.arm_id === arm.arm_id && !endingCapture, 'host_timed_owner', 'Retain the original active timed sequence.');
          const observation = observed(type, step, payload, clock);
          return {durability: retainCaptured(observation, arm.arm_id)};
        },
        onBoundary(value) {
          return enqueue(async () => {
            need(activeArm?.arm_id === value.arm_id && !endingCapture && value.pending_play_settlements === 0,
              'host_timed_boundary', 'Recover the original presentation boundary before continuing.');
            phase = 'reconciling'; restoreOrdinaryChrome(); screen('Saving your progress'); publish();
            await drain();
            const current = await freshCurrent();
            await arms.settle({armId: value.arm_id, admission: timedAdmission(current)});
            activeArm = null; await closeTimedRenderer(); await route();
          });
        },
        onInterrupt: interruptedTimed});
      ownerKind = 'timed'; phase = 'presenting'; session.inert = true; session.hidden = true;
      // A queued first rAF can carry a timestamp older than the arm's actual
      // transactioncomplete. Fence after that commit and synchronous setup;
      // the renderer defers such a frame instead of clamping its timestamp.
      observeClock();
      timedRenderer.start(); publish();
    } catch (errorValue) {
      if (timedRenderer) {
        timedRenderer.interrupt('timed_presentation_failed', 'interrupted', errorValue);
        throw errorValue;
      }
      // The arm exists but construction failed before any observed exposure.
      // Retain an actual new interruption; never remove/rearm that sequence.
      presentationBox.replaceChildren();
      capturedEnding('interrupted', 'timed_presentation_unavailable'); await recoverEnding();
    }
  }
  async function showFinish(savedIntent = null) {
    await closeSender(); ownerKind = 'finish'; phase = 'saving'; endingScreen(); publish();
    if (!finish) finish = createParticipantFinishController({...held, onState: publish});
    const saved = await finish.inspect(); active();
    const result = saved.request_saved ? await finish.retry() : await finish.complete({outcome: savedIntent.outcome, finalSequence: savedIntent.sequence});
    active(); phase = result.phase === 'resolved' ? 'resolved' : 'finished';
    screen(phase === 'resolved' ? 'This session has been closed' : 'Thank you', phase === 'resolved' ?
      'The researcher has closed this session. Keep this browser’s saved progress until they confirm it is no longer needed.' :
      result.outcome === 'completed' ? view.presentation.debrief || 'Your responses have been saved.' :
        result.outcome === 'withdrawn' ? 'You have withdrawn from this study. Your partial session has been saved.' :
          'This session was interrupted. Your saved responses have been kept. Contact your researcher before starting again.');
    publish();
  }
  async function recoverEnding() {
    phase = 'saving'; endingScreen(); publish();
    const saved = endingCapture ? await ending.prepare(endingCapture) : await ending.read();
    need(saved !== null, 'host_ending_missing', 'An actual ending must be saved before finalization.');
    endingCapture = saved.observation; endingDurable = saved.document; visibilityStep = null; phase = 'saving'; publish();
    await drain(); await closeTimedRenderer();
    await freshCurrent();
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
    capturedEnding('completed', null);
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
    need(!rendererActive(), 'host_timed_active', 'Wait for the current presentation boundary.');
    problem = null; const value = await freshCurrent(); active();
    if (!view || !steps) installView(value);
    if (value.phase === 'closed_by_server') {
      visibilityStep = null; phase = value.current.researcher_resolution ? 'resolved' : 'finished';
      screen('This session has ended', 'Keep this browser’s saved data. The current study status is confirmed by the study service.'); publish(); return;
    }
    const savedEnding = await ending.read();
    if (savedEnding || endingCapture) {await recoverEnding(); return;}
    await ensureArms();
    const savedArm = await arms.inspect();
    if (savedArm && await recoverTimedArm(value, savedArm)) return;
    if (view.presentation.camera !== null || view.presentation.equipment !== null) {
      visibilityStep = null; phase = 'unsupported';
      screen('Equipment setup is required',
        'This study requires an equipment or camera setup component that is not connected in this version. Your session is saved; contact your researcher.');
      await closeSender(); publish(); return;
    }
    // Whole-study admission, before any instruction/questionnaire observation.
    // Provider decoding alone does not qualify a media evidence/receiver profile.
    if (view.steps.some(step => step.type === 'stimulus' && !['text', 'image'].includes(step.material?.type))) {
      visibilityStep = null; phase = 'unsupported';
      screen('This study needs another presentation component',
        'This study includes media that is not connected in this version. Your saved progress is retained. Contact your researcher before continuing.');
      await closeSender(); publish(); return;
    }
    const nextKey = value.current.resume.next_step_key;
    if (nextKey === null) {
      visibilityStep = null; visit = null; phase = 'ending';
      screen('Ready to finish', 'Select Finish study to submit your responses.');
      button('Finish study', finishClick, true); publish(); return;
    }
    const step = steps.get(nextKey);
    need(step, 'host_step', 'The received next screen is not part of this assigned study.');
    if (timedStep(step)) {await beginTimed(step); return;}
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
    need(!timedRenderer || ['interrupted', 'closed'].includes(timedRenderer.state().phase),
      'host_timed_active', 'Wait for the current presentation to stop before recovering saved progress.');
    return enqueue(async () => {
      problem = null;
      if (endingCapture || ownerKind === 'finish') {endingScreen(); publish();}
      // Reopen ending custody under its existing lifetime lock. This remains
      // possible even while an original terminal capture is only in memory.
      if (ending) await ending.recover();
      if (arms) await arms.recover();
      if (pendingTimedInterruption && !endingCapture) {
        // Adoption is synchronous and may queue the original ending behind this
        // retry. Never await that queued job from inside its own predecessor.
        interruptedTimed(pendingTimedInterruption); return;
      }
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
    if (timedRenderer?.state().phase === 'boundary')
      return Promise.reject(fail('host_timed_boundary', 'Wait for this presentation boundary to finish saving before closing.'));
    if (rendererActive()) timedRenderer.interrupt('timed_owner_closed', 'interrupted');
    visibilityStep = null;
    materialAbort.abort();
    const task = tail.then(async () => {
      need(!pendingTimedInterruption || endingCapture !== null, 'host_timed_unsaved',
        'The original presentation interruption is not yet retained. Keep this page open and retry.');
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
      await closeTimedRenderer();
      await closeSender(); await finish?.close(); finish = null;
      await stimulusMedia?.close(); await arms?.close(); await illustrations?.close(); await ending?.close(); await entry?.close();
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
