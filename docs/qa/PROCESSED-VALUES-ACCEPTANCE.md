# Exact processed-value reader acceptance

24 September 2026. **Connected browser acceptance passed for the scoped Windows
fixtures below.** Read with [the source and export contract](PROCESSED-VALUES-CONTRACT.md).
This is output-reader/workflow evidence. It does not qualify a measurement
device, detector, physiological interpretation or scientific recipe.

## Implemented boundary

`signal_values_page` and `signal_values_export` read one complete original
`physiology-series` or `physiology-events` table and one declared numeric
measure. They preserve the selected inclusive coordinate range, table/recording/
channel, units, original clock strings and report/catalog/artifact identities.
All coordinate-selected rows remain present, including explicit null values,
false retention and unknown retention. A complete selection includes null
coordinates; a finite range explicitly counts the rows it cannot place.

The worker never reads a plotted envelope. Pages contain 25/50/100 rows,
with an 8 MiB encoded-row bound and explicit byte-limited continuation. Request
and result bounds are 4 MiB and 16 MiB. CSV is streamed, capped at 2 GiB with
explicit failure/partial-output cleanup, and published with its manifest in one
native-guarded transaction. Finite numbers are direct Python binary64 round-trip
decimals, including signed zero. Flat text is spreadsheet-protected; original
typed JSON preserves native text/false/empty/null. No private path is exported.

Current report/project/catalog authority and immutable source bytes are checked
before work and publication. The UI verifies source and result bytes in a
background process under native read guards, then streams a prepared CSV through
httpuv without a bulk R copy or numerical reserialization. Access loss clears
the page, row detail and active download. This publication profile is Windows;
there is no claim of a newly qualified POSIX guard.

## Executed evidence

- `tests/workers/signal_values.py`: **16 passing** exact-decimal, typed null/
  false/empty/Unicode, formula-text, inclusive/empty/missing-coordinate selection,
  page/byte bounds, wrong source/table/measure/clock, tamper, existing-file
  preservation and failed-export cleanup checks.
- `tests/platform-signal-values.R`: **27 passing** direct real worker + native
  publication + Shiny checks. Full 137-row export, original report/byte identity,
  cancellation fencing and retry, moved catalog/archived project refusal,
  streamed immutable download, stale-page rejection, authority-loss clearing
  and reopen. Retained run: `make/work/test-runs/brohn-values-qa-529410c1332a`.
  These exercise the adapters directly; they are not a substitute for the
  separately executed supervised-manager browser journey below.
- `tests/platform-signal-value-context.R`: **6 passing** focused final UI checks.
  A catalog for another report revision cannot open against the current report;
  matching context remains actionable, close clears verification, large source
  counts remain exact, source identifiers can wrap, and actions precede the table.
- Independent peer probe retained before and after fixes at
  `oka/work/signal-values-peer-mzwdodxu` and `signal-values-peer-oodbg92x`.
  It found and then confirmed corrected unknown-versus-false retention counts,
  rejection of a forged string/label `source_sample_index`, and conservative
  spreadsheet text escaping. Signed zero and adjacent binary64 values round-trip.
- The separate `tests/reference/fnirs_saved_review.R` receipt at
  `oka/work/brohn-fnirs-saved-01/acceptance.json` contains **18 checks and eight
  successful supervised jobs**, including two `signal_values_export` jobs over
  actual production fNIRS outputs. Both complete selected-table totals match;
  the original reports remain unchanged. The original software-phantom method
  and subsequent visual acceptance have their own scopes and receipts.

## Production output compatibility

`tests/workers/signal_values_profiles.py` compares **every exported numeric
coordinate/measure cell and original typed row** against the complete original
artifact, not its preview. Original row order, source index, retention, null
state, units and full totals also match. It exercises every numeric measurement
column in every retained fixture table, including empty declared event tables.
All CSVs, manifests and newly generated worker inputs/results are retained under
`oka/work/brohn-values-profiles-01`.

