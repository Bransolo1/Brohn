# Contact PPG and detected PRV: recorded-reference evaluation

20 September 2026. The production `ppg-elgendi-detected-prv/1.0` profile was evaluated unchanged against **direct human PPG pulse annotations**. No ECG detector supplied the reference. Eight preselected eight-minute CapnoBase recordings supplied 5,400 reference pulses outside labelled artifacts; every pulse matched within the prespecified **strictly less than 50 ms** window. This supports bounded pulse-detection agreement on these recordings, not automatic whole-record PRV qualification: artifact-associated detections substantially distorted two records' RMSSD.

No production R or Python worker file was edited. Added harness: `tests/reference/ppg_capnobase.py`. The evidence is offline execution of the actual production Python worker and complete saved artifacts; it does not add researcher-browser, queue/publication or physical-equipment acceptance.

## Reference and independence

The [CapnoBase IEEE TBME Respiratory Rate Benchmark](https://doi.org/10.5683/SP2/NLB8IT), deposited by Walter Karlen, contains 42 eight-minute recordings. Its [official metadata](https://borealisdata.ca/api/datasets/:persistentId/?persistentId=doi:10.5683/SP2/NLB8IT) identifies expert PPG pulse-peak labels and explicitly discourages training or tuning against this benchmark. The [dataset README](https://borealisdata.ca/api/access/datafile/141710) describes human-rater beat and artifact labels; derived rate trends are separate fields. Its 2013 revision corrected PPG reference rate trends, which this evaluation does not use. Dataset version 1.1 and all selected file IDs/checksums are retained locally.

The [original study](https://pubmed.ncbi.nlm.nih.gov/23399950/) evaluated respiratory-rate estimation in 29 children and 13 adults. That result is not transferred to this pulse/PRV evaluation. The [PPG-beats dataset documentation](https://ppg-beats.readthedocs.io/en/latest/datasets/capnobase/) describes surgical/anaesthesia monitoring, mostly high-quality recordings. The eight selected records contain five paediatric and three adult cases. They are not a motion, arrhythmia, diverse skin-tone, low-perfusion, wrist-device or target-population qualification cohort.

Reference landmarks are `labels.pleth.peak.x`; source PPG is `signal.pleth.y`. ECG annotations, ECG-derived intervals and monitor heart-rate trends are not used. MATLAB sample indices are converted to zero-based source indices by subtracting one, without fitting a lag. Declared file sampling is 300 Hz, giving a 3.333 ms sample grid. Source amplitudes retain their exported arbitrary scale; no calibrated voltage or optical-unit claim is made.

## Frozen protocol

Plan frozen at **2026-09-20 06:07:26 UTC**, before detector comparisons, with SHA-256:

`2dab55bc1edcbae525f679793959f09a032edd548ae6f870095436b9e8464ea5`

Before this plan, only the published documentation, dataset metadata and first file's schema/units/array shapes were inspected. No waveform values, peak locations or detector scores were inspected. Selection was lexicographic filename ranks **1, 7, 13, 19, 25, 31, 37, 42**, yielding `0009, 0029, 0103, 0123, 0142, 0311, 0329, 0370`.

Each worker read the first 144,000 samples, `[0,480)` seconds. Both reference and detected events were restricted to `[2,478)` seconds, matching the frozen two-second edge exclusion. No resampling, amplitude normalization, polarity inversion, recentering, lag correction or parameter optimization was applied. The [Elgendi method paper](https://pmc.ncbi.nlm.nih.gov/articles/PMC3805543/) supplies the method rationale; the actual tested implementation is pinned NeuroKit2 0.2.13, `ppg_clean(method="elgendi")` followed by `ppg_peaks(method="elgendi", correct_artifacts=False)`. The [implementation documentation](https://neuropsychology.github.io/NeuroKit/_modules/neurokit2/ppg/ppg_findpeaks.html) identifies moving-average thresholding and the filtered systolic-peak target. The original publication's accuracy does not qualify this implementation or these endpoints.

Primary scoring uses WFDB 4.3.0 one-to-one annotation matching at 50 ms; prespecified secondary windows are 20 and 150 ms. WFDB excludes the exact boundary: a six-sample difference does **not** match at 20 ms. This was checked with an independent one-event example and is stated explicitly rather than presenting an inclusive tolerance.

Source-labelled artifact intervals use conservative inclusive sample endpoints. Events within them are removed from primary scoring. An interval is excluded from artifact-free endpoint calculations if **any part** intersects a labelled artifact, preserving original adjacency rather than concatenating retained sections. Paired-interval errors require consecutive matched events in both original lists. The profile's 300–2,000 ms plausibility screen is applied equally to independent reference and detected endpoint calculations; it does not establish normal-to-normal intervals.

### Reader/setup corrections retained

The frozen plan initially described artifact storage as an `N×2` MATLAB array. On the first nonempty artifact file, the reader stopped before evaluating that record: the actual representation is a vector of alternating start/end samples. The adapter now decodes those pairs; the selected records, supplied boundaries, inclusive masking rule and scoring protocol were unchanged. Earlier complete results were retained. Initial harness-only errors also concerned the worker's nested parameter dictionary and the explicit, pre-created complete-artifact output directory. Initial outputs/errors remain alongside the first record. None caused a production change or scientific parameter adjustment.

A subsequent clean eight-record run reproduced all event indices, endpoint values, paired-interval errors and source/CSV hashes. It is a technical replay of the same data, not eight additional independent records.

## Measured agreement

Across the eight windows there were 5,428 human pulse labels and 5,431 detections. The supplied artifact intervals contained 28 labels and 31 detections; their mismatch is not classified as verified false pulses. The primary denominator is the remaining 5,400 labels and 5,400 detections.

| Strict location window | Matched | Unmatched detections | Missed labels | Precision | Recall |
|---|---:|---:|---:|---:|---:|
| <20 ms | 4,810 | 590 | 590 | 89.074% | 89.074% |
| **<50 ms, primary** | **5,400** | **0** | **0** | **100%** | **100%** |
| <150 ms | 5,400 | 0 | 0 | 100% | 100% |

These are pulse-level descriptive proportions within eight recordings, not thousands of independent participant observations or a universal accuracy bound. At 20 ms, an otherwise present pulse outside the location window contributes both an unmatched detection and a missed label.

| Record | Group | Scored pulses | Signed median location error (ms) | Absolute location error p95 (ms) | Absolute paired-interval error p95 (ms) | Artifact-free RMSSD: labels → detections (ms) |
|---|---|---:|---:|---:|---:|---:|
| 0009 | Paediatric | 810 | +6.67 | 16.67 | 13.33 | 21.50 → 16.81 |
| 0029 | Paediatric | 541 | 0.00 | 16.67 | 26.67 | 83.31 → 80.83 |
| 0103 | Paediatric | 819 | +16.67 | 23.33 | 10.00 | 10.41 → 6.76 |
| 0123 | Paediatric | 706 | +10.00 | 20.00 | 16.67 | 31.09 → 27.88 |
| 0142 | Paediatric | 731 | +10.00 | 16.67 | 13.33 | 18.05 → 13.10 |
| 0311 | Adult | 550 | +16.67 | 23.33 | 6.67 | 8.26 → 9.09 |
| 0329 | Adult | 695 | +3.33 | 6.67 | 6.67 | 11.32 → 9.35 |
| 0370 | Adult | 548 | +3.33 | 6.67 | 6.67 | 14.65 → 12.26 |

There are 5,383 eligible consecutive matched interval comparisons. Maximum absolute paired-interval error is 36.67 ms. Artifact-free mean-interval differences range from −0.012 to +0.050 ms; reciprocal mean-interval pulse-rate differences are below 0.008 beats/min. Artifact-free RMSSD differences range from −4.95 to +0.84 ms, including approximately −35% in record 0103 despite perfect matching at 50 ms. Accurate pulse counts and average rate therefore do not establish close agreement for variability endpoints. Exact sample-SD, mean interval, RMSSD, rate, support counts and their differences are retained in each `agreement.json`.

### Whole-record artifact effects

| Record | Full all-label RMSSD (ms) | Full detected RMSSD (ms) | Independently artifact-excluded label / detected RMSSD (ms) |
|---|---:|---:|---:|
| 0123 | 31.05 | 115.16 | 31.09 / 27.88 |
| 0370 | 46.10 | 71.99 | 14.65 / 12.26 |

The full all-label comparisons include source-labelled artifact and are **descriptive**, not reliable physiological truth inside those intervals. The production profile does not read these external human artifact masks. In post hoc waveform inspection, record 0123 contains a flat portion whose filtered boundaries receive detections; record 0370 contains distorted pulses and a broad low-amplitude rise. The saved raw/cleaned plots make these cases reviewable without changing any detection.

## Product implication and remaining acceptance

Keep the existing status **unreviewed algorithm detections** and the distinction between calculation and scientific qualification. Do not promote the 100% pulse-count result to blanket PPG/PRV readiness. The largest immediate product gap exposed here is an auditable artifact/beat-review workflow that can explicitly exclude source-bound intervals and recalculate PRV without joining across removed time. Existing marker overlays provide visual review but do not themselves apply or qualify corrections.

A future reviewed profile should retain the original events and report, name the reviewer/mask/landmark rule, show excluded support, preserve source sample indices, and verify no artificial adjacent interval pairs across gaps. It should be assessed on separately frozen records and relevant devices/populations before adoption. These benchmark records must not become tuning data. No detector replacement or automatic global flatline correction is justified by this bounded evaluation.

This is **PPG pulse interval variability**, not ECG HRV or validated NN variability. No pulse-transit adjustment was fitted. The [Gil et al. primary experiment](https://pubmed.ncbi.nlm.nih.gov/20702919/) studied PRV/HRV agreement under a specific tilt-table protocol; such condition-specific evidence is not a basis for general interchangeability. Hardware contact, wavelength, skin tone, sensor saturation, physical timing, movement and clinical interpretation remain unqualified here. Frequency-domain endpoint agreement was not assessed in this task.

## Evidence and reproduction

All original data and generated artifacts are outside the repository:

`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-ppg-capnobase-01`

- `plan.json`, `plan.sha256`, `dataset-metadata.json`, `README-source.txt`: frozen protocol and primary provenance/terms. The README permits research use with citation; the dataset's additional terms are retained. No raw records are redistributed in Git.
- `source/*_8min.mat`: original public files, checked against the deposited MD5 plus locally recorded SHA-256.
- Each record folder: exact CSV/request, production result/log, complete event/series artifacts and independent `agreement.json`.
- `results.json`: complete measured results, source/code hashes and reader versions.
- `reference-waveforms.png`: prespecified first 2–12 s from all eight records.
- `timing-and-prv-errors.png`: timing and endpoint differences.
- `artifact-context.png`: explicitly post hoc source/cleaned traces around the first labelled artifact in records 0123 and 0370.
- Fresh technical replay: `../brohn-ppg-capnobase-replay-01/reproduction-check.json`, all eight records reproduced exactly for the stated endpoints and event lists.

The three figures were visually inspected; legend/title collisions were corrected. Complete event artifacts, not display previews, supplied all detections. The reader independently checks artifact hash, row sequencing and complete counts. Independent arithmetic agrees with the worker's saved full-record endpoint values; that arithmetic check is separate from external annotation agreement.

Reader environment: Python 3.12, NumPy 2.2.6, SciPy 1.15.3, WFDB 4.3.0, h5py 3.14.0; Matplotlib for figures. Production methods environment was unchanged. Frozen worker hashes:

- `scripts/workers/physiology.py`: `959aa9a3f7b2c701bd37706ff04ddbe7f71d60f5d777bce11240c5b76a424cc6`
- `scripts/workers/physiology_artifacts.py`: `a5e8a8f6ef4a1f6eba7a25cfce15864284020b3c8409b725ccad3d09e9c8d457`

Hash naming clarification: in the original `agreement.json` and per-record `results.json` entries, `worker_sha256` is the SHA-256 of **`worker-result.json`**, not the Python source. For example, 0123's result-file hash is `d4b3cd08b9f60e90a01d75d21da76df83bb76421be625abee9e5e290efee3d40`. The production source hashes above are retained separately in `plan.production_code_sha256`, the final results' `production_code_sha256`, every worker result's `engine`, and the complete artifact headers. Future harness output uses the clearer key `worker_result_sha256`; reading old evidence remains supported.

A read-only audit of all eight original and eight replay records verified the frozen plan/metadata, deposited source checksums, prepared CSV/request association, result-file hashes, source-code identities, complete artifact hashes/headers/counts, and numerical replay agreement. Its receipt is `../brohn-ppg-preserved-evidence-audit.json`, with `../audit_ppg_evidence.py` beside it. The replay adds a textual `tolerance_rule` explaining the unchanged strict WFDB boundary; output paths and result-file hashes differ by run. Event arrays, endpoint comparisons, interval errors, saved event-table declarations and pooled numerical scores agree. The audit did not rerun a worker or alter either evidence folder.

From the repository, with a new output folder outside it:

```powershell
$reader = 'C:/Users/User/Documents/Codex/2026-09-20/oka/work/reference-reader-venv/Scripts/python.exe'
$evidence = 'C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-ppg-capnobase-new'
& $reader tests/reference/ppg_capnobase.py prepare --output $evidence
& $reader tests/reference/ppg_capnobase.py run --output $evidence --methods-python '../../work/tooling/methods-venv/Scripts/python.exe'
& $reader tests/reference/ppg_capnobase.py render --output $evidence
```

For an exact replay of the original frozen plan, copy its `plan.json`, `plan.sha256`, `dataset-metadata.json` and `README-source.txt` into a fresh folder before `run`; copying its `source` folder avoids another download. The harness rejects a changed production source hash and refuses to overwrite a completed evaluation. `--resume` retains verified completed record results after a setup/reader interruption. A repeat remains a technical replay, not new held-out evidence.
