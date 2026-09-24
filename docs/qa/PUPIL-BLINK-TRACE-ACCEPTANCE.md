# Pupil and source-labelled blink trace acceptance

20 September 2026; connected SVG/keyboard/restart acceptance completed 24 September 2026. Software evidence only. No physical eye tracker, pupil calibration, physiological blink annotation or cognitive interpretation is qualified here. Primary academic rationale and the intentionally limited scope are in [the trace contract](PUPIL-BLINK-TRACE-CONTRACT.md).

## Implemented foundation

The original sampled-gaze recipe now accepts an optional streaming sink. It supplies its own resolved baseline and interval masks; the writer does not repeat the numerical analysis. New complete `physiology-series` artifacts retain every accepted source row, including no-passive groups, original input text, typed values, source flags, effective pupil eligibility, following-interval support and terminal nulls. One table is one exact person/session/exposure/stimulus and mapped pupil source. Original numerical summaries remain unchanged.

The unchanged I-VT identifier remains `brohn-adjacent-ray-ivt/0.1.0-draft`. New source-labelled blink flags use the separate `source-labelled-blink-boundaries/1.1` policy, including labels continuing across passive-phase boundaries. Historical reports retain their bytes and disclose the older semantics. Sources without mapped pupil or blink data do not receive a suggestion that rerunning them can create an absent measurement.

The dedicated `gaze-pupil-source-trace/1.0` reader returns all rows in an explicit window, or no plotted rows if more than 5,000 are selected. A complete metadata catalog gives original bounds and an initial window based on the actual first 5,000 source coordinates. That initial window is explicitly distinguished from the full table. The generic single-mask signal envelope is unsuitable for this profile; shared integration refuses that plot route while retaining exact-value inspection.

Raw finite invalid values are unconnected crosses. Raw valid lines break at phase changes, unsupported gaps and invalid endpoints. Corrected lines additionally require the original pupil interval eligibility. Positive source blink labels are ticks, including an isolated zero-duration label. Blue shading marks the declared baseline window, not complete observed coverage. The baseline mean is a saved reference line. Nearly identical values get a display-only minimum axis span to avoid magnifying binary64 rounding differences into a large apparent response. Numerical rows and source artifacts remain exact.

## Interfaces and shared integration

New modules:

- `R/platform-gaze-traces.R`: `brohn_gaze_trace_sink(scratch, data, metadata)` returns `emit`, `finish(analysis, source_provenance)` and `abort`; `brohn_gaze_trace_read(artifact, scratch)` reads the complete catalog, with `table`, `start_ms`, `end_ms` arguments for an exact preview.
- `scripts/workers/gaze_trace.py`: bounded exchange-to-typed-artifact writer, complete catalog and dedicated exact-window reader. Existing `physiology_artifacts.py` performs typed complete-stream verification before attachment/publication.
- `R/platform-gaze-trace-views.R`: `brohn_gaze_trace_plot_model`, `brohn_gaze_trace_svg`, `brohn_gaze_trace_export_svg` and `brohn_gaze_trace_ui`; compact and wide layouts contain the same saved points and masks. Numerical/method detail is initially collapsed, with a named keyboard-focusable scrolling table.
- `R/platform-gaze-trace-jobs.R`: operations `gaze_trace_catalog` and `gaze_trace_preview`; entity `gaze_trace_view`; `brohn_gaze_trace_job_input`, `brohn_hold_gaze_trace_sources`, `brohn_analyse_gaze_trace`, `brohn_publish_gaze_trace`, `brohn_gaze_trace_record`, and `brohn_queue_gaze_trace`.
- `R/platform-gaze-trace-server.R` and `www/gaze-trace-ui.js`: `brohn_install_gaze_trace_server` and `brohn_gaze_trace_report_ui`. The complete source and exact window/support are streamed from retained objects after background hash verification under native read guards. Visible time fields are submitted with each action before input debounce. The existing gaze-exposure selector is matched by report and person/session/stimulus/exposure, and a switch clears the old pupil result before selecting the matching trace.

Shared integration includes retention dispatch, exact original-CSV native guards, current project/source authority through final publication, worker source closure, report hook, and generic line-preview refusal. Its companion `R/platform-gaze-retention.R` supplies those original-analysis interfaces. It holds `brohn_hold_gaze_trace_sources()` guards across each derived worker job, revalidates pinned input after acquiring them, and retains them through publication. The publisher independently acquires guards and checks current authority inside the final transaction. The domain's loaded implementation fence includes the trace view module because its model validates preview output.

The exchange and final artifact each have a 2 GiB bound, a 2 MiB line bound, at most 10,000 tables and the existing 2,000,000-input-row ceiling. R materializes only 64 exchange rows at a time beyond the analysis's existing source/group arrays. No second giant sample list is inserted in a report. Preview/catalog documents are bounded to 16 MiB, with incremental encoded-byte checks before accumulation and reserved metadata/envelope space. Exceeding a limit fails explicitly and requires a smaller source or window; no prefix is published as complete.

