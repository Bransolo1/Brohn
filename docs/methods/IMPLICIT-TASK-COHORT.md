# Explicit implicit-task cohort summaries

`R/platform-task-cohort.R` is a pure domain package. Its tests exercise canonical
administrations produced by the actual CSV/protocol-registry importer and
independent arithmetic. New storage and view adapters are implemented separately
in `platform-task-cohort-storage.R` and `platform-task-cohort-views.R`. Shared
loaders, worker dispatch and app registration are connected. Actual isolated
worker publication is checked below; integrated browser qualification remains
separate.

## Public contract

Source after `platform-core.R` and `platform-methods.R`. No SQL, file discovery,
device, Python package or network operation occurs in this package.

```r
brohn_task_cohort_identity_rows(attempts)
# Unapplied person/session crosswalk rows: every destination initially NULL.

brohn_task_cohort(attempts, plan, identity_map)
# schema="brohn-task-cohort/1.0", kind="implicit_cohort"
# membership, attempt_metrics, per_session, per_person, summaries,
# contrasts=list(), quality, provenance, limitations
```

`attempts` is an unnamed list of 1 to 5,000 canonical
`brohn-task-attempt/1.0` records. The package checks source keys, administration
hash identity, score/task/person/session/origin references, supported score
versions, registered metric names, units, finite values and completion gates.
It consumes frozen score evidence; it does not recompute scores or establish
that external clocks, materials or source software were scientifically qualified.

The explicit plan has exactly these fields:

```r
list(
  schema="brohn-task-cohort-plan/1.0",
  description="Researcher's named selection and repeat policy",
  membership=list(list(attempt_id="task-attempt-...", attempt_hash="<SHA-256>")),
  homogeneous=list(
    task_id="<exact task ID>", task_definition_hash="<SHA-256>",
    profile="rt-deary-liewald-choice/1.0",
    collection_origin="pilot", material_origin="researcher_supplied",
    score_schema="brohn-task-score/1.1",
    scoring_recipe="brohn-rt-metric-support/1.0",
    evidence_level="declared_trial_summary"
  ),
  repeat_policy="equal_attempts_within_session_then_equal_sessions_within_person"
)
```

Origins above illustrate separate declarations; copy actual immutable values,
never change an existing administration to fit the cohort. For existing
`brohn-task-score/1.0`, `scoring_recipe` is explicitly NULL. Current registered
IAT, BIAT and keyboard AAT scores use that older schema. A homogeneous cohort may
also describe old RT 1.0 scores under their original aggregate eligibility gate;
it cannot mix them with RT 1.1 or manufacture the newer support semantics.

Every selected record must be supplied, and its full canonical hash must match.
Input list order is normalized to the frozen membership order. A missing selected
record rejects; the storage wrapper must retain/report that integrity failure
instead of replacing it with the latest result. A supplied unavailable or
incomplete administration stays selected with its reasons and unavailable metric
rows. There is no best-retake or favorable-outcome selection.

## Explicit person and session identities

The crosswalk has exactly these fields and row shapes:

```r
list(
  schema="brohn-task-cohort-identities/1.0",
  linkage_statement="Researcher's explicit basis for this identity linkage",
  participants=list(list(source_collection_id="collection-A",
    participant_id="001", person_id="person-P")),
  sessions=list(list(source_collection_id="collection-A",
    participant_id="001", source_session_id="visit-source-1",
    session_id="visit-P-1", equivalence_statement=NULL))
)
```

All identity fields are exact text. `"001"`, `"1"`, `"0"` and `"false"` remain
distinct. Tuple hashes avoid delimiter collisions. The same source participant
code in two collections has two crosswalk rows; neither labels nor file order
create cross-source identity. A researcher may explicitly link a source with an
original false linkage flag; the output retains that false flag and the new
researcher assertion separately. This does not claim independent verification.
The review dialog discloses the number of originally unlinked administrations
and requires identity evidence notes before its source-code or edited-code modes
can link them. A display code alone is not evidence that two runs concern one
person. Leaving those administrations unlinked remains an explicit option.

