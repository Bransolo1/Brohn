# Optional local facial AU and native-expression provider

Status, 24 September 2026: the optional provider and connected researcher route have executed source/clock/output-agreement and full browser evidence. Researcher mapping, source-bound jobs, immutable publication, native-result UI, complete downloads, saved-result restart and optional installation/doctor hooks are implemented. A small installation-status wording correction has separate focused evidence; processing is unchanged. Existing MediaPipe geometry/blendshape recipes and their saved results are unchanged. See [acceptance evidence and limits](../qa/FACIAL-EXPRESSION-ACCEPTANCE.md).

## Selected route and model terms

Brohn selects Py-Feat **2.0.0**, `Detectorv1(face_model="retinaface", landmark_model="mobilefacenet", au_model="xgb", emotion_model="resmasknet", identity_model=None, gaze_model=None, device="cpu")`. The publisher identifies these four modular models as MIT-licensed. This is the publisher's model-licence declaration, distinct from the package licence. The landmark model's sparse HuggingFace card does not itself contain a licence field; the explicit model licence comes from the publisher's model documentation and linked upstream provenance. [Py-Feat model licences](https://py-feat.org/pages/models/), [package licence at v2.0.0](https://github.com/cosanlab/py-feat/blob/v2.0.0/LICENSE).

| Component | Selected artifact | Pinned HuggingFace revision | SHA-256 |
| --- | --- | --- | --- |
| RetinaFace ResNet34 | `model.safetensors` | `2e4495d934ed359ae8ddc0946d82f85e1e328e52` | `f339890a869284bb39dc16ed6f52acc21d74a73d6e419088697e46ee0b54eaf2` |
| MobileFaceNet landmarks | `mobilefacenet_model_best.pth.tar` | `dbb61907988fc8f82b0d0316b07fde520f6c7cc4` | `b994af026bfddbafc507a6f1c8737a9896bab20ed2b0cfb6ae90b81736970313` |
| XGBoost action units | `xgb_au_classifier_v2.skops` | `e81d0d6b0dd2b0d66e89fbf95a635101aae18a9a` | `d21a2a4977fce0924c557835d17414ac588e30b68248549244313ebfd3864881` |
| ResMaskNet categories | `ResMaskNet_Z_resmasking_dropout1_rot30.pth` | `13cf04b102169d7c5fe872adc43b549bf40f67c7` | `1aa0454662df6c59ab8bc4db80a25be5a109acfda970d32e7593cde2d3aeae68` |
| ResMaskNet configuration | `config.json` | same ResMaskNet revision | `1e0727d5c9a7b512a42461a1a955f2cf949f967feeefd858532025cf7e54c6e2` |

