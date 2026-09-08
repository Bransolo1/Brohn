# Brohn researcher acceptance and independent oracles

Prepared 2026-09-08. Owner: independent researcher QA workstream. This is a
software evaluation from the perspective of a consumer researcher designing,
running and reporting a study. **It is not observed human usability research,
live-device qualification or evidence that every proposed method is valid.**
The [machine-readable fixture](../../tests/fixtures/researcher-scenarios.json)
contains original fictional data, independent expected values and acceptance
stories. Its execution ledger links the verified actual-browser harnesses and
their evidence hashes. Original scenario bundles retain `not_executed` until
every exact clause is exercised together; narrower executed coverage is recorded
in the ledger and below rather than overstating those original bundles.

## The study the evaluator must actually complete

Research question: does the revised package B attract more valid gaze to its
logo than current package A, and is its explicit liking different? A is the
experimental control. A neutral, protocol-controlled screen supplies a separate
physiological baseline. Passive viewing lasts five seconds per image; liking
follows each image and must be excluded from passive-viewing physiology/gaze.
An EDA recipe adds independently reported response activity; it does not create
an emotion, preference or causal attribution score.

Use two original fixture images with the same declared display geometry and
semantic logo AOI. Select counterbalanced AB/BA; inspect both participant
previews, practice, consent and debrief. Collect fictional pilot runs separately
from the analytical cohort. Import the supplied deterministic prepared measures
where live hardware is unavailable, keeping that source visible. Four fictional
participants have five sessions; one participant returns, and one control-image
gaze stream fails while that person's liking remains valid. Correct an AOI,
compare old and new reports, close collection, find the historical report,
clone the design, export/import it, and confirm the new study is empty.

The fixture timings and numerical policies are deliberately simple test inputs,
not universal sensor or protocol recommendations. A five-second exposure alone
does not establish enough duration for HRV or an EDA event-response method.

## Acceptance matrix

| ID | Researcher/participant action | Independent oracle or visible outcome | Failure severity |
|---|---|---|---|
| RQA-01 | Create the controlled package study and review its phases | Control A, baseline, practice, passive viewing and questions are distinct; B minus A is explicit | Critical |
| RQA-02 | Preview AB and BA, pilot, then release a frozen revision | Correct stimulus and liking referents in both orders; pilot never enters cohort; later edits do not change an open release | Critical |
| RQA-03 | Open a participant entry point in a fresh browser | Pinned runner works without researcher access; consent/eligibility/debrief; loopback is labelled local and not presented as an internet URL | Critical |
| RQA-04 | Change a survey branch, submit zero/false, correct required response | Truth table in fixture; hidden dependent answer removed from current scoring but retained in history; item error receives focus | Critical |
| RQA-05 | Submit a session, replay receipt, reconnect and start next participant | One allocation/run/result for same submission key; exact event sequence; previous participant state does not carry over | Critical |
| RQA-06 | Import, map and accept prepared eye data for five sessions | Raw bytes stay immutable; unique participant/session/presentation linkage; invalid geometry, units or overlapping intervals need repair | Critical |
| RQA-07 | Read automatic gaze and liking comparison | 3 people contribute gaze, 4 liking; gaze mean 10.8333333333 pp, liking mean 1.375 scale points; no frame/session pseudoreplication | Critical |
| RQA-08 | Continue after optional gaze fails for P04's A presentation | A gaze and paired gaze unavailable; B share 30%; liking difference +2 retained; absent data never becomes zero | Critical |
| RQA-09 | Inspect EDA peaks, windows and baseline subtraction | Count/rate, responder mean, mean magnitude and missing-window counts match fixture; units and separate denominators visible | Critical |
| RQA-10 | Review synchronized gaze/EDA and question phases | Clock transform and support explicit; missing/too-uncertain maps disable only cross-modal analysis; motor/question samples excluded | Critical |
| RQA-11 | Revisit study history, amend AOI and reanalyse | Original per-session difference +25 pp retained; amended fixture +12.5 pp has new AOI/config/result identity; source bytes unchanged | Critical |
| RQA-12 | Clone selected historical design and run it anew | Design semantics copied with lineage; new study and run state; zero participants/answers/results/invites; original report unchanged | Critical |
| RQA-13 | Save template, export, import into a clean workspace | Controls, phases, branch truth tables, timing, AOI and recipe settings preserved independently of ID remapping; unsupported dependencies are visible | Critical |
| RQA-14 | Cancel import, retry a corrupt package or encounter lost disk/write access | No visible partial study or overwritten original; readable repair, safe retry; non-executable design import | Critical |
| RQA-15 | Execute timed BIAT and inspect correction events | First error 400 ms, final-correct 650 ms; native ticks exact; 64 candidate scored trials, 6/63 fast fraction after one slow trial | Critical |
| RQA-16 | Configure AAT, inspect mappings and interpret its report | Test double mean difference +100 ms; keyboard task never reports joystick movement; physical device unavailable gives an actionable route | Critical |
| RQA-17 | Use keyboard, narrow window and reduced motion through whole study | All actual commands operable; focus follows errors/dialog close; tables explain charts; researcher appearance cannot change participant luminance/timing | Major |
| RQA-18 | Close collection, archive, restore and reopen historical results | No new enrollment after closure; pending runs retain explicit outcome; archive/restore does not reopen deployment or resurrect purged data | Critical |

These 18 executable stories supplement the [34 product journeys](../product/journey-acceptance.json).
They do not reduce the 50-capability scope. For each enabled method pack, repeat
the shared author/import → eligibility → processing → review → report → reopen
route with its named numerical oracle and data contract. A menu, generic plot or
successful library import is insufficient evidence that its route works.

## Independent numerical expectations

The JSON fixture is authored without calling Brohn's analysis functions.

- Gaze uses `100 * inside_duration / valid_passive_duration`; invalid and active
  periods are not denominator time. P01's two session differences are +25 and
  +20 pp; its prespecified within-person average is +22.5. P02 contributes +10
  and P03 zero. The group mean is `(22.5 + 10 + 0) / 3 = 10.8333333333` pp.
  P04 has missing A gaze, so no pair. The tempting +13.75 pp session mean is
  explicitly wrong for this declared equal-person estimand. A different
  prespecified mixed model is a different estimand and needs its own oracle.
