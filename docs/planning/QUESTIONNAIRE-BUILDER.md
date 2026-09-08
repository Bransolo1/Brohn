# Questionnaire builder: evidence and implementation strategy

**Version 0.2 revision:** [The UX review](UX-TEAM-REVIEW.md) adds Alchemer evidence for runtime preview and response status, and specifies accessible correction and bounded branch-coverage reporting. [The application contract](ARCHITECTURE-CONTRACT.md) defines the shared R/TypeScript expression AST, immutable question/option IDs, optimistic concurrency, answer-event journal, and separate passive-viewing versus questionnaire epochs. The initial Qualtrics question-type and flow scope below remains in force.

Research date: **5 September 2026**. Primary operator: undergraduate psychology researcher. Proposed product: a complete study platform with eye tracking first, questionnaire blocks as a core capability, and additional physiology/implicit methods introduced through certified recipes.

**Evidence labels:** **O** = visually observed in downloaded official documentation image; **D** = documented evidence from official product documentation or an explicitly cited primary methods paper; **V** = vendor performance/benefit claim, not independently verified; **P** = proposed implementation or inference. No authenticated Qualtrics session was accessed. Screenshots demonstrate specific states, not the complete present product. Current pages contain older screenshots and experience-specific caveats; the library image visibly says 2021. Absence from this review means unverified, not absent from the product.

## Decision

**P:** Build an integrated questionnaire system, not an external survey link bolted onto the experiment. The novice starts from a complete eye-tracking recipe such as “Compare two designs and ask which they prefer.” The recipe supplies the viewing sequence, calibration checks, AOIs, explicit liking questions and an interpretable results page. A full builder remains available for adaptation, reusable measures and advanced studies.

The valuable Qualtrics pattern is a question rendered as participants will see it, with focused editing controls, reusable blocks and explicit flow logic. The proposed differentiation is that every answer already knows which exposure, stimulus, AOI and measurement period it refers to. Automation should remove repeated configuration and manual joins while keeping protocol decisions visible.

## Official UI evidence collected

**16 official support screenshots** are in `evidence/qualtrics/`. `provenance.json` records the source page, original image URL, retrieval date, dimensions, file hash and evidence type. `contact-sheet.png` provides a 4×4 overview. `evidence/manifest.json` is the packaged cross-platform evidence index. All 16 appear to be actual product UI states in the inspected contact sheet; randomizer, piping, accessibility and library originals were additionally inspected at full resolution. No videos or MP4 files were downloaded.

