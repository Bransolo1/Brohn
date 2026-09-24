# Portable connected release smoke

This is a small connected release check for the Windows local profile: a researcher creates and releases an original questionnaire, a browser participant finishes it, the supervised worker publishes an automatic report, actual downloads retain its exact values, and a full service restart reopens the same result. It does not qualify the full platform, scientific methods, physical devices, hosted TLS/OIDC or a clean operating-system installation.

## Run from a configured installation

Use the source checkout being tested and a configuration prepared for that source with `scripts/setup-local.ps1` or `scripts/configure-local.ps1`. Required inputs are the exact R/library and protected-publication configuration, Node 22 or newer, the pinned Playwright and axe packages, and an explicitly named installed Chromium browser executable. Node 24 and installed Chrome are the exercised versions. The command installs or downloads nothing.

```powershell
& C:/Brohn/source/scripts/run-connected-smoke.ps1 `
  -ConfigurationPath C:/Brohn/local/local-installation.json `
  -OutputDirectory C:/Brohn/evidence/fresh-smoke-01 `
  -NodePath C:/Tools/node/node.exe `
  -BrowserExecutablePath 'C:/Program Files/Google/Chrome/Application/chrome.exe'
```

The evidence parent directory must already exist; the final directory must be new. The command works from an unrelated current directory. If JavaScript tools are installed outside the checkout, add `-NodeToolsRoot C:/Brohn/qa-tools`. That directory must contain `node_modules` with the versions in this checkout's `package.json`; module entry paths must belong to those verified packages. Install those development tools separately using the pinned package-manager lockfile. No global-module or neighboring `work` fallback is used.

`-CheckOnly` checks the configured R/publication/Python prerequisites and launches/closes the specified browser without opening a research workspace or starting HTTP services. The normal route selects two available loopback ports, starts the actual `scripts/run-brohn.R` supervisor, and retains separate service logs for both startup cycles. A port race fails rather than adopting a user's unrelated service.

The configuration supplies runtimes only. Its saved workspace is a forbidden evidence destination, and no configured study store is opened. A fresh workspace lives under the new evidence directory. Checkout/runtime/configuration overlap, existing output and junction-based escapes are rejected. Child processes receive isolated Brohn/R environment settings; the caller environment and original configuration bytes remain unchanged. Cleanup requests graceful shutdown of the owned supervisor; an emergency fallback targets only its exact process tree and makes the check fail.

## What the connected check establishes

- Actual researcher controls create a five-question survey and publish a sample-origin release. It includes a required rating, optional blank and whitespace text, nonblank text with exact spacing and an optional second rating.
- The real participant page uses preserved release code, accepts consent, refuses a missing required answer, records numeric `4`, intentionally omits three optional answers, preserves the complete nonblank Unicode text, and reaches the durable final receipt.
- The actual receiver journal is contiguous and complete. Exactly one automatic `analyse_run` job publishes at attempt one through native protected storage.
- Independent expectations require the numeric mean/count to be `4`/`1`, each omitted value to remain null (three missing answers), the exact text and its count to remain unchanged, and the unlinked session to receive no invented unique-person count or inferential contrast.
- Downloaded JSON equals the retained report; Python's standard CSV reader reconstructs every native response record from the actual observation CSV. Standalone HTML displays every question.
- Fresh researcher context after full service shutdown/restart downloads byte-identical JSON, with unchanged design, journal, report and runtime assignment and no duplicate automatic analysis.
- Source and configuration hashes are compared before/after; desktop/narrow screenshots and automated axe/reflow results are retained externally for visual inspection.

## Source and native-build portability

The original developer checkout's `src/publication_guard.c` used LF bytes (`18cf63b18cef7404d09792713dc7434969df42a83dba97b00b36160ed1b03710`). A fresh Windows checkout with `core.autocrlf=true` has CRLF bytes (`88a1d6d88ddf197fa0325658e1aeb3a1ddf592b7a0df241f23a2f2f3ede35811`). The original compiled guard correctly refuses that different source identity. The two files differ only in line endings; the guard's exact-byte check is retained.

Build the guard for the selected checkout through the supplied setup/build route using an explicit existing compiler, and save a separate checked installation configuration. Do not change source bytes or relabel an old native manifest to bypass this check. The qualification uses a new external guard built for the untouched fresh clone; the original configuration, manifest and workspace remain retained.

## Accepted evidence and precise source scope

On 24 September 2026, the connected run passed **22 checks and four automated accessibility/reflow scans**. Its receipt is `C:/Users/User/Documents/Brohn portable qualification/20260924-01/journey-03/results.json`. It ran from the unrelated `separate caller` directory using a fresh local clone of commit `2b3b31a2eee67aaea64d57c2586695c2591a525c`, explicit Windows Git `core.autocrlf=true`, and no clone-local `node_modules`. The selected external R library, Python, Node tool installation and browser were used explicitly.

