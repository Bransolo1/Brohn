# Reproduce saved constant EDA reader and export checks

These checks read generated or separately retained scientific outputs. They do
not run a detector, fit a signal, replay a study or establish device validity.
Keep the output directories fresh. Python 3.12.10 is the qualified report
runtime; the export oracle uses only its standard library.

Generate original component fixtures separately with the repository's
`tests/eda-constant-producer.py`, following its documented arguments. That
producer check needs the pinned methods environment and a saved pre-change
baseline checkout. Its corpus must retain each case's original `result.json`,
source CSV and typed artifact pair. The pure script labels its minimal report
wrappers as synthetic; they are not native saved reports.

```text
python -B tests/eda-constant-pure.py REPO REPO BASELINE GENERATED_CORPUS FRESH_PURE_OUT
Rscript tests/eda-constant-report-pure.R REPO REPO FRESH_PURE_OUT FRESH_RENDER_OUT
python -B tests/eda-constant-oracle-refusals.py REPO FRESH_PURE_OUT FRESH_ORACLE_TEST_OUT
```

The Python component check covers six source levels/units, complete null
coordinates and CSVs, explicit unavailable measures and denominators, mixed,
short and segmented support, profile refusal, and the actual 500,001-coordinate
capacity boundary. It reports a skipped direct legacy comparison if the input
legacy fixture was generated without artifacts; it never substitutes previews.
The R check exercises the catalog and explanatory figures/tables, using real
report styles. It does not claim browser, print or published-package testing.

For the direct legacy comparison, supply a retained preparation request with
its complete original files still available. This is read-only and does not
reopen its source store:

```text
python -B tests/eda-constant-legacy-python.py REPO BASELINE OLD_PREPARATION_REQUEST FRESH_LEGACY_OUT
```

It compares the entire original recipe-1.0 direct model and three CSV files,
preparation-0.1 evidence/catalog/verifications, and old model conservation
inside new preparation 0.2. Original file hashes must remain unchanged.

For an actual native package, first export the original supervised source
bundle through the guarded application reader. Keep its sealed-copy paths
available while running the independent oracle. The actual HTML must be the
browser or guarded-resource download corresponding to the ZIP:

```text
python -B tests/verify-eda-constant-report-download.py --bundle ORIGINAL_BUNDLE --zip ACTUAL_ZIP --html ACTUAL_HTML --output FRESH_ORACLE_OUT
```

Add `--compare-zip PRIOR_ZIP` for a figure-only change using the same exact
scientific **and prepared** source sets. Removing an optional distribution
preparation changes that contract even when the complete scientific evidence
remains identical. Use the narrowly scoped comparison in
[the native guide](EDA-CONSTANT-NATIVE-REPRODUCE.md) for the qualified six-source
full-versus-no-figures pair. The strict oracle remains unchanged.
The oracle permits legitimate section-ordinal file relocation
while requiring complete companion roles, media types, bytes and multiplicity.
It checks all original scientific values/types/nulls/order and alias joins;
every typed stream row and complete CSV; the ten constant findings and null
amplitude denominators; coordinate indices, times, edge masks and empty
candidate tables; old grammar inside new packages; SVG geometry or truthful
status panels; and deterministic offline ZIP/HTML integrity. It imports no
Brohn application or scientific module.

Use the qualified R library and methods/native runtime configuration described
by the repository's QA setup for R loading. These tests do not change global
runtime settings, start a service, raise capacity limits or trim evidence.
Native worker authority, lease lifecycle, browser accessibility and cold
history remain separate integration gates; component success does not replace
them.
