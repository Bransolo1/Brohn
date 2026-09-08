# Two-team review: a simpler experience on a complete research engine

Version 0.2 · 5 September 2026 · planning and design revision

The UX team reviewed the first-study journey, accessibility, questionnaire behavior, recovery and comprehension. The biovital and implicit-methods team reviewed signal acquisition, scientific processing, behavioural protocols, data linkage and the full R application architecture. Their combined review produced **44 findings: 16 UX, 19 biovital/architecture and 9 implicit-method findings**. Several examine the same dependency from different perspectives; this is not a count of 44 independent missing features.

The plan now includes **150 distinct still-image references across 16 platforms**, with **34 new stills** collected for the review. The implementation backlog contains **238 candidate items**. Most audit proposals refine existing work; only eight new tickets were added. These are specifications and acceptance criteria, not completed features. The interactive concept demonstrates selected revisions using simulated values.

## What changed

| Review finding | Revised product behavior | Delivery evidence |
|---|---|---|
| Choices could change a heading while leaving the same analysis underneath | One compiled recipe controls materials, assignment, questions, readiness and analysis. Paired and independent designs produce their own result schema. Edits invalidate affected outputs. | UX-G01/G02; ARC-G01; updated concept and application contract |
| A clean sample always required an AOI decision | The prepared sample reaches Results without compulsory exception handling. Exception practice remains available separately. | UX-G03; concept demonstrates three primary activations from its initial Plan screen; the full home-to-report budget remains ≤5 and requires user testing |
| An AOI could need review while its report remained accessible as current | Decisions bind to artifact and policy revisions. Geometry edits and undo create new revisions; affected results become stale. Final publication waits for required decisions. | UX-G04; ARC-G05; concept exercises flag, accept, undo and blocked Results |
| A green device indicator did not define study readiness | Preflight records the participant, physical device/configuration, calibration, display geometry, permissions, clock evidence and storage. Relevant changes expire the relevant checks. | UX-G06; BIO-G01/G02/G03; acquisition contract |
| “Recording finished” could imply data and results were complete | Participant execution, capture, transfer, processing and review have separate states. A sealed run manifest records required streams, hashes, terminal sequences and gaps. | ARC-G02/G03/G04; runtime failure and recovery contracts |
| AOI dwell and usable sample size were underdefined | The proposed flagship uses **valid-gaze-time share**, with explicit eligible viewing window, validity/gap construction and aggregation. Report **B minus A** in percentage points. Fixation measures and TTFF remain separate. Each outcome has its own usable observations and exclusions. | BIO-G06/G07; UX-G10; IM-G08 |
| “BIAT” or “AAT” could hide consequential protocol differences | Method manifests pin protocol, input mapping, first/corrected latency, scorer, exclusions and score direction. Vendor-compatible import profiles remain distinguishable from paper-derived profiles. | IM-G01/G02/G03; exact protocol/scorer specification and fixture requirements |
| Questionnaire preview could suggest every possible path had been tested | Separate visual inspection from participant runtime rehearsal. Enumerate bounded fixtures; report representative/boundary checks and limits for unbounded inputs. Keep question/option IDs and answer history stable. | UX-G05/G08/G15; shared R/TypeScript expression contract |
| Sharing and collection completion were underspecified | End-of-participant differs from study finalization. A collection plan determines the report cohort. Reopened collection produces a new report snapshot; sharing grants specify audience, content, expiry and revocation. | UX-G12/G14; two new lifecycle tickets |

The sample concept also now removes liking from its flow and results when the question is disabled, changes the displayed comparison when assignment changes, draws the proposed label region around the label, and returns a pending-AOI user to the review action. These are original UI design changes, not competitor screenshots or evidence of a working backend.

## Frontend to backend decisions

The platform remains **R-first**. The technical plan assigns each runtime a concrete responsibility:

| Layer | Implementation direction | User-visible consequence |
|---|---|---|
| Researcher interface | Shiny, bslib and golem; reusable TypeScript canvas/flow/replay controls | Guided and advanced views edit the same study; accessible alternatives accompany scientific controls |
| Application authority | Plumber API and R domain/compiler services | Validated commands, conflict handling and immutable published protocols; UI state cannot silently become scientific truth |
| Participant execution | Independently served TypeScript runner, preloaded assets and local event journal | Stimulus timing and accepted responses do not depend on Shiny round trips |
| Lab acquisition | Local native/Python supervisor with qualified device adapters | Stable device identity, required-stream start barrier, disk spooling, markers and explicit reconnect behavior |
| Persistence | Service-managed SQLite/filesystem locally; PostgreSQL/object storage in shared mode | Recoverable saved studies and immutable data; the browser can close without becoming the data store |
| Processing | Durable jobs and separate R workers; qualified vision/EEG processes where needed | Automatic processing survives a UI restart, retries idempotently and reuses valid upstream work |
| Evidence and reports | Result manifests, frozen report snapshots, separate access grants | A number retains its inputs, method, uncertainty and exclusions; sharing does not silently change a conclusion |

