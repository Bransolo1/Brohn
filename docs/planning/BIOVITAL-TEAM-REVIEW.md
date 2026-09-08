# Biovital and R architecture team review

Audit date: 5 September 2026. Reviewed the five named strategy, R architecture, UX/roadmap, webcam and backlog deliverables against the whole brief. This is a planning/evidence review: no application, scientific validation or usability benchmark has been executed. P0 means the gap must be resolved before claiming the affected launch capability; it is not an allegation of a defect in shipped software.

The baseline covers the right scope and is unusually explicit about immutable data, scientific limits, standalone R, holistic acquisition and novice usability. Its main weakness is the distance between those principles and executable contracts: a developer could still implement an attractive screen that records incomplete data, changes a scientific recipe without invalidating results, or reports a plausible metric with the wrong denominator. The new architecture supplement specifies those boundaries in detail.

Keep the undergraduate guided eye-study route as the main operator experience. Keep eye/EEG/EDA, physical AAT, a specified brief IAT, reaction times, questionnaires and qualified webcam workflows in the holistic platform. The behavioural specialist's `implicit-specialist-review.md` defines IM-G01–IM-G09, including distinct BIAT paper/vendor profiles, AAT input/mapping, precision planning and inference. This review does not substitute a generic D-score for those definitions. Its architecture counterpart is `architecture-contract.md`, including three full sequence flows.

## Findings and acceptance contracts

### BIO-G01 · P0 · Required streams need an arm/start/stop/finalize protocol

**Brief requirement:** An undergraduate must reliably collect the holistic rig through one understandable flow.

**Baseline evidence:** R-ARCHITECTURE.md:171–179 and 624; backlog B011, B126–B140. Discovery, buffers and disconnects are already required; barrier, identity reservation and terminal completeness are unspecified.

**Implementation fix:** Add stable physical/source identity matching, station lease, required/optional stream plan, capture-ready barrier, pre-roll, idempotent start/stop and a final manifest with expected terminal sequences. Separate participant end, local save, verified transfer and report eligibility.

**Acceptance:** Same-name source ambiguity blocks arming; failed required recorder prevents first scientific stimulus; failed stop or missing final chunk yields a recoverable partial manifest. GUI/network loss cannot stop a qualified local recording or trigger silent trial replay.

**Now versus later:** Planning contract specified here. Exercise simulator crashes at G2, then simultaneous reference-eye/EEG/EDA/physical-AAT recording, missing stream, disk exhaustion and stop/restart faults at G3. Implementation and validation remain future work.

**Evidence:** BIO-UI06, BIO-UI08, BIO-UI10

### BIO-G02 · P0 · Calibration and channel configuration need validity scope

**Brief requirement:** Classic biosignal centralisation must preserve what was actually measured and guide novice preparation.

**Baseline evidence:** R-ARCHITECTURE.md:107,171,221–223; B019–B021, B128, B130, B132. Fields and health views exist conceptually; eligibility and expiry logic are left open.

**Implementation fix:** Introduce versioned device configuration and PreflightEvidence tied to participant, serial/firmware, sensor placement, channels, gain/units, reference/ground, hardware filters, coordinate transforms and validation context. Store actual settings separately from requested ones. Mark unavailable contact metrics as unsupported; define recalibration triggers after refit/restart/context change.

**Acceptance:** Round-trip retains physical channel mapping and reference; changed camera/viewport, EEG reference or sensor replacement invalidates affected readiness. A vendor contact score cannot be displayed as measured impedance unless that is its documented quantity. Sample mode requires no fitting.

**Now versus later:** Planning contract specified here. Confirm sensor-specific calibration/fit procedures and permissible evidence reuse on each supported rig; test novice recovery from deliberately changed settings. Implementation and validation remain future work.

**Evidence:** BIO-UI05, BIO-UI07, BIO-UI09

### BIO-G03 · P0 · Timing gates need per-path metrology and failure consequences

**Brief requirement:** EEG, RT, joystick, eye, webcam and questionnaire events must align without overstating precision.

**Baseline evidence:** R-ARCHITECTURE.md:197–209; B029–B030, B065, B134–B136, B206, B211. Physical tests and percentile targets are already proposed; exact profiles and output-specific consequences remain undefined.

**Implementation fix:** Publish a latency/error budget per device→host, display→physical onset, input→event and clock-mapping path. Preserve raw clocks and physical metrology separately. Tie each method to permitted bias/jitter/tails/gaps over study duration; hold software/OS/driver/browser profile identity.

