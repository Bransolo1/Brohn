# Eye-tracking study flexibility

Owner requirement, 1 October 2026: support common consumer eye-tracking designs, including shelf testing, control stimuli and multiple stimulus versions within one study. This extends the existing platform work; it is not a declaration that every design is currently supported. Detailed academic applicability review and implementation are active.

## Required design families

- Packaging and static shelves: single-pack inspection, competing products, alternative layouts, shelf position/facings, prices, claims, signage and matched comparator/control displays.
- Free viewing, target search and findability: distinct instructions, target-present/absent trials, correctness, time limits, completion/abandonment and explicit task outcomes.
- Advertising: static creative, video scenes, repeated exposures, brand/product/message AOIs and synchronized explicit responses.
- Websites, apps and ecommerce: task journeys, scrolling, responsive layouts, state changes, search, navigation and choice, with actual displayed coordinate context.
- Reading, labels and menus: text/claim regions, comprehension and search questions, layout variants and meaningful region correspondence.
- Physical shelves and product use: wearable/scene-camera records, real-world actions, changing viewpoints and original recording alignment.
- Comparative and longitudinal designs: within-person, between-person and mixed allocation, repeated sessions, exposure history, matched material sets and planned comparisons.

## Cross-design flexibility requirements

| Requirement | Implementation and acceptance needed |
| --- | --- |
| Controls | Multiple control/test/neutral/comparator conditions; explicit rationale, matched features and planned contrasts. A stimulus control does not create a recorded physiological baseline. |
| Versions in one study | Distinct stimulus IDs and immutable asset hashes; convenient duplicate/edit workflow; later explicit concept, variant, layout and material-family identities. Never overwrite what an existing participant saw. |
| Assignment | Declare who sees which versions, frequency, order and position. Prevent unintended repeated exposure; retain seed, assigned set and actual presentation record. Rotation alone does not balance every carryover effect. |
| Shelf construction | Stable product/brand/SKU and placement identities, rows/columns/facings, controlled size/position/price changes, reproducible layouts and reviewed AOIs. Treat a shelf image and a physical shelf as different acquisition contexts. |
| AOIs | Static rectangles and future polygons/dynamic regions; semantic correspondence across versions, overlap/unassigned rules, source/frame binding and boundary sensitivity. Review automatic proposals before use. |
| Timing and task flow | Task instructions, practice, exposure, participant response, inter-trial/recovery and baseline as separate declared elements. Preserve observed onset/offset, timeout and interruption evidence. |
| Device and geometry | Calibration/validation, spatial uncertainty, sampling/loss, geometry, distance/head movement and source-specific suitability. Webcam selection does not establish validated gaze acquisition. |
| Measures | Clearly defined sample gaze time, fixation candidates, dwell/latency/visits/transitions and pupil/blink support, plus choice, correctness, comprehension and explicit liking where designed. Looking is not automatically liking. |
| Analysis | Version/condition/placement-aware summaries and planned contrasts; person/session/stimulus hierarchy, exposure opportunity, missingness/censoring and uncertainty. Avoid silently pooling variants that answer different questions. |
| Accessible workflow | Reusable templates, bulk material/region operations, keyboard/numeric alternatives, understandable preflight and review, low-click authoring and complete historical reproduction. |

## Checked current implementation

The inspected source16 schema permits up to 100 conditions and 500 stimuli,
including multiple stimuli per condition and multiple control-role conditions
([validator](../../R/platform-core.R)). These are operational ceilings, not
recommended study sizes. Registered roles remain `control`, `test`, `neutral`
and `other`; benchmark/comparator purpose can be named without inventing a new
schema role. Material hashes and saved design revisions retain distinct assets.

The ordinary-stimulus compiler includes every listed stimulus once per allocation
using fixed order, cyclic rotation or full shuffle. It does not implement
within-study between/mixed variant assignment. Two-stimulus rotation gives AB/BA
across allocations, not a four-trial ABBA sequence or general carryover balance.
Registered task blocks and MaxDiff have their own contracts.

Current [planned gaze comparisons](../../R/platform-analysis-plan.R) match AOIs
by label and aggregate exposures within a condition/session before person-level
comparison. Assigning versions to one condition can pool them. A new condition
does not automatically create a contrast, and multiple control roles do not
automatically generate all pairwise tests. Concept, variant-set, layout and
product-placement identities remain future design fields.