The [application contract](ARCHITECTURE-CONTRACT.md) includes object schemas, proposed canonical endpoints, three sequence diagrams, screen-to-state mappings, publish transactions, clock/recording behavior, worker leases, local/cloud topology, plugin upgrades and failure acceptance cases. It takes precedence over shorthand endpoint examples in the team worksheets. The [R implementation plan](R-ARCHITECTURE.md) retains package choices, module boundaries and the longer engineering roadmap.

## Evidence added to close reference gaps

| Reference set | New stills | Design questions it informs |
|---|---:|---|
| Maze, Lookback, Alchemer | 13 | Report audience; setup/prechecks; questionnaire preview and response status |
| Inquisit, OpenSesame, PsyToolkit | 11 | Method configuration, variable inspection, source-linked debugging and participant instructions/trial states |
| EEGLAB, BrainVision, LabRecorder | 10 | Channel/interval quality, ICA/filter review, recording configuration, annotations and required streams |

The [atlas](UI-ATLAS.html) has collection filters and keyword/gap-ID search. Every added still has a source URL, local path, dimensions, hash and observation limits. The [gap register](GAP-REGISTER.csv) links findings to evidence and backlog IDs. The original 116 references and nine timestamped tutorial stills remain included. **No MP4 or other video file is stored in this package.**

These sources improve coverage of individual states. They do not establish every current authenticated transition, accessibility behavior, algorithm or competitor feature absence. The remaining controlled capture and benchmark work is explicit in [evidence coverage](EVIDENCE-COVERAGE.md). The plan borrows interaction lessons and specifies an original interface; it does not promise a pixel-for-pixel reconstruction.

## Delivery changes without duplicate promises

The eight new tickets cover collection finalization/reopening, report sharing grants, a later respiration pack, a recipe precision/trial-budget planner, reliability reporting, VAAST, timed intuitive association and named vendor behavioural imports. The [revision map](BACKLOG-REVISION-MAP.json) records which audit proposals strengthened existing tickets and which became new items. Linked acceptance requirements increase work; existing estimates must be revisited, rather than treating refinements as free.

The first twelve two-week sprints remain a **provisional vertical-slice sequence**, not a guarantee that the full platform fits into six months. Their detailed plan is in [UX and roadmap](UX-AND-ROADMAP.md). Foundation specifications come first; implementation, hardware integration and method qualification remain separate gates. Later releases extend the same study model instead of creating disconnected modules.

| Gate | Revised emphasis |
|---|---|
| G0/G1 foundations | Freeze study/method contracts, event/clock schemas, state transitions, accessibility behavior, reference fixtures and research scope |
| G2 vertical slice | Prepared eye + liking study, questionnaire core, static AOIs, deterministic analysis/reporting, named BIAT/AAT implementation; simulated/import-supported AAT is permitted here |
| G3 live rig | Eye, EEG, EDA and physical AAT integration; required-stream barrier, calibration, timing evidence and recovery |
| G4 qualification | Scientific reference checks, timing/hardware and modality-specific eligibility, novice comprehension, action budgets and reliable automatic analysis |
| G5 launch experience | Cohesive deployment, local access/backup, documentation, supportable guided workflows and controlled report handoff |
| G6/G7 expansion | Full IAT and other qualified implicit packs, shared/cloud operations, advanced research workflows and later physiological packs |

Minimum local access and backup/restore remain launch requirements. Expanded shared/cloud roles and operations remain later. Full IAT is consistently G6; it no longer appears as an accidental G2 promise. ECG/PPG/HRV and EMG were already planned at G7; respiration is now explicit there.

## What is ready and what still needs proof

**Ready for implementation planning:** reviewed UX direction, architecture contracts, method specifications, source-linked references, a traceable gap register and a deduplicated backlog. The updated sample interaction has been exercised for design invalidation, questionnaire removal, AOI review/undo and current-result gating.

**Still future work:** production code, actual hardware acquisition, numerical/scientific qualification, access-control testing, timing metrology, novice usability studies and matched competitor benchmarking. One draft BIAT profile explicitly retains an unresolved fast-trial denominator until independently reviewed against a scoring fixture; that profile must not publish as qualified. A market-leading experience is the target to test, not a result established by this dossier.

No GitHub repository has been published. The future repository should contain original code/assets and permitted fixtures; the third-party screenshot reference collection remains separate from the code licence.
