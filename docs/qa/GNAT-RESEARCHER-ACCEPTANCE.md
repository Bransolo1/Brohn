# GNAT connected researcher acceptance

Status: **connected scope accepted across explicit preserved phases, completed
24–25 September 2026 (Perth)**. Final focused restart finished at 00:01:34 on
25 September. This is deliberately not presented as an uninterrupted single
passing harness run.
This document does not promote component checks into end-to-end acceptance.

The joined receipt is
`C:/Users/User/Documents/Brohn QA/gnat-preflight-01/joined-acceptance.json`.
It verifies two complete saved administrations (384 task trials and 789 outer
events each), two real imported summaries, one reviewed two-person cohort,
five exact numerical report objects and seven successful first-attempt jobs:
two native analyses, two source ingestions, two imported analyses and one
cohort analysis. The final restart adds zero jobs and preserves every retained
session, report, runtime assignment and job. All owned services and browsers
are stopped.

The named `gnat-brohn-single-target/1.0` procedure is a Brohn adaptation. Its
384 trials comprise 80 category-training, 64 pairing-practice and 240 test
trials. The test rounds remain separate at 750 ms and 600 ms. This acceptance
does not claim historical/vendor equivalence, measured physical timing,
construct validity or population reliability. See
[implementation boundaries](GNAT-NEXT-IMPLEMENTATION-PACKET.md) and the current
[procedure contract](../methods/GNAT-BROHN-PROCEDURE.md).

## Connected scope

- Researcher creates an original fictional Aster study in the actual authoring
  UI, declares material rights, target/context/attribute roles and context
  rationale, supplies variable-length exemplar lists and a separate liking
  question, saves a template, clones and reimports the portable design.
- Researcher releases the study with a sample collection origin and two
  required distinct synthetic aliases. Each browser completes all 384 trials
  at the unchanged procedure timing using trusted Space presses or genuine
  withholding. No fixture seeds reports or bypasses timed trials.
- The integrated supervisor receives the original journals and runs one real
  automatic report job per completed administration. An independent
  `statistics.NormalDist` oracle checks every cell's counts, sensitivity and
  criterion against authored response plans, with separate within-round
  contrasts. Withholding has a null key and null latency.
- Native report JSON, score CSV, full trial CSV, frozen registry and complete
  plot exports are downloaded through the actual UI. All 384 rows and the 240
  test-only selection are checked; CSV exact-record JSON reconstructs every
  plotted row. Categorical SVG retains every outcome position.
- Both native trial sources are imported through the reviewed upload and
  mapping flow. Imported arithmetic must agree with native output while
  explicitly retaining `declared_trial_summary` evidence instead of claiming
  raw journal replay.
- Researcher reviews the two administration/person links and saves one cohort.
  All ten metric means and sample SDs are checked against two equally weighted
  person values; native/import copies cannot become additional people. The two
  deadline contrasts are separately selected and exported.
- Complete supervisor shutdown/restart and a fresh browser reopen identical
  native reports without new analyses, changed journals or changed runtime
  assignments. Native result-object hashes remain verified.

## Harness and prerequisites

The new files are `tests/researcher-gnat.mjs`,
`tests/researcher-gnat-oracle.mjs`, `tests/researcher-gnat-oracle-check.mjs` and
`tests/fixtures/researcher-gnat.R`. The harness shares the accepted portable
smoke's destination validation, isolated runtime environment and exact pinned
external Playwright/axe resolution. It does not use developer-relative runtime
fallbacks or the configuration's saved workspace.

Run the fixture-only self-check with an explicitly selected Node executable:

```powershell
& $NodePath (Join-Path $Checkout 'tests/researcher-gnat-oracle-check.mjs')
```

For the connected run, use an existing installation configuration with the
exact checkout-specific native publication guard, an installed Chromium
executable, Node 22 or newer, and the checkout's pinned Playwright/axe packages
in an explicitly selected tools directory. Source the repository's strict
configuration parser and pipe a runtime-only request to Node:

