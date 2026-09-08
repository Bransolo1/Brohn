# Next questionnaire and implicit-task delivery audit

Snapshot: 8 September 2026. Read-only planning audit; no product code changed.
Execution was limited to original, in-memory compiler and arithmetic probes. Existing test files
were inspected, not rerun or counted as newly passed evidence.

## Decision

The next broad-use vertical slice should be **dependency-safe questionnaire
sections with reproducible participant assignment**, beginning with the concrete
answer-order defect below. This improves ordinary eye-tracking-plus-liking and
commercial survey studies without requiring a new scientific model. Deliver its
authoring, frozen compilation, participant presentation, reuse and report audit
together. Back navigation is the next distinct slice: it needs an answer-revision
contract, not a button that decrements the current step.

An independently buildable methods slice is a **source-bound import and cohort
report for the already implemented IAT/BIAT profiles**. Adding another task name
before that route is complete would leave commercial teams manually combining
participant scores. Of the requested new paradigms, GNAT has the smallest new
execution mechanism and an explicit sensitivity recipe; AMP and evaluative
priming need a shared multi-phase trial mechanism. The subsequent
[SC-IAT source audit](SCIAT-IMPLEMENTATION-CONTRACT.md) resolves the prepared
variant's quotas and scorer inputs; vendor-runtime replay and feedback/sampling
semantics remain specific qualification gates.

This follows the authoritative [MASTER](../MASTER-ARCHITECTURE.md), sections 1,
4 and 6; [build manifest](../preparation/build-manifest.json), BWP04/BWP05/BWP10;
and [UX-J03](../product/journey-acceptance.json), whose acceptance explicitly
includes changing a branch-driving answer, preserving response history and
removing hidden dependent answers from current results. BWP04 remains
`implementing`; its broad acceptance text must not be read as completed behaviour.

## Implemented contracts and exact remaining seams

