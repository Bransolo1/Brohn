# Brohn complete-answer explorer acceptance

Resumed 20 September 2026 from the unregistered 8 September draft. The explorer
is a read-only derived view of a pinned questionnaire report. It does not
reanalyse outcomes, edit observations or join visits into inferred people.

## Delivered boundary

The researcher opens **Explore all answers** from a saved questionnaire report.
A supervised preparation job builds one immutable, source-bound SQLite index.
Questions and Answers have independent literal, case-sensitive filters and
25/50/100-row pages. Detail exposes native types, unabridged UTF-8 chunks,
canonical source records, acknowledged changes and dependent-answer clearing.
Questions retain saved whole-report summaries when answer filters change.

The index retains report/project/revision/body identity, original result-object
support, source/artifact/design hashes and implementation identity. Native
Windows guards hold original source files and staged output through publication.
Query actions recheck the opened record, handle, project and immutable revision.
Existing full downloads remain available during failure, cancellation and retry.

## Executed evidence

| Scope | Evidence |
|---|---|
| Pure source/index/query | `tests/platform-questionnaire-index.R`: 77 checks. Native false/zero/text/null, full Unicode reconstruction, record/cursor/source binding, typed revision links, limits and integrity rejection. |
| Store/publication | `tests/platform-questionnaire-explorer-storage.R`: 59 checks, including two actual native publications, SQL rollback, cancellation/stale attempts, authority revocation, corruption and reopening. |
| Researcher components | `tests/platform-questionnaire-explorer-views.R`: 40 Shiny component checks, including exact queries, typed/chunked detail, stale-action rejection and stable forms. |
| Supervised workers | `tests/fixtures/researcher-questionnaire-explorer.R worker`: 13 checks, two successful publications and one deliberately failed deadline attempt; no partial index published. |
| Existing job regressions | `tests/platform-jobs.R`: 30 actual R subprocess/publication checks. |
| Existing complete-source regressions | `tests/platform-questionnaire-artifact-storage.R`: 24 storage/export/synthesis checks. |
| Researcher browser journey | `tests/researcher-questionnaire-explorer.mjs`: 14 checks, including actual cancellation/retry, complete pagination, typed values, exact Unicode reconstruction, downloads and retained history. Five desktop/390-pixel automated accessibility scans have zero violations, overflow or targets below 44 pixels. |

The fresh fixture has 720 typed answer records, 12 saved question summaries,
a 60-entry distribution and a long Unicode value (80,031 Unicode characters,
200,031 UTF-8 bytes). A second source imports the original retained synthetic
receiver report byte-for-byte into the QA store: 200 final answers and 803
questionnaire events backed by a 24,405,317-byte typed artifact. The source QA
workspace is unchanged. This is not participant research or device qualification.

Local evidence lives outside the repository at
`C:/Users/User/Documents/Codex/2026-09-20/oka/work/irp-questionnaire-explorer-20260920-02`.
`worker-evidence.json` retains exact requests, receipts and resource audit rows
for the final core implementation; the earlier execution remains in
`worker-evidence-first-implementation.json`.
The browser harness creates a separate evidence directory per execution and
retains failed attempts as well as successful checks.
The complete 14-check browser execution is in
`browser-evidence-1789874123794/results.json`. Subsequent visual inspection found
a narrow-screen caption wrapping vertically; its accessible caption now uses
explicit scoped clipping, with an additional layout assertion in the harness.
The final UI/CSS execution is `browser-evidence-1789874536508/results.json`:
12 browser journey checks passed using the previously published indexes, with
all five scans clear of accessibility violations, overflow, undersized targets
and vertically wrapped captions. Desktop and narrow screenshots were also
visually inspected. The prior two cancellation/retry checks remain supported
by the 14-check execution; this layout-only rerun started no worker.
These screenshots precede the owner's name clarification: their temporary IRP
header was subsequently restored to the original Brohn assets and labels.
Explorer behavior and the scientific implementation were unchanged. External
evidence folder names and synthetic fixture titles are retained for traceability.

## Measured local preparation

| Source | Coordinator elapsed | Sampled peak resident memory | SQLite index |
|---|---:|---:|---:|
| 720 typed records | 29.85 s | 143.4 MiB | 1,626,112 bytes |
| Retained 200-answer history | 72.70 s | 236.9 MiB | 62,676,992 bytes |

The preparation profile permits 300 seconds, 1 GiB polled resident memory,
1 GiB scratch and a 1 GiB SQLite file ceiling. Resident memory polling is a
termination guard, not a hard allocation guarantee. The existing full typed
reader runs only in the supervised child. These fixtures do not establish
support for every source up to the codec's 512 MiB input bound.

## Reproduce

Use the restored R library and the native publication configuration from the
local installation guide. Component checks are listed in `scripts/qa-catalog.json`.
Create a fresh external folder whose basename starts `irp-questionnaire-explorer-`:

```text
Rscript --vanilla tests/platform-questionnaire-index.R
Rscript --vanilla tests/platform-questionnaire-explorer-storage.R
Rscript --vanilla tests/platform-questionnaire-explorer-views.R
Rscript --vanilla tests/fixtures/researcher-questionnaire-explorer.R setup FOLDER [RETAINED_FIXTURE_JSON]
Rscript --vanilla tests/fixtures/researcher-questionnaire-explorer.R worker FOLDER
node tests/researcher-questionnaire-explorer.mjs FOLDER
```

The optional retained fixture is original local QA evidence, not bundled data.
Inspect the browser harness's runtime paths before running on another machine.
Do not use an actual research workspace as a test fixture.

## Participant review refinement

`tests/participant-question-revision-delivery.mjs` passes 32 actual browser/receiver
checks and two automated accessibility scans with zero violations. Information
rows use **Review information**. Progress counts visible questions within the
current questionnaire occurrence, excludes information and hidden rows, and
labels answer/final review explicitly. Branching, adjacent parts, sealed Back
boundaries, reload and the existing 6+4 scoring fixture retain their original
protocol/design and receiver semantics. Evidence is retained at
`../../work/test-runs/brohn-question-revision-delivery-URD3ZU/results.json`.

## Remaining boundaries

Index publication is qualified on this Windows native-guard profile only.
Browser session links remain explicitly unavailable until exact local
protocol/event authorization is established; complete retained event payloads
are inspectable. Search does not claim Unicode case folding. This is scoped
software acceptance, not human usability, scientific-method or full-platform
qualification. The 50-capability plan and remaining work packages stay open.

The UI retains only bounded pages/detail and closes an idle view after 15 minutes.
There is no full-analysis Shiny cache or new shared process cache. Aggregate LRU
cache budgets in the design contract remain proposed, not implemented guarantees.
