// Fixture logic only. This does not qualify the renderer or scientific worker.
import assert from 'node:assert/strict';
import {profile, responsePlan, assertJournal, expectedCells} from './researcher-gnat-oracle.mjs';
const timeline = [];
for (let block = 0; block < 4; block++) for (let i = 0; i < 20; i++) timeline.push({id: `training-${block}-${i}`, type: 'task_trial',
  phase: 'training', cell_id: null, expected_action: i % 2 ? 'go' : 'nogo', timeout_ms: 1000});
for (const round of [1, 2]) for (const pairing of ['target_positive', 'target_negative']) for (const phase of ['practice', 'test']) {
  for (let i = 0; i < (phase === 'test' ? 60 : 16); i++) timeline.push({id: `${round}-${pairing}-${phase}-${i}`, type: 'task_trial',
    phase, pairing, cell_id: `r${round}-${pairing.endsWith('positive') ? 'positive' : 'negative'}`,
    expected_action: i % 2 ? 'go' : 'nogo', timeout_ms: round === 1 ? 750 : 600});
}
const compiled = {profile, timeline}, original = structuredClone(compiled), checks = [];
for (const person of [0, 1]) {
  const plan = responsePlan(compiled, person); assert.equal(plan.length, 384); assert.deepEqual(compiled, original);
  for (const cell of expectedCells(person)) {
    const rows = plan.filter(row => row.phase === 'test' && row.cell_id === cell.id);
    assert.equal(rows.length, 60);
    for (const key of ['hits', 'misses', 'false_alarms', 'correct_rejections']) {
      const outcome = {hits: 'hit', misses: 'miss', false_alarms: 'false_alarm', correct_rejections: 'correct_rejection'}[key];
      assert.equal(rows.filter(row => row.outcome === outcome).length, cell[key]);
    }
  }
  checks.push(`person${person}: authored per-cell signal/noise totals and nonmutating full384 plan`);
  const events = plan.flatMap(row => [
    {type: 'task_event', payload: {kind: 'task_trial_started', data: {trial_id: row.trial_id}}},
    {type: 'task_event', payload: {kind: 'task_trial_finished', data: {trial_id: row.trial_id, outcome: row.outcome,
      response_outcome: row.outcome, correct: ['hit', 'correct_rejection'].includes(row.outcome),
      response_code: row.respond ? 'Space' : null, response_ms: row.respond ? 125 : null}}}
  ]);
  assert.equal(assertJournal(compiled, events, plan).length, 384);
  const corruption = structuredClone(events); corruption.find(e => e.payload.kind === 'task_trial_finished' && e.payload.data.response_ms === null).payload.data.response_ms = 0;
  assert.throws(() => assertJournal(compiled, corruption, plan));
  assert.throws(() => assertJournal(compiled, events.slice(0, -2), plan));
  const wrong = structuredClone(events); wrong[1].payload.data.outcome = 'interrupted'; assert.throws(() => assertJournal(compiled, wrong, plan));
  checks.push(`person${person}: all384 journal accepted; fabricated withholding RT, missing trial and changed outcome refused`);
}
console.log(JSON.stringify({status: 'passed', checks, scope: 'Independent browser fixture expectations only; no services, product scoring or browser acceptance.'}, null, 2));
