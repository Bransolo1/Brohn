# Other physiology: reusable analysis recipes

Brohn draft, 2026-09-08. Target **NeuroKit2 0.2.13** in the isolated Python worker; R owns recipe selection, eligibility, contrasts and reporting. API availability is not scientific qualification. Package pins are in [requirements-methods.txt](../../../scripts/benchmarks/requirements-methods.txt). Online NeuroKit documentation can describe development versions: freeze the installed implementation and explicit parameters.

## Common contract and current evidence

Require channel name/type, declared amplitude unit and scaling, sampling rate in Hz, source timestamps, missing spans, sensor/site, acquisition filters, event clock mapping and protocol/exposure identity. Store raw, cleaned, rejected and corrected data separately. Split discontinuous runs before filtering; exclude filter transients. Never let convenience functions silently fill missing samples, alter beats or choose event-versus-interval analysis without a recipe decision. Return usable duration, event/interval counts, correction fraction and exclusion reasons for every measure.

The [reference results](physiology-reference-results.json) verify analytic MeanNN, SDNN and RMSSD, plus an explicit pNN50 denominator. Processing the public resting example produced aligned ECG/RSP series, 478 R peaks returned after the pipeline's automatic correction and 80 respiratory peaks. These are **smoke checks**, not labelled beat/breath accuracy; source amplitude calibration was not independently established. No PPG, EMG, EOG, rPPG or fNIRS benchmark is complete.

## ECG and HRV

