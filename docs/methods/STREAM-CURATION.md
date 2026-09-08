# Preserved streams to declared analogue analysis

This route connects a preserved XDF/Brohn stream bundle, including a curated
local acquisition source, to actual channel analysis. The researcher selects one
declared analogue stream and scalar numeric channels, reviews units, sample rate
and identity, and prepares **one** derived CSV dataset. The original recording,
canonical typed JSONL, clock/metadata evidence and original CSV remain immutable.

The route supports EEG, EDA, ECG, PPG, respiration and EMG input preparation.
Marker, boolean, text, unclassified, irregular-rate and uncalibrated-count inputs
are not silently relabelled as physiological measurements. Curation itself is a
data preparation operation; its counters are not scientific scores.

## Researcher flow and automation

The preserved stream card offers **Curate channels for analysis**. The dialog
shows exact channel identities, source units, nominal rate and source identity
preview. It requires a source/identity review, unit rationale, unit confirmation
and explicit agreement to preserve gaps/reset boundaries and omit rows missing
any selected channel without interpolation.

Existing participant/session codes are retained. Optional declared codes fill
only missing source identities. They never replace an existing person's code.
Condition/exposure identities are not inferred from file names, marker proximity
or clock segments. Source-declared condition/exposure values remain preserved;
the mapping selects them only if every included row has that source identity.

**Run standard channel analysis after preparation** defaults to checked. Before
confirmation, the dialog shows the actual standard recipe and complete numerical
parameters. The recipe describes channels/recordings; it does not assume a
condition effect or experimental baseline. Successful preparation publishes an
accepted dataset and queues its scientific job in the same fenced transaction.
The frozen dataset and curation manifest keep those parameters and the analysis
job identity. There is no additional compulsory Data/Open/Analyse step.

Unchecking automatic analysis prepares the dataset for separately configured
supported analysis. Known unsupported standard sample rates require that manual
choice. No usable segments produce a `needs_attention` curation record with full
decisions, no empty scientific dataset and no analysis job. Method-specific
short segments, bad amplitudes and other exclusions remain the scientific
worker's responsibility and stay visible in its saved result.

The standard EEG path uses acquisition-reference channel Welch spectra;
standard EDA uses the registered tonic/phasic/SCR recipe. ECG's displayed default
uses a 50 Hz mains setting, detected intervals and explicit interval screening;
the acquisition environment must support that setting. PPG variability stays
separate from ECG HRV. Respiration's displayed default assumes positive
excursions toward inspiration. EMG does not invent an MVC or burst threshold.
An unsupported research interpretation is never supplied because a numerical
channel analysis succeeded.

## Immutable worker contract

`extract_stream` is the supervised operation; the recipe is
`analogue-stream-curation/1.0`. Queue input pins:

- Source stream entity ID, revision and body hash.
- Parent stream-import ID, revision and body hash.
- Raw dataset ID, revision/body hash and original source hash.
- Complete canonical stream JSONL hash and every original stream artifact.
- The explicit reviewed selection, including `run_analysis`.

The worker uses only the standard library but runs in Brohn's methods Python
environment, which the enabled downstream analyses also require. Its CLI is:

```text
python scripts/workers/stream_extract.py --request request.json --output result.json
```

Request schema `brohn-stream-extract-request/1.0` contains `operation`, the trusted
canonical `source_path` and `source_hash`, preserved `stream` manifest,
`selection`, and the attempt's `output_directory`. Selection schema
`brohn-stream-selection/1.0` contains `channel_ids`, `modality`, reviewed `unit`,
exact source `sampling_rate`, nullable missing-identity `participant_id` and
`session_id`, `origin_statement`, `unit_rationale`, `confirm_source_units`,
`confirm_boundaries`, and boolean `run_analysis`.

Result schema `brohn-stream-extract-result/1.0` contains exact source identity,
selection, settings, complete support counts, all derived segment records,
bounded preview/columns/mapping and two complete artifacts: `curated_signal_csv`
and `curation_decisions_jsonl`. R publishes the complete curation manifest as
another immutable JSON object, replaces scratch paths with object hashes and
retains source-code identities. Publication renews the job fence and validates
size/hash/source-row counts before creating the derived dataset.

## Timing, type and unit policy

Every canonical source row is processed in its stored order; sequence, stream,
source count and SHA-256 must agree. Exact source timestamp text and native
binary timestamp evidence remain unchanged. Decimal subtraction creates seconds
relative to each derived segment. No original int64 timestamp is rounded through
a floating absolute epoch. Conversion must preserve strictly increasing usable
relative times.

