# Saved event-related EDA review

Status: delivered and connected acceptance passed on 24 September 2026. This is original synthetic software evidence, not scientific or live-device qualification.

## Researcher outcome

From an event-related EDA report, **Review EDA event windows** opens the saved event/channel cells, paged in groups of 25. **Prepare event window** verifies the original report, dataset, full continuous-series artifact and detector-candidate artifact in a supervised worker. Phasic, tonic and cleaned conductance then share that saved review; switching components does not rerun detection, scoring or the review job.

The figure shows the original measured onset, authored baseline/response bounds, allowed onset-latency interval and declared recovery limit. Original source segments and retained/excluded processing-edge runs remain disconnected. Incomplete windows receive hatching. Overlap, missing support and original null feature values remain explicit. An unavailable event half-recovery never appears as a valid selected recovery marker. EDA is not presented as emotion or independent-person evidence.

Complete sample, original-feature and detector-marker CSVs accompany source-bound SVG and JSON exports. A labelled first-50 sample preview is distinct from the complete CSV. Original features and their denominators remain unchanged. Saved event windows reopen without new jobs, including after process restart. Native file guards and background hash verification protect sources/results/exports without bulk hashing in the Shiny event loop; selection changes revoke older download URLs.

## Method and evidence boundaries

Supported original recipes are `eda-event-highpass/1.0` and `eda-event-cvxeda-defaults/1.0`, as specified in [the accepted EDA method](../methods/EVENT-RELATED-EDA.md). The review reads already measured source coordinates and already computed samples and candidates. It does not create an event join, infer a clock, average an unsupported baseline, interpolate a gap or independently rescore an SCR.

The review window runs inclusively from the authored baseline start to recovery end, relative to the selected saved event onset. All selected saved samples remain in the complete export, including excluded processing edges. Original missing source samples remain absent from processed artifacts and visible through source masks/support. Plot reduction selects actual endpoints/extrema within buckets and preserves segment/retention boundaries. Exact saved selected-SCR identity must match a complete candidate row.

Initial limits: 500,000 selected samples; 200 trace/support groups; at most 2,000 displayed actual points per component; three complete CSVs each at most 128 MiB; normal 16 MiB JSON envelope bound. Exceeding a bound fails explicitly with original evidence retained. No silent truncation or partial substitute is published.

## Independent checks

- `tests/workers/eda_review.py`: 11 passing hand-authored typed-source checks. Complete selected values/indices, measured times, source corruption, wrong clock/settings, invented candidate, overlap/nulls, unsupported recovery, incomplete baseline, split support and CSV text safety. No decomposition or scoring implementation is used as the arithmetic oracle.
- `tests/platform-eda-review.R`: 27 passing source authority, idempotence, changed-input rejection, complete export, immutable original feature, SVG/source geometry and unavailable-support checks.
- Final R receipt: `work/test-runs/brohn-eda-review-domain-20260924-02/results.json` relative to the development workspace; SHA-256 `53e6b251f9de0ae594e33cec6919a241931c0cc65ac9bafe06b94d2a31c4db8b`. One queue/idempotence guard job was cancelled; no scientific child job ran. The earlier domain workspace `-01` likewise contains one cancelled guard job.
- `tests/researcher-eda-review.mjs`: 22 passing connected checks. Actual researcher import, mapping, scientific analysis, event review, full exports, keyboard component switch, forged/stale URL rejection and saved reopening/restart. Six desktop/mobile scans have zero axe violations, page overflows or actual SVG text intersections; all six final chart screenshots were visually inspected.
- `tests/verify-eda-review.py`: 38 passing independent checks comparing every retained exported sample and every plotted value to the original complete typed artifact, plus original report/feature preservation, source-clock marker identity and SVG geometry.

## Retained connected evidence

Final receipt directory, relative to the development workspace:

`work/test-runs/brohn-eda-review-browser-20260924-02/browser-1790223772039`

| Receipt | SHA-256 |
| --- | --- |
| `results.json` | `996e126f199f50bfba678a4ba4dd60c8d7ecc0ef7aec8f42c2eef7d8d637b286` |
| `independent-source-audit.json` | `83cd2655d35ef0764564d244b05050ad0c2d234064b646700ff29156fc5a8806` |

The original six measured events used a 4,500-row synthetic recording. The missing source sample at index 3,000 remains absent from the 4,499-row complete processed artifacts; it is not interpolated. Five saved review selections cover a detected response, supported nonresponse, overlapping event, gap and excluded recording edge. The detected-response export contains all 301 selected source samples, rather than the original report's 2,000-row whole-recording display preview.

The accepted workspace contains exactly seven actual jobs: one `ingest_source`, one original `analyse_dataset`, and five `eda_review` jobs. All succeeded on attempt 1. Original report `report-job_a429e69a1c514515e8bdd14c1f7ddbe0`, imported bytes, original feature values, saved event support and complete artifact bytes remained unchanged. Reopening and an actual application/worker process restart produced identical JSON and CSV without new jobs. Port 3883 and its owned worker were stopped at completion.

The final browser run continued the original import/report already saved in this same isolated workspace after correcting two UI defects. It did not fabricate a source/report fixture or repeat scientific analysis. The preceding receipts and the actual native job history preserve that lineage.

## Failed attempts retained honestly

The first fresh browser fixture, `brohn-eda-review-browser-20260924-01`, imported successfully. Its original `analyse_dataset` job failed before any derived review because the existing Windows artifact writer could not rename a hash-named file after its path exceeded the native path limit. One import job succeeded, one scientific job failed, and no derived review job ran. Both services were stopped. Four direct diagnostic scientific calls isolated path length from source/settings: Python without artifacts, Python with artifacts and the short-path R adapter succeeded; the native-length R adapter reproduced `WinError 3` in `physiology_artifacts.TableWriter.finish`. These calls are not browser acceptance and do not qualify the measurements.

The integration owner shortened the scratch artifact filename while retaining the full kind/SHA-256 in its manifest and typed header, with a matching long-path/collision regression. The second fresh browser workspace then published the original scientific report successfully.

Within workspace `-02`, `browser-1790223334932` caught a partially named list in the new UI's background verification request; `unname()` fixed the serialization boundary. Its first derived job had already succeeded. `browser-1790223592745` then caught a narrow-page overflow from a long raw missing-reason code; plain-language reasons and explicit wrapping fixed it. The final run reused those immutable saved reviews and added only the remaining edge review. No assertions were relaxed and no scientific values changed to obtain the accepted screenshots.

## Reproduction

Use the repository's configured native R library, methods Python and native publication guard. From the repository root, create a fresh external folder whose basename starts `brohn-eda-review-browser-`, then run:

```text
Rscript --vanilla tests/fixtures/researcher-eda-review.R setup <fresh-folder>
node tests/researcher-eda-review.mjs <fresh-folder>
python tests/verify-eda-review.py <fresh-folder> <receipt-directory>
```

The test creates synthetic sources only. `BROHN_EDA_REVIEW_TEST_PORT` overrides the default 3883 at setup. An explicit `--resume` on the browser harness reuses the one existing actual report and its idempotent review jobs after a UI-only correction; it refuses a workspace with a different report count. Neither mode operates on the researcher's normal study store.
