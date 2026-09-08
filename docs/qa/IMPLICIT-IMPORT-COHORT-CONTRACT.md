# Implicit task import and cohort report contract

Original read-only audit, 8 September 2026. No product source, installed package, running
service or scientific worker was changed. Original arithmetic and receiver/scorer
boundary probes ran in memory against the source identities at the end of this
document. The historical seam review below records the starting point; the
implementation addendum supersedes its proposed import status.

## Implementation addendum

The five-profile import is now connected through retained original CSV/TSV,
immutable protocol registry, exact study/task mapping, supervised analysis and
saved reports. The assigned-protocol modal exports original native trial rows,
the matching registry and evidence notes. Summary reimport explicitly reduces
the evidence level to declared trial summaries; it does not acquire the original
journal's replay, clock, key or frame evidence. See
[the import method guide](../methods/IMPLICIT-TRIAL-IMPORT.md).

The pure import suite passes 114 checks. A separate 20-check decimal interchange
suite covers native 17-digit scientific notation, subnormal values and rejected
nonzero underflow. These are exact parser and source-preservation checks, not
timing qualification. Native full-journal export/reimport passes 15 checks and
the mapping UI has 14 R/Shiny checks. The saved-worker suite passes 46 checks,
including three published reports and two deliberate pinned-source failures;
that worker execution preceded the decimal-parser extension. The fresh actual
browser export/intake/import journey passes 19 checks/five accessibility scans,
including two scientific publications against the extended parser. See
[the executed journey](NATIVE-TASK-IMPORT-RESEARCHER-JOURNEY.md).

The descriptive cohort domain passes 68 pure checks; its connected storage has
45 checks and the reviewed identity/membership UI has 33 Shiny checks. The
actual saved-worker journey passes 29 checks/five publications; the browser
journey passes 19 checks/five accessibility scans. The optional report-title
extension has seven checks and one actual saved analysis of original seeded
source reports. These results remain
scoped evidence rather than a full-platform release claim.

## Recommended next slice

The metric-specific RT support correction below is now implemented and tested.
The source-preserving import/export path and descriptive cohort report are
connected for the **five existing exact profiles**. Their contract uses Brohn-compatible trial summaries plus
a frozen protocol registry. An arbitrary vendor CSV is not automatically compatible
because its columns say IAT, correct or latency. Vendor-specific converters can
later produce this contract after their procedure and timing definitions are
reviewed. Do not add a generic D-score switch.

Reuse the existing `implicit` data family, immutable originals, explicit mapping,
fenced analysis jobs and report publication. It is already a retainable source
family in `brohn_ingest_dataset` / `brohn_queue_ingestion`; its formerly rejected
analysis branch now validates the exact mapping and frozen registry. This fills
that gap within the existing acquisition and storage system.

## Original audit: implementation seams before this slice

