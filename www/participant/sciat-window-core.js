/* Original pure first-response state machine. No DOM, network, clocks or storage. */
(() => {
  "use strict";
  const PROFILE = "sciat-brohn-response-window-im100/1.0";
  const codes = new Set(["KeyE", "KeyI"]);
  const number = n => typeof n === "number" && Number.isFinite(n) && n >= 0 && n <= 1e12;
  const require = (ok, message) => { if (!ok) throw new Error(message); };
  const round = n => Number(n.toFixed(6));
  function create(trial, onset, held = []) {
    require(trial?.task_profile === PROFILE && trial.forced_correction === false && trial.timeout_ms === 1500 &&
      trial.response_feedback_ms === 150 && trial.omission_feedback_ms === 500 && trial.post_feedback_blank_ms === 250 &&
      codes.has(trial.correct_code) && number(onset) && Array.isArray(held) && held.length <= 2 &&
      held.every(c => codes.has(c)) && new Set(held).size === held.length, "Invalid frozen SC-IAT trial.");
    return {trial_id: trial.id, correct_code: trial.correct_code, onset_ms: round(onset), deadline_ms: round(onset + 1500),
      phase: "response", held: [...held], held_at_onset: [...held], keys: [], first: null, response_outcome: null,
      response_closed_ms: null, feedback_start_ms: null, feedback_end_ms: null, blank_end_ms: null,
      last_event_ms: null, last_observed_ms: round(onset), outcome: null, interruption_reason: null};
  }
  function transition(original, action) {
    const s = structuredClone(original);
    require(action && typeof action.type === "string" && number(action.now) && action.now >= s.last_observed_ms,
      "SC-IAT observations must preserve monotonic handler time.");
    const now = round(action.now);
    require(s.phase !== "finished" && s.phase !== "interrupted", "The SC-IAT trial is already terminal.");
    const interrupt = reason => { s.phase = "interrupted"; s.outcome = "interrupted"; s.interruption_reason = reason; };
    if (action.type === "key") {
      require(["down", "up"].includes(action.keyType) && codes.has(action.code) && number(action.event_ms) &&
        action.event_ms <= now + .002 && [action.repeat, action.trusted, action.modifiers].every(v => typeof v === "boolean"),
        "SC-IAT needs an explicit physical-key observation and event timestamp.");
      const at = round(action.event_ms), reversed = s.last_event_ms !== null && at < s.last_event_ms;
      const reason = !action.trusted ? "synthetic_key_event" : action.modifiers ? "modified_key" : reversed ? "event_clock_reversed" :
        action.keyType === "up" ? "key_release" : action.repeat ? "key_repeat" : s.held.includes(action.code) ? "key_held_from_previous_phase" :
        at < s.onset_ms ? "anticipatory" : at > s.deadline_ms ? "after_deadline" : s.first ? "after_first_response" :
        !["response", "pending"].includes(s.phase) ? "eligible_key_after_seal" : null;
      const k = {type: action.keyType, code: action.code, event_ms: at, observed_ms: now, repeat: action.repeat,
        trusted: action.trusted, modifiers: action.modifiers, response_open: ["response", "pending"].includes(s.phase), accepted: reason === null, ignored_reason: reason};
      s.keys.push(k); s.last_event_ms = at;
      // Modifier combinations cannot answer, but a physical release still
      // releases the key. Otherwise Shift+keyup can poison the next response.
      if (action.trusted) {
        if (action.keyType === "up") s.held = s.held.filter(c => c !== action.code);
        else if (!s.held.includes(action.code)) s.held.push(action.code);
      }
      if (reason === null) { s.first = k; s.response_outcome = "response"; }
      if (reason === "eligible_key_after_seal" || reason === "event_clock_reversed") interrupt(reason);
      if (s.keys.length >= 5000) interrupt("excessive_key_events");
    } else if (action.type === "deadline") {
      require(["response", "pending"].includes(s.phase) && now >= s.deadline_ms, "The response deadline has not elapsed.");
      s.phase = "pending";
    } else if (action.type === "seal") {
      require(["response", "pending"].includes(s.phase) && (s.first || now >= s.deadline_ms), "The response window cannot yet close.");
      s.response_closed_ms = now; s.response_outcome = s.first ? "response" : "omission"; s.phase = "feedback_pending";
    } else if (action.type === "feedback_start") {
      require(s.phase === "feedback_pending" && now >= s.response_closed_ms, "Feedback needs a closed response window.");
      s.feedback_start_ms = now; s.phase = "feedback";
    } else if (action.type === "feedback_end") {
      require(s.phase === "feedback" && now - s.feedback_start_ms >= (s.first ? 150 : 500), "Feedback is shorter than the frozen duration.");
      s.feedback_end_ms = now; s.phase = "blank";
    } else if (action.type === "blank_end") {
      require(s.phase === "blank" && now - s.feedback_end_ms >= 250, "The post-feedback blank is incomplete.");
      s.blank_end_ms = now; s.phase = "finished"; s.outcome = s.response_outcome;
    } else if (action.type === "interrupt") {
      require(typeof action.reason === "string" && action.reason.length > 0 && action.reason.length <= 500, "Interruption needs a reason.");
      interrupt(action.reason);
    } else throw new Error("Unsupported SC-IAT state transition.");
    s.last_observed_ms = now; return s;
  }
  function result(s) {
    require(["finished", "interrupted"].includes(s.phase), "An unfinished trial cannot be exported as complete.");
    return {outcome: s.outcome, response_outcome: s.response_outcome, response_code: s.first?.code ?? null,
      response_ms: s.first ? round(s.first.event_ms - s.onset_ms) : null, correct: s.first ? s.first.code === s.correct_code : null,
      onset_ms: s.onset_ms, deadline_ms: s.deadline_ms, response_closed_ms: s.response_closed_ms,
      feedback_start_ms: s.feedback_start_ms, feedback_end_ms: s.feedback_end_ms, blank_end_ms: s.blank_end_ms,
      keys: structuredClone(s.keys), interruption_reason: s.interruption_reason};
  }
  globalThis.BrohnSciatWindowCore = Object.freeze({profile: PROFILE, version: "1.0.0", create, transition, result});
})();