**Acceptance:** Known display delay cannot disappear after LSL offset correction. Source restart creates a new segment; deliberately injected drift/tail failure disables the affected ERP/RT output or marks an explicit limitation according to its frozen profile. Broad AOI summaries can remain eligible when a fine timing method is not.

**Now versus later:** Planning contract specified here. Use shared physical pulses, photodiode/audio loopback and calibrated input injection under full acquisition/preview/worker load; preregister tolerances before qualification. Implementation and validation remain future work.

**Evidence:** BIO-UI06, BIO-UI10, BIO-S01

### BIO-G04 · P0 · EEG automation needs an exact artifact and spectral method card

**Brief requirement:** End-to-end EEG processing must produce reproducible interpretable consumer/UX outputs.

**Baseline evidence:** R-ARCHITECTURE.md:223,228; B038–B039, B098, B141–B142. Pipeline capabilities are named but algorithms and output definitions are not yet fixed.

**Implementation fix:** Specify import/reference/montage/rank checks, actual hardware filters, offline filter design/phase/padding/boundaries, bad-channel and interval rules, optional ICA training/apply datasets and component disposition, interpolation policy and spectral estimator. Distinguish evidence review from component removal. Qualify one spectral profile first; ERP remains its own profile.

**Acceptance:** A fixture with rank reduction, removed intervals, channel permutation and known spectral components produces expected units/features. Filtering does not cross declared gaps; ICA flags alone do not subtract components. Automated repair and rejection produce distinct masks and counts.

**Now versus later:** Planning contract specified here. Independent comparator and held-out rig data establish spectral/error tolerances and retained-data effects. No fixed filter/ICA threshold is declared universally valid by this audit. Implementation and validation remain future work.

**Evidence:** BIO-UI01, BIO-UI02, BIO-UI03, BIO-UI04, BIO-S02, BIO-S03

### BIO-G05 · P0 · EDA tonic/phasic and event summaries need explicit acquisition-compatible definitions

**Brief requirement:** Agile EDA analysis must run automatically while respecting physiology and the actual signal.

**Baseline evidence:** R-ARCHITECTURE.md:222,230,234; STRATEGY.md:99; B021, B037, B097, B143. Units, windows and overlaps are acknowledged; selected decomposition/threshold/normalization profile remains open.

**Implementation fix:** Separate DC-capable conductance/tonic summaries from phasic analysis; retain site, sensor circuit, units/range, hardware filtering, sampling and contact evidence. Freeze cleaning/decomposition/SCR detector, threshold units, latency/search/recovery windows, overlap rule and baseline/normalization. Never select event-vs-interval analysis merely from library defaults or trial duration.

**Acceptance:** Known unit scaling, nonresponse, disconnected flatline, overlap, edge-truncated peak and inadequate baseline each yield their declared distinct result. A phasic-only source cannot produce tonic SCL. Missing windows do not become zero-amplitude responses. Passive and active-rating windows cannot be conflated.

**Now versus later:** Planning contract specified here. Validate a named method against pinned reference implementation and rig data at actual rates. Characterise differences among methods instead of demanding all legitimate decompositions agree. Implementation and validation remain future work.

**Evidence:** BIO-S04

### BIO-G06 · P0 · Eye/AOI metric names need exact integrals, denominators and no-event rules

**Brief requirement:** A novice common-eye-study report must be automatic and understandable.

**Baseline evidence:** R-ARCHITECTURE.md:221,459–468; STRATEGY.md:95–96; B036, B073, B077, B089–B093. Required distinctions are listed, but dwell share and fixation assignment are still underspecified.

**Implementation fix:** Give sample-time gaze dwell and fixation-based dwell separate method IDs. Freeze exposure/visibility, binocular validity, interval integration/gap cap, AOI boundary/overlap assignment, fixation detection/assignment and visit rules. Define raw duration, eligible valid time, coverage and condition contrast. Define no fixation as a no-event/censor case, invalid exposure as missing.

**Acceptance:** Hand-calculated fixtures for irregular sampling, last sample, one invalid eye, short/long gaps, overlapping AOIs, boundary points, absent targets and all-invalid exposure match the method card. The flagship contrast is B minus A in percentage points (positive means greater gaze share for B; A is the reference). Swapping A/B reverses the signed contrast while preserving absolute quality counts. Webcam profile cannot inherit laboratory fixation eligibility.

**Now versus later:** Planning contract specified here. Qualify the chosen primary method and minimum eligible-data rules on held-out dedicated/webcam data separately; test students can explain denominator and absent-vs-not-looked distinction. Implementation and validation remain future work.

**Evidence:** BIO-S05

### BIO-G07 · P0 · Webcam qualification needs frame/model-specific eligibility and retained-data limits

