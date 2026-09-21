# Measurement visual coverage audit

20 September 2026. Read-only source and evidence reconciliation for PC05. No
test suite or browser journey was rerun for this audit. **Recorded evidence**
below means an executed result documented in the named acceptance record;
**source path** means current code is connected, without a claim that its
measurement-specific browser journey has passed.

The 50 entries in `docs/preparation/capability-register.json` define intended
scope, not enabled recipes. The build manifest still marks BWP01–15/BWP17 as
implementing and BWP16 as planned. Neither a package status nor an installed
model establishes visual or scientific acceptance. This audit resolves enabled
profiles from the validators, worker dispatch and actual report hooks. Read it
with [measurement methods](MEASUREMENT-ACADEMIC-ACCEPTANCE.md).

## Shared report paths and their limits

All saved reports enter through `brohn_report_detail_ui()` in
`R/platform-data-views.R`. The following shorthand makes the matrix precise.

| Path | Actual content, numerical alternative and export |
|---|---|
| **Report** | Origin/status, coverage, features (first 100), observations (first 50), recording support (first 100), settings and provenance. Generic CSV chooses observations when present, otherwise features, then choice/task rows; it is **not every result collection combined**. Full JSON retains the saved result; externally packed output requires its complete-artifact route. HTML includes report content and explicitly connected static gaze/neural plots, not every interactive explorer. |
| **Signal** | `R/platform-signal-views.R` plus the verified streaming `signal_preview.py` worker. Only complete `physiology-series`/`physiology-events` artifacts enable it. Select recording/channel/table/measure and complete or inclusive range. Extrema-preserving envelopes retain source support fragments; cadence/reset/missing boundaries are disconnected. Units and original clock origin are explicit. Empty ranges show a reason and counts. Cancel/retry and corrupt-source refusal preserve the report. SVG and view/provenance JSON are downloadable; full typed artifacts download separately. **The ordinary on-screen numerical alternative contains support counts/extrema/fragments, not a paged exact x/y sample table. There is no generic complete selected-measure CSV action.** Cardiac marker tables are a separate exception. |
| **Neural** | `R/platform-neural-views-plots.R` reads complete bounded saved arrays, selects recording/condition/channel and exact sample window, and exposes up to 50 plotted values plus saved features. All channel values/frequencies export as CSV and typed JSON; the current chart exports as SVG. Static HTML defaults to a supported cell and states remaining coverage. Source/trial/grid/unit mismatch visibly refuses a plot. |
| **Gaze** | `R/platform-gaze-report-views.R` selects an exact exposure, pins original stimulus bytes/geometry, and displays candidate/AOI graphics and numerical tables. Default candidate display is capped at 200; static HTML defaults to 12 exposures. Counts explicitly disclose limits. Missing/corrupt images leave a labelled frame and numerical evidence; missing valid gaze never becomes a zero share. Full JSON retains all result records; generic CSV is the AOI observation collection, not every pupil/blink feature. |
| **Task** | `R/platform-task-plots.R` and `platform-task-plot-views.R` read the complete selected imported administration audit or exact native journal/protocol. Chronology and latency histogram use all selected rows, independently of 50-row table pages. First response/final correct and all/scored positions are explicit. SVG, all selected rows CSV and complete typed source/provenance JSON are separate downloads. Missing retained source fails visibly. Cohort dots use saved person-level values, not pooled trials. |
| **Answers** | `R/platform-questionnaire-explorer-views.R` uses a source-bound index of complete saved typed answers and history. Literal filters, 25/50/100-row pages, unabridged text chunks and exact source detail are available. Whole-report question summaries do not change with answer filters. This is a complete numeric/text explorer; it does not supply questionnaire distribution charts. |

The Signal path has recorded Chrome evidence for EDA and native EEG Welch
(34 assertions/six scans in [researcher QA](RESEARCHER-QA.md)), plus the separate
cardiac and movement routes below. That does **not** establish actual browser
acceptance for fNIRS, EMG, respiration or audio simply because they publish the
same artifact schema.

## Enabled physical and model-derived profiles