```powershell
. (Join-Path $Checkout 'scripts/local-configuration.ps1')
$cfg = Read-BrohnLocalConfiguration $ConfigurationPath
$request = [ordered]@{
  schema = 'brohn-researcher-gnat-request/1.0'
  project = $Checkout; output = $FreshExternalEvidenceDirectory
  configuration_path = $cfg.configuration_path
  configuration_sha256 = (Get-FileHash -LiteralPath $cfg.configuration_path -Algorithm SHA256).Hash.ToLowerInvariant()
  forbidden_workspace = $cfg.workspace
  rscript = $cfg.rscript; r_library = $cfg.r_library
  publication_python = $cfg.publication_python
  publication_manifest = $cfg.publication_manifest
  portability_python = $cfg.portability_python
  node_tools_root = $NodeToolsRoot
  browser_executable = $BrowserExecutablePath
}
$priorEncoding = $OutputEncoding
try {
  $OutputEncoding = [Text.UTF8Encoding]::new($false)
  $request | ConvertTo-Json -Depth 6 -Compress | & $NodePath (Join-Path $Checkout 'tests/researcher-gnat.mjs')
  if ($LASTEXITCODE -ne 0) { throw 'Inspect the retained GNAT failure receipt.' }
} finally { $OutputEncoding = $priorEncoding }
```

All paths above must be explicitly supplied absolute paths. The evidence
directory must not exist and its parent must exist. Runtime/configuration,
checkout and saved workspace overlap are refused. Ports are chosen from
available loopback ports; only the newly launched supervisor/process tree is
stopped. A 40-minute harness safety budget does not alter any participant
deadline or receiver timeout. Every failed attempt stays in its original
evidence directory.

Before a qualifying run, freeze all recorded production sources and enable
the normal GNAT chooser only after its component gates pass. The final
receipt must include source/configuration hashes, supervisor shutdown,
original independent oracle outputs, job identities, all exports, automated
accessibility results and screenshots actually inspected. Existing Windows
runtimes are not a clean-machine installation test. No device, camera,
emotion inference or hosted TLS/OIDC claim is in this scope.

## Evidence

The fixture-only Node self-check passes four grouped assertions: both authored
384-trial plans have the intended independent cell counts and preserve their
inputs; fabricated zero-latency withholding, missing trials and changed outcomes
are refused. The JavaScript syntax and R fixture parse also pass. These checks
start no services and establish no product acceptance.

`C:/Users/User/Documents/Brohn QA/gnat-connected-01/results.json` retains the
first actual attempt. Authoring, variable exemplar lists, template/clone/design
import, desktop/390px accessibility and actual live material/feedback visuals
passed. The driver then timed out at the next self-paced instruction screen.
It had repeatedly copied the growing IndexedDB journal through the automation
protocol during timed trials. It eventually observed stale onsets and sent
some intended responses to later stimuli. The retained diagnostic identifies
248 finished trials, 510 acknowledged outer events and 53 differences from its
intended action plan, beginning at trial 86. Brohn retains those actual outcomes;
they were not relabelled or scored as a completed administration.

The failed original journal, screenshot, executed harness and diagnostic remain
in that directory. Its supervisor stopped all owned services normally, and
source/configuration hashes stayed unchanged. No report was produced. This is
a harness failure, not evidence of a complete qualified GNAT workflow.

The corrected driver observes live DOM onsets passively, checks their exact
ordinal/material and reads the current durable trial checkpoint once inside
the page. Only compact identity/state crosses the automation connection. It
requires the exact live trial and a response-dispatch margin before sending a
trusted Space; it never slows the procedure, pauses its clock, patches the
renderer or fabricates events. Complete original journals are independently
checked after the task. The fresh source-pinned 02 administration below
qualifies that correction.

