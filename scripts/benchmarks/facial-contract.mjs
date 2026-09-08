// Offline specification replay; not a FaceReader parser, SDK or model adapter.
// Native field names and the single documented numerical example are attributed
// below. Other cases are authored synthetic probes, with no participant data.
import assert from 'node:assert/strict';
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const sources = {
  api: 'https://noldus.com/shared/resources/book/noldus-product-documentation/chapter/facereader/page/facereader-9-api-overview-and-usage',
  log: 'https://noldus.com/shared/resources/book/noldus-product-documentation/chapter/facereader/page/facereader-10-detailed-log',
};
const checks = [];
function check(name, body) {
  body();
  checks.push({ name, status: 'pass' });
}
function ticksToSeconds(raw) {
  if (typeof raw !== 'string' || !/^\d+$/.test(raw)) throw new Error('ticks require a decimal string');
  const ticks = BigInt(raw);
  const tail = (ticks % 10000000n).toString().padStart(7, '0').replace(/0+$/, '');
  return `${ticks / 10000000n}${tail ? '.' + tail : ''}`;
}
function clockDomain(analysisType) {
  if (analysisType === 'Video') return 'video-relative';
  if (analysisType === 'Camera') return 'since-analysis-start';
  throw new Error('unmapped analysis type');
}
function extractTypedValue(item) {
  if (item.Type === 'Value' && Array.isArray(item.Value) && item.Value.every(Number.isFinite)) {
    return { native_label: item.Label, kind: 'numeric', values: [...item.Value] };
  }
  if (item.Type === 'State' && Array.isArray(item.State) && item.State.every(x => typeof x === 'string')) {
    return { native_label: item.Label, kind: 'state', values: [...item.State] };
  }
  throw new Error('unmapped or malformed classification type');
}
// Brohn's proposed boundary behavior, not a claim that these tokens have a
// particular location in FaceReader XML. The source defines detailed-log tokens.
function missingness(raw, present = true) {
  if (!present) return { usable: false, reason: 'field-absent', value: null };
  if (raw === null) return { usable: false, reason: 'null-unmapped', value: null };
  const reasons = { FIND_FAILED: 'face-not-found', FIT_FAILED: 'face-model-failed', MISSING: 'frame-skipped' };
  if (Object.hasOwn(reasons, raw)) return { usable: false, reason: reasons[raw], value: null };
  if (typeof raw === 'number' && Number.isFinite(raw)) return { usable: true, reason: null, value: raw };
  return { usable: false, reason: 'unmapped-token', value: null };
}

const documentedSubset = {
  origin: 'public-documentation-example',
  specification: 'FaceReader 9 API technical note',
  AnalysisType: 'Video', FrameTimeTicks: '3697600000',
  classification: { Type: 'Value', Label: 'Neutral', Value: [0.201352075], State: [] },
};
check('published frame ticks reproduce 369.76 seconds exactly', () => {
  assert.equal(ticksToSeconds(documentedSubset.FrameTimeTicks), '369.76');
});
check('camera and video use distinct documented clock origins', () => {
  assert.equal(clockDomain('Video'), 'video-relative');
  assert.equal(clockDomain('Camera'), 'since-analysis-start');
  assert.throws(() => clockDomain('unknown'));
});
check('published numeric label and array remain native', () => {
  assert.deepEqual(extractTypedValue(documentedSubset.classification), {
    native_label: 'Neutral', kind: 'numeric', values: [0.201352075],
  });
});
check('state classification is never coerced to numeric intensity', () => {
  assert.deepEqual(extractTypedValue({ Type: 'State', Label: 'Dominant Expression', State: ['Happy'], Value: [] }), {
    native_label: 'Dominant Expression', kind: 'state', values: ['Happy'],
  });
});
check('synthetic zero, null and absent remain distinct', () => {
  assert.deepEqual(missingness(0), { usable: true, reason: null, value: 0 });
  assert.equal(missingness(null).reason, 'null-unmapped');
  assert.equal(missingness(undefined, false).reason, 'field-absent');
});
check('documented detailed-log failure tokens remain missing', () => {
  assert.equal(missingness('FIND_FAILED').reason, 'face-not-found');
  assert.equal(missingness('FIT_FAILED').reason, 'face-model-failed');
  assert.equal(missingness('MISSING').reason, 'frame-skipped');
  assert.equal(missingness('configured-custom-token').reason, 'unmapped-token');
});
check('synthetic timestamp above JavaScript safe integer remains exact', () => {
  assert.equal(ticksToSeconds('9007199254740993'), '900719925.4740993');
  assert.throws(() => ticksToSeconds(9007199254740993));
});
check('synthetic multi-value arrays and unsupported types remain explicit', () => {
  assert.deepEqual(extractTypedValue({ Type: 'Value', Label: 'Example', Value: [1, 2] }).values, [1, 2]);
  assert.throws(() => extractTypedValue({ Type: 'Unknown', Label: 'Example', Value: [1] }));
  assert.throws(() => extractTypedValue({ Type: 'Value', Label: 'Example', Value: [NaN] }));
});

const report = {
  schema: 'brohn-facial-contract-evidence/0.1.0-draft',
  origin: 'public-documentation-example-and-synthetic-contract-probes',
  qualification: 'offline-specification-replay-only',
  checked_on: '2026-09-08', runtime: process.version,
  sources,
  public_example: documentedSubset,
  passed: checks.length, failed: 0, checks,
  limitations: [
    'No vendor SDK, model weights, camera, participant data, upload or paid endpoint was used.',
    'This is not a full XML parser, live API test, supported FaceReader 10 wire contract or model validation.',
    'No model version, model determinism, classification accuracy or timing accuracy was established.',
    'Custom missing tokens, acquisition timestamps and XML placement require a versioned vendor fixture.',
  ],
};
const output = new URL('../../docs/methods/reuse/facial-contract-results.json', import.meta.url);
mkdirSync(fileURLToPath(new URL('.', output)), { recursive: true });
writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
console.log(`Facial contract replay: ${checks.length} checks passed; offline examples only.`);
