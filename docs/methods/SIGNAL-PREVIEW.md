# Verified processed-signal catalog and preview

`scripts/workers/signal_preview.py` reads a complete [typed physiology artifact](PROCESSED-PHYSIOLOGY-ARTIFACTS.md) and returns a bounded catalog or extrema-preserving plot dataset. It does not reread raw device data, change a physiology recipe or compute a new scientific score.

`tests/workers/signal_preview.py`: 24 passing tests, including independent count/extrema fixtures and an actual complete EDA artifact.

## Connected researcher workflow

Reports with complete processed physiology artifacts expose **Explore signal traces
and spectra** and, where available, **Explore detected events**. A queued catalog
reads the saved artifact and presents actual recording/channel/table identities.
The researcher chooses a measure and either the full range or explicit inclusive
start/end coordinates. **Show signal** queues a separate view; its source report
and scientific calculations remain unchanged.

The accessible SVG shows separate support fragments with labelled time, frequency
or event coordinates and measurement units. Numerical support includes full and
selected counts, missing values/coordinates, exclusions and exact eligible extrema.
Clock origin remains its original string. The complete output, saved view/provenance
JSON and SVG chart are separately downloadable. Empty selections remain empty.
Narrow displays use a keyboard-focusable chart scrolling region.

`R/platform-signal.R` publishes each catalog/preview as an immutable `signal_view`
entity under the same lease fence as its job. It pins the report revision/hash,
artifact hash and typed receipt, selection, worker identities and full source
metadata. A view is not a new scientific report. `R/platform-signal-views.R` checks
report/table form identities before accepting commands from changing Shiny inputs.

`tests/platform-signal.R` passes 32 R checks with real supervised Python jobs,
source/extrema/count oracles, gap-aware SVG, inclusive/empty ranges, stale/cancelled
publication, original report preservation, Shiny controls/downloads and workspace
reopen. Actual browser signal-explorer acceptance is tracked separately in the
researcher QA record; these checks alone do not establish browser usability.

## Worker request

Use `--request <json> --output <new-json>`. Request JSON is bounded to 2 MiB, output to 16 MiB. Duplicate/nonfinite JSON fields are rejected. The output path must be new; source artifacts, input requests and existing files cannot be overwritten.

```json
{
  "schema": "brohn-signal-preview-request/1.0",
  "operation": "signal_preview",
  "artifact": {
    "kind": "physiology-series",
    "path": "<private immutable object path>",
    "sha256": "<object hash>",
    "bytes": 12345,
    "schema": "brohn-physiology-tables/1.0",
    "tables": 2,
    "rows": 3000,
    "provenance_sha256": "<provenance hash>",
    "complete": true
  },
  "verification_receipt": {
    "schema": "brohn-physiology-artifact-receipt/1.0",
    "status": "verified",
    "artifacts": ["<exact original artifact verification receipt entry>"]
  },
  "selection": {
    "table_ids": ["eda-segment-1-samples"],
    "recording_id": "recording-1",
    "channel": "eda1",
    "value_column": "phasic_us",
    "range": [18, 27]
  },
  "parameters": {"max_bins": 800}
}
```

The receipt placeholder above represents the actual object returned by the artifact verifier, not a string. Bind `sha256/bytes` to the saved object's `hash/size` when building the internal request. The parent is responsible for study/project access and resolving a verified immutable object path. Temporary/local paths never appear in the output.

The worker compares kind, hash, size, schema, table/row counts and provenance hash with the original typed verification receipt. It independently verifies the **complete file**, including SHA, typed chunks, sequence offsets and completion counts. Preview generation uses two verified streaming passes: one for exact support/ranges, one for envelope bins. A tampered or missing source/receipt blocks the view; the worker never swaps in another table or latest report.

## Discover actual tables first

Set `operation: "signal_catalog"` and omit selection/parameters. Alternatively, an explicit `selection: null` requests the catalog. Optional `page: {offset: 0, limit: 100}` permits offsets 0–10,000 and pages of 1–200 tables.

The `brohn-signal-catalog/1.0` result includes:

