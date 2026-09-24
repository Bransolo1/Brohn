# Saved-video geometry resource acceptance

24 September 2026. This is a measured software resource and exact-data test of
the current saved-video explorer. It does not qualify video acquisition, model
inference, facial expressions, attention or emotion interpretation.

## Current implementation and retained source

The earlier successful `brohn-vision-limits-native-02` receipt recorded worker
SHA-256 `fb3fcd74ed0d89770ded577c4a0974a4d8ae9fef237709cf3b24266522cb9ec8`.
It was retained as historical evidence, rather than reused as proof of the
current worker. The new run executed and independently rechecked:

`scripts/workers/vision_explorer.py` SHA-256
`c0c02ca4e3c18450090d908ca96160190b365cf82183c93dcda4d05931533271`.

The original synthetic `complete.jsonl` remains at
`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-vision-limits-native-01`.
The test read this source without copying or regenerating it. A fresh request,
derived index and results were written to
`C:/Users/User/Documents/Codex/2026-09-05/make/work/test-runs/brohn-vision-limits-native-20260924-01`.

The source is 2,140,382,779 bytes, close to the 2 GiB accepted source bound, with
the maximum 36,000 accepted frames and 58 native metrics per frame. Every frame
contains one face with 478 landmarks, one pose with 33 landmarks and two hands
with 21 landmarks each. Long exact numeric tokens make the stream large without
inventing extra frames. This is the native-width success case; it does not
establish that every combination of the separate 128-metric and source maxima
fits the 256 MiB index cap.

## Executed results

The existing `tests/workers/vision_explorer_limits.py` reuse path completed with
exit 0 and all three resource/response checks. The new independent
`tests/workers/vision_explorer_resource_review.py` completed with exit 0 and
17 checks against the retained output and original source.

| Measurement | Current result | Bound or independent expectation |
| --- | --- | --- |
| Complete source frames | 36,000 | 36,000 maximum accepted frames; source lines and SQLite rows independently counted |
| Native metrics / metric values | 58 / 2,088,000 | Every metric present for every frame; independently queried from SQLite |
| Derived index | 105,435,136 bytes (100.55 MiB) | Below 256 MiB; complete manifest and actual file size agree |
| Build interpreter peak working set | 31,649,792 bytes (30.18 MiB) | Below 192 MiB |
| Build interpreter peak commit | 22,814,720 bytes (21.76 MiB) | Below 192 MiB |
| Resource-run elapsed time | 269.063 seconds | Observed on this development machine; not a speed guarantee |
| Plot support | 36,000 valid frames, 359.99 seconds | Adjacent endpoint intervals; no final-frame extrapolation |
| Plot display | 1,000 retained points, one valid fragment | At most 2,000 points; both first and last frame remain present |
| Plot response | 186,841 bytes | Below 2 MiB |
| Complete last-frame detail | 131,287 bytes | Below 2 MiB; native JSON byte-identical to the original final line |

The memory receipt is the **actual Python interpreter's Win32 lifetime peak**
from `GetProcessMemoryInfo` using its own current-process handle after the build.
It is not a sample of the small Windows virtual-environment launcher. The saved
`process-observation.json` independently identifies actual worker interpreter
PID 2432 (`Python312/python.exe`), launched through venv PID 18116. These are
historical process identities; both processes were confirmed absent after the
run. The peak measurement covers the build interpreter. Subsequent read-only
plot/detail review has explicit response bounds here, not a separately measured
memory-peak claim.

The independent audit streamed the entire original again after the worker,
counted all 36,000 lines and confirmed unchanged SHA-256:
`6cbd6c0d7b796595e96ba0d2377a8cde69109e2e3034d08617679d40badeb01e`.
It compares the final response's original JSON directly to that independently
read final line and compares all exposed numeric token strings using the Python
standard JSON parser. The final frame is 35,999, with exact original PTS
`9007199254741351.9900`, exact relative time 359.99 seconds and saved model time
359,990 milliseconds. The original PTS origin is above binary64's exact integer
range; the test checks its decimal preservation rather than accepting a rounded
floating-point reconstruction. Every displayed point retains the independent
fixture's 0.25 metric value and its exact source timing.

## Evidence and reproduction

The fresh external directory contains:

- `request.json`, `worker-result.json`, `index.sqlite` and
  `actual-runtime-memory.json`.
- `limits-evidence.json`, SHA-256
  `3ba73c25c8c2c2fcb3b9d55249e7d6a8a895a91c1814576006eb46186c638bcd`.
- `source-exactness-review.json`, SHA-256
  `d9843b1ee39cab4d6116480799f8c13a4af6353f09c46906a6cc0e8a706e7393`.
- `complete-plot.json`, `last-frame-detail.json` and the separate live process
  observation. The original 2.14 GB source remains only in its prior directory.

From the repository root on the prepared Windows development machine:

```powershell
$brohnResourceRun = '<new nonexistent external result directory>'
& ../../work/tooling/methods-venv/Scripts/python.exe -B tests/workers/vision_explorer_limits.py --folder $brohnResourceRun --case native-width --reuse-request 'C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-vision-limits-native-02/request.json'
& ../../work/tooling/methods-venv/Scripts/python.exe -B tests/workers/vision_explorer_resource_review.py --folder $brohnResourceRun --expected-worker-sha256 c0c02ca4e3c18450090d908ca96160190b365cf82183c93dcda4d05931533271
```

The first command refuses an existing output directory. The second audit
refuses to replace an earlier review receipt. The frozen expected worker hash
must match; changing the implementation requires a new measured run and new
evidence. Local runtimes and the large retained synthetic fixture are not
bundled with a fresh Git clone. No production code changed for this acceptance.
