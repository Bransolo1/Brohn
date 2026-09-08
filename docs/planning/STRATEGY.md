# An open research studio, built around a complete study

**Version 0.2 · two-team review incorporated.** Start with [Review and changes](REVIEW-AND-CHANGES.md) for the gap register and decisions. [The application contract](ARCHITECTURE-CONTRACT.md) now connects screen actions to saved state, R services, acquisition and reproducible reports. Scientific, hardware and novice-usability qualification remain future delivery work.

Strategic implementation plan · 5 September 2026 · version 0.1

Build a platform in which an undergraduate psychologist can choose a research question, prepare a study, collect eye tracking and other measures, and receive an understandable, reproducible analysis without writing code. Its scientific core is R. Its long-term scope is a single environment for dedicated and webcam-based eye tracking, webcam facial/behavioural observations, qualified emotion/attention research methods, EEG, EDA, reaction-time methods, approach–avoidance tasks, abbreviated IAT variants and explicit questionnaires.

The strategic advantage is the complete workflow: **question → prepared protocol → collection → quality checks → AOIs → analysis → understandable report**. Openness, low effort and visible scientific reasoning reinforce each other.

## Product contract

The user's latest instructions establish undergraduate psychologists as the primary operator persona. Commercial consumer/UX teams remain an important deployment context. These are compatible: the platform should help an inexperienced operator deliver a well-specified study and give experienced researchers the controls and audit trail they need.

The first useful release must complete a common eye-tracking study. The holistic launch must connect eye tracking, EEG, EDA, behavioural tasks and questionnaires in the same study model and provide a qualified integrated collection route. Early demonstrations using sample data or imports are milestones, not claims of complete hardware or commercial readiness.

The name “Research Studio” in the concept is a working label. No public product name, GitHub organisation, hardware purchase, licence choice or deployment destination has been selected. This package is a researched plan and design concept; it does not contain an implemented or validated research platform.

### What winning looks like

1. A student can run a prepared sample eye-tracking study and explain its report within ten minutes, with no code and no need to select a fixation algorithm.
2. A supervised novice can repeat that workflow with supported hardware; calibration, preparation and participant time are measured separately from interface actions.
3. A researcher can add liking ratings, EDA, EEG or an implicit task without rebuilding participant identities, stimuli, events or the analysis around them.
4. Most normal studies reach a draft report automatically. Ambiguous AOIs, poor recordings and consequential deviations appear in one review queue with a concrete next action.
5. Another researcher can reproduce a published result from the exported data, method versions, decisions and R environment.

These are proposed acceptance targets. They are not measured product performance or claims of superiority over competitors.

## The first flagship experience

**“Which design attracts attention, and which design do people say they like?”**

Start with the complete “Compare two visual designs” recipe: one image for A and one for B, viewed by the same participants. The student adds the two images, names the conditions and confirms the intended semantic targets and collection plan. The system prepares counterbalanced stimulus order, data-quality rules, the primary AOI outcome, a liking question after each stimulus and the paired analysis. It explains each choice in ordinary language and freezes the protocol before collection. Multiple stimulus items per condition or different participants in each condition use separate qualified recipes whose models respect that design; they do not silently inherit the two-image paired analysis.

The operator checks participant consent and device readiness, runs calibration and begins. The participant sees only the task. Eye data and questionnaire events are recorded against the same study and trial IDs. Later versions allow an EEG+EDA rig and a separately qualified push/pull or brief-IAT block in that same flow.

AOI semantics and the primary outcome are declared before collection. Geometry proposals use stimulus content before capture where possible; later corrections are made without consulting condition outcomes. When recording ends, the platform imports or finalises data, aligns clocks, checks quality, computes fixations and defined AOI metrics, and runs the planned comparison. The student reviews actual exceptions. A lab or course policy determines any separate audit sample of automatically accepted decisions; the clean beginner sample adds no compulsory audit clicks. The report explains attention and liking separately, shows uncertainty and exclusions, and links to the relevant plot, data and methods.

**Key design decision:** reduce decisions as well as clicks. A wizard that asks twenty unexplained scientific questions is still inaccessible. Defaults belong to a reviewed, versioned recipe and remain visible through “Why this choice?” and “Advanced”.

## Market evidence changes the target

