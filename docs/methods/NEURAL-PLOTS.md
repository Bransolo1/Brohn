# Saved neural response plots

`R/platform-neural-views-plots.R` is a read-only presentation adapter for the
three explicit recipes in [NEURAL-RECIPES.md](NEURAL-RECIPES.md). It reads the
complete arrays retained by `scripts/workers/neural.py` inside the immutable
report. The neural worker currently refuses arrays above its 500,000-value
bound; these results are not previews of an untracked external matrix.

The UI does not run EEG processing, choose an electrode ROI, average cells,
correct a baseline, compute SNR, interpolate frequencies, or infer a component.
Raw source objects, report bodies, processing hashes and frozen settings remain
unchanged. A successful chart is software presentation evidence, not device
timing or research-method qualification.

## What the researcher sees

| Recipe | View | Retained meaning |
| --- | --- | --- |
| ERP | Mean voltage with pointwise mean +/- saved trial SEM | Microvolts, positive upward; uncertainty is within one recording/condition, not a participant confidence interval. One trial has no SEM. |
| Morlet | Time course at one explicitly selected recorded frequency; transformed power, original power or ITC | Exact frequency-by-time rows; the power unit follows the frozen baseline transform. ITC uses original total-signal phases even when induced power was selected. |
| Frequency tagging | Mean trial PSD with saved target-bin markers | uV^2/Hz density, with existing target, neighboring noise and SNR features. No integration or new target choice occurs in the view. |

Selecting a cell includes its recording, condition, channel and complete source
group. Participant, session, exposure and segment labels remain distinct. A
repeated label is not a request to pool people or concatenate reset segments.
Unavailable conditions stay visible in the recording support table and produce
no zero waveform.

The default plot displays up to 2,000 **consecutive exact saved samples**, and
the first-index control can inspect any later window. Counts state the selected
indices, complete trace size and missingness. It never substitutes a subsampled
or averaged waveform. Straight segments are visual guides between neighboring
available saved points; null values disconnect the line. Morlet wavelet edges
are absent according to their retained support. There is no heatmap suggesting
measurement at intermediate, uncomputed frequencies.

Each plot displays trial retention/exclusion/minimum counts, origin, units,
voltage baseline, reference and filter. Morlet power-baseline parameters and
excluded edge samples, or frequency-tagging spectral window/taper/bin width,
are explicit. Expandable details retain the full saved settings, measured-onset
alignment statement, support and source/report hashes. The numerical preview
shows up to 50 selected points and states that limit.

## Verification and bounds

The model checks the registered worker/result schema and recipe; the analysis
source SHA-256 must equal its report-pinned source. Each channel has exactly one
recording/condition/source-group support record and the same retained trial
count and origin. Trial counts reconcile requested, retained and excluded.
ERP and Morlet time axes must agree with the actual sampling rate, frozen epoch
and Morlet edge exclusions. PSD bins must agree with the retained FFT size and
sampling rate. Unordered, irregular, wrong-length or transposed arrays fail
visibly; the UI does not repair them.

Values must be finite numeric scalars or explicitly allowed nulls. Strings and
booleans cannot become measurements. SEM and power cannot be negative; ITC
cannot leave 0..1. Morlet transformed units must agree with the frozen power
baseline mode. The complete array bound is 500,000 values and the view catalog
has a 10,000-cell/recording bound. Malformed results retain the original
numerical report while the plot explains the unmet contract.

## Exports and accessibility

* **Download complete channel series:** all saved samples for the selected
  recording/condition/channel. For Morlet this includes every retained
  frequency and all three arrays, regardless of the currently selected trace.
  Empty CSV cells mean missing values. Coordinate units, group JSON and source/
  report hashes travel with the data; source text receives spreadsheet-formula
  protection without changing measurement columns.
* **Download series + provenance:** exact original typed series, features,
  support, parameters, source/processing provenance and selected display window.
  JSON preserves nulls and the original source labels exactly.
* **Download displayed chart:** standalone SVG for the current exact window,
  with readable title/description and report/source hashes, retained trials,
  baseline and recipe identity embedded in the accessible description.

Wide and 320-pixel compact SVG layouts have explicit accessible descriptions and
numerical alternatives. Styling is scoped and embedded so static HTML exports
reflow without depending on the live Shiny stylesheet. No external media or
script is loaded by the plot. All labels are escaped through htmltools. The
immutable report hash scopes cell selectors, and a separate form identity
blocks stale controls or downloads after switching report/channel or navigating
away. Numeric entry errors remain visible without altering the report.

## Integration

Source `R/platform-neural-views-plots.R` after the core, report table and shell
helpers. Shared integration is owned by the app coordinator:

```r
# Immutable report body in the report detail UI:
brohn_neural_explorer_ui(report)

# Once in the researcher server:
brohn_install_neural_plots(input, output, session, store, state,
                          attempt, message, prepare_download)

# Read-only standalone report HTML; defaults to its first supported cell:
brohn_neural_report_plots(report)
```

Pure helpers are `brohn_neural_plot_model(report)`,
`brohn_neural_plot_selection(model, selector, metric, frequency_hz, start_index,
maximum_points)`, `brohn_neural_plot_svg(view, width = 680)` and
`brohn_neural_plot_csv(model, selector, path)`. The static report states how many
other cells remain in the full report; the live selector reaches every cell.

## Evidence

`tests/platform-neural-views-plots.R` passes **47 checks** using fresh actual
worker outputs from the original synthetic numerical fixtures. The pulse stays
10 uV with three retained trials; the stationary sine retains its approximately
one power-baseline ratio and phase consistency; the known tagged sine retains
400 uV^2/Hz at 10 Hz. Checks include exact matrix orientation and series values,
missingness, null gaps, full CSV rows beyond the displayed preview, source and
trial/grid/unit/type refusal, escaped hostile labels, immutable report
preservation, and real Shiny report/form/window/navigation guards.

`tests/researcher-neural-plots.mjs` now passes **66 actual Chrome/Shiny checks**,
including **7 axe scans** with no violations. Through the researcher UI it
imports an original two-channel EDF pulse, authors measured event lists,
baseline/rejection rules and each recipe, then obtains the actual supervised
ERP, Morlet and frequency-tagging reports. Independent expectations are
10/20-uV evoked pulses, stationary Morlet ratio/phase support, and target
density 400, neighboring noise density 4 and SNR 100. A zero channel retains
undefined ratios/phase/SNR as null while its raw power/PSD stays zero.

The browser checks verify source/result objects and report hashes, exact
frequency/channel/window persistence, full CSV/JSON/SVG exports, historical
report reopening in a fresh session, actual 390-pixel SVG label bounds and
standalone HTML reflow. Two discovered display defects were fixed: long tick
labels from tiny native voltage residuals, and the generic export serializer
losing its HTML head. Tick formatting preserves the original tiny values;
the shared exporter now retains its title, viewport and CSS. Desktop and
compact screenshots were also visually inspected.

Original fixtures are in `tests/fixtures/researcher-neural-plots.py`. Local
evidence is under `work/test-runs/brohn-neural-plots-ui-evidence/` outside the
repository. These are real software journeys with original synthetic data;
they do not assert physical-device qualification or testing with participants.
