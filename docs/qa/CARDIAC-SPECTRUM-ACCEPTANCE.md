# Cardiac interval spectrum acceptance

20 September 2026. Original software fixtures only; no physical equipment,
participant qualification or annotated empirical ECG benchmark is claimed.

The existing ECG and PPG candidate frequency metrics now retain their complete
Welch density in an additional frequency table inside the existing immutable
`physiology-events` artifact. Temporal detected peaks retain their separate table,
source sample indices and original clock reference. Artifact row totals include
both typed tables; detected-peak support counts remain peak counts.

The saved `brohn-cardiac-interval-spectrum/1.0` support specifies:

- `detected_r_peak_intervals_rr` versus `detected_pulse_intervals_prv`, a readable
  `rhythm_basis`, and `normal_to_normal_confirmed: false`;
- every 0–2 Hz bin, frequency in Hz and density in ms^2/Hz;
- linear interval-endpoint interpolation at 4 Hz without extrapolation;
- SciPy Welch, DFT-even Hann, 128 s / 512 samples, 50% overlap, constant
  detrending per segment, mean one-sided density, exact FFT/bin settings;
- interval/peak counts, peak span, required duration, interpolation support,
  source segment start and number of averaged windows;
- LF `[0.04, 0.15)` and HF `[0.15, 0.4]`, integrated as the sum of complete
  included density bins times the exact frequency-bin width. There is no
  interpolated band edge or separate plotting estimator.

Insufficient duration, fewer than ten intervals or any rejected interval leaves
frequency powers unavailable and produces no spectral table. The declared minimum
peak span is at least 300 s. Actual constant intervals can yield zero density and
zero band powers; division by zero leaves LF/HF unavailable with its reason.
This support rule is an existing software recipe, not a universal quality rule.

The existing background signal explorer discovers the typed frequency table and
plots it in Hz and ms^2/Hz. It renders the declared bands, basis, estimator, exact
full-spectrum powers and support. Narrowing a displayed range does not relabel
the saved full-spectrum powers as window-specific estimates. Source/report/worker
and artifact-writer hashes remain bound by the existing publication path.
The plot explicitly says detected intervals require review, PPG variability is
PRV, normal-to-normal HRV is not established, and LF/HF is not a stress or
sympathovagal-balance measure.

## Executed evidence

- `tests/workers/cardiac_spectrum.py`: 5 tests. The numerical oracle implements
  independent segment-wise NumPy DFT/Hann normalization and compares all 257
  density bins, then verifies exact band integration and known 0.1/0.25 Hz
  modulations. It also checks unavailable support, legitimate zero density,
  distinct bases, actual ECG/PPG detectors and complete typed artifact roundtrip.
- Existing `tests/workers/physiology.py`: 18 passed, 2 skipped because audio and
  fNIRS require their separate prepared environments.
- Existing `tests/workers/physiology_artifacts.py`: 24 passed, 2 skipped for those
  same separate audio/fNIRS environments. Six standard modalities pass.
- `tests/platform-cardiac-spectrum.R`: 22 passed across six actual supervised
  ECG/PPG analysis, catalog and preview jobs. Exact artifact bins reproduce report
  LF/HF, provenance/basis remain explicit, plots use real bins, immutable reports
  and original source hashes stay unchanged, and saved reports/views reopen.
- `tests/researcher-cardiac-spectrum.mjs`: 25 passed using those actual saved
  previews and the production renderer, both 1440 px and 390 px wide. Four axe
  scans clear; no page overflow or sub-44 px controls; one responsive chart per
  page with the two declared bands. Desktop and narrow screenshots were inspected.
  A final display-only refinement anchors nonnegative cardiac density at zero
  and gives narrow tick labels more space; the renderer/browser checks were
  repeated using the same immutable saved previews.

Evidence is retained under `../../work/test-runs/brohn-cardiac-spectrum-20260920`
with worker/browser result JSON, four accessibility receipts, four screenshots,
exact saved view JSON and downloadable SVGs. Chrome exercised the production
component; this is not an additional full application click-through. The existing
generic signal-explorer journey is separate prior evidence.

Commands use the prepared `methods-venv` Python, native Windows Rscript with
`R_LIBS_USER=../../work/r-library-brohn-restore`, and
`BROHN_PUBLICATION_PYTHON=../../work/tooling/methods-venv/Scripts/python.exe`.
Run the R suite before the browser suite to recreate its evidence.

This slice does not turn descriptive acquisition monitoring into a signal-quality
verdict and does not qualify cardiac detectors against an annotated empirical
corpus. Academic interpretation limits are retained in
`docs/qa/MEASUREMENT-ACADEMIC-ACCEPTANCE.md`.