| Enabled recipe / register scope | Researcher visual and source meaning | Support, numerical/export route and remaining coverage |
|---|---|---|
| Prepared AOI gaze, `aoi-valid-gaze-time-share/0.1.0-draft` (`gaze.aoi`) | **Gaze** pinned stimulus/AOI rectangles and 0–100% valid-time-share bars. Prepared intervals do not contain fixation coordinates; no reconstructed scanpath is drawn. | AOI inside/valid/unobserved milliseconds and exact denominator accompany bars. Missing support remains unavailable; overlapping AOI shares may sum above 100%. Gaze/Report exports. Recorded 30 component checks and 23 researcher checks/three scans cover sampled/prepared views, exact assets and unavailable exposure. See [gaze views](../methods/GAZE-REPORT-VIEWS.md), [researcher QA](RESEARCHER-QA.md). |
| Sampled gaze, `brohn-adjacent-ray-ivt/0.1.0-draft` (`gaze.events`, `gaze.aoi`) | **Gaze** numbered equal-size fixation-candidate centroids, saved direct transition links, AOI shares and candidate timing. Coordinates use the declared rendered stimulus frame; off-stimulus values remain in the table. | Candidate source rows, duration, valid coverage, TTFF/censoring and gap masks remain separate. A candidate map is not continuous gaze replay. Recorded evidence is the same scoped gaze journey; dynamic geometry, synchronized stimulus replay and an independently annotated detector validation remain absent. |
| Pupil and externally labelled blinks within sampled-gaze (`gaze.pupil_blink`) | Current gaze analysis saves `pupil_summary` and `source_labelled_blink` feature records. The dedicated **Gaze** graphic does not render pupil diameter/correction or blink-time traces. | Native mm/mm²/pixels/pixels²/device units, valid pupil milliseconds, baseline mean/coverage and corrected mean remain saved; invalid baseline is missing. Full JSON preserves them, generic feature preview may show them, while AOI CSV does not export all feature records. **Missing visual path:** raw/corrected pupil and blink/invalid masks. Complete pupil samples are not retained in this result schema; do not plot a synthetic trace from its mean. Arithmetic evidence exists in `tests/platform-gaze.R`, not a pupil visual-browser receipt. |
| EEG channel Welch, `eeg-welch-channel/1.0` (`eeg.spectrum`) | **Signal** complete frequency-bin density in µV²/Hz; **Report** band powers in µV², relative-power denominators and RMS. Axis stays Hz. | Full frequency artifact, exact observed bins/support, empty/invalid range handling and Signal exports. No raw-voltage sample table is emitted by the current Welch artifact adapter, so its report does not acquire a raw EEG waveform through this path. Recorded 45 native-header/EDA checks plus 34 Signal checks exercise actual EDF spectrum and exports. [Recorded EDF agreement](EEG-WELCH-RECORDED-REFERENCE.md) is numerical reference evidence, not another browser walkthrough. |
| EEG ERP, `eeg-erp-epochs/1.0` (`eeg.erp`) | **Neural** mean voltage ± saved pointwise trial SEM, µV versus seconds, positive upward; saved baseline and component settings are visible. | Retained/requested/excluded trials, event/source declarations, null SEM for one trial and unavailable conditions remain explicit. CSV/JSON/SVG/HTML available. Recorded 66 Chrome checks/seven scans across ERP/Morlet/tagging include independent 10/20-µV pulses and exports ([neural plots](../methods/NEURAL-PLOTS.md)). A dedicated individual-trial waveform/rejection-raster display is not implemented by this adapter. |
| EEG Morlet, current `eeg-morlet-epochs/1.1`, historical `/1.0` (`eeg.time_frequency`) | **Neural** complete time-frequency map plus exact frequency slice. Raw power µV², frozen transform units or ITC 0–1; native pixels retain all saved cells, with discrete actual-frequency rows. | Missing and unsupported masks differ from zero; baseline duration/kernel support and trial counts remain visible. Complete CSV/JSON and map/slice SVG/HTML. Recorded 67 component checks and fresh 21 browser checks/six scans in [map acceptance](NEURAL-TIME-FREQUENCY-MAP-ACCEPTANCE.md), including missing/zero/unavailable and reopened versions. Source-label Unicode under the separate neural CSV writer was not independently re-audited here. |
| EEG tagging, `eeg-frequency-tagging/1.0` (`eeg.frequency_tagging`) | **Neural** trial-mean PSD µV²/Hz with saved target-bin markers; neighboring noise and SNR remain saved features. | Exact FFT/bin/window and trial support, zero-noise unavailable SNR and no invented target selection. Same CSV/JSON/SVG/HTML path. The recorded 66-check neural journey tests a known 400-density target, noise 4 and SNR 100. No physical flicker-output qualification is implied. |
| fNIRS, `fnirs-od-beer-lambert/1.0` (`fnirs.hemodynamics`, descriptive subset) | **Signal source path** exposes complete optical-density (dimensionless) and haemoglobin-change (µM) columns per channel/segment. **Report** includes HbO/HbR channel identity, geometry and SCI screening feature. | Full typed series preserves original sample indices, wavelength/pathlength settings and source hash. Missing/bad spans remain split. Artifact tests ran separately in the prepared fNIRS environment ([artifact contract](../methods/PROCESSED-PHYSIOLOGY-ARTIFACTS.md)); **no fNIRS-specific researcher plot/browser/export receipt was located**. No joint HbO/HbR comparison, event GLM, motion correction or short-channel model is supplied. |
| Whole-recording EDA, `eda-neurokit-highpass/1.0` (`eda.activity`) | **Signal source path** exposes cleaned, tonic and phasic µS traces and separate candidate-event scatter values; **Report** has tonic/SCR summaries. | Retained/filter-edge support and candidate amplitude/rise/recovery units remain in artifacts. Generic trace does not overlay the candidate onset/peak/recovery on its waveform. Existing worker/domain tests establish arithmetic/artifacts; the documented connected EDA browser fixtures exercise the event recipe below, so whole-recording visual parity is **not independently closed**. |
| Event EDA, `eda-event-highpass/1.0` (`eda.activity`) | **Signal** continuous cleaned/tonic/phasic µS plus candidate-event artifact; **Report** adds readable baseline/response/SCR support tables and exact eligible event/channel denominators. | Baseline=5, response=5, change=0 and supported nonresponse=0 remain distinct from missing responder amplitude, overlap and late boundary exclusions. Recorded 45 native-header/EDA checks/seven scans and 34 Signal checks/six scans. HTML/CSV and complete artifacts checked. **Missing:** an event-centred overlay showing authored baseline/response/latency/recovery windows with the trace. |
| Event EDA, `eda-event-cvxeda-defaults/1.0` (`eda.activity`) | Same connected output/UI schema as event highpass; decomposition recipe remains explicit. | [Event-EDA contract](../methods/EVENT-RELATED-EDA.md) records 28 Python/65 R checks, including actual worker and artifact publication. This audit found no separate actual cvxEDA researcher plot browser receipt. Do not borrow the highpass numerical oracle or describe decomposition as resolving overlapping-event attribution. |
| ECG, `ecg-neurokit-detected-rr/1.0` (`ecg.hrv`, detected-RR subset) | **Signal** saved converted input or cleaned voltage with exact saved peak markers; previous RR/plausibility table. Separate complete RR Welch density in ms²/Hz with saved LF/HF bands. | Source/clean distinction, retained edge policy, exact marker indices, detected-RR rather than NN, full-spectrum powers and unavailable spectral support remain explicit. Actual recorded-reference waveform and browser acceptance: [input waveform](CARDIAC-INPUT-WAVEFORM-ACCEPTANCE.md); [spectrum](CARDIAC-SPECTRUM-ACCEPTANCE.md). A temporal interval scatter is selectable, but no new artefact correction is inferred from displaying it. Source-bound exclusion/reanalysis has separate direct, curated-source and browser acceptance in CARDIAC-EXCLUSION-ACCEPTANCE.md; it does not qualify the detector. |
| PPG, `ppg-elgendi-detected-prv/1.0` (`ppg.prv`) | Same input/clean/marker/interval/spectrum routes as ECG, with the retained source amplitude unit and explicit PRV basis. | No SpO₂, blood pressure, ECG-HRV equivalence or NN claim. Recorded waveform/browser paths include actual PPG reference reports; [eight-record comparison](PPG-RECORDED-REFERENCE.md) separately records detector/endpoint limits. Missing/rejected intervals suppress unsupported frequency output. Source-bound exclusion/recalculation has separate bounded acceptance, without granting detector or NN qualification. |
| Respiration, `respiration-displacement-khodadad/1.0` (`respiration.cycles`) | **Signal source path** exposes cleaned displacement/volume, and separate event columns for cycle amplitude, duration, inspiration and expiration. Units are the declared source unit and seconds. | Quantity, inspiration polarity, mapping evidence, retained edges and complete-cycle counts stay saved. Flow is retained without this phase analysis. The 19-check respiration suite covers actual declaration→worker→report arithmetic, **not a dedicated Chrome plot journey**. Raw signed source is not in the complete processed series, and no cycle/phase overlay ties extrema to the waveform. |
| Surface EMG, `emg-butterworth-rms/1.0` (`emg.activation`) | **Signal source path** exposes cleaned voltage/RMS envelope in µV; event artifact contains optional explicit-threshold bursts. **Report** includes RMS/envelope and frequency summaries. | Filter settings, retained samples, threshold/boundary-truncated support remain distinct. Full artifacts preserve clean/RMS series, not a complete original-voltage overlay or complete EMG spectrum. Existing physiology/artifact cases are source-level evidence; **no EMG-specific complete researcher visual journey was located**. No MVC-normalized, facial/startle or fatigue interpretation is automatically enabled. |
| Temperature, `temperature-calibrated-descriptive/1.0` (`temperature.peripheral`) | **Signal source path** for calibrated °C; **Report** adds source/calibration/context, segment means/slopes and explicitly defined excursion evidence. | Complete typed series/events and report CSV/JSON/HTML available; support does not bridge gaps. [Peripheral browser journey](PERIPHERAL-RESEARCHER-JOURNEY.md) records 48 checks/eight scans and exact temperature reports/exports. Its plotted full/range assertions target acceleration; independent saved-job checks exercise temperature/event previews. A separate Chrome temperature-curve/threshold-overlay receipt is not established. |
| Acceleration, `acceleration-calibrated-triaxial/1.0` (`movement.sensors`, acceleration subset) | **Signal** ordered calibrated axes and derived magnitude in m/s²; optional ENMO g/derivative quantities retain their exact column unit. **Report** has declared gravity policy and operational excursion support. | Recorded 48-check/eight-scan peripheral journey plots actual four-sample g→9.80665 m/s² data and disconnected selected points, exports/reopens unchanged sources. Numeric support/artifact route is generic Signal. No orientation reconstruction, force, GPS or biomechanical inference is enabled by that plot. |
| Audio, `audio-praat-acoustics/1.0` (`audio.acoustics`, acoustic subset) | **Signal source path** exposes frame RMS in FS and spectral centroid in Hz; separate pitch-frame events in Hz. **Report** has pitch/periodicity and source summaries. | Pitch null/unvoiced versus zero-energy centroid support remains typed; frame centre/hop/rate and original audio bytes are retained. Dedicated-environment artifact tests are documented, **not an actual audio-analysis visual browser journey**. No saved waveform/spectrogram/speech transcript view is connected. Native microphone RMS preflight is a separate acquisition check, not this analysis display. |
| `face_geometry_v1` (`webcam.facial`, geometry/native blendshape subset) | **Report only**: features and first compact per-frame observations; complete `vision-observations` JSONL download. `platform-vision-views.R` is the AOI-proposal UI, not a face-result explorer. | Units include image-width ratios, degrees and model-native blendshape values; per-channel valid-frame/time support is retained. Recorded camera journeys process generated non-face video and correctly show insufficient support; they do **not** qualify a successful face-geometry plot. **No dedicated temporal/landmark plot or complete frame table is connected.** |
| `face_pose_hands_v1`, `custom_v1` (`webcam.pose` and selected geometry channels) | Same **Report-only** path; frame artifact retains face/pose/hand landmarks and explicit model states. Custom mode chooses distinct face/pose/hands channels. | Invalid/absent/multiple/border/handedness support stays in saved data; image-plane ratios/angles are not calibrated 3-D motion. Complete JSONL is available, but generic CSV uses the bounded observation preview. **No successful per-channel researcher visual/export acceptance was located; no skeleton/time view or video-linked replay exists in these result hooks.** |