**Brief requirement:** Webcam gaze and emotion/attention research must be accessible and scientifically scoped.

**Baseline evidence:** WEBCAM-EMOTION-ATTENTION.md sections 1–5; R-ARCHITECTURE.md:185–191; B207–B230. Observation/inference separation and condition strata are strong; deployable eligibility thresholds and downstream replay guarantees are not fixed.

**Implementation fix:** Tie each camera/browser/model profile to actual delivered and processed frame cadence, timestamp availability, spatial/temporal error, multi-face/occlusion masks, calibration coverage and revalidation triggers. Register frame and inference clocks separately. Link gaze, blink/AU and expression annotations to their own qualification and exact weight licences. Explain inability to re-extract if raw frames are not retained.

**Acceptance:** Camera swap, tab suspension, inference backlog and multiple faces produce scoped invalid intervals. Model confidence never becomes assumed calibrated probability. With raw-video retention off, export records reproducibility limits; sample mode requests no permission. Region gaze does not unlock pupillometry/reading/precise saccades.

**Now versus later:** Planning contract specified here. Independent gaze targets and task-specific reference measures; named population/condition strata; model-specific behavioural annotation agreement. Reported emotion remains a separate construct criterion. Implementation and validation remain future work.

**Evidence:** BIO-S06

### BIO-G08 · P0 · Multimodal joins need explicit analysis units and eligibility sets

**Brief requirement:** Link explicit liking to biovitals and implicit outcomes without pseudoreplication or unnecessary data loss.

**Baseline evidence:** R-ARCHITECTURE.md:285,466–468; B079, B091, B100–B102, B222. Participant structure and missingness are recognised; per-output cohort/overlap semantics remain unspecified.

**Implementation fix:** Store exposure and analysis-unit IDs separately from samples/events. Create an eligibility manifest for every result with modality-specific exclusions, paired-complete sets, joint matched sets, structural missingness and dropped observation reasons. Keep A/B two-image recipe distinct from multi-item and independent-group methods. Join liking once per declared observation; AOI expansion cannot multiply respondent N.

**Acceptance:** A fixture with usable liking but missing eye/EEG preserves liking-only N and gives the correct smaller paired/joint N. Repeated trials increase observations but not independent participants. Delayed EDA and joystick movement/rating epochs preserve overlap tags and cannot become independent stimulus responses by ID join alone.

**Now versus later:** Planning contract specified here. Independent statistical review and simulation of intended paired/multi-item/association recipes, missingness sensitivity and uncertainty coverage. Cross-reference IM-G07/IM-G08. Implementation and validation remain future work.

**Evidence:** BIO-S04

### BIO-G09 · P0 · QC waivers and report readiness need deterministic disposition rules

**Brief requirement:** Automatic end-to-end reporting must make failures comprehensible without bypassing science.

**Baseline evidence:** R-ARCHITECTURE.md:215,474–478; UX-AND-ROADMAP.md exception review; B079–B084, B103–B110. Deferred/waived states and stale-output guards exist; permission to publish after each disposition is not defined.

**Implementation fix:** Separate observation quality finding, proposed repair and human/policy disposition. Scope decisions to immutable artifact hashes and outputs. Declare unwaivable method prerequisites versus waivable documented limitations. Publish provisional, partial-scope and final-complete states with correct denominator and limitations. Clean qualified policy-approved data can pass without extra clicks.

**Acceptance:** Waiving missing calibration cannot manufacture method eligibility. No valid data yields unavailable output rather than zero effect. Changed inputs invalidate affected approvals. A permitted eye-only report clearly states missing EEG while a full-rig final report remains blocked.

**Now versus later:** Planning contract specified here. Seeded exception study with novice and expert operators: correct recovery, no silent data loss and correct understanding of partial results. Implementation and validation remain future work.

**Evidence:** BIO-UI02, BIO-UI03

### BIO-G10 · P1 · Qualification needs a fixed corpus and typed evidence registry

**Brief requirement:** The platform must earn reliable automation and market-leading workflow claims.

**Baseline evidence:** R-ARCHITECTURE.md:595–613; UX-AND-ROADMAP.md claim ladder; B008, B086–B087, B140–B149, B201, B223–B226. Benchmark categories exist; dataset manifests, threshold ownership and release assertions are not concrete.

**Implementation fix:** Create QualificationProfile records with named use case, version matrix, dataset/consent/licence manifests, train/tune/test separation, independent reference, preregistered thresholds, failure strata and signed outcome. Separate numerical equivalence, construct validity and user-effort evidence; algorithm agreement alone establishes none of the others.