| Existing function or contract | What can be reused | What must be added or kept distinct |
| --- | --- | --- |
| `brohn_task_profiles`, `brohn_task_validate`, `brohn_task_compile` in [platform-methods.R](../../R/platform-methods.R) | Exact profile IDs, material/category roles, reviewed controls, deterministic compiled trial tables and assignments | A validated import registry and explicit compilation provenance. A seed or profile name alone is not the realized presentation. |
| `brohn_task_score`, `brohn_iat_d1` | Profile-specific arithmetic on trusted terminal response summaries | They are not complete public import validators. Preserve all original rows and perform outcome/timing consistency checks first. |
| `.brohn_task_delivery_apply` / `.brohn_task_delivery_complete` in [platform-task-delivery.R](../../R/platform-task-delivery.R) | Strict instruction/trial cursor, page-clock boundaries, onset/key/summary consistency, forced correction, deadline and interruption checks | A Brohn journal import can replay this contract. A summary-only external CSV cannot acquire invented clocks, key histories, frame observations or replay status. |
| `brohn_analyse_runs` in [platform-jobs.R](../../R/platform-jobs.R) | Completed saved run membership, terminal task events, task scores, run/event hashes and declared alias linkage | Currently emits per-administration cards, not a person-aware task cohort summary. It extracts already validated terminal events; it does not itself replay the whole task journal before scoring. |
| `brohn_queue_cohort` | Freezes completed release membership and separates study designs/origins | Its current recipe is explicit questionnaire responses. Add a named task-cohort plan rather than claiming trial rows are independent people. |
| [MaxDiff import](../../R/platform-maxdiff-import.R) and `brohn_score_run_maxdiff` | Character-preserved CSV/TSV; exact design binding; original row hashes; explicit source selector, origin, linkage and missingness; journal replay before native reports | Task trials additionally need first/final response distinctions, actual presentation order, correction/deadline semantics and method-specific exclusions. MaxDiff aggregate choice weighting is not an equal-person task-score policy. |
| `brohn_export_report_csv` / `brohn_report_content` | Accessible report shells and exact numeric serialization | The generic CSV chooses questionnaire observations first, then other available rows. In mixed studies it does not export all task results. Add dedicated task trials, administration scores and cohort downloads. |
| `brohn_analysis_plan_metrics` | Existing explicit comparison-family and multiplicity machinery | Its registered outcomes are gaze and questionnaire/scales. Task outcomes are not registered. Do not silently feed IAT mappings A/B into study-condition comparisons. |

`compiled$origin` means **material origin** (`synthetic` or
`researcher_supplied`). A run/dataset's `origin` means **collection origin**
(`sample`, `preview`, `pilot`, `live`, `imported`). Keep both in every export and
report. Existing task cards already label the former as materials.
Follow the existing source-origin gate: original synthetic demonstration materials
remain sample/preview imports. A file or mapping edit cannot upgrade them to
pilot/live research evidence.

## Minimal interoperable file and identity contract

The first adapter accepts one CSV/TSV plus one immutable JSON protocol registry
for one selected task definition. Multiple allocations/administrations can share
that registry. Suggested initial bounds: 20,000 source rows, 1,024 uniquely named
columns, 16 MiB registry, and no silent truncation. Larger collections can be
explicitly split and combined through frozen, reviewed cohort membership.

The registry is `brohn-implicit-protocol-registry/1.0`:

```text
{
  schema,
  task: <the complete original brohn-task-block/1.0>,
  protocols: [
    {id, compiled_hash, compiled: <complete brohn-compiled-task/1.0>}
  ]
}
```

Each registry entry retains all instruction and trial order, block IDs, trial IDs,
score-block/pair flags, category/material identities and content/asset hashes,
correct/allowed keys, side assignment, cue/action/position, foreperiod,
intertrial/timeout/zoom settings, design hash, allocation and source rationale.
The task must match the selected immutable study task definition; each entry
must match its task hash and a supported compiler contract. No arbitrary fields
can change a scoring window or mark extra trials as scored. Compiler checks
must compare the complete normalized table, not merely total trial counts.

V1 can deliberately accept only supplied Brohn compiled tables matching the
registered task/allocation. Other vendor formats remain preserved with concrete
unsupported/missing-evidence reasons until a named adapter exists. A later
reviewed external-table adapter must validate the complete method constraints;
it cannot substitute current Brohn randomization for an unknown original order.

Store the registry itself as a hashed object, not an editable filepath. Store
mapping revision/hash and the exact linked study revision/hash. A protocol hash
means byte-semantic identity under Brohn's versioned R canonical JSON encoder,
not generic cross-language JSON hashing or historical authorship proof.

The stored native run protocol has no transport URLs. Delivery only augments
renderer copies in `.brohn_delivery_protocol_urls`. Export the stored version:
never export participant access tokens or deployment asset-token URLs. Preserve
asset content identities. A design template or clone has new identities and
does not implicitly inherit collected data; incompatible hashes need an explicit
source-design selection, not silent re-keying.

