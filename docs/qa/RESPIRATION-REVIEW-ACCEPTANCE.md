# Saved respiration cycle and phase review

Status: accepted bounded software slice, 24 September 2026. The actual researcher journey passed 21 checks and five accessibility/reflow/chart-label scans. This completes a connected PC05 respiration review route; it does not sign off the whole platform, physical devices, clinical interpretation or capacity.

## Researcher route

Data library -> transfer an original respiration recording -> explicitly map time, sampling rate, amplitude unit, source quantity and inspiration direction -> automatic saved analysis -> Open report -> Review respiration cycles -> choose one exact recording/channel/continuous segment and decimal time window -> inspect saved clean waveform, inspiration and expiration phases, complete-cycle boundaries and exact values -> export -> reopen the saved window after an application restart.

The view reads the complete immutable processing artifacts. It does not rerun filtering, peak detection or scoring when the investigator changes a window or display page. The saved report, dataset revision, study when present, project, source bytes, effective parameters, retained report envelope and both processed artifacts remain bound to the derived review. Scientific results stay unchanged.

The waveform is the saved cleaned, polarity-normalized signal, with its processed unit displayed. The UI also states the original quantity, inspiration direction and unit. It does not present the normalized waveform as a raw signed overlay or treat belt amplitude as calibrated tidal volume. Solid and dashed traces distinguish retained samples from excluded processing edges. A selected segment never joins another segment across missing data. Unsupported segments explain why they cannot supply a processed waveform; an empty window is not a zero-valued physiological result.

At most 50 complete cycles overlay the chart at once; the first-cycle control changes the displayed page without another job. Complete CSVs retain all selected samples, all intersecting saved cycles and all three extrema for each cycle. A clipped viewport does not shorten a cycle's saved phase durations or discard its out-of-view extrema. SVG metadata, JSON provenance and CSVs provide an exact alternative to the bounded chart and first-50-row table. The worker rejects selections beyond its declared size profile rather than silently truncating exports.

## Executed evidence

Evidence remains outside the repository under `../../work/test-runs/` from the repository root. The checked-in fixtures and harnesses reproduce it without human recordings.

| Layer | Executed result | Evidence receipt | SHA-256 |
| --- | --- | --- | --- |
| Independent complete-artifact reader | 16 passed; zero failures/errors | `brohn-respiration-reader-20260924-03/results.json` | `4d33a3aa129ba05eba99e27cb1ce19a4fd6ebc2eaa202734104344ccb3e8f695` |
| R source authority, validation and rendering | 27 passed | `brohn-respiration-domain-20260924-02/results.json` | `f7b074aaba32a2b12df77c88cc859a0f5ffd19a4ac0595d393f394d8a8a0ba60` |
| Actual browser, import, scientific worker and restart | 21 passed; five clean scans; zero page errors | `brohn-respiration-review-browser-20260924-01/browser-1790225896857/results.json` | `1248986659218e90c8abbdf81e040789bd146ef3701874e156ab8a8a9cca5b93` |

The browser fixture is a new 36,000-row, 50 Hz analytic volume signal stored with negative inspiration direction and declared unit L. Each period independently contains two seconds of inspiration and three seconds of expiration: 12 breaths/minute. Missing samples at 360 and 700 seconds create two computed continuous segments and one final 20-second segment that is unavailable. The fixture is explicitly synthetic; its unit declaration is not a device-calibration claim.

The browser used the real source-transfer/import, mapping, scientific worker and guarded result-publication paths. Saved rate agreed with the independent construction within 0.03 breaths/minute; saved inspiration/expiration values agreed within 0.08 seconds. The first-segment CSV retained all 18,000 source samples, exact source indices and `i / 50` source times. Its retained and excluded edge flags survived export. The complete cycle and marker CSVs reconciled to every selected saved cycle, including more than the first 50 visible overlays.

The same uninterrupted accepted browser run exercised:

- Both real computed segments, full-window and genuine second-page cycle overlays, and the unavailable short segment.
- A partial 11–13 second viewport retaining the full saved cycle and out-of-view extrema; a 355–365 second gap boundary containing only samples from the selected first segment.
- An out-of-support 500–501 second window with zero selected rows and a header-only CSV; reversed bounds refused before queuing another job.
- Wrong-key and stale CSV URL refusal after changing the selected range or switching to an unavailable segment.
- Saved-view reopen, complete process stop/start, byte-identical CSV recovery, unchanged original report and no extra scientific job on reopen.
- Desktop 1440 px and mobile 390 px pages, plus partial/gap/empty mobile states: zero axe violations, no horizontal document overflow and no SVG text intersections in five scans.

The run began with an empty workspace: **seven new successful jobs**, comprising one import, one scientific analysis and five saved-review jobs; **zero inherited jobs**. Five saved reviews and one original report remained. Original CSV SHA-256 `fd346b567017ca951ec3d4e56fd779ff85f50ded84d5558537b1cb95c7f15698` was unchanged. The harness compared its eight implementation-file hashes before and after the journey; each saved job additionally retains the normal native worker/publication identity. Both owned services ended cleanly and ports 3927/3928 had no remaining listener.