**Acceptance:** Each claimed supported output resolves to an evidence record and approved tolerance. A failing subgroup/condition cannot disappear from the aggregate. Same-method agreement, AOI downstream metric error, inter-rater disagreement and novice time/correctness appear independently. No build is labelled validated from screenshots or synthetic fixtures alone.

**Now versus later:** Planning contract specified here. Run held-out physical/scientific and usability evaluations at G3/G4; quantify uncertainty and publish limited support matrix at G5. Implementation and validation remain future work.

**Evidence:** BIO-UI01, BIO-UI03, BIO-S05

### BIO-G11 · P2 · Broader biovital centralisation needs an explicit extension boundary

**Brief requirement:** Classic biosignal centralisation should not accidentally exclude later ECG/PPG/HRV, respiration and EMG.

**Baseline evidence:** STRATEGY.md:5 and 13 define launch core; backlog B195 already names ECG/PPG/HRV and B196 EMG at D:G7. These are covered later, not omitted. Respiration lacks its own explicit staged pack.

**Implementation fix:** Reserve typed ECG, PPG, respiration and EMG streams in the extension taxonomy, and add later qualified acquisition/import/analysis packs. HRV is derived from a declared beat/interval source with correction, duration and context requirements; ECG and PPG are not interchangeable by renaming. Keep these outside required G5 scope unless funded scope is revised.

**Acceptance:** The capability registry distinguishes planned/imported/acquired/method-qualified support. Unknown generic voltage streams cannot be advertised as ECG/HRV. Later pack manifests require sensor/site/unit/timebase, event detection, artifact decisions and method-specific benchmarks.

**Now versus later:** Planning contract specified here. Future reference-device and beat/respiration/EMG method qualification; this audit resolves taxonomy/staging, not clinical or physiological validation. Implementation and validation remain future work.

**Evidence:** Baseline contract audit; proposal rather than an externally observed product fact.

### ARC-G01 · P0 · Guided frontend state needs one authoritative domain model

**Brief requirement:** A premium low-click R frontend must change the same objects that determine acquisition and analysis.

**Baseline evidence:** R-ARCHITECTURE.md:17–24,59,345–369,437–443; B013–B018. Component separation exists; screen→command→stored object mapping is incomplete.

**Implementation fix:** Adopt the architecture supplement object/UX map: StudyDraft, CompiledStudyRevision, ParticipantAllocation, RunSession, PreflightEvidence, ReviewDecision, ResultCardManifest and ReportSnapshot. Use revision preconditions and typed command replies. Bind design/measure/question controls to saved changes and dependent eligibility, not cosmetic client state.

**Acceptance:** Switching paired to independent/multi-item design cannot retain old paired current results. Reload and Advanced↔Guided round-trip reconstruct the same revision; two-editor conflicts are explicit. Every visible enabled action has a tested command or local-only state label.

**Now versus later:** Planning contract specified here. Integration contract tests plus novice/expert usability tests; Shiny/TypeScript prototype responsiveness under realistic viewport/graph interactions. Implementation and validation remain future work.

**Evidence:** Baseline contract audit; proposal rather than an externally observed product fact.

### ARC-G02 · P0 · Publish needs an atomic compilation and allocation boundary

**Brief requirement:** Questionnaire/tasks/analysis must execute exactly the reviewed frozen study.

**Baseline evidence:** R-ARCHITECTURE.md:244–285,349–368; B018, B041–B055. Safe AST and frozen manifests are required, but atomic asset publication, compiler source maps and allocation retry semantics are absent.

**Implementation fix:** Preseal assets; validate typed questionnaire AST and recipe graph with R/TS parity; commit CompiledStudyRevision and outbox in one metadata transaction. Allocate participant/counterbalance exactly once per idempotent run-creation command; mode is mandatory and immutable.

**Acceptance:** Lost publish reply returns same release on retry; incomplete asset prevents release; null/skip branch fixtures agree in R and browser. Sample/preview cannot enter live cohort or consume live allocation. An old release never resolves mutable question/asset/method references.

**Now versus later:** Planning contract specified here. Crash/transaction, compiler parity and malicious-content/unsafe-expression tests; full preview-to-live response/event comparison. Implementation and validation remain future work.

**Evidence:** Baseline contract audit; proposal rather than an externally observed product fact.

### ARC-G03 · P0 · Browser journal and upload finalization need durable acknowledgment rules

**Brief requirement:** Remote/browser and offline collection must recover without missing or replayed observations.

**Baseline evidence:** R-ARCHITECTURE.md:177–179 and jobs; B062, B137, B213, B217. Local persistence and replay prevention exist as intentions, without sequence/ACK/conflict/finalization payloads.

