# Native recording header inspection

Brohn inspects a pinned original recording before the researcher confirms which
channels to analyse. This produces a `header_inspection` catalog entity, not a
scientific report. The UI shows source channel names, native rates, unit and
calibration declarations, recorded duration, and a bounded annotation preview.
Applying those values to the mapping form requires an explicit confirmation.

## Formats and evidence

| Format | Reader and scope | Important distinctions |
| --- | --- | --- |
| EDF / BDF | Brohn parses fixed technical headers and bounded annotation payloads | Per-channel native rates remain separate. Unknown units/ranges stay unknown. Patient/recording identity fields are excluded from the preview. |
| FIF | MNE 1.12.1 without signal preload | Names, channel types, FIFF unit/calibration codes, bad-channel flags and annotations. Referenced companion files are refused before the raw reader opens them. |
| SET | Bounded MATLAB v5/v7 expansion, then MNE | Standalone continuous SET only. External FDT references and v7.3 files need a separate explicit adapter. Embedded samples must be decoded with the structure but are never returned. |
| SNIRF | h5py structural/time checks, then MNE header reader | One NIRS group and one data block with explicit measurementList groups. External/soft links and virtual/external datasets are refused. Actual timestamps must be regular; no resampling is applied. |
| WAV | SoundFile/libsndfile metadata | Channel indexes, encoding, frame count and rate. Full-scale amplitude is distinct from sound pressure; channel indexes are not speaker identities. WAV cue/broadcast annotations are explicitly unavailable here. |

EDF permits different samples-per-record counts and physical calibration ranges
for individual signals. EDF+D records may be discontinuous, so summed record
duration is distinguished from elapsed time. MNE upsamples selected mixed-rate
EDF channels; Brohn's header confirmation therefore rejects a mixed-rate channel
selection rather than silently triggering that conversion.
[EDF specification](https://www.edfplus.info/specs/edf.html),
[EDF+ specification](https://www.edfplus.info/specs/edfplus.html),
[MNE EDF reader](https://mne.tools/stable/generated/mne.io.read_raw_edf.html).

SNIRF's `dataUnit` is optional. Missing units remain undeclared, and intensity
metadata is not treated as a calibrated haemoglobin measurement. SNIRF supports
both explicit sample timestamps and a start/spacing pair; these are inspected
before invoking the current single-recording reader.
[SNIRF specification](https://github.com/fNIRS/snirf/blob/master/snirf_specification.md).

## Worker contract

Run `python scripts/workers/headers.py --request request.json --output result.json`.
The request is exactly:

```json
{
  "schema": "brohn-header-request/1.0",
  "operation": "inspect_header",
  "format": "edf",
  "source_path": "ABSOLUTE_IMMUTABLE_SOURCE_PATH",
  "source_hash": "SHA256_HEX"
}
```

The result uses `brohn-header-result/1.0` and status `inspected`,
`needs_attention`, or `error`. Successful results contain `source`, `engine`
(including worker SHA-256 and reader versions), `header`, `parameters`, and
`limitations`. `header` contains `channels`, `channel_count`, `recording`,
`annotations`, `quality`, and `warnings`. Channel source units and analysis units
are separate fields; conventions are recorded in `calibration_evidence`.
Unavailable values are JSON null. No participant identifier is derived from a
filename or from the recording header.

Inspection bounds: 512 MiB source, 512 channels, 100,000 annotations with a
100-entry preview, and a 2 MiB result. EDF/BDF annotation bytes are bounded to
16 MiB. SET expanded containers are bounded to 64 MiB. SNIRF is limited to
10,000 HDF5 metadata nodes, 2 million sample timestamps and 20 million values
per dataset shape. Exceeding a bound produces an explicit error rather than a
partial or silently truncated header. Full original files always remain in the
immutable object store.

Use `methods-venv` for EDF/BDF/FIF/SET, `acquisition-venv` for SNIRF, and
`vision-audio-venv` for WAV. No new packages were installed for this adapter.

## R and UI contract

`brohn_queue_header_inspection()` creates an `inspect_header` job before
scientific mapping is accepted. `brohn_header_input()` pins dataset revision,
body hash and source hash. `brohn_analyse_header()` invokes the isolated Python
worker. `brohn_publish_header_inspection()` checks the job publication fence and
saves the metadata entity and downloadable immutable JSON. Cancelled attempts,
substituted dataset bodies and stale attempt tokens cannot publish.

`brohn_header_for_dataset()` retrieves a source-matching inspection, including
when later metadata edits retain the same source bytes.
`brohn_header_mapping_defaults()` derives candidate values only from explicitly
selected names. `brohn_parse_native_channel_input()` accepts ordinary comma
lists and JSON arrays so literal commas within names can roundtrip exactly.

The header UI queues work asynchronously, preserves the current mapping form,
and exposes progress, channel/annotation evidence and safe downloads. The
researcher chooses channels and clicks **Confirm channels and units** before
their names, rate and native-unit policy are copied. Collection notes and final
analysis confirmation remain part of the existing mapping flow. A source/header
identity guard prevents an old view from populating another recording.

## Checks completed

Original fixtures cover EDF and BDF mixed rates, discontinuous record timing,
missing calibration units, bounded event annotations, truncated records,
incorrect hashes, FIF types/bad channels/annotations, unsafe file references,
compressed standalone SET and external FDT rejection, SNIRF measurement metadata
and irregular timestamps/external links, and stereo floating-point WAV metadata.
Nine Python tests pass across the three prepared environments.

The shared `physiology.native_eeg()` reader also enforces the calibration gate,
including for neural ERP/time-frequency/frequency-tagging requests. Manual
mapping cannot bypass declared EDF/BDF voltage units and valid physical/digital
ranges, or FIF voltage/calibration metadata. Discontinuous or inconsistent EDF
record timing requires a segmented route. Selected EDF channels are loaded
explicitly so unrelated faster channels cannot silently upsample them. Six
additional tests in `tests/workers/native-calibration.py` cover these boundaries
and independent digital-to-physical-to-voltage arithmetic. Negative amplifier
gain is retained: EDF permits reversed physical endpoints but requires distinct
physical values and ordered digital endpoints.
[EDF+ calibration rules](https://www.edfplus.info/specs/edfplus.html).

`tests/platform-headers.R` passes 29 assertions through the actual R supervisor,
Python process, immutable catalog publication, stale/cancelled fences, Shiny
confirmation commands and immutable download handlers. These are format and
workflow checks using generated fixtures; they do not qualify physical devices,
calibration, or every file exported by a vendor.
