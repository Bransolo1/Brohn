# Architecture and method readiness

**Initial review retained:** the [master architecture](../MASTER-ARCHITECTURE.md)
and [large-build readiness](LARGE-BUILD-READINESS.md) now govern implementation.
Their capability, tool and evidence records supersede candidate/unresolved status
in this earlier review. Later preparation exercised isolated SDK/model references
and resolved the selected BIAT denominator; product integration and physical/human
qualification remain open.

Reviewed 2026-09-08 against executable R modules, current contracts and the
selective planning archive. This is preparation for a larger implementation,
not evidence of new functionality or scientific qualification. No SDK, model,
hardware or participant validation was performed in this review.

The R-first architecture remains appropriate: R owns study semantics, quality
rules, scoring and analysis; Shiny/bslib owns the researcher workflow; a separate
browser runner owns participant presentation and response capture; isolated
services own acquisition and long jobs. No frontend rewrite is required to
start. Preserve these boundaries while implementing larger, integrated waves.

## Five critical findings

1. **The shared execution contract is the next dependency.**
   `R/protocol.R` generates exactly two planned trials/exposures and viewing/liking
   phases. `R/records.R` requires nonempty context IDs but does not resolve them
   against that registry; sessions have no protocol hash and every lifecycle
   dimension must remain `not_started`. Bind sessions and observed events to a
   frozen protocol before execution. Separate planned node IDs from realized
   presentation instances so repetitions, practice retries, branching and resumed
   sessions cannot collide. Version the schema and migrate old drafts explicitly:
   current validators reject unknown fields, so adding fields in one component
   without coordinated R/browser/wire changes will break portability.

2. **The existing prepared CSV is a bounded analysis input, not the future
   multimodal storage format.** `R/analysis.R` accepts participant/stimulus/time/
   coordinate/validity/phase columns, with no run, exposure, stream or clock keys.
   Do not reuse it to join repeated trials, ratings, EEG and EDA. Introduce a
   run manifest, typed channel descriptors and immutable recording objects;
   preserve raw bytes, source units, source clocks, acquisition configuration,
   calibration, gaps and adapter identity. Every derivative needs input hashes,
   mapping/recipe/AOI revisions, parameters, masks and software environment.
   Preserve decimal-string timestamp precision across JSON and test explicit
   int64 conversion at the columnar boundary. A source hash detects byte changes;
   it does not establish how recording occurred.

3. **Durable allocation, recording and processing must precede automation.**
   Local draft/report saves are useful but do not implement event ACK/retry,
   recording finalization, queue leases or crash recovery. Persist assignment
   atomically, including allocation algorithm/version, seed, realized order and
   reservations; preview must not consume live allocations. Define independent
   execution/capture/transfer/review transitions and evidence needed to complete
   each. A job must use frozen inputs, an isolated work directory, durable status,
   idempotency key and validated output-manifest promotion. Async Shiny work or a
   computation DAG alone cannot satisfy those lifecycle requirements.

4. **Questionnaires need an execution and linkage engine, alongside authoring.**
   Current support is one seven-option liking item and response-state snapshots,
   not committed answers or a general survey. Implement typed questions, safe
   declarative branches, immutable question/option revisions, presentation IDs,
   answer revisions and distinct onset/interaction/change/commit events. Join an
   answer through its declared run/exposure/stimulus referent; an AOI-specific
   question must explicitly name the AOI revision/window. Session demographics
   may have no stimulus referent. Preserve not shown, declined, skipped,
   unanswered and answered states as appropriate. Define back-navigation and
   dependent-answer invalidation. R validation, browser execution and preview
   must agree on branch/validation fixtures before a large type library grows.

5. **Scientific and usability gates must remain independent of feature count.**
   The only implemented method is
   `aoi-valid-gaze-time-share/0.1.0-draft`; there is no qualified raw preprocessing,
   fixation pipeline or inference. The archive still identifies an unresolved
   BIAT fast-trial denominator and physical AAT scoring profile. Freeze protocol,
   runner and scorer versions before operational method cards. Specify each
   recipe's control, baseline, practice/retry, attention-check, randomization,
   exclusion and contrast rules. Measure undergraduate task success and
   comprehension early; the completed browser checks are not formative testing
   or a formal accessibility audit.

## Implementation waves and integration gates

These are larger delivery units containing small reviewable changes. A later
usage reset permits more engineering work; hardware access, independent method
references and human testing still determine which gates can actually close.

