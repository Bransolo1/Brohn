# Complete processed physiology artifacts

`scripts/workers/physiology_artifacts.py` preserves complete processed tables separately from the bounded report/chart previews. Its two artifact kinds are `physiology-series` and `physiology-events`; the format is typed NDJSON, `brohn-physiology-tables/1.0`, with media type `application/x-ndjson`.

The source recording already has an immutable object hash. New ECG/PPG artifacts retain complete unit-converted input samples alongside the cleaned waveform for artifact review; these are preprocessing input values, not original file bytes or acquisition-filter-free measurements. Other adapters continue to omit full raw arrays. The original source remains authoritative. Historical cardiac artifacts remain unchanged and need a new analysis to gain this input column. Original row/sample indices, clock origin strings, coordinate references, units, method settings, source header/calibration evidence and source identities are retained.

## Current adapters

An optional `artifact_directory` in a `brohn-worker-request/1.0` request enables preservation. The parent creates an existing private `scratch/artifacts` directory for the current attempt. Without this option, the old bounded-JSON interface is unchanged; earlier preview-only reports require a new analysis to create full processed artifacts.

| Worker family | Full preserved data |
| --- | --- |
| Standard EDA | Clean, tonic and phasic samples with retention flags; all detected SCR morphology candidates. |
| Event-related EDA | Continuous clean/tonic/phasic samples with source indices and retention flags; all SCR candidates with onset/recovery support. Measured stimulus/nuisance onset logs and event eligibility remain complete in the main result. |
| ECG / PPG | Input values before cleaning (after declared unit conversion), cleaned waveform, retention support, every detected peak and its preceding interval/plausibility. The input column and conversion are explicit in table support. |
| Respiration | Clean waveform, retention support, every complete detected cycle with timing/amplitude. |
| EMG | Clean waveform and RMS envelope, retention support, every configured threshold burst. |
| EEG Welch | All calculated PSD frequency bins and densities. Its time-domain arrays contain only raw voltage, so no duplicate full time-domain artifact is created. |
| Audio | Every computed spectral frame and every Praat pitch frame, with their distinct measured frame-centre coordinates. Unvoiced pitch remains null. |
| fNIRS | All calculated optical-density and haemoglobin samples, original source indices, explicit source-channel pairing, geometry and pathlength settings. |

The neural epoch/Morlet/frequency-tagging worker already retains complete bounded typed arrays in its report. It is not routed through this adapter and does not gain an implied unbounded export. No artifact changes the underlying measurement or supplies additional scientific qualification.

## Typed stream

Every file has this ordered record sequence:

1. One `header`: schema, artifact kind, frozen provenance and its SHA-256.
2. A `table`: stable table ID, source identity, typed columns, coordinate declaration, source/retention/method support and exact expected row count.
3. Consecutive `rows` chunks: table ID, zero-based row offset and ordered row arrays. Chunks contain at most 4,096 rows; the default writer uses 512.
4. A `table_end` matching the exact observed/expected row count. Steps 2–4 may repeat for independent segments/channels.
5. A final `complete` receipt matching table count, total row count and provenance hash.

Example table column declaration:

```json
{
  "name": "tonic_us",
  "type": "float64",
  "unit": "uS",
  "nullable": false,
  "role": "processed_measure"
}
```

Supported scalar types are `float64`, exact bounded `integer`, `boolean` and `string`; nullability is explicit per column. Numeric fields require units, including `dimensionless`, `proportion` or `sample_index` where relevant. True/false cannot silently become 1/0. Nonfinite numbers are rejected; callers must explicitly represent unavailable evidence as null in a nullable column. Large exact clock origins use decimal strings rather than floating-point absolute timestamps.

Each table declares `axis: time | frequency | event`, a readable reference, the original clock origin string and original clock unit. Sampling coordinates are never inferred from row order, resampled or joined across source gaps. Source row ranges and the exact numerical recipe are stored at table level. Event/channel/person/session identities remain distinct; table counts are not participant counts.

The header's provenance binds the immutable source SHA, operation, origin, implementation/engine identity and frozen requested settings/source mapping/source header evidence. Effective settings and continuous support are also retained in each table. This permits a complete standalone artifact to remain interpretable alongside the source object and report, without embedding temporary filesystem paths.

## Writer and failure contract

