# Closed-session researcher recovery acceptance

Accepted 24 September 2026 for the bounded cases below. This is functional delivery and provenance evidence, not human usability, hardware timing, recording decodeability, emotion-model or scientific-method qualification.

## Researcher and participant behaviour

From a closed release's collection review or participant Review row, **Review session recovery** opens the exact assigned session. The researcher sees received progress, the original participant ending/receipt, recording bytes and missing recording support. They supply a reason and affirm the consequences before recording an immutable researcher decision. There is no broad automatic termination.

The decision is a separate `session_resolution` entity. Original `delivery_runs`, assigned protocol JSON, participant event journal, operation receipts, camera start/end receipts and stored chunk bytes remain unchanged. Original missing final acknowledgments stay missing. An absent participant ending is labelled **Researcher interruption**; received participant endings remain their actual declared outcome. Collection History and manifest exports pin the separate decision and distinguish its counts from original completed/withdrawn/interrupted receipt counts.

New evidence is refused after resolution, within the same receiving transaction that checks the sidecar. Exact already-received operations remain idempotent. A participant's active page handles the real `researcher_resolved` error by stopping presentation/recording delivery, releasing camera tracks and preserving unsent local responses and chunks. On a later visit, authenticated session status is checked before camera recovery, so Brohn does not manufacture an old recorder endpoint, start a replacement camera or delete the browser's retained evidence. The participant receives no operator reason or other participant credentials.

The collection can close with an explicitly acknowledged unobserved recording end or partial capture. Active processing always blocks closure. A failed/cancelled partial assembly is acknowledged only if its exact job ID, operation, terminal status, request hash and capture hash were reviewed in the immutable decision. A later failed attempt, unrelated request or failed full-recording assembly cannot inherit that acknowledgment. No missing camera analysis is presented as a result.

## Separate received-completion analysis

If the complete original journal replays to an actual participant `completed` ending and required camera completion support exists, **Analyse confirmed completion** queues `analyse_resolved_run`. This route also supports a required-camera original completion receipt; it does not demand an invented participant final receipt. Missing required camera evidence remains ineligible.

The existing response/task/scale scorer runs on the original run metadata and journal. The saved report includes the immutable sidecar ID/hash/body, original receipt state and original missing `finalized_at`. It is a distinct source-bound report; the raw `in_progress` session does not silently enter ordinary completed-run/cohort routes. Native guarded publication verifies the implementation identity, exact input and current pinned source again before committing. Collections can include the corresponding report only with matching run, release, design, sequence and sidecar provenance.

Initial review profile: at most 100,000 received events and 64 MiB of event JSON; original evidence is retained if outside this profile. Initial separate-analysis transport: at most 8 MiB, with no event truncation or substitute incomplete classification. Camera receipt support is not a claim that an encoded recording was decoded or physically synchronized. Ordinary source/decoder workflows keep their existing eligibility rules.

## Executed evidence

All retained workspaces below are outside the repository and contain only original synthetic fixtures. The executed commands use the repository's R runtime and restored R library with `LC_ALL=C`.

- `tests/platform-session-resolution.R`: **40 passed** in `../../work/test-runs/brohn-session-domain-20260924-05`. Covers scope, reason, stale event and processing reviews, immutable original SQL records, idempotence/conflict, preserved completed/withdrawn/interrupted endings, numeric zero, child-side altered-journal rejection, ordinary-route exclusion, active descendant jobs, exact old event/start/chunk retries, rejection of new events/bytes/endpoints, exact partial-job acknowledgment, required-camera supported completion, failed full-recording assembly remaining unresolved, backup preservation and paused-restore refusal. The required-camera domain case uses an original generated test-pattern WebM and synthetic original clock/receipt fixtures; it does not claim observed participant timing.
- `tests/researcher-session-resolution.mjs` with `tests/fixtures/researcher-session-resolution.R`: **8 substantive end-to-end checks passed**, **7 clean automated accessibility/reflow/text-intersection scans** across 1440 px and 390 px views. Final evidence: `../../work/test-runs/brohn-session-browser-20260924-03/browser-1790220975615`.
- Actual browser camera case: Chrome's synthetic device sent **22,659 original bytes** before connectivity loss. After researcher resolution, the still-open page saved its next numeric answer locally, encountered a real authenticated HTTP 409 on reconnection, released camera tracks and retained that answer plus **9 local chunks** without creating a participant or camera finish request. Page close/reopen requested no replacement camera and preserved the local journal. Original server journal, raw status and camera bytes stayed identical; collection closure succeeded with no fabricated response report.
- Actual browser completion case: original response value **0**, completed step sequence and participant `completed` event reached R; `/finish` was deliberately blocked before receipt. Researcher confirmation queued one actual supervised R worker, which produced the exact value 0 with the pinned decision and missing original final receipt. Report download, collection finalization/history, genuine service restart and backup/restore all passed.
- `tests/verify-session-resolution.py`: **19 independent Python checks passed** against read-only SQLite, content-addressed camera/observation bytes, complete original event rows and actual downloaded decision/report/collection exports. It uses no R scorer or application assertion helper. Receipt: final evidence directory's `independent-audit.json`.
- Seven final screenshots were opened and visually inspected: desktop/narrow recovery review, narrow confirmed completion, finalized camera collection, both participant resolution screens and restored-history resolution. Modal copy and controls are readable; long narrow dialogs scroll, and the collection table retains its labelled keyboard-focusable horizontal scroll region.

