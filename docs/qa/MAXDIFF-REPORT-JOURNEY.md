# MaxDiff completed-study report acceptance

`tests/researcher-maxdiff-reports.mjs` passes **24 assertions and four
accessibility scans**, with **five actual production worker processes**.
The fresh run did not use its report-only resume mode. Evidence is retained at
`work/test-runs/brohn-maxdiff-researcher-Quiv8b/report-evidence/results.json`.
The source study was created through the separately verified
[researcher authoring journey](MAXDIFF-RESEARCHER-JOURNEY.md).

## Independent numerical and identity oracle

Three actual browser visits complete the frozen four-set required importance
exercise and explicitly skip every set of the optional preference exercise.
Their required choices cycle across the three offered positions: first/second,
second/third and third/first for best/worst. Thus each item has exactly three
best selections, three worst selections and nine complete-pair exposures. Its
exposure-adjusted score is zero. The connected aggregate fit has neutral
utilities and probability `1/6` for every distinct ordered pair in each triple.

Every optional item has nine presented missing exposures, zero complete-pair
exposures and an unavailable adjusted score. Its aggregate fit remains
unavailable. Missingness is not turned into indifference. The separately
answered liking values are `1`, `3`, `5`, with mean `3`; choice pairs are not
counted as questionnaire answers.

The first two visits use the same explicit source code; the third uses another.
Reports therefore retain three sessions and two declared person codes. They
also retain the actual browser response clocks, exact event hashes and sample
origin. They perform no independent-participant inference and make no claim
of scientifically qualified consumer preference measurement.

## Observed full workflow

| Action | Actual evidence |
| --- | --- |
| Complete visits | Each completed browser visit saves its response journal and queues exactly one automatic analysis request. Three initial scientific subprocesses publish their receipt reports. |
| Freeze a cohort | The researcher queues a cohort containing the exact three completed run IDs and explicitly cancels it. |
| Add a later visit | A fourth actual completed visit produces its own automatic report. It does not silently enter the earlier frozen request. |
| Retry saved inputs | The actual Retry saved inputs action creates a new attempt containing exactly the cancelled request. Its report uses the original three visits and excludes the fourth. |
| Audit the result | Counts, denominators, missingness, model probabilities, declared participant/session counts and separate liking match the independent oracle above. |
| Verify persistence | Downloaded JSON equals the catalog report. Removing only its expected result-object handle makes the report exactly equal to its retained publication envelope. The retained object's SHA-256 matches its recorded handle; no numerical tolerance is used for this equality. |
| Export complete data | Dedicated choice CSV contains all 24 exposure identities and actual offered orders: 12 complete required pairs and 12 explicit optional omissions, with source hashes and sample origin. Generic observations CSV contains only the three liking responses. |
| Read offline | The actual HTML download contains both distinct exercise sections, count regions and aggregate utilities. Desktop and 390px offline scans pass. |
| Reopen history | A fresh researcher browser session opens byte-identical report JSON. The study and report remain unchanged. Final history contains four automatic visit reports, one frozen retry report and the cancelled predecessor. |
| Accessibility | Saved report desktop/narrow and offline HTML desktop/narrow have no axe violations or page overflow. No visible Shiny failures or browser exceptions remain. |

The report-only recovery option exists to inspect already executed immutable
results after a UI fix. It asserts the retained successful jobs and does not
pretend to rerun workers. The final passing evidence above was a fresh full
execution with five workers, not that recovery path.

## Findings fixed before the fresh pass

The original report review found a skipped heading level and duplicate table
region names when two exercises were present. Utilities now use a third-level
heading, and every result/coverage/evidence table includes an exercise ordinal
and title. Ordinals keep the accessible names distinct even when titles match.

The exact persistence check also found catalog rounding of binary64 values,
including `1/6`, while the retained publication file preserved more precision.
The fix uses the same 17-digit numeric encoder as the protocol/report contract.
Original stored JSON and hashes are not rewritten. Entity/job replay preserves
old exact decoded values and rejects previously rounded-away differences;
receipt-target checks and bounded legacy near-limit replay are covered by
`tests/platform-json-precision.R`. The earlier failing fixture under
`work/test-runs/brohn-maxdiff-researcher-3OsQjp` remains untouched as evidence.

This is an automated simulated researcher and synthetic response pattern using
actual local services and scientific subprocesses. It is not observation of
human users, physical-device or onset qualification, preference reliability
evidence or validation of a field-study design. Frozen cancelled-request retry
is exercised; a general rerun-successful-report UI action is not claimed.
