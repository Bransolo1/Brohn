# Native participant equipment preflight: contract and initial audit

Status: implementation completed for the bounded first slice, 20 September 2026.
See [executed acceptance and remaining limits](PARTICIPANT-EQUIPMENT-PREFLIGHT-ACCEPTANCE.md).
The audit table below records the starting state; it is not the current feature
status. This extends PC10 and does not close device qualification. No physical
hardware was available. Executed tests use original synthetic media, browser
automation, isolated receiver storage and software replay.

Implementation decisions: new drafts enable relevant camera and compiled task-key
checks by default; optional native control practice defaults off. Historical
policy absence keeps its original behavior. The frozen operational limits are
2,000 ms observation freshness and 15,000 ms initial recording/receipt wait.
One `brohn-participant-equipment-check/1.0` envelope holds typed observations;
there is no separately serialized observation schema. Key checks apply once per
page, with explicit page identity and clock origin. Saved historical camera checks
can arrive after an interrupted recording ends, while current entry still needs
fresh camera observations after its check receipt.

## Existing behavior and the concrete gap

| Source | Implemented behavior | Missing participant evidence |
| --- | --- | --- |
| `www/participant/runner.js`, `enterStudy()` | Separate camera consent/retention information, explicit Enable camera, actual local video preview, optional decline, required-camera stop path. Recording starts on Begin study before protocol presentation. | Preview has no observed-frame count/age. The status immediately says recording after the MediaRecorder start event; it does not distinguish browser writes and receiver receipts. |
| `www/participant/camera.js`, `prepare()`, `collectFrames()`, `start()` | Explicit getUserMedia, actual track settings, one WebM recorder, frame-callback observations with browser/page identity and study phase. Late permission cannot attach after cancellation. | Frame observation starts only after recording. No live mute/unmute, stalled-frame, audio-buffer or recording-progress presentation. A live track and fulfilled `video.play()` are not evidence of arriving frames or durable bytes. |
| `camera.js`, `acceptBlob()`, `flush()`, `stop()`, `recover()` | Atomic IndexedDB segment/chunk writes; separate acknowledged sequences/bytes; bounded pending bytes; idempotent uploads; one-container finalization; interrupted reload recovery. | The necessary storage counts already exist but are not surfaced. MediaRecorder state must not stand in for these counts. |
| `R/platform-capture.R` | Frozen consent/policy and run binding, immutable ordered chunk receipts, final totals, clock-instance checks, observed browser study-coverage bounds, separate supervised decoding/model work. | No preflight policy/result record or current participant monitor. Completion proves the stated transfer/bounds checks, not encoded-frame alignment, eye tracking, adequate lighting or face-model support. |
| `www/participant/tasks.js` | Physical-keyboard instructions; exact compiled `allowed_codes`; trusted, nonrepeat, released-key rules; recorded first/correct response; visibility/focus/resize interruption; rAF-before-paint onset and frame-gap observations. | No check that the participant can generate each required code before a timed block. The browser cannot identify a physical keyboard model or qualify its latency from these events. |
| `runner.js`, native questionnaire/MaxDiff controls | Accessible native input and explicit durable responses. There is no raw touch-motion acquisition profile. | No optional practice control demonstrating the participant's actual activation route. Touch capability declarations must not become proof that touch input was observed or substitute for the keyboard-only task profiles. |

Existing regression foundations are `tests/camera-controller.mjs`,
`tests/participant-camera-races.mjs`, `tests/participant-persist-regressions.mjs`,
`tests/researcher-camera.mjs`, `tests/platform-capture.R`,
`tests/platform-task-integration.mjs` and `tests/participant-runner.mjs`.
They are prior evidence, not execution of this proposed contract.

## Scope of the first complete implementation

Implement camera preview/recording checks, requested-microphone observations,
required task-key practice, and a native control practice check in the actual
participant journey. Include the saved researcher evidence and one complete
camera-to-automatic-report regression. Do not introduce live model inference,
calibrated gaze, biometric inference, hardware enumeration requirements or a new
scientific score.

Add an optional frozen design policy `participant_equipment`, schema
`brohn-participant-equipment-policy/1.0`. Absence keeps a historical release's
existing behavior. New drafts may opt into the named checks; the researcher sees
their requirements and interpretation before release. Requirements derive from
the frozen camera policy and compiled task codes, never user-agent guesses:

- Camera requested: enable the camera observation and first-write check.
- Camera audio requested: add the microphone observation panel; never request
  audio when the frozen camera policy says false.
- Compiled keyboard tasks: require each distinct allowed code for the relevant
  task, with one down/up cycle and no held keys before entering its first block.
- Native response controls: offer an untimed practice action usable with keyboard,
  mouse, pen or touch. It is not a timed-task substitute and does not impose a
  new touch-only requirement on an accessible questionnaire.

