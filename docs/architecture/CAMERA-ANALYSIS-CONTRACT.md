# Camera recording to optional automatic facial analysis

Status, 24 September 2026: policy 1.1 is now connected to researcher settings, participant named agreement, original capture publication, automatic native queue, source guards and saved-report access. Existing geometry/retain-only policies preserve their original meaning. Loaded integration has 13 passing checks over real receipts and two guarded assemblies; joined connected acceptance has 17 completed browser groups including seven clean accessibility/reflow scans, plus six independent native-reference checks. The optional pipeline is delivered; the wider platform and empirical validity are not declared complete. See [acceptance evidence](../qa/CAMERA-FACIAL-AUTOMATION-ACCEPTANCE.md) for the exact qualified scope and retained failures.

## Researcher and participant flow

The researcher chooses one action after recording: retain the source, process local face geometry, or process local facial action units and native expression categories. Choosing facial analysis reveals the exact recording-relative window, explicit frame stride and support-gap setting. It also shows the named participant notice, optional runtime readiness and the estimated analysed-frame budget. There is no silent resampling or replacement with a different model.

The existing participant camera setup presents the researcher's recording and retention information plus the registered named processing notice. Its existing affirmative camera agreement covers both recording and that displayed processing. A second redundant consent button is unnecessary. Declining records both choices as false. The frozen policy digest is echoed with the decision; this is evidence of the displayed version, not a claim that hashing creates permission.

After a durably completed participant session and supported completed recording, assembly saves the original source, observations, decoder evidence and policy. The same qualified native facial pipeline is queued automatically with the original dataset revision and settings. The researcher opens its ordinary report from the recording/session. Pending assembly, unsupported source, failed optional setup or native processing limits must remain visible with the relevant retained source or job action. Receiving the participant's source must not depend on a successful optional analysis.

## Policy and request contract

Existing `brohn-camera-policy/1.0` fields and meaning remain unchanged, including `none` and `face_geometry_v1`. New `brohn-camera-policy/1.1` is only for `facial_au_expression_pyfeat_v1`. It retains every recording field and adds:

| Field | Contract |
| --- | --- |
| `analysis_settings` | `brohn-camera-facial-settings/1.0`: exact decimal-string `start_s`; exact decimal-string or null `end_s`; integer `frame_stride` 1-120; native-supported numeric `max_support_gap_s` |
| `analysis_notice` | Exact registered plain-language notice returned by `brohn_camera_analysis_notice()` |
| `analysis_policy_hash` | Canonical SHA-256 of the entire frozen policy except this hash field, including original recording/retention wording and all processing settings |

The start request retains all existing fields. For policy 1.1 only, it additionally contains `analysis_consent`, equal to the existing logical `consented`, and the exact `analysis_policy_hash`. Old receipts without these fields remain valid. Adding them retroactively to a policy 1.0 receipt is refused. The full original policy already travels in the immutable camera start, frozen study/protocol, assembly and source provenance.

The registered notice says the local models estimate 20 action-unit and seven native category scores, do not establish feelings/attention/liking, and have identity/gaze/pose disabled. Only eligible completed recordings enter automatic processing. Retention remains governed by the displayed recording information. This follows the existing [facial model contract](../methods/FACIAL-AU-NATIVE-PROFILE.md); no new model or psychological measure is introduced.

Planning uses the declared duration and frame rate, adds two boundary frames and applies the explicit stride. A plan over 300 selected frames must be shortened or assigned a larger explicit stride. The actual worker independently uses encoded original PTS and its own 2-300-frame limit. The estimate does not guarantee that a browser delivered its requested frame rate, enough frames or enough single-face support. A nominal sample interval above the support gap must be explained: native frame means may exist while a time-weighted result has no supported adjacent interval.

## Loaded helper API

`R/platform-camera-analysis.R` depends on existing capture validators, the facial mapping helpers and core canonical hashing. It is loaded after capture in the application and included in supervised camera/backup child identities.

