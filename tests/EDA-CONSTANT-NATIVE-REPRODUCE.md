# Reproduce exact-constant EDA through native workers

Use the configured R, pinned methods Python and native publication guard from
[the EDA source guide](EDA-DISPLAY-REPRODUCE.md). These are synthetic software
checks, not participant collection or device qualification. Use short, fresh
output paths outside the repository. Never copy or open a live participant store.

First generate the ordinary EDA/event/liking originals with the existing generator:

```text
Rscript REPO/tests/eda-display-originals.R REPO ORIGINALS
```

Wait for a successful `ORIGINALS/results.json` and a closed store. Create a fresh
`CONSTANTS` directory. Copy `ORIGINALS/workspace` to `CONSTANTS/workspace` and
`ORIGINALS/results.json` to `CONSTANTS/original-results.json`. Keep the originals
unchanged. Save an absolute-path JSON configuration outside the repository:

```json
{"checkout":"C:/path/to/Brohn","out":"C:/brohn-qa/constants"}
```

Replace both paths with the actual checkout and fresh `CONSTANTS` directory.

```text
Rscript REPO/tests/eda-constant-originals.R CONSTANTS_CONFIG
```

This performs real ingestion and explicit recipe 1.1 scientific jobs for constant
levels, equivalent siemens input and mixed constant/ordinary/short segments. It
also leaves one imported constant source unanalysed for an actual researcher
journey. The original scientific job rows and reports must remain unchanged.
Only the newly created jobs must succeed; a deliberately retained cancelled
historical job is not a new scientific failure. Preserve failed receipts.

After this store closes successfully, create a fresh `PACKAGES` directory. Copy
`CONSTANTS/workspace` into `PACKAGES/workspace`, and copy
`CONSTANTS/results.json` to `PACKAGES/native-results.json`. Save another config
with the same checkout and `out` pointing at `PACKAGES`.

```text
Rscript REPO/tests/eda-constant-packages.R PACKAGES_CONFIG
```

This uses actual standalone reviews, display prerequisites and complete package
workers. It includes all six sources: constant levels, equivalent units, mixed
support, ordinary continuous EDA, event EDA and liking. It then creates a second
complete-evidence package without figures using the existing preparations.
Normal 60-second leases and the 300-second supervised worker deadline apply.
Do not extend these limits or remove sources to turn a failure into acceptance.
No new scientific analysis is permitted in this package phase.

Each completed package directory contains its exact downloaded HTML/ZIP/manifest
and guarded `original-source-bundle.json`. Keep the source paths available until
independent verification has finished:

```text
python -B REPO/tests/verify-eda-constant-report-download.py --bundle PACKAGE/original-source-bundle.json --zip PACKAGE/report.brohn-report.zip --html PACKAGE/report.html --output FRESH_ORACLE_OUTPUT
Rscript REPO/tests/report-eda-validation-performance.R REPO PACKAGE/original-source-bundle.json FRESH_CONTRACT_OUTPUT
```

The oracle creates the fresh output directory and writes `results.json` inside
it. The contract check compares old equality behavior, rejects invalid JSON, tests
same-size evidence tampering and changed scientific inputs, and verifies that
per-render model reuse cannot cross independent calls. Its call counters are
declared component instrumentation, not evidence of production job timing.

For an already saved browser package, `tests/eda-constant-original-bundle.R`
exports its guarded source bundle and verifies unchanged logical catalog tables;
read its argument contract before use. Close all services using that disposable
workspace first. Do not insert handcrafted scientific records to stand in for
ingestion or native publication.

Old recipe/model/package compatibility requires separately retained originals
created by the old implementation. Follow
[the history/source guide](EDA-CONSTANT-SOURCE-REPRODUCE.md) for that phase.
These commands do not establish browser usability, keyboard or phone layout,
cold startup, physical timing or scientific construct validity. Those have
separate acceptance records and source identities.

For this exact six-source full-versus-no-figures fixture, compare both packages
after their independent original-source oracles pass:

```text
python -B REPO/tests/compare-eda-constant-package-variants.py --full PACKAGES/mixed-all/report.brohn-report.zip --evidence-only PACKAGES/evidence-only/report.brohn-report.zip --full-oracle FULL_ORACLE/results.json --evidence-oracle EVIDENCE_ORACLE/results.json --output FRESH_COMPARISON/results.json
```

The comparison checks 49 unchanged complete data/evidence members, six exact
scientific refs, five exact EDA preparations, the source graph, complete coverage
and both manifest inventories. Its explicit omission list is 25 SVGs and five
section-bound presentation companions. The complete paired contrast and all four
original observations must remain in the scientific projection. This is a narrow
fixture-specific check, not a generic licence to discard companion files.
The strict oracle's `--compare-zip` mode requires the same scientific **and
prepared** source sets; it correctly refuses this variant's removed optional
distribution preparation. Run both standalone oracles and the explicit comparison
instead of weakening that mode.