- Liking person differences are +2.5, +1, 0 and +2. Mean +1.375 uses four
  people. These ordinal ratings do not make physiological arousal into liking.
- Two accepted EDA peaks in 10 valid seconds yield 12 peaks/minute. Their
  amplitudes 0.2 and 0.4 microSiemens average 0.3. Across three complete event
  windows with magnitudes 0.2, 0.4 and zero, mean magnitude is 0.2, response
  probability 2/3. A fourth unavailable window contributes no invented zero.
- BIAT's complete procedure is separately gated. A tiny hand pair-score fixture
  tests only the denominator algebra; its eight values must be rejected as an
  incomplete full BIAT. Fast-fraction fixtures preserve pre-bounding latencies.
- AAT's +100 ms is the explicitly defined double mean difference of original
  synthetic cells; it is not a universal individual preference cutoff.

Compare numbers at the fixture tolerances; compare identities, units, phase,
exclusion reasons and origin exactly. Deliberately change a denominator, swap
A/B, duplicate a submission or clear a required mapping to establish that the
test detects a defect. Do not loosen a failing oracle to match the application.

## How to execute and record the QA layer

1. **Contract/arithmetic:** a test harness reads this fixture and calls product
   services. Assert the independent constants, complete failure states and raw
   hash preservation. Save product revision, command, fixture hash and actual
   output. Fixture self-consistency is a separate check, not product acceptance.
2. **Researcher walkthrough:** use a clean temporary workspace and the actual
   browser UI. Perform the study above; collect screenshots, field values,
   visible report tables/downloads and reproducible defects. A test-only import
   seam may load fixture signals; never relabel them as participant capture.
3. **General QA:** persistence/restart, stale revision, duplicate submission,
   import bounds, accessibility, error recovery and participant-route isolation.
   Tests must assert application behaviour, not only matching static markup.
4. **Human/device evidence:** separately observe novice researchers and measure
   the specified physical station. Record population, rig/version, task and
   outcomes. Until then, comprehension, click targets, timing accuracy and
   construct interpretation retain their actual evidence status.

For every run, record `not_executed`, `passed`, `failed`, or `blocked` with an
explicit evidence type: `synthetic_service_execution`, `automated_browser`,
`agent_walkthrough`, `observed_human`, or `named_device_measurement`. A blocked
provider/device does not excuse an unrelated software failure. An agent can
simulate a researcher's workflow; it cannot record invented human observations.

Critical failures include wrong scientific identity/units/denominator, missing
data presented as zero, mixed origins, hidden reanalysis, participant data in a
clone, silent study mutation or inaccessible participant delivery. Major
failures prevent independent completion or error recovery. Repair and repeat
the affected journey plus its dependent outputs. Keep unsupported routes
truthfully unavailable, while completing the supported end-to-end route.

Architecture changes discovered in this exercise must update the
[master](../MASTER-ARCHITECTURE.md) and relevant shared contract before independent
implementers diverge. Existing method reuse limits remain binding:
[gaze](../methods/reuse/GAZE-REUSE.md), [EDA](../methods/reuse/EDA-ANALYSIS.md),
[implicit](../methods/reuse/IMPLICIT-REUSE.md), [controls](../methods/CONTROL-DESIGN.md)
and [portable designs](../product/DESIGN-PORTABILITY.md).

## Executed software checkpoints

2026-09-08: [platform-core assertions](../../tests/platform-core.R) execute the
actual R domain/compiler/clone functions with independent fixture expectations.
Coverage includes phase separation, two/three-condition allocation, RNG
preservation, typed zero/false logic, scope-dependent branches, clone identity
remapping, strict JSON and legacy migration. This is `synthetic_service_execution`.
The 18 complete stories are broader than these individual checks and are not
marked globally passed.

The workstream subsequently implemented portable designs under explicit parent
assignment, so its [90 passing portability assertions](../../tests/platform-portability.R)
are implementation tests awaiting parent review, not an independent external
audit. They exercise real ZIP/catalog roundtrips, non-ASCII text, independently
specified control/branch/AOI behavior, 25 malformed/adversarial packages,
transaction rollback and safe orphan reconciliation. The package profile includes
the implemented comparison/questionnaire schema and registered implicit task
profiles; arbitrary executable task blocks and unregistered recipes are rejected
rather than silently discarded. Known selected
measure dependencies can remain in an incomplete draft. No live-device, hosted
delivery, model accuracy or human usability evidence is implied by these checks.

The independent [participant browser harness](../../tests/platform-integration.mjs)
passes **34 assertions** through actual Chrome, the R HTTP service and SQLite:
two complete counterbalanced sessions, all 12 supported questionnaire types,
typed numeric zero/boolean false/string "false", forward display logic, per-image
answers, an untimed draft reload, interrupted timed reload, final receipts,
required participant aliases, consent and real media requests. Three desktop/
narrow automated accessibility scans have no detected violations. These are
`automated_browser` results with original synthetic responses. Back navigation,
observed novice comprehension and physical presentation timing were not tested.

[Independent analysis tests](../../tests/platform-analysis.R) pass **45 assertions**
including the 10.8333333333 pp gaze and 1.375 liking oracles, repeated identities,
missing gaze pairs, explicit passive-phase filtering, frozen response codes,
scope, interval overlap and coordinate units. These tests exposed and drove
repairs for active-response gaze entering passive analysis, imported response
validation, and generated session labels being treated as person identities.

[Actual worker tests](../../tests/platform-jobs.R) pass **27 assertions** through
real R subprocesses and the durable catalog. They cover immutable source and
design pins, changed AOI producing a new 45 pp report without changing the old
10.8333333333 pp report, a corrupt source reference, cancellation while a child
is running, and automatic reporting after a persisted participant completion.
The changed-AOI oracle is a separate cohort fixture from the single-session
geometry example in RQA-11. Reports without an explicit identity declaration
suppress unsupported unique-person counts and paired inference.

