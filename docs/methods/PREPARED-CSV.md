# Canonical prepared gaze import

This format has an R/CLI path and a bounded local Shiny import flow. It is not a
device-export importer. The researcher must supply already prepared,
eligible intervals on one exposure timeline per participant/stimulus. The
importer cannot establish calibration, correct clock alignment or source origin.

From the repository root with dependencies installed:

```sh
Rscript scripts/analyse-prepared.R study.json gaze.csv new-report.json
Rscript examples/reproduce-import.R new-report.json
```

Use a valid exported study bundle with both PNG images and at least one AOI.
The output folder must exist; the CLI refuses to overwrite an existing report.
Reproduction uses the embedded original CSV, not the saved result tables.

## Required format

```csv
participant_id,stimulus_id,start_ms,end_ms,x,y,valid,phase
001,stimulus-a,0,200,0.5,0.47,true,passive_viewing
001,stimulus-a,200,1000,0.8,0.8,true,passive_viewing
001,stimulus-b,0,400,0.5,0.47,true,passive_viewing
001,stimulus-b,400,1000,0.8,0.8,true,passive_viewing
```

These illustrative rows are fictional. Coordinates must refer to the actual
study images; filenames alone do not map a vendor's coordinates or clocks.

- UTF-8 without a BOM; comma separated, LF or CRLF records. Complete final rows
  need no terminal newline. Quoted commas, doubled quotes and quoted newlines
  are supported. Malformed quoting, ragged rows and empty data are rejected.
- Exact eight header names, each once; header order may vary. ID text, including
  leading zeros, is preserved without trimming. Unknown stimulus IDs are rejected.
- Numeric columns use finite decimal notation. No scientific notation, Inf,
  NaN or literal NA. Only x/y may be blank. `valid` is exactly `true` or `false`.
- start_ms/end_ms are milliseconds; x/y are normalized top-left image coordinates.
  No unit guessing, duration inference, coordinate conversion or interpolation.
- See PREPARED-GAZE.md for phase, validity, interval-overlap and pairing rules.
  Repeated exposures require a later schema; do not merge them into this format.

The R reader defaults to 5 MiB and 100,000 data rows. Callers can lower limits.
These are source limits, not peak-memory or throughput guarantees. Parsing uses
token offsets before the full field/row check; a 5 MiB pathological comma fixture
was rejected but temporarily reached about 121 MiB of R vector memory. A local
10,000-row/20-participant fixture took 0.82–1.24 seconds including the kernel.
This is a sanity measurement, not a production performance qualification. The
local single-user UI uses lower limits: 1 MiB, 20,000 intervals, 500 participants
and 40 areas. The same limits apply when reopening local reports, before kernel
calculation. Tables and exclusion lists preview 100 rows; exports retain all.
Resource-isolated jobs remain required before shared/multi-user upload.

## Portable report and origin

`prepared-gaze-report/0.1.0` stores a frozen study, original CSV bytes in base64,
SHA-256, byte/row counts, prepared intervals, draft calculation and limitations.
It is labelled `imported_prepared` and `unqualified`; import does not verify that
data are real, recorded live, scientifically valid or consistent with the planned
presentation duration/order. Absolute input paths are excluded.

Export rechecks the original CSV hash/counts and recalculates derived tables from
those bytes. Changing cached output tables cannot change the exported answer.
The external CSV is never edited. Report saves use a cooperating-writer lock and
same-directory temporary replacement, with the same durability limits as drafts.
In the local UI, open Collect in a preview draft. A sample offers Create a working
copy first, preserving images/areas while changing study identity and origin.
CSV selection validates, calculates, saves and opens Results automatically.
Reports are kept beside the draft in <draft.json>.analyses, with revision-prefixed
filenames. Reopening loads and recomputes the latest report for the exact study
snapshot. A changed revision clears the current result and retains older reports.
An invalid latest report is reported rather than replaced with an older result.
There is no historical-analysis browser, shared workspace or background job queue.
