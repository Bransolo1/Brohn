# Prepared gaze interval kernel (draft)

`analyze_gaze_intervals(study, intervals)` implements duration arithmetic for already
prepared intervals. Its method ID is `aoi-valid-gaze-time-share/0.1.0-draft`; its
status is always `unqualified`. Hand-calculated synthetic checks establish draft
mathematical behavior, not a scientifically qualified analysis recipe.

Raw-data preprocessing is missing. This kernel does not import eye-tracker data,
map device timestamps, synchronize clocks, determine exposure eligibility, detect
fixations, remove artifacts, or verify calibration. The caller must prepare aligned,
eligible intervals and establish phase, validity, coordinates, and duration before
calling it. It cannot detect incorrect provenance or preprocessing from this table.

## Input contract

The study must pass the existing study, PNG asset, and AOI validators. Both stimulus
slots must have actual validated PNGs, and at least one rectangle AOI must be bound
to its PNG SHA-256. Condition A is the first study stimulus, B the second.

The data frame has exactly these columns; column and row order may vary:

| Column | Meaning |
| --- | --- |
| `participant_id`, `stimulus_id` | Nonempty character IDs; stimulus IDs must be in the study. Participant IDs match exactly, including any whitespace. |
| `start_ms`, `end_ms` | Finite numeric milliseconds on one prepared exposure timeline per participant/stimulus; `0 <= start_ms < end_ms`. |
| `x`, `y` | Numeric normalized image coordinates, origin at top left. Every `valid = TRUE` row requires finite values in `[0,1]`, including active rows. Invalid-row coordinates are ignored and may be missing or out of range. |
| `valid` | Logical TRUE/FALSE, without missing values; supplied by the caller. |
| `phase` | Exactly `passive_viewing` or `active_response`. |

Time intervals are `[start_ms, end_ms)`. Touching endpoints are allowed, but any
overlap within a participant/stimulus is rejected, including duplicate rows and
overlaps in invalid or active rows. Unsorted input is accepted. Gaps are never
filled or bridged. There is no exposure ID: repeated exposures must not be merged
into this single-exposure contract. No sample-duration inference is performed.

Only participants appearing in the input can be reported; a separate participant
roster is not accepted. A correctly typed empty table returns no participant rows
and a zero-complete-pair summary for each declared AOI label.

## Arithmetic and boundaries

Each interval contributes `end_ms - start_ms` milliseconds. For each participant,
stimulus, and AOI:

* `valid_duration_ms` is the sum of durations for valid passive-viewing intervals.
* `inside_duration_ms` is the sum of those durations whose supplied point is inside
  the rectangle. The caller has prepared each interval as represented by that point.
* `share_pct = 100 * inside_duration_ms / valid_duration_ms`. A zero denominator
  produces `NA`, including when the stimulus has no intervals; it never produces 0%.

An AOI with left/top `(x, y)` and right/bottom `(x + width, y + height)` includes
the left and top edges and excludes the right and bottom edges. An edge exactly at
the image boundary 1 includes the coordinate 1. Permitted floating-point overshoot
past 1 from the existing AOI validator is clamped to 1; other boundaries are compared
without tolerance. This gives adjacent rectangles a single owner at a shared edge.
Intentionally overlapping AOIs are evaluated independently, so their percentages
need not sum to 100. Named labels are metadata and never analysis instructions.

## Output

The return value is a list with fixed scalar fields `method_id`, `status`,
`time_unit = "ms"`, and `contrast = "B-A"`, followed by four data frames:

* `input_quality`: `participant_id`, `stimulus_id`, `condition`, `interval_count`,
  `recorded_duration_ms`, `valid_passive_interval_count`, `valid_passive_duration_ms`,
  `invalid_passive_interval_count`, `invalid_passive_duration_ms`,
  `active_interval_count`, `active_duration_ms`, `gap_duration_ms`.
  There is one row per observed participant and each study stimulus, including a
  zero-count row for a missing side. The three phase/validity categories are
  disjoint and cover the supplied rows. Active includes valid and invalid rows.
  Gaps cover only time between supplied intervals, not unknown leading/trailing time.
* `per_aoi`: `participant_id`, `stimulus_id`, `condition`, `aoi_id`, `aoi_label`,
  `valid_duration_ms`, `inside_duration_ms`, `share_pct`. There is one row for every
  observed participant and every declared AOI, even when its stimulus has no rows.
* `pairs`: `participant_id`, `aoi_label`, `share_pct_a`, `share_pct_b`, `difference_pp`,
  `included`, `reason_a`, `reason_b`, `exclusion_reason`. Pairing uses the same
  participant and exact, case-sensitive AOI label after trimming outer whitespace;
  it does not match AOI IDs or infer semantic equivalence from similar text.
  Labels from either stimulus are included. A valid complete pair gets
  `difference_pp = share_pct_b - share_pct_a`. An excluded pair has `NA` difference.
  Side-specific reasons are `missing_aoi`, `missing_intervals`, or
  `zero_valid_passive_duration`, in that priority order. A usable side retains its
  percentage even when the other side fails. Included sides have `NA` reasons;
  `exclusion_reason` joins failures as, for example, `B: missing_intervals`.
* `summary`: `aoi_label`, `complete_pair_count`, `excluded_pair_count`,
  `mean_difference_pp`. The mean gives equal weight to each included participant's
  B-minus-A percentage-point difference. It is `NA` when no complete pair exists.

Rows are deterministic: participants and trimmed labels use radix sorting, and
stimuli use the study's A/B order. Quality durations explain exclusion and missingness;
they do not diagnose device quality. The kernel supplies no p-value, confidence
interval, significance claim, perceptual interpretation, or causal conclusion.

## Verification scope

Run `tests/analysis.R` from the repository root in the existing R environment.
The checks use synthetic PNGs and independently hand-calculated prepared intervals.
They cover duration weighting, exclusions, gaps, rectangle boundaries, participant
pairing, missingness, input validation, image binding, and order invariance. They
provide no evidence of real-device acquisition or scientific qualification.
