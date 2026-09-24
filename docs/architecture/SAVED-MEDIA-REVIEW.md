# Saved facial and original-container media review

24 September 2026, resumed after checkpoint `2b3b31a`. Complete saved facial
review now has [connected acceptance](../qa/FACIAL-REVIEW-ACCEPTANCE.md).
Original-container video/audio review now has [gap/export/restart acceptance](../qa/MEDIA-SOURCE-REVIEW-ACCEPTANCE.md).
This continues PC05/PC12 and preserves earlier reports.

## Shared recorded pixels

`scripts/workers/media_pixels.py` prepares one exact source frame by sequential
decode index within an explicit original video stream. It never seeks by rounded
seconds or assumed frame rate, reruns a model, rotates, mirrors or rescales.
Its standard-library PNG encoder preserves decoded RGB bytes. The caller owns
the verified complete PTS/dimension ledger, decoder compatibility, original
source/permission authority and held source guards.

The helper accepts explicit local paths and the source SHA/size, absolute stream
index, dimensions and frame index. Facial review additionally requires the exact
saved decoded-RGB SHA. It returns a PNG descriptor, RGB SHA, decoder binary SHA,
stream/frame identity and decode policy. Source and decoder bytes are checked
before decoding and after image preparation; an existing output is never replaced.

Bounds are 512 MiB source, 36,000 source frames, a 3840×2160 pixel-area ceiling
(portrait orientation is also supported), 32 MiB PNG,
64 KiB decoder errors and a maximum 120-second preparation deadline. A watchdog
kills a blocked decoder; the parent supervised job retains overall cancellation
and process-tree cleanup. Artifacts are prepared in an owned directory and only
the ordinary guarded job publisher makes them durable workspace objects.

`tests/workers/media_pixels.py` passes 23 checks at
`work/test-runs/brohn-media-pixels-20260924-02/results.json`. A lossless original
two-stream video contains independently authored distinctive pixels. An
independent PNG decoder verifies every selected pixel. Wrong source/size/RGB,
missing indices/streams, invalid bounds, duplicate output and a source change
during PNG preparation refuse publication. Real injected child processes exercise
timeout/error-overflow cleanup. The earlier 21-check receipt remains at `-01`;
`-02` moves the final byte checks after PNG creation and adds that late-mutation
case. No physical camera, model inference or timing validity is implied.

Actual facial publication then exposed a Windows path-length failure: the
temporary image fitted its nested job path, but a final name containing the
full SHA did not. The helper now uses `recorded-frame.png` inside its already
owned single-frame job directory. The descriptor retains the complete SHA;
atomic no-clobber publication and temporary cleanup are unchanged. The current
`-03/results.json` receipt passes 25 checks, including real file I/O in a
210-character directory and independently decoded exact pixels. This is a
practical nested-path correction, not support for arbitrarily long Windows paths.

## Facial review

Index the complete saved native JSONL and CSV with exact report, dataset,
processing settings and original-camera authority. Use the saved rational PTS,
native fields and frame-local face ordinals. Show actual eligible sampled points
and explicit absent/multiple/invalid/gap states. The original scientific means
and reports remain unchanged when the display window changes.

Frame images must match the previously recorded RGB hash using the original
compatible decoder. Viewing saved observations requires no model weights or
Py-Feat inference. Complete numeric exports and exact-frame images preserve
their source identity; matching face ordinals across time never establishes
person identity. Named native categories do not establish feelings or attention.

The cursor settles for 500 ms before complete-row lookup and frame preparation.
One automatic frame job may be pending per view; subsequent keyboard choices
coalesce to the latest selection without cancelling shared jobs. The old image
clears immediately. The standalone labelled figure retains responsive chart
geometry, readable labels and exact source details at 320/390/1440 pixels.

## Video beside a derived acoustic report

Begin from an existing saved audio-review window with verified extraction
lineage to one original video container. Reuse the actual audio-frame PTS ledger:
map a selected sample using its containing frame's PTS plus its within-frame
sample offset/rate. Retain the nominal first-PTS sample clock and its original
residual separately. Inspect an explicitly selected video stream and preserve
all original frame PTS/durations, gaps and overlaps.

Only an actually supported frame may contain the cursor. Unknown duration
supports exact PTS only; no nominal-FPS duration is invented. Show quantization,
mapping precision and boundary context without presenting them as measured
physical synchronization uncertainty. Export the complete frame/mapping ledger
and unchanged selected audio samples. This does not align unrelated EEG/EDA or
camera recordings; those need a separately reviewed clock-mapping contract.

## Integration and acceptance

R owns original source authority, selection, immutable entities and job receipts.
Bounded isolated workers prepare indices, mappings and images. The shared report
and audio-review entry points expose these views, with fresh permission checks
on every selection, saved reopening and download. Historical reviewed artifacts
retain their original implementation identity; new jobs require current code.

The linked acceptance records independently check complete numerical/pixel
exports, missing/gap/multiple-source states, stale/revoked access, cancellation
and actual researcher navigation through restart. Record every job and distinguish
display preparation from scientific inference. Root owns shared loader/app/job
wiring; facial and media workers own their dedicated modules and tests.
