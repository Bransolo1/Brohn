# Brohn scientific workers

`physiology.py` executes bounded, explicit recording-level analysis. R owns the
immutable dataset version, job lifecycle, researcher review, protocol linkage,
participant-aware comparisons and reporting. Worker completion is numerical
execution evidence; it does not establish device or scientific qualification.

## Runtime and supported recipes

| Modality | Prepared Python environment | Implemented outputs |
|---|---|---|
| `eda` | `work/tooling/methods-venv` | Conductance cleaning, 0.05-Hz tonic/phasic separation, SCR onset/peak/amplitude/rise/50% recovery, tonic level/slope, response activity and phasic area. |
| `eeg` | `work/tooling/methods-venv` | Channel Welch PSD, explicit absolute/relative bands, total power and RMS. CSV, EDF, BDF, FIF and MATLAB v5/v7 EEGLAB SET readers; SET companions must be local `.fdt` basenames. |
| `ecg` | `work/tooling/methods-venv` | Explicit uncorrected R-peak detection, candidate RR interval/rate/time-domain variability and duration-gated LF/HF spectral outputs. |
| `ppg` | `work/tooling/methods-venv` | Explicit uncorrected systolic pulse peaks, pulse rate and candidate PRV, separately named from ECG. |
| `respiration` | `work/tooling/methods-venv` | Complete cycles, rate, inspiration/expiration duration, cycle amplitude and amplitude/duration. |
| `emg` | `work/tooling/methods-venv` | Explicit Butterworth bandpass, rectified and RMS envelope, integrated amplitude, mean/median frequency; bursts only with an explicit calibrated threshold. |
| `audio` | `work/tooling/vision-audio-venv` | WAV/FLAC/OGG digital RMS/peak, Praat pitch with unvoiced missingness, periodic-frame fraction and spectral centroid. |
| `fnirs` | `work/tooling/acquisition-venv` | Native continuous-wave SNIRF, optical density, wavelength-specific Beer-Lambert HbO/HbR conversion, geometry and scalp-coupling screening. |

These directories live under the task's external `work` directory, not in the
repository. The standard profile requires NeuroKit2 0.2.13 and/or MNE 1.12.1;
audio requires Praat-Parselmouth 0.4.7. Results record all relevant package versions.
Nothing installs or downloads itself when a worker runs.

## Request and invocation

```text
python scripts/workers/physiology.py --request request.json --output result.json
```

```json
{
  "schema": "brohn-worker-request/1.0",
  "operation": "physiology",
  "modality": "eeg",
  "source_path": "/immutable-job-source/recording.csv",
  "format": "csv",
  "metadata": {
    "time_column": "timestamp",
    "time_unit": "ms",
    "sampling_rate": 256,
    "value_columns": ["Cz", "Pz"],
    "unit": "uV",
    "participant_column": "participant",
    "session_column": "session",
    "condition_column": "condition",
    "exposure_column": "exposure"
  },
  "parameters": {}
}
```

CSV time units are `s`, `ms`, `us`, `ns` or `sample`. Large integer tick origins
are subtracted as decimals before conversion to floating point. Preserve the
returned exact `source_time_origin`. Time must increase inside each contiguous
group and agree with the declared sample rate. Default tolerance is 2% of one
sample interval; an explicit `timestamp_tolerance_s` may be at most half an
interval. Gaps over 1.5 intervals split processing. This is not a resampling
service. Sample-index-based signal algorithms use the declared sample rate;
original relative timestamps remain in returned event/series records.

Grouping columns split recordings whenever participant, session, condition or
exposure identity changes. Missing/invalid samples split individual channels;
filtering and successive-interval differences never bridge those boundaries.
Without identity columns, a file is one recording, not a table of independent
participants. No cohort standard errors, p-values or condition effects are
created from samples or peaks.

Voltage and conductance scaling is explicit. EEG canonical data are volts;
ECG/EMG outputs are microvolts; EDA outputs are microsiemens. PPG/respiration
accept supported physical or explicitly relative source units. Unknown units
fail. No mean-centering or magnitude heuristic guesses a unit.

Native EEG uses `unit: "native"` or `"V"`, selected `value_columns`, and optional
header-rate cross-checking. Native bad channels and BAD annotations are excluded
before segmentation. Annotation counts, bounded annotation records, native first
sample and scaling are retained. HDF5/v7.3 EEGLAB is explicitly unsupported.

