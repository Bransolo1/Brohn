# Native participant equipment checks: executed acceptance

20 September 2026. Original software-generated browser camera/audio, actual
Chromium, actual IndexedDB, actual R receiver and supervised workers. No physical
camera, microphone, eye tracker, keyboard latency or physiological quality was
qualified. PC10 remains partial outside this bounded slice.

## Implemented behavior

New drafts carry optional policy `brohn-participant-equipment-policy/1.0`.
Only requested camera/audio and actual compiled task key codes become default
requirements. Native response-control practice is separately opt-in. Existing
releases without the policy preserve their original flow. The researcher edits
these choices in Plan via **Set up participant equipment checks**; frozen release
requirements and exact saved results remain inspectable in session evidence.

Camera permission and recording remain separate explicit participant actions.
The actual preview observes increasing frame callbacks before any recording.
Requested microphone support comes from AudioWorklet input blocks; no microphone
permission is requested when the camera policy has audio disabled. The same
MediaRecorder produces the consented setup lead-in and study recording.

Panels distinguish track availability, current frame/audio arrival, recorder
state, browser-committed bytes, receiver-acknowledged bytes and pending bytes.
Acknowledged counts are cumulative historical receipts, not evidence that the
encoder is writing now. Image, voice and gaze quality remain unknown. The native
camera does not display an eye-tracker indicator or inferred gaze.

The first-recording check waits for current input plus at least one browser
commit and authenticated byte-prefix receipt. Freshness is 2,000 ms and the
initial wait is 15,000 ms: engineering responsiveness settings, not scientific
quality thresholds. A timeout shows Retry/Stop, retains original bytes and uses
the same recorder. Current camera/audio state is checked again after the saved
equipment-event receipt, so losing the stream during a slow receipt cannot enter
the study using stale observations.

Required task keys use trusted, released key-code observations before trials.
Optional native control practice records its actual activation route. Both use
separate setup events and do not enter scoring or advance the protocol cursor.
The key check applies once per current browser page; a subsequent focus change
does not erase it. Existing timed-task visibility/focus rules still apply. A new
page cannot reuse the previous page's check.

The receiver validates strict fields, policy hash, explicit page identity and
clock origin, capture ownership, native settings and exact acknowledged chunk
prefix. Retry deduplicates the original event. A delayed original check may be
retained after recording completion/interruption as historical evidence, not
current approval. Observed final capture time bounds the check. Only the exact
unobserved-reload sentinel skips that upper bound: interrupted status,
`container_complete=false`, reload reason, and final clock identical to the
original start clock.

## Executed checks

| Harness | Result | Scope |
| --- | --- | --- |
| `tests/participant-equipment-model.mjs` | 18 passed | Exact freshness boundary, future/muted support, local versus receiver writes, zero/absent/nonfinite/suspended audio, independent alternating and constant Float32 amplitudes. |
| `tests/platform-participant-equipment.R` | 27 passed | Default/legacy policy, page/policy gates, real receiver prefix/ownership, duplicate event, historical recovery, reopened evidence and finite constant microphone receipt. |
| `tests/participant-equipment-races.mjs` | 9 passed | Independent real-browser delayed-receipt signal loss and exact original-event reload recovery; unchanged production source hashes. |
| `tests/platform-participant-equipment-races.R` | 16 passed | Independent actual receiver exact sentinel versus reason-only ending, explicit page clock and legacy absence. |
| `tests/platform-capture-views.R` | 43 passed | Actual Shiny camera and equipment policy authoring, dependent control, preserved camera policy and historical choices. |
| `tests/platform-capture.R` | 63 passed | Historical absent-policy actual release/receipt, one-container assembly/decoder, cancelled publication/retry, portability, backup and reopened original bytes. |
| `tests/participant-equipment.mjs` | 24 assertions, 2 scans, 9 actual jobs passed | Six real releases: camera, requested audio, complete 28-trial modern key-gated RT, optional camera decline, optional native control practice and historical absence. |
| `tests/researcher-participant-equipment.mjs` | 4 assertions, 4 scans passed | Independent actual clone/save authoring, requested audio/key/control/legacy evidence, exact JSON download, desktop and 390 px. |
| `tests/participant-equipment.mjs`, visual-only follow-up | 10 assertions, 2 scans passed | Settled-frame screenshots of desktop actual preview and 390 px receipt waiting; closes original capture as withdrawn; no scientific jobs. |

