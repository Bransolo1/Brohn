# Sampled gaze analysis contract

Implemented 2026-09-08 in `R/platform-gaze.R`. The exported functions are
`brohn_validate_raw_gaze_mapping(metadata, columns = NULL)` and
`brohn_raw_gaze_analysis(data, metadata, design)`. The module uses the frozen
study design, preserves source row references, and returns the same analysis
envelope as the other Brohn analysis modules. The caller retains the original
source object and its mapping; the detector never rewrites the recording.

The executable method is **brohn-adjacent-ray-ivt/0.1.0-draft**. It is a fixed
angular velocity recipe with transparent boundaries, not an implementation of
the Tobii I-VT processing chain. Outputs remain fixation and saccade
**candidates**, with `qualified = FALSE`. Device/annotation agreement has not
been established. The [reuse review](reuse/GAZE-REUSE.md) separates published
methods, runnable upstream references and the remaining qualification work.

## Input and mapping

One source has 2 to 2,000,000 rows. Each row needs a participant, session,
exposure, known stimulus, nonnegative relative timestamp, gaze position and
explicit validity. Time must strictly increase in the source order within
each participant/session/exposure; duplicate or reversed timestamps fail.
Repeated presentations require distinct exposure IDs. Baseline and other
phase rows retain the same exposure/stimulus identifiers, so an intervening
phase cannot disappear and accidentally connect two gaze segments.

| Metadata field | Required interpretation |
|---|---|
| `gaze_representation` | Exactly `samples`. |
| `unit` | Exactly `stimulus_normalized`, relative to the actual rendered stimulus rectangle. Display-normalized coordinates need a separate verified placement transform. |
| `time_unit` | `ms` or `s`; relative clocks below 1e12 ms. Analysis outputs use ms. |
| `time_column`, `x_column`, `y_column`, `valid_column` | Source fields. Validity is explicit true/false or 1/0. A declared-valid sample with missing coordinates fails; invalid coordinates are never zero-filled. |
| `participant_column`, `session_column`, `stimulus_column`, `exposure_column` | Required identifiers. Each exposure identifies exactly one stimulus in the pinned design. |
| `condition_column` | Optional; populated values must agree with the stimulus condition. |
| `phase_column`, `phase_value` | Map the passive viewing phase. Alternatively declare `source_phase = 'passive_viewing_only'`. |
| `exposure_start_column`, `exposure_end_column` | Optional paired columns for actual observed exposure bounds, in the same time unit. Each must be constant within an exposure. Scheduled durations are not sufficient. Required for TTFF/censoring eligibility. |
| `geometry` | Numeric `width_mm`, `height_mm`, `distance_mm`, `center_x_mm`, `center_y_mm`. These describe the rendered stimulus size, eye-to-plane distance and eye-relative center position. All are explicitly supplied. |
| `geometry_source` | How the physical geometry was measured or established. |
| `parameters` | Numeric `velocity_threshold_deg_s`, `min_fixation_ms`, `min_saccade_ms`, `max_gap_ms`, plus descriptive `threshold_source`. No scientific preset is silently chosen. |
| `left_valid_column`, `right_valid_column` | Optional explicit per-eye availability flags, reported separately from combined-gaze validity. |
| `blink_column`, `blink_source` | Optional external blink labels and their provenance. Generic track loss never creates a blink. |
| `pupil_column`, `pupil_unit`, `pupil_source` | Optional measured pupil signal; units are `mm`, `mm2`, `pixels`, `pixels2` or `device_units`. Diameter and area units remain distinct. |
| `pupil_valid_column` | Optional explicit signal validity. Pupil integration also requires positive finite values and excludes external blink labels. |
| `pupil_baseline` | Required with pupil: `list(mode = 'none')` or the explicit subtractive recipe below. |

The physical geometry must apply to every exposure in a job. This static
planar model does not infer geometry from image dimensions, device names or
webcam coordinates, and does not account for untracked head motion. Different
image placements, variable distances and smooth pursuit need another declared
profile or separate jobs. Normalized positions outside 0..1 are retained as
off-stimulus gaze, provided their source validity is true.

## Detection and missingness

For position `(x,y)`, the eye-origin ray is
`((x - .5) * width_mm + center_x_mm, (.5 - y) * height_mm + center_y_mm, distance_mm)`.
The angle between adjacent rays is `atan2(norm(cross(a,b)), dot(a,b))` in
degrees. Angular velocity divides that angle by the actual adjacent sample
interval in seconds.

An interval is eligible only when both endpoints are in the passive phase,
both are valid, neither is externally labelled a blink, and the interval is
at most the declared maximum gap. The detector never sorts, fills, smooths,
merges or extends the final sample. Invalid samples and phase boundaries split
segments. Geometry and eligible coordinates must produce finite velocities.

Contiguous low-velocity intervals (`velocity <= threshold`) become fixation
candidates once their summed duration reaches `min_fixation_ms`. High-velocity
intervals use `min_saccade_ms`. Shorter runs remain explicit
`short_unclassified_segment` records. Position is a duration-weighted mean of
the interval midpoint positions. Each candidate includes source row bounds,
observed start/end/duration, sample count, peak angular velocity, angular path,
AOI membership and a boundary-truncation flag. Candidate counts describe the
detector output; they do not certify the true number of eye movements.

## AOIs, comparisons and first fixation

