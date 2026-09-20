# Exact saved cardiac detections on the cleaned waveform

20 September 2026. This adds a connected ECG/PPG review display. It does not
change detection, correct events, classify beats, qualify normal-to-normal
intervals or validate physical equipment. The [annotated ECG review](ECG-DETECTOR-REFERENCE-REVIEW.md)
documents the known detector limitation that motivated this work.

## Source and display contract

New ECG/PPG cleaned-waveform views use `processed-signal-view/1.1.0` with an
optional `brohn-cardiac-marker-overlay/1.0`. Both complete event and waveform
artifacts are pinned to the same immutable report and processing provenance.
The reader verifies their bytes, exact recording/channel/segment identities,
clock metadata, source support and recipe. Each detection joins an exact
retained source sample and its saved time. No nearest-time join or interpolation
is permitted. Private source paths are absent from the saved view.

All selected markers are retained independently of the line's extrema-based
display reduction. Hollow circles show their actual saved cleaned values;
markers are not taken from a decimated line. Event-table/row, waveform-table,
source-sample and exact time identities are preserved, along with the original
previous interval and plausibility flag. Source and event-row indices are
zero-based. A previous interval may begin outside the selected window.

`available` means a complete selected overlay of at most 2,000 detections.
`empty` means no selected saved detections, not absent heartbeats or acceptable
signal quality. `too_many_markers` counts every selected saved event record and
draws none, with a concrete narrower-range route. Its alignment is explicitly
`not_checked_display_limit_exceeded`: those event positions have not been
joined to individual waveform samples. A smaller window is required to perform
that check. It never quietly displays the first 2,000 or claims the counted
positions were verified. Complete original event output remains downloadable.

The chart is explicitly a **saved cleaned waveform**. It does not promise an
original-waveform toggle. The existing source recording download remains
available. Historical saved views without an overlay remain without inferred
markers. The view cannot grant reviewed, NN, physiological-quality or
device-qualified status. ECG labels retain detected R peaks/RR; PPG retains
detected systolic pulse peaks/PRV.

## Researcher interaction and exports

The normal chart remains visually primary. Below it, a short summary gives
the marker count, hollow-circle meaning and unreviewed status. A closed native
disclosure exposes every selected marker's numeric coordinates and interval
evidence, with null and false states kept distinct. Number strings retain
17-digit precision instead of the generic table's six-significant-digit
format. Table identities and source/segment provenance remain in the JSON.

The existing **Download chart** action exports the same complete selected
overlay in a standalone accessible SVG. **Download view + provenance** returns
the immutable saved view including both artifact identities and the exact
marker list. The selected time range uses the existing controls; changing it
creates a derived display without rescoring the scientific report. Existing
interval-annotation and cardiac-spectrum controls are preserved.

## Executed evidence

| Layer | Result | Scope |
|---|---|---|
| `tests/workers/cardiac_markers.py` | 19 checks pass | Independent source-sample/value oracles; marker preservation despite line reduction; ECG/PPG identity; null/false intervals; inclusive range; exact limit and excess all-or-none output; source/time/provenance refusal. Above-limit sample/time bounds reject, while in-bounds mismatches or excluded samples remain explicitly unchecked and reject when narrowed. |
| Existing `tests/workers/signal_preview.py` | 24 checks pass | Existing complete source, extrema, fragment and view contracts on the new reader. |
| `tests/platform-cardiac-markers.R` | 37 checks pass; six supervised jobs | Final bound correction: exact queue binding, actual complete-reader joins, immutable reports, exported views, refusal of substituted/reviewed/partial/duplicate data, narrow range and store reopen. Actual over-limit reader output is accepted only as unchecked; count cannot exceed complete event rows. |
| Existing `tests/platform-signal.R` | 32 checks pass | Actual worker, provenance, extrema, support, publication fences, Shiny actions/downloads and restart. |
| `tests/reference/ecg_marker_review.R` | Five checks pass; three actual jobs | Original published MIT-BIH108 CSV import, unchanged actual production detector, complete artifacts, exact 10–18 s display and store reopen. This is display fidelity, not detection accuracy. |
| `tests/platform-cardiac-marker-views.R` | 25 checks pass | Actual saved synthetic ECG/PPG and recorded108 views; independent expected SVG coordinates; markers missing from a one-bin line still drawn; precise table/null/false states; accessible standalone descriptions; legacy absence; actual 2,502-event and empty-event outputs; explicit unchecked over-limit alignment; malformed display refusal. |
| `tests/researcher-cardiac-markers.mjs` full mode | 26 checks pass; eight clear scans | Independent fixture renders and isolated copied public-reference workspace through actual app/worker. All 273 events, invalid-range recovery, exact seven-event window, SVG/JSON downloads, empty range, unchanged original report and fresh-session reopen. Full-page accessibility, reflow and actual waveform label checks. |
| Same browser suite, `--render-only` after bound correction | 15 checks pass; five clear scans | Final saved renderer across ECG, PPG, published108, 2,502-event limit and empty-event cases. Includes the corrected explicit unchecked over-limit wording/contract. This is not a second complete app journey. |

Backend evidence:

- Final backend: `C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-cardiac-markers-02/acceptance.json` (original30-check run retained in `brohn-cardiac-markers-01`).
- `C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-cardiac-reference-02/acceptance.json`
- Final UI renderer: `C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-cardiac-marker-ui-03/renderer-results.json`
- Actual full app: `C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-cardiac-marker-ui-02/browser-1789881842167/results.json`
- Final saved-renderer checks: `C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-cardiac-marker-ui-03/browser-1789882125135/results.json`

The first full browser run is retained under `brohn-cardiac-marker-ui-01`.
Its full app assertions and axe/reflow checks passed, but the per-chart image
selector targeted a navigation icon on full app pages. The harness selector
was corrected to responsive signal containers and the entire app run repeated
in `ui-02`. Its `actual-reference-desktop-chart.png` and
`actual-reference-390-chart.png` are the representative actual waveform images;
the narrow image was visually inspected. All owned browser, fixture server and
worker handles closed cleanly.

After that complete app run, a peer audit found that over-limit output skipped
the individual sample join but still described exact alignment. The backend
and renderer now retain the event count while explicitly marking positions
unchecked. Final `ui-03` checks cover that correction. The backend also checks
every saved event against source sample and observed time bounds before selecting
the display state; the final37-check backend run includes six fresh supervised
jobs. Available/empty exact joins and the scientific detector remain unchanged.

The public-reference pipeline preserves all 273 original detector events,
including the seven in 10–18 s. Its source remains `imported` with published
reference provenance. Its known poor annotated agreement is unchanged. An
initial reference-test attempt used a Unicode title under the C locale;
the fixture title was made ASCII and rerun. That harness correction changed
no scientific method or source data.

The actual narrow recorded-waveform screenshot was visually inspected: all
seven circles are visible at their saved values, units and axes fit, and the
negative QRS landmarks remain visible. No reference annotations are overlaid
in the product, and viewing these circles does not mark them as reviewed.

Correction/editing, a source-bound original-waveform view and a qualified
replacement detector remain separate work. The display provides evidence for
review while preserving the known limitations.
