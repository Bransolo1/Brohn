# Saved video to acoustic analysis

Connected acceptance, 24 September 2026. Saved imported video and explicitly
consented browser camera audio can now enter acoustic analysis through the data
library: inspect tracks, choose a stream, create a derived WAV, confirm its
original channel, run the existing acoustic recipe, then review its waveform,
spectrogram and retained acoustic series. Original video bytes remain unchanged.

## Source and timing contract

The source video remains immutable. `video-audio-source/1.0` first inspects its
actual audio streams, then decodes the explicitly selected container stream.
There is no channel mixing, resampling, time stretching or inserted silence.
A multichannel WAV keeps the original channel order; the existing acoustic
recipe still requires an explicit channel selection. Compressed input is
identified by codec: its decoded samples are not the uncompressed microphone
waveform. Digital full scale does not establish calibrated sound pressure.

The derived float64 WAV contains every decoded sample. Its separate frame CSV
retains original integer PTS ticks, rational time base, frame/sample boundaries
and residuals against the continuous sample clock. Sample zero means the first
retained decoded sample; the source timestamp origin can be negative. Codec
trimming is included in decoded frame counts and independently checked against
the actual complete output. Every frame must agree with its sample position
within one container time-base tick plus one sample period. This explicit
precision bound accommodates quantized container timestamps; it is not a
measurement of physical synchronization. A reset, missing timestamp, changing
rate/channel count or gap/drift beyond that bound refuses extraction rather than
concatenating a misleading continuous recording. Finer gaps cannot be ruled out
within the declared precision.

