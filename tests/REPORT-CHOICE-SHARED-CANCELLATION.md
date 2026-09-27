# Shared preparation cancellation regression

From an installed Brohn source checkout with its R dependencies available:

```text
Rscript tests/report-choice-shared-cancellation.R . /path/to/fresh-external-evidence
```

The evidence directory must not exist. A third argument may supply a complete loader checkout when the first argument is a partial candidate; omit it for normal installation. Run in a fresh R process. No browser, service, scientific dataset or Python worker is required.

This test uses real SQLite intents, queued/claimed jobs, fenced failure and cancellation. Explicit spies supply source metadata and preparation boundaries. It does not qualify native authority, worker processes or scientific calculations.

Intent A owns three running prerequisites. Intent B shares them and has one independent prerequisite. The independent job fails. Cancelling A must preserve all three running jobs because failed B retains them for retry. Explicitly cancelling B must remove its consumer count. The test also checks that all four dependency refs survive the failure, then makes every fixture job terminal and closes the store. A failed invariant exits nonzero; `results.json` retains the observed state.

Promotion: copy this file and `report-choice-shared-cancellation.R` into the repository's `tests/` directory. The independently reviewed source hashes and retained original failure are indexed in the external packet's `PEER-ROOT-HOOKS-REVIEW.json` and `PEER-ROOT-HOOKS-PORTABLE.json`. Those receipts describe the tested snapshot, not future installation results.