The first attempt also predates two independently found presentation fixes:
the imported timing-definition label and GNAT's study-overview measure choice.
Their corrected sources are included in the separately pinned 02 and later
receipts. The plot-domain timing correction has SHA-256
`eb70caf56068287a84fe3eff8cdb7ebd92901611822ea4bba3c0cf2e9a81f6e3`.

`C:/Users/User/Documents/Brohn QA/gnat-connected-02/results.json` contains the
fresh current-source administration after those fixes. All 384 actual outcomes
match the authored response plan, and the real automatic saved report agrees
with the independent cell/metric oracle. Native JSON, score CSV, HTML and
complete plot JSON/CSV/SVG exports were produced. Four automated accessibility
scans passed. The harness then incorrectly called Playwright `innerText()` on
an SVG `<desc>` element. The preserved failure is an automation API error,
not a missing or failed administration. All owned services stopped normally.
The corrected assertion reads SVG `textContent`; the remaining `innerText`
calls target HTML feedback and the HTML body only.

The stopped synthetic workspace was copied to a fresh external destination
for downstream continuation. Recovery verifies the entire source workspace
byte tree before/after copying, requires normal prior shutdown and identical
production sources, and retains inherited run/job/report identities separately
from new work. It neither changes the original evidence nor repeats or
rescores a completed administration. The optional request field `resume_from`
is restricted to this failed, original-synthetic, normally stopped fixture
contract; it is not a production recovery operation.

`C:/Users/User/Documents/Brohn QA/gnat-connected-03/results.json` reverified the
inherited native report and all 384/test-only 240 plot rows, exact CSV records,
categorical SVG and table page 8. The SVG API correction passed. A subsequent
accessibility scan raced a pending numeric-page update: axe observed Shiny's
temporarily dimmed recalculating output still containing rows 351–384, while
the later screenshot showed the settled readable chart. That failure is
retained. No new participant or job was created, and the original workspace
and production bytes remained unchanged. The harness now waits for the exact
requested page/first trial and a continuously settled visible render before
scanning; no styles or accessibility rules are disabled. Attempt 04 continues
from the unchanged stopped 02 workspace. The complete two-person/import/cohort
journey had not yet been accepted at that stage.

The 03 result and seven-lane chart screenshots were visually inspected at
390px. They preserve readable outcome labels and distinguish observed
withholding from absent evidence. The report's initial viewport remains
dominated by controls; a separate results-first UX proposal is outside this
source-frozen qualification.

Attempt 04 passed the settled chart scan and retained the exact first-person
report. Its second administration began with a No-Go trial; waiting for the
100ms feedback after capturing that trial's material missed the transient
feedback and stalled the automation. Nineteen genuine terminal trials remain
in its separate incomplete workspace, with no second report. They are not
repaired or reused. Capture is therefore removed from participant 2's timed
loop entirely: the first completed administration and component evidence
already establish visual presentation, while participant 2 supplies a second
independent complete journal and downstream person-level checks. Post-task
result screenshots remain enabled. Attempt 05 was stopped before new
enrollment to apply this narrower harness policy; it is not another completed
administration or a product failure.

Attempt 06 then exposed an overbroad harness wait: requiring the entire Shiny
application to remain idle for 700ms conflicted with unrelated periodic status
refreshes. It stopped before participant 2 enrolled and made no new report.
That wait was removed; the exact requested numerical page/row remains a
required readiness condition. Attempt 07 resumes only unfinished work from
the unchanged stopped 02 store. Its explicit `verified_native_ui_from` points
to 04 and requires matching production start/end hashes, exact original report
identity/body, the completed 384-row plot/export assertion and a clean mobile
scan. A separate inherited-UI receipt pins those earlier checks rather than
claiming they were repeated in 07. This optional continuation evidence is
specific to normally stopped synthetic QA; ordinary fresh runs still execute
every step.