The [AOI editor](../../R/platform-aoi.R) admits attached static images and
normalized rectangles. Moving media, text and scene regions need another
coordinate profile. [Local delivery](../../R/platform-delivery.R) admits
text/image/audio/video but explicitly refuses web stimuli, although the broader
design schema names that type. A screenshot study and live website study are
different capabilities.

## Checked-source design matrix

This bounded review maps source16 behavior to requirements; it is not exhaustive
all-options coverage or scientific qualification. A1–A9 and V1–V3 refer to the
[portable source/depth companion](EYE-TRACKING-FLEXIBILITY-SOURCES.md). Academic
papers, official device examples and working software are separate evidence types.

| Design family | Available pieces in the inspected source | Required flexibility and boundary | Evidence |
| --- | --- | --- | --- |
| Static shelf and packaging | Image assets, multiple conditions/stimuli, static rectangle AOIs and saved gaze summaries. | Product/SKU, layout and placement/facing identities; controlled position/size/price/signage; benchmark displays and separately observed choice. A flattened shelf image is possible; a planogram constructor and factorial allocation are not. | A1 selected design/procedure text; A2 abstract; independent author teams. |
| Free view versus target search/findability | Global instructions, timed passive viewing and before/after/end questions. | Task-specific target/presence, response, correctness, not-found, timeout and stopping rule. A post-exposure rating or first fixation candidate is not recorded search success. | A3/A4 task and choice contexts; A5 ad goals. Exact target-absent/censoring protocol needs further appraisal. |
| Static advertising and creative variants | Static materials/AOIs with linked explicit questions. | Version/control identity; brand/picture/text meaning; separate recall, comprehension and liking; exposure history. Gaze share is not a liking score. | A5/A6 abstract-level, different teams. |
| Video, animation and dynamic shelves | Local video playback and preserved asset/duration. | Actual playback/seek/skip timeline, scene cuts, time-varying AOI visibility and mapping uncertainty. Static rectangles do not track moving targets; browser time does not establish physical onset. | A7 abstract plus V1 technical context, neither a dynamic detector validation. |
| Web/app/ecommerce tasks | A static screenshot can be an image; live web is not admitted by local delivery. | Supported capture adapter, page/state/viewport/scroll/DOM identity, task/click/outcome events and gaze coordinate transform. Screen recording alone is not semantic AOI tracking. | A8 limited publisher text; V3 vendor tutorial, not independent validation. |
| Comparative preference and choice | Linked numeric questions and separately registered MaxDiff. | Choice-set/alternative/position identity, actual selection/latency, no-choice and timeout, planned comparisons. A side-by-side image remains passive unless a response protocol is implemented. | A4 selected methods; A9 abstract, different teams/settings. |
| Physical shelf, mobile/wearable and product use | Imports only under admitted source mappings; current raw gaze geometry uses a fixed stimulus plane. | Named device/clock chain, scene/action context, viewpoint, occlusion, object motion, localization loss and reviewed mapping revisions. Missing localization must not become zero dwell. | A2 lab/store abstract; V2 technical limitations. No Brohn wearable qualification. |
| Reading, labels and menus | Static label/menu screenshots, reviewed rectangles and explicit questions. | Exact text/language/font/wrapping, semantic or word/line regions where needed, scrolling and comprehension/search outcomes. Word-reading/regression estimands are not implemented by a screenshot template. | A8 navigation and A5 advertising only; reading-specific appraisal remains open. |
| Repeated/A–B/multiple versions and sessions | Many stimuli per condition; all-stimulus ordering; imported exposure/session identities. | Variant sets, intended frequency, within/between/mixed allocation, position policy and prior-exposure history; distinguish intended assignments from actual presentation. | A1 mixed manipulations; A4 order/starting-condition limitations. No general carryover or longitudinal preset. |

## First authoring slice — implemented and scoped acceptance passed

**Add stimulus version** is implemented. Its 36 domain/portable and 28 actual
Shiny observer/SQLite checks pass alongside the desktop/phone keyboard,
control/condition, material replacement, Save and reopen journey. Read the
[acceptance record](../qa/STIMULUS-VERSIONS-ACCEPTANCE.md) and
[researcher guide](../operations/STIMULUS-VERSIONS-AND-CONTROLS.md).
The delivered contract is:

- Require an explicit version name and identify the source stimulus.
- Offer an existing condition or a new condition with editable registered role;
  default to a new condition to avoid accidental pooling, without claiming that
  every scientific variant must be a condition.