Required mapped CSV fields:

| Field | Exact semantics |
| --- | --- |
| `participant_id`, `participant_linkage` | Original code as text; explicit boolean declaring whether it identifies repeat visits. `NA`, `001`, `0` and Unicode remain distinct text. This is a declaration, not verified identity. |
| `session_id`, `attempt_id` | An explicit session and task administration. A retake is another attempt, never extra rows appended to the first administration. |
| `protocol_id` | One exact registry entry. Its profile/task/hash cannot vary within an attempt. |
| `presentation_index`, `trial_id` | Explicit realized ordinal among task trials and exact frozen trial ID. Join by these identities; source file row order is preserved as provenance but never substituted for observed order. |
| `presented` | Explicit boolean. A planned but unpresented trial is different from an onset followed by no response. |
| `outcome` | `correct`, `incorrect`, `timeout`, `interrupted`, or import-only `not_presented`. The last never enters the scorer as a measured trial. |
| `first_code`, `final_code`, `first_correct` | Original accepted first key, terminal correct key, and explicit first-response correctness. No response uses null keys and false first-correct, with a separate responded flag derived from the key; it is not automatically an error. |
| `first_response_ms`, `final_correct_ms` | Separate decimal millisecond strings measured from target onset. Empty only when genuinely absent. A final-correct time is not an added error penalty or a first-key time. |
| `missing_reason` | Required for interrupted/unpresented/source-missing evidence; retain actual source reason. A timeout means a declared observed response window expired, not merely a blank cell. |

Named source constants belong in the saved mapping rather than being guessed:
`task_id`, `origin_statement`, `source_collection_id`, collection software/version
when recorded, source RT definition, deadline/terminal-response rule, evidence
level and registry object/hash. Optional selectors for mixed-task/origin files
must be explicitly mapped, as in MaxDiff; every nonselected row keeps its source
row hash and exclusion reason. A source-declared protocol/code hash is retained
separately from a hash calculated during import. Missing original software
identity stays unknown; the analysis worker's code hash is not a collection-time
renderer hash.

Use `brohn_read_table`'s character-preserving reader with `na.strings=character()`.
Use a dedicated strict RT parser, not `brohn_numeric`, which currently treats
literal `NA`, `NaN` and `null` as missing. Empty nullable cells alone become null;
unexpected numeric tokens are review errors. Keep raw decimal strings alongside
checked finite numeric milliseconds. No missing-as-zero, silent unit conversion,
apostrophe removal, rounding, factor coercion or reclassification from column
labels. Boolean tokens should use the existing explicit MaxDiff allowlist.

An attempt record should contain:

```text
schema = brohn-task-attempt/1.0
id, source_collection_id, source_attempt_id
participant_id, participant_linkage, session_id, attempt_id
task_id, task_definition_hash, protocol_id, compiled_hash, profile
collection_origin, material_origin
completion_status, evidence_level
source = {dataset_id, revision, original_hash, mapping_hash,
          registry_object_hash, selected_original_rows, selected_rows_hash}
responses, trial_audit, score, timing_quality, missing_reasons
```

`id` is source-bound; duplicate original rows must not create extra trials.
The logical tuple collection/session/attempt/trial also detects repeated export
copies within a reviewed cohort even when file hashes differ. Source namespaces
must remain explicit across imports; identical person labels in two files do
not establish linkage or disjointness.

## Evidence and outcome validation before scoring

Use two visible evidence levels:

- `brohn_journal_replayed`: complete original protocol and receipt/event journal
  pass the delivery replay and terminal-state checks. Retain original event
  sequences/hashes, clock instance/origin, onset and key history. Browser time is
  still an observation, not physical display/keyboard qualification.
- `declared_trial_summary`: an external summary matches the bound procedure and
  passes all summary consistency checks. Missing original clocks or correction
  key history are recorded as unavailable. It cannot claim journal replay or
  timing quality. If required first/final latency semantics are unavailable, keep
  rows and return unavailable scoring; never invent them to satisfy the API.