The first complete original journal also supplies an observed workload
receipt at `C:/Users/User/Documents/Brohn QA/gnat-preflight-01/first-observed-timing.json`.
Its 384 trials and 12 instruction screens take 369.289 seconds from the first
instruction to the final terminal event in one monotonic clock instance.
Within-block removal-frame-to-next-onset gaps (372 transitions) have minimum
522.5 ms, median 550.95 ms, 95th percentile 600.67 ms and maximum 706.5 ms.
Across all 383 transitions, including self-paced instruction boundaries, the
maximum is 905.4 ms. Quantiles use linear interpolation, equivalent to R type 7.
The receipt binds the original journal SHA-256 and retains each gap. These are
observed software timings under automated input and loopback durable delivery,
not physical display qualification or human completion-time estimates. The
separately retained blank-end-to-next-onset interval does not isolate storage
cost from other intervening software work.

Attempt 07's second administration completes all 384 trials with the exact
authored outcome plan, receives one real automatic report and passes the
independent count, d-prime and criterion checks. Its observed task elapsed time
is 378.802 seconds. Within-block gaps (372) have minimum 522.2 ms, median
545.15 ms, 95th percentile 572.2 ms and maximum 607.5 ms. The separate
`second-observed-timing.json` in the same external preflight directory retains
the exact source binding and all transitions. Both valid administrations meet
the unchanged 500ms minimum in their saved software observations.

Attempt 07 ultimately passes 22 grouped checks and eight clean accessibility
scans, including both actual CSV/registry imports and complete native/import
plots, before a pointer-action race in the cohort's server-loaded Selectize
option. All completed journals, reports and imported datasets are retained.
Attempt 08 copies that normally stopped store and uses ordinary keyboard
option selection with an exact selected-report assertion. It preserves all
earlier accepted phases and creates only the reviewed cohort: ten means,
sample SDs, 20 person values, both separately selected deadline contrasts,
full exports and a clean 390px cohort scan pass. Its supervisor restart also
returns byte-identical native report JSON. A last harness action then tried
to click the study's Plan tab while still on the report screen. The stopped
08 state preserves all five reports and seven successful jobs; no research
calculation failed.

The final continuation copies 08 and uses explicit `restart_only` scope.
That mode requires the prior accepted cohort assertion, exactly two completed
administrations, five saved reports and seven successful first-attempt jobs.
It repeats no participant task, import, analysis or accepted plot scan. It
reopens the study before checking its Plan tab and compares all sessions,
reports, runtime assignments, jobs and numerical result-object identities
before/after restart. This final navigation/evidence check is separate from
the earlier full researcher phases; no single uninterrupted all-in-one pass
is claimed.

The final 09 receipt passes nine focused groups and repeats no accessibility
scans or scientific jobs. Phase receipts contain 02: nine groups/four clean
scans; 04: eleven groups/three clean scans; 07: 22 groups/eight clean scans;
08: fourteen groups/one clean scan; and 09: nine groups/no repeated scans.
These overlapping phase totals must not be summed as unique assertions.
Their raw failure statuses and precise accepted subsets remain in the joined
receipt and original evidence directories.

All five accepted phases use the same 359 production-source identities over
published base `d2889f4d29fc27e1467a3a2a137e05278cbbc0a0` plus the exact GNAT
working-tree changes. Their sorted verification-map SHA-256 is
`961c20cf0010c5d56c4410b1390b0486c8b37b51472b0f0205b23e745bb3a679`;
the full file-by-file manifest is `gnat-connected-09/source-start.json` under
the external evidence parent. Harness corrections have separate hashes and
executed copies in each phase. No production bytes changed within a phase.

The final joined check rehashes the original stopped 02/07/08 workspaces
(47/129/149 files respectively) and confirms every byte is unchanged. The
supplied configuration, native-guard manifest and nine files in the real
configured workspace are also unchanged. Partial 01/04 administrations and
all failed/superseded harness evidence remain external; they are excluded
from the accepted two-person research dataset. No data, service capability,
screenshots or private installation configuration is included in Git.