The connected [researcher UI lifecycle](../../tests/researcher-workspace.mjs)
passes **85 assertions** through the actual Shiny workspace, separate participant
service and worker processes. An original packaging study is edited, released,
completed with scoped liking answers 1 and 7, and reported automatically. Actual
HTML/CSV/JSON report downloads retain those values. The researcher then uploads
and maps original prepared gaze intervals: the report reproduces the independent
10.8333333333 pp oracle with three people, four paired sessions and all ten
active-response intervals excluded. This route explicitly uses prepared intervals;
it does not claim raw sample fixation detection. Clone, template reuse and a real
downloaded ZIP import produce distinct study identities, preserve immutable image
bytes, and contain no source sessions or results. A fresh browser session reopens
the original history and both reports. Historical revision export and cloning
retain the selected earlier source. Archiving open recruitment is blocked with
an explanation; after closing it, a fresh participant sees the closed status
before consent. Archive is read-only with reports preserved, and restore does not
reopen recruitment. Immediate stage/study navigation saves edits before debounce,
keeps clone/source fields isolated by identity, and leaves the earlier report JSON
exactly unchanged. All **16 desktop/narrow automated
accessibility scans** report zero violations, with no observed page overflow or
browser exceptions. Earlier runs exposed and drove repairs to practice-design
export lineage, report table labels, modal names/headings, a page-layout argument
binding error, and text dimming in periodically refreshed output panels. Final evidence is saved under
`work/test-runs/brohn-ui-evidence/results.json` in the workspace, together with
screenshots and original exported artifacts. These are automated synthetic
researcher actions; no observed novice usability or live-device qualification is
implied.

The workstream then implemented the nested task receiver and runner bridge,
with parent review of clock identity and per-trial key bounds. Its
[receiver suite](../../tests/platform-task-integration.R) passes **27 assertions**
including incomplete procedure, order, identities, onset/foreperiod, first/final
latency, correction summary, typed flags, ignored keys, interruption and rejected
score payloads. The [actual task browser suite](../../tests/platform-task-integration.mjs)
passes **21 assertions**: a complete 28-trial simple RT procedure, complete
180-trial seven-block IAT, first error then forced correction, real immutable
task-image delivery, conservative instruction reload, and Escape at instruction
and timed-trial boundaries. All final outcomes are retained by the real R
receiver. Two instruction-page WCAG A/AA scans report no violations. Browser
keypresses are synthetic automation operating the real browser input API; they
are not participant observations or a physical timing qualification.

Independent review of the parent's task cloning/portable extension is recorded
by [36 passing task portability assertions](../../tests/platform-task-portability.R).
All five registered profiles retain independently specified trial counts,
category semantics, allocation mappings and scoring membership across an actual
ZIP transfer. Task/category/material identities change, an original PNG hash
does not, private paths and invalid image dimensions are rejected, and source
participants/reports are absent. BIAT, keyboard AAT and four-choice RT were not
each completed in the real browser suite; their compiled/portable checks do not
claim otherwise. No task has been scientifically qualified merely by these
software results.

The task-only mode of [researcher extensions](../../tests/researcher-extensions.mjs)
passes **14 checks** from a blank study authored entirely through the researcher
UI to a real participant completion and automatic immutable report. The exported
design retains the selected simple reaction-time profile and edited title; the
report contains exactly 20 retained test trials, separately from eight practice
trials. Four desktop/narrow authoring and report accessibility scans are clear.
The optional task-only evidence is stored separately under
`work/test-runs/brohn-extension-task-evidence`.

The complete extension now passes **27 checks**. Actual pointer drawing creates
an independently specified rectangle at x=.1, y=.1, width=.2, height=.2; keyboard
movement and undo preserve the same coordinate frame. The saved portable design
retains that exact geometry and source image hash. A real MagicTouch child worker
creates a reviewable proposal and downloadable PNG mask. Export before review
proves that the model output has not silently become an analytical AOI. Explicit
acceptance then stores the separately reviewed x=.3, y=.3, width=.2, height=.2
rectangle in a new design revision, preserving the stimulus hash. This is followed
by the complete authored-task route above. Seven desktop/narrow accessibility
scans are clear, without page overflow or browser exceptions. Evidence is under
`work/test-runs/brohn-extension-evidence/results.json`. This is geometric and
workflow verification, not semantic segmentation accuracy qualification.

The extended AOI pass exposed the product's own palette PNG being rejected by the
model worker; a decoder repair now preserves the original source bytes while
converting supported opaque pixels in memory. It also found actual HTTP 500 mask
downloads caused by read-only transfer copies on Windows. A writable verified
transfer copy now returns HTTP 200 with the exact 2701-byte PNG; the stored source
remains immutable. Earlier failed jobs remain preserved alongside successful
attempts. Visual review additionally corrected questionnaire-only coverage counts
and raw metric identifiers that were confusing in task reports.

The focused [task export browser check](../../tests/researcher-task-exports.mjs)
passes **six assertions** reopening that existing report. JSON stays unchanged;
standalone HTML uses readable outcome labels; CSV contains five declared metric
rows with exact canonical person/session/task identities, values, units and
eligibility. It does not invent trial observation rows. This caught a real CSV
escaping defect that unnecessarily prefixed ordinary `task`, `run`, `true` and
`test` values; corrected downloads now retain those identifiers. Evidence is
under `work/test-runs/brohn-task-export-evidence`.

The [combined-measure browser journey](../../tests/researcher-multimodal.mjs)
passes **29 assertions**, with six clear desktop/narrow accessibility scans.
Two actual worker-generated source reports use original repeated-person gaze
and liking data with deliberately different source identity prefixes. The UI
requires the correct collection origin, explicit identity confirmation and
written evidence, rejects unknown source mappings and duplicate hypotheses,
and accepts an actually downloaded/edited/uploaded ten-row crosswalk. The queued
synthesis preserves gaze 10.8333333333 pp with three people/four paired visits
and liking 1.375 with four people/five visits. Each measure keeps its own
denominator; both hypotheses remain in the declared Holm family. Source hashes,
reviewed shared identities and the complete crosswalk survive in actual
HTML/CSV/JSON exports. This is parallel measure comparison, not temporal signal
synchronization or a validated composite score. Evidence is under
`work/test-runs/brohn-multimodal-ui-evidence`.

