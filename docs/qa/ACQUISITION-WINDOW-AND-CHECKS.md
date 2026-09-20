# Equipment time windows and reviewed acquisition checks

20 September 2026. This follows the earlier
[publication and monitoring acceptance](ACQUISITION-PUBLICATION-AND-MONITORING.md).
All new evidence uses original software-generated sources. No physical hardware,
calibration accuracy, physiological validity or device-specific reliability is
qualified by this slice.

## Bounded committed windows

`brohn-acquisition-monitoring/2.0` adds a source-time window of at most five
seconds. It uses fixed-capacity buckets, never a raw five-second buffer that
grows with sample rate. Each channel/bucket retains the first, minimum, maximum
and last actual finite source points, with original sequence, source segment,
timestamp and fragment identity. No new amplitude or timestamp is interpolated.
The point population preserves each represented bucket's extrema.

- At most eight selected preview channels per stream, sixteen streams and 4,096
  window points in total. The bucket count is `min(128, floor(4096 / (4 * total
  selected channels)))`; adding channels reduces the display resolution.
- The status file remains capped at 2 MiB. Original statistics for every recorded
  channel remain bounded separately. Up to sixteen recent committed rows per
  stream are retained independently for exact latest numeric observations,
  source-valid gaze and existing descriptive summaries. Text display remains
  limited to 64 UTF-8 bytes; canonical recording values remain complete.
- Whole expired buckets are removed, so actual retained coverage can be shorter
  than five seconds. The model exposes actual first/last source times, span,
  committed count, bucket width, plotted count and coverage policy.
- Source clock resets begin a new window. Nonfinite values, coincident/reversed
  timestamps and declared gap boundaries split waveform fragments. Lines only
  connect points in the same source segment and fragment. Isolated supported
  points remain visible as dots. Unrepresented fragment portions are counted and
  disclosed; they never create a connection across a hidden boundary.
- Source gap classification uses the reviewed source gap threshold where one was
  supplied. No universal cadence tolerance or missing-packet detector is inferred.

This monitoring copy does not resample, replace or change the original durable
chunks, timestamps, clock evidence or archive. Complete committed check counts
are accumulated before display selection; extrema points never supply a check's
denominator.

## Explicit acquisition criteria

`brohn-acquisition-readiness/1.1` supports up to eight optional named criteria per
source. The researcher can author and review them in Collect before queueing:

- exact native source-code matches, including categorical text such as `001`;
- finite numeric fraction;
- fraction within explicitly declared inclusive source-unit bounds;
- observed source cadence within explicitly declared inclusive Hz bounds.

Each criterion freezes its name/version, source channel and exact original unit,
source evidence and rationale, five-second window, minimum complete sample count,
minimum observed span, maximum committed-data age and applicable code/threshold.
Numeric support and thresholds start blank. Native text versus numeric code
handling derives from the original channel type. A criterion needs an explicit
measurement family and selected monitoring channel. Unknown units, unsupported
numeric channel formats, mismatched native code types and incomplete evidence
cannot be accepted as a reviewed criterion.

The UI shows the exact criterion before Start. Its review binds a hash of the
criterion, source UID/metadata, measurement family, channel role and unit. Editing
any dependent field clears the review; Start independently requires the matching
review hash. Adding another criterion preserves existing authored fields. The
normal acquisition request/revision/ownership boundaries remain in force.

Monitoring reports **Meets selected acquisition check**, **Selected acquisition
check unmet** or **Acquisition check unknown**, with exact observed fraction/Hz,
complete committed sample count and span. It keeps physiological quality
explicitly unqualified. Exact rule provenance is available under a closed
disclosure so it does not obscure the waveform.

Missing or mismatched criterion evidence, missing units, insufficient support,
stale committed data, closed subscriptions and unavailable telemetry remain
unknown. Fresh received-but-uncommitted data cannot renew a passing check:
committed-data age is separate from last receipt age. Cadence is `(n-1) / actual
source span` only for an uninterrupted window; a declared boundary makes that
cadence criterion unknown. A failed finite/range/source-code observation remains
an observed failure rather than being removed from the denominator.

