# Original-source authority for derived reports and downloads

24 September 2026. General saved-report and dataset screens now enforce the
same original-video authority as the processed-signal and audio readers. A
report remains immutable when its source becomes unavailable; it cannot supply
an old cached download after the parent changes project ownership.

`brohn_report_for_review()` resolves the exact report and its complete derived
audio lineage. Report HTML, observations, JSON/provenance and complete artifacts
use this resolver before download. The original derived-WAV route also checks
its parent before copying bytes. A two-second view check clears an affected
report/dataset with an actionable message, while each HTTP download checks
immediately. The timer does not repeatedly rebuild unchanged input controls.

The generic plot/interval checks are recorded separately in
[Derived audio signal authorization](DERIVED-AUDIO-SIGNAL-AUTHORIZATION.md).
They cover another21 signal and14 interval checks, including commit rollback,
exact values, interval reuse and immediate SVG/JSON/CSV refusal. They do not
replace the actual HTTP checks below.

## Actual browser evidence

`tests/researcher-derived-access.mjs` passes **8 checks and2 clean desktop/mobile
accessibility and reflow scans**, on an isolated copy of the accepted synthetic
video/extraction workspace. It starts only its own local researcher service.
It makes **zero new jobs** and preserves every original report, original video
and derived WAV hash.

The final receipt is outside Git at
`../../work/test-runs/brohn-derived-access-20260924-01/browser-1790227559185/results.json`.
The receipt records exact implementation hashes and HTTP response hashes:

- Existing HTML, observations CSV, report JSON and complete processed artifact
  URLs return their original bytes while authorized.
- A temporary parent-ownership change makes every already-issued URL fail.
  The open report clears and explains the source-access issue.
- Restoring the exact parent authority reopens identical exports without any
  rescoring or replacement report.
- The complete derived WAV has its original SHA-256 before the fault. Its old
  URL fails after the same parent change, and the open dataset also clears.
- Notification dismissal works from the keyboard and returns focus to the
  workspace. No page errors or horizontal page overflow were recorded.

The fault changes only the copied test catalog and is restored in `finally`.
No credentials, real participant records or original research stores enter the
fixture. These checks exercise local source ownership, not a public-hosted
capacity or physical-device claim.

## Corrections and reproduction

The first retained attempt expected one exact status label after several failed
downloads. The page had correctly cleared, but the latest download correctly
changed its status to Download needs attention. The assertion now checks the
actual home view and actionable source error. A later actual axe scan found an
unnamed notification region. Researcher notifications now have a named region,
keyboard-operable close controls and visible focus; the final receipt above
includes the corrected error-state scan and keyboard action.

Use the R/native configuration in [Running checks](RUNNING-CHECKS.md), the
repository Playwright/axe dependencies and installed Chrome. Create a new
external directory named `brohn-derived-access-*`. Run the fixture helper's
`setup` mode with that directory and an accepted `brohn-audio-extract-browser-*`
directory, then run the browser script with the new directory. Port3935 must be
free. The helper verifies terminal source jobs before copying the fixture and
the browser stops only its own service.

Subsequent notification stacking and report-spacing work has a separate
[source-pinned visual receipt](REPORT-LAYOUT-AND-NOTIFICATIONS.md); the receipt
above is not silently relabelled as evidence for later source changes.
