# Saved surface-EMG waveform and burst review

Status: accepted bounded software slice, 24 September 2026. The joined connected journey passed 24 checks and six accessibility/reflow/chart-label scans; the final display/history repair passed 28 direct checks plus 12 actual saved-view checks and two clean mobile scans. This is a bounded PC05 slice, not whole-platform, device or clinical qualification.

## Connected behavior

Data library -> import original surface-EMG voltage -> map time, sampling rate and original amplitude unit -> choose filter, RMS window and excluded edges -> optionally enter a positive RMS burst threshold in microvolts and minimum duration -> automatic analysis -> Open report -> Review EMG waveform -> choose an exact recording/channel/continuous segment and source-time window -> review input/clean/RMS tracks, saved bursts and original measurements -> export and reopen.

The threshold defaults to off, with no invented numeric value. A blank low-pass uses the existing recipe default (the smaller of 450 Hz and 40% of the declared sample rate). Enabling bursts requires an explicit threshold. An absent threshold differs from a configured threshold whose saved analysis found no accepted bursts.

The three chart components share one source-time window while retaining separate labelled voltage axes. Input voltage is the saved unit-converted input before cleaning; the original source file remains authoritative. The root-integrated artifact writer now retains `raw_uv` for newly processed EMG reports with an explicit input-waveform declaration. Historical reports without complete input samples keep their clean/RMS review and disclose the unavailable input component. No input waveform is reconstructed from a report preview.

The reader checks complete immutable artifacts and preserves saved values, filtering/envelope settings, source scale, retained/excluded sample flags and original whole-segment features. It does not filter again, calculate a replacement envelope, detect new bursts or rescore the selected window. Raw voltage is not relabelled as MVC-normalized activation, fatigue, facial emotion or a startle response.

Samples use a closed source-time window. Bursts use their original half-open `[start, end)` sample-cell support; intersecting bursts retain their full original bounds, duration, peak RMS and boundary-truncation flag even when partially outside the viewport. The exclusive end is anchored to the last active sample plus one declared sample interval and is labelled as a boundary, never an observed sample. The displayed peak marker selects the first actual saved RMS maximum within the burst. Complete CSVs preserve every selected sample, burst and marker.

At most 50 saved burst overlays appear at a time. Changing the first burst index only changes the display page. Each component's bounded envelope uses actual source endpoints/extrema, with retained/excluded runs kept separate. Missing intervals and other segments are never joined. Exact CSVs, original whole-segment measurements, source provenance and SVG metadata remain available alongside the visual summary.

## Implemented checks and authority

- The independent stdlib reader verifies both complete artifacts, identity, original clock, method, typed quantities, source indices, hashes, counts and source/report bytes. Saved burst boundaries, peak, duration, threshold support and boundary flags are checked against their retained RMS sample cells. Missing thresholds cannot acquire burst outcomes.
- R validates original report, dataset revision/mapping, project, study provenance when present, retained envelope and artifact support before queueing, execution, publication and reopen. Returned features remain exactly the original segment features.
- R and Python use exact decimal window comparisons. An authored bound such as `2.100000000000000001` excludes the exact 2.1-second sample; converting only to a double would lose that distinction.
- Normal guarded publication pins the R reader, Python reader and artifact-reader identities; outputs and original objects stay sealed. Export preparation verifies bytes and retained envelopes outside the Shiny loop. Current source selection, project/report authority and a fresh random key guard complete CSV responses.
- The reader profile refuses oversized work rather than truncating it: 500,000 selected samples, 5,000 selected bursts, 128 MiB per CSV, 24 MiB result JSON, 200 support runs and 2,000 display points per component. These are implementation bounds, not demonstrated load capacity.

## Evidence

Retained evidence outside the repository:

