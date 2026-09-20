# Acquisition publication and equipment monitoring acceptance

20 September 2026. Software qualification on the prepared Windows profile only.
All source material in these tests is generated or replayed. No physical device,
person, electrode contact, gaze calibration or timing accuracy was qualified.

## Guarded manager publication

The independent acquisition manager now uses the existing qualified Windows
native publication guard for the complete original recording archive and for
the separate reviewed stream-bundle import. Acquisition publication jobs are
reserved operations: `acquisition_preserve` and `acquisition_prepare`. Generic
analysis workers cannot claim either queued or expired running reservations.

Each attempt records the exact manager process identity, workspace, acquisition
revision and body hash, plus acquisition/recorder implementation hashes. The
manager owns an exact job fence. Preparation, archive validation, bulk copying,
hashing and export happen outside the SQLite writer transaction. Checkpoints
validate job/manager/source authority and renew the lease. Native file guards
remain held through the final metadata transaction.

Original archive registration, the retained publication receipt, the new
acquisition revision and successful job completion commit together. Reviewed
import likewise commits the retained bundle/receipt, accepted dataset, exact
dependent `normalise_dataset` job and acquisition revision together. The dataset
starts at revision 1, already accepted, rather than exposing intermediate
unreviewed revisions. Review extraction uses the preserved immutable archive,
not the mutable former recording directory. Every extracted member must match
the full retained inventory before export.

A restarted manager cancels an old reserved attempt only when its exact owner
is proven absent. A live or ambiguous owner blocks takeover. Failure retains
the original source and requires a fresh fenced attempt; it does not fabricate
recording completion. Cancellation can interrupt native staging. Synchronous
ZIP creation/extraction notices cancellation at the following checkpoint.

Metadata-only discovery remains on its prior direct object-registration path.
Its JSON reader/receipt is bounded to 16 MiB; this acceptance does not claim that
path was converted to staged publication. The recorder source sample-byte limit
is 512 MiB, the complete original archive inventory limit is 700 MiB, and the
existing separate stream-bundle exporter remains limited to 64 MiB.

`tests/platform-acquisition-publication.R`: **23 checks passed** using actual
processes, native seals and SQLite rollback triggers. Coverage includes both
generic-worker exclusions, expired/cancelled fences, substituted ownership,
archive and review transaction rollback, fresh retry, exact dependent-job
identity, changed mutable recording tree, cancelled and stale publication,
actual killed-manager recovery and store reopen. A separate participant HTTP
receiver acknowledged an event during native copying of an original archive
containing **128 MiB of incompressible generated diagnostic bytes**. That local
receipt took **0.311259 seconds**, remained exactly idempotent, and did not make
the synthetic bytes into sensor measurements or establish a latency guarantee.

## Equipment observations

This section records the first bounded monitoring acceptance. The subsequent
`monitoring/2.0` time windows and `readiness/1.1` authoring, exact review and named
acquisition checks are qualified separately in
[Equipment time windows and reviewed acquisition checks](ACQUISITION-WINDOW-AND-CHECKS.md).

The recorder now emits `brohn-acquisition-monitoring/1.0` in its atomic status
file. It distinguishes subscription state, received samples and durable committed
samples. Monitoring contains at most 16 recent committed rows per stream and
eight explicitly selected preview channels, with statistics for every original
channel. Text previews are limited to 64 UTF-8 bytes. The entire status file is
bounded to 2 MiB. Canonical chunks retain complete original values, source clock
representations and byte-level evidence independently of those monitoring limits.

Sample age uses the recorder's monotonic clock plus local elapsed wall time since
the snapshot. It is not a measurement of hardware transport delay or cross-device
clock alignment. Observed cadence is the inverse median of positive source-time
intervals within a source segment in the bounded preview; reversals are excluded,
not resampled. Declared gap thresholds and source resets stay explicit.

The saved `brohn-acquisition-readiness/1.0` declaration binds measurement family,
original channel roles/units, preview selection, optional source rails and source
context to the frozen recording request. Missing, foreign or legacy telemetry
stays unknown. A running service alone no longer produces a green equipment-ready
claim. UI badges separately describe subscription, receipt and committed writes;
measurement quality remains explicitly unqualified.

The production monitor has typed observations for gaze, ECG, PPG, EEG, EDA,
fNIRS, respiration, EMG, EOG, temperature, movement, audio, camera telemetry,
implicit-task telemetry and unclassified sources. These are descriptive source
observations, not a replacement for each measurement's retained analysis pipeline.
In particular:

- Gaze position requires explicit X/Y/validity mapping, matching original units,
  frame, coordinate origin, eye identity and the source's valid code. Invalid
  latest samples never substitute an earlier valid eye position. Pixel coordinates
  require declared dimensions. Calibration accuracy remains unqualified.
- EEG impedance/contact, PPG motion/contact, camera face counts/confidence and
  task timing/input states appear only as explicitly mapped source observations.
  No such values are inferred from generic amplitude or process state.
- Negative declared EDA conductance and nonpositive fNIRS intensity are flagged.
  Repeated values and declared-rail excursions are described without invented
  physiological thresholds. Respiration, EMG/EOG and temperature retain native
  waveforms/units without inferred diagnosis, calibrated volume, force or gaze.
- Movement magnitude is an explicitly mapped same-unit XYZ norm and retains the
  declared frame/gravity policy. Audio RMS names its finite sample count and raw
  bounded window; it does not imply pressure calibration or an emotion estimate.
- Camera and task adapters here cover supplied LSL telemetry. They do not invent
  camera frames or replace native camera/task delivery checks.

Scientific interpretation and future profile criteria must follow the
[measurement academic acceptance audit](MEASUREMENT-ACADEMIC-ACCEPTANCE.md).
Any future usable-quality rule must identify its source, settings, window and
minimum support; no universal green threshold was added here.

## Recorded verification

- `tests/platform-acquisition.R`: **52 checks passed** with a real isolated
  synthetic LSL outlet and independent manager processes, including saved EDA
  roles, actual subscribed/received/committed telemetry, preservation, reviewed
  import, manager crash recovery, exact archive identity and reopen.
- `tests/acquisition/lsl_recorder.py`: **23 tests passed**. Actual local LSL and
  direct production-Writer cases cover source-clock/value fidelity, nonfinite
  samples, no-sample completion, committed-versus-unwritten counts, monitoring
  selection, bounded Unicode previews with full canonical strings, corruption,
  original limits and honest interrupted quality evidence.
- `tests/platform-acquisition-quality.R`: **49 checks passed** across 15 families
  replayed through the production Writer into the R model and production UI
  renderer. Includes source validity/roles/units, gaps/resets, bounded/full source
  separation, invalid-gaze behavior, exact XYZ/audio support, foreign/missing
  telemetry and finite extreme-value SVG coordinates.
- `tests/researcher-acquisition-quality.mjs`: **13 checks passed** in real Chrome
  against the production renderer with original replay evidence. Desktop and
  390-pixel layouts have zero axe violations, no horizontal page overflow and
  disclosure targets of at least 44 pixels. Narrow EDA/gaze screenshots were
  inspected. This is component browser acceptance, not a physical device test.

Retained replay models, HTML, browser results, axe reports and screenshots are
under `work/test-runs/brohn-monitoring-replay-20260920` in the outer `make`
workspace. Test commands use the prepared R library
`../../work/r-library-brohn-restore`, Rscript
`../../work/native-r/bin/Rscript.exe`, publication Python
`../../work/tooling/methods-venv/Scripts/python.exe` and acquisition Python
`../../work/tooling/acquisition-venv/Scripts/python.exe`.
