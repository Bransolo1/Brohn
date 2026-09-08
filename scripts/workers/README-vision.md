# Vision evidence and supervised AOI proposals

`vision.py --request request.json --output result.json` is a local worker. It
downloads no models, opens no camera/microphone, and executes no user plugins.
Source bytes are SHA-256 checked before and after processing. Result schema is
`brohn-vision-result/1.0`; failed input produces `status: error` and exit code 2.

## Imported video

Use `../../work/tooling/vision-audio-venv/Scripts/python.exe`, MediaPipe **1.0.1**,
the pinned face/pose-lite/hand assets in
[the manifest](../../docs/preparation/media-models.json), and matching FFprobe /
FFmpeg executables on PATH (tested **9.0.1-full_build-www.gyan.dev**). Model bytes
stay outside Git. `BROHN_MEDIA_MODEL_DIR` can locate the same hash-checked cache.

```json
{
  "schema": "brohn-vision-request/1.0",
  "operation": "analyse_video",
  "source_path": "C:/local/immutable-recording.mp4",
  "source_hash": "<lowercase SHA-256>",
  "output_directory": "C:/local/job-artifacts",
  "metadata": {
    "profile": "face_pose_hands_v1",
    "start_s": 0,
    "max_support_gap_s": 0.25
  }
}
```

Profiles: `face_geometry_v1` (default), `face_pose_hands_v1`, or `custom_v1`
with an explicit unique `channels` subset of `face`, `pose`, `hands`.
`start_s`/`end_s` select a closed interval relative to the first source PTS.
Optional `max_support_gap_s` (0.001–10 s) defaults to 0.25. Other metadata keys
are rejected. The recipe accepts local MP4/MOV, Matroska/WebM and AVI containers;
remote protocols and playlist demuxers are excluded. Bounds are 512 MiB, 600 s,
36,000 decoded frames, 4K pixel count, and 2 GiB full observation artifact.
Non-square pixels, rotation metadata and changing dimensions require an explicit
upright source export first. Audio streams are ignored.

Two FFprobe passes count decoded frames and collect actual presentation PTS;
matching FFmpeg decodes the same selected video stream without FPS conversion or
autorotation. Missing/reversed/duplicate PTS, millisecond collisions, frame-count
mismatch and partial decoding fail explicitly. Original decimal PTS strings and
time base are retained; subtracting the first PTS with decimal arithmetic avoids
large-clock cancellation. MediaPipe VIDEO mode receives floored relative ms.
This is the file presentation clock, not a qualified acquisition/synchronization
clock. No nominal-FPS timestamp reconstruction is performed.

Full native normalized landmarks, presence/visibility fields, blendshapes,
per-frame masks and named geometry are written to a hashed JSONL artifact.
`observations` contains the first at most 2,000 **compact** frames, bounded to
2 MiB; it omits large landmark arrays. `artifacts` records path/hash/bytes for
the coordinator to preserve immutably before cleaning scratch space. All-frame
statistics are calculated before preview truncation. `features` gives frame
means, valid frame counts, adjacent valid time support, and trapezoidal time
means separately. No valid-to-invalid interval, long gap or final-frame duration
is imputed. Absent signals produce empty features and `insufficient_support`.

Faces/poses are detected up to two; multiple detections are masked from summary,
with saturated counts explicitly marked as lower bounds. Face border/nonfinite
geometry is masked; pose angles require joint visibility ≥0.5. Hand summaries
require unique model-native handedness within a frame. No face or person ID,
stable track, cross-frame physical velocity, metric depth or calibrated head
angle is inferred. Distances use isotropic image-plane coordinates divided by
image width; elbow angles use the 2D image plane. Results can be affected by
perspective, mirroring, occlusion and model error.

Blendshapes are native rendering coefficients. They are not FACS AUs, emotion,
happiness, attention, screen gaze or rPPG. CPU delegation is explicit; Brohn
does not add temporal smoothing, while native model internals/thread scheduling
remain those of the pinned implementation. Model/package/hash and decoder
versions are returned, with provider generation from the preparation manifest.

## Click-to-propose AOI

Use **the separate** `../../work/tooling/segmentation-venv/Scripts/python.exe`,
MediaPipe **0.10.21**, MagicTouch v1 SHA
`e24338a717c1b7ad8d159666677ef400babb7f33b8ad60c4d96db4ecf694cd25`.
The default cache is `../../work/tooling/segmentation-venv/models/magic_touch_v1.tflite`;
`BROHN_SEGMENTATION_MODEL_PATH` may locate identical bytes. Request keys are the
same, with `operation: "segment_aoi"` and exactly
`metadata: {"prompt": {"x": 0.5, "y": 0.5}}`.

Input must be an immutable opaque 8-bit grayscale, palette, RGB or alpha-variant
PNG within the 4K pixel bound. Palette entries expand to RGB and grayscale is
replicated into RGB in memory; fully opaque alpha is removed. Original source
bytes/hash and pixel geometry remain unchanged, and the conversion is recorded.
Transparent images require a frozen opaque background first. The native
MagicTouch foreground is **category 0**, background **255**. Brohn selects only
the 8-connected component containing the supplied prompt; it never guesses a
nearest/largest replacement. A prompt outside foreground returns `no_proposal`.
The result preserves holes in an exact binary PNG (Brohn foreground 255,
background 0). It includes normalized bounding box, pixel bounds, mask SHA,
component/discarded-area counts, confidence summary, image-border contact and
approximate contour/hole hierarchy. Contours use a 1 px simplification tolerance;
over 10,000 points they are omitted explicitly while the exact mask remains.
The rectangle includes area outside a nonrectangular mask.

The category/confidence arrays can disagree around boundaries: the pinned CPU
category path interpolates logits on an aligned-corner grid, whereas confidence
is activated before OpenCV linear resizing. We retain native categories and
report the disagreement count rather than rethresholding the confidence map.
This behaviour was checked against the
[versioned MediaPipe C++ implementation](https://github.com/google-ai-edge/mediapipe/blob/v0.10.21/mediapipe/tasks/cc/vision/image_segmenter/calculators/tensors_to_segmentation_calculator.cc).

Every proposal has `accepted: false`, `status: needs_review`, source/model
provenance, and an identity image-to-stimulus transform. The caller must show
the actual mask and let the researcher accept/edit it. Confidence supplies no
semantic AOI label or boundary-accuracy qualification. This worker never
overwrites reviewed AOIs or performs temporal propagation.

## Evidence and limits

```powershell
& ../../work/tooling/vision-audio-venv/Scripts/python.exe tests/workers/vision.py GeometryTests VideoTests
& ../../work/tooling/segmentation-venv/Scripts/python.exe tests/workers/vision.py SegmentationTests
```

Tests use original synthetic angle/distance/hand/face coordinates, known mask
bounds/holes/components, exact large-clock and irregular PTS, missingness and
time-denominator arithmetic, source-integrity/overwrite guards, ten original
VFR black frames through all three real models, and a generated two-colour
rectangle through real MagicTouch. Positive geometry fixtures exercise numeric
extraction; they do not establish real-person detection or construct validity.
No real person, camera or downloaded media is used. No natural-image AOI
accuracy, demographic robustness or live-device timing claim follows.