For either level, all expected trials must be accounted for before a complete
administration score. An absent row creates an explicitly **derived expected-gap
diagnostic**, not a fabricated source row. Unknown trial IDs, duplicate trial
identity/ordinals, contradictory source protocol/origin and changed definitions
are structural import failures. Legitimate omissions, interruptions, unpresented
tail trials or insufficient scoring support retain the source and produce
unavailable/excluded administration outcomes with reasons.

Summary checks must enforce at least:

1. Correctness agrees with the frozen key, and keys belong to that trial. First
   key and first latency are both present or both absent. First-correct requires
   correct outcome and equal first/final latency within the declared numerical
   tolerance. Final-correct cannot precede first response or outlive the frozen
   acceptance deadline; retain the receiver's fixed 0.002 ms arithmetic tolerance,
   rather than allowing an arbitrary researcher-selected deadline tolerance.
2. A non-forced correct outcome has one correct first response; it cannot contain
   an erroneous first response followed by a correction. Non-forced incorrect
   requires a genuine wrong first response and no final correct key/time.
   Non-forced timeout has no accepted response. Never count the same response as
   both an error and an omission through a contradictory outcome label.
3. IAT/BIAT allow wrong first keys followed by final correction, preserving both
   latencies. Any unresolved correction/timeout/interrupted trial makes the
   administration incomplete under these existing profiles, including practice.
4. Anticipatory, held/repeated, synthetic or after-deadline keys cannot become
   accepted first responses. Preserve their observed counts/history when supplied;
   do not invent zeros when a summary did not record them. Source resets cannot
   be bridged with guessed clock offsets.
5. Scored/practice membership, mapping roles, pairs and AAT cells come from the
   frozen protocol, not source labels or a user checkbox. BIAT pair suffixes `p`
   and `t` are internal pair labels, not an instruction to include/exclude all
   source rows labelled practice/test in the same way as full IAT.

## Preserve five distinct scoring contracts

These rules describe the code inspected, with primary procedure references and
the existing [prepared reference](../methods/reuse/IMPLICIT-REUSE.md). They are
not interchangeable validation claims for new materials or populations.