## Enabled response, questionnaire and cross-measure profiles

| Enabled profile / scope | Actual visual, support and export | Recorded evidence / gap |
|---|---|---|
| IAT `iat-gnb2003-d1/1.0` (`implicit.iat`) | **Task** trial chronology/histogram, first versus final-correct latency in ms; **Report** D1 and scoring counts/exclusions. Practice and scored combined blocks remain distinct from mere recorded positions. | The 42-check [task plot suite](TASK-PLOT-ACCEPTANCE.md) covers all five registered task profiles; 11 researcher checks/five scans cover complete 180-trial IAT, native source, incomplete/unknown imports, downloads and cohort switching. This is not a separate browser run for every five-profile combination. |
| Brief IAT `biat-nosek2014-goodfocal/1.0` (`implicit.biat`) | Same **Task** route; saved warm-up/target exclusion and bounded D-score audit remain separate from raw latency points. | Same recorded component coverage and shared browser boundary; no plot-derived rescoring. |
| Keyboard AAT `aat-keyboard-cue-balanced/1.0` (`approach.aat`) | **Task** latency chronology/distribution, **Report** target/action support and relative push-minus-pull initiation advantage in ms. | Same component coverage. No joystick movement/trajectory visualization or motor-execution claim. |
| Simple RT `rt-deary-liewald-simple/1.0` (`choice.psychophysics`, RT subset) | **Task** first-response latency, omissions/errors/practice markers; **Report** independently supported mean/median/SD/error/omission metrics. | One-response mean/median and unavailable SD/omission examples are explicitly tested. No normative/age/cognitive labels. |
| Choice RT `rt-deary-liewald-choice/1.0` (`choice.psychophysics`, RT subset) | Same route with four-choice correctness and explicit missed/incorrect-first status. | Exact denominator and unavailable support remain metric-specific; same five-profile component evidence. |
| Task cohorts (`brohn-task-cohort/1.0`) | **Task** complete saved person-level dots for a selected metric; table and CSV/JSON retain per-person, session, administration and membership evidence. | Repeated sessions are not extra people. Missing linkage disables person estimates; each metric has its own supported denominator. Actual task-plot browser switches measures and inspects partial SD support. |
| Twelve questionnaire types plus branching/revision (`questionnaire.items`, `questionnaire.flow`) | **Answers** complete typed explorer and saved whole-report counts; numeric means only where the saved analysis supplies them. Zero/false/text/null, omissions, not displayed, acknowledged information and invalidations remain distinct. | [Explorer acceptance](QUESTIONNAIRE-EXPLORER-ACCEPTANCE.md): 77 pure/59 storage/40 Shiny; 14 browser assertions/five scans with a subsequent layout-only retake. Complete exports, long Unicode and history tested. **No distribution/condition chart is implemented**; complex answers should not be flattened into a universal numeric plot. |
| Scale scoring `explicit-questionnaire-scale/1.0` (`questionnaire.scales`) | **Report** scale coverage and first 30 assessment rows; complete scale-score CSV and full item-evidence JSON. Saved key, bounds, reverse scoring, missing/prorated status and separate assessments remain explicit. | Actual scale/revision/export journeys are recorded in researcher QA. **No assessment/person distribution or repeated-assessment chart**, and no on-screen complete scale-score paging equivalent to Answers, was found in `brohn_scale_results_ui()`. No reliability/normative interpretation is implied. |
| Object-case `object-case-paired-maxdiff/1.0` (`choice.conjoint_maxdiff`, MaxDiff subset) | Saved exposure-adjusted item bars and identifiable aggregate utility dots; complete numerical tables, SVG and exact plot-values JSON, choice-ledger CSV. Units are complete-pair proportions or sum-zero logits. | [Plot acceptance](MAXDIFF-PLOT-ACCEPTANCE.md): 11 focused and 11 browser checks/five scans; independent paired-likelihood oracle. Unavailable utility/support remains labelled; no confidence interval or individual preference is invented. Item images do not change this scoring/display contract. Conjoint is not enabled by this implementation. |
| Declared paired contrasts and `multimodal-explicit-crosswalk/1.0-draft` (`multimodal.analysis`) | **Report** numerical contrast cards with unit, retained people/paired sessions, uncertainty/support and source coverage; original metric observations export as CSV with full JSON/HTML. | Actual controlled/multimodal/peripheral browser routes are documented in researcher QA. **No dedicated paired-person change/forest plot or synchronized multimodal trace view** is connected. Reviewed identity mapping permits parallel measure comparison, not inferred temporal synchronization. |
| Source-bound signal interval summaries/reuse | Signal interval view plots saved window means and keeps complete-support summary rows; exact table/CSV/JSON/SVG and original artifact references. | [Interval acceptance](SIGNAL-INTERVAL-ACCEPTANCE.md) and [reuse acceptance](SIGNAL-INTERVAL-REUSE-ACCEPTANCE.md) cover actual jobs, range/empty/error/reopen and downloads. These descriptive windows do not provide an event-locked physiological model or complete synchronized media replay. |

