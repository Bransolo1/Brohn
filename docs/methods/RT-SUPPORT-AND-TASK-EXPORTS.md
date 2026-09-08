# Reaction-time support and task-result exports

Implemented checkpoint, 8 September 2026. These are descriptive results from the
existing named Brohn task profiles. Browser/physical timing, materials and
population applicability retain their own qualification requirements.

## Per-measure support

New simple/choice RT analyses use `brohn-task-score/1.1` and
`brohn-rt-metric-support/1.0`. Collection profiles and compiled protocols are
unchanged. Complete expected trial evidence remains required, including practice.

| Measure | Eligible observations | Minimum |
| --- | --- | --- |
| Mean and median RT | Correct first test responses inside the frozen RT window | 1 |
| Within-task sample SD | Same retained correct responses; divisor n minus 1 | 2 |
| First-response error rate | Wrong first answers / all answered scored test trials, including outside-window answers | 1 answered test |
| Omission rate | Observed no-response timeouts / all scored test outcomes | 1 scored test |

Each metric stores `eligible`, `reason` and `support`, including its population,
eligible/minimum counts, numerator, denominator, denominator definition and
applicable RT bounds. A task-level `eligible:true` means at least one measure is
supported. Consumers must use **metric eligibility** for each outcome.

One correct 500 ms test response and39 observed timeouts produce mean/median500 ms,
unavailable SD,0/1 errors and39/40 omissions. All40 test timeouts produce100%
omissions; the error rate is unavailable because no test response was recorded.
Missing or interrupted task evidence cannot establish that complete denominator.
The UI labels partial results and shows support beside each measure.

Earlier `/1.0` reports are immutable and keep their original two-correct-response
gate. Non-RT scoring arithmetic is unchanged; no old result is silently rescored.

## Dedicated saved task results

Reports containing implicit/RT results expose **Download task scores CSV** even
when they also contain questionnaire observations. `brohn-task-score-csv/1.0`
contains one row per saved task metric, or an explicit unavailable-administration
row when no metric exists. It retains separate collection/material origins,
task/metric eligibility and reasons, recipe identity, native participant linkage,
counts, full D-score audit/cell support and per-metric support JSON. The report UI
also exposes pair/exclusion and target/action details in its scoring disclosure.

The generic observations download continues to prefer questionnaire observations
for mixed reports. Its task-only fallback now uses the same named task-score
columns. This deliberately replaces the earlier ambiguous task/metric `eligible`
and `reason` fields; the two can differ for a partial RT result.

CSV is a spreadsheet-safe display export: formula-like text has an apostrophe
prefix. JSON + provenance retains the original typed values. Neither download
claims to be a trial-source import file or an original event journal. The planned
[source-bound import/cohort route](../qa/IMPLICIT-IMPORT-COHORT-CONTRACT.md) requires
its own registry, trial semantics and evidence validation.

## Evidence

- `tests/platform-methods-rt-support.R`:56 checks using complete original journals
  through the real receiver and independent arithmetic for all five profiles.
- `tests/platform-methods.R`:324 checks including162 upstream IAT comparisons.
- `tests/platform-methods-rt-support-views.R`:12 checks for explanations, partial
  support, exact denominators, offline rendering and unchanged historical objects.
- `tests/platform-task-score-exports.R`:15 checks for mixed reports, unavailable
  metrics/administrations, separate origins, precision, audit retention and CSV.

Actual browser task-download QA and the broader import/cohort implementation are
separate from these component checks.