Person/session destinations may be explicit NULL; missing rows also mean unlinked.
All selected administrations must have both mappings before any person-level or
cohort mean/SD is emitted. If even one is unlinked, administration metric outcomes
remain available but all person counts and person/session summaries are withheld.
To analyse a linked subset, the researcher must freeze a new explicit membership.

Crosswalk source tuples must be unique and belong to the selected administrations.
One source session cannot split into two destination sessions. Multiple source
sessions cannot silently collapse into one person/session; all collapsing rows
must carry the same nonempty `equivalence_statement`. A destination session code
is scoped to its destination person, so two people may both have `visit-1`.

## Repeat arithmetic and metric support

Two named repeat policies are implemented:

- `one_selected_attempt_per_person`: membership must contain at most one selected
  administration for each mapped person, before checking any metric eligibility.
  An unavailable second administration is still a second selected administration.
- `equal_attempts_within_session_then_equal_sessions_within_person`: for each
  metric separately, average eligible attempt values inside a declared session,
  average contributing sessions inside a person, then give each contributing
  person equal cohort weight. Selected unsupported attempts and sessions remain
  in audit rows with counts/reasons; no missing value is imputed as zero.

If P has two sessions with means 1 and 1, and Q has one session with mean 3,
the cohort mean is `(mean(1,1)+3)/2 = 2`, with two people. The administration mean
`(1+1+3)/3 = 5/3` is not this estimand. A separate nested fixture has P's first
session attempts 0 and 2, P's second session 3, and Q's session 6. The result is
`(mean(mean(0,2),3)+6)/2 = 4`; P has three attempts, two sessions and one person.

RT 1.1 uses each metric's frozen `eligible`, `reason` and `support`, rather than
the task's aggregate flag. One correct 500 ms response plus 39 no-response
timeouts contributes mean/median 500, error proportion 0/1 and omission proportion
39/40. Its within-attempt sample SD has no supported value. Fully omitted tests
contribute omission proportion 1, with error rate unavailable rather than zero.
Original numerator/denominator and RT-window evidence remain in `attempt_metrics`.

Means of rates are equal-weight means under the repeat policy, not pooled
trial ratios. A mean of participant median-RT outcomes is not a pooled-response
median. The within-attempt RT SD is an outcome distinct from the between-person
sample SD calculated across that outcome's person means.

Each summary includes selected/eligible administration counts, selected and
contributing person counts, contributing session counts, mean, between-person SD,
status, reasons and an estimand label. Between-person SD needs at least two
contributing people. Two identical person values correctly yield zero SD; one
person yields NULL SD. No confidence interval or test is produced in either case.

## Duplicate and source integrity policy

The package rejects duplicate selected administration IDs, logical administration
keys and overlapping original byte/row evidence. The logical key binds collection,
source participant, session, source attempt and exact task-definition hash. Thus
a reformatted/reimported export with a different file hash but truthful retained
source identities is a duplicate. Re-labelling the namespace does not permit the
same original bytes and rows to count twice.

Equal score values alone are not evidence of duplication. Changed file bytes
combined with falsely changed collection/attempt declarations cannot reliably be
detected by this package. The wrapper must preserve source provenance and ask the
researcher to resolve duplicate evidence rather than silently deduplicate based
on equal values or nearest timestamps.

## Storage and UI integration boundaries

The parent integration must scope exact report IDs to the project/study before
reading, resolve immutable report bodies and object hashes, freeze all canonical
administration hashes plus plan and crosswalk, and retain the selected source
references in the queued request. Keep unavailable selected attempts. Never swap
a missing frozen object for the newest report. A native adapter must produce the
same canonical identity and source-bound score fields, with its own exact evidence
level; declared CSV summaries and native replay evidence remain separate groups.

Render `membership` and `attempt_metrics` even when person summaries are withheld.
Display per-metric N beside each mean. Show the two repeat policies with ordinary
language and require an explicit selection. Prepopulate only source identity rows;
destination identity suggestions require review and must not be applied on save
merely because labels match. Export full plan/crosswalk and source hashes alongside
all support rows. No group t-test, CI, clinical interpretation, causal statement,
generic implicit composite, or emotion score is part of this recipe.