In pinned NeuroKit 0.2.13, `ecg_process` hardcodes `correct_artifacts=True` and forwards additional kwargs only to cleaning. Compose `ecg_clean` and `ecg_peaks` directly for recipes needing explicit detector/correction settings; do not present unsupported convenience-wrapper parameters as applied. [Pinned processing wrapper](https://raw.githubusercontent.com/neuropsychology/NeuroKit/v0.2.13/neurokit2/ecg/ecg_process.py).

Input ECG as voltage with electrode lead, polarity and conversion recorded; amplitude in mV or microvolts must never be inferred from magnitude. Use `ecg_clean`, `ecg_peaks`, `ecg_quality` and, after inspection, `ecg_process`; choose a named detector such as `neurokit`, `pantompkins1985` or `hamilton2002`. Preserve original sample indices and detector/correction settings. Quality scores flag candidates; they do not establish normal sinus beats. Review clipping, contact loss, motion, missed/double detections and ectopic intervals. Keep original RR and accepted normal-to-normal (NN) intervals distinct; do not concatenate across rejected gaps. [NeuroKit ECG APIs](https://neuropsychology.github.io/NeuroKit/functions/ecg.html).

| Recipe | Definition and constraints |
|---|---|
| Heart rate / cardiac response | Interval rate is `60000 / RR_ms` bpm. Distinguish its time-weighted mean from `60000 / mean(RR_ms)`. For event responses, declare pre-event baseline, response window and interpolation; report usable beats/time. Short-trial heart-rate change does not establish short-trial HRV. |
| Time-domain HRV | `hrv_time`: MeanNN is mean NN; SDNN is sample standard deviation (`ddof=1`); RMSSD is root mean square of accepted **successive** NN differences, all in ms. Retain NN and successive-pair counts. The analytic fixture gives 1000, 141.59846508095774 and 200 ms respectively. |
| pNN50 | Count absolute successive differences **greater than**, not equal to, 50 ms. Pinned NeuroKit divides by `len(retained_differences)+1`: 399/400 = **99.75%** on the complete 400-interval fixture; dividing by 399 differences gives 100%. Missingness can change the retained-pair denominator. Export numerator, denominator and convention. [Pinned implementation](https://raw.githubusercontent.com/neuropsychology/NeuroKit/v0.2.13/neurokit2/hrv/hrv_time.py). |
| Frequency-domain HRV | `hrv_frequency`: freeze PSD estimator, detrending, interpolation rate, usable duration and normalization. Conventional LF is 0.04–0.15 Hz, HF 0.15–0.40 Hz; specify boundary handling. Absolute power is ms²; normalized power requires its denominator. Do not label LF/HF sympathovagal balance or a universal stress score. [API](https://neuropsychology.github.io/NeuroKit/functions/hrv.html), [interpretation limits](https://pubmed.ncbi.nlm.nih.gov/23431279/). |

Start with comparable stationary five-minute blocks after an acclimatization/baseline protocol; shorter recordings require metric-specific evidence. Exclude unsupported frequency bands and long-term metrics instead of treating returned numbers as qualified. Record posture, movement, breathing and experimental order. `hrv_nonlinear` and `hrv_rsa` are later recipes requiring duration/parameter sensitivity checks; RSA requires synchronized respiration and a declared estimation method. [Psychophysiology recommendations](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2017.00213/full).

## Contact PPG

Require optical channel units (often device-relative), wavelength/site, sample rate and motion/contact information. `ppg_process(method="elgendi", method_quality="templatematch")` provides cleaning, systolic peaks, pulse rate and quality; `ppg_clean`/`ppg_peaks` expose the separate stages. Check saturation, low perfusion, movement, irregular sampling and false peaks; retain rejected windows. [Pinned PPG implementation](https://raw.githubusercontent.com/neuropsychology/NeuroKit/v0.2.13/neurokit2/ppg/ppg_process.py).

Name interval variability **PRV**, preserving pulse peak/foot definition. Do not inherit ECG HRV qualification: pulse transit and waveform changes add variability. Validate timing and each PRV endpoint against simultaneous ECG across intended conditions, using bias/limits of agreement and error distributions, not correlation alone. [Paired empirical study](https://pubmed.ncbi.nlm.nih.gov/18663635/). PPG amplitude is not calibrated blood volume; these recipes do not infer oxygen saturation or blood pressure.

## Respiration

Use belt displacement, airflow or calibrated volume with modality-specific units; establish whether upward movement means inspiration. Belt amplitude alone does not provide tidal volume in litres. `rsp_process(method="khodadad2018")`, `rsp_clean`, `rsp_peaks`, `rsp_rate` and `rsp_intervalrelated` support cycle detection, rate, phase durations and amplitude. Record RVT method (`harrison2021`, `birn2006` or `power2020`) separately. [Respiration APIs](https://neuropsychology.github.io/NeuroKit/functions/rsp.html).

Report breaths/minute, inspiration/expiration duration in seconds, their ratio, accepted cycle count, and amplitude/RVT with source units. Specify complete-cycle inclusion, sigh/cough/speech handling and missing-span boundaries. Analyze enough complete breaths; the package's interval-analysis duration heuristic is not a scientific minimum. Compare matched baseline/task windows. Check belt slip, clipping, motion, inverted polarity and implausible cycle shapes against raw traces; no-breath detections are unavailable, not zero breathing.

## Surface, facial and startle EMG

Record voltage scaling, bipolar montage, muscle/side, electrode placement, acquisition bandwidth and reference/ground. Follow [SENIAM muscle-specific placement](https://seniam.org/sensor_location.htm); facial placements need their own protocol. `emg_clean`, `emg_amplitude`, `emg_activation`, `emg_eventrelated` and `emg_intervalrelated` provide reusable stages. NeuroKit's BioSPPy cleaner uses a 100-Hz high-pass, not a universal EMG setting. Its missing-data forward fill is unsuitable as an implicit Brohn policy. [Pinned cleaner](https://raw.githubusercontent.com/neuropsychology/NeuroKit/v0.2.13/neurokit2/emg/emg_clean.py), [EMG APIs](https://neuropsychology.github.io/NeuroKit/functions/emg.html).

| Recipe | Required outputs and controls |
|---|---|
| General surface EMG | Specify bandpass/notch, rectification or RMS, envelope window and burst threshold/minimum duration. Output RMS/envelope amplitude in voltage, integrated rectified activity in voltage-seconds, onset/offset and active-time fraction. MVC normalization requires a recorded reference contraction; retain the divisor. Check motion, line noise, ECG leakage and crosstalk. |
| Facial EMG | Separate corrugator/zygomaticus channels and baseline/task windows; report within-participant amplitude contrasts and valid trials. Control talking, chewing, blinks and electrode motion. Electrical muscle activity does not directly yield emotion categories. |
| Startle eyeblink | Use orbicularis-oculi EMG and measured probe onset. Prespecify baseline, onset/peak latency windows and response threshold. Report peak-minus-baseline/onset definition, latency, response probability and artifact exclusions. Distinguish magnitude including valid nonresponses from amplitude among responders; artifacts are missing. Generic burst detection is insufficient. [Startle consensus](https://pubmed.ncbi.nlm.nih.gov/15720576/). |

## Advanced routes and empirical acceptance

- **Pupil:** use [GAZE-REUSE.md](GAZE-REUSE.md)'s per-eye units, blink masking, luminance controls and subtractive baseline rules; webcam gaze is not pupil diameter.
- **EOG:** `eog_process`/`eog_peaks` require voltage, horizontal/vertical montage and reviewed blink labels. Calibrated gaze angle is a separate calibration problem. [EOG APIs](https://neuropsychology.github.io/NeuroKit/functions/eog.html).
- **rPPG:** evaluate POS/CHROM through [rPPG-Toolbox](https://github.com/ubicomplab/rPPG-Toolbox) with frame timestamps, lighting/motion/skin-tone strata and simultaneous reference ECG/PPG. NeuroKit's [`video_ppg`](https://neuropsychology.github.io/NeuroKit/_modules/neurokit2/video/video_ppg.html) is explicitly described upstream as nonworking/experimental; do not adopt it. No video models were installed.
- **fNIRS:** MNE offers optical density, scalp-coupling checks, motion repair and Beer–Lambert conversion. Require wavelengths, source-detector geometry, pathlength factors, short-channel/systemic-noise strategy, HbO/HbR units and haemodynamic windows; GLM needs a separately pinned MNE-NIRS route. [MNE workflow](https://mne.tools/stable/auto_tutorials/preprocessing/70_fnirs_processing.html), [consensus](https://pmc.ncbi.nlm.nih.gov/articles/PMC7793571/).

Next references: annotated [MIT-BIH ECG](https://physionet.org/content/mitdb/1.0.0/) and [BIDMC PPG/respiration](https://physionet.org/content/bidmc/1.0.0/), retained externally under their stated licences. These clinical datasets test algorithms, not Brohn's target population. Measure event precision/recall, timing error, unit accuracy and endpoint agreement; obtain independently reviewed EMG/breath/beat labels and device-specific recordings before qualification. Keep package reproduction, empirical agreement and acquisition validation separately reported.
