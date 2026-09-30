# Sampled gaze and AOI options: bounded academic appraisal

Reviewed 1 October 2026 against source16, `SOURCE.json` SHA-256 `eda1eec7b58fbfd83d9461b093e9b99e19053469ef90bf9f9d932265724e5bcd`. Five option families are considered below. `CLAIM-FIELD-MATRIX.md` binds the findings to exact source fields; `SOURCES.md` records review depth and independence. This is an additive appraisal, not a scientific qualification, implementation change or exhaustive gaze inventory. No R, stores, services, scientific jobs or paper downloads were used.

The present `brohn-adjacent-ray-ivt/0.1.0-draft` already calls its events candidates and records `qualified=FALSE`. It requires chosen detector settings and physical geometry; it does not silently apply a vendor preset. Existing report text distinguishes fixation dwell from endpoint-assigned gaze time and preserves unavailable latency. These safeguards should remain. The main next step is clearer estimand-specific guidance and device/task qualification, rather than renaming the current output as validated fixations or attention.

## 1. Geometry, adjacent-ray velocity, duration and gaps

The detector computes angle between adjacent rays through a fixed planar stimulus, divides by actual elapsed time, and groups usable low/high-velocity intervals. Minimum durations accept or reject those runs; invalid endpoints, phase boundaries and excessive gaps interrupt support. It neither smooths nor interpolates nor merges neighboring candidates. Parser ranges are admissible inputs, not academic recommendations.

Salvucci–Goldberg supplies historical method ancestry only at the available abstract depth. Andersson and the newer Nir–Deouell comparison establish why detector, timing metric and dataset matter; the latter evaluates seven algorithms on static-image datasets from 500/300 Hz desktop systems. Its calibrated settings and rankings cannot qualify this implementation on a webcam, moving head or consumer display. Reporting guidance supports recording acquisition, uncertainty and processing choices, not selecting a universal threshold. [S1](https://doi.org/10.1145/355017.355028), [S2](https://link.springer.com/article/10.3758/s13428-016-0738-9), [S4](https://link.springer.com/article/10.3758/s13428-026-02983-5), [S5](https://link.springer.com/article/10.3758/s13428-023-02187-1).

A prospective named recipe could compare fixed and adaptive detectors using independent annotations, onset/offset error as well as event counts, and sensitivity to noise, gaps, sample rate and settings. That is new scientific work. Neither the existing contextual `saccades` comparison nor published reference rankings establish Brohn agreement.

## 2. AOI construction, geometry and measurement uncertainty

The current editor supports static image rectangles in normalized coordinates. AOI size, separation and expected gaze uncertainty deserve an explicit rationale. Hessels' noise-robust results concern face/sparse stimuli; Orquin–Ashby–Clarke's signal-detection account exposes the competing false-positive/false-negative costs. Neither means every AOI should be enlarged. The new AOI guidance supports deliberate assignment and geometry choices, with confirmatory versus exploratory construction made explicit. [S6](https://link.springer.com/article/10.3758/s13428-015-0676-y), [S7](https://onlinelibrary.wiley.com/doi/10.1002/bdm.1867), [S8](https://link.springer.com/article/10.3758/s13428-025-02937-3).

For packaging or advertisements, different area, location, content and visibility remain alternative explanations for differences. A matching label is not measurement equivalence. Preserve the saved geometry/revision and require a separate coordinate/visibility policy before extending this profile to moving scenes. A pilot sensitivity analysis can compare prespecified plausible boundaries; it must not silently choose the boundary producing the preferred result.

## 3. Gaze time, candidate dwell and first contact

`valid_share_percent` assigns an interval only when both valid endpoints are inside. Crossing intervals and valid off-stimulus time remain in its denominator. This operational rule does not prove that the unobserved trajectory stayed inside, and must not be described as an unconditional lower bound on true dwell.

`fixation_dwell_ms` instead sums full durations of candidates whose duration-weighted centroid lies inside. `ttff_ms` uses the start of the first such candidate, which can precede raw boundary entry. The literature's gaze-entry, visit and fixation-based quantities are not interchangeable. [S6](https://link.springer.com/article/10.3758/s13428-015-0676-y), [S8](https://link.springer.com/article/10.3758/s13428-025-02937-3).

The implementation sensibly distinguishes missing prior observation, unknown onset at the left boundary, absent exposure clock and complete-observation right censoring. These are explicit software policies, not a literature-qualified survival estimator. There is no fitted survival model here. A future statistical treatment needs its own event definition and censoring/missingness assumptions; do not replace unavailable cases with zero or average only observed latencies without an explicit estimand.

## 4. Overlap, assignment and transitions

Overlaps are independent memberships, so shares and candidate durations can count the same support more than once across AOIs. The saved transition joins only adjacent fixation candidates with distinct single AOI assignments and usable intervening support. An outside/overlap candidate blocks the link; it is not skipped. A qualifying saccade is not required. These are reproducible assignment choices, not a normalized transition model or observed continuous scanpath. Geometry and assignment sources support making such choices explicit but do not validate this exact rule. [S6](https://link.springer.com/article/10.3758/s13428-015-0676-y), [S7](https://onlinelibrary.wiley.com/doi/10.1002/bdm.1867), [S8](https://link.springer.com/article/10.3758/s13428-025-02937-3).

Retain the existing candidate-order and saved-link explanation. If visits, transition probabilities or exclusive ownership are later needed, introduce a separately named definition with an unassigned state and declared denominator; do not reinterpret historical links.

## 5. Pupil support, external blinks and baseline

Brohn preserves pupil units and external blink provenance, rejects nonpositive/invalid pupil samples, and computes a duration-weighted trapezoid mean. An optional pre-exposure baseline is subtracted only with chosen duration/coverage support. It performs no blink-edge padding, artifact-speed filtering, interpolation or gaze-position correction.

Mathôt's baseline evaluation supports caution about contaminated baselines; subtraction is not a complete cleaning pipeline. Kret–Sjak-Shie's pipeline includes additional artifact operations absent here. Hayes–Petrov independently demonstrates gaze-position measurement distortion on artificial eyes and a particular instrument. These sources motivate checks, not automatic adoption of their example settings or correction formulas. [S9](https://link.springer.com/article/10.3758/s13428-017-1007-2), [S10](https://link.springer.com/article/10.3758/s13428-018-1075-y), [S11](https://pmc.ncbi.nlm.nih.gov/articles/PMC4637269/).

Current baseline support is therefore a chosen availability rule, not a universally sufficient period. Luminance, gaze geometry, unit definition and informative missingness remain interpretation constraints. Externally labelled blink duration is observed sample support, not independently detected full eyelid closure. Dunn's reporting guideline explicitly excludes incidental pupil/blink measurements; it cannot fill this gap.

## Priority follow-up

`PROPOSED-CHANGES.md` separates low-impact wording from scientific departures. No current registry entry is changed or promoted. Launch guidance can explain the saved definitions and unknowns now; numerical recommendations, automatic masks, new detectors, visit models and consumer constructs need distinct validation and versioned recipes. Independent teams are present in this reading, but reused datasets and overlapping authors prevent treating the bibliography as eleven independent confirmations.
