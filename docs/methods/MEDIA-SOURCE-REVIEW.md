# Saved container media review

Profile `saved-container-media-review/1.0` joins original video pixels to an
existing video-derived acoustic source window. It never recalculates acoustic
measurements or infers an external EEG/EDA/device clock. The exact saved audio
review, original report, derived WAV, extraction receipt, original video,
consent lineage where applicable, and both frame ledgers remain distinct pinned
sources. Original scientific records remain immutable.

## Researcher route

From **Review original audio**, apply or reopen a saved audio window, then choose
**Review video with this audio window**. The original video track inventory is
prepared once with visible progress/cancellation; a saved exact inventory reopens
without another job. Choose an encoded video track and an audio position in
seconds. The position resolves to the nearest retained original sample; exact
half-sample ties move to the later sample. Inputs use at most nine decimal
places, must be inside the original half-open audio window, and cannot round
beyond its final retained sample. The exact resolved sample index is visible.

Apply the cursor to inspect an original recorded frame beside the unchanged
waveform. A missing or ambiguous source interval shows an unavailable state,
not a held frame. Changing either track or cursor hides the previous result and
revokes its image/CSV access. Saved reviews reopen after restart without scoring
or regenerating their saved source artifacts; current access and source bytes
are still verified. Advanced identity/clock details are separate from the
ordinary position control.

## Explicit clock mapping

The complete saved audio frame ledger supplies original integer PTS ticks,
rational time base, decoded sample boundaries and quantization residuals. For a
selected sample `n` in decoded audio frame `f`, the declared container coordinate
is exactly:

```text
container_time = f.pts_ticks * audio_time_base
               + (n - f.start_sample) / sampling_rate
```

The worker uses rational arithmetic, not binary64 subtraction of large native
ticks. It also retains nominal first-PTS-plus-sample time, the actual frame's
residual against that nominal clock, and the extraction's complete consistency
bound (one audio timestamp tick plus one sample period). Each video's original
time-base tick is separate. Boundary proximity is disclosed; these numerical
bounds describe retained timestamps and never establish measured physical
synchronization accuracy.

Every original audio ledger row is checked: contiguous sample coverage, original
frame ordinal, PTS monotonicity, time base, sample count, source-zero declaration,
residual and complete extent. No preview establishes a mapping.

The selected video stream is completely probed. The complete ledger preserves
frame ordinal, original PTS ticks, rational PTS, reported duration field(s),
unknown duration, gaps and overlaps. A supported image has a unique containing
half-open declared frame interval. With no positive reported duration, only that
frame's exact PTS is supported. Missing, duplicate or reversed PTS disable the
mapped frame. Overlapping candidate intervals do not arbitrarily choose pixels.
No duration is synthesized from a nominal frame rate or next frame's timestamp.

Frame pixels are decoded sequentially from the exact selected container stream,
without temporal seeking, rotation, rescaling or inference. The shared bounded
`media_pixels.py` helper retains original RGB24 digest, decoded count, decoder
hash and a deterministic PNG. Codec-decoded pixels are not a claim about a
pre-compression camera image or physical display timing.

## Sources, bounds and exports

The exact container/stream selection and full frame inventory use documented
[FFprobe interfaces](https://ffmpeg.org/ffprobe.html). Decoding uses explicit
stream mapping and passthrough frame handling through
[FFmpeg](https://ffmpeg.org/ffmpeg.html). Executable identity is preserved; native
binaries are not bundled into this repository.

Initial profile: 512 MiB original container; at most 64 total container streams
and indices 0-63; 36,000 decoded video frames; encoded pixel area no greater than
3840x2160 (portrait supported); 64 MiB probe metadata; 16 MiB complete video ledger;
32 MiB PNG. The original audio review remains bounded to two million selected
samples; the extraction retains its own 20-million-channel-value and 500,000-frame
bounds. Limits refuse complete unsupported sources rather than truncating them.

The visible timestamp table shows up to 100 rows and states its complete count.
Downloads retain the complete video ledger, original complete audio frame
ledger, byte-identical original selected audio sample CSV, exact PNG where
supported, waveform SVG with mapping metadata, and separate source/mapping JSON.
The waveform's existing display bins and source values are not replaced.

Worker publication uses native source read seals and transactional rechecks of
current ownership/source authority. Review opens asynchronously verify complete
source/artifact bytes while preserving native read seals. Image and download
requests recheck the live original audio selection, project/source authority,
current cursor and opaque URL capability. Closing/changing the source invalidates
the old URLs. Reading a historical saved mapping does not replace its preserved
implementation hashes with the currently installed helper.

The current saved-media chooser lists the latest 40 records for one saved audio
window. This is a bounded chooser, not a claim that every historical cursor has a
paged researcher route. Older records and their artifacts remain in the store;
pagination/search and a visible latest-40/total label are follow-ons. Opening a source with no listed inventory queues
a new bounded inspection rather than inferring tracks from earlier pixels.

## Scope limits

This is an original-container media/audio cursor review. It is not continuous
browser audiovisual playback, a drift-calibration editor, external signal
alignment, hardware timing qualification, face inference, speech/emotion
recognition or an acoustic rescoring method. Webcam-derived sources retain the
existing acquisition/consent gates; a separate imported fixture is not evidence
of new physical camera or microphone qualification.
