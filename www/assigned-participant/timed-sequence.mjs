/* Inactive renderer: host owns admission, strict arm custody, all durable writes,
 * recovery and endings. No network, independent clock identity or storage here. */
const presentingDocuments = new WeakSet();
const fail = (code, message) => Object.assign(new Error(message), {code, retained: true});
const need = (ok, code, message) => {if (!ok) throw fail(code, message);};
const decimal = x => typeof x === 'string' && /^[0-9]+(?:\.[0-9]+)?$/.test(x) && Number.isFinite(Number(x));
const finite = x => typeof x === 'number' && Number.isFinite(x);
const publicKey = (value, prefix) => typeof value === 'string' && value.length === 68 &&
  value.startsWith(prefix + '-') && /^[0-9a-f]{64}$/.test(value.slice(4));
const deepFreeze = value => {
  if (value && typeof value === 'object') {for (const child of Object.values(value)) deepFreeze(child); Object.freeze(value);}
  return value;
};
// Admitted plain data includes exact finite observations such as negative zero.
const copy = value => deepFreeze(structuredClone(value));
const clockFields = ['id', 'unit', 'value', 'instance_id', 'time_origin_ms'];
const sameClock = (left, right) => left && Object.keys(left).length === clockFields.length &&
  clockFields.every(field => left[field] === right[field]);

