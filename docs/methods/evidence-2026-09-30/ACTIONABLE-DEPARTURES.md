# Option-level remediation and scientific release gates

This is a bounded code-and-literature comparison dated 30 September 2026, not a finding that every current result is invalid. Paths and line numbers refer to the unchanged application code indexed in `INVENTORY.json` and `SOURCE-SUPPLEMENT.json`. The initial production snapshot was `e861399f8cb40fb261855121f7f22baa99096a81`; the later evidence-contract commit `3aeb27f942f0359e0e7941df1c8a031dff4a28fb` changed documentation. No analyses were executed for this audit.

The gates below are proposed work, not passed tests. Separate scientific computation changes from interpretation, protocol and evidence-binding work. Any changed calculation, eligibility criterion, filtering, detector, scoring or denominator requires an explicit new recipe/version and independent reference expectations. Historical requests, settings, outputs and their citations must remain exact. A UI clarification can describe the original method without rescoring it.

## A01 — Continuous EDA: relative candidates versus a defined conductance response

**Confirmed procedure difference.** `eda-neurokit-highpass/1.0` and `/1.1`, `scripts/workers/physiology.py:124`, `:398` and `:430`, use relative prominence (default 0.1), without an absolute conductance-amplitude criterion. `scr_count` is the count of emitted retained candidates. The event EDA recipes separately require an absolute criterion; they must not be conflated with continuous EDA.