The policy names operational check versions, support rules and freshness settings.
It does not contain universal scientific quality thresholds. Initial defaults
should be explicit product settings, for example a 2,000 ms foreground observation
age for the displayed `current` camera/microphone state and a 15,000 ms first-write
waiting deadline. These are proposed application responsiveness limits, not
camera accuracy or physiological acceptance criteria; freeze their values and
rationale in the policy and test their exact boundaries. A waiting deadline shows
Retry/Stop rather than inventing missing data or silently starting timed steps.

## Separate states and truthful wording

Every panel reports independent fields, not a single green Ready flag.

| Panel | Connection / availability | Receiving evidence | Recording evidence | Supported interpretation |
| --- | --- | --- | --- | --- |
| Camera | Permission not requested/pending/denied; track live/ended; enabled and muted state; actual width/height/settings | Two distinct increasing video-frame callbacks on the current track generation, observed count, last callback age, dimensions and callback cadence | Before explicit start: not recording. Then recorder started, first bytes pending, browser committed bytes, receiver-acknowledged bytes, final receipt independently | `Camera frames observed` or `Meets camera transport check`; image/face/gaze quality unknown |
| Microphone, only when requested | Audio track live/ended/muted/enabled and audio-context running/suspended | Actual processed input-block count and channel support, sample rate of the processing context, last block age; bounded RMS/peak level in normalized full-scale units | Same multiplexed recording's committed/acknowledged bytes, explicitly not per-track byte totals | `Audio buffers observed`; silence/level observations are descriptive. Audibility, speech quality, SPL calibration and emotional meaning unknown |
| Task keyboard | Browser keyboard event route available; physical device identity unknown | Each required compiled code observed through trusted nonrepeat down/up; focus visible; held-key set empty | Check result saved locally/received separately; actual task events keep their existing journal and scoring | `Required keys checked`; hardware latency and physical keyboard qualification unknown |
| Native controls | Actual accessible control available | Trusted native activation; report pointer type only from an observed pointer event; keyboard/assistive activation may have no pointer type | Practice result saved/received; no scored response created | `Practice control activated`; no touch sampling, pressure or response-latency qualification |

For camera cadence label the number as **observed preview callback rate**, not
device capture FPS or decoded recording FPS. Repeated static imagery can still
have new frames; do not use pixel differences as a liveness requirement.
No-face, face confidence and gaze validity are unknown because no live model runs.
A native camera preview must never show manufactured pupil/eye markers, a gaze
dot or an eye-tracker connected badge. Even a later face-landmark overlay would
need its actual model/version/support and would not alone establish calibrated
screen gaze.

RMS/peak use actual finite input samples. Display zero level as zero level, not
device failure; no input channels, suspended processing or missing support remain
unknown. Saturation counts may mean samples reaching a declared digital rail,
not acoustic clipping or a calibrated microphone limit. Do not count periodic
main-thread analyser reads as proof of newly received audio. A small AudioWorklet
can aggregate actual input blocks and publish bounded summaries, with a silent
output path so the participant never hears microphone feedback. Preserve native
track settings separately from processing-context resampling settings.

## Participant flow and timing

1. Keep general consent and separate camera/audio consent. Preflight precedes
   scored trials and protocol stimulus exposure. No camera permission, model
   download, microphone request or recording happens on page load.
2. Present only checks required by the selected release. Key practice uses neutral
   labels and codes, not task stimuli, categories, correctness or scored trials.
   It never creates `task_trial_started` or `task_trial_finished` events.
3. Enable camera attaches the real preview and begins bounded monitoring only.
   Clearly say that recording has not started. Preserve optional decline and
   pending-permission Stop behavior. If frame observation is unsupported, show
   unknown with the exact reason; a required observation check cannot pass.
4. `Start recording and continue` is the explicit recording action. Keep the same
   one-container recorder. Show the recording check while waiting for at least
   one nonempty blob to finish its IndexedDB transaction and its receiver receipt.
   Only then offer/perform entry into the study timeline. The first chunks are
   real consented lead-in recording, not a discarded test recording; say so.
   The existing maximum duration starts with recording and includes this lead-in.
5. Do not start timed steps while a required check is pending, failed, stale or
   unacknowledged. Retrying upload reuses the same frozen bytes/request. If waiting
   continues, show local saved/pending counts and Stop, without promising a
   timeslice callback deadline. Do not restart the recorder to obtain a receipt.
6. During tasks retain the small, nondistracting recording status; do not put the
   participant's face or a changing waveform beside controlled stimuli. A detail
   panel is available during untimed setup/boundaries. Update text at a bounded
   rate and announce state transitions, not every frame, to assistive technology.