Static AOIs use the frozen normalized rectangles and half-open edges: left/top
included, right/bottom excluded. Raw gaze time belongs to an AOI only where
both eligible interval endpoints are inside it. Boundary-crossing intervals
remain unassigned and their duration is reported. The share denominator
includes all valid observed gaze time, including off-stimulus gaze. No usable
gaze yields a missing share and missing fixation dwell, rather than zero.

Fixation dwell sums candidate durations whose weighted centroids belong to
the AOI. This differs from raw endpoint-consistent gaze time. Overlapping AOIs
are evaluated independently; their shares can sum above 100%. Transitions
require consecutive candidates with unique, distinct AOI membership and no
unknown interval between them. Outside-AOI and overlapping candidates are
not silently skipped to create a transition. The shared paired-comparison
engine compares AOI labels between conditions, keeps participant-level N, and
uses separate `valid_gaze_share` and `fixation_dwell` outcomes.

TTFF always reports its observation status:

| `ttff_status` | Numeric result and meaning |
|---|---|
| `observed_fixation_candidate` | `ttff_ms` is the first candidate onset minus actual exposure onset, with uninterrupted usable preceding observation. |
| `left_boundary_candidate_onset_unknown` | No numeric TTFF: a candidate already starts at the left boundary. Its observed latency can still be zero in the separately named descriptive field. |
| `right_censored_no_fixation_candidate` | No numeric TTFF; `censor_time_ms` is the full exposure duration, only when the entire declared interval was observed validly. |
| `unavailable_no_exposure_clock` | Actual exposure bounds were not mapped. Recorded sample span is not substituted for them. |
| `unavailable_missing_prior_observation` | A candidate was observed, but missing prior observation prevents first-fixation interpretation. |
| `unavailable_incomplete_observation` | No candidate and incomplete usable exposure coverage; absence is not classified as a complete never-fixated trial. |

`first_observed_candidate_from_recorded_start_ms` and
`first_observed_candidate_from_exposure_ms` describe observed contact separately
from TTFF. `valid_coverage`, `complete_observation`, observed span and valid ms
remain visible. A last sample before the actual offset cannot establish full
coverage, because there is no inferred tail. These records support a later
prespecified survival analysis; this module does not fit one.

## Pupil and external blink labels

Pupil means use trapezoid integration over adjacent positive, finite, valid
samples wholly inside their window. Unknown samples, blinks, unsupported gaps
and phase boundaries contribute no duration. No interpolation is performed at
window edges. Pupil validity is its own signal: unavailable gaze does not
silently imply unavailable pupil or vice versa.

Subtractive correction is explicitly configured:

```r
pupil_baseline = list(
  mode = "subtractive",
  phase_value = "baseline",
  start_column = "baseline_start",
  end_column = "baseline_end",
  minimum_coverage = 0.90,
  minimum_duration_ms = 500,
  source = "Replace with the study's prespecified pupil baseline recipe"
)
```

The values above illustrate the shape, not a universal recommended threshold.
Baseline bounds must precede the exposure. The baseline phase must differ from
passive viewing. Both coverage and minimum valid duration must pass before
`baseline_corrected_mean = mean_pupil - baseline_mean` is reported. An
insufficient baseline leaves the raw mean available and the corrected result
missing, with `excluded_insufficient_valid_baseline`. Mode `none` reports no
corrected result. Luminance, measurement geometry and task order remain
interpretation constraints; there is no universal attention, engagement or
emotion score.

External blink labels produce observed first/last labelled sample times and
duration, sample count and onset/offset-unobserved flags. Label runs split at
unsupported gaps. This preserves the source detector's claim; it is not a
second independently validated blink detector. Unavailable left/right eyes
produce masks and counts without being relabelled as blinks.

## Result and validation

The returned envelope is `list(kind, title, features, observations, contrasts,
quality, parameters, limitations)`. `kind` is `gaze`. `features` records have
`record_type` values `fixation_candidate`, `saccade_candidate`,
`short_unclassified_segment`, `quality_mask`, `aoi_transition`,
`source_labelled_blink`, `pupil_summary` or `exposure_summary`. `observations`
contains one AOI/exposure metric record. Every scientific feature retains
participant/session/exposure/stimulus/condition identifiers. Output is bounded
at 100,000 feature records; larger sources must be split into recording jobs.

Run from the repository root with the Brohn R library configured:

```powershell
$env:R_LIBS_USER = '../../work/r-library-brohn'
& '../../work/native-r/bin/Rscript.exe' --vanilla tests/platform-gaze.R
```

The test suite independently checks geometry, two 200 ms fixation candidates
separated by a 10 ms angular movement, AOI denominators, censoring, lost samples,
phase boundaries, time units and translation, off-stimulus positions,
unavailable eyes, explicit blink labels, and a 6 mm minus 4 mm pupil fixture.
Boundary tests reject invented partial baseline intervals and missing-as-zero
outcomes. The contextual upstream comparison pins saccades 0.2.1 and its helper
hash to the [existing reference](reuse/gaze-reference-results.json). Both
detectors identify the stationary clusters in a synthetic recording, but their
different algorithms are not asserted numerically equivalent.

These checks establish implementation arithmetic and missingness behavior.
Independent annotated recordings, device-specific precision/latency evidence,
prespecified detector thresholds and named vendor adapter fixtures remain the
qualification gates documented in the reuse review. The runtime module does
not import or require saccades; the isolated methods library is used only by
the contextual comparison test.
