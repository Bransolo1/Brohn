# Questionnaire answer revision: bounded implementation contract

Status: connected implementation under researcher-report acceptance. The
source inspection and six-observation original probe below describe the original
forward-only seam and remain historical evidence. The opt-in implementation has
75 pure R, 28 connected receiver/scoring, 14 Shiny, 39 pure JS and 23 actual
browser/receiver checks with two accessibility scans. Thirteen legacy browser
checks also pass. See [the browser evidence](QUESTIONNAIRE-REVISION-BROWSER.md).
The full researcher-to-worker report journey and large-history artifact path
remain under implementation. This contract follows [questionnaire sections](../methods/QUESTIONNAIRE-SECTIONS.md)
and the [delivery audit](NEXT-PROTOCOL-DELIVERY-AUDIT.md).

## Product decision

Allow a participant to correct an answer within the questionnaire assessment
they are currently completing. Preserve the assigned question/section/option
order, every submitted answer and the actual stimulus exposure. Show a short
review before leaving that assessment. Once the participant continues to the
next part, its answers are sealed.

The first implementation must connect authoring, the frozen protocol, browser
journal, receiver, recovery, effective-answer analysis and exports together.
A browser Back button on the existing event path is insufficient.

The scope is an untimed questionnaire occurrence: the before-study questions,
the questions after one particular presented stimulus, or the end questions.
Sections and groups are presentation organisation inside that occurrence; they
do not create additional scientific assessments. Do not introduce a Back action
across a stimulus, baseline, fixation, implicit task, MaxDiff set, consent gate,
camera setup, sealed assessment or finished run in this slice.

## Observed current seams

| Source | Current behaviour and implication |
|---|---|
| `www/participant/runner.js`: `persist`, `advance`, `present`, `showQuestion` | Committing appends a response and finish, advances the cursor and may immediately start the next stimulus. The IndexedDB write is copy-on-write and the in-memory state is published only after transaction success. Preserve that atomicity. There is no final-question review window today. |
| `runner.js`: `currentValue`, `saveDraft`, `answersFor` | Widget drafts are separate from committed events. Before/end answers share a browser global map; after-each answers use stimulus ID. Revision needs an occurrence-keyed answer head and draft generation, rather than treating a stale widget draft as a committed answer. |
| `R/platform-delivery.R`: `.brohn_delivery_apply`, `_advance`, `_resume` | The authoritative cursor moves forward. A completed question cannot restart. Hidden skips must match frozen logic. Repeated ordinary responses while the same question is still active can replace current state; this is not a revision protocol. |
| `R/platform-jobs.R`: `brohn_analyse_runs` | Every ordinary response event becomes an observation. Adding a second answer event would inflate response counts and change distributions. |
| `R/platform-scales.R`: `brohn_scale_run_responses`, `brohn_score_scales` | Scale preparation includes every matching response event. Duplicate item records are explicitly ambiguous and unscoreable. Do not weaken this check or use arbitrary last-row-wins. |
| `R/platform-analysis.R`: `brohn_import_responses` | Imported duplicate exposure/question identities are rejected unless revisions have been explicitly curated. That remains correct for existing flat files. |
| `R/platform-core.R`: `brohn_compile`; question sections module | Realised order and option codes are frozen. Section metadata is a sibling of the frozen question. Review/revision metadata must also remain a sibling so it does not change the question or scale key. |

[The original current-behaviour probe](../../tests/fixtures/questionnaire-answer-revision-probe.R)
uses two synthetic rating items with a complete arithmetic-mean key. It submits
2 then 6 to the first still-active item, and 4 to the second. Current replay
accepts completion and holds first-item value 6; ordinary analysis reports two
first-item responses with mean 4 and three total observations; the scale is
`not_scoreable / invalid_or_ambiguous_item`. Restarting the old completed item
is rejected. Six assertions pass, with source/design/protocol/event hashes at
`work/test-runs/brohn-answer-revision-probe/results.json` relative to the project
preparation directory. No database, HTTP service, queued job or scientific
subprocess was created. A future explicitly resolved final-value oracle is
two items, 6 and 4, mean 5. The probe is evidence of the integration seam, not
permission to reinterpret historical duplicate journals as revisions.

