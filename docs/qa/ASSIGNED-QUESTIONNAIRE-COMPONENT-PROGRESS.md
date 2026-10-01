# Assigned questionnaire collection: component evidence

Updated 2 October 2026. This records local implementation progress toward
[assigned delivery](../architecture/ASSIGNED-QUESTIONNAIRE-DELIVERY.md) and
[QF01–QF08](../research/QUESTIONNAIRE-QUALTRICS-PARITY.md). The new delivery profile
is **not active in the released app**. These are scoped engineering checks, not
Qualtrics parity, scientific validation or a completed researcher journey.

| Component | Executed evidence | Scope still open |
| --- | --- | --- |
| Assigned API-only router | 50 route/header checks pass, including finite declared upload limits, transfer-encoding refusal, exact paths/token syntax, original origin and safe error responses. Source syntax includes entry and finish. Natural independent closure and all1533 source files conserved. | No actual TCP, proxy, coordinator, storage or browser journey in this phase. |
| Entry/welcome and assigned finish | Independent static source review; both sources parse in the header phase. Finish now supplies the actual admitted1.2 revision context and a seven-value scalar envelope. | Direct coordinator execution, actual HTTP resource ownership and completed/withdrawn/interrupted jobs remain. Full-history writer replay and downstream1.2 worker compatibility are explicit activation gates. |
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
| Actual assigned-event receiver | Core: 20 case/24 wrapper controls on the original small information questionnaire; independent closed-store Python oracle: 204 controls. Exact received bytes, original events, derivations, model and receipts remain associated. | Broader workloads, equipment and real HTTP/controller integration have separate unfinished checks. Synthetic renderer registration is not production activation. |
| Receiver atomicity and lost replies | 55 case/34 wrapper controls across five fresh stores. Actual faults at operation/event/relation insertion and ACK update roll back all effects; a response failure after commit recovers the original receipt without duplicate writes. | Counts include repeated setup. This does not prove cross-process contention, physical equipment or the complete browser-to-server journey. |
| HTTP byte helpers | 63 checks using installed httpuv1.6.17 InputStream and four actual R-encoded result fixtures. Exact raw request/response bytes, body lengths, headers and 4 MiB boundaries pass. | No live HTTP route tested. httpuv buffers before Rook; application bounds are not a hosted ingress limit. |
| Receiver schema, peer and retained-integrity gates | Schema110/46, fences118/46, rating-questionnaire12/27 and retained-integrity145/47 case/wrapper controls pass. Actual second-connection changes refuse stale commits; exact winners recover. Corrupt retained requests/results/relations refuse without repair. | Counts include repeated setup. Peer interleaving is two connections in one process; physical equipment and whole collected large studies remain separate gates. |
| Operation-journal compatibility and transactions | The successor passes all39 original Chrome controls, then118 operation controls and7 syntax checks. Actual v1 migration, restart/two-tab ownership, pending-before-send, native transaction abort, atomic result/model/ACK, late receipts and fresh-state fences pass. | Results are synthetic fixtures; this is not an actual R/HTTP roundtrip. Two earlier harness-observer failures remain retained. No combined controller or new profile activation. |
| Single-digit decoder optimization | Four phases pass: original core259, focused367, original limits5 and full paired comparison15, plus24 wrapper checks. Complete raw/typed values, reference snapshots and newly serialized output bytes agree. | Repeated controls are included in these counts. One sequential public-call pair was74.96/65.45 seconds. This is still too slow and is not a production benchmark; combined runtime remains separate. |
| Question controls with operation journal | 90 actual browser controls and9 syntax checks pass, with five zero-violation Axe scans. All21 raw-row comparisons match the prior durable02 observations after the declared metadata migration. Owner inspected all five current screenshots; root independently inspected three narrow-layout recovery states. | The reconciliation screen is a harness guard. The earlier86-check R replay was not rerun, and real HTTP/current authority/controller behavior remains open. |
| Start/current response join | Five small-source cases pass96 case/34 wrapper controls: one owned full admission, exact predecessor current response after actual progress/terminal state, lost reply/retry, revoked access, real peer progress/source drift and handle closure. | Complete collected large studies and actual HTTP remain untested. The earlier binding assertion failed on R object-key order; the corrected fixture compares complete typed objects while retaining exact view bytes and public run key. |

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

The first camera/resource phase stopped during fixture design validation: its
explicit1.2 design was mistakenly passed to the legacy validator. Only actual
PNG registration/setup ran; no release, start or camera operation occurred.
Failure and natural independent closure are retained. A separate successor uses
the actual variant validator and fixes a run-specific public frame key in a later
unrun resolution case. Camera/resource runtime bytes are unchanged.

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
decoded-domain checking 21.59 seconds. A separately qualified six-line single-
digit fast path then preserved all complete outputs and limits; its fresh ordered
pair measured74.96/65.45 seconds. This is a12.7% reduction in that one diagnostic,
not acceptable extreme-request latency or a stable speedup estimate. Earlier
whole-test elapsed time must not be described as isolated decoder time.

A separate two-connection WAL diagnostic passed 46 controls for same-connection
change observations, read-only restoration and busy behavior. This is controlled
same-process interleaving, not a completed receiver or separate-process race.
The receiver implementation admits source-owned required schema/trigger definitions;
merely snapshotting a database with already-missing protections is insufficient.
Core transactions, rollback, required-schema faults, same-process peer changes,
retained-receipt integrity and local browser atomic ACK/model persistence now
have the scoped evidence above. Physical equipment, actual HTTP/controller
joining and separate-process contention retain their own execution gates.

Failed qualification attempts remain part of the record. The rating fixture
initially supplied a source number where the public event contract requires an
assigned option key; the corrected fixture uses the real answer translator and
retains the same expected source value. Browser harness corrections explicitly
wait for the native abort listener and test frozen mutation in a strict callback.
All original behavioral assertions remain, and runtime bytes are unchanged by
those harness repairs. These failures are not recorded as product passes.

Current-session qualification checks 101 original events with two bounded reads,
preserves negative zero and refuses incorrect hashes, identities, noncanonical
bytes, non-text bodies and oversized rows. Actual peer commits during replay
exercise credential revocation, journal advancement, event-ID corruption and
researcher resolution. A stale response refuses; a new read sees coherent saved
state. Information acknowledgement, review/sealing and token-bound page recovery
use original event replay. These reader tests are separate from receiver evidence
and do not create physical device evidence.

## Next integration obligations

1. Preserve the qualified store/current/receiver behavior while connecting the
   actual router and loader. Add separate-writer first-start contention and genuine
   large questionnaire collection/reopen evidence.
2. Connect the qualified durable screen/bridge/order path and its independent R
   replay to the actual participant controller. Join the separately tested
   receiver with browser ACK/state transactions and draft recovery.
3. Exercise the separately qualified server and browser atomic commits through
   real HTTP: exact pending bytes before send, lost replies/restarts, current-state
   refresh, changed branches and immutable historical answers.
4. Connect assigned resources, actual equipment/camera receipts, interruption
   and ending paths, then run the create–publish–collect–restart–results journey.
5. Resolve cold-admission latency and qualify representative complete workloads.
   QF02–QF08 flow authoring, guided analysis and editable dashboards remain open.

All17 work-package statuses remain unchanged; this progress closes no package.