Audio requires `unit: "FS"` (digital full scale). Sampling rate is read from its
header and checked against any declaration. Multichannel audio requires an
explicit zero-based `channel_index`; it is never silently mixed. Native files
can declare `participant_id`, `session_id`, `condition_id` and `exposure_id`.

fNIRS requires `unit: "native"`, complete wavelength-paired `value_columns` and
`parameters: {"ppf": [6, 6]}` with the researcher's chosen factors for the two
ascending wavelengths. The numbers in this example are not a universal preset.
Native geometry must be finite and nonzero. No absolute-value repair of negative
intensity or hidden interpolation occurs. A missing channel sample splits joint
wavelength support. Optical density references each segment's arithmetic mean
intensity, which is distinct from an experimental baseline. Series identify
the source intensity channel for each optical-density value.

## Output and support

The schema is `brohn-worker-result/1.0`. Top-level fields include `engine`,
`source`, `parameters`, `features`, `events`, `series`, `recordings`, `quality`,
`limitations` and `artifacts`. Every numerical result carries `recording_id`,
`segment_id`, `channel` and a `group` object with explicitly supplied identities.
Features have `scope: "recording"`; a segment is always identifiable. Unavailable
results remain `null`, never fabricated zeros. Source and segment sample indices
are named separately when present.

Statuses are `completed`, `partial`, `insufficient_support` and `error`.
Unsupported inputs/settings return an explicit error and exit code 2. A short or
otherwise ineligible segment gets `status: "unavailable"` and its own reason;
other eligible segments still run. No successful empty report conceals them.

Minimum support is part of each named recipe:

- EDA: 20 retained seconds plus at least 10 seconds excluded at each filter edge.
- ECG/PPG: 10 retained seconds plus at least 2 seconds at each edge. Frequency
  outputs additionally require 300 seconds and complete plausible intervals.
- Respiration: 20 retained seconds plus at least 5 seconds at each edge.
- EEG: two complete Welch windows, each 2 seconds by default.
- EMG: at least one retained second after the declared filter/envelope edges.
- Audio: two seconds. fNIRS: 20 continuous positive-intensity seconds.

Event and trace displays are capped at 2,000 records each. Total/displayed counts
and the selection rule are returned. All features use the complete retained
input, not truncated preview arrays. The worker caps file size at 512 MiB,
CSV/native samples at two million, decoded values at twenty million, channels at
64 and channel segments at 2,000. Output replacement is atomic and cannot replace
the request or source file. Request JSON rejects duplicate fields/nonfinite values.

## Interpretation boundaries

EDA preserves the pinned detector's relative-prominence threshold and fixed 50%
recovery; cvxEDA is not silently substituted. The low/high-pass components are
not claimed to reconstruct the input exactly. Peaks do not automatically belong
to the nearest stimulus.

ECG/PPG cleaning composes the explicit cleaner and detector APIs with automatic
artifact correction disabled. Plausibility-screened intervals are candidates,
not confirmed normal-to-normal beats. Report retained intervals and successive
pair counts. pNN50 uses retained-interval count as its declared denominator;
differences crossing rejected intervals are excluded. LF/HF is not a stress or
sympathovagal-balance score.

EEG does not silently re-reference, notch, interpolate channels, remove ICA
components or invent ERPs without measured markers. EMG does not invent MVC,
facial/startle or emotion interpretations. Respiration polarity needs checking,
and source amplitude is not automatically tidal volume. Acoustic periodicity is
not speech recognition, VAD, attention or emotion. fNIRS still requires explicitly
specified motion/systemic nuisance handling and task GLM/baseline recipes for
task-evoked inference.

## Executable evidence

`tests/workers/physiology.py` contains:

- 13 standard tests in the methods environment: independent sine PSD/RMS and
  units, known RR arithmetic, group/missing-gap separation, exact large ticks,
  minimum support, explicit failures, atomic CLI and native FIF annotation
  handling; synthetic EDA/ECG/PPG/respiration execution also passes.
- `AudioTests` in the audio environment: known 220-Hz tone, analytic RMS, silence
  missingness and grouping.
- `FnirsTests` in the acquisition environment: native SNIRF conversion,
  independently calculated log optical density, 3-cm geometry, inverse pathlength
  scaling and rejection when factors are absent.

Run a selected suite as `python tests/workers/physiology.py PhysiologyTests`,
`AudioTests` or `FnirsTests` in the respective environment. These are wiring,
analytic and synthetic/reference checks, not representative empirical accuracy
or physical device qualification. Native FIF and SNIRF are exercised; native
EDF/BDF/SET and audio FLAC/OGG still need real-format journey fixtures.
