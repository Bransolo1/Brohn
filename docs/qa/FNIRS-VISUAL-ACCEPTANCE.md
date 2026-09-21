# Saved fNIRS visualization and exact export acceptance

20 September 2026. **Connected browser qualification is pending.** This scope
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
all worker outcomes are retained with the browser receipt. Final executed counts
and evidence locations will be added when the connected journey closes.

## Limits

Passing this route would establish saved-output visualization and export
fidelity for these two cases. It would not establish neural interpretation,
motion-removal efficacy, hardware synchronization, optode placement quality or
human usability. The complete selection means the complete chosen saved table;
removed input spans remain documented by source support and segment boundaries,
and are not invented as haemoglobin values.
