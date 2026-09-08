# Object-case MaxDiff: design, evidence and first implementation

Brohn's `object-case-paired-maxdiff/1.0` is an explicit best-worst choice procedure. A researcher supplies named items and the exact sets in which they appear; a participant chooses two different items using the saved question and best/worst labels. It is not an implicit association, reaction-time score, conjoint attribute-level model, emotion measure or individual preference estimator.

This first pack implements frozen explicit designs, coverage review, complete-pair counts and an aggregate paired multinomial logit likelihood. Participant-aware uncertainty, hierarchical Bayes, individual utilities, optimal-design generation and market-share prediction remain outside this pack. Their absence must remain visible in reports; this pack does not complete every BWP14 acceptance criterion.

## Research and reference basis

The [support.BWS 0.4-6 manual](https://cran.r-project.org/web/packages/support.BWS/support.BWS.pdf) describes object-case best-worst designs, item/pair balance, normalized best-minus-worst counts, and distinct paired, marginal and sequential models. Brohn implements the paired model. [Sawtooth's analysis overview](https://sawtoothsoftware.com/help/lighthouse-studio/manual/analyzing-maxdiff.html) distinguishes counting, aggregate logit and individual/HB approaches. Its [design guidance](https://info.sawtoothsoftware.com/help/discover/survey-elements/maxdiff/design-settings) supports reviewing set burden, connectivity and repeated item exposure. These sources support method choices, not a claim that a particular Brohn study is qualified or optimally designed.

Reference verification is separate from runtime dependencies. The official CRAN archive `support.BWS_0.4-6.tar.gz` is retained outside the repository at `work/method-references/maxdiff/`, SHA-256 `041cf69fa7cc8a250d83b2de7ca9e5801d9d4359f0230e9fbbcbab4c29518750`. Its GPL >= 2 source and generated fruit example were inspected and executed from that reference directory; no reference package item text, dataset or source implementation is embedded in Brohn's runtime. Optional test comparison uses the prepared survival 3.8-6 library. These optional references are not installed by tests.

## Frozen contract

`brohn_maxdiff_new()` returns original synthetic example materials, clearly labelled for replacement. A design has:

```text
schema: brohn-maxdiff-design/1.0
id, title
profile: object-case-paired-maxdiff/1.0
origin: synthetic | researcher_supplied
materials_rights: nonempty provenance/permission statement
items: [{id, label}, ...]                 # 3..60 stable item identities
sets: [{id, item_ids: [id, ...]}, ...]     # 1..200 sets; 3..8 distinct items each
seed: positive whole integer
settings:
  prompt: nonempty research question/instructions
  best_label, worst_label: nonempty, distinct labels
  required: boolean
  set_order, item_order: fixed | seeded
  design_rationale: nonempty rationale
  analysis: {fit_aggregate: boolean}
```

The research framing is part of the design hash. “Most/least important” and “most/least preferred” are different questions. `required` governs completing a presented pair and never removes the participant's ability to withdraw. Unknown fields and invalid identities are rejected rather than silently discarded.

`brohn_maxdiff_design_review(design)` returns item frequencies, all pair co-occurrences, eight declared-position counts per item, connectivity and explicit warnings. Actual observed positions are separately counted in the result. Equal observed frequencies alone never confer an optimal/BIBD qualification. Fixed positions, unequal coverage, repeated combinations and large sets are disclosed.

`brohn_maxdiff_compile(design, allocation_index=1L)` requires every item to be offered and the design graph to be connected. It returns `brohn-maxdiff-protocol/1.0`, the complete frozen design/hash, allocation index and `trials`: `{id, set_id, position, item_order}`. Seeded allocation preserves the process's global RNG state. Every declared set appears once per allocation; there is no concealed subset selection or generated optimal design. Trial identity contains the full design hash and allocation index. Root integration places exercises in `design.maxdiff` and uses separate explicit-choice protocol steps.

## Response and missingness contract

The scorer accepts up to 20,000 exposure records. Every record explicitly supplies:

```text
id, participant_id, participant_linkage:boolean, session_id, exposure_id
design_hash, set_id, item_order:[item IDs in actual displayed order]
presented:boolean
status: answered | missing | not_presented
best_id: item ID | null
worst_id: item ID | null
missing_reason: text | null
```

Complete answers require two distinct typed item IDs from the offered set. Missing records retain an optional partial choice, with a required reason; they are excluded as complete choice outcomes. Unpresented records require no choices and a reason. Duplicate record identities or participant-code/session/exposure tuples are rejected. A receiver must compare actual order and trial identity with the frozen protocol; imported ledgers preserve their declared actual order and must identify their source.

`participant_linkage` declares whether the source participant code links a person. Anonymous run IDs use `false`. `quality.participant_count` is null unless every nonempty input record declares linkage; `quality.session_count` still counts source participant-code/session tuples. Mixed declarations never produce a unique-person claim. Repeated sets and sessions remain evidence, not new independent people.

For each item the saved score is `(best_count - worst_count) / answered_exposures_containing_item`. Presented, answered and missing exposures are separate fields. Zero eligible exposures yields null, not zero preference. Partial answers contribute neither a best nor a worst count. This complete-pair denominator is an explicit missing-data policy; it does not assume missingness is random.

## Exact aggregate model

For an offered set S, the probability of the ordered best/worst pair (b,w) is:

```text
P(b,w | S,u) = exp(u[b] - u[w]) /
              sum(exp(u[i] - u[j]) for i,j in S where i != j)
```

The objective is the sum of negative log probabilities of the actual complete pairs. Each complete pair has weight one. A person contributing more complete choices contributes more to this aggregate choice-weighted fit. Best and worst are not independent responses; no marginal/sequential replacement or synthetic pair expansion changes their likelihood.

Implementation uses log-sum-exp, analytic gradient and information, and base R BFGS. The last item is the internal reference, and output utilities are centered to sum zero. Parameters record optimizer/tolerances, constraints, weighting, iterations and information diagnostics. No ridge, prior or invented outcome rescues a failed fit.

Brohn checks connectedness of the answered item design and finite-MLE existence before fitting. The latter is an original diagnostic for this paired likelihood: each chosen best item must be at least as high as all offered items, and each chosen worst at most as high, along a possible separating direction. Edges `best -> offered` and `offered -> worst` express those inequalities. Strong connectivity forces every such direction to be constant. Otherwise a nonconstant recession direction prevents a finite unpenalised MLE. These edges are only a diagnostic; they are never added as pseudo-responses to the objective.

No answers, disconnected answered designs, complete/quasi-separation, nonconvergence and poor numerical information each produce an explicit unavailable reason and an empty utility list. Available fits retain NLL, null NLL, mean gradient, convergence code, information eigenvalue/condition and offered-set pair probabilities. Utilities are relative logit units, not percentages. Standard errors and population intervals are null: repeated choices are not independent participants, and a separate participant-aware uncertainty method is required.

## Source and integration APIs

`brohn_maxdiff_analysis(design, responses, source=NULL)` returns `brohn-maxdiff-result/1.0`: complete frozen design, design hash, response hash, original exposure ledger, review, item counts, model, quality and limitations. An optional source supplies exact `hash`, `origin` and optional `id`/`revision`. Synthetic materials cannot be upgraded to a live/pilot/imported source through this adapter. Reports must retain source origin and these hashes unchanged.

Core APIs are `brohn_maxdiff_validate`, `brohn_maxdiff_design_review`, `brohn_maxdiff_compile`, `brohn_maxdiff_validate_responses`, `brohn_maxdiff_likelihood`, `brohn_maxdiff_fit` and `brohn_maxdiff_analysis`. Source this module after platform core. The UI hooks in `R/platform-maxdiff-views.R` are `brohn_maxdiff_summary_ui(design)`, `brohn_install_maxdiff_ui(input,output,session,current,state,attempt,capture,update_study)` and `brohn_maxdiff_result_ui(result)`. Source views after the shell and data-table helpers. Install after `capture` exists. The updater accepts only `update_study(design)`.

The Tasks-stage editor reads/writes only `design.maxdiff`. `maxdiff_add` and `maxdiff_edit` open a dedicated draft. `maxdiff_save`, `maxdiff_cancel`, `maxdiff_delete` and `maxdiff_review` receive `{token}` commands. Structural commands also carry the exact draft version, action and item/set IDs. Both the hidden study/Tasks form identity and editor identity must match; Save first flushes pending underlying study edits and rejects a changed revision/hash. Cancel invalidates the draft, and an old Cancel cannot close a newer editor.

Item labels retain stable IDs. Membership selects append new choices, and explicit keyboard Move buttons control item/set order. Structure is rerendered only after an acknowledged structural action, preserving other pending label/membership values; input identities include the draft version so stale fields cannot overwrite the new controls. “Check design coverage” reflects its explicitly captured form, and Save validates again. A structurally valid disconnected draft can be saved for further work but cannot be compiled for collection. Adding a set uses the first three existing items as a visible draft starting point; it makes no balance/optimality claim.

`brohn_maxdiff_result_ui` consumes saved result values without refitting. It checks retained design/response hashes, displays actual complete/missing/unpresented denominators and linked-person versus session evidence, and shows aggregate utilities only when the saved fit is estimated. Saved failure reasons, source hashes, likelihood diagnostics and design coverage remain inspectable. Full immutable ledger/result exports are integration hooks owned by the common report layer.

## Verification and boundaries

`tests/platform-maxdiff.R` passes 47 checks in the prepared environment. Independent original examples verify a 37-choice paired likelihood and recovered utilities `(log(2),0,-log(2))`, gradient arithmetic, stable extreme logits, reference-item invariance, unequal exposures, missing/partial answers, separation, connectivity, order and RNG preservation, source hashes, typed identities and anonymous/mixed linkage. The upstream 100-person, 700-choice generated fruit reference agrees on all seven centered utilities, the exact paired likelihood and normalized counts. A support.BWS one-question data-construction defect is explicitly recorded; the independent one-set oracle uses an independently assembled survival likelihood instead of fabricating extra questions.

These are calculation and contract checks. Actual researcher authoring, participant collection, durable transport, immutable exports and broad consumer-study fitness require their own integrated tests after the hooks are connected. No physical-device qualification is relevant to this explicit-choice pack.

`tests/platform-maxdiff-views.R` passes 32 additional scoped checks using Shiny's real server harness: framing and typed settings, preserved label/item/set identities and movement, blocked referenced-item removal, stale structure events, review, Save/Cancel/late Save, old Cancel, concurrent revision changes, navigation/archive rejection, explicit removal, and escaped source-bound results with unavailable scores. These checks do not claim a completed browser/receiver journey; that remains required after integration.

## Participant component contract

Load `www/participant/maxdiff.css` after the frozen participant stylesheet and `maxdiff.js` before use. No researcher stylesheet is required. `window.BrohnMaxDiff.create({container, choice, draft, onDraft, onSubmit, onError})` returns `{dispose}`. The exact `choice` fields are:

```text
exercise_id, design_hash, set_id, trial_id, position
item_order: [stable item IDs in actual frozen order]
items: [{id,label}, ...] in exactly that same order
prompt, best_label, worst_label, required:boolean
```

The component validates this contract before mounting. A restored `draft` is null/absent or exactly `{best_id: item ID|null, worst_id: item ID|null}`; partial valid drafts are supported. Foreign IDs, numeric coercion, duplicate best/worst or a mismatch between item order and labels fail explicitly before mounting. The caller retains the full source/protocol linkage and is responsible for choosing the matching per-trial draft.

Two native radio groups expose the saved best/worst labels, exact item order and keyboard navigation. An item selected on one side is unavailable on the other. Clear explicitly resets both choices. A complete pair submits only through Continue. Optional blank sets use Skip; an optional partial set offers the explicit “Clear choices and skip this set” action, which clears the draft before submitting null. Required does not suppress the enclosing runner's withdrawal action.

`onDraft({best_id,worst_id})` may be asynchronous. Calls are serialized in selection order. Submission waits for its own latest complete/blank draft write before calling `onSubmit(pair|null)`. While that Promise is pending, every component control is frozen. Success remains locked until the caller replaces/disposes the screen; failure retains the explicit choices, displays a safe text error, calls `onError(Error)` and allows retry. A later retry can recover a failed draft write. `dispose()` removes only the component's own DOM/listeners and prevents late submit callbacks from changing the departed screen.

There are no network requests, camera permissions, clock reads or event writes inside this module. The enclosing runner must own the untimed step's onset, response event, frozen protocol comparison, journal, receipt and study completion. Component success alone does not establish a durable receipt unless the caller's Promise has that meaning.

`tests/participant-maxdiff.mjs` passes 28 actual Chrome component checks and three clear axe scans, including native keyboard arrows, exact IDs/order, literal markup-like item text, restored choices, pending/failing/retried callbacks, ordered asynchronous draft writes, optional missing behavior, malformed source rejection, disposal and an actual 390px eight-item screen with long text and 48px targets. Evidence is retained outside the repository under `work/test-runs/brohn-maxdiff-component-evidence`. This is an original synthetic component fixture with caller hooks; it does not claim real receiver authorization, portable design integration or an end-to-end research run.

## Actual participant delivery evidence

`tests/participant-maxdiff-delivery.mjs` and its original R fixture pass **42 checks and two clear accessibility scans** against the actual `scripts/run-participant.R` launcher, isolated SQLite workspace and native x64 R interpreter. The owned service uses a local fixture stop-file watcher to call `httpuv::interrupt()`, then exits through the actual launcher cleanup with code zero. No main service is stopped and no scientific worker runs.

The real released sample study contains two required sets, a separate optional exercise and a final numeric liking question. Browser clicks retain all exact item orders and source exercise hashes. Reload during a partial choice restores the selected best without inferring a worst; two page onsets remain, uninterrupted response time is null, and the saved active-segment time agrees with the real clock difference. A real receiver commit followed by one deliberately lost HTTP acknowledgement is retried once with the identical operation, events, IDs, sequences, clocks and payload. Optional clear-and-skip retains an explicit null. Closure retains a contiguous ledger and a single queued analysis job; replaying the final receipt does not enqueue another. Anonymous enrollment remains unlinked and sample origin is preserved.

A real IndexedDB readwrite transaction is deliberately aborted after the response put is issued. The saved choice/cursor/next sequence remain unchanged, both selected items remain on the same screen, and retry produces exactly one eventual response/completion with none of the aborted event identities. This specifically verifies the shared runner's copy-on-write `persist`: it restores the previous record before awaiting storage and publishes the candidate record only after transaction success. Updating the button state alone would not protect the in-memory sequence/cursor or prevent asynchronous delivery of uncommitted events.

Withdrawal while a partial pair is selected creates no response/completion for that pair. Withdrawal with a prior answer's delivery pending retains that first answer once, leaves the later selected pair unsubmitted and ends withdrawn with no analysis job. Direct negative HTTP fixtures reject same-item pairs, foreign/numeric item IDs, required nulls, invented uninterrupted times, unrecorded recovery, foreign page clocks, completion without an answer and a second acknowledged answer. Their deliberately declared synthetic clocks are separate from the real browser timing checks.

Latest evidence is `work/test-runs/brohn-maxdiff-delivery-0X75E9/results.json`, with read-only `inspection.json`, actual desktop/narrow screenshots and graceful `server.log`. Earlier delivery-only evidence at `brohn-maxdiff-delivery-H0VHdx` passed 36 checks before adding the storage failure, source exercise hash and repeated receipt checks. This qualifies the tested delivery/rollback contracts; it does not claim a completed scientific job, participant-aware uncertainty or field research validation.

The shared storage change also passes the existing typed-questionnaire journey (13 checks, including two expected queued-job assertions) and camera permission-race/decline journey (17 checks and a clear 390px accessibility scan). `tests/participant-persist-regressions.mjs` reuses those harnesses with explicit test-only isolated service/workspace settings and records the exact runner SHA-256. No recording is started, no scientific worker runs, and all completed-run jobs remain queued. Full source/mode evidence is under `work/test-runs/brohn-maxdiff-delivery-regressions-ibnxTj`; the [researcher QA ledger](../qa/RESEARCHER-QA.md) distinguishes these regression checks from analysis qualification.

## Mapped CSV/TSV import

`R/platform-maxdiff-import.R` adds a dedicated `maxdiff` dataset modality. Its public APIs are `brohn_validate_maxdiff_mapping(dataset, design=NULL)` and `brohn_import_maxdiff_analysis(data, metadata, design, source)`. Source after platform core and the MaxDiff core. The validator requires CSV/TSV, an explicit linked `study_id` and positive `study_revision`, and the following exact mapping fields:

| Mapping | Meaning |
| --- | --- |
| `exercise_id` | Stable chosen `design.maxdiff` exercise identity |
| `origin_statement` | Required description of the original collection source |
| `participant_column`, `participant_linkage_column` | Source participant code and explicit linkage declaration |
| `session_column`, `exposure_column` | Separate session and occurrence identities |
| `design_hash_column`, `set_column` | Exact exercise hash and named offered set |
| `item_order_column` | JSON array of exact offered string IDs in their recorded order |
| `presented_column`, `status_column` | Explicit presentation boolean and answered/missing/not_presented status |
| `best_column`, `worst_column`, `missing_reason_column` | Explicit choices or empty cells, and the applicable missing reason |
| `exercise_column` (optional) | Filter a multi-exercise source by the exact selected exercise ID |
| `origin_column` (optional) | Verify selected row origins against the immutable source origin |

Mapped semantic fields use distinct columns. A full design supplied to validation must match the linked study and contain the selected exercise; it also permits the known synthetic-material origin check before dispatch. A metadata-only validation is not a substitute for that design-aware preflight. The worker always receives the full frozen study and validates its selected exercise again.

Read source data with the existing `brohn_read_table`, preserving all columns as character and setting `na.strings=character()`. An already inferred numeric/factor column or R `NA` is rejected rather than reverse-engineered. The boolean fields accept exactly `true`, `false`, `TRUE`, `FALSE`, `1`, `0`; yes/no, whitespace-padded tokens and missing-code words do not silently become linkage/presentation states. Only exactly empty best/worst/missing-reason cells become null. The string `NA` remains text: it can be an item ID only when that exact ID was actually declared and offered.

Embedded JSON arrays must use normal quoted CSV/TSV fields with doubled embedded quotation marks. For an R TSV writer use `write.table(..., sep="\t", quote=TRUE, qmethod="double")`; a writer's different escape convention must be explicitly converted before import, not guessed by the analysis. The actual offered order is preserved, never sorted or reconstructed from a set summary. Full canonical response validation rejects foreign IDs/hashes, same-item pairs, unsupported missing states and duplicate participant-code/session/exposure tuples before any score is returned.

The total source limit is 20,000 rows, including excluded other-exercise rows. If an exercise selector is mapped, only exact matches enter scoring; zero matches is an error. Every source row retains its original one-based data-row index, canonical decoded-cell-object hash, selected/excluded reason and declared exercise/origin. Selected rows additionally retain all mapped cell text. Excluded rows are not parsed as choices from the selected exercise, and their complete original bytes remain in the pinned source. Without an exercise selector, every row must match the selected exercise hash. No hidden truncation or row-order participant/position inference is performed.

The coordinator supplies the immutable `{hash, origin, id, revision}` source after verifying the actual input object. Selected mapped row origins must match it exactly. Original synthetic exercise materials allow only sample/preview origin; importing a file cannot upgrade them to imported, pilot or live evidence. With no origin column, the result explicitly records that verification rests on the immutable source declaration alone. A quoted spreadsheet-safety prefix stays literal text; the adapter never guesses that a leading apostrophe should be removed.

The outer analysis has `kind="explicit_choice"`, a title, `choice_tasks=list(result)`, complete selected canonical `observations`, all `source_rows` and their hash, source/selected/excluded counts, complete/missing/unpresented coverage, linkage/session evidence, frozen mapping parameters and limitations. The nested `brohn-maxdiff-result/1.0` keeps its original schema and full exposure ledger unchanged. It scores only complete pairs. Missing-only input remains a retained unusable analysis with null scores. Imported row text never establishes browser onset, uninterrupted RT or encoded camera timing.

`tests/platform-maxdiff-import.R` passes **47 checks**. These include actual Brohn CSV export/read/import, an actual correctly quoted TSV, six equiprobable ordered choices giving utilities zero and exact NLL `6*log(6)`, alternating actual item order, stable source-row identities, missing/unpresented/partial pairs, multi-exercise exclusions, exact source hashes/origins, anonymous/mixed linkage, typed boolean/JSON failures, literal `NA` identity, duplicate exposures, the full row bound and preserved base result fields. These are pure adapter/reference checks, distinct from the saved-platform evidence below.

### Saved import and mapping evidence

`tests/platform-maxdiff-import-platform.R` passes **40 checks** using the production `brohn_server` handler, an owned temporary SQLite/object workspace, the actual supervised R worker and immutable report publication. The original fixture is a Brohn-generated multi-exercise CSV containing six balanced complete pairs, a partial response, an unpresented set and a different exercise. It is synthetic sample material throughout.

The saved analysis reproduces zero aggregate utilities and NLL `6*log(6)`. Its denominator remains six complete pairs; the partial, unpresented and excluded rows remain separately visible. Seven presented occurrences of the same set produce six repeat exposures, while the unpresented row adds no presentation. One explicitly linked person/session remains one, and imported rows acquire no response times or implicit scores. Exact item order, selected raw cell evidence and every source-row hash survive the worker boundary.

The test changes both the current study wording and dataset mapping after queueing. The completed report retains the original queued study revision/hash, exercise framing, dataset revision/hash and CSV bytes. A forced reanalysis creates another report while the first report retains its single unchanged revision. Actual rejected jobs cover a later exercise design that does not match the source row hashes, a conflicting selected-row origin and a tampered frozen request. A separate wrong-byte input path is rejected without modifying registered source objects. No rejected attempt publishes a scientific result.

Downloads cover the complete original CSV including the excluded exercise, generic observations CSV, dedicated best-worst choices CSV, full report JSON and standalone HTML. Use the dedicated best-worst CSV for a self-contained reimport with `exercise_id` and `origin` columns; generic observations preserve canonical selected responses but do not add these optional export context columns. Reimporting the dedicated CSV reproduces the independent likelihood. Immutable file hashes and exact identity/observation/source-row hashes are checked. Catalog-versus-retained-envelope and full JSON download checks now require exact canonical hashes and numeric equality with zero tolerance. The initial integration exposed differing catalog/report numeric serialization settings; the shared storage correction preserves binary64 precision without changing historical stored bytes. Only arithmetic against independently computed fitting references uses numeric tolerances. A fresh database connection reopens the unchanged report and full result object.

The **16 mapping-only checks** also run independently with `--mapping-only` and launch no scientific workers. They execute the unchanged production server function body with only its workspace argument bound for Shiny's test session. They reject an unmatched study identity, an external change while "current" remains selected, old dataset controls after navigation and a replayed stale accepted form. Confirmed selections pin the actual saved revision before the one-step mapping-and-analysis command queues its job. Old physiology controls cannot leak into MaxDiff metadata; a foreign exercise, missing revision or synthetic-origin upgrade is rejected before a mapping write. Test-created queued jobs are cancelled before leaving this mode.

This is saved-backend and Shiny reactive-handler evidence. It does not replace actual browser navigation/accessibility evidence or establish field validity of a researcher's custom choice design. The test removes only its verified owned temporary workspace after process cleanup.
