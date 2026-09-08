/* Canonical-server questionnaire navigation. No network, storage or scoring. */
(() => {
  'use strict';
  const hash = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
  const integer = (value, min = 0, max = 10000000) => Number.isSafeInteger(value) && value >= min && value <= max;
  const require = (ok, message) => {if (!ok) throw new Error(message);};
  const equal = (a, b) => {
    if (a === b) return true;
    if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every((value, i) => equal(value, b[i]));
    if (a && b && typeof a === 'object' && typeof b === 'object' && !Array.isArray(a) && !Array.isArray(b)) {
      const keys = Object.keys(a).sort(); return equal(keys, Object.keys(b).sort()) && keys.every(key => equal(a[key], b[key]));
    }
    return false;
  };
  const clone = value => structuredClone(value);
  function create(protocol, pinnedHash) {
    require(protocol?.design?.questionnaire_navigation?.schema === 'brohn-questionnaire-navigation/1.0' &&
      protocol.design.questionnaire_navigation.profile === 'within-occurrence-revision/1.0' && hash(pinnedHash),
    'This questionnaire needs its supported frozen navigation policy and protocol identity.');
    require(Array.isArray(protocol.timeline) && protocol.timeline.length <= 20000 && Array.isArray(protocol.questionnaire_occurrences),
      'The questionnaire occurrence manifest is missing.');
    const steps = new Map(protocol.timeline.map(step => [step.id, step]));
    const occurrences = new Map(protocol.questionnaire_occurrences.map(occurrence => [occurrence.id, occurrence]));
    require(steps.size === protocol.timeline.length && occurrences.size === protocol.questionnaire_occurrences.length,
      'The questionnaire contains duplicate frozen step or occurrence identities.');
    const stepId = id => id === null || typeof id === 'string' && steps.has(id);
    const ids = (values, predicate = stepId) => Array.isArray(values) && values.length <= 20000 &&
      new Set(values).size === values.length && values.every(value => typeof value === 'string' && predicate(value));
    function validate(packet, {acknowledgedSequence = null, stateHash = null, offset = null} = {}) {
      require(packet?.schema === 'brohn-questionnaire-packet/1.0' && packet.protocol_hash === pinnedHash &&
        hash(packet.state_hash) && integer(packet.acknowledged_sequence) && integer(packet.protocol_cursor, 1, protocol.timeline.length + 1),
      'The study service returned an invalid or foreign questionnaire state. Your local journal has been retained.');
      if (acknowledgedSequence !== null) require(packet.acknowledged_sequence === acknowledgedSequence, 'Questionnaire state and receipt sequence disagree.');
      if (stateHash !== null) require(packet.state_hash === stateHash, 'Questionnaire state changed while its answers were being recovered. Retry recovery.');
      require(packet.next_step_id === (protocol.timeline[packet.protocol_cursor - 1]?.id ?? null), 'The questionnaire receipt has an inconsistent protocol boundary.');
      const page = packet.resume_page;
      require(page?.schema === 'brohn-questionnaire-revision-resume/1.0' && page.protocol_hash === pinnedHash && hash(page.state_hash) &&
        integer(page.offset, 0, 20000) && integer(page.total_records, 0, 20000) && page.offset <= page.total_records && Array.isArray(page.records) &&
        page.records.length <= page.total_records - page.offset &&
        (page.next_offset === null ? page.offset + page.records.length === page.total_records :
          integer(page.next_offset, page.offset + 1, page.total_records - 1) && page.next_offset === page.offset + page.records.length),
      'The questionnaire recovery page is incomplete or has an invalid range.');
      if (offset !== null) require(page.offset === offset, 'The questionnaire recovery page does not match the requested answer range.');
      for (const row of page.records) {
        const step = steps.get(row.step_id), occurrence = occurrences.get(row.occurrence_id);
        require(step?.type === 'question' && occurrence && step.questionnaire_occurrence_id === occurrence.id &&
          step.question.id === row.question_id && row.stimulus_id === step.stimulus_id && row.condition_id === step.condition_id &&
          row.scope === step.question.scope && integer(row.dependency_generation) && integer(row.answer_version) && integer(row.revision_count) &&
          typeof row.information === 'boolean' && row.information === (step.question.type === 'information') && typeof row.ever_visited === 'boolean' &&
          ['answered', 'optional_omission', 'not_displayed', 'invalidated_unanswered', 'not_submitted', 'information_acknowledged', 'information_unacknowledged'].includes(row.status),
        'A recovered answer does not belong to its exact frozen questionnaire occurrence.');
      }
      const latest = packet.latest_occurrence, actions = packet.actions;
      require(actions && ['enter_step_id', 'next_step_id', 'back_step_id'].every(key => stepId(actions[key])) &&
        ids(actions.editable_step_ids) && typeof actions.can_seal === 'boolean', 'The study service returned unsupported questionnaire actions.');
      if (latest !== null) {
        const occurrence = occurrences.get(latest.id);
        require(occurrence && integer(latest.state_version) && typeof latest.sealed === 'boolean' &&
          latest.review_step_id === occurrence.review_step_id && hash(latest.projection_hash), 'The current questionnaire occurrence is not source-bound.');
        const member = id => id === occurrence.review_step_id || occurrence.question_step_ids.includes(id);
        require(['enter_step_id', 'next_step_id', 'back_step_id'].every(key => actions[key] === null || member(actions[key])) &&
          actions.editable_step_ids.every(id => occurrence.question_step_ids.includes(id)), 'A questionnaire action crosses its sealed or timed boundary.');
        if (latest.visit !== null) require(typeof latest.visit.id === 'string' && member(latest.visit.step_id) &&
          typeof latest.visit.instance_id === 'string' && typeof latest.visit.time_origin_ms === 'string' &&
          typeof latest.visit.onset_ms === 'string' && Number.isFinite(Number(latest.visit.onset_ms)) &&
          typeof latest.visit.resumed === 'boolean' && typeof latest.visit.committed === 'boolean', 'The questionnaire visit is incomplete.');
        require(!actions.can_seal || !latest.sealed && latest.visit?.step_id === latest.review_step_id, 'Only the current review can seal its answers.');
      } else require(['enter_step_id', 'next_step_id', 'back_step_id'].every(key => actions[key] === null) &&
        actions.editable_step_ids.length === 0 && !actions.can_seal, 'An absent questionnaire occurrence cannot offer editing actions.');
      return packet;
    }
    async function pages(first, fetchPage) {
      validate(first, {offset: 0}); const records = [...first.resume_page.records];
      let page = first;
      while (page.resume_page.next_offset !== null) {
        const offset = page.resume_page.next_offset;
        page = validate(await fetchPage(offset, first.state_hash), {stateHash: first.state_hash, acknowledgedSequence: first.acknowledged_sequence, offset});
        require(page.resume_page.state_hash === first.resume_page.state_hash && page.resume_page.total_records === first.resume_page.total_records,
          'Questionnaire answer pages do not describe the same saved state.');
        records.push(...page.resume_page.records);
      }
      require(new Set(records.map(row => row.step_id)).size === records.length && records.length === first.resume_page.total_records,
        'Questionnaire recovery contains duplicated or missing answer rows.');
      return {packet: clone(first), records: clone(records)};
    }
    function payload(model, action, {value = null, target = null, visitId = null, clock = null} = {}) {
      const packet = validate(model.packet), current = packet.latest_occurrence;
      require(current && !current.sealed, 'This questionnaire occurrence is already sealed.');
      const visit = current.visit, base = {schema: 'brohn-questionnaire-event/1.0', occurrence_id: current.id, state_version: current.state_version};
      if (['enter', 'next', 'back', 'edit', 'resume'].includes(action)) {
        if (action === 'edit') require(packet.actions.editable_step_ids.includes(target), 'Choose a visible reached answer from this review.');
        else if (action === 'resume') {require(visit !== null, 'There is no current questionnaire visit to resume.'); target = visit.step_id;}
        else {target = packet.actions[`${action}_step_id`]; require(target !== null, 'This questionnaire navigation action is unavailable.');}
        require(typeof visitId === 'string' && visitId.length > 0, 'Create a fresh questionnaire visit identity.');
        return {step: steps.get(target), payload: {...base, kind: 'visit', visit_id: visitId, reason: action, from_visit_id: visit?.id ?? null}};
      }
      require(visit !== null, 'Wait for the current question visit to be received.');
      const step = steps.get(visit.step_id);
      if (action === 'seal') {
        require(packet.actions.can_seal, 'Complete all visible answers before continuing to the next part.');
        return {step, payload: {...base, kind: 'seal', visit_id: visit.id, projection_hash: current.projection_hash}};
      }
      require(action === 'commit' && step.type === 'question' && !visit.committed, 'This question visit has already been submitted.');
      if (step.question.type === 'information') return {step, payload: {...base, kind: 'acknowledge', visit_id: visit.id}};
      const row = model.records.find(row => row.step_id === step.id);
      require(row && row.occurrence_id === current.id, 'Wait for the complete saved answer state before submitting.');
      require(clock?.instance_id === visit.instance_id && clock.time_origin_ms === visit.time_origin_ms &&
        Number.isFinite(clock.value) && clock.value >= Number(visit.onset_ms), 'Resume this question before submitting from a new page.');
      const elapsed = clock.value - Number(visit.onset_ms);
      return {step, payload: {...base, kind: 'commit', visit_id: visit.id, previous_answer_event_id: row.last_answer_event_id,
        dependency_generation: row.dependency_generation, value,
        response_time_ms: row.last_answer_event_id === null && !visit.resumed ? elapsed : null,
        active_segment_response_ms: elapsed, resumed: visit.resumed}};
    }
    function draftValue(model, step, draft) {
      const row = model.records.find(row => row.step_id === step.id);
      if (draft && draft.occurrence_id === step.questionnaire_occurrence_id && draft.step_id === step.id &&
          draft.dependency_generation === row?.dependency_generation) return clone(draft.value);
      return row?.status === 'answered' || row?.status === 'optional_omission' ? clone(row.value) : null;
    }
    function reconcileDrafts(model, drafts) {
      const kept = Object.create(null), rows = new Map(model.records.map(row => [row.step_id, row]));
      for (const [sid, draft] of Object.entries(drafts || {})) {
        const row = rows.get(sid);
        if (row && row.status !== 'not_displayed' && draft.occurrence_id === row.occurrence_id && draft.step_id === sid &&
            draft.dependency_generation === row.dependency_generation) kept[sid] = clone(draft);
      }
      return kept;
    }
    return Object.freeze({validate, pages, payload, draftValue, reconcileDrafts, step: id => steps.get(id), occurrence: id => occurrences.get(id)});
  }
  globalThis.BrohnQuestionRevision = Object.freeze({create, equal});
})();