## Frozen policy and protocol

Proposed optional design field:

```json
{
  "questionnaire_navigation": {
    "schema": "brohn-questionnaire-navigation/1.0",
    "profile": "within-occurrence-revision/1.0",
    "dependent_answers": "clear-transitive-on-change",
    "seal": "explicit-review"
  }
}
```

The values are named fixed policies, not free-form code. Absence retains the
existing flat forward-only event/compiler behaviour, including future starts
from an old frozen release. Do not add this field during load, ordinary autosave,
clone or import of a legacy design. An explicit author action enables it in a
new draft/release. Clone/template/portable reuse retain an enabled policy, but
new runs get new occurrence identities through their actual frozen protocol.
Invalid or unavailable policy versions fail release validation clearly.

Compile the existing assigned timeline first; then add occurrence metadata and
review steps. This two-pass approach preserves all pre-existing original step
IDs and option assignments. It matters because the legacy option policy uses
timeline length as part of its seed: inserting review steps during the old
question loop would otherwise alter later options incidentally. Absent policy
must keep protocol bytes unchanged. Enabled policy creates a new design hash
and new explicit navigation metadata, with no rerandomisation on editing.

Each nonempty contiguous same-scope question occurrence has a frozen manifest:

```text
schema: brohn-questionnaire-occurrence/1.0
id: deterministic hash-derived identity in a dedicated namespace
design_hash, scope, first_question_step_id
stimulus_step_id: exact preceding stimulus step, or null before/end
stimulus_id, condition_id: frozen source identities, or null before/end
question_step_ids: exact realised ordered step IDs
review_step_id: dedicated noncolliding hash-derived ID
section_assignment_id: existing assignment ID when present, otherwise null
policy_hash, dependency_graph_hash
```

The manifest identity derives from the exact scope, preceding stimulus-step
identity and member steps in the frozen design/protocol; it never derives from
the mutable browser cursor. A compound section is not a new occurrence. If
before and end questions are adjacent in a survey without stimuli, their scopes
still make them two separate occurrences. Empty groups create no review step.
Current support for presenting each stimulus once is unchanged; these occurrence
keys avoid introducing another stimulus-ID-only ambiguity for future repeats.

Add `step.questionnaire_occurrence_id` to existing question steps and one
`type=questionnaire_review`, `phase=active_response` step after each occurrence.
Its stimulus/condition/occurrence references match that assessment. It is an
untimed review screen, without a question answer, scale item or synthetic
stimulus. Count it in the existing complete-protocol step limit. Keep the
existing section labels and option order visible on question revisits.

## Participant interaction

Provide one primary Continue action and a secondary Back action. Back selects
the preceding currently visible question already reached in this occurrence;
it does not force the current unfinished answer to validate or submit. Retain a
typed unsent draft locally, subject to the dependency invalidation below. The
first question has no Back target. Preserve labels, input focus, ranking
confirmation, untouched sliders, typed codes and all current required checks.

When a participant revisits a question, use its current valid draft when that
draft belongs to the current dependency generation; otherwise prefill its
effective committed answer. A previously committed null omission is distinct
from a question never answered. Navigating through an unchanged committed value
records a confirmation visit without creating another scored observation.

The review screen lists the current visible questions and answers with an Edit
action for each and an accessible numerical/text alternative for structured
answers. Do not reveal hidden questions, old sensitive answers or scientific
scores. The primary action says `Continue to the next part`, or `Finish study`
at the final occurrence. Explain once: `You can change these answers until you
continue. Changing an earlier answer may clear its follow-up answers.` A
successful seal ACK is required before an irreversible next timed presentation.
At the final review, seal is followed by the existing finish/camera/receipt flow.