| Production output source | Table/measure exports | Source rows compared | Exact scope |
|---|---:|---:|---|
| Retained actual EDA, EEG, temperature and triaxial acceleration jobs | 159 | 9,329 | Original synthetic fixture recordings already processed by production workers; full support/group tables, spectra and empty event tables. Source inventory: `oka/work/retained-processed-artifact-inventory.json`. |
| Recorded ECG and PPG reports | 7 | 505,242 | Existing MIT-BIH 108 / CapnoBase 0123 saved artifacts from `brohn-cardiac-input-02`; no scientific analysis rerun. Full saved input/cleaned/event/spectral columns actually present in those reports. |
| Newly executed respiration production worker | 7 | 6,048 | Original sinusoidal displacement with explicit inspiration polarity; complete cleaned series and cycle event columns. |
| Newly executed EMG production worker | 5 | 10,003 | Original 80 Hz voltage plus explicit 0.2 µV RMS burst threshold; cleaned/RMS rows and a nonempty threshold-burst record. |
| Newly executed audio production worker | 3 | 8,993 | Original 30-second 200 Hz tone through the prepared Praat/audio profile; all spectral/RMS and pitch frames. |
| Newly executed fNIRS production worker | 4 | 12,000 | Original two-wavelength synthetic SNIRF through the prepared acquisition profile; both complete optical-density/haemoglobin-change channel tables. |
| **Total** | **185** | **551,615** | Reader compatibility across ten enabled physiology families, not ten independent scientific validations. |

The separate 137-row browser/domain fixture is **schema-shaped software edge
data**, not physiology produced by a scientific worker. Its time/event/frequency
declarations deliberately include missing values, unknown retention, hostile
text, Unicode and signed zero. It must not be described as live or measured.

## Connected browser and visual evidence

`tests/researcher-signal-values.mjs` completed **22 assertions and five clean
accessibility/reflow scans**, using an isolated copy of the retained cardiac
workspace plus the explicitly artificial 137-row schema fixture. The actual
worker processed **14 new exact-value jobs**: seven successful pages, six
successful complete exports and one explicitly cancelled page request. Retry
preserved its exact inclusive range. This count excludes the copied historical
analysis/catalog jobs; no physiological analysis was rerun.

The journey covers typed null, signed zero, unknown/excluded retention, literal
Unicode/markup row detail, next/previous paging, cancellation/retry, inclusive
and empty ranges, absent coordinates, time/frequency/event units, immutable
download receipts and report reopening. The recorded ECG input export contains
**108,000 rows / 113,505,185 bytes**, beyond the plot preview. The original schema
fixture, ECG and PPG report body hashes remain unchanged; PPG was preserved in
the copied workspace and was not a separate browser selection in this journey.

An additional independent Python standard-library audit reads the original
native NDJSON and the six actual browser downloads directly, without invoking
the production artifact parser or exporter. **All 108,414 selected rows** match:
every coordinate and measure round-trips to the original binary64 (including
signed zero), every original typed row matches, and row indices, null/retention
state, units, table declarations, report binding and byte hashes agree. The
zero-row export is included in the six downloads and contributes no rows.

All five retained screenshots were visually inspected: desktop exact values;
390-pixel exact values, support/detail, frequency values and recorded ECG input.
Numeric strings remain horizontal, essential actions reflow, and the labelled
horizontal table can be scrolled with the keyboard. Automated scans report no
axe violations, document overflow or actions below the checked 44px target.
These checks do not replace participant or assistive-technology usability work.

Retained evidence (outside the source repository):

- `make/work/test-runs/brohn-signal-values-browser-resume-20260924-01/browser-1790214475079/results.json`
  — assertions, scans, source-code hashes, jobs and immutable report identities.
  SHA-256: `6250bc5bcb54f2d97566a9dd5a1d0c25ec4fe26938046ec1d7a2349b663d02e6`.
- The same directory contains the six CSV/schema pairs, screenshots and
  `independent-download-audit.json`; its reproducible audit script is retained
  in the parent test directory.
- Recorded ECG CSV SHA-256:
  `04a6caf3a6663e9703026f9bcb09e75a38912e18644ff5ef9bcd5b7f3b57c038`.

The September 20 `oka/work/brohn-signal-values-browser-01` through `-04` runs
remain retained failures. They exposed selector assumptions, keyboard timing,
reflow and stale-selection issues during development. The latest historical
run completed 18 assertions/five scans but timed out reopening Data library at
30 seconds. The resumed harness waits for the actual library control within
the existing 120-second readiness bound; reopening now passes without a
production-code change. This proves the completed route, not a production
latency target. The fixture accepts `BROHN_QA_PORT` for isolated runs; this run
used port 3881 and terminated its own services after inspection.
