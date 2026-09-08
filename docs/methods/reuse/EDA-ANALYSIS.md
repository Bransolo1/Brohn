# EDA: implementation-ready analysis recipes

Prepared 2026-09-08. Reuse **NeuroKit2 0.2.13**, with **CVXOPT 1.3.2** for the cvxEDA route, in an isolated local worker. R selects the named recipe, validates its inputs, applies study eligibility/contrasts and generates the report. These are analysis specifications and executable references; the Brohn UI does not yet run them.

## Input and quality contract

Require conductance units and conversion, original sample rate/timestamps, sensor/electrode site, acquisition filters, calibration, missing spans, protocol/exposure/event IDs and clock mapping. Canonical calibrated conductance is microSiemens (µS); resistance requires an explicit reciprocal conversion with units and invalid-zero handling. Unknown device-relative amplitude stays in source units and cannot use an absolute µS threshold. Record environmental and placement conditions. The [electrodermal publication recommendations](https://onlinelibrary.wiley.com/doi/10.1111/j.1469-8986.2012.01384.x) provide the reporting foundation.

Brohn's proposed adapter must flag clipping, disconnection, flatline, abrupt motion/contact changes, implausible slopes and irregular timing using device-specific limits. Preserve raw samples, masks and reasons. Do not delete missing rows and concatenate time. Split discontinuities before filtering; any short-gap interpolation needs an explicit maximum gap, algorithm and retained interpolation mask. Exclude filter transients and invalid event windows. Motion channels can support artifact review; they cannot prove that every remaining peak is physiological.

## Continuous processing

1. **Clean:** `eda_clean(method="neurokit", sampling_rate=fs)`. The pinned implementation uses a fourth-order 3-Hz Butterworth low-pass; below 7 Hz it skips that filter. It also forward-fills missing values, which must not become Brohn's implicit missing-data policy. Freeze usable sampling rates, phase/padding, preprocessing order and boundary exclusions in the adapter; fail visibly when a selected recipe cannot run. [Pinned cleaner](https://raw.githubusercontent.com/neuropsychology/NeuroKit/v0.2.13/neurokit2/eda/eda_clean.py)
2. **Separate tonic/phasic:** `eda_phasic(method="highpass", cutoff=0.05)` is the first reproduced reference configuration. The implementation separately low-passes tonic and high-passes phasic, so do not promise exact additive reconstruction. Median smoothing and cvxEDA are different methods with different parameter meanings; store separate recipe IDs. [Pinned decomposition](https://raw.githubusercontent.com/neuropsychology/NeuroKit/v0.2.13/neurokit2/eda/eda_phasic.py)
3. **Detect responses:** `eda_peaks(method="neurokit", amplitude_min=0.1)`. In this path, the threshold uses candidate peak **prominence relative to maximum prominence**, not 0.1 µS, raw peak height or onset-to-peak amplitude. An absolute amplitude rule requires a distinct calibrated rule and sensitivity checks. Preserve detector, threshold definition and onset/peak sample indices. The public wrapper fixes recovery at **50%**; other fractions need a reviewed adapter, not a fictional configurable argument. [Peak API](https://neuropsychology.github.io/NeuroKit/functions/eda.html), [prominence implementation](https://raw.githubusercontent.com/neuropsychology/NeuroKit/v0.2.13/neurokit2/signal/signal_findpeaks.py), [pinned peak extraction](https://raw.githubusercontent.com/neuropsychology/NeuroKit/v0.2.13/neurokit2/eda/eda_peaks.py)

Processing runs on continuous valid segments before trial summaries. Cropping each short trial first changes boundaries and loses ongoing responses. Explicitly select interval or event analysis; do not let `eda_analyze` choose the scientific design from epoch length. Keep the reference configuration separate from a device-specific production preset.

## Output catalogue

These are proposed Brohn definitions to implement and test. Every row carries participant, session, condition, exposure/window, method revision, valid support and exclusion reasons.

| Recipe | Outputs and required decisions |
|---|---|
| Tonic level / SCL | Mean and median tonic conductance; optional slope in µS/s. Retain valid seconds, estimator and baseline/task windows. Unequal sampling requires explicit time weighting. Raw conductance mean and decomposed tonic mean are distinct fields. |
| Baseline contrast | Task minus baseline tonic level in µS, with both means and valid durations. Relative-percent or standardized contrasts need a separate named divisor; a zero/near-zero baseline must not produce an infinite percentage. |
| SCR morphology | Onset, peak and recovery times; peak height and onset-to-peak amplitude as separate fields; rise duration and declared recovery fraction/time. Convert sample indices using the segment clock. Missing onset or unobserved recovery yields a reasoned null. |
| Interval response activity | Peak count, count per minute of valid observation, amplitude mean/median among finite accepted amplitudes, and responder count. Report peak-count and amplitude denominators separately. Peaks lacking a valid onset must not silently contribute an amplitude of zero. |
| Phasic area | Integral over a defined window in µS·s with integration rule and coverage. Signed area, positive-only area and summed SCR amplitudes are separate estimands; high-pass phasic can be negative. |
| Event response | Response probability, amplitude, latency from measured onset, rise/recovery and area for a prespecified response window. Store baseline, latency bounds, event-selection/overlap rule, observed-window coverage and responder definition. |
| Condition inference | Participant-level contrasts or a prespecified hierarchical model, with effect estimate, interval and retained participant/trial counts. Preserve stimulus identity, order and paired control structure. Samples/peaks are not independent participants. |

A valid observed response window with no qualifying response may contribute **zero response magnitude** and a nonresponse flag. Missing recording, invalid baseline or incomplete required support produces **unavailable**, not zero. “Mean amplitude among responders” and “mean magnitude including valid nonresponses” must be separate outputs with visible denominators. Do not invent a single response window or amplitude threshold for all stimuli, sensors and tasks.

## Agile studies and overlapping responses

Brohn's design checks should compare presentation spacing with the chosen baseline/response windows. Separate viewing, question display, button press and movement events: each may affect the recorded response. A neutral/control stimulus is an experimental comparator; it is not automatically a physiological baseline. Freeze the contrast and order assignment before analysis.

For rapid events, prefer a separately specified continuous deconvolution or event-convolution model with nuisance events and diagnostics. A peak nearest to an image is not necessarily caused by that image. [cvxEDA](https://github.com/lciti/cvxEDA) estimates tonic/phasic components under a response model; [PsPM](https://bachlab.github.io/PsPM/) provides an established model-based analysis route for event designs. Decomposition alone does not solve event attribution. PsPM is a future reference/comparison route, not installed here.

The initial low-click experience should select a study template and automatically run eligible recipes after collection/import finalizes. Show tonic change, response activity and data retained in plain language. A single review panel handles flagged segments and reruns affected outputs after mask approval. Advanced settings and method details remain available without making a student configure filters on every study. These are UX requirements, not existing controls.

## cvxEDA adapter constraint and evidence

The pinned public `eda_phasic(method="cvxeda")` **does not forward custom kwargs** to its helper. We verified that behavior. Its effective defaults are `tau0=2`, `tau1=0.7`, `delta_knot=10`, `alpha=0.0008`, `gamma=0.01`, `solver=None`, `reltol=1e-9`. Until a reviewed configurable adapter exists, reject nondefault requests and label applied settings as pinned defaults. Do not build controls that silently do nothing. The public return has tonic/phasic arrays; exposing driver/residual/solver diagnostics needs an additional adapter. Original cvxEDA/CVXOPT distribution terms require a compatible release decision.

Completed evidence:

- [Physiology reference](physiology-reference-results.json): two pinned public NeuroKit examples; aligned finite components and ordered peak outputs. Resting example reproduces two peaks and published rounded mean amplitude 1.872206, but only **one** amplitude is finite. Source amplitude calibration was not independently established; these are developer-example regression checks.
- [cvxEDA reference](eda-deconvolution-results.json): **6 checks**, including effective defaults and the ignored-kwargs probe. A noiseless 40-second model-compatible signal at 25 Hz gives reconstruction RMSE **0.0008243**, tonic MAE **0.0007329**, and phasic MAE **0.0007713** in source units. These tolerances test numerical recovery on that constructed signal.

Next integration checks: known µS scaling, missing-gap/edge behavior, threshold sensitivity, event-clock offsets, valid nonresponses versus missing observations, overlapping/nuisance-event fixtures and agreement with a permitted annotated/reference pipeline. Reuse the published method evidence; these checks address Brohn's wiring and the specific recipe rather than rebuilding EDA science. Commands and source provenance are in the [benchmark guide](../../../scripts/benchmarks/README.md).
