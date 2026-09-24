# Linked measurements and recorded events

PC12 software slice, 24 September 2026. **Passed: 11 connected browser assertion groups, five clean accessibility/reflow scans, 13 full-source worker checks and 13 independent source-authority checks.** All owned researcher/worker processes stopped cleanly. This is a qualified software slice, not whole-platform, device, synchronization or scientific signoff.

## Researcher route

Create a consumer comparison study with explicit control/test conditions. Import the original multistream recording into the Data library, associate the saved study, declare its origin and preserve original clocks. On that recording, **Review measurements with recorded events** lets the researcher select two to four signal/event channels, explain the shared source-clock declaration, set an exact relative-time window and cursor, and apply the review.

The supervised `linked_review` job scans the complete pinned canonical sources and retained boundary evidence. The resulting linked source timeline, actual observations around the cursor, recorded event context, exact 100-row table pages and complete window CSV share one saved selection. Saved reviews reopen from the same original recording without recomputation. A full JSON manifest retains source revisions, hashes, clock, origin, selection and worker identity. Editing the visible selection hides the old display and revokes its CSV URL until the current selection is applied or a saved review is reopened.

## Source and clock contract

- All selected channels must belong to the same preserved import of one original recording. Matching clock names across unrelated recordings are insufficient.
- The complete clock descriptor must match, with supported exact decimal timestamps and declared monotonic, device or Unix clock. Explicit participant and session identity must agree across the selected sources.
- The investigator reviews the source declaration; this **does not establish physical synchronization accuracy**. Close timestamps and row order are never evidence of alignment.
- The first selected track supplies its first observed, unreconstructed native timestamp as the reference anchor. Relative seconds use decimal arithmetic. The window is start-inclusive/end-exclusive. No corrections, interpolation, resampling or fitted clock map are applied.
- Source clock resets, reversals, duplicate signal timestamps, changes of clock or ambiguous correction epochs refuse the overlay and CSV with an actionable explanation. There is no invented epoch correspondence.
- Nominal gaps and missing values break plotted lines. Rows without an observed placeable timestamp are counted explicitly and receive no invented time. Each signal retains its own source unit and vertical scale.
- Display envelopes use first/last/minimum/maximum points per time bin within each continuous source/value run. Complete CSV and exact table values retain original timestamp strings and floating JSON tokens. Exceeding a display bound suppresses that entire track plot rather than silently truncating it.
- The recorded event list makes stimulus context readable without requiring SVG hover. Markers remain recorded events; no condition, exposure or causal relation is inferred from their labels.

## Bounds and publication

Two to four tracks; one-day maximum window; supported display coordinates within one billion relative seconds; 100 exact rows per page; 200 rendered markers; at most 2,000 display bins across continuous runs per track; 64 MiB complete window CSV. The existing supervised explorer resource profile applies (1 GiB, 300 seconds). Original object bytes remain immutable. CSV publication and download use existing native read seals, identity validation and source guards. A stale URL returns 404 instead of a previous selection's data.

The reader uses complete preserved JSONL and boundary artifacts, never source previews. Display limits are independent of complete source support. Tables name their origins and source rows; counts are observations rather than participant denominators.

## Independent original fixture

`tests/fixtures/researcher-linked-review.py` generates five clearly labelled synthetic streams, with one original timestamp anchor above binary64 exact integer range: `9007199254741013 ns`. Conductance has one missing value and an explicit sampling gap; voltage has independently specified `100 + 2*i` values; markers include a candidate onset exactly `1.250000001 s` after the anchor and literal HTML-like text. Two additional streams deliberately declare an incompatible clock and a same-clock reset.

The independent oracle is 35 conductance + 40 voltage + 3 event rows in `[0,4)`, with cursor `1.25` bracketed by actual voltage values `124` and `126`. `[0,8)` contains 158 rows, exceeding both the import preview and the first exact UI page. `[1.250000001,3.25)` includes the candidate onset and excludes the end-boundary event. `[20,21)` is empty. No signal here is a natural participant response or a qualified sensor measurement.

## Retained execution

