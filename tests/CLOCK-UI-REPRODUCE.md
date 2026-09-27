# Portable clock feedback checks

The installed `tests/clock-review-ui.mjs` and `tests/clock-plot-feedback.mjs` use only standard Node.js modules; no `npm install`, browser, server or research workspace is needed.

From the repository root:

```sh
node tests/clock-review-ui.mjs
node tests/clock-plot-feedback.mjs
```

Each script reads `../www/clock-review-ui.js` relative to its own file. Any assertion failure exits nonzero. Success prints the check count. The first script has 24 checks for focus ownership, explicit preparation, stale completion and ready-heading top alignment. The second has 12 checks for passive plot preparation, two-frame acknowledgement and no focus/scroll change.

To inspect an alternative asset and retain full JSON receipts, pass its path followed by the output file path. The output directory must already exist:

```sh
node tests/clock-review-ui.mjs www/clock-review-ui.js C:/Brohn-QA/review-client-results.json
node tests/clock-plot-feedback.mjs www/clock-review-ui.js C:/Brohn-QA/plot-feedback-results.json
```

These are deterministic simulated-DOM/animation tests of the **whole** client script, including both initializers. They are useful regression checks, but do not establish real browser paint, keyboard geometry, accessibility, HTTP, Shiny behavior, native resource sealing or worker correctness. The connected application and scientific qualification require their separate evidence.

Qualified working asset SHA-256: `ecff3bed1377f1eee0f45e327da032568b1cc4804eac0f1c2bb3a4f20087bf55` (checkout-11). The [source-phase manifest](../docs/qa/CLOCK-SOURCE-PHASES.json) records the qualified source identities and separate evidence phases.
