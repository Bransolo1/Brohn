# Multistream recording interchange

BWP06 importer, implemented in `scripts/workers/interchange.py`. This accepts
recorded multistream evidence through the prepared acquisition environment. It
does not acquire from a physical device, infer synchronization accuracy, compute
psychological scores or register datasets in the R catalog itself.

Run with `../../work/tooling/acquisition-venv/Scripts/python.exe`; XDF uses pinned
**pyxdf 1.17.5**. No new package, model, device SDK or external recording was
downloaded. Engine and worker-code identities are returned in every result.

## Worker contract

```json
{
  "schema": "brohn-interchange-request/1.0",
  "operation": "import_multistream",
  "format": "xdf",
  "source_path": "C:/local/immutable-source.xdf",
  "source_hash": "<lowercase SHA-256>",
  "output_directory": "C:/local/job/artifacts",
  "metadata": {
    "origin": "imported",
    "origin_statement": "Describe where this recording came from.",
    "clock_policy": "preserve_only"
  }
}
```

CLI: `interchange.py --request request.json --output result.json`.
`format` is `xdf` or `brohn_stream_bundle`; the latter reads the explicit JSON
schema below. Source and output must be separate. Request keys are allowlisted,
source bytes are hashed before and after import, and duplicate JSON keys or
nonfinite JSON literals are rejected. There is no URL, plugin or script input.

Output schema is `brohn-interchange-result/1.0`, operation `import_multistream`.
Successful status is `imported` or `needs_mapping`; malformed/unsupported input
returns `error`, a structured message and exit code 2. Missing units, an
unclassified stream, missing XDF footer or conflicting origin produce
`needs_mapping`. Clock boundaries and missing values remain explicit evidence
even when import succeeds; success is not permission to analyse them blindly.

Each `streams[]` item has:

- `schema: brohn-imported-stream/1.0`, `id`, source name/type/kind, `source_id`,
  `uid`, source session metadata, channels, clock and nominal sample rate.
- Independent origin, declaration/basis and conflict status. Sample/synthetic
  source declarations remain sample even if a caller requests live. Conflicting
  declarations produce `mixed`; a missing origin uses the researcher's declaration
  and is explicitly marked unverified. Stream IDs/UIDs are not participant IDs.
- Full sample/value counts; segment/clock-offset counts with bounded previews;
  ordered sample preview; quality flags and secondary CSV schema.
- Three hashed artifacts: `stream_samples_jsonl`, `stream_samples_csv`, and
  `stream_evidence_jsonl`. Each has stream ID, kind, path, SHA-256 and byte count.

The result also contains a `container_evidence_json` artifact with the complete
file header, extension-chunk evidence, parser-warning record or bundle-level
declaration. Its `stream_id` is null. `artifacts[]` repeats all artifact handles
for publication. Full channel XML, stream headers/footers, recorded offsets,
chunk-to-sample ranges and all segments are in evidence artifacts; compact
manifests do not discard this metadata.

The R coordinator must promote every successful artifact into its immutable
object store under the job publication fence, verify path/size/hash, replace
scratch paths with object handles, and only then clean scratch. A failed import
must publish no child dataset: partially written/generated scratch artifacts
are not an accepted import. Do not register empty streams as nonempty datasets;
their zero-byte canonical JSONL and nonempty metadata/CSV header are valid
evidence of a stream that contributed no samples.

## Canonical samples and boundaries

JSONL is authoritative. Each line retains `sequence`, `stream_id`, `segment_id`,
`clock_id`, `timestamp_unit`, decimal-string `source_timestamp`, `timestamp_state`,
`timestamp_ieee754_le_hex` for explicitly encoded XDF timestamps, reconstruction
flag, decimal-string `time_since_segment_start_s`, explicit identity, typed
`values` and per-channel `value_states`.

Finite numeric values remain numbers except **int64 values are decimal strings**.
Boolean false, numeric zero and empty marker text remain distinct. Null is
missing; XDF NaN and positive/negative infinity become null plus their exact
nonfinite state. The complete original file remains the binary reference.
XDF timestamp bit patterns are retained even for nonfinite timestamps. Timestamp
strings preserve the source unit/representation; decimal arithmetic prevents
large-clock cancellation. No conversion is advertised as extra timing precision.

Rows are never sorted, deduplicated, interpolated or merged across streams.
Independent segments begin on explicit reset, changed identity/clock ID,
timestamp reversal, duplicate analogue timestamp, missing/unanchored timing,
or an interval above 1.5 declared nominal periods. Reversal is conservatively
labelled `timestamp_reversal`, since it may represent a reset or out-of-order
record. Marker ties remain distinct ordered events. Irregular streams have no
invented gap threshold. XDF packing Boundary chunks are not recording resets.
Segment metadata includes boundaries, first/last source sequences, identities,
span and descriptive row rate; there is no pooled rate across resets or people.

CSV is a secondary interchange view with timestamp strings, identity fields,
`value_<channel-id>` and `state_<channel-id>` columns. Read using its manifest
schema; automatic spreadsheet/type inference can lose int64 precision or
conflate empty text with missing values. No CSV value is modified for display.
Before downstream physiology analysis, explicitly map channels, units, identities,
phases and usable timing segments. Sample sequences are not independent people.

## XDF behaviour