The [recorded-stream browser journey](../../tests/researcher-interchange.mjs)
passes **39 assertions**, with five clear desktop/narrow accessibility scans.
Original XDF bytes are uploaded, declared, processed by the actual R/Python
worker and downloaded unchanged. Three streams and 12 rows retain source order,
clock reversal/reconstruction, three unapplied correction records, NaN/infinity
states, empty/coincident marker text and exact signed integers beyond 2^53.
Unknown units remain uncalibrated. A source-note amendment creates a new version;
the old manifest reopens identically in a fresh browser session. A separate
typed bundle retains nanosecond clocks, source identity boundaries, zero/false/
missing markers and a declared empty stream. Conflicting live-import/sample-source
labels produce mixed provenance rather than upgrading synthetic data. A truncated
XDF fails without a partial catalog, keeps its original bytes and records a
separate failed retry. No scientific report is invented by preservation alone.
The strengthened rerun also verifies that initial empty, failed truncated-source,
and failed retry states render without visible Shiny R output errors.
Evidence is under `work/test-runs/brohn-interchange-ui-evidence`.

The [planned-analysis browser journey](../../tests/researcher-analysis-plan.mjs)
passes **29 assertions**, with four clear desktop/narrow accessibility scans.
The researcher declares a two-outcome family before collection; empty rationale
and duplicate hypotheses are rejected. Clone and actual ZIP import remap question,
comparison and condition identities together. Four real browser visits include a
repeat person and an optional omitted test answer. The cohort report preserves
all eight answers and yields the independently expected effect of 2 from person
means 3 and 1, with two eligible people and three paired visits. Its unadjusted
p-value matches the df=1 Cauchy tail, and unavailable gaze retains the full family
of two using the conservative Bonferroni bound. The report freezes the exact plan
and its pre-session timing evidence; HTML/CSV/JSON retain this interpretation and
the omission. Evidence is under `work/test-runs/brohn-analysis-plan-ui-evidence`.

Browser exceptions and accessibility checks do not detect every server-rendered
R error. After an empty-list rendering defect was found independently, the browser
suites also assert that no visible `.shiny-output-error` remains. Those strengthened
assertions require their own executed reruns. The recorded-stream and 85-check main
researcher lifecycle journeys have passed this additional coverage; earlier runs of other journeys do not establish it until
their strengthened reruns pass.

The [exact typed-logic participant regression](../../tests/participant-logic.mjs)
passes **11 assertions** through the actual delivery service. Two completed,
durably saved synthetic visits distinguish numeric `1 + 1e-10` from `1`, and
collection membership in `[1, false]` from `["1", 0]`. All six conditional-page
decisions in each visit agree with the persisted skip events. The original typed
option codes survive unchanged in response records. This checks participant
execution and reception; it does not substitute for the questionnaire flow editor's
separate usability walkthrough. Evidence is under `work/test-runs/brohn-exact-logic-evidence`.

The [native-header and event-EDA browser journey](../../tests/researcher-native-eda.mjs)
passes **45 assertions**, with seven clear desktop/narrow accessibility scans and
no visible Shiny R errors. The researcher inspects original EDF bytes, refuses
unknown voltage units and mixed native rates, explicitly confirms Cz/100 Hz/native
scaling, and obtains the independently expected 10 Hz peak and quantized-source RMS.
The full Welch frequency artifact downloads with its immutable hash. Source-header
identity text is excluded from the inspection; source channels, units, annotations,
duration and calibration evidence remain visible.

A separate original 120-second, 25-Hz constant-5-uS recording receives explicit
baseline/response/latency/recovery windows and overlap rules. The actual EDA worker
processes the continuous recording once. A complete event yields baseline=5,
response=5 and change=0; supported nonresponse magnitude=0 while responder amplitude
is null. Two overlapping events and one late boundary event remain unavailable
with distinct reasons. Actual HTML/CSV preserve these explanations. The complete
processed artifact retains all 3,000 samples, original indices, typed support flags
and 2,500 retained samples without duplicating raw values. Changing measured onsets
from a source column to an explicit event list creates a new report with identical
timing/support outcomes. This pass found and repaired a nested-grid overflow in the
EDA support tables; the final 390-pixel report fits and has no detected accessibility
violations. Evidence is under `work/test-runs/brohn-native-eda-ui-evidence`.

The [compound-rule editor journey](../../tests/researcher-question-flow.mjs) passes
**18 assertions**, with three clear desktop/narrow accessibility scans and no
visible Shiny R errors. Starting from original typed question fixtures, the actual
editor builds `AND(OR(exact numeric equality, numeric membership), NOT(text membership))`,
moves grouped conditions in both directions, and saves the exact tree into an
actual portable design. Cancelling a cleared draft and changing an unrelated prompt
both preserve the saved rule. A fresh researcher session reopens it. Two automated participant
visits use the newly published revision; their completed receipts and saved
skip events agree with the compound decisions. The first question cannot select
an unavailable earlier response. Older releases retain their frozen rules.
Evidence is under `work/test-runs/brohn-question-flow-ui-evidence`.


The [processed-signal explorer journey](../../tests/researcher-signal-view.mjs)
passes **34 assertions**, with six clear desktop/narrow accessibility scans and
no visible Shiny R errors. Actual queued view jobs read the immutable full EDA
and native EEG artifacts. The EDA view preserves 3,000 source rows, 2,500 eligible
rows and 500 excluded edge rows. Its inclusive 18-to-27-second window contains
exactly 226 measured samples; an edge-only 0-to-5-second window retains 126
excluded rows and produces no invented chart. Invalid windows are rejected.
Native Welch exploration preserves all 101 frequency bins and the independently
expected 10-Hz maximum, with Hz and uV^2/Hz axes. Actual SVG and JSON downloads
retain units, gap semantics and source identities; complete scientific report
records remain unchanged. This walkthrough found two form-reset causes: unchanged
leaf polling and the whole-report audit refresh after successful publication.
Both were repaired, then the complete journey passed with explicit post-publication,
background-poll and narrow-viewport selection-retention checks. The subsequent responsive retake verifies every visible x/y axis and tick label fits the compact 390-pixel chart without horizontal panning; actual standalone SVG exports retain the full 920-pixel layout. Fresh conductance and spectral-density charts were visually inspected. Evidence is under
`work/test-runs/brohn-signal-view-ui-evidence`.