## Binary64 and original text

The R-to-Python exchange uses 17 significant digits and a decimal token for double-valued signed zero. The complete typed artifact retains the numeric value and original source text separately. Tests include `6.0000000000000009`, whitespace around the original text, `null`, zero, negative values, false and absent source flags.

The existing general R JSON serializer emits negative zero as integer token `-0`, which its reader subsequently parses as integer zero. New preview rows therefore carry Python-produced `exact_record_json` and exact decimal strings as the authoritative native-value representation. Numeric plot convenience fields can pass through that general serializer, while the native JSON string and complete typed artifact preserve signed zero. This is explicit in each preview's `exactness` field; original numeric bytes are not reconstructed from a summary or silently claimed to survive an unsuitable serializer.

The available-window SVG export uses the same saved-point/mask renderer, adds a visible legend, and embeds XML-escaped report/artifact/source identity, original origin, units, selected range and denominator, and baseline support. SVG geometry is rounded to 0.001 display units; it is not a substitute for the exact numeric export. The link shares the verified preview's native source guards and current authority checks. Empty or oversized windows do not expose a chart export.

## Completed independent checks

| Evidence | Result and scope |
| --- | --- |
| `tests/platform-gaze-traces.R` | **49 passed**: actual R analysis/sink → Python complete writer → receipt → catalog → exact preview → renderer/domain; independent 4-to-6 subtraction, linear irregular baseline oracle, 80/90 ms interior-window support, boundary cases, all original rows including a no-passive group, interleaved people, invalid values/flags, terminal nulls, signed zero/difficult decimal, source/bounds substitution refusal, distinct plot masks, source-bound SVG/XML escaping and accessible numerical-region semantics. |
| `tests/platform-gaze-trace-server.R` | **10 passed**: isolated Shiny exposure coordination with two people sharing clocks/session/stimulus/exposure labels, current report matching, immediate visible-field payload versus stale inputs, stale-form refusal and clearing on report exit. Storage/native functions are deliberately stubbed here; these are not publication tests. |
| `tests/workers/gaze_trace.py` | **15 passed**: actual typed streams, all-or-none 5,001-row display limit, useful exact 5,000-row initial window, wrong person, missing/duplicate/reordered source rows, incorrect following endpoint, terminal duration, incomplete/trailing stream, same-size mutation outside the selected range, forbidden generic mask substitution, preservation of null/text/negative zero, and incremental preview/catalog allocation guards. |
| Existing `tests/platform-gaze.R` | **38 passed**, including original geometry, candidates, AOIs, missingness, clocks, pupil/blink arithmetic and the pinned `saccades` context comparison. Different detectors are not treated as an agreement/qualification claim. |
| `tests/gaze-trace-component.mjs` | **10 passed**, actual Chrome on R-rendered markup, with **two clear axe/reflow scans** at 1440 and 390 pixels, keyboard disclosure, exact numeric alternative, visible invalid observations/single blink tick and no runtime errors. This is a standalone component, not the connected saved-report journey. |
| `tests/reference/gaze_trace_saved_review.R`, final saved run | **19 passed across eight supervised jobs**: actual original CSV analysis/retention, complete catalog, exact clean/dirty previews, writable-before/denied-during/writable-after native original-source guard controls, authority revocation after input preparation preventing publication, retry, unchanged source/report and reopened saved views. Includes the generic exact-value catalog, complete 22-row pupil CSV preserving signed zero/difficult decimal/native flags, and R annotation/line-route refusal. Evidence: `brohn-gaze-saved-02/acceptance.json`; the initial 16-check/six-job run is separately retained at `brohn-gaze-saved-01`. |
| Existing `tests/platform-jobs.R` and `tests/platform-gaze-jobs.R` | **30 and nine passed**, respectively. The gaze backup/reopen regression now permits deliberately retained bounded publication-control records while continuing to forbid scientific scratch or bulk source copies in the workspace snapshot. |
| Initial connected `tests/researcher-gaze-traces.mjs` | **18 passed**, with three clear axe/reflow scans (dirty desktop, dirty 390, no-view 390). Actual source-bound catalog/window jobs, existing gaze selector matching/following, immediate exact inclusive ranges, original typed-artifact hash, queued cancel/keyboard retry, no-view rows, revoked old links, and unchanged original report/artifact. Retained at `brohn-gaze-browser-03/browser-1789895232256`; the later completed run below extends this evidence. |
| Final connected `tests/researcher-gaze-traces.mjs`, 24 September | **28 passed**, with **five clear axe/reflow scans** (dirty desktop, dirty 390, expanded numerical table 390, no-view 390, reopened desktop). Includes every earlier source/window check, exact-source SVG download, named keyboard-scrolling numerical region, chart-link revocation on range/exposure/report changes, full researcher-service/worker restart, identical saved-window and SVG exports after restart, and reuse without any additional job. Seven new jobs on a separate copied workspace: one catalog and five previews succeeded; one queued preview was cancelled and retried as a separate successful job. No original scientific analysis was rerun. |
| Independent retained SVG review | **Eight checks passed** using Python's standard-library XML parser: downloaded SVG metadata equals the exact saved window's complete support, identity, range, binding, source provenance and artifact descriptor; the independent fixture expects a 4 mm baseline over 100 ms and 22 selected rows from 0 to 210 ms. This is a separate saved-artifact review, not eight extra browser assertions. |