| Area | Current implementation | Remaining work and user consequence |
| --- | --- | --- |
| Question types and validation | `brohn_question`, `brohn_validate_question`, `.brohn_delivery_answer`; `questionFields`, `validate`, `showQuestion` in the browser. Frozen typed options, required/optional answers, numeric ranges, matrix/ranking/allocation validation are implemented. | Richer requested-response versus required behaviour, question/choice piping, translations and instrument blocks are not represented by the current question schema. Do not substitute an ordinary numeric option code for a quantitative scale item. |
| Display logic | `brohn_validate_rule` and `brohn_rule` in [platform-core.R](../../R/platform-core.R), `brohn_flow_earlier`/tree operations in [platform-question-flow.R](../../R/platform-question-flow.R), browser `ruleMatches`/`answersFor`. AND/OR/NOT, answered, typed equality/inequality, numeric thresholds and membership are present. | This is conditional visibility, not a general branch graph. There is no destination node, branch action, screen-out outcome, loop or repeat-until node in the design/receiver contract. New matrix-row, rank-position or allocation-option predicates also need explicit typed operators. |
| Earlier-answer scope | `brohn_flow_earlier`, design validation and `.brohn_delivery_effective_answers`: before questions use earlier before answers; after-each uses before plus earlier answers for that stimulus; end uses before plus earlier end answers. | End questions cannot silently read the last after-each response. Cross-exposure comparisons need an explicit referent. Future repeated instances of the same stimulus need exposure-instance keys, because the current answer cache keys after-each answers by stimulus ID. |
| Hidden questions | Browser `present` emits `step_finished` with `skipped=true`, `reason=display_logic`. `.brohn_delivery_apply` checks the same frozen predicate; `_advance` may bypass hidden questions during recovery. | A hidden question is not a voluntary skip, ordinary null response or screen-out. Optional null is presently an omission; there is no separate general declined-answer status. Reports should expose these distinct states rather than infer them from absence. |
| Stimulus and option order | `brohn_compile` supports fixed, cyclic counterbalanced and seeded randomized stimulus order. It materializes option order in each frozen question step. | Option randomization currently omits participant allocation from its seed; see the measured defect below. Cyclic stimulus rotation is not a general balanced Latin-square or mixed-design allocator. |
| Questionnaire/task blocks | `design.questions` is a flat ordered list with three scopes. `design.blocks` is validated entirely through `brohn_task_validate`. | `design.blocks` contains timed implicit/RT procedures, not reusable questionnaire sections. There is no question-order, questionnaire-block-order or subset-selection policy. Timed task blocks execute in saved order after all stimuli, then MaxDiff, then end questions. No arbitrary task/question interleaving is implemented. |
| Recovery and back | Browser `advance` appends response + finish and increments its index; `.brohn_delivery_apply` advances a single cursor and validates current step order. Untimed question/instruction/MaxDiff recovery is supported; timed interruption remains explicit. | No participant Back action or legal navigation event exists. A previous completed question cannot simply restart. Editing a completed answer requires versioned current-answer selection, dependency clearing and a bounded navigation policy shared by browser, receiver and analysis. |
| Answer-history scoring | `.brohn_delivery_apply` can replace the value of an active question in current state. `brohn_analyse_runs` currently consumes every `response` event; `brohn_score_run_scales` preserves assessment evidence and `brohn_score_scales` rejects ambiguous duplicate items. | The current browser emits one committed response per completed question. Enabling edits without a new reducer would double-count raw responses or make scales unscoreable. A valid event journal is not yet a resolved answer-revision history. |
| Existing timed tasks | `brohn_task_profiles`, `brohn_task_compile`, `brohn_task_score` in [platform-methods.R](../../R/platform-methods.R); exact nested replay in [platform-task-delivery.R](../../R/platform-task-delivery.R); five matching profiles in [tasks.js](../../www/participant/tasks.js). | Enabled profiles are IAT D1, good-focal BIAT, Brohn keyboard AAT cue task, simple RT and four-choice RT. SC-IAT, GNAT, priming and AMP are absent and correctly rejected as unregistered. Keyboard initiation is not a physical joystick movement measure. |
| Task reports/imports | `brohn_analyse_runs` scores received frozen task trials; results preserve participant/session, profile, counts and direction. Portability preserves task definitions and assets. | Task scores remain participant/task descriptive records, without a declared cross-person task summary recipe. `brohn_analyse_input` has no dedicated source-bound `implicit` dataset import/scoring branch; raw-file preservation does not provide vendor/task scoring compatibility. |

Primary implementation locations: [compiler](../../R/platform-core.R),
[receiver](../../R/platform-delivery.R), [participant renderer](../../www/participant/runner.js),
[run analysis](../../R/platform-jobs.R), [scale scorer](../../R/platform-scales.R),
[task authoring](../../R/platform-task-views.R), [portability](../../R/platform-portability.R).
Prepared behaviour details are in [display-logic authoring](../methods/QUESTION-FLOW-BUILDER.md)
and [scale scoring](../methods/QUESTIONNAIRE-SCALES.md). The five-profile registry
was confirmed by loading the current shared modules.

## P0: correct or explicitly name answer-order assignment

In `brohn_compile` (currently lines 272–276), option shuffling uses
`design$seed + length(timeline)`. It does not include `allocation_index` or a
question/assessment identity. A six-option before-study question compiled for
allocations 1 through 12 produced **one unique order**:
`choice5, choice1, choice2, choice4, choice3, choice6`.

This is a reproducible shuffled layout, not per-participant random assignment.
The small read-only probe used an original survey, six original option IDs and
`randomize_options=TRUE`; it created no deployment or participant records.

Next correction must distinguish policies such as fixed saved order,
once-per-study shuffle and per-participant shuffle. Bind the selected policy to a
versioned deterministic assignment using immutable identities, allocation and
assessment/exposure scope. Adding an unrelated earlier question should not
silently change another item's assignment merely by shifting its timeline index.
Keep existing frozen releases and their realized order unchanged. Persisting a
seed is insufficient if the assignment algorithm changes without a version.