The [gaze visual-report journey](../../tests/researcher-gaze-view.mjs) passes
**23 assertions**, with three clear desktop/narrow accessibility scans and no
visible Shiny R errors. The actual exposure selector keeps repeated visits
separate: the original first visit has 80 ms valid support and 25% AOI gaze share;
the repeat visit has 100 ms and 40%. A missing-support exposure remains unavailable
without a zero-percent bar. Inline image bytes match the saved stimulus SHA-256;
the 800-by-600 raster and normalized AOI retain their exact geometry. Prepared AOI
summaries do not produce fixation locations or transition links. The actual
standalone HTML includes all ten exposure images from immutable assets, and
exploration/export leave the scientific JSON unchanged. The narrow chart was also
visually inspected. These automated original-synthetic journeys test data and UI
contracts; they do not establish observed human usability or live-device accuracy.
Evidence is under `work/test-runs/brohn-gaze-view-ui-evidence`.


The [browser-camera researcher journey](../../tests/researcher-camera.mjs) passes
**63 assertions**, with nine clear desktop/narrow accessibility scans and no
visible Shiny R errors or browser exceptions. The researcher authors camera limits,
separate recording information, explicit retention text and the processing profile
through the actual Plan editor. A missing retention statement is rejected. Optional
and required policies survive actual design ZIP exports and remain frozen per release.
Four automated participant visits use a generated 320-by-240, 15-Hz Y4M pattern;
no physical camera, microphone or human participant is used.

An optional decline never invokes camera permission and creates no recording bytes.
A required session requests permission only after separate affirmative agreement.
Real Chrome MediaRecorder output reaches the authenticated R receiver. The test
allows the service to accept a chunk, deliberately loses its acknowledgement, then
also takes the browser offline: identical retries do not duplicate bytes, and
pending recording chunks remain in IndexedDB. The stopped recording and study both
receive final receipts; tracks stop and acknowledged local journals are cleared.
Original bytes, clock instance, step context, frozen policy, study/run identities
and pilot origin survive publication. The actual child decoder reads 83 frames in
this pass; the registered local model processes all 83 and reports absent faces,
null landmarks/blendshapes and insufficient support instead of invented geometry.

Actual browser permission denial prevents required recording and retains withdrawal.
Reload after partial recording retains one recorder's bytes, the exact original
start-clock sentinel and an unobserved incomplete ending; it does not request a
replacement recorder or queue partial data for automatic geometry. The researcher
reopens the resulting Data-library source and downloads hash-identical original
WebM, full callback JSONL, decoded-frame JSON and capture manifest. The geometry
report and complete per-frame model artifact download separately. Narrow controls
were also visually inspected. This is software-contract evidence; frame callbacks
do not establish encoded-frame alignment, physical accuracy or human consent comprehension.
Evidence is under `work/test-runs/brohn-camera-ui-evidence`.

This walkthrough identified and repaired a standalone-export gap: the capture
manifest now carries the exact frozen consent, retention policy, processing choice,
study/revision/design/protocol references and declared participant linkage. The
complete 63-assertion rerun verifies these fields in the actual downloaded manifest
against the recorded policy and source identities. Thus the recording retains a
self-contained policy/provenance artifact even without automatic geometry analysis.

The [local-LSL researcher journey](../../tests/researcher-acquisition.mjs) passes
**36 assertions**, with five clear desktop/narrow accessibility scans and no
visible Shiny R errors. Two original loopback pylsl outlets supply conductance and
markers; no physical device or participant is involved. Explicit metadata discovery
finds only the two requested source identities and subscribes to neither. The
researcher reviews source clocks, every channel unit, participant/session identity,
sample origin and discontinuity limits. Unreviewed selections and falsely declaring
the synthetic sources as live data are rejected. Background polling preserves the
review fields, and changing studies does not carry those selections or history into
the other study.

The actual independent recorder receives both streams until the researcher chooses
Stop and save. The original ZIP downloads through the browser with its immutable
hash. An independent ZIP reader verifies every member and compares the saved rows
against the outlet's own sent log: source order, coincident and reversed timestamps,
IEEE-754 timestamp/value bits (including negative zero), empty and Unicode markers
are unchanged. Declared gaps remain explicit; clock correction observations are
retained without applying them or claiming synchronization. A completed recording
is not automatically declared quality-qualified or turned into a scientific report.

Only explicit Prepare separate datasets queues secondary curation. The resulting
Data-library record retains the original acquisition hash, study revision, sample
origin and complete signal/marker counts. Actual full JSONL downloads preserve both
irregular clocks, original values and participant/session identities. A fresh browser
reopens the study and downloads the same original ZIP; the other study still shows
no foreign recording. This tests local transport, provenance and researcher workflow,
not live hardware accuracy or independently aligned multimodal clocks. Evidence is
under `work/test-runs/brohn-acquisition-ui-evidence`.

The focused [camera cancellation and receipt regression](../../tests/participant-camera-races.mjs)
adds **16 passing assertions** and one clear 390-pixel accessibility scan through
the actual participant service. Four new original-synthetic visits exercise a real
Chrome fake-device stream whose fulfilled permission result is deliberately held
until after Stop or Continue without camera. Late resolution ends the track and
cannot recreate a preview, start recording or publish bytes. Required Stop remains
a withdrawn run with no capture row; optional decline completes with exactly one
explicit declined capture.

For two other visits, the real receiver accepts an explicit camera decline before
the harness replaces its acknowledgement with a 503 response. Both same-page retry
and page reload replay the identical capture ID, operation and original clock.
Recovery requests no camera permission, invents no recording ending, and completes
with a saved run, declined capture, zero chunks and no recording publication.
Evidence is under `work/test-runs/brohn-camera-race-evidence`.

The [preserved-stream curation journey](../../tests/researcher-stream-curation.mjs)
passes **33 assertions**, with five clear desktop/narrow accessibility scans and
no visible Shiny R errors. An independent original bundle contains 1,600 EEG rows,
a native nanosecond-clock reset, one missing selected observation and a missing
unselected auxiliary value. Marker streams cannot enter analogue curation. Missing
review declarations and Cancel create no derived records. Selected channels, unit
rationale and identity fields remain stable during background polling.

