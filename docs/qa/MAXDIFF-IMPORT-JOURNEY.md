# MaxDiff import browser acceptance

The full mode of `tests/researcher-maxdiff-import.mjs` passes **23 assertions
and five accessibility scans**, including three actual production worker
processes. Evidence is retained at
`work/test-runs/brohn-maxdiff-import-ui-CVT7Zh/evidence/results.json`.

Its separately executed mapping-only mode passes **14 assertions and three
accessibility scans**. That earlier evidence is retained at
`work/test-runs/brohn-maxdiff-import-ui-a5UATH/evidence/results.json`.
The separate original fixture is `tests/fixtures/researcher-maxdiff-import.R`.
No scientific worker or report is part of this completed mapping-only evidence.

The actual browser uploads an independently formatted original CSV through the
Data library. Its saved study has required importance and optional preference
exercises. The source contains six balanced ordered pairs, a partial answer,
an unpresented set and a row belonging to the other exercise. The literal
participant code `001` and alternating offered orders are preserved in the
source bytes; they are not numbers or sorted sets.

| Research action | Observed mapping evidence |
| --- | --- |
| Upload | Best-worst data family and explicit sample origin retain the exact original CSV SHA-256. |
| Review suggestions | Matching column names populate every choice, identity, presented-status, offered-order and origin field. |
| Choose the exercise | The actual open picker distinguishes both exercises and retains the chosen stable identity; desktop and 390px axe scans are clear. |
| Detect a changed current draft | The fixture edits the saved study after the form renders. Confirm is rejected before a dataset revision or job is written. |
| Select the original version | Choosing saved Revision 1 explicitly binds the original exercise and study hash and queues exactly one request. |
| Reject stale dataset controls | Replaying the earlier dataset's identity and submit event cannot change the newly opened second dataset or enqueue another job. |
| Reopen and retrieve | Reopening retains Revision 1 and its exercise. The full original-source download is byte-identical; narrow-screen mapping passes axe and overflow checks. |
| Stop before scientific processing | The only queued request is explicitly cancelled. No worker was launched and no report exists. |

The full-mode worker result matches the independent likelihood oracle
`6 * log(6)` with neutral utilities. Each of the three items has two best and
two worst selections, six complete-pair exposures and one presented missing
exposure. The unpresented row remains outside those presented counts. Nine
original source rows become eight selected exercise rows and one explicitly
excluded row belonging to the optional exercise. One source person and visit
remain one person and visit, rather than eight independent participants.

The complete choice CSV retains all eight selected rows, including the partial
and unpresented records. Full JSON also retains the excluded row, its source
position and hash. Literal participant code `001`, alternating offered orders,
source SHA-256 and explicit sample origin remain unchanged. The actual saved
model and downloaded JSON match. Report views pass desktop and 390px scans.

Two additional original files deliberately contain a wrong exercise hash or a
conflicting selected-row origin. Their actual worker attempts fail with clear
recorded reasons, preserve their original bytes, and create no report. Those
failures leave the earlier successful report and independently edited current
study unchanged. These are expected negative cases, not silently skipped work.

The initial mapping attempt corrected a harness synchronization issue: changing
the study version remounts the exercise picker, so the test waits for the old
control to detach before selecting the new one. It does not insert a timing
delay, force-click an obscured control, or weaken the saved identity guard.

This is automated simulated-researcher evidence against actual local Shiny and
SQLite. It is not a human usability study, an external-platform endorsement or
a claim of scientifically qualified consumer preference measurement.
