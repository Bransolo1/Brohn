# Clock overview controller: independent review

27 September 2026. External qualification only; application edits belong to the integrating root agent.

## Result

No unresolved controller defect was found in the qualified checkout-10 state transitions. Forty-three checks pass across `state-03/results.json` and `retry-fences-01/results.json`. The broad run retains one **harness fixture-selection error**, described below; its missing scenario was repaired and passed in the focused run. This is not a claim that the broad receipt is entirely green.

The original window becomes ready before the separate overview starts. Its four downloads remain usable during overview preparation, background waiting, cancellation and failure. A retry creates new preparation feedback before current-source reads, history lookup or a queue operation; its matching painted-status acknowledgement performs those operations. A queued or running attempt is reattached, while a cancelled attempt receives an explicit new job. Current access is checked again after feedback, at completion and when serving the evidence download.

## Exact evidence and retained failures

| Receipt | Outcome | Scope |
| --- | --- | --- |
| `state-01/` | Setup stopped before scenarios | Harness used the map/preview record reader for a window. Corrected to the window reader. |
| `state-02/results.json` | 24 of 25 checks passed; one application failure | An atomic failed-job error detail surfaced an internal R `$`-operator error. The controller remained alive and original exports remained usable. Root fixed defensive error extraction. |
| `state-03/results.json` | All 27 reached checks passed; six scenarios completed; seventh stopped | Checkout-10 retest confirms retry feedback ordering and the error fix. An additional test incorrectly assumed another saved window used the current map revision. No such fixture existed. |
| `retry-fences-01/results.json` | All 16 checks / four scenarios passed | Uses the actual saved map-version catalog to reach a different genuine window. Covers the previously blocked scenario, access revoked after retry feedback, queued/running reattachment, duplicate acknowledgements and defensive error variants. |
| `js-01-results.json` | All 12 simulated client checks passed | Passive overview acknowledgement on the full checkout-10 script; no focus or scroll change. Final presentation-only script checks are recorded separately below. |

The root agent independently observed a separate checkout-09 browser problem: retry performed expensive current-source work before changing the old failure display. The root fixed it by publishing a new preparation ticket first. This review reproduces the operation ordering through spies and state assertions; it does not claim to have measured the root's browser delay.

`state-03/harness-as-run.R` preserves the test containing the fixture-selection mistake. `retry-fences-01/harness-as-run.R` preserves the successful focused continuation. The corrected reusable generator selects a map head and then its genuine historical version through the installed catalog callbacks.

## What was exercised

- No plot history lookup or queue operation before its own matching acknowledgement; stale tickets are refused.
- Main-window readiness and all four original capabilities during plot preparation, waiting, cancellation, missing receipts, malformed errors and successful completion.
- Genuine saved exact-window overview reuse; a result for another window is refused.
- Cancellation followed by retry: immediate new preparation ticket, stale retry acknowledgement refusal, explicit renewed job, successful result.
- Bounds edited before acknowledgement or during background work; returning to the original bounds preserves original exports.
- Window replacement, navigation and close reject late acknowledgements/completions. Plot resources release before the borrowed window resource.
- Actual source ownership changed in the **copied** SQLite store: plot download refuses access, and revocation between retry feedback and acknowledgement prevents both history lookup and new queue work. Ownership is restored in `finally`.
- Retry reattaches both queued and running jobs without duplicating an attempt, including repeated acknowledgements.
- Missing, scalar, null, NA, vector and blank error details use the fallback; legitimate error text is capped at 1,000 characters.
- Passive client acknowledgement requires two animation frames and a rendered visible-document status. Removal, replacement, hiding and cancellation invalidate pending acknowledgement. Retry receives its own ticket. No passive focus movement or scrolling occurs.

## Limits and genuine components

The state harness uses `shiny::testServer`, not a live HTTP application. It copies the terminal `clock-plot-next-20260925/adapter-02/workspace` first. Its saved import selections, three-row event pages, previews, map versions, windows, plot records and original artifacts are genuine. Saved-record and current-source readers execute against those copies. Capability checks directly invoke the installed `registerDataObj` filters with real descriptors and original files.

Pending jobs and resource lifetime handles are deliberately scoped in-memory spies. They let the harness force stale completion and exact interleavings without claiming to run a real worker or qualify native resource sealing. History selection is a scoped spy that reads genuine records and only returns a matching exact window. The new-window mismatch check crosses actual map/version/window catalog callbacks, then refuses the deliberately wrong saved result at the resource boundary. The pure renderer was separately qualified against independent source/geometry checks and actual Chrome.

Both successful state receipts verify unchanged original terminal-store bytes and all seven frozen controller source files. Native seal integrity, real worker publication, real browser paint/keyboard behavior, cold restart and genuine original-export transport belong to the root and resource-agent evidence. These state checks add race coverage; they do not replace those receipts. No services were started by this review.