These are researcher-declared acquisition checks, not a built-in library of
scientifically qualified device thresholds. Source text is preserved and reviewed;
Brohn does not independently certify the cited manual or protocol. Measurement
interpretation limits remain in the
[academic acceptance audit](MEASUREMENT-ACADEMIC-ACCEPTANCE.md).

## Executed acceptance

- `tests/acquisition/monitoring_window.py`: **6 tests passed**. Includes 60,000
  samples at 10 kHz across eight channels, fixed bucket storage, an exact narrow
  extreme retained with its source index/time, full denominators independent of
  plotted points, invalid/gap/reset fragmentation, actual durable gaze-code replay,
  native criterion validation and the sixteen-stream/128-channel layout with the
  global point and snapshot bounds. The maximum-layout bound test operates the
  production window accumulator directly; it does not claim a hardware throughput
  measurement.
- `tests/platform-acquisition-window.R`: **25 checks passed** using production
  Writer replay. Includes 6,000 original ECG-like values at 1 kHz, passing finite
  and cadence criteria, failing EDA range, exact native text contact codes,
  stale/closed/received-versus-committed separation, missing units, substituted
  rules/denominators, malformed window evidence and production rendering.
- Existing `tests/acquisition/lsl_recorder.py`: **23 tests passed**, including
  isolated actual LSL sources, canonical clock/value fidelity, source identity,
  commit limits, cancellation, crash prefixes and honest quality evidence.
- Existing `tests/platform-acquisition-quality.R`: **49 checks passed** across
  fifteen families through the production Writer, model and renderer.
- Strengthened `tests/platform-acquisition.R`: **53 checks passed** with an actual
  isolated synthetic LSL outlet and independent acquisition managers. The reviewed
  /1.1 criterion survives the queue and produces a passing source-bound check with
  a bounded window; archival publication, import, owner/crash recovery and reopen
  also pass. It remains unqualified physiological data.
- `tests/fixtures/researcher-acquisition-checks.R` and
  `tests/researcher-acquisition-checks.mjs`: **7 actual Chrome journey checks and
  5 clear scans**. The researcher authors EDA range/finite checks and a native
  EEG contact-code check, adds a criterion without losing a draft, changes a
  reviewed threshold, recovers from rejected Start and freezes exact units and
  text `001` in the real public queue. Production Writer replay then evaluates
  that exact queued request: range unmet, finite/code checks met, stale/closed
  unknown. Authoring and monitoring pass desktop/390 px axe, page-overflow and
  44 px control checks with no browser script errors. This journey uses seeded
  metadata-only discovery and replay after queueing; the separate 53-check suite
  supplies the independent manager/LSL evidence.

The full browser evidence is in
`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-acquisition-checks-03/browser-evidence-1789880511641`.
The final disclosure-only monitoring refresh is recorded alongside the browser
harness evidence after re-rendering the same saved replay, without re-recording
or changing any numerical result: **3 checks and 3 clear scans** in
`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-acquisition-checks-03/browser-evidence-1789881360500`.
It includes keyboard opening/closing of the saved criterion disclosure. Final
desktop/narrow waveform screenshots were inspected. Detailed browser setup and
reproduction commands are in
[the browser acceptance record](ACQUISITION-CHECKS-BROWSER-ACCEPTANCE.md).

Run Python tests with `../../work/tooling/acquisition-venv/Scripts/python.exe`.
Run R tests with `../../work/native-r/bin/Rscript.exe`, the prepared
`R_LIBS_USER=../../work/r-library-brohn-restore`, and the native publication helper
`BROHN_PUBLICATION_PYTHON=../../work/tooling/methods-venv/Scripts/python.exe`.
The browser fixture/harness accepts an isolated evidence directory and uses the
prepared local Chrome and Node runtime.

## Remaining scope

PC10 remains partial. Reusable reviewed equipment setups, device-specific
qualification, broader measurement-specific protocol libraries, native camera
frames and native implicit-delivery checks are separate work. Current gaze,
impedance, contact, camera-model and task observations require actual explicit
source mappings; no missing observable becomes a healthy/green measurement.