One explicit review prepares and automatically analyses the selected scalp channel.
The 1,599 retained rows form segments of 800, 400 and 399 samples. The first two
independently yield 6/12-Hz peaks and 32/72-uV-squared power; the third remains
unavailable because it cannot support two declared two-second analysis windows.
These are three signal segments for one original person/visit, not three participants
or invented experimental exposures. All 1,600 original rows appear in the decision
artifact; the unselected auxiliary omission does not discard its otherwise usable row.

Actual generic Data-source and curation-dialog CSV downloads match the immutable
source/artifact hashes. Every retained CSV row is checked for original timestamp
text, source sequence, unchanged identity and the declared microvolt-to-volt factor;
large nanosecond epochs and the reset are not rounded. Full curation manifest and
row-decision downloads retain original lineage and the reviewed analysis choice.
Returning to the original recording downloads identical input bytes. An unchecked
automatic-analysis choice creates only a prepared dataset; an all-missing stream
retains twenty exclusions and produces neither an empty dataset nor a score.
A fresh researcher session reopens both earlier decisions. This is synthetic
software and arithmetic evidence, not physical EEG qualification. Evidence is under
`work/test-runs/brohn-stream-curation-ui-evidence`.

The launcher regression [tests/platform-participant-protocols.R](../../tests/platform-participant-protocols.R)
passes **18 assertions** using the checked-in participant startup script in a
separate R process, on a dynamic loopback port and disposable owned workspace.
It verifies actual HTTP enrollment for a frozen scale-bearing design, exact
protocol/key hashes, same-start retry identity, consent rejection without a run,
conflicting participant rejection, independence from later draft edits, correct
workspace health, absence of researcher administration routes and durable reopening.
This specifically guards against a validator being loaded in the researcher process
but absent from the separately launched participant service.

The [questionnaire-scale researcher journey](../../tests/researcher-scales.mjs)
passes **34 assertions** with five clear desktop/narrow accessibility scans.
Four original optional end-of-study items use codes 1–5; two saved keys reverse
items B/D. Rapidly checking both keys, removing/reselecting D and switching the
assessment placement preserves the actual saved key. This exposed and now guards
a UI race in which a delayed item-list render previously reset a checked reverse
box. Cancel preserves the design, and an incompatible keyed-item bound edit is
rejected with an explicit route to discard unsaved question changes.

Two real browser visits by the same synthetic participant retain two assessments
and one person. Original answers [1,2,4,5] become [1,4,4,1], sum to 10 and convert
from the theoretical range 4–20 to **37.5** on 0–100. Omitting D leaves the
complete-item key unscoreable. A separately declared minimum-three/prorated key
uses mean([1,4,4]) × 4 = 12 and converts to **50**, without a hidden zero.
The actual child-worker cohort report, complete score CSV, standalone HTML and
per-item response hashes/step sequences preserve these results.

An independently imported twelve-row CSV declares two assessment IDs within one
person/visit and reproduces the same scores. Four rows with no assessment ID
remain unassigned rather than being combined by row order. The report pins the
original bytes and mapping. Actual clone and portable import give fresh study,
scale and question identities while preserving scoring directions and graph
references; the original study reopens unchanged, and the clone has no source
participant results. Evidence is under `work/test-runs/brohn-scales-ui-evidence`.
These are original arithmetic and software fixtures, not validation of a named
psychological instrument or observation of human usability.

The [planned scale comparison journey](../../tests/researcher-scale-comparisons.mjs)
passes **26 assertions**, with five clear desktop/narrow accessibility scans.
The researcher authors two optional numeric items after each stimulus, reverses
the second in an original mean scale, and saves a two-outcome comparison family
containing that scale and the first item. Cancel after changing the rationale
and removing an outcome preserves the full saved plan.

The actual mapping/child-worker path processes an original twenty-two-row CSV
with eleven explicit assessments. Two control assessments in P1's first visit
average to 12; the test is 14, giving a difference of 2. P1's second visit gives
6, so that person contributes 4. P2/P3 contribute 8/12, and P4 lacks a scoreable
test assessment. Both planned outcomes therefore yield **8** across **three
people and four paired visits**, with one excluded pair. The independent
two-sided df-2 probability is `1 - sqrt(6/7)`, approximately 0.0741799002; the
complete two-outcome Holm family gives 0.1483598005. The unadjusted interval uses
three people, not eleven assessments. Full item/scale evidence and the unavailable
assessment remain in the report.

Actual standalone HTML and full scale-score CSV retain names, units, all eleven
assessments and the applied correction. Imported source timing is not relabelled
as pre-session collection evidence. Clone and portable import remap the planned
scale and item outcomes together with their question and condition identities,
preserving reverse directions and the rationale without copying results.
Evidence is under `work/test-runs/brohn-scale-comparisons-ui-evidence`.

The [historical retrieval contract](HISTORICAL-RETRIEVAL.md) records **14 independent
backend assertions** and **21 actual-browser assertions**, with three clear narrow
accessibility scans. An isolated catalog places 510 newer unrelated records ahead
of 43 matching datasets/reports and 110 unrelated jobs ahead of one matching old
attempt. Review/Results/History and dataset report lists retain exact forty/three
pages, original identities and full report/source hashes. Foreign-project rows,
stale offsets and previous-study page events cannot contaminate the current view.
A fresh session reopens the old evidence. The owned fixture service exits cleanly;
these purpose-built catalog reports do not claim any scientific computation.

The [historical selector extension](../../tests/researcher-history-selectors.mjs)
passes **16 assertions** and three accessibility scans. It saves and reopens an
older archived study/revision mapping behind 510 newer studies, rejects a late
other-dataset overwrite, and selects/reviews the exact oldest report sources.
Actual server responses exclude foreign-project and unrelated choices. The
open report dropdown exposed a missing combobox `aria-controls`; the shared fix
passes desktop/narrow scans and retains keyboard selection behavior. Its queued
mapping request is explicitly cancelled; no scientific worker runs in this fixture.