- `make/work/test-runs/brohn-linked-worker-20260924-01/results.json`: 13 passing full-source worker cases through the actual importer, with two independently modified canonical edge/adversarial copies for missing timestamp and different-person refusal. Source hashes and fixture path are retained.
- Browser attempt `brohn-linked-browser-20260924-01/browser-1790219223482/failure.json` exposed an existing Windows long-path import failure before linked review. Root repaired importer artifact promotion to retain its already-created short unique filename; full SHA/kind identity stays in the manifest. The long-path regression and complete importer suite passed separately.
- Browser attempt `brohn-linked-browser-20260924-02/browser-1790219619313/failure.json` passed long-workspace import and stopped at an overly strict nested-label selector. The harness now uses the checkbox role and accessible name.
- Browser attempt `brohn-linked-browser-20260924-03/browser-1790219781363/failure.json` found the test pressing Enter before remote study options arrived. The harness now waits for and clicks the actual option, verifying a bound value. These latter failures did not expose a linked calculation result or qualify the final route.

The final fresh run used the same intended long workspace layout after the importer repair:

| Receipt | Result | SHA-256 |
| --- | --- | --- |
| `make/work/test-runs/brohn-linked-browser-20260924-04/browser-1790219870440/results.json` | 11 browser groups; five zero-violation axe scans and zero page overflow | `fa54d21e8a8d40271a86dced27a727a28b72d8ae1009a6650068be641ab70885` |
| `make/work/test-runs/brohn-linked-browser-20260924-04/authority-results.json` | 13 read-only source authority checks | `b9dc914646e83ae16d0d11f82a7401e96ceeae30a8c63ea1a2780a7eda7c34a6` |
| `make/work/test-runs/brohn-linked-worker-20260924-01/results.json` | 13 worker checks | `dddf705681930b1811243c4a567aed91101d55f24c1658eb29387246816c3a1e` |

The final browser run created exactly **10 real jobs**: one successful intake, one successful preserved import, seven successful linked reviews and one deliberately cancelled linked review. Retry created a separate replacement, and historical reopening plus actual researcher/worker restart created no additional jobs. The prior failed attempts are separate workspaces and are not mixed into these counts.

The first exact window CSV contains all 78 selected observations and hashes to `fc9e222df23bb203064e9bd8544b545523b8e75f1d79de8867b79a8eab8e21c7`; the wider 158-row CSV hashes to `458525dadd98cc22823e740bab4a8f556f55f5586f10d1da4ee37146c2d6ffb8`. Original recording SHA-256 is `900cf602cb2e2dfc11fab549064d3cc7bcc07c928da97610e14efbb9b1c98707`. The final receipt records ten implementation hashes captured before the browser launched and matched at completion, including the repaired importer. The original recording, all five preserved stream records and import record remained unchanged. Exact manifest and CSV downloads survived a new app/worker process pair.

Desktop and 390px compact timeline images, the empty-window timeline and restarted timeline were visually inspected: axes and units are readable, the common cursor is visible, missing-value and sampling-gap breaks remain separate, empty tracks show no observations, and the reopened display agrees with the original. Narrow form and reset-selection captures were also inspected for wrapping. Five retained axe reports contain no violations. This is automated accessibility plus visual inspection of these views, not a human assistive-technology study or comprehensive platform accessibility certification.

The read-only authority checks independently reject swapped sample/evidence hashes, changed clock/origin/project, duplicate selection, absent clock declaration review/rationale, unrelated dataset reopening and substituted support/window values. They confirm the complete dataset, stream, review and job catalog hashes are unchanged by those checks.

## Scope boundary

This slice does not provide hardware timing qualification, measured synchronization error, a calibrated alignment-map editor, epoch matching across reset streams, cross-recording alignment, or a psychological interpretation of channels. Unsupported clocks/reset cases remain explicit refusals. Existing processed-signal interval annotations and reuse remain separate: no coordinate mapping from these raw source seconds to a processed report is invented. Capacity limits and all modalities are not exhaustively qualified by this one original fixture.

Run the browser harness on an isolated workspace with the configured R library, Python and native publication guard; the harness uses port 3901 and stops only its owned services. `tests/platform-linked-review.R` then performs read-only catalog/authority checks against that completed fixture. No real participant data, production studies or hosted endpoints are used.

From the repository root, with the configured R library and `LC_ALL=C`, the authority invocation used for this receipt is:

```text
Rscript --vanilla tests/platform-linked-review.R ../../work/test-runs/brohn-linked-browser-20260924-04 ../../work/test-runs/brohn-linked-browser-20260924-04/authority-results.json
```

This script requires a completed browser fixture and an output receipt path; it is intentionally not a fixture-free default QA entry.
