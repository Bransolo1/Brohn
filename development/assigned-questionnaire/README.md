# Assigned participant delivery — development source

John: this is actual implementation source for review, not a second runnable
application or an enabled participant profile. Run Brohn using the main repository
README. No active loader, renderer, route or feature flag points at this directory.

[SOURCES.json](SOURCES.json) binds every implementation file to its retained local
source; [DEPENDENCIES.json](DEPENDENCIES.json) reconciles shared JS imports, records
the selected component successor and identifies unchanged native-worker files.
[Scoped evidence](../../docs/qa/ASSIGNED-QUESTIONNAIRE-COMPONENT-PROGRESS.md), the
[delivery contract](../../docs/architecture/ASSIGNED-QUESTIONNAIRE-DELIVERY.md) and
[workstream](../../docs/WORKSTREAM.md) distinguish what ran from what remains.

Latest checkpoint: 72 source files, including scoped ordinary-host, finish-network
and media-preparation implementations. Read the
[recovery acceptance](../../docs/qa/PARTICIPANT-RECOVERY-CHECKPOINT.md) before joining
these sources. The full selected host still needs actual-R entry-to-report testing.

| Source group | Purpose and boundary |
| --- | --- |
| entry-screen, start-controller and start-session | Consent/alias, exact original start custody/retry, restart and fresh CURRENT handoff. Actual R entry tested separately; no whole participant host. |
| questionnaire-controller, pages, model, drafts, question-submit and event-order | Owned current-generation/page/answer flow, typed local drafts, exact observation retention and one-click continue after fresh commit evidence. Actual held R journey passes. |
| view-question and assigned-illustrations | Combined draft-flush/image-alert component passes the actual held R recovery journey with a test-only image adapter. Assigned authenticated PNG loading has separate native preparation/cleanup acceptance; its full-host R join remains open. |
| participant-host, participant-host.css and host-ending | Single ordinary owner, instructions, ending custody and focused finishing/recovery UI. Scoped native storage and controlled-authority browser evidence; complete real-R host still open. |
| finish-session and finish-controller | Original ending request/receipt custody plus authenticated recovery and exact retry. Separate storage and controlled-authority network acceptance, not a full R host. |
| stimulus-media | Exact assigned text/image/audio/video preparation, cancellation and native decode/readiness. No exposure, physical onset, timed renderer or actual R-resource claim. |
| current-session, operation-sender, observation-journal and literal helpers | Fresh CURRENT admission, exact durable operation retry, separate typed drafts/observations/ACK and original literal response bytes. |
| R/platform-participant-view-* and original operation/context helpers | Assigned source storage, current/receive, entry/welcome, camera/resource, finish and HTTP/router contracts. Existing scoped backend evidence retained; complete server dependency closure remains outside this snapshot. |
| R/platform-variant-* and method/evidence history helpers | Read original saved revision/protocol/assignment/event evidence and invoke unchanged analysis algorithms. Completed-run profile; resolved partial runs and wider export remain open. |
| R/platform-participant-variant-finish.R | Original finish transaction creates the explicit idempotent analysis job and preserves legacy completed receipt retry. |
| R/platform-worker-dispatch.R, platform-processing-retry-dispatch.R and scripts | Ordinary exact-profile selection, native analysis/publication, compatible immutable Retry and visible unsupported-profile failure. Known-profile admission can still stop the queue. |
| R/platform-load.R | Exact tested worker-loader overlay for inspection. It is not the application's active loader and does not register participant HTTP or frontend source. |

## Exact composition still requires integration

This snapshot selects controller3d947 and component3bd8a4d1. They pass together in
real-R recovery02 with a test-only image adapter. Actual01 exposed a missing
flushDraft API in component5abe; the successor combines the original draft drain
with that component's image-alert repair. Historical combinations and their
failures remain in the evidence index. Provider6196 still has separate acceptance.

The selected ordinary host is UI06. Its focused tests exercised instructions and
ending recovery with the older component present but no questionnaire transitions.
Those passes cannot establish the new complete host/component/provider composition.

Entry/start, held questionnaire, finish/backend, native worker and Retry are
individually scoped. A single entry-to-collection-to-finish participant host,
ordinary/timed/task/MaxDiff/equipment/camera renderers, actual R-provider join and
the researcher author-to-report journey remain to implement or qualify. The added
host and finish-network sources retain their separate scoped qualification.
The accepted sender's combined held-declaration4MiB limit remains narrower than
the public view's16MiB schema ceiling.

## What can be verified from this checkout

With Python3.9 or later, run from the repository root:

```text
python development/assigned-questionnaire/verify_snapshot.py
```

This read-only command checks source hashes and static relative-import closure.
It does not execute R/JavaScript, exercise APIs or reproduce the local acceptance
tests. Complete participant compiler/projection/context overlays, original
synthetic fixture builders, bounded QA supervisors and toolchain are not yet a
portable public test kit. The evidence index supplies local receipt identities,
not files claimed to be bundled here. Raw participant workspaces, credentials,
browser profiles and process logs are excluded. Packaging that complete test kit
and exact source composition is a remaining delivery task.

No algorithm or scientific interpretation changes in this snapshot. Small
synthetic tests and unchanged calculation identities do not establish independent
method/device validity. Keep method citations and qualification scoped to their
actual evidence. Qualtrics parity remains the full
[QF01–QF08 queue](../../docs/research/QUESTIONNAIRE-QUALTRICS-PARITY.md), including
survey-flow authoring, advanced automatic analysis and editable unified dashboards.
