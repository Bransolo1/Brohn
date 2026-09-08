# Product experience and delivery roadmap

**Version 0.2 revision:** [The UX team review](UX-TEAM-REVIEW.md) defines the action, saved state, recovery and verification for sixteen gaps. [The application contract](ARCHITECTURE-CONTRACT.md) fixes the corresponding backend behavior. The revised interactive concept demonstrates a clean sample route, dependent design/liking choices, stale analysis, required AOI review and reversible acceptance. Its values are illustrative; it is not a research runner.

The five-stage navigation remains Plan → Questions → Collect → Review → Results. A clean prepared sample reaches its explained result without compulsory exception review. Review approval is bound to the exact artifact and policy revision; changing a dependent input makes results stale and stops final publication. Sample, preview, pilot and live runs retain distinct provenance. Study completion is separate from the end of one participant. Shared reports are frozen snapshots with explicit access grants.

Planning date: 5 September 2026. This is a proposed product design and delivery model, not a description of software already built. Competitor evidence belongs in the companion research atlas; the interactions below are original recommendations informed by the user's goal.

Packaged companions: `R-ARCHITECTURE.md` for technical contracts; `QUESTIONNAIRE-BUILDER.md` for question types and flow; `WEBCAM-EMOTION-ATTENTION.md` for camera-based methods; `IMPLEMENTATION-BACKLOG.csv` for candidate work items; and `evidence/manifest.json` for visual-evidence provenance. This document is packaged as `UX-AND-ROADMAP.md`.

Build an open research workbench that takes a question from study design to a reproducible result, makes automated AOIs a first-class workflow, and lets a first-time researcher complete the same pipeline an expert can inspect, modify, and rerun in R.

## 1. The product to build

The emotional promise is **“I can run a rigorous study without becoming a systems integrator.”** The primary operator is an **undergraduate psychology researcher who should be able to finish a first eye-tracking study quickly**. Commercial consumer-research and UX teams remain the deployment and collaboration context. Premium should mean clarity, composure, dependable recovery, fast feedback, and beautiful evidence. It should not mean hiding decisions behind an inscrutable score.

The strategic wedge is a complete, template-driven loop: choose a research question; adapt a method; validate its execution; collect or import observations; automate preparation and AOIs; review only exceptions; compare results; export an executable research bundle. Automated end-to-end analysis is a primary product requirement: common recipes own the quality checks, AOI defaults, metrics, participant-level aggregation, appropriate comparison and readable report. A student should not have to assemble this pipeline. The launch contract also includes a full flagship study combining **eye tracking, EEG, EDA, reaction times, push/pull approach–avoidance tasks, an explicitly specified abbreviated IAT and an integrated questionnaire builder**. All modalities and explicit responses enter the canonical schema and fixture programme from the first phase. A simple eye-study experience is the default front door into this holistic platform, not a reduction of the platform's scope.

The flagship demonstration is a consumer concept/creative study: show counterbalanced visual concepts while recording eye/EEG/EDA; run a compatible, separate block of push/pull trials and abbreviated association trials; align events; review signal and AOI quality; inspect modality-specific results and condition comparisons; generate one evidence-linked report. A recipe distinguishes compatible simultaneous acquisition from sequential tasks, so combining methods does not imply every response is measured at the exact same moment. There is no unvalidated all-in-one “consumer truth” score.

Existing iMotions automation, Auto AOI, R integration and segmentation are competitor capabilities to benchmark, not inventions to claim here. Differentiation must be demonstrated by the connected experience, method agility, open reproducibility, lower review effort at equivalent quality, and a smoother commercial workflow. AOI automation is a crucial part of that system, not a unique claim by itself.

The reinforcing system is:

1. Versioned study recipes connect tasks, devices, quality rules, AOIs, metrics, models, and reporting.
2. Every automated step creates evidence of what changed and which decisions remain.
3. Researchers correct exceptions, with corrections retained as reusable rules within the appropriate project scope.
4. Reproducible example studies and openly documented benchmarks help contributors improve adapters, AOI proposals, and methods.
5. A discoverable extension library lets independent research teams contribute recipes and adapters against the same contracts.

Competitors can copy an attractive builder or a summary card quickly. A coherent library of tested recipes, independently verified adapter capabilities, realistic regression fixtures, transparent correction histories, and interoperable research exports becomes harder to reproduce over time. Open source makes this a community quality advantage rather than a proprietary-data moat.

**Claim ladder:** on launch, describe measured workflow behaviour: imports supported formats, preserves provenance, implements named algorithms, reproduces results. After prototypes, claim observed improvements in completion time or usability only with the study conditions reported. Claims of reliable decision improvement, robust measurement across devices, or improved research outcomes require appropriate independent and longitudinal evidence. “Market-leading” is the design objective, not a claim established by this plan.

## 2. Design rules and information architecture

### The default guided experience: five stages with very few required decisions

Show **Plan → Questions → Collect → Review → Results**. Plan encompasses the recipe, materials, conditions, predeclared semantic AOIs and primary outcome; Questions contains the linked questionnaire. The student adapts only the required design choices and resolves actual exceptions. Prepared content does not require a confirmation on every page. Participant allocation, preprocessing, standard QC, named metric definitions, analysis and report are generated from the chosen recipe. Default choices remain inspectable and editable in the distinct advanced workbench. No AI chat or external LLM is required to complete a study.

Proposed target for the **built-in paired-image sample**: an explained reproducible report in **10 minutes or less**, **0 scientific configuration decisions** and at most **5 total activations** from the welcome screen, counting clicks, taps or equivalent keyboard activations. Assets, sample recordings and AOIs are preloaded; processing runs locally. No compulsory audit-sampling clicks are added to this clean example. This is an unvalidated usability target to measure in prototypes; it does not include installation, recruitment, fitting sensors or real participant collection.

For a common real study with prepared stimulus files, target **at most 4 substantive design decisions and 12 total activations, including file-chooser actions, selections and confirmations**. The decisions cover design, materials/conditions, semantic targets/primary outcome and collection plan. Target **at most 4 software activations to start another participant on a ready rig**, with physical fitting, consent and calibration duration reported separately. Finalizing collection triggers the qualified report with **0 required analysis-configuration decisions**. Track typing, hardware actions, collection duration and exception/audit review separately. Report median and spread for novice and experienced users, plus completion and comprehension. Never lower a click count by hiding an unresolved scientific choice. A visible “Show advanced workbench” switch reveals the richer navigation without creating a separate project format.

### Interaction rules

- Start with the question and intended comparison. Offer methods with prerequisites and expected outputs. Do not imply a question can automatically establish a latent psychological construct.
- Show one primary next action. Keep a contextual right panel for explanation, prerequisites, and the evidence behind suggestions.
- Keep object identity stable: a stimulus, AOI, event, participant session, metric, and analysis revision should have the same name and ID wherever they appear.
- Preserve progressive disclosure without separating novice and expert data models. A simple control edits the same versioned specification that an expert sees in a diff.
- Always show whether a number is raw, processed, descriptive, inferential, or a model estimate. Never allow a marketing label to silently replace its operational definition.
- Make running work visible but unobtrusive. Progress reports completed units and phase, and explains indeterminate stages rather than inventing percentages.
- Make recovery local: an invalid import row, rejected AOI proposal, failed batch, or disconnected device should not destroy unrelated work.
- Make durable actions explicit: collection uses a frozen study revision; analysis uses a frozen configuration; changing a template produces a new revision with affected outputs marked stale.

