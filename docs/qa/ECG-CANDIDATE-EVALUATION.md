# Offline ECG candidate evaluation

20 September 2026. **Do not replace the production detector with this candidate
yet.** A frozen WFDB XQRS candidate substantially improves the negative-landmark
failure in record 108 and some held-out timing results, but it retains extra and
missed events and worsens interval fidelity in other records. Production code,
its environment and all existing scientific reports were unchanged.

This is an executed comparison, not a qualification of ECG HRV, normal-to-normal
intervals, arrhythmia classification or physical equipment. It builds on the
[original detector review](ECG-DETECTOR-REFERENCE-REVIEW.md).

## Candidate chosen before the outcomes

`wfdb-xqrs-fixed-initialization-candidate/0.1` uses WFDB Python 4.3.0
`XQRS(original_signal_in_mV, fs, Conf()).detect(learn=False)`. All `Conf` values
are the library defaults: initial/min/max heart rate 75/25/200, QRS width 0.1 s,
initial/minimum threshold 0.13/0 mV, refractory period 0.2 s and T-wave inspection
period 0. The full config, implementation hashes and environment are saved.

The mechanism follows the [pinned original implementation](https://github.com/MIT-LCP/wfdb-python/blob/v4.3.0/wfdb/processing/qrs.py):
5–20 Hz filtering followed by squared Ricker moving-wave output, adaptive
thresholding and backsearch. It localizes maxima in that transformed output,
not positive maxima in the signed ECG. The optional initializer itself searches
positive signed peaks and correlates with a positive template; disabling it
avoids reintroducing that preference. This decision was fixed before any
candidate result was inspected. See the [official algorithm documentation](https://wfdb.readthedocs.io/en/latest/processing.html#qrs-detectors).

No sign flip, peak recentering, `correct_peaks`, ectopic correction or NN
classification was added. This is a different complete processing method from
production's NeuroKit 0.2.13 cleaning/detection: its bandwidth, localization,
initialization and refractory behavior differ. An improvement cannot be
attributed solely to polarity. Energy maxima can identify a different QRS
landmark, and default amplitude settings require the declared mV input.

The candidate ran in the isolated reader environment (WFDB4.3.0, NumPy 2.2.6,
SciPy 1.15.3). Existing production calls used the unchanged prepared methods
environment and original worker. No package was installed into production.

## Frozen experiment and its limits

The original plan was saved before downloading/evaluating held-out records at:

`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-ecg-candidate-xqrs-01/preselection.json`

Its SHA-256 is
`d11f0eb945f8c6d76f122e93b8da110c748f58cd8b4e5e6a3ad7b7deba71c76f`.
This is an internally frozen record, not an externally registered study.

- Previously inspected diagnostic records: 100,101,108,200.
- Preselected records not previously evaluated in this work: 103,105,111,117,207,213.
- Each uses original MIT-BIH 1.0.0 first-channel MLII in mV, first 300 s at 360 Hz.
  The harness stops if that declared channel/unit/rate differs.
- Evaluation covers [2,298) s. WFDB4.3.0 one-to-one location matching is performed
  separately at 50 and 150 ms. Every beat-annotation class is a target; non-beat
  markers are excluded. This is not a standard full-record bxb/EC57 evaluation.
- All sources, original event lists, production outputs, candidate indices,
  package/implementation hashes and comparisons remain outside the repository.
  All six held-out production baselines were executed through the actual worker;
  the four prior baselines were hash-verified and reused.
- The same 300–2000 ms plausibility rule is applied to reference and detected
  intervals. Adjacent-pair endpoints do not bridge rejected intervals. Additional
  paired errors require consecutive annotations matched to consecutive detections.
  These are **all-beat interval comparisons**, not validated NN HRV.

“Held out” refers to this development exercise. MIT-BIH may have informed the
library author's development; these records are not an independent external
validation of XQRS. Six five-minute excerpts also leave most of the database
and other acquisition settings untested. No record was removed after results.

## Important arrhythmia limitation in the frozen scoring rule

The original rule excludes ventricular-flutter-wave `!` annotations while
continuing to count detections inside flutter intervals. Thus its FP column is
an **unmatched-event tally relative to the chosen beat targets**. It cannot
automatically be interpreted as invented heartbeats during ventricular flutter.
The [primary record 207 notes](https://physionet.org/physiobank/database/html/mitdbdir/records.htm#207)
describe flutter and changing conduction morphology within the first five
minutes. This is a limitation of this exploratory comparator, not an excuse to
remove a difficult record or change its original outcome.

Post-outcome context, saved separately without rescoring the primary table:
97 of the candidate's 98 unmatched events at 150 ms lie within source-annotated
`[`/`]` flutter intervals;18 of the baseline's 20 do. Outside them, the counts are
one and two respectively. The candidate still misses 45 of 100 annotated PVC
targets in this record at 150 ms. Its detections are not an arrhythmia diagnosis.
Future validation must prespecify unsupported-rhythm and annotation handling,
including interval endpoints that span such episodes. The current all-beat
reference endpoints for207 are not physiologically meaningful HRV ground truth.

## Recorded outcomes

Each entry is **TP / unmatched FP / FN**. B=current production, C=frozen candidate.
The frozen counts include the flutter limitation above. Full per-record
sensitivity, PPV, timing-error distributions and beat/morphology strata are in
`results.json` and each record's `agreement.json`.

| Record / partition | 50 ms: B → C | 150 ms: B → C |
|---|---|---|
| 100 diagnostic | 366/0/0 → 366/0/0 | 366/0/0 → 366/0/0 |
| 101 diagnostic | 336/1/1 → 336/2/1 | 336/1/1 → 336/2/1 |
| 108 diagnostic | 129/144/149 → 257/70/21 | 220/53/58 → 257/70/21 |
| 200 diagnostic | 413/13/14 → 425/2/2 | 426/0/1 → 426/1/1 |
| 103 held out | 350/0/0 → 350/0/0 | 350/0/0 → 350/0/0 |
| 105 held out | 411/0/0 → 411/0/0 | 411/0/0 → 411/0/0 |
| 111 held out | 344/0/0 → 344/0/0 | 344/0/0 → 344/0/0 |
| 117 held out | 247/0/0 → 247/0/0 | 247/0/0 → 247/0/0 |
| 207 held out | 149/87/115 → 213/104/51 | 216/20/48 → 219/98/45 |
| 213 held out | 539/4/4 → 540/3/3 | 543/0/0 → 543/0/0 |

| Partition / tolerance | Production sensitivity / PPV | Candidate sensitivity / PPV |
|---|---:|---:|
| Diagnostic, 50 ms | 88.35% / 88.73% | 98.30% / 94.92% |
| Diagnostic, 150 ms | 95.74% / 96.15% | 98.37% / 94.99% |
| Held out, 50 ms | 94.49% / 95.73% | 97.50% / 95.16% |
| Held out, 150 ms | 97.78% / 99.06% | 97.92% / 95.57% |

These are descriptive pooled counts, not confidence bounds or release criteria.
The held-out PPV decrease is dominated by the flutter-target limitation and
must not be described as an established increase in physiological false beats.

Record 108 nonetheless supplies real mechanism-related improvement:50 ms
sensitivity rises 46.40%→92.45% and PPV 47.25%→78.59%. Negative local-landmark
matches rise 28/177→156/177, while all 101 nonnegative landmarks remain matched.
At150 ms its median absolute timing error improves38.89→2.78 ms and 95th
percentile 61.11→38.89 ms. But 70 unmatched events remain, with no annotated flutter
in this record. Its mean-interval-derived rate worsens 56.16→58.98 bpm against
reference 56.24, even though its RMSSD error becomes smaller. No single improved
endpoint establishes an acceptable replacement.

| Record | Reference RR SD / RMSSD (ms) | Production SD / RMSSD | Candidate SD / RMSSD |
|---|---:|---:|---:|
| 100 | 38.83 / 56.03 | 38.91 / 56.21 | 38.98 / 56.36 |
| 101 | 59.96 / 32.61 | 64.53 / 53.16 | 61.48 / 38.74 |
| 108 | 97.64 / 132.97 | 154.26 / 212.23 | 146.51 / 160.86 |
| 200 | 153.19 / 271.83 | 178.41 / 323.97 | 156.69 / 279.44 |
| 103 | 38.06 / 29.05 | 38.07 / 29.13 | 38.04 / 29.06 |
| 105 | 70.95 / 117.47 | 70.80 / 117.25 | 70.54 / 116.79 |
| 111 | 31.87 / 33.83 | 31.62 / 33.20 | 31.64 / 33.14 |
| 117 | 30.98 / 37.76 | 29.49 / 33.62 | 38.11 / 56.34 |
| 207* | 322.14 / 595.20 | 457.62 / 690.50 | 482.68 / 489.13 |
| 213 | 20.14 / 33.72 | 17.29 / 28.47 | 27.30 / 47.06 |

*207 includes unsupported flutter episodes in the original comparison; its
values are retained for transparency, not interpreted as HRV.*

Record 117 demonstrates a second limitation independently of unmatched counts:
both methods match every target even at 50 ms, but candidate interval jitter
increases. The 95th percentile absolute error for consecutive matched intervals
is27.78 ms versus 19.44 ms; its largest error is41.67 ms versus 22.22 ms. The
candidate can switch QRS landmarks as morphology changes. Reference annotations
also do not invariably sit on the visually largest extremum. Manual adjudication
of disputed fiducials is required before attributing every difference to the
detector. Record 213 similarly has perfect 150 ms matching but candidate interval
error95th percentile 36.11 ms versus 5.56 ms and larger RMSSD error.

## Independent morphology probes and visual review

Original analytically constructed pulse trains use independently specified
beat times with variable intervals. Positive, inverted and alternating-sign
trains each recover 32/32 targets with no extras and zero sample timing error.
A biphasic train recovers 32/32 with95th percentile 2.78 ms error. A dominant late
negative deflection produces 31/32 matches and 30.56 ms95th-percentile timing
error: sign symmetry does not establish the intended fiducial.

All five synthetic cases and all ten original reference signals return
**identical candidate indices after a full-signal sign reversal**. Flat input
returns no detections; the evaluation wrapper refuses nonfinite input instead
of repairing gaps. These probe a mechanism at 360 Hz only. They are not an
empirical artifact/noise, sampling-rate or hardware qualification.

The separately saved `diagnostic-context/candidate-waveform-diagnosis.png` was
visually inspected. It shows original MLII with reference, baseline and candidate
markers for108's10–18 s window,117's largest matched-pair interval error, and
207's first candidate unmatched event outside flutter after 10 s. Window-selection
rules are recorded in `supplemental-context.json`; this post-outcome illustration
neither tunes the method nor changes the original scores.

## Reproduction and next qualification step

The portable harness is `tests/reference/ecg_candidate_evaluation.py`.
`prepare` refuses to overwrite a plan, hashes the candidate/production/harness,
and freezes the dataset and analysis rules before `run`. `run` verifies those
identities, keeps source files bounded and outside the repository, records every
original file hash, and refuses to overwrite completed results. The original
work-directory harness remains retained with its original frozen hash.

The repository harness was independently rerun as a **technical reproduction**,
explicitly linked with `--reproduce-plan` to the original plan. All ten event
lists, reference/candidate/baseline comparisons, interval endpoints, synthetic
results and source hashes matched exactly. This is not additional held-out
evidence. Its receipt is:

`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-ecg-candidate-xqrs-replay-01/reproduction-check.json`.

Example from the repository root, using the separate prepared reader Python:

```powershell
$reader = 'C:/Users/User/Documents/Codex/2026-09-20/oka/work/reference-reader-venv/Scripts/python.exe'
$prior = 'C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-reference-ecg-mitbih-01'
$plan = 'C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-ecg-candidate-xqrs-01/preselection.json'
$output = 'C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-ecg-candidate-reproduction-new'
$methods = (Resolve-Path '../../work/tooling/methods-venv/Scripts/python.exe').Path
& $reader tests/reference/ecg_candidate_evaluation.py prepare $output --prior $prior --methods-python $methods --reproduce-plan $plan
& $reader tests/reference/ecg_candidate_evaluation.py run $output --prior $prior --methods-python $methods
```

The defensible next step is a newly frozen development/validation contract,
not turning on this candidate. Preserve these observed records as development
evidence. Specify how QRS landmarks, flutter/unreadable episodes, excluded spans
and transitions affect detection and interval denominators. Require source-bound
manual review for disputed landmarks and retain each correction rather than
rewriting annotations to favor an algorithm.

Then test any revised method on new, uninspected full-duration recordings and
an independent acquisition source, with per-record and rhythm/morphology results,
strict timing errors and downstream interval support. Include noise conditions
such as the [original MIT-BIH Noise Stress Test resource](https://physionet.org/content/nstdb/1.0.0/)
and sampling/unit changes, without treating that derived resource as independent
participants. Freeze tolerances and intended endpoint requirements before use;
do not choose an algorithm by the best aggregate score on already inspected
records. Use the appropriate [reference comparison protocol](https://physionet.org/physiotools/wag/bxb-1.htm)
if a standards-based claim is eventually sought.

Any approved future candidate needs a new named production recipe, source and
parameter pinning, complete marker/interval artifacts and retention of old
reports. At this checkpoint, the exact unreviewed marker display remains the
production response; detector replacement, qualified NN HRV and physical-device
validation remain open.