Required acceptance: exact seeded oracle; identical retry/resume order; varied
orders across a prespecified multi-allocation fixture; zero/false/text codes
unchanged; unchanged unrelated-question assignment; old frozen release replay;
actual participant export showing the same displayed order. Statistical balance
is a separate policy—ordinary shuffle must not be labelled even allocation.

## Next complete slice: questionnaire sections and safe ordering

Student story: “I have demographics, concept liking and reasons. Keep dependent
follow-ups with their parent, vary the independent sections, and show exactly
what each participant received.” Commercial benefit: less manual order control
and reusable sections with auditable assignment.

Use a new optional, versioned questionnaire-section field; do not reinterpret
`design.blocks`. A section needs immutable ID, label, question IDs, one existing
scope, and explicit fixed/shuffle policy. Each included question belongs to at
most one section. Define legacy flat questions as fixed ordered sections for
compilation, without rewriting historical studies. Section instance identity and
realized section/question/option order become protocol fields and report
provenance. The existing flat participant timeline can remain the execution
representation, so timing and receipt machinery need only narrow hooks.

First release should shuffle **independent units only**. A question and its
dependent follow-ups move together with fixed internal order, or the editor
explains why their order is fixed. Cross-section dependencies must be rejected
or explicitly fixed before publication. Do not silently perform a nonuniform
topological shuffle and describe it as unconstrained randomization. Keep the
current before/after-each/end scope rules; do not introduce unbounded loops,
adaptive sampling or arbitrary jumps in this slice.

Proposed independent ownership: a new section domain/assignment module plus
authoring view and fixtures. Parent-owned hooks remain narrow in core validation,
compiler, cloning, portable export/import, participant section labels and report
provenance. A pure domain packet can be built alongside other work before shared
hooks land; the slice is complete only after the real researcher/participant
journey passes.

Acceptance cases:

1. Author two independent sections and one conditional parent/follow-up unit;
   keyboard reorder and explicit Save/Cancel preserve intended membership.
2. Invalid cross-scope, duplicated, deleted and stale question references fail
   before publishing. Renaming a label leaves identities and stored keys intact.
3. Two prespecified allocation seeds reproduce independent expected order tables.
   Duplicate start, quota races, reconnect and reload retain the same assignment.
4. A hidden required follow-up is skipped with its reason; an optional empty
   response stays an omission; numeric zero and boolean false remain answers.
5. After-each sections retain the actual stimulus and preceding exposure identity.
   Rearranging questions does not alter passive-viewing/baseline intervals or
   split one scale assessment into fake independent observations.
6. Clone/template/export/import remaps section/question references and preserves
   scoring keys; no source participant state or realized assignment transfers.
7. A researcher opens the actual participant link, completes both an exposed and
   hidden follow-up path, reopens the saved report, and sees exact realized order,
   source revision and scale evidence. Keyboard focus and accessible labels pass
   alongside the functional journey. Human comprehension remains separately tested.

## Following slice: bounded back navigation and dependent clearing

Implement back/edit only within the current **untimed questionnaire assessment**
first. Seal that assessment before another stimulus, baseline or timed task.
Never replay a timed exposure or allow navigation to alter already observed
physiology under the old exposure identity.

Specify an append-only answer revision carrying question-step/assessment identity,
revision, predecessor event, changed/committed status and reason. An explicit
navigation event records source and destination; the receiver reconstructs legal
state. A single authoritative reducer selects the effective committed answer for
each assessment item. Keep the original revision history available separately.
Changing a driver clears now-hidden dependent answers from the effective map and
records why; revisiting a newly visible question should require a fresh answer
unless the saved policy explicitly permits restoration. Do not silently resurrect
an old answer or treat its original RT as the latency of the edited response.