The five retained chart screenshots were visually inspected after the automated scans. Labels and legends are readable, phases remain distinct, missing support stays visibly blank, and the empty state is explicit. The full 390 px page was also inspected for the connection between controls, interpretation and export actions. A long full-window trace is intentionally dense at phone width; narrowing the source-time window gives individual-cycle detail. No visual claim rests only on a screenshot filename.

## Exactness and integrity checks

The independent reader tests use separate hand-authored saved values and verify complete tables, source identity, row counts, hashes, extrema-to-sample correspondence, phase arithmetic, source-clock agreement, retained support, original-source corruption, incomplete support and output collision refusal. See [the reader evidence note](RESPIRATION-CYCLE-READER.md).

R tests separately reject changed report/dataset/project/origin authority, unknown segments, altered support, missing complete verification, changed returned selection/parameters, out-of-window samples, altered phase durations and excluded boundaries promoted into supported cycles. Decimal comparison preserves authored bounds such as `10.000000000000000001`: the exact 10-second marker remains outside that window even though a double-only comparison would round the bound. This test still preserves the original full 10→12→15 second cycle and its phase values.

Publication holds the original objects and staged outputs under the existing native guards, validates the exact R reader plus both Python source identities, and checks fresh authority before committing. Downloads retain source/export holds, verify the saved envelope and bytes outside the Shiny loop, and recheck current source selection and saved authority before responding. The CSV route permits GET/HEAD with the current random key and returns 404 for an invalid or stale selection.

## Reproduction

Run from the repository root using the prepared local R/native-publication/Python environment described in the main setup documentation. `R_LIBS_USER` must point to the restored R library and `LC_ALL=C` is required for the Windows parser check. Supply `BROHN_PUBLICATION_PYTHON` and `BROHN_PUBLICATION_NATIVE_MANIFEST` for the installed Python and native publication guard.

```powershell
$env:R_LIBS_USER = (Resolve-Path ../../work/r-library-brohn-restore).Path
$env:LC_ALL = 'C'
$env:BROHN_PUBLICATION_PYTHON = (Resolve-Path ../../work/tooling/methods-venv/Scripts/python.exe).Path
$env:BROHN_PUBLICATION_NATIVE_MANIFEST = (Resolve-Path ../../work/tooling/brohn-native/publication-guard.json).Path
& ../../work/tooling/methods-venv/Scripts/python.exe tests/workers/respiration_review.py
& ../../work/native-r/bin/Rscript.exe --vanilla tests/platform-respiration-review.R
$respirationFixture = '../../work/test-runs/brohn-respiration-review-browser-fresh'
New-Item -ItemType Directory -Path $respirationFixture -ErrorAction Stop
& ../../work/native-r/bin/Rscript.exe --vanilla tests/fixtures/researcher-respiration-review.R setup $respirationFixture
node tests/researcher-respiration-review.mjs $respirationFixture
```

Use a fresh fixture directory and a free port 3927, or set `BROHN_RESPIRATION_REVIEW_TEST_PORT` before setup. The browser harness starts and stops only its own researcher/worker services and performs one real restart. It requires the repository's existing Playwright/axe dependencies and installed Chrome. The accepted run used the bundled Node executable rather than relying on PATH.

## Retained development limitations

Earlier reader fixtures failed before execution because the hand-authored artifact lacked its generator identity; that fixture was corrected. The first R domain invocation used `normalizePath(..., mustWork=TRUE)` before creating its evidence folder; the harness was corrected. A first generated browser script failed `node --check` before services started and was corrected. These are distinct from the accepted uninterrupted browser run; no product failure was hidden by a shorter directory, substituted signal or already-built report.

This slice does not prove clinical validity, device calibration, live acquisition, physical synchronization or arbitrary-capacity performance. The complete-reader profile remains bounded to 500,000 selected samples, 5,000 intersecting cycles and 128 MiB per CSV; the display remains bounded to 2,000 source points and 200 support runs. Existing raw-source/signal explorers remain separate routes. Browser cancel/retry was not exercised in this respiration journey; the R domain test only cancels two queued guard requests. Larger recording menus/history and simultaneous-user load need their own evidence. No study outcome, affective state or new clinical construct is inferred by this review.

## Subsequent time-axis display repair

The later EMG visual review found that the shared three-significant-digit formatting pattern could give duplicated time labels in narrow windows. The respiration view now formats the entire tick vector until positions have distinct labels, removes duplicate numerical ticks at adjacent floating-point endpoints, and explicitly states an offset/base for large time origins. This changes labels only; source positions, exact decimal selection, saved samples, cycle values and scientific report bytes stay unchanged.

