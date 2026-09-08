# Authenticated browser-camera receipts

Implementation: `R/platform-capture.R`. This complements the participant
[camera collection contract](BROWSER-CAMERA-CAPTURE.md). It is local browser
collection, not physical camera or encoded-frame synchronization qualification.

The standalone capture manifest includes the exact frozen consent, retention,
audio and processing policy; study/revision/deployment/design/protocol references;
and declared participant linkage. Publication verifies these against the original
capture receipt. Its contents are available even when automatic processing is off.
The administrative backup CLI loads the same camera-integrity extension.

## Frozen policy

`design.camera` is optional. Presence enables this policy:

```
schema: brohn-camera-policy/1.0
required: boolean
audio: boolean
consent_text: nonempty text
retention_text: nonempty text
width: integer 160..1920
height: integer 120..1080
frame_rate: number 1..60
max_duration_s: number 1..600
max_bytes: integer 1024..134217728
analysis_profile: none | face_geometry_v1
```

Dimensions/rate are requested upper bounds. Actual settings are retained and
cannot exceed them; audio must match the explicit frozen choice. Camera and
retention text each have a 12,000-character limit. Existing designs without the
property continue through their original consent and study flow.

## Receiver contract

POST `camera_start`, `camera_chunk`, and `camera_finish` routes use the run's
existing Bearer credential and a 4 MiB JSON request limit. The backend functions
are `.brohn_camera_start`, `.brohn_camera_chunk`, and `.brohn_camera_finish`,
each with `(store, run_id, token, request)`.

There is exactly one camera capture identity per participant run. A new page
cannot splice a newly initialized recorder into its old container. Consent
decline is an explicit immutable decision; a different recorder needs a new run.
Recording starts are accepted before study steps start. Start pins the full
frozen design, policy, study revision, protocol hash, run, participant-code
declaration and source origin.

Start request:

```
capture_id: camera-<UUID>
consented: boolean
clock: {id: browser-monotonic, unit: ms, value: decimal-string,
        instance_id: string, time_origin_ms: decimal-string}
mime_type: video/webm[;codecs=...] | null
settings: {width, height, frame_rate, audio} | null
reason: string | null
operation_id: string
```

A declined start has `consented=false`, null MIME/settings and a reason. An
unavailable setup may have `consented=true`, null MIME/settings and a reason.
Successful recording setup has MIME/settings and no failure reason. Response:
`{capture_id, status, next_sequence}`. Exact request retries are idempotent;
changing an earlier operation or recording identity is rejected.

Chunk request:

```
capture_id, sequence, data_base64, sha256, operation_id
observation: {
  callback_ms: decimal-string,
  event_timecode_ms: number | null,
  frames: [{now_ms, media_time_s, presentation_time_ms|null,
            expected_display_time_ms|null, capture_time_ms|null,
            presented_frames, width, height, step_id|null, phase|null}],
  unretained_frame_callbacks: integer
}
```

Raw chunks are capped at **2 MiB**, leaving JSON space after base64 expansion.
There are at most 4,096 chunks and 60,000 retained video callbacks per capture,
with at most 500 callbacks in a chunk. Actual byte counts also enforce the
smaller frozen policy limit. Callback clocks cannot reverse; repeated Blob
callback times may accompany byte splits, but retained frame callbacks cannot
repeat. Only the first split piece should carry its Blob's frame observations.
Frame step/phase references must belong to the frozen protocol.

Raw chunk bytes and observation JSON are separate immutable hashed objects. Each
sequence can be accepted once; an exact retry under a new operation ID returns
the acknowledgment, while different bytes or observations produce a conflict.
Missing sequences, foreign captures, invalid hashes and noncanonical base64 are
rejected. Response: `{capture_id, acked_sequence, total_bytes, status:'saved'}`.

Finish request:

```
capture_id, final_sequence, total_bytes,
outcome: completed | interrupted | withdrawn,
container_complete: boolean,
clock: same browser-clock instance as start,
reason: string | null,
operation_id
```

Totals must match all acknowledged chunks. A completed recording needs bytes,
a stopped complete container and no failure reason. Interrupted/withdrawn endings
require a reason and retain all bytes. A reload with unknown old-page ending uses
the exact original start clock with `outcome=interrupted`,
`container_complete=false`, and
`reason=page_reload_recording_end_unobserved`. This sentinel never supplies a
recording end or completion coverage.

The terminal receipt is immutable and queues assembly when bytes exist.
Response: `{capture_id,status:'saved',outcome,decoding:'separate_processing'}`.
Transfer success does not assert decoder support.

## Assembly and publication

The `assemble_capture` job uses:

- `brohn_capture_input(store, job)` for immutable capture/chunk/object references.
- `brohn_assemble_capture(input, scratch)` in the supervised child.
- `brohn_publish_capture(store, output, scratch, job, input, output_path)` under
  the existing publication fence.

Each source chunk is hash checked and combined in its acknowledged byte order.
A boundary-aware EBML walker accepts one WebM document/segment and rejects
separately initialized concatenated containers. It skips encoded element
payloads rather than searching them for magic byte sequences. Truncated or
unsupported containers are retained as partial/unsupported source evidence.

For a supported container, local ffprobe actually decodes frames with a
180-second time limit and bounded output. The recording retains decoder version
and executable hash, video/audio frame counts, original encoded PTS support,
actual stream settings and warnings. This does not map encoded PTS to browser
callback or stimulus clocks. A changed channel configuration, unavailable or
reversed video PTS, decoder error or duration beyond policy prevents automatic
processing support.

Publication verifies scratch containment, artifact size/hash, exact ordered
source chunks and the manifest before committing the dataset and camera entity
under the live job fence. The Data-library source pins its original WebM bytes,
capture/run/design/protocol identities, origin and recording outcome. Full chunk
observations, decoder-frame metadata and capture manifest become downloadable
immutable artifacts. No scratch path remains in a published record.

`brohn_camera_completion(store, run_id)` returns
`{eligible,required,status,reasons,...}`. A missing optional decision is not an
implicit decline. Explicit optional decline/unavailability permits the remaining
study; recording interruption does not become optional complete coverage.
Completed capture must cover the study step/response clocks in the original
browser instance. It does not need to cover the later `run_finished` event.

`brohn_queue_capture_analysis(store, run_id)` is idempotent and must be called
after a completed study receipt and from assembly publication. It queues the
registered face geometry route only after both run and capture are completed,
the frozen policy requests that profile and decoded source support passes.
Partial/withdrawn sources stay available for review without automatic geometry.

## Backup and portability

Camera tables and immutable chunk/observation objects are included in normal
workspace snapshots. The backup catalog validator calls
`brohn_capture_catalog_integrity(con)` to verify camera start/final hashes,
frozen design/protocol, contiguous sequences, byte counts and object references.
Existing restore behavior closes deployment links, rotates run credentials and
pauses processing; no camera credential bypass is added.

Design ZIPs retain the optional policy through ordinary R validation and full
design serialization. The Python package validator already permits valid JSON
design documents and checks file/manifests; it does not require a new camera
field allowlist. Design exports contain policy, not captured participant bytes.

Scoped executable evidence lives in `tests/platform-capture.R`; actual browser
MediaRecorder and local-journal behavior has separate controller/integration
tests. The generated fixtures establish software behavior, not physical-device
accuracy or consent comprehension.