## Checkout-10 source hashes

SHA-256 values are also embedded in both state receipts.

| Source | SHA-256 |
| --- | --- |
| `platform-clock-catalog-views.R` | `4c1a992be30996e232ac70c3a80ee12396c8f8050f722c16ea19ad0909bb1313` |
| `platform-clock-catalog.R` | `f2594738250b4b0ed3ef90ac28201b00c0e21559f7cf30e83e664f015cbe6d8e` |
| `platform-clock-dispatch-views.R` | `6171997000a2c000fdbb369bea259040f814c3b70adf5fe99bda50948f46ca3b` |
| `platform-clock-plot-review-views.R` | `80a6511bab50ec7deb1fd829bc918d60aa25f7f170239b050a8c67f3102d1b5d` |
| `platform-clock-selection.R` | `d10f52d1d9c017a2cb454f24a844f0a8537d3070fd4733446efc90d270955565` |
| `platform-clock-view-model.R` | `5f9d02aa410dd90c93080deb3be15e2b6c730c0f33313b5487b43464e1d6fa63` |
| `platform-clock-views.R` | `e8a0cc9e49b245db963a9dab53015914e3e03df06e3646df17032ba341987507` |
| `clock-review-ui.js` before presentation change | `962dacd9db3840c3a7f27c54364087ce57f8ad1415dfaea06651604b631a6342` |

## Receipt hashes

| Receipt | SHA-256 |
| --- | --- |
| `state-02/results.json` | `89e17136f809b5cde8e3cacb0ff3a6d1bfe098a03ebcf1e8e46ff935a88de9b6` |
| `state-03/results.json` | `3183398fef14ec2d75acf298c05c6892bb7ce4c272b0add181b10c1e0e66ac05` |
| `retry-fences-01/results.json` | `cdfc65e555e4e4cf8ac608ed86e5ed6e622bf0b41edb321f950f9dff79ed7d9a` |
| `js-01-results.json` | `64d2c5bf5054ad6518d11f1e0123b9083a55273ac82730d64b8043e3f325af03` |

## Final presentation-only qualification

Checkout-11 changes exactly three source paths from checkout-10. Inspection confirms that the R changes move existing explanatory paragraphs below the chart and make the completed status paragraph visually hidden while retaining the live region. The JavaScript change aligns owned completed headings to the viewport start; preparation and failure retain center alignment. No job, authority, native-resource or state transition logic changed, so native/state checks were not repeated for this presentation change.

`presentation-js-01-results.json` passes all **24** full-script simulated-DOM checks, including preparation centered before acknowledgement, completed heading aligned to start, and no focus or scroll reclaim after deliberate keyboard focus, wheel or touch navigation. `passive-js-02-results.json` passes all **12** passive overview checks on the same final asset. The full current script executes in both harnesses, with separate selectors and multiple listeners/observers for its two initializers.

The portable versions in `portable-tests/` also pass (24 and 12 checks) against that same asset. Copy them to the repository as `tests/clock-review-ui.mjs` and `tests/clock-plot-feedback.mjs`; the accompanying `REPRODUCE.md` explains default and explicit-path commands. They require only built-in Node modules. `portable-main-01-results.json` and `portable-passive-01-results.json` retain the packaged-script checks. No default-path installed-repository run is claimed by this external harness; that path resolves to `../www/clock-review-ui.js` relative to each installed test file.

| Final file / receipt | SHA-256 |
| --- | --- |
| checkout-11 `www/clock-review-ui.js` | `ecff3bed1377f1eee0f45e327da032568b1cc4804eac0f1c2bb3a4f20087bf55` |
| checkout-11 `R/platform-clock-dispatch-views.R` | `1d16de4c15b293f54f1d05ffba6b72c9782d8f6d9250636bf6346eff12ca08b1` |
| checkout-11 `R/platform-clock-plot-review-views.R` | `439325b43e097f1e0787bd3a83fdb62cab904357c85f29e2fac87c3cbe8e0830` |
| `presentation-js-01-results.json` | `eb192a418293c88c78c2788f15fd88643b047e13c6624ea28bf4cd2b86cda526` |
| `passive-js-02-results.json` | `2eb964b5da3f64a6d1bb834ea2adfebf98dd0757e25bd6535ffbdb7ba78c4405` |
| portable `clock-review-ui.mjs` | `d71314f6d1c935b9c9c528fc355da292d4e21bbcb8fde9332a208cc70d0d7818` |
| portable `clock-plot-feedback.mjs` | `0c18d74ed52cd89438eacd16d04de70833f6d13d3725ea0a131ad1797339d6b0` |

All review-owned processes are terminal. No root application/service was started or stopped by this review. Remaining actual connected-browser geometry and accessibility evidence is owned by the root's final browser run.
