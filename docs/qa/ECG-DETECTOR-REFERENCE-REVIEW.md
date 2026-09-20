# ECG detector reference review

20 September 2026. Read-only method review of the first annotated ECG evaluation.
No detector setting, source polarity, filtering, correction or production profile
was changed during this review. The results identify an important limitation of
`ecg-neurokit-detected-rr/1.0`; they do not qualify a replacement or clinical HRV.

## Measured failure

`tests/reference/ecg_mitbih.py` ran the actual production worker on the first
300 seconds of the first MLII channel of four preselected MIT-BIH records at
360 Hz. Matching covers [2, 298) seconds after the frozen two-second edge rule.
The original WFDB files, download hashes, prepared CSV, worker result and
agreement results are retained at:

`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-reference-ecg-mitbih-01/`

The comparison uses WFDB Python 4.3.0 one-to-one annotation matching, separately
at 50 and 150 ms. It is not a bxb/EC57 certification. All beat classes are
detection targets; rhythm, blocked-P and other non-beat markers are excluded.
MIT-BIH annotation times generally identify the signal-0 R-wave landmark, but
annotation conventions and morphology still matter to timing interpretation.
See the [original WFDB annotation definition](https://www.physionet.org/physiotools/wpg/wpg_30.htm)
and [annotation codes](https://archive.physionet.org/physiobank/annotations.shtml).

| Record | Reference / detected | 50 ms: TP / FP / FN | 150 ms: TP / FP / FN | 150 ms sensitivity / PPV |
|---|---:|---:|---:|---:|
| 100 | 366 / 366 | 366 / 0 / 0 | 366 / 0 / 0 | 100.00% / 100.00% |
| 101 | 337 / 337 | 336 / 1 / 1 | 336 / 1 / 1 | 99.70% / 99.70% |
| 108 | 278 / 273 | 129 / 144 / 149 | 220 / 53 / 58 | 79.14% / 80.59% |
| 200 | 427 / 426 | 413 / 13 / 14 | 426 / 0 / 1 | 99.77% / 100.00% |

Record 108's matched detections at 150 ms have median signed timing error
−36.11 ms, median absolute error 38.89 ms and 95th-percentile absolute error
61.11 ms. The looser tolerance improves agreement substantially but does not
eliminate missed/extra detections. At 50 ms sensitivity is 46.40% and PPV 47.25%.

| Record | Rate from mean interval, reference → detected (bpm) | RR SD, reference → detected (ms) | RMSSD, reference → detected (ms) |
|---|---:|---:|---:|
| 100 | 74.23 → 74.23 | 38.83 → 38.91 | 56.03 → 56.21 |
| 101 | 68.35 → 68.35 | 59.96 → 64.53 | 32.61 → 53.16 |
| 108 | 56.24 → 56.16 | 97.64 → 154.26 | 132.97 → 212.23 |
| 200 | 86.59 → 86.38 | 153.19 → 178.41 | 271.83 → 323.97 |

These reference endpoints use **all annotated beats with the same interval
plausibility rule**. They are not normal-to-normal HRV ground truth. The table
demonstrates why count or mean-rate agreement cannot establish RR fidelity;
even record 101's one missed/extra pair materially changes RMSSD.

The actual runtime reports Python 3.12.10, NeuroKit2 0.2.13, NumPy 2.5.3 and
SciPy 1.18.1. The saved worker hash is
`959aa9a3f7b2c701bd37706ff04ddbe7f71d60f5d777bce11240c5b76a424cc6`.
The independent WFDB reader environment and every result hash are recorded in
`results.json`. The worker's `quality.usable=true` coexists with
`requires_research_review=true` and `scientifically_qualified=false`: usable
here means computation produced output, not acceptable beat detection.

## Mechanism supported by source and waveform inspection

`scripts/workers/physiology.py:494` cleans with NeuroKit and line 495 calls its
`neurokit` peak method with artifact correction disabled. No inversion step is
called. The pinned [NeuroKit 0.2.13 detector](https://github.com/neuropsychology/NeuroKit/blob/v0.2.13/neurokit2/ecg/ecg_findpeaks.py)
constructs candidate QRS regions from a smoothed absolute gradient, then
searches each **signed** segment for its most prominent local maximum.
The region envelope is insensitive to a global sign change; its final
fiducial selection is not. Its length and refractory rules can also reject
regions. The [pinned cleaning source](https://github.com/neuropsychology/NeuroKit/blob/v0.2.13/neurokit2/ecg/ecg_clean.py)
uses a 0.5 Hz high-pass followed by the selected power-line filter.

A separate read-only script,
`C:/Users/User/Documents/Codex/2026-09-20/oka/work/review_ecg_polarity.py`, compared
original MLII values at the frozen detected and reference sample indices.
Amplitude relative to the local ±150 ms median is a descriptive morphology
probe, not a polarity classifier or quality threshold. In record 108, 177 of
275 normal-beat reference landmarks are negative by this measure, whereas 264
of 273 detections are positive. Records 100 and 101 have no negative normal
reference landmarks by this same probe. Record 200 includes negative ectopic
landmarks; its normal landmarks are positive.

`independent-review/record108-morphology.png` displays original samples and both
sets of markers in four explicit windows: 10–18, 40–48, 100–108 and 280–288 s.
It was visually inspected. Early negative QRS landmarks are frequently missed
or preceded by positive selected points; the late window includes positive
landmarks that are closely matched. This is direct evidence consistent with
polarity-sensitive localization, including changing morphology within the
same evaluated segment. It does not establish that polarity explains every
error: candidate-region thresholds, noise, other deflections and reference
fiducial conventions also contribute. No alternative detector was run or
tuned to turn this diagnostic set into a passing result.

The [original record-108 notes](https://physionet.org/physiobank/database/html/mitdbdir/records.htm#108)
describe sinus arrhythmia, multiform PVCs and substantial **lower-channel**
noise/baseline shifts. This evaluation used the upper MLII channel; the lower
channel note is not sufficient evidence to explain its failure. The noted
7:41 axis shift is outside the evaluated first five minutes and is not used
as evidence for our observed within-window changes.

Do not silently enable a global inversion. NeuroKit's separate
[inversion utility](https://github.com/neuropsychology/NeuroKit/blob/v0.2.13/neurokit2/ecg/ecg_invert.py)
uses an aggregate sign decision; it is not proof of consistent morphology or
correct beat fiducials throughout a recording. Absolute-valued localization
could choose an S wave or another dominant deflection and also requires
independent qualification. Neither approach is a justified blanket patch.

## Immediate bounded product response

Expose exact saved detections on the **saved cleaned waveform**, with an
explicit unreviewed status, exact numerical rows and downloads. This addresses
the immediate visibility gap; it does not complete artifact editing or
establish NN intervals. Reviewing ECG alongside detected events is consistent
with [Laborde, Mosley and Thayer's recommendations](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2017.00213/full),
which warn against relying on automatic interval correction alone.

The proposed `brohn-cardiac-marker-overlay/1.0` contract should:

- Bind the complete event and series artifacts from the same immutable report
  and provenance hash. Match exact recording, channel, segment, source sample
  and saved time; reject any mismatch or mutated source. Keep local paths out
  of view/export data.
- Display all selected ECG R-peak or PPG systolic-pulse detections at their
  original matched cleaned-series values. Never interpolate a marker from a
  decimated line. Preserve markers even when the line uses extrema reduction,
  and include marker values in chart bounds.
- Retain event-table/row and series-table identities, source sample/time,
  saved previous interval and saved plausibility flag. Show null separately
  from false. A preceding interval may begin outside the selected window;
  label that fact without recomputing or implying within-window support.
- Return `available`, `empty` or `too_many_markers`; above the fixed 2,000-marker
  display bound, draw no partial overlay and offer a narrower window. Keep the
  complete event artifact downloadable. Empty means no selected detections,
  not absent heartbeats or a good-quality signal.
- Label these as **unreviewed algorithm detections**. A plausible interval,
  visible marker, opened chart or successful worker must never grant reviewed,
  NN, clinical, physiological-quality or device-qualified status. PPG remains
  pulse/PRV evidence, not ECG/HRV.

The existing complete series artifact contains cleaned values; this first
overlay must not promise a raw/clean toggle. Original recording export remains
available. A source-bound original-waveform viewer and immutable correction
ledger are separate follow-up work. A useful future correction contract would
retain additions/deletions/moves, reviewer and reason, original and revised
event lists, exact affected intervals and newly versioned reports.

## Requirements before changing a detector profile

1. Preserve `/1.0` saved results and pin any alternative as a new named method,
   including cleaning, polarity policy, detector parameters and dependency
   versions. Select the candidate from primary method evidence before further
   evaluation, rather than choosing the best score on these four records.
2. Independently constructed fixtures should contain positive, inverted,
   biphasic and changing-morphology beats with known fiducial times, variable
   intervals, missed/extra/noisy deflections, baseline drift, flat/clipped spans,
   boundaries and discontinuities. Check event timing and retained RR pairs,
   not only that an expected function was called. No bridging excluded gaps.
3. Freeze development records, held-out subjects/records, leads, durations,
   tolerances, beat classes and primary endpoints in advance. These four
   inspected records are now diagnostic/development evidence and cannot be
   described as an untouched holdout. Use full-duration annotated data and an
   independent recording source relevant to the intended population/device.
4. Retain per-record sensitivity, PPV, counts and signed/absolute timing errors
   at prespecified tolerances, with morphology/noise/beat-class strata. Check
   resulting RR, successive-pair support and endpoint errors as well. Avoid a
   single pooled result concealing a failed record, and retain unavailable
   records in the denominator. This review does not invent a universal passing
   sensitivity or physiological quality threshold.
5. Detection evaluation and NN/HRV validation are separate. Prespecify artifact
   and ectopy review, missingness/editing rules and suitable physiological
   protocols before claiming qualified HRV. Actual physical lead placement,
   contact, device filters and timing remain untested without equipment.

The marker overlay is therefore the recommended immediate connected scope.
Detector-method replacement remains open until the independent and held-out
work supports a specific, versioned change.
