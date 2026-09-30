# EDA parent lease pulse component test

Use the project's pinned R library (set `R_LIBS_USER`), then run from a checkout:

```text
Rscript tests/eda-report-lease-pulse.R REPO_ROOT FRESH_OUTPUT
```

The test runs in about a few seconds without a service or child process. It creates only new synthetic SQLite stores in `FRESH_OUTPUT`. It extracts the exact pulse-installation expression from `brohn_process_job` and evaluates it in a private environment with a coherent injected wall/store clock. The actual claim, renewal, cancellation, publication-owner guard and terminal job APIs remain unchanged. No production namespace, options or source files are modified.

The checks cover a normal 60-second lease across 120 simulated seconds of preparation/short-child/publication phases, immediate cancellation, exact expiry, replacement attempts, captured original identity, both deadline bounds, safe terminal failure, and exclusion of legacy routes. The final receipt pins every loaded source hash and the executed pulse expression.

This is deterministic component coverage. It does not qualify native source holds, child supervision, actual scheduling latency, full report assembly or browser recovery. Those need the separate real normal-60-second worker, callback-cleanup and connected research journeys. A callback after an already expired lease must refuse; it never revives that attempt.