On a changed driver, announce which follow-ups need answering again and keep
focus predictable. Do not jump a user back to a hidden field or trap them on an
empty branch. After editing, Continue follows the realised visible order,
retaining independent committed values so they do not have to be re-entered.
Review can offer `Return to review` only when all intervening visible required
items are already valid. No arbitrary direct jump to an unreached future item.

Optional empty submissions retain the existing `optional_omission` semantics.
There is no general explicit `prefer not to answer` state unless the design
actually offers one. A required item never removes the right to withdraw.

## One new journal/reducer path

Use a dedicated `questionnaire_event` outer event type for enabled occurrences,
with one source-bound reducer shared by receive, replay, resume and analysis.
Do not permit legacy `response`/`step_finished` to bypass that reducer inside
an enabled occurrence. Keep the old event path untouched for legacy protocols
and for instructions, stimulus timing, implicit tasks and MaxDiff.

The existing outer sequence/ID/clock/step/question/stimulus/condition/phase fields
and exact idempotency checks remain mandatory. The payload adds:

```text
schema: brohn-questionnaire-event/1.0
kind: visit | commit | acknowledge | seal
occurrence_id
state_version: expected current occurrence transition version
...kind-specific fields below
```

Every accepted transition increments the occurrence version. The receiver
computes its new state; the client cannot send a replacement answer map, trusted
invalidation list, arbitrary cursor or precomputed visibility result. The same
event at the same durable sequence is a normal ACK retry, not a new transition.
An event with new identity but an obsolete version is rejected atomically.

| Kind | Required payload and receiver rules |
|---|---|
| `visit` | New `visit_id`; `reason=enter/next/back/edit/resume`; `from_visit_id` null only for entry. Outer step is the exact displayed question or the occurrence review step. Entry is permitted only at the current global protocol boundary. Next follows current visible order after a valid commit/acknowledgement. Back/Edit can target only a reached, currently visible member of the same unsealed occurrence. Resume explicitly closes the previous page visit and creates a new clock-bound visit. |
| `commit` | Current `visit_id`; `previous_answer_event_id` equal to the last committed answer in this item's history, including an invalidated predecessor, or explicit null only if none exists; current `dependency_generation`; `value` including typed null; `response_time_ms`; `active_segment_response_ms`; `resumed`. Outer step must be the current visible ordinary question. Reuse the current typed-answer validator, including option identities, matrix rows, ranking and allocation bounds. One commit per visit. Changed values create a new effective head; exact unchanged values confirm only an already-valid effective head. Re-answering an invalidated item creates fresh evidence even when its value happens to match the historical value. |
| `acknowledge` | Current `visit_id` for an information-only question. Records progression but never produces a scored null response. One acknowledgement per visit. |
| `seal` | Current review `visit_id` plus the expected effective projection hash. All currently visible required questions must have valid effective commits and reached information steps must be acknowledged. Optional unanswered visible questions must have an explicit omission before sealing; visiting review does not fabricate omissions. Receiver recomputes the projection and visibility. No later questionnaire event may alter this occurrence. |

This exact namespace is now accepted for explicitly enabled protocols. The pure
module owns transition rules and version validation. The participant bridge uses
canonical paged server packets and opaque R projection hashes; it does not
reimplement the R hash encoder or trust client-supplied answer state.

The global protocol cursor remains inside the occurrence until seal; a dedicated
occurrence cursor/visit controls question progression. On seal it advances past
the review to the next original protocol step. The ordinary `completed` resume
list must not be used as the current validity mask: a previously completed
question can have its answer invalidated. Distinguish `ever_visited`, current
answer heads, current visibility and sealed completion.

Withdrawal or interruption is still handled by the existing terminal path and
preserves all committed history. It does not auto-seal, manufacture a required
answer or enqueue a completed-run report. No revisions after final run closure.

## Dependency clearing and typed equality

