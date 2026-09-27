# Saved EDA preparation: source and worker regression

These tests generate synthetic research inputs or consume an explicitly supplied,
closed original fixture store. No participant corpus is included in Git. Use a
fresh, short local output path for each command, such as `C:/brohn-qa/eda-originals`.
Windows legacy path limits still apply to existing upstream scientific artifacts.

Run the repository's documented installation and native publication readiness
steps first. Required methods runtime is the pinned CPython 3.12.10 environment;
the published EDA methods dependencies must be installed. Configure `R_LIBS_USER`,
`BROHN_PYTHON_METHODS`, `BROHN_PUBLICATION_PYTHON` and
`BROHN_PUBLICATION_NATIVE_MANIFEST` to that installation. These are executable or
manifest paths, not API credentials. Commands below use your actual Rscript
executable, repository checkout and fresh evidence directories.

```text
Rscript tests/eda-display-primitives.R REPO FRESH_PRIMITIVES
Rscript tests/eda-display-originals.R REPO FRESH_ORIGINALS
Rscript tests/eda-display-source-validation.R REPO ORIGINALS FRESH_VALIDATION
Rscript tests/eda-display-workers.R REPO ORIGINALS FRESH_WORKERS
Rscript tests/eda-display-source-windows.R REPO WORKERS FRESH_WINDOWS
Rscript tests/eda-display-source-integrity.R REPO WORKERS FRESH_INTEGRITY
Rscript tests/eda-display-boundaries.R REPO WORKERS FRESH_BOUNDARIES
Rscript tests/eda-display-source-pulse.R REPO ORIGINALS FRESH_SOURCE_PULSE
Rscript tests/eda-large-originals.R REPO FRESH_LARGE_ORIGINALS
Rscript tests/eda-display-large-recovery.R REPO LARGE_ORIGINALS FRESH_LARGE_RECOVERY
```

The first test covers exact decimal request normalization, typed-value hashing,
JSON transport, signed zero, unsafe lexical integers, and separation from the
existing explicit-distribution helper names. It does not start a scientific job.

The originals generator creates six actual ingestion/scientific jobs before any
export boundary: event EDA, continuous EDA and explicit liking in one synthetic
study. Event witnesses include response, nonresponse, overlap, missing data and
processing-edge support. Continuous witnesses include siemens-to-microsiemens
conversion, more complete rows than the preview, marker paging, computed and
unavailable segments. Liking retains missing responses, the saved paired estimate
and its null interval. Similar textual identifiers do not establish cross-source
identity; this generator does not create a combined estimate.

The semantic test accepts these original event/continuous files and optionally
the separately generated `controlled`, `cvxeda` and `unavailable` originals. It
refuses unregistered nested fields, altered support/eligibility/counts and null
coercion. Its record lists exactly which original families were supplied. It does
not fit or recompute any measure.

The worker test copies the supplied closed `ORIGINALS/workspace` into its fresh
output directory, then queues real EDA display jobs for the recognized original
reports. It opens the resulting evidence under native read guards, retains exact
artifact byte copies and validates source/catalog/model bindings. It checks that
original job rows, revisions, object metadata and bytes remain unchanged. Output
includes `*-prepared.json`, byte-bound `*-evidence.json`, and `results.json` for
the renderer tests. Do not run it against a live source store.

The window, integrity and boundary tests each copy that closed worker fixture. Window tests compare
cold source metadata with the exact published keys/bounds while forbidding full
scientific file reads and object rehashes in those callbacks. Integrity tests
temporarily alter bytes only inside their owned copy, confirm checksum refusal
before decode, restore every byte/attribute, and check original producer proof.
They retain all store tables unchanged. The boundaries test also runs two genuine
display jobs: an empty between-sample window and an invalid original cell. Parent
timing wrappers call unchanged functions; cleanup checks inspect released handles
and removed scratch. The separate source-pulse test cancels two normal-lease attempts through the real
API after native seals are acquired and before hydration, checks every released
native pointer, and preserves original science and objects. It creates no child
and makes no nested-process or hosted-actor claim; those have separate evidence.

The optional large generator creates a genuine 500,100-sample saved source. Its
recovery test first exercises the actual 500,000-sample display limit, then submits
a new exact 10-to-20-second window and checks full original evidence conservation.
The source may contain saved numerical-noise candidates; the test does not revise
or scientifically endorse them. See [integration reproduction](EDA-REPORT-INTEGRATION-REPRODUCE.md).

Display worker, boundary and large recovery tests claim the normal 60-second
lease. Parent callbacks renew only current attempts through source preparation,
child execution and publication. They retain normal expiry/cancellation fences.
Timing wrappers pass the same callback through unchanged implementation functions.

This small public corpus does not reproduce every external acceptance fixture.
Acquisition lineage, cvxEDA, current-reader
revocation, connected browser flows and child cancellation have separate scoped
receipts. Portable checks are not physical-device, construct-validity, hosted
identity-provider, or capacity qualification. The export operation reads saved
results and builds displays; it does not rerun scientific scoring.
