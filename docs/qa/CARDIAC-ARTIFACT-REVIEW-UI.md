# Cardiac artifact review: researcher interface acceptance

20 September 2026. This interface extends the
[source exclusion contract](../methods/CARDIAC-ARTIFACT-REANALYSIS-CONTRACT.md).
It is a workflow and exact-source regression, not a new detector accuracy study,
NN classification, physiological validation or physical-device qualification.

## Interaction and source binding

From an original ECG/PPG waveform catalog, the researcher creates or reopens a
versioned artifact review for one exact source table/channel. Historical reports
without preserved input explain that a new original analysis is needed. Exclusion
reviews do not silently become masks on generic saved intervals.

Time entry is resolved against actual original source timestamps, preserving the
typed decimal strings and declared origin. The researcher sees the exact first
and last included source times, source-row bounds and count before saving.
Advanced source-row entry uses zero-based input rows and an exclusive endpoint;
it can include the final observed sample without inventing a timestamp after it.
Curated acquisition sequence numbers are explicitly separate from derived rows.

Native button/keyboard actions submit all current DOM values in one message.
This avoids a delayed Shiny numeric/text event changing what Preview or Save
meant. Editing immediately hides stale approval in the browser; the server also
compares the complete form, source and revision. Unsaved edits cannot queue a
calculation of different saved exclusions. Mutations use current-version checks;
a concurrent save requires explicit reopen. Earlier decisions remain immutable,
and restore creates a new current version.

A separate complete support preview is required after saving an exclusion. Its
input waveform includes original parent filter-edge samples and researcher
exclusions as separately labelled/color-coded fragments; no line joins across
their boundaries. Display points never enter analysis. Exact excluded samples,
first/last times and remaining independent runs are tabulated. Predicted support
does not predict a cardiac score or qualify signal quality.

The recalculation action freezes the saved review and its matching preview.
The separate report retains its version, source and support, with parent/new
navigation and complete JSON downloads. ECG remains detected RR and PPG detected
PRV; normal-to-normal and physiological qualification remain false.

Exact tables keep source numbers on one line inside a named, keyboard-focusable
horizontal scroll region. A visible instruction explains scrolling. Headings use
readable source-row/time terms and support states say "Ready to calculate" or
"Insufficient support". Missing restriction text is a dash. Complete source bounds,
counts and observed times are converted to exact strings before the shared table
renderer, avoiding its abbreviated generic numeric display.

## Executed component checks

- `tests/cardiac-review-ui.mjs`: 7 real Chromium form-adapter assertions passed.
  Immediate DOM edits preserve exact decimal text; native Enter submits once;
  edits hide stale approval; changed source/form identities are read at click;
  duplicate script installation does not duplicate actions.
- `tests/platform-cardiac-review-views.R`: 19 actual-store/Shiny/chart checks
  passed using a fresh copy of the retained input-waveform reference workspace.
  Includes actual domain creation, exact queued time text, one-sample changes,
  cancelled resolution retry with identical candidate/request, unsaved and stale
  version rejection, history/restore, removal, foreign source,
  leaving the report and distinct excluded/filter-edge plot fragments. Queued
  jobs were inspected/cancelled; this component suite runs no scientific worker.
- `tests/platform-cardiac-review-format.R`: 5 focused checks passed after the
  narrow-table correction. Seven-digit source bounds/counts and complete observed
  time strings survive the real shared table renderer; support wording is
  readable; the scroll region is keyboard-focusable and has visible guidance.

Final component evidence:
`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-cardiac-review-ui-model-03/results.json`.
Rendering caches its already validated source snapshot; each action and download
reopens the domain authority. Completed jobs are handled once and no longer
polled. This avoids repeatedly hashing the parent during ordinary rendering.

## Actual browser acceptance

`tests/researcher-cardiac-review.mjs` and its separate fixture copy retained public
reference bytes into an isolated workspace. The harness exercises actual time
resolution, changed-form invalidation, explicit save, complete preview, source-row
editing, history restore and result download/navigation through supervised jobs.
It scans desktop/390 px accessibility and action targets and records source hashes.
The final full browser run passed **17 assertions, including two desktop/390 px
scans, and four actual supervised jobs** (two time resolutions, one complete
support preview and one separate recalculation). Both scans have zero axe
violations, no page overflow, no undersized action targets and readable exact
table cells; ArrowRight moved the narrow table's scroll position. Desktop and
narrow screenshots were visually inspected, including the exact table and chart.
There were no browser exceptions. All owned browser/server/worker processes
closed after the successful run.

Final evidence:
`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-cardiac-review-browser-05/browser-1789890919009/results.json`.
The same directory retains source hashes, original parent before/after downloads,
version-2 exclusions, the complete support preview, the separate recalculated
report and restored version-4 exclusions. Immediate visible time text
`20.30001` to `22.70001` resolves rows `[7309,8173)`: 864 excluded samples from
108000 inputs, two remaining runs and 104256 predicted retained samples. The
saved report retains the exact version-2 review and explicit unqualified detected
RR semantics. Original report JSON compares equal before/after. A one-sample edit
creates version 3; restoring version 2 creates version 4 with the same spans.
UI/domain/worker/physiology/artifact-reader source hashes remained unchanged
throughout the acceptance.

Earlier retained runs exposed a slow repeated-hash rendering path,
narrow grid overflow and then visually unusable per-character table wrapping.
These were corrected before final acceptance. Automated zero-overflow and axe
results alone did not qualify the earlier narrow screenshot. The final harness
also checks non-wrapping cell height and actual ArrowRight scrolling; its saved
desktop and narrow images require visual inspection. A separate old-form
rejection in the harness was a correctly rejected action sent before the Cancel
editor replacement arrived; the harness now waits for the new form identity.
Run 04 was explicitly stopped before any new cardiac job while the root fixed
deterministic shared artifact-reader cleanup; it is not claimed as acceptance.

The retained baseline is `oka/work/brohn-cardiac-input-02`; it is copied read-only.
No reference labels are product-provided scientific approval, no detector
parameters are tuned, and the original source/report must remain unchanged.
