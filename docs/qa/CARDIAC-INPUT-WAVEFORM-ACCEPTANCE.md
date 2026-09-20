# ECG/PPG input waveform and saved detection review

20 September 2026. Scoped acceptance: component/storage, recorded-reference and
the full researcher-browser journey passed.
This is display/source preservation work, not detector correction or qualification.

New ECG/PPG complete series preserve every unit-converted input sample (`raw`)
alongside `clean`, the existing retention flags and original analysis-input row
indices. These values precede Brohn cleaning; acquisition filters may already
exist. Source bytes, calibration/mapping and clock identity remain authoritative.
Other modality writers keep their existing raw-omission policy. If no series was
produced, the result must not claim that input samples were preserved.

The researcher chooses input or cleaned waveform. Cleaned remains the default.
Both use the same exact saved detection sample indices/times, previous intervals
and plausibility flags. The input view plots the corresponding input amplitude;
it does not rerun detection, relocate peaks or grant review/NN status. Tables,
accessible SVG descriptions and exports identify which waveform supplies the
amplitude and that detection came from the cleaned signal.

New requests use `processed-signal-view/1.2.0`; overlay format1.1 adds explicit
`waveform_column` and `detection_basis`. Historical format1.0 remains readable
only as a cleaned-waveform overlay. Old clean-only reports do not acquire an
invented input column. An explicit new analysis is required to produce it.
Exact report/artifact/clock/table/method joins and the 2,000-marker all-or-none
display bound remain unchanged. Over-limit counts keep alignment unchecked.

The existing plot eligibility rule applies to both columns: analysis-excluded
edge samples remain in the complete input artifact but are not drawn. This
limitation is stated in the input table disclosure and support counts. A full
artifact-review/recalculation workflow is separate outstanding work in
[the proposed contract](../methods/CARDIAC-ARTIFACT-REANALYSIS-CONTRACT.md).

## Executed evidence

- Python marker suite:23 passed, including exact raw values, unchanged events,
  no invented legacy input, missing/excluded refusal, range and over-limit rules.
- Existing signal preview suite:24 passed.
- Complete artifact suite:24 passed with2 unrelated runtime-profile skips.
  Its actual six-modality check verifies complete ECG/PPG source values against
  independent declared conversion, and unchanged feature/event results.
- Added short-PPG regression:1 passed after independent review found a metadata
  flag claiming duplicated input when no series existed. The flag now requires
  an actual series manifest.
- R storage/render suite:51 passed with8 actual supervised jobs, immutable source
  reports, raw/clean exact values, legacy cleaned views, substituted basis/column
  refusal, full exports and reopen. Evidence:
  `C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-cardiac-markers-03`.
- Recorded reference regression:22 checks with8 actual supervised jobs pass on
  known MIT-BIH108 ECG and CapnoBase0123 PPG. All features and saved events exactly
  match prior reference execution, all plotted input values/markers match the
  original CSV with the declared conversion, and reports/views reopen unchanged.
  Evidence: `C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-cardiac-input-02`.
- Actual researcher browser:21 checks and4 clear accessibility/reflow scans pass
  across ECG/PPG at1440 and390 pixels. Exact visible ranges, input/clean switching,
  original detection identities/amplitudes, keyboard table access, JSON/SVG
  downloads, unchanged report bodies and fresh-page reopening all pass.
  Evidence: `C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-cardiac-input-ui-01/browser-1789887191696`.
  The ECG narrow and PPG desktop charts were also visually inspected.

The first public-reference run successfully published ECG report, catalog and
both waveforms, then failed the test's CSV comparison because R `identical()`
distinguishes an integer-valued JSON number from an equal R double. An independent
check verified all671 plotted values and coordinates exactly after normalizing
numeric storage type. No rounding or tolerance was introduced. This failed run
is retained in `oka/work/brohn-cardiac-input-01`; it is not final acceptance.

Reference regression harness: `tests/reference/cardiac_input_review.R`, taking the
existing MIT-BIH evidence root, CapnoBase evidence root and a fresh external
`brohn-cardiac-input-*` output folder. It compares unchanged reference features,
events and original samples, then reopens the saved reports. It uses known
regression records108/0123; these are not new holdouts.

Browser harness: `tests/researcher-cardiac-input.mjs`, taking a fresh external
`brohn-cardiac-input-ui-*` folder and the accepted reference output. It operates
the actual researcher/worker and checks both waveform choices, keyboard/table
use, exact JSON/SVG, source preservation, restart and desktop/narrow layout.
The first browser attempt passed the ECG source/range/table/SVG checks, then its
accessibility harness required an explicit Playwright browser context. The
harness was corrected and the full journey rerun successfully against the same
saved workspace. The failed attempt remains in
`oka/work/brohn-cardiac-input-ui-01/browser-1789887003374`; no report or scientific
output was changed to make the test pass.
