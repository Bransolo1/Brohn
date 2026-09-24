# Saved-report spacing and recoverable download errors

24 September 2026. Actual rendered report inspection found blank gaps of120 and
336 pixels between visible cards. Empty Shiny outputs each reserved a grid gap.
The report now spaces populated sections, retains live output bindings and uses
ordinary block wrappers so newly populated controls receive the same spacing.
The inactive exact-values progress output returns `NULL` instead of an empty
nested panel. The change is confined to researcher report layout.

Repeated failed downloads update one persistent, keyboard-dismissible message.
The page also retains its actionable error. This prevents a stack of duplicate
notifications obscuring the workspace. Enter and Space dismiss the message and
return focus to the workspace.

`tests/researcher-report-layout.mjs` passes **five connected checks and four
clean accessibility/reflow scans**, with **zero new jobs** and all original
report/video/WAV hashes unchanged. It inspects actual visible card bounds,
opens previously empty audio controls, navigates away and reopens them, changes
to390-pixel layout and issues three genuinely refused old download requests.
No fabricated results or new scientific processing are involved.

The final receipt is
`../../work/test-runs/brohn-derived-access-20260924-01/layout-1790228613775/results.json`.
The separate pre-change diagnostic is `layout-1790228152933/results.json` in
the same fixture. Maximum report spacing is now32 pixels on desktop, including
the heading's existing margin, and20 pixels on mobile. The Home introduction's
intentional52-pixel gap is outside this report-only change. All four scans have
zero axe violations and no horizontal page overflow. Desktop opened-report and
mobile error screenshots were inspected after execution.

Retained intermediate attempts exposed an overly short five-second cold-control
wait, an assertion incorrectly applying report spacing to Home, and an inactive
nested exact-values wrapper still consuming space. A later rendered inspection
also confirmed that Shiny output wrappers needed explicit block layout for
consistent spacing. The final test checks both minimum and maximum separation;
removing large gaps while making cards touch would not pass.

Run against a new isolated copied fixture prepared by
`tests/fixtures/researcher-derived-access.R`, as described in
[the download-access acceptance](DERIVED-AUDIO-DOWNLOAD-ACCESS.md). The harness
starts/stops only its owned service on3935 and stores screenshots, visible
layout measurements, source hashes and receipts outside Git. Its optional
`--diagnostic` mode captures the unqualified baseline without reporting a pass.

## Clear coverage and current error appearance

The subsequent current-source receipt is
`../../work/test-runs/brohn-derived-access-20260924-01/layout-1790229107103/results.json`:
**six connected checks and four clean scans**, with zero new jobs. It adds the
actual plain-language coverage card, expandable original fields and matching
downloaded HTML. Error notifications now use Brohn's opaque dark surface and a
44-pixel keyboard-operable close control; the browser measures that target.
The final desktop report and mobile error screenshots were inspected.

The new `R/platform-report-coverage.R` presents saved physiological/audio support
with its own denominators: channel segments, channel samples, acoustic frame
rows, event/channel windows, supported SCR windows and retained neural epochs.
It never turns these into participant counts, substitutes zero for a missing
count, infers absent physiological activity from zero event rows or recalculates
results. All original fields remain in an expandable complete table. Sparse
historical reports explain when recognizable summary counts are absent.

`tests/platform-report-coverage.R` passes24 independent saved-metadata checks in
`brohn-report-coverage-20260924-02/results.json`, including inconsistent, missing,
nonfinite, boolean and text counts, original-report preservation and escaped
future fields. The existing22 report-comprehension and10 offline-HTML checks
also pass. The actual browser receipt covers the audio report; the other
metadata cases are direct component evidence, not additional browser journeys.
An initial test-label formatter incorrectly tried to serialize deliberate
nonfinite invalid inputs; replacing that label with its case name fixed the
test without weakening the production checks.