The initial thesis that competitors centralise biosignals but offer little automation is too broad. iMotions already documents integrated collection, R notebooks and automated AOIs. Its Fall 2025 material adds survey-question AOIs, video segmentation, richer replay and aggregated exports. The defensible opportunity is to make validated methods, cross-measure analysis and novice comprehension work together with less assembly. [iMotions Lab](https://imotions.com/products/imotions-lab/), [R notebooks](https://imotions.com/products/imotions-lab/developers/r-notebooks/), [Automated AOI](https://imotions.com/products/imotions-lab/modules/automated-aoi/), [Fall 2025 update](https://imotions.com/wp-content/uploads/brochures/iMotions%20software%20update_fall_25.pdf)

Tobii Pro Lab contributes a useful Design/Record/Analyze structure. Its Advanced Screen workflow connects stimulus templates to a design table, and its release history documents automatic text AOIs and other automation. A new platform must match the clarity and depth of these interactions before claiming to exceed them. [Screen-based workflows](https://www.tobii.com/products/software/behavior-research-software/tobii-pro-lab/screen-based-eye-tracking-studies), [Advanced Screen design](https://www.tobii.com/resource-center/learn-articles/conduct-eye-tracking-studies-more-efficiently), [Feature history](https://www.tobii.com/products/software/behavior-research-software/tobii-pro-lab/features)

The accompanying competitor review separates template availability from general programmability. Inquisit provides strong implicit-task examples; Gorilla and Labvanced show visual task construction; PsychoPy and jsPsych are engineering/ecosystem references; RealEye demonstrates accessible eye analysis; CloudArmy contributes consumer-question-led packaging. Qualtrics is the questionnaire and flow reference. “Not verified” is not scored as “missing”. See the individual evidence-backed specifications for details and source URLs.

### Comparison framework

| Comparator | What to study or match | Differentiation to test |
|---|---|---|
| iMotions Lab and Online | Multimodal organisation; replay; AOIs; integrated R processing; mixed methods | An open, fully linked recipe that a novice can run and explain |
| Tobii Pro Lab | Eye-study structure; design tables; calibration; AOI and metric workspaces | Guided analysis choice and cross-measure reporting from the original protocol |
| Inquisit | Exact named paradigms, instructions and scoring definitions | A complete research workflow around those methods |
| Gorilla / Labvanced | Visual task/flow editing, debugging, randomisation and reuse | Defaults that begin with a research question and include analysis |
| PsychoPy / jsPsych | Task execution, timing evidence and extensible components | A consistent novice interface above qualified execution engines |
| RealEye | Immediate access to gaze visualisation, AOIs and downloadable summaries | A shared model for lab-grade multimodal and explicit measures |
| CloudArmy | Consumer research framed around questions and decisions | Open methods, provenance and reusable analysis rather than opaque outputs |
| Qualtrics | Questionnaire construction, logic, flow, previews and reusable blocks | Stimulus- and event-linked explicit responses and automatic multimodal analysis |

This is a strategic comparison, not a completed hands-on usability ranking. No competitor was benchmarked under matched users, hardware and study conditions in this task.

## A premium interface with a simple front door

The default navigation has five stages: **Plan → Questions → Collect → Review → Results**. Plan encompasses the recipe, materials, conditions and predeclared AOIs; Questions contains the linked questionnaire. Prepared content can pass through these stages without an obligatory confirmation on each page. Projects, assets, devices, methods and permissions exist in the distinct advanced information architecture but do not compete for attention during a first study. A returning expert can open the full workbench directly.

Use stable placement, readable typography, generous targets and one dominant action. Present status with words as well as colour. Preserve a visible route back, keep edits reversible and state what a change will recompute. An AOI or questionnaire change should not send a novice hunting through different modules to repair downstream analysis.

The product has three levels of detail:

* **Guided:** the research question, sensible defaults, checks that need attention and understandable results.
* **Explain:** why a rule was chosen, how a measure is defined, what was excluded and what the finding can support.
* **Advanced:** algorithm settings, study graphs, statistical models, raw data and code.

These are views of the same saved study. They must not create incompatible study formats or separate “student” and “professional” applications.

### Proposed novice usability budgets

| Journey | Proposed budget | How it is counted |
|---|---|---|
| Open a prepared sample and read its report | ≤5 total activations; 0 scientific configuration decisions; ≤10 minutes | Starts from the home screen; includes report navigation, excludes download/install; no compulsory audit clicks |
| Prepare a common eye study using existing stimulus files | ≤4 substantive design decisions; ≤12 total activations | Includes file-chooser actions, selections and confirmations; decisions cover design, materials/conditions, semantic targets/primary outcome and collection plan; record typing separately |
| Add a repeated liking question from a recipe | ≤3 activations | Includes inserting and confirming scope; existing linkage is automatic |
| Start another participant on a ready rig | ≤4 software activations | Physical fitting, consent conversation and calibration duration reported separately |
| End recording to an analysis-ready draft | Zero required configuration actions for the qualified recipe | Review exceptions separately; do not conceal automatic failures in the average |
| Re-run after one accepted AOI correction | One action or automatic queued recomputation | Preserve the previous report and show affected outputs |

Test with at least 8–12 new undergraduate users in formative rounds, then a larger summative sample appropriate to the acceptance decision. Record unaided completion, time, errors, support interventions and comprehension together. A participant who clicks quickly but misreads dwell time as liking has not succeeded. These sample ranges are planning assumptions, not statistical power calculations.

## End-to-end analysis is a product surface

“Automatic analysis” means more than an export button. Every recipe includes preprocessing, exclusions, AOI/epoch definitions, primary and secondary outcomes, statistical design, missingness handling, diagnostics, uncertainty and a report template. It declares where the user must review and which steps can run unattended.

| Common approach | Automatic path | Important interpretation preserved |
|---|---|---|
| Static A/B visual comparison | Gaze QC → qualified fixation recipe → AOIs → participant-level metrics → planned paired or independent comparison → report | Fixations are not independent participants; more viewing does not necessarily mean more liking |
| Visual search / shelf findability | Target definition → target visibility → first target entry and success → response-time alignment → censoring-aware summaries | Never-looking is not a zero time-to-first-fixation; response error and attention are separate |
| Video/ad testing | Media timestamps → shot/epoch definitions → dynamic AOIs → visibility and gaze coverage → prespecified segment contrasts | AOI absence, occlusion and gaze loss differ; movement can alter what is measurable |
| Reading | Text layout AOIs → valid fixations and transitions → declared reading metrics → planned comparison | Different display layout/language versions are recorded; text accessibility changes can affect the method |
| EDA response analysis | Units/contact QC → declared filtering/decomposition → baseline/event windows → participant summaries → contrasts | Delayed/overlapping responses and movement are handled; EDA does not itself identify positive or negative emotion |
| EEG analysis | Montage/reference checks → filters/artifact handling → qualified epochs or spectra → retained-data counts → contrasts | No universal emotion or engagement score; method, channels and valid timing determine available claims |
| Brief IAT / approach–avoidance | Exact task version → response/timing QC → named scoring rules → error/exclusion summary → uncertainty | Shortening a task or changing joystick to swipe creates a method variant requiring its own qualification |
| Explicit liking + physiology | Linked responses → labelled passive/question epochs → aligned participant/stimulus summaries → planned joint model or separate outcomes | Rating-period motor/cognitive effects are not folded into passive-viewing responses; association is not causation |

This table specifies intended behaviour. The detailed architecture and method registry define the implementation and validation requirements; it does not assert that any recipe is already validated. Method-specific assumptions must be reviewed with research specialists before release.

### How the automation works

Run a versioned dependency graph: `original files + frozen study → canonical streams/events → clock correction → quality masks → derived signals → AOIs/epochs → metrics → planned models → report`.

Any change marks only its dependent results stale. Jobs survive closing the researcher screen, produce durable logs, can resume safely and never overwrite originals. The report carries a run ID and a manifest of its exact inputs and versions. A previous report remains inspectable after recomputation.

The review queue groups exceptions by the decision required: fix sensor fit, check a clock discontinuity, review an AOI track, accept a documented exclusion, or resolve an ambiguous question code. Show consequence, evidence, suggested action and undo. Automatic acceptance and audit sampling are governed by a qualified lab/course policy. Measure audit work separately from the clean beginner sample, which requires no extra compulsory sampling clicks; an actual quality exception still needs its specified resolution.

Natural-language assistance can help create a draft protocol or explain a result. It must not silently change the method, invent statistical findings or become a dependency for running a study. Deterministic R results and report templates are sufficient for the core product.

## The AOI automation programme

Build four routes on one AOI data model: researcher-defined static geometry; template/DOM/text-based regions; video object segmentation and tracking; and wearable-scene mapping to a reference. “Logo”, “price”, “face” and “call to action” are versioned semantic labels attached to objects, not truth inferred from a screenshot alone.

Start with static AOIs and exact stimulus coordinates, then ship assisted video tracking. Store polygon/mask, validity interval, visibility, occlusion, object identity, confidence, source and reviewer decision. A hidden object, an offscreen object and invalid gaze are separate states. Report the denominator used for each metric. Link parent and child regions explicitly and define overlap rules before computing comparisons.

Qualification measures both geometry and the resulting research metrics: boundary agreement, track identity switches, occlusion errors, gaze-to-AOI assignment and metric differences against expert annotations. Measure researcher correction time as well as model accuracy. The desired advantage is less total work at acceptable analytic error, not a persuasive-looking overlay.

## Qualtrics-level questionnaires, linked by design

The questionnaire editor and task editor share a flow model. A question can appear at intake, before/after a stimulus, between task blocks or at debrief. Each answer preserves question and option IDs, versions, participant/run/trial/stimulus context, onset and commit times, missingness and the flow path taken.

The full destination includes multiple choice, numeric/text input, ratings, sliders, matrix variants, ranking, constant sum, semantic differentials, images/media, embedded data, piping, display/skip/branch logic, randomisation, loop-and-merge and reusable blocks. Prioritise a declared set of high-value, accessible types first; “Qualtrics-level” is an interaction and capability target, not an immediate parity claim.

A novice inserts “Liking after each stimulus” as a prepared block. Advanced users edit the question, response anchors, branch rules, scoring and report mapping. Preview the actual participant path, including mobile layout and simulated answers. Explain logic in sentences and show which answers cause a branch. Lint unreachable questions, missing variables, impossible branches and potentially endless loops before launch.

The questionnaire specification and Qualtrics screenshot references in this package provide the detailed type taxonomy and flow requirements. Preserve the distinction between collecting an explicit answer, deriving an instrument score and relating that score to physiological data.

## R implementation direction

### Webcam, expression and attention research

Webcam collection belongs in the long-term platform. A guided remote recipe should test the camera, lighting, calibration and usable-data coverage, then expose only the methods qualified for that setup. Webcam gaze and dedicated eye-tracker gaze remain distinct sources with their own accuracy/precision limits; supporting one does not establish equivalence to the other. Record head pose, blink and facial-action estimates with their source, model/version, timestamps and quality. Optional expression-model predictions remain attributed model outputs, while a participant's reported emotion is an explicit questionnaire response. Attention is operationalised through named gaze, task and physiological measures; the product does not claim a universal emotion or engagement truth.

The companion `WEBCAM-EMOTION-ATTENTION.md` specification expands method choices and qualification. Camera processing may run locally in the browser or through an optional versioned vision worker. The collection recipe declares whether raw frames, derived features or both are retained/transferred. Remote transport preserves the same participant/stimulus/trial/timebase contracts and remains outside timing-critical task execution. A complete sample and supported core study do not require a paid expression API.

### Scientific and application boundaries

Use R for the scientific domain, not for every timing-critical callback. Start with a modular Shiny/bslib researcher application and reusable TypeScript components for the AOI editor, media timeline, questionnaire interactions and task runner. Keep capture in an independent local service using qualified device SDK/LSL adapters. Use R workers for the scientific pipeline and qualified external workers where necessary for EEG or computer vision.

Keep the domain usable as R packages outside the GUI. Use versioned schemas, immutable originals, Arrow/Parquet derivatives, transactional metadata, durable jobs, a method registry and reproducible report generation. Local/offline study operation is a first-class requirement, particularly for teaching labs.

The architecture specification includes component contracts, data models, timing, job semantics, storage, frontend alternatives, API shapes, plugin boundaries, testing and deployment. A two-sprint interaction spike should validate the hardest AOI/timeline/questionnaire interactions before the shell is locked. Framework choice is an engineering decision; premium UX depends on the workbench design and its measured performance.

## Delivery strategy and funding logic

Use two-week sprints and gated capability releases. Do not commit to hundreds of sequential sprints before measuring team throughput, hardware integration effort and validation work. The backlog is an option set across parallel domains, with acceptance criteria and dependencies; it is not a calendar.

| Gate | Deliverable that can be demonstrated | Evidence needed to pass |
|---|---|---|
| G0 · Foundation | Shared study/event/response/AOI contracts and accessible interaction prototypes | Expert review; novice walkthrough; reproducible synthetic fixtures |
| G1 · Centralisation | Eye, EEG, EDA, task and questionnaire data in one coherent project | Import fixtures, units/clock checks, linked inspection and round-trip exports |
| G2 · Integrated alpha | Guided eye study, core questionnaire/liking flow and named brief-IAT/AAT implementations reach automatic reports; eye/EEG/EDA imports share a timeline | Independent scoring fixtures; response-to-stimulus/epoch links; novice sample testing; recovery tests. AAT may use simulated/import-supported inputs here; no physical-method qualification is implied |
| G3 · Live integration | One declared rig records eye+EEG+EDA with timed tasks, physical AAT input and linked questionnaire responses | Device qualification, physical clock/timing evidence, response-event linkage, data-loss and restart tests |
| G4 · Method and AOI qualification | Named brief-IAT/AAT and multimodal recipes, declared questionnaire types/logic, explicit-liking joins and AOI automation meet their protocol gates | Independent method/scoring comparisons, physical-input qualification, survey runtime/accessibility tests, annotated datasets, comprehension and correction-time benchmarks; qualified beta limited to the named support matrix |
| G5 · Supported public launch | An installable, documented open-source platform with supported workflows | Reproduction on a clean machine, usability/accessibility gates, release and support readiness |
| G6 · Expansion | More hardware, recipes, advanced questionnaires and collaboration | Adoption evidence and qualification for each addition |

`UX-AND-ROADMAP.md` uses the same G0–G6 sequence and additionally names G7 for ongoing platform maturity beyond expansion. G7 does not change the G0–G5 launch requirements.

The first 12 sprints detailed in the UX roadmap target a useful integrated alpha and progressively exercise the full model. They do not guarantee production readiness, scientific validation or all hardware support in six months. A small founding team will need more sequential time; a multidisciplinary team can work on device adapters, method qualification, survey logic and interface implementation in parallel. Capacity assumptions and alternative schedules appear in the roadmap.

### Where to invest first

Fund the connected study model, reference datasets, recipe engine, student workflow and automated analysis before expanding hardware breadth. Start hardware qualification early because lead times and SDK constraints can dominate the critical path. Questionnaire linkage and static AOIs are foundation features; dynamic AOI automation, richer EEG methods and broader survey types grow through explicit gates.

Run four recurring research tracks alongside delivery: novice usability; scientific-method qualification; hardware/timing qualification; and competitor workflow benchmarking. Reassess the roadmap at release gates and quarterly. Promote backlog items using measured user friction and study completion, not screenshot novelty.

## Open-source implementation and GitHub handoff

The repository should contain the scientific packages, app, schemas, qualified example recipes, synthetic/reference fixtures, architecture decisions, contribution guidance and test workflows. Keep acquisition/algorithm plugins behind documented contracts, with supported-device and validated-method matrices. A release records software dependencies, model versions and dataset licences.

Choose the code licence deliberately before public publication. Apache-2.0 is a candidate when permissive reuse is the priority; copyleft may be preferable if reciprocal distribution is the priority. Check actual dependencies, device SDK redistribution and task/stimulus rights before selecting. The current plan does not issue a legal conclusion or assume that vendor examples can be copied into an open repository.

The vendor screenshots are a private research reference library. Keep them outside the public source repository unless their redistribution terms have been established. Publish original interaction specifications, source links and newly drawn product designs instead. The proposed `.gitignore` and release checklist make that separation operational without blocking design work.

Publish in phases: documentation and synthetic example; runnable local study; qualified methods and importers; certified live adapter set; supported release. For each, provide installation, a ten-minute example, a reproducibility command, known limitations and contributor tasks sized for independent work.

## Evidence coverage and remaining discovery

The visual library contains actual vendor-published interface images, annotated documentation captures and selected feature illustrations, with provenance and version/age notes. It is sufficient to study major layouts and build original workflow specifications. It is **not** a complete capture of every current authenticated state, nor enough to guarantee a faithful reconstruction of any whole competitor application.

The iMotions help site redirected to a login during this task. Other gaps include authenticated onboarding, exact device errors, autosave/concurrent editing, some current report configuration and deeper permission states. Historical screenshots are labelled and must not be presented as current UI.

Before claiming full workflow parity, run scripted hands-on sessions using authorised demo accounts: create a study, add media and questions, randomise, pilot, connect/calibrate, record, correct AOIs, rerun analysis, export and recover from a failure. Capture before/action/after states, software version, duration, click count, visible feedback and data consequences. The evidence capture checklist and coverage table specify that work.

No public GitHub repository was created in this task. The deliverables are ready to guide that implementation, with unresolved choices isolated from work that can begin immediately.