| Profile | Included data and procedure | Scoring/support |
| --- | --- | --- |
| `iat-gnb2003-d1/1.0` | Seven blocks, 20/20/20/40/20/20/40; combined blocks 3/4/6/7 give 120 scored trials. Corrections use final-correct RT; combined practice is included. | Remove >10,000 ms, then fast fraction <300 ms over retained scored trials; exclude if >0.10. Average `(mean B-mean A)/sample SD(A concatenated B)` separately for practice/test pairs. No extra penalty/bounding/log transform. Empty pair, missing/nonpositive RT or zero SD is unavailable. Positive means faster in declared mapping A. [2003 source](https://faculty.washington.edu/agg/pdf/GN%26B.JPSP.2003.pdf) |
| `biat-nosek2014-goodfocal/1.0` | One excluded 16-trial warm-up, then four 20-trial good-focal blocks; each starts with four excluded target-only trials. Normally 64 scored trials. | Remove >10,000 ms; screen original <300 ms fraction on the remaining scored population, then bound retained RT to 400–2,000 ms. Average D from consecutive mapping pairs using sample SD. Retain correction-inclusive errors. Pair labels must follow exact ABAB/BABA assignment. [2014 source](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0110938) |
| `aat-keyboard-cue-balanced/1.0` | Original Brohn frame-cue keyboard recipe: 16 practice + 80 test; 20 test trials in each target×approach/avoid cell; Down approaches, Up avoids, cue assignment counterbalanced, 150 ms zoom feedback. | Correct first responses 200–2,000 ms inclusive; at least 4 retained trials per cell. `(avoid−approach) A − (avoid−approach) B`, in ms. Never label this joystick movement/execution or a universal AAT algorithm. |
| `rt-deary-liewald-simple/1.0` | 8 practice + 20 test, central X, B key; frozen sampled integer foreperiod 1,000–3,000 ms; task timeout is a separate recorded setting. | Correct first-response test RT 0–5,000 ms inclusive. New score schema 1.1 requires 1 retained response for mean/median and 2 for sample SD. Errors use answered test trials, including answers outside the RT window; omissions use all scored test trials. Complete uninterrupted task evidence is still required. |
| `rt-deary-liewald-choice/1.0` | 8 practice + 40 test; four equally represented positions, C/V/N/M; same foreperiod range with exact realized order retained. | Same RT summary rules, separately named profile. Position counts, incorrect responses and omissions remain explicit; no combining simple/choice RT as one population outcome. |

An IAT mapping contrast or keyboard target-B comparison is not itself a randomized
experimental study control. A packaging intervention or explicit-liking comparison
needs its own design/identity/assessment relation. Do not infer study condition
from mapping A/B, response side, category label, file name or nearest timestamp.

The prepared simple/choice description references a Deary–Liewald adaptation.
The [vendor choice manual](https://www.millisecond.com/library/v7/drearyliewaldreactiontimetask/dlc/dlc.manual)
specifies 500 ms practice error feedback and no test feedback. The inspected Brohn
renderer creates an incorrect-response message and immediately clears feedback
before its intertrial wait; it has no explicit 500 ms practice-feedback phase.
Therefore vendor procedure equivalence must not be inferred from this profile's
name. Preserve the actual Brohn recipe and record that adaptation gap; a timed
feedback change needs explicit recipe/renderer qualification. The original paper
was referenced but its full text was not newly retrieved in this audit.

## Independently reproduced findings

**Raw scorer is an insufficient import boundary.** In a complete 48-trial choice
fixture, replace one test row with `outcome:incorrect`, null first/final keys and
times, and `first_correct:false`. The pure scorer returns computed/eligible,
39 retained correct test trials, errors 0 and omissions 0. Its mean remains 500 ms.
The actual `.brohn_task_delivery_apply` rejects that same fully shaped terminal
payload: `An incorrect completion is inconsistent with forced correction or first
response.` A valid keyed baseline advanced the identical receiver state first.
This establishes a missing public-import precondition, **not a demonstrated
participant-API acceptance bug**. Do not weaken the receiver to accommodate it.

**Historical metric-support defect, now corrected.** A complete choice task
with 8 correct practice trials, 1 correct test response at 500 ms and 39 genuine test
timeouts is accepted by the timeout receiver contract. Its omission fraction is
39/40 = 0.975. At the original audit identity below, `brohn_task_score` retained the correct counts but returned
`metrics:[]` because fewer than 2 correct tests remain for the RT summary. The
correction now emits omission 39/40, error 0/1, mean/median 500 ms and unavailable
sample SD. Unknown behavior stays unknown; this case has observed nonresponses,
not missing records.

The implemented RT-only result is `brohn-task-score/1.1` with
`scoring_recipe="brohn-rt-metric-support/1.0"`. Each metric retains its own
`eligible`, `reason` and support population/count/denominator; `support_policy`
explicitly records the change from the earlier two-response whole-task gate.
Task-level eligibility means any metric is supported, never that an RT summary
or every metric is usable. Future cohort aggregation must consume per-metric
eligibility. All-timeout tasks retain omission rate 1 and unavailable error rate
with denominator 0; neither missing RT nor error rate is imputed to zero.
Named collection profiles, RT windows, non-RT scorers and immutable previously
published reports remain unchanged. The focused
[56-check regression](../../tests/platform-methods-rt-support.R) replays complete
original journals through the strict receiver and checks all five full-profile
hand arithmetic oracles. The existing method suite passes 324 checks, including
all 162 upstream IAT reference tasks. This update does not register an import
adapter or a task-cohort inference recipe.

Counts/timing omissions also deserve explicit audit fields: current result cards
show counts but omit the D scorer's `scoring_audit` pair means/SD/exclusion
denominators; early-key and frame observations survive the journal but are not
retained in `task_scores`. Export full evidence through dedicated files rather
than relying on the generic mixed-modality CSV's fallback behavior.

Original arithmetic checks matched all five scorers:

| Original fixture | Independent expected result, matching actual code |
| --- | --- |
| Full IAT: each mapping-A block alternates 500/700 ms; B alternates 900/1,100 ms. | `(400/sqrt(2,000,000/39) + 400/sqrt(4,000,000/79))/2 = 1.7719955283643436`. Centered sums and N−1 are explicit; no call to the scorer or `sd()` defines the oracle. |
| Full BIAT: same within-mapping alternation after its excluded prefixes. | `400/sqrt(1,600,000/31) = 1.7606816861659007`. Each pair contains 16 scored A and 16 scored B trials. |
| Keyboard AAT: A avoid 800/approach 500; B avoid 700/approach 600. | `(800−500)−(700−600) = 200 ms`. |
| Simple RT: test latency `300+10×trial_index`, 1..20. | Mean/median 405 ms; SD `sqrt(66,500/19) = 59.16079783099616 ms`. |
| Choice RT: `300+10×position`, ten trials per position. | Mean/median 325 ms; SD `sqrt(5,000/39) = 11.322770341445958 ms`. |

These are arithmetic and software-contract probes, not clinical norms, construct
validity, predictive accuracy or new independent author-data reproduction.

## Pinned minimal original CSV/registry fixture specification

An implementer can create the first committed fixture from this exact in-memory
specification. No fixture file was written by this audit. Under R 4.6.1 and
`RNGkind()` = Mersenne-Twister / Inversion / Rejection:

```r
task <- brohn_task_new("iat-gnb2003-d1/1.0", id="import-iat-audit")
compiled <- brohn_task_compile(task, 1L)
registry <- list(schema="brohn-implicit-protocol-registry/1.0", task=task,
  protocols=list(list(id="protocol-iat-1", compiled_hash=brohn_hash(compiled),
    compiled=compiled)))
```

Take every `task_trial` in compiled timeline order, including practice, giving 180
rows. Headers, in order, are the 15 required CSV fields listed above. Every row
has participant `P1`, linkage `true`, session `S1`, attempt `attempt-1`, protocol
`protocol-iat-1`, ordinal 1..180, frozen trial ID, presented `true`, outcome
`correct`, first/final code equal to the frozen correct code, first-correct
`true`, and an empty missing reason. First/final RT are equal: mapping A uses 500
on odd within-block trial indices and 700 on even; mapping B uses 900/1,100.
This applies to all trials, though only the designated 120 contribute to D.

Serialize all header/data cells with double quotes, escape embedded quotes by
doubling, commas between cells, **UTF-8 without BOM, LF after every row including
the last**, no spaces outside cells. Decimal RTs and indices have no leading
zeros or decimal suffix. Result: 23,720 CSV bytes, 180 data rows.

| Pinned identity | SHA-256 |
| --- | --- |
| Original task definition | `ea657cae43a441e9ed9a8e3ea8628a65330a59742aa2407b4d34efb239873a22` |
| Compiled task | `e7fd8704914e0a29dd78863d50789021890f973a8e9d82ac346b4b8c84465359` |
| Registry canonical Brohn JSON | `0a40b8b2db1c1f47b08279fbcb61d7c61fe5d1c222583e19d37e243f9e207bb5` |
| Exact CSV bytes | `a7d6fdfb544a6008fa0eb04dfd1df9cdac21f70bc4c2f266dc9c08a852de0af3` |

Expected D is 1.7719955283643436, with 40 and 80 retained trials in its two pairs,
zero slow removals and 0/120 fast fraction. Once saved, fixture protocols must be
read as frozen tables; do not regenerate expected files with a changed compiler
and silently overwrite their hashes. Additional variants must test corrected
errors, exact 300/10,000 ms boundaries, >10% fast exclusion, BIAT 6/63 before
bounding, changed material/hash, partial administrations and absent source clocks.

## Cohort and repeated-person behavior

The default is an explicit selected set of immutable administration/report IDs,
one exact task definition/profile and one collection origin. Freeze selection,
source/report object hashes, identity crosswalk and plan in the queue request.
Never replace an unavailable selected report with a newer result. Reject a source
from another project without leaking its contents. Preserve included/excluded
administrations and per-metric reasons in the final artifact.

Within a native release, explicitly supplied aliases may link visits, labelled
`supplied_alias_not_identity_verified`. Blank aliases remain unlinked sessions.
Across imported sources require an explicit crosswalk keyed by source namespace
and source person code. Shared labels, row positions and sample times do not
establish the same person. Mixed/unlinked sessions keep administration outcomes;
the initial policy withholds unique-person counts and population intervals unless
the researcher explicitly selects a completely linked subset.

Require a repeat policy whenever a person has multiple eligible administrations.
First support `one_selected_attempt_per_person` and
`equal_attempts_within_session_then_equal_sessions_within_person`. The latter
first scores every complete attempt independently, averages selected eligible
attempt scores within each session, then averages sessions within each person,
then gives each person equal cohort weight. Never recompute D from pooled trial
rows, pool simple and choice RT, choose a favorable retake automatically, or let a
person's longer file add independent observations. Preserve attempt order and
count; averaging does not correct learning or carryover effects.

Report administration N, eligible administration N, linked people N, sessions N
and contributing people **for each metric**. Cohort SD describes between-person
scores. A task RT's within-attempt sample SD is a separate outcome; its average is
not the cohort SD. A mean of participant median RTs must be labelled as such,
not as the median of all responses. Error/omission fractions retain numerator and
denominator at attempt level before the declared equal-person aggregation.

Independent repeat oracle, using keyboard-AAT contrast milliseconds: person P
has sessions with means 1 and 1; Q has one
session mean 3. Cohort mean is 2 with N=2, not 5/3 with N=3. Adding duplicate evidence
is refused; adding another eligible session at 1 for P leaves the equal-person
mean and N unchanged. For a matched intervention RT-difference oracle, P has session differences
1 and 3, Q has 6: equal-person mean is `(mean(1,3)+6)/2=4`, not 10/3. Do not construct
such a difference from unpaired sessions or treat IAT mapping A/B as intervention
conditions.

Initial cohort reporting can be descriptive. Optional inference must be a named,
explicit plan: one-sample comparisons to a stated value or genuine paired
study-condition differences, on linked person-level values, with assumptions,
support and the full declared multiplicity family. Use the existing tested
between-person t/CI and Holm machinery only after task measures and condition
bindings are registered. N=1 and zero/negligible between-person variance do not
produce a fabricated zero-width interval. No alpha/reliability from one person,
individual preference bands, emotion labels or sales prediction score.

## Small API handoff and end-to-end acceptance

Proposed original modules: `R/platform-task-import.R` and
`R/platform-task-cohort.R`, with separate mapping/report views. Domain helpers:

```text
brohn_validate_task_import_mapping(dataset, design=NULL)
brohn_validate_task_protocol_registry(registry, design, task_id)
brohn_import_task_trials(data, metadata, design, source, protocols)
  -> analysis(kind="implicit", task_scores, task_attempts, source_rows,
              trial_audit, quality, parameters, limitations)
brohn_score_run_tasks(input)
  -> same canonical task_attempts from frozen native journals
brohn_task_cohort(attempts, plan, identity_map)
  -> per_person, summaries, contrasts, quality, provenance
brohn_task_export_trials(attempts, path)
brohn_task_export_scores(attempts, path)
```

`source` carries dataset ID/revision/original SHA and immutable collection origin;
`protocols` is decoded from the verified registry object. The pure adapter owns
no file discovery, credentials or SQL. Root can dispatch the existing
`analyse_dataset` job for `modality="implicit"`, freezing the registry reference
with mapping/study/source revisions. A later queue wrapper
`brohn_queue_task_cohort(store, report_ids, plan, identity_map)` uses existing
fenced publication, with heavy validation/hash work outside the writer lock.
Do not combine this with acquisition lifecycle ownership.

Deliver one clear researcher journey: choose the saved task/source revision;
attach original CSV and registry; review automatically matched column names,
source timing definition, origins, identities and expected/observed support;
save mapping; run background analysis; open administration and cohort outcomes.
Show unsupported evidence with the exact missing field and a recovery action.
Retain pending/import-failed source bytes. Keep details collapsible; do not ask a
student to set hidden scoring thresholds that already belong to the frozen
profile.

Acceptance must cover:

1. The exact 180-row IAT fixture imports, runs through an actual fenced job,
   matches every pair/count/D, downloads and reopens unchanged. A native run's
   dedicated trial export and registry reimport match its stored result.
2. All five original arithmetic fixtures and boundary variants retain their own
   profile/scoring definitions. Unsupported SC-IAT/GNAT/priming/AMP remain outside
   these adapters; the [SC-IAT contract](SCIAT-IMPLEMENTATION-CONTRACT.md) is separate.
3. Impossible non-forced rows reject before scoring. A genuine 1-correct/39-timeout
   choice attempt reports known omissions while keeping unsupported RT metrics
   unavailable. Forced-correction incompletion never produces an ordinary D.
4. Unknown/duplicate trial, edited registry/material, changed task/study revision,
   wrong key, first/final inversion, unknown RT token, source-origin conflict and
   explicit subset selection retain source bytes and exact row reasons.
5. Repeats/cross-source identity and missing modalities do not alter another
   metric's N. Cohort retries use the frozen selected reports, not current latest.
6. Mixed questionnaire/task studies expose dedicated complete task downloads;
   full CSV/JSON and offline HTML retain scores, support, source hashes and
   exclusion details. Formula-safe display CSV must not be mistaken for the
   canonical machine roundtrip format; raw canonical text is separately retained.
7. Actual browser QA follows upload, mapping correction, job completion, study
   history, report inspection and export on narrow/keyboard-only layouts. Existing
   immutable sources and reports remain unchanged after errors/retry/clone.

## Audit source identity and remaining external work

| Inspected source | SHA-256 |
| --- | --- |
| `R/platform-methods.R` | `06f3af8a1157d39105712be768a44da5175f6b718dc50b7ce8de1f71460a476c` |
| `R/platform-task-delivery.R` | `de00579d46c7fe702c3d9ef633b9f9786c940efe57840d4b3c0f19b0b70d5636` |
| `www/participant/tasks.js` | `05b2f810b335f8d677a8884bc8ace5401989064bddddbdf8765e1d22c24e01de` |
| `R/platform-maxdiff-import.R` | `95e3f1acdd6911912df6fa2065e26ef09043f1c4d2581388ac6595f64da52d74` |
| `R/platform-maxdiff-platform.R` | `c923ae588061d6673e2431caa7dc655623ab101da4afa043fe24aac3e7bcaa55` |
| `R/platform-jobs.R` | `a3a3fe5118474b4fce0730fbdfc3ebd28a11d16119177205432c31bacbb4da7a` |

The existing prepared IAT package benchmark was read, not rerun or replaced.
This audit used original inputs for new arithmetic/boundary checks. External
work is specific: provider export semantics and source-output equivalence;
actual materials/population suitability; physical display/input timing;
independent BIAT author-data reproduction and keyboard-AAT applicability.
These do not block source-preserving software implementation, but they must not
be relabelled as completed qualification by a successful import or a matching D.
