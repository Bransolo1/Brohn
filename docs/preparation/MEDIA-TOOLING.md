# Vision, AOI and audio development tools

Prepared 2026-09-08. An isolated Python 3.12.10 environment at
`../../work/tooling/vision-audio-venv` contains **43 pinned packages**;
[requirements](../../scripts/readiness/requirements-media.txt). `pip check` passes.
No camera, microphone, person or external media was used. The model assets are
software downloads outside the repository, not recordings.

| Installed tool | Version | Prepared use and actual evidence |
|---|---|---|
| MediaPipe | 1.0.1 | CPU face, hand and body inference on blank synthetic frames; preserves no-detection results. Geometry/blendshapes are not calibrated gaze or FACS AUs. |
| EfficientDet-Lite0 | int8 artifact pinned by generation/hash | Object-detector execution and bounded return list. Its COCO label vocabulary supports generic object proposals, not arbitrary brands or text AOIs. |
| OpenCV contrib | 5.0.0.93 | Known contour bounds, image translation from optical flow, and GrabCut foreground on a two-colour synthetic fixture. |
| ONNX Runtime / Silero VAD | 1.29.0 / v6.2 commit `be95df9152c0d7618fa1edfeb296fc3dae32376f` | CPU recurrent inference and silence threshold probe at 16 kHz; no speech accuracy or transcription test. |
| Praat-Parselmouth | 0.4.7 | Known 220-Hz pitch extraction; supports further declared acoustic recipes. |
| librosa / soundfile | 1.0.0 / 0.14.0 | Analytic RMS comparison; audio feature/I/O dependencies available. No microphone capture. |

There are **17 passing media assertions**, including six cached-model hashes.
One additional attempted capability is explicitly unavailable in this environment:
MediaPipe 1.0.1's Windows DLL lacks `MpInteractiveSegmenterCreate`. The Python API
exists but cannot instantiate that task. This failure is retained in
[media-results.json](media-results.json), not counted as successful inference.

The working neural segmentation route is separately pinned **MediaPipe 0.10.21
+ MagicTouch v1** in [SEGMENTATION-TOOLING.md](SEGMENTATION-TOOLING.md). Its **six
checks pass**. Keep that environment separate: the versions have different task
APIs and dependencies. For that model, foreground category is **0** and background
is **255**; a generic nonzero-mask conversion would invert an AOI. GrabCut is also
available as an assisted-segmentation route. Both need research-stimulus accuracy
and correction-effort benchmarks before claims about automatic AOI quality.

## Downloaded artifacts and provenance

[media-models.json](media-models.json) records six official artifacts totaling
54,811,078 bytes: face, hand, pose-lite, EfficientDet-Lite0, MagicTouch v2 and
Silero VAD. A seventh, working legacy MagicTouch artifact is recorded separately
by the segmentation result. Google downloads retain provider generation plus
SHA-256; Silero retains a source commit plus SHA-256. Hashes were recorded from
the first official HTTPS download, not independently publisher-signed manifests.
Subsequent reads/downloads must match them. MagicTouch v2 remains a cached candidate
with the documented Windows failure; it is not the selected runtime.

These models/engines do not supply emotion recognition, rPPG or webcam screen-gaze
qualification by implication. The [facial provider plan](../methods/reuse/FACIAL-PROVIDERS.md)
retains Py-Feat and entitled Affectiva/FaceReader routes for AU/native-expression
outputs. Source frames, model results, source clocks and face-track IDs remain
separate. Preserve no-face/occlusion/poor-quality observations as missing rather
than a neutral expression.

## Reproduction

From the repository root in PowerShell:

```powershell
$mediaPython = '../../work/tooling/vision-audio-venv/Scripts/python.exe'
& $mediaPython scripts/readiness/prepare-media-models.py --model-dir ../../work/tooling/media-models --manifest docs/preparation/media-models.json
if ($LASTEXITCODE -ne 0) { throw 'Model integrity/download failed' }
& $mediaPython scripts/readiness/media-reference.py --model-dir ../../work/tooling/media-models --manifest docs/preparation/media-models.json --output docs/preparation/media-results.json
if ($LASTEXITCODE -ne 0) { throw 'Media reference mismatch' }
```

The result status remains `passed_with_unavailable_capability` while the v1.0.1
task is unavailable; read its capability field, not just the process exit code.
The separate segmentation command is in its own tool document. Do not upgrade
one worker's packages to satisfy another. Model weights and all synthetic media
caches remain under `work`, outside Git.

## Additional recipe requirements

Voice analysis must preserve sample rate/channel/gain, voiced support, clipping,
VAD state/context and segment boundaries. Define pitch range, intensity reference,
window/hop, jitter/shimmer/HNR algorithms and voiced-only denominators explicitly.
Do not treat an acoustic descriptor as a stress or emotion label. Speech activity
is not a transcript, and speaker diarization is a separate model task. Optional
transcription requires a versioned language/model adapter and permissioned inputs.

Pose/hand processing requires coordinate frames, visibility/tracking quality and
frame timestamps. Motion summaries use a declared body reference and camera setup;
normalized image motion is not calibrated physical velocity. Optical flow can
help propagate a reviewed AOI, but requires drift/loss detection and correction.
Object detection, assisted segmentation, OCR and open-vocabulary AOIs stay distinct
model capabilities within the master architecture.

Primary sources: [MediaPipe face](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker),
[pose](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker),
[hand](https://developers.google.com/edge/mediapipe/solutions/vision/hand_landmarker),
[object detection](https://developers.google.com/edge/mediapipe/solutions/vision/object_detector),
[interactive segmentation](https://developers.google.com/edge/mediapipe/solutions/vision/interactive_segmenter).
The executed Python interfaces are pinned because current guides and installed
releases differ. Acoustic and voice references:
[Parselmouth](https://parselmouth.readthedocs.io/en/stable/),
[librosa source](https://github.com/librosa/librosa),
[Silero source and ONNX guidance](https://github.com/snakers4/silero-vad/tree/be95df9152c0d7618fa1edfeb296fc3dae32376f).
Inspect package and model licences separately before bundling; use the existing
facial/provider and platform records for their distinct terms.
