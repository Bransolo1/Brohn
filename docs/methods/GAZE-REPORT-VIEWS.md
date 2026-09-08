# Gaze visual reports

Implemented in `R/platform-gaze-report-views.R`. This module reads immutable
analysis output and its pinned design. It never re-runs a detector, changes an
AOI, fills missing values, calculates a new scientific score or combines people.

## Available views

One selector chooses a participant/session/stimulus/exposure combination.
Composite identities are hashed without delimiter ambiguity, and selector values
include the report body hash. A control left over from another report cannot
select or silently display that other report's data.

- **Raw sampled gaze:** numbered, equal-size saved fixation-candidate centroids
  over the exact pinned raster image and AOI rectangles. Numbers represent saved
  temporal order; size does not represent duration. Candidate coordinates,
  start/end/duration, source rows, samples, AOI membership and boundary flags have
  a numerical alternative. Unavailable or inconsistent candidate order disables
  point plotting; it is not sorted or repaired by the UI.
- **Direct AOI transitions:** a dashed link appears only between consecutive
  candidate records with an exact persisted transition event and no conflicting
  invalid-gaze, sample-gap or phase-boundary mask. Off-stimulus or omitted
  candidates cannot be skipped to join two distant points. These links represent
  saved transitions, not a reconstructed sampled eye trajectory.
- **Prepared intervals:** the pinned stimulus and region definitions, plus
  saved AOI time measures. Their analysis output does not retain fixation
  coordinates, so no fixation map or heatmap is synthesized from AOI summaries.
- **AOI time:** fixed 0–100% share bars and a numerical table retain the saved
  valid-time denominator, inside time, crossing time where available, candidate
  dwell/count/duration, TTFF and censoring status. NULL means unavailable; zero
  valid time does not become a zero-percent bar. Overlapping AOIs remain separate
  and their shares may sum above 100%.

The view repeats source origin, phase declaration, per-exposure source/passive/
invalid sample counts where saved, valid interval duration, unsupported time and
coverage status. It distinguishes candidate dwell from endpoint-assigned gaze
time. A prepared-interval observation span is not presented as an independently
observed complete stimulus exposure.

## Geometry and assets

The [raw-gaze contract](RAW-GAZE-ANALYSIS.md) defines `stimulus_normalized` relative
to the actual rendered stimulus rectangle. The viewer requires that mapping in
both analysis parameters and provenance. It does not infer a display-to-stimulus
transform, crop, contain offset or head-motion correction. Raw diagrams retain
the declared rendered width/height ratio; prepared diagrams use the pinned image
aspect ratio and do not claim to reconstruct participant screen placement.

Image bytes come only from `provenance.design.stimuli[*].asset` in the verified
object store. The embedded design must match `provenance.design_hash`. PNG/JPEG
signatures, size, registered object hash and media type are checked before data
URI embedding. Current study revisions, URL fields and arbitrary local paths
are never used as fallback images. Unsupported, missing or corrupt assets leave
a labelled normalized frame with numerical results retained.

Off-stimulus coordinates remain unchanged in the candidate table and valid-time
support; they are not clamped to an image edge. AOI rectangles preserve the
saved normalized coordinates. Region boundaries use the analysis recipe's
half-open membership convention; drawing a border does not change membership.

## Bounds and accessibility

Interactive output renders one selected exposure. Static HTML defaults to the
first 12 exposures, explicitly states shown/total counts and points to the
workspace selector and full JSON for the remainder. Defaults show at most 200
candidate records per exposure; the saved AOI measures still use complete
support. Limits may be explicitly set to 100 exposures and 1,000 points.

At most 100,000 observations and 100,000 feature records, grouped into 10,000
exposures, are accepted by this adapter. Inline media is capped at 5 MiB per
image and 16 MiB cumulative image bytes per rendered call. Exceeding an image
budget produces an explicit missing-image explanation, never a different image.

SVGs have image roles, titles and descriptions, readable high-contrast markers,
and responsive sizing. Numerical tables have column headers and labelled,
keyboard-focusable horizontal scroll regions. Text is escaped by htmltools;
static exports require no scripts, network assets or filesystem references.

## Integration

Source `platform-gaze-report-views.R` after `platform-data-views.R` and the
existing core/store/library/gaze modules.

1. Add `brohn_gaze_explorer_ui(r$body)` to the saved-report detail view.
2. Install `brohn_install_gaze_report_server(input, output, session, store, state)`
   once in `brohn_server`. It uses existing `state$page == 'report'` and
   `state$report_id` and produces `output$gaze_report_view`.
3. For downloaded HTML, make `brohn_export_report_html(report, path, store=NULL)`
   accept the workspace store and include `brohn_gaze_report_ui(store, report)`
   before the ordinary numerical report. Pass `store` from its download handler.
   Existing two-argument callers remain supported; without a store the diagram
   explains why its pinned image is unavailable.

Pure helper APIs are `brohn_gaze_report_model(report)`,
`brohn_gaze_report_points(group, maximum=200L)` and
`brohn_gaze_report_links(group, displayed)`. The static entry point is
`brohn_gaze_report_ui(store, report, exposure_key=NULL,
maximum_exposures=12L, maximum_points=200L)`.

## Evidence

`tests/platform-gaze-report-views.R` passes 30 assertions using original synthetic
gaze passed through the actual analysis function, stored and reloaded from the
immutable catalog. It checks image bytes and dimensions, later study edits,
corrupt-image rejection, identities, masks, off-stimulus support, missing values,
prepared-interval limits, exact candidate ordering, bounded previews, escaped
text, self-contained offline HTML and real Shiny selection/stale-control behavior.

These checks qualify this display implementation against its saved-data
contract. They do not establish physiological/device validity of the candidate
detector. The renderer retains the method limitations already recorded by the
[analysis recipe](RAW-GAZE-ANALYSIS.md).