## Acquisition is a separate layer

The accepted 15-family live/replay monitoring path shows the selected source's
bounded recent waveform, numeric arrival/committed counts and researcher-reviewed
checks. Gaze coordinates require explicit roles; source-native validity/contact
codes remain source observations. Connected, receiving, durably recording and
selected checks met/unmet/unknown remain different states. See
[acquisition acceptance](ACQUISITION-CHECKS-BROWSER-ACCEPTANCE.md) and
[native participant checks](PARTICIPANT-EQUIPMENT-PREFLIGHT-ACCEPTANCE.md).

These monitoring displays do not close the missing **saved-analysis** views
above. In particular, accepting an EOG source for preservation/monitoring does
not enable an EOG detector, and a camera preview or audio-level bar does not
provide an analysed geometry timeline or acoustic report graph.

## The remaining register is still in scope

No enabled named analysis/visual recipe was found for the following 19 register
entries in the inspected current validators/dispatch. They are implementation
scope, not failures of an already accepted visual profile:

`gaze.naturalistic`, `neural.advanced`, `cardiorespiratory.coupling`,
`emg.facial_startle`, `eog.ocular`, `hemodynamics.advanced`, `webcam.gaze`,
`webcam.physiology`, `implicit.single_category`, `implicit.gnat`,
`implicit.priming`, `implicit.amp`, `approach.vaast_manikin`,
`implicit.agile_relational`, `attention.tasks`, `inhibition.interference`,
`inhibition.stop_signal`, `learning.memory`, `motor.trajectory`.

