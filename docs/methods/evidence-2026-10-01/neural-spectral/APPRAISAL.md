# EEG spectral and Morlet options: bounded academic appraisal

Reviewed 1 October 2026 against joined source13, whose production bytes equal
source12. This covers Welch1.0 and Morlet1.0/1.1 only. It is an inactive evidence
candidate; no recipe, default, registry, saved output or qualification changes.
ERP, SSVEP, connectivity, artifact correction and consumer prediction retain
their separate open reviews. The broader platform inventory remains applicable.

## Supporting literature and review scope

- **Keil et al. (2022)**, *Recommendations and publication guidelines for studies
  using frequency domain and time-frequency domain analyses of neural time
  series*, Psychophysiology59(5), e14052. [Publisher](https://onlinelibrary.wiley.com/doi/10.1111/psyp.14052).
  Selected supporting text: sections3.1.1–3.1.3,3.2.4,3.2.6 and Tables2–4.
  Consensus guidance requires explicit spectral resolution, taper, normalization,
  reference, smoothing and baseline assumptions. It discourages unqualified
  relative-power interpretation and recommends retaining the full spectrum.
  Baseline duration, separation and edge support need justification. It is not
  an empirical qualification of Brohn's settings or a consumer construct model.
- **Grandchamp and Delorme (2011)**, *Single-Trial Normalization for Event-Related
  Spectral Decomposition Reduces Sensitivity to Noisy Trials*, Frontiers in
  Psychology2:236. [Publisher](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2011.00236/full).
  Selected supporting text: ERSP models, classical baseline approaches and
  Discussion. Simulation and visual-task analyses compare normalization order
  and noise sensitivity. Their proposed full-epoch single-trial normalization
  differs from Brohn's mean-power-then-baseline route. This supports making that
  distinction visible; it does not establish one universal baseline winner or
  validate Brohn's subtraction/floor policy. Method-development evidence.
- **Gyurkovics, Clements, Low, Fabiani and Gratton (2021)**, *The impact of 1/f
  activity and baseline correction on the results and interpretation of
  time-frequency analyses of EEG/MEG data: A cautionary tale*, NeuroImage237,
  118192, doi:10.1016/j.neuroimage.2021.118192.
  [University-hosted paper](https://ueaeprints.uea.ac.uk/id/eprint/96237/1/Gyurkovics_etal_2021_NeuroImage.pdf).
  Selected supporting text: sections4.2–4.3. In additive simulations, division
  followed by dB conversion could distort condition/group comparisons when
  broadband levels differed. Subtraction performed better under that assumed
  model; this is not proof that every dataset follows it. They require an explicit
  baseline model and discuss unresolved mixtures. Fabiani/Gratton also coauthor
  Keil2022, so these are not fully independent author groups.
- **van Diepen and Mazaheri (2018)**, *The Caveats of observing Inter-Trial
  Phase-Coherence in Cognitive Neuroscience*, Scientific Reports8:2990.
  [Publisher](https://www.nature.com/articles/s41598-018-20423-z).
  Selected supporting text: equation3, simulations and concluding discussion.
  Power/SNR and evoked amplitude/latency can alter measured phase consistency
  without the intended phase mechanism. Their simulation settings do not cover
  every study. Brohn's original-signal ITC therefore needs its own interpretation,
  even when the accompanying power is evoked-subtracted. Distinct authors from
  the other appraised groups; no direct Brohn or consumer validation.
- **Rawls and Sponheim (2025)**, *Oscillatory and Aperiodic Contributions to EEG
  Event-Related Time-Frequency Metrics During Cognitive Control and Reinforcement
  Processing: A Registered Report*, Psychophysiology62(6), e70073.
  [Publisher](https://onlinelibrary.wiley.com/doi/10.1111/psyp.70073).
  Selected supporting text: sections2.1,2.5,4.1,4.4. Separate periodic/aperiodic
  analyses found both forms of task dynamics in flanker/gambling recordings;
  final samples64/44 were deployed US veterans without the specified PTSD/mTBI
  diagnoses. STFT resolution and parameterization limits remain. This provides
  recent, distinct-author evidence for examining spectral composition, not a
  ready-made advertising, preference or engagement model. Brohn does not implement
  this study's parameterization through its existing Welch/Morlet recipes.

The following are **metadata/abstract-scope leads in this pass**, not claims of
full supporting-text review:

- **Donoghue et al. (2020)**, *Parameterizing neural power spectra into periodic
  and aperiodic components*, Nature Neuroscience23,1655–1665,
  [doi:10.1038/s41593-020-00744-x](https://www.nature.com/articles/s41593-020-00744-x).
  Publisher abstract describes confounding between conventional bands and
  aperiodic parameters, and its proposed separation algorithm. Full publisher
  text was restricted and PMC returned a browser challenge. Exact fitting choices
  have not been reviewed here. Method authors; software availability is separate.
- **Cohen (2019)**, *A better way to define and describe Morlet wavelets for
  time-frequency analysis*, NeuroImage199,81–86,
  [doi:10.1016/j.neuroimage.2019.05.048](https://pubmed.ncbi.nlm.nih.gov/31145982/).
  Verified abstract describes explicit temporal/frequency smoothing using FWHM.
  No exact kernel/parameter equivalence is established. Cohen also coauthors
  Keil2022, so this is not independent corroboration of that consensus.
- **Welch (1967)**, *The use of fast Fourier transform for the estimation of power
  spectra: A method based on time averaging over short, modified periodograms*,
  IEEE Transactions on Audio and Electroacoustics15(2),70–73,
  doi:10.1109/TAU.1967.1161901.
  [Author institution record](https://research.ibm.com/publications/the-use-of-fast-fourier-transform-for-the-estimation-of-power-spectra-a-method-based-on-time-averaging-over-short-modified-periodograms).
  Indexed institution abstract screened; direct page retrieval timed out. This
  identifies the method's origin only, not an empirical rationale for Brohn's
  two-second,50%-overlap default. Obtain supporting text for detailed appraisal.

## Exact implementation findings

The machine-readable matrix binds each row to exact recipe versions, fields,
source functions and evidence IDs. Its multi-source links describe relevant
context, not independent qualification of every allowed value.

1. Welch uses `round(window_s*fs)` samples, Hann taper, mean periodogram averaging,
   DC removal and floor-to-integer overlap. It requires two declared windows of
   continuous input. Default2s/50%, allowed1–30s/0–0.9 are software choices.
   Band power sums half-open bins times their width. The full PSD is retained.
   No extra reference, notch, ICA or artifact removal is applied silently.
2. Named bands and the relative denominator are independently configurable. A
   numerator need not be contained in that denominator: the saved value can
   exceed1 and cannot universally mean a fraction of total power. The default
   denominator1–45Hz is a stated reference band. Canonical band names do not
   establish consumer constructs or isolate oscillatory peaks from background.
3. Morlet's selectable cycles are1–30 per frequency. The worker uses zero-mean
   MNE wavelets, FFT convolution and no decimation. The longest discrete kernel
   determines edge exclusion for all frequencies. Recipe1.1 additionally requires
   every baseline kernel to finish strictly before onset and meet declared
   duration at the lowest frequency. This is finite-kernel support; earlier
   acquisition or forward/backward filtering may still spread activity in time.
4. Both Morlet recipes average trial power before applying none/subtract/ratio/
   percent/dB. Baseline power must be strictly greater than the configured floor
   for **all enabled transforms, including subtraction**. That last condition
   is an explicit support policy, not a mathematical denominator requirement for
   subtraction. No source here qualifies its threshold. Recipe1.1 support checks
   do not establish baseline comparability, stationarity or construct validity.
5. Induced power subtracts the condition mean waveform from each retained trial
   before power estimation. ITC always uses phases from the original total
   signal. It averages unit vectors over non-tiny amplitudes, requires at least
   two contributing trials per point, and reports minimum support. That numeric
   floor is neither adequate reliability nor an unbiased sample-size correction.
   Averaged power, ITC and a later participant contrast remain different estimands.
6. Epoch recipes jointly reject missing selected-channel support and require one
   continuous segment. Optional reference/filter/voltage baseline, geometric
   overlap and amplitude/flat rejection precede analysis. A declared minimum
   trial count is a computational admission, not a sample-size justification.
   This pass records these shared prerequisites but does not fully appraise
   their exact settings. Filter/ERP/SSVEP acceptance remains separate.

## Product and design work to implement next

Show a compact method summary beside selection: actual quantity, averaging unit,
baseline model, support and interpretation limit, with expandable citations.
For relative spectra say "ratio to the declared reference band" when the bands
are not nested; retain the full spectrum and denominator. Treat that as a future
presentation correction, not a silent change to stored numbers or recipe IDs.

Prespecify channel/region, frequency/window and main contrast; record acquisition
reference, artifacts, actual event-clock evidence and anticipated usable trials.
Distinguish measured stimulus onset from a software marker. Match or explicitly
model stimulus properties and response/movement demands for the consumer question.
Keep a control stimulus separate from a physiological reference epoch. Order,
carryover, participant/stimulus hierarchy and multiplicity use the wider design
contract; these papers do not supply one universal consumer-study template.

Before a supported profile is offered, independently verify each estimator and
normalization against numerical examples, then test signal/artifact sensitivity
and agreement on appropriate recorded data. Assess baseline model, kernel
smearing, count imbalance and aperiodic changes. Empirical consumer prediction
requires its own held-out validity work. New parameterization, robust trial
normalization or bias-corrected phase estimators need separate versioned recipes.
Do not replace historical calculations or call all eight citations independent.