[Boucsein et al. (2012)](https://pubmed.ncbi.nlm.nih.gov/22680988/) recommends defining the minimum conductance change for nonspecific responses, with context/instrument-dependent values around 0.01–0.05 µS. This supports reviewing the definition and noise floor, **not automatically inserting a universal 0.05 µS cutoff**. The high-pass implementation does not inherit validation from [cvxEDA](https://pubmed.ncbi.nlm.nih.gov/26336110/).

**Gate:** retain candidate wording for existing outputs; define a separately named, reviewed future response recipe with acquisition/noise rationale. Reference cases must cover near-flat noise, changes below/at/above the declared absolute criterion, relative-prominence scaling, missing onset/recovery, processing edges and exact constants. Independently annotated recordings must establish detector agreement for the intended device and context. Saved 1.0/1.1 results must remain byte-identical.

## A02 — Keyboard AAT: exact procedure and scoring need their own validation

**Confirmed difference and transfer gap.** `aat-keyboard-cue-balanced/1.0`, `R/platform-methods.R:156`, `:204`, `:293` and `:300`, measures frame-cued key initiation, retains correct first responses within 200–2000 ms, requires four retained trials per category/action cell and reports the unstandardized double difference of cell means in milliseconds.

[Kahveci et al. (2024)](https://pmc.ncbi.nlm.nih.gov/articles/PMC10990989/) evaluates preprocessing and scoring across variants; recommendations depend on task relevance and the tested data. [Krieglmeyer & Deutsch (2010)](https://www.tandfonline.com/doi/abs/10.1080/02699930903047298) independently compares different response implementations. Neither establishes that this exact keyboard/frame-cue recipe is equivalent to joystick movement or a validated consumer preference measure. Do not wholesale transplant a joystick pipeline or automatically replace milliseconds with D.

**Gate:** bind input device, cue relevance, practice/test counts, timing, error rules and scoring to direct evidence. Test known four-cell arithmetic, asymmetrical exclusions, exact RT boundaries and unavailable cells; separately measure browser timing, repeat reliability and consumer criterion validity for this procedure. Any alternative D score or exclusion rule gets a new profile and explicit units. The current double difference is not a single compatibility aggregate.

## A03 — Cardiac: computational support is not NN or metric-duration qualification

**Disclosed scope, not an arithmetic bug.** `scripts/workers/physiology.py:472` retains plausible detected intervals, computes RMSSD from originally adjacent valid pairs without bridging an excluded interval, and gives the pNN50 candidate a retained-interval denominator. This is explicitly disclosed; do not silently change that denominator. `:539` permits processing after ten retained seconds, while frequency features separately require at least 300 seconds of supported peak span. Ten seconds is not general HRV-duration guidance.

[Quigley et al. (2024)](https://pubmed.ncbi.nlm.nih.gov/38873876/) and [Laborde et al. (2017)](https://pmc.ncbi.nlm.nih.gov/articles/PMC5316555/) support metric-, acquisition- and protocol-specific review. Ultra-short evidence such as [Muñoz et al. (2015)](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0138921) is conditional, not a universal ten-second permission or prohibition. PPG remains PRV.

**Gate:** preserve current detected-RR/PRV names, definitions and availability. A future NN-qualified route needs beat annotation/artifact rules, metric-specific duration and respiration/activity context, independent ECG/pulse references and locked reference calculations. Cover excluded-beat adjacency, numerator/denominator, short support, interpolation/band edges and simultaneous ECG–PPG differences. Do not infer stress from LF/HF.

## A04 — EEG: parser bounds and finite wavelet support do not approve a protocol

**Evidence-binding gap.** `R/platform-neural.R:66` admits filter edges of at least three high-pass cycles; `:109` admits a positive Morlet baseline cycle floor and written rationale. Recipe 1.1 correctly checks complete finite pre-event wavelet support. These are implementation rules, not proof that every admitted filter/order/baseline is suitable. The worker itself distinguishes wavelet support from earlier filter spreading (`scripts/workers/neural.py:276`).

[Keil et al. (2022)](https://pubmed.ncbi.nlm.nih.gov/35398913/) and [Widmann et al. (2015)](https://pubmed.ncbi.nlm.nih.gov/25128257/) motivate explicit frequency/filter/window decisions and artifact evaluation.

**Gate:** review every template's reference, filter, edge policy, trial rejection, channels/time windows, cycles, transform, bands and denominator. Use independent impulse/step and known-frequency oracles, including zero-phase pre-event spreading and baseline contamination; add empirical timing/artifact checks. A very small entered cycle floor or a free-text rationale cannot confer scientific qualification. New algorithmic safeguards require versioned science; clearer review status does not.

## A05 — Pupil: explicit baseline support still needs protocol justification

**Admission versus recommendation.** `R/platform-gaze.R:62` permits declared minimum baseline coverage from 0.01 and duration from 1 ms. `:263` implements time-weighted eligible adjacent support and checks the baseline precedes exposure. Those lower parser bounds are not recommended baseline quality.

[Mathôt et al. (2018)](https://pubmed.ncbi.nlm.nih.gov/29330763/) and [Kret & Sjak-Shie (2019)](https://pubmed.ncbi.nlm.nih.gov/29992408/) require attention to baseline quality and preprocessing; they do not justify every admitted value.

**Gate:** template-specific baseline duration/coverage, luminance and gaze-angle control, units and blink-edge policy must have rationale. Reference cases should cover sparse baselines, invalid/zero values, blinks, gaps, unequal time support and missing baseline outcomes. Preserve diameter versus area and each eye's meaning. Interpolation, smoothing or changed eligibility is new science, not a display fix.

## A06 — Sensor and engine transfers: disclose the tested modality

**Transfer gaps.** `respiration-displacement-khodadad/1.0` admits belt displacement or calibrated lung volume (`scripts/workers/physiology.py:153`, `:574`), while [Khodadad et al. (2018)](https://pubmed.ncbi.nlm.nih.gov/30074906/) studied electrical impedance tomography. [Massaroni et al. (2019)](https://pmc.ncbi.nlm.nih.gov/articles/PMC6413190/) describes distinct measurement technologies. Current temperature support can be as short as one second, generic EMG has a default bandpass/RMS envelope, and audio has generic pitch/frame defaults; those are operational choices, not universal consumer protocols.

**Gate:** require source/sensor-specific reference and applicability evidence. Test breath polarity and independently labelled cycles; physical temperature calibration/site/settling; muscle-specific EMG montage/filter/envelope; voice/pitch/noise and microphone effects. Keep airflow, calibrated volume, facial/startle EMG and spontaneous emotional inference as separate procedures. Each changed algorithm/default becomes a reviewed new version. The family matrix identifies starting literature; it has not closed these option reviews.

## A07 — Model-specific face, webcam and fNIRS interpretation

**Version and confound gaps.** The pinned facial detector uses model bytes and settings later than the [Py-Feat 2023 paper](https://pubmed.ncbi.nlm.nih.gov/38156250/). Tool citation alone does not validate those exact bytes, threshold, stride or target population. Current fNIRS conversion has no motion correction or short-channel regression (`scripts/workers/physiology.py:775`); [Yücel et al. (2021)](https://pmc.ncbi.nlm.nih.gov/articles/PMC7793571/) and [Tachtsidis & Scholkmann (2016)](https://pmc.ncbi.nlm.nih.gov/articles/PMC4791590/) make physiological confounds relevant to interpretation.

**Gate:** pin validated model/provider/configuration, labelled independent datasets, population/device/occlusion conditions and uncertainty. Keep facial outputs as model scores and webcam geometry distinct from measured gaze. fNIRS conversion agreement does not isolate neural activation; any motion/systemic correction or event baseline is separately versioned and validated. Consumer inference requires direct additional evidence.

## A08 — Instruments, AOIs and statistics need exact estimands

**Applicability gaps.** Generic questionnaire reverse/sum/mean/proration/conversion is not validation of supplied wording or translations. MaxDiff's current paired aggregate model is not participant-level HB. AOI labels do not establish geometric equivalence. Aggregating within person and applying a paired comparison is not repeated-measures correlation or a model of participant-and-stimulus generalization.

**Gate:** bind instrument/key/missingness rules and administration; MaxDiff likelihood/design connectivity; AOI construction and comparability; statistical estimand, sampling, repeated measures and multiplicity to appropriate sources in the matrix. Test each declared calculation against independent expectations and each unavailable branch. New scoring, uncertainty or statistical model requires a new named method. Keep explicit choices separate from implicit cognition and do not invent a multimodal psychological composite.

## A09 — Entry labels and report interpretation: a separate UI gate

**Confirmed inconsistent entry vocabulary:** `R/platform-guidance-views.R:4` and `R/platform-views.R:3`, `:139` offer “ECG / HRV”, although current signal/review views correctly say detected RR, NN unconfirmed. Prefer “ECG / detected intervals” for this route; a future qualified NN-HRV route should declare its separate support.

**Consistency risk to check, not a found numerical error:** `scr_count`/`scr_rate` retain response names, including `R/platform-eda-continuous-review-views.R:30`. That particular table is the constant/unavailable branch and visibly withholds response support. Ordinary direct review at `:217` already calls markers candidates and explicitly discloses relative prominence at `:224`. Ensure summaries and connected/offline exports preserve candidate status and the original denominator rather than upgrading the meaning of a saved key.

**Existing boundaries to preserve:** `R/platform-signal-views.R:69` rejects NN/stress interpretation; `R/platform-facial-expression-views.R:8`, `:60` separates classifier labels from feelings, attention and liking; gaze analysis retains candidate status and pupil confounds. These are not missing safeguards.

**Gate:** review entry, configuration, saved review, summary, comparison, HTML, JSON and ZIP vocabulary against one versioned claim record. A “computed” or “design checks passed” badge describes execution/structural checks, not academic approval. Include short-support, all-unavailable and historical-result examples. This audit inspected source strings only; it did not rerun those browser/export flows.

## A10 — Starters versus scientifically reviewed templates

The live `comparison`, `survey` and `blank` starters and saved-template reuse preserve structure, not an academic approval record. Comparison's 5000 ms exposure, 500 ms fixation, zero baseline, cyclic allocation and seven-point liking item need study-specific rationale. A source pointer, hash or successful design parser is not that rationale.

**Gate:** use the separate [study-design evidence](study-design/EVIDENCE.md) and [template preflight](study-design/TEMPLATE-PREFLIGHT.md) for design/order/carryover, timing, physiology, power, participant/stimulus sampling, preregistration, exclusions, missingness and multiplicity. Bind approved templates to exact options and evidence revisions; preserve amendments. No universal timing value, evidence badge or sample-size default is proposed here.

## Release sequence

1. Finish the code-derived option/default catalogue and link every review claim to the exact execution branch. Keep discovered/screened/full-text/applicability/qualified states distinct.
2. Review multiple suitable academic sources, independence, corrections and contrary evidence for each claim/context. Record unresolved support explicitly.
3. For computational changes, introduce a new recipe with independent numerical/reference and failure-state tests; separately collect physical, psychometric, construct and consumer validation.
4. Verify UI and exports communicate the same scoped claim and preserve historical numerical/identity/availability evidence.
5. Qualify only the named configuration, population, device and use case supported by those receipts. This packet does not complete that sequence.