### Navigation model

**Guided navigation:** Home, My studies, Help; the selected study uses the five steps above. Devices appear only when the chosen collection route needs them. A small task tray shows background progress and exceptions. The screen catalogue below describes underlying surfaces rather than navigation items exposed to a novice.

**Advanced global navigation:** Workspaces, Studies, Recipe library, Data library, Devices, Runs, Extensions, Help. Workspace settings contain access, local storage, remote endpoints, retention configuration, and contributor information.

**Advanced study navigation:** Overview → Design → Participants → Collect → Prepare → AOIs → Analyze → Report. This describes a logical journey, not a rigid wizard: existing-data studies can enter at Prepare; experts can move between stages; prerequisites are contextual. The guided path automatically executes these operations and surfaces only relevant choices and exceptions.

**Persistent shell:** workspace/study breadcrumb; global search/command menu; current revision; save status; job indicator; contextual help. A bottom tray exposes active jobs, device health, and recoverable errors without covering keyboard focus. The right inspector opens only when useful. Destructive bulk actions use a preview of affected objects.

**Object model visible to users:** Workspace → Study → frozen Study revision → Participant/session → Streams/events/stimuli → Processing run → AOI revision → Analysis run → Report revision. Data files remain separate from the study so a file can be attached without being duplicated; rights and consent scope control reuse.

### Visual system

A calm light theme is the default analysis workspace; a restrained dark theme is useful for lab observation and long signal-review sessions. Use a neutral canvas, high-contrast typography, sparse colour, generous spacing, a predictable type scale, and thin structural separators. Reserve semantic colour for state; signals and AOI categories use colour plus labels and patterns. Scientific plots use consistent units, legible axes, explicit denominators, and accessible palettes. A density switch serves experts without shrinking essential targets. Key screens should work at 1280×800 and 1920×1080; mobile supports study status and participant tasks that are explicitly qualified, not the full AOI editor.

## 3. Screen blueprint: 25 concrete surfaces

Each screen requires designs for loading, first-use, populated, permission-limited, empty-result, recoverable failure, stale revision, and completed states where relevant. “Empty” must tell users what makes this screen useful, offer sample data, and preserve a route forward.

| # | Screen and user job | Main composition and interactions | Required distinctive states |
|---|---|---|---|
| 01 | Welcome / first value | Two choices: open the prepared sample or create/import a study. The sample uses the same Plan → Questions → Collect → Review → Results stages, with completed content and no required scientific settings or confirmation on every page. | No R installation, dependencies installing, offline ready, sample reset, successful first report. |
| 02 | Workspace home | Recently active studies, work that needs attention, queued runs, storage/device summary; create study is primary. Resume opens the actual interrupted step. | No studies; all clear; one failed run; offline; permission-limited studies. |
| 03 | Research question / recipe finder | Question field plus method cards for attention, association, response inhibition, priming, and custom protocols. Cards show required inputs, execution setting, outputs, maturity, and exemplar. | No compatible hardware; import-supported recipe; timing qualification required; unsupported combination. |
| 04 | Study overview | One-page study brief, stage progress, next action, frozen/current revision, participant counts by status, latest quality summary. | Draft; collecting; analysis available; protocol changed; archived with reproducible bundle. |
| 05 | Recipe setup | Guided method-specific forms; live protocol summary; rationale beside defaults; explicit comparison and analysis unit. “Advanced” opens the exact configuration. | Missing requirement; recommended vs custom setting; invalid parameter; example-loaded. |
| 06 | Study flow builder | Central blocks for instructions, calibration, trials, breaks, questions, triggers; left block library; right properties. Keyboard-add and reorder are first-class. | Branch dead end; unbalanced condition; missing stimulus; too-long session; frozen revision. |
| 07 | Stimulus library / assignment | Asset grid with dimensions, duration, locale, condition and rights fields; batch import and table editing; preview selected trial. | Duplicate asset; failed transcode; missing font; changed asset with affected trials. |
| 08 | Variables, randomization and allocation | Plain-language factor/level editor plus generated allocation preview. Seed, counterbalancing, constraints and per-participant schedules are inspectable. | Impossible constraints; empty cell; reserved participant; locked allocation after launch. |
| 09 | Pilot and launch readiness | Participant-screen preview; automated protocol checks; simulated run; real pilot records; timing/device compatibility cards. Launch produces a frozen manifest. | Passed; proceed-with-documented-limitation; must-fix; stale pilot after relevant edit. |
| 10 | Participants / sessions | Pseudonymous table; eligibility, scheduled/completed status, valid-data coverage; separate identity mapping if configured. Bulk operations preview impact. | Partial session; withdrawal request; duplicate identifier; reconnect awaiting decision. |
| 11 | Device setup / calibration | Capability cards, clocks/sample rates, required channels, live signal preview, calibration route. Show supported rather than merely detected features. | Simulator; connected; unsupported firmware; missing channel; calibration poor; drift. |
| 12 | Participant runner | Distraction-free, preloaded execution; clear instructions, practice, accessible response mapping where the method permits; truthful completion state. | Practice retry; asset failure; focus loss; connection interruption; interrupted timed trial; completion. |
| 13 | Collection control room | Session list and selected participant timeline; device health; annotations; planned vs observed event timing; pause/stop controls with consequences. | Stream drop; trigger mismatch; low signal; operator annotation; safe session finish. |
| 14 | Import mapping and validation | Drag files/folders; auto-detected format; editable channel/unit/time mappings; row/file-level preview; source metadata retained. | Mixed units; ambiguous clock; missing columns; non-monotonic timestamps; duplicate import. |
| 15 | Synchronized session explorer | Shared time cursor across stimulus replay, gaze, EDA, ECG/PPG, events and response trials. Independent stream validity masks remain visible. | Estimated alignment; unavailable channel; dropped interval; segment comparison; annotation conflict. |
| 16 | Preparation / processing recipe | A readable pipeline with defaults, method version, affected channels, expected output; preview before/after on selected intervals. | Not run; cached; running; partial failure; parameter change invalidating descendants. |
| 17 | Quality and exception inbox | Ranked review queue grouped by root cause; evidence preview; accept, revise, exclude, retry or defer; show downstream impact. | No exceptions; unreviewed batch; disputed rule; blocked report; ignored-with-reason. |
| 18 | AOI workbench | Large stimulus canvas, geometry/semantic tree, timeline, object list, proposal/approved layers, side-by-side QA examples. | Static image; DOM element; video track; occluded; missing proposal; changed stimulus; stale gaze mapping. |
| 19 | AOI batch review | Contact sheet ranked by uncertainty and coverage; keyboard approval; representative and random QA samples; correction propagation preview. | Drift cluster; identity swap; bulk action limited by policy; audit sample failed. |
| 20 | Analysis plan and comparison | Prespecified questions, contrasts, analysis unit, filters and exclusion policy; descriptive/inferential tabs; method cards with assumptions. | Insufficient data; singular model; not estimable; post hoc modification; sensitivity comparison. |
| 21 | Evidence explorer | Linked plots, participant/trial table, AOI metrics, uncertainty; every card can open its derivation, exclusions, configuration and input revision. | Zero valid observations; small sample; missing condition; disagreement between modalities; multiple-comparison scope. |
| 22 | Report composer / export | Editable narrative linked to frozen result cards; methods and appendix auto-populate; export previews; reader view. | Stale chart; unsupported claim text; partial data; failed render; publication bundle validated. |
| 23 | Run history / reproducibility | Runs as a dependency graph or list; exact configuration diff; environment; cached artefacts; resume/retry; one-click reproduce. | Environment unavailable; retired extension; hash mismatch; interrupted run; reproducibility verified. |
| 24 | Recipe / extension studio | Manifest editor, schema checks, example fixture, documentation preview, capability claims and local installation. Contribution wizard creates a reviewable package. | Untrusted extension; API mismatch; failing fixture; optional SDK absent; compatible update available. |
| 25 | Questionnaire editor / logic debugger | Form preview, question/type library, wording/options/validation inspector, explicit scale coding; flow tree for branches, piping, randomization and checkpoints; response dictionary generated alongside. | Invalid pipe; unreachable question; randomizer imbalance; unsupported type; mobile matrix alternative; missing/not-shown/declined response; changed published question. |

