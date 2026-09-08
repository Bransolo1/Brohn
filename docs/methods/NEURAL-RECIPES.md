# Explicit neural recipes

Implemented 2026-09-08 by `scripts/workers/neural.py`, using the prepared
MNE 1.12.1 environment. R owns study/recipe selection, source integrity and
participant-aware analysis. This separate offline worker adds three numerical
routes to the existing Welch worker:

| Recipe ID | Outputs |
|---|---|
| `eeg-erp-epochs/1.0` | Condition/channel evoked waveforms, within-recording trial SEM, prespecified mean amplitude and optional polarity-constrained peak. |
| `eeg-morlet-epochs/1.0` | Total or evoked-subtracted induced wavelet power, explicit power baseline transforms and original-signal inter-trial phase consistency. |
| `eeg-frequency-tagging/1.0` | Declared tag/harmonic spectral bins, neighboring-bin noise density and SNR from averaged trial spectra. |

These recipes compute signal measures. They do not identify an ERP component
automatically, establish device timing, infer source-localized activation, or
produce psychological engagement/emotion scores. See the broader
[EEG implementation specification](reuse/EEG-ANALYSIS.md) for qualification,
ICA, montage, connectivity and participant-level inference work that remains
separate.

## Request and source contract

The worker accepts `schema = 'brohn-worker-request/1.0'`,
`operation = 'neural'`, `modality = 'eeg'`, `source_path`, `format`, `metadata`
and `parameters`. If top-level `parameters` is absent, it reads
`metadata.parameters`. The source is retained unchanged and SHA-256 is returned.

CSV/TSV uses the shared bounded reader and explicitly declared `time_column`,
`time_unit`, `sampling_rate`, `value_columns` and voltage `unit` (`V`, `mV`,
`uV`, with supported micro-symbol spellings). A TSV delimiter follows the
declared format even when the immutable object has no extension. Native EDF,
BDF and FIF use the named MNE reader, selected channel names, `unit = 'native'`
or `V`, and a required sampling rate that must agree with the file header.
Native physical scaling produces volts; native bad channels and BAD annotations
remain excluded.

Participant/session columns are declared together when available. Optional
condition and exposure columns split contiguous source segments. No processing
crosses a change in any mapped identity. Native inputs use explicit
`participant_id`, `session_id`, `condition_id`, `exposure_id` metadata instead.
Absent person identity is labelled `recording_only_no_participant_inference`.
Repeated segments are not merged merely because their labels match. Source
origin (`sample`, `preview`, `pilot`, `live`, `imported` or `unspecified`) is
retained and does not change with successful computation.

Choose exactly one event route:

* `metadata.event_column` for CSV/TSV: a code only on an onset row; empty/null
  strings mean no event. Held-high trigger channels need a separate explicit
  transition adapter, not this onset-column interpretation.
* `metadata.events`: an array of `{time_s, code, recording_id?, id?}`. Codes
  are strings. `time_s` is relative to sample zero of that contiguous source
  recording, not the study start or a wall clock. For native files this is
  `raw.times` zero; original `first_samp`/time origin remain separately reported.
  Multiple recording segments require `recording_id` such as `recording-1`.

Event times must strictly increase. Simultaneous or repeated aligned sample
events are not silently collapsed. The nearest recorded sample must meet
`event_tolerance_s`, bounded by half one sample interval; that half-interval is
the alignment default. Alignment errors and source sample indices are saved.
Unmapped event codes appear in the exclusion ledger. Mapped event conditions
must agree with an explicitly mapped source condition, when one exists.
Event provenance must explain synchronization and measured onsets; this worker
does not claim that a browser marker automatically has an EEG clock mapping.

## Required common settings

There are no hidden scientific presets. Every request explicitly supplies the
common settings below and the selected recipe's settings. The following is a
synthetic-example shape, not a universally recommended study recipe:

```json
{
  "recipe": "eeg-erp-epochs/1.0",
  "event_codes": {"A": "condition-a", "B": "condition-b"},
  "event_source": "Measured device-marker source and clock alignment evidence",
  "epoch_s": [-0.2, 0.8],
  "baseline_s": [-0.2, 0],
  "reference": {"mode": "acquisition", "source": "Recorded acquisition reference"},
  "filter": {"mode": "none"},
  "rejection": {"window_s": [-0.2, 0.8], "peak_to_peak_uv": 150, "flat_uv": null},
  "minimum_trials": 20,
  "overlap_policy": "reject",
  "settings_source": "Prespecified protocol/version and rationale",
  "amplitude_window_s": [0.3, 0.5],
  "peak_polarity": "none"
}
```