Freeze the directed dependencies in every question's `show_if` AST. A change is
an exact native-type/value change, not a text-coercing or tolerance-based
comparison: number 0, boolean false and string `"0"` are distinct. Compare arrays
and objects using the same explicit typed semantics used by committed-answer
validation; preserve ordered rankings. Do not treat an untouched slider or an
absent field as a zero.

The first policy deliberately clears **all transitive dependent answers in this
occurrence when a committed driver changes**, including dependents that remain
visible after recalculation. An answer given under a previous routing context
must be confirmed afresh. This is conservative and predictable; it is a named
research policy and must be visible when the author enables Back.

Apply in realised dependency order:

1. Commit the changed driver as the new head, recording its predecessor.
2. Identify its transitive dependent questions in this occurrence. Remove their
   effective heads, current confirmations/acknowledgements and local drafts.
3. Recompute predicates using eligible earlier effective answers and immutable
   before-scope answers from a sealed earlier occurrence. Clear effective state
   for every now-hidden item even if the expression uses `not` or `answered`.
4. Record a derived invalidation entry per affected previous head, identifying
   the cause commit, question, rule hash, old head and policy version. Retain the
   original answer bytes in the append-only history.
5. Require a new commit if an invalidated item becomes visible again. Never
   resurrect the old answer or its stale local draft automatically.

Independent later answers remain effective and prefilled. Instrument membership
alone does not make every item a routing dependent; scale items are rescored
from their final effective values at the original assessment identity. A hidden
required item is not required until it becomes visible. An optional cleared
dependent remains unsubmitted until explicitly omitted or answered.

Do not clear or edit a sealed earlier occurrence. Before-scope answers can
control subsequent after-each/end flow because they were already sealed before
those occurrences. The first release adds no end-to-after-each reference and no
cross-exposure answer editing. Refuse protocols that cannot satisfy their
existing scope/dependency-order rules.

## Timing, capture and offline recovery

Question visit onsets retain the actual browser monotonic clock instance and
observed time. Bind a commit to its current visit; reject negative/foreign-clock
elapsed values. For a first uninterrupted submission, retain the observed
question response time. A changed/revised or resumed answer has
`response_time_ms=null`; expose the edit visit's `active_segment_response_ms`
separately with an explicit descriptive label. Do not sum visits, clock origins,
hidden time or reload delays into an apparent initial response latency.

An unchanged confirmed value retains its original effective answer evidence;
the separate confirmation visit records that it was reviewed. Do not relabel
question editing time as an implicit association or reaction-time measure.

All visits, commits and resulting local cursor/draft/answer changes must be
prepared on a candidate and written together using the existing copy-on-write
IndexedDB queue. A storage failure leaves both visible navigation and effective
answers unchanged. Await the durable write before rendering another visit.
Network synchronisation may see only committed local journal entries. A slow
ACK, repeated click, race with Back or withdrawal cannot create two current
heads or transmit a mutation whose local transaction failed.

Use the existing sequence/batch/operation idempotency for retries. Offline edits
within the current occurrence are allowed while the bounded journal is writable.
The boundary review displays `Saving answers` and waits for seal acknowledgement
before any next timed stimulus/task. If the receiver rejects a transition,
display an actionable conflict/recovery message; do not silently discard the
local journal or continue into the next exposure.

Resume metadata for an enabled unsealed occurrence must include its frozen ID,
transition version, current target, previous visit identity, effective head IDs,
visible/reached status and a projection hash. Reload creates a new visit and
null initial RT. Reconcile the local acknowledged prefix with server state
before applying pending events. A matching unsubmitted draft may be restored
only from local storage; the server must not invent one. If local storage was
lost, recover committed answers and expose that unsent edits are unavailable.

Bound resume payloads explicitly using the existing question/text/journal
limits. Return a clear retrieval error or a source-bound paged projection when
the full answer snapshot exceeds the response budget; never silently truncate
text, structured answers or invalidation history. A pager, if needed, is an
implementation detail beneath the same single resume action, not extra user
clicks. Test the selected bound before claiming all supported long-text designs.