## 4. Four end-to-end journeys

### A. First-time researcher: compare two package designs

Open the prepared sample workspace and its report, with an optional interactive explanation. The sample uses one A image and one B image viewed by the same participants. To create a real study from it, add the two images, name the conditions and confirm the intended semantic targets/primary outcome and collection plan. The recipe explains that gaze indicates visual attention under the study conditions; liking is a separate explicit measure. The counterbalanced schedule, quality rules, metric definitions and paired analysis are prepared. Generate AOI geometry from stimulus content before capture where possible, declare semantics before collection and make later corrections without consulting condition outcomes. Run the required readiness/calibration procedure and freeze the study. Import supported eye-tracking exports or collect through a qualified adapter. Preparation, gaze-to-AOI mapping and prespecified analysis run automatically, routing actual exceptions to review. Audit sampling follows a separate qualified lab/course policy; the clean beginner sample adds no compulsory audit steps. The report links each statement to evidence and explains the conclusion. Multiple stimulus items per condition or separate participant groups use a different qualified recipe whose model respects that design. Forking preserves the original study and comparability metadata.

Proposed usability target: at least 80% of a small formative cohort completes the sample without live support, with no silent scientific configuration errors. This is an initial design target, not a market benchmark or statistically conclusive claim. Then test a realistic novice cohort and report uncertainty.

### B. Agile implicit study: concept–attribute associations

Select an IAT recipe, review the construct and relative comparison, assign stimulus sets, preview category mappings and block sequence, and inspect the named scoring implementation. Automated checks identify overlapping stimulus categories, incomplete sets, unbalanced allocation and missing exclusions. Practice records are separate from scored records. Pilots reveal instruction confusion and technical timing issues before launch. The run freezes blocks, mappings, scoring rule and exclusions. The report describes relative response patterns and their uncertainty without converting a score into an individual's hidden truth. Forking allows stimuli or blocks to change, but highlights when those changes limit cross-study comparison.

The initial scoring implementation should be independently checked against published examples/reference code, not merely tested against itself. Greenwald, Nosek and Banaji's original improved-scoring paper is the source to specify the implementation variant. [Original paper](https://banaji.sites.fas.harvard.edu/research/publications/articles/2003_Greenwald_JPSP.pdf)

### C. Lab operator: eye tracking plus autonomic signals

Open today's session and select a qualified capability profile. Calibration and a brief signal test verify the actual sensor channels. The control room shows collection health independently of eventual scientific validity. During a dropout, local buffering continues where the adapter supports it, and the stream gap becomes an event rather than a fabricated continuous trace. The operator can document a disturbance without changing raw data. The synchronization explorer distinguishes measured offset, inferred alignment and uncertain intervals. Downstream metrics use modality-specific validity masks and show the sample loss introduced by each rule.

### D. Experienced researcher: repair video AOIs and rerun

Import a video study, run scene segmentation and object proposals, and review tracks in ranked batches. Correct a drifting logo track with keyframes; preview propagation across affected frames; mark occlusion, reappearance and identity separately. Approve a revision, then compute gaze-to-AOI mapping. In a later sensitivity analysis, change the allowed padding and dwell rule; the pipeline reruns only dependent steps. Compare both results, preserve the original analysis, and export a bundle containing the precise AOI revision, masks, stimulus transform, model metadata and derivation code.

## 5. AOI workbench specification

AOIs are research objects, not just painted polygons. Every AOI has an immutable ID; human-readable name; semantic category; source stimulus revision; geometry/coordinate system; temporal validity; creation method; author/reviewer; version; and uncertainty/review state. Instances may belong to one semantic category across stimuli without being assumed geometrically equivalent.

### Creation paths

- **Static:** rectangle, ellipse and polygon; keyboard coordinate editing; snapping; duplication; proportion/pixel views; imported geometry. The original stimulus dimensions and displayed transform are preserved.
- **DOM/web:** a captured element, selector and bounding box tied to a specific page/view state; viewport, scroll and responsive breakpoint metadata; fallback when the element is absent. Live page changes must not silently redefine an existing AOI.
- **Template propagation:** copy an approved region to stimuli with the same layout; preview the transform and exceptions before applying.
- **Semantic proposal:** suggest candidate objects, OCR text and categories. Show proposal origin/model version and review status. An unknown model confidence is not presented as a calibrated probability.
- **Video:** keyframe geometry; interpolation or tracking between frames; scene boundaries; object identity; occlusion; confidence intervals or scores where available. Reappearance creates an explicit identity decision.
- **World/3D, later:** calibrated surface/object registration and coordinate transforms; only available when the acquisition and mapping contract is qualified.

### Precision controls that affect results

AOI hierarchy and overlap policies must be explicit: exclusive priority, multiple membership, or parent/child aggregation. Padding in pixels or visual angle, temporal inclusion, interpolation, gaze coordinate transforms, invalid samples, off-screen gaze, visit/dwell definitions, binocular combination, and fixation mapping belong to versioned metric configuration. A changed stimulus crop must invalidate affected mapping. A hidden or fully occluded object must not attract valid hits through stale geometry. Heatmap salience must not be allowed to masquerade as a measured AOI definition.

### Review system

Separate “proposed,” “approved,” “rejected,” “needs review,” “not visible,” and “not applicable.” The review queue prioritizes low-confidence segments, discontinuities, overlap conflicts, unexplained object motion, scene cuts, and missing expected categories. Confidence-driven sampling is supplemented by stratified/random audits so a confidently wrong model is still discoverable. An expert may accept a batch only under a documented, benchmarked policy; initial video automation produces proposals for review. A correction can propagate only after showing its affected range and a before/after preview. Changes are undoable and attributable.

### Benchmark gate

Before metrics from automatic AOIs can be promoted without full manual approval, evaluate an independently annotated, held-out corpus stratified by relevant use cases: small text, products, faces, occlusion, motion blur, zoom, scene changes and layout variants. Report geometric agreement, temporal visibility, identity switches, category errors and disagreement in downstream gaze metrics. Thresholds are set per use case from the tolerable research error; no universal confidence or intersection-over-union threshold is promised. Compare end-to-end review time and corrected metric quality against the existing manual process. Keep a stable regression set separate from development feedback. Store permissioned evaluation material or synthetic fixtures; do not quietly train on participant recordings.

## 6. Automation as an inspectable product

