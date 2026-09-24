# Exact paired aggregation without repeated regrouping

The existing saved comparison scorer rebuilt its entire person-group index once for every person when constructing `participant_differences`. This made the final summary quadratic despite already having computed the same groups for the person means.

`brohn_paired_contrasts()` now keeps the ordered session and person index lists within each condition comparison. The existing loops, means, exclusions, person ordering, t intervals and output fields use those same indices. The change adds no statistical defaults, eligibility rule, pairing inference, timeout increase or new scoring scheme. The grouping function and research-method identifiers are unchanged.

## Measured baseline and production result

The original synthetic benchmark has 1,000 people and 3,000 observations: two control observations (10 and 14) and one test observation (14) per person. A second declared test condition has no observations and retains its original unavailable result. The expected supported difference is 2 for every person. The benchmark includes a frozen copy of the pre-change implementation plus separate unequal-repeat and closed-form numerical oracles.

| Measurement | Frozen baseline | Optimized production |
| --- | ---: | ---: |
| Elapsed time, same 1,000-person input | 191.23 s | 2.36 s |
| Calls to person grouping | 1,002 | 2 |
| Person rows regrouped | 1,001,000 | 1,000 |
| Calls to session grouping | 4 | 2 |
| Session rows regrouped | 12,000 | 6,000 |

The direct scorer was approximately **81 times faster** on this fixture and host. The before/after complete canonical output hash is identical: `bb1e74e099b40cac976af0a150b188cf943985d5e1c530771554c1389e6f76b0`. Rprof attributed 99.71% of the baseline's sampled inclusive time to `brohn_group`; sampled profiler time is distinct from elapsed time. An isolated in-process candidate measured 2.81 s before shared source was edited. Production was then measured separately against the retained original baseline.

No broader scale or device-performance claim follows from this benchmark. The prior actual questionnaire worker took about 190 seconds for this source; end-to-end publication also includes imports, validation, provenance and immutable-object publication.

## Regression coverage

`tests/platform-paired-aggregation.R` passes 15 ordinary checks and 18 checks in benchmark-verification mode. It requires exact R-object and canonical-JSON equality with the frozen implementation across source permutations, opaque identities, multiple outcomes and units, unequal repeat visits, one/no condition pairs, all-missing inputs, nonfinite-value exclusions and empty selections. Independent arithmetic checks use person differences 4, 8 and 12, with estimate 8 and the df=2 closed-form uncertainty. The declared analysis-plan path must retain its complete analysis, p-values and multiplicity exactly.

The existing `tests/platform-analysis.R` also passes its 46 independent gaze, explicit-response, phase, missingness, identity and typed-value assertions after the change. `tests/platform-scale-comparisons.R` passes 31 checks, including its actual saved worker, scoring-key provenance and stale-action coverage.

Four actual workers re-published the accepted questionnaire, gaze, 1,000-person and combined fixtures from pinned original inputs in a fresh external workspace copy. Each new report preserves the complete original canonical analysis and provenance exactly, including all observations, exclusions, participant ordering, confidence intervals, p-values, multiplicity and source revisions. Each original report remains unchanged.

| Actual worker operation | Elapsed time |
| --- | ---: |
| Questionnaire | 6.63 s |
| Gaze | 4.57 s |
| 1,000-person questionnaire | 24.70 s |
| Combined comparison | 6.19 s |

These are complete supervised worker timings, distinct from the 2.36-second direct scorer benchmark. All four published reports fingerprint the optimized `R/platform-analysis.R` as `53ec896ba7f7d5d1e54e1b73a0c06fa1031da02a11382827409a12e7b07dd330`.

The first harness process printed all four successful comparisons and wrote their receipt, then exited with a trailing parse error because its test file was edited while R was still reading it. This process is retained as failed evidence; it is not described as a passing harness run. After it exited, a separate `tests/fixtures/verify-paired-aggregation.R` run passed with exit code 0 without launching jobs. That independent verification reopened the original and copied stores and checked all four terminal job states, original and new report hashes, complete canonical outputs, and the saved processing fingerprints against current source. No original accepted report was rewritten.

## Reproduction and evidence

Use restored Brohn R dependencies and the registered publication runtime from the repository root.

```text
Rscript tests/platform-paired-aggregation.R
Rscript tests/platform-paired-aggregation.R --benchmark <external-baseline-receipt.json>
Rscript tests/platform-paired-aggregation.R --verify-benchmark <external-baseline-receipt.json> <external-production-receipt.json>
Rscript tests/fixtures/researcher-paired-aggregation.R <accepted-paired-browser-fixture-directory> <fresh-external-worker-directory>
Rscript tests/fixtures/verify-paired-aggregation.R <accepted-paired-browser-fixture-directory> <completed-external-worker-directory>
```

The last directory must already exist, have a name beginning `brohn-paired-aggregation-worker-`, and contain no workspace. The accepted source fixture must include its optional `seed-stress` report. Preserve the original receipt for verification rather than repeatedly spending three minutes rerunning the frozen reference.

External profiling evidence is in `make/work/test-runs/brohn-paired-aggregation-20260924-01/`: `baseline-and-candidate-02.json`, `production.json` and their Rprof files. The initial profiling attempt was interrupted because line wrapping in the test's candidate-generation step defeated its substitutions. Its partial profiler output and explanation remain available; no production source was changed by that attempt. The corrected benchmark derives its candidate from exact frozen fixture text and checks the replacement before expensive profiling.

External worker evidence is in `make/work/test-runs/brohn-paired-aggregation-worker-20260924-01/`:

- `acceptance.json`: SHA-256 `d5bfee1d1a1b7a90a6768576affbea0d121a4ebde7028926ae18750c3d6cbc52`.
- `retained-output-verification.json`: SHA-256 `a7649c8124bd75b23c4675a7d0ffa23898b27a2f7c4f28cccc6425bc94fca042`.
- `harness-process-failure.txt`: the failed parent-process output and recovery explanation.

The accepted original source is `make/work/test-runs/brohn-paired-browser-20260924-01/`. QA workspaces, datasets and receipts remain external to the repository; committed fixtures generate only original synthetic research data.
