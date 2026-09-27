# Reproduce connected saved EDA reports

These commands generate synthetic originals, then exercise real saved intents,
display/distribution workers, native source guards, complete report publication
and current-reader checks. They do not collect participants or qualify a device.
Use [the source guide](EDA-DISPLAY-REPRODUCE.md) to configure R, the pinned methods
Python runtime and the native publication guard first. Keep all generated stores
outside the checkout and use fresh short paths, for example under `C:/brohn-qa`.
The destination's parent directory must already exist. Never supply a live store.

Replace uppercase placeholders with absolute paths and use your configured
Rscript/Python executables. No API credentials or local datasets belong in Git.

```text
Rscript REPO/tests/eda-display-originals.R REPO ORIGINALS
Rscript REPO/tests/eda-report-originals-extended.R REPO ORIGINALS EXTENDED
Rscript REPO/tests/report-eda-packages.R REPO EXTENDED REPORT_CHECKS
```

The extension copies the closed original store, then generates seven further
ingestion/scientific jobs: an unavailable continuous recording, four controlled
person/condition cells, an explicitly reviewed EDA/liking crosswalk and paired
comparison, and event cvxEDA. It retains the different two-person EDA and
one-person liking denominators. No display or report-export job runs in this
source-generation stage. Input originals remain unchanged.

The report test copies that extended store and runs nine package variants:
event, unavailable, cvxEDA, paired-only with its required EDA parent, paired plus
the same selected parent, continuous with liking, evidence without figures,
an exact-decimal focused window and a figure-only change. It checks preparation
reuse, complete related-source inclusion, exact published download bytes,
revoked/restored producer proof and unchanged original science. It records
worker and export timings; concurrent qualification is not a capacity benchmark.
Jobs use the normal 60-second worker lease. Renewal must span parent source
preparation, child execution and verified publication; extending the test lease
would conceal the cancelled-report recovery defect found in the browser journey.

For independent runs, a fourth argument can be `sources`, `paired` or `mixed`.
Use a different fresh output directory for each group. Together those groups
cover the same nine cases as the default `all`; running both is unnecessary.
Each output has `results.json`, and each completed package retains its exact
HTML, ZIP, manifest and separately extracted `original-source-bundle.json`.
Retain failed outputs. Correct a failure and use a fresh run, rather than editing
its results or changing already-running source files.

Use the independent stdlib oracle on every completed package:

```text
PYTHON REPO/tests/verify-eda-report-download.py --bundle PACKAGE_DIR/original-source-bundle.json --zip PACKAGE_DIR/report.brohn-report.zip --html PACKAGE_DIR/report.html --output FRESH_ORACLE_OUT
```

See [pure export checks](EDA-REPORT-PACKAGE-REPRODUCE.md) for typed-value,
geometry, alias, complete-stream and substitution checks. A saved source bundle
references exact held artifact copies; keep those files with the test output
until the oracle finishes. The oracle imports no Brohn scientific implementation.

## Optional real child lifetime

```text
Rscript REPO/tests/eda-large-originals.R REPO LARGE_ORIGINALS
Rscript REPO/tests/eda-display-lifetime.R REPO LARGE_ORIGINALS FRESH_LIFETIME_OUT large-report
```

The large witness has500100samples and can take several minutes and substantial
disk space. Its constant input deliberately exposes an unresolved legacy
detector counterexample: tiny numerical fluctuations are saved as candidates.
This is a software resource/cancellation witness, not valid physiological
response evidence. Preserve its exact-flatline and synthetic labels.

The lifetime test observes actual R and Python process identities before normal
cancellation or lease replacement under a declared temporary test clock. It
checks workers stop before native source guards are released, all guards close,
obsolete publication fails and originals remain exact. Parent observation is
instrumented. A small input that finishes before the helper is observed does not
pass cancellation qualification merely because normal cleanup succeeded.

These commands do not establish researcher browser behavior, visual accessibility,
print layout, cold application restart, device timing, construct validity or
large-workload readiness. Those have separately reported acceptance phases.
