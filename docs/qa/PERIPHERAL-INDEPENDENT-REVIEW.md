# Independent review of calibrated temperature and acceleration

Reviewed 2026-09-08 against the master architecture, prepared capability register,
peripheral worker/domain/views and the connected signal-artifact contracts.
This is independent software and researcher-semantics review using original
synthetic values. It is not observed human usability, empirical sensor accuracy
or evidence of psychological construct validity.

## Scope and reference definitions

This pack describes already calibrated imported temperature and three ordered
acceleration channels. Calibration, sensor placement, acquisition filters and
recording conditions are source declarations. It does not calibrate raw counts,
estimate thermal ROIs, subtract a recorded physiological baseline, reconstruct
motion trajectories, or classify an emotional or medical state.

The conversion checks use standard gravity 9.80665 m/s² per g and the Celsius,
Kelvin and Fahrenheit offsets in the [NIST unit conversion reference](https://www.nist.gov/pml/special-publication-811/nist-guide-si-appendix-b-conversion-factors/nist-guide-si-appendix-b8).
Standard gravity is a conversion constant; it is not a measurement of local
gravity or a sensor-calibration result.

The zero-truncated ENMO check subtracts one g from each sample's vector magnitude,
clips each negative result, then averages. This matches the operation order in
the [GGIR authors' acceleration metric documentation](https://wadpac.github.io/GGIR/articles/chapter4_AccMetrics.html).
Brohn's explicitly untruncated alternative is separately labelled and recorded.
Neither route runs GGIR's free-living calibration, epoch aggregation or activity
classification pipeline. [GGIR's calibration documentation](https://search.r-project.org/CRAN/refmans/GGIR/html/g.calibrate.html)
describes a separate estimation procedure; declaring units does not perform it.

## Independent execution

The original [independent test suite](../../tests/workers/peripheral-independent.py)
contains 19 bounded tests. It builds fresh CSV bytes and computes its oracles with
explicit sample lists, rational arithmetic and ordinary mathematical identities;
it does not call production helpers to generate expected values. The signal
checks call the real downstream preview module on full typed artifacts.

Command from the repository root:

```powershell
& '../../work/tooling/methods-venv/Scripts/python.exe' tests/workers/peripheral-independent.py
```

The first unchanged 16-test execution passed 15 tests and exposed the low-rate
default defect below. The final **19-test retake passed** after the owner added
the new temperature provenance field and corrected omitted defaults. Its
[actual execution log](../../../../work/test-runs/brohn-peripheral-independent/test-output.txt)
and [executed source hashes](../../../../work/test-runs/brohn-peripheral-independent/source-hashes.json)
are retained. This execution used direct numerical/preview calls; it did not
launch an application, publication queue or physical device.

| Original counterexample | Independent expected result |
|---|---|
| Temperatures 1, 2, 4 at seconds 0, 1, 2 | Sample mean 7/3; trapezoidal time mean 2.25; sample SD √(7/3); linear slope 90 °C/min. |
| Temperatures 0, 4, 2 at seconds 0, 0.8, 2, with declared tolerance | Sample mean 2; time mean 2.6; rational OLS uses actual intervals. |
| −40, 0, 100 °C represented independently as K and °F | Endpoint change 140 °C and time mean 15 °C; source unit offsets do not become differences. |
| Magnitudes 0.5, 1.5, 0.5 g | Zero-truncated ENMO mean 1/6 g; untruncated mean −1/6 g. Clipping the mean instead would be wrong. |
| Unit gravity vector rotating between signed Cartesian axes | ENMO zero; recorded-vector derivative RMS is 9.80665√2 m/s³. Rotation is not translational movement. |
| Constant norm with changing vector direction and 0.8/1.2-second intervals | Nonzero derivative from the actual vector differences and intervals, with two valid differences. |
| Return to the same control/person/exposure after another group | Three separate recording intervals; no sorting, pooling or invented people. |
| Finite samples separated by a clock gap or missing selected axis | Separate support and derivatives; observed axes remain available, derived vector at the missing sample is null. |
| Below-threshold values exactly at entry/return boundaries | Entry is inclusive; recovery is strictly beyond the return boundary; observed span is independent of recovery time. |
| Threshold active either side of a missing row | Separate left/right-censored excursions; no duration assigned across the missing row. |
| Two active observations one second apart, requested duration two seconds | Zero qualifying excursions on eligible support; no extrapolated final sample cell. |
| Detector requested with all-invalid or insufficient support | Event count unavailable, rather than a false zero. |
| 0.1 Hz input with omitted versus explicitly invalid duration | Absent default supports the 10-second sample interval; explicitly chosen invalid one-second minimum is rejected. |
| 2,003 samples with original integer clock beyond binary64 exact integers | Full artifact retains every source row and exact clock string, despite the 2,000-row preview. |
| Downstream preview with missing rows, a clock gap and a finite but too-short tail | Exactly three supported fragments and six plotted rows; no connector across the gap or plotted excluded tail. |
| Full threshold-event artifact | One numeric time coordinate, canonical value unit, separate event points without connecting lines. |

## Findings and corrections

1. **Slow-rate default:** supported 0.1 Hz data with no explicit settings failed
   because a fixed one-second default was shorter than one sample interval.
   Normalize only omitted defaults to `max(1, 1 / sampling_rate)` in both R and
   Python. Explicit invalid researcher settings must still fail. The first
   independent run reproduced the failure on `(0,20), (10,21), (20,22)`.
2. **No support is not a negative finding:** a requested threshold initially
   returned zero events even when no interval was usable. The owner corrected
   this to null before our first execution; all three independent no-support
   cases passed. Report copy must preserve that distinction.
3. **Plot support contract:** the owner found and corrected missing shared
   retention/source-index/cadence metadata and multiple event-coordinate roles.
   The independent downstream tests cover the resulting gap and exclusion
   behavior. These aliases describe original rows and support; they are not
   resampling or invented sample timestamps.
4. **Recording context and threshold language:** temperature preparation calls
   for ambient conditions and equilibration. The mapping now needs one explicit
   recording-conditions/settling-time declaration, with unknown allowed.
   Threshold wording should describe protocol-defined excursions, inclusive
   entry, strict recovery and censored boundaries; activity present at the first
   sample is not an observed onset crossing.
5. **Synthesis needs its own adapter:** the generic physiology extractor cannot
   directly consume the new per-support identities and nested recipe structure.
   Root added a dedicated adapter preserving original feature rows/hashes and
   matching support interval, recording, channel, group and sample/span evidence.
   Its shared engine retains equal-observation weighting within session and
   equal-person inference; it does not silently duration-weight intervals.
   Fragmented observations with the same actual exposure must retain duplicate
   identity rejection until a reviewed within-exposure aggregation exists.
6. **Ordered source axes belong to a synthesis definition:** movement uses a
   constant vector outcome label. The ordered `value_columns` must also enter
   the definition so different selected triplets do not appear identical merely
   because their site/calibration/orientation descriptions match. This was sent
   to root as a concrete comparison-definition review finding.

## Browser acceptance after integration

Use an original controlled packaging study with declared people, repeat sessions,
conditions and exposure IDs. Import the temperature and acceleration fixtures;
review exact source units/axes/calibration/context; retain original bytes; queue
the real analysis and inspect source-separated intervals. Download complete
CSV/JSON and typed series/events, then reopen the saved report. On desktop and
390-pixel viewports, check accessible controls and readable units/support reasons.

For the combined-study route, explicitly review identity links and choose one
temperature or acceleration contrast beside liking. Check independently expected
person-level differences; confirm that different source triplets/settings cannot
silently combine and that a fragmented same-exposure comparison stays unavailable.
Plot missing/gapped support using full artifacts, and confirm current range and
channel selections survive job completion and viewport changes. The separate
[actual researcher journey](PERIPHERAL-RESEARCHER-JOURNEY.md) now passes48
assertions and eight accessibility scans, including source ingestion, real
scientific workers, the combined comparison and the first-time0.1Hz UI correction.
That application evidence complements the19 independent numerical tests above;
it does not establish physical-device accuracy or observed human usability.

Thermal cameras/ROI tracking, recorded-baseline contrasts, force/pressure/GPS,
gyroscope fusion, device calibration and empirical research qualification remain
separate capabilities in the broader platform roadmap.
