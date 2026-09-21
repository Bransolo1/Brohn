# Exact processed values and complete selected-measure export

20 September 2026. Approved bounded implementation contract; acceptance is
pending. This read-only route supplements the existing processed-signal plot.
It does not recalculate a scientific measure or consume plot-envelope points.

The source is one exact complete `physiology-series` or `physiology-events`
artifact, its original verification receipt, an immutable catalog, and one
catalog table/numeric measurement. Report revision/body, artifact bytes/hash,
catalog revision/body, table identity, coordinate/reference/origin, unit and
current project authority are pinned. Native source guards hold original
objects through the child worker and atomic publication. Revocation or changed
source clears UI data and blocks subsequent actions/downloads.

Selections contain table ID, recording/channel, numeric measure and an inclusive
finite range or explicit complete range. **Every selected source row remains
present**, including null measurements and `retained=false`; the plot's eligible
point policy is not an export filter. Complete range also includes null
coordinates. A numeric range cannot locate those rows, so their full-source
count and exclusion from range selection remain explicit. No sorting, joining,
interpolation, resampling or reclassification occurs. Original row indices and
all native row fields/types remain available alongside the selected value.

Two supervised operations, `signal_values_page` and `signal_values_export`,
stream and verify the complete artifact independently of its preview. Pages
request 25, 50 or 100 rows with an absolute selected-row offset. Byte bounds
may return fewer rows, with exact total, returned range and continuation; no
truncation is hidden. Previous navigation needs no growing cursor history.
An out-of-range page is empty, with the exact selection total still shown.

Export writes every selected row to a new UTF-8 CSV in owned scratch, then
publishes its immutable bytes and a source-bound manifest together. Finite
binary64 values use round-trip decimal strings produced directly by the Python
artifact reader, including signed zero; R never reserializes the measurement
CSV. Null cells have explicit null/type fields. Exact typed original row JSON
preserves boolean false, empty strings and null separately. Human text columns
receive spreadsheet-formula protection; typed JSON and numeric cells retain
their native meaning. Units, original clock strings, source indices and
report/artifact/selection identifiers accompany exported rows. The manifest
retains complete table declarations, support and all row counts even when the
selected export contains zero rows. No source path is exported.

Request/read/page/export bounds fail explicitly and remove unfinished output;
an oversized export is never called complete. Existing coordinator cancellation,
retry, publication fencing and restart/reopen apply. The UI uses native labelled
controls, visible processing/error/empty states, paged numerical rows, exact row
detail and separately prepared complete CSV download. Changing a range or page
cannot silently change the scientific report or reset unrelated form state.

Owned new files: `scripts/workers/signal_values.py`,
`R/platform-signal-values.R`, `R/platform-signal-value-views.R`, focused worker,
R/Shiny and researcher-browser fixtures, and this scoped contract/acceptance.
Coordinator owns existing load/job/worker registration and signal-view hooks
after all active scientific jobs have closed.

Required evidence: independent binary64/signed-zero CSV round-trip; typed
false/null/empty text and hostile Unicode/formula labels; source-row and support
counts beyond preview limits; inclusive/empty/range-unplaceable coordinates;
exact time/event/frequency units and clock strings; every currently emitted
physiology/peripheral/audio/fNIRS table shape; wrong catalog/table/measure,
missing/tampered/mutating files and stale project/report authority; bounded page
continuation and full streaming export; atomic cancellation/failure/retry;
actual researcher page/detail/download/reopen plus keyboard/390-pixel scans.
Fixtures and per-family evidence must distinguish real worker-produced output
from schema-shaped test tables. No hardware or scientific qualification claim.