Only uncompressed XDF version 1/1.0 with supported numeric/string channel
representations is accepted. The strict preflight checks chunk byte boundaries,
UTF-8/XML, channel/sample counts, footer counts, timestamp encodings and string
sizes before pyxdf allocates arrays. Invalid/truncated input fails; pyxdf's
fault-recovery logging cannot silently turn a damaged source into a complete
import. Duplicate stream IDs fail rather than overwriting an earlier header.
Separate streams sharing a source ID or name stay separate.

Clock synchronization, clock-reset correction and dejitter in pyxdf are disabled.
Explicit timestamps are compared with preflight originals. Omitted XDF
timestamps use pyxdf's nominal-rate decompression and are individually flagged.
An omitted timestamp before a finite explicit anchor is marked unanchored and
excluded from usable elapsed timing. Derived global `effective_srate` is ignored.

ClockOffset chunks retain collection time, offset, exact binary timestamp/offset
bits, chunk position and preceding sample count. They are **not applied**. Their
reference clock and uncertainty stay null when absent. A collection-time reversal
adds a conservative boundary at the next sample. No offset/drift fit or
cross-device alignment is implied. The XDF specification defines offset addition
and treats collection times as being in the source stream's clock domain;
interpolation/fitting is a separate explicit transform, not this importer's job.
[XDF specification](https://github.com/sccn/xdf/wiki/Specifications).

Channel labels/types/units come only from declared channel metadata. Nonstandard
global metadata remains in original XML and is not guessed into per-channel
units. Unknown types remain `unclassified`; an explicit Markers/Events stream
type identifies markers, and known modality names identify signals. Source
scale/offset metadata is preserved without applying a calibration.

## Brohn stream bundle 1.0

The complete file is one UTF-8 JSON object, with no referenced files or URLs:

```json
{
  "schema": "brohn-stream-bundle/1.0",
  "origin": "sample",
  "streams": [{
    "id": "eda",
    "name": "Original synthetic EDA",
    "type": "EDA",
    "kind": "signal",
    "source_id": "original-device-a",
    "uid": "original-stream-a",
    "clock": {
      "id": "device-a",
      "unit": "ns",
      "kind": "device",
      "representation": "decimal_string",
      "resolution": "1000"
    },
    "nominal_srate": 10,
    "identity": {"participant_id": "synthetic-p1", "session_id": "synthetic-s1"},
    "channels": [{
      "id": "conductance",
      "label": "EDA",
      "type": "EDA",
      "unit": "uS",
      "value_type": "float64"
    }],
    "clock_offsets": [{
      "collection_timestamp": "9007199254740993",
      "offset_s": "0.125",
      "reference_clock_id": "master",
      "uncertainty_s": "0.001"
    }],
    "samples": [
      {"timestamp": "9007199254740993", "values": [1.25]},
      {"timestamp": "9007199354740993", "values": [null]}
    ]
  }]
}
```

Top-level optional `description` is preserved. Stream name/type/source ID/UID
may explicitly be null. Optional stream `origin`, `identity`, `clock_offsets`
and `metadata` are retained. Bundle origin `mixed` permits distinct declared
stream origins; a stream cannot erase or silently upgrade a bundle's synthetic
origin. IDs must be unique safe identifiers; labels need not be IDs.

`kind` is `signal`, `markers` or `unclassified`. Channel types are `float64`,
`float32`, `int8`, `int16`, `int32`, `int64`, `string`, `boolean`. Channel label,
type and unit may explicitly be null. Optional scale/offset are decimal strings
and are never applied here. Float32 inputs must already be exactly representable;
the importer does not silently round them. Unsafe large integers require int64
decimal strings instead of a lossy float conversion.

Clock units are `s`, `ms`, `us`, `ns` or `ticks`; ticks additionally require a
positive decimal-string `seconds_per_tick`. Clock kind is `monotonic`, `unix`,
`device` or `unspecified_epoch`. Optional resolution is a positive decimal string
in source units, not an inferred accuracy claim. Every sample timestamp is a
decimal string or explicit null; values have exactly one entry per channel.
Optional sample `identity` replaces the stream identity for that row, `clock_id`
declares a new clock identity, and `reset: true` declares a boundary. There is no
carry-forward of an earlier sample's participant identity. Identity keys are
participant/session/condition/exposure IDs only.

## Bounds and evidence

- Source: 512 MiB; JSON bundle: 64 MiB; 64 streams; 256 channels per stream;
  2 million total rows and 20 million total values.
- XDF: 100,000 chunks, 1 MiB per XML record, 32 KiB per text value, no DTD/entities.
- Full generated artifacts: 4 GiB; compact result: 8 MiB; 100,000 segments per
  stream. Bounds fail explicitly rather than truncating full samples.
- Previews: at most 20 samples per stream and 1 MiB total; at most 20 segment,
  offset or extension descriptors in their previews. Full evidence stays in the
  immutable artifacts, with original total counts reported.

Run `acquisition-venv/Scripts/python.exe tests/workers/interchange.py` from the
repository root using the prepared relative environment path above.
Eight passing test families cover original interleaved numeric/marker/int64 XDF,
raw/omitted/irregular/reversed timestamps, correction observations and reset
boundaries, source UIDs and unknown units, NaN/Inf preservation, missing footer,
truncation/corrupt lengths/unsafe advertised allocation/reused IDs, exact bundle
nanosecond clocks above 2^53, null/false/zero types, participant changes, gaps,
unapplied scale, origin conflicts, complete data beyond preview limits, artifact
hashes, CLI failures and source-overwrite protection.

These are format, precision and preservation tests. LabRecorder/vendor recording
fixtures, throughput limits and physical-device clock qualification remain
separate evidence. The R catalog/review adapter is a subsequent integration step.
