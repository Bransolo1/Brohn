# Configured core QA subset

This optional Windows QA profile runs seven existing checks from an arbitrary checkout and caller directory using an explicit local installation configuration. It does not open that configuration's saved research workspace. The [connected browser smoke](CONNECTED-PORTABLE-SMOKE-ACCEPTANCE.md) remains separate.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:/Brohn/source/scripts/run-configured-checks.ps1 -ConfigurationPath C:/Brohn/local/local-installation.json -OutputDirectory C:/Brohn/evidence/fresh-component-run
```

The final evidence directory must be new and its parent must exist. `-Test store` selects one reviewed check; in a PowerShell session `-Test store,delivery` selects those two. The default runs `core`, `store`, `delivery`, `run-evidence`, `backup`, `task-portability` and `task-import-platform`. The additive `configured_profiles.portable-core` metadata in [qa-catalog.json](../../scripts/qa-catalog.json) records exactly this reviewed scope and prerequisites. Existing suites, test IDs and the direct [run-checks.R](../../scripts/run-checks.R) command remain available.

The exact R lockfile library, publication Python and source-bound native guard are required for all checks because `run-checks.R` verifies them before execution. The task-portability check also uses the explicitly configured portability Python. No Node, browser, compiler or optional scientific environment is required by this subset. Windows PowerShell 5.1 is supported; this is not an added PowerShell 7 platform dependency.

The launcher resolves physical paths through Windows file handles, so junctions cannot redirect evidence into the checkout, saved workspace or supplied configuration/runtime paths. It refuses existing/overlapping destinations and unreviewed test IDs. Each child receives its own selected local runtime environment, private R user directory and temporary directory. Inherited Brohn and R settings are cleared only in the child; caller settings and configuration bytes are preserved. No hosted secrets or scientific profile settings are forwarded by this launcher.

Each selected check keeps its existing assertions and catalog timeout. The runner creates a fresh per-test evidence parent under its own external results directory and supplies `BROHN_QA_EVIDENCE_PARENT`. Imported-task acceptance retains its actual stores, jobs and artifacts there. The outer launcher bounds runtime preflight/receipt overhead separately; watchdog failure remains a failure. Cleanup targets only a launched process with the same PID/start identity and its descendants. All logs and failed receipts remain external.

Developer library overrides were removed only from the five selected test files that contained them. The core test already used the selected library; the imported-task test needed only its retained evidence parent changed. The five original task-portability fixtures are unchanged, with their assertion label corrected to say five selected profiles. SC-IAT and other separately accepted profiles are not silently added to this fixture.

Every other catalog entry remains outside this portability qualification. Optional external `implicitMeasures`, `saccades` and MaxDiff comparisons retain their original tests and source/version checks. Their absence is not silently counted as passing this configured subset. The [next-steps audit](PORTABLE-CATALOG-NEXT-STEPS.md) records the broader dependency work.

## Qualification evidence

Qualified on 24 September 2026 under actual Windows PowerShell **5.1.26100.9444** and the explicitly configured R 4.6.1/library/publication runtimes. The evaluation checkout was a separate fresh clone of `2b3b31a2eee67aaea64d57c2586695c2591a525c` plus the exact accepted integrated overlay (`4e26b2ba6ef9a8230a5afdbc5077c229e68a8625c4124fa8d94d1045a2f1006c`), followed only by these QA changes. The original accepted connected-smoke clone remained unchanged. Execution used an unrelated `separate caller` directory and deliberately wrong inherited Brohn/R settings; the selected configuration won in child processes while caller settings remained unchanged.

The **408 component assertions** comprise seven accepted test receipts, with targeted follow-ups rather than a fabricated all-in-one clean pass:

| Existing check | Assertions | Accepted external run |
| --- | --- | --- |
| `core` | 109 | `C:/Users/User/Documents/Brohn QA/20260924-01/checks/core/results.json` |
| `store` | 74 | `20260924-01/checks/store/results.json` under the same parent |
| `delivery` | 56 | `20260924-01/checks/delivery/results.json` |
| `run-evidence` | 57 | `20260924-01/checks/run-evidence/results.json` |
| `backup` | 30 | `20260924-02/checks/backup/results.json` |
| `task-portability` | 36 | `20260924-01/checks/task-portability/results.json` |
| `task-import-platform` | 46 | `20260924-03/checks/task-import-platform/results.json` |

The imported-task check ran five supervised processing attempts: three published the expected reports; two deliberately tampered study/dataset hashes failed without replacing original sources or reports. These expected refusals are part of its 46 checks. Run evidence includes the original 20,748,348-byte synthetic journal and compact 1,518-byte worker input. Original calculation/count/byte-hash expectations were retained.

An additional **19 focused checks** passed in `C:/Users/User/Documents/Codex/2026-09-05/make/work/portable-qa-next-20260924/evaluation-01/focused-03/results.json`. They cover actual R native-argument bytes, existing/protected/junction destinations, unreviewed test IDs and changed catalog scope, missing libraries, actual R refusal of an invalid native manifest before test execution, and exact owned-parent/descendant cleanup including refusal of the wrong start identity. The earlier 15-check and 19-check receipts remain separate; final checks assert the specific refusal reasons and current preflight boundary.

`evaluation-01/qualification.json` binds every accepted test receipt and final owned source hash. Key hashes are launcher `8b2a73bf0720a0c1f6f7675e8ef62f6637db286290d184057d9f9e4ed27a931a`, helpers `c9ec1a58f8d8e4e235ffc6c9013c16387d435f062e9e922665496929739fd5cf`, and runner `1d759e14915bd7804ed4305a35224eb03837633b966533ca0a60b9faeb720cd0`. Each accepted child receipt verifies its test/application sources remained stable during that execution. The supplied configuration/native manifest and all nine configured workspace files stayed byte-identical; all 354 source identities of the earlier accepted smoke clone also stayed unchanged. No owned R, Python, Node or browser process remained after qualification.

## Retained failures and portability lessons

- The first run passed five checks. Its backup fixture incorrectly compared canonical long paths with the shortened Windows temporary path while copying an artifact for fault injection. Normalize the fixture directory immediately; the production backup implementation and assertions were not changed.
- The first import attempt correctly rejected its pinned source-byte oracle because `core.autocrlf=true` rewrote the LF CSV from 23,720 to 23,901 bytes. The narrow [.gitattributes](../../.gitattributes) rule preserves committed synthetic fixture bytes. The evaluation used normal Git checkout from the unchanged index under that policy, and all five original CSV/registry hashes matched their unchanged manifest. No input normalization or recalculated oracle hid the mismatch; the failed imported source remains in its separate store.
- The second import attempt progressed through 21 assertions, then its actual publisher encountered Windows MAX_PATH because the new QA folders repeated the long test ID. The runner now uses a compact `e/001` address within each unique results directory, with the full test ID retained in the receipt. The next import run passed. This shortens QA paths; it is not a claim that arbitrary deep Windows research paths are supported.

The initial failing runs, failed job and focused preflight failures remain externally retained. The five unaffected passing checks were not rerun after fixture/path-only repairs. Catalog installation preserves any subsequently added test entries; only this exact seven-entry subset and its configured prerequisites are covered by these receipts. This is an existing Windows-host/source-portability qualification, not a clean-machine installation or full-catalog acceptance.
