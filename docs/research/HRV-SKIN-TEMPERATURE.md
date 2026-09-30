# HRV and skin temperature: implementation inventory and next gates

30 September 2026. The owner requires both measures across Brohn's complete
study-to-report journey. This is a scoped inventory of production
`c43c54d93dc202a9b76b061a82d4c028d072dcd6`, not a new qualification or a change to
saved methods. The external evidence packet is
`work/cardiac-report-next-20260930/hrv-temperature-scope-01`; its source hashes,
before/after documents and checks retain this audit independently of later builds.
All 50 capabilities and 17 work-package statuses remain unchanged, including
planned BWP16. BWP09 already names `ecg.hrv`, `ppg.prv` and
`temperature.peripheral` in the [build manifest](../preparation/build-manifest.json).

## What exists and what remains

| Journey stage | Present implementation | Remaining gate |
|---|---|---|
| Study and protocol | ECG/HRV, PPG and temperature measure choices; declared presentation baseline duration; saved study association. | A method-aware plan must distinguish experimental control from a recorded physiological baseline and check duration/support before promising HRV or thermal contrasts. The current design comparison registry contains gaze and questionnaire measures, not these physiological recipes. |
| Original sources | Direct ECG/PPG analysis; actual ECG/PPG multistream extraction with complete curation decisions; calibrated temperature CSV/TSV mapping with declared units, site, calibration, filters and recording conditions. | Temperature is absent from `brohn_stream_modalities()`. Add a bounded, separately qualified temperature extraction route and named-device evidence; do not infer live hardware support from generic stream capture or CSV acceptance. |
| Review and exclusions | Full saved input/cleaned cardiac traces, retained detected peaks, interval plausibility and frequency bins. Cardiac exclusion review creates a separate recalculated child with exact preview/ledger/source crosswalk. Temperature preserves gaps, invalid rows and supported intervals; generic named time-window summaries are available. | Cardiac source-span exclusion is not beat classification or NN adjudication. Temperature lacks an equivalent dedicated source-exclusion/reanalysis contract. Keep annotation, excluded support and any later scientific recalculation distinct. |
| Numerical analysis | Detected RR/PRV time measures and qualified-by-recipe frequency support; calibrated temperature descriptions and optional protocol threshold excursions. | Confirmed NN-HRV and optional nonlinear measures need explicit new recipes and independent reference evidence. Skin-temperature validity needs sensor/context support, not merely a channel named temperature. |
| Baseline/event comparison | Reviewed multimodal synthesis can compare compatible saved physiological features using declared report/person/session/condition identities; temperature support is checked per contiguous source interval. | No dedicated cardiac HRV or skin-temperature recorded-baseline/event estimator is established by these paths. Generic waveform means, presentation `baseline_ms`, within-trace endpoint change and control-condition contrasts must not be relabelled as one. |
| Saved review, report and export | Individual reports, full typed signal/event artifacts, signal explorer and existing exports; scoped prior cardiac/peripheral QA. | Production complete-findings package admission still omits ECG, PPG and temperature. The active external cardiac package candidate needs its own joined native/history/browser acceptance. Temperature needs a separate complete-evidence reader/display/package adapter and the same acceptance gates. |

Code anchors: [cardiac worker](../../scripts/workers/physiology.py),
[exclusion API](../../R/platform-cardiac-review.R),
[stream curation](../../R/platform-stream-curation.R),
[temperature mapping](../../R/platform-peripheral.R),
[temperature worker](../../scripts/workers/peripheral.py),
[supported synthesis](../../R/platform-peripheral-synthesis.R),
[generic interval annotations](../../R/platform-signal-annotations.R),
[interval reuse](../../R/platform-signal-reuse.R),
[design comparison registry](../../R/platform-analysis-plan.R), and
[current package admission](../../R/platform-report-package-sources.R).

## Cardiac method boundary

Current recipes are `ecg-neurokit-detected-rr/1.0` and
`ppg-elgendi-detected-prv/1.0`. They clean/detect using the recorded recipe,
exclude declared edges and screen interval duration; automatic artifact
correction and NN qualification are disabled. The worker requires at least ten
retained seconds for detection. This is computational admission, not a general
HRV recording-duration recommendation.