**Implementation fix:** Use source/segment/sequence identities, schema/hash-checked numbered event batches, contiguous durable ACKs, staged object upload and expected final sequences. Separate local durable spool from remote ACK. Monitor quota; enforce bounded interruption/recovery policy.

**Acceptance:** Out-of-order duplicates deduplicate; same sequence/different hash quarantines; dropped last chunk blocks verified completion. Reload/network reconnect never silently replays a presented trial. Quota-full results remain recoverable/partial with explicit missing intervals.

**Now versus later:** Planning contract specified here. Supported browser/storage/OS matrix tested with network loss, quota exhaustion, tab suspension and process crash; no universal power-loss durability claim. Implementation and validation remain future work.

**Evidence:** BIO-UI10, BIO-S07

### ARC-G04 · P0 · Jobs need transaction-to-queue delivery and stale-worker promotion controls

**Brief requirement:** Automation must survive process loss and produce one coherent artifact history.

**Baseline evidence:** R-ARCHITECTURE.md:384–407; B032–B035. At-least-once, leases and atomic promotion already exist; application transaction/outbox and expired lease promotion details are unspecified.

**Implementation fix:** Commit command result and outbox event with metadata; retry outbox delivery. Split analysis spec/job/attempt; check active lease token at artifact promotion; enforce artifact-key uniqueness including all scientific dependencies. Never rely on Shiny session memory to schedule recovery.

**Acceptance:** Crashes before/after SQL commit, delivery, output write and promotion yield no lost accepted job or duplicate current artifact. Old worker cannot promote under expired lease. Render retry reuses pinned computed results without rerunning science.

**Now versus later:** Planning contract specified here. Fault-injection integration tests under concurrent attempts, cancellation and restart; performance measurements on declared corpus. Implementation and validation remain future work.

**Evidence:** BIO-S08

### ARC-G05 · P0 · AOI edits need approval and report snapshot invalidation semantics

**Brief requirement:** End-to-end AOI automation must preserve scientific meaning through correction and recomputation.

**Baseline evidence:** R-ARCHITECTURE.md:313,343,474; B074, B078, B083, B109, B180. Invalidation exists but target-hash approval and concurrent recompute publication boundaries are incomplete.

**Implementation fix:** Separate AOI semantic identity, geometry revision, decision target and dependency graph. Save under concurrency precondition; invalidate affected mapping/metrics/contrasts/report approval; retain previous report historically; current pointer advances only when all dependency revisions match.

**Acceptance:** A concurrent old analysis cannot overwrite new current results. Undo creates a new revision. Outcome-blind correction policy is recorded. Aggregate cohort changes invalidate more than the edited stimulus where necessary; clean approved AOIs add no compulsory review clicks.

**Now versus later:** Planning contract specified here. Race/replay and independent AOI fixture tests, followed by blinded metric-error and review-time evaluation. Implementation and validation remain future work.

**Evidence:** Baseline contract audit; proposal rather than an externally observed product fact.

### ARC-G06 · P0 · Local/cloud deployment needs station pairing and resource ownership

**Brief requirement:** The R app must work locally/offline and support lab/remote use without assuming cloud hardware access.

**Baseline evidence:** R-ARCHITECTURE.md:24,90–92,433,568–593; B016, B116–B121, B126, B181. Topology options are described; station control, auth/storage connections and scheduler priorities remain broad.

**Implementation fix:** Use one local metadata authority, independent acquisition supervisor and paired scoped station connection; shared mode uses PostgreSQL/object store. Isolate R workers/CV inference; protect capture over preview/jobs. Rebuild Shiny state after reconnect. Use authenticated HTTPS and validated origins/scopes rather than exposing arbitrary local device endpoints. Resolve G5 minimum access/backup requirements versus C:G6 shared-role/backup tickets B178/B182: basic local controls and restore evidence precede launch; advanced shared deployment remains G6 unless explicitly brought forward.

**Acceptance:** Cloud UI cannot claim direct USB discovery. Shiny process crash preserves capture/jobs; worker load does not starve configured recorder capacity. Local→shared backup/restore retains IDs, hashes and decisions. Participant tokens cannot read unrelated sessions or submit code.

**Now versus later:** Planning contract specified here. Threat/permission and load tests, clean-machine deployment and backup/restore drill on each supported topology. Implementation and validation remain future work.

**Evidence:** BIO-S09

### ARC-G07 · P1 · Plugin/runtime and schema upgrades need compatibility enforcement

**Brief requirement:** Open-source contributors must extend hardware, questionnaires and algorithms without changing old results.

