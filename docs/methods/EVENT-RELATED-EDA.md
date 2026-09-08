# Event-related EDA with continuous context

Implemented worker: `scripts/workers/eda_events.py`. Numerical and source-boundary checks: `tests/workers/eda_events.py`.

The R contract and accessible controls live in `R/platform-eda-events.R` and `R/platform-eda-events-views.R`; `tests/platform-eda-events.R` checks mapping, JSON shape, actual worker execution, measure-specific support and complete artifact publication/restart/download. Current focused evidence: 28 Python tests and 65 R checks pass.

This recipe processes each continuous person/session/source-recording channel **before** extracting stimulus windows. Alternating condition/exposure labels do not restart filters. A two-second stimulus can therefore use a sixty-second continuous recording. A two-second source file cannot manufacture that context.

Status: implemented bounded offline computation with independent synthetic arithmetic and pinned upstream execution checks. This does not establish external device timing, universal artifact thresholds or empirical construct validity. It produces conductance measures, never automatic emotion labels. Rapid-event response attribution via a separately specified event-convolution model remains a different, unimplemented recipe.

## Request contract

The JSON envelope is `brohn-worker-request/1.0`, `operation: "eda_events"`, `modality: "eda"`, with `source_path`, `format: "csv" | "tsv"`, `metadata`, and a top-level `parameters` object. Declare the delimiter even when an immutable source object has no filename extension.

Metadata requires:

- `time_column`, `time_unit: "s" | "ms"`, `sampling_rate` from 8 to 2,000 Hz.
- `value_columns`: selected calibrated conductance channels; `unit: "uS"` (Unicode micro variants accepted) or `"S"`. Siemens converts to microsiemens. Resistance and uncalibrated device counts are rejected.
- `participant_column` and `session_column`: explicit source identities. These are recording grouping labels, not a cross-import identity match or independent-subject qualification.
- Optional `recording_column`: acquisition segment/reset identity. Clock reversal inside an unchanged person/session/recording is an error. Contiguous returns to an earlier identity are separate source recordings and are never concatenated.
- Optional `valid_column`: true/false or 1/0; blank/missing is invalid. Signal gaps, missing/negative conductance and invalid samples split processing. No forward fill, interpolation, gap bridge, silent rate conversion or automatic artifact repair occurs.
- Optional `timestamp_tolerance_s`: default `0.02 / sampling_rate`, maximum half a sample. Non-gap intervals must agree with the declared rate within tolerance; gaps above 1.5 sample intervals split the trace.
- `origin` is retained: sample, preview, pilot, live, imported or unspecified.

Exactly one event source is required:

1. `event_column` contains a code **only at the measured onset row**, blank otherwise. `exposure_column` provides a unique trial ID at each target onset. Optional `condition_column` must agree with the code mapping at each onset; optional `stimulus_column` preserves stimulus identity. Changing labels on other rows does not split preprocessing. Repeating a marker throughout a trial creates duplicate exposures and is rejected.
2. `events` is an explicit array of `{time_s, code, exposure_id, recording_id?, condition_id?, stimulus_id?}`. Times are seconds relative to the **first source timestamp of the named continuous source recording**, before filtering or gap splitting. With several recordings, each event must name the generated `recording-1`, `recording-2`, etc., in contiguous source order. All target exposures are unique within that recording.

The original clock origin is retained as a decimal string; subtraction happens before conversion to floating point. Explicit onset times align only to a measured sample within `event_tolerance_s` (default half a sample, configurable down to zero). Requested time, aligned measured time, alignment error and source row remain in the result. No synthetic event sample is interpolated. Simultaneous codes at one sample are rejected until represented by an explicit combined-event protocol.

## Required recipe settings

These values are a **test fixture**, not a universal consumer-research protocol:

```json
{
  "recipe": "eda-event-highpass/1.0",
  "event_codes": {"A": "control", "B": "test"},
  "nuisance_codes": ["MOVE"],
  "event_source": "Measured stimulus onset markers in the acquisition clock",
  "settings_source": "Named preregistered study protocol and revision",
  "baseline_s": [-2, 0],
  "response_s": [0, 6],
  "onset_latency_s": [0.5, 4],
  "recovery_end_s": 10,
  "nuisance_effect_s": [0, 8],
  "overlap_policy": "exclude",
  "response_selection": "first_onset",
  "minimum_scr_amplitude_us": 0.05,
  "relative_prominence": 0.1,
  "edge_exclusion_s": 10,
  "minimum_segment_s": 40
}
```

Both named recipes require every setting above. Unknown parameters fail; no unsupported custom solver/filter/response setting is ignored.