Saved time features include interval/retained/pair counts, mean interval, sample
interval SD, RMSSD, a pNN50 **candidate**, and two distinct rate summaries. The
saved pNN50 candidate divides by retained intervals; RMSSD uses only originally
adjacent plausible pairs. Preserve those definitions and denominators. Do not
rename the saved SD to confirmed SDNN or treat plausibility bounds as proof of
sinus beats. NN intervals refer to adjacent normal cardiac cycles; the
[ESC/NASPE measurement standard](https://www.escardio.org/static-file/Escardio/Guidelines/Scientific-Statements/guidelines-Heart-Rate-Variability-FT-1996.pdf)
provides the physiological definition. PPG pulse timing is separately labelled
PRV: direct ECG/PPG comparisons can show strong correlation without agreement
of individual measures ([Wong et al., 2012](https://pubmed.ncbi.nlm.nih.gov/22350367/)).

Frequency output currently requires at least ten intervals, every interval
plausible, and a declared peak span of at least 300 seconds. It retains 4 Hz
linear interpolation without extrapolation, 128-second Hann Welch windows,
50% overlap, constant detrending, every saved PSD bin, and the exact LF/HF
integration boundaries. Available zero power is different from unavailable
support; LF/HF remains unavailable when its HF denominator is zero. Exclusion
children restart at each surviving run; neither differences nor spectra may
bridge an excluded span. These are the existing recipe's rules, not universal
scientific sufficiency criteria.

The next method contract must specify NN review/correction provenance, adjacency,
minimum usable duration per metric, stationarity/context and respiration support,
baseline/task/recovery windows, missing/excluded fractions, repeated-epoch and
person weighting. Duration and interpretation must follow the intended measure
and protocol rather than a universal short window; the
[2024 Society for Psychophysiological Research guidelines](https://doi.org/10.1111/psyp.14604)
provide current measurement/reporting guidance. Optional Poincare, entropy or
DFA measures need named parameters, support refusal and reference oracles before
admission. Their availability in [NeuroKit's HRV API](https://neuropsychology.github.io/NeuroKit/functions/hrv.html)
does not mean Brohn implements them. No stress, emotion or sympathovagal-balance
score is part of this requirement.

## Skin-temperature method boundary

`temperature-calibrated-descriptive/1.0` accepts already calibrated Celsius,
Kelvin or Fahrenheit and retains Celsius values. It does not calibrate raw
counts. Per supported continuous interval it saves mean, sample SD, minimum,
maximum, range, first/last values, endpoint change, linear slope in degrees
Celsius/minute and a trapezoidal time-weighted mean. Missing data and clock gaps
split support; filtering, imputation and resampling are not added. Optional
threshold excursions require a declared protocol rationale and retain sampled
boundaries/censoring; they are not an automatic physiological event detector.

Existing mapping text records sensor site, calibration source, acquisition
filtering and conditions/settling, including explicitly unknown context. These
are declarations, not verified physical accuracy. A skin-temperature profile
must distinguish skin contact/site from ambient, core or thermal-image values,
and preserve sensor model, attachment/coverage, calibration evidence and
uncertainty, ambient/local microclimate, settling interval and stable-condition
support. Experiments with contact sensors show that environmental gradients and
coverage can change bias even after conventional calibration
([MacRae et al., 2018](https://pubmed.ncbi.nlm.nih.gov/30062610/)). No universal
settling duration, temperature cutoff or emotional meaning is asserted here.

A valid baseline/event recipe must bind actual recorded time and event evidence,
the same person/session/site/unit/calibration context, explicit baseline and
response/recovery windows, gap/exclusion support and aggregation. Retain the full
trace and show the supported baseline/response portions with numerical
alternatives. Endpoint change is last minus first within an interval; current
paired condition synthesis is a separately declared comparison. Neither silently
subtracts a recorded baseline. Fragmented observations in one exposure remain
unavailable for pooling until a specific aggregation recipe is reviewed.

## Bounded next implementation sequence

1. **Finish the active saved cardiac adapter** (BWP02/06/09/13/15/17): exact
   originals and exclusion parents, full streams/peaks/spectra/ledger/crosswalk,
   accessible figures/tables, one Prepare flow, current-authority historical
   reads, evidence-only conservation and native/offline/cold acceptance. This
   preserves current RR/PRV science; it does not establish NN-HRV.
2. **Freeze the next scientific contracts** (BWP03/09): NN/adjudication and
   metric-specific HRV duration/baseline policies; skin-site/context and recorded
   baseline/event rules. Use original reference cases and declared expected
   results, then independent algorithms and adversarial support cases. Version
   changed science; keep current reports byte-exact. Optional nonlinear metrics
   remain separately gated.
3. **Connect temperature source and reporting adapters** (BWP06/09/13): retain
   direct calibrated import, add the needed multistream and exclusion paths,
   then a saved-reader/display/package contract covering all original values,
   intervals, events, unavailable outcomes, source metadata and decisions.
4. **Qualify the complete researcher route** (BWP15/17): plan → source → explicit
   mapping → quality/exclusion review → supported analysis → baseline/event
   comparison → saved review → portable report → exact historical reopen.
   Show method/support reasons before findings; keep full traces and optional
   details accessible at 390 px, desktop and print. Check latency, cancellation,
   duplicate commands, authority revocation and cold restart. Keep synthetic,
   empirical reference, named-device and observed-usability evidence distinct.

Reuse existing evidence rather than rerunning it for this inventory:
[cardiac spectra](../qa/CARDIAC-SPECTRUM-ACCEPTANCE.md),
[curated exclusions](../qa/CARDIAC-EXCLUSION-CURATED-SOURCE-ACCEPTANCE.md),
[peripheral independent checks](../qa/PERIPHERAL-INDEPENDENT-REVIEW.md), and
[the 48-check peripheral researcher journey](../qa/PERIPHERAL-RESEARCHER-JOURNEY.md).
Those scoped software receipts do not qualify physical devices, NN classification,
the new baseline/event contracts or the whole platform. No new analysis jobs or
tests were run for this documentation audit.