Weight digests come from the pinned publisher Git-LFS pointers; the small configuration digest comes from the first official pinned HTTPS retrieval. The [checked-in asset manifest](../../scripts/readiness/facial-models.json) records sizes, URLs and model-card links. Actual model bytes stay outside Git. [RetinaFace model card](https://huggingface.co/py-feat/retinaface_r34), [XGB model card](https://huggingface.co/py-feat/xgb_au), [ResMaskNet model card](https://huggingface.co/py-feat/resmasknet).

`Detectorv2`, ArcFace, FaceNet, img2pose, gaze and pose-MLP weights are excluded. Detectorv2 and ArcFace weights have noncommercial restrictions; turning identity off in Detectorv2 would not make those weights the selected modular profile. Py-Feat v1 attempts a separate pose-MLP lazily, even with RetinaFace. Brohn permits only the five selected local asset files, refuses unregistered local pose weights, and leaves that auxiliary branch unavailable. No pose estimates, identity embeddings or gaze values are exported. Native prediction code is unmodified; the adapter replaces model-file resolution with the pinned local allowlist. [Current official model distinctions](https://py-feat.org/pages/models/).

## Optional installation boundary

The prepared isolated runtime uses Python 3.12.10, Py-Feat 2.0.0, CPU PyTorch 2.11.0, torchvision 0.26.0 and TorchCodec 0.11.0. Sixty resolved packages are pinned in [requirements-facial-au.txt](../../scripts/readiness/requirements-facial-au.txt); `pip check` passed. Py-Feat wheel SHA-256 is `47e24b3dfd29c6ec626e7b7339240ec298e2c5d04fb686d015c1d1aa8ed92d98`. The runtime manifest additionally pins 75 installed Py-Feat source files. [PyPI 2.0.0 release](https://pypi.org/project/py-feat/2.0.0/), [TorchCodec version compatibility](https://github.com/meta-pytorch/torchcodec/blob/v0.11.0/README.md).

Py-Feat imports TorchCodec eagerly, including for a tensor/image call. The first import failed with the machine's existing static FFmpeg 9. TorchCodec 0.11 requires shared FFmpeg 4–8 DLLs on Windows. A separate **8.1.3 LGPL shared** build, dated 23 September 2026, fixes that concrete dependency. The archive is from BtbN, a provider linked by FFmpeg's official download page. Archive SHA-256 `60a055792e88524db437a78c2fcd4471536abf3b30d34fae1249591c00e13432`; all ten native files are pinned. No system PATH or existing profile is changed. Its included notices/source references stay with the optional installation. [FFmpeg Windows providers](https://www.ffmpeg.org/download.html#build-windows), [pinned BtbN release](https://github.com/BtbN/FFmpeg-Builds/releases/tag/autobuild-2026-09-23-14-55).

Prepare a fresh environment outside the repository using the pinned requirements and existing wheel-only installation pattern, then explicitly download/verify the model and DLL assets:

```powershell
& $python312 -I -m venv $newFacialEnvironment
& "$newFacialEnvironment/Scripts/python.exe" -I -m pip install --only-binary=:all: --no-deps -r scripts/readiness/requirements-facial-au.txt
& "$newFacialEnvironment/Scripts/python.exe" -I -m pip check
& $python312 scripts/readiness/prepare-facial-models.py --destination $newModelDirectory
& $python312 scripts/readiness/prepare-facial-ffmpeg.py --destination $newSharedRuntimeDirectory
```

The existing installer also accepts `scripts/install-python-profiles.ps1 -Profiles facial-au`. Download/verify the pinned model and shared-runtime assets separately using the preparation commands above. Configure the three external locations through `scripts/configure-local.ps1` or `scripts/setup-local.ps1` alongside the other required installation arguments:

```powershell
-ScientificProfiles @{'facial-au' = "$newFacialEnvironment/Scripts/python.exe"} `
-RuntimeAssets @{facial_models = $newModelDirectory; facial_ffmpeg = $newSharedRuntimeBinDirectory}
```

`facial_ffmpeg` is the extracted `bin` directory, not the archive or its parent. Saved configuration requires both runtime-asset directories when the facial profile is selected. Existing configurations without this optional profile remain compatible. `scripts/doctor.R --profiles facial-au` checks the optional installation.

Executed dependency/model/runtime checks and local-configuration replacement/launcher/environment-restoration evidence are recorded in [facial runtime acceptance](../qa/FACIAL-RUNTIME-ACCEPTANCE.md). Installation readiness is separate from model or research-method validity.

For an explicitly managed process, the same bindings are `BROHN_PYTHON_FACIAL_AU`, `BROHN_FACIAL_MODEL_DIR` and `BROHN_FACIAL_FFMPEG_DIR`. Normal local startup scopes/restores these environment bindings from saved configuration. Current prepared paths are `../../work/tooling/facial-au-venv`, `../../work/tooling/facial-au-models` and `../../work/tooling/facial-ffmpeg/ffmpeg-n8.1.3-win64-lgpl-shared-8.1/bin`. These local paths are preparation evidence, not portable defaults or a deployment claim. No participant video is downloaded or sent to a model service.

## Worker and product contract

Run `scripts/workers/facial_expression.py --request REQUEST --output RESULT` in the isolated profile. The strict request schema is `brohn-facial-expression-request/1.0` with `source_path`, `source_hash`, existing separate `output_directory`, and `metadata`:

- `profile`: `facial_au_expression_pyfeat_v1`.
- `origin_statement` and `consent_statement`: explicit researcher statements, both required. A statement is not independently verified consent; the connected app must preserve the relevant study/capture basis.
- `start_s`: nonnegative decimal string, default `"0"`; `end_s`: decimal string or `null` for the last original frame.
- `frame_stride`: integer 1–120, default 1. The source window is selected first, then every declared Nth included frame is analysed. Skipped frames are counted and carry no invented detections.
- `max_support_gap_s`: finite 0.001–10, default 0.25.

Current bounds are 512 MiB source, 600-second original video, 4K pixel area, and 2–300 analysed frames. The worker refuses excess work with a window/stride action instead of silently sampling or truncating. This is an initial CPU execution bound, not a demonstrated throughput/capacity promise. Original encoded pixels are analysed without crop, resize or autorotation.

Result schema `brohn-facial-expression-result/1.0`, kind `facial_expression`, contains source identity, engine/assets/packages, effective parameters, quality, 27 explicit native features, a first-50-frame preview and two complete artifacts: `facial-observations` JSONL and `facial-values` CSV. Paths exist only in the staged artifact manifest; normal publication must replace those with sealed object references.

Every frame retains its original integer PTS string, rational source time base, the original FFprobe printed PTS, exact rational source/relative times, source frame index and decoded-RGB hash. Integer PTS is authoritative; no FPS reconstruction or inference-completion timestamp substitutes for it. Duplicate/reversed PTS, ambiguous rotation/aspect and inconsistent decoded frame counts are refused.

Detected faces retain per-frame ordinal, native pixel bounding box, detector score, 20 named AU scores and the seven native categories `anger`, `disgust`, `fear`, `happiness`, `sadness`, `surprise`, `neutral`. Native names remain visibly identified as model outputs. A true numeric zero remains zero. No-face placeholders become an explicit `no_face` row with no face measurements, never a neutral expression. Partial native missingness remains null. Multiple faces retain separate per-frame outputs and a `multiple_faces` state; they are excluded from recording summaries. A seventeenth detected face refuses the result rather than publishing a partial count.

Aggregate values use only valid single-face sampled frames. Frame means disclose their denominator. Time-weighted means use adjacent eligible endpoints within the stated gap cutoff, with exact rational duration accounting and no last-frame extrapolation. No-face/multiple-face states break support. A per-frame ordinal does not track identity; even successive single-face frames do not establish that the same person remained present.

The selected XGB output is an AU model score, not a FACS intensity annotation. AU07 has a different decision objective and can behave differently from the other AU scores. Category softmax scores describe classifier output, not a measured internal emotion, happiness, attention or preference. Existing questionnaire answers stay a separate measure. [Native AU scoring note](https://py-feat.org/pages/models/), [original Py-Feat research paper](https://link.springer.com/article/10.1007/s42761-023-00191-4).

## Executed evidence and next connected gate

Evidence lives outside Git under `../../work/test-runs/`:

- `brohn-facial-contract-20260924-01/results.json`: **12 independent stdlib checks** for strict source/consent inputs, exact decimal/int64 clock handling, zero/missing/multiple/partial states, capacity, disabled branches and support denominators. SHA-256 `3d4a7940fa5ce83ebfa207f268af4f6d825265f44985b17ade17f576f7680d89`.
- `brohn-facial-native-20260924-01/results.json`: **nine actual worker/native agreement checks**, SHA-256 `e41c071fcee9c644b15fc68ac2a5e84631e6631f57cc92e6fe5a552204e9e18e`. A permitted upstream test still is explicitly resized/composed into blank/single/single/multiple/blank/single fixture frames. Lossless video PTS are independently authored as 2000, 2040, 2110, 2310, 2710, 2910 at time base 1/1000. All decoded RGB hashes match those composed frames. The actual worker returns two no-face, three single-face and one multi-face state; eligible adjacent duration is exactly 7/100 seconds.
- Every exported face bbox, detector score, AU and category value exactly matches separately instantiated public `Detectorv1.detect` calls, without invoking Brohn's frame conversion or summary functions. All 27 means and time-weighted means reconcile to those independent native values. Six complete JSONL frames and seven CSV rows retain original source identity. Worker elapsed time was about 39.44 seconds for this six-frame fixture; this single execution is not a load benchmark.

Original synthetic video SHA-256 `251248e52a49b17a258e59ce31b27b5a05ff0bdc39f116e355c1959a09f0bf6c`; complete JSONL SHA-256 `c0e6ccfceabd67c0d7487b2f8ad7aa561180b2e426998ddb4cf64460de8fd589`; CSV SHA-256 `a8cb001ea72852663ee6e88a31c6b2e84406e17eb8b9eecf76bf6b9c2d19fbb1`. The fixture records the original Apache-2.0 upstream test image and its exact commit/hash. No new person is recorded, no recognition identity is extracted, and no actual-model accuracy claim follows from repeated reference imagery.

The earlier missing-DLL import failure and first native still probe remain at `../../work/tooling/facial-provider-investigation/`. The package emits an XGBoost serialized-model compatibility warning while loading the publisher's pinned v2 artifact; the actual reference run above executes successfully and keeps that warning in the attempt logs. No model is silently converted, retrained or replaced.

The connected application now preserves explicit researcher selection/permission/source metadata, guards the original video during processing, pins the worker, existing `vision.py` inspector and all three runtime/asset/requirements files, and validates the complete JSONL/CSV before immutable publication. Its readable report keeps native categories separate from psychological claims. Exact CSV downloads include all faces and missing-frame placeholders; the summary CSV contains the 27 aggregate measures. See [connected acceptance evidence](../qa/FACIAL-EXPRESSION-ACCEPTANCE.md) for the current browser gate and remaining qualification limits. No device/accuracy/clinical/multi-user sign-off follows from the provider receipt.