Final browser `results.json` SHA-256:
`0099b115e06bd9499ec0637d506f82e3355cc48c219060fa4e1740a76ebbd503`

Independent audit SHA-256:
`a236f8c69773c41c5f91ee8d2d15c17bcbe010d46ce437f338b83b6712f4f1e0`

Actual worker: `job_e9f305e9a7052e81634a98a99df10f0b`, operation `analyse_resolved_run`, attempt 1, succeeded. Report: `report-job_e9f305e9a7052e81634a98a99df10f0b`. It records `staged-windows-parent-read-seal/1.0` publication. Both owned services on ports 3883/3884 stopped after the journey.

## Defects found and attempt accounting

The first browser attempt stopped before a decision or job because its accessibility scan sampled a replacing modal during the Bootstrap fade; the harness now waits for actual opacity/animation completion. The second attempt completed live participant recovery and abandoned collection closure, then detected intersecting wrapped heading line boxes at 390 px. The recovery modal now uses adequate heading line height and a normal-size checkbox within a 44 px label target. The third fresh journey passed against unchanged source hashes. Browser attempts 1 and 2 created **zero jobs**; attempt 3 created **one successful job**, with no retries.

Five fresh domain attempts are retained. Attempt 1 had a fixture-only receipt-table column mistake and no jobs. Attempt 4 had a fixture-only base64 escaping mistake. Domain attempts 2/3/4/5 contain respectively 3/3/2/5 deliberately cancelled queue entries used to exercise guards; no scientific child was launched by the domain harness. All are terminal. The independent verifier initially confused a camera request-content hash with its raw object hash; its final oracle separately checks raw bytes, original chunk metadata and hashed observation bytes.

Root integration regressions also passed after receiving guards were wired: `tests/platform-delivery.R` **56**, `tests/platform-capture.R` **63**, existing collection domain **19**, and actual `tests/participant-persist-regressions.mjs` **13 typed-branch + 17 camera permission/decline recovery checks** with one clean narrow scan. The latter evidence is at `../../work/test-runs/brohn-maxdiff-delivery-regressions-LLNZqY/results.json`; its scope is distinct from this feature's new acceptance journey.

## Reproduce

```powershell
$env:R_LIBS_USER=(Resolve-Path ../../work/r-library-brohn-restore)
$env:LC_ALL='C'
$env:BROHN_PUBLICATION_PYTHON=(Resolve-Path ../../work/tooling/methods-venv/Scripts/python.exe)
$env:BROHN_SESSION_TEST_ROOT='<fresh external brohn-session-domain-* directory>'
& ../../work/native-r/bin/Rscript.exe --vanilla tests/platform-session-resolution.R
node tests/researcher-session-resolution.mjs '<fresh external brohn-session-browser-* directory>'
python tests/verify-session-resolution.py '<browser directory>' '<browser directory>/browser-<receipt timestamp>'
```

The browser fixture reserves ports 3883/3884, starts/stops only its owned services and refuses an existing fixture config. Freeze shared worker sources during the actual job; the harness records and compares exact source fingerprints. It does not alter original research workspaces.