export function createTimedSequence({container, sequence, preparedHandles, appearance, armId, pageClock,
  frameClock, eventClockFence, observeMediaClock, capture, captureMedia = null, snapshotMedia = null,
  onBoundary, onInterrupt}) {
  need(container?.nodeType === 1 && container.ownerDocument?.defaultView,
    'timed_container', 'Use the original participant page container.');
  const document = container.ownerDocument, win = document.defaultView;
  need(win === globalThis.window && typeof win.requestAnimationFrame === 'function',
    'timed_environment', 'Use the original browser presentation page.');
  need([frameClock, eventClockFence, observeMediaClock, capture, onBoundary, onInterrupt].every(fn => typeof fn === 'function'),
    'timed_callbacks', 'Connect the host clock, retained captures, boundary and ending owners.');
  need(typeof armId === 'string' && armId.length > 0 && armId.length <= 128 &&
    typeof pageClock?.instance_id === 'string' && pageClock.instance_id.length > 0 && decimal(pageClock.time_origin_ms),
    'timed_arm', 'Keep the original durably armed sequence and page identity.');
  const page = copy(pageClock), steps = copy(sequence);
  const origin = win.performance.timeOrigin;
  need(finite(origin) && origin >= 0 && page.time_origin_ms === origin.toFixed(3),
    'timed_clock', 'Keep the actual original page time origin.');
  need(Array.isArray(steps) && steps.length > 0 && steps.length <= 20000 &&
    new Set(steps.map(step => step?.step_key)).size === steps.length, 'timed_sequence', 'Present the exact assigned timed sequence once.');
  for (const step of steps) need(publicKey(step.step_key, 'pvs') && publicKey(step.stimulus_key, 'pvi') &&
    ['baseline', 'fixation', 'stimulus'].includes(step.type) && step.phase === (step.type === 'stimulus' ? 'passive_viewing' : step.type) &&
    Number.isInteger(step.duration_ms) && step.duration_ms >= (step.type === 'stimulus' ? 100 : 1) &&
    step.duration_ms <= (step.type === 'stimulus' ? 3600000 : 600000),
  'timed_sequence', 'Keep the original assigned duration, stimulus and phase.');
  need(/^#[0-9a-f]{6}$/i.test(appearance?.background) && /^#[0-9a-f]{6}$/i.test(appearance?.foreground),
    'timed_appearance', 'Use the assigned participant appearance.');
  need(Array.isArray(preparedHandles), 'timed_materials', 'Prepare the complete assigned material set before arming.');
  const handles = new Map(preparedHandles.map(handle => [handle?.step_key, handle]));
  need(handles.size === preparedHandles.length, 'timed_materials', 'Keep one prepared handle for each assigned stimulus step.');
  const used = new Set(), materials = new Map(); let hasMedia = false;
  for (const step of steps.filter(step => step.type === 'stimulus')) {
    const handle = handles.get(step.step_key), kind = step.material?.type, element = handle?.element;
    const tag = {text: 'DIV', image: 'IMG', audio: 'AUDIO', video: 'VIDEO'}[kind];
    need(tag && element?.ownerDocument === document && element.tagName === tag && !element.isConnected &&
      !used.has(element) && typeof handle.release === 'function', 'timed_materials', 'Borrow each exact prepared stimulus element once.');
    if (kind === 'text') need(element.textContent === step.material.content && element.classList.contains('assigned-stimulus-text'),
      'timed_materials', 'Keep the assigned literal text and presentation class.');
    if (kind === 'image') need(element.complete && element.naturalWidth > 0 && element.naturalHeight > 0,
      'timed_materials', 'Prepare each assigned image before presentation.');
    if (['audio', 'video'].includes(kind)) {
      need(element.readyState >= 4 && !element.error && element.paused && element.currentTime === 0 &&
        !element.autoplay && !element.loop && !element.controls && element.playbackRate === 1,
      'timed_materials', 'Keep the prepared media ready, paused and at its original beginning.');
      hasMedia = true;
    }
    used.add(element); materials.set(step.step_key, {element, kind});
  }
  need(!hasMedia || typeof captureMedia === 'function' && typeof snapshotMedia === 'function',
    'timed_media_capability', 'Connect the admitted durable media evidence profile before presenting audio or video.');

  const shell = document.createElement('section'), header = document.createElement('div');
  const stage = document.createElement('div'), footer = document.createElement('footer'), withdraw = document.createElement('button');
  shell.className = 'brohn-timed-shell'; shell.hidden = true; shell.setAttribute('aria-label', 'Study presentation');
  shell.style.setProperty('--participant-bg', appearance.background); shell.style.setProperty('--participant-fg', appearance.foreground);
  header.className = 'brohn-timed-header-space'; header.setAttribute('aria-hidden', 'true');
  stage.className = 'brohn-timed-stage'; footer.className = 'brohn-timed-footer';
  withdraw.className = 'brohn-timed-withdraw'; withdraw.type = 'button'; withdraw.textContent = 'Withdraw from study';
  footer.append(withdraw); shell.append(header, stage, footer); container.append(shell);
  let phase = 'prepared', index = -1, current = null, frame = null, ownsEnvironment = false;
  let problem = null, interrupted = false, boundaryNotified = false, hasPresented = false, closed = false, closing = null;
  let interruptionJob = null, boundaryJob = null, pendingPlay = 0, captureDepth = 0, interruptionDelivery = null;
  const pending = new Set(), nativeListeners = [], failures = [], unownedMedia = new Set(), unownedBoundaries = new Set();
  const occurrence = new WeakMap(); let nextOccurrence = 0;
  const originals = records => Array.from(records).sort((a, b) => occurrence.get(a) - occurrence.get(b));
  const state = () => deepFreeze({schema: 'participant-timed-renderer-state/0.1', arm_id: armId, phase,
    active_step_key: current?.step.step_key ?? null, index, pending_writes: pending.size,
    pending_play_settlements: pendingPlay, unowned_media_records: unownedMedia.size,
    unowned_boundary_records: unownedBoundaries.size,
    capture_bridges: captureDepth,
    boundary_notified: boundaryNotified, interrupted,
    error: problem ? {code: problem.code || 'timed_failure', message: problem.message} : null});

  function checkClock(clock) {
    need(clock && Object.keys(clock).length === clockFields.length && clock.id === 'browser-monotonic' && clock.unit === 'ms' && decimal(clock.value) && Number(clock.value) <= 1e12 &&
      clock.instance_id === page.instance_id && clock.time_origin_ms === page.time_origin_ms && win.performance.timeOrigin === origin,
    'timed_clock', 'Keep the original observed page clock.');
    return copy(clock);
  }
  function track(result) {
    need(result && typeof result.durability?.then === 'function', 'timed_capture', 'The host must retain each original observation.');
    const promise = Promise.resolve(result.durability); pending.add(promise);
    promise.then(() => pending.delete(promise), error => {
      pending.delete(promise); failures.push(error); problem ||= error;
      if (!closed) interrupt('timed_observation_not_saved', 'interrupted', error);
    });
    return result;
  }
  function captureBoundary(type, step, payload, clock) {
    const original = deepFreeze({type, step, payload, clock}); occurrence.set(original, nextOccurrence++); captureDepth++;
    try {
      return track(capture(original));
    }
    catch (error) {unownedBoundaries.add(original); problem ||= error; failures.push(error); throw error;}
    finally {captureDepth--; deliverInterruption();}
  }
  function mediaRecord(record, kind, error = null) {
    if (closed) return;
    const element = record.element, sampled = observeMediaClock();
    if (closed) return;
    const clock = checkClock(sampled);
    const item = deepFreeze({arm_id: armId, step_key: record.step.step_key, kind, clock,
      media_current_time: finite(element.currentTime) && element.currentTime >= 0 ? element.currentTime : null,
      playback_rate: finite(element.playbackRate) ? element.playbackRate : null,
      ready_state: element.readyState, network_state: element.networkState, paused: element.paused, ended: element.ended,
      error_name: typeof error?.name === 'string' ? error.name : null,
      error_code: Number.isInteger(element.error?.code) ? element.error.code : null});
    // The synchronous bridge may fail before the host has original custody.
    // Keep that exact record accessible even after renderer DOM/listener close.
    occurrence.set(item, nextOccurrence++); captureDepth++;
    try {track(captureMedia(item)); return clock;}
    catch (error) {unownedMedia.add(item); problem ||= error; failures.push(error); throw error;}
    finally {captureDepth--; deliverInterruption();}
  }
  function listenMedia(record) {
    for (const kind of ['playing', 'waiting', 'stalled', 'error', 'pause', 'ended', 'seeking', 'seeked', 'ratechange']) {
      const handler = () => {
        if (closed) return;
        try {
          const clock = mediaRecord(record, kind);
          if (!clock) return;
          if (kind === 'playing') record.playbackObserved = Number(clock.value);
          if (phase === 'presenting' && current?.step === record.step &&
            (['waiting', 'stalled', 'error', 'seeking', 'seeked'].includes(kind) || kind === 'ratechange' && record.element.playbackRate !== 1))
            interrupt(`media_${kind}`);
        } catch (error) {interrupt('timed_media_capture_failed', 'interrupted', error);}
      };
      record.element.addEventListener(kind, handler); nativeListeners.push(() => record.element.removeEventListener(kind, handler));
    }
  }
  function play(record) {
    try {mediaRecord(record, 'play_requested');}
    catch (error) {interrupt('timed_media_capture_failed', 'interrupted', error); return;}
    if (closed || interrupted || phase !== 'presenting') return;
    try {
      const result = record.element.play();
      need(result && typeof result.then === 'function', 'timed_media_play', 'This browser did not return a media playback acknowledgement.');
      pendingPlay++;
      Promise.resolve(result).then(() => {
        pendingPlay--;
        if (!closed) try {mediaRecord(record, 'play_resolved');} catch (error) {interrupt('timed_media_capture_failed', 'interrupted', error);}
      }, error => {
        pendingPlay--;
        if (!closed) {
          try {mediaRecord(record, 'play_rejected', error);} catch (failure) {problem ||= failure;}
          interrupt('media_playback_blocked', 'interrupted', error);
        }
      });
    } catch (error) {
      // A synchronous native play throw is also an observed rejection.
      try {mediaRecord(record, 'play_rejected', error);} catch (failure) {problem ||= failure;}
      interrupt('media_playback_blocked', 'interrupted', error);
    }
  }
  function pause(record) {
    if (!record || record.pauseRequested) return;
    record.pauseRequested = true; let failure = null;
    // Attempt the native stop even if evidence capture itself fails.
    try {mediaRecord(record, 'pause_requested');} catch (error) {problem ||= error; failures.push(error); failure ||= error;}
    try {record.element.pause();} catch (error) {problem ||= error; failures.push(error); failure ||= error;}
    return failure;
  }
  function releaseEnvironment() {
    if (!ownsEnvironment) return;
    document.removeEventListener('visibilitychange', visibility);
    document.removeEventListener('keydown', keyboard, true);
    for (const name of ['blur', 'focus', 'resize', 'pagehide']) win.removeEventListener(name, environment);
    ownsEnvironment = false; presentingDocuments.delete(document);
  }
  function halt() {
    if (frame !== null) {win.cancelAnimationFrame(frame); frame = null;}
    // Stop and remove before a later host now() interruption/terminal capture.
    pause(current?.media); stage.replaceChildren(); shell.hidden = true; releaseEnvironment();
  }
  function stopPresentation() {
    if (closed) return;
    if (phase === 'presenting' || phase === 'waiting_frame') phase = 'stopped';
    halt(); return state();
  }
  function interrupt(reason, outcome = 'interrupted', error = null) {
    if (closed || interrupted) return interruptionJob;
    need(typeof reason === 'string' && reason.length > 0 && ['interrupted', 'withdrawn'].includes(outcome),
      'timed_interrupt', 'Keep the actual interruption or withdrawal cause.');
    interrupted = true; phase = 'interrupted'; problem ||= error;
    let resolve, reject;
    interruptionJob = new Promise((yes, no) => {resolve = yes; reject = no;});
    interruptionJob.catch(failure => {problem ||= failure; failures.push(failure);});
    halt();
    interruptionDelivery = {reason, outcome, step: current?.step ?? steps[Math.max(index, 0)],
      frame_started: hasPresented, resolve, reject};
    deliverInterruption();
    return interruptionJob;
  }
  function deliverInterruption() {
    if (captureDepth !== 0 || interruptionDelivery === null) return;
    const delivery = interruptionDelivery; interruptionDelivery = null;
    // Halt is already synchronous and complete. A reentrant capture must first
    // return its durability or throw: provisional tuples are never adoptable.
    try {
      Promise.resolve(onInterrupt(deepFreeze({arm_id: armId, reason: delivery.reason, outcome: delivery.outcome,
        step: delivery.step, frame_started: delivery.frame_started,
        unowned_media_records: originals(unownedMedia), unowned_boundary_records: originals(unownedBoundaries),
        error: problem ? {code: problem.code || 'timed_failure', message: problem.message} : null})))
        .then(delivery.resolve, delivery.reject);
    } catch (error) {delivery.reject(error);}
  }
  function visibility() {if (document.hidden) interrupt('visibilitychange');}
  function environment(event) {
    if (event.type === 'blur' || event.type === 'resize' || event.type === 'pagehide' || document.hidden || !document.hasFocus())
      interrupt(event.type);
  }
  function keyboard(event) {
    if (event.key === 'Escape') {event.preventDefault(); event.stopPropagation(); interrupt('participant_requested', 'withdrawn');}
  }
  withdraw.addEventListener('click', () => {interrupt('participant_requested', 'withdrawn');});
  function claimEnvironment() {
    need(!presentingDocuments.has(document), 'timed_owner', 'Only one timed renderer may own the participant page.');
    presentingDocuments.add(document); ownsEnvironment = true;
    document.addEventListener('visibilitychange', visibility); document.addEventListener('keydown', keyboard, true);
    for (const name of ['blur', 'focus', 'resize', 'pagehide']) win.addEventListener(name, environment);
  }
  function elementFor(step) {
    if (step.type === 'stimulus') return materials.get(step.step_key).element;
    const element = document.createElement('span');
    element.textContent = step.type === 'fixation' ? '+' : '';
    element.setAttribute('aria-label', step.type === 'fixation' ? 'Fixation cross' : 'Baseline');
    if (step.type === 'fixation') element.className = 'brohn-timed-fixation';
    return element;
  }
  function begin(nextIndex, clock) {
    if (closed || interrupted || !['waiting_frame', 'presenting'].includes(phase)) return;
    index = nextIndex; const step = steps[index], element = elementFor(step), assigned = materials.get(step.step_key);
    const record = assigned && ['audio', 'video'].includes(assigned.kind) ?
      {step, element, playbackObserved: null, pauseRequested: false} : null;
    if (record) {
      need(element.readyState >= 4 && !element.error && element.paused && element.currentTime === 0 &&
        !element.autoplay && !element.loop && !element.controls && element.playbackRate === 1,
      'timed_materials', 'The assigned prepared media changed before its presentation.');
      listenMedia(record);
    }
    current = {step, onset: Number(clock.value), previous: null, frames: 0, maxGap: 0, media: record};
    stage.replaceChildren(element); shell.hidden = false; phase = 'presenting'; hasPresented = true;
    const rect = element.getBoundingClientRect();
    captureBoundary('step_started', step, {
      scheduled_duration_ms: step.duration_ms, timing_reference: 'requestAnimationFrame_before_paint',
      viewport: {width: win.innerWidth, height: win.innerHeight, device_pixel_ratio: win.devicePixelRatio},
      stimulus_rect: {x: rect.x, y: rect.y, width: rect.width, height: rect.height},
      media_current_time: record ? element.currentTime : null, media_playback_observed_ms: null
    }, clock);
    if (record && !closed && !interrupted && phase === 'presenting') play(record);
  }
  function finishStep(clock) {
    const elapsed = Number(clock.value) - current.onset;
    const payload = {elapsed_ms: elapsed, resumed: false, scheduled_duration_ms: current.step.duration_ms,
      observed_duration_ms: elapsed, frames: current.frames, max_frame_gap_ms: current.maxGap};
    const stopFailure = pause(current.media); if (stopFailure) throw stopFailure;
    if (closed || interrupted || phase !== 'presenting') return;
    if (hasMedia) {
      const sampled = observeMediaClock();
      if (closed || interrupted || phase !== 'presenting') return;
      const attachmentClock = checkClock(sampled);
      const evidence = snapshotMedia(deepFreeze({arm_id: armId, attachment_clock: attachmentClock}));
      need(evidence === null || evidence && typeof evidence === 'object' && !('then' in evidence) &&
        Object.keys(evidence).length === 3 && evidence.schema === 'participant-timed-media-evidence/0.1' &&
        sameClock(evidence.attachment_clock, attachmentClock) && Array.isArray(evidence.groups) && evidence.groups.length === 1 &&
        Object.keys(evidence.groups[0] ?? {}).length === 2 && evidence.groups[0].arm_id === armId && Array.isArray(evidence.groups[0].records),
        'timed_media_snapshot', 'Snapshot and reserve original media attachment records synchronously.');
      if (evidence !== null) payload.timed_media = copy(evidence);
    }
    if (closed || interrupted || phase !== 'presenting') return;
    captureBoundary('step_finished', current.step, payload, clock);
    stage.replaceChildren();
  }
  async function drainCaptured() {
    if (failures.length) throw failures[0];
    need(unownedMedia.size === 0, 'timed_media_not_retained',
      'Retain the original media observations through the host before treating this renderer as drained.');
    need(unownedBoundaries.size === 0, 'timed_boundary_not_retained',
      'Retain the original frame observations through the host before treating this renderer as drained.');
    while (pending.size) {await Promise.all(Array.from(pending)); if (failures.length) throw failures[0];}
  }
  function boundary() {
    phase = 'boundary'; halt(); current = null;
    boundaryJob = (async () => {
      await drainCaptured();
      if (closed || interrupted) return;
      boundaryNotified = true;
      // No wait for a native event that has no guaranteed delivery. The host
      // retains remaining media records and owns terminal snapshot/recovery.
      await onBoundary(deepFreeze({arm_id: armId, step_keys: steps.map(step => step.step_key),
        pending_play_settlements: pendingPlay}));
    })();
    boundaryJob.catch(error => {
      // Host may close this DOM before a later handoff action fails. Retain
      // that failure without reviving the closed renderer or losing it.
      problem ||= error; failures.push(error);
      if (!closed) interrupt('timed_boundary_not_saved', 'interrupted', error);
    });
  }
  function tick(raw) {
    frame = null;
    if (closed || interrupted || !['waiting_frame', 'presenting'].includes(phase)) return;
    try {
      need(finite(raw) && raw >= 0, 'timed_clock', 'The original animation-frame clock is unavailable.');
      if (document.hidden || !document.hasFocus()) {interrupt('timed_step_without_window_focus'); return;}
      const fence = eventClockFence();
      if (closed || interrupted || !['waiting_frame', 'presenting'].includes(phase)) return;
      need(finite(fence) && fence >= 0, 'timed_clock', 'Keep the host-wide sampled event clock fence.');
      if (raw < fence) {
        if (phase === 'waiting_frame') {frame = win.requestAnimationFrame(tick); return;}
        interrupt('timed_event_clock_conflict'); return;
      }
      const sampled = frameClock(raw);
      if (closed || interrupted || !['waiting_frame', 'presenting'].includes(phase)) return;
      const clock = checkClock(sampled);
      need(clock.value === raw.toFixed(6), 'timed_clock', 'Retain the actual frame timestamp without clamping or substitution.');
      if (!current) begin(0, clock);
      else {
        const value = Number(clock.value);
        need(value >= current.onset && (current.previous === null || raw >= current.previous),
          'timed_clock', 'The observed frame clock moved backwards.');
        // Legacy convention: count only ticks after onset; max gap excludes
        // onset-to-first-tick and retains raw rAF differences. Elapsed uses the
        // original serialized event clocks, matching the durable arm documents.
        if (current.previous !== null) current.maxGap = Math.max(current.maxGap, raw - current.previous);
        current.previous = raw; current.frames++;
        if (value - current.onset >= current.step.duration_ms) {
          finishStep(clock);
          if (!closed && !interrupted && phase === 'presenting') {
            if (index + 1 < steps.length) begin(index + 1, clock);
            else {boundary(); return;}
          }
        }
      }
      if (!closed && !interrupted && phase === 'presenting') frame = win.requestAnimationFrame(tick);
    } catch (error) {
      problem ||= error; failures.push(error);
      interrupt('timed_presentation_failed', 'interrupted', error);
    }
  }
  function start() {
    need(!closed && phase === 'prepared', 'timed_replay', 'A durably armed sequence may be presented only once.');
    // Host has already committed the arm and transferred all environment ownership.
    phase = 'waiting_frame'; claimEnvironment();
    if (document.hidden || !document.hasFocus()) interrupt('timed_step_started_without_window_focus');
    else frame = win.requestAnimationFrame(tick);
    return state();
  }
  function close() {
    if (!closing) {
      if (['waiting_frame', 'presenting', 'stopped'].includes(phase)) interrupt('timed_owner_closed');
      halt(); closed = true; phase = 'closed';
      for (const remove of nativeListeners) remove(); nativeListeners.length = 0; shell.remove();
      // Prepared handles remain the host provider's property; do not revoke
      // another sequence's URLs or erase media/journal retry custody.
      // Capture can call close synchronously before returning its durability.
      // Join after that stack returns and track() registers the original write.
      closing = Promise.resolve().then(drainCaptured); closing.catch(() => {});
    }
    return closing;
  }
  return Object.freeze({start, interrupt, stopPresentation, close, state,
    unownedBoundaryRecords: () => Object.freeze(originals(unownedBoundaries)),
    unownedMediaRecords: () => Object.freeze(originals(unownedMedia))});
}
