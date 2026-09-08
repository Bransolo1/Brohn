# UX team review: a coherent automatic research workflow

Review date: **5 September 2026**. Scope: STRATEGY, UX-AND-ROADMAP, QUESTIONNAIRE-BUILDER, UI-ATLAS, EVIDENCE-COVERAGE and the original interactive concept. The main issue is **state choreography**, not a shortage of named features. Preserve the ambitious holistic platform and its strong scientific/accessibility requirements; specify how a novice action changes the frozen protocol, collection evidence, review decisions and automatic report.

This audit identifies 16 actionable gaps/refinements. P1 means required before claiming the affected prototype or release workflow is qualified; P2 means an important refinement or later handoff. None is asserted to be a production incident: the current concept explicitly contains simulated values and no data collection. Status `specified` or `evidence_added` means a concrete improvement and/or new reference exists; **implementation and empirical validation remain open**.

The same five stages remain **Plan → Questions → Collect → Review → Results**. Preserve the clean sample ≤5 total activations / zero scientific decisions / ≤10 minutes; prepared real study ≤4 substantive design decisions and ≤12 total activations including file-chooser actions; next participant ≤4 software activations on a ready rig; zero analysis-configuration decisions from finalized data to the qualified report. Measure typing, physical fitting, consent/calibration duration, exceptions and actual collection separately. The budget is a testable target, not an observed result.

## Evidence and method

Reviewed source text and the exact concept in a local UTF-8 wrapper without changing the fragment. Browser reproduction: from Plan, activating the Results tab directly displayed the simulated paired report before any AOI acceptance. Source inspection additionally found no design/measure-checkbox handlers and a recipe handler that only swaps a heading. Do not interpret rendering artifacts from an unwrapped HTML fragment as product defects.

Added **13 original official UI stills**, visually inspected: Maze 3, Lookback 4, Alchemer 6. Selection was driven by missing sharing, preflight, preview and response-recovery contracts. OpenSesame evidence is being captured separately by the main review team and is deliberately excluded from this manifest. No video or animated GIF is retained. `outputs/evidence/v2-ux/manifest.json` uses paths relative to outputs and maps stills to the stable gap IDs below.

**Observed** means visible in the saved still or reproduced in our concept. **Documented** means stated in primary documentation. **Proposed** means our original design. A vendor still does not prove present-day transition behavior, accessibility, performance or feature absence. Alchemer response rows visibly date to 2018; current access dates do not make historical UI current.

