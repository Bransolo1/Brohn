# Frozen clock UX checkout10 core regression

The existing configured seven-test core subset passed once on 27 September 2026 against `work/clock-ux-next-20260925/checkout-10`. No application or test source was edited, no accepted test was weakened, and no failed attempt or rerun was needed. The trigger was the changed shared `platform-jobs.R` / `analysis-worker.R` clock dispatch closure.

| Existing catalog test | Passed assertions |
| --- | ---: |
| core | 109 |
| store | 74 |
| delivery | 56 |
| run-evidence | 57 |
| backup | 30 |
| task-portability | 36 |
| task-import-platform | 46 |
| Total | 408 |

The imported-task test completed five actual supervised attempts: three expected report publications and two expected refusals of tampered saved references. Its source, store, job and artifact evidence remains under the runner's own external fixture directory. Each existing assertion and catalog deadline was preserved.

The actual unmodified `scripts/run-configured-checks.ps1` launched the actual `scripts/run-checks.R` and `qa-catalog.json` entries, using this folder's fresh `local-installation.json`. The configuration explicitly chooses `work/native-r/bin/x64/Rscript.exe`, restored `work/r-library-brohn-restore`, methods-venv Python for publication and portability, and `work/tooling/brohn-native/publication-guard.json`. The core launcher intentionally forwards no optional scientific profile environment variables; this subset does not need them. R is 4.6.1 and the actual invoking PowerShell is 7.6.5. The runner checked the required R lockfile and native publisher prerequisites before every selected test.

The configured workspace was a unique nonexistent placeholder and was never created. Each selected test created only its own synthetic fixtures. The delivery test's exact existing temporary HTTP subprocess was explicitly authorized by the parent after inspection: it binds `127.0.0.1`, chooses `httpuv::randomPort()`, and kills/waits its own child with an additional `on.exit` cleanup. No researcher app was launched, and no fixed 3970 or 3838 port was selected by this work.

The evidence root is deliberately short to preserve the previously qualified Windows path boundary:

`C:/Users/User/Documents/Brohn QA/c10-20260927-01`

The outer `results.json` records all seven passes, unchanged configuration bytes and unchanged launcher sources. Every child receipt verifies its test and 311 implementation files remained unchanged during execution. The independent preflight and closing inventory also matched all 390 source hashes from `checkout-10-receipt.json`, all 1,269 original non-cache files, all five exact synthetic import CSV byte/hash oracles, and the selected runtime/native guard bytes. The configured placeholder workspace remains absent. A narrow post-run process observation found no R or Python process with the unique evidence directory in its command line; this is not a claim about unrelated host processes.

All seven test stderr logs retain the same 188-byte startup warning: inherited `C.UTF-8` failed for four locale categories on this Windows host. No test failed. These warnings were retained; successful tests were not rerun merely to clear stderr.

The combined receipt is `acceptance.json`, SHA-256:

`b7c2d0db162dc65c7c72ed384ae9984391b119112b6483d0c0f16b81e8d7f63d`

This is a shared-core regression result using existing synthetic checks. It does not qualify physical devices, optional scientific comparators, browser journeys, user comprehension, latency, concurrent throughput or the complete product. Clock-specific component, supervised publication and researcher browser evidence remains separate.
