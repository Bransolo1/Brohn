# Portable clock Python source-test proposal

27 September 2026. `proposed-tests/` contains an installed-layout source bundle
and a separate catalog addition fragment. Production and the accepted backend
checkout were not modified. No source API was changed.

## Actual qualification

`frozen-repo-01` was copied from the accepted plot-adapter checkout07, preserving
all 1,221 original files byte-for-byte. The proposed tests and one catalog entry
were added only to the new copy. The source snapshot is retained in
`frozen-repo-01-receipt.json`.

The actual installed `scripts/run-checks.R --test clock-python` route ran once
against that frozen combined source. `catalog-run-01/results.json` reports
success in 49.6 seconds. Its nested clock suite reports 141 passing checks:
affine 21, source 17, preview 13, events 10, window 19, window-worker 23, plot 24 and
plot-worker 14. Every per-component source fingerprint remained unchanged.
There were no failing qualification attempts or component reruns in this bundle
phase. The earlier external component/integration failures remain documented in
their original phase receipts.

The real R launcher supplied its running R executable to the plot-worker test.
That test generated a fresh worker result, parsed/re-serialized it through the
installed `brohn_json`, and verified its unchanged meaning and exact full plot
artifact bytes. No previously saved machine-local R-roundtrip file was used.

## Proposed repository additions

- Eight Python test scripts, `clock_test_support.py`, two R launcher/roundtrip
  scripts and `tests/CLOCK-PYTHON-REPRODUCE.md`.
- An identical copy of the already tracked synthetic linked-review fixture.
- One `clock-python` / `interchange` entry proposed by
  `qa-catalog-additions.json`, with a timeout of 2,100 seconds. No configured-profile
  expansion and no change to `scripts/run-checks.R`.

Only the files in `proposed-tests/tests/` are candidates for copying into the
repository's `tests/`. Merge the proposed catalog entry into the existing
`scripts/qa-catalog.json` without replacing other entries. The staging generators,
copied validation tree and retained evidence directories are not publication
payloads.

## Preserved and excluded evidence

Existing deterministic assertions and independent oracles were retained for
affine, source, preview and complete windows. Event and worker inputs now come
from the actual importer over fresh synthetic fixtures rather than external
acceptance directories. The original plot test dependent on three genuine saved
catalog records was excluded explicitly. It was not replaced with a fabricated
catalog or claimed as portable history qualification.

The R map tests were inspected: their save/version/atomic completion/retry and
fresh-process checks rely on original preserved importer/preview/job receipts
and runtime configuration. They remain separate supervised integration evidence.
No application authority, browser, real device or scientific construct claim is
made by this Python bundle.

Portable source files contain no absolute local runtime or accepted-workspace
paths. Configured Python and R executables are supplied by the installed runtime;
all original synthetic inputs, artifacts, faults and receipts are written under
a fresh caller-owned evidence directory outside the source repository.
