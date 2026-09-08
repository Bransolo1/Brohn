# Implemented contract 0.1.0

Executable definitions: R/study.R, R/records.R and R/json.R. Tests use synthetic
fixtures only. This is a developing contract, not a stable public API.

| Object | Fields / invariants |
|---|---|
| Study draft | schema_version, id, positive integer revision; paired_two_images only; ordered A/B; two distinct stimulus IDs; unique known measures including eye |
| Liking question | stable ID/revision, single_choice, prompt, after_each_stimulus, required boolean, seven stable option IDs/codes/labels; absent when questionnaire is disabled |
| Analysis intent | fixed draft method; B-A contrast; unqualified status. Prepared-interval arithmetic is implemented separately; no arbitrary formula execution |
| Session | study ID/revision, session/participant IDs; sample/preview/pilot/live mode; separate execution/capture/transfer/review states initialized to not_started |
| Clock | unique ID, domain ID, device/host/browser monotonic or UTC domain; s/ms/us/ns unit |
| Stream segment | source ID + segment ID; linked run, clock and selected modality |
| Event | unique (run, source, segment, sequence); matching study revision/origin; trial, exposure, stimulus and epoch references; viewing/response phase |
| Source time | clock/domain/unit matching stream clock; original decimal-string value; explicit source_sample/host_arrival/presentation_observed/response_observed/inference_complete meaning |
| Response snapshot | question ID/revision; displayed option order; unanswered/skipped/answered; valid option ID and matching ordinal code only when answered |
| Bundle | one study/run plus clock, stream and event arrays; validated cross-references; explicit version |
| Optional title | human study name, separate from stable ID; earlier title-free drafts still load |
| Optional stimulus_assets | one inline PNG per stimulus; media type, pixel dimensions, SHA-256 and canonical base64; each PNG at most 5 MiB, 4096 per side and 8 million pixels |
| Optional aois | named rectangles in normalized top-left image coordinates; positive in-bounds size; stable region ID and exact image SHA-256 binding; unique labels within each stimulus |
| Optional comparison | control_condition is none/A/B; rationale is text up to 2000 characters; designation does not change stimulus IDs or B-A direction |
| Optional presentation | order is counterbalanced_ab_ba/fixed_ab/fixed_ba; shared viewing_duration_ms is an integer 500..600000; absent fields use an editable five-second AB/BA draft preset |
| Capability registry | eye, EEG, EDA, RT, AAT, BIAT, questionnaire, webcam gaze, facial geometry, facial-expression estimates; every entry is planned |

Registry membership is a name contract, not an executable combined recipe or a
hardware claim. Only the paired eye + optional liking draft has detailed fields.
## Wire and identity rules

`bundle_to_json()` validates before encoding. `bundle_from_json()` checks shape,
normalises only declared vector fields and validates before returning. Unknown
or duplicate record fields are rejected. IDs are strings; revisions and sequence
numbers are positive integers no greater than 2^53 - 1. Arrays stay arrays even
when empty or containing one value. Missing response values/option IDs are explicit
JSON nulls; absence is not zero or neutral liking. Required questions cannot be
skipped; unanswered is permitted in a draft snapshot.

Raw timestamps are **decimal strings**, for example `"1234567890123456783"`.
This refines the numeric illustration in the archived architecture: nanosecond
counts can exceed the exact integer range shared by R and JavaScript. No conversion,
rounding, mapped time, onset correction or synchronization is performed. The unit
and clock domain remain attached to the original value.

Repeated event identities are rejected within a bundle. The same sequence in a
different source/segment is allowed, as are out-of-order arrivals. A clock reset
can be represented by a declared new segment. These checks do not prove packet
continuity, physical timing accuracy or recording completeness.

Response snapshots use `question.response_state` in the active_response phase;
they do not assert a committed participant answer. The example's unanswered,
skipped and answered snapshots test missingness only. Observation events currently
carry context metadata, not signal samples.

## Boundaries retained for later increments

Origin consistency is checked within a bundle. Tamper-proof origin,
power-loss durable storage, journals, ACK/retry receivers, lifecycle transitions,
device file ingestion, channel definitions, clock mappings and acquisition are
not implemented. Observation trial/exposure/epoch IDs are required references but
are not yet bound to the new planned protocol registry. Stimulus and question identity
are checked against the study. Session lifecycle dimensions remain not_started.
Other questionnaire types/flow and inference models remain future work.

## Implemented local authoring and storage

Local reads are bounded to 16 MiB and decode UTF-8 explicitly. Saves validate
before same-directory temporary writes and replacement; cooperating-writer locks,
explicit overwrite and stale fingerprints protect existing files. See
LOCAL-DEVELOPMENT.md for the limits of these guarantees.

Titles, question wording, image and AOI edits update draft revisions while keeping
study/run identities and origin. Recording-bearing or pilot/live bundles are
read-only in the guided editor. Image replacement clears that image's AOIs rather
than transferring old coordinates to different content. The UI states this before
replacement. The same image is a no-op and retains its areas. Rectangle drawing
rounds new selections to 0.01% of each axis; the contract retains supplied numeric
precision for imported areas. Manual AOI definition is not automated segmentation.

PNG dimensions are checked from IHDR before decode, then the bytes are fully
decoded and hashed. No external paths are retained in the portable asset record.
Pairs of bounded images fit within the draft JSON limit. This is a local draft
format; large recording files will require separate object storage.

The draft eye kernel computes valid interval duration inside a named AOI divided
by eligible valid interval duration during passive viewing. B minus A is reported
in percentage points. Its prepared-interval rules and independent fixtures are
documented in methods/PREPARED-GAZE.md. It does not construct intervals from raw
samples, qualify device validity, map clocks or perform inferential statistics.
Question periods remain separate from passive viewing, and liking refers to the
stimulus rather than automatically to an individual AOI.

Sample-report/0.1.0 contains explicit synthetic origin, study, prepared intervals,
computed tables and limitations. Export recomputes tables from its inputs and
preserves array/null types. examples/reproduce-sample.R recalculates an exported
report without relying on its stored tables. Fixed fictional intervals do not
simulate the planned duration/order. No sample data enters the recording bundle.

Presentation previews contain intended viewing and optional question rows, with
stable stimulus/condition/role references. Planned response duration is missing
(participant paced). This is not an allocation log, observed trial registry or
timer. Control roles and ordering remain separate; see methods/CONTROL-DESIGN.md.

The separate prepared CSV R/CLI importer retains exact original bytes in portable
prepared-gaze-report/0.1.0 artifacts, with source SHA-256 and frozen study. Report
export recomputes from those bytes. Imported origin remains distinct from the
fictional sample and does not verify recording provenance. See methods/PREPARED-CSV.md
for grammar, resource bounds and the unimplemented UI/job lifecycle.

`study-protocol/0.1.0` preserves the full study and strict planned trial/exposure/
epoch/order registries with a canonical SHA-256. Local saves refuse replacement;
exact matching snapshots reopen and older revisions are retained. Registry
validation describes planned procedure, not observed sessions or timing. See
methods/PROTOCOL-SNAPSHOTS.md for encoding, storage and scientific boundaries.
