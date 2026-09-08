# Completed-transfer review regression

On 2026-09-08, the actual isolated MaxDiff import journey passed **27 checks and five axe scans** against the completed-transfer review and background preservation route. This is new evidence; the earlier MaxDiff import records remain unchanged.

Command, from the repository with its prepared Node/Playwright dependencies:

```text
node tests/researcher-maxdiff-import.mjs
```

Evidence is retained outside the repository in `work/test-runs/brohn-maxdiff-import-ui-g0WqQl/evidence/`: `results.json`, screenshots, axe results, original-source and complete-choice downloads, full report JSON and process logs. The fresh fixture store and original synthetic source files are in its parent directory. The test launched its own x64 R/Shiny process on a random local port, then stopped it through its owned stop request. It did not use or change the shared running workspace.

## What changed in the test harness

`tests/helpers/source-import.mjs` checks the exact completed filename, intended destination, dataset title, modality and origin displayed by the review. It waits for the actual Shiny input binding to carry the current review identity before clicking `Import this file`. It then waits for the automatically opened dataset title and mapping identity, using the separate multistream identity where appropriate. Study-linked upload callers declare the expected study destination explicitly.

Eight existing journeys now use that helper: researcher workspace, native/EDA, neural plots, interchange, stream curation, scales, scale comparisons and MaxDiff import. All eight plus the helper pass JavaScript syntax checks. Only the full MaxDiff journey was executed for this bounded regression; updating a helper does not establish a new browser result for the other seven. The independently owned peripheral browser test was left unchanged.

The isolated MaxDiff fixture retains explicit control over scientific workers. Source-preservation jobs are recorded and processed separately. Its protected second source is imported before queueing analysis, then reopened for the same stale-control rejection. This ordering avoids processing an older scientific request merely to reach a later source import. Full job snapshots retain both operations; existing assertions about scientific queue counts still apply to scientific jobs.

## Observed outcomes

Each of four actual transfers created no dataset, ingestion entity or job until the displayed review was confirmed. Four real `ingest_source` workers then preserved the exact original bytes, saved the reviewed filename/title/family/sample origin and unlinked Data destination, and opened the correct dataset mapping. Their immutable source hashes and import/job identities are retained in `results.json` and the fixture snapshot.

Three scientific worker attempts followed: one successful imported-choice analysis and two deliberate source failures. The successful result retained the independent `6 * log(6)` likelihood, neutral utilities, exact best/worst and exposure counts, leading-zero participant identity, offered item order, partial response, unpresented set and excluded exercise row. Downloaded JSON matched the saved report, and the complete choices CSV and original-source download retained their source evidence.

A changed current study was rejected before curation or scientific queueing. Explicitly choosing its original saved revision froze the correct exercise and hash. Stale controls from another dataset could not overwrite the protected source or add a scientific job. Deliberately incorrect exercise hashes and conflicting row origins produced recorded failures, preserved the originals and created no false report; the earlier report stayed unchanged.

The five zero-violation axe scans covered the open exercise picker at desktop and 390px, pinned mapping at 390px, and the report at desktop and 390px. These pages also passed document-width checks. There were no browser exceptions or visible Shiny errors. The final transfer-review screen was checked for its actual fields and binding; it was not an additional axe scan in this run.

This is automated researcher-workflow and storage regression evidence using original synthetic inputs. It does not qualify physical devices or establish external validity of a consumer preference study.
