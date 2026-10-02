# Assigned questionnaire delivery — development source

John: these are actual implementation files for the current questionnaire and
stimulus-assignment work. They are a **source review snapshot**, not a runnable
second application or an enabled participant profile. Continue launching Brohn
with the main repository's normal instructions.

The [delivery contract](../../docs/architecture/ASSIGNED-QUESTIONNAIRE-DELIVERY.md),
[workstream](../../docs/WORKSTREAM.md) and [scoped test evidence](../../docs/qa/ASSIGNED-QUESTIONNAIRE-COMPONENT-PROGRESS.md)
remain authoritative. [SOURCES.json](SOURCES.json) binds each file to its exact
local implementation bytes and records its scope. Local QA receipts and complete
transitive R overlays/fixtures are not bundled here; this folder alone cannot
reproduce their test runs. Do not infer that all files were tested together.

| Files | Purpose |
| --- | --- |
| R/platform-participant-view-store.R | Atomic original assignment, exact retained source and owned authenticated handles. |
| R/platform-participant-view-current.R | Current answer-history reconstruction; start reuses its real handle and returns current state on retry. |
| R/platform-participant-view-receive.R | Atomic event receipt, original-event derivation, saved result and progress; exact retries. |
| R/platform-participant-operation-documents.R | Consistent model/receipt/result bytes. A historical receipt does not authorize editing. |
| R/platform-participant-view-http.R | Strict raw request admission and byte-preserving responses. Does not supply a router or network ingress limit. |
| R/platform-participant-view-router.R | Inactive routing for eleven endpoints with explicit startup storage admission;24 direct startup checks pass. Earlier50 header controls bind the earlier source. Actual HTTP opening03 and events01 now pass their scoped backend journeys; earlier RNG failures remain preserved. |
| R/platform-participant-view-entry.R | Narrow consent/welcome and selectorless PNG access; entry24 and welcome24 direct controls pass. Opening does not allocate a participant. |
| R/platform-participant-view-finish.R | Original completion/receipt/job transaction after outside-writer replay and source fences.93 direct finish controls pass; original camera history still aggregates. Actual HTTP interrupted/completed finish passes; downstream worker and browser controller remain. |
| R/platform-variant-session-resolution.R | Explicit original1.2 researcher recovery; core27 and received-completion17 direct checks pass, original participant history preserved. Camera18/33 and same-process writer fences27/33 now pass separately; resolved analysis, camera HTTP/worker and physical claims remain open. |
| R/platform-participant-view-camera.R | Original camera operations with assigned policy/step references. Camera 1.0 passes 45 direct checks and named policy 1.1 passes 35. Writer fences pass22 direct checks; the old terminal04 failure remains a legacy1.2 reader incompatibility. New explicit resolver core/received and camera18/33 ordering checks pass; old failure remains preserved. HTTP, worker and physical recording remain. |
| R/platform-participant-view-resource.R | 36 direct checks pass for authenticated assigned PNGs, bounded verified snapshots, source changes and cleanup. Full files only; actual HTTP full-PNG and ignored-Range behavior pass separately. Interrupted transfer and large media remain. |
| R/platform-participant-received-bytes.R and platform-participant-wire-json.R | Separately checked decoder/encoder optimizations; complete source validation and limits remain. |
| R/platform-participant-context-pool.R | Bounded private context reuse with fresh access checks. All six phases pass (97 case/120 wrapper checks); actual HTTP/coordinator integration and deployment remain separate. |
| www/participant/operation-sender.mjs, current-session.mjs and current-structure.mjs | Actual fetch/current admission and exact literal questionnaire handoff.27 literal/143 Chrome/39 syntax controls pass against synthetic authority; R/controller, page loader and original start bootstrap remain. |
| www/participant/questionnaire-model.mjs and packet-structure.mjs |58 pure controls for original literal view/packet admission, public actions and draft applicability. Encoded page bounds are not mobile/heap qualification; no page loader or controller. |
| www/participant/questionnaire-drafts.mjs and question-domain.mjs |35 Chrome/8 syntax controls for native local typed drafts, generation/CAS, restart/lock/versionchange. Exact shared pure question-domain extraction; drafts are separate from answers and ACK. |
| www/participant/observation-journal.mjs | Browser observations, durable pending operations, atomic receipt/model/progress and explicit storage-only retention. Exact retry handles for failed captures are process-local, not crash-durable. |
| www/participant/operation-result.mjs, request-bytes.mjs and wire-json.mjs | Typed request encoding and literal received-result checking without recreating R numeric spelling. |

No loader, route, renderer registration or default feature flag points at this
folder. Never register the legacy participant bundle as compatible with these
modules. They still need the original compiler/projection/context and method
overlays, exact implementation registration, page loading and browser controller,
original bootstrap, camera HTTP/worker and joined researcher acceptance. Actual
backend opening/collection HTTP is a separate pass using synthetic observations,
not a browser-to-R journey. Cold study
loading and extreme request latency remain open.

When promoting a coherent candidate, bind its complete dependencies and repeat
the required integration checks on that candidate. Preserve existing released
studies, historical answers and saved analyses. Keep this snapshot's identity in
the evidence history; do not silently relabel an older test as testing new bytes.

The Qualtrics target extends beyond this delivery layer: whole-study flow
authoring, repeats/piping/carry-forward, guided analysis and editable unified
dashboards remain in the [QF01–QF08 queue](../../docs/research/QUESTIONNAIRE-QUALTRICS-PARITY.md).
