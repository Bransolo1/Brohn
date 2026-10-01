# Assigned questionnaires: collection and recovery architecture

## Recovery checkpoint — 2 October 2026

Actual Chrome sender recovery now passes 85 controls against synthetic Node
authority; it preserves pending operation bytes through lost replies and restart,
then refreshes CURRENT before enabling collection. This does not qualify actual
R HTTP or the questionnaire controller. Browser-internal retransmissions can
produce more physical requests than the two explicit application attempts.

The private context pool passes core and full retained-response equivalence.
The retained diagnostic was29.37s cold,31.50s first pooled admission and0.34s warm.
All six direct pool phases now pass, including access, mutation, lifetime and
accounting (97 case/120 wrapper checks). Use by actual coordinators remains a
separate gate. Assigned PNG resource tests also pass 36 direct checks, while
HTTP/disconnect/range behavior and cold-resource latency remain unqualified. The sender's in-flight append restriction still needs an explicit
storage-only observed-event boundary plus a durable draft store.

The new local finish successor prepares full replay and original camera support
before the writer, with unchanged-source/schema/change-counter fences. It is
not yet directly qualified. Camera support still aggregates history outside the
writer; protocol decoding/comparison remains inside. Initialize and admit the
complete receiver schema at startup. Never repair missing storage in a request.
Automatic protocol1.2 analysis and later export need explicit historical-reader
support; queued jobs cannot be presented as completed analyses.

This is the active QF01 / EF02–EF03 integration contract, dated 2 October 2026.
It extends [questionnaire parity requirements](../research/QUESTIONNAIRE-QUALTRICS-PARITY.md)
and the [eye-tracking flexibility queue](../research/EYE-TRACKING-FLEXIBILITY.md).
Implementation is local and inactive; the released application still presents
every listed ordinary stimulus. This document does not claim assigned delivery,
Qualtrics parity or completion of the wider platform.

The [development snapshot](../../development/assigned-questionnaire/README.md)
now retains16 exact implementation/dependency files with individual identities
and scopes. The complete source overlays, fixtures and joined deployment still
need portable promotion. Do not wire these partial modules into the legacy
renderer or treat the snapshot as a runnable new participant profile.

The inactive API now connects entry/welcome, start/current, events, questionnaire
paging, assigned media, camera and finish coordinators. Its 50 header/route checks
pass; actual TCP and coordinator journeys remain. Opening content exposes no
experimental resource registry. Finish explicitly supplies the admitted design1.2
revision context to original replay. Its remaining whole-history writer replay
and downstream1.2 analysis-worker support must be qualified before activation.
The browser sender and bounded server-context reuse are being tested separately;
neither changes source authority or enables the new delivery profile.

## What the researcher and participant should experience

A researcher can combine shared controls, alternative materials and questions in
one study. The participant receives only their assigned material, with the exact
question/option order and explicit answer types. A slow save does not alter a
response's observed timestamp. Failed saving keeps the answer visible and offers
one clear recovery action. Resume preserves the original assignment and response
history; it must never regenerate a different questionnaire.

Within an unsealed questionnaire occurrence, supported back/edit operations retain
earlier answers as history and apply the saved dependency policy. A timed exposure
is not repeated merely because the browser refreshed. Information acknowledgement
remains distinct from a scored answer. Missing, declined, hidden and invalidated
answers do not become zeroes. Results retain original control/version membership
and the correct person/session/exposure references.

## One original source, a separate participant presentation

The full compiled protocol remains private and retains its original raw-byte hash,
allocation and analytical meaning. A separate closed presentation contains only
assigned public content and opaque keys. A private map translates those keys back
to original source events; it is never a browser resource. The presentation, map,
complete original source and exact renderer runtime are bound atomically to the
run at first start. Resume reopens those stored bytes without recompiling them.

The planned new profile is `participant-view-delivery/0.1`. A server-owned renderer
registration must identify the actual assigned-view implementation and match its
release runtime manifest. The legacy participant bundle cannot be relabelled as
compatible. Until the new renderer and routes are connected, registration refuses.
Legacy routes must also refuse marked new-profile runs rather than expose their
full private protocol or another arm's assets through an older endpoint.

Before fetching large stored bodies, participant reads check credentials, current
workspace/hosted policy, source ownership, runtime binding and actual SQL byte
lengths. They then verify raw hashes and admit the complete original/view/map
context. Current authority and immutable identities are checked again after that
work. A context is not an authorization token; researcher-only readers do not
become participant access paths. Closing recruitment and revoking an existing run
retain their distinct policies.

## Saving, timing and recovery

Valid submission captures the answer, original page clock and one event identity
synchronously, before waiting for its draft save. A shared ordered queue reserves
that observation's position. Later visibility/task observations cannot pass it.
A pre-handoff draft failure releases only an empty reservation. Once handed off,
an ambiguous retry retains the same immutable observation, clock and identity.

The durable browser journal must allocate sequences in a committed transaction,
reconcile repeated identities and preserve exact queued request strings before
their first network send. Recovery must reconcile pending work and server ACKs
before allowing more answers. Actual IndexedDB reopening, storage failure,
offline/reconnect and two-tab exclusion remain required. The current in-memory
queue and submission bridge do not establish those behaviors alone.

