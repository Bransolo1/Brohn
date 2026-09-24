/* Original pure Go/No-Go observation engine. No DOM, storage or ambient clock. */
(() => {
  "use strict";
  const profile = "gnat-brohn-single-target/1.0";
  const require = (ok, message) => { if (!ok) throw new Error(message); };
  const time = n => typeof n === "number" && Number.isFinite(n) && n >= 0 && n <= 1e12;
  const text = (v, max = 64) => typeof v === "string" && v.length > 0 && v.length <= max;
  const round = n => Number(n.toFixed(6));
  const outcome = (action, response) => action === "go" ? response ? "hit" : "miss" : response ? "false_alarm" : "correct_rejection";
  function create(trial, onset, held = []) {
    const deadline = trial?.phase === "training" ? 1000 : trial?.round_id === "r1" ? 750 : trial?.round_id === "r2" ? 600 : null;
    require(trial?.task_profile === profile && trial.mode === "gnat" && text(trial.id, 128) &&
      ["go", "nogo"].includes(trial.expected_action) && ["training", "practice", "test"].includes(trial.phase) &&
      trial.timeout_ms === deadline && trial.feedback_ms === 100 && trial.offset_to_next_onset_min_ms === 500 &&
      trial.forced_correction === false && Array.isArray(trial.allowed_codes) && trial.allowed_codes.length === 1 && trial.allowed_codes[0] === "Space" &&
      time(onset) && Array.isArray(held) && held.length <= 128 && held.every(c => text(c)) && new Set(held).size === held.length && !held.includes("Space"),
    "GNAT requires its frozen trial and a released Space key at onset.");
    return {trial_id: trial.id, expected_action: trial.expected_action, onset_ms: round(onset), deadline_ms: round(onset + deadline),
      phase: "response", held: [...held], held_at_onset: [...held], keys: [], first: null,
      visibility: [{observed_ms: round(onset), visible: true, focused: true}], response_outcome: null,
      deadline_timer_ms: null, deadline_frame_ms: null, response_closed_ms: null, feedback_start_ms: null,
      feedback_end_ms: null, blank_end_ms: null, last_event_ms: null, last_observed_ms: round(onset),
      outcome: null, interruption_reason: null};
  }
  function transition(original, action) {
    const s = structuredClone(original);
    require(action && text(action.type) && time(action.now) && action.now >= s.last_observed_ms,
      "GNAT observations must retain monotonic handler time.");
    require(!["finished", "interrupted"].includes(s.phase), "This GNAT trial is already terminal.");
    const now = round(action.now);
    const interrupt = reason => { s.phase = "interrupted"; s.outcome = "interrupted"; s.interruption_reason = reason; };
    if (action.type === "key") {
      require(["down", "up"].includes(action.keyType) && text(action.code) && time(action.event_ms) && action.event_ms <= now &&
        [action.repeat, action.trusted, action.modifiers].every(v => typeof v === "boolean"),
      "GNAT needs complete key observations with an eligible page-clock timestamp.");
      require(s.keys.length < 5000, "GNAT key evidence exceeds its declared bound.");
      const at = round(action.event_ms), reversed = s.last_event_ms !== null && at < s.last_event_ms;
      const impossible = action.trusted && action.code === "Space" && !s.held.includes("Space") && (action.keyType === "up" || action.repeat);
      const open = ["response", "pending"].includes(s.phase);
      const reason = !action.trusted ? "synthetic_key_event" : action.modifiers ? "modified_key" : reversed ? "event_clock_reversed" :
        action.keyType === "up" ? "key_release" : action.code !== "Space" ? "other_key" : action.repeat ? "key_repeat" :
        s.held.includes(action.code) ? "key_held_from_previous_phase" : at < s.onset_ms ? "anticipatory" :
        at >= s.deadline_ms ? "after_deadline" : s.first ? "after_first_response" : !open ? "eligible_key_after_seal" : null;
      const k = {type: action.keyType, code: action.code, event_ms: at, observed_ms: now, repeat: action.repeat,
        trusted: action.trusted, modifiers: action.modifiers, response_open: open, accepted: reason === null, ignored_reason: reason};
      s.keys.push(k); s.last_event_ms = at;
      if (action.trusted) {
        if (action.keyType === "up") s.held = s.held.filter(c => c !== action.code);
        else if (!s.held.includes(action.code)) s.held.push(action.code);
      }
      if (reason === null) { s.first = k; s.response_outcome = outcome(s.expected_action, true); }
      if (impossible) interrupt("impossible_space_key_state");
      else if (["event_clock_reversed", "eligible_key_after_seal", "anticipatory"].includes(reason)) interrupt(reason);
      else if (s.keys.length === 5000) interrupt("excessive_key_events");
    } else if (action.type === "deadline_timer") {
      require(["response", "pending"].includes(s.phase) && s.deadline_timer_ms === null && now >= s.deadline_ms,
        "Withholding requires its actual deadline timer.");
      s.deadline_timer_ms = now; s.phase = "pending";
    } else if (action.type === "deadline_frame") {
      require(s.phase === "pending" && s.deadline_timer_ms !== null && s.deadline_frame_ms === null && now >= s.deadline_timer_ms,
        "Withholding requires an animation frame after its observed timer.");
      s.deadline_frame_ms = now;
    } else if (action.type === "seal") {
      require(["response", "pending"].includes(s.phase) && (s.first ||
        s.deadline_timer_ms !== null && s.deadline_frame_ms !== null && now >= s.deadline_frame_ms && now >= s.deadline_ms),
      "GNAT cannot seal withholding before its complete deadline evidence.");
      s.response_closed_ms = now; s.feedback_start_ms = now; s.response_outcome = outcome(s.expected_action, s.first !== null); s.phase = "feedback";
    } else if (action.type === "feedback_end") {
      require(s.phase === "feedback" && now >= s.feedback_start_ms + 100, "GNAT feedback must last at least 100 ms.");
      s.feedback_end_ms = now; s.phase = "blank";
    } else if (action.type === "blank_end") {
      require(s.phase === "blank" && now >= Math.max(s.feedback_end_ms + 400, s.response_closed_ms + 500) && !s.held.includes("Space"),
        "GNAT needs its full blank interval and released Space key before progression.");
      const last = s.visibility.at(-1);
      require(last.observed_ms >= now && last.visible && last.focused, "GNAT needs a final visible and focused observation through the blank.");
      s.blank_end_ms = now; s.phase = "finished"; s.outcome = s.response_outcome;
    } else if (action.type === "visibility") {
      require(typeof action.visible === "boolean" && typeof action.focused === "boolean" && s.visibility.length < 1000,
        "GNAT visibility needs literal bounded observations.");
      s.visibility.push({observed_ms: now, visible: action.visible, focused: action.focused});
      if (!action.visible || !action.focused) interrupt(!action.visible ? "visibility_lost_during_trial" : "window_focus_lost_during_trial");
    } else if (action.type === "interrupt") {
      require(text(action.reason, 500), "GNAT interruption needs a retained reason."); interrupt(action.reason);
    } else throw new Error("Unsupported GNAT observation transition.");
    s.last_observed_ms = now; return s;
  }
  function result(s) {
    require(["finished", "interrupted"].includes(s.phase), "Incomplete GNAT evidence cannot be exported as finished.");
    return {outcome: s.outcome, response_outcome: s.response_outcome, response_code: s.first ? "Space" : null,
      response_ms: s.first ? round(s.first.event_ms - s.onset_ms) : null,
      correct: s.outcome === "interrupted" ? null : ["hit", "correct_rejection"].includes(s.outcome),
      onset_ms: s.onset_ms, deadline_ms: s.deadline_ms, deadline_timer_ms: s.deadline_timer_ms, deadline_frame_ms: s.deadline_frame_ms,
      response_closed_ms: s.response_closed_ms, feedback_start_ms: s.feedback_start_ms, feedback_end_ms: s.feedback_end_ms,
      blank_end_ms: s.blank_end_ms, keys: structuredClone(s.keys), visibility: structuredClone(s.visibility), interruption_reason: s.interruption_reason};
  }
  globalThis.BrohnGnatCore = Object.freeze({profile, version: "1.0.0", create, transition, result});
})();