| Function | Result/purpose |
| --- | --- |
| `brohn_camera_analysis_settings(start_s,end_s,frame_stride,max_support_gap_s)` | Typed settings without altering authored decimal strings |
| `brohn_camera_analysis_policy(base,settings)` | New prospective policy 1.1; original `base` stays unchanged |
| `brohn_camera_analysis_validate_policy(policy)` | Recording limits, exact window, supported settings, registered notice, current digest and planning bound |
| `brohn_camera_analysis_validate_ack(policy,request)` | Matching original policy and one affirmative/negative camera choice |
| `brohn_camera_analysis_budget(policy)` | Explicit planning estimate and nominal adjacent-interval support |
| `brohn_camera_analysis_metadata(capture)` | Frozen native mapping, source explanation and bounded permission statement referencing original policy/protocol |
| `brohn_camera_analysis_eligibility(run,capture,publication=NULL)` | `{eligible,code,reason,action}`; expected pending/ineligible states have an actionable explanation |
| `brohn_camera_analysis_source(run,capture,publication,dataset,mode)` | Typed full source authority, with `automatic` or `manual` mode; fails on changed identities or source evidence |

The final function checks original project, study revision, release, design, protocol, run, participant, capture receipt, published assembly, source hash/bytes, original policy and complete retained artifacts. Its authority contains exact dataset/publication revisions and hashes, permission/settings/source hashes, original outcomes and every source object reference to hold through processing/publication. It is a pure validator: it does not itself establish store access, read artifacts or acquire file guards.

## Original agreement versus later attestation

Automatic processing requires an original policy 1.1 positive named decision, raw participant status `completed`, transfer `saved`, capture status `completed`, observed container end, supported assembly and the original dataset revision 1 with exactly factory-derived settings. A researcher-confirmed session resolution cannot rewrite raw completion for this automatic route.

Manual reviewed analysis remains available for policy 1.0 geometry/retain-only recordings when a researcher separately documents facial-processing permission. The authority records `permission_kind=researcher_attestation` and preserves the original policy. It never calls that later statement original participant permission. Original matching policy 1.1 metadata records `original_named_participant`. Revised settings requiring a separate statement cannot pass by copying the generated original statement verbatim. Neither path overrides a declined/withdrawn source or existing access/withdrawal controls.

The store resolver also consults received participant-ending evidence and any source-bound session resolution. A received withdrawal remains binding even if a final receipt was lost and the raw run still says in progress. This has now been tested against actual received SQLite journals and immutable sidecars, independently of the pure hand-authored helper tests.

`R/platform-camera-analysis-store.R` exposes `brohn_camera_analysis_resolve(store, dataset_record, mode=c("manual","automatic"), verify=TRUE)`. The record is the actual saved entity with its body, project and revision. Genuine non-camera facial imports return null; camera-backed sources return the pure authority plus the original dataset revision, complete received-journal hash/ending, original chunk-manifest hash and any exact session-resolution reference. Current and original dataset lineage must agree, so a mapping revision cannot erase camera permission provenance. Current/historical project ownership and the frozen study/release/protocol are checked before returning authority.

The resolver verifies the retained camera publication envelope, complete assembly manifest and every registered source object, including original incoming chunks and their observation records. Chunk identities must exactly match the assembled manifest. The original single-chunk recording may retain `application/octet-stream` from byte-identical object deduplication; this known storage representation is accepted without relabelling it. Source kind, WebM format, hashes, byte counts, policy and original assembly remain pinned. Other media types are refused.

`verify=FALSE` resolves the complete current catalog, pins every original journal header, validates its immutable ending and checks object availability/size. It avoids full journal decoding/replay, byte hashing and retained JSON reads inside participant finalization. `verify=TRUE` additionally decodes and replays the complete bounded journal and verifies retained bytes. Queue preparation may use that option, but actual processing/publication must verify bytes, hold every returned `source_refs` object and repeat the source resolution. The resolver makes no inference or source mutation. It uses the existing hosted/store/project checks and does not add a new access model.

## Connected integration hooks

