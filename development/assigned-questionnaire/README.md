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
| R/platform-participant-view-camera.R | Inactive adapter to original camera operations, using assigned policy and step references. Actual camera integration tests remain. |
| R/platform-participant-view-resource.R | Unrun draft serving only authenticated assigned resources through bounded verified snapshots. Full files only; range/media and HTTP ownership tests remain. |
| R/platform-participant-received-bytes.R and platform-participant-wire-json.R | Separately checked decoder/encoder optimizations; complete source validation and limits remain. |
| www/participant/observation-journal.mjs | Browser observations, durable pending operations and atomic receipt/model/progress storage. |
| www/participant/operation-result.mjs, request-bytes.mjs and wire-json.mjs | Typed request encoding and literal received-result checking without recreating R numeric spelling. |

No loader, route, renderer registration or default feature flag points at this
folder. Never register the legacy participant bundle as compatible with these
modules. They still need the original compiler/projection/context and method
overlays, exact implementation registration, browser controller, entry/welcome,
camera/resource/finalization paths and joined researcher acceptance. Cold study
loading and extreme request latency remain open.

When promoting a coherent candidate, bind its complete dependencies and repeat
the required integration checks on that candidate. Preserve existing released
studies, historical answers and saved analyses. Keep this snapshot's identity in
the evidence history; do not silently relabel an older test as testing new bytes.

The Qualtrics target extends beyond this delivery layer: whole-study flow
authoring, repeats/piping/carry-forward, guided analysis and editable unified
dashboards remain in the [QF01–QF08 queue](../../docs/research/QUESTIONNAIRE-QUALTRICS-PARITY.md).
