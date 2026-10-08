# Responsive reports and durable preparation

Development decision, 9 October 2026. The requirements below extend the existing
saved-report contract. The qualified catalogue is now active; background reading
and durable preparation remain planned. None of the 17 packages / 50 capabilities
is completed by this checkpoint.

## Confirmed problem

The ordinary application at `ecb2ffb` was tested against an unchanged copy of a
large saved ECG/PPG package. Entering report preparation took 31.38 seconds;
selecting the exact history entry took another 171.66 seconds to reach ready.
The journey exceeded its existing 240-second application/browser bound. It did
not complete downloads, accessibility scans or a fresh-process reopening.
The failed attempt is retained. Increasing that bound is not a product fix.

A full retry on the promoted catalogue runtime also failed the unchanged bound.
Entry improved to 1.93 seconds in this observation, but history-to-ready took
173.95 seconds, followed by 7.70 seconds to idle. The genuine HTML GET took
30.93 seconds and saved exactly the original 737,297 bytes. Its HEAD request
started without a retained response; ZIP, five accessibility scans and cold
reopening were not reached. The R guard stopped the browser; all 30 observed
processes and the listener subsequently closed. This was not natural successful
completion. A separate 35-check inspection conserved original rows/files and
the exact permitted startup additions. Independent failure review: `97c6d606`.

Incremental same-clock browser observations separated approximately 30.26
seconds from preparation feedback to exact-report opening, then 143.03 seconds
to ready. These include acknowledgement, scheduling and client/flush work;
they are not R function timings. The successful HTML and conservation evidence
do not make the overall run or download suite pass. Retain the original failed
run in `cardiac-researcher-ui-successor02-qa-20261009`; do not start a cold run
or repeat unchanged source merely to seek a better outcome.

The predecessor source catalogue built complete scientific choices while listing
findings. Saved-history hydration, report opening, periodic current checks and
download checks also run synchronously in the Shiny process. The initial browser
run did not retain enough intermediate observations to attribute its total to
individual calls; source inspection is not a substitute for measured timings.

The ordinary worker processes jobs, but advancement of a saved report intent
between prerequisite preparation and assembly still depends on an active UI
controller or explicit Resume. Existing API coordinator evidence does not prove
that a researcher can click Prepare, leave and return to a completed report.

## Required researcher experience

1. Show the authorized saved-findings list without validating every analysis.
   Add checks the chosen exact saved version and explains any problem. Remove
   remains available even when a previously selected source is unavailable.
2. Show feedback before expensive work. Preserve current contents and unapplied
   edits when an Add fails or is cancelled, subject to current access checks.
   A changed draft must never present an older report as its new result.
3. Keep navigation and cancellation responsive during long validation. Status,
   keyboard focus and phone layout need actual browser evidence; a frame
   acknowledgement alone does not prove paint or interruptibility.
4. One explicit Prepare saves the exact instruction. Leaving or restarting the
   UI must not discard it. History should show durable progress and the result.
   Failure offers explicit Retry; expired authority requires explicit Resume
   under current access. Unsaved edits do not cancel accepted saved work.

## Implementation sequence and boundaries

### 1. Lazy catalogue and edit-safe feedback

The active catalogue uses cheap, authorized descriptors for listing and the
original complete source admission for Add. A descriptor grants no scientific
validity or preparation permission. Add rechecks the exact revision, study and
project before and after full admission and before adopting the new contents.
Invalid optional labels make only that row unavailable; scope or identity errors
remain fatal. No new report or job is created merely by selecting findings.

Keep `R/platform-load.R` exact: it is itself part of the report renderer identity.
The additive UI helper must be sourced from `app.R`, after the existing loaders
and before `shinyApp`, with local scope and UTF-8. Join helper, server, views and
application source pins together. Verify the complete original renderer/worker
inventories, not just the new helper's filename.

### 2. Owned background reading

The proposed next primitive is a supervised persistent reader process retaining
the original open/current/release operations. Database connections, locked R
environments and native file holds stay in their owning process. The parent
retains session, generation, intent and draft checks; stale completions cannot
be adopted. Hosted context must be verified and bound in the child as well.

Moving only open into a background task is insufficient: periodic checks and
every actual GET/HEAD would still block. Avoid an accumulating polling queue.
Each download requires fresh access/source checks after that request, plus a
defined file-hold lifetime through the completed response. A returned path or
earlier status check is insufficient. The asynchronous HTTP response and stream
ownership seam is an explicit unresolved activation gate.