1. **Load and fingerprints.** Source this helper after the existing capture/facial functions are available. Pin it in affected camera assembly/facial analysis child and publication identities. Existing geometry outputs retain their own profile and meaning.
2. **Policy validation and original requests.** Dispatch `brohn_validate_camera_policy()` to the new validator only for schema 1.1. The new validator delegates its unchanged recording fields back through the schema 1.0 branch. Extend the camera-start allowed field set; validate the exact acknowledgement against the authenticated frozen policy before storing it. Backup validation must validate new acknowledgements without rewriting old starts.
3. **Study camera UI and participant setup.** Add the facial choice, explicit settings, registered notice and optional-runtime readiness to `platform-capture-views.R`. New-policy edits receive a new digest and future study revision. `runner.js` displays the notice with the existing affirmative choice; `camera.js` includes its two new start fields only for schema 1.1. Decline, failed permission, reload and retry preserve the original decision and digest.
4. **Capture publication.** Both Windows guarded and legacy publishers derive facial metadata using the factory only when the frozen policy requests it. Keep ordinary retained recordings and geometry paths unchanged. Preserve original policy and complete assembly provenance. Unsupported/partial recordings stay reviewable without automatic facial processing.
5. **Automatic queue.** Extend `brohn_queue_capture_analysis()` after its existing geometry branch. Resolve original run/capture/publication, inspect named eligibility, select original dataset revision 1 and enqueue `analyse_dataset` with explicit automatic camera authority. Calls after assembly and after participant finalization remain idempotent, covering either ordering. Expected ineligibility returns without damaging durable capture/finalization. Do not run model readiness or inference inside the receiving transaction.
6. **Queue/input/retry authority.** `brohn_queue_dataset()` must invoke `brohn_camera_analysis_resolve()` for every facial dataset, including checking original revision 1 when its current mapping no longer says `browser_camera`; otherwise a manual mapping could bypass original source controls. Queue requests retain a `camera_analysis_authority` pin and its explicit mode. `brohn_job_input()` re-resolves the same original run, capture, publication, dataset revision and received-ending/withdrawal evidence, compares the entire authority, and passes it into the child. A retry uses the same pin; it cannot acquire new permission implicitly. Non-camera facial imports continue with their existing reviewed-import permission.
7. **Source guards, report and publication.** Extend the existing facial raw-video read guard to all authority `source_refs`; re-resolve after guards are acquired and immediately before publication. The child report retains this authority in provenance. Publication compares it with the pinned fresh input before accepting the native result. `brohn_camera_analysis_report_source()` revalidates exact original source authority for saved-report access; download handlers continue to apply current source/hosted authority before returning payloads. Historical manual policy 1.0 reports without the new pin receive a clearly labelled current-source review, without rewriting their original report. Named policy 1.1 reports cannot omit their authority pin. A model result is not permission to bypass revoked access.
8. **History and recovery.** Saved camera/source/report panels show original named permission or later researcher attestation, original outcome, settings and policy hash. Cloning creates a prospective design; it does not copy participant permission. Restore keeps immutable starts and source objects and respects the existing paused-workspace policy. Resuming a stored job still rechecks its original authority and runtime identities.

## Connected acceptance and remaining scope

The executed acceptance uses an isolated workspace and clearly labelled licensed fake-camera media, without real participants; exact completed/remaining scope is in the [acceptance receipt](../qa/CAMERA-FACIAL-AUTOMATION-ACCEPTANCE.md). Future regressions should use fresh fixtures or explicitly documented immutable-source continuations. Exercise researcher creation/settings and original named notice, release freeze, participant camera agreement, actual MediaRecorder chunks, durable completion, native assembly and automatic native facial report. Compare exact selected PTS, complete JSONL/CSV and source hashes with independent native output or direct source-reader expectations. Include the ordinary explicit-liking question and participant report so the journey remains a complete study.

Cover assembly-before-final-receipt and final-receipt-before-assembly, repeated finalization/queue calls, decline, optional camera unavailable, interrupted/reload capture, received withdrawal with missing final receipt, incomplete/unsupported container, exact settings bounds, automatic revision substitution refusal, manual legacy attestation, source change during processing, stale downloads, restart, backup/restore and zero duplicate jobs. Preserve failures and distinguish inherited from newly queued jobs. Inspect desktop/mobile screenshots and accessibility; the source remains synthetic software evidence, not device accuracy or model validity.