This is the committed base plus the new portable smoke files and the separately reviewed participant omission correction, not a qualification of subsequent media/facial work. The overlaid runner SHA-256 is `cb443e2ba828ae6a5f064372a5f9bba18d47447b000154b52bf130e3a5f8d25d`. `overlay-04.json` records the exact overlay, while `journey-03/source-start.json` and `source-end.json` bind all executed application/test sources and confirm no changes during the run. The new guard/configuration was prepared using the clone's source bytes and the existing explicit TinyCC compiler; no tools, packages or browser were installed.

The saved report contains five responses, mean rating `4`, three omissions and the exact nonblank text `  Caf\u00e9 + original concept  ` (the escape denotes the actual accented character). Exactly one automatic analysis attempt succeeded. JSON and complete CSV matched the independently specified original values; full supervisor restart reopened byte-identical JSON with unchanged study, journal, report and runtime assignment. Both service cycles stopped normally and a subsequent process inventory found zero owned processes. `downloads.json` records all download byte hashes and lengths.

Separate checks passed **21 pure path/tool/environment checks** (`tests/connected-smoke-support.mjs`) and **17 actual launcher readiness/refusal checks** (`tests/connected-smoke-launcher.ps1`, receipt `launcher-01/results.json`). The latter runs with deliberately wrong inherited hosted/workspace/R settings, verifies the explicit configuration wins, restores caller environment/pipe encoding, creates no study store or HTTP service in readiness mode, and refuses existing evidence, protected destinations and a missing browser. Earlier readiness-only success is separately recorded in `readiness-03/results.json`.

The external `qualification.json` and before/after configured-workspace inventories confirm that all nine files in the original configured workspace are byte-identical. The original configuration SHA-256 remains `97bb7ad695fbd0013ff86f47e13b044f675d2da86ccf033c6bc61c6c767e9a49`; the separately prepared clone configuration remains `d29d833736a8999b2f48954b528ec3c368a66232afde0949fd9eb54acadc4c36`. The smoke does not open or mutate that original workspace.

Exercised runtimes: R 4.6.1 with the exact lockfile library, Node 24.19.0, Playwright 1.63.0, axe Playwright 4.13.0 and Chrome 153.0.8010.54. This remains an existing Windows-host qualification, not a clean-machine installation claim.

## Final integrated source checkpoint

The subsequent current-source run passed **22 connected checks and four clean accessibility/reflow scans** at `C:/Users/User/Documents/Brohn portable qualification/20260924-integrated-01/journey-01/results.json`. Both review-module owners confirmed their production files were stable before copying. A new detached clone of the same published base, with `core.autocrlf=true` and no local `node_modules`, received all 66 nonignored changed/new files from that working-source checkpoint. `overlay.json` records each exact byte hash; its own SHA-256 is `4e26b2ba6ef9a8230a5afdbc5077c229e68a8625c4124fa8d94d1045a2f1006c`. Later work in the original checkout was not copied into this frozen qualification source.

The unchanged smoke ran from the unrelated `separate caller` directory with the same explicit external runtimes/configuration. The clone's untouched native C source matched the previously built CRLF guard, so it reused that exact manifest without rebuilding or weakening source checks. `journey-01/source-start.json` and `source-end.json` preserve all **354 application/test source identities**, unchanged throughout the run; the starting manifest SHA-256 is `dceb8c36811faa6f5932b88acc9c2858ef21243a771fe2bcb951e9ac2a310bba`.

Key frozen application identities:

| File | SHA-256 |
| --- | --- |
| `R/platform-data-views.R` | `61f7d00d6b3b09774c1a91cc3a95ccff7c1cf889952a0c3821178ac4a120f9d9` |
| `R/platform-media-review-views.R` | `b85d5a5044b9740be347ca412c006fe2a562c70f6133beb1fd36045dec6fd332` |
| `R/platform-facial-review-views.R` | `89715585bbbcb5addb5edd7aa39fb2fb007075ca295c44882586b930980d0d08` |
| `www/participant/runner.js` | `cb443e2ba828ae6a5f064372a5f9bba18d47447b000154b52bf130e3a5f8d25d` |

Actual researcher creation/release, preserved participant runtime, required-answer refusal, all five exact response records, one successful automatic analysis at attempt one, JSON/CSV downloads and full service restart passed. Reopened JSON is byte-identical (`f88d8b6931f74ae5f0bd1766add71bb2885d3c0e33948ffaebac7a8acd03e366`), and restart adds no second analysis. Both supervisor cycles exited zero without forced cleanup. A post-run process inventory found no owned R, Node or browser processes. `protected-before.json`, `protected-after.json` and `qualification.json` confirm the original configuration, supplied configuration, native manifest and all nine protected workspace files are unchanged.

