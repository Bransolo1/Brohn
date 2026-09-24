/* Browser observation and durable delivery; scientific/domain validation remains in R. */
(() => {
  "use strict";
  const $ = id => document.getElementById(id);
  const content = $("content"), status = $("save-status"), errorBox = $("error");
  const token = new URL(location.href).searchParams.get("token") || new URL(location.href).searchParams.get("study");
  const uid = () => crypto.randomUUID ? crypto.randomUUID() : "id-" + Array.from(crypto.getRandomValues(new Uint8Array(16)), n => n.toString(16).padStart(2, "0")).join("");
  const segmentId = uid();
  let db, entry, record, busy = false, syncing = false, finished = false, interrupted = false;
  let taskController = null, taskExecution = null, taskStop = null;
  let choiceController = null;
  let cameraController = null, cameraReady = false, endingRequested = false;
  let equipmentAbort = null, equipmentInputsReady = false, equipmentPanelStop = null, equipmentTimer = null;
  const equipmentPending = new Map();
  let activeStep = null, onset = null, resumedStep = false, frameHandle = null, activeMedia = null;
  let writeChain = Promise.resolve(), timer = null, releaseLock = null;
  let syncTask = null, revisionController = null, revisionBusy = false, revisionView = null;
  let revisionNotice = "";
  const preparedMedia = new Map();
  let questionIllustrations = null, illustrationLoading = false, illustrationAbort = null;
  const hasChoiceIllustrations = () => record?.protocol?.design?.maxdiff?.some(e=>e.items.some(i=>Object.hasOwn(i,"illustration")));
  const hasQuestionIllustrations = () => record?.protocol?.design?.questions?.some(q => Object.hasOwn(q, "illustration")) || hasChoiceIllustrations();
  function appendQuestionIllustration(parent, step, compact = false) {
    if (!step.question?.illustration) return;
    if (!questionIllustrations) throw new Error("Prepare the saved question images before continuing.");
    const image = questionIllustrations.node(step, compact);
    if (!image) throw new Error("The exact question image is unavailable.");
    parent.append(image);
  }
  async function prepareQuestionIllustrations(retry) {
    if (!hasQuestionIllustrations() || questionIllustrations) return true;
    if (illustrationLoading || endingRequested || record.finish || finished) return false;
    illustrationLoading = true; illustrationAbort = new AbortController();
    screen(hasChoiceIllustrations()?"Preparing study images":"Preparing question images", "Your saved illustrations are being checked before the study continues.");
    try {
      if (!window.BrohnIllustrations) throw new Error("The study image helper is unavailable. Reload this page to try again.");
      const prepared = await BrohnIllustrations.prepare(record.protocol, {signal: illustrationAbort.signal});
      if (endingRequested || record.finish || finished) return false;
      questionIllustrations = prepared; return true;
    } catch (error) {
      if (endingRequested || record.finish || finished) return false;
      screen(hasChoiceIllustrations()?"A study image needs another try":"A question image needs another try", "Your existing session and saved answers are retained. No response has been started by this image check.");
      showError(error); content.append(button(hasChoiceIllustrations()?"Retry study images":"Retry question images", retry, true)); return false;
    } finally {illustrationLoading = false;}
  }
  const node = (tag, text, attrs = {}) => {
    const element = document.createElement(tag);
    if (text !== null && text !== undefined) element.textContent = text;
    for (const [key, value] of Object.entries(attrs)) {
      if (value !== null && value !== undefined) element.setAttribute(key, String(value));
    }
    return element;
  };
  const button = (text, handler, primary = false) => {
    const element = node("button", text, {type: "button", class: primary ? "primary" : "secondary"});
    element.addEventListener("click", () => Promise.resolve(handler()).catch(showError));
    return element;
  };
  function showError(error) {
    errorBox.replaceChildren(node("p", typeof error === "string" ? error : error.message || "The study could not continue. Please contact your researcher."));
    errorBox.hidden = false;
  }
  function clearError() { errorBox.hidden = true; errorBox.replaceChildren(); }
  function screen(title, text = null) {
    document.body.classList.remove("timed");
    clearError(); content.replaceChildren(node("h1", title));
    if (text) content.append(node("p", text));
    content.focus();
  }
  function applyAppearance(appearance) {
    for (const [property, value] of [["--participant-bg", appearance?.background], ["--participant-fg", appearance?.foreground]]) {
      if (!/^#[a-f\d]{6}$/i.test(value || "")) throw new Error("The study appearance is incomplete. Please contact your researcher.");
      document.documentElement.style.setProperty(property, value);
    }
  }
  function transaction(mode, action) {
    return new Promise((resolve, reject) => {
      const tx = db.transaction("sessions", mode), store = tx.objectStore("sessions");
      let result;
      try { result = action(store); } catch (error) { reject(error); return; }
      tx.oncomplete = () => resolve(result?.result);
      tx.onerror = () => reject(new Error("This browser could not safely save your progress. Free some storage or contact your researcher."));
      tx.onabort = tx.onerror;
    });
  }
  function persist(change = () => {}) {
    const task = writeChain.then(async () => {
      const previous = record;
      let candidate;
      try {
        record = structuredClone(previous);
        change();
        candidate = record;
      } finally {
        // Async delivery may read the session while IndexedDB is committing.
        // Keep unsaved events/cursors private until the transaction succeeds.
        record = previous;
      }
      // IndexedDB clones the candidate synchronously in put(). A failed write
      // leaves both the stored session and its in-memory cursor unchanged.
      await transaction("readwrite", store => store.put(candidate));
      record = candidate;
    });
    writeChain = task.catch(() => {});
    return task;
  }
  async function openDatabase() {
    if (!window.indexedDB) throw new Error("This browser does not support saved study progress. Please use a current browser or contact your researcher.");
    db = await new Promise((resolve, reject) => {
      const request = indexedDB.open("brohn-participant", 1);
      request.onupgradeneeded = () => request.result.createObjectStore("sessions", {keyPath: "token"});
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(new Error("Saved progress is unavailable in this browser. Please allow site storage before starting."));
    });
    record = await transaction("readonly", store => store.get(token));
  }
  async function acquireLock() {
    if (!navigator.locks) throw new Error("This browser context cannot protect your study from opening in two tabs. Use an HTTPS study link or this computer's localhost link in a current browser.");
    return new Promise(resolve => {
      navigator.locks.request(`brohn-study-${token}`, {ifAvailable: true}, lock => {
        if (!lock) { resolve(false); return; }
        resolve(true);
        return new Promise(release => { releaseLock = release; });
      }).catch(error => { showError(error); resolve(false); });
    });
  }
  async function api(path, body = undefined, auth = true) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    try {
      const headers = {Accept: "application/json"};
      if (body !== undefined) headers["Content-Type"] = "application/json";
      if (auth && record?.access_token) headers.Authorization = `Bearer ${record.access_token}`;
      const response = await fetch(path, {method: body === undefined ? "GET" : "POST", headers,
        ...(body === undefined ? {} : {body: JSON.stringify(body)}), signal: controller.signal,
        cache: "no-store", credentials: "omit", referrerPolicy: "no-referrer"});
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        const message = typeof data.error?.message === "string" ? data.error.message :
          typeof data.error === "string" ? data.error : typeof data.message === "string" ? data.message :
          `Study service returned ${response.status}. Please contact your researcher.`;
        const error = new Error(message.slice(0, 400));
        error.code = data.error?.code;
        error.permanent = response.status >= 400 && response.status < 500 && response.status !== 408 && response.status !== 429;
        if (error.code === "researcher_resolved" && record?.run_id) await researcherResolved(null);
        if (["upload_expired", "run_revoked", "run_access"].includes(error.code) && record?.run_id) await hostedAccessEnded(error.code, message);
        throw error;
      }
      return data;
    } catch (error) {
      if (error.name === "AbortError") throw new Error("The connection timed out. Your progress is saved on this browser; retry when the connection is available.");
      throw error;
    } finally { clearTimeout(timeout); }
  }
  const answered = value => value !== null && value !== undefined &&
    (!Array.isArray(value) || value.length > 0) &&
    (typeof value !== "object" || Array.isArray(value) || Object.keys(value).length > 0) &&
    (typeof value !== "string" || value.length > 0) &&
    (!Array.isArray(value) || !value.every(item => typeof item === "string" && item.length === 0));
  async function researcherResolved(summary) {
    finished = true; endingRequested = true;
    clearTimeout(timer); clearInterval(equipmentTimer);
    illustrationAbort?.abort(); equipmentAbort?.abort(); taskController?.abort();
    equipmentPanelStop?.(); equipmentPanelStop = null;
    stopPresentation(); cameraController?.closeDelivery();
    await persist(() => {record.delivery_blocked = true; record.researcher_resolution = summary || {resolved: true};});
    $("withdraw").hidden = true;
    const cameraStatus = $("camera-status");
    if (cameraStatus && !cameraStatus.hidden) cameraStatus.textContent = "Recording stopped. Unsent local recording data are retained.";
    screen("The researcher has closed this session",
      "The decision uses evidence already received by the study service. It does not confirm receipt of unsent responses or recordings. Your local saved data remain in this browser.");
    content.append(node("p", "Contact your researcher before clearing browser storage. This session cannot collect further responses."));
    if (summary?.participant_ending) content.append(node("p", `Received participant ending: ${summary.participant_ending}. The original receipt and researcher decision remain separate.`));
    status.textContent = "Session resolved by the researcher; local data retained.";
  }
  async function hostedAccessEnded(code, message) {
    finished = true; endingRequested = true;
    clearTimeout(timer); clearInterval(equipmentTimer);
    illustrationAbort?.abort(); equipmentAbort?.abort(); taskController?.abort();
    equipmentPanelStop?.(); equipmentPanelStop = null;
    stopPresentation(); cameraController?.closeDelivery();
    await persist(() => {record.delivery_blocked = true; record.hosted_access = {code, message};});
    $("withdraw").hidden = true;
    const cameraStatus = $("camera-status");
    if (cameraStatus && !cameraStatus.hidden) cameraStatus.textContent = "Recording stopped. Unsent local recording data are retained.";
    screen("This session can no longer send data", message);
    content.append(node("p", "Your saved responses and recordings remain in this browser. This does not confirm delivery. Contact your researcher before clearing browser storage."));
    status.textContent = "Session access ended; local data retained.";
  }
  const equal = (a, b) => {
    if (typeof a === "number" && typeof b === "number") return a === b;
    if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every((value, index) => equal(value, b[index]));
    if (a && b && typeof a === "object" && typeof b === "object") {
      const keys = Object.keys(a).sort(); return equal(keys, Object.keys(b).sort()) && keys.every(key => equal(a[key], b[key]));
    }
    return a === b;
  };
  function ruleMatches(rule, answers) {
    if (!rule) return true;
    if (rule.op === "and") return rule.rules.every(child => ruleMatches(child, answers));
    if (rule.op === "or") return rule.rules.some(child => ruleMatches(child, answers));
    if (rule.op === "not") return !ruleMatches(rule.rule, answers);
    const value = answers[rule.question_id];
    if (rule.op === "answered") return answered(value);
    if (!answered(value)) return false;
    if (rule.op === "equals") return equal(value, rule.value);
    if (rule.op === "not_equals") return !equal(value, rule.value);
    if (rule.op === "contains") {
      const flattened = Array.isArray(value) ? value.flat(Infinity) : value && typeof value === "object" ? Object.values(value).flat(Infinity) : [value];
      return flattened.some(item => equal(item, rule.value));
    }
    if (rule.op === "greater") return typeof value === "number" && typeof rule.value === "number" && value > rule.value;
    if (rule.op === "less") return typeof value === "number" && typeof rule.value === "number" && value < rule.value;
    throw new Error("This study uses unsupported question logic.");
  }
  function answersFor(step) {
    return {...record.answers.global, ...(step.stimulus_id ? record.answers.stimuli[step.stimulus_id] || {} : {})};
  }
  function makeEvent(type, payload = {}, step = activeStep, when = performance.now()) {
    if (!Number.isFinite(when) || when < 0) throw new Error("The browser clock is unavailable.");
    return {sequence: record.next_sequence++, id: uid(), type,
      step_id: step?.id || null, stimulus_id: step?.stimulus_id || null,
      condition_id: step?.condition_id || null, question_id: step?.question?.id || null,
      phase: step?.phase || "session", clock: {id: "browser-monotonic", unit: "ms", value: when.toFixed(6),
        instance_id: segmentId, time_origin_ms: performance.timeOrigin.toFixed(3)},
      payload: {...payload, clock_segment_id: segmentId, time_origin_ms: performance.timeOrigin.toFixed(3)}};
  }
  async function event(type, payload = {}, step = activeStep, when = performance.now()) {
    if (!record?.run_id || finished) return;
    await persist(() => { record.events.push(makeEvent(type, payload, step, when)); });
    void sync();
  }
  function pendingCount() { return record?.events?.filter(item => item.sequence > record.acked_sequence).length || 0; }
  async function emitEquipment(kind, evidence) {
    const requirements=record.protocol.equipment;
    let sequence=equipmentPending.get(kind);
    if(!sequence){
      await persist(()=>{const item=makeEvent("equipment_event",{},null);item.phase="equipment_setup";
        item.payload={schema:"brohn-participant-equipment-check/1.0",policy_hash:requirements.policy_hash,kind,attempt_id:uid(),evidence};
        record.events.push(item);sequence=item.sequence;});equipmentPending.set(kind,sequence);
    }
    await sync();
    if(!record || record.acked_sequence<sequence)throw new Error("The equipment check is saved in this browser. Retry when the study service can confirm receipt.");
  }
  function camera() {
    if (!record?.protocol?.design?.camera) return null;
    if (!window.BrohnCamera) throw new Error("The study's camera module is unavailable. Contact your researcher before starting.");
    if (!cameraController || cameraController.runId !== record.run_id) cameraController = new BrohnCamera({
      policy: record.protocol.design.camera, runId: record.run_id, api, instanceId: segmentId, timeOrigin: performance.timeOrigin,
      getStep: () => activeStep, monitor: record.protocol.equipment?.camera === true,
      onFailure: error => {showError(error); void finish("interrupted", error.message).catch(showError);}
    });
    return cameraController;
  }
  async function enterStudy(resumed = false) {
    if (!await prepareQuestionIllustrations(() => enterStudy(resumed))) return;
    if (endingRequested || record.finish || finished) return;
    const requirements=record.protocol.equipment;
    if(requirements){
      if(!window.BrohnEquipment)throw new Error("This release's equipment checks are unavailable.");
      equipmentAbort ||= new AbortController(); $("withdraw").hidden=false;
      if(!equipmentInputsReady){
        try{await BrohnEquipment.inputs({container:content,requirements,emit:emitEquipment,signal:equipmentAbort.signal});equipmentInputsReady=true;}
        catch(error){if(!endingRequested&&!record.finish){showError(error);content.append(button("Retry equipment checks",()=>enterStudy(resumed),true));}return;}
      }
      if(cameraReady&&requirements.camera&&cameraController?.segment?.start_request.consented===false)
        await emitEquipment("camera_declined",{capture_id:cameraController.segment.capture_id});
    }
    const recorder = camera();
    if (!recorder || cameraReady) {await present(resumed); return;}
    const policy = record.protocol.design.camera;
    screen("Camera setup", policy.consent_text);
    content.append(node("p", policy.retention_text), node("p", `This study requests ${policy.audio ? "camera and microphone" : "camera without microphone"} recording, up to ${policy.width} by ${policy.height} pixels and ${policy.frame_rate} frames per second.`, {class: "hint"}));
    const agreement = node("input", null, {type: "checkbox", id: "camera-agreement"}), label = node("label", null, {for: "camera-agreement", class: "choice"});
    label.append(agreement, node("span", `I agree to the ${policy.audio ? "camera and microphone" : "camera"} recording described above.`)); content.append(label);
    const video = node("video", null, {id: "camera-preview", muted: "", playsinline: "", "aria-label": "Camera positioning preview", style: "display:block;max-width:100%;width:480px;border-radius:12px"});
    let preparing = false, decision = null, declineButton = null;
    const setupActive = () => !cameraReady && !endingRequested && !record.finish && !finished;
    const enable = button("Enable camera", async () => {
      if (preparing || decision || !setupActive()) return;
      if (!agreement.checked) {showError("Confirm your agreement before enabling the camera."); agreement.focus(); return;}
      preparing = true; enable.disabled = true; clearError();
      try {
        await recorder.prepare(video);
        if (!setupActive() || decision) {recorder.releaseTracks(); return;}
        content.append(video);
        const recordingHint=node("p", requirements?.camera ? "Position yourself comfortably. Recording has not started. Start recording and continue saves this setup lead-in as part of the same study recording." : "Position yourself comfortably. Recording begins when you choose Begin study.");content.append(recordingHint);
        if(requirements?.camera)equipmentPanelStop=BrohnEquipment.panel(content,recorder,requirements);
        let checking=false;
        const begin = button(requirements?.camera?"Start recording and continue":"Begin study", async () => {
          if (!setupActive() || checking || decision === "decline") return;
          checking=true;
          decision = "record"; begin.disabled = true; if (declineButton) declineButton.disabled = true;
          try {
            if(!recorder.recorder)await recorder.start();
            if(requirements?.camera)recordingHint.textContent="Recording has started. This setup lead-in is retained in the same study recording. Checking current input and saved-byte receipts before continuing.";
            if(requirements?.camera){
              const evidence=await BrohnEquipment.firstWrite({controller:recorder,requirements,signal:equipmentAbort.signal});
              await emitEquipment("camera",evidence);
              const current=BrohnEquipment.cameraCheck(recorder.snapshot(),requirements);
              if(!current.video||!current.audio||recorder.recorder?.state!=="recording")
                throw new Error("The saved equipment check is historical. Current camera or microphone input changed while waiting for its receipt. Restore the input and retry the check, or stop.");
            }
            if (!setupActive()) {await recorder.stop("interrupted", "study_ended_during_camera_setup"); return;}
            cameraReady = true; equipmentPanelStop?.();equipmentPanelStop=null;
            // Keep the muted preview decoder available for observed frame metadata.
            // The participant's face is not displayed alongside research stimuli.
            const probe = node("div", null, {id: "camera-frame-probe", "aria-hidden": "true", style: "position:fixed;left:0;top:0;width:1px;height:1px;opacity:0.01;overflow:hidden;pointer-events:none"});
            video.setAttribute("tabindex", "-1"); probe.append(video); document.body.append(probe);
            const indicator = $("camera-status"); if (indicator) {indicator.hidden = false; indicator.textContent = policy.audio ? "Camera and microphone recording" : "Camera recording";}
            if(requirements?.camera&&indicator){
              const update=()=>{const s=recorder.snapshot(),c=BrohnEquipment.cameraCheck(s,requirements);
                const receipt=s.recording.browser_bytes>s.recording.acked_bytes?"newer committed bytes waiting for receipt":c.receiver?"all browser-committed bytes acknowledged":"waiting for first saved bytes";
                const text=`${c.video?"Camera frames observed":"Current camera frame support unavailable"}${requirements.audio?(c.audio?"; audio buffers observed":"; current audio support unavailable"):""}; recorder ${recorder.recorder?.state||"not started"}; ${receipt}.`;
                if(indicator.textContent!==text)indicator.textContent=text;};update();equipmentTimer=setInterval(update,1000);
            }
            await present(resumed);
          } catch (error) {
            if(requirements?.camera&&setupActive()&&!recorder.damaged){showError(error);begin.textContent="Retry recording check";begin.disabled=false;}
            else if(!endingRequested&&!record.finish){await finish("interrupted", error.message);showError(error);}
          } finally {checking=false;}
        }, true);
        content.append(begin); begin.focus();
      } catch (error) {if (setupActive() && !decision) {showError(error); enable.disabled = false;}}
      finally {preparing = false;}
    }, true);
    content.append(enable);
    if (!policy.required) {
      declineButton = button("Continue without camera", async () => {
        if (!setupActive() || decision === "record") return;
        decision = "decline"; declineButton.disabled = true; enable.disabled = true;
        try {
          await recorder.decline("participant_declined");
          if (!setupActive()) return;
          if(requirements?.camera)await emitEquipment("camera_declined",{capture_id:recorder.segment.capture_id});
          cameraReady = true; equipmentPanelStop?.();equipmentPanelStop=null;await present(resumed);
        } finally {if (setupActive()) declineButton.disabled = false;}
      });
      content.append(declineButton);
    }
    else content.append(node("p", "Camera recording is required for this study. If you cannot or do not wish to enable it, choose Stop study.", {class: "hint"}));
    $("withdraw").hidden = false; status.textContent = "Camera permission and setup happen before the study's timed steps.";
  }
  function setSaveStatus() {
    if (!record?.run_id || finished) return;
    status.textContent = pendingCount() ? "Responses saved in this browser. Waiting for the study service to confirm receipt." : "Responses received by the study service.";
  }
  function sync() {
    if (syncTask) return syncTask;
    syncTask = syncOnce().finally(() => {syncTask = null;});
    return syncTask;
  }
  async function syncOnce() {
    if (syncing || finished || !record?.run_id || record.delivery_blocked) return;
    syncing = true; clearTimeout(timer); setSaveStatus();
    try {
      while (pendingCount()) {
        if (!record.batch) {
          await persist(() => {
            const events = record.events.filter(item => item.sequence > record.acked_sequence).slice(0, 100);
            record.batch = {operation_id: uid(), first: events[0].sequence, last: events.at(-1).sequence};
          });
        }
        const batch = record.batch;
        const result = await api(`/api/events/${encodeURIComponent(record.run_id)}`, {
          operation_id: batch.operation_id,
          events: record.events.filter(item => item.sequence >= batch.first && item.sequence <= batch.last)});
        if (!Number.isSafeInteger(result.acked_sequence) || result.acked_sequence < batch.last || result.acked_sequence >= record.next_sequence) {
          throw new Error("The study service returned an inconsistent receipt. Your local responses have been retained.");
        }
        const model = hasRevision() ? await revisionPacket(result.questionnaire, result.acked_sequence) : null;
        await persist(() => {
          record.acked_sequence = result.acked_sequence; record.batch = null;
          if (model) saveRevisionModel(model);
        });
      }
      setSaveStatus();
      if (record.finish) {
        const recorder = camera();
        if (recorder) {
          await recorder.flush();
          if (recorder.segment?.finish_request && !recorder.segment.receipt) await recorder.flush();
          if (recorder.segment?.finish_request && !recorder.segment.receipt) throw new Error("The camera recording is still waiting for its final receipt. Your study progress remains saved.");
        }
        const receipt = await api(`/api/finish/${encodeURIComponent(record.run_id)}`, record.finish);
        if (receipt.status !== "saved" || receipt.outcome !== record.finish.outcome) throw new Error("The study service has not confirmed the final study receipt.");
        const debrief = record.protocol.design.debrief, outcome = record.finish.outcome;
        if (recorder) await recorder.purge();
        await writeChain; await transaction("readwrite", store => store.delete(token));
        finished = true; record = null; $("withdraw").hidden = true;
        screen(outcome === "completed" ? "Thank you. Your responses are saved." : outcome === "withdrawn" ? "You have stopped the study." : "The study was interrupted.", debrief);
        if (outcome !== "completed") content.append(node("p", outcome === "interrupted" ? "Your partial session has been saved as interrupted. It will not be treated as a completed study." : "Your partial session has been marked as withdrawn. Contact the researcher for any request about retaining or deleting your responses."));
        status.textContent = "Final receipt confirmed by the study service.";
        content.append(button("Start a new participant session", () => location.reload()));
      }
    } catch (error) {
      if (record?.researcher_resolution || record?.hosted_access) return;
      status.textContent = "Saved in this browser. Delivery to the study service is still pending.";
      if (error.permanent) { await persist(() => { record.delivery_blocked = true; }); showError(error); }
      else timer = setTimeout(() => void sync(), 4000);
    } finally {
      syncing = false;
      if (record?.revision?.pending && record.acked_sequence >= record.revision.pending.sequence && !revisionBusy && !endingRequested && (!hasQuestionIllustrations() || questionIllustrations))
        setTimeout(() => void continueRevision().catch(showError), 0);
    }
  }
  function stopPresentation(keepTimed = false) {
    revisionView = null;
    choiceController?.dispose(); choiceController = null;
    if (frameHandle !== null) cancelAnimationFrame(frameHandle);
    frameHandle = null; activeMedia?.pause(); activeMedia = null;
    if (!keepTimed) document.body.classList.remove("timed");
  }
  async function finish(outcome, reason = null) {
    if (finished || !record?.run_id || record.finish || endingRequested) return;
    if (taskExecution) {
      // Let the task retain its partial trial/interruption before the run ending.
      taskStop = {outcome, reason}; taskController?.abort(); return;
    }
    endingRequested = true; interrupted = outcome !== "completed"; illustrationAbort?.abort(); equipmentAbort?.abort();
    equipmentPanelStop?.(); equipmentPanelStop=null;clearInterval(equipmentTimer);stopPresentation();
    try {
      if (cameraController) await cameraController.stop(outcome, reason);
      if (cameraController?.damaged && outcome === "completed") {outcome = "interrupted"; interrupted = true; reason = reason || "camera_recording_incomplete";}
    } catch (error) {endingRequested = false; throw error;}
    const cameraStatus = $("camera-status"); if (cameraStatus && !cameraStatus.hidden) cameraStatus.textContent = "Camera stopped; saving recording";
    try {
      await persist(() => {
        record.events.push(makeEvent(outcome === "withdrawn" ? "withdrawal" : "run_finished", {outcome, reason}));
        record.finish = {outcome, final_sequence: record.next_sequence - 1, operation_id: uid()};
        record.step_state = "finishing";
      });
    } catch (error) {endingRequested = false; throw error;}
    $("withdraw").hidden = true;
    screen(outcome === "completed" ? "Saving your responses" : "Saving your partial session",
      outcome === "interrupted" ? "A timed part of the study was interrupted. It cannot be replayed as though the interruption had not occurred." : "Please keep this page open until the study service confirms receipt.");
    content.append(button("Retry saving", async () => { if (record) await persist(() => { record.delivery_blocked = false; }); await sync(); }));
    void sync();
  }
  async function withdraw() {
    if (!record?.run_id || record.finish) return;
    if (["timed", "task"].includes(record.step_state)) return finish("withdrawn", "participant_stopped_timed_step");
    if (window.confirm("Stop this study? Your partial session will be marked as withdrawn.")) await finish("withdrawn", "participant_requested");
  }
  function currentValue(step) { return record.drafts[step.id] === undefined ? null : record.drafts[step.id]; }
  function saveDraft(step, value) { void persist(() => { record.drafts[step.id] = value; }).catch(showError); }
  function questionFields(step, options = {}) {
    const q = step.question, box = node("div"), current = Object.hasOwn(options, "value") ? options.value : currentValue(step), fields = [];
    const save = value => options.onDraft ? options.onDraft(value) : saveDraft(step, value);
    let read = () => null;
    const choices = (name, selected, multiple = false, legend = null) => {
      const set = node("fieldset"), layout = node("div", null, {class: q.type === "rating" ? "rating" : "choices"});
      if (legend) set.append(node("legend", legend)); else set.setAttribute("aria-labelledby", "question-prompt");
      q.options.forEach((option, index) => {
        const input = node("input", null, {type: multiple ? "checkbox" : "radio", name, id: `${name}-${index}`, value: option.id});
        input.checked = multiple ? (selected || []).some(value => equal(value, option.value)) : equal(selected, option.value);
        fields.push(input);
        layout.append(Object.assign(node("label", null, {class: "choice", for: input.id}), {}));
        layout.lastChild.append(input, node("span", option.label));
      });
      set.append(layout); return set;
    };
    if (["rating", "single_choice", "multiple_choice"].includes(q.type)) {
      box.append(choices("answer", current, q.type === "multiple_choice"));
      read = () => q.type === "multiple_choice" ? q.options.filter((_, i) => fields[i].checked).map(option => option.value) : q.options[fields.findIndex(field => field.checked)]?.value ?? null;
    } else if (q.type === "dropdown") {
      const label = node("label", "Choose an answer", {for: "answer"});
      const select = node("select", null, {id: "answer"}); select.append(node("option", "Select an option", {value: ""}));
      q.options.forEach(option => { const item = node("option", option.label, {value: option.id}); item.selected = equal(current, option.value); select.append(item); });
      box.className = "field"; box.append(label, select); fields.push(select);
      read = () => q.options.find(option => option.id === select.value)?.value ?? null;
    } else if (["text", "long_text", "number", "slider"].includes(q.type)) {
      const numeric = ["number", "slider"].includes(q.type);
      const input = node(q.type === "long_text" ? "textarea" : "input", null,
        {id: "answer", ...(q.type === "long_text" ? {rows: 6} : {type: q.type === "slider" ? "range" : q.type === "number" ? "number" : "text"}),
          ...(numeric ? {min: q.min, max: q.max, step: q.step} : {maxlength: 20000}), autocomplete: "off"});
      let touched = current !== null;
      if (current !== null) input.value = current;
      if (q.type === "slider" && current === null) input.value = q.min;
      const output = node("output", current === null ? "Move the slider to choose a value." : String(current), {for: "answer", id: "slider-value"});
      box.className = "field"; box.append(node("label", q.type === "slider" ? `Choose a value from ${q.min} to ${q.max}` : "Your answer", {for: "answer"}), input);
      if (q.type === "slider") {
        box.append(output); input.setAttribute("aria-describedby", "slider-value");
        input.addEventListener("input", () => { touched = true; output.textContent = input.value; });
        box.append(button("Confirm slider value", () => { touched = true; output.textContent = input.value; save(Number(input.value)); }));
      }
      fields.push(input);
      read = () => numeric ? ((q.type === "slider" && !touched) || input.value === "" ? null : Number(input.value)) : input.value;
    } else if (q.type === "matrix") {
      q.rows.forEach(row => { const group = choices(`row-${row.id}`, current?.[row.id] ?? null, false, row.label); group.className = "matrix-row"; box.append(group); });
      read = () => {
        const values = Object.fromEntries(q.rows.map((row, r) => [row.id,
          q.options[fields.slice(r * q.options.length, (r + 1) * q.options.length).findIndex(input => input.checked)]?.value ?? null]));
        return Object.values(values).every(value => value === null) ? null : values;
      };
    } else if (q.type === "ranking") {
      let order = Array.isArray(current) ? current.slice() : q.options.map(option => option.id);
      let confirmed = current !== null;
      const list = node("ol", null, {class: "ranking-list"});
      const render = focusId => {
        list.replaceChildren();
        order.forEach((id, index) => {
          const option = q.options.find(item => item.id === id), item = node("li", null, {class: "ranking-item"});
          item.append(node("span", `${index + 1}. ${option.label}`, {class: "ranking-label"}));
          for (const [offset, label] of [[-1, "Move up"], [1, "Move down"]]) {
            const move = button(label, () => {
              const next = index + offset;
              if (next < 0 || next >= order.length) return;
              [order[index], order[next]] = [order[next], order[index]];
              confirmed = true; save(order.slice()); render(`${id}-${offset}`);
            });
            move.id = `${id}-${offset}`; move.setAttribute("aria-label", `${label}: ${option.label}`);
            move.disabled = index + offset < 0 || index + offset >= order.length; item.append(move);
          }
          list.append(item);
        });
        if (focusId) { const target = document.getElementById(focusId); if (target && !target.disabled) target.focus(); else list.querySelector("button:not(:disabled)")?.focus(); }
      };
      box.append(node("p", "Use Move up and Move down to put the options in your preferred order. Select Confirm this order when it is correct.", {class: "hint"}), list);
      box.append(button("Confirm this order", () => { confirmed = true; save(order.slice()); status.textContent = "Order confirmed. Select Continue to submit it."; }));
      render(); read = () => confirmed ? order.slice() : null;
    } else if (q.type === "allocation") {
      const total = node("p", null, {class: "allocation-total", role: "status", "aria-live": "polite"});
      q.options.forEach(option => {
        const row = node("div", null, {class: "allocation-row"}), input = node("input", null, {type: "number", id: `allocation-${option.id}`, min: 0, max: q.max, step: q.step});
        input.value = current?.[option.id] ?? ""; fields.push(input);
        row.append(node("label", option.label, {for: input.id}), input); box.append(row);
      });
      read = () => {
        const values = Object.fromEntries(q.options.map((option, i) => [option.id, fields[i].value === "" ? null : Number(fields[i].value)]));
        return Object.values(values).every(value => value === null) ? null : values;
      };
      const showTotal = () => { total.textContent = `${fields.reduce((sum, field) => sum + (Number(field.value) || 0), 0)} of ${q.max} allocated`; };
      fields.forEach(field => field.addEventListener("input", showTotal)); showTotal(); box.append(total);
    } else if (q.type !== "information") throw new Error("This study contains an unsupported question type.");
    for (const field of fields) {
      field.addEventListener("input", () => save(read()));
      field.addEventListener("change", () => save(read()));
    }
    return {box, read, fields};
  }
  function validate(q, value, fields) {
    if (q.type === "information") return null;
    const empty = !answered(value) || (typeof value === "string" && !value.trim());
    if (empty) return q.required ? "Please answer this question before continuing." : null;
    if (fields.some(field => !field.checkValidity())) return "Please enter a value within the displayed range and step.";
    if (["number", "slider"].includes(q.type) && (!Number.isFinite(value) || value < q.min || value > q.max)) return `Enter a value from ${q.min} to ${q.max}.`;
    if (q.type === "matrix" && q.required && q.rows.some(row => !answered(value[row.id]))) return "Please answer every row before continuing.";
    if (q.type === "allocation") {
      const values = Object.values(value);
      if (values.some(item => item === null || !Number.isFinite(item) || item < 0)) return "Enter an amount for every option, including zero where appropriate.";
      if (Math.abs(values.reduce((a, b) => a + b, 0) - q.max) > 1e-7) return `Allocate exactly ${q.max} in total before continuing.`;
    }
    return null;
  }
  const hasRevision = () => Boolean(record?.protocol?.design?.questionnaire_navigation);
  const revisionActive = () => record?.run_id && !record.finish && !finished && !interrupted && !endingRequested;
  function revision() {
    if (!window.BrohnQuestionRevision?.create) throw new Error("This study's answer review module is unavailable. Your progress has been retained.");
    if (!revisionController) revisionController = window.BrohnQuestionRevision.create(record.protocol, record.protocol_hash);
    return revisionController;
  }
  async function revisionPacket(packet, acknowledgedSequence) {
    revision().validate(packet, {acknowledgedSequence, offset: 0});
    return revision().pages(packet, (offset, state_hash) => api(`/api/questionnaire_state/${encodeURIComponent(record.run_id)}`, {offset, state_hash}));
  }
  // Called only inside the same IndexedDB transaction as the corresponding ACK.
  function saveRevisionModel(model) {
    record.revision ||= {drafts: {}, pending: null, model: null};
    record.revision.model = model;
    record.revision.drafts = revision().reconcileDrafts(model, record.revision.drafts);
  }
  async function flushRevision() {
    await writeChain;
    const through = record.next_sequence - 1;
    await sync();
    if (!revisionActive()) return false;
    if (record.acked_sequence < through) throw new Error("Your change is saved in this browser and is waiting for confirmation. Keep this page open or retry when the connection returns.");
    return true;
  }
  async function fetchRevisionState() {
    if (!await flushRevision()) return false;
    const packet = await api(`/api/questionnaire_state/${encodeURIComponent(record.run_id)}`, {offset: 0, state_hash: null});
    const model = await revisionPacket(packet, record.acked_sequence);
    await persist(() => {saveRevisionModel(model);});
    return true;
  }
  function freezeRevision(frozen) {
    if (!revisionView) return;
    for (const element of revisionView.container.querySelectorAll("input, textarea, select, button")) {
      if (frozen) {element.dataset.revisionDisabled = element.disabled ? "true" : "false"; element.disabled = true;}
      else if (element.dataset.revisionDisabled !== undefined) {
        element.disabled = element.dataset.revisionDisabled === "true"; delete element.dataset.revisionDisabled;
      }
    }
  }
  function revisionDraft(step, value) {
    const model = record?.revision?.model, row = model?.records.find(row => row.step_id === step.id);
    if (!row || revisionBusy || !revisionActive() || revisionView?.step.id !== step.id) return;
    const draft = {step_id: step.id, occurrence_id: row.occurrence_id, dependency_generation: row.dependency_generation, value};
    void persist(() => {record.revision.drafts[step.id] = draft;}).then(() => {
      if (revisionView?.step.id === step.id && !revisionBusy) status.textContent = "Draft saved in this browser. Continue sends this answer; Back keeps this draft without submitting it.";
    }).catch(showError);
  }
  function readableAnswer(question, row) {
    if (row.information) return row.status === "information_acknowledged" ? "Information acknowledged" : "Not yet acknowledged";
    if (row.status === "optional_omission") return "Skipped (optional)";
    if (row.status !== "answered") return row.status === "invalidated_unanswered" ? "Answer again after your earlier change" : "Not yet answered";
    const value = row.value, label = value => question.options?.find(option => equal(option.value, value))?.label ?? String(value);
    if (question.type === "matrix") return question.rows.map(item => `${item.label}: ${value?.[item.id] === null ? "Not answered" : label(value?.[item.id])}`).join("; ");
    if (question.type === "allocation") return question.options.map(item => `${item.label}: ${value?.[item.id] ?? "Not answered"}`).join("; ");
    if (question.type === "ranking") return value.map((id, i) => `${i + 1}. ${question.options.find(option => option.id === id)?.label || id}`).join("; ");
    if (Array.isArray(value)) return value.map(label).join("; ");
    return question.options ? label(value) : String(value);
  }
  function renderRevision(step, provisional = false) {
    const model = record.revision.model, current = model.packet.latest_occurrence;
    const review = step.type === "questionnaire_review";
    const final = review && record.protocol.timeline.at(-1)?.id === step.id;
    // The delivery cursor stays at occurrence entry until sealing. Describe
    // the displayed questionnaire using its frozen order and server projection.
    const occurrence = revision().occurrence(step.questionnaire_occurrence_id);
    const visibleAnswers = new Set(model.records.filter(row => row.occurrence_id === occurrence.id &&
      row.status !== "not_displayed" && !row.information).map(row => row.step_id));
    const questionSteps = occurrence.question_step_ids.filter(id => visibleAnswers.has(id));
    const position = questionSteps.indexOf(step.id);
    $("study-progress").textContent = review ? (final ? "Final review" : "Answer review") :
      step.question.type === "information" ? "Information in this part" :
      position >= 0 ? `Question ${position + 1} of ${questionSteps.length} in this part` : "Questionnaire";
    activeStep = step; screen(review ? "Review your answers" : step.question.prompt);
    content.dataset.questionnaireStep = step.id;
    content.dataset.questionnaireOccurrence = step.questionnaire_occurrence_id;
    if (revisionNotice) content.append(node("p", revisionNotice, {role: "status", id: "questionnaire-changes", class: "hint"}));
    if (review) {
      content.append(node("p", "Check the answers in this part. You can edit them here. Continuing confirms this part and you cannot return to it."));
      const rows = model.records.filter(row => row.occurrence_id === current.id && row.status !== "not_displayed");
      const list = node("ol", null, {id: "questionnaire-answer-review"});
      for (const row of rows) {
        const source = revision().step(row.step_id), item = node("li", null, {class: "matrix-row"});
        item.append(node("h2", source.question.prompt)); appendQuestionIllustration(item, source, true);
        item.append(node("p", readableAnswer(source.question, row)));
        if (model.packet.actions.editable_step_ids.includes(row.step_id)) {
          const edit = button(row.information ? "Review information" : "Edit answer", () => revisionAction("edit", {target: row.step_id}));
          edit.setAttribute("aria-label", `${row.information ? "Review information" : "Edit"}: ${source.question.prompt}`); item.append(edit);
        }
        list.append(item);
      }
      content.append(list);
      const actions = node("div", null, {class: "actions"});
      if (model.packet.actions.back_step_id) actions.append(button("Back", () => revisionAction("back")));
      const seal = button(final ? "Finish study" : "Continue to the next part", () => revisionAction("seal"), true);
      seal.id = "questionnaire-seal"; seal.disabled = !model.packet.actions.can_seal || provisional; actions.append(seal); content.append(actions);
      revisionView = {step, container: content, read: null};
    } else {
      if (step.questionnaire?.section_label) content.prepend(node("p", step.questionnaire.section_label, {class: "question-meta", id: "question-section"}));
      content.querySelector("h1").id = "question-prompt";
      if (step.questionnaire?.section_label) content.querySelector("h1").setAttribute("aria-describedby", "question-section");
      content.append(node("p", step.question.type === "information" ? "Study information" : step.question.required ? "Required" : "Optional", {class: "question-meta"}));
      const value = revision().draftValue(model, step, record.revision.drafts[step.id]);
      appendQuestionIllustration(content, step);
      const form = node("form", null, {novalidate: "novalidate", id: "questionnaire-answer"});
      const fields = questionFields(step, {value, onDraft: value => revisionDraft(step, value)}); form.append(fields.box);
      const actions = node("div", null, {class: "actions"});
      if (!provisional && model.packet.actions.back_step_id) actions.append(button("Back", () => revisionAction("back", {draft: fields.read()})));
      const next = node("button", "Continue", {type: "submit", class: "primary"}); actions.append(next); form.append(actions);
      form.addEventListener("submit", event => {
        event.preventDefault(); if (revisionBusy) return; clearError();
        const value = fields.read(), message = validate(step.question, value, fields.fields);
        if (message) {showError(message); errorBox.focus(); return;}
        const submitted = !step.question.required && (!answered(value) || typeof value === "string" && !value.trim()) ? null : value;
        void revisionAction("commit", {value: submitted}).catch(showError);
      });
      content.append(form); revisionView = {step, container: content, read: fields.read};
    }
    if (provisional) freezeRevision(true);
    else status.textContent = "Answers received. You can use Back within this part; unsent changes remain local drafts.";
  }
  function pendingRevisionScreen(error = null) {
    if (!revisionActive()) return;
    screen("Saving this change", "Your pending action is saved in this browser. We will continue after the study service confirms it. You can stop the study at any time.");
    revisionView = null;
    const retry = button("Retry saving", () => continueRevision(), true); retry.id = "questionnaire-retry"; content.append(retry);
    if (error) showError(error);
  }
  async function sendRevisionAction(action, options = {}) {
    if (!await flushRevision() || !revisionActive()) return;
    let model = record.revision.model;
    // A committed answer is immutable within its visit. Continue after an ACK
    // or reload moves on without adding a second commit.
    if (action === "commit" && model.packet.latest_occurrence?.visit?.committed) action = "next";
    const visiting = ["enter", "next", "back", "edit", "resume"].includes(action);
    let planned;
    if (visiting) {
      planned = revision().payload(model, action, {...options, visitId: uid()});
      renderRevision(planned.step, true);
    }
    const now = Number(performance.now().toFixed(6));
    const clock = {value: now, instance_id: segmentId, time_origin_ms: performance.timeOrigin.toFixed(3)};
    if (!planned) planned = revision().payload(model, action, {...options, clock});
    await persist(() => {
      if (record.revision.pending) throw new Error("Wait for the preceding change to be confirmed.");
      const event = makeEvent("questionnaire_event", planned.payload, planned.step, now);
      record.events.push(event);
      record.revision.pending = {sequence: event.sequence, action, occurrence_id: planned.payload.occurrence_id,
        step_id: planned.step.id, before: action === "commit" ? model.records.filter(row => row.occurrence_id === planned.payload.occurrence_id &&
          ["answered", "optional_omission", "information_acknowledged"].includes(row.status)).map(row => ({step_id: row.step_id, generation: row.dependency_generation})) : []};
      record.current_step = planned.step.id; record.step_state = "questionnaire_pending";
    });
    await completeRevisionPending();
  }
  async function completeRevisionPending() {
    if (!await flushRevision() || !revisionActive()) return;
    const pending = record.revision.pending;
    if (!pending) return;
    const model = record.revision.model, packet = model.packet;
    if (pending.action === "commit") {
      const changed = pending.before.filter(old => model.records.some(row => row.step_id === old.step_id && row.dependency_generation > old.generation));
      if (changed.length) revisionNotice = `Your changed answer cleared ${changed.length} dependent ${changed.length === 1 ? "answer" : "answers"}. Please answer them again if they appear.`;
    }
    if (pending.action === "seal" && !(packet.last_transition?.occurrence_id === pending.occurrence_id && packet.last_transition.sealed))
      throw new Error("The service has not confirmed this part's final review. Your journal has been retained.");
    await persist(() => {
      record.revision.pending = null;
      if (pending.action === "commit") delete record.revision.drafts[pending.step_id];
      if (pending.action === "seal") {
        record.index = packet.protocol_cursor - 1; record.current_step = null; record.step_state = "between";
        for (const [id, draft] of Object.entries(record.revision.drafts)) if (draft.occurrence_id === pending.occurrence_id) delete record.revision.drafts[id];
      } else record.step_state = packet.latest_occurrence?.visit?.step_id === packet.latest_occurrence?.review_step_id ? "questionnaire_review" : "questionnaire_question";
    });
    if (!revisionActive()) return;
    if (pending.action === "seal") {revisionNotice = ""; revisionView = null; activeStep = null; revisionBusy = false; await present(); return;}
    if (pending.action === "commit") {await sendRevisionAction("next"); return;}
    const visit = packet.latest_occurrence?.visit;
    if (visit?.instance_id !== segmentId) {await sendRevisionAction("resume"); return;}
    renderRevision(revision().step(visit.step_id));
  }
  async function continueRevision() {
    if (revisionBusy || !revisionActive()) return;
    revisionBusy = true; freezeRevision(true);
    try {await completeRevisionPending();}
    catch (error) {pendingRevisionScreen(error);}
    finally {revisionBusy = false;}
  }
  async function revisionAction(action, options = {}) {
    if (revisionBusy || !revisionActive()) return;
    const previousView = revisionView;
    revisionBusy = true; freezeRevision(true); clearError();
    try {
      if (Object.hasOwn(options, "draft") && previousView?.step.type === "question") {
        const row = record.revision.model.records.find(row => row.step_id === previousView.step.id);
        await persist(() => {record.revision.drafts[previousView.step.id] = {step_id: row.step_id, occurrence_id: row.occurrence_id,
          dependency_generation: row.dependency_generation, value: options.draft};});
      }
      await sendRevisionAction(action, options);
    } catch (error) {
      if (record?.revision?.pending) pendingRevisionScreen(error);
      else if (revisionActive()) {
        // Local transaction failure does not move the durable visit or cursor.
        // Keep the actual input nodes when the failed action was a commit.
        if (previousView === revisionView) freezeRevision(false);
        else if (record.revision.model.packet.latest_occurrence?.visit) renderRevision(revision().step(record.revision.model.packet.latest_occurrence.visit.step_id));
        showError(error);
      }
    } finally {revisionBusy = false;}
  }
  async function presentRevision(resume = false) {
    if (!revisionActive()) return;
    if (record.revision?.pending) return continueRevision();
    if (revisionBusy) throw new Error("Wait for the current questionnaire action to finish.");
    revisionBusy = true;
    try {
      if (!await fetchRevisionState() || !revisionActive()) return;
      const packet = record.revision.model.packet;
      if (packet.protocol_cursor - 1 !== record.index) {
        await persist(() => {record.index = packet.protocol_cursor - 1; record.current_step = null; record.step_state = "between";});
        revisionBusy = false; return present(resume);
      }
      const current = packet.latest_occurrence;
      if (!current || current.sealed) throw new Error("The study service did not provide an open questionnaire occurrence at this boundary.");
      if (!current.visit) await sendRevisionAction("enter");
      else if (current.visit.instance_id !== segmentId) await sendRevisionAction("resume");
      else renderRevision(revision().step(current.visit.step_id));
    } catch (error) {
      if (record?.revision?.pending) pendingRevisionScreen(error);
      else if (revisionActive()) {screen("Recovering your saved answers", "Connect to the study service before continuing. Local drafts remain saved."); showError(error); content.append(button("Retry recovery", () => presentRevision(true), true));}
    } finally {revisionBusy = false;}
  }
  async function advance(step, value, extra = {}) {
    if (busy || interrupted || record.finish) return;
    busy = true; const now = performance.now();
    try {
      await persist(() => {
        if (step.type === "question" && step.question.type !== "information") {
          const target = step.stimulus_id ? (record.answers.stimuli[step.stimulus_id] ||= {}) : record.answers.global;
          target[step.question.id] = value;
          record.events.push(makeEvent("response", {value, response_time_ms: resumedStep ? null : now - onset,
            active_segment_response_ms: now - onset, resumed: resumedStep, scope: step.question.scope,
            ...(step.question.type === "ranking" && value ? {option_values: value.map(id => step.question.options.find(option => option.id === id).value)} : {})}, step, now));
        }
        if (step.type === "maxdiff") record.events.push(makeEvent("response", {value,
          response_time_ms: resumedStep ? null : now - onset, active_segment_response_ms: now - onset, resumed: resumedStep}, step, now));
        record.events.push(makeEvent("step_finished", {elapsed_ms: resumedStep ? null : now - onset, resumed: resumedStep, ...extra}, step, now));
        record.index++; record.step_state = "between"; record.current_step = null;
      });
      activeStep = null; void sync();
      choiceController?.dispose(); choiceController = null;
    } finally { busy = false; }
    await present();
  }
  async function showQuestion(step, resume = false) {
    screen(step.question.prompt);
    if (step.questionnaire?.section_label) content.prepend(node("p", step.questionnaire.section_label, {class: "question-meta", id: "question-section"}));
    content.querySelector("h1").id = "question-prompt";
    if (step.questionnaire?.section_label) content.querySelector("h1").setAttribute("aria-describedby", "question-section");
    content.append(node("p", step.question.type === "information" ? "Study information" : step.question.required ? "Required" : "Optional", {class: "question-meta"}));
    appendQuestionIllustration(content, step);
    const form = node("form", null, {novalidate: "novalidate"});
    const fields = questionFields(step); form.append(fields.box);
    const next = node("button", "Continue", {type: "submit", class: "primary"}); form.append(next);
    form.addEventListener("submit", async e => {
      e.preventDefault(); clearError();
      const value = fields.read(), message = validate(step.question, value, fields.fields);
      if (message) { showError(message); errorBox.focus(); return; }
      next.disabled = true;
      try { await advance(step, value); } catch (error) { next.disabled = false; showError(error); }
    });
    content.append(form); onset = performance.now(); resumedStep = resume;
    await event("step_started", {resumed: resume}, step, onset);
  }
  async function showMaxDiff(step, resume = false) {
    if (!window.BrohnMaxDiff?.create) return finish("interrupted", "best_worst_renderer_unavailable");
    screen(step.choice.prompt);
    // The dedicated renderer owns the prompt heading and labelled groups.
    const container = node("div"); content.replaceChildren(container);
    onset = performance.now(); resumedStep = resume;
    await event("step_started", {resumed: resume}, step, onset);
    if (interrupted || record.finish || endingRequested) return;
    choiceController = window.BrohnMaxDiff.create({container, choice: step.choice, draft: currentValue(step),
      illustration:item=>questionIllustrations?.itemNode(step,item),
      onDraft: value => persist(() => {record.drafts[step.id] = value;}), onSubmit: async value => {
        clearError(); if (interrupted || record.finish || endingRequested || activeStep?.id !== step.id) throw new Error("This choice set is no longer active.");
        await advance(step, value);
      }, onError: error => {showError(error); errorBox.focus();}});
  }
  async function readyMedia(stimulus) {
    if (stimulus.type === "text") return node("div", stimulus.content, {class: "text-stimulus"});
    if (!["image", "audio", "video"].includes(stimulus.type)) throw new Error("Web stimuli do not have a supported delivery profile. This session cannot continue. Please contact the researcher.");
    const source = new URL(stimulus.asset?.url || "", location.href);
    if (!stimulus.asset?.url || source.origin !== location.origin || !source.pathname.startsWith("/api/assets/")) throw new Error("The study media address is missing or unsupported.");
    const media = node(stimulus.type === "image" ? "img" : stimulus.type, null, {src: source.href, ...(stimulus.type === "image" ? {alt: stimulus.image_alt ?? "Study image"} : {preload: "auto", playsinline: "playsinline"})});
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("The study media did not load. Your timed trial has not been replayed.")), 30000);
      media.addEventListener(stimulus.type === "image" ? "load" : "canplaythrough", () => { clearTimeout(timeout); resolve(); }, {once: true});
      media.addEventListener("error", () => { clearTimeout(timeout); reject(new Error("The study media could not be opened. Please contact the researcher.")); }, {once: true});
      if (stimulus.type === "image" && media.complete && media.naturalWidth) { clearTimeout(timeout); resolve(); }
      if (stimulus.type !== "image") media.load();
    });
    return media;
  }
  async function preloadTimeline() {
    const steps = record.protocol.timeline.filter(step => step.type === "stimulus");
    const declaredBytes = steps.reduce((total, step) => total + (step.stimulus.asset?.size || 0), 0);
    if (declaredBytes > 512 * 1024 * 1024) throw new Error("This browser study exceeds the supported media preload size. Ask the researcher to use a smaller media set.");
    // Decode before the protocol begins, so baseline/fixation are not interrupted by loading UI.
    let cursor = 0;
    const worker = async () => {
      while (cursor < steps.length) {
        const step = steps[cursor++];
        if (!preparedMedia.has(step.id)) preparedMedia.set(step.id, await readyMedia(step.stimulus));
      }
    };
    await Promise.all(Array.from({length: Math.min(4, steps.length)}, worker));
  }
  async function showTimed(step) {
    let media;
    try {
      media = step.type === "stimulus" ? preparedMedia.get(step.id) : step.type === "fixation" ? node("span", "+", {class: "fixation", "aria-label": "Fixation cross"}) : node("span", "", {"aria-label": "Baseline"});
      if (!media) throw new Error("The study media was not prepared before the timed sequence.");
    }
    catch (error) { await finish("interrupted", error.message); return; }
    if (interrupted || record.finish) return;
    const start = async () => {
      if (document.hidden || !document.hasFocus()) { await finish("interrupted", "timed_step_started_without_window_focus"); return; }
      const stage = node("div", null, {class: "stimulus-stage"}); stage.append(media);
      onset = null;
      await persist(() => { record.step_state = "timed"; });
      let playbackObserved = null;
      if (["audio", "video"].includes(step.stimulus?.type)) {
        activeMedia = media;
        media.currentTime = 0;
        media.addEventListener("playing", () => { playbackObserved = performance.now(); }, {once: true});
        for (const name of ["waiting", "stalled", "error"]) {
          media.addEventListener(name, () => {
            if (activeMedia === media && onset !== null && record?.step_state === "timed" && !record.finish) void finish("interrupted", `media_${name}`).catch(showError);
          }, {once: true});
        }
        try { await media.play(); } catch { await finish("interrupted", "media_playback_blocked"); return; }
      }
      let previous = null, maxFrameGap = 0, frames = 0;
      void new Promise(resolve => {
        frameHandle = requestAnimationFrame(now => {
          if (interrupted || record.finish) { resolve(); return; }
          content.replaceChildren(stage); document.body.classList.add("timed"); onset = now; resumedStep = false;
          const rect = media.getBoundingClientRect();
          void event("step_started", {scheduled_duration_ms: step.duration_ms, timing_reference: "requestAnimationFrame_before_paint",
            viewport: {width: innerWidth, height: innerHeight, device_pixel_ratio: devicePixelRatio},
            stimulus_rect: {x: rect.x, y: rect.y, width: rect.width, height: rect.height},
            media_current_time: activeMedia?.currentTime ?? null, media_playback_observed_ms: playbackObserved}, step, now).catch(error => {
              stopPresentation(); interrupted = true; showError(error);
            });
          const tick = time => {
            if (interrupted || record.finish) { resolve(); return; }
            if (previous !== null) maxFrameGap = Math.max(maxFrameGap, time - previous);
            previous = time; frames++;
            if (time - onset >= step.duration_ms) {
              stopPresentation(true); content.replaceChildren();
              void advance(step, null, {scheduled_duration_ms: step.duration_ms, observed_duration_ms: time - onset, frames, max_frame_gap_ms: maxFrameGap}).catch(showError);
              resolve();
            } else frameHandle = requestAnimationFrame(tick);
          };
          frameHandle = requestAnimationFrame(tick);
        });
      });
    };
    await start();
  }
  async function showTask(step) {
    if (!window.BrohnTasks?.run) return finish("interrupted", "task_renderer_unavailable");
    stopPresentation(); clearError(); onset = performance.now(); resumedStep = false;
    await persist(() => {record.step_state = "task";});
    await event("step_started", {resumed: false, task_id: step.task.id}, step, onset);
    taskController = new AbortController(); taskStop = null;
    try {
      taskExecution = window.BrohnTasks.run({container: content, compiled: step.task, signal: taskController.signal, clockInstanceId: segmentId,
        emit: (kind, data) => event("task_event", {kind, data}, step),
        onCheckpoint: point => persist(() => {record.task_checkpoint = point;})});
      const result = await taskExecution;
      taskExecution = null; taskController = null;
      if (taskStop || result.outcome !== "completed") {
        const ending = taskStop || {outcome: "interrupted", reason: result.reason || "task_interrupted"};
        taskStop = null; return finish(ending.outcome, ending.reason);
      }
      await advance(step, null, {task_outcome: "completed"});
    } catch (error) {
      taskExecution = null; taskController = null; taskStop = null;
      await finish("interrupted", error.message || "task_execution_failed");
    }
  }
  async function present(resume = false) {
    if (!record || record.finish || interrupted) return;
    if (record.index >= record.protocol.timeline.length) { await finish("completed"); return; }
    activeStep = record.protocol.timeline[record.index];
    $("withdraw").hidden = false;
    if (hasRevision() && activeStep.questionnaire_occurrence_id) {
      $("study-progress").textContent = "Questionnaire";
      return presentRevision(resume);
    }
    $("study-progress").textContent = `Part ${record.index + 1} of ${record.protocol.timeline.length}`;
    if (activeStep.type === "question" && !ruleMatches(activeStep.question.show_if, answersFor(activeStep))) {
      const skipped = activeStep;
      await persist(() => {
        record.events.push(makeEvent("step_finished", {skipped: true, reason: "display_logic", elapsed_ms: null}, skipped));
        delete record.drafts[skipped.id]; record.index++; record.step_state = "between"; record.current_step = null;
      });
      return present();
    }
    await persist(() => { record.current_step = activeStep.id; record.step_state = ["question", "maxdiff", "instructions"].includes(activeStep.type) ? activeStep.type : "timed_preparing"; });
    if (activeStep.type === "question") return showQuestion(activeStep, resume);
    if (activeStep.type === "maxdiff") return showMaxDiff(activeStep, resume);
    if (activeStep.type === "task") return showTask(activeStep);
    if (activeStep.type === "instructions") {
      screen("Before you begin", activeStep.text);
      content.append(node("p", "For timed sections, stay in this tab. Press Escape to stop. Changing windows or resizing during a timed screen ends that session as interrupted."));
      onset = performance.now(); resumedStep = resume;
      await event("step_started", {resumed: resume}, activeStep, onset);
      content.append(button("Begin", () => advance(activeStep, null), true)); return;
    }
    if (["baseline", "fixation", "stimulus"].includes(activeStep.type)) return showTimed(activeStep);
    await finish("interrupted", "unsupported_timeline_step");
  }
  async function start(consented, participantAlias = "") {
    if (busy) return; busy = true; clearError();
    try {
      if (!record?.pending_start) {
        record = {token, pending_start: {consented, participant_alias: participantAlias, client_id: uid(), operation_id: uid()}};
        await persist();
      }
      screen("Preparing your session", "Please wait while the study service creates your session.");
      const session = await api(`/api/start/${encodeURIComponent(token)}`, record.pending_start, false);
      if (!session.run_id || !session.access_token || !Array.isArray(session.protocol?.timeline) || !Number.isSafeInteger(session.expected_sequence) || session.expected_sequence < 1) throw new Error("The study service returned an incomplete session. Please contact your researcher.");
      if (session.expected_sequence > 1 && !session.resume) throw new Error("The existing session requires a verified recovery point. Please contact your researcher.");
      const recovery = session.expected_sequence > 1 ? session.resume : null;
      const recoveredIndex = recovery ? (recovery.next_step_id ? session.protocol.timeline.findIndex(step => step.id === recovery.next_step_id) : session.protocol.timeline.length) : 0;
      if (recoveredIndex < 0) throw new Error("The study service returned an unknown recovery point.");
      await persist(() => {
        record = {token, deployment: entry.deployment, run_id: session.run_id, access_token: session.access_token, protocol: session.protocol,
          ...(session.protocol.design.questionnaire_navigation ? {protocol_hash: session.protocol_hash, revision: {drafts: {}, pending: null, model: null}} : {}),
          next_sequence: session.expected_sequence, acked_sequence: session.expected_sequence - 1, events: [],
          answers: recovery ? {global: {...recovery.answers?.before, ...recovery.answers?.end}, stimuli: recovery.answers?.after_each || {}} : {global: {}, stimuli: {}},
          drafts: {}, index: recoveredIndex, step_state: "between", current_step: null, batch: null, finish: null};
      });
      if (hasRevision()) {
        revisionController = null;
        const initial = session.resume?.questionnaire;
        if (initial) {const model = await revisionPacket(initial, record.acked_sequence); await persist(() => {saveRevisionModel(model);});}
        else await fetchRevisionState();
      }
      applyAppearance(record.protocol.design.appearance);
      if (session.researcher_resolution?.resolved) {await researcherResolved(session.researcher_resolution); return;}
      try { await preloadTimeline(); } catch (error) { await finish("interrupted", error.message); return; }
      const recoveringActive = recovery?.active_step_id && record.protocol.timeline.find(step => step.id === recovery.active_step_id);
      if (recoveringActive && ["stimulus", "baseline", "fixation", "task"].includes(recoveringActive.type)) {
        activeStep = recoveringActive; await finish("interrupted", "server_recovery_during_timed_step");
      } else if (recovery) {
        screen("Your existing session can be recovered", "Continue from the study service's saved untimed point. Previously received responses will not be submitted again.");
        content.append(button("Resume this session", () => enterStudy(true), true));
      } else { busy = false; await enterStudy(); }
    } catch (error) { showError(error); content.append(button("Retry session setup", () => start(consented))); }
    finally { busy = false; }
  }
  function welcomeScreen() {
    screen(entry.welcome.title);
    if (!window.BrohnWelcome) throw new Error("The study welcome page could not load. Reload this page or contact your researcher.");
    let source = null;
    if (entry.welcome.asset) {
      const url = new URL(entry.welcome_image_url || "", location.href);
      if (url.origin !== location.origin || !url.pathname.startsWith("/api/assets/")) throw new Error("The study welcome image address is unavailable. Please contact your researcher.");
      source = url.href;
    }
    window.BrohnWelcome.render(content, entry.welcome, {imageSource: source, onContinue: consentScreen,
      onError: showError, onReady: clearError});
    status.textContent = "Your session has not started. Study information and consent follow this welcome page.";
  }
  function consentScreen() {
    screen(entry.consent.title || entry.deployment.title, entry.consent.text);
    const form = node("form", null, {novalidate: "novalidate"}), label = node("label", null, {class: "choice", for: "consent"});
    const input = node("input", null, {type: "checkbox", id: "consent"});
    label.append(input, node("span", "I have read the study information and agree to take part."));
    form.append(label);
    const alias = node("input", null, {type: "text", id: "participant-alias", maxlength: 200,
      autocomplete: "off", "aria-describedby": "participant-alias-help", ...(entry.alias_required ? {required: "required"} : {})});
    const aliasField = node("div", null, {class: "field"});
    aliasField.append(node("label", entry.alias_required ? "Participant alias (required)" : "Participant alias (optional)", {for: "participant-alias"}), alias,
      node("p", "Use the code provided by your researcher. A full name is not needed.", {id: "participant-alias-help", class: "hint"}));
    form.append(aliasField);
    if (!entry.consent.required) form.append(node("p", "Acknowledgement is optional for this study. You can continue without selecting the box.", {class: "hint"}));
    form.append(node("button", "Start study", {type: "submit", class: "primary"}));
    form.addEventListener("submit", async e => {
      e.preventDefault();
      if (entry.consent.required && !input.checked) { showError("Please confirm your agreement before starting, or close this page if you do not wish to take part."); input.focus(); return; }
      const participantAlias = alias.value.trim();
      if (entry.alias_required && !participantAlias) { showError("Enter the participant alias provided by your researcher before starting."); alias.focus(); return; }
      if (new TextEncoder().encode(participantAlias).length > 200) { showError("This participant alias is too long. Use a shorter code from your researcher."); alias.focus(); return; }
      await start(input.checked, participantAlias);
    });
    content.append(form);
    if (entry.welcome) content.append(button("Back to welcome", welcomeScreen));
    status.textContent = "Your session starts only when you choose Start study.";
  }
  async function boot() {
    if (!token || !/^[A-Za-z0-9_-]{16,256}$/.test(token)) throw new Error("This study link is incomplete. Open the full participant link supplied by your researcher.");
    if (!await acquireLock()) throw new Error("This study is already open in another tab. Continue there, or close that tab and reload this one.");
    await openDatabase();
    if (record?.hosted_access) {await hostedAccessEnded(record.hosted_access.code, record.hosted_access.message); return;}
    try { entry = await api(`/api/entry/${encodeURIComponent(token)}`, undefined, false); }
    catch (error) {
      if (!record?.run_id) throw error;
      entry = {deployment: record.deployment || {title: record.protocol.design.title, origin: "pilot"},
        appearance: record.protocol.design.appearance, supported: true};
    }
    if (!entry.supported && !record?.run_id) throw new Error("This study is not available in this browser delivery profile. Please contact your researcher.");
    document.title = `${entry.deployment.title} | Brohn study`;
    $("study-origin").textContent = entry.deployment.origin === "live" ? "" : `${entry.deployment.origin || "pilot"} session`;
    applyAppearance(record?.protocol?.design?.appearance || entry.appearance);
    if (!record?.run_id && !record?.pending_start && entry.deployment.status !== "open") {
      const paused = entry.deployment.status === "paused";
      screen(paused ? "This study is paused" : "This study is closed",
        paused ? "New sessions are temporarily paused. Please contact your researcher about when to return." :
          "This link is no longer accepting new participants. Please contact your researcher if you expected to take part.");
      status.textContent = "No participant session has been started.";
      return;
    }
    if (!record) { if (entry.welcome) welcomeScreen(); else consentScreen(); return; }
    if (record.pending_start) {
      screen("Your session setup is unfinished", "Continue the same setup request to avoid creating a duplicate participant session.");
      content.append(button("Continue session setup", () => start(record.pending_start.consented), true)); return;
    }
    if (record.researcher_resolution?.resolved) {await researcherResolved(record.researcher_resolution); return;}
    // Check the authenticated session before changing a saved camera journal or
    // creating recovery events. Offline continuation retains its existing rules.
    try {
      const savedStatus = await api(`/api/session_status/${encodeURIComponent(record.run_id)}`);
      if (savedStatus.run_id !== record.run_id) throw new Error("The session status identity does not match this browser.");
      if (savedStatus.researcher_resolution?.resolved) {await researcherResolved(savedStatus.researcher_resolution); return;}
    } catch (error) {
      if (record?.hosted_access) return;
      if (error.permanent) throw error;
    }
    if (record.protocol?.design?.camera) {
      try {
        const recovery = await camera().recover(); cameraReady = recovery.declined === true;
        if (recovery.found && !recovery.declined && !record.finish) {await finish("interrupted", "page_reload_during_camera_session"); return;}
      } catch (error) {
        screen("Your camera recording needs recovery", "Previously saved chunks remain in this browser. Restore the connection and retry before closing this page.");
        showError(error); content.append(button("Retry recording recovery", () => location.reload(), true)); return;
      }
    }
    if (record.finish) {
      screen("Your final receipt is pending", "Your responses remain saved in this browser. Retry delivery to confirm the final receipt.");
      content.append(button("Retry saving", async () => { await persist(() => { record.delivery_blocked = false; }); await sync(); }, true)); void sync(); return;
    }
    if (["timed", "timed_preparing", "task"].includes(record.step_state)) {
      activeStep = record.protocol.timeline[record.index];
      await finish("interrupted", "reload_during_timed_step"); return;
    }
    screen("An unfinished session is saved", "Continue this participant's session only if you are the same participant. Saved answers can be restored at this untimed point.");
    content.append(button("Resume this participant session", async () => {
      try { await preloadTimeline(); } catch (error) { await finish("interrupted", error.message); return; }
      void sync(); await enterStudy(true);
    }, true));
    content.append(button("End this session for a different participant", () => finish("withdrawn", "different_participant_requested")));
  }
  $("withdraw").addEventListener("click", () => void withdraw().catch(showError));
  document.addEventListener("keydown", e => { if (e.key === "Escape" && record?.run_id && !record.finish) { e.preventDefault(); void withdraw().catch(showError); } });
  const environmentEvent = reason => {
    if (!record?.run_id || record.finish || finished) return;
    const timed = record.step_state === "timed";
    const invalidated = timed && (reason === "blur" || reason === "resize" || document.hidden);
    // Stop a timed presentation synchronously; storage latency must not extend an invalid trial.
    if (invalidated) { interrupted = true; stopPresentation(); }
    void event("visibility", {reason, hidden: document.hidden, focused: document.hasFocus(), viewport: {width: innerWidth, height: innerHeight}}, activeStep).then(() => {
      if (invalidated) return finish("interrupted", `${reason}_during_timed_step`);
    }).catch(showError);
  };
  document.addEventListener("visibilitychange", () => environmentEvent("visibilitychange"));
  window.addEventListener("blur", () => environmentEvent("blur"));
  window.addEventListener("focus", () => environmentEvent("focus"));
  window.addEventListener("resize", () => environmentEvent("resize"));
  window.addEventListener("pagehide", () => cameraController?.releaseTracks());
  window.addEventListener("online", () => void sync());
  window.addEventListener("beforeunload", e => { if (record?.run_id && !finished) { e.preventDefault(); e.returnValue = ""; } });
  // Expose deterministic rule evaluation for contract fixtures; no participant state is exposed.
  window.BrohnParticipantRules = Object.freeze({matches: ruleMatches, answered});
  void boot().catch(error => { screen("This study could not open"); showError(error); content.append(button("Try again", () => location.reload())); });
})();