Source segment/clock/identity changes, reversals, duplicate signal timestamps,
gaps greater than 1.5 nominal intervals and removed rows create separate derived
segments. Within a segment, regular intervals must agree with the source nominal
rate to the named 2% interval tolerance plus a 1e-12-second numerical allowance.
Irregular input fails rather than being silently resampled. Original recorded
clock offsets remain unapplied. Reconstructed source timestamps are explicitly
counted; preservation is not proof of physical synchronization.

The missing policy is explicitly **listwise across selected channels**: a row
with any selected missing/nonfinite value or an unanchored/nonfinite time is
excluded from the analysis CSV. Every source row still appears in the full
decision JSONL, including its original sequence, source clock text, identity,
disposition and reasons. Reason counters can overlap; the included/excluded
totals always reconcile to the original row count. Selecting fewer channels can
retain otherwise eligible observations without changing the original source.

Floating measurements must remain JSON numbers, and integer channels retain
their declared numeric type. Numeric-looking strings and booleans cannot become
measurements. Selected int64 measurements beyond exact binary64 range are
rejected instead of rounded. They remain available in the canonical source.

Known compatible units convert by an explicit named factor (for example uV to
V or S to uS). Missing source units require a researcher declaration and rationale
and are labelled as such. Arbitrary units cannot become calibrated volts by
relabeling. Nonidentity source scale/offset declarations require a separately
calibrated source; this first route does not apply undocumented ADC calibration.

## Derived columns and grouping

Reserved columns are:

| Column | Meaning |
| --- | --- |
| `brohn_time_s` | Exact decimal seconds relative to the derived segment start |
| `brohn_segment_id` | Independent analysis segment; never a participant/session/exposure |
| `brohn_participant_id`, `brohn_session_id` | Original or explicitly filled missing identity |
| `brohn_condition_id`, `brohn_exposure_id` | Original explicit source values, possibly absent |
| `source_sequence`, `source_segment_id`, `source_clock_id` | Original row and source-boundary identity |
| `source_timestamp`, `source_timestamp_unit` | Original exact clock text and units |
| `source_timestamp_ieee754_le_hex`, `source_reconstructed_timestamp` | Native timing evidence |
| `source_identity_json` | Unchanged original identity fields in typed JSON text |
| `value_<channel-id>` | Reviewed unit-converted scalar measurements |

The mapping uses the separate `segment_column` in addition to participant and
session columns. Scientific processing cannot filter across a reset while
pretending it is the same continuous recording, nor turn segments into extra
people. The one derived dataset avoids creating thousands of library entries.

Input bounds are 2,000,000 source rows, 20,000,000 selected values, 64 selected
channels and 2,000 derived segments. Full CSV output is limited to 512 MiB; full
canonical/decision evidence has a 4 GiB bound. Exceeding a bound fails visibly
with an explicit split-source instruction; metrics are never computed from a
silently truncated display preview.

## UI hooks and evidence

The core module is `R/platform-stream-curation.R`; views are
`R/platform-stream-curation-views.R`. The stream detail includes
`brohn_stream_curation_ui(record)`. The app installs
`brohn_install_stream_curation_ui(...)`, and derived Data includes
`brohn_curated_stream_dataset_ui(store, record)` for original-source navigation
and full decision/manifest downloads. Modal editor identities protect Cancel,
late Prepare, stale source selection and navigation. Review downloads verify
that the current source/derived dataset owns the selected immutable curation.
The same guarded review includes **Download complete curated CSV** whenever a
usable derived dataset exists. It transfers the exact immutable object through
the writable-download helper, including all source timestamp text and segment
columns; it is not the on-screen row preview.

`tests/workers/stream_extract.py` uses 15 original synthetic fixtures for exact
large clocks, unit arithmetic, independent 10 Hz amplitude/power, reset/gap/
missingness, identity preservation, typed-value refusal and integrity failures.
`tests/platform-stream-curation.R` executes the full supervised bundle import,
curation and actual EEG worker. The same synthetic person/visit has a clock reset
between a 20 uV 10 Hz signal and a 10 uV 20 Hz signal: saved independent powers
are 200 and 50 uV-squared and peaks are 10 and 20 Hz. It also checks publication
fences, complete artifacts, restart/download preservation, unusable source
handling and researcher draft controls. These are software and numerical
reference checks, not physical-device or scientific-study qualification.
