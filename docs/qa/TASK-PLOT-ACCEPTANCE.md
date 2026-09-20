# Complete task plots — 20 September 2026

Brohn now connects saved task reports to trial chronology, latency distribution,
and descriptive person-level cohort plots. These are presentation adapters; no
scientific scorer, worker recipe, protocol compiler or participant timing code
was changed.

## Source and interpretation contract

- Imported IAT, Brief IAT, keyboard AAT, simple RT and choice RT use every
  canonical administration audit position and its original response fields.
  Expected count must match the saved score. Missing source rows, observed
  timeout, interruption, practice/unscored positions, wrong first responses,
  out-of-window values and timing-definition uncertainty stay distinct.
- Native reports enumerate complete frozen run/task declarations, then open
  only the selected original complete protocol and journal. Receiver replay,
  saved design/event hashes, allocation identity, exact study/project ownership,
  and retained protocol-byte identity when available must agree. A native source
  that is no longer available fails visibly. Neither bounded questionnaire
  previews nor reconstructed summary scores supply trial data; unrelated large
  questionnaire artifacts are not hydrated to plot a task.
- First-response and final-correct latency are explicit separate choices. Raw
  values, original imported decimal strings, and scoring audit remain separate.
  Imported dispositions are retained; native diagnostic dispositions use the
  registered profile rules and are labelled as diagnostics. Saved scores are
  never recalculated by the explorer.
- Every selected finite value enters the chronology and 20 equal-width
  distribution bins. Bins use exact right-closed boundaries, including the
  minimum in the first bin, without histogram boundary fuzz. Unavailable values
  never become zero. Scope filters are explicit; the complete source remains in
  the typed JSON export. Table pages of 50 rows do not bound the plotted data.
- Cohort dots use the complete saved `per_person` rows for one exact metric.
  Repeat-session weighting and metric-specific available people, sessions and
  administrations remain those of the saved cohort. Missing person values and
  unavailable linkage remain unavailable. No pooled-trial estimate, confidence
  interval, significance test or generic implicit composite is added.
- SVG exports include visible selected-latency labels and marker keys. CSV
  contains every selected row, exact typed `exact_record_json`, and source/report
  identities; JSON retains all plot-source rows and provenance. Spreadsheet-safe
  display prefixes do not change the exact typed record. Downloads recheck the
  current source and replay the original native journal where applicable.

## Connected implementation

`R/platform-task-plots.R` contains the complete-source readers and pure plot data
adapters. `R/platform-task-plot-views.R` contains native labelled controls,
responsive figures, numeric alternatives and bound downloads. The report hook
is `brohn_task_plot_explorer_ui(record)`; the server installer is
`brohn_install_task_plots(input, output, session, store, state, attempt,
prepare_download)`. App/load registration and the report hook are connected.

Opening verifies the retained full result envelope. Subsequent control/table
actions use small current authority/catalog checks and original immutable
object-byte verification, retaining the already verified model. Report changes
and source/project authority loss clear the view. Unrelated workspace refresh
does not reset selected evidence or the numerical page. Leaving the report
clears its source state. Complete native source loading is lazy per selected
administration.

## Executed evidence

Runtime: restored local Windows R, library `r-library-brohn-restore`, native Chrome
at desktop 1440×1080 and narrow 390×844. Fixtures are original synthetic sources;
direct saved test report publication is not a supervised-worker claim.

- `tests/platform-task-plots.R`: **42** focused source/model/Shiny assertions.
  Includes all five task profiles; first 150 ms versus final-correct 500 ms;
  exact bin-edge arithmetic; rejection of a truncated 50-row audit; one correct
  response plus 39 omissions; derived missing position; unknown timing; cohort
  partial SD support; repeat weighting; native exact-journal rejection;
  preview-independent catalog; complete exports; page/state preservation;
  stale control and authority-revocation cleanup.
- `tests/researcher-task-plots.mjs`: **11** actual researcher journey assertions
  and **5** zero-violation axe/reflow/44-pixel-control/caption scans. The journey
  opens real saved reports through Studies → Results, inspects the full
  180-trial IAT, changes latency with the keyboard, pages numerical values,
  downloads actual SVG/CSV/JSON, filters scored positions, opens native receiver
  evidence, inspects incomplete/unknown imports, and switches cohort metrics.
- Figure screenshots are captured separately at the actual responsive size,
  in addition to page screenshots. This avoids axe/focus scroll restoration
  hiding the plotted area. Final chronology, omission, cohort-support and
  distribution figures were visually inspected at desktop and narrow sizes;
  marker labels, positive latency/SD axes and unavailable strips are legible.

Final executed browser evidence:
`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-task-plots-20260920-01/browser-evidence-1789879624000`.
It contains `results.json`, the five axe reports, actual SVG/CSV/JSON downloads,
page and individual figure screenshots, and the researcher service log. The
service stopped cleanly with no R or browser exceptions.

Reproduce from the repository root:

```powershell
$env:R_LIBS_USER=(Resolve-Path ../../work/r-library-brohn-restore).Path
$env:LC_ALL='C'
& ../../work/native-r/bin/Rscript.exe --vanilla tests/platform-task-plots.R
node tests/researcher-task-plots.mjs C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-task-plots-new
```

The source adapter enforces 20,000 expected positions per administration and
5,000 person rows per metric. Those are enforced bounds, not a maximum-capacity
performance qualification. No vendor hardware, physical response timing, human
usability study or psychological construct validation is claimed by these
software checks. Native incomplete sessions remain unavailable through the
existing complete-journal export gate; incomplete imported administrations can
be inspected with their explicitly missing expected positions.
