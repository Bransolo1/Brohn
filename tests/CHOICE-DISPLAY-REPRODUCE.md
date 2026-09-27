# Choice source and preparation regression

These two proposed public files generate synthetic originals and exercise real
local scientific and preparation workers. They do not require a checked-in
participant dataset or this development packet.

- `tests/choice-display-backend.R`
- `tests/fixtures/choice-report-originals.R`

Use the repository installation guide to configure R packages, the methods
Python executable and native publication guard. In the same shell, configure
`R_LIBS_USER`, `BROHN_PUBLICATION_PYTHON`, `BROHN_PYTHON_METHODS` and
`BROHN_PUBLICATION_NATIVE_MANIFEST` for that installation. This test requires
actual native source/publication seals and fails if they are unavailable.

Run with the actual Rscript executable and absolute paths:

```text
Rscript tests/choice-display-backend.R <repo-root> <fresh-evidence-directory>
```

The evidence directory must not already exist. Prefer a directory outside the
checkout. The test creates all studies, synthetic receiver events and imported
CSV rows under that directory, closes stores and settles owned jobs on failure,
and leaves evidence for diagnosis. It does not launch an application service.

The accepted first execution (`portable-01`) passed **12 original-source checks,
21 preparation checks and seven malformed-result refusals**. These are separate
phases, not 40 distinct platform features. The original phase uses two genuine
scientific workers: one native mixed choice-RT/liking/reverse-scale/MaxDiff report
and one imported choice report. The preparation phase adds two choice displays,
one task display version0.2 and one explicit distribution version0.2, conserving
the original scores and objects. Pure refusals disable fit, likelihood and score
entry points, then reject malformed parameter types/semantics, missing design
coverage, zero probability mass and invented probability support.

The resulting `backend/` folder contains the exact portable inputs for the pure
report tests:

- `native-prepared.json` — original report plus saved choice display.
- `native-task-prepared.json` — same original plus saved task display version0.2.
- `native-distribution-prepared.json` — saved explicit distribution version0.2.
- `import-prepared.json` — imported original plus saved choice display.

Original scientific work finishes before the preparation/export boundary. Native
task preparation performs its separately identified registered display audit;
choice and distribution preparation do not refit or rescore original results.
The test does not qualify real participant timing, physical devices, hosted
identity providers, browser interaction, cancellation during a live child, or
all seven task profiles mixed with choice. The mixed native witness uses the
existing choice-RT profile. Separate retained gates cover repeated visits,
packed sources, 60-item and nonuniform examples, local reader guards and native
proof faults; their counts should not be assigned to this portable invocation.
