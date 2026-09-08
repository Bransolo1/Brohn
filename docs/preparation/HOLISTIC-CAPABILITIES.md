# Brohn holistic capability and analysis scope

Prepared 2026-09-08. This is the expanded scope for the forthcoming large build, extending the earlier method examples. The intended product is a complete research workflow: design a controlled study, combine behavioral tasks and questionnaires with the available sensors, collect or import, resolve quality exceptions, and receive a reproducible result.

The [capability register](capability-register.json) contains **50 capability entries across 28 families**. It distinguishes measurement, experimental procedure, analysis and interpretation. It is a planning contract, not an enabled-feature list. Existing implementation and reference evidence remain in the [method reuse register](../methods/reuse/README.md); the broader [architecture review](ARCHITECTURE-READINESS.md) supplies shared-system constraints.

## Why the scope is broader

The competitor baseline includes more than EDA, EEG and gaze. iMotions publicly lists fNIRS, facial expression, respiration, motion capture, GPS and voice, alongside its conventional physiological modules and remote webcam features. These are explicit Brohn families rather than unrecorded future ideas. [iMotions product catalogue](https://imotions.com/)

Commercial research also needs explicit choice and rich questionnaires, linked to each stimulus and task. Qualtrics exposes a broad item library and configurable respondent paths; its conjoint and MaxDiff workflows reinforce that choice experiments need their own design and analysis, not merely another rating widget. [Question types](https://www.qualtrics.com/support/survey-platform/survey-module/editing-questions/question-types-guide/question-types-overview/), [conjoint/MaxDiff survey integration](https://www.qualtrics.com/support/conjoint-project/survey-tab-px/building-additional-survey-content-px/)

Behavioral coverage extends beyond IAT and push/pull. Established task libraries include single-category association, GNAT, priming, AMP, attention, interference, learning and response inhibition. Their presence in a vendor library establishes a useful scope reference; it does not freeze Brohn's protocol or grant redistribution rights to scripts. [Inquisit implicit methods](https://www.millisecond.com/library/categories/implicitattitudes), [PsyToolkit experiment library](https://www.psytoolkit.org/library/)

## Four concepts the architecture must keep separate

| Layer | Example | Required identity |
|---|---|---|
| Modality | EEG voltage, pupil diameter, facial landmarks, keypresses, questionnaire answers | Stream/channel, units, source clock, sensor/model, validity |
| Paradigm | Oddball, BIAT, control/test viewing, AMP, conjoint | Protocol, stimulus/control assignments, timing, response mapping |
| Analysis | ERP mean amplitude, SCR response, D score, AOI dwell, choice utility | Recipe/version, parameters, reference engine, quality and uncertainty |
| Interpretation | Visual allocation, association strength, reported liking, a model's expression label | Defined claim, population/context, evidence and limitations |

This separation allows EEG during an IAT or eye tracking during a questionnaire without inventing a new modality. It also prevents a facial expression category from becoming a participant's reported feeling, or a gaze coordinate becoming a universal attention score. Brohn can show these results together and explain where they agree or differ.

## Full coverage map

The register specifies inputs, outputs, controls, dependencies and status for each row below. Some rows cover related variants; every runnable variant still needs its own frozen profile.

| Area | Capability IDs and included analyses |
|---|---|
| Eye and ocular behavior | `gaze.events`: raw gaze, fixation/saccade events, validity, later pro/antisaccade and pursuit. `gaze.aoi`: dwell, visits, fixation counts, first fixation with censoring, transitions, scanpaths and heatmaps. `gaze.pupil_blink`: pupil baseline/timecourse, peak/area, blinks. `gaze.naturalistic`: moving AOIs, glasses, screen recordings and VR/world coordinates. |
| EEG and neural response | `eeg.erp`: reference, filters, bad channels, reviewed ICA, epochs and ERP. `eeg.spectrum`: PSD, absolute/relative bands and specified asymmetry. `eeg.time_frequency`: ERSP, ERD/ERS and ITC. `eeg.frequency_tagging`: SSVEP/ASSR. `neural.advanced`: connectivity, source models, microstate/complexity/aperiodic extensions and decoding. |
| Hemodynamic brain measurement | `fnirs.hemodynamics`: native/SNIRF import, optical density, HbO/HbR, channel quality, motion treatment, short-channel nuisance regressors, task GLM and ROI contrasts. |
| Autonomic/cardiorespiratory | `eda.activity`: tonic, phasic, SCR and nonspecific activity. `ecg.hrv`: beats, rate, time/frequency/nonlinear HRV. `ppg.prv`: pulses, PRV and pulse amplitude. `respiration.cycles`: cycle rate/amplitude/timing and variability. `cardiorespiratory.coupling`: RSA and separately specified coupling. |
| Muscle and peripheral physiology | `emg.activation`: bursts, RMS/integrated activation and spectral fatigue. `emg.facial_startle`: muscle-specific facial response and startle. `eog.ocular`: EOG blinks/ocular regressors. `temperature.peripheral`: skin or thermal ROI changes. `hemodynamics.advanced`: BP, impedance, PEP/LVET and supported device oxygenation. |
| Movement and context | `movement.sensors`: IMU, force, pressure and GPS context. `webcam.pose`: visible body/hand landmarks, geometry and movement. |
| Webcam and audio | `webcam.facial`: geometry, AU and native expression outputs. `webcam.gaze`: calibration, validation and screen gaze. `webcam.physiology`: separately tested rPPG and camera respiration. `audio.acoustics`: speech timing, pitch/intensity, jitter/shimmer/HNR and optional transcription/model adapters. |
| Implicit association | `implicit.iat`, `implicit.biat`, `implicit.single_category`, `implicit.gnat`: distinct full, brief, single-category and signal-detection profiles. `implicit.agile_relational`: speeded association/verification, with EAST/IRAP/RRT as separate extensions. |
| Priming and approach | `implicit.priming`: evaluative/semantic/masked procedures. `implicit.amp`: prime-related evaluation proportions. `approach.aat`: input-specific push/pull assessment or training. `approach.vaast_manikin`: separate self/object-motion profiles. |
| Attention and cognitive behavior | `attention.tasks`: dot-probe, cueing, search, ANT and vigilance extensions. `inhibition.interference`: Stroop, Flanker, Simon and Go/No-Go. `inhibition.stop_signal`: adaptive stop-signal and SSRT. `learning.memory`: implicit learning, recognition, working memory and conditioning. `choice.psychophysics`: forced choice, thresholds, discounting/risk and later decision models. `motor.trajectory`: mouse/touch/reaching paths. |
| Explicit response and UX | `questionnaire.items`: choice, text/numeric, Likert/matrix, slider, rank, allocation and hotspots. `questionnaire.flow`: branching, piping, randomization, quotas, loops, translations and repeated waves. `questionnaire.scales`: keyed scores, coverage, UX task outcomes and psychometrics. `choice.conjoint_maxdiff`: paired choice, best/worst, conjoint and utility simulation. |
| End-to-end platform | `design.protocols`, `centralization.recordings`, `multimodal.analysis`, `reporting.automation`, `operations.research`: controlled design, synchronized recordings, joint analysis, automatic reporting and recoverable team/teaching workflows. |

Beyond these consumer/UX families, the generic stream/adapter and recipe interface can admit EGG, imported MEG/fMRI derivatives, biochemical/context observations or new sensors without redefining the core database. Those are specialist extensions requiring their own schemas and methods, not a claim of current native acquisition or an automatic promise to implement all biomedical instruments.

## Reuse decisions for the expanded families

**fNIRS:** use MNE with an MNE-NIRS worker extension. The official package covers supported device loading, optical-density/hemoglobin conversion, channel quality and configurable GLM analysis. Preserve wavelengths, optode coordinates, pathlength settings and short-channel identity in the input contract. [MNE-NIRS](https://mne.tools/mne-nirs/stable/index.html)

**Frequency tagging and advanced EEG:** a versioned SSVEP recipe can reuse MNE's documented spectrum/SNR approach. Connectivity belongs in a distinct pack using MNE-Connectivity and an explicit estimator, rather than adding a generic “connectedness” field to band power. Physical presentation evidence and independent noise/ROI definitions belong with the task. [MNE frequency-tagging example](https://mne.tools/1.7/auto_tutorials/time-freq/50_ssvep.html), [MNE-Connectivity API](https://mne.tools/mne-connectivity/stable/generated/mne_connectivity.spectral_connectivity_epochs.html)

**Video movement and camera physiology:** MediaPipe supplies a concrete pose-landmark route; geometry/confidence are outputs in their own right. pyVHR is a candidate comparison framework for video pulse estimation. Camera respiration needs its own algorithm or provider: installing a face tracker or an ECG package does not implement it. [MediaPipe pose](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker), [pyVHR](https://github.com/phuselab/pyVHR)

**Audio:** Praat/Parselmouth is a concrete local acoustic-analysis candidate. Keep voice activity, acoustic features, transcription and affect prediction as different job types. openSMILE can be an optional licensed route; its published terms restrict commercial-product use of the freely available distribution, so it should not silently become Brohn's default. [Parselmouth](https://parselmouth.readthedocs.io/en/stable/), [openSMILE licensing](https://audeering.github.io/opensmile/about.html)

**Specialized physiology:** retain a named-device extension for calibrated blood pressure, impedance cardiography and oxygenation. BIOPAC's documented families show the relevant outputs and acquisition dependencies. These streams can use the common import, clock and report services while their calibration and derivations stay device-specific. [Cardiovascular measurements](https://www.biopac.com/application/cardiovascular-hemodynamics/), [impedance cardiography](https://www.biopac.com/application/icg-impedance-cardiographycardiac-output/)

**Behavioral methods:** implement complete protocol/scorer pairs from original methods, with vendor variants identified separately. Stop-signal has a consensus procedure and analysis reference; VAAST has author-provided implementation and R analysis material. These are concrete adoption routes. [Stop-signal consensus](https://elifesciences.org/articles/46323), [VAAST author implementation](https://us.psytoolkit.org/experiment-library/vaast_images.html)

**Explicit choice:** evaluate cbcTools for design/simulation and mlogit for discrete-choice analysis; the survey compiler supplies the participant tasks and stable design IDs. A single best/worst question is not automatically a complete MaxDiff design. [cbcTools](https://cran.r-project.org/web/packages/cbcTools/index.html), [mlogit](https://cran.r-project.org/web/packages/mlogit/index.html)

Downloads and installations are tracked separately from this scope review. Every prepared engine still needs a Brohn adapter and recipe-level integration evidence. Reuse the published method as it stands; test the particular units, settings, timing and output mapping Brohn adds.

## What low-click holistic operation means

1. **Start with a question.** “Which packaging draws notice and is preferred?” selects viewing/control design, gaze outcomes and liking. A different question can add association, EDA or facial outputs without asking the user to assemble an analysis pipeline.
2. **Show available routes.** A capability resolver checks imported data, available local devices and configured models/providers. Explain exactly what a route supplies; preview and sample data remain visibly separate.
3. **Compile one study.** Stimulus/control, baseline, practice, task and questionnaire blocks share a timeline. The protocol stores assignment, response mappings, referents, clock needs and the intended analysis before collection.
4. **Run one preflight.** Check reachable questionnaire paths, controls, assets, input mode, consent, calibration and storage. Each issue links directly to its fix. Novice users see the necessary decision; advanced parameters remain inspectable.
5. **Collect or import once.** Record source clocks, session and exposure keys, raw files, quality and interruption state. Recording completion launches eligible jobs automatically.
6. **Review exceptions in context.** A synchronized trace/media view explains a gap or proposed exclusion. Accepting a revision recomputes affected results, retaining previous artifacts. Automatic AOIs are reviewable proposals.
7. **Read outcomes, then methods.** Show control comparison, usable participants/trials, effect uncertainty and linked explicit results. A methods appendix and reproducible export expose exact versions/settings without cluttering the main result.

The same route must work with keyboard navigation, visible focus, screen-reader labels, readable contrast, plain-language errors, reversible edits and responsive layouts. A novice should not need to know Python, install a scorer or manually join tables.

## Architecture requirements this scope adds

- A **capability resolver** joins registry entries, supported data profiles, installed engines and configured device/model/provider identities. Display capability, readiness and method evidence separately.
- A **multi-rate recording model** handles sampled analog channels, irregular events, audio/video frames, geometry and explicit choices. Coordinate frames, calibration and raw versus corrected clocks are first-class. LSL records synchronization information; correct import and mapping still matter. [LSL synchronization](https://labstreaminglayer.readthedocs.io/info/time_synchronization.html)
- A **recipe compiler** expands a method card into protocol, collection requirements, processing DAG, quality rules, contrasts and report components. It rejects unspecified scientifically consequential defaults.
- A **shared job/artifact service** supports R, Python and optional provider workers, cancellation/retry, hashes, model configuration and partial modality failure. Long processing stays outside Shiny requests.
- A **study-wide quality model** retains separate modality masks and interpretable valid support. A participant excluded from pupil analysis can remain eligible for liking.
- A **statistical plan** declares participant/trial/stimulus structure, controls, baselines, uncertainty, multiplicity and missingness. Multimodal fusion is an extension with external or held-out outcomes, not automatic averaging of incompatible scores.
- An **adapter/recipe extension contract** keeps all 50 entries representable even when only some are enabled on a particular machine. Enabling a named live adapter additionally requires evidence for that actual setup.

## Build disposition and remaining decisions

The register proposes **33 core-build entries**, **14 explicit extension entries** and **3 entries requiring a named device/provider route**. These tiers sequence delivery; they do not shrink Brohn's long-term scope. A core entry may contain advanced variants that stay disabled until their individual profiles are complete.

Before calling the large build runnable, map every core entry to its implementation package and import/run-to-report acceptance fixture. Resolve the exact initial protocols for SC-IAT, GNAT, priming, AMP, attention and interference tasks; do not replace them with an unlabelled generic reaction-time demo. Bind engine versions and available model artifacts from the tool inventory, select native import fixtures, and keep provider/rig requirements visible. This is integration preparation, not a request to recreate the underlying published science.

The existing 238-ticket planning archive remains the historical backlog. This register supplies the current holistic coverage map; the master build plan must account for every ID as core work, a named dependency or an explicit extension.
