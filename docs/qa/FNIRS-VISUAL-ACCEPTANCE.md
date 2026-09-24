# Saved fNIRS visualization and exact export acceptance

24 September 2026. **Connected saved-output and corrected visual acceptance
passed for the two software-phantom cases below.** This scope
checks the existing researcher plot and exact-value routes against saved
production output; it adds no physiological calculation or device claim.

## Source boundary

The source is `oka/work/brohn-fnirs-saved-01`: two original SNIRF software
phantoms, processed by actual supervised analysis jobs after the independent
scalar conversion checks in `tests/reference/fnirs_phantom.py`.
`tests/reference/fnirs_saved_review.R` passed **18 checks and eight actual jobs**:
two analyses, two complete catalogs, two saved previews and two exact CSVs.
The cases preserve unequal wavelength-specific pathlength factors `[6, 5]` and
a ten-sample nonpositive-intensity gap that produces separate retained segments.
These are original software phantoms, not human recordings or physical
instrument measurements.

## Browser boundary

`tests/fixtures/researcher-fnirs.R` copies the closed saved workspace into an
isolated test workspace. `tests/researcher-fnirs.mjs` drives the actual researcher
app and supervised job manager. Six table/measure selections cover saved HbO,
HbR and both optical-density wavelength channels, including the post-gap HbO/HbR
segments. Every plotted point is compared with its declared original row;
every exported CSV coordinate, value and typed row is compared with the complete
original artifact. The oracle reads the native artifact directly and does not
derive expected values from a preview or from the exported CSV itself.

The acceptance also requires exact report/artifact binding, original sample
indices and clock, units, wavelength/PPF/segment metadata, downloadable SVG and
source JSON, complete CSV byte receipts, reopening, unchanged original reports,
desktop and 390-pixel visual inspection, keyboard-accessible exact values, and
no silent joining across separate source segments. Production source hashes and
all worker outcomes are retained with the browser receipts below.

## Limits

This route establishes saved-output visualization and export
fidelity for these two cases. It does not establish neural interpretation,
motion-removal efficacy, hardware synchronization, optode placement quality or
human usability. The complete selection means the complete chosen saved table;
removed input spans remain documented by source support and segment boundaries,
and are not invented as haemoglobin values.

## Executed continuation and visual correction

The first resumed researcher journey completed **33 assertions and five clean
axe/reflow scans**. Its six selections compare every plotted point and every
complete CSV row against the original typed artifact: 700 rows each for HbO,
HbR and both wavelength optical-density measures in the unequal-pathlength
case, plus 390 rows each for post-gap HbO/HbR. **All 3,580 selected rows match.**
Original sample indices, clock, units, PPF `[6, 5]`, wavelengths `[760, 850]`,
source segment metadata and both saved report hashes remain unchanged.

That run executed **17 new successful read-only jobs**: six previews, six exact
pages and five complete exports. The first complete export reused its already
saved result. The eight original saved-review jobs remain separate and are not
counted as newly executed. No original scientific analysis was rerun.

Visual inspection caught a defect that the initial bounds-only scan missed:
the compact optical-density figure's `-0.000732` tick overlapped the rotated
`dimensionless` unit. An independent DOM geometry receipt confirms the two
intersecting text boxes. The original figure and receipt remain retained.
`brohn_signal_svg()` now reserves a gutter from the displayed tick lengths and
uses bounded scientific notation for unusually long tick labels. It changes
presentation only; ranges, original values, fragment boundaries and exact
downloads are preserved.

All six unchanged saved views have since been rendered at actual **320px and
920px widths: 12 figures**. Every text box fits the figure and no axis/tick text
boxes intersect. The corrected compact optical-density and post-gap figures
were also visually inspected at their actual size. The researcher browser
harness now asserts text nonintersection, in addition to clipping, accessibility
and reflow. Its final rerun reuses the same isolated saved workspace and records
new jobs relative to the start of that invocation.

Retained evidence outside the repository:

- `make/work/test-runs/brohn-fnirs-browser-resume-20260924-01/browser-1790214475399/results.json`
  contains the first complete data-fidelity journey, job/source fingerprints and
  unchanged report hashes.
- That directory also contains the original `compact-label-collision.json`,
  compact SVG and screenshots. The initial clean axe/bounds checks do not
  supersede this subsequently discovered visual defect.
- `corrected-figures/actual-size/geometry-results.json` contains the 12 corrected
  retained-view renders and actual-size screenshots.

The final connected researcher rerun completed **33 assertions and five clean
scans**, now including actual SVG text-intersection checks. All six complete
CSV selections and their plotted points still match the 3,580 original rows;
SVG/source downloads, keyboard scrolling/row inspection and report reopening
also pass. The final desktop, compact optical-density, exact-value and post-gap
screenshots were inspected. Both original report hashes remain unchanged and
there are no browser exceptions or production-source changes during the run.

This renderer rerun created **zero new jobs**: it reused the 25 successful saved
jobs (eight original plus the 17 new read-only jobs above). The successful
receipt is
`make/work/test-runs/brohn-fnirs-browser-resume-20260924-01/browser-1790215716928/results.json`,
SHA-256 `9ad5e4fbc75faa569dd6cb1891786510bd5151aae376ace59f70e5d8aa2c6954`.
Source-code fingerprints, per-selection CSV hashes, report identities and job
counts are included there. Port 3882 and the fixture's owned services closed;
the copied workspace has no queued/running jobs. Original reference stores were
not modified. This is output fidelity and scoped workflow/visual evidence,
not physical instrument, neural interpretation or human usability qualification.