- `eda-event-highpass/1.0`: NeuroKit2 0.2.13 cleaner, fixed 3 Hz/order-4 lowpass, then highpass decomposition at 0.05 Hz. Tonic and phasic components are computed separately and need not reconstruct the cleaned signal exactly.
- `eda-event-cvxeda-defaults/1.0`: same cleaner, then the pinned public cvxEDA wrapper with CVXOPT 1.3.2. Verified effective defaults: `tau0=2`, `tau1=0.7`, `delta_knot=10`, `alpha=0.0008`, `gamma=0.01`, `solver=null`, `reltol=1e-9`. The public wrapper drops custom CVX keyword arguments in this pinned version, so this recipe rejects them. Segments above 10,000 samples are unavailable; they are not silently cut or downsampled. No driver, residual or solver-convergence diagnostic is claimed.

The reuse evidence and upstream API findings are documented in [EDA-ANALYSIS.md](reuse/EDA-ANALYSIS.md). The relevant implementation sources are the pinned [NeuroKit cleaner](https://raw.githubusercontent.com/neuropsychology/NeuroKit/v0.2.13/neurokit2/eda/eda_clean.py), [decomposition](https://raw.githubusercontent.com/neuropsychology/NeuroKit/v0.2.13/neurokit2/eda/eda_phasic.py), [peak wrapper](https://raw.githubusercontent.com/neuropsychology/NeuroKit/v0.2.13/neurokit2/eda/eda_peaks.py), and original [cvxEDA repository](https://github.com/lciti/cvxEDA).

Minimum continuous context is at least 40 seconds and at least `2 * edge_exclusion_s + 20` seconds, measured as source sample count/rate. At least ten seconds are removed at both segment edges. These are explicit conservative support constraints, **not a proof that every filter transient has settled**. The actual first/last retained timestamp is recorded; no unobserved interval after the final sample is appended.

Baseline must end at or before onset; response begins at or after onset. Baseline/response integration endpoints must lie on the declared relative sample grid, then must have measured endpoints within the source timestamp tolerance. Latency and recovery thresholds are comparisons against observed candidate times and may fall between samples. Every sample of both windows must lie inside the same retained continuous segment. Partial-window statistics are not substituted when the required baseline or response support fails.

## Measures and denominators

Each event/channel result records baseline and response requested/observed endpoints, sample counts, measured duration, endpoint alignment errors and segment ID. Integration uses the actual timestamps, not nominal trial duration.

| Output name | Calculation and support |
| --- | --- |
| `tonic_baseline_mean` | Trapezoid integral over complete baseline, divided by observed baseline duration; uS. |
| `tonic_response_mean` | Equivalent time-weighted response mean; uS. |
| `tonic_response_minus_baseline` | Response mean minus baseline mean; uS. |
| `phasic_response_area_signed` | Signed trapezoid integral in the complete response window; uS*s. |
| `phasic_response_area_positive` | Clip negative **measured** phasic samples to zero, then trapezoid integral; uS*s. |
| `scr_response_magnitude` | Selected qualifying onset-to-peak amplitude. Zero only for supported, successfully detected nonresponse events; uS. |
| `scr_responder_amplitude` | Same amplitude for responders only. Nonresponses are null; denominator differs from magnitude. |
| `scr_qualifying_count` | Number of candidate responses meeting latency, response-peak and absolute amplitude requirements. |
| `scr_nonresponse` | 1 if eligible with zero qualifying candidates, 0 if a responder; unavailable remains null. |
| `scr_onset_latency`, `scr_peak_latency` | Selected observed onset/peak minus the measured event onset; seconds. |
| `scr_rise_time` | Selected observed peak minus its onset; seconds. |
| `scr_half_recovery_time` | Observed 50% amplitude recovery minus peak, only within retained support, declared recovery boundary and before another source event; seconds. |

The detector first applies a segment-relative **candidate prominence** threshold. Brohn then applies the explicitly calibrated `minimum_scr_amplitude_us` to observed phasic onset-to-peak amplitude. Those are different thresholds. The selected candidate is the earliest qualifying onset or the largest qualifying amplitude, as declared; ties resolve deterministically by onset. A qualifying onset lies in the closed latency interval, and its peak lies in the closed response interval.

An unknown onset or a sufficiently large already-started SCR peaking within the response window makes event SCR attribution unavailable; it is not counted as a clean nonresponse. A wrapper failure also leaves SCR outcomes unavailable while supported tonic/phasic summaries survive. The pinned wrapper's genuinely peakless-input failure is handled only after a separate strict-local-maxima check; generic detector errors never become zero responses.

The selected response's missing or late half-recovery does not erase its supported amplitude. A later source event before recovery censors recovery. Continuous SCR candidates remain in the result for review, separate from measured source events and attributed trial measures.

## Overlap and missingness

The event's combined baseline-to-response interval is compared with every other target's corresponding interval and every declared nuisance effect interval. Touching endpoints count as overlap. `exclude` leaves all event outcomes unavailable. `descriptive_only` retains fully supported tonic/phasic window summaries with a descriptive interpretation flag; SCR attribution stays unavailable.

This rule is intentionally conservative. It does not establish that unlabelled earlier stimuli cannot have lingering physiological effects. Decomposing continuous EDA with cvxEDA does not resolve which of two rapid stimuli caused a response. Event-convolution modelling with a declared design matrix, response model, nuisance regressors and checked identifiability is a separate future method, not an automatic fallback.

Missingness is never filled as zero. Lossless run-length `source_masks` identify original signal missingness, source validity exclusions, negative conductance and exact clock-gap boundaries. `segments` retain preprocessing source row ranges, support and explicit failure reasons. Arrays shown in `series` are a bounded display sample only; calculations and candidate records use complete retained support.

## Result and integration contract

Source `platform-eda-events.R` after the core domain helpers and before jobs; source its views before the dataset views. Integration hooks are `brohn_eda_events_recipe_choices()`, `brohn_eda_events_is_event(metadata)`, `brohn_validate_eda_events_mapping(metadata, columns, source_format, design = NULL)`, `brohn_eda_events_worker_request(metadata, source_format, columns)`, `brohn_eda_events_settings_ui(metadata, columns, source_format)` and `brohn_eda_events_input(input, metadata, source_format)`. Supplying the frozen design to the validator checks condition/stimulus membership. Worker-side source checks still validate actual onset rows, reset boundaries and measured support.

New form controls use the `map_eda_event_` prefix and the shared source form retains person/session/exposure/time/channel/unit controls. New protocol integration windows begin blank; saved explicit settings reopen intact. `brohn_eda_events_support(result)` and `brohn_eda_events_support_ui(result)` expose measure-specific availability and each event's support/reasons without treating event counts as participant counts.

The result uses `brohn-worker-result/1.0`, with `operation`, `modality`, `status`, source hash/clock/unit evidence, pinned package versions, worker/shared-reader code hashes, per-recording effective parameters, `features`, `events`, `series`, `recordings`, `segments`, `source_masks`, `quality`, `limitations`, and optional `artifacts`.

When the parent supplies `artifact_directory`, full continuous processed samples and SCR candidates are additionally preserved in verified typed artifacts; see [complete processed physiology artifacts](PROCESSED-PHYSIOLOGY-ARTIFACTS.md). The main report remains bounded for display and its event support/source masks remain complete. Without that optional compatibility extension, `artifacts` is empty.

- `recordings` contains **event/channel cells** for compatibility with the report support layer. It includes `event_id`, `recording_id`, condition/exposure/stimulus IDs, person/session group, origin, requested and aligned onset, baseline/response support, `status`, `scr_status`, reasons, overlap IDs and selected SCR.
- Each feature has `scope: "event"`, `eligible`, `support_status`, `missing_reason`, unit and all identities. General window-cell success must not override measure-specific eligibility.
- `events` distinguishes `stimulus_event`, `nuisance_event` and `scr_candidate`. No nearest-event joining is performed.
- A completed job means numerical processing finished; `quality.scientifically_qualified` remains false. No person-level inferential statistics are calculated. Trials, channels and repeated sessions are not extra people.

Bounds: 512 MiB source, shared reader's 2 million rows/20 million signal values, 2,000 onsets, 10,000 event/channel cells, 2,000 channel segments, 20,000 complete SCR candidates and 20,000 source-mask intervals. Exceeding a scientific output bound fails explicitly; candidates and masks are never silently sampled. Display series share a 2,000-point budget. CLI requests are bounded to 2 MiB with duplicate/nonfinite JSON rejection and atomic result publication; source/request files cannot be replaced by the output.

## Evidence and limitations of the checks

The worker suite independently checks linear tonic means (39 and 47 uS, difference 8), triangular phasic area (4 uS*s), signed negative area, hand-defined SCR latency/rise/recovery arithmetic, denominator differences, overlap/nuisance rules, missing baseline, cross-segment rejection and late recovery. Actual pinned highpass execution is compared with a separately called full-recording upstream trace. A known Bateman pulse produces the expected checked peak around 22.08 seconds for an event at 20 seconds in the synthetic fixture. Actual cvxEDA public-default execution is checked alongside the existing [deconvolution reference benchmark](../../scripts/benchmarks/eda-deconvolution-reference.py).

Source tests cover alternating short-trial condition labels, independent people and resets, original missingness versus source invalidity, negative conductance, clock gaps, calibrated S/uS equivalence, exact large decimal clock origins, onset alignment, typed onset identities, extensionless TSV objects, unknown/mismatched codes, invalid settings and CLI output protection. Synthetic arithmetic and matching the chosen upstream method are bounded evidence; noisy empirical motion, sensor disconnects, within-person responsivity and external event-clock qualification remain necessary acquisition/protocol checks.