The [MaxDiff participant delivery journey](../../tests/participant-maxdiff-delivery.mjs)
passes **42 assertions** and two clear desktop/narrow accessibility scans against
an isolated real participant launcher and SQLite receiver. Two required original
choice sets, a separate optional set and typed explicit liking retain their exact
frozen order, source exercise hashes, numeric answer and contiguous event ledger.
Anonymous enrollment stays unlinked and original material stays sample origin.
Reload restores the partial choice and preserves both page onsets; uninterrupted
RT remains null while actual active-segment timing is checked independently.

One actual receiver commit deliberately loses its acknowledgement; the exact
operation/event/clock batch retries once with no duplicate. Replaying closure
retains one queued analysis job. A real browser IndexedDB response transaction
is also aborted: the saved cursor/sequence and selected pair remain unchanged,
then retry yields one response and one finish, with no aborted event IDs. This
guards the shared runner's copy-on-write rollback and prevents uncommitted
events being exposed to asynchronous delivery. Withdrawal with selected or
pending choices remains withdrawn; direct invalid pair/timing/duplicate events
are rejected without retained rows. Full evidence is under
`work/test-runs/brohn-maxdiff-delivery-0X75E9`; the owned x64 service stops
gracefully with code zero. Analysis jobs are verified as queued, and no scientific
worker, physical device or human participant is used by this fixture. The
[method contract](../methods/MAXDIFF.md) separately records 47 calculation,
32 researcher-server and 28 component assertions with their narrower scopes.

After the shared participant `persist()` rollback change, the
[persistence regression orchestrator](../../tests/participant-persist-regressions.mjs)
reruns the existing typed questionnaire and camera permission-race journeys
against the same production runner and a separate real participant launcher.
`participant-logic.mjs` passes **13 checks**: its original eleven exact-number,
typed-choice and durable branch assertions plus one expected queued-job check
for each completed visit. `participant-camera-races.mjs` passes **17 checks**,
including a clear 390px accessibility scan. Stopping or declining while the
actual generated-device permission promise is pending releases the late tracks;
same-page and reload recovery replay the accepted decline request with its
original capture identity/clock. Declined visits have no video bytes, publication
or assembly job, and the required-permission stop remains withdrawn.

Both existing harnesses retain their default connected journeys. Test-only
`BROHN_PARTICIPANT_URL`, `BROHN_TEST_WORKSPACE`, `BROHN_TEST_OUTPUT`,
`BROHN_TEST_NO_WORKER=1` and the prepared camera release configuration select
the isolated mode. Its results explicitly assert completed/declined receipts
and expected queued `analyse_run` jobs, never worker success. A new original
camera policy and generated 320x240 Y4M stream are confined to the test workspace;
recording is never started. Evidence, exact mode and runner SHA-256 are retained
under `work/test-runs/brohn-maxdiff-delivery-regressions-ibnxTj`. The owned native
x64 participant service exits gracefully with code zero; no main workspace,
main service or scientific child is used by these regressions.


The [MaxDiff researcher journey](MAXDIFF-RESEARCHER-JOURNEY.md) passes **27
assertions and five accessibility scans** in a separate actual Shiny and
participant workspace. It authors original required importance and optional
preference exercises alongside explicit liking, checks exact item/set order,
coverage, Cancel and stale form identities, then uses template/clone/ZIP with
fresh identities and preserved internal graphs. Synthetic Pilot/Live releases
remain rejected; the explicit sample walkthrough starts its frozen design.
The original study retains one actual withdrawn sample visit and unchanged
source, with zero jobs or reports. A found background-autosave error dismissal
is fixed and checked across 2.6 seconds of untouched polling; deliberate
successful release clears it. This is automated simulated researcher evidence,
not human usability observation or a scientific worker result.


The [MaxDiff import mapping journey](MAXDIFF-IMPORT-JOURNEY.md) passes **14
assertions and three accessibility scans** through the actual Data library.
Original CSV bytes, suggested column mappings, selected exercise and saved
Revision 1 remain exact. An externally edited current draft is rejected before
curation; prior-dataset controls cannot overwrite a new source. The mapping-only
run cancels its sole queued job and launches no scientific worker or report.
Full import/report execution is tracked separately from this completed UI scope.


The full [MaxDiff import browser journey](MAXDIFF-IMPORT-JOURNEY.md) now passes
**23 assertions and five accessibility scans**, including three real production
worker processes. The positive source yields the independent six-pair likelihood,
complete CSV/JSON and exact identities/orders; partial and unpresented rows remain
missing evidence, while the other exercise row is explicitly excluded. Wrong
exercise-hash and conflicting-origin sources fail with retained bytes and no
report. This separately recorded full result complements the mapping-only14
checkpoint; it does not turn generated rows into human research qualification.


The [completed-study MaxDiff report journey](MAXDIFF-REPORT-JOURNEY.md) passes
**24 assertions and four accessibility scans**, with five actual production
workers in a fresh run. The independent cyclic-response oracle yields exactly
3 best/3 worst/9 complete exposures per item, neutral paired utilities and1/6
ordered-pair probabilities. Optional omissions retain unavailable scores, and
liking1/3/5 remains separate. A cancelled three-visit cohort retries its exact
inputs after a later fourth visit, preserving two explicit person codes. Full
CSV/HTML/JSON exports and fresh-session reopening pass, including strict
catalog-versus-publication-envelope equality and SHA verification after the
numeric precision fix. Two earlier accessibility findings and the original
rounding mismatch remain recorded with their failed evidence and fresh retake.

The [independent peripheral review](PERIPHERAL-INDEPENDENT-REVIEW.md) passes
**19 original Python tests**, including real full-artifact signal previews.
Temperature unit/mean/slope arithmetic, ENMO truncation order, rotating gravity,
actual-interval derivatives, repeated source identities, gap/missing censoring,
no-support event counts and exact large source clocks pass. The initial review
exposed a low-rate default failure; its correction preserves explicit invalid
setting rejection. Full-artifact plots retain three separated support fragments
and exclude finite samples without enough contiguous duration. Application
publication, actual browser authoring and combined-study comparisons retain
separate acceptance; no physical-device or human-usability qualification is
claimed by these synthetic checks.