Source inspection narrows that gate: Shiny's data-object response can pass a
promise through its [middleware](https://github.com/rstudio/shiny/blob/v1.14.0/R/middleware.R#L330-L423),
and [httpuv 1.6.17](https://github.com/rstudio/httpuv/blob/v1.6.17/R/httpuv.R#L62-L143)
resolves it before response conversion. Heavy work must still run in a separate
process. This source evidence is not a successful browser transport test.
httpuv's Windows file source acquires its own deny-write/delete read handle,
but the current R API offers no verified handle-transfer or response-completion
notification. Its promise cleanup closes request input, not the response stream.
Qualify overlapping ownership through GET/HEAD conversion, disconnect and error
cleanup before releasing Brohn's hold. An immutable raw snapshot is a possible
bounded small-response alternative; it must not silently remove large-archive
support. See the [native conversion](https://github.com/rstudio/httpuv/blob/v1.6.17/src/webapplication.cpp#L183-L260)
and [Windows file source](https://github.com/rstudio/httpuv/blob/v1.6.17/src/filedatasource-win.cpp).

Cancellation invalidates UI adoption and download keys immediately. Child and
parent shutdown must release the exact owned handles/processes within bounded
limits. Do not terminate unrelated processes. This is a proposed design, not
implemented responsive cancellation or a claim of faster computation.

### 3. Durable orchestration

Capture a separate, versioned orchestration authorization at the real Prepare
action. Bind the exact intent, request, generation, workspace, project and actor
to its allowed operations. Never convert a display grant into assembly authority.
Historical intents require explicit authorized Resume before enrollment.

Add a bounded coordinator step to the ordinary worker. Reuse existing revision,
deduplication and publication fences so two workers and an open UI converge on
one assembly job. Preserve job resource limits. Advance only eligible waiting
work; never auto-retry failed, cancelled, superseded or unauthorized work.
Revocation, expiry and policy changes must remain effective between stages.
Cancelling one preparation must not cancel shared dependencies owned by another.

### 4. Further computation improvements

Keep validation separate from authorization. An operation-local memo candidate
preserves complete output bytes but reduced one observed open only from 119.15
to 113.66 seconds, and current from 5.66 to 5.33 seconds. That is one ordered
comparison, not a stable speed guarantee or acceptable latency.

Persistent validation certificates are deferred. Existing publication receipts
bind historical producers and artifacts; they do not certify acceptance under
the current validator. Any future reuse needs complete trusted input and validator
identity while retaining fresh authority, source, object and native-hold checks.
Saved scientific values and historical method versions must remain exact.

## Current evidence and next acceptance

The catalogue/disclosure composition is now active in the normal app; the reader
memo remains private. See [source-specific acceptance](../qa/REPORT-SOURCE-CATALOG-ACCEPTANCE.md).
The lazy catalogue passed 27 actual SQLite/local-authority checks and 34 Shiny
controller checks with explicit backend/resource spies. Its accessible-name
successor then passed 239 controller checks across 47 scenarios in four suites:
47 general, 55 task, 31 choice and 106 EDA checks. These preserve all 227 earlier
assertions and add 12 Add/acknowledgement checks. They do not qualify browser
behaviour. The later disclosure-state change preserves the same server/helper;
its composed ordinary app passed 14 browser, five R and 37 saved-data checks,
with two zero-violation Axe scans. Keyboard Add/Remove preserved the draft and
open panel; deliberate close and navigation reset worked. Source names remain
available to screen readers. Do not combine these source scopes into one claimed
whole-application test run.

In that completed browser run, catalogue entry took 1.81 seconds, Add 4.17
seconds, Remove 0.83 seconds and Back 0.73 seconds. Checking feedback appeared
in the DOM after 353 ms; this is not proof of paint. These are single observations
on the original fixture. The predecessor run remains failed at an ambiguous
heading locator; its correction only selects the intended level-two heading.
All original rows/files were preserved, with only the 73 source-audited startup
schema additions and 15 empty new tables. No job or report was created.

The changed full R manifest passed a focused 24-check fresh participant-service
compatibility run. Existing-run CURRENT and literal old-operation replay retained
original descriptors/results. One explicitly synthetic visibility event recorded
the current descriptor with the unchanged renderer. The second allocation,
schema, other rows and objects stayed exact; no Finish/job/report was created.
This tests original in-process routes after a fresh registration, not browser
transport or universal historical deployment compatibility. Restart complete
services; do not replace source beneath an already registered process.

The memo candidate separately passed 62 component, 24 real saved-selection
fault and 20 full saved-reader checks. Complete original output/artifact bytes
were conserved. Its original comparison baseline remains failed at a later
incorrect whitespace-fault expectation; only its retained successful pre-fault
output/timings support the comparison. Independent cleanup records confirm the
test owners closed and protected inputs stayed exact.

Retained local evidence owners are `cardiac-researcher-ui-qa-20261009`,
`cardiac-history-feedback-qa-20261009`,
`cardiac-history-feedback-eda-test-qa-20261009`,
`cardiac-reader-performance-next-20261009/qualification03` and
`report-source-lazy-catalog-qa-20261009`, with regression evidence in
`report-source-lazy-regression-qa-20261009` and browser acceptance in
`report-source-lazy-browser-qa-successor02-20261009`. These are development-workspace
receipts, not bundled public fixtures or portable acceptance of this checkout.

- [x] Qualify the composed ordinary app's actual entry/Add/Remove flow, edit
  preservation, keyboard/mobile presentation and accessibility.
- [x] Verify participant-service manifest compatibility and promote the exact
  qualified source and six portable controller/catalogue tests to the main checkout.
- [ ] Complete saved cardiac history, exact HTML/ZIP downloads and cold reopen
  within the unchanged bounds after addressing the latency defect.
- [ ] Qualify owned reader cancellation, late completion, parent/child death,
  authority changes and download stream lifetime before UI activation.
- [ ] Prove browser Prepare → leave → ordinary worker → fresh browser result,
  including worker restart, concurrency, explicit Retry and shared-dependency
  cancellation without rewriting original results or creating duplicate jobs.

Continue assigned A/V, participant readiness, questionnaire/design flexibility
and scientific/device/hosting work in the [workstream](../WORKSTREAM.md).
