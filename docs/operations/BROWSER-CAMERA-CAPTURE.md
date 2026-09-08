# Browser camera collection contract

This bounded local extension is implemented and exercised through the actual
researcher and participant interfaces with generated video fixtures. Imported-video
geometry has a separate processing route. This is not physical-camera qualification.

The authored design may include an optional `camera` policy. It specifies whether
recording is required for completion, separate camera consent and retention text,
whether audio is requested, requested frame size/rate, bounded recording limits,
and the selected downstream geometry profile or no automatic processing. A saved
release freezes this policy with the design; clone/template/export preserve it.
Existing designs without a camera policy retain their current participant flow.

Participant flow: general consent → explicit camera agreement → browser permission
and setup → study → stop recorder → durable upload receipts → final study receipt.
The permission prompt and camera setup occur before timed stimuli. Declined,
unavailable, interrupted, transferring and saved capture states are separate.
An optional-camera study may continue after an explicit decline. A required-camera
study cannot report complete camera coverage after a denial or interruption.

Only the participant's affirmative action invokes `getUserMedia`. Audio is disabled
unless the frozen policy explicitly enables it. The interface indicates recording
and exposes the existing stop-study action. Camera or microphone tracks are stopped
on completion, withdrawal, interruption, setup failure and page exit.

`MediaRecorder` output is saved to a separate bounded IndexedDB chunk journal and
uploaded in sequence with authenticated, idempotent receipts. Each chunk retains
its byte hash, recorder identity, browser clock instance and observed callback
time. A retry cannot replace an already accepted sequence with different bytes.
The server retains partial bytes on failure and publishes a recording dataset only
after all declared final chunks are accounted for. A page restart creates a new
recorder segment; separately initialized containers are never byte-concatenated.

The browser recording standard requires the combination of chunks from one
completed recording to be playable; it does not require each individual chunk to
be independently playable. Encoded bitrate is a target rather than a guaranteed
bound. Brohn therefore enforces measured byte limits and distinguishes complete
transport from subsequent decoder support. [W3C MediaStream Recording](https://www.w3.org/TR/mediastream-recording/).

Chunk delivery callbacks do not establish frame exposure times. Optional video
frame callbacks retain their actual metadata and browser-clock relationship;
their media timeline must not be assumed identical to the encoded recorder's
timeline. Alignment to stimuli remains observed browser evidence until a verified
mapping exists. [Video frame callback specification](https://wicg.github.io/video-rvfc/).

The resulting Data-library source keeps its original encoded bytes, capture/run
identity, exact frozen design hash and clock/transfer evidence. Automatic geometry
uses the registered local model route and records its existing provenance. Native
landmarks or blendshapes do not automatically become emotion, calibrated screen
gaze, attentional state or physiological measures. Those transformations retain
their own source-bound recipes and qualification requirements.

Acceptance requires real browser tests with an original generated media fixture:
explicit consent and denied permission, ordered recording/upload, offline retry,
idempotent duplicate, malformed/out-of-order chunk rejection, stop and cleanup,
reload segmentation, complete-file decoding, run/design linkage, immutable Data
source and actual model processing. This fixture evidence is separate from human
consent testing, physical camera accuracy and hosted participant delivery.
