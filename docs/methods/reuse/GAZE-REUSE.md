# Gaze reuse and analysis recipes

Reviewed 2026-09-08. Brohn should reuse established detectors and analysis packages behind explicit R contracts. Package execution, published method evidence, independent annotation agreement, and device qualification are separate gates. The existing `aoi-valid-gaze-time-share/0.1.0-draft` remains unqualified prepared-interval arithmetic; it is not a fixation detector.

## First executable reference

The completed no-account reference uses **saccades 0.2-1** (R prints `0.2.1`), upstream commit `bb55d203a09eb6b942058d08f4df697bdb440486`, and **zoom 2.0.6**, isolated in `work/r-library-methods`. From the repository root:

```powershell
& '../../work/native-r/bin/Rscript.exe' --vanilla scripts/benchmarks/gaze-reference.R
# Add --install to reproduce installation into the separate methods library.
```

[The benchmark](../../../scripts/benchmarks/gaze-reference.R) runs the bundled `samples` recording through `detect.fixations(lambda=6, smooth.coordinates=FALSE, smooth.saccades=TRUE)`. It records package/helper hashes and aggregate results, keeping participant samples outside the repository. The [pinned upstream source](https://github.com/tmalsburg/saccades/tree/bb55d203a09eb6b942058d08f4df697bdb440486/saccades) is GPL-2; its required plotting dependency zoom is GPL-3-or-later. Keep attribution and distribution review explicit.

[Observed results](gaze-reference-results.json): R 4.6.1; 88,511 samples, ten trials; **20 checks pass**. Whole-record detection gives 1,531 fixation labels; separate trial calls give 1,477. Observed timestamp steps span 3–5 ms. README describes 240 Hz whereas packaged help says approximately 250 Hz; neither substitutes for recorded timestamps. Source `(0,0)` sentinels identify 2,063 track-loss samples. They remain in this upstream reproduction, so its event totals are not cleaned valid-gaze results.

The difference between whole-record and trial-isolated output exposes shared filtering/threshold behavior. The benchmark converts factor trial IDs to text because unused levels and factor-code aggregation otherwise break isolation. It tests time translation, grouping, nonoverlap, source bounds, duration arithmetic, and rejection of missing coordinates/duplicate or reversed timestamps. Zero-duration events are recorded, not silently imported into Brohn. This is a runnable reference and wrapper check, **not independent fixation ground truth**.

## Reusable components

| Candidate | Exact useful scope and dependency implications |
|---|---|
| **saccades**, pinned above | Engbert–Kliegl velocity-relative threshold detection; experimental blink/artifact heuristics. Assumes nominally uniform sampling and excludes smooth pursuit. CRAN 0.1-1 is older and differs materially; never substitute it silently. [Source](https://raw.githubusercontent.com/tmalsburg/saccades/master/saccades/R/saccade_recognition.R). |
| **eyetools 0.10.0**, candidate | `combine_eyes`, `interpolate`, `fixation_dispersion`, `fixation_VTI`, `saccade_VTI`, `AOI_time`, `AOI_seq`, `plot_heatmap`. GPL-3; dependencies include ggplot2/ggforce, zoo, hdf5r and magick. HDF5/ImageMagick increase installation requirements. [Manifest](https://raw.githubusercontent.com/tombeesley/eyetools/master/DESCRIPTION). |
| **gazer 0.2.4**, candidate | EyeLink ASC/Titta-oriented import, AOI mapping, pupil cleaning, blink interpolation, baselines and aggregation. GPL-3; tidyverse components, data.table, signal, zoo, lme4 and upstream saccades. Pin the transitive detector too. [Manifest](https://raw.githubusercontent.com/dmirman/gazer/master/DESCRIPTION), [method paper](https://pmc.ncbi.nlm.nih.gov/articles/PMC7544668/). |
| **eyetrackingR 0.2.2**, candidate | Sample-based track-loss cleaning, AOI proportions, time windows/growth curves, bootstrap clusters and onset-contingent switching. MIT; dplyr/tidyr/purrr, ggplot2, broom/broom.mixed, zoo. It assumes equally spaced samples and does not read vendor files. [Manifest](https://raw.githubusercontent.com/samhforbes/eyetrackingR/master/DESCRIPTION), [preparation](https://samhforbes.github.io/eyetrackingR/articles/preparing_your_data_vignette.html). |

Only saccades/zoom were installed and exercised here. `eyetools::fixation_VTI` defaults include 100 degrees/s, 150 ms minimum fixation, 20 ms minimum saccade and 100 px dispersion. Angular conversion needs screen dimensions, viewing distance and sampling configuration. Its current saccade code allocates an all-pairs distance matrix: benchmark bounded trials before adoption. This is a distinct implementation, not Tobii equivalence. [Detector](https://tombeesley.github.io/eyetools/reference/fixation_VTI.html), [conversion source](https://raw.githubusercontent.com/tombeesley/eyetools/master/R/saccade_VTI.R).

**Tobii I-VT** is a configurable processing chain. A reproducible historical reference is Pro Lab 1.162's Fixation preset: interpolation disabled; binocular average; three-sample moving median; 20 ms velocity window; 30 degrees/s threshold; merge within 75 ms/0.5 degrees; reject fixations shorter than 60 ms. The Attention preset uses 100 degrees/s. Freeze software version and every setting when obtaining comparison exports; defaults are not universal study recommendations. [Official manual, appendix B2.9](https://s3.amazonaws.com/lynx.tobii/TobiiProLab_1_162_UserManual.pdf).

## Brohn recipe catalog

The [sampled-gaze analysis contract](../RAW-GAZE-ANALYSIS.md) now implements a
transparent fixed adjacent-ray I-VT candidate recipe, static AOI metrics,
conservative first-fixation observation status, external blink masks and
explicit pupil baseline arithmetic. Its independent fixtures and contextual
upstream comparison pass; it remains unqualified for named devices or
annotation agreement. The broader catalog below also includes future work
such as visits, heatmaps and prespecified survival models:

| Recipe | Required decisions and reporting |
|---|---|
| Fixations/saccades | Preserve event onset/end, duration, position and detector identity. Report count and duration distributions; event rate denominator is eligible observed time. Angular amplitude/velocity requires physical geometry; pixel displacement is a different unit. |
| Dwell/visits | Separate summed fixation duration, raw valid-gaze duration, and visit-span duration, which may include intervening saccades. Declare entry/exit, gap and re-entry rules. `AOI_seq` collapses consecutive same-AOI fixations and assumes nonoverlapping AOIs. [Reference](https://tombeesley.github.io/eyetools/reference/AOI_seq.html). |
| First fixation | TTFF starts at actual stimulus/AOI visibility onset. Record whether fixation was already underway. No observed fixation is not zero latency: with continuous usable observation, right-censor at exposure end; track-loss intervals can require interval-censoring or exclusion. Report viewed fraction and eligible counts alongside latency. `survival::Surv` supports censoring; its use here requires a prespecified analysis. [R documentation](https://stat.ethz.ch/R-manual/R-devel/library/survival/html/Surv.html). |
| AOI shares | Retain Brohn's valid passive-time denominator, outside-AOI valid gaze, and missing zero-denominator result. `AOI_time(as_prop=TRUE)` divides by supplied trial time, so it is not an automatic replacement. `eyetrackingR` must explicitly set `treat_non_aoi_looks_as_missing=FALSE` for comparable outside-AOI treatment. [AOI_time](https://tombeesley.github.io/eyetools/reference/AOI_time.html), [denominator option](https://samhforbes.github.io/eyetrackingR/reference/make_eyetrackingr_data.html). |
| Transitions/heatmaps | Collapse repeated same-AOI events; specify outside-AOI and overlap ownership; never bridge unknown gaps. Transition probabilities divide by observed departures from each origin. Freeze heatmap bandwidth, count/duration weighting, image mapping and participant weighting. Heatmaps remain descriptive. |
| Blink/pupil | Separate blink events from generic track loss. Store pupil units/per-eye validity; mark artifacts before bounded interpolation. Prespecify response/baseline windows, minimum usable baseline, and subtractive correction; report baseline exclusions and original/corrected traces. Control luminance, viewing geometry and task order. [Pupil preprocessing](https://pmc.ncbi.nlm.nih.gov/articles/PMC6538573/), [baseline evidence](https://pmc.ncbi.nlm.nih.gov/articles/PMC5809553/). |

## Import and acceptance gates

First integration should be an offline sampled-gaze adapter/reference job, followed by one named vendor export adapter with its own fixture. Preserve participant/session/exposure IDs, raw timestamp strings/units and clock mapping; split trials, invalid runs and exposure phases before detection. Never merge repeated exposures into the current prepared schema. Disable gap filling initially; record later interpolation masks and limits.

Keep display pixels/normalized display coordinates distinct from normalized **image** coordinates. Tobii's active-display origin is top left; map through actual image placement, letterboxing, scale and scrolling. Preserve per-eye validity before combination and off-image status before analysis. Use the existing image-hash binding and half-open AOI edges. [Tobii coordinates](https://developer.tobiipro.com/commonconcepts/coordinatesystems.html), [per-eye gaze](https://developer.tobiipro.com/commonconcepts/gaze.html).

Next external benchmark: [Lund2013](https://github.com/richardandersson/EyeMovementDetectorEvaluation) supplies MATLAB data labelled by two annotators under repository GPL-3; use an external fixture cache and verify file-specific terms. Compare static-image trials separately from pursuit-containing video; report per-class sample agreement, event F1, onset/offset errors and human disagreement. [HFC](https://github.com/dcnieho/humanFixationClassification) offers reference event-agreement algorithms under CC-BY-4.0, but its recordings/coder settings are CC-BY-NC-SA-4.0. Do not treat public availability as unrestricted commercial fixture permission. Numerical acceptance requires exact wrapper/direct agreement under identical segmentation/settings; scientific thresholds must be justified against independent annotations and the intended study before qualification.

**Commercial option:** RealEye provides API v2.6 for study management and v1 for results, requiring an API-enabled licence and `X-AUTH-TOKEN`. Its public CSV examples can inform schema inspection; redistribution permission is not established. Exported fixation settings include velocity in **%/s**, unlike Tobii degrees/s. Webcam predictions need their own precision/latency and AOI-size evaluation; do not derive microsaccades or calibrated pupil diameter from gaze-coordinate exports. [API](https://support.realeye.io/realeye-api), [CSV](https://support.realeye.io/data-export-to-csv?hsLang=en), [filter units](https://support.realeye.io/downloading-csv-files-with-custom-set-minimum-fixation-duration). No account or device integration was attempted.
