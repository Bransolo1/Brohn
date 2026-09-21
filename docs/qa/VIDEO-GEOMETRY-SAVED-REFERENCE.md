# Saved video geometry: actual model and supervised index reference

20 September 2026. **39 checks and six actual supervised jobs passed** across
face, pose and hand geometry. This establishes saved-source agreement and the
tested storage lifecycle. It does not establish model accuracy, physiological
measurement quality or the connected researcher interface.

`tests/fixtures/prepare-vision-reference.py` obtains three official
`google-ai-edge/mediapipe-samples` test images at commit
`c2518ec444c3a3a99689e5d31eddadc240c83a0c`. The upstream repository license,
image/video hashes, source URLs, encoding command and actual inference results
are retained outside the repository in
`oka/work/brohn-vision-references-01/reference-manifest.json`.
The source is static reference imagery, repeated into four lossless video
frames with presentation timestamps beginning at 2 seconds. It is not a natural
motion benchmark or a recording of a newly recruited participant.

`tests/reference/vision_saved_review.R` imports each video, saves its explicit
channel mapping, runs the existing production model recipe in a real child
process, publishes the immutable report, then queues and publishes a separate
complete observation index. All three reports retain four valid frames. Exact
source bytes, original PTS origin, encoded-pixel orientation and pinned model
hashes agree with the reference manifest. The saved provider environment is
MediaPipe 1.0.1; the report retains its full package and decoder identities.

For every report, an independent line read of its original JSONL artifact is
compared byte-for-byte, excluding the line terminator, with all four selected
frame-detail records. Two-row paging reaches the actual final frame. Plot
support retains all four frames and explicit metric units. Each native index
and its publication receipt reopens after the store closes. Original report
hashes and original observation artifact hashes remain unchanged.

The native source-guard control removes the ordinary Windows read-only
attribute first. Writing the observation artifact succeeds before the index
job, fails at its publication boundary while the source guard is held, then
succeeds after release. This control does not infer a native guard merely from
an existing read-only file attribute.

Retained evidence:

- `oka/work/brohn-vision-saved-01/acceptance.json`: 39 checks, six jobs,
  source/report/index identities, model pins and reference attribution.
- `oka/work/brohn-vision-reference-index-02/results.json`: six earlier exact
  worker-reader comparisons, including every indexed metric's native token.
- `oka/work/brohn-vision-storage-04/results.json`: separate 22-check native
  storage and asynchronous verification lifecycle receipt.

The complete explorer's exact image binding, overlays, browser interaction and
export acceptance remain separate work under
[the explorer contract](VIDEO-GEOMETRY-EXPLORER-CONTRACT.md). Native blendshapes
remain model coefficients. Image-plane geometry does not acquire an emotion,
attention, calibrated gaze, physical joint-angle or rPPG interpretation.