Latest retained foundation evidence: `C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-gaze-traces-08/acceptance.json`; original CSV, complete artifact, fixture design/mapping and requests/results are in the same directory. The earlier component browser evidence remains under `brohn-gaze-traces-07/component-browser-1789894304769/acceptance.json`, `trace-1440.png` and `trace-390.png`. Both screenshots were inspected; the compact plot corrects the initially unreadable scaled-down axis text.

Earlier runs remain retained. The first staged 30-check run compared the original unmodified numerical output to the staged version after removing only the new boundary-policy field. A later integration test exposed R lazy evaluation when `finish(analysis_call(...))` checked counts before forcing its argument; forcing the analysis promise fixed this. An initial component scan exposed a missing heading in the standalone fixture shell, which was corrected. Neither changed scientific scoring.

Independent resource probes exposed a late-rejection problem: 250 valid rows containing large original text fields reached 97,607,551 traced Python bytes before the final 16 MiB response check. The corrected reader accounts for each encoded row before appending it. Separate preview and large-catalog tests now reject without partial output below 48 MiB traced peak. This changes allocation/refusal timing only; complete artifact content and academic summaries are unchanged.

## Completed connected follow-up and remaining qualification

Actual original-source native guard controls, authority refusal, saved catalog/preview publication, retry, restart, SVG export and keyboard scrolling have passed at the scoped counts above. `tests/reference/gaze_trace_saved_review.R` uses the original 47-row data/mapping from `brohn-gaze-traces-06`; the final browser run copied the completed `brohn-gaze-saved-02` workspace into a new external fixture. It ran on loopback port 3883, stopped and restarted both owned services, and exited successfully with no matching child services left running. The original reference workspace and all previous attempts remain unchanged.

Final evidence directory:
`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-gaze-browser-20260924-01/browser-1790214505973`.
Its `acceptance.json` SHA-256 is
`ad70c7664fb0dd6f92a6a4a9a3da9ae76e61ae27f4ac9d767ad35a6ad5004022`.
The separate `svg-source-review.json` SHA-256 is
`0a2cdb31efeced2dbed2ea3f0436c59dee9f613ebd86d60677be96fdee5096d0`.
Retained source artifact SHA-256 remains
`85790572c29ff74de37f8b7f74f392da85e5af3e9d6216dde579acce0ccb08a6`;
original report-body hash remains
`1a37658d9ce6fc6d07484df69c4d994d27b3bdd0f76e0f41ae4734bdf1ff08c8`.
`before-restart.json`, the final workspace inspection, original and reopened
window/SVG downloads, complete 47-row artifact, screenshots, axe outputs and
service log are retained alongside that run. The 390-pixel original trace,
expanded keyboard-scrolling values, no-view trace, exported SVG and reopened
desktop trace screenshots were inspected: labels and legend remain readable,
invalid values and gaps remain visible, and unsupported correction stays absent.

The first browser attempt read the exposure control before report mounting,
and the second incorrectly treated Shiny's Selectize control as a native select.
Later attempts 04 and 05 ended with screenshot errors, not running jobs: an
export-page screenshot timed out and the output-wrapper screenshot had no usable
element box. The final harness captures the actual trace section and the SVG
element at a fixed export canvas, then restores focus to the researcher page.
These were test-harness changes only; no scientific or product code was changed
for the final acceptance. The harness now accepts an explicit
`BROHN_GAZE_TEST_PORT` and existing runtime environment settings for isolated
parallel runs.

To repeat on this prepared development machine, use a new, nonexistent fixture
directory whose name starts with `brohn-gaze-browser-`, the retained
`brohn-gaze-saved-02` reference directory, and an unused port:

```powershell
$env:BROHN_GAZE_TEST_PORT = '3883'
node tests/researcher-gaze-traces.mjs '<new external fixture directory>' 'C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-gaze-saved-02'
```

The reference data and configured native runtime are local development evidence,
not bundled fixtures or proof of a clean-machine installer. The test accepts
`BROHN_RSCRIPT`, `R_LIBS_USER`, `BROHN_PUBLICATION_PYTHON` and
`BROHN_PUBLICATION_NATIVE_MANIFEST` overrides.

Physical acquisition, source blink-label accuracy, pupil calibration, luminance/geometry confounds and scientific appropriateness of a selected baseline remain outside this software evidence. Complete trace visibility improves auditability; it does not certify a general preprocessing pipeline.