- Actual table IDs, recording/channel/person/session identities, declared coordinates and exact original clock-origin strings.
- A numeric coordinate column and numeric measure columns with explicit types/units/nullability/roles.
- Expected rows, counted observed coordinate rows and actual coordinate range for each returned table.
- Source/support metadata, with large repeated method parameter blocks omitted from the catalog.
- `pagination.offset`, `limit`, `returned`, `total_tables` and `next_offset`. The catalog never shows the first page as though it were the entire artifact.

The full artifact is verified even when one catalog page is requested. Catalog descriptors come from typed tables and observed coordinates; channel names, units and ranges are not guessed from raw files or labels.

## Select a faithful view

A preview selects 1–50 exact table IDs, one recording ID, one channel, one numeric measurement column and either an inclusive coordinate range or explicit `range: null` for the full observed range. Unit/axis/clock-reference differences and different person/session/reset identities require separate views. Tables remain separate support fragments even when their metadata agrees.

`max_bins` is 1–2,000, at least the selected table count. The total bin budget is divided across selected tables. A support break may split a nominal bin into several disconnected envelope records; it never reconnects the fragments merely to meet a plot budget. More than 2,000 support fragments or 10,000 envelope records fails explicitly with a request to narrow the range.

Each envelope retains its first, last, minimum and maximum **observed** point. Duplicate points are removed by original row index, and the remaining points are emitted in source order. Every point retains x, y, original table row index, optional original source sample index and retention support. The envelope also records its source count, table ID, fragment ID and bin index. These are extrema/count summaries, not interpolated/resampled scientific data.

The `brohn-signal-preview/1.0` result contains:

- `axis`: explicit time/frequency/event kind, coordinate unit, value unit/name, original clock origin/unit and coordinate reference.
- `full_range` and `selected_range`: exact row counts, observed coordinate/value counts, eligible counts, excluded-retention counts, missing-value/coordinate counts, observed coordinate range, observed value range and eligible value range.
- Per-table complete counts/ranges/support, `effective_range`, envelope records and support fragments.
- Quality counts showing that the envelopes account for every selected eligible row, plus emitted bin/point/fragment counts.

Observed value ranges include finite values in excluded edge/support rows. Eligible ranges include only rows with finite coordinates, finite values and retained support. These denominators remain separate. Missing values are null, not zero. Missing coordinates cannot be assigned to a numeric subrange; they remain visible in the full-source missing-coordinate count. An outside/unsupported selection returns `status: "empty_range"` with counts and no invented points.

## Gaps, axes and clock evidence

Missing values, missing coordinates and non-retained samples break a trace. Nonconsecutive original source sample indices break support. When the artifact declares sampling cadence, deviations beyond its recorded timestamp tolerance and floating-point roundoff also disconnect the trace. Every table/reset boundary stays disconnected. Decreasing/duplicate coordinates within one table are rejected as ambiguous resets, rather than sorted into a fictitious continuous series.

Time cadence comes only from explicit source sampling rate or explicit audio frame hop/rate. If cadence is unavailable, time data are returned as points with no connecting trace. Event-axis data are scatter points. Frequency-axis data remain spectra in Hz with their declared value density unit; they cannot be relabelled as time traces. No automatic nearest-time join or clock alignment occurs.

Render only within each fragment's `connection_policy`; never draw a line between fragment IDs. The exact original clock origin remains a string. Plot x values are the artifact's recorded relative float64 coordinates; the view cannot recover precision already absent from an upstream artifact and does not convert large absolute clocks to new doubles.

## Evidence

Independent fixtures check hand-computed first/min/max/last order, a 10,001-sample signal with narrow +100 and -60 spikes that ordinary sparse sampling would miss, inclusive range counts, null and excluded values, discontinuities inside one bin, source-index and cadence gaps, separate table/reset/person identities, spectrum/scatter semantics, missing cadence, one-point ranges and exact large clock-origin strings. Pagination is tested across five tables with explicit continuation.

An actual event-related EDA artifact contains 3,000 processed samples and 2,500 retained rows at 25 Hz with ten-second edge exclusions. A selected 18–27 second window contains exactly 226 eligible measured rows; an eight-bin view preserves the exact minimum and maximum of the independently obtained complete phasic array. Receipt/hash tampering, wrong table/measure selection, unsupported settings, incompatible axes and CLI overwrite/error cases are rejected.

This is a faithful visual-access layer over previously computed data. It does not establish device accuracy, validate emotional interpretations or replace full-artifact exports for subsequent numerical analysis.
