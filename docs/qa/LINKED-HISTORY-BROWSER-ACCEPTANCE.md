# Linked review history browser acceptance

25 September 2026. **Passed: 14 grouped checks, four clean accessibility scans.**
This is a current installed-source browser qualification, following the separate
48 domain/history and 34 Shiny integration checks. No product change was needed.

Receipt: `C:/Users/User/Documents/Brohn QA/lh-20260925-01/results.json`.
Receipt SHA-256: `593736d724cabbba7f1c4b2312c2e3abac1331381cb41e8f5a923f52daea6a1e`.
The exact 365-file source manifest is adjacent `source-start.json` and equals
`source-end.json`; its file SHA-256 is
`4b8e0a4e446fc95623d58b450aaa278d1d79c3e628cecea0fa0d4ce50bf7b27d`.
It covers published GNAT base `935d2217db2a43ba65d5b969627834d1184c7c1b`
plus the frozen integrated UX changes, not a later source tree.

The installed linked files match the reviewed candidates exactly:

| File | SHA-256 |
| --- | --- |
| `R/platform-linked-history.R` | `dcc0286ac4ad85ca4e6afa7a19afed2349a02721f46f6fd6e0e3e7c5b6698026` |
| `R/platform-linked-history-views.R` | `a9f8dac88b162e8f9ee986e941e86a3239719a584173989d63390af393140c33` |
| `R/platform-linked-review-views.R` | `da6d74296a902cf5c2242e9ebffbccc1b832afadb0600e008b4fe76fb7a84e1d` |

## Actual scope

The fixture copies the previously qualified original synthetic workspace
`work/test-runs/brohn-linked-browser-20260924-04/workspace` into a fresh external
directory. All 121 original files are hash-verified unchanged after the run.
Only the copy receives 65 clearly synthetic metadata history rows; those rows
reuse existing saved results and do not represent newly processed observations.
Together with seven actual prior views they make a 72-view paging corpus.

The actual browser reaches every page uniquely, including the original view
beyond the former 40-row cutoff. The history disclosure remains mounted/open.
Keyboard Older navigation and the oldest boundary focus the rendered status;
the status identifies the range and explains the boundary. Desktop and 390px
screenshots were inspected and have no page overflow or scoped WCAG axe errors.

The original available, empty-window and unsupported-reset views reopen their
saved support states. The actual 78-row result restores exact input values and
downloads its complete manifest and CSV unchanged. Its identity is
`linked-review-job_31f1af9f19017285855ebcb56efc9540`, canonical saved-body SHA
`24f7e1e7ade2aaf334e2d11a1ee483dfa340623025dc19f153beae78e3694286`, CSV SHA
`fc9e222df23bb203064e9bd8544b545523b8e75f1d79de8867b79a8eab8e21c7`.
The 158-row saved view also restores its second numerical page at offset 100.
History discovery, opening and export create no processing or scoring jobs.

While that browser holds an edited, unapplied draft, a separate QA connection
calls the existing validated `brohn_queue_multistream(..., force=TRUE)` API.
The real supervised importer completes one new `normalise_dataset` job against
the exact original source. This is an actual processing/publication path, not
mocked import/stream IDs. The helper trigger exercises an import arriving from
another connection; this slice does **not** claim a browser upload action.

After arrival, the selected import, checked tracks, exact decimal start/end and
cursor strings, rationale and confirmation remain identical to the visible
draft. Both before/after field receipts are retained. The researcher then
selects the genuinely new import and different tracks, and reopens the old
158-row view from history. Its original import, channel identities, input
lexemes and numerical offset 100 are restored after client acknowledgements;
the complete CSV and manifest again agree exactly. The saved old source is
never recomputed. Mobile source/plot screenshots were visually inspected.

Full supervisor and browser restart reopens the same original view and exports.
The complete final dataset/import/stream/job/review snapshot agrees with the
pre-restart snapshot. The inventory grows from ten inherited jobs to eleven
solely through the intentional importer, which succeeds on attempt 1. Existing
job identities/statuses, datasets, preserved imports and streams are unchanged.
No new `linked_review` or scientific scoring job is added. Both service cycles
stop normally, the browser closes, and a process inventory confirms no owned
R service remains on ports 3973/3974.

## Reproduction and package

The unchanged executed files are packaged as:

- `tests/researcher-linked-history.mjs` from the external qualification directory.
- `tests/fixtures/researcher-linked-history.R` from its `fixture.R`.

The Node harness takes one runtime-only JSON request on stdin. Use explicit
absolute paths for the checkout, existing installed R/library/publication Python
and native manifest, portability Python, configuration path/hash, pinned Node
tools directory and Chromium executable. It reuses the portable smoke's strict
destination and runtime isolation helpers. Node 22+ and the checkout's exact
Playwright/axe versions are required; no download or installation is performed.

The request schema is `brohn-linked-history-browser-request/1.0`. Its shared
runtime fields match the connected smoke request; additional fields are
`original_workspace` (a normally stopped, previously qualified **synthetic**
linked fixture) and `fixture_path` (absolute path to the R fixture). `output`
must be a new external directory whose parent already exists. The supplied
real research workspace is forbidden as output and is never opened. Ports
3973/3974 must be free. Invocation is:

```powershell
Get-Content -LiteralPath $RuntimeRequestJson -Raw |
  & $NodePath (Join-Path $Checkout 'tests/researcher-linked-history.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Inspect the retained linked-history receipt.' }
```

Qualification used an unrelated caller directory and existing Windows runtimes.
It is not a clean-machine setup test. Original fixture construction remains a
separate prerequisite; this history slice does not rerun the earlier broad
linked-analysis study/import journey. All configuration, media, source objects,
receipts and screenshots remain external to Git.

## Limits

The history corpus above 40 is explicitly synthetic metadata. Only the original
saved views and the new preservation job supply actual processing evidence.
This loopback browser run adds no hardware clock synchronization, alignment,
physical focus/timing measurement, human usability or scientific validity claim.
Hosted revocation and stale-row permission faults are covered by the separate
candidate/domain checks, not a newly deployed hosted browser in this slice.
Read-only inspection confirms the installed domain still requires current hosted
session/project authority, available project/dataset state and exact pinned
dataset/import/stream membership; a history cursor grants no authority.
