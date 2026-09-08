// node tests/check-wire.mjs <fixture-directory>; fixtures emitted by tests/run.R
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
export async function checkWire(directory) {
  const b = JSON.parse(await fs.readFile(path.join(directory, 'bundle.json'), 'utf8'));
  const precision = JSON.parse(await fs.readFile(path.join(directory, 'precision.json'), 'utf8'));
  assert.equal(precision.study.revision, Number.MAX_SAFE_INTEGER);
  assert.equal(precision.study.questions[0].revision, 1234567890123456);
  assert.equal(precision.events[2].sequence, Number.MAX_SAFE_INTEGER);
  await fs.writeFile(path.join(directory, 'precision.node.json'), JSON.stringify(precision));
  const empty = JSON.parse(await fs.readFile(path.join(directory, 'empty.json'), 'utf8'));
  const images = JSON.parse(await fs.readFile(path.join(directory, 'images.json'), 'utf8'));
  const report = JSON.parse(await fs.readFile(path.join(directory, 'sample-report.json'), 'utf8'));
  const imported = JSON.parse(await fs.readFile(path.join(directory, 'import-report.json'), 'utf8'));
  const protocol = JSON.parse(await fs.readFile(path.join(directory, 'protocol.json'), 'utf8'));
  assert.equal(protocol.status, 'planned');
  assert.equal(protocol.study.revision, 1234567890123456);
  assert.equal(protocol.study.questions[0].revision, Number.MAX_SAFE_INTEGER);
  assert.ok(Array.isArray(protocol.registry.trials));
  assert.ok(Array.isArray(protocol.registry.exposures));
  assert.ok(Array.isArray(protocol.registry.epochs));
  assert.ok(Array.isArray(protocol.registry.orders));
  for (const order of protocol.registry.orders) assert.ok(Array.isArray(order.trial_ids));
  for (const epoch of protocol.registry.epochs) {
    if (epoch.phase === 'passive_viewing') {
      assert.equal(epoch.question_id, null);
      assert.equal(epoch.question_revision, null);
    } else assert.equal(epoch.planned_duration_ms, null);
  }
  await fs.writeFile(path.join(directory, 'protocol.node.json'), JSON.stringify(protocol));
  assert.equal(imported.origin, 'imported_prepared');
  assert.equal(imported.status, 'unqualified');
  const originalCsv = Buffer.from(imported.source.data_base64, 'base64');
  assert.equal(createHash('sha256').update(originalCsv).digest('hex'), imported.source.sha256);
  assert.equal(originalCsv.length, imported.source.byte_count);
  assert.deepEqual(imported.study.measures, ['eye']);
  assert.equal(imported.analysis.summary[0].mean_difference_pp, 20);
  assert.equal(report.origin, 'synthetic_demonstration');
  assert.equal(report.analysis.status, 'unqualified');
  assert.deepEqual(report.study.measures, ['eye']);
  assert.deepEqual(report.study.questions, []);
  assert.deepEqual(report.study.comparison, {control_condition:'A', rationale:'Current design, same viewing task'});
  assert.deepEqual(report.study.presentation, {order:'counterbalanced_ab_ba', viewing_duration_ms:6000});
  assert.equal(report.prepared_intervals[2].x, null);
  assert.equal(report.analysis.summary[0].mean_difference_pp, 20);
  assert.equal(images.study.stimulus_assets.length, 2);
  for (const asset of images.study.stimulus_assets) {
    const bytes = Buffer.from(asset.data_base64, 'base64');
    assert.equal(createHash('sha256').update(bytes).digest('hex'), asset.sha256);
    assert.equal(bytes.readUInt32BE(16), asset.width);
    assert.equal(bytes.readUInt32BE(20), asset.height);
    assert.equal(bytes.toString('base64'), asset.data_base64);
  }
  assert.equal(b.session.mode, 'sample');
  assert.equal(b.events[2].source_time.value, '1234567890123456783');
  assert.equal(b.events[2].response.value, 6);
  assert.deepEqual(b.events.map(e => e.response.status), ['unanswered', 'skipped', 'answered']);
  assert.deepEqual(b.events.slice(0, 2).map(e => [e.response.option_id, e.response.value]), [[null, null], [null, null]]);
  assert.ok(Array.isArray(b.study.measures));
  assert.deepEqual(empty.study.measures, ['eye']);
  assert.deepEqual(empty.study.questions, []);
  assert.deepEqual(empty.events, []);
  for (const e of b.events) {
    assert.equal(e.run_id, b.session.id);
    assert.equal(e.study_revision, b.study.revision);
    assert.equal(e.mode, b.session.mode);
    assert.equal(e.response.question_id, b.study.questions[0].id);
    assert.deepEqual(e.response.displayed_option_ids, b.study.questions[0].option_ids);
  }
  await fs.writeFile(path.join(directory, 'bundle.node.json'), JSON.stringify(b));
  await fs.writeFile(path.join(directory, 'images.node.json'), JSON.stringify(images));
  await fs.writeFile(path.join(directory, 'sample-report.node.json'), JSON.stringify(report));
  await fs.writeFile(path.join(directory, 'import-report.node.json'), JSON.stringify(imported));
  console.log('PASS: JavaScript wire checks and re-encoding');
}
if (process.argv[2]) await checkWire(process.argv[2]);