Existing timed-task and camera reload rules prevail. An active browser camera
recording still ends the study interrupted on page reload; Back does not join
containers across page instances or pretend missing recorded time exists.
Within the same page, questionnaire editing can extend recording time, so
normal duration/byte limits and actual capture-stop interruption remain active.
Keep new questionnaire visit/review events as `active_response`; do not assign
their physiology to the preceding passive stimulus interval.

## Effective records, analysis and retained history

Expose one authoritative pure projection, for example:

```r
brohn_questionnaire_revision_projection(protocol, events)
# schema, policy_hash, protocol_hash, events_hash, sealed_occurrences,
# effective_records, history_records, invalidations, quality
```

For the enabled profile, each effective item identity is
`run_id + occurrence_id + question_id`; preserve `question_step_id` and the
existing `exposure_id` separately. Include its current head event ID, predecessor
chain, first/current visit, revision count, typed value, missing status and exact
source hashes. Only sealed completed-run projections enter automatic completed
reports. Interrupted runs may have a separate descriptive audit, without a
false complete-scale or study-completion claim.

Preserve existing scale identities: `scope:before`, `scope:end` or
`stimulus-step:<actual preceding stimulus step id>`. The occurrence ID is
additional source evidence, not a new participant, session, condition or scale
assessment. Replaying five edits must still yield one item in one scale
assessment. Keep the general scorer's duplicate ambiguity rejection for
unqualified/flat imports; the qualified reducer resolves only its own versioned
revision histories.

`brohn_analyse_runs`, `brohn_scale_run_responses`, questionnaire contrasts and
the explicit-response side of multimodal synthesis must consume this same
effective projection. No separate last-response filter in each consumer.
Effective missing states are explicit: optional omission; never displayed;
invalidated then not displayed; invalidated and currently awaiting an answer;
never submitted in an incomplete occurrence. Keep previous values only in
history, not current means, scales, liking correlations or denominators.

Provide two complete exports: effective responses for normal analysis and
append-only answer/visit/invalidation history for audit. Each row includes exact
run/occurrence/question/step/head identities and typed JSON value; CSV escaping
and exact JSON serialization follow the existing report contracts. The report
records the original event artifact hash, projection hash and reducer source
identity. HTML explains the policy, final-answer denominators and revision count
without rendering hidden historical answers by default. Source bytes and
previously published reports remain immutable on reanalysis.

Reimport the effective-response export through an explicitly mapped current-row
contract. Do not present a history CSV as a normal one-row-per-question dataset.
A later history importer must verify its declared revision policy, predecessor
chain, protocol/source hashes, occurrence identity and completed projection.
The existing generic duplicate-response import failure remains until that
connected source-bound path is implemented.

## Integration seams and delivery order

| Owner/file seam | Required change |
|---|---|
| New pure `R/platform-questionnaire-revision.R` | Validate named policy/manifests/events; reduce visits, current heads, dependencies and sealing; expose effective/history projection and resume state. Unit tests own all typed, branch, version and assessment invariants. |
| Core compiler/validator/clone/portability | Optional field with absent legacy byte compatibility; two-pass occurrence/review decoration; preserve original question/step/option order; fresh clone identities; policy/hash retained in portable round trip. |
| `platform-delivery.R` / service launcher | Load the reducer; new event allowlist/dispatch after normal envelope/clock/ref checks; prohibit bypass events for enabled questions; atomic durable replay, resume, finish guard. Keep existing bearer, closure, ACK and origin rules. |
| Participant module + runner | Reuse all current question widgets; add occurrence controller, Back/review, click/draft freeze, dependency clearing, live status/focus and current answer restoration; integrate copy-on-write journal and ACK-before-timed seal. No own network transport or camera bypass. |
| `platform-jobs.R`, analysis/scales/multimodal | One shared effective projection before existing descriptive scoring; full history artifacts and projection/source identity in the supervised input/output closure. Existing saved cohorts stay pinned. |
| Researcher question/release UI | Explicit policy choice and concise dependent-answer/sealing explanation; current legacy state visible; preview actual boundaries. No arbitrary custom policy combinations. |
| Reports/downloads/Data mapping | Current-response and history labels, full immutable exports, reusable effective-row contract and exact reopened values. |

