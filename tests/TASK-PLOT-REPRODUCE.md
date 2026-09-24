# Repeatable task preparation checks

The two component tests are installed under `tests/`. Run from the repository root using its configured R library:

```text
node tests/task-plot-ui.mjs
Rscript --vanilla tests/platform-task-plot-state.R
```

The Node test reads `www/task-plot-ui.js` relative to the test file. Optional arguments override the asset path and result JSON path. Its default result lives in a fresh temporary directory. It uses only Node built-ins and performs 19 DOM/animation-order assertions, including viewport bounds, navigation, exact tickets, focus handoff, deliberate scrolling and manual focus changes.

The R test takes an optional fresh output directory and otherwise creates a temporary one. It loads the actual application and creates a complete labelled synthetic 48-trial receiver journal. Fixture analysis runs directly to prepare one saved report; queued fixture jobs are cancelled before assertions. The 19 assertions cover actual source reads, status/token markup, source changes, navigation, real project revocation and unchanged prepared tables/jobs. Scoring is trapped after fixture setup. It requires the normal application R dependencies and `tests/fixtures/original-task-journal.R`, but no existing QA workspace, model installation, browser or external service.

These component tests do not measure real browser paint or scientific validity. The separate retained-store Chrome continuation records actual viewport geometry, keyboard focus, immutable exports and original-source preservation.