- `../../work/test-runs/brohn-emg-reader-20260924-01/`: 13 independent tests. Hand-authored saved values, 10,001 exact samples, legacy omitted input, absent/configured-zero thresholds, partial/exclusive boundary cases, distinct support runs, source/clock/corruption refusals and actual CLI/output collision checks. Receipt SHA-256: `a510f8fb463f0e083499c432a86dac57ea63cf292342ce1b9b92c7e37a0778bc`.
- `../../work/test-runs/brohn-emg-domain-20260924-01/`: 31 checks. Source authority, idempotency, returned-value substitution refusal, exact decimal clipping, three-component SVG/source metadata and explicit researcher threshold controls. Two queued guard requests are cancelled; this hand-authored test does not run the scientific scorer. Receipt SHA-256: `f77de2cb6d8cf76cf5febd04a8275fe0bcfff87ba14fdb981a144a3f1dd15bd2`.
- `../../work/test-runs/brohn-emg-input-artifacts-20260924-01/`: root's four focused artifact regressions, including actual 10,000-sample mV-to-uV input retention with unchanged scientific features and bursts. The receipt is explicitly transcribed from captured successful execution `ae2c4a`, not a new test run. Receipt SHA-256: `6b5ba4951b0dfb9042831668a3dabfe2f25b5768a27f272504a2562b1a2b879d`.
- `../../work/test-runs/brohn-emg-review-browser-20260924-02/`: fresh synthetic 32,600-row mV source, 500 Hz sampling, 80 Hz carrier. Amplitude is independently authored as 20 uV for the first half of each second and 2 uV for the second half. Missing samples at 60 and 65 seconds create two computed segments and a final short unsupported segment. The actual researcher import/mapping/scientific-worker journey is recorded by the joined receipt below.

The first browser attempt remains at `brohn-emg-review-browser-20260924-01/browser-1790227266794/failure.json`. It passed the actual unconfigured-threshold import/report/review and a clean mobile scan, then its native storage inspector opened the store during a publication commit and received the explicit transient busy response. The harness incorrectly treated that as terminal. It now waits for the actual visible report cards and records initial source hashes before the browser journey. The separate failed attempt completed four jobs (one import, two scientific analyses and one saved review) before its owned worker stopped; it contributes no checks to the accepted workspace-02 receipt.

During browser attempt 02, root repaired global notification landmark/keyboard semantics in `www/platform-ui.js` and `www/brohn.css` at `2026-09-24T05:25:57.52Z`. These assets are outside the ten R/worker files pinned by the EMG harness and outside scientific worker identities. Older browser asset bytes were not independently captured. After that repair the JS SHA-256 is `988b86f63a400b533754d001cc8e18e901f4a3962bd2c5755f5c8be36f2d9a51` and CSS SHA-256 is `73f477d88bbbbb9281d7369f51e3a0b030d98f6994b08e45280a7e3c7dd7e7c4`. Source-hash claims here cover the recorded R/worker files; they do not imply every frontend asset was frozen for the entire run.

The accepted connected receipt is `brohn-emg-review-browser-20260924-02/continuation-1790227781612/results.json`, SHA-256 `4bb0cca7bb39fce14678d083164e10f8fa31f1e96b601bc15965c68a1f82d662`. It explicitly joins retained assertions/downloads/scans from `browser-1790227459601`, recording its failure, initial source-hash receipt and exact retained-file hashes. That browser stopped at a numeric pager assertion because the harness had filled the field without committing the normal change event. The continuation commits with Tab, verifies unchanged ten-file R/worker identities, reopens the same immutable source and proves the genuine second page without a new job. This is joined evidence, not an uninterrupted-run claim.

Across that accepted workspace there are **11 successful jobs**: one original import, three actual scientific analyses (threshold absent, 8 uV and 1,000 uV) and seven saved-window reader jobs. The initial stage contributed five jobs; the continuation added six. No existing job was inherited when the workspace was created. All three original reports, source bytes and saved whole-segment features remained unchanged on real process restart. The original CSV SHA-256 is `3ebd56635cf96b6ca421a44ab9c5c230eb3332f930cba17d2d0eb4d9ca70df42`.

The full first-segment CSV has 30,000 exact source indices/timestamps with input conversion checked against the original mV CSV. Sixty saved bursts extend beyond one display page; their boundaries agree with the independently authored half-second amplitude pulses within 0.06 seconds. Interior RMS values agree with the independent sine expectations `20 / sqrt(2)` and `2 / sqrt(2)` uV within 0.25 and 0.1 uV respectively, allowing the declared filter/envelope behavior. These tolerances are software-fixture assertions, not empirical device accuracy.

The connected run also proves partial-window bursts keep full original metrics and out-of-view boundaries; wrong-key/stale CSV links return 404; missing intervals remain blank; a second segment preserves its own support; short unavailable and empty windows do not invent zero muscle activity; invalid bounds do not queue a job; and a high explicitly configured threshold yields a saved zero-burst result distinct from an absent threshold. Desktop 1440 px and five 390 px states have zero axe violations, no horizontal document overflow and no SVG text collisions. All six chart screenshots were visually inspected. Original and continuation browser page-error lists are empty.