- Create fresh stimulus/AOI IDs while preserving exact material descriptor,
  timing, content, alternative text and AOI values from the current draft.
  Preserve original and historical records.
- Explain that every participant sees each listed ordinary stimulus once and
  that same-condition versions may be combined in summaries.
- Retain authorization, current-revision, archive/collection, capacity and
  material checks; failure or cancel must not leave a partial condition/stimulus.
  Existing replacement of image bytes must retain its AOI-clearing behavior.
- Pass exact value/identity conservation, both condition routes, stale/unknown
  inputs, capacity boundaries, compile semantics, historical binding and actual
  keyboard/mobile/focus checks. Pure cloning tests alone are not journey acceptance.

The new-condition default is a product safeguard, not an academic prescription.
Baseline 0 ms, fixation 500 ms and ordinary exposure 5000 ms remain operational
starter defaults, not method-qualified timings. A neutral/control display does
not create recorded physiological baseline support.

## Ordered implementation queue

EF01 authoring is accepted within its recorded scope. EF02–EF12 remain open.
This queue adds detail within all 50 capabilities and 17 unfinished packages;
it does not replace their existing individual statuses.

| ID | Required next output | Acceptance/dependency |
| --- | --- | --- |
| **EF01 — scoped acceptance passed** | Add stimulus version, above. | Domain/portable36, controller28 and actual desktop/phone researcher journey. No science/schema/assignment claim. |
| **EF02 — next** | Concept, variant-set and immutable asset/layout revision identities, separate from conditions. | Versioned design/import/export/clone contract; no ID aliasing or historical rewrites. BWP03/BWP15. |
| **EF03 — next** | Explicit within/between/mixed allocation, variant subset/frequency, mutually exclusive versions and position/order policy. | Seed/algorithm/assigned set/actual sequence and resume semantics; accidental-repeat and allocation checks. Compiler/delivery, BWP03/BWP06. |
| **EF04 — next** | Static shelf/packaging builder or validated planogram import with product, placement, facings, size, price and signage. | Reproducible asset/layout, controlled-factor diff, exact coordinates and accessible editing. Factorial generation remains a separately named method. |
| **EF05 — next** | Reviewed semantic AOI correspondence across versions/layouts and repeated facings. | Meaning versus instance, absent region, overlap and assignment rules; no label-only accidental join. Changed estimands require new recipes. BWP09. |
| **EF06 — next** | Task-aware target search and ordinary forced choice, distinct from passive viewing/MaxDiff. | Target/choice IDs, success/error/absent/timeout/abandonment, response-triggered offset and actual clocks; new delivery/event protocol. |
| **EF07 — later** | Dynamic AOIs/video scenes and playback timeline. | Frame/time transforms, visibility, seek/skip, reviewed tracking and unknown intervals; detector suitability separately evidenced. |
| **EF08 — later** | Live web/app capture and page/DOM/viewport/scroll context. | Named adapter, state/event/geometry bindings and navigation outcomes; URL alone is insufficient. |
| **EF09 — later** | Wearable/physical shelf/product-use acquisition and scene mapping. | Named device/software/clock, calibration, localization/occlusion/motion and correction provenance; physical qualification remains open. |
| **EF10 — ongoing** | Multiple controls, matching rationale and controlled-property differences through design/analysis. | Existing registered roles remain legal; explicit planned references and multiplicity, not inferred pairing. |
| **EF11 — ongoing** | Version/opportunity-aware analysis and complete portable reports. | Preserve denominators, not-viewed/unlocalized/invalid/not-fixated distinctions, censoring and participant/session/stimulus hierarchy. General crossed-stimulus inference is beyond current paired-condition inference. BWP09/BWP13. |
| **EF12 — ongoing** | Evidence-backed design catalog and actual researcher acceptance per supported family. | Separate authorable/deliverable/importable/analyzable/exportable statuses, exact citations/depth and operational defaults. BWP03/BWP15/BWP17. |

For full-family claims, test designing, releasing, collecting/importing,
analysing, exporting, cloning and reopening each supported profile. Acquisition,
scientific qualification and researcher usability remain distinct. The
[academic evidence contract](../methods/ACADEMIC-EVIDENCE-CONTRACT.md) requires
multiple applicable sources and actual option-specific review; references do not
supply universal sample sizes, durations, AOI margins or detector cutoffs.