**Baseline evidence:** R-ARCHITECTURE.md:409–433 and 580; B011, B018, B185–B188, B208. Process protocol and licences are defined, but upgrade negotiation and historical execution policy need acceptance tests.

**Implementation fix:** Handshake protocol/schema/plugin/method/model/environment versions independently; reject incompatible major versions before collection; test supported minor versions with fixtures. Keep exact weight/code licence profiles and old recipe references. Record migration adapters and retained-runtime/export policy.

**Acceptance:** Updating plugin or model creates a new derivative provenance chain; unsupported protocol fails before arm. A named old report remains interpretable/reproducible under published retention policy. Unlicensed model weights cannot enter redistributable release through an MIT wrapper.

**Now versus later:** Planning contract specified here. Contributor conformance matrix, schema migration/reproduction fixtures and model/SDK licence review; no inherited qualification after an update. Implementation and validation remain future work.

**Evidence:** Baseline contract audit; proposal rather than an externally observed product fact.

### ARC-G08 · P1 · Large-data UI queries need bounded rendering and event reconciliation

**Brief requirement:** Premium interface responsiveness must persist across many streams and months of studies.

**Baseline evidence:** R-ARCHITECTURE.md:90,359–360,505,611; B031, B035, B138. Bounded data and latency targets exist; query shape, authorization and incremental state feed remain unspecified.

**Implementation fix:** Require stream/time/channel/resolution query bounds and immutable multiresolution tiles; run raw exports as jobs. Use authorized event cursors plus full status reconciliation on missed updates. Keep UI cursor/selection local while authoritative current-result bindings come from server manifests.

**Acceptance:** 64-channel viewport and AOI/media cursor never load full study into Shiny memory. Overlarge request is rejected or becomes a job. Lost status events recover via cursor/status refresh; no fabricated completion percentages. Measure keyboard equivalence and existing p95 budgets.

**Now versus later:** Planning contract specified here. Published small/typical/stress corpus benchmarks on declared hardware; at-scale interaction/usability and per-study authorization tests. Implementation and validation remain future work.

**Evidence:** Baseline contract audit; proposal rather than an externally observed product fact.

## Concrete candidate method cards to finish in G0

These are implementation proposals, not universal scientific defaults. They deliberately choose or expose definitions currently deferred to implementation tickets. The scientific owner must freeze any still-unresolved numerical parameters before a card may publish an executable qualified study. A card with an unresolved threshold is `draft_specification`, never a silently runnable student default.

### Common static-image eye recipe

For the first paired-image recipe, standardise the proposed primary measure as `aoi-valid-gaze-time-share/1.0.0`: eligible valid gaze duration within the predeclared label AOI divided by eligible valid gaze duration during the declared exposure window. Store its percentage, numerator seconds, denominator seconds, scheduled/visible exposure seconds and coverage together. The signed paired B minus A contrast is in percentage points, with positive values indicating greater gaze share for B and A as the reference condition. This is the agreed planning definition requiring fixture and scientific qualification; it is not measured platform performance. It is sample-time gaze allocation, not fixation duration. Named fixation counts and durations remain separate secondary endpoints; they cannot silently replace the primary.

Define piecewise sample-interval integration, end-of-exposure clipping, maximum hold duration, gap handling and binocular validity/combination as explicit method parameters. One invalid eye, both invalid, valid off-screen coordinates and an absent AOI are different states. Decide whether AOI overlap permits multiple membership or resolves a predeclared priority; shares need not sum to one under multiple membership. A point on a boundary follows a documented inclusion rule. A non-visible target has no eligible exposure; it is not equivalent to a visible target that was never looked at.

Named fixation metrics are secondaries until their device-specific algorithm is qualified. Specify whether a fixation belongs by centroid, duration-overlap or another rule, and whether fixation onset before exposure is eligible. Count visits by explicit transitions/debounce and invalid-gap treatment. Time to first fixation includes observed time, event indicator and eligible exposure; no-event and invalid-data cases remain distinguishable. Aggregate each participant's declared B minus A difference; multi-item/independent-group designs use separate method cards. Report the tested sample, uncertainty and limitations in deterministic language, rather than calling longer looking greater liking.

### EEG first spectral recipe and optional ERP

Choose one named output family and a justified montage/reference for the flagship consumer protocol. The method card must supply actual acquisition units, channel types/locations, reference/ground, hardware filters, line-frequency context, rate and usable epoch criteria. Define the entire offline filter (type, band edges/transition width/order, phase, padding, edge exclusion) and any resampling/anti-aliasing. Never treat a live display filter as the saved scientific processing configuration.