Visual inspection identified a display defect despite those scans: three significant digits made the 100–101 second empty-window midpoint read `100` instead of `100.5`. The repaired EMG and respiration views now choose precision for the complete tick vector, discard duplicated numerical positions at adjacent floating-point endpoints, and explicitly disclose an offset/base when a large origin would otherwise make labels too long. Source positions and measurements are unchanged. `brohn-physiology-axis-20260924-01/results.json` records 16 direct vector/SVG checks, SHA-256 `a85f5d433fa2d40873e46a7ac65ffb926b9daeb2d1f260bdf45f589add9ad5be`; actual saved-view follow-up evidence follows.

The first display follow-up receipt is `brohn-physiology-axis-browser-20260924-01/results.json`, SHA-256 `6ce4e9a69ce51c5b936bcaadc8b9fc6dc2fefe740236f46dcf315c1893e501d7`. It cold-copies the two stopped accepted workspaces into isolated sibling fixtures. Eight actual application checks and two 390 px axe/reflow/text-collision scans pass, with zero browser errors. EMG reopens the identical saved review and CSV with zero new jobs. Respiration prepares one new derived reader view under the current artifact-reader identity; it does not run filtering, breath detection or scientific analysis. All original scientific reports and input bytes remain unchanged, and the baseline workspaces are untouched.

Both corrected chart screenshots were visually inspected: the midpoint reads `100.5` for EMG and `500.5` for respiration. The current full EMG mobile page was also inspected. The focused receipt pins fourteen files, including both then-current view modules, both readers, shared artifact reader, relevant shared hooks and current JS/CSS. Root's later empty signal-progress-wrapper adjustment is outside that explicit hash scope; no claim is made that every frontend source file was frozen. All owned services are terminal.

No human or clinical recording is used. Source scale, filter effects and software agreement do not establish electrode placement, physical calibration, muscle specificity, physical timing accuracy or a psychological construct.

## Reproduction

Use the existing restored R library, `LC_ALL=C`, prepared methods Python, native publication guard, installed Chrome and repository Playwright/axe dependencies. Run from the repository root with a new fixture directory and a free port 3931.

```powershell
$env:R_LIBS_USER = (Resolve-Path ../../work/r-library-brohn-restore).Path
$env:LC_ALL = 'C'
$env:BROHN_PUBLICATION_PYTHON = (Resolve-Path ../../work/tooling/methods-venv/Scripts/python.exe).Path
$env:BROHN_PUBLICATION_NATIVE_MANIFEST = (Resolve-Path ../../work/tooling/brohn-native/publication-guard.json).Path
& ../../work/tooling/methods-venv/Scripts/python.exe tests/workers/emg_review.py
& ../../work/native-r/bin/Rscript.exe --vanilla tests/platform-emg-review.R
$emgFixture = '../../work/test-runs/brohn-emg-review-browser-fresh'
New-Item -ItemType Directory -Path $emgFixture -ErrorAction Stop
& ../../work/native-r/bin/Rscript.exe --vanilla tests/fixtures/researcher-emg-review.R setup $emgFixture
node tests/researcher-emg-review.mjs $emgFixture
```

Set `BROHN_EMG_REVIEW_TEST_PORT` before setup to choose another available port. The harness starts and stops only its own researcher/worker services. Scientific method references and remaining qualification needs remain in [the academic acceptance audit](MEASUREMENT-ACADEMIC-ACCEPTANCE.md) and [other physiology reuse notes](../methods/reuse/OTHER-PHYSIOLOGY.md).

Remaining scope: the legacy omitted-input fallback has independent reader coverage; it is not presented as a newly executed historical-device browser benchmark. This journey does not exercise browser cancel/retry, arbitrary recording/history counts or multi-user capacity. Physical calibration, electrode/contact/crosstalk qualification, independently annotated human recordings and any MVC/facial/startle/fatigue profiles retain their separate evidence requirements.

For the focused saved-result follow-up, supply the two completed baseline fixture paths and new, unused clone paths. No physical recording is acquired and no original scientific report is rescored:

```powershell
node tests/researcher-physiology-axis.mjs ../../work/test-runs/brohn-axis-browser-fresh ../../work/test-runs/brohn-emg-review-browser-20260924-02 ../../work/test-runs/brohn-emg-review-browser-axis-fresh ../../work/test-runs/brohn-respiration-review-browser-20260924-01 ../../work/test-runs/brohn-respiration-review-browser-axis-fresh
```

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
