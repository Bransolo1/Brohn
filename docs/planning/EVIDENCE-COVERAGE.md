# Visual evidence, workflow coverage and capture protocol

## Version 0.2 gap-directed evidence

The audit adds official stills from Maze, Lookback, Alchemer, Inquisit, OpenSesame, PsyToolkit, EEGLAB, LabRecorder and BrainVision. The [gap register](GAP-REGISTER.csv) ties each finding to a proposed fix and evidence IDs. Search an ID or workflow keyword in the [atlas](UI-ATLAS.html); newly added records include gap tags. The original competitor matrix below is retained because new providers do not prove missing transitions inside iMotions or Tobii.

| Gap-directed workflow | Added visible evidence | What remains unproven |
|---|---|---|
| Preflight and readiness | Lookback setup/prechecks, capture/device configuration references | Expiration, exact hardware compatibility, calibration accuracy and recovery transitions |
| Questionnaire rehearsal/status | Alchemer test/preview and response state, in addition to Qualtrics builder/flow | Exhaustive paths for arbitrary inputs; accessible completion under assistive technology |
| Implicit task construction/debugging | Inquisit editor/watch, OpenSesame variable/error/category screens, PsyToolkit participant states | Scorer equivalence, measurement validity and full operator-to-analysis workflow |
| Signal preparation and acquisition | EEGLAB, LabRecorder and BrainVision screens | Automatic choices, synchronization accuracy and safe continuation after failure |
| Report handoff | Maze report audience/share controls | Immutable snapshot semantics, revocation behavior and our future authorization implementation |

The new evidence fills reference gaps, while the design documents fill specification gaps. Neither counts as implemented behavior or validated scientific performance. No additional video files were stored.

Captured/reviewed 5 September 2026. The atlas preserves source URL, source date/version when known, image dimensions, provenance and a local file. Vendor documentation screenshots prove what a screen looked like in that source; they do not prove current interaction behaviour. The original product concept is identified separately from competitor evidence.

## Coverage legend

**V:** a visible interface excerpt was inspected. **D:** supporting documentation was read. **P:** part of the workflow is visible, but not complete. **G:** a material gap remains. No score implies a competitor lacks the capability.

| Workflow | iMotions | Tobii Pro Lab | Implicit platforms | Qualtrics |
|---|---|---|---|---|
| Project/workspace creation | V/P tutorial and public references | V new-project manual | V Gorilla/RealEye | D/V editor context |
| Stimuli and trial setup | V tutorial | V stimulus/text/timeline | V Gorilla/PsychoPy | V question configuration; D/P media configuration |
| Questionnaire editor and types | V old editor + 2025 survey image | G not primary benchmark | D/V selected builder evidence | V official type/editor screenshots |
| Blocks, branching and randomisation | V/P tutorial grouping | D/V timeline/design-table concepts | V Gorilla experiment tree | V flow/branch/randomiser/piping |
| Device selection and readiness | V/P settings and sensor strip | D/P manual | D Labvanced LSL | Not the primary device benchmark |
| Calibration and recording | P; further controlled capture needed | P; missing full calibration-results/dashboard | D/P | Not the primary device benchmark |
| Replay and signals | V iMotions Lab/Online | D/P | V/P RealEye | Not a biosignal benchmark |
| Static/dynamic AOIs | V editor and examples | V/P text AOIs, tags, mapping | V RealEye + documentation | Not a gaze-analysis benchmark |
| Metrics, contrasts and reports | V/P metrics/export; configuration incomplete | V metrics and export panels | V/P dataset and AOI summaries | D/P; full reports not captured |
| Export / reproducibility | V/P tutorial and documentation | V export settings | V/P data views | D/P |
| Accessibility states | G hands-on screen-reader audit | G hands-on audit | D/P | V accessibility-check interface; G full audit |
| Errors, reconnection, job recovery | G | G | G | G |
| Permissions, concurrent edits, migrations | G | G | P version/commit UI | G |

## What the snippets support

They support comparison of layout, vocabulary, controls, state density and demonstrated workflow sequences. The full-resolution originals should be inspected from the atlas; contact sheets are navigation aids. Some snippets show only a panel, annotated example, stimulus or rendered analysis. Those kinds are labelled so they are not counted as complete operator screens.

Public materials vary in age. The Tobii manual acquired for this task identifies itself as 2026.06.04; depicted build numbers are not guaranteed. iMotions AOI-editor images describe version 9, while its release PDF is Fall 2025. Current documentation pages may reuse older images. Some PsychoPy images visibly date to 2024 and some Qualtrics reference images to 2021. The atlas must not be represented as an exhaustive 2026 interface capture.

## From observed pattern to original implementation

| Evidence pattern | Proposed implementation | Evidence required beyond screenshots |
|---|---|---|
| Project selector and module navigation | One study aggregate and five guided stages | Save/reopen, migration, recovery and access behaviour |
| Stimulus canvas with property inspector | Reusable local browser editor and typed stimulus schema | Keyboard interaction, coordinate transforms, undo and rendering performance |
| Trial tables / experiment trees | One validated protocol graph with plain-language summary | Randomisation semantics, block boundaries, unreachable-node linting |
| Question editor / survey flow | Typed question and flow model linked to trial events | Branch evaluation, missingness, versioning, export round trips |
| Sensor strip / recording control | Independent acquisition process and readiness checklist | Hardware qualification, clock drift, reconnect and crash tests |
| Replay timeline / metrics table | Shared time cursor plus versioned metric contract | Algorithm definitions, sample masks and alignment error |
| AOI editor, tags and aggregation | Geometry, semantic labels, exposure rules and revisions | Ground-truth annotation, overlap rules and metric-error benchmarking |
| Report or export panel | Reproducible bundle generated by the frozen analysis recipe | Independent reproduction and student comprehension testing |

## Hands-on gap-closing script

Run this with an authorised demonstration account and a synthetic study before claiming feature or workflow parity. Do not collect real participant data for UI benchmarking.

1. Create/reopen a project; record default navigation and empty state.
2. Add two images, one video and a questionnaire. Capture editor before and after each action.
3. Add repeated liking, a branch, a randomised block and a loop with embedded stimulus data; preview at least three paths.
4. Configure an available eye/EEG/EDA rig; capture discovery, disconnection, calibration, poor-quality feedback and successful readiness.
5. Run the prepared study; record operator/participant separation, timeline events and recovery from an interrupted session.
6. Inspect data quality; change one exclusion with a reason; observe whether results become stale.
7. Create static AOIs, copy a template, track a moving object and correct an occlusion or identity switch.
8. Calculate the same prespecified outcomes; inspect denominators, exclusions, uncertainty and missingness.
9. Export raw data, derived data, methods and reports; reopen the exported study on another machine.
10. Capture an accessible route through each screen: keyboard, visible focus, error association, screen reader and 200% zoom.

For each transition store: evidence ID; product/version; viewport; account/permission context; precondition; action; before/after snippet; visible feedback; resulting object/data mutation; action count; duration; accessibility notes; source/timestamp; uncertainty. Keep any protected/private content out of the public repo.

## Video policy

Only selected still screenshots and timestamped source links are retained. No MP4 files or full video downloads form part of this package. A sequence of sampled frames is not a claim that the whole video was watched in real time. Animated documentation assets are represented as still frames in the delivered atlas.

## Publication boundary

This reference library is for private product research. Public source code should contain original designs and links to vendor sources; screenshot redistribution requires its own rights decision. The clean repository plan excludes this evidence directory. Nothing has been published externally.
