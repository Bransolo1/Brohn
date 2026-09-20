# Complete saved time-frequency map

20 September 2026. This view displays complete immutable Morlet arrays for one
recording, condition and channel. It is not new EEG processing or evidence of
physical device qualification. Source origin and the [baseline limitations](NEURAL-BASELINE-ACCEPTANCE.md)
remain visible.

## What is actually encoded

The map includes every saved time sample at every requested frequency, even
when the exact frequency slice is displaying only seven or 2,000 samples.
Frequencies appear as equally spaced **discrete rows** with their actual Hz
labels. Their row height does not imply a frequency bandwidth, and there are
no invented intermediate frequencies.

A lossless PNG contains one native pixel per saved frequency/time cell. The
lowest frequency is the bottom row; no transpose, frequency sorting or source
array mutation occurs. The PNG is embedded in the standalone SVG and HTML,
with no external image request. Colour is quantized to 256 display levels.
This changes no saved value. CSS nearest-neighbour scaling is display-only;
at a small viewport, multiple native time cells may not be individually
resolvable. The UI says this and provides the exact frequency slice and
complete numerical CSV/JSON. No resampling, averaging or interpolation is
performed on the scientific matrix.

The visible domain is the frozen epoch, extended half a sample at each end
solely to show sample-centred cells. The retained image covers the corresponding
half-sample bounds of the saved time axis. Excluded wavelet edges remain
hatched, with the exact excluded sample count retained. Missing saved values
are grey. Observed zero values use the quantitative scale and remain visually
different from missing values. A wholly missing measure still has an explicit
mask map, but has no quantitative colour scale or invented zero waveform.

## Scale and controls

| Measure | Complete-channel colour rule |
|---|---|
| Raw wavelet power; uncorrected power | Sequential, zero to observed maximum. An entirely observed-zero matrix uses a documented display range of zero to one. |
| Power ratio | Sequential, zero to the larger of one or observed maximum. |
| Subtracted power, percent change, dB | Diverging, symmetric about zero with the largest absolute observed value. The all-zero display fallback is −1 to +1. |
| ITC | Fixed zero to one. |

Limits use the complete selected channel and measure. Changing the selected
frequency or slice start does not rescale or truncate the map. Different
channels and measures may have different limits, which are explicitly shown;
colour alone must not be used for unlabelled cross-channel comparison.

The existing labelled frequency control selects the exact saved row and the
map outlines that row. Its time course, numerical alternative and sample-index
window are retained below the full map. The onset line, units, colour limits,
missing/unsupported legend and baseline window are included in the SVG. There
is no pointer-only interaction needed to recover a value or choose a frequency.

Baseline duration, cycles, longest half-support, latest contributing sample
and eligibility counts remain beside the plot. Detailed per-frequency support
is expandable in readable cards, replacing the dense narrow-screen table.
Those declarations do not establish scientific validity or eliminate temporal
smearing from earlier filters.

## Exports and guards

`Download time-frequency map` exports a self-contained complete-channel SVG.
The existing chart download still exports the exact selected frequency slice.
Structured export includes map extents, colour limits/rule, support counts,
frequency-axis convention and rendering method alongside original arrays,
source/report hashes and baseline provenance. Complete CSV retains all original
matrix rows and now explicitly labels each measure's `missing_value` or
`retained_value`, epoch bounds and excluded edge sample count. It does not add
zero rows for unsupported edges.

The existing report adapter validates exact source binding, typed arrays,
frequency axes, epoch sampling grid and versioned baseline diagnostics before
constructing the map. A stale report selector or invalid exact slice refuses
the result rather than drawing another recording's data. Rendering and export
leave source bytes and saved report hashes unchanged.

## Evidence

- `tests/platform-neural-views-plots.R`: 67 checks pass with actual ERP,
  historical/reviewed Morlet and tagging worker outputs. New checks cover complete
  matrix retention, native PNG dimensions/orientation, original missing-cell
  location, unsupported time extents, all-missing/zero distinction, signed and
  ITC scales, slice-independent complete maps and explicit CSV masks. A separate
  presentation boundary fixture retains all 160,000 cells and a known late
  highest-frequency value beyond the 2,000-point slice limit.
- `tests/researcher-neural-baseline-map.mjs` with its isolated R fixture exercises
  actual researcher controls, failed declaration recovery, unavailable
  near-event worker result, researcher correction, new actual report,
  downloads, desktop/390px reflow, accessible figures and reopening both saved
  versions. The baseline-only run passed 11 checks and four accessibility
  scans at `work/brohn-neural-map-baseline-02/browser-1789878965650`.
- The first two combined map runs were retained as evidence of a source-import
  snapshot readiness failure before any analysis job. They are not counted as
  passing map runs. The parent fixed the receipt-after-observation race while
  retaining ownership/source checks.
- The final fresh combined run passed **21 checks and six clean accessibility,
  page-reflow and SVG-label scans**, including actual successful/unavailable
  jobs, full map pixels/support, fixed ITC scale, missing-versus-zero maps,
  exact-slice/poll persistence, real SVG/CSV/JSON/HTML downloads, 390px exports
  and immutable historical reopen. Evidence:
  `C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-neural-map-final-03/browser-1789879948763/results.json`.
  Representative images: `corrected-desktop-map.png`, `corrected-390-map.png`,
  `missing-map-390-map.png`, `zero-power-map-390-map.png`. All fixture server,
  worker and browser handles were closed. The actual narrow map was visually
  inspected after the run.
- The actual earlier corrected report was exported through the final renderer;
  Chrome at 390px retained one native map, one slice and page width 390. The map
  screenshot was visually inspected: labelled frequency rows, event marker,
  hatched edges, mask legend, units, colour limits and baseline label fit.

No time-frequency inference, group statistics, source localization or
automatic psychological label was added by this visualization.