Preserve bad-channel and bad-interval decisions and reference/rank changes. If ICA is used, specify what data train the decomposition, channel/rank compatibility, application data and exact rejected components; classifier scores are evidence, not automatic neurological truth. For spectral outputs freeze estimator, window/taper, overlap, detrending, frequency resolution, band limits, absolute versus relative power, log transform, reference band denominator and aggregation order. Known sine/noise fixtures can test numerical implementation; they cannot establish consumer meaning. A frontal asymmetry or engagement interpretation requires its own research/qualification card and cannot be inferred from simply offering band power.

ERP is a separate optional qualified recipe: measured event onset, channel/ROI, epoch/baseline, artifact policy, minimum trials, averaging and amplitude/latency estimator must be specified. Resting/long-window spectral qualification does not establish ERP timing validity.

### EDA first recipe

Declare conductance source type, site, units, acquisition rate, sensor/hardware-filter configuration and usable baseline/response context. Separate tonic level/change from phasic response features. The first method card must choose a pinned decomposition and detector, with absolute versus relative detection threshold unambiguous; a library's similarly named argument may have a different unit. Specify event latency/search window, amplitude reference, onset/peak/recovery definition, overlap policy and how nonresponse, edge truncation and artifact rejection affect denominators. A scalar zero is allowed only when the method's conditions for a valid nonresponse are met.

Keep passive exposure, question/joystick movement and recovery periods tagged. Rapid RT/AAT/BIAT trials cannot automatically provide independent EDA events; a longer interval contrast or qualified overlap model is a different recipe. If conductance has already been high-pass filtered by acquisition, do not reconstruct a purported tonic signal by relabelling. The R API owns method selection and result meaning even if a pinned Python worker implements the approved method.

### Qualification corpus and method card checklist

For each launch method store: question/estimand; analysis unit and direction; required capabilities; input schema; exact computation; all numerical parameters and units; eligibility and missingness; immutable masks/repair decisions; reference implementation/data; numerical tolerance and statistical interval coverage criteria; named rig/browser profiles; known unsupported tasks; deterministic explanation; license/consent/retention evidence; qualification date and reviewer. Separate simulator, hand-calculated, independent published and physical-rig datasets. Split tuning from final test before selecting thresholds. Record calibration failure and retained-data distribution, not only conditional accuracy among successful runs.

Physical timing trials include realistic full study duration, simultaneous full-rig capture and preview/CV/analysis load. Report biases, tails, drift and missing samples by source path. AOI validation includes downstream dwell/TTFF error and reviewer effort at matched scientific quality. Webcam validation includes calibration failure and valid observation coverage by named operating conditions. A held-out validation failure is a support limitation or a failed release gate, not a reason to redefine the outcome after seeing the result.

## Official provider evidence and design implications

All sources below were checked on 5 September 2026. Documentation screenshots demonstrate specific controls/representations, not current commercial product quality or complete UX coverage. Historical images are labelled accordingly.