The central interaction is **“Run the approved recipe; bring me the exceptions.”** A study recipe declares its input requirements, transformations, parameters, quality rules, review gates, estimators, reporting rules and provenance requirements. The same manifest drives the UI, batch executor and R reproduction command.

| Automation level | Product promise | Appropriate initial examples |
|---|---|---|
| Assist | Propose; the researcher decides. | AOI geometry/categories, channel mappings, candidate report structure. |
| Execute approved rule | Run an explicit versioned instruction and record it. | Unit conversion, deterministic IAT scoring, declared exclusions, report rendering. |
| Route exceptions | Continue independent work, isolate cases requiring attention. | Missing channels, low-quality segments, model failure, AOI ambiguity. |
| Policy-based approval | Accept within a qualified context, audit a sample, escalate drift. | Repeated static-layout AOIs after use-case validation; later bounded video cases. |

Every automated decision card contains: action; reason; inputs/version; configured rule or model; affected items; expected downstream impact; uncertainty/limits; preview; undo or rerun; and activity history. The system distinguishes “completed,” “scientifically reviewable” and “approved for this report.”

### Exception model

Severity is driven by consequence: **blocks this calculation**, **review required**, or **informational**. Each exception has an object and scope, evidence, remedy, dependencies, and a durable status. Group 2,000 identical missing-channel errors as one root cause with affected sessions. Never group unrelated causes merely to make the inbox look smaller.

Resolve actions are specific: fix the mapping; select the correct clock; revise AOI; exclude a segment/participant with reason; choose a documented analysis alternative; rerun the affected node; or accept a bounded limitation. “Ignore all” should not erase provenance. An exception can be waived for one report without changing the global method.

### Recovery contract

- Interrupted imports resume from verified completed files; duplicate content is detected.
- Long jobs checkpoint suitable intermediate outputs and recover idempotently; retry never duplicates a participant, event or export.
- Raw data is immutable; corrections create revisions or derived layers.
- Participant execution buffers where supported. A timed trial interrupted by tab focus or connectivity is flagged according to the protocol; the UI cannot promise to resume it without consequences.
- Disconnection and timing degradation are visible in results, not just collection logs.
- A stale output offers “see what changed” and “rerun affected steps.” A failed report does not require repeating processing.
- Unavailable extensions identify the missing compatible version and allow export of recoverable data.

Browser execution is not a substitute for timing qualification. jsPsych's own documentation distinguishes display timing from response-time measurement and warns that device/browser variation matters. Accordingly, define timing requirements per paradigm, preserve observed execution metadata, and use hardware validation for sensitive protocols. [jsPsych timing documentation](https://www.jspsych.org/latest/overview/timing-accuracy/)

## 7. Recipe portfolio and graduation path

### Questionnaire builder: a core platform system

Design for Qualtrics-class authoring quality and a progressively expanding feature set. The launch should support a declared, tested type set: single-choice, multiple-choice, short/long text, numeric entry, labelled Likert ratings, accessible slider and a responsive matrix variant with equivalent keyboard/list controls. Start guided eye-study recipes with a ready-to-use explicit-liking item and optional comprehension/task questions; students can accept wording and coding defaults without constructing a survey from scratch.

The question schema includes stable question/option IDs, displayed wording and option order, labels and stored values, validation, missing/not-shown/declined distinctions, language, displayed revision, parent stimulus/condition/session, and observed presentation/response events. Keep original responses and versioned corrections separate. Generated data dictionaries must explain reverse scoring and derived scales; a composite score requires an explicit versioned rule rather than being guessed from question titles.

Flow supports blocks, display/skip/branch logic, bounded loops where later qualified, piped text, embedded variables, randomization and allocation. A logic linter checks unreachable paths, circular dependencies, invalid references, impossible validation, hidden-required questions and incompatible randomizers. A debugger lets researchers run a chosen path, inspect variables and see why a branch fired. Accessibility includes labelled controls, keyboard interaction, readable validation, correct focus after branching, small-screen matrix alternatives and no mandatory drag ranking without an equivalent control.

Freezing a study freezes question wording, option coding and logic. Preview uses the actual runtime, including mobile and keyboard paths. Checkpoints retain progress while recording whether a timed block was interrupted. Export includes the questionnaire specification, response dictionary, applied logic/allocation and analysis rules. Public examples use original or permissioned wording.

The launch combined report can compare explicit liking with the prespecified attention, EEG, EDA and behavioural outcomes while preserving participant/stimulus linkage. It distinguishes descriptive agreement, correlation and a properly specified repeated-measures model; an association is not labelled causal or presented as evidence that one sensor reveals the respondent's “real” answer. Missing modalities do not silently remove otherwise usable questionnaire responses. More advanced question types, panel operations, quotas, multilingual tools and collaborative workflows grow through tested method/UX packs rather than an immediate claim of full Qualtrics parity.

### Common eye-tracking recipes: automatic analysis is included

These are recipe specifications to validate, not claims that one default fits every experiment. Each recipe defines its primary question, analysis unit, missingness treatment, exclusion policy and uncertainty method before collection; an advanced change creates a new revision.

| Common study | Few researcher decisions | Automatically executed pipeline | Default result and scientific handling |
|---|---|---|---|
| Paired static-image A/B viewing | One image for A and one for B viewed by the same participants; labels; predeclared semantic AOIs and primary question. | Counterbalance → qualified collection/import → validity and fixation recipe → outcome-blind geometry review where needed → gaze mapping → per-participant metrics → prespecified paired contrast → report. | Show participant-level paired difference and interval. Multiple stimulus items or independent groups require a separately qualified recipe/model; no fixation is treated as an independent participant. |
| Video-ad comparison / moment review | Videos; condition labels; event windows; primary comparison. | Media-clock alignment → validity masks → temporal AOI proposals/review → event-window features → participant-level summaries → paired or independent analysis according to assignment → report. | Present exposure-adjusted denominators and uncertainty; distinguish exploratory moment scanning from prespecified contrasts; account for multiplicity where appropriate. |
| Visual search / find a target | Target; distractors; task completion response; target-present/absent design. | Allocation → response and gaze event capture → target AOI → gaze validity → target discovery and task success → participant-aware comparison → report. | Report success and search latency together. No-lookers are not silently dropped from time-to-first-fixation: retain right-censoring at the valid observation window for a suitable survival analysis, and distinguish tracking loss from known non-looking. |
| Reading / information finding | Text/assets; question/task; word/line/region grouping; primary comparison. | Record font/layout/viewport → DOM/text-region or reviewed OCR AOIs → gaze quality and mapping → first-pass/total-time/regression definitions → participant/item-aware analysis → report. | Word/item and participant dependencies matter; use the declared aggregation or qualified mixed model. Include comprehension accuracy when collected; no automatic inference that longer dwell means greater comprehension. |

For TTFF, “never fixated while validly observed” and “not observable because gaze data was missing” are different states. Recipes show the eligible window, fixation event definition, event indicator and censoring reason; they must not replace non-lookers with zero or compute a misleading average only among lookers without labelling that estimand. Guided reports show simple language such as “among participants with usable viewing data,” with counts and assumptions one action away.

Automation completion means a generated analysis plan, transformations, comparison, plots, plain-language description, methods appendix and reproducible bundle—not merely exporting cleaned CSVs. Rules-based narrative templates are sufficient initially; optional generative text cannot change results, hide exclusions or make stronger claims.