`../../work/test-runs/brohn-physiology-axis-20260924-01/results.json` records 16 direct checks across EMG and respiration (eight per view), including 100–101 and 500–501 second windows, large origins, adjacent floating-point endpoints, tiny spans and exported SVG base declarations. SHA-256: `a85f5d433fa2d40873e46a7ac65ffb926b9daeb2d1f260bdf45f589add9ad5be`.

The actual-app follow-up is `../../work/test-runs/brohn-physiology-axis-browser-20260924-01/results.json`, SHA-256 `6ce4e9a69ce51c5b936bcaadc8b9fc6dc2fefe740236f46dcf315c1893e501d7`: eight checks across the two families, with two clean 390 px accessibility/reflow/chart-label scans and zero page errors. The respiration baseline was cold-copied to `brohn-respiration-review-browser-axis-01`. Because the artifact reader had since gained EMG input retention and changed identity, the copied original saved respiration report supplied **one new derived reader job** under the current exact identity. No filtering, breath detection or original scientific analysis ran again. The original report remained identical; the selected empty-window CSV remained byte-identical; the corrected current SVG displays the 500.5-second midpoint. Its screenshot was visually inspected, all owned services stopped, and the baseline workspace remained untouched.

This focused receipt qualifies the intermediate time-axis view, alongside the earlier complete scientific/researcher journey. The subsequent final display/history evidence is recorded below. See the focused follow-up command in [EMG review acceptance](EMG-REVIEW-ACCEPTANCE.md).

## Final saved-history and both-axis qualification

The final view repair makes saved windows identifiable by their exact authored range and saved timestamp. Human-facing settings use the shortest decimal representation that round-trips to the same number, so `0.05` and `0.1` remain readable. Exact JSON/CSV measurements and source-bound selection strings are unchanged.

Y-axis labels now use vector-wide precision too: narrow amplitudes cannot collapse to repeated labels. Long labels switch to an explicitly disclosed base, with exact original tick values retained in SVG `data-value-tick` and the base in `data-value-offset`. A very large origin can cause R `pretty()` to return only one visible tick; this case uses distinct evenly spaced axis positions. This is display layout, not signal normalization or rescoring. The compact gutter accommodates the labels, and every EMG component discloses its own base when needed.

- `brohn-physiology-axis-20260924-03/results.json`: **28 direct display checks** across both families. SHA-256 `191b0d991db05863a1a4c72aff13df696873be9aecd26b568e458f0ed29eb24f`. The preceding `brohn-physiology-axis-20260924-02/failure.json` retains the failed large-origin SVG assertion that exposed the single-tick behavior; it is not counted as a passed run.
- `brohn-physiology-axis-20260924-03/display-render-results.json`: two hand-authored standalone 320 px large-Y-origin SVGs rendered without out-of-canvas labels or text collisions and were visually inspected. SHA-256 `e611c18ab52e1d6522ffa488ee4ab2bb1ac7ee1dafe504fa9698bd7a6c5ded86`. These are labelled display fixtures, not newly processed scientific results.
- `brohn-physiology-history-browser-20260924-01/results.json`: **12 actual application checks, two clean 390 px axe/reflow/chart-label scans, zero page errors**. SHA-256 `0e5a3b44f00a320b64769650b922853f51e0a5406886f41cba1fb250fb9926e3`. The researcher selects each saved empty window by its human-visible exact range and timestamp, rather than an internal identifier. The browser verifies distinct X/Y labels, readable settings, unchanged complete CSV/provenance exports, unchanged original reports and saved reviews. Both cold-copy workspaces inherit the earlier evidence; **zero new derived or scientific jobs** run. Original baseline workspaces are untouched, and the owned services stop cleanly.

The final actual browser pins sixteen source files before and after, including the current shared report-coverage helper, signal-value view, hooks and frontend assets. Final EMG view SHA-256: `d8d8885b95b85d42e6c2ca55b3e3d2200debb8d80b0e9d347724ca52b1ab54ec`; final respiration view SHA-256: `8344b6997b694549f980980c9699a48800a51ff64ed52ea1ab94fa4098dd1688`. Both final chart screenshots and full-page layouts were inspected. The actual-app proof covers the saved empty windows; narrow Y and large-base edge cases have the separately labelled direct/render proof above. Earlier complete scientific/researcher evidence remains scoped to its recorded source identities.

To repeat the no-job history proof, supply the completed axis-copy fixtures containing current-identity saved windows and fresh, unused output/clone paths:

```powershell
& ../../work/native-r/bin/Rscript.exe --vanilla tests/platform-physiology-axis.R ../../work/test-runs/brohn-physiology-axis-fresh
node tests/researcher-physiology-history.mjs ../../work/test-runs/brohn-history-browser-fresh ../../work/test-runs/brohn-emg-review-browser-axis-01 ../../work/test-runs/brohn-emg-review-browser-history-fresh ../../work/test-runs/brohn-respiration-review-browser-axis-01 ../../work/test-runs/brohn-respiration-review-browser-history-fresh
```