| Source ID | Primary source | Relevant observation and implication |
|---|---|---|
| BIO-S01 | [LSL time synchronization](https://labstreaminglayer.readthedocs.io/info/time_synchronization.html) | Separate clock alignment from device/application delay. Our profile therefore retains physical latency evidence as well as clock anchors. |
| BIO-S02 | [EEGLAB filtering](https://eeglab.org/tutorials/05_Preprocess/Filtering.html) | Filtering interacts with artifacts and boundaries; a reproducible method needs precise filter and interval rules. |
| BIO-S03 | [EEGLAB ICA](https://eeglab.org/tutorials/06_RejectArtifacts/RunICA.html), [MNE ICA](https://mne.tools/stable/auto_tutorials/preprocessing/40_artifact_correction_ica.html) | ICA setup, component evidence and application are distinct operations; preserve all stages and the exact chosen implementation. |
| BIO-S04 | [NeuroKit EDA API](https://neuropsychology.github.io/NeuroKit/functions/eda.html) | APIs expose multiple decomposition/detection methods, different event/interval behavior and threshold semantics. Pin explicit choices; a convenience default is not the study's analysis plan. |
| BIO-S05 | [Pupil Core Capture documentation](https://docs.pupil-labs.com/core/software/pupil-capture/) | Calibration and validation are separate controls; calibration coverage and quality are context-dependent. Our readiness should express method-specific evidence. |
| BIO-S06 | [Browser video frame callback API](https://developer.mozilla.org/en-US/docs/Web/API/HTMLVideoElement/requestVideoFrameCallback) | Available media/presentation metadata is not universal physical sensor exposure timing. Preserve the distinction in webcam provenance. |
| BIO-S07 | [IndexedDB API](https://developer.mozilla.org/en-US/docs/Web/API/IndexedDB_API) | Browser transactional storage supports journaling; persistence/quota behavior still requires an explicit recovery contract and supported-environment testing. |
| BIO-S08 | [Shiny nonblocking operations](https://shiny.posit.co/r/articles/improve/nonblocking/) | Slow work requires actual delegation; session responsiveness is distinct from a durable job service. |
| BIO-S09 | [Plumber security](https://www.rplumber.io/articles/security.html) | API hosting/input/resource boundaries require application controls; a framework selection does not implement authorization or safe uploads. |

[EEGLAB automated rejection](https://eeglab.org/tutorials/06_RejectArtifacts/cleanrawdata.html) distinguishes channel/interval rejection from ASR correction, and identifies dependence on channel-location information. The review uses that as evidence to expose the exact artifact disposition while keeping qualified automation as the default. It does not recommend copying EEGLAB's displayed thresholds into every study.

[BrainVision Recorder tips](https://pressrelease.brainproducts.com/recorder-tips/) was originally published 9 August 2017 according to its page metadata; the assets were rehosted in 2022 and the depicted build is not verified. The captured impedance, workspace, channel-position, annotation and file-naming controls are historical UX evidence. Their value is concrete: preserve physical channel identity, disclose actual acquisition configuration, keep operator events and make saving understandable. They are not proof that the current Recorder UI is identical.

[LabRecorder's official repository](https://github.com/labstreaminglayer/App-LabRecorder) provides its stream-selection/recording UI and documents required-stream configuration, ambiguous same-name selection and recovery constraints. Our single-action collection flow must retain those controls in its underlying contract while reducing repetitive operator work.

BIOPAC's official EDA product/manual URLs were checked but returned access errors for full direct retrieval. A putative OpenSignals PDF URL returned HTML rather than a PDF. No screenshot or product claim is presented as verified from those failed downloads. This evidence set uses the successfully retrieved official provider documentation; broader provider coverage is an explicit remaining research opportunity, not an inflated screenshot count.

## Screenshot evidence inventory

Ten actual official documentation UI stills were downloaded as static images, visually inspected, and retained under `evidence/v2-biovital/`. No video, animated GIF or full manual is retained in the deliverable set. Two Pupil documentation images were rejected after inspection because they were schematic representations rather than actual captured controls. Their source documentation remains useful scientific evidence. All kept stills have portable path, source page/image URL, source-version limitation, content hash and gap linkage in `evidence/v2-biovital/manifest.json`.

| Evidence ID | Captured state | Why it matters |
|---|---|---|
| BIO-UI01 | EEGLAB automated-cleaning settings | Qualified defaults need disclosed exact operations and parameter provenance. |
| BIO-UI02 | EEGLAB rejected signal intervals/channels | Show what changed and what usable data remain. |
| BIO-UI03 | EEGLAB ICA component properties/review | Keep supporting evidence and a targeted disposition. |
| BIO-UI04 | EEGLAB FIR filter dialog | Distinguish precise scientific filter semantics from visual smoothing. |
| BIO-UI05 | BrainVision impedance and physical channel labels | Guided fit checks retain sensor/channel identity. |
| BIO-UI06 | BrainVision operator annotation | Operator events belong on the common timeline. |
| BIO-UI07 | BrainVision workspace acquisition summary | Requested versus actual acquisition settings remain inspectable. |
| BIO-UI08 | BrainVision resulting recording filename | A novice needs clear save destination and safe run identity. |
| BIO-UI09 | BrainVision channel/electrode-position mapping | Channel labels, physical inputs and reference cannot be guessed. |
| BIO-UI10 | LSL LabRecorder stream selection/run identity | Required-stream readiness and recording state must be explicit beneath low-click orchestration. |

## Integration and release impact

The architecture contract resolves the proposed behavior of frontend/backend boundaries, state transitions and failure handling at planning level. The method-card proposals resolve names/definitions enough to drive implementation work, while the deliberately unresolved numerical method parameters remain qualification dependencies. The structured gap file and 19 proposed backlog rows make these follow-through obligations machine-readable; they do not mark app development complete.

Keep common definitions and simulator recovery in G0–G2; prove physical full-rig timing and recovery in G3; qualify specific signal/behavioural/webcam methods and AOI automation at G4; publish the supported matrix at G5. Keep full IAT at its existing C:G6 ticket, resolving the conflicting G2 phrase (IM-G09). ECG/PPG/HRV, respiration and EMG remain named later extension packs, with EMG already represented by B196. This preserves the ambitious platform without turning every future sensor into a hidden launch dependency.