Epoch endpoints lie on the declared sample grid and include the event onset.
The last sample is included. Voltage baseline is explicitly null or an
inclusive window ending at/before onset. Peak-to-peak and flat thresholds are
in microvolts; null disables the corresponding test. Rejection needs at least
two sampled points. `minimum_trials` is a method decision, not a proof of
reliability. Every declared condition gets retained/excluded/requested counts;
an absent or insufficient condition has no zero-valued scientific features.

Reference modes are `acquisition`, `average` of all selected channels, or
`channels` with a unique named `channels` list selected from the source.
All require `source` provenance. Average reference needs at least two channels.
These are explicit numerical transforms; montage/topology is not inferred.

Filtering is either `{mode:'none'}` or
`{mode:'butterworth_bandpass',low_hz,high_hz,order,edge_exclusion_s}`.
The latter uses SciPy second-order-section forward/backward filtering, order
1..8, explicit cutoffs below Nyquist and odd padding. Its conservative minimum
declared edge is three cycles of the high-pass cutoff (`3/low_hz` seconds)
per side. This floor is a software support rule, not empirical filter-response
qualification. Filter coefficients, phase and excluded support are returned.

Processing order is: identify jointly finite selected channels and source
gaps/annotations; re-reference each isolated valid span; filter if requested;
exclude declared edges; form only completely supported epochs; apply amplitude
rejection to the explicit window; then apply voltage baseline and compute the
requested measure. No missing samples are filled and no epochs cross gaps.
Amplitude rejection excludes the whole trial across selected channels, retaining
a common trial cohort. It is screening, not comprehensive artifact detection.
Peak-to-peak screening uses the processed voltage. Flat screening uses original
source voltage in that window, so a mathematically zero rereferenced electrode
does not invent source track loss.

With overlap policy `reject`, the first supported geometrically overlapping
epoch owns the interval even if it subsequently fails amplitude screening;
rejection outcome therefore does not select which overlapping event wins.
Policy `allow` records the protocol decision and does not turn dependent trials
into independent people.

## ERP

