# ECG recorded-reference evaluation — unresolved accuracy finding

Executed 20 September 2026. The production detector completed all four recordings,
but the result **does not pass a broad automatic ECG accuracy claim**. Record 108
has many missed, extra and displaced detections. Plausible mean heart rate alone
does not establish beat-timing accuracy or acceptable interval variability.

## Fixed comparison and provenance

`tests/reference/ecg_mitbih.py` selects records 100, 101, 108 and 200 before evaluation,
uses their first 300 seconds and first MLII channel at 360 Hz, and evaluates the
retained interval `[2,298)` seconds. These are a small subset of the published
[MIT-BIH Arrhythmia Database 1.0.0](https://physionet.org/content/mitdb/1.0.0/), which
provides cardiologist-reviewed beat annotations. Original `.hea/.dat/.atr` files,
converted mV CSVs, SHA-256 download manifest, requests, original worker outputs,
environment versions and complete comparisons remain outside the repository:

```text
C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-reference-ecg-mitbih-01/
```

Data attribution: Moody GB, Mark RG. The impact of the MIT-BIH Arrhythmia
Database. IEEE Engineering in Medicine and Biology 20(3):45–50 (2001).
PhysioNet dataset DOI:10.13026/C2F305. Files use Open Data Commons Attribution
License 1.0. No reference recording or participant-level waveform is committed.

The actual production CLI runs `ecg-neurokit-detected-rr/1.0`, NeuroKit2 0.2.13,
NumPy 2.5.3 and SciPy 1.18.1 on Windows Python 3.12.10. Settings are declared 60-Hz
powerline and 2-second edge exclusion, with existing 300–2000 ms interval bounds.
No detector setting was tuned against these outcomes. Worker SHA-256:
`959aa9a3f7b2c701bd37706ff04ddbe7f71d60f5d777bce11240c5b76a424cc6`.

A separate pinned WFDB 4.3.0 environment reads references and compares locations.
The script asserts that the event list is complete, not a truncated preview,
and that sample indices, counted peaks and unchanged worker hashes agree.
All annotation classes denoting beats are detection targets; rhythm and other
nonbeat markers are excluded. This does not establish normal-to-normal intervals.

## Observed detection agreement

The two matching tolerances are reported separately. Sensitivity=matched/reference
beats; positive predictive value (PPV)=matched/detected peaks. Matches are one-to-one
using [WFDB compare_annotations](https://wfdb.readthedocs.io/en/latest/processing.html).
This exploratory subset is **not** the standard `bxb`/EC57 benchmark or compliance
test. No acceptance threshold was selected after looking at the results.

| Record | Tolerance | Matched | Extra | Missed | Sensitivity | PPV | 95th percentile absolute timing error of matches |
|---|---:|---:|---:|---:|---:|---:|---:|
|100|50ms|366|0|0|100.00%|100.00%|2.78ms|
|100|150ms|366|0|0|100.00%|100.00%|2.78ms|
|101|50ms|336|1|1|99.70%|99.70%|2.78ms|
|101|150ms|336|1|1|99.70%|99.70%|2.78ms|
|108|50ms|129|144|149|46.40%|47.25%|41.67ms|
|108|150ms|220|53|58|79.14%|80.59%|61.11ms|
|200|50ms|413|13|14|96.72%|96.95%|44.44ms|
|200|150ms|426|0|1|99.77%|100.00%|47.22ms|

Independent calculations from the reference annotations use the same plausibility
bound and preserve adjacency without creating pairs across rejected intervals.
For record 108, reference/detected mean-interval-derived heart rates are 56.240 and
56.155 beats/min; RR sample SD is 97.640 versus 154.256 ms, and RMSSD is 132.973
versus 212.232 ms. For record 200, RR SD is 153.193 versus 178.405 ms and RMSSD is
271.826 versus 323.966 ms despite near-complete matching at 150 ms. A loose
beat-matching window cannot qualify variability endpoints. These are descriptive
all-beat reference comparisons, not clinical HRV ground truth.

## Required follow-through

- Investigate polarity, morphology and noise against the original annotations
  and the named upstream detector implementation. Retain the failing result.
- Preserve raw signals, exact detected markers and review support. A successfully
  computed report or a finite waveform must not be labelled scientifically usable.
- Any changed method needs its own frozen recipe and provenance, independent
  signed/morphology/noise cases and a predeclared untouched evaluation set.
  Do not select a detector based only on these four observed outcomes.
- Broader annotated recordings, target-population agreement, timing-sensitive
  endpoints and device accuracy remain unqualified. No physical sensor was tested.

Reproduce with an isolated reader environment installed from
`tests/reference/requirements-wfdb.txt`, then run:

```powershell
<reader-python> tests/reference/ecg_mitbih.py --output <outside-repository-folder> --methods-python <production-methods-python> --download
```

The first reader attempt exposed WFDB 4.3.0 incompatibility with Pandas 3; the
separate reader environment was pinned to Pandas 2.2.3/NumPy 2.2.6/SciPy 1.15.3.
Production scientific dependencies were unchanged. Full reader package versions
are retained in `results.json`. This execution exercises the production Python
worker. Follow-up `tests/reference/ecg_marker_review.R` passed five checks across
three actual supervised jobs: preserved public record 108 import, production
analysis, exact saved-marker view and reopening. Evidence:
`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-cardiac-reference-02/`.
The 10–18-second view preserves exactly the original detector's event samples,
times and previous intervals, including its errors; analysis and source hashes
remain unchanged. This is pipeline/display fidelity, not improved detector
accuracy. Full researcher browser interaction is recorded separately.