The new request codec uses actual received HTTP bytes as operation identity.
Reusing an operation ID with different bytes conflicts, including whitespace;
legacy receipt semantics stay unchanged. Received bytes and translated original
events are separate evidence domains. A receiver transaction must commit the
received operation, immutable derivation, original-schema events, ACK and receipt
together, or roll them all back. The original replay and committed equipment/
camera checks remain authoritative. Receipt retries still check current access.

Questionnaire packet, resume and answer-projection tokens use distinct domains.
Pagination returns complete records tied to one state and ACK, never truncated
answers or rows combined across changing states. Revised/resumed answers retain
null initial response time and the supported active-segment observation.

## Capacity and latency are product requirements

Stored documents are bounded independently from delivery: a 16 MiB stored codec
allowance does not authorize a 16 MiB HTTP response. First start measures the
complete escaped response, including its quoted exact presentation, against
4 MiB; questionnaire state packets remain within 3 MiB using whole-record pages.
Oversize designs must be explained before recruitment, not partly served.

Local component qualification found two unresolved performance concerns:

- Full admission of a large retained protocol took 24.66 seconds after removing
  a duplicate full admission; its predecessor took 42.45 seconds in the same
  comparison. These are individual observations. The existing legacy browser's
  15-second request timeout is incompatible with such a synchronous cold path.
  The complete store phase separately took 83.82 seconds for the first-start
  compile/project/admit-and-commit pipeline and 27.55 seconds for cold reopen.
  Its writer transaction took 0.09 seconds; a check on an already-held handle
  took 0.02 seconds. These scopes overlap and must not be added or substituted
  for one another. Profiling must distinguish first start from context admission.
- The strict raw decoder passed the actual two-million-node boundary. Its whole
  admission test took 77.03 seconds, including an extra raw hash and complete-value
  oracle; the one-node-over refusal check took 37.40 seconds. These are test-case
  timings, not isolated decoder benchmarks. Separate public-call and oracle timing
  is required before choosing an optimization. Passing these extreme checks does
  not establish acceptable interactive latency.

Resolve these before activation through measured implementation improvements or
an explicit versioned work/scheduling policy with understandable progress and
exact retry behavior. Do not merely hide the delay or silently reduce supported
content. Reuse of admitted server-owned state requires current authority and exact
immutable identities; it cannot reuse a cached access decision or trust a client
validation flag. Allocation races, concurrent starts and cold/warm performance
need representative workloads as well as single-run correctness tests.

## Current integration gates

The [2 October component progress](../qa/ASSIGNED-QUESTIONNAIRE-COMPONENT-PROGRESS.md)
records the executed screen-to-R replay, actual Chrome journal, joined durable
question screen and independent original R replay. All six assigned-store phases
and six bounded current-reader phases also pass. The retained current response
took 28.91 seconds. Paired profiling and a bounded key-only wire memo now have
separate exact-output evidence; one retained constructor comparison measured
27.61/24.64 seconds. This does not qualify product latency. The pure R operation
document encoder and browser literal-result verifier also pass; they are not
the atomic receive or browser acknowledgement transaction. The authenticated
receive/derive transaction, latency work and complete researcher journey are
still required. The response boundary test uses
a synthetic projected packet; genuine large questionnaire collection/reopen
remains a separate integration gate.

An operation confirmation retains its original request identity, committed
interval and exact model bytes. A lost reply can recover that historical result;
it must not overwrite a newer local model or imply that a finalized session is
still editable. Browser storage must commit pending state, ACK, receipt and model
together, and automatically refresh current state during ambiguous/restarted
delivery. No extra participant confirmation click is required for that refresh.

The staged legacy guards also block new-profile entry/assets and common camera
authorization. New welcome/resource/camera/finalization routes need explicit
assigned access; removing those guards or calling the old camera API with an
internal run ID is not an integration solution. Preserve the original camera
receipt, consent, chunk-prefix and clock obligations.

The local components have separate scoped checks for typed question projection,
state/history translation, event replay, exact request encoding/decoding, native
question controls, ordered observations and submission recovery. Those passes
are not an integrated researcher acceptance. Runtime evidence is retained locally
under `work/participant-*`; a portable release receipt is still required when the
combined implementation is promoted into this repository.

1. Complete atomic first start and participant-authorized stored presentation
   reopening, including rollback, contested allocation and exact-byte retries.
2. Connect actual question controls, submit bridge and shared order to original R
   replay; check held submission, later visibility, draft failure and ambiguous
   retries without changed response times or duplicate answers.
3. Connect the durable browser journal and received/derived server transaction;
   prove restart, offline recovery, storage denial and current-access behavior.
4. Connect assigned resources and camera/equipment on both new and legacy route
   boundaries; preserve actual consent, chunk, source and clock obligations.
5. Complete all question/task profiles and review/edit/seal paths on the actual
   integrated renderer; qualify latency, bounds, errors and accessibility.
6. Run the researcher journey: create controls/two versions, liking/scale/branch,
   preview, publish, collect and reconcile exact history/results after restart.

Broader flow authoring, variables/repeats, guided analysis and editable dashboards
retain QF02–QF08. All 17 platform work packages retain their existing statuses.