7. Ended/disabled tracks, recorder errors and durable-write failures interrupt as
   appropriate under the frozen policy. A mute event, hidden page or missing
   callback changes the current observation state; it does not rewrite previously
   saved counts. A missing preview callback alone is not proof the encoder stopped.
   Preserve existing timed visibility/focus rules. No silent replacement stream,
   clock splice, replayed trial or revived previous approval.
8. This first implementation checks required keys once per current browser page.
   A later focus change (including an operating-system camera permission dialog)
   does not erase the observed key check. Existing task focus/visibility guards
   still apply at every timed trial. A new page requires a new input check; a
   prior page's result is historical evidence. Resume after reload retains the
   existing camera interruption semantics; it cannot replace that recording.

## Source, journal and storage contract

Propose `brohn-participant-equipment-observation/1.0` for bounded check evidence and
`brohn-participant-equipment-check/1.0` for its named-rule outcome. Retain:

- frozen protocol/policy hash, check version, check ID and current page clock
  instance/time origin; camera evidence additionally identifies capture ID where
  one exists and an ephemeral track generation;
- exact requirements/settings, observation window, support counts, clock units,
  last-observation age at evaluation, outcome/reason and software-origin statement;
- keyboard required/observed codes and down/up support only inside the check;
  native control identity and observed activation type, without free typing,
  unrelated keys, pointer paths, device IDs or unnecessary hardware labels;
- camera requested/actual settings and frame counters; microphone requested/native
  settings plus processing-context settings; no preflight image snapshots or extra
  raw audio storage;
- browser committed sequence/byte high-water marks separately from receiver
  acknowledged high-water marks and final capture receipt. Never promote pending
  blobs or a MediaRecorder event into a durable-write claim.

Use the existing ordered, idempotent participant journal for a new strictly typed
`equipment_event`, with null question/stimulus/condition identity and phase
`equipment_setup`. This requires an explicit receiver event-validator extension:
the current allowlist rejects such events. Accepted equipment events must not
advance the protocol cursor, satisfy a question, enter task scoring or become an
exposure denominator. They remain inspectable evidence. Bound each payload, e.g.
64 KiB, and retain transitions/final check summaries rather than every monitoring
tick. Continuous frame/media observations retain the existing recording artifacts.

The receiver verifies check/policy identity, current page clock, ordered event
identity, support arithmetic and required camera capture/acknowledged-byte facts.
It derives the permission to enter a policy-gated first step from accepted check
results; a bare client `passed=true` is insufficient. Native input is still
client-observed evidence, not authenticated physical-device proof. Bind a result
to its exact policy and current check attempt. Changed requirements, a new page,
track replacement, a resumed interrupted attempt or altered observations require
fresh checks. Duplicate retries return the original receipt; conflicts reject.

Live snapshots use bounded memory: one current camera frame displayed by video,
aggregated counters plus at most a five-second/300-entry callback ring, and at
most 50 aggregate audio summaries (10 Hz for five seconds), with explicit omitted
counts when applicable. Full received recording bytes retain the original
64 MiB pending-buffer and 2 MiB transfer chunk limits. Monitoring never changes
canonical recording bytes, creates a second encoder or gathers new permissions.

Strengthen receipt checks while exposing counters: verify the current capture ID,
status, monotonic sequence and consistent totals before deleting a local pending
chunk or displaying receiver-saved. The receiver is authoritative for receipt
state; local progress remains visibly separate during an offline retry.

## Researcher presentation and implementation boundaries

The release review shows which checks apply, the exact settings and that physical
latency/image/voice/gaze quality are unqualified. The saved participant session
view shows check outcomes, reasons, observed settings, local/receiver support and
the original policy/clock/capture references. Old runs show `Not collected by this
release`, not a failed or passed retrospective result. No stored check is reusable
approval for another participant, release, device generation or browser visit.

Likely implementation ownership:

- New `www/participant/equipment.js` for bounded check models and untimed UI;
  optional small same-origin audio-worklet module for requested audio summaries.
- `www/participant/camera.js` for monitoring subscriptions and committed/receipt
  notifications; preserve existing prepare-generation, journal and stop semantics.
- Narrow `runner.js` integration and `index.html` static inclusion; coordinate with
  question-illustration ownership before editing. `tasks.js` needs at most a
  boundary hook; do not refactor trial timing or scoring to add practice.
- New R participant-equipment domain module; root coordinates core optional-field
  validation/compile policy, load/worker source closure, delivery event admission,
  source-bound gates/static routes and session evidence views. Do not use camera
  chunk observation schema additions merely to smuggle unrelated input events.

## Required focused acceptance

