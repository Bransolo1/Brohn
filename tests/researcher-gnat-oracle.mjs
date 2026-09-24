// Independent expectations for original browser inputs. No product scorer import.
import assert from 'node:assert/strict';
export const profile = 'gnat-brohn-single-target/1.0';
export const aliases = ['ORIGINAL-GNAT-001', 'ORIGINAL-GNAT-002'];
export function responsePlan(compiled, person) {
  assert.equal(compiled.profile, profile);
  assert.ok([0, 1].includes(person));
  const trials = compiled.timeline.filter(t => t.type === 'task_trial');
  assert.equal(trials.length, 384);
  const seen = new Map();
  return trials.map(trial => {
    let respond = trial.expected_action === 'go';
    if (trial.phase === 'test') {
      const positive = trial.pairing === 'target_positive';
      const limits = person === 0 ? (positive ? [24, 6] : [18, 12]) : (positive ? [21, 3] : [15, 9]);
      const key = `${trial.cell_id}:${trial.expected_action}`;
      const position = (seen.get(key) || 0) + 1; seen.set(key, position);
      respond = position <= limits[trial.expected_action === 'go' ? 0 : 1];
    }
    const outcome = trial.expected_action === 'go' ? (respond ? 'hit' : 'miss') : (respond ? 'false_alarm' : 'correct_rejection');
    return {trial_id: trial.id, phase: trial.phase, cell_id: trial.cell_id, respond, outcome};
  });
}
export function assertJournal(compiled, events, plan) {
  const started = events.filter(e => e.type === 'task_event' && e.payload.kind === 'task_trial_started');
  const finished = events.filter(e => e.type === 'task_event' && e.payload.kind === 'task_trial_finished').map(e => e.payload.data);
  assert.equal(started.length, 384); assert.equal(finished.length, 384);
  assert.deepEqual(finished.map(r => r.trial_id), plan.map(r => r.trial_id));
  assert.deepEqual(finished.map(r => r.outcome), plan.map(r => r.outcome));
  for (let i = 0; i < plan.length; i++) {
    const actual = finished[i], expected = plan[i];
    assert.equal(actual.response_outcome, expected.outcome);
    assert.equal(actual.correct, ['hit', 'correct_rejection'].includes(expected.outcome));
    if (!expected.respond) {assert.equal(actual.response_code, null); assert.equal(actual.response_ms, null);}
    else {assert.equal(actual.response_code, 'Space'); assert.ok(actual.response_ms >= 0);
      assert.ok(actual.response_ms < compiled.timeline.find(t => t.id === actual.trial_id).timeout_ms);}
  }
  return finished;
}
// Python statistics.NormalDist is evaluated separately by the harness for the
// numerical oracle. These counts are authored independently of saved results.
export function expectedCells(person) {
  const cells = [];
  for (const round of [1, 2]) for (const sign of ['positive', 'negative']) {
    const [hits, falseAlarms] = person === 0 ? (sign === 'positive' ? [24, 6] : [18, 12]) : (sign === 'positive' ? [21, 3] : [15, 9]);
    cells.push({id: `r${round}-${sign}`, deadline_ms: round === 1 ? 750 : 600,
      hits, misses: 30 - hits, false_alarms: falseAlarms, correct_rejections: 30 - falseAlarms});
  }
  return cells;
}
export function assertScore(score, person, numericOracle) {
  assert.equal(score.profile, profile); assert.equal(score.status, 'computed'); assert.equal(score.eligible, true);
  assert.deepEqual(score.counts, {expected: 384, received: 384, expected_training: 80, expected_practice: 64,
    expected_test: 240, training: 80, practice: 64, test: 240, interrupted: 0});
  assert.equal(score.scoring_audit.cells.length, 4); assert.equal(score.metrics.length, 10);
  for (const cell of expectedCells(person)) {
    const actual = score.scoring_audit.cells.find(c => c.id === cell.id);
    for (const [key, value] of Object.entries(cell)) assert.equal(actual[key], value);
    const oracle = numericOracle.find(c => c.id === cell.id);
    assert.ok(Math.abs(actual.d_prime - oracle.d_prime) < 1e-12);
    assert.ok(Math.abs(actual.criterion - oracle.criterion) < 1e-12);
    assert.equal(actual.raw_rates.hit, cell.hits / 30); assert.equal(actual.raw_rates.false_alarm, cell.false_alarms / 30);
    assert.deepEqual(actual.endpoint_adjustments, {hit: false, false_alarm: false});
    assert.equal(actual.response_rt.hit.n, cell.hits); assert.equal(actual.response_rt.false_alarm.n, cell.false_alarms);
  }
  for (const round of [1, 2]) {
    const expected = numericOracle.find(c => c.id === `r${round}-positive`).d_prime - numericOracle.find(c => c.id === `r${round}-negative`).d_prime;
    assert.ok(Math.abs(score.metrics.find(m => m.name === `GNAT_r${round}_target_positive_contrast`).value - expected) < 1e-12);
  }
  assert.ok(score.metrics.every(m => m.unit === 'dimensionless'));
}
