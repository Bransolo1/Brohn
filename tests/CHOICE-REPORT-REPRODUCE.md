# Reproduce the choice report checks

These tests generate their input using Brohn's synthetic source/preparation test,
then render complete saved results without refitting, rescoring or replaying a
journal. No participant dataset, saved workspace, archive or runtime is checked
into the repository for these tests.

Use the installation guide to configure R and its packages, the methods Python
executable and the native publication guard. The original/preparation stage needs
`R_LIBS_USER`, `BROHN_PUBLICATION_PYTHON`, `BROHN_PYTHON_METHODS` and
`BROHN_PUBLICATION_NATIVE_MANIFEST` set for that installation. The qualified
archive/raster profile uses CPython 3.12.10 and Pillow 12.3.0. Do not substitute an
unqualified runtime by editing the profile. Every output directory below must be
fresh; keep evidence outside the checkout.

In these commands, replace `REPO`, `SOURCE_OUT`, `RENDER_OUT`, `CHECK_OUT`, and
`PYTHON` with absolute paths, and use the configured Rscript executable:

```text
Rscript REPO/tests/choice-display-backend.R REPO SOURCE_OUT
Rscript REPO/tests/choice-report-package-resolver.R REPO CHECK_OUT/resolver
Rscript REPO/tests/choice-report-package-pure.R REPO SOURCE_OUT/backend RENDER_OUT PYTHON
```

The first command produces the exact original report and saved preparation
envelopes used by the pure stage: `native-prepared.json`,
`native-task-prepared.json`, `native-distribution-prepared.json`, and
`import-prepared.json`. Input generated elsewhere is also acceptable if its
original producer and preparation provenance are retained; a hand-authored model
fixture is not proof of genuine preparation or scientific-worker execution.

The resolver has 20 synthetic metadata/type/page-boundary and display-label
checks. The pure stage has 14 checks covering mixed native RT/liking/scale/choice
results, three saved utility states, original and package-alias identity modes,
explicit nulls and absent fields, opaque response IDs, complete companions when
figures are removed, deterministic repeat output, and keyboard-scroll markup.
Scientific and journal-replay entry points are replaced by fail-fast stubs during
pure assembly. The source stage has its own separately reported checks.

Run the independent Python oracle on the four default/focused exports:

```text
PYTHON REPO/tests/verify_choice_download.py --bundle RENDER_OUT/native-default-bundle.json --zip RENDER_OUT/native-default/report.brohn-report.zip --html RENDER_OUT/native-default/report.html --output CHECK_OUT/native-default
PYTHON REPO/tests/verify_choice_download.py --bundle RENDER_OUT/native-focused-bundle.json --zip RENDER_OUT/native-focused/report.brohn-report.zip --html RENDER_OUT/native-focused/report.html --compare-zip RENDER_OUT/native-default/report.brohn-report.zip --output CHECK_OUT/native-focused
PYTHON REPO/tests/verify_choice_download.py --bundle RENDER_OUT/import-default-bundle.json --zip RENDER_OUT/import-default/report.brohn-report.zip --html RENDER_OUT/import-default/report.html --output CHECK_OUT/import-default
PYTHON REPO/tests/verify_choice_download.py --bundle RENDER_OUT/import-focused-bundle.json --zip RENDER_OUT/import-focused/report.brohn-report.zip --html RENDER_OUT/import-focused/report.html --compare-zip RENDER_OUT/import-default/report.brohn-report.zip --output CHECK_OUT/import-focused
PYTHON REPO/tests/choice-report-oracle-refusals.py RENDER_OUT/import-default-bundle.json RENDER_OUT/import-default/report.brohn-report.zip CHECK_OUT/refusals
```

The independent reader imports no Brohn/scoring code. It checks exact typed
scientific/provenance values, allowed identity relationships, complete CSV and
prepared-model collections, actual SVG values/coordinates, static HTML links,
and ZIP inventory/hash/CRC/fixed metadata. Focused comparisons require identical
complete source/exercise companions. A saved distribution may move with a
section ordinal only when its exact source identity, bytes, role and multiplicity
are unchanged. Use `--compare-zip` only for the same renderer implementation;
changing renderer source correctly changes the projection's implementation hash.

The nine negative cases mutate copied artifact bytes and recompute inventory
hashes. They must still refuse dropped rows, null/blank and false/zero changes,
opaque-ID substitution, unknown scientific fields, changed mapped cells, broken
alias joins, a null standard error changed to zero, and false coverage. Original
inputs remain untouched. Successful receipts are `results.json` in each fresh
output directory. The first qualified portable run passed 58, 55, 26 and 27 oracle
checks respectively, plus all nine negative cases; counts describe that fixture,
not independent platform features.

These pure tests do not establish current-reader authorization, native seals,
worker cancellation, application browser behavior, visual accessibility, real
participant timing, physical device synchronization or estimator validity. The
source test separately exercises native preparation/publication. Repeated visits,
packed reports, 60-item page-two charts, nonuniform utilities and actual browser
downloads have additional retained qualification evidence and are not claimed by
this compact portable invocation. No test reruns the whole seven-profile task
scoring suite.