The five operational entries (`design.protocols`, `centralization.recordings`,
`multimodal.analysis`, `reporting.automation`, `operations.research`) remain
cross-cutting acceptance work; the multimodal recipe is listed above because it
also computes results. Partial register families remain partial: band power is
not every EEG asymmetry recipe, descriptive fNIRS is not a GLM, keyboard AAT is
not a physical movement task, and the five registered tasks do not activate the
rest of the cognitive-task catalog. Preserve the complete 50-entry scope.

## Three prioritized implementation gaps

1. **Give every processed trace a complete accessible value route.** Extend the
   existing verified Signal reader with bounded paged selected-table values and
   a streaming complete selected-measure CSV export. Keep original row/sample
   index, coordinate/unit, retained/missing reason, fragment/identity and source
   hashes; do not export the extrema envelope as if it were all samples.
   This immediately benefits the already enabled EDA, cardiac, respiration,
   EMG, temperature, movement, fNIRS and audio paths. Qualify real saved output
   from each family, including empty/invalid range and keyboard/narrow use.
   Then add measurement-specific event overlays; the first useful bounded one
   is event-EDA baseline/response/candidate windows against complete phasic data.
   Current support-count tables and a downloadable typed artifact alone do not
   fulfill point-level accessible inspection.

2. **Add a source-bound saved video-geometry explorer.** Read complete immutable
   `vision-observations` through a bounded frame/time/channel catalog; provide
   frame-state/validity timeline, exact numerical frame detail and a selected
   landmark/geometry view with units. Retain absent/multiple/border/ambiguous
   states and model-native handedness. Download exact selected data and a
   labelled figure. A video overlay must require an explicit decoded-frame
   binding; browser callback time is not automatically encoded-frame time.
   Test successful face/pose/hand fixtures as well as absent/invalid cases. Do
   not count the existing absent-face automatic report or preflight preview as
   acceptance of this missing result view.

3. **Complete pupil and source-labelled blink visual evidence.** Introduce a
   complete source-bound pupil sample view/artifact before drawing traces; the
   current saved mean cannot supply it. Show original and subtractively corrected
   measurements, the declared baseline window, pupil validity and externally
   labelled blink masks in original units, with gaps and failed-baseline states.
   Keep each exposure/session separate and support an exact numeric/CSV/JSON
   alternative. Qualify known baseline arithmetic and missing/zero/blink
   boundaries through an actual saved-report browser journey. Do not relabel
   tracking loss as a blink or the trace as an attention measure.

These are proposed next slices, not implemented changes from this audit.
Questionnaire/scale charts, paired-comparison plots and modality-specific
overlays remain explicit secondary gaps in the matrix. Cardiac exclusion/reanalysis now has separate direct, curated-source and
researcher-browser evidence in [its acceptance record](CARDIAC-EXCLUSION-ACCEPTANCE.md);
existing input/clean/spectrum views are not re-counted as proof of that workflow. No physical-device, participant usability or broader scientific
qualification is asserted.