Independent domain evidence lives in `tests/platform-task-cohort.R`. It includes
all five original profile oracles, repeat and nested-repeat arithmetic, partial
RT support, all omissions, N=1/zero variance, exact identity strings/namespaces,
unlinked withholding, unavailable membership, session equivalence, source copies,
hash rejection, mixed profiles/recipes/origins and typed numerical failures.

## Implemented storage and view adapter handoff

`brohn_task_cohort_report_catalog(store, study_id, project_id=NULL, limit=40,
offset=0)` returns metadata-only pages with exact totals, filtering project and
study before the limit. Empty task-score arrays from ordinary questionnaire
reports are excluded. Native summary reports remain discoverable with an explicit
unsupported-source reason; no native attempt or replay claim is manufactured.

`brohn_task_cohort_catalog(store, study_id, report_ids, task_id=NULL)` checks 1 to
100 exact reports. It verifies project ownership before decoding a report, its
frozen study provenance, full result object hash/size, equality of catalog versus
retained result analysis/provenance, canonical imported attempts, and retained
original/registry object bytes. It returns source references, complete attempts,
source-report bindings, homogeneous groups, unapplied identities and a selection
hash. Valid canonical administrations remain available to selection even when
their report's aggregate scientific-support flag is false.

`brohn_prepare_task_cohort` and `brohn_queue_task_cohort` take `store`, `study_id`,
`report_ids`, `attempt_ids`, `identity_map`, `repeat_policy`, `description`,
`expected_selection_hash`, and optional `task_id` and `report_title`. The reviewed selection hash
must still match. Every selected report must contribute an explicitly chosen
administration; unsupported or unused sources must be removed deliberately. The
request schema is `brohn-task-cohort-request/1.0`, recipe
`brohn-task-cohort-descriptive/1.0`, capped at 4 MiB. The queue operation is
`analyse_task_cohort`, with idempotency based on the complete frozen request hash.
Separate `plan_hash` and `identity_map_hash` bind the reviewed repeat/membership
policy and identity crosswalk; both the store input adapter and scientific child
check them. These are integrity checks, not authentication against a caller who
can replace an entire request and all its hashes.

`report_title` is an optional short, explicitly reviewed display name, capped at
240 UTF-8 bytes without C0/C1 control characters. Preparation, stored input and
the isolated analysis adapter each validate it. NULL is omitted from the request
entirely, preserving legacy request hashes and the old study-derived title.
The full plan description retains its original 5,000-byte contract independently;
it is never truncated or reinterpreted as a title. The existing UI name field
supplies the short report name and its existing plan description with no extra
step. New named reports use that exact text; saved reports are never renamed.

`brohn_task_cohort_input(store, request)` reads exact pinned report revisions,
rechecks all source objects and administration bindings, and returns a bounded
12 MiB `brohn-task-cohort-input/1.0` containing request plus selected attempts.
Later report heads, draft edits or study archival cannot replace this input.
`brohn_analyse_task_cohort(input)` returns the ordinary report envelope shape:
title, study ID, NULL dataset ID, origin, full source provenance and cohort
analysis. When no person mean is supported, the report is `needs_review` while
retaining administration evidence. The existing staged, fenced generic report
publisher can publish this result without a new bulk-write transaction path.

Shared job hooks register `analyse_task_cohort` in input, analysis and retry
dispatch, and include both domain/storage modules in scientific child source hashes.
The app installer is `brohn_install_task_cohort_ui(input, output, session, store,
state, current, attempt, message, refresh)`. Its `task_cohort_open` command carries
the current study ID from Results or History, with the existing study form identity.
It uses fresh per-dialog tokens, stable input nodes, explicit Cancel invalidation,
and context checks before every action. Larger memberships/crosswalks offer full
JSON templates instead of silently truncated editors. Source-code linking needs
explicit confirmation and keeps source collections separate.

Report integration calls `brohn_task_cohort_report_ui(report$analysis)`.
`brohn_export_task_cohort_csv(report, path, level)` exports `summaries` by default,
or `per_person`, `per_session`, `attempt_metrics`, `membership`, using the existing
precise and spreadsheet-safe report CSV encoder. Table previews state their total
row counts and the availability of the complete JSON evidence.