The full journey injected a foreign chunk receipt followed by unavailable
responses. It did not enter the protocol, did not delete the unacknowledged
prefix and did not start another recorder. Retry sent the exact original chunk
request. Requested audio used the same permission/recorder path. Synthetic
KeyboardEvent dispatch could not satisfy key practice. Actual browser keyboard
actions completed the check and every original RT trial. Camera decline made no
permission request. All six session journals received final storage receipts.

The nine supervised jobs were six session analyses, two camera assemblies and
one automatic face-geometry analysis. The completed original recording decoded;
the original static non-face image produced `insufficient_support` with zero
valid face frames. A successful equipment transport check did not become a
scientific face/gaze result.

The final AudioWorklet correction clamps finite accumulated RMS to observed
peak, enforcing the mathematical RMS <= peak invariant. Float32 constants
0.3/-0.3 and 0.7/-0.7 across 38 blocks of 128 samples at 48 kHz otherwise round a
few ulps above peak. The independent expected value is the exact Float32
amplitude; the real receiver preserves 0.30000001192092896 for both RMS and peak.
This is numerical normalization, not a quality threshold.

The independent review reproduced and then resolved delayed-receipt signal loss,
pending-event reload recovery, omitted new-policy page identity, and overly broad
reason-only reload sentinel acceptance. The final race run passed with identical
source hashes before and after. See
[the peer review](PARTICIPANT-EQUIPMENT-PREFLIGHT-PEER-REVIEW.md).

## Evidence receipts and source versions

Evidence lives outside the repository under
`C:/Users/User/Documents/Codex/2026-09-20/oka/work/`:

- `brohn-participant-equipment-TboVSv`: full 24-assertion/9-job journey, saved
  reports, actual session/capture records and participant script hashes.
- `brohn-participant-equipment-SR4dQo`: final visual-only preview/pending captures.
  Both PNGs were visually inspected after axe cleanup and two animation frames;
  zero axe violations and no horizontal overflow. Its legacy result-mode field
  says workers pending; this run intentionally launches no workers.
- `brohn-equipment-review-04`: independent final researcher authoring/evidence
  screenshots, exact downloaded microphone evidence and four clean axe,
  overflow and 44 px action-target scans.
- `brohn-participant-equipment-DaLNje`: independent final real-browser race
  requests, exact recovered event, saved interruption and matched source hashes.
- `equipment-peer-historical-final02`: independent final 16 actual receiver and
  page-clock cases, including retained unobserved reload and rejected observed
  endings carrying the same reason text.

The full supervised journey predates the final strict unobserved-end sentinel
and RMS rounding corrections. Those changes have focused real-receiver and
independent numerical regressions; do not describe the earlier journey's hashes
as the final production revision. Source-fenced race evidence records the final
core/delivery/equipment/runner identities separately. An earlier peer run passed
its eight behaviors but correctly failed the source fence when unrelated core
illustration work changed during execution; it is not matching-source evidence.

## Relevant unchanged behavior rechecked

- Camera controller: 12 real browser checks, including one recorder, actual
  chunks, lost receipt and reload behavior.
- Participant persistence: 13 typed-branch plus 17 real pending-permission,
  decline/reload checks.
- Actual task integration: 21 browser checks across complete RT/IAT, correction
  and interruption, plus 27 R integration checks.
- Methods: 324 existing checks, including all 162 eligible upstream task vectors;
  RT support: 56 checks.
- Minimal-source compatibility: core 109, delivery 56, portability 90 and library
  storage 18 checks. Fixtures explicitly source the registered equipment domain;
  historical task/camera regressions explicitly set absent policy. Dedicated new
  policy browser tests retain the real gates.

## Limits retained

Camera callbacks measure browser preview arrival, not capture FPS or encoded
exposure alignment. Microphone rate describes the processing context; normalized
RMS/peak are not native calibration, SPL or speech quality. Combined recording
bytes cannot prove separate per-track bytes. Native input is client-observed
evidence, not authenticated physical-device identity or latency qualification.

Saved checks are evidence for the original page/recording, never reusable
approval for another visit. No automatic replacement of a lost capture or
calibrated gaze inference was introduced. Continuous monitoring is bounded to
300 frame callbacks/five seconds and 50 aggregate audio summaries; canonical
recorded bytes remain unchanged.

The researcher evidence accessor currently decodes the existing complete session
journal before filtering equipment events, and displays all saved checks. A
bounded scan/paged disclosure remains a follow-up for exceptionally large
journals; this acceptance makes no large-session scaling claim.

The design rationale and primary implementation guidance are in
[the contract and initial audit](PARTICIPANT-EQUIPMENT-PREFLIGHT-CONTRACT.md).
The user-facing instructions are in `oka/outputs/Brohn-Equipment-Checks.md`.
