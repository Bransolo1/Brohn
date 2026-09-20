# Cardiac source exclusion: implementation and acceptance

20 September 2026. **Bounded worker, saved-job and researcher-browser acceptance
passed.** This document does not qualify a detector,
artifact reviewer, physiological endpoint, physical sensor or full platform.

The implementation follows the bounded
[source exclusion contract](../methods/CARDIAC-ARTIFACT-REANALYSIS-CONTRACT.md).
The original source, parent report, input samples and detections remain unchanged.
A saved review addresses one original ECG/PPG CSV/TSV continuous table and channel.
Curated CSV inputs retain their acquisition row/clock crosswalk and full decisions.
The first version requires the parent's exact detector source hash, Python version
and NumPy/SciPy/NeuroKit package versions. An older implementation/environment
requires a fresh original analysis before review; historical results are readable.

Named policy `cardiac-source-exclusion/1.0` freezes researcher-selected half-open
source sample spans. Overlap/adjacency form one processing union, while all original
reasons remain saved. Typed seconds are resolved from the original decimal source
timestamps; they are never converted to indices by assuming a sampling rate or
subtracting a floating epoch. The resolver shows exact first/last selected times
and samples before saving. To include the final sample, the explicit exclusive
source-sample bound is available instead of inventing a timestamp beyond the data.

Every remaining run is passed independently to the unchanged parent cleaner and
detector. Excluded values cannot enter filtering or threshold estimation. Each run
gets the parent's declared edge guard, and its first retained peak has no previous
interval. Neither intervals nor successive differences cross an exclusion. Outputs
stay per-run; no pooled RMSSD, concatenated spectrum or inferred participant count
is produced. ECG remains detected RR and PPG remains detected PRV. Plausibility
screening and manual exclusion do not establish sinus-origin/NN intervals.

The preview includes the original input at parent filter edges, labels those edges
separately from researcher exclusions and calculates support before execution.
These support estimates are not predicted cardiac scores. Short/all-excluded
support remains explicitly unavailable. The parent's edge policy is an engineering
choice, not empirical proof that filter transients have disappeared.

R owns saved versions, source authority, queuing, supervised execution and result
publication. Original CSV, complete input artifact and all curated lineage objects
receive native Windows read guards before the child begins, followed by renewed
full-byte checks. Handles remain held through completion. Publication independently
holds/rechecks them and checks current project/source authority inside its final
transaction. Stale/cancelled attempts cannot publish. This initial publication
route requires the existing qualified Windows guard; it is not a new OS claim.

## Executed worker evidence

- `tests/workers/cardiac_review.py`: 12 tests pass. They cover exact canonical ECG
  conversion, large decimal epochs, typed boundary membership, overlap/adjacency,
  final samples, empty/short/all-excluded support, source/mapping/clock/person/method
  substitution, actual standalone-versus-separated ECG/PPG processing, independent
  interval/RMSSD arithmetic and one-sample gaps. Replacing only excluded PPG values
  with extreme values leaves all surviving processed rows, events and features
  exactly unchanged.
- Independent second-person/nonzero source-index probe: six checks pass at
  `oka/work/cardiac-review-peer-01/group-coordinate-result.json`. A second
  recording begins at source row6000; its retained runs keep original person,
  source row and recording-relative time identities.
- Independent environment gate: seven checks pass at
  `oka/work/cardiac-review-engine-peer-02/results.json`. Six reverified typed
  artifacts declaring a different detector hash, Python, NumPy, SciPy, NeuroKit
  version or parent operation are refused. These are historical-metadata
  simulations; old binaries were not run.
- `tests/workers/cardiac_review_curation.py`: 11 tests pass, using actual existing
  stream extraction, parent physiology and cardiac review. Its8009 original rows
  yield8002 derived rows; selected derived row2100 maps to acquisition sequence2107
  with its original large nanosecond timestamp. Full decision/CSV identity checks,
  130-endpoint storage bound, separate reanalysis, tampering and changed-during-read
  rejection pass. Evidence: `oka/work/cardiac-review-curation-tjueln69/acceptance.json`.

These numerical tests establish tested source, boundary and isolation behavior.
They do not validate the chosen exclusions, automatic artifact discovery, detector
accuracy, normal-beat classification or PRV/HRV interchangeability. The existing
MIT-BIH and CapnoBase sources used for integration are known regression recordings.
No parameter tuning, new holdout accuracy claim or benchmark training is performed.

## Saved integration and browser evidence

`tests/platform-cardiac-review.R` passed **38 checks across 10 supervised jobs**
in `oka/work/brohn-cardiac-review-02/acceptance.json`. Both original ECG and PPG
complete source-to-preview, exact typed boundary resolution, saved decisions,
separate reports, undo/history, cancellation/retry and reopening. Each original
source permits a non-mutating write-open before its native guard, refuses it
during real report publication, and permits it again afterward; original bytes
and parent reports remain exact. The test clears ordinary read-only attributes
only in its copied workspace before these controls and restores them afterward.
The earlier 34-check `-01` run remains retained, but its denial-only probe did not
distinguish native guards from existing read-only attributes.

The independent [curated-source suite](CARDIAC-EXCLUSION-CURATED-SOURCE-ACCEPTANCE.md)
passes **24 checks across eight supervised jobs**, including one deliberately
refused final publication and successful retry. Seven original/derived/parent
objects pass the before/during/after write-open controls. Nine independent
authority revocations, exact acquisition crosswalks, same-size corruption and
reopening are covered. Both R suites preceded the reader-cleanup-only correction
below; their complete per-job source identities remain saved.

Real researcher browser acceptance passes **17 assertions, two desktop/390-pixel
scans and four supervised jobs** after the cleanup correction. The exact typed
request resolves 864 original samples, creates a saved version, previews two
separate runs and publishes its matching report. Parent JSON remains unchanged;
source-row edit and restoration preserve version history. Immediate keyboard
actions, readable narrow tables, actual horizontal keyboard scrolling and
downloads pass. Seven adapter, 19 Shiny and five formatting checks also pass.
See the [interface record](CARDIAC-ARTIFACT-REVIEW-UI.md) for the final matched
source hashes and evidence. Earlier visual inspection caught an unreadable
narrow table despite passing automated overflow checks; that failure is retained.

## Retained corrections

Initial implementation compared a full artifact's method-bearing descriptor with
the intentionally compact catalog descriptor. Matching now uses the catalog's
declared fields and separately verifies the full original method. The initial
test cleanup exposed retained generator handles on callback exceptions in the
existing artifact reader. The reader now closes its generator in `finally`.
Five permanent regressions in `tests/workers/artifact_reader_cleanup.py` first
failed and now pass with the original exception traceback still retained:
table/row callback failures, interruption, invalid header and structural rejection.
They inspect real stream closure and rename/restore the original file without
garbage collection. Existing artifact checks pass 25 tests with two unrelated
environment-specific skips. The 12 cardiac and 11 curated cardiac worker tests
also pass after cleanup. No detector or numerical processing changed.

The time-resolution oracle initially compared equivalent decimal formatting
(`0.300000` versus `0.300`). It now compares exact Decimal values, without rounding
or tolerance. A Windows C-locale parse issue in a new display title was corrected
to ASCII. Independent review caught the omitted detector-environment gate; the
new gate and its adversarial checks are included above.