The separate [peripheral researcher journey](PERIPHERAL-RESEARCHER-JOURNEY.md)
passes **48 assertions and eight accessibility scans** through actual Chrome,
Shiny, durable upload ingestion and production workers. A controlled packaging
study retains original temperature, ordered acceleration and liking sources;
explicit identity review yields8°C across three people/four paired visits and
2.25rating points across four people/five visits. Fragmented same-exposure
acceleration remains unavailable in the full three-comparison Holm family.
Complete artifacts, gap-preserving plots, CSV/HTML/JSON exports and fresh-session
reopening pass with exact catalog/envelope hashes. The actual browser exposed
and then verified the correction for blank automatic support at0.1Hz. Its failed
source is retained and its narrow retake is explicitly recorded; no device or
human-participant qualification is implied.

The [questionnaire assignment researcher journey](QUESTION-ASSIGNMENT-RESEARCHER-JOURNEY.md)
passes **32 assertions and six accessibility scans**. It completes eight actual
browser sessions against separate local services, preserving 32 native responses
with numeric, text and boolean codes. Explicit draft upgrades and checkbox
opt-in change future assignments; ordinary legacy saves and later starts on an
old release retain their original contract. An untimed reload keeps the offered
order and draft answer. The researcher can review typed options and download the
original assigned protocol byte-exactly, with a clear distinction between an
assigned sequence and actual completion evidence. Template, clone, portable
reimport and reopening retain policy and code types. No scientific worker or
human/device qualification is included in this bounded acceptance.

The [saved-report comprehension retake](SAVED-REPORT-COMPREHENSION.md) passes
**22 scoped R checks**, the existing **10 offline HTML checks**, and **17 actual
browser checks with five accessibility scans**. Existing combined reports now
show frozen question wording, named physical quantities and readable units,
specific unavailable-support explanations and a concise coverage narrative.
Every quality count remains available in technical details. Original CSV bytes,
JSON, all five report envelopes, source hashes, revisions and job histories stay
exact; no analysis was regenerated for this presentation change.


### Questionnaire sections: actual researcher acceptance

[Section authoring and delivery](QUESTION-SECTIONS-RESEARCHER-JOURNEY.md) passes
18 checks and four automated accessibility scans in a fresh isolated runtime.
Two real browser sessions and their automatic workers retain exact section,
group, question and typed branch assignments; four independent scale scores are
37.5, 100, 25 and 50. Full CSV/JSON/protocol downloads and template/clone/ZIP reuse
preserve the saved graph and report evidence. The initial immediate name-to-Create
race was fixed and the unchanged fast interaction passed; its failed evidence
remains available. Original synthetic inputs and automated browser interaction
do not qualify human comprehension, hardware or research timing.

### Documentation recovery note

On 2026-09-08 an encoding error during an appendix write truncated this document.
The staged original and all recorded subsequent successful text patches/appends
from both QA workstreams restored its historical content. No test source,
scientific source, fixture, report or evidence result was changed by that error.
All 28 then-current execution-ledger evidence files were verified against their retained
SHA-256 values. The recovery preserves source prose and normalizes line endings;
it is not represented as a byte-exact restoration of the lost working file.
Recovery inputs, the zero-byte failure state, staged snapshot, text replay trace
and restored content are retained under
`work/test-runs/brohn-question-sections-ui-BKOX6s/qa-ledger-recovery`.
The section acceptance paragraph above is newly added after that restoration.

The [historical sessions and partial task review](SESSION-TASK-REVIEW.md) passes
**25 actual browser checks and seven accessibility scans**. Exact 40/two session
pages, stale/foreign controls, archived Review and immutable assigned-protocol
downloads pass. A separately labelled direct synthetic receiver/scorer fixture
preserves partial RT support in mixed-report task CSV, JSON and standalone HTML:
39/40 omissions, 0/1 errors, available 500 ms mean/median and unavailable sample
SD. Task and metric eligibility remain distinct. All 42 catalog starts remain
uncompleted, no scientific jobs run, and no human or device evidence is implied.


The [native task export and reimport journey](NATIVE-TASK-IMPORT-RESEARCHER-JOURNEY.md)
passes **19 actual browser checks and five accessibility scans** after retaining
its earlier observed reviewed intake. A complete original synthetic receiver
journal exports all 48 trials and its registry. Actual imported analyses preserve
unknown timing as unavailable, then produce exact 500 ms mean/median, 39/40
omissions, 0/1 errors and unavailable sample SD after explicit definitions.
Imported evidence remains declared summaries; it does not inherit native replay.
Malformed registry recovery, leading-zero identities, original bytes, both report
envelopes and full exports pass. One intake and two scientific jobs succeed;
the original run-analysis job remains cancelled before execution. All services
stop, and both analyses retain the same 34 executed source-file identities.


The [answer-review researcher journey](QUESTION-REVISION-RESEARCHER-JOURNEY.md)
passes **19 connected assertions and five accessibility scans**, with one actual
completed browser session and one automatic scale report. Native false/zero,
direct/transitive/still-visible invalidation, Back, optional omission,
information acknowledgement, four sealed assessment boundaries and untimed
reload all pass. Final values 6 and 4 score once as mean 5; twelve status records,
nine ordinary observations and exact acknowledged history remain distinct.
A retained-source protocol/reuse continuation corrects a session-list test wait;
no participant or scientific job is repeated. The earlier release stays
forward-only and its separate legacy start remains uncompleted. A misleading
held-cursor progress label was identified visually and handed to the runner
owner; large-history publication remains a separately tracked boundary.

The [complete questionnaire artifact journey](QUESTIONNAIRE-ARTIFACT-RESEARCHER-JOURNEY.md)
passes **10 connected browser assertions and seven accessibility scans**, using
the newly qualified retained receiver-boundary report. Actual downloads preserve
all 200 unabridged final answers, 400 committed versions and 803 questionnaire
history events; full JSON, CSV and independently decoded typed artifact agree.
Fresh-session reopening leaves original report, study and journal hashes intact.
One actual synthesis worker reads six numeric rows beyond the ten-row preview,
giving independent differences 2, 4 and 6, mean 4 and three people/visits.
The first attempt's table-region selector omitted an accessibility suffix; its
test-only correction reused the same source without repeating any analysis.
Both source reports remain immutable, no jobs remain pending, and all owned
services stop. This is original synthetic and automated interaction evidence,
not a claim of human usability, physical timing or unlimited-memory support.
