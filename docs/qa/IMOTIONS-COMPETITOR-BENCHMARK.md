# iMotions workflow benchmark for Brohn

Research checked **20 September 2026**. This is a product acceptance benchmark,
not a parity certification. Brohn has working, tested local research workflows;
the evidence reviewed does not establish an end-to-end replacement for iMotions.

## Evidence and interpretation

The audit read official release posts, current product/developer documentation,
and the complete English auto-generated transcripts of five videos on the
[official iMotions channel](https://www.youtube.com/@iMotions). Video titles,
channel identity and exact publication dates were checked on YouTube. The videos
were **transcript-reviewed, not watched end to end or independently reproduced**.
Automatic captions contain errors in product and sensor names; official written
sources take precedence for those names. Demonstration interpretations such as
“engagement” or “surprise” are the presenter's claims, not scientific validation
performed by this audit.

Historical posts are the current accessible versions of dated announcements,
not archived snapshots. For example, the 2021 AOI article was edited in 2026.
The rolling release log contains entries later than this audit date; those were
excluded from the as-of benchmark. Public Help Center links lead to customer
access: gated implementation manuals were not inspected. A first transcript
request for the iMotions 11 video failed and its visible panel remained loading;
reopening the video resolved this and its complete transcript was then read.
No unresolved transcript limitation applies to the five videos below.

### Historical and current primary sources

| ID | Date / generation | Read source and concrete workflow evidence |
| --- | --- | --- |
| H8 | 2 July 2019 / iMotions 8 | [Release announcement](https://imotions.com/blog/learning/product-news/imotions-software-release-8/): select device and R processing algorithm, inspect resulting signals, export; reference-image gaze mapping with manual repair and exclusion of moving regions; named sensor/VR integrations. |
| H81 | 15 September 2020 / 8.1.10 | [Sensor Data Preview and R Notebooks](https://imotions.com/blog/learning/product-news/product-release-news-sensor-data-preview-and-r-notebooks/): configure and inspect incoming signals before/during collection; exposed processing parameters, EEG Welch processing and windowed GSR summaries. |
| H9 | 11 March 2021 / 9.0 | [AOI editor release](https://imotions.com/blog/learning/product-news/product-release-new-areas-of-interest-aoi-editor-in-imotions-9-0/): shape editing, time activation and keyframe interpolation; reusable templates, undo/lock, linked annotations; defined gaze/fixation/saccade metrics and individual/aggregate CSV plus visual export. |
| H92 | 29 March 2022 / 9.2 | [Release article](https://imotions.com/blog/learning/product-news/whats-new-in-imotions-9-2/): reusable automated annotations derived from start/end events, including marker/API/input events, across respondents and stimuli. |
| H10 | 18 January 2024 / 10 | [Release announcement](https://imotions.com/about-us/news/imotions-10-makes-leading-human-behavior-research-platform-more-intuitive-scalable-dynamic/): study setup and builder redesign, configurable study structure and easier management. V10 below supplies more specific narrated actions. |
| H11 | 5 November 2025 / 11 | [Release announcement](https://imotions.com/about-us/news/imotions-launches-imotions-11-delivering-increased-speed-flexibility-insight-to-human-behavior-research/): named hardware additions, native fNIRS, advanced surveys, multimodal dashboard, calibration export and searchable study library. |
| R26 | 12 March 2026 | [Multi-Respondent View](https://imotions.com/blog/learning/product-news/multi-respondent-view/): compare recordings side by side, align their timelines to stimulus, analysis or manual markers, and inspect corresponding signals. The written walkthrough was read; its embedded clip was not separately watched. |
| O26 | 1 September 2026 | [Online launch](https://imotions.com/about-us/news/imotions-online-launch-press-release/): browser links/panel recruitment, randomized and conditional studies, segmentation, annotations and full export. Predictive benchmarking without respondents, media testing with respondents, and custom behavioral research are distinct study types. |
| LOG | Rolling release history, only entries through 20 September 2026 used | [Release notes](https://imotions.com/products/imotions-lab/release-notes/): operational fixes include annotation export, missing gaze support, AOI batch application and synchronized replay ranges. These are regression scenarios, not proof that any release is defect-free. |

### Official YouTube content actually reviewed

Times identify narrated portions of the accessible auto-generated transcripts.
No third-party recap or transcript service was used.

| ID | YouTube publication / source | Observed narration and its acceptance implication |
| --- | --- | --- |
| V10 | 17 January 2024 — [iMotions 10 launch video](https://www.youtube.com/watch?v=eAMrorVxQRw) | 0:20–1:31: setup wizard chooses study context, block-based flow, batch stimulus editing, copied/edited flows for within/between-subject designs. Brohn needs a discoverable route through these actions, not merely a serializable protocol. |
| V11 | 4 November 2025 — [iMotions 11 — New Features](https://www.youtube.com/watch?v=mvHceW5UGlc) | 0:22–1:57: hardware additions, survey logic/media, dashboard, calibration export, whole-stimulus replay and library search. Caption misspellings were checked against H11; this is a narrated feature tour, not a measurement benchmark. |
| V1 | 4 November 2025 — [Mario Kart: From data to insights](https://www.youtube.com/watch?v=KWyRJImKvHg) | 0:35–1:10: survey, reading baseline, racing task. 2:11–3:28: screen eye tracking/face data, gaze replay and race-only annotation. 3:30–4:29: compare conditions, export graphs and their data, then perform statistics **in Excel**. This demonstrates a connected analysis/export workflow; it does not demonstrate that inference was run inside iMotions. |
| V2 | 5 November 2025 — [Mario Kart: More sensors, more insights](https://www.youtube.com/watch?v=bxQAuaBr3lw) | 0:37–1:13: keyboard markers and precise replay navigation. 1:23–2:18: moving-object AOIs and gaze-driven automatic annotations. 2:46–3:01: event-relative ten-second analysis interval. 3:31–3:55: inspect face, voice and transcript outputs alongside other measures. Requires one reusable event definition connecting review, selection and analysis. |
| V3 | 18 November 2025 — [Research outside of the Lab](https://www.youtube.com/watch?v=hMYAHgWjBjc) | 1:02–1:17: glasses, ECG/heart-rate, respiration, EMG and GPS collection. 1:42–2:04: whole-race, lap and segment selections. 2:27–3:38 and 4:08–5:15: synchronized location, muscular activity, gaze, audio and physiological review. The narrator explicitly distinguishes arousal intensity from emotional valence at 1:32–1:38. Naturalistic coordinates and timing require their own qualification. |

## Brohn evidence baseline

Compared against [README](../../README.md), [STATUS](../../STATUS.md),
[known gaps](../KNOWN-GAPS.md), the 50-entry
[capability register](../preparation/capability-register.json) and the 17-package
[build manifest](../preparation/build-manifest.json). Both JSON files have a
preparation date of 8 September 2026. Their `current_status` strings are not a
current feature inventory: for example, the register still describes a single
questionnaire item while current software evidence covers branching, scales,
participant revisions and a complete retained-answer explorer. The register is
used here for intended scope and the manifest for acceptance ownership.

The table distinguishes **existing scoped evidence** from **acceptance not yet
established**. It does not infer that code is absent merely because a reviewed
document lacks an integrated test. Subsequent implementation needs a new dated
acceptance record before a row can be closed.

## Observable acceptance matrix

P0 identifies the common end-to-end lab workflow. P1 extends this to broader
competitive use. These priorities are this audit's product judgment.

| Priority / workflow | iMotions evidence | Required observable Brohn acceptance | Existing evidence and remaining gap | External input |
| --- | --- | --- | --- | --- |
| **P0 Study design → runnable plan** | H10, V10; [Study Builder](https://imotions.com/products/imotions-lab/features/study-builder/) documents media, blocks, study flows, sensor selection and live markers. | Start from blank/template; add baseline, media, survey and task; batch-edit, assign two flows, preview actual participant layout, freeze and run; edit a reusable source without changing the frozen run. | Libraries, clones, templates, portable designs, branching and five task profiles have connected evidence in README/STATUS. One multimodal scenario must show all transitions without manual database/script intervention. `design.protocols`, BWP03–05/15. | Representative researchers for observed completion; protocol materials for additional task packs. |
| **P0 Device setup → live quality → collection** | H81, H11; [LSL support](https://imotions.com/products/imotions-lab/developers/lsl-support/) explicitly depends on an available LSL-capable device adapter. | Choose named streams, inspect units/rates/quality, associate participant and frozen plan, calibrate where required, start/stop visibly and seal originals; dropout/reset/disconnect have explicit outcomes. | [Local acquisition](../operations/LOCAL-ACQUISITION.md) has explicit selection, original archives and recovery; [completion investigation](ACQUISITION-COMPLETION-INVESTIGATION.md) reports 75 corrected checks. This is transport evidence, not device or signal-validity qualification. `centralization.recordings`, BWP06/16. | Named physical devices, entitled SDKs and reference/calibration equipment. |
| **P0 Synchronization and stimulus events** | H8, H92, V2/V3; [API](https://imotions.com/products/imotions-lab/developers/api/) documents receiving/forwarding events and remote run controls. | Preserve source clocks; record mapping/offset uncertainty, actual stimulus/event identity and gaps. A known common event must line up across two streams, video and participant events within a declared, measured tolerance; refuse unsupported joins. | Multistream preservation and import bridges exist. Current signal views explicitly perform no automatic alignment. A unified qualified capture→aligned-review journey is not established. `centralization.recordings`, `multimodal.analysis`, BWP05/06/13/16. | Physical onset/clock reference for hardware timing claims; synthetic common-event fixtures can proceed immediately. |
| **P0 Individual and group replay** | R26, V1/V3; [Analysis](https://imotions.com/products/imotions-lab/features/analysis/) describes synchronized individual and aggregate review. | Scrub one shared timeline showing stimulus/video, gaze and selected signals; step to events, adjust range, compare respondents aligned to a chosen marker; keep unsupported spans disconnected and expose numerical alternatives. | [Signal views](../methods/SIGNAL-PREVIEW.md) preserve exact support/extrema; [gaze views](../methods/GAZE-REPORT-VIEWS.md) pin one exposure. These are useful components, not evidence of shared multi-respondent audiovisual replay. BWP07/13/15. | Rights-cleared synchronized example recordings; no device purchase needed for imported-data implementation. |
| **P0 Annotations → reusable analysis windows** | H92, V2, R26. | Add/edit marker and interval by keyboard/mouse; save author/history; define an event-relative window once; apply across chosen participants/stimuli; handle overlapping, absent and repeated events; recompute a new report without altering the old one. | Event-related EEG/EDA and pinned comparison plans exist. A common researcher-facing annotation editor and reusable rule flow spanning media and modalities is not established by the reviewed evidence. BWP07–09/13/15. | Independent event/window fixtures; domain review of each interpretation. |
| **P0 AOI correction → metrics → reuse** | H9, V2. | Draw/correct rectangular and polygonal regions; define time activation and moving keyframes; preview interpolation; undo, copy template, review proposals; inspect TTFF censoring, overlap and valid-time denominators; export per-person and aggregate results. | Static pinned gaze/AOI reports and reviewed vision proposals are connected. Full dynamic/video AOI authoring, object tracking and linked dwell-annotation workflow remain unqualified. `gaze.aoi`, BWP07/11. | Representative labeled videos and model rights for automated proposals. Manual authoring can proceed independently. |
| **P0 Processing → reproducible multimodal comparison** | H8/H81 describe exposed R processing; V1/V2 connect measures to selected conditions/events. | Select source-bound recipe, baseline/window and quality policy; show effective parameters and retained support; compare by participant/condition using declared repeat/missingness policy; one failed modality must not erase good outputs. | Supervised physiology/EEG jobs, planned comparisons, synthesis and descriptive task cohorts have scoped evidence. Full registry coverage and the annotation-to-cohort journey remain open. No universal latent “engagement” score follows from available sensor columns. BWP08–13. | Independent numerical fixtures for each recipe; scientifically appropriate reference data. |
| **P0 Export → historical reopen → reuse** | H9, V1; API documents study ZIP, raw sensor and recording exports. | Download raw, processed, event/AOI and summary tables plus exact plotted data/settings; reopen old report after design changes; clone design without participant records; import into a fresh installation and reproduce eligible outputs. | Full artifacts, HTML/CSV/JSON, design ZIPs, immutable history and backup routes exist. [Questionnaire explorer](QUESTIONNAIRE-EXPLORER-ACCEPTANCE.md) demonstrates 720 answers and retained revisions beyond preview limits. Whole-catalog cross-installation reproducibility remains open. BWP01/02/13/17. | Clean supported machine and permitted redistributable fixture assets. |
| **P1 Naturalistic / glasses / VR** | H8/H11, V3; Study Builder distinguishes screen-free, glasses and VR. | Import/record scene/world data; retain camera geometry, distortion correction, calibration and reference mappings; repair mappings and review synchronized scene/audio/physiology. | `gaze.naturalistic`, movement extensions and BWP16 remain planned/qualified separately. A screen-normalized image overlay is not this workflow. | Exact glasses/VR/GPS device profile, calibration, licenses and real-world reference recordings. |
| **P1 Face, voice and webcam modalities** | H11, V2/V3, O26. | Keep geometry, AU/expression estimates, voice acoustics, transcript and webcam physiological estimates distinct; show model/version, consent/retention, missing-face/audio quality and validated prerequisites. | Camera consent/capture and optional local geometry are connected; acoustic processing exists. Expression/AU provider, calibrated webcam gaze and webcam physiology need implementation/reference evidence. `webcam.*`, `audio.acoustics`, BWP11/12. | Entitled model/provider and reference recordings. These do not block geometry/acoustics work already supported. |
| **P1 Remote participants and research operations** | O26; API documents integration with collection/distribution infrastructure. | Create scoped participant link; recruit/assign, consent, resume, close/reopen under policy; isolate projects, revoke access, monitor failures and restore consistently; share a frozen report with explicit access rules. | Loopback participant delivery is tested. HTTPS hosting, researcher authentication, full enrollment/waves and controlled sharing are not qualified. BWP02/05/15/17. | Host/domain/TLS, operator and recruitment/panel credentials. Access policies and local tests are implementation work. |
| **P0 Supported installation and recovery** | [System requirements](https://imotions.com/products/imotions-lab/system-requirements/) names Windows, hardware and optional GPU/device requirements; LOG documents real recovery/export edge cases. | Install supported profile on a clean machine; open supplied study, collect/import, analyze, export, recover interrupted work and restore backup; missing optional hardware/models yields a concrete supported route. | Restored R library, Windows entry points, durable jobs, resource guards and service recovery have evidence. Clean-machine product installer and full supported-profile catalog remain open. `operations.research`, BWP15/17. | Clean test machines and declared hardware/OS profiles. Human onboarding/manual accessibility evaluation remains necessary. |

## Next product gates

1. **Deliver one complete local multimodal journey:** frozen study → explicit
   stream/import setup → common events → shared replay/annotation → corrected AOI
   → condition/cohort comparison → exact export → historical reopen. Retain real
   UI/worker artifacts and independent numeric oracles at every handoff.
2. **Close the shared review layer:** one timeline, event/interval editor and
   reusable window definitions across stimulus, video, gaze and physiology.
   This is the clearest gap between today's separate viewers and the reviewed
   demonstrations. It can be built and tested with imported fixtures now.
3. **Qualify named acquisition and supported installation profiles**, including
   clock/onset measurements and restart/restore. A generic LSL inlet or passing
   synthetic test does not establish plug-and-play sensor support.
4. **Complete wider product routes explicitly:** dynamic/naturalistic gaze,
   entitled face/webcam outputs and hosted operations. Preserve visible status
   and supported alternatives until each has its own acceptance evidence.

The benchmark does not require copying every commercial module or inferred
emotion claim. It requires a declared competitive scope whose enabled workflows
actually connect, with remaining product implementation separated from the
hardware, provider, hosting and human-evaluation inputs needed to qualify it.