| Wave | Integrated deliverable | Required exit evidence |
|---|---|---|
| 1. Common execution and provenance | Protocol binding, realized instance IDs, phase/event vocabulary, channel/run/object manifests, clock mapping records and schema migrations. Keep the current paired study as the first executable recipe. | Old drafts/reports remain readable; R/browser round-trip fixtures preserve values; unknown/stale references fail; two repeated exposures cannot merge; reset/drift/gap fixtures preserve original clocks and explicit unmapped intervals. |
| 2. Runnable study and recovery | Separate preloaded participant runner, persistent assignment, event journal/receiver, truthful run states and the first committed liking response. Add typed question/branch foundations and browser-independent domain fixtures. | Frozen two-image protocol runs and replays into R; focus loss, asset failure, reload, duplicate delivery and disconnect produce explicit outcomes; retry preserves assignment and answer identity; interrupted timed trials follow a declared policy. Software timing evidence remains labelled as such. |
| 3. Automatic first eye-study pipeline | One specified eye export adapter, calibrated coordinate transform, raw-to-prepared processing, manual AOI metric recipe, linked liking table, durable analysis job and reproducible report. Retain the existing prepared CSV importer separately. | Named reference file reproduces expected units/coordinates/validity and independent metric fixtures; app restart restores job/result state; crash/cancel/retry cannot publish partial outputs; missing eye data does not erase valid ratings; keyboard/reflow/focus checks plus formative undergraduate sample-to-own-study evidence. |
| 4. Parallel method slices | EEG and EDA reference imports/recipes; RT, reviewed BIAT and AAT input/scoring profiles; core questionnaire types/flow; webcam capture/geometry/gaze prototypes. All consume Wave 1 manifests and Wave 3 jobs/results. | Each slice has a frozen method manifest, independent numerical reference, QC/missingness semantics and an end-to-end report; branch/response parity passes; input-specific timing requirements are declared. Unresolved BIAT/AAT decisions block those operational scorers, not unrelated slices. |
| 5. Integrated live rig | One named eye/EEG/EDA/response-device configuration, authenticated local sidecar, calibration/preflight, synchronization explorer and concurrent collection with questionnaires/implicit blocks. | Physical onset/trigger and cross-clock measurements on the actual rig; disconnect, clock reset, disk-full and service-restart tests; complete raw-to-report provenance. Simulator success cannot close this gate. Webcam is qualified for its own camera/display/protocol profile. |
| 6. Automation and release qualification | AOI proposals/review, frozen statistical recipes, exception routing, historical analyses, reproducibility packaging and integrated study report. AOI work can begin after Wave 3 geometry/provenance stabilizes. | Blinded AOI reference benchmark and correction audit; inferential fixtures respect participants/stimuli/repetitions and denominators; scientifically reviewed multimodal pilot; independent undergraduate completion; clean-machine restore/install and backup recovery. Publish only the measured support matrix. |

Begin reference-rig/SDK feasibility and exact BIAT/AAT specification work during
Wave 1. Begin formative testing of the existing guided sample immediately rather
than waiting for Wave 6. The critical path is shared contracts → persisted runner
and jobs → reference-data eye workflow → integrated modality evidence; broader
device and question catalogues should build on that path.

## Rules that the waves must preserve

- **Timing:** calculate RT from appropriate observations in one qualified
  monotonic domain, never Shiny/network round trips or UTC subtraction. Preserve
  intended onset, browser callback, marker send/receive and measured physical
  onset separately. Clock mappings need anchors, validity intervals, drift,
  residual/uncertainty information and revision IDs. Unknown alignment stays
  unknown; LSL availability alone does not qualify the complete rig.
- **Method windows:** passive viewing, explicit evaluation, motor response,
  instructions, practice and rest/baseline are distinct. EEG requires named
  montage/reference/units/filter/epoch rules; EDA requires placement, conductance
  units, artifact/baseline/response-window and overlap rules. Rapid implicit
  trials are not automatically isolated EDA responses. Physical AAT onset,
  completion, trajectories and neutral calibration differ from keyboard proxies.
- **Webcam interpretation:** keep visibility, geometry/blendshapes, estimated
  gaze, named AU estimates, model expression scores and self-report distinct.
  Frame capture time differs from inference completion. Preserve model/calibration
  identity, quality masks and missing frames. A face estimate is not measured
  emotion, and a model confidence value is not calibrated psychological certainty.
  Raw-video retention is a declared study policy; derived-only retention needs
  provenance and an explicit limit on later reprocessing.
- **Novice workflow:** preserve Plan → Questions → Collect → Review → Results.
  Qualified course/recipe defaults own technical processing choices; expose
  meaningful research decisions and actionable exceptions. Keep keyboard
  equivalents for AOIs and question controls, text/table access to plots and
  correct focus during branching. Show provisional versus final results and
  planned versus observed deviations. Usability targets remain targets until
  measured with representative students.

## Focused tooling experiments

These are investigations of candidates already discussed in the archive, not
fresh claims about current versions or licences and not an installation request.
Pin and verify exact artifacts before adoption.

| Candidate | Small experiment that settles an architectural decision |
|---|---|
| jsPsych | Consume one frozen protocol in a separate runner; log frame callbacks, focus loss and response events into the canonical journal; replay the same fixture in R. |
| SQLite metadata service + targets/crew | Demonstrate one leased persistent job and allocation reservation, process termination/restart, cancellation and atomic artifact publication. Keep queue state outside the DAG. |
| Arrow/Parquet with optional DuckDB reads | Round-trip modality channel types and large timestamps through R and a sidecar; read a bounded viewport without loading a whole recording. Keep transactional job writes in metadata storage. |
| LSL and conditional BrainFlow/vendor SDK | Use synthetic/playback sources to test the process adapter, clock resets and gaps; separately confirm named-device/OS/SDK feasibility before installation or qualification claims. |
| eegUtils, with isolated MNE/NeuroKit2 comparators where needed | Reproduce one named EEG/EDA reference pipeline and document method-specific tolerance, units and exclusions. Choose only the workers the selected recipes require. |
| MediaPipe Face Landmarker and a separately assessed webcam-gaze adapter | Test timestamp/model/quality fields and worker isolation; assess gaze calibration independently. The archived WebGazer, Py-Feat and OpenFace notes identify maintenance/model-licence questions requiring current verification before adoption. |

Evidence basis: [active contracts](../CONTRACTS.md),
[control design](../methods/CONTROL-DESIGN.md),
[R architecture and source register](../planning/R-ARCHITECTURE.md),
[questionnaire semantics](../planning/QUESTIONNAIRE-BUILDER.md),
[implicit-method review](../planning/IMPLICIT-METHODS-REVIEW.md),
[webcam measurement boundaries](../planning/WEBCAM-EMOTION-ATTENTION.md),
and [open gates](../KNOWN-GAPS.md). External references in those documents are
archival evidence; this review did not refresh their availability or terms.