The newly downloaded standalone HTML additionally passed **18 focused checks and two clean axe scans** at `offline-wrap-01/results.json` with `--mode current` and no injected styles. Its SHA-256 is `ffab0db372c02e74060ded1c7db88edb1fd579990319277133b7bfaec840e8da`. The actual release, participant receipt, interactive report and narrow HTML screenshots were inspected; focused 320/390-pixel checks retain whole words/identifiers and native keyboard scrolling without page overflow. This is a connected core-route check with the integrated review modules present. It does not rerun facial/audio inference or replace those modules' independent saved-source review acceptance.

## Visual limit and retained failures

All four screenshots were inspected. The desktop release screen, narrow participant receipt and interactive saved report are legible. The original standalone HTML's four-column quality table had awkward word fragmentation at 390 pixels even though it had no horizontal overflow or axe violation. `journey-03/offline-report-390.png` and the exact `report.html` retain that limitation. The data/download/restart acceptance remains valid; the separate correction and actual-export follow-up below establish the current narrow HTML presentation.

A separate in-memory CSS candidate `td,th{overflow-wrap:normal;word-break:normal}` passed **18 focused checks and two axe scans** in `offline-word-wrap-02/results.json`. At 320/390 pixels, `participant` and `Unavailable` each occupy one line instead of three/two, while the existing labelled, focusable regions contain wider tables. Actual Tab and left/right arrow keys scroll both quality and observation tables; original 32-character identifier tokens remain whole, with no page overflow or changed values. Candidate screenshots, including the identifiers, were inspected. The original HTML SHA remains unchanged. This is candidate-only evidence; `tests/report-html-word-wrap.mjs --mode current` can qualify the next actual export without style injection after the production correction. The earlier 16-check candidate receipt remains separate; the final run adds explicit identifier-token geometry and screenshots.

Focused regression on a fresh actual export (no injected CSS):

```powershell
node C:/Brohn/source/tests/report-html-word-wrap.mjs --html C:/Brohn/evidence/report.html --output C:/Brohn/evidence/fresh-wrap-check --node-tools-root C:/Brohn/qa-tools --browser 'C:/Program Files/Google/Chrome/Application/chrome.exe' --mode current
```

Use `--mode candidate` only when intentionally testing the recorded CSS in memory against the unchanged old export.

After the exact CSS correction was applied to `R/platform-data-views.R`, a fresh R export of the unchanged accepted source report passed **18 checks and two axe scans** with `--mode current` and no style injection. Evidence is `offline-actual-export-01/export.json` and `offline-actual-wrap-01/results.json` under the same external qualification root. The source report SHA-256 is `9925d13e38a8a4cca181ddd6c7f5c7bc8cde0bd51ca00cdd35669c9448ea0000`, renderer SHA-256 is `61f7d00d6b3b09774c1a91cc3a95ccff7c1cf889952a0c3821178ac4a120f9d9`, and actual HTML SHA-256 is `531860d40bf5929aeae70af00c2df85dd82ca983db22f81ec2561b0a459382d8`. Screenshots of the quality, observation and identifier regions at 320/390 pixels were inspected: whole words and exact identifier tokens remain legible within keyboard-scrollable tables, without widening the page. No R or HTTP service was started by this focused browser check; its browser closed normally. This qualifies the actual standalone export correction, separately from the planned final integrated connected smoke.

- `readiness-01` stopped before services because axe does not export its package manifest as a Node subpath. The new helper now reads the selected installation's manifest directly, verifies its resolved entry belongs to that same package, and tests the restricted-exports case.
- `readiness-02` stopped before services because the original LF-native guard did not match the CRLF exported source. That was the expected source-integrity refusal; rebuilding into a new external location resolved it without changing source or the original configuration.
- `journey-01` completed a real participant and automatic job, then a fixture-only run-field typo stopped verification. The fixture was corrected to use `completion_status` and `transfer_status`; this attempt is not counted as a connected pass.
- `journey-02` exposed a product defect: standard optional blank text was submitted as an empty string and counted as answered. Root made standard submission match the existing revised-questionnaire omission rule. Only newly committed optional empty/whitespace/unanswered values become null; nonblank values retain exact bytes and historical stored responses are unchanged. The five-question `journey-03` explicitly checks that correction, optional rating omission and required-answer refusal.

Every attempt retains separate logs/results and completed owned-service cleanup. All stores, generated capabilities, source exports, native binaries, downloads, screenshots and raw receipts remain outside Git.

## Remaining broader QA portability

This route makes one connected core path reproducible; it does not make every legacy check portable. A direct-text audit of the committed QA catalog found developer-folder references in 8 of 87 domain entries, 3 of 29 operations entries, 7 of 23 scientific entries and 1 of 4 interchange entries. These are textual hits, not execution failures; indirect fixture dependencies remain to inventory. `scripts/run-checks.R` already resolves its checkout and external evidence, but still expects runtime environment setup. Its full suites and `npm run test:browser` (historical prototype) remain distinct from this new connected profile.