| File | Observed UI state | Documented capability and implementation implication |
|---|---|---|
| 01-question-types.png | **O:** Add-question menu beside rendered question | **D:** Type picker and library entry point. **P:** Offer examples and outcomes first; keep type names searchable. [Question types](https://www.qualtrics.com/support/survey-platform/survey-module/editing-questions/question-types-guide/question-types-overview/) |
| 02-question-editor.png | **O:** Selected cards, left edit pane and bulk actions | **D:** Multi-question operations and copying. **P:** Direct editing plus undo, with destructive edits showing affected logic. [Creating questions](https://www.qualtrics.com/support/survey-platform/survey-module/editing-questions/creating-questions/) |
| 03-matrix.png | **O:** Matrix canvas and answer-type selector | **D:** Multiple matrix variations. **P:** Use a common item/scale model and provide a small-screen alternative. A matrix MaxDiff format alone does not establish a complete MaxDiff experimental design system. [Matrix](https://www.qualtrics.com/support/survey-platform/survey-module/editing-questions/question-types-guide/standard-content/matrix-table/) |
| 04-slider.png | **O:** Slider rows and min/max settings | **D:** Bounds, steps, labels and N/A. A default position can be treated as an answer without movement unless configured otherwise. **P:** Preserve untouched, zero, midpoint and N/A separately. [Slider](https://www.qualtrics.com/support/survey-platform/survey-module/editing-questions/question-types-guide/standard-content/slider/) |
| 05-rank-order.png | **O:** Drag-order rows and format selector | **D:** Several formats; current new-experience compatibility differs. **P:** Always support keyboard move-up/down and ranked-choice controls. [Rank order](https://www.qualtrics.com/support/survey-platform/survey-module/editing-questions/question-types-guide/standard-content/rank-order/) |
| 06-display-logic.png | **O:** Condition builder with reference-source menu | **D:** Conditional question/choice visibility and in-page behavior. **P:** Show readable logic plus the reason an item appears on every preview path. [Display logic](https://www.qualtrics.com/support/survey-platform/survey-module/question-options/display-logic/) |
| 07-validation.png | **O:** Custom-validation condition and failure-message selector | **D:** Forced/requested response and custom/content constraints. **P:** Required, gently requested and optional must be separate settings. [Validation](https://www.qualtrics.com/support/survey-platform/survey-module/editing-questions/validation/) |
| 08-survey-flow.png | **O:** Nested branch containing an end-of-survey node | **D:** Ordered blocks and nested control elements. **P:** One flow should combine viewing, questions, sensors and tasks. [Survey Flow](https://www.qualtrics.com/support/survey-platform/survey-module/survey-flow/survey-flow-overview/) |
| 09-randomizer.png | **O:** Select-count control, even-presentation option and nested blocks | **D:** Random subset/order and exposure counters. **P:** Distinguish shuffle, counterbalance and allocation; record the realized assignment. [Randomizer](https://www.qualtrics.com/support/survey-platform/survey-module/survey-flow/standard-elements/randomizer/) |
| 10-embedded-data.png | **O:** Metadata names, types and analysis flags | **D:** Typed data fields can feed logic and reporting. **P:** Offer named participant/stimulus fields with types; hide opaque IDs from novices. [Embedded data](https://www.qualtrics.com/support/survey-platform/survey-module/survey-flow/standard-elements/embedded-data/) |
| 11-preview.png | **O:** Mobile participant preview | **D:** Full, block and question preview; desktop mobile preview is not an actual-device test. **P:** Sandbox preview plus real-device handoff and synthetic answer paths. [Preview](https://www.qualtrics.com/support/survey-platform/survey-module/preview-survey/) |
| 12-piped-text.png | **O:** Cascading menus selecting a question and answer representation | **D:** Response/metadata insertion into text. **P:** Replace syntax with typed chips, sample rendering and explicit missing-value fallback. [Piped text](https://www.qualtrics.com/support/survey-platform/survey-module/editing-questions/piped-text/piped-text-overview/) |
| 13-scoring.png | **O:** Matrix row scoring menu | **D:** Category scoring is distinct from answer recodes and can be updated retrospectively. **P:** Version scoring separately from raw answers. [Scoring](https://www.qualtrics.com/support/survey-platform/survey-module/survey-tools/scoring/) |
| 14-loop-merge.png | **O:** Tabular fields driving repeated content | **D:** Repeat blocks with row data and optional random ordering. **P:** A repeated questionnaire is a new exposure instance; never overwrite the previous answer. [Loop & Merge](https://www.qualtrics.com/support/survey-platform/survey-module/block-options/loop-and-merge/) |
| 15-accessibility.png | **O:** ExpertReview lists affected questions with links | **D:** New experience checks WCAG 2.2; legacy checks differ. The checker does not fully evaluate visual appearance. **P:** Fix-in-place diagnostics and direct keyboard/screen-reader evaluation. [Accessibility](https://www.qualtrics.com/support/survey-platform/survey-module/survey-tools/check-survey-accessibility/) |
| 16-question-editor.png | **O:** Question-library drawer and copy-from-project action | **D:** Reusable content; current docs describe migration from older library to certified questions. **P:** Reusable instrument packs with provenance, version, permissions and explicit forks. [Library questions](https://www.qualtrics.com/support/survey-platform/survey-module/editing-questions/question-types-guide/pre-made-qualtrics-library-questions/) |

**Evidence limits:** The contact sheet establishes a rich set of authoring states but does not prove transitions, loading/error behavior, latency, data-loss protection or novice usability. Interface equivalence is not the product objective. Subsequent testing should use a real account or public interactive walkthrough only where a missing state changes design decisions.

## Proposed question taxonomy

The following is a product proposal, not a claim that every item is present in a particular Qualtrics license.

| Delivery tier | Question family | Required semantics |
|---|---|---|
| Foundation | Single choice, multiple choice, binary choice, image choice | Stable option IDs; labels separate from values; ordered/unordered choice semantics; exclusive “none”; minimum/maximum selections; optional other text |
| Foundation | Explicit liking, preference, confidence and semantic differential | Named construct and referent; 5/7-point templates with editable anchors; endpoint direction; no default answer; raw response and derived score separate |
| Foundation | Slider / visual analogue scale | Null until interaction or explicit confirmation; touched flag; bounds/step; keyboard and numeric alternative; distinguish missing/N/A/prefer-not-to-answer |
| Foundation | Short/long text, numeric entry and form | Typed answer; unit and range; locale parsing; length; purpose-specific validation; no unnecessary personal-data collection |
| Foundation | Matrix / repeated rating items | Shared scale; explicit row IDs; mobile stack view; statement and scale ordering separately; no sideways-scroll requirement |
| Foundation | Text/media instructions, consent, comprehension check | Rich text with constrained formatting; alt text/captions; answerable consent distinct from instructions; failure/retry/exit route defined |
| Next | Rank order, constant sum, pairwise preference | Keyboard equivalent; untouched ordering not a submitted ranking; ties and partial rank explicit; total constraint visible |
| Next | Reusable multi-item measures | Source/license, exact wording, translation version, scoring key, missing-item policy; protected standard version and explicit editable fork |
| Next | Image hotspot, item/AOI selection, feature-specific liking | Click coordinates plus selected object/AOI version; responsive geometry transform; equivalent object list when method allows |
| Later | Best–worst/MaxDiff, adaptive questionnaires, conjoint | Full experimental design and analysis recipe required beyond a visual question widget |
| Later | Continuous video rating, annotation and voice/video response | Sample stream with timestamps, lag assumptions, active response interval, storage policy and accessibility alternative; explicitly a different task from passive viewing |

Support translation of wording, anchors, errors, alt text and instructions as a versioned unit. A language change must not silently switch the measure or scoring interpretation. Export a codebook with every response type.

## Novice authoring experience

**P:** Use the canonical five guided stages: **Plan → Questions → Collect → Review → Results**. Plan contains the recipe, materials and study sequence. Questions contains questionnaire cards linked directly to view, task and rest phases; its context panel preserves the surrounding study sequence. “Ask a question about this image” inserts a question already linked to the current stimulus. A recipe can offer “Ask after each image” or “Ask once at the end,” with a small sequence preview showing the difference. Collect includes device readiness and preflight checks; Review handles recorded-data quality and analysis decisions.

**P:** The first sample experience must require **at most 5 interface activations in total**. A prepared real study must require **at most 4 study-design decisions and 12 activations**. These are whole-path acceptance targets, not per-screen budgets or measured competitor performance. Use prepared assets, a complete recipe and prefilled questionnaire defaults; count any mandatory question selection, settings dialog, confirmation and navigation action in the total. Report the actual counting protocol and deviations during usability testing rather than hiding additional work in an uncounted setup stage.

Selecting a question opens one inspector with three plain-language sections: **Answer format**, **When it appears**, **How it is used**. Editing text occurs on the rendered card. The drawer shows a working miniature of each question, a one-sentence use case, and recent/reusable items. Show the default option first, rather than an unranked catalogue of every widget. Keep a persistent preview of the participant screen and estimated burden.

Use sentence logic: “Show this question when consent is yes.” Reveal nested AND/OR controls only when requested. A path simulator can explain “This question is skipped because the participant chose option B.” A condition chip opens its source; deleting a referenced answer offers a concrete repair. Piping is a named token with a realistic example and fallback, not a code fragment that the researcher must learn.

The preflight check within Collect groups actionable issues into **Must fix**, **Please review**, and **Ready**. Each issue opens the exact question/flow node and shows its impact. Check contradictory validation, inaccessible interaction, missing referent, hidden required questions, unreachable blocks, answer-before-definition references, impossible quotas, repeated-use IDs, untranslated anchors and insufficient event markers. Preview data must be isolated from recruitment quotas, randomization counts and production analysis. This isolation is our proposed contract, not a blanket claim about Qualtrics counter behavior.

## Flow and persistence contract

**P:** Store one immutable, versioned study definition. The authoring UI can be implemented through R/Shiny with a dedicated browser component; participant presentation should consume a compiled declarative definition and log events locally, avoiding a server round trip as the clock for each visual response. The exact frontend framework belongs to the platform architecture decision.

Represent flow as typed nodes: `sequence`, `block`, `question`, `view_stimulus`, `rest`, `sensor_check`, `task`, `branch`, `randomize`, `repeat`, `set_field`, `end`. Authoring is a structured tree with explicit references; the compiler validates dependencies and emits a runnable plan. Limit arbitrary jumps initially. Conditional expressions use a typed AST with `all`, `any`, comparisons, existence and collection membership, not executable R supplied by survey content.

```json
{
  "study_version": "immutable-version-id",
  "node_id": "compare_designs",
  "type": "repeat",
  "over": {"stimulus_set_id": "designs-v3"},
  "order": {"method": "counterbalanced", "plan_id": "allocation-v2"},
  "children": [
    {"node_id": "view", "type": "view_stimulus", "phase": "passive_view"},
    {
      "node_id": "like", "type": "question", "question_version": "liking-v1",
      "referent": {"kind": "current_exposure"},
      "response": {"kind": "ordinal", "values": [1,2,3,4,5,6,7], "initial": null}
    }
  ]
}
```

Each run receives stable session, node-instance and exposure IDs. Keep allocation atomic; store the random seed, algorithm version, eligibility state and realized order. Even exposure counters are not interchangeable with randomized block allocation. Resuming a session must preserve assignment and avoid duplication. Append answer revision events with idempotency keys; derive the submitted answer without deleting its history. An explicit return/back-navigation policy determines whether changing an earlier answer invalidates dependent downstream responses.

`draft` autosaves are separate from `published` collection versions. Publishing compiles a validated snapshot, assets and instrument versions. Existing sessions stay pinned to their starting version. Provide a semantic change review: “anchor changed,” “scoring changed,” “new branch,” rather than a raw JSON diff. Classroom preview, pilot and live data are separate environments. Snapshot the software and recipe versions in every export.

## Explicit liking must join to the intended exposure

**P:** Every answer record needs `study_version`, opaque `participant_id`, `session_id`, `node_instance_id`, `question_version`, `answer_revision`, `status`, raw typed value, locale and input mode. The optional referent is an object containing `exposure_id`, `trial_id`, `stimulus_id`, `asset_hash/version`, `aoi_set_version`, selected `aoi_ids`, and an explicit `segment_start/end` in the stimulus time base. Session-level demographics intentionally have no stimulus referent. A comparison question may refer to several exposures through a join table.

Distinguish **the time the answer was made** from **the earlier time the answer describes**. Log `question_visible`, `first_interaction`, `answer_changed`, `answer_submitted`, `page_hidden`, `stimulus_on/off`, `baseline_start/end`, `rating_start/end`, and response-device events. Include each event's clock domain, timestamp, synchronization transform/version, uncertainty estimate and delivery/acknowledgment state. A browser callback timestamp is not proof of the physical display onset; retain hardware timing validation where needed.

Example: a participant sees packaging image A, fixates its logo, then chooses 6/7 for overall liking. The liking belongs to the **whole exposure**, while the logo dwell metric belongs to an **AOI within that exposure**. The system can relate them analytically but must not relabel 6/7 as liking of the logo. If the question specifically asks about the logo, save that narrower referent. For video, record whether an answer concerns the entire video, a marked interval, a paused frame or continuous contemporaneous experience.

Keep R-facing tables in long form: `participants`, `sessions`, `exposures`, `questions`, `answers`, `answer_referents`, `events`, `aoi_versions`, `aoi_metrics`, `physiology_features`, `qc_flags`. Provide a validated join helper using immutable IDs, never participant names or row order. Results should show explicit rating, gaze and physiological measures as separately labelled outcomes. Analysis recipes may estimate their association with participant/stimulus repeated measures, order/condition and planned covariates. Do not treat duplicated AOI rows as independent liking observations or create an unvalidated overall “emotion score.”

## EEG/EDA and questionnaire timing

**D:** Overlapping skin-conductance responses complicate simple peak extraction; a primary method paper presents tonic/phasic decomposition and integration for event-related EDA, including short interstimulus intervals. This supports designing for overlap and recording event history; it does not establish one universal analysis window. [Benedek & Kaernbach, 2010](https://pubmed.ncbi.nlm.nih.gov/20451556/)

**D:** EEG events associated with stimulus presentation and button responses can overlap. Regression-based ERP methods can model temporally adjacent events under explicit assumptions. [Smith & Kutas, 2015](https://pubmed.ncbi.nlm.nih.gov/25195691/) A specific P300 study found button pressing affected amplitude/topography through motor activity; this is evidence to retain response markers, not a universal claim that every EEG response must be discarded. [Salisbury et al., 2001](https://pubmed.ncbi.nlm.nih.gov/11514251/)

**P:** Make a passive-viewing recipe phase-aware: configured baseline/rest → stimulus viewing → configured separation/recovery → rating → next exposure. Protocols set timings by modality and research question; never silently prescribe a fixed baseline for all studies. Show the author a combined timeline of planned stimulus, rating, response and physiological windows, highlighting overlaps before collection.

The rating prompt adds visual content and a cognitive task; mouse/key activity adds movement and response-related activity. Gaze on rating controls must be labelled as questionnaire gaze and excluded from the previous stimulus's AOIs by default. EDA changes may extend into the rating period; cropping solely at question onset does not eliminate an earlier response's tail. EEG pipelines must define stimulus-locked versus response-locked epochs, baseline scope, artifact handling and any overlap model. Preserve raw recordings and every event needed to reanalyse these decisions.

Continuous liking ratings during a video are a separate dual-task recipe, with input activity, possible response lag and changed gaze behavior stated in the study design and report. Do not imply that EDA measures liking, that attention implies preference, or that coincident arousal identifies which visual object caused it. Automated reports should present registered measures and quality limitations in direct language, with analysis parameters available one click deeper.

## Accessibility and comprehension acceptance

**P:** Aim for WCAG 2.2 AA for authoring and participant interfaces and verify concrete tasks with keyboard and screen-reader users. Use semantic groups/labels, visible focus, adequate target sizes, contrast-safe tokens, zoom/reflow and error summaries linked to affected inputs. Provide alternatives to dragging and sliders, preserve focus through branching, avoid silent auto-advance, and distinguish response time from accessibility-related navigation time. Do not mix input modes in a timing analysis without recording them.

A checker can catch missing labels, invalid focus targets and unsupported interactions; it cannot establish that a novice understands the measure. Test reading, choice comprehension and recovery. Recipe text should explain what AOIs and calibration do at the point of use. Eye tracking and visual paradigms can have method-specific participation requirements; provide an explicit accessibility pathway and record adaptations without suggesting all modes yield interchangeable scientific measurements.

## Delivery sequence and completion gates

| Milestone | Scope | Observable completion gate |
|---|---|---|
| Q1: integrated foundations | Core question renderer, explicit liking cards, event schema, exposure joins, null/missing semantics, basic preview | Complete the first sample experience within 5 total activations; a two-image eye recipe with questions joins answers to correct exposures across reload and repeats without manual spreadsheet joins |
| Q2: novice builder | Direct editing, type examples, basic matrices/sliders/rank, validation, blocks, undo, library | Target novices launch the prepared real-study path within 4 study-design decisions and 12 activations; preregister additional task-success/comprehension targets after baseline testing |
| Q3: flow compiler | Branches, piping, repeat, assignment/counterbalance, static checks, path simulator, version publishing | Synthetic runs cover every enumerated path in a bounded fixture; report representative coverage and its limits for unbounded inputs; invalid/deleted references are caught before collection; resume preserves assignment |
| Q4: trustworthy measurement | Sensor event integration, phase windows, AOI referents, QC, scoring versions, R exports and report | Reference dataset reproduces expected joins/scores; questionnaire periods remain distinguishable from passive stimulus periods |
| Q5: reusable instruments and access | Measures library, translation, role permissions, classroom pilot flow, keyboard/screen-reader audit | Tutor can distribute a pinned recipe and inspect student adaptations; participant modes and instrument provenance survive export |
| Q6: advanced agile research | Pairwise/best–worst packages, richer AOI questions, continuous rating, adaptive rules | Each package ships with validated design, timing envelope, analysis, synthetic example and a novice usability evaluation |

Required targeted verification includes untouched-slider versus zero, N/A versus unanswered, hidden-required questions, branch changes after back navigation, repeated-question instances, multi-exposure comparisons, scoring-version changes, offline/retry duplication, randomization concurrency, browser tab hiding and missing sensor markers. Test actual participant devices in addition to responsive preview. Keep an explicit coverage ledger of screenshot-informed states, implemented states, automated checks and human usability evidence.

The success metric is the proportion of novices who produce an interpretable, correctly joined study result with acceptable data quality, followed by their ability to explain what the result does and does not show. Click count and attractive panels support that outcome; they are not substitutes for it.
