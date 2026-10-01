# Assigned questionnaire collection: component evidence

Updated 2 October 2026. This records local implementation progress toward
[assigned delivery](../architecture/ASSIGNED-QUESTIONNAIRE-DELIVERY.md) and
[QF01–QF08](../research/QUESTIONNAIRE-QUALTRICS-PARITY.md). The new delivery profile
is **not active in the released app**. These are scoped engineering checks, not
Qualtrics parity, scientific validation or a completed researcher journey.

| Component | Executed evidence | Scope still open |
| --- | --- | --- |
| Native typed question controls, implementation09 | 744 rule goldens, 37 pure controls, 237 browser assertions and 34 zero-violation Axe scans across baseline, submission and invalid-text phases. All 16 current screenshots reviewed by the component owner; four recovery/completion screens also reviewed independently. | Screen-reader testing, full controller and final combined runtime. Automated accessibility scans are not complete accessibility qualification. |
| Ordered submission bridge | 60 pure controls. Captures one answer, clock and event ID before waiting; preserves them through an ambiguous retry. | The callback's real storage and receiver behavior are separate dependencies. |
| Actual question screen + bridge + shared order | Browser03: 43 assertions and three zero-violation Axe/overflow scans. Held save, ambiguous retry, discarded capture and destroyed component exercised. | This phase uses controlled clocks and an explicitly in-memory journal. |
| Original R replay of that browser artifact | 61 checks using the original saved source, view, map and first visit. Numeric zero remains distinct from false; later visibility advances the original clock. Duplicate and altered-timing cases refuse. | Equipment setup is a separately declared synthetic precondition. No physical camera, camera receipt, contiguous complete run or real HTTP transaction is claimed. |
| Durable local observation journal | 39 actual Chrome assertions, including a real browser-process restart, two-tab exclusion, real transaction abort, injected storage denial, typed/signed-zero values, sequence/ID reuse, corruption refusal, complete-record count/byte pages and the initialization/version-change race. | Pending HTTP requests, atomic ACK/receipt/questionnaire-state persistence, drafts, first-start recovery and the complete participant controller are not implemented by this storage core. |
| Question09 + bridge/order + actual durable journal | Browser02: 90 assertions and five zero-violation Axe/overflow scans. All five scenarios used the same original run/view in separate synthetic profiles, then closed and relaunched Chrome. Exact saved rows/cursors survived; aborted and ambiguously committed intermediate states remain independently inspectable. Both reviewers inspected all five current screenshots. | The no-edit reconciliation screen is a harness guard; HTTP receipts and a complete participant recovery controller remain open. |
| Fresh original R replay of durable browser02 | 86 checks: all 61 original obligations and 25 additions. Independently verified exact saved JSON bytes/hashes, run/renderer binding, restart readback, abort/retry distinctions and source event replay across all five scenarios. | Controlled clocks and the original separately synthetic equipment precondition remain. Actual HTTP receipt/draft/controller behavior is not supplied by these tests. |
| Atomic assigned-presentation store, successor02 | Core: 50 store and 23 wrapper controls. First rollback phase: 26 store and 23 wrapper controls; all six intended insert failures left every tracked table unchanged. Second atomic phase: 23 store and 23 wrapper controls cover quota, allocation contention, post-commit ambiguity and exact retry. | Contention is exercised by same-process interleaving; actual separate writers remain to qualify. Later authority phases, larger complete-source positives, bounded current replay and HTTP integration remain open. These are separate phases over synthetic registered assets, not a production renderer. |

The browser-to-R case retained initial response time100.125 ms for a held
submission; the deliberately discarded capture followed by a fresh submission
used300.625 ms from the original visit. These are controlled fixture values,
not measurements of hardware accuracy or real participant behavior.

The new storage core resolves after IndexedDB transaction completion and requests
strict durability. It uses Web Locks to prevent two same-origin tabs from owning
one run. It does not guarantee recovery after user deletion, browser eviction or
device loss. Its local pages stop between complete records at100 observations or
4MiB of retained observation JSON; the next record can be inspected to determine
that boundary. This is not a whole-study limit.

Visual review identified a completion-label defect: the accepted08 fixture could
show a disabled "Retry submission" beside a completion message. The separately
qualified09 successor now distinguishes a fresh submission, an ambiguous
same-answer retry and disabled completion. Its current screens pass. Parent UI
must separately explain local persistence and service receipt; this correction
does not make the earlier browser03 replay a test of09 or activate the new UI.

## Evidence location and preservation

Detailed source bindings, test outputs, failure records and process-closure
receipts remain in the local build workspace under `work/participant-*`. This
repository note is a portable progress summary, not a replacement for that
evidence bundle. Preserve those source artifacts for combined promotion; these
inactive modules have not yet been promoted into the released runtime.
The [component evidence index](ASSIGNED-QUESTIONNAIRE-COMPONENT-SOURCES.json)
records exact local receipt/source hashes and their scope. Its local paths do not
claim that those implementation files have already been added to this repository.

Two connected-browser attempts caught harness defects before browser03: an
invalid destructuring statement, then a locator expecting the initial button
label after draft recovery. Their failure outputs remain retained. A separate
R setup attempt corrected an optional-camera assumption against the actual
required-camera protocol. No source protocol or equipment rule was relaxed.

The storage review found and fixed a real initialization ownership race before
its first browser execution. Its regression used native transactions, a real
version change and real lock probes in an isolated context. Forced cleanup did
not substitute for a successful natural completion.

The first store qualification caught a real cold-open bug: an order-sensitive R
comparison rejected an otherwise identical renderer object after wire decoding
sorted its keys. Successor02 compares typed object values while preserving all
complete-source and assignment checks. Actual committed retry now passes;
deliberately changed renderer ID and manifest values still refuse after complete
admission. The failed run and its original source remain retained.

## Next integration obligations

1. Complete the current atomic first-start/assigned-presentation store tests,
   then the bounded current-state replay and participant response.
2. Connect the qualified durable screen/bridge/order path and its independent R
   replay to the actual participant controller. Both scoped phases pass; neither
   supplies the remaining authenticated receiver, ACK/state or draft recovery.
3. Retain exact pending request bytes before send. Commit server received bytes,
   derivation, original events and receipt atomically. Commit browser ACK,
   validated questionnaire state and pending-operation changes together.
4. Connect assigned resources, actual equipment/camera receipts, interruption
   and ending paths, then run the create–publish–collect–restart–results journey.
5. Resolve cold-admission latency and qualify representative complete workloads.
   QF02–QF08 flow authoring, guided analysis and editable dashboards remain open.

All17 work-package statuses remain unchanged; this progress closes no package.