### Launch vertical slices: every core modality reaches the commercial result

| Slice | Foundation / alpha work | Full launch workflow | Dependency and acceptance gate |
|---|---|---|---|
| Eye tracking | Source clocks, gaze validity, stimulus transform and eye export import; fixation/event primitives; static AOI lifecycle. | Calibrate → capture on named tracker → synchronize → review quality → approve AOIs → attention metrics → traceable report. | Hardware accuracy/precision and timestamp qualification; coordinate-transform and metric reference fixtures. |
| EEG | Continuous channels, montage/reference, units, sampling and events; import; versioned filtering and epoching; bad-channel/segment review; first named spectral/ERP outputs appropriate to recipe. | Setup/contact check → live channel health → trigger validation → capture → reference/reject/prepare → condition analysis → report. | Named amplifier/SDK/firmware/OS qualification; independent pipeline output agreement; protocol-specific epoch and event timing requirements. |
| EDA | Conductance units, clock, sensor placement metadata; import; artefact/flatline rules; baseline and tonic/phasic pipeline specification. | Signal check → capture → segment/baseline → review artefacts → named features/condition comparison → report. | Sensor/adapter qualification; known/reference signals and artefact handling; no implied universal arousal interpretation. |
| Reaction time | Planned/observed events; stimulus onset and response timestamps; response mapping, correctness, focus and input metadata. | Practice → qualified execution → valid-trial review → method-specific trimming/exclusion → comparison and uncertainty. | Timing harness and execution matrix; trial handling reviewed against protocol; excluded trials visible. |
| Push/pull AAT | Exact task/input contract, direction/movement onset/completion definitions, counterbalancing, practice and scoring fixture. | Input calibration → practice → compatible stimuli/response task → RT/error QC → named approach/avoidance contrast. | Separate joystick/keyboard/touch/movement qualification. Physical push/pull and arbitrary key surrogates are not silently treated as the same paradigm. |
| Abbreviated IAT | Initial proposed implementation is the **Brief IAT (BIAT)** with a documented focal-category design and scoring rule; a user-requested custom shortened IAT receives its own recipe identity. | Category and stimulus setup → focal mapping and practice → counterbalanced run → protocol-specific scoring and exclusions → relative association evidence. | Independent BIAT scoring fixtures plus protocol/input timing pilot; each further abbreviation becomes a separately reviewed variant. |
| Combined flagship | Shared study/session/event graph and modality-specific validity masks; compatible collection blocks plus sequential behavioural blocks. | One design and control room → one exception workflow → linked results by condition/AOI/event → one reproducible evidence-linked report. | Full-rig stress/pilot study; planned event linkage verified; missingness per modality explicit; no unjustified score fusion or causal narrative. |
| Questionnaire / explicit liking | Stable response dictionary, declared question types, flow/branch/piping contracts, first liking scale and rule-based scoring fixture. | Build or accept template → lint and debug → participant response → coded/quality-checked data → linked explicit/biovital analysis → report. | Every launch type and logic combination passes runtime/accessibility fixtures; wording/coding/logic revision retained; integrated analysis respects participant/stimulus dependencies. |

BIAT is a specific procedure, not just fewer conventional IAT trials. Specify its initial implementation against Sriram and Greenwald's method and the later dedicated scoring recommendations; treat further shortening as a new, instrumented recipe. [Original BIAT paper](https://faculty.washington.edu/agg/pdf/Sriram%26Greenwald.BIAT.2009.pdf), [BIAT scoring research](https://faculty.washington.edu/agg/pdf/Nosek%26al.BIAT%20scoring%20algorith.PLoS%20ONE.2014.pdf)