Acceptance must include A → B → Back to A → change A → B hidden; a second change
making B visible; nested and NOT predicates with missing answers; required-item
repair; offline duplicate delivery; reload during revision; foreign/stale step
rejection; closure of an assessment; and scales/raw-item reports counting only
the final effective answer. Old response events remain intact. Explicit branch
jumps and screen-out endings follow as a separate graph/ending contract, including
eligibility/quota consequences; display logic must not be relabelled as that work.

## Source-bound implicit-method work

Prepared references were read first: [implicit reuse](../methods/reuse/IMPLICIT-REUSE.md)
and [protocol templates](../preparation/PROTOCOL-TEMPLATES.md). Official manuals
below were then reopened for this audit. These are procedure references, not
permission to copy vendor scripts/materials or evidence of Brohn timing validity.

| Pack | Local work that can proceed | Specific evidence boundary |
| --- | --- | --- |
| Existing IAT/BIAT import and cohort | Define exact source procedure/profile, frozen block/category mapping, first versus final-correct fields, original source hash, identity columns and source-output row provenance. Reuse the implemented scorer only when these contracts match. Add declared participant-level aggregation and uncertainty; repeated sessions require an explicit rule, not extra independent people. | Prepared hand/upstream arithmetic exists. A vendor export labelled “D” alone does not establish compatibility; its scored blocks, errors and exclusion denominators must match. Imported or collected trial rows cannot be treated as independent participants. |
| SC-IAT | Implement a distinct three-category compiler and rehearsal for the candidate in the [focused source contract](SCIAT-IMPLEMENTATION-CONTRACT.md). Its source audit resolves exact block quotas, test-score input selection, sign and fast-response denominator. Do not feed its two test blocks into the full-IAT four-score-block reducer. | The official manual explicitly distinguishes its forced correction/no fixed response window from Karpinski–Steinman's procedure. The focused audit subsequently inspected the exact vendor source; runtime SD, sampling and feedback receipts remain gates before activation. Preserve that candidate's source identity and original Brohn implementation. [SC-IAT manual](https://www.millisecond.com/library/v7/iat/sc_iat/singlecategoryiat/singlecategory/singlecategoryiat.manual) |
| GNAT | Add a named Go/No-Go deadline contract: expected action is respond or withhold; distinguish hit, miss, false alarm and correct rejection. Record full deadline completion even with no key. Score each declared deadline/association cell, with explicit signal/noise support and boundary correction. | The official demo is explicitly minimalist. Its procedure says 750/600 ms while some summary labels say 700/550; freeze actual declared settings. Its exact 0/1-rate adjustment is .005/.995, not a universal correction rule. Duration reduction requires new evidence, not an “agile” label on the demo. [GNAT manual](https://www.millisecond.com/library/v7/gnat/gnat/gnat/gnatdemo.manual) |
| Evaluative priming | Add prime/blank/target/ITI phase events, target-specific baseline support, persistent prime-pair assignments and a named facilitation scorer. An absent correct baseline for a target yields unavailable facilitation, not zero. | The prepared supraliminal adaptation matches prime categories to the same adjective targets and includes separate baselines/fillers. Semantic or masked priming is not enabled by renaming this pack. [Evaluative-priming manual](https://www.millisecond.com/library/v7/evaluativepriming/evaluativepriming/evaluativepriming.manual) |
| AMP | Use the same phase engine for prime → blank → ambiguous target → mask/evaluation. Store target/prime assignment and mask/response policy. Report pleasant-response proportions and declared neutral-prime contrasts; RT remains descriptive. | The source profile uses 75/125/100 ms stages. Refresh quantization and observed onset/offset must be retained; “75 ms requested” is not physical delivery evidence. Missing evaluations are not unpleasant answers. Reviewed ambiguous targets/materials and language suitability remain study-specific. [AMP manual](https://www.millisecond.com/library/v7/amp/amp/amp.manual) |

### Smallest new paradigm slice: GNAT

GNAT avoids a new prime/mask sequence while forcing the correct distinction
between a valid withheld response and a missing response. The existing task
schema/scorer assumes a correct key and, for correct outcomes, a response latency;
therefore a null-key/no-latency correct rejection needs an explicit new contract.
Do not weaken existing IAT correction or RT timeout checks globally.

Use the prepared configured profile with original rehearsal materials, frozen
signal/noise category roles, per-cell counts, deadline round, practice policy and
assignment. Required pure arithmetic fixture: 8/10 hits and 2/10 false alarms give
`d' = 1.6832424671458286`, criterion 0 within floating-point tolerance; swapping the rates reverses d'. Test exact
0/1 corrections separately, preserving uncorrected counts. A zero denominator,
missing cell, interrupted deadline, absent display onset or hidden tab cannot
produce a completed cell. Do not silently pool deadline rounds.

The vertical acceptance is author → rehearse → publish → actual Go/No-Go browser
responses → server replay → immutable participant report → explicitly declared
cohort summary → portable reuse. Test a correct withholding with no RT, early
keys, late keys, exactly-at-deadline policy, repeated keydown, practice exclusion,
malformed events, cancellation/reload, and independent direction/count oracles.
Device timing qualification and reliability for a shortened consumer protocol
remain external evidence; original implementation and synthetic correctness
fixtures do not require a paid service or physical device to proceed.

## Release-order ledger

1. Correct/name option-assignment semantics and preserve old releases.
2. Questionnaire sections with dependency-safe ordering, reuse and an audited
   participant/report route (BWP04/BWP05).
3. Bounded untimed answer revision/back/clearing, then explicit branch endings
   (BWP04/BWP05 and UX-J03).
4. In parallel: source-bound imports and declared cohort results for current
   task profiles (BWP10/BWP13), then GNAT's distinct withholding contract.
5. Shared multi-phase trial evidence, then AMP and evaluative priming separately.
   SC-IAT activation follows its resolved source-bound scorer, not a generic D.

Local implementation work includes schemas, authoring, deterministic compilers,
server/browser parity, immutable imports/reports, scoring fixtures and accessible
error recovery. External evidence is narrower: chosen material permissions and
population suitability, the remaining SC-IAT runtime reference receipts, physical
display/input timing, method-specific reliability and observed novice
comprehension. No missing screenshot or package install blocks the local slices
identified here; this audit did not download scripts, assets or videos.

## Audit identity

Relevant source SHA-256 at inspection (other files were read for contracts):

| File | SHA-256 |
| --- | --- |
| `R/platform-core.R` | `d8d9aa19aa5bd66073771c56a148ab95bce0ab570b231dc8be7bd665250c24a9` |
| `R/platform-delivery.R` | `72bdddd8d8d0965e2e0ca681ed27fc1b194174a58dc6db10dafbdb89f8dc5b9e` |
| `R/platform-methods.R` | `06f3af8a1157d39105712be768a44da5175f6b718dc50b7ce8de1f71460a476c` |
| `R/platform-task-delivery.R` | `de00579d46c7fe702c3d9ef633b9f9786c940efe57840d4b3c0f19b0b70d5636` |
| `R/platform-jobs.R` | `a3a3fe5118474b4fce0730fbdfc3ebd28a11d16119177205432c31bacbb4da7a` |
| `R/platform-scales.R` | `5ae113ae1370f0272c6a11d369cf9f52433f3100c938b85b76fed05ab26cd71a` |
| `www/participant/runner.js` | `3ced568095d2906cdd1a411ac334bd7d3383cd75e8f2b23e0ed549daed43d092` |
| `www/participant/tasks.js` | `05b2f810b335f8d677a8884bc8ace5401989064bddddbdf8765e1d22c24e01de` |
