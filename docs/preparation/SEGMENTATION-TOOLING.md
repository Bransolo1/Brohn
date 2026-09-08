# Brohn interactive segmentation fallback

Prepared 2026-09-08. The isolated fallback installs and executes successfully;
six synthetic output-contract checks pass and `pip check` reports no broken
requirements. The Windows MediaPipe 1.0.1 preparation encountered
`AttributeError: function 'MpInteractiveSegmenterCreate' not found` while creating
the interactive segmenter. Its Python wrapper calls that native symbol; changing
an input image or a model path does not supply a missing DLL entry point. Keep the
working face/pose/hand/object environment unchanged.

The bounded fallback attempt selects **MediaPipe 0.10.21 + MagicTouch v1 float32**
in a separate `../../work/tooling/segmentation-venv`. This pairing is grounded in
the official version-tagged README, which links that exact model family/version,
and the same release's Python interactive-segmenter tests. It is not an attempt
to feed the newer MagicTouch v2 `.task` bundle into an older implementation.
[Versioned model example](https://github.com/google-ai-edge/mediapipe/blob/v0.10.21/mediapipe/tasks/web/vision/README.md),
[versioned Python API tests](https://github.com/google-ai-edge/mediapipe/blob/v0.10.21/mediapipe/tasks/python/test/vision/interactive_segmenter_test.py).

## Exact assets and API

- Python 3.12 Windows AMD64 wheel: `mediapipe==0.10.21`.
- Explicit compatible pins: `numpy==1.26.4`, `opencv-contrib-python==4.11.0.86`,
  `jax==0.4.35`, `jaxlib==0.4.35`. Full resolved versions are in
  [requirements-segmentation.txt](../../scripts/readiness/requirements-segmentation.txt).
- Model: `interactive_segmenter/magic_touch/float32/1/magic_touch.tflite`,
  downloaded from the official Google model bucket, **6,227,884 bytes**.
- Generation: `1683146867404767`.
- SHA-256: `e24338a717c1b7ad8d159666677ef400babb7f33b8ad60c4d96db4ecf694cd25`.
- Cached model: `../../work/tooling/segmentation-venv/models/magic_touch_v1.tflite`.
- Creation uses `interactive_segmenter.InteractiveSegmenter.create_from_options`
  with `BaseOptions.Delegate.CPU`, category and confidence masks enabled.
- The prompt is `RegionOfInterest.Format.KEYPOINT` with a normalized x/y point;
  output is selected-object/background segmentation.

**Use the selected model's actual encoding:** MagicTouch v1 supplies **one**
foreground-confidence mask. Its native category mask uses **0 for foreground and
255 for background**, with a foreground cutoff strictly greater than 0.5 in the
upstream single-channel calculator. Convert to Brohn's boolean mask using
`category_mask == 0`; treating nonzero pixels as the AOI would invert the result.
An initial probe assumed two channels and 0/1 categories, failed, and was corrected
only after checking the versioned C++ implementation. This distinction is retained
in the result record. Other models can have different label conventions.
[Pinned category-mask implementation](https://github.com/google-ai-edge/mediapipe/blob/v0.10.21/mediapipe/tasks/cc/vision/image_segmenter/calculators/tensors_to_segmentation_calculator.cc#L165).

No model weights are in the repository. The parent media environment and its
model manifest were not modified. Package/model versions and the official HTTPS
download generation are recorded in [segmentation-results.json](segmentation-results.json).

## Build use

Expose this as an optional isolated **click-to-propose AOI** engine. Supply the
immutable stimulus hash, decoded image dimensions and normalized prompt point.
Return the mask, model identity, prompt and image-to-stimulus transform. Convert
the mask to editable polygons, preserve holes/components under an explicit rule,
and let the researcher confirm the intended region. Mask confidence does not
provide an AOI name or establish a scientifically meaningful region.

The synthetic reference uses a 320 by 240 image created in memory with a colored
rectangle. It checks pinned versions/model bytes, successful CPU execution,
category shape/type/IDs and confidence shape/range. It does **not** measure
segmentation accuracy on products, text, moving objects or researcher-defined
AOIs. No image, video, camera or microphone data is downloaded or recorded.
The model's documented use is interactive object/background segmentation;
semantic labels and temporal tracking require separate components.
[MagicTouch model card](https://storage.googleapis.com/mediapipe-assets/Model%20Card%20MagicTouch.pdf).

Manual rectangular/polygon AOIs remain available. OpenCV GrabCut supplies an
additional local rectangle/scribble-guided proposal route already being exercised
in the main media preparation. Neither proposal engine should silently replace
a reviewed AOI after a stimulus or model revision.

## Reproduce

From the repository root, create a fresh Python 3.12 virtual environment at the
isolated path, then:

```powershell
& ../../work/tooling/segmentation-venv/Scripts/python.exe -m pip install -r scripts/readiness/requirements-segmentation.txt
& ../../work/tooling/segmentation-venv/Scripts/python.exe -m pip check
& ../../work/tooling/segmentation-venv/Scripts/python.exe scripts/readiness/segmentation-reference.py
```

For a missing model cache, download the
[generation-pinned official model](https://storage.googleapis.com/mediapipe-models/interactive_segmenter/magic_touch/float32/1/magic_touch.tflite?generation=1683146867404767)
outside the repository. The script refuses a mismatched SHA-256. `--model` and
`--output` accept explicit local paths. Do not upgrade this optional worker by
changing just one of its pinned model, package or NumPy compatibility settings;
test a new complete combination and record a new engine identity.