Push/pull methods also require explicit operational definitions: a published mobile AAT records movement through device sensors and separates its implementation from the joystick comparison. The platform should preserve these input and timing distinctions rather than claiming equivalence from a common screen. [Original mobile AAT research](https://link.springer.com/article/10.3758/s13428-020-01379-3)

| Recipe family | Initial product stage | Complete recipe must contain | Graduation requirement |
|---|---|---|---|
| Static visual attention / creative A/B | Build now | Counterbalanced exposure, gaze import, static AOIs, validity mask, dwell/visit/TTFF definitions, group comparison and report. | Golden-data reproduction and qualified import; live use also requires adapter qualification. |
| IAT | Build now | Block sequence, category mappings, stimulus checks, practice, counterbalancing, named scoring variant, exclusion rules and uncertainty. | Independent scoring verification and runner timing/behaviour pilot. |
| Video attention / creative moments | Build instrumented | Media clock, frame transforms, temporal AOIs, key events, visibility, per-window summaries. | Video alignment and tracking benchmark; corrected metric equivalence. |
| Gaze + EDA product experience | Build instrumented | Event alignment, baseline/segmentation, artefact rules, named features, modality-specific missingness. | Reference-data agreement; synchronized acquisition validation where live. |
| ECG/PPG response and HRV | Build instrumented | Peak/artefact review, interval derivation, segment suitability, named feature definitions. | Algorithm validation and explicit protocol/window suitability. |
| Affective/semantic priming | Later method pack | Prime-target timing, masking where appropriate, SOA control, checks, trial exclusions, contrasts. | Physical display timing qualification for claimed setting; validated analysis. |
| AMP, SC-IAT, GNAT, evaluative movement | Later method packs | Method-specific stimuli, instructions, trial handling and interpretation limits. | Separate published-method implementation checks; not “IAT with different labels.” |
| Stroop / emotional Stroop / dot-probe | Later method packs | Condition structure, balance, timing and error handling, reliability-aware analysis. | Protocol validation and named reliability/quality summaries. |
| Website / interaction / UX tasks | After runner + DOM contracts | Page state capture, navigation/events, screen transforms, DOM AOIs, task success and gaze linkage. | Cross-browser and responsive-layout mapping qualification. |
| EEG consumer/UX response | Launch requirement; build instrumented from foundation | Channels/montage/reference, sample clock, event triggers, bad-channel/segment review, named spectral/ERP features where protocol supports them, preprocessing and explicit uncertainty. | Independent reference-data agreement plus physical trigger/timing qualification on the launch rig; no unvalidated attention/emotion score. |
| Push/pull approach–avoidance task | Launch requirement | Input-device mapping, motion/direction or key-mapping definition, approach/avoidance counterbalancing, RT/error handling, practice and named scoring. | Input-specific timing/behaviour qualification, published protocol specification and independently checked scoring. |
| Abbreviated IAT / brief association recipe | Launch requirement | Exact paradigm identified rather than a vague “short IAT”; category/focal mappings, blocks, stimuli, allocation, scoring variant and exclusions. | Separate protocol/scoring validation; do not assume conventional IAT validation transfers automatically. |
| Facial EMG / facial-behaviour analysis | Later domain extensions | Channel or model metadata, preprocessing, method-specific QC and definitions. | Independent domain review and reference benchmarks; no generic “emotion detector” claim. |
| Mobile / wearable / VR | Advanced acquisition | Device timestamps, coordinates, scene/object mapping, calibration and dropout handling. | Use-case-specific physical accuracy, timing and transform validation. |

Each recipe has maturity labels **example**, **experimental**, **validated implementation**, and **qualified configuration**. A validated algorithm implementation does not automatically validate a research construct, new stimulus set, population, device or protocol. Distinguish those claims in the library.

## 8. Onboarding, accessibility and earned confidence

The first experience should complete a real miniature study, not tour an empty dashboard. Provide a clearly synthetic sample, a prerecorded import example, and a device simulator. The walkthrough gradually introduces stimulus → observation → quality mask → AOI → result → derivation. Users can replay any step without damaging their work. A “why this step exists” explanation belongs next to the relevant action. Completion celebrates a verifiable achievement: “Your report can be reproduced from these inputs.”

Target WCAG 2.2 AA for the researcher interface with documented testing coverage; do not claim conformance before testing. Implement keyboard navigation, visible/unobscured focus, semantic controls, readable errors, resize/reflow where feasible, text alternatives, colour-independent status, and non-dragging alternatives to every builder action. AOI canvases need a synchronized object table with select/move/resize/rename controls and numeric geometry editing. Signal plots need data tables and textual summaries. Progress and asynchronous changes require appropriate status announcements. [W3C WCAG 2.2](https://www.w3.org/TR/WCAG22/)

Participant accessibility and measurement integrity need to be designed together. Alternative input modes, display conditions, larger text, translated instructions, motor accommodations or assistive technologies can change a timed task. Record relevant execution configuration, provide qualified accessible variants where possible, and explain study eligibility with dignity. Never silently modify a timed measurement while pretending it is the same condition. Instruction and consent surfaces should still be accessible even where a specific paradigm has participation constraints.

### Product psychology turned into testable design

| Observation | Mechanism | Enabling build response | Smallest useful proof |
|---|---|---|---|
| A novice may mistake automation for certainty. | Smooth output inflates confidence without understanding. | Evidence cards show method, valid sample, uncertainty and review state; short comprehension checks in onboarding. | Users can accurately explain why a flagged result is provisional after first use. |
| A method library can overwhelm. | Too many choices prevent action. | Start with a question, show 2–3 suitable recipes with reasons, preserve full search. | Compare first-study completion and appropriateness of method choice with a flat catalogue. |
| Exception review may feel like failed automation. | Unexplained interruptions reduce perceived competence. | Show completed work, grouped cause and a local fix with preview; retain successful work. | Time to recover and proportion completing the study after a seeded failure. |
| Fast repeated studies may drift methodologically. | Easy edits hide comparability changes. | Version diff, protected allocation, validity-impact labels and a visible fork lineage. | Researchers correctly identify which altered studies can support the same comparison. |
| Report automation may invite unsupported narratives. | Fluent explanation outruns the underlying evidence. | Result-linked text blocks and operational definitions; distinguish generated description from researcher interpretation. | Independent reviewers find fewer unsupported statements at equal reporting speed. |
| Experienced users may distrust simplified controls. | Hidden transformations weaken agency. | The same pipeline exposes configuration, R code, exact dependencies and a reproducible bundle. | An external researcher reproduces and intentionally changes one analysis without the UI. |

## 9. Delivery architecture assumptions

Align delivery around an R scientific core and a Shiny/bslib/golem application shell. Use browser-native TypeScript components for demanding canvas/WebGL interactions and an isolated jsPsych participant runner. Avoid routing time-critical trial execution through Shiny's server reactive loop. Define stable JSON-schema/OpenAPI contracts so the shell can evolve to a broader TypeScript/React application if measured UX or team constraints justify the migration.

Hardware acquisition uses a separate local adapter process capable of using the relevant native/Python SDK; R coordinates and analyzes. “R-based” describes ownership of methods, pipelines and product logic, not a claim that every device SDK or graphics primitive is implemented in R. Preserve original clocks and alignment uncertainty. Use a durable executor for jobs; a computational dependency engine is not itself a durable job queue.

The first integration milestone is import-first and local-first, with qualified eye/EEG/EDA/behaviour imports in the foundation. It is followed by a reference live rig that integrates eye, EEG and EDA with the behavioural runtime and tested event timing; this integrated capability is a launch requirement. Hardware access and SDK terms must be confirmed early. The R EEG core may use a qualified MNE subprocess through explicit contracts rather than recreating every mature algorithm in R. Dynamic video proposals follow static/DOM AOIs and quality benchmarks. Detailed module/package recommendations belong in the architecture companion.

## 10. Milestones and gates

The plan is a sequence of evidence gates, not a promise to fit an entire competitor suite into six months. The first 12 two-week sprints assume a coordinated core team working in parallel and access to scientific reviewers, hardware and representative commercial researchers. They target a credible **integrated research alpha**, with the data spine for all launch modalities, first eye/EEG/EDA pipelines, behavioural tasks, static AOIs and reporting. A full multimodal qualified-rig beta is the next launch gate. Hardware breadth, remote multi-tenant operations and advanced AOI tracking can continue later, but EEG/EDA and agile behavioural methods are launch commitments.

| Gate | Exit evidence | Depends on | Release consequence |
|---|---|---|---|
| G0 — product and contract ready | Agreed flagship protocol covering eye/EEG/EDA/RT/push–pull/abbreviated IAT and explicit-liking questionnaire; object model/fixtures for every modality and response; exact task/type variants; target matrix; novice guided journey tested. | Discovery and architecture spikes. | Authorize integrated implementation against measurable scope. |
| G1 — all-modality scientific spine | Eye/EEG/EDA/behaviour and questionnaire imports retain raw data clocks and response dictionary; named first pipelines reproduce references; common events/validity masks; configuration/hash/environment exported. | G0; independent reference fixtures. | Internal researcher build; no broad method-validity claim. |
| G2 — reproducible integrated alpha | Guided two-image attention study, named brief-IAT/AAT implementations and core questionnaire/liking flow reach automatic reports; eye/EEG/EDA imports share a timeline; response-to-stimulus/epoch joins and recovery pass; versions retained; independent scoring and reproduction pass. AAT may use simulated/import-supported inputs here. | G1; runner, questionnaire, static AOI, modality analysis, packaging and reliability contracts. | Invite limited external research partners to supported alpha; physical AAT integration is G3 and method qualification is G4; no full commercial-readiness claim. |
| G3 — full live reference rig | One named rig integrates live eye+EEG+EDA with RT, physical push/pull input and questionnaire responses on the common timeline; capture/timing/dropout/clock and response-event-linkage tests pass; calibration is documented. | G1–G2; equipment and SDK access; acquisition harness begun early in parallel. | Collect supervised complete flagship studies; expand device breadth deliberately. |
| G4 — method and AOI qualification | EEG/EDA/eye pipelines match references; BIAT/AAT execution/scoring and declared questionnaire types/logic qualified; explicit-biovital analysis validated; static AOI benchmark passes; novice/commercial pilot workflows meet agreed quality bar. | G2–G3; independent domain review; held-out AOI corpus; physical execution and survey accessibility tests. | Full flagship is scientifically and operationally ready for commercial beta within the named matrix. |
| G5 — commercial/public-launch package | Clean-machine installation; tutorials; reproducible bundle; critical-path accessibility; migration/recovery checks; no open data-loss defects; clear method/device matrix; public repository materials complete. | G4; release hardening and pilot findings addressed. | Launch the complete consumer/UX workflow; publish only concrete reviewed deliverables within the user's authorization. |
| G6 — automation, collaboration and ecosystem | Dynamic/DOM AOI benchmarks qualify selected automation policies; self-hosted roles; stable extension contracts; migration/recovery tests; public examples and contribution process. | G5; video/media clocks, benchmark tooling, persistence and permissions. | Broaden advanced automation and deployment with supportable claims. |
| G7 — broad platform maturity | Additional method/device packs independently qualified; benchmark regressions controlled; longitudinal adoption and contribution health. | G3–G6 plus sustained maintenance capacity. | Expand domains and deployment modes without diluting the core loop. |

**Critical dependency path:** versioned data/event/clock contracts → deterministic processing → quality masks → AOI lifecycle/coordinate transforms → gaze-to-AOI mapping → metrics/analysis → evidence-linked reports. Participant runner and study builder can proceed in parallel once the protocol contract is stable. Live collection depends on both event contracts and physical validation. Autonomous AOI approval depends on a benchmark, not merely an AI integration. Multi-user editing depends on revision/conflict rules established in local-first work.

## 11. First 12 two-week sprints

The backlog CSV supplies issue-sized slices; the sprint table specifies integrated outcomes. Acceptance criteria apply to the selected scope and named supported matrix. A failed gate reduces breadth or extends the milestone rather than lowering correctness requirements.

| Sprint | Goal and integrated work | Acceptance evidence | Dependency / exit |
|---|---|---|---|
| 1 | Define novice eye-study journey and full flagship contracts. Prototype guided steps, automatic paired analysis and explicit-liking questionnaire; specify all modalities, push/pull/BIAT, response dictionary and survey flow. | Schema covers all modalities and explicit responses; 5 formative sessions include undergraduates; decision/actions and comprehension recorded; recipe generates analysis; method/type-set definitions and rig shortlist documented. | Start G0; fixture permissions and device access recorded. |
| 2 | Build guided shell and reproducibility foundation. Project/store, immutable raw data, manifests, automatic sample recipe, contextual advanced mode and keyboard navigation. | Clean environment opens sample; configuration round-trips; all guided controls keyboard reachable; action-count instrumentation works; automated sample-to-report stub preserves a clear path to the 10-minute target. | G0 exit; contracts versioned. |
| 3 | Import selected eye, EEG and EDA reference formats plus generic event/trial tables. Mapping preview, units, EEG channel/montage metadata, original clocks and validation; synchronized explorer stub. | Each modality fixture imports identically twice; duplicate prevention; missing/invalid metadata stays local; unit and clock errors visible; uncertainty explicit where alignment is inferred. | Data spine usable across all launch modalities. |
| 4 | Durable processing slice. Job states, retry, caching/invalidation; gaze validity; initial EDA preparation; EEG processing bridge and channel-quality pass; independent reference execution. | First named outputs match independent fixtures within declared tolerances; interrupted work resumes without duplicate output; parameter changes invalidate correct descendants; unchanged rerun deterministic. | G1 candidate; no generic physiological interpretation claim. |
| 5 | Protocol, questionnaire and stimulus builder. Flow blocks, first question types, explicit liking, basic display/branch/piping logic, asset assignment, seeded randomization, dictionary and freeze/diff. | Allocation reproducible; invalid branches/pipes/hidden-required questions block launch; question IDs/coding and rendered wording persist; keyboard preview works; frozen protocols do not mutate. | G1 exit and builder/questionnaire contracts ready. |
| 6 | Participant runner and pilot readiness. Viewing, BIAT/push–pull and questionnaire blocks, practice/preload, response/event logs, survey checkpoint and branch debugger; full IAT reference where useful. | Pilot traces match block/question logic and input mappings; no server round trip controls timed onset; interruptions and displayed question versions captured; keyboard/mobile survey paths tested; timing claims limited to matrix. | Supervised behavioural/survey pilots begin; physical timing harness continues. |
| 7 | Static AOI workbench. Geometry, transforms, semantic categories, overlap rules, approval/revisions, import/export; early template proposals. | Golden gaze points map correctly under scaling/cropping and overlap policies; keyboard and numeric editing works; changing image/AOI invalidates mapping; rejected proposals cannot silently enter approved metrics. | Static AOI lifecycle established. |
| 8 | Multimodal quality and exception workflow. Linked stimulus, eye, EEG, EDA and RT review; bad channels/segments, reason-coded exclusions, grouped errors, modality-specific masks and batch review. | A seeded poor-quality/misaligned multimodal study can be repaired locally; all exclusions attributable; absence in one modality does not silently exclude another; bulk changes preview impact. | G2 candidate. |
| 9 | Automatic recipe analysis. Static A/B paired analysis, target-search success/TTFF censoring and descriptive reading/video foundations; independently verify BIAT/AAT scoring, eye metrics and first EEG/EDA features. | Student reaches appropriate analysis without model selection; named results match independent fixtures; no-lookers/missingness handled explicitly; participant/item dependencies respected; no-data states truthful; advanced changes versioned. | G2 scientific exit for the initial bounded feature set; advanced video/reading qualification continues. |
| 10 | Evidence-linked reporting and open research bundle. Reusable result cards, operational definitions, reproducible R/Quarto output, provenance appendix, export preview. | External reviewer can trace every result card to input and configuration; bundle reproduces on clean environment; report identifies exploratory changes and sample loss; stale cards block misleading final export. | G2 workflow candidate. |
| 11 | Hardening with external pilot teams. Installation, documentation, recovery, representative dataset performance, critical-path accessibility and usability fixes. | Pilot users complete defined workflows; seeded interruption/data-loss tests pass; critical accessibility defects closed; support questions are reflected in onboarding; performance results name dataset and machine. | G2 release candidate; no feature expansion. |
| 12 | Integrated alpha and next-gate planning. Versioned v0.1 package, supported matrix, fixture guide, migration/rollback rehearsal; full eye/EEG/EDA live-rig integration backlog and behavioural qualification evidence. | Fresh install and reproduction pass; no unresolved data-loss defect; demo includes all launch modalities with qualified imports and accurately labeled simulator/live state; external alpha feedback triaged; G3–G4 dependencies staffed and scoped. | G2 integrated alpha; G3–G5 remain the full flagship launch requirements. |

Sprint one formative usability sessions are for discovering problems, not statistical validation. Recruit experienced researchers, novice operators, an analyst familiar with R, and accessibility participants across the broader programme; do not treat five people as coverage of all roles or disabilities.

## 12. Longer horizon: delivery waves and parallel streams

After sprint 12, commit to the next gate and a small rolling two-to-three-sprint horizon. Reprioritize quarterly using completion friction, review time, reliability, scientific demand and community contribution evidence.

| Wave | Directional horizon for a core team | Main epics | Gate |
|---|---|---|---|
| A: integrated research alpha | First 12 sprints / about 6 months under the stated team assumption | All launch modality/response schemas/imports; first EEG/EDA/eye pipelines; RT/AAT/BIAT and questionnaire builder/runtime; static AOIs; automated novice analysis/report; packaging. | G2 |
| B: full multimodal commercial beta + stronger automation | Approximately next 3–6 months, overlapping bounded streams; extend if rig/method qualification needs it | Live eye/EEG/EDA adapters on one certified rig, physical synchronization harness, complete flagship UX, qualified behavioural inputs, static-AOI benchmark, release hardening; video/DOM spikes in parallel where capacity permits. | G3–G5 required for launch |
| C: repeatable research operations | Approximately next 6–12 months, scope contingent | Broader implicit method packs, multi-user/self-hosting, dynamic AOI policies, remote study operations, extension SDK, migrations and deployment support. | G6 |
| D: platform breadth and leadership | Ongoing; no credible fixed end date before learning from B/C | More devices and EEG protocols, EMG, wearable/VR, methods ecosystem, cross-study evidence, enterprise-scale operation where demanded. | G7 |

These are planning ranges, not estimates derived from an existing team's velocity. Two-week sprints mean roughly 26 iterations per year per delivery cadence. Hundreds of serial sprints imply multiple years; a large issue inventory is not evidence that this duration is necessary. Parallel teams may share one cadence, and their sprint counts should not be added to imply elapsed calendar time.

### Capacity scenarios

| Scenario | Assumed effective capacity and skills | Sensible scope and calendar implication |
|---|---|---|
| Solo / very small contributor effort | 1–2 effective full-time equivalents; specialist review and equipment access intermittent. | Build import and a complete cross-modality demonstration first; reuse established components. The 12-sprint core-team scope is not a six-month promise. A narrower alpha may take 9–18+ months; full flagship launch is a longer, presently unbounded commitment. |
| Focused core team | 5–7 effective full-time equivalents across R/methods, application UX, browser runtime, data systems, testing/research design; fractional EEG/psychophysiology review. | A six-month integrated alpha and subsequent 3–6+ month full-rig beta are planning hypotheses. Run scientific/data and UX/runner work in parallel; acquire hardware and start timing spikes early. |
| Expanded programme | 9–12 effective full-time equivalents with durable domain, acquisition, UX, infrastructure and quality capacity. | Preserve the same spine; parallelize device qualification, method packs, AOI benchmarking and operations after contracts stabilize. Do not proportionally divide calendar by headcount. |

“Effective capacity” includes code review, integration and maintenance rather than assuming every person delivers uninterrupted feature work. Initial planning reserve: 20–30% of delivery capacity for quality, dependency changes, research validation, documentation and unpredictable integration. Re-estimate after 3–4 completed sprints using actual cycle time. No named owners are assigned in this roadmap.

## 13. Open-source delivery operating model

Use a repository structure and release process that lets researchers trust the methods and contributors find a small useful task. Keep public source, redistributable fixtures, example recipes and generated method documentation separate from licensed SDK binaries and participant data. An adapter can be open source even when the user's vendor SDK must be installed separately; document this distinction in the capability matrix.

Minimum repository deliverables before public launch: clear problem statement and supported scope; quickstart; runnable synthetic demo; explicit software licence and third-party inventory; contributor guide; code of conduct; support/security reporting routes; versioned schemas; test/benchmark instructions; method/reference documentation; issue templates; a roadmap that distinguishes committed and exploratory work. Product naming and visual assets should be original.

Use release labels such as experimental, beta and stable separately from method maturity. A stable UI can contain an experimental method pack. Semantic versioning and migration fixtures protect saved studies. Each pull request affecting a method includes evidence of impact on reference results. Interface-only changes should avoid irrelevant scientific test expansion; changes to clocks, masks, AOIs, scoring or models require targeted numerical and regression evidence.

GitHub project views can filter the CSV by phase, epic, priority and dependency. Convert accepted rows to actual issues only after repository location, naming and initial scope are agreed. The supplied inventory is deliberately broader than the first release. No repository publishing, issue creation or external messages are performed by this planning work.

### Backlog contract

The companion `IMPLEMENTATION-BACKLOG.csv` contains **230 candidate work items**, not 230 sprint commitments, including the webcam/emotion/attention additions in `WEBCAM-EMOTION-ATTENTION.md`. `A:S01` through `A:S12` identify a proposed integration window; `B:G3` and later labels identify milestone gates. Dependencies express ordering and are validated as an acyclic graph. A ticket's placement in a sprint is provisional until the team sizes the actual implementation and confirms capacity.

`P0` means a core launch or required foundation item; `P1` means important scope to sequence around that core; `P2` means expansion. Priority is not a claim that every P0 fits the first twelve sprints. `S` indicates a small bounded task, `M` a moderate implementation or validation slice, and `L` a high-uncertainty or larger slice that must be decomposed or time-boxed before sprint commitment. These are relative planning classes, not hours or performance guarantees. Numerical tolerances and benchmark targets belong in the corresponding method specification before implementation, rather than being invented in the backlog.

The first planning review should reconcile the 12-sprint integration narrative against observed team capacity, hardware availability and scientific-review throughput. Preserve the complete launch contract and the novice automatic-analysis experience; adjust calendar or parallel staffing when they cannot both be delivered at the required quality. Do not silently relabel an import demonstration as full platform completion.

## 14. Scorecard and release decision rules

Measure product speed and research capability together:

| Dimension | Measures | Interpretation |
|---|---|---|
| First value | Time to first reproducible sample report; unaided completion; appropriate recipe choice. | A faster wrong study is not success. |
| Automation | Human review minutes per study; fraction of eligible work executed automatically; exception recurrence; correction propagation time. | Report by recipe/dataset; count only work meeting the same quality target. |
| AOIs | Held-out geometry/visibility/identity errors; metric disagreement; reviewer time; confident-error discovery rate. | A high proposal acceptance rate alone is not quality. |
| Scientific transparency | Independent reproduction rate; traceable output coverage; exclusion comprehension; unsupported-claim rate in reviewed reports. | Every published result should have a path to its inputs. |
| Reliability | Recoverable job completion; import/data-loss defects; restart/retry success; qualified timing and alignment performance. | Do not average away data loss or unsupported configurations. |
| Accessibility | Critical-path keyboard/screen-reader completion; unresolved serious defects; user-reported barriers. | Automated scanners supplement rather than replace task testing. |
| Adoption and contribution | Completed studies per active lab; repeat-study creation; time to first contribution; maintainable adapter/method contributions. | Stars/downloads are context, not research outcomes. |

Publish baseline conditions before setting performance claims. Compare against the current workflow with equivalent tasks, data, reviewer standards and supported hardware. Broaden tests only when new changes or unresolved concerns justify them. The next release should earn trust by completing the loop reliably and visibly reducing work, then use that foundation to expand methods and acquisition breadth.

## Source notes

- [Greenwald, Nosek and Banaji (2003), original improved IAT scoring paper](https://banaji.sites.fas.harvard.edu/research/publications/articles/2003_Greenwald_JPSP.pdf): implementation specification source; does not by itself validate new stimuli or individual-level product claims.
- [jsPsych timing accuracy documentation](https://www.jspsych.org/latest/overview/timing-accuracy/): informs the distinction between runner capability and configuration-specific timing qualification.
- [W3C WCAG 2.2](https://www.w3.org/TR/WCAG22/): accessibility target and test requirements; this proposed product has not been audited for conformance.
- [Sriram and Greenwald (2009), Brief IAT](https://faculty.washington.edu/agg/pdf/Sriram%26Greenwald.BIAT.2009.pdf) and [Nosek et al. (2014), BIAT scoring](https://faculty.washington.edu/agg/pdf/Nosek%26al.BIAT%20scoring%20algorith.PLoS%20ONE.2014.pdf): initial brief-association recipe specification sources.
- [Original mobile approach–avoidance task study](https://link.springer.com/article/10.3758/s13428-020-01379-3): input-specific implementation and validation example.

All product targets, team ranges, sequencing and interface designs in this document are recommendations and assumptions. They must be tested during discovery and delivery. No primary study is cited as evidence that this unbuilt platform already achieves them.