| Test | Independent expected result |
| --- | --- |
| Camera prepare with original numbered/static Y4M fake device | Actual changing callback counters and visible video; no camera start/chunk requests before explicit recording. Static content does not fail transport. No gaze/face-validity claim. |
| Recorder start before first blob; delayed blob; empty blob | Started remains distinct from committed. Empty data cannot pass. First nonempty blob must complete actual IndexedDB transaction. |
| Receiver accepted chunk but response lost; offline/retry; wrong capture receipt | Local counts remain while receipt unknown. Retry preserves exact operation/bytes once. Foreign or inconsistent acknowledgement cannot purge pending bytes or claim saved. |
| Real first-write gate through actual R receiver | No first timed event precedes accepted preflight/recording receipt. Final one-container bytes decode; ordered native PTS and original callback clock remain separate. |
| Mute/unmute/track ended, disabled track, hidden page, stalled callbacks | Separate observed states and original ages/counters; no stale green. Existing timed interruption and late-permission Stop/Decline behavior preserved. |
| Requested audio: original sine, zero/silence, absent channels, suspended context | Known RMS/peak/support match independent expectations; no new audio permission when false; silence not declared usable speech; processing counters cannot stand in for per-track recording bytes. |
| Required task codes using actual browser keyboard actions | Every required code plus release needed; repeated/held/modifier/wrong/untrusted JS events do not satisfy check. Check does not create trials, alter random order, first-response timing, task checkpoints or scored denominators. |
| Native control by keyboard/mouse/emulated touch; keyboard-only task on touch context | Actual activation route is recorded honestly; capability alone cannot pass. A touch activation cannot satisfy missing task key codes. Accessible keyboard activation remains available. |
| Policy edit, old release, new browser page, copied/malformed check, stale attempt | Frozen release keeps exact requirements; historical missing policy unchanged. Fresh binding required; receiver rejects foreign protocol/capture/clock and inconsistent outcomes. |
| Local quota failure, stop during each asynchronous stage, reload and reopen | No timed entry without saved required checks; no late tracks, duplicate recorder or invented ending. Original partial bytes and accepted evidence remain recoverable. |
| Complete camera study with automatic face-geometry processing | Original non-face video yields actual saved absent-face/insufficient-support results, unchanged by a successful transport preflight. Saved checks visible with original references. |
| Desktop and 390 px, keyboard-only navigation, axe and real controls | Readable preview/status, no overflow, minimum44 px action targets, unique labels, state transitions announced once; no diagnostic animation in timed stimuli. |

Implement small deterministic model/receiver tests plus one actual released-study
browser journey in an isolated workspace. Reuse existing camera/controller/race
and task regression harnesses for changed paths. Run scientific workers only
after source freeze. Save exact script hashes, original media hashes, request and
receipt evidence, screenshots, observed failure cases and the declared fake-device
origin. Do not call browser fake-device automation physical hardware validation.

## Sources and interpretation boundaries

The existing [measurement academic audit](MEASUREMENT-ACADEMIC-ACCEPTANCE.md)
remains the per-modality reference. The following primary implementation guidance
was checked for this proposal on 20 September 2026:

- [W3C Media Capture and Streams](https://www.w3.org/TR/mediacapture-streams/):
  track state/settings, mute/enabled distinctions and dynamic source changes.
  A track setting or connection is not an image-quality result.
- [W3C MediaStream Recording](https://www.w3.org/TR/mediastream-recording/):
  timeslice is not an exact callback deadline; individual blobs need not decode
  independently; muted/disabled tracks can encode black/silence.
- [Browser frame callback guidance](https://web.dev/articles/requestvideoframecallback-rvfc):
  callbacks observe compositor delivery, may be display-rate limited and have
  best-effort timing. They do not establish exposure/encoded-frame alignment.
- [W3C Web Audio](https://www.w3.org/TR/webaudio-1.1/): processing graphs and
  AudioWorklet input support. Processing-context samples remain separate from
  hardware capture/calibration claims. This version is a working draft.
- [W3C keyboard code values](https://www.w3.org/TR/uievents-code/) and
  [Pointer Events](https://www.w3.org/TR/pointerevents3/): declared code/observed
  pointer types supply event semantics, not device-latency qualification.
- [PsychoPy timing guidance](https://psychopy.org/general/timing/millisecondPrecision.html):
  software timestamps alone cannot qualify physical display/input timing.
- [MediaPipe Face Landmarker](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker):
  model outputs need their specific interpretation; this first preflight does
  not run that model or infer gaze from a camera connection.

The academic audit's [eye-tracking reporting reference](https://pmc.ncbi.nlm.nih.gov/articles/PMC11225961/)
remains relevant for calibration, accuracy, loss and timing evidence. Its PMC
page returned a browser challenge during this bounded audit; no new claims of
re-reading its full text are made here. PC10 remains partial after this proposed
slice until the named external-device and measurement-specific gaps are closed.