## Evidence retained so far

Run from repository root with the restored R library and `LC_ALL=C`:

```powershell
& ../../work/native-r/bin/Rscript.exe tests/platform-camera-analysis.R ../../work/test-runs/brohn-camera-analysis-domain-20260924-04
& ../../work/native-r/bin/Rscript.exe tests/platform-camera-analysis-store.R ../../work/test-runs/brohn-camera-authority-20260924-03
& ../../work/native-r/bin/Rscript.exe tests/platform-camera-analysis-store-retained.R ../../work/test-runs/brohn-camera-authority-20260924-03 ../../work/test-runs/brohn-camera-authority-retained-20260924-01
```

All evidence stays outside Git under the outer workspace's `work/test-runs`. Actual assembly also requires the configured `BROHN_PUBLICATION_PYTHON`, `BROHN_PUBLICATION_NATIVE_MANIFEST` and existing FFmpeg/FFprobe. The retained-source script requires the completed actual fixture and is not a standalone default suite.

| Receipt | Result and SHA-256 |
| --- | --- |
| `brohn-camera-analysis-domain-20260924-04/results.json` | 50 pure checks; `ac99be9ce61974db2ab847fb32a867209038c6fd49f1f80cf3bf4cba007def59` |
| `brohn-camera-authority-20260924-03/results.json` | 19 actual SQLite/source checks; `505a935c9abeea4898ffb1b790c8ea8be497b119d7929e391534feb953f657e1` |
| `brohn-camera-authority-retained-20260924-01/results.json` | Six focused current-source continuation checks; `dadd43a1dd000fa057f6ec34b2643171d1458fae827bf790abf5ef4e14e54f4e` |

The pure checks cover exact policy/acknowledgement, unsupported budget/decimal boundaries, original completion eligibility, distinct legacy/manual permission, artifact/source substitutions and immutable hand-authored originals. The actual fixture generated a test-pattern WebM without a human, received it through real participant camera APIs, processed three guarded assembly children and saved later reviewed manual facial mappings. It created four jobs: three successful assemblies plus one automatically queued response-analysis job explicitly cancelled before execution; zero inherited jobs or facial analyses. Complete, unfinished, withdrawn-with-lost-final and separately resolved states were exercised. Read-only resolution and restart preserved actual original SQL records, bytes and authority.

The six-check continuation uses the same retained fixture after adding exact SQLite-chunk-to-assembly-manifest comparison. It verifies the prior completed authority, actual interruption and withdrawal sidecars, and deliberately substitutes an observation identity in a rollback-only fixture transaction. The resolver refuses that mismatch; every original SQL row, immutable trigger and object hash is then confirmed unchanged. No child jobs were repeated. The 19-check receipt is retained unmodified; this is an explicitly joined final-source qualification, not an uninterrupted run under one source hash.

The first pure `-01` attempt passed 30 checks then failed because the test removed a named list element and passed an `NA` argument to `do.call`. Its transcribed failure receipt is retained. Corrected `-02` passed 47 checks; `-03` added copied-original-statement refusal; final `-04` adds deduplicated media-type cases. Actual authority `-01` exposed the too-strict assumption that a deduplicated camera object always says video/WebM; the helper was corrected. Actual `-02` passed six checks then the harness incorrectly asked canonical JSON hashing to serialize raw SQL data frames; direct exact-record comparison repaired the harness. Both failure workspaces/logs remain retained. Those original preparation receipts do not claim policy 1.1 runtime integration, automatic facial inference or a camera browser journey. The later loaded integration and connected browser scope are recorded separately in the acceptance document.

Work paused at the user's request after camera automation evidence closure. A dedicated facial per-frame/time-series and exact-frame explorer is a later slice; it has not been started. Existing native summaries, preview and complete artifacts remain available.
