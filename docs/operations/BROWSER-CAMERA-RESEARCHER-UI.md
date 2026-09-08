# Researcher camera workflow

The Plan card **Camera and microphone** configures the optional frozen camera
policy. **Set up camera recording** opens an explicit Save/Cancel dialog. Enabling
the feature requires separate participant-facing recording and retention text;
the product does not invent an organisation's access or deletion policy.

The researcher chooses optional or required recording, microphone inclusion,
local face geometry processing or retained-source review, and bounded maximum
dimensions, frame rate, duration and bytes. Browser constraints use the bounds
as requested targets and maxima. A recording limit interrupts the session and
retains partial bytes; the dialog explains that instructions and questionnaires
also consume recording time.

Save validates the real camera policy and creates a study revision. Each dialog
has a unique editor identity. Save first flushes ordinary Plan edits and rejects
the camera draft if the underlying design changed. A late Save, old Cancel,
stale form identity, archived study or navigation cannot change another draft.
Cancel discards the draft without saving. Disabling removes the policy only from
the current design revision. Older designs and released participant protocols
retain their policy. Cloning, reusable designs and portable design ZIPs retain
the exact policy; they do not copy participant recordings.

## Collection and source history

Sessions distinguish no requested recording, awaiting a camera decision,
explicit decline, unavailable setup, receiving chunks and received/interrupted/
withdrawn recording. A started receipt does not prove the device is still live.
Chunk/byte counts describe server acknowledgments. Video preparation has its own
queued/running/failed/cancelled state and a retry action for saved assembly input.
After publication, **Open camera dataset** opens that run's immutable source.

The Data page identifies the frozen run, participant code, origin, design and
protocol hashes, recorded outcome, declared container completeness and actual
decoder support. It offers full immutable artifacts:

- Original camera recording (WebM).
- Chunk clocks and frame callbacks (JSONL).
- Decoded frames and native timestamps (JSON), when decoder evidence exists.
- Capture and transfer manifest (JSON), including frozen policy and provenance.

The selector pins dataset ID, revision, original source hash, artifact kind and
artifact hash. Download validation checks the current page and dataset, rejects
foreign or stale selections, verifies stored bytes and makes a writable transfer
copy. Original immutable objects remain read-only. This matters on Windows,
where inheriting a source object's read-only attribute can break HTTP transfer.
Partial/unplayable bytes remain downloadable with their actual outcome.

Browser callback observations are not encoded-frame alignment evidence. Face
landmarks and native blendshapes do not automatically establish emotion,
calibrated gaze or attention. These limitations are visible beside the source,
separately from sample/pilot/live origin and completion.

## Module integration and evidence

`R/platform-capture-views.R` provides:

- `brohn_camera_plan_ui(design)` and `brohn_install_camera_plan_ui(...)`.
- `brohn_camera_session_ui(store, run)`.
- `brohn_camera_dataset_ui(store, record)`.
- `brohn_camera_dataset_artifact(store, request, dataset_id)`.
- `brohn_install_camera_artifact_ui(...)`.

The loader sources these views before the general views. The app installs Plan
handlers after its capture/save helpers and artifact downloads beside other
download handlers. Plan, Sessions and Data contain narrow view hooks.

`tests/platform-capture-views.R` passes 39 checks across actual Shiny save/cancel/
staleness, policy bounds and microphone typing, archive/navigation, preserved
history, clone/template/ZIP reuse, immutable download ownership and real frozen
participant decision receipts. Artifact display fixtures are explicitly original
synthetic bytes, not decoder qualification. The separate camera backend suite
executes real supervised assembly and source preservation. Actual researcher
browser recording, retry and download acceptance is recorded separately by the
researcher QA suite; these component checks do not substitute for that journey.
