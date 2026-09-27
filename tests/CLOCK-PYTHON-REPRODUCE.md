# Reproduce the deterministic clock component checks

This suite creates synthetic recordings through Brohn's actual preservation
importer, then exercises exact clock arithmetic, complete source/event inspection,
reviewed previews, complete original-row windows and their display artifacts.
It uses the installed worker modules and creates all generated data in a fresh
external evidence directory. It never opens a configured research workspace.

The catalog entry is `clock-python`, in the `interchange` suite. After
the clock workers and this test bundle are installed, configure
`BROHN_PYTHON_METHODS` to the installed methods Python executable and run from the
repository root using the restored R environment:

```text
Rscript --vanilla scripts/run-checks.R --test clock-python --output C:/Brohn-QA/clock-python-01
```

Choose a new output directory for each run. The existing catalog launcher keeps
its own source identity, logs and result manifest. The clock launcher retains an
additional per-component receipt and output logs below that directory. Tests
refuse an existing output folder rather than deleting earlier evidence.

For a direct run of the same R launcher:

```text
Rscript --vanilla tests/platform-clock-python.R C:/Brohn-QA/clock-python-direct-01
```

The eight Python tests can also run separately as
`python -B tests/clock-NAME.py EXTERNAL_NEW_DIRECTORY`. The plot-worker test
executes an actual R canonical-JSON roundtrip; provide `BROHN_TEST_RSCRIPT` or
put `Rscript` on PATH when invoking that Python test directly. The registered
R launcher supplies its own R executable automatically.

## Included coverage

| Component | Checks | Principal evidence |
| --- | ---: | --- |
| Affine arithmetic | 21 | Independent integer cross-products, exact clocks/units, drift/residuals, bounded decimal parsing |
| Original source | 17 | Generated canonical streams, full source/segment/identity inspection, corruption beyond selected rows |
| Reviewed preview | 13 | Actual original-event selections, independently expected affine relation, held-out checks, identity/origin/reset refusal |
| Event pages | 10 | Whole-source searches/counts, repeated labels, exact number tokens, unselectable originals and bounded pages |
| Complete window | 19 | Every-row independent Fraction/value/endpoint oracle, complete exports, unequal rates, gaps, empty and paged windows |
| Window worker | 23 | Actual worker outputs, preview binding, optional identity, malformed output and byte/resource refusal |
| Complete plot | 24 | All 6,700 selected rows, late extrema, page independence, rational bins, gaps, event counts, constants/unavailable states and narrow exact axes |
| Plot worker | 14 | Actual child execution/verifier, complete artifact binding, partial-output refusal and actual R JSON interoperability |

All 141 checks passed once through the real catalog launcher in the external
qualification run. This count describes those component checks, not 141
independent research methods or end-to-end acceptance scenarios.

`clock_test_support.py` constructs fresh recordings locally. The existing
`fixtures/researcher-linked-review.py` is also a deterministic synthetic source
generator; the bundle includes its identical source for dependency clarity.
No recordings, SQLite stores, previous acceptance results, participant files,
device SDKs, model weights or local runtime paths are required by these tests.

## Explicit exclusions

The original plot test that reopened three genuine previously published saved
windows was intentionally not ported. It requires the original supervised
catalog and job history and remains separate integration evidence. The portable
plot count is therefore 24, while the corresponding external component suite
contains 25 tests.

The previous event/window-worker synthetic input files were replaced with newly
generated equivalent declared fixtures. Their assertions remain component
checks; generating these fixtures does not reproduce any original investigator
dataset or historical application publication.

R map save/version/retry/atomic publication tests, worker actor/reader authority,
native resource lifetimes, persisted-history migration, browser flows and
physical-device/construct qualification are outside this suite. The accepted
map tests require retained original import/preview receipts and private
configuration; they were inspected and kept separate rather than relabelled as
portable Python checks. Preview/event worker orchestration is also not inferred
from these pure component tests.

This catalog entry does not add this suite to the separately reviewed
`portable-core` configured profile. No application or test runner API change is
required.
