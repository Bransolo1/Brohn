# Recorded EEG: native EDF calibration and independent Welch agreement

Date: 20 September 2026. **Passed within the stated numerical scope.** Six public EDF+ recordings were processed by the unchanged `eeg-welch-channel/1.0` worker. An independent binary reader matched all 175,200 selected calibrated samples and their timestamps exactly. All 2,898 complete PSD bins and 252 channel-level feature values agreed with a separate explicit-DFT calculation within the frozen tolerances. This is not artifact-removal, brain-state, clinical or physical acquisition qualification.

## Primary source and prespecified selection

The [EEG Motor Movement/Imagery Dataset v1.0.0](https://physionet.org/content/eegmmidb/1.0.0/), contributed by Gerwin Schalk, provides 64 EEG channels recorded with BCI2000 at 160 Hz. Runs R01/R02 are eyes-open/eyes-closed baseline recordings. Files use EDF+ with a separate annotation signal; the dataset documentation distinguishes electrode indices and run-specific event meanings. Source attribution: [Schalk, 2009, dataset DOI](https://doi.org/10.13026/C28G6P), [Schalk et al., 2004, BCI2000](https://pubmed.ncbi.nlm.nih.gov/15188875/), and the site's requested [PhysioNet platform citation](https://doi.org/10.1038/s44360-026-00096-z). Files are supplied under the Open Data Commons Attribution License v1.0; raw recordings are not redistributed in this repository.

Before downloading or inspecting waveforms, the protocol selected subjects **S001, S050 and S109**, each with **R01 and R02**, and sites **Cz, O1 and O2**. Only a unique header label matching each prespecified site after removal of trailing periods was accepted. Exact source labels remained `Cz..`, `O1..`, `O2..` in worker requests and artifacts. No channel, run, interval or parameter was selected by spectral outcome.

Every sample of each original file was used. Five files contain 61 seconds; S109R01 contains 60 seconds. The T0 annotations cover 60.2 seconds in the 61-second files and 59.5 seconds in S109R01. The comparison therefore concerns **whole recorded files**, including their unannotated final fraction; it does not claim every sample belongs to an exact annotated baseline window. No padding or annotation-driven trimming was introduced.

The original frozen `plan.json` SHA-256 is:

`f2a657fb4d2d92eb98957f4b4575a1796c62518482a85a84a10167c2676c6e48`

The original plan and execution timestamps are retained in the evidence. The downloaded EDF SHA-256 values matched PhysioNet's published `SHA256SUMS.txt`. Record selection and tolerances were frozen before reading the EDFs. These records are now known regression data; another execution is a technical replay, not fresh held-out evidence.

## Independent method

The reference reader uses standard Python and NumPy 2.2.6. It does not call MNE, SciPy, Brohn's header parser or its Welch implementation to obtain reference samples or spectra.

It reads each EDF signal's signed little-endian 16-bit data block directly and applies the header's physical/digital endpoint conversion, then converts the declared amplitude unit to volts. It checks file size, unique channel names, record counts, per-channel sample counts and each EDF+ record's timekeeping annotation. The [original EDF specification](https://www.edfplus.info/specs/edf.html) defines the signal blocks and calibration fields; the [EDF+ specification](https://www.edfplus.info/specs/edfplus.html) distinguishes contiguous and interrupted record timing. Discontinuities or BAD annotations would have stopped this fixed-scope comparison rather than being ignored.

The independent Welch calculation follows averaging of modified periodograms described by [Welch, 1967](https://doi.org/10.1109/TAU.1967.1161901); the [original paper text](https://ocean.phys.msu.ru/courses/geoseries/1967%20Welch,%20The%20Use%20of%20Fast%20Fourier%20Transform%20for%20the%20Estimation%20of%20Power%20Spectra_%20A%20Method%20Based%20on%20Time%20Averaging%20Over%20Short,%20Modified%20Periodograms.pdf) was available through a university-hosted copy. The implementation computes a complex DFT matrix explicitly, rather than calling an FFT or shared PSD helper:

- Two-second windows: 320 samples at 160 Hz; 160-sample overlap; only complete windows.
- Subtract each window's arithmetic mean, then apply the periodic Hann `0.5 − 0.5 cos(2πn/320)`.
- Square the complex transform magnitude and divide by `fs × sum(window²)`; double positive-frequency interior bins, leaving DC and Nyquist undoubled.
- Average the individual densities; retain every 0–80 Hz bin at 0.5 Hz spacing. Convert V²/Hz to µV²/Hz explicitly.
- Integrate by density-bin sum times 0.5 Hz. Delta `[1,4)`, theta `[4,8)`, alpha `[8,13)`, beta `[13,30)` and gamma `[30,45)` use half-open boundaries. Relative power uses `[1,45)` as denominator.

The production call explicitly passes these settings to MNE; it does not rely on MNE's default Hamming window. [MNE's primary API documentation](https://mne.tools/stable/generated/mne.time_frequency.psd_array_welch.html) describes its per-window demeaning and aggregation behavior. The documentation currently describes a newer release; execution used **MNE 1.12.1**, NumPy 2.5.3 and SciPy 1.18.1 under Python 3.12.10.

Separate analytical checks establish the oracle's scaling: a constant signal becomes zero after demeaning; a 20 µV peak-amplitude, bin-centred sine has 200 µV² integrated power; a 20 µV alternating Nyquist signal has 400 µV², with no erroneous Nyquist doubling. Each reference result also satisfies the corresponding window-weighted Parseval identity.

## Executed results

Six actual production worker processes wrote complete artifacts. Six separate production-reader probes returned the full selected native sample arrays and times, allowing a direct comparison to the independent EDF parser. The probes are the implementation **under test**, not the reference oracle. No R catalog publication or browser test was added by this task.

| Original file | Samples per channel | Duration (s) | Welch windows | Maximum absolute PSD difference (µV²/Hz) |
| --- | ---: | ---: | ---: | ---: |
| S001R01 | 9,760 | 61 | 60 | 4.55 × 10⁻¹³ |
| S001R02 | 9,760 | 61 | 60 | 1.14 × 10⁻¹² |
| S050R01 | 9,760 | 61 | 60 | 4.84 × 10⁻¹⁴ |
| S050R02 | 9,760 | 61 | 60 | 2.27 × 10⁻¹³ |
| S109R01 | 9,600 | 60 | 59 | 2.27 × 10⁻¹³ |
| S109R02 | 9,760 | 61 | 60 | 9.09 × 10⁻¹³ |

There are three channels per file, 161 complete PSD bins per channel, and 14 checked features per channel. Across all 18 channel-recordings:

| Quantity | Largest measured absolute difference |
| --- | ---: |
| Calibrated native sample | 0 V |
| Native relative timestamp | 0 s |
| PSD density | 1.14 × 10⁻¹² µV²/Hz |
| Absolute band power | 9.09 × 10⁻¹³ µV² |
| Relative band power | 4.44 × 10⁻¹⁶ proportion |
| RMS amplitude | 7.11 × 10⁻¹⁵ µV |
| Peak frequency | 0 Hz |

Worst relative PSD-bin error was 8.12 × 10⁻¹³. The frozen density tolerance was `1e-8 µV²/Hz + 1e-9 × abs(reference)`; power and relative-power absolute tolerances were `1e-7 µV²` and `1e-10` respectively, with the same relative tolerance. No tolerance was loosened after seeing results. All recorded files passed on the initial worker run.

A subsequent **read-only audit passed 288 checks** of the saved native header/calibration fields, artifact provenance and source/table identities, original sample support, actual method settings, typed column units and feature units/bands. Complete artifact rows and completion counts supplied the numerical comparisons; report/chart previews were not used as the PSD source. The audit and figures were added to the harness after the numerical run; the exact execution-time harness copy/hash remains retained. This did not alter the frozen protocol, numerical oracle or original results.

## What this does and does not establish

This evidence supports native parsing/calibration and the **declared channel-level Welch arithmetic** on these original recorded files. It is independent of the production EDF/MNE/SciPy calculation, though both run on the same host and use floating-point arithmetic.

All selected headers declare µV with identical physical/digital ranges of −8092 to 8092: one digital step is 1 µV. Thus this public set exercises a declared unity physical gain plus µV-to-V conversion. It does not independently qualify every nonzero-offset/gain, native format or calibration convention. All sampled data records were continuous at 160 Hz; physical clock accuracy and device calibration were not measured. No selected sample reached the declared digital rails, but that is not proof of good electrode contact or absence of artifact. The source prefilter text `HP:0Hz LP:0Hz N:0Hz` is preserved as header evidence, not independently verified hardware behavior.

The source retains its acquisition reference. There is no additional high-pass/notch, re-reference, ICA, bad-segment detection or artifact correction in this recipe. Large low-frequency components and narrow spectral peaks remain visible. The figures illustrate numerical outputs; they are not expert artifact labels. Eyes-closed recordings show different spectra in this sample, but no alpha-change or physiological-state criterion was used to pass the implementation, and no attention/emotion score is inferred. Sixty overlapping Welch windows are not sixty independent participants or a demonstrated stationarity interval.

Remaining work includes independently evaluated artifact handling, declared reference/preprocessing choices suited to the study, endpoint interpretation in the intended population, and physical hardware/timing qualification. ERP, Morlet, source localization, connectivity, device impedance and clinical EEG are outside this comparison. No production defect was found in this bounded numerical evaluation; it is not blanket EEG readiness.

## Evidence and reproduction

Original data and all generated files are outside Git:

`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-eeg-physionet-01`

- `plan.json`, `plan.sha256`, `SHA256SUMS.txt`: prespecified protocol and official source hashes.
- `execution-lock.json`, `harness-at-execution.py`: exact production/harness identities at execution.
- `source/*.edf`: unchanged public files.
- Each record folder: independent header, request, production result/log, native reader sample/time probe, complete artifact and `agreement.json`.
- `results.json`: all 18 channel comparisons, frequency bins, reference/worker densities, feature values/errors and source identities.
- `saved-metadata-audit.json`: 288 successful read-only checks.
- `recorded-welch-spectra.png`: complete 0–80 Hz spectra with independent/production overlays.
- `recorded-input-waveforms.png`: first five seconds of independently calibrated O1 source samples, an illustration rather than a selected analysis interval.

Both figures were visually inspected for readable labels, legends, units and clipping. All processes were closed after completion. Frozen production hashes:

| Source | SHA-256 |
| --- | --- |
| `scripts/workers/physiology.py` | `73f987d7feff700e66438f2a4d96f2489b011d45fa118f7f5fa5a71ba4edc04d` |
| `scripts/workers/physiology_artifacts.py` | `76c153d621704ffbbde7db5fda443c2817e2cd5421bd5c4725bda9797593070e` |
| `scripts/workers/headers.py` | `9a34f1c9dd0bcfc5fe1e995da35ad43b1175f28c0b1d7dc5e660e3bc8f3ee158` |

From the repository, using a **new** output folder outside it:

```powershell
$reader = 'C:/Users/User/Documents/Codex/2026-09-20/oka/work/reference-reader-venv/Scripts/python.exe'
$evidence = 'C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-eeg-physionet-new'
& $reader tests/reference/eeg_welch_physionet.py prepare --output $evidence
& $reader tests/reference/eeg_welch_physionet.py run --output $evidence --methods-python '../../work/tooling/methods-venv/Scripts/python.exe'
& $reader tests/reference/eeg_welch_physionet.py audit --output $evidence
& $reader tests/reference/eeg_welch_physionet.py render --output $evidence
```

For the original protocol bytes, copy its plan, plan hash and checksum list into a fresh folder before `run`; copying the `source` directory avoids downloading it again. Exact version replay also requires the listed production code and runtime versions. The harness records current source identities before execution and aborts if they change while jobs run. A different code/runtime result is a newly identified technical comparison, not an overwrite of the retained evidence.
