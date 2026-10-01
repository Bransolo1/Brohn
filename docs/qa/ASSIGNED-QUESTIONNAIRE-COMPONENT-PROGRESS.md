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
| Atomic assigned-presentation store, successor02 | All six phases pass: core 50/23, rollback 26/23, atomic retry 23/23, authority 36/23, complete forward-only source 16/22 and complete retained source 18/22 (store/wrapper assertions). The six intended insert failures preserve all tracked rows; authority changes refuse. Every phase closes naturally with original inputs conserved. | The totals include repeated checks. Contention uses same-process interleaving; separate writers and HTTP integration remain to qualify. Current replay has its separate evidence below. Synthetic registered assets do not establish a production renderer. |
| Bounded current-session reader | All six phases pass: initial/ending, journal integrity, separate-connection changes, literal resolution, questionnaire/page bounds and complete retained source. 263 case and 157 wrapper assertions include repeated setup. Original source, inputs and RNG remain exact; all phases close naturally. | The complete retained positive has no collected events; the questionnaire journal uses the actual small information-question source. Outer 4 MiB fitting is a separately labelled synthetic packet test. A genuine large design–collection–reopen journey, HTTP and server receive/derive transaction remain open. |
| Bounded object-key encoding memo | Original 345 R/366 Node/450 Python controls, 26 focused controls and 11 retained-context checks pass. Complete values, encoded bytes and all scoped context lookups match. One constructor pair measured 27.61/24.64 seconds with full source admission retained. | This is one ordered timing pair, not a stable speedup or acceptable loading-time claim. Combined runtime promotion remains separate. |
| Pure operation receipt/model encoder | 54 R, 10 wrapper and 42 independent Python checks pass. Exact typed values, historical commit interval, whole-record prefix fitting and the complete escaped 4 MiB result are checked. | Inputs are synthetic projected-state declarations; this helper does not admit a request, authorize a source, commit SQL or reconstruct historical receipts. |
| Browser literal operation-result checker | 122 Node checks: four actual R-encoded synthetic document sets, three typed/copy checks, 97 synthetic refusals, 16 synthetic positives and two conservation checks. Exact model strings, signed zero, association, whole-result/raw-packet boundaries and immutable input capture pass. | No HTTP, browser storage transaction, current authority or editing permission is established. The journal must invoke this checker on actual received bytes and its actual saved pending operation. |

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

The complete retained-store case exposed a product latency gap: first-start
compile/project/admit-and-commit took 83.82 seconds; a separate cold reopen took
27.55 seconds. The writer transaction itself took 0.09 seconds. These are single
observations with different timing scopes, not a stable performance benchmark.
The fast 0.02-second check on an already-held handle does not replace cold
admission. Paired profiling now separates validation and encoding costs; no
validation or supported content limit was removed.
The separate full current-session response subsequently took 28.91 seconds on
the complete retained source. It passed correctness checks, not a latency target.

The paired retained profile preserved identical complete snapshots. Public
constructors took 27.33/28.29 seconds; the instrumented call included 16.23 seconds
in full source admission and 7.12 seconds in two wire encodings. Nested timings
must not be added. Repeated questionnaire-map checks were a small cost. The
separately qualified bounded per-call key memo then preserved all complete
outputs, with the diagnostic 27.61/24.64-second pair reported above.

The extreme decoder profile also preserved identical complete values: public
calls took 75.00/74.94 seconds, with an additional separate 4.20/4.08 seconds for
the output oracle/snapshot. The instrumented lexical scan took 46.18 seconds and
decoded-domain checking 21.59 seconds. These costs remain unresolved. Earlier
whole-test elapsed time must not be described as isolated decoder time.

A separate two-connection WAL diagnostic passed 46 controls for same-connection
change observations, read-only restoration and busy behavior. This is controlled
same-process interleaving, not a completed receiver or separate-process race.
The receiver draft now admits source-owned required schema/trigger definitions;
merely snapshotting a database with already-missing protections is insufficient.
Actual receiver transactions, rollback, equipment parity and browser local atomic
ACK/model persistence still require their own execution evidence.

Current-session qualification checks 101 original events with two bounded reads,
preserves negative zero and refuses incorrect hashes, identities, noncanonical
bytes, non-text bodies and oversized rows. Actual peer commits during replay
exercise credential revocation, journal advancement, event-ID corruption and
researcher resolution. A stale response refuses; a new read sees coherent saved
state. Information acknowledgement, review/sealing and token-bound page recovery
use original event replay. These tests neither create physical device evidence
nor prove the still-absent authenticated receive transaction.

## Next integration obligations

1. Preserve the qualified current-reader behavior while connecting one owned
   source context to receive/derive transactions. Add separate-writer first-start
   contention and genuine large questionnaire collection/reopen evidence.
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