MNE `EpochsArray` applies the explicit inclusive voltage baseline; condition
averages use the retained epochs. Brohn emits the complete channel/time
waveform in microvolts, trial count and pointwise within-recording trial SEM.
A single retained trial has missing SEM. This uncertainty is not a
between-participant confidence interval. [MNE EpochsArray API](https://mne.tools/stable/generated/mne.EpochsArray.html)

`amplitude_window_s` is inclusive. `erp_mean_amplitude` averages its samples.
Optional `peak_polarity` is `positive`, `negative`, `absolute` or `none`.
No requested-polarity peak yields missing amplitude/latency. Tied extrema use
the first sample; an extremum at a search-window edge is flagged. The worker
does not choose electrode ROIs, component names or latency windows after
examining condition differences.

## Morlet

Additional settings: increasing `frequencies_hz` (1..40 frequencies), one
`n_cycles` value per frequency, `power = 'total'|'induced'`,
`summary_window_s`, and `power_baseline`. `power_baseline` is `{mode:'none'}`
or `{mode,window_s,minimum_power_uv2}` with mode `subtract`, `ratio`, `percent`
or `db`. Its window ends at/before onset.

The worker calls MNE's complex array transform with zero-mean Morlet wavelets,
FFT convolution, no decimation and one job. It excludes the full sampled
half-width of the longest wavelet at both epoch edges. Summary and power
baseline windows must lie wholly within this support; two baseline samples
are required. These fixed edge rules prevent reporting zero-padded boundaries
as observed response. [MNE Morlet array API](https://mne.tools/stable/generated/mne.time_frequency.tfr_array_morlet.html)

Trial power is averaged in linear units first. Baseline correction then uses
the average power over the declared baseline: subtraction, ratio,
`100*(ratio-1)` or `10*log10(ratio)`. Nonpositive or below-declared-floor
denominators remain missing. The reported unit is wavelet power in uV^2, not
PSD density. Induced power subtracts the within-recording/condition evoked
waveform from each trial before its transform; the original source remains
untouched.

ITC uses the original total-signal unit phases, even when induced power was
selected. A sample needs phase support from at least two retained trials;
zero-amplitude samples do not invent phase. Values stay in 0..1. Trial counts
and the minimum phase-support count accompany summaries. ITC's trial-count
bias and low-amplitude interpretation remain research decisions.

Each series record includes frequency/time axes and frequency-by-time arrays
for raw wavelet power, transformed power and ITC. Axes are not flattened or
silently decimated. Summary features use the declared time window.

## Frequency tagging

Additional settings are `spectral_window_s`, `tag_frequencies_hz`, integer
`harmonics`, `window = 'hann'|'boxcar'`, `noise_neighbor_bins`,
`noise_skip_bins` and `max_bin_offset_hz`. The spectral window is half-open.
There is one non-zero-padded Welch window per retained epoch, DC removal,
explicit taper and mean trial PSD. Frequencies and density are retained.

The requested tags and harmonics must be below Nyquist and resolve to distinct
bins within the declared tolerance. `tag_bin_density` is the selected bin's
uV^2/Hz density, not integrated band power or calibrated oscillation amplitude.
Noise uses the declared symmetric neighboring bins on each side after the
skipped bins. An unavailable neighbor, DC/Nyquist boundary or another target
in that noise set makes SNR unavailable. A zero noise denominator produces
missing SNR, not infinity. SNR divides mean trial target density by mean
trial neighboring density; it does not average per-trial ratios.

The [MNE frequency-tagging tutorial](https://mne.tools/stable/auto_tutorials/time-freq/50_ssvep.html)
provides primary context for neighboring-frequency SNR. Brohn's strict bin,
collision, support and averaging policies above are its own explicit contract.
Leakage, response duration, harmonics, reference effects and task interpretation
must be considered in the protocol. These outputs are not a stimulus classifier
or automatic attention measurement.

## Result, limits and tests

The response uses `brohn-worker-result/1.0` with `features`, `series`, complete
event exclusion ledger, `recordings`, `quality`, per-recording `parameters`,
`limitations`, engine versions and source hash. A recording/condition summary
has origin, source origin/index/scaling, requested/retained/excluded trials,
derived settings and explicit support status. Features carry recording,
condition, source group, channel, unit and `scope = 'recording_condition'`.
No participant inference is performed. Trial retention can succeed while a
specific recipe's support remains insufficient; both states remain visible.

Bounds: source 512 MiB; 2,000,000 CSV rows; 64 selected channels;
20,000,000 source values; 10,000 events; 10,000,000 epoch values per recording;
40,000,000 trial/channel/frequency/time Morlet work units; 500,000 inline array
values per result. Oversized jobs must be split. This release does not silently
drop/downsample arrays or emit untracked external array files.

Run `../../work/tooling/methods-venv/Scripts/python.exe tests/workers/neural.py`.
The independent synthetic fixtures check a 10-uV evoked pulse and baseline,
zero/one-trial missingness, named/average reference, exact timing and large
integer time origins, participant boundaries, explicit marker routes,
overlap/artifact/gap behavior, stationary-sine Morlet ratio/phase, opposed-phase
ITC, induced removal, known 10*log10(4) dB correction, exact 400-uV^2/Hz sine
density, independently specified SNR=100, and zero/colliding denominators.
Handwritten EDF/BDF headers/data independently test native physical scaling;
FIF checks native first sample and BAD-annotation exclusions. CLI checks verify
immutable sources, atomic JSON completion and structured errors.

These fixtures establish numerical behavior and boundary handling. They do not
replace permissioned real recordings, independently reviewed artifacts,
device-specific timing/precision or named protocol reliability evidence.

## R integration

Source `R/platform-neural.R` after the domain module and before jobs, including
in `scripts/analysis-worker.R`. Source `R/platform-neural-views.R` before the
dataset view. The mapping hooks are
`brohn_neural_settings_ui(metadata, columns, source_format)`,
`brohn_neural_input(input, metadata, source_format)` and
`brohn_validate_neural_mapping(metadata, columns, source_format)`.
The input helper accepts readable code-to-condition lines and CSV onset lists,
then stores typed objects/arrays; explicit null and one-item arrays survive
serialization.

`brohn_neural_worker_request(metadata, source_format = NULL, columns = NULL)`
returns `operation`, `script` and `parameters`. Missing/legacy Welch settings
retain the existing physiology route. Only registered epoch recipes select
the neural worker. Pass the actual format and source origin from the frozen
dataset. `tests/platform-neural.R` passes 44 checks, including a real
R-to-Python evoked-pulse request and the complete durable ingest, accepted
mapping, fenced R-supervisor/Python-child job, immutable report publication and
verified restart path. The disclosure controls are checked for labelled inputs
and method-specific content. The Python suite passes 27 tests. These automated
checks do not claim participant usability testing.