`TableWriter(directory, kind, provenance)` accepts streaming rows with `write_table(...)` or aligned arrays with `write_arrays(...)`. Callers must declare all columns and the exact row count. `ArtifactSet` coordinates the two streams; `write_physiology_bundle(...)` and `write_eda_event_segment(...)` implement the registered worker adapters before any preview selection.

Each stream is written to an owned temporary file, flushed and fsynced, then renamed to a content-hash filename only after the complete receipt is written. The job receives successful manifests only after both streams finish. A failed second stream can leave an unreferenced first file in that attempt's scratch directory; it cannot produce a successful partial artifact manifest. The owning attempt cleanup handles those bytes. This is atomic per file and receipt publication, not a cross-filesystem transaction or power-loss durability qualification.

Scientific segment failures occur before table writing: the main report records the unavailable segment and prior successful segments remain in the complete artifact streams. A schema/count/disk integrity failure during writing fails the entire job explicitly; it does not silently publish truncated scientific data. A complete zero-row event table distinguishes a successful detector with no candidates from an omitted or incomplete output. When no processed table exists, no spurious artifact is published.

Bounds are explicit: 2 GiB per stream, 20 million rows, 10,000 tables, 128 columns, 2 MiB per JSON record, 4,096 rows per chunk and depth 24 for metadata. Exceeding a bound fails rather than truncates. The optional writer diagnostic preview contains at most 2,000 first rows and is labelled as diagnostic. Existing workers retain their separately labelled uniformly sampled report previews; neither preview is used to calculate scientific features.

## Verification and fenced publication

The scientific child calls the verifier after the worker completes and **before** the parent enters the catalog publication transaction:

```text
python scripts/workers/physiology_artifacts.py
  --verify-manifest <manifest.json>
  --directory <attempt/artifacts>
  --output <new-receipt.json>
```

The manifest is a plain JSON array of one or two worker manifests, bounded to 1 MiB. Each manifest contains `kind`, `path`, `sha256`, `bytes`, `schema`, `tables`, `rows`, `provenance_sha256`, `complete`, `media_type` and diagnostic preview metadata. The verifier requires the declared directory, full size/SHA match, typed headers and rows, consecutive offsets, exact counts and final completion. It rechecks the hash after streaming to detect replacement during verification. It rejects duplicate JSON fields, invalid values, missing completion and trailing records. The verifier receipt uses a new output path; no existing file may be replaced.

Successful compact receipt:

```json
{
  "schema": "brohn-physiology-artifact-receipt/1.0",
  "status": "verified",
  "artifacts": [
    {
      "kind": "physiology-series",
      "sha256": "<sha256>",
      "bytes": 12345,
      "schema": "brohn-physiology-tables/1.0",
      "tables": 2,
      "rows": 3000,
      "provenance_sha256": "<sha256>",
      "verified": true
    }
  ]
}
```

The parent independently checks attempt-directory containment, current bytes/SHA, metadata agreement with this receipt and the worker's current lease/fencing token. Only then are files promoted to immutable object storage with the report. Temporary `path` becomes the object's `hash`/`size` reference; schema, counts, provenance and completion metadata remain attached. A verification receipt cannot replace the parent's publication fence or byte checks. Heavy Python stream validation therefore does not hold the SQLite write transaction.

`verify_artifact(manifest, directory, on_table, on_rows)` also supports bounded streaming inspection in Python. Callbacks start after the size/hash check, but their output remains provisional until the function returns successfully because a later structural failure can still invalidate the stream.

## Verification evidence

`tests/workers/physiology_artifacts.py` has 26 distinct checks: 24 execute in the methods environment, with actual audio and actual fNIRS tests run separately in their prepared profiles. Independent fixtures preserve 12,001 processed samples and 7,001 events beyond preview limits; verify complete arithmetic, typed booleans/nulls, exact clock strings, stream-only generators, identity separation, limits, corruption, changed bytes during reading, invalid offsets/types/counts, interruption/fsync failures and CLI receipt protection.

Actual worker tests cover all six standard numeric physiology families, event-related EDA, audio and fNIRS. EDA arrays compare exactly with the complete computed arrays; a failed short EMG segment leaves the prior 5,000-sample segment intact. The fNIRS full artifact independently matches optical-density arithmetic and retains geometry/source indices. Tests do not assert that retaining or hashing outputs establishes sensor calibration, artifact-free recordings or psychological construct validity.
