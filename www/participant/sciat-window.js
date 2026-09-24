/* Brohn response-window adaptation. Existing caller owns consent, journal,
 * exact transport retries, session ending and scoring. Never restart timed work. */
(() => {
  "use strict";
  const node = (tag, text = null, attributes = {}) => {
    const n = document.createElement(tag); if (text !== null) n.textContent = text;
    for (const [k, v] of Object.entries(attributes)) n.setAttribute(k, String(v)); return n;
  };
  async function run({container, compiled, emit, onCheckpoint, signal, clockInstanceId, checkpoint = null}) {
    const core = window.BrohnSciatWindowCore;
    if (!core || !(container instanceof HTMLElement) || compiled?.profile !== core.profile ||
      compiled.timeline?.length !== 196 || typeof emit !== "function" || typeof onCheckpoint !== "function" ||
      typeof clockInstanceId !== "string" || !clockInstanceId || checkpoint !== null) {
      throw new Error(checkpoint !== null ? "A received SC-IAT task cannot restart after refresh; preserve its journal and interrupt the session." : "SC-IAT needs its frozen procedure, page clock and durable caller.");
    }
    if (!document.getElementById("brohn-sciat-window-style")) {
      document.head.append(node("style", ".brohn-sciat{font-family:Arial,sans-serif;min-height:65vh}.brohn-sciat *{box-sizing:border-box}.brohn-sciat h1{font-size:1.7rem}.brohn-sciat p{max-width:70ch;line-height:1.5}.brohn-sciat button{font:inherit;min-height:48px;padding:12px 20px;background:inherit;color:inherit;border:1px solid currentColor;border-radius:8px}.brohn-sciat button:focus-visible{outline:3px double currentColor;outline-offset:4px}.brohn-sciat .sciat-map{display:flex;justify-content:space-between;gap:20px;min-height:96px;white-space:pre-wrap}.brohn-sciat .sciat-map>div{width:46%;overflow-wrap:anywhere}.brohn-sciat .sciat-map>div:last-child{text-align:right}.brohn-sciat .sciat-stage{height:42vh;min-height:220px;display:flex;align-items:center;justify-content:center;font-size:1.8rem;line-height:1.3;text-align:center}.brohn-sciat .sciat-material{max-width:100%;overflow-wrap:anywhere}.brohn-sciat img{max-width:100%;max-height:38vh;object-fit:contain}.brohn-sciat .sciat-feedback{min-height:72px;text-align:center;font-size:1.2rem}.brohn-sciat .sciat-feedback strong{display:block;font-size:2rem}", {id: "brohn-sciat-window-style"}));
    }
    const images = new Map(); let imageBytes = 0;
    for (const t of compiled.timeline) if (t.material?.type === "image" && !images.has(t.material.id)) {
      imageBytes += t.material.asset?.size || 0;
      if (imageBytes > 256*1024*1024) throw new Error("SC-IAT images exceed the supported preload size.");
      const url = new URL(t.material.asset?.url || "", location.href);
      if (!t.material.asset?.url || url.origin !== location.origin || !url.pathname.startsWith("/api/assets/")) throw new Error("SC-IAT image needs its existing authorized immutable asset URL.");
      const im = new Image(); im.alt = t.material.image_alt;
      await new Promise((resolve, reject) => { const timer = setTimeout(() => reject(Error("SC-IAT image preload timed out.")), 30000);
        im.onload = () => {clearTimeout(timer);resolve();}; im.onerror = () => {clearTimeout(timer);reject(Error("SC-IAT image failed to load."));}; im.src = url.href; });
      if (im.decode) await im.decode(); images.set(t.material.id, im);
    }
    const root = node("div", null, {class: "brohn-sciat"}); container.replaceChildren(root);
    const now = () => Number(performance.now().toFixed(6));
    const clock = n => ({id: "browser-monotonic", unit: "ms", value: n.toFixed(6), instance_id: clockInstanceId, time_origin_ms: performance.timeOrigin.toFixed(3)});
    let chain = Promise.resolve(), failure = null, reason = null, current = null, active = null, cancel = null, last = null;
    const responses = [], held = new Set(), sealedOmissions = [];
    const interrupt = why => { if (reason) return; reason = why; if (active && !["finished", "interrupted"].includes(active.phase)) active = core.transition(active, {type: "interrupt", now: now(), reason: why}); cancel?.(); };
    const commit = (kind, data) => {
      const fixed = structuredClone(data);
      chain = chain.then(() => emit(kind, fixed)); chain.catch(e => {failure = e;interrupt("journal_write_failed");}); return chain;
    };
    const base = t => ({task_id: compiled.id, trial_id: t.id, block_id: t.block_id, procedure_hash: compiled.procedure_hash});
    const stop = () => interrupt("caller_aborted");
    const visibility = () => {if (current?.type === "task_trial" && document.hidden) interrupt("visibility_lost_during_trial");};
    const blur = () => {if (current?.type === "task_trial") interrupt("window_focus_lost_during_trial");};
    const resize = () => {if (current?.type === "task_trial") interrupt("viewport_changed_during_trial");};
    const key = event => {
      if (event.code === "Escape" && event.type === "keydown") {event.preventDefault();interrupt("participant_stopped");return;}
      if (!["KeyE", "KeyI"].includes(event.code)) return;
      const wasHeld = held.has(event.code);
      if (event.isTrusted) {if (event.type === "keyup") held.delete(event.code);else held.add(event.code);}
      const observed = now(); let stamp = event.timeStamp;
      if (stamp > performance.timeOrigin) stamp -= performance.timeOrigin;
      if (!Number.isFinite(stamp) || stamp < 0 || stamp > observed + .002) {interrupt("unsupported_keyboard_event_clock");return;}
      if (event.type === "keydown" && event.isTrusted && !event.repeat && !wasHeld && !event.ctrlKey && !event.altKey && !event.metaKey && !event.shiftKey &&
        sealedOmissions.some(w => stamp >= w.onset && stamp <= w.deadline)) {interrupt("eligible_key_after_seal");return;}
      if (!active || ["finished", "interrupted"].includes(active.phase)) return;
      event.preventDefault();
      active = core.transition(active, {type: "key", now: observed, event_ms: stamp, keyType: event.type === "keydown" ? "down" : "up",
        code: event.code, repeat: event.repeat, trusted: event.isTrusted, modifiers: event.ctrlKey || event.altKey || event.metaKey || event.shiftKey});
      if (active.phase === "interrupted") interrupt(active.interruption_reason);
    };
    document.addEventListener("keydown", key, true); document.addEventListener("keyup", key, true);
    document.addEventListener("visibilitychange", visibility); window.addEventListener("blur", blur); window.addEventListener("resize", resize);
    signal?.addEventListener("abort", stop, {once: true}); if (signal?.aborted) stop();
    try {
      for (current of compiled.timeline) {
        if (reason) break;
        if (current.type === "task_instructions") {
          root.replaceChildren(node("h1", compiled.title, {tabindex: "-1"}), node("p", current.text),
            node("p", "Use a physical keyboard. Keep this page in focus. Escape stops the study; refreshing ends this timed task."));
          root.querySelector("h1").focus();
          await onCheckpoint({task_id: compiled.id, step_id: current.id, resumable: false, phase: "instructions", last_completed_trial_id: last});
          await commit("task_instructions", {task_id: compiled.id, step_id: current.id, block_id: current.block_id, procedure_hash: compiled.procedure_hash, clock: clock(now())});
          await new Promise(resolve => {const button = node("button", "Begin this block", {type: "button"});root.append(button);cancel = resolve;
            button.addEventListener("click", () => {button.disabled = true;cancel = null;resolve();}, {once: true});});
          continue;
        }
        if (current.type !== "task_trial") throw Error("Unknown frozen SC-IAT timeline step.");
        await onCheckpoint({task_id: compiled.id, step_id: current.id, resumable: false, phase: "timed", last_completed_trial_id: last});
        if (reason) break;
        if (document.hidden || !document.hasFocus()) {interrupt("trial_started_without_focus");break;}
        const map = node("div", null, {class: "sciat-map"});map.append(node("div", `E\n${current.left_label}`), node("div", `I\n${current.right_label}`));
        const stage = node("div", null, {class: "sciat-stage"}), feedback = node("div", null, {class: "sciat-feedback", "aria-live": "polite"});
        const material = node("div", null, {class: "sciat-material"});
        if (current.material.type === "image") material.append(images.get(current.material.id).cloneNode(true));else material.textContent = current.material.content;
        root.replaceChildren(map, stage, feedback, node("p", "Press Escape to stop."));
        let frames = 0, maxGap = 0, lastFrame = null, pendingDrain = false, drainReady = false, handle = null;
        await new Promise((resolve, reject) => {
          const finish = () => {cancelAnimationFrame(handle);cancel = null;resolve();};cancel = finish;
          const tick = () => {
            try {
              const at = now();frames++; if (lastFrame !== null) maxGap = Math.max(maxGap, at-lastFrame);lastFrame = at;
              if (reason) {finish();return;}
              if (!active) {
                stage.append(material); const rect = material.getBoundingClientRect();
                active = core.create(current, at, [...held]);
                void commit("task_trial_started", {...base(current), clock: clock(at), held_codes: [...held], timing_reference: "requestAnimationFrame_before_paint",
                  viewport: {width: innerWidth, height: innerHeight, device_pixel_ratio: devicePixelRatio}, stimulus_rect: {x: rect.x, y: rect.y, width: rect.width, height: rect.height}}).catch(() => {});
              }
              if (["response", "pending"].includes(active.phase)) {
                if (!active.first && at >= active.deadline_ms && !pendingDrain) {
                  active = core.transition(active, {type: "deadline", now: at});pendingDrain = true;
                  setTimeout(() => {drainReady = true;}, 0);
                }
                if (active.first || drainReady) {
                  active = core.transition(active, {type: "seal", now: at});stage.replaceChildren();
                  const correct = active.first?.code === current.correct_code;
                  feedback.replaceChildren(node("strong", active.first ? correct ? "O" : "X" : "Respond sooner"), node("span", active.first ? correct ? "Correct" : "Incorrect" : "Please respond within 1.5 seconds."));
                  active = core.transition(active, {type: "feedback_start", now: at});
                }
              } else if (active.phase === "feedback" && at-active.feedback_start_ms >= (active.first ? 150 : 500)) {
                feedback.replaceChildren();active = core.transition(active, {type: "feedback_end", now: at});
              } else if (active.phase === "blank" && at-active.feedback_end_ms >= 250) {
                active = core.transition(active, {type: "blank_end", now: at});finish();return;
              }
              handle = requestAnimationFrame(tick);
            } catch (e) {cancelAnimationFrame(handle);cancel = null;reject(e);}
          };handle = requestAnimationFrame(tick);
        });
        if (active) {
          const result = {...base(current), ...core.result(active), clock: clock(now()), frame_count: frames, max_frame_gap_ms: maxGap};
          if (result.response_outcome === "omission") sealedOmissions.push({onset: result.onset_ms, deadline: result.deadline_ms});
          await commit("task_trial_finished", result);responses.push(result);if (result.outcome !== "interrupted") last = current.id;active = null;
        }
      }
      if (reason && !failure) await commit("task_interrupted", {task_id: compiled.id, step_id: current?.id ?? last, procedure_hash: compiled.procedure_hash, reason, clock: clock(now())});
      await chain;if (failure) throw failure;
      return {outcome: reason ? "interrupted" : "completed", reason, responses, last_completed_trial_id: last};
    } finally {
      cancel?.();document.removeEventListener("keydown", key, true);document.removeEventListener("keyup", key, true);
      document.removeEventListener("visibilitychange", visibility);window.removeEventListener("blur", blur);window.removeEventListener("resize", resize);signal?.removeEventListener("abort", stop);
    }
  }
  window.BrohnSciatWindow = Object.freeze({version: "1.0.0", run});
})();