Implement in this order: pure reducer and independent fixtures; compiler and
real receiver replay; effective analysis/export adapters; participant controller
with actual IndexedDB failures; authoring and complete actual browser journey.
Do not expose the author toggle until every connected path supports the pinned
profile. Do not use a broad new navigation framework for timed tasks or MaxDiff.

## Required acceptance evidence

1. **Legacy compatibility:** absent policy gives byte-identical old assigned
   protocols and order on new starts; old response events/reports/imports retain
   their established interpretation. Enabled clone/template/ZIP round trips
   preserve the policy and typed questions under fresh identities.
2. **Original arithmetic:** item A initially 2, revised to 6; item B 4. Exactly
   two effective items and one complete mean 5; history keeps all commits and
   confirmations. Reanalysis, CSV/JSON/report envelope and reopening preserve
   the same binary64 values/source hashes. A historical duplicate legacy item
   remains ambiguous rather than being silently healed.
3. **Branch invalidation:** answer driver A so B and B-dependent C appear; submit
   both; Back changes A so B hides. B/C heads and drafts are invalidated. Change A
   back; B/C require fresh answers. Exercise nested AND/OR/NOT, `answered`, exact
   numeric versus text membership and false/0. An independent later D remains
   effective and prefilled. Also test a changed driver whose dependent remains
   visible: the declared conservative policy still requires reconfirmation.
4. **Last-item correction:** after the last question, review permits editing;
   no next baseline/fixation/stimulus is started before a valid seal ACK. An
   all-hidden remaining branch still reaches review without an infinite loop
   or a fabricated optional answer.
5. **Assessment identity:** two actual control/test stimuli with identical
   question IDs have distinct occurrence anchors and two scale assessments.
   Revisions after control never alter test answers, assignments or earlier
   timed onset/finish events. Section/group boundaries do not increase counts.
6. **Complete widget semantics:** typed single/multi/dropdown, text/long-text,
   number, untouched slider, matrix optional-null row, keyboard ranking and
   allocation retain correct committed-versus-draft state. Information steps
   acknowledge without a scored response. Required errors focus the same visible
   form and never prevent withdrawal.
7. **Real durability faults:** inject actual IndexedDB transaction failure on a
   commit/navigation; same visit/cursor/head remains visible and nothing is
   transmitted. Retry yields one event. Lose network ACK, reload with a pending
   batch, resume with and without local drafts, and verify exact receiver event
   order and seal. Do not substitute only a component transport stub.
8. **Receiver counterexamples:** reject a foreign occurrence/question/head,
   stale state version, duplicate new commit within one visit, invalid typed
   answer, illegal future jump, previous sealed occurrence, mixed page clock,
   seal with unmet required fields and legacy-event bypass. Reject post-closure
   revision. Confirm duplicate identical transport is safe and does not create
   another version or report job.
9. **Timing/capture:** first uninterrupted response has supported visit timing;
   changed/resumed response initial RT is null. No replay of a timed trial or
   stimulus. Camera-active reload retains the established interrupted ending;
   explicit optional camera decline follows normal questionnaire recovery.
10. **Researcher journey/accessibility:** author and release the named policy;
    real participant uses keyboard Back/Edit/review, branch clearing is announced,
    focus moves to the correct question/error, narrow 390px layout and axe pass,
    researcher downloads current/history/protocol, sees one automatic saved
    scale/liking result and reopens it. Report counts, source hashes and absence
    of passive-viewing contamination are checked independently.

These are implementation gates, not completed results. Method suitability,
participant comprehension and any physical timing claims still require their
own evidence; the software contract specifically prevents rewriting observed
exposures while allowing honest questionnaire corrections.