Scoped results: 68 pure domain checks, 45 saved-object/source-adapter
checks, and 33 actual Shiny-handler/typed-input checks. Storage fixtures directly
publish original test objects; they are not supervised scientific worker claims.
All jobs created by these adapter tests were cancelled at attempt zero. The view
checks include the four dedicated evidence downloads, exact report-schema and
current-page guards, the original-linkage disclosure/notes requirement, and new
report-name bounds. Storage coverage includes legacy NULL omission, independent
long plan notes and short name, exact 240-byte Unicode acceptance, and invalid
name rejection in all three domain entry points.

`tests/platform-task-cohort-worker.R` then passed 29 checks on 2026-09-08. It
published two original synthetic choice-RT imports and three cohort reports
through actual isolated supervised children and the sealed, fenced Windows
publisher. The primary fixture gives P two sessions at 1 ms and Q one at 3 ms:
the cohort mean is 2, not 5/3. Its error-proportion mean of 1/6 remains exactly
equal as binary64 in the catalog, retained report JSON and dedicated CSV. A
second selection combines Q with an original one-correct/39-timeout attempt:
RT mean has two contributing people while within-attempt RT SD has one. The
unlinked report keeps all selected evidence and withholds person summaries.

The same run checked pinned report versions after later head/draft changes and
archival, full JSON/CSV/HTML export, reopen, source object hashes, and scientific
code identity. Three separately mutated frozen requests (crosswalk, plan and
source report hash) reached terminal failure without publishing reports. All
eight supervised attempts settled. Evidence is retained at
`work/test-runs/brohn-task-cohort-worker-20260908-181819-5f6847e8/evidence.json`
under the outer workspace, not the repository. An earlier incomplete test run
stopped after three valid publications because it called the generic CSV helper
instead of the app's cohort-specific dispatch; only that test expectation was
corrected before the full fresh run.

`tests/researcher-task-cohort.mjs` subsequently passed 19 actual browser checks and
five automated accessibility scans with Chrome. The two original source imports
and two browser-queued cohort reports reside in the isolated workspace
`work/test-runs/brohn-researcher-task-cohort-RBbweF`. Final evidence is
`evidence-resume-1788863456221/results.json`; earlier folders retain the original
publications and failures. The continuation reused completed source/report
objects; it did not alter or replace them to obtain a pass.

The original CSV records deliberately declare false participant linkage. The
browser checked the disclosure, downloaded a complete unapplied identity map,
rejected missing confirmation/identity notes and inconsistent one-administration
selection, then explicitly linked against a named original synthetic register.
It queued the equal-person and partial-support cohorts, downloaded all five CSV
tables plus exact full JSON and HTML, cancelled from History without creating
work, and reloaded/reopened unchanged reports. Expanded report downloads and
membership review passed at 1440 px and 390 px; the standalone HTML passed at
390 px. All scans had zero automated violations and no page overflow. This is not
a substitute for human assistive-technology evaluation.

The browser found one product defect: the expanded evidence-download toolbar in
the page heading overflowed the desktop viewport. The controls were moved into
their own report-body card, preserving IDs and file contents. The failed
`evidence-resume-1788863157546/failure.png` remains alongside the passing expanded
desktop/mobile screenshots. Other initial stops were harness corrections: focus
the search by clicking before typing during modal initialization, check the
offline accessible region rather than expecting its label as visible text, and
wait for the report h1 rather than matching same-titled cards during navigation.

These browser checks preceded the optional short-title addition. The original
browser reports retain their exact study-derived titles. Its separate
`tests/platform-task-cohort-title-worker.R` passed seven checks with one actual
isolated scientific publication, recorded at
`work/test-runs/brohn-task-cohort-title-20260908-183638-76f4d435/evidence.json`.
That setup uses original directly saved source-report fixtures, rather than
claiming additional source-import workers. The named report retained its exact
reviewed title in catalog, complete object, HTML, study report lookup and reopen;
long plan notes, mean 2 and original source reports remained unchanged. No pending
jobs or owned processes remained.

These checks do not establish native journal replay, physical timing accuracy,
population inference or hosted delivery.