Implementation uses the documented exact stream selection and frame metadata
interfaces of [FFprobe](https://ffmpeg.org/ffprobe.html) and explicit PCM output
in [FFmpeg](https://ffmpeg.org/ffmpeg.html). Container-specific timing remains
subject to the [demuxer's format behavior](https://ffmpeg.org/ffmpeg-formats.html).
The request and result bind the original source SHA-256; executable versions
and hashes, NumPy/SoundFile/libsndfile versions and artifact hashes are retained.
The external executables are not bundled into the source repository.

Bounds:512MiB encoded source;64 container streams;64 audio channels;
1–384kHz sample rate;20million decoded channel values;500,000 decoder frames;
96MiB frame metadata; explicit child time/file/log limits. The initial continuous
profile refuses timestamp time bases coarser than10ms. It does not trim a long
recording automatically. No audio autoplay or biometric interpretation follows
from extraction.

## Executed worker evidence

`tests/audio-extract-worker.py` passes32 checks in external receipt
`../../work/test-runs/brohn-audio-extract-worker-20260924-03/results.json`.
The source fixtures are original analytic stereo tones and abstract test video;
no participant recordings or competitor material were used.

- All288,000 lossless PCM16 channel values agree exactly with the original
  integer samples divided by32768. Both channel order and sample counts survive.
- The Opus fixture matches an independent complete decoder output exactly and
  retains its trimming/quantized timestamp ledger, without claiming agreement
  with pre-compression PCM.
- MP4/AAC preserves its complete decoder-defined sample extent, including
  decoded padding, and matches a separate complete PCM decode. The command-line
  interface preserves the exact requested binding and rejects malformed requests.
- Explicit second-stream selection, video without audio, wrong/non-audio stream,
  source substitution, output collision and duplicate JSON keys are covered.
- An actual timestamp-gap container is refused. Independent frame cases check
  reset/missing/noninteger PTS, channel/rate/stream changes, drift, exact tolerance
  boundary, negative original time origin and unsupported coarse clocks.
- Complete frame/sample coverage, exported timestamp residuals, artifact hashes
  and unchanged original recordings are checked.

Attempt01 also passed28 checks; it exposed a Python test-string escape warning.
The test now uses an explicit raw string. Attempt02 additionally records native
audio-library identities and checks decoder/probe executable hashes again at
completion. Attempt03 adds AAC, boolean-selection and actual command-line cases;
the production worker remains unchanged from02. These checks do not establish
actual browser-camera extraction or scientific construct validity.

## Connected acceptance evidence

`tests/platform-audio-extraction.R` passes 26 domain checks in
`../../work/test-runs/brohn-audio-extraction-domain-20260924-03/results.json`.
This suite invokes the real decoder, but its synthetic publication envelopes
are explicitly marked as domain fixtures, not actual saved-worker publications.
It verifies absent study linkage, exact source/project ownership, two streams,
all 288,000 original PCM16 values through an independent RIFF reader, full frame
coverage, missing stream rejection and declared no-mixing/no-resampling policy.
Derived lineage cannot be stripped, erased, assigned another study, or injected
from a mapping form. Generic acoustic queue/input retain it and refuse changed
parent ownership or substituted lineage. Ordinary imported WAV behavior remains
unchanged; the earlier audio-review domain suite also passes its 28 checks at
`../../work/test-runs/brohn-audio-domain-20260924-06/results.json`.

`tests/researcher-audio-extraction.mjs` completes all 22 connected checks and
four accessibility/reflow scans in
`../../work/test-runs/brohn-audio-extract-browser-20260924-01/browser-1790225640320/results.json`.
Each scan has zero axe violations and no page overflow at desktop width 1440
or mobile width 390. Final desktop track selection and mobile camera derivation
screenshots were visually inspected. Wider numerical tables scroll locally.

- The imported two-track source requires explicit selection. Its complete WAV
  download contains exactly the original 288,000 channel values, independently
  checked against generated integer PCM bytes; every frame-ledger row is
  downloadable. A forged token fails, and changing stream selection revokes the
  previous WAV URL immediately.
- Normal mapping and a real acoustic worker publish a report with exact parent
  video/extraction lineage. A real source-review worker then exposes the selected
  original channel's waveform/spectrum with the same lineage. This extension
  does not alter the saved acoustic scoring method.
- Keyboard cancellation publishes no inventory or derived data. Keyboard retry
  follows the replacement job ID. Video without audio has a clear unavailable
  state. An actual timestamp-gap container fails without producing falsely
  continuous audio.
- A real participant browser uses original generated video/audio as fake devices.
  General study consent alone causes no media-access call. Explicit camera and
  microphone consent precedes capture. The completed run is assembled, its actual
  audio stream is inspected, and its Opus recording is decoded to 210,240 samples
  at 48 kHz in one original channel. The derived record pins frozen consent,
  capture, run, study/protocol and assembled stream evidence. This verifies
  software behavior, not a physical microphone or human acoustic validity.
- A fresh researcher/worker process reopens the same derivation receipt and
  complete WAV without new jobs, changed original sources or altered acoustic
  reports. All jobs reach their intended terminal state, including cancellation
  and deliberate gap refusal.

The successful journey reused the already published lossless extraction from
the preceding attempt (the unchanged Python decoder was already independently
qualified), then ran fresh acoustic, source-review, no-audio, gap and camera
jobs. Its 1.89-second imported selection result is therefore a retained-result
reopen, not a fresh decode benchmark. The fresh camera extraction reached its
downloadable result in 13.21 seconds. This receipt does not measure a general
latency target for large sources.

`tests/platform-audio-extraction-publication.R` adds seven actual-worker
revocation checks in
`../../work/test-runs/brohn-audio-extract-browser-20260924-01/publication-01/result.json`.
After a fresh acoustic calculation, an in-process test callback deliberately
moves the parent source to another project immediately before commit. Publication
fails; no new report appears, original reports and video are unchanged, and the
catalog ownership change rolls back. The failed job remains in the external QA
workspace. No production function or source file is replaced on disk.

These receipts fingerprint the extraction domain
`1dc5daea334aa065dbc4bce78a6ca27a5cf33c2693ef6ada4068b23dff6a1329`,
extraction view module
`859496e42fc079827dafe8e4c5526ca57bea04461112501e8f992e5cfa534634`,
and Python decoder
`2d2691d982a1d0da562048355d73d5811a93a815fad58a8819ed1cd45f0ad40c`.
Full shared-source fingerprints are retained in the receipts. Subsequent changes
to shared job protection require their own focused verification; this evidence
does not silently qualify later source revisions.

## Retained failures and reproduction

Earlier browser attempts remain external. `browser-1790224816750` exposed an
ambiguous harness selector ("Stream 2" also matched "2 channels"); the harness
now selects the exact native stream index and asserts it. Attempts
`browser-1790224910416` and `browser-1790225243054` exposed and reproduced a real
mapping bug: Shiny converts an empty numeric input to logical `NA`, whereas the
shared mapping cleanup only removed numeric `NA`. The corrected cleanup removes
scalar missing values while preserving zero and false, with seven focused tests
through the actual installed Shiny input handler. No numeric sampling rate is
invented for the blank optional field. The successful journey above follows this
repair. All prior original media, source records and failed receipts remain.

Create a new external directory named `brohn-audio-extract-browser-*`, then run
the fixture's `setup` mode followed by the Node researcher harness. Ports 3923 and
3924 must be free. Use the repository's restored R library, compiled publication
guard, audio Python environment, FFmpeg/FFprobe, Chrome, Playwright and axe.
`tests/fixtures/audio-extraction-media.py` generates only original analytic
tones and abstract video. The harness starts and stops its own researcher,
participant and worker processes and places every media file, temporary local
participant token, screenshot and receipt outside the repository. Run the
publication-fault test separately after those processes and jobs are terminal.

The worker request has exact fields `schema`, `operation` (`inspect`/`extract`),
`binding`, `source_path`, `source_hash`, `selection` (null or exact `stream_index`),
and `output_directory`. Domain code supplies these from retained records. The
result contains track inventory, selected recording metadata and two artifact
manifests (`decoded-audio`, `audio-frame-ledger`); it is not a scientific score.
