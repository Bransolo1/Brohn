# Measurement visual coverage audit

24 September 2026 update to the 20 September source audit for PC05.
New scoped evidence is linked below; the original whole-profile audit was not
rerun as a complete suite. **Recorded evidence**
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
| **Signal** | Complete source-bound signal plots keep gaps, units and coverage; exact selected values now have bounded paging, original typed fields and complete CSV plus schema/provenance. Numeric exports read the full chosen table/range, not its envelope. [Processed-value acceptance](PROCESSED-VALUES-ACCEPTANCE.md) records 22 browser assertions/five scans and an independent audit of all 108,414 rows across six downloads. This shared route does not qualify every modality-specific interpretation or navigation latency. |
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
| Pupil and externally labelled blinks within sampled-gaze (`gaze.pupil_blink`) | Complete retained pupil samples support original/corrected traces, baseline context, validity/blink masks, exact values, complete artifact/CSV and source-bound SVG. Unsupported correction stays absent; labels retain original units and separate exposures. | [Trace acceptance](PUPIL-BLINK-TRACE-ACCEPTANCE.md): 28 browser assertions/five scans plus eight independent SVG checks, cancellation/retry and full service restart with byte-identical saved exports. Calibration, luminance confounds, source blink-label accuracy and baseline appropriateness remain separate. |
| EEG channel Welch, `eeg-welch-channel/1.0` (`eeg.spectrum`) | **Signal** complete frequency-bin density in µV²/Hz; **Report** band powers in µV², relative-power denominators and RMS. Axis stays Hz. | Full frequency artifact, exact observed bins/support, empty/invalid range handling and Signal exports. No raw-voltage sample table is emitted by the current Welch artifact adapter, so its report does not acquire a raw EEG waveform through this path. Recorded 45 native-header/EDA checks plus 34 Signal checks exercise actual EDF spectrum and exports. [Recorded EDF agreement](EEG-WELCH-RECORDED-REFERENCE.md) is numerical reference evidence, not another browser walkthrough. |
| EEG ERP, `eeg-erp-epochs/1.0` (`eeg.erp`) | **Neural** mean voltage ± saved pointwise trial SEM, µV versus seconds, positive upward; saved baseline and component settings are visible. | Retained/requested/excluded trials, event/source declarations, null SEM for one trial and unavailable conditions remain explicit. CSV/JSON/SVG/HTML available. Recorded 66 Chrome checks/seven scans across ERP/Morlet/tagging include independent 10/20-µV pulses and exports ([neural plots](../methods/NEURAL-PLOTS.md)). A dedicated individual-trial waveform/rejection-raster display is not implemented by this adapter. |
| EEG Morlet, current `eeg-morlet-epochs/1.1`, historical `/1.0` (`eeg.time_frequency`) | **Neural** complete time-frequency map plus exact frequency slice. Raw power µV², frozen transform units or ITC 0–1; native pixels retain all saved cells, with discrete actual-frequency rows. | Missing and unsupported masks differ from zero; baseline duration/kernel support and trial counts remain visible. Complete CSV/JSON and map/slice SVG/HTML. Recorded 67 component checks and fresh 21 browser checks/six scans in [map acceptance](NEURAL-TIME-FREQUENCY-MAP-ACCEPTANCE.md), including missing/zero/unavailable and reopened versions. Source-label Unicode under the separate neural CSV writer was not independently re-audited here. |
| EEG tagging, `eeg-frequency-tagging/1.0` (`eeg.frequency_tagging`) | **Neural** trial-mean PSD µV²/Hz with saved target-bin markers; neighboring noise and SNR remain saved features. | Exact FFT/bin/window and trial support, zero-noise unavailable SNR and no invented target selection. Same CSV/JSON/SVG/HTML path. The recorded 66-check neural journey tests a known 400-density target, noise 4 and SNR 100. No physical flicker-output qualification is implied. |
| fNIRS, `fnirs-od-beer-lambert/1.0` (`fnirs.hemodynamics`, descriptive subset) | Complete optical density and HbO/HbR-change columns retain native indices, original clock, wavelength/pathlength factors and disconnected source segments. Exact point/CSV/typed-source exports are connected. | [Independent phantom](FNIRS-INDEPENDENT-PHANTOM.md) and [visual/export record](FNIRS-VISUAL-ACCEPTANCE.md) distinguish saved-output checks from current browser acceptance. Final browser acceptance passes 33 assertions/five scans and all 3,580 selected source rows; narrow-screen label collisions are corrected and tested. Joint HbO/HbR comparison, event GLM, motion correction and short-channel models remain open. |
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
| `face_geometry_v1` (`webcam.facial`, geometry/native blendshape subset) | Complete source-bound frame/metric explorer is connected to reports: validity timeline, selected measure/time range, exact original frame JSON, native landmark pages, genuine decoded PNG overlay and complete numeric CSV/manifest. | [Researcher journey](VIDEO-GEOMETRY-RESEARCHER-JOURNEY.md) records current face/pose/hand browser evidence and retained failures; [resource acceptance](VIDEO-GEOMETRY-RESOURCE-ACCEPTANCE.md) covers a separate 36,000-frame synthetic native-width index. Four-frame model/browser cases do not qualify browser paging beyond the old 2000-frame preview. Geometry/blendshapes are not validated emotion or attention. |
| `face_pose_hands_v1`, `custom_v1` (`webcam.pose` and selected geometry channels) | Same complete explorer, with native pose/hand points, explicit handedness and saved validity states; mixed-validity buckets remain visibly mixed. | Same scoped [journey](VIDEO-GEOMETRY-RESEARCHER-JOURNEY.md). Original encoded dimensions and PTS bind recorded pixels; image-plane geometry is not calibrated 3-D motion. Synchronized multimodal/media replay and wider browser capacity remain separate. |

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

## Implemented priorities and remaining review work

The original three priorities (complete processed values, saved video geometry,
and retained pupil/blink traces) now have connected implementations. The
[September 24 checkpoint](PUBLICATION-CHECKPOINT-20260924.md) and linked records
state their executed browser, export, restart and resource boundaries.

Remaining work includes complete saved-output journeys for every enabled family,
event-EDA baseline/response overlays, respiration/EMG/audio-specific views,
questionnaire/scale distributions, paired-person comparisons and synchronized
multimodal replay. Exact values and an accessible generic chart do not replace
those modality-specific requirements. Video also needs a connected browser case
beyond the legacy 2000-frame preview; the independent 36,000-frame index test is
separate evidence. Large-report navigation and repeated synchronous context reads
need profiling with original source authority preserved.

Cardiac exclusion/reanalysis retains separate direct, curated-source and
[researcher-browser evidence](CARDIAC-EXCLUSION-ACCEPTANCE.md). Physical devices,
participant/human comprehension and broader scientific qualification remain open.