The most useful new primary-source distinctions are: [Maze report sharing](https://help.maze.co/articles/7690642785-sharing-and-exporting-your-maze-reports) documents live report links and PDF limitations; [Maze study distribution](https://help.maze.co/articles/5879655153-sharing-your-unmoderated-study) distinguishes response tracking, shared devices and preview access; [Lookback PreCheck](https://help.lookback.io/en/articles/9833471-participant-precheck) distinguishes prior setup readiness from a guarantee of successful later collection. These motivate explicit contracts, not a claim that our product already outperforms them.

Alchemer contributes concrete [preview/test controls](https://help.alchemer.com/help/testing-your-survey), [test generation limits](https://help.alchemer.com/help/generate-test-responses), [logic evaluation](https://help.alchemer.com/help/getting-started-logic), [retained-input error feedback](https://help.alchemer.com/help/verify-two-textboxes), [response handling](https://help.alchemer.com/help/viewing-responses), and [accessibility diagnostics](https://help.alchemer.com/help/how-to-build-accessible-surveys). The survey supplement records their observed/documented distinctions in more detail.

## Shared frontend-to-R contract

The browser/Shiny view sends semantic commands; R domain services own validation, compilation, derivation and scientific analysis. Browser task execution and native acquisition do not wait for Shiny reactive round trips. Align with the architecture team's canonical objects: **StudyDraft → immutable CompiledStudyRevision; RunSession pins revision, allocation, mode and method registry; PreflightEvidence has fingerprints and expiry; ReviewDecision binds an artifact hash; AOIRevision is immutable; ResultCardManifest and ReportSnapshot pin their inputs; ShareGrant is separate.**

All mutation endpoint names below are proposed API contracts, not existing code. Use `expected_revision` compare-and-swap and idempotency keys for writes; a durable outbox delivers events. UI state is derived from persisted objects, never inferred from changed button text. Results may show clearly provisional unaffected cards, while final publication requires the required QC/review snapshot. Reconnection restores an event cursor and renders the saved state. The interface may remain Shiny/bslib with browser components; these contracts also support a later shell without rewriting the R scientific core.

## Priorities and exact improvements

### UX-G01 · P1 · One coherent recipe state across every stage

**Brief requirement:** A novice selects an appropriate common eye recipe and receives its correct automatic analysis.

**Present evidence:** The written plan correctly separates paired images, independent groups and multiple stimulus items. The concept recipe selector only changes the heading; design selection has no handler, while the result always describes paired records. This is an illustrative prototype contradiction, not a production-data finding.

**Baseline location:** `STRATEGY.md:31; UX-AND-ROADMAP.md:104; work/research-studio-concept.html:15,19,23` (line references identify the reviewed baseline; later integration may shift them).

**Proposed improvement:** Compile a selected recipe into materials requirements, allocation, questions, capabilities, AOI semantics, analysis and report cards. A target-search selection must replace the A/B rating flow and result schema. Either implement a qualified independent-groups recipe or render the option unavailable with a useful explanation. After collection, fork a changed design and retain old results as historical.

**Acceptance:** Changing each exposed recipe/design updates every dependent stage and its provenance. A two-group fixture cannot produce a paired-estimate card; reopening the draft retains the choice. Unsupported choices never appear to succeed.

**Frontend → R contract:** Action: Choose recipe or change assignment. Saved state: Draft edited; compiled revision invalidated; affected previews/results marked stale. Source of truth: `StudyDraft -> immutable CompiledStudyRevision`. API/event: `PATCH /study-drafts/{id} with expected_revision; POST /study-drafts/{id}/compile; study.compiled/study.compile_failed`. Failure/recovery: Keep the last valid compiled revision visible as historical; show a source-linked incompatibility and undo; never silently reuse its outputs.

**Evidence still missing:** Coherent interactive fixtures for paired images, search, video and independent groups; novice recipe-choice comprehension.

**New evidence IDs:** None; this is a baseline/prototype contract finding. **Status:** specified; implementation/validation remain.

### UX-G02 · P1 · Capability choices need a valid whole-study route

**Brief requirement:** Holistic eye, EEG, EDA, RT, physical AAT, named brief IAT, questionnaires and webcam mechanisms in one accessible system.

**Present evidence:** The plan stages qualification realistically. The concept presents independent Webcam, EDA, EEG and RT/AAT checkboxes without functional effects or required-device details; a checkbox does not define a brief-IAT or physical-AAT protocol.

**Baseline location:** `STRATEGY.md:13,140,158; UX-AND-ROADMAP.md:84,192–238; concept:17,23` (line references identify the reviewed baseline; later integration may shift them).

**Proposed improvement:** Use recipe-owned capability profiles, showing a plain-language purpose and required/optional signals. Resolve lab-eye versus webcam-eye, named behavioural task version/input mapping and expression annotations as distinct method choices. Show what becomes available in Results before accepting a change. Adding EEG/EDA introduces baseline/trigger/fit tasks inside Collect; no extra top-level stage.

**Acceptance:** Selecting a supported combined profile changes protocol events, preflight and report outcomes. Missing required hardware gives a specific remedy. An optional failed stream can continue only under the frozen partial-data policy, with affected cards identified. Webcam gaze never inherits lab precision qualification.

**Frontend → R contract:** Action: Select or extend capability profile. Saved state: Method plan and registry snapshot saved; preflight invalidated as needed. Source of truth: `CompiledStudyRevision.method_plan; RunSession.method_registry_snapshot`. API/event: `POST /study-drafts/{id}/capability-plan:validate; capability.plan_changed; preflight.invalidated`. Failure/recovery: Explain the precise unsupported combination and offer a supported profile or save draft; do not silently downgrade sensors or inference.

**Evidence still missing:** Qualified reference rig, webcam conditions and full multimodal novice/operator prototype; conditional method compatibility fixtures.

**New evidence IDs:** None; this is a baseline/prototype contract finding. **Status:** specified; implementation/validation remain.

### UX-G03 · P1 · Separate clean sample, exception practice and real creation

**Brief requirement:** First explained sample report in ≤10 minutes, ≤5 total activations and zero scientific configuration decisions.

**Present evidence:** The plan explicitly excludes compulsory review from a clean sample. The concept always displays one AOI exception, has no welcome/sample-versus-real fork and no actual asset-import control. Its five-stage walkthrough is not yet a measured first-value path.

**Baseline location:** `UX-AND-ROADMAP.md:37,74,104,245; concept:15–21` (line references identify the reviewed baseline; later integration may shift them).

**Proposed improvement:** Welcome offers Open sample and Create study. The sample can open a prepared report immediately with optional stage exploration; a separate Practice fixing a region scenario deliberately adds an exception. Create from sample clones design only and requires real assets/collection plan, clearly excluding sample recordings. Place context explanations beside the current decision, not in a compulsory tutorial.

**Acceptance:** Instrument the complete welcome-to-explained-report path at ≤5 activations, no compulsory review and zero science settings. Creating a real study cannot carry synthetic observations into live results. Measure understanding of gaze versus liking as well as elapsed time.

**Frontend → R contract:** Action: Open sample or create from sample. Saved state: Sample session created, or new real draft cloned without recordings. Source of truth: `RunSession.mode=sample; StudyDraft.clone_origin; ActionTelemetry`. API/event: `POST /samples/{recipe}/open; POST /studies:clone-design; sample.opened`. Failure/recovery: Offline sample loads bundled assets; interrupted sample can reset; unavailable dependencies produce one local repair action without losing the draft.

**Evidence still missing:** Eight–twelve formative novice sessions followed by a justified summative design; installation and hardware time measured separately.

**New evidence IDs:** None; this is a baseline/prototype contract finding. **Status:** specified; implementation/validation remain.

### UX-G04 · P1 · Review decisions must control affected artifacts

**Brief requirement:** Automatic AOIs with low-effort, accessible, scientifically defensible exception review.

**Present evidence:** The plan describes semantic and geometric review well. In the concept, Results opens before AOI acceptance (reproduced in browser), accept/undo only changes text, the drawn whole-package outline conflicts with the label-region description, and the coordinate table cannot edit geometry.

**Baseline location:** `STRATEGY.md:35,112; UX-AND-ROADMAP.md:91–92,122–174; concept:18,19,21,23` (line references identify the reviewed baseline; later integration may shift them).

**Proposed improvement:** Show the exact contested geometry over the relevant stimulus and a synchronized editable geometry table. Provide accept, edit, reject and defer with consequences. Bind decisions to artifact hashes and review policy. Permit explicitly provisional unaffected cards, but block final report publication until required review is complete. Withhold outcome contrasts during AOI correction; display stimulus content and relevant tracking evidence.

**Acceptance:** Accepting or editing a region creates a revision and reruns only dependent metrics. Undo marks dependent cards stale. A report with unresolved required review cannot be published. Keyboard rectangle/polygon changes match canvas geometry and survive reload.

**Frontend → R contract:** Action: Accept/edit/reject an AOI proposal. Saved state: AOI revision and attributed decision appended; dependent job state updated. Source of truth: `AOIRevision; ReviewDecision bound to artifact hash; ReportSnapshot eligibility`. API/event: `POST /aoi-revisions; POST /review-decisions; aoi.revised/review.decided; jobs.invalidated`. Failure/recovery: Compare-and-swap rejects a stale approval and opens the latest geometry; retry is idempotent; previous artifact and decision remain auditable.

**Evidence still missing:** Real geometry-editing prototype, transform fixtures, independent AOI benchmark and blinded-review usability test.

**New evidence IDs:** None; this is a baseline/prototype contract finding. **Status:** specified; implementation/validation remain.

### UX-G05 · P1 · Make preview modes and coverage honest

**Brief requirement:** Qualtrics-quality flow testing without contaminating automatic live analysis.

**Present evidence:** The baseline already requires isolated preview and actual-runtime checks. Q3 promises every reachable path without bounding free-text/numeric/repeated branches. The concept shows one static flow, not an executed branch. Official Alchemer stills demonstrate mode controls and test generation, not exhaustive correctness.

**Baseline location:** `QUESTIONNAIRE-BUILDER.md:68,96,132; UX-AND-ROADMAP.md:188; concept:16` (line references identify the reviewed baseline; later integration may shift them).

**Proposed improvement:** Default to Run as participant using the compiled runtime with simulated external effects. Inspect all content is a separate author mode and earns no runtime-coverage credit. A preview ledger records study hash, initial state, seed, exercised branches, input boundaries, failures and unsupported checks. Prove exhaustive paths only for finite bounded fixtures; show branch/outcome and selected-boundary coverage with declared limits elsewhere.

**Acceptance:** A finite two-branch fixture exercises all enumerated paths; an unbounded text rule reports representative checks and its limit. Inspect-all never turns failing runtime checks green. Sample/preview/pilot/live provenance is immutable and no simulated action changes live quotas or devices.

**Frontend → R contract:** Action: Run participant preview or inspect all content. Saved state: Mode-specific RunSession and trace saved; coverage tied to exact compiled revision. Source of truth: `RunSession; PreviewTrace; CoverageManifest`. API/event: `POST /run-sessions {mode, revision}; preview.trace_recorded; preview.coverage_updated`. Failure/recovery: Resume only compatible preview checkpoints; retain failing traces; source-linked unsupported checks remain visible rather than green.

**Evidence still missing:** Runner equivalence suite, custom-code coverage policy and novice comprehension of test versus live.

**New evidence IDs:** maze-study-link-settings, survey-02-preview-test-toolbar, survey-06-generated-test-responses **Status:** evidence_added; implementation/validation remain.

### UX-G06 · P1 · Readiness is current evidence, not one green status

**Brief requirement:** Rapid calibration and accessible permission recovery across lab and webcam collection.

**Present evidence:** The plan lists calibration, drift and unsupported firmware; the concept only shows prepared sample availability. Lookback documents useful pre-session checking and explicitly limits what a previous pass guarantees. Camera permission stills show a concrete participant-facing boundary.

**Baseline location:** `UX-AND-ROADMAP.md:82–86,116; STRATEGY.md:140; concept:17` (line references identify the reviewed baseline; later integration may shift them).

**Proposed improvement:** Collect separates protocol ready, consent ready, device connection, synchronization, signal quality, calibration and storage/transport. Hide irrelevant checks, explain each failing required check in one sentence, and expose one local repair action. Bind evidence to device/config/browser fingerprints and expiry. Camera permission is not calibration or emotion-model validity. Provide a participant preview of camera framing and clear local-processing/retention wording.

**Acceptance:** Changing camera, display geometry, device configuration or an expired calibration invalidates only relevant evidence. Denied camera permission, poor lighting and sensor loss each have an operable recovery route. A screen-share/microphone request appears only when required by the recipe.

**Frontend → R contract:** Action: Start setup, retry failed check or change device. Saved state: Individual evidence records pass/fail/expiry; session readiness derived. Source of truth: `PreflightEvidence keyed to RunSession and hardware/browser/config hashes`. API/event: `POST /run-sessions/{id}/preflight; preflight.check_completed/preflight.invalidated; device.connection_changed`. Failure/recovery: Preserve successful unrelated checks, show why a pass expired, reconnect through the adapter; do not manufacture continuity over missing data.

**Evidence still missing:** Actual browser/OS permission-denial tests, calibration-quality visualization and qualified hardware/lighting/fairness matrix.

**New evidence IDs:** lookback-ready-participants, lookback-camera-permissions, lookback-precheck-complete **Status:** evidence_added; implementation/validation remain.

### UX-G07 · P1 · Design the repeated participant cycle and interruptions

**Brief requirement:** ≤4 software activations for the next participant on a ready rig, including clear recovery.

**Present evidence:** Participant states and reconnect are already named; neither the concept nor the screen table specifies the exact handoff sequence, identity boundary, duplicate prevention or attempt policy. Maze shows shared-device link settings; Lookback shows a visible waiting/end state.

**Baseline location:** `UX-AND-ROADMAP.md:39,83–86,116; concept:17` (line references identify the reviewed baseline; later integration may shift them).

**Proposed improvement:** One Next participant action creates a fresh pseudonymous session and reuses only valid rig readiness. Present a short consent/comprehension and fit/calibration handoff, then start. Keep operator and participant surfaces distinct. On interruption show Saved up to trial X, what remains, and the permitted resume/repeat/stop actions. A repeat creates a new exposure/attempt linked to the original, never overwrites it.

**Acceptance:** A shared lab computer runs two distinct participants with no answer carryover. Browser reload during a trial follows the frozen resume policy without duplicate accepted responses or fabricated continuous biosignals. Next-participant software path meets ≤4 activations; physical/consent/calibration time is reported separately.

**Frontend → R contract:** Action: Next participant; pause/resume/repeat/end. Saved state: Allocation, consent version, checkpoint and attempt lineage persisted. Source of truth: `RunSession; ParticipantAllocation; ConsentRecord; ExposureInstance; EventLog`. API/event: `POST /run-sessions; POST /run-sessions/{id}/commands; session.paused/session.resumed/exposure.repeated`. Failure/recovery: Persist local acknowledged checkpoints; use idempotent commands and explicit gap events; an unsafe mid-trial resume routes to the declared stop/repeat policy.

**Evidence still missing:** Observed complete novice operator cycle, disconnect/reload failure injection and accessibility session handoff.

**New evidence IDs:** maze-study-link-settings, lookback-waiting-moderator **Status:** evidence_added; implementation/validation remain.

### UX-G08 · P1 · Question edits need local repair and failure rehearsal

**Brief requirement:** Accessible branching, piping, randomisation and questionnaire recovery with minimal expert intervention.

**Present evidence:** Lint, debugger and errors already exist in the plan. Missing precision concerns evaluation boundaries after moves, invalidated preview evidence and deliberate error-state testing. Alchemer image 01 is a retest advisory, not proof of a broken reference; image 04 shows retained values and linked errors.

**Baseline location:** `QUESTIONNAIRE-BUILDER.md:66–74,94,122,132; UX-AND-ROADMAP.md:186–188; concept:16` (line references identify the reviewed baseline; later integration may shift them).

**Proposed improvement:** After an edit, show affected dependencies beside the question/flow node and offer local repair or undo. Define when same-page, page-entry and submit conditions evaluate in our runtime. From Collect, rehearse required blanks, exclusive choices, numeric boundaries and cross-field failures. Retain entered values and link one summary to exact fields; expose diagnostics only when actionable.

**Acceptance:** Moving a source below a dependent node produces a specific compiler finding and invalidates only affected preview traces. Keyboard-only users recover from required, numeric and cross-field failures; accepted-answer timestamps remain distinct from failed validation attempts.

**Frontend → R contract:** Action: Move/edit question; run error rehearsal; submit invalid answer. Saved state: Draft graph revision, dependency impacts and validation attempt events saved. Source of truth: `QuestionGraph within StudyDraft; CompiledStudyRevision; ResponseEvent; PreviewTrace`. API/event: `PATCH /study-drafts/{id}/questions; compile.diagnostic; response.validation_failed/response.accepted`. Failure/recovery: Preserve values and focus destination; undo the structural edit; failed submissions do not become accepted responses or increment live completion.

**Evidence still missing:** Real sentence-logic editor, reference-impact fixture and assistive-technology error-recovery tasks.

**New evidence IDs:** survey-01-logic-reference-warning, survey-04-validation-errors, survey-06-generated-test-responses **Status:** evidence_added; implementation/validation remain.

### UX-G09 · P1 · An actionable automation queue with real recovery

**Brief requirement:** Massive end-to-end automation that removes manual analysis coordination.

**Present evidence:** The architecture correctly separates durable jobs from the interface. The concept queue is static text and accept changes it to queued without job state or failure/retry. The absent feature is a reviewable orchestration interaction, not an absent queue requirement.

**Baseline location:** `STRATEGY.md:110–112; UX-AND-ROADMAP.md:60,90,93,147–174; concept:18,23` (line references identify the reviewed baseline; later integration may shift them).

**Proposed improvement:** Use one study status summary: ready, collecting, processing, needs your decision, draft ready. Expand only current blockers into a source-linked action with cause, consequence and remedy. Distinguish retryable transport/worker failure from scientific review. Job progress remains visible after navigation/restart; completed work is retained and only stale dependencies rerun.

**Acceptance:** Kill a worker mid-analysis, reopen the app and retry once: one logical job result is published, previous completed stages are reused and no duplicate report appears. A missing question code opens its precise repair screen; a clock gap opens synchronized evidence.

**Frontend → R contract:** Action: Finalize collection, resolve review or retry job. Saved state: Job DAG status and durable event cursor saved; eligible report assembled. Source of truth: `JobRecord; ArtifactManifest; ReviewDecision; ReportSnapshot`. API/event: `POST /studies/{id}/analysis-jobs; GET /jobs/{id}; SSE job.progress/job.failed/job.completed`. Failure/recovery: Use idempotency keys and durable outbox; reconnect with last event cursor; retry only retryable steps and preserve the exact failure evidence.

**Evidence still missing:** Durable-job implementation, event reconnect tests, realistic processing latency and novice exception triage.

**New evidence IDs:** None; this is a baseline/prototype contract finding. **Status:** specified; implementation/validation remain.

### UX-G10 · P1 · Explain uncertainty and denominators per outcome

**Brief requirement:** Undergraduates understand automated results without mistaking gaze, facial output or EDA for preference/emotion.

**Present evidence:** The science plan correctly separates outcomes and exclusions. The concept has one shared 36-of-40 paired-record count attributed to eye QC beside both gaze and liking, leaving each denominator ambiguous; its 95% interval has no visible method. It says illustrative values, so these are renderer-contract gaps.

**Baseline location:** `STRATEGY.md:35,87; UX-AND-ROADMAP.md:94,137,192–238; concept:19` (line references identify the reviewed baseline; later integration may shift them).

**Proposed improvement:** Every result card contains the research question, operational outcome, participant/item denominator, units, estimate and interval type, inclusion rule, comparison design and qualification/review status. Expand How computed for versioned method/input lineage. Show no-lookers and censoring where TTFF is used, rather than silently dropping them. Explain attention, liking and optional AU/model annotations as separate observations; synthesize agreement/disagreement without a universal hidden score.

**Acceptance:** An eye-invalid but survey-valid session contributes only to eligible outcomes and both counts are shown correctly. TTFF fixtures retain non-lookers under the declared censoring model. A student can explain an interval crossing zero, an inconclusive result and expression-model uncertainty.

**Frontend → R contract:** Action: Open result card or explanation. Saved state: Per-outcome eligibility and immutable card manifest materialized. Source of truth: `ResultCardManifest; OutcomeEligibility; ReportSnapshot`. API/event: `GET /reports/{id}/cards; GET /result-cards/{id}/provenance; result.card_materialized`. Failure/recovery: Zero-eligible or failed-method outcomes show a reason and remedy, not zero effect; stale cards retain a historical label and cannot masquerade as current.

**Evidence still missing:** Outcome-specific rendering fixtures, statistical reference verification and comprehension evaluation with novice users.

**New evidence IDs:** survey-05-response-status-filter **Status:** evidence_added; implementation/validation remain.

### UX-G11 · P1 · Accessibility must operate the scientific controls

**Brief requirement:** Premium accessible flows including AOI alternatives, questionnaires and reports.

**Present evidence:** Accessibility requirements are strong in prose. The AOI table is read-only, matrix preview is absent and tab controls lack a complete roving-focus pattern in source. No current accessibility conformance is inferred from this source audit or the Alchemer diagnostic still.

**Baseline location:** `UX-AND-ROADMAP.md:91,186,243–249; QUESTIONNAIRE-BUILDER.md:48,122; concept:15–23` (line references identify the reviewed baseline; later integration may shift them).

**Proposed improvement:** Implement one keyboard route through Plan to Results, editable numeric/polygon AOI geometry, labelled targets and synchronized focus. Generate matrix row/anchor narration from stable question/option IDs; table and stacked alternatives preserve answers and direction. Results supply text/table equivalents of charts, visible focus and accessible downloaded output. Do not detect assistive technology to silently alter measurement conditions.

**Acceptance:** On the declared supported keyboard/screen-reader/browser matrix, a participant answers a reversed-anchor matrix, corrects an error and changes layout without answer mutation; a researcher edits an AOI and traces a result. Test reflow/zoom, focus restoration and error announcements through complete tasks.

**Frontend → R contract:** Action: Navigate, edit geometry, change question layout or open report. Saved state: Same semantic answers/geometry saved; presentation preference separate. Source of truth: `QuestionDefinition IDs; ResponseEvent; AOIRevision; UserPresentationPreference`. API/event: `PATCH /user-preferences; POST /aoi-revisions; response.accepted; UI focus follows acknowledged semantic operation`. Failure/recovery: Recover focus at the affected item after re-render; preserve input on failure; fallback representation never changes scoring or answer IDs.

**Evidence still missing:** Real AT users and independent task-based accessibility audit; diagnostics alone are insufficient.

**New evidence IDs:** survey-03-accessibility-diagnostics, survey-04-validation-errors **Status:** evidence_added; implementation/validation remain.

### UX-G12 · P2 · Define the collection-plan decision and finish boundary

**Brief requirement:** A real study needs at most four substantive design decisions and an automatic report without post-hoc model shopping.

**Present evidence:** Collection plan is already one of the four declared decisions, but its visible fields, instructor defaults and finish/pause/reopen semantics are not concrete. A student could otherwise confuse an available draft result with permission to stop sampling.

**Baseline location:** `STRATEGY.md:31,81; UX-AND-ROADMAP.md:39,104; concept:15,17,21` (line references identify the reviewed baseline; later integration may shift them).

**Proposed improvement:** Make collection plan a compact card within Plan: instructor/lab preset, target/rationale, recruitment/eligibility and declared stopping rule, with method-specific detail disclosed when needed. Treat Pause recruitment, End participant and Finalize collection as distinct actions. Show interim status without encouraging outcome-driven stopping; changing a frozen stopping rule creates an attributed protocol amendment.

**Acceptance:** A tutor preset requires no extra scientific configuration; a real study records the chosen plan before collection. Finalize automatically triggers the frozen analysis. Reopening collection creates a new report snapshot and visibly preserves the prior conclusion/date.

**Frontend → R contract:** Action: Confirm collection plan; finalize or reopen collection. Saved state: Plan frozen with study revision; collection lifecycle transition saved. Source of truth: `CompiledStudyRevision.collection_plan; CollectionState; ReportSnapshot`. API/event: `POST /studies/{id}/collection:finalize; collection.finalized/collection.reopened`. Failure/recovery: Explain unresolved session/upload/review dependencies; permit an explicitly provisional draft, preserve prior snapshots, and retry finalization idempotently.

**Evidence still missing:** Recipe-specific sample-planning content, study-design expert review and novice stopping-rule comprehension.

**New evidence IDs:** None; this is a baseline/prototype contract finding. **Status:** specified; implementation/validation remain.

### UX-G13 · P2 · Turn tutor and commercial collaboration into precise handoffs

**Brief requirement:** Student independence plus commercial reusable research without duplicating project formats.

**Present evidence:** Pinned course recipes and permissions are mentioned, but author/participant/reviewer handoffs, a feedback request and merge/conflict experience are not designed. Optional review must not add compulsory approval clicks to every novice sample.

**Baseline location:** `UX-AND-ROADMAP.md:54,95–98; QUESTIONNAIRE-BUILDER.md:134; STRATEGY.md:156–164` (line references identify the reviewed baseline; later integration may shift them).

**Proposed improvement:** A tutor or research lead distributes a pinned recipe revision and method profile. Students/team members create attributed drafts with their own data boundaries. Request feedback links to a specific revision and unresolved decisions. Review comments refer to objects/regions/questions. A new upstream recipe offers an impact comparison; it never silently upgrades active sessions. Role-based publishing can be enabled by workspace policy.

**Acceptance:** Two users edit the same question: no silent overwrite, a focused conflict shows both values and a safe resolve path. A tutor template update leaves active sessions pinned. A student can reproduce their report independently after receiving object-linked feedback.

**Frontend → R contract:** Action: Use pinned recipe, request feedback or resolve edit conflict. Saved state: Fork lineage, object comments and permission policy recorded. Source of truth: `StudyDraft; RecipeRevision; ReviewThread; WorkspacePolicy`. API/event: `POST /recipe-revisions/{id}/fork; POST /review-threads; study.edit_conflict`. Failure/recovery: CAS returns conflict with retained local draft; feedback remains on its referenced revision; no unapproved migration of active protocols.

**Evidence still missing:** Role-specific prototype, concurrent-edit tests and novice/tutor/commercial-team handoff study.

**New evidence IDs:** None; this is a baseline/prototype contract finding. **Status:** specified; implementation/validation remain.

### UX-G14 · P2 · Sharing needs an audience and snapshot contract

**Brief requirement:** Accessible comprehensible deliverables for undergraduate assessment and commercial stakeholders.

**Present evidence:** The plan specifies reproducible export and the concept only lists bundle contents. It does not yet show who can access a report, whether it changes with new participants, or how to revoke a link. Maze supplies actual audience/export UI and documents live-report behavior; our design should make this choice explicit.

**Baseline location:** `UX-AND-ROADMAP.md:95,302; EVIDENCE-COVERAGE.md:metrics/export rows; concept:19,23` (line references identify the reviewed baseline; later integration may shift them).

**Proposed improvement:** Results offers Download bundle and Share report. Default sharing is a qualified immutable snapshot with a clearly selected audience; optional live reporting names its changing-data behavior. Preview shows exact included report/data/media and privacy transformations, with raw face/video off unless deliberately included under the study policy. A share panel lists active grants and revoke. PDF states which interaction is replaced by tables or omitted.

**Acceptance:** A recipient sees the declared snapshot version and no unauthorized raw media. New responses do not alter a frozen snapshot. Revocation removes future access; export retries preserve one content-addressed bundle. A provisional result cannot acquire a misleading final share label.

**Frontend → R contract:** Action: Share, download or revoke. Saved state: Qualified snapshot and separate access grant/export job saved. Source of truth: `ReportSnapshot; ShareGrant; ExportManifest; JobRecord`. API/event: `POST /report-snapshots; POST /share-grants; DELETE /share-grants/{id}; export.completed`. Failure/recovery: Failed bundle creation retains retryable job state; expired/revoked links show a useful status without disclosing study contents; no hidden fallback to public access.

**Evidence still missing:** Authenticated authorization tests, accessible report/export audit and recipient comprehension of snapshot versus live.

**New evidence IDs:** maze-report-sharing, maze-report-download **Status:** evidence_added; implementation/validation remain.

### UX-G15 · P1 · Separate correction, participant replay and response eligibility

**Brief requirement:** Questionnaire answers and biovital exposure history remain correctly linked through edits and incomplete sessions.

**Present evidence:** Answer revisions and back-navigation policy already exist in the baseline, but researcher correction versus participant return is not specified as a user-facing choice. The official Alchemer response documentation distinguishes edit routes; its status screen shows parallel classifications. We should define our own explicit semantics.

**Baseline location:** `QUESTIONNAIRE-BUILDER.md:94–96; UX-AND-ROADMAP.md:83,188; concept:19` (line references identify the reviewed baseline; later integration may shift them).

**Proposed improvement:** Store origin, progress, QC and per-outcome eligibility separately. A researcher correction appends an attributed reason and a before/after analytic-impact panel without inventing exposures. Participant return reevaluates the frozen runtime, marks answers superseded by a path change, and records new exposures as new instances. Keep original paths visible and external side effects idempotent.

**Acceptance:** A submitted response with optional blanks remains submitted. A partial run contributes only under outcome eligibility rules; a synthetic run never enters live N by accident. Correction preserves original exposure history and invalidates affected cards; participant back-navigation logs actual new exposures without duplicating actions.

**Frontend → R contract:** Action: Correct response or return to earlier participant node. Saved state: Attributed response revision/path events and eligibility recalculated. Source of truth: `ResponseEvent; ExposureInstance; RunSession; OutcomeEligibility`. API/event: `POST /responses/{id}/corrections; runner.navigate_back; response.corrected/path.reevaluated; jobs.invalidated`. Failure/recovery: Show affected downstream answers before correction; preserve original accepted values and exposures; prohibit unsupported runtime rewind with a plain-language explanation.

**Evidence still missing:** Correction/replay fixtures with conditional liking and randomized exposure; policy review for timing-sensitive repeated tasks.

**New evidence IDs:** survey-05-response-status-filter, survey-02-preview-test-toolbar **Status:** evidence_added; implementation/validation remain.

### UX-G16 · P2 · Make the evidence atlas answer workflow questions

**Brief requirement:** Holistic competitor understanding sufficient to plan reconstruction, with honest remaining gaps.

**Present evidence:** The atlas supports platform/text filtering, still-image detail and provenance; coverage correctly labels gaps. However, a reader cannot directly traverse a task from before-state to action to after-state or filter evidence by recovery/accessibility/transition coverage. Public screenshots cannot justify complete product-replica or superiority claims.

**Baseline location:** `UI-ATLAS.html:filter and modal scripts; EVIDENCE-COVERAGE.md:8–28,46–61` (line references identify the reviewed baseline; later integration may shift them).

**Proposed improvement:** Add a task-first view for create, branch/preview, readiness, recover, AOI review, analysis and share, keeping platform as a secondary filter. Each evidence card distinguishes observed still, documented behavior and proposed design, with date/build uncertainty. Link missing transitions to a capture task and UX acceptance criterion. Store paired before/after evidence and actions when authorized live benchmarking becomes available.

**Acceptance:** Selecting Calibration recovery shows only relevant evidence and explicit missing transitions. All 13 new stills resolve locally with source provenance and observation limits. No count of screenshots is reported as a count of proven workflows; user-created concept is visibly separate.

**Frontend → R contract:** Action: Filter by task or open evidence detail. Saved state: Evidence metadata and gap links versioned; no research-study state mutation. Source of truth: `EvidenceManifest; UXGapRegister`. API/event: `Static manifest schema + build-time validation; evidence.coverage_updated`. Failure/recovery: Missing image/source is reported in the build; UI retains descriptive metadata and gap status; do not replace absent behavior evidence with an invented screenshot.

**Evidence still missing:** Authorized current-version transition capture, objective action/time measurements and real accessibility tests.

**New evidence IDs:** maze-report-sharing, survey-04-validation-errors, lookback-camera-permissions **Status:** evidence_added; implementation/validation remain.

## Delivery sequence and usable exit evidence

1. **Foundation / G0:** settle G01–G02, G05, G07–G09 and G15 object/event contracts while UI, R compiler and acquisition spikes run in parallel. Add frozen recipe and origin/eligibility fixtures before accumulating screens.
2. **First guided vertical slice / G1–G2:** implement G03 clean sample and real fork, G04 hash-bound AOI review, G10 outcome cards and G11 accessible controls together. Demonstrate both the zero-exception path and one complete exception/recovery path. Update every live control in the concept or visibly mark it unavailable.
3. **Integrated collection / G3:** prove G06–G07 on the actual eye/EEG/EDA/task reference rig and the separately qualified webcam route. Questionnaire responses share the same exposure/time schema. Import-only demonstrations remain intermediate milestones.
4. **Qualification and supported release / G4–G5:** close measured novice completion/comprehension, method/AOI/hardware verification, questionnaire boundary coverage, crash recovery and accessible report tests. Add G12 finalization semantics and G14 qualified sharing/export. G13 advanced collaboration can mature by deployment need; course recipe pinning is earlier.
5. **Evidence maintenance / ongoing:** G16 links each workflow claim to a still, documented behavior, executed contract test or observed user task. New competitor imagery improves design evidence; it never substitutes for our implementation/validation gate.

The accompanying CSV contains issue-sized additions only; it does not replace the 230-row master backlog, renumber dependencies, or turn a multi-team programme into a fixed serial sprint estimate. Existing requirements should be refined in their current epics during integration, not duplicated as a second independent subsystem.
