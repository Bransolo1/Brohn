# John: Brohn development handoff

**Current checkpoint, 25 September 2026:** development remains active after
`0b7bf38`. Read the [saved-review responsiveness checkpoint](qa/PUBLICATION-REVIEW-RESPONSIVENESS-20260925.md)
for the current changes, distinct source phases and retained failures. Media
and task-source opening do less repeated work, expose accurate focused progress,
respect keyboard/scroll focus changes and preserve exact sources and exports.
They remain several-second synchronous reads, not a completed performance gate.

The [review guide](operations/REVIEW-SAVED-RESULTS.md) covers the normal flow.
Portable checks have explicit instructions for [media](../tests/media-feedback/REPRODUCE.md)
and [task plots](../tests/TASK-PLOT-REPRODUCE.md). Media qualification needs a
verified retained synthetic corpus copied into a new workspace; task component
tests create their own fixture. Do not use a real research workspace for tests.

The immediate next feature is reviewed cross-recording clock selection and
review. Local backend and hosted-actor paths have external qualification; the
normal UI and full researcher journey are still pending and not enabled here.
Follow the [workstream](WORKSTREAM.md) and [completion backlog](PRODUCT-COMPLETION-BACKLOG.md).
All 50 capabilities and 17 packages remain in scope; publishing is not a pause.

**Resumed after checkpoint `2b3b31a`, 24 September 2026:** the owner explicitly
requested continued development. The [workstream](WORKSTREAM.md) now tracks
portable connected QA, facial temporal review and declared video/audio mapping.
The integrated-source core journey, complete facial review and video/audio
gap/export/restart journey now have [scoped acceptance](qa/PUBLICATION-SAVED-MEDIA-20260924.md).
Next: configured core-catalog portability and GNAT's complete distinct journey.
The pause below is historical.

**Paused checkpoint — 24 September 2026:** the owner requested this source
handoff to `Bransolo1/Brohn` on `main`. Read [the workstream](WORKSTREAM.md) for
delivered changes, ordered next steps and restart rules. The goal was paused at
that publication and resumed by the later explicit instruction above; it remains
unfinished.

**Start here — 24 September 2026:** read the
[current workflow continuation](qa/INTEGRATED-WORKFLOWS-20260924.md),
[latest checkpoint](qa/PUBLICATION-SCIAT-FACIAL-20260924.md),
[current status](../STATUS.md), [master architecture](MASTER-ARCHITECTURE.md),
[remaining work](KNOWN-GAPS.md) and [build manifest](preparation/build-manifest.json).
Use the [local installation guide](operations/LOCAL-INSTALLATION.md) to set up
your own runtime; the new `setup-local.ps1` joins exact restore, native storage
preparation and configuration in one checked command. Source from the other local development task is consolidated
in this repository. Its saved QA data and runtime dependencies are external;
machine-local receipt paths in the evidence documents will not exist in a clone.
Start a branch from current `main`; preserve original reports and run the checks
for the feature you change. The dated September 8 instructions below are history.

Protected isolated-team hosting, saved-video audio derivation and respiration
cycle/phase review now have scoped connected acceptance. Exact navigation from a
saved answer to its participant session also passes its original-source, visible
tables and export journey. Derived-audio reports, plots, intervals and complete
WAV downloads now enforce original-source authority. EMG review and the final
respiration/EMG axes and saved-history fixes now have connected evidence.
Whole-recording EDA now has connected source/export/restart and bounded
responsiveness evidence. Optional local facial AU/native-category processing now
passes its connected researcher journey; read [the acceptance](qa/FACIAL-EXPRESSION-ACCEPTANCE.md)
and [runtime setup](qa/FACIAL-RUNTIME-ACCEPTANCE.md) before enabling it. Dedicated
Brohn response-window SC-IAT now passes its [connected journey](qa/SCIAT-WINDOW-RESEARCHER-ACCEPTANCE.md),
including four complete administrations, omitted/fast responses, exact summary
reimports, reviewed comparison and restart. The independent source/scoring oracle
passes 102 checks; 13 jobs succeeded without duplicate rescoring. Automatic camera
analysis and preserved participant-code delivery are now connected. Their joined
browser, researcher-review and reference status is recorded in the checkpoint. Read their
current architecture contracts before changing either route.
Audio waveform/spectrogram and event-EDA review also have connected evidence
in the workflow ledger. Follow that ledger's separate source versions and
retained failures; publication or passing one journey does not close the roadmap.

**Historical source handoff, 21 September 2026:** read the
[publication checkpoint](qa/PUBLICATION-CHECKPOINT-20260921.md),
[current status](../STATUS.md) and [completion backlog](PRODUCT-COMPLETION-BACKLOG.md).
The questionnaire explorer is now connected. Latest work covers complete signal
values, pupil/blink traces, fNIRS review and saved-video exploration; their
remaining acceptance is recorded in the checkpoint. The old next-step list
below describes September 8 and must not be used as the current backlog.

**Update, 20 September 2026:** the owner resumed work and reconfirmed the name Brohn.
Use [current status](../STATUS.md) and [explorer acceptance](qa/QUESTIONNAIRE-EXPLORER-ACCEPTANCE.md)
for the latest implementation. The stopped-state notes below remain historical evidence.


Development paused at the owner's request on **8 September 2026**. This is a
public source checkpoint, not a finished product release. No background build
or scheduled continuation is running. The next development session is planned
for the following week; you can work from this checkpoint in the meantime.

Repository: [Bransolo1/Brohn](https://github.com/Bransolo1/Brohn).
Licence: [MIT](../LICENSE). Start changes on your own branch and submit a pull
request. Public access lets you clone or fork; write access requires the owner
to add your GitHub account separately.

## Get oriented

The [documentation map](README.md) links the product vision, all master plans,
method references, UX specifications and remaining-work trackers.

1. Read [README](../README.md) and [STATUS](../STATUS.md) for the current product.
2. Follow [Local installation](operations/LOCAL-INSTALLATION.md). The exercised
   profile is Windows AMD64, R 4.6.1, the exact 46-package R lock, a Python
   standard-library interpreter and the compiled Windows publication guard.
   Optional scientific profiles have separate requirements and model setup.
3. Read [AGENTS](../AGENTS.md), [master architecture](MASTER-ARCHITECTURE.md),
   [build manifest](preparation/build-manifest.json) and [active sprint](sprints/02-full-platform.md).
   The 50-capability plan is the intended scope, not an enabled-feature list.
4. Read [Contributor workflow](../CONTRIBUTING.md) before modifying shared
   protocol, storage, scoring or UI contracts.

The R/Shiny researcher interface, browser participant runner, durable SQLite
workspace and supervised scientific processes form the connected application.
Use `run-local.ps1` or `scripts/run-brohn.R` to start the connected services.
`scripts/run-local.R`, `-Legacy`, and `npm run test:browser` target the old
prototype; starting that page is not starting the complete connected platform.

The repository does not contain the original developer's `../../work` tools,
R/Python environments, runtime workspaces or large QA evidence. Configure your
own explicit paths using the installation guide. Never point a test harness
at a workspace holding real studies.

## Latest accepted work

- Participant questionnaire Back/Edit, explicit review sealing and typed
  dependency clearing. Final answers feed summaries/scales once; acknowledged
  edits stay separate. Existing forward-only releases remain unchanged.
  [Researcher journey](qa/QUESTION-REVISION-RESEARCHER-JOURNEY.md): 19 checks,
  five automated accessibility scans, one real local software analysis.
- Five-profile implicit trial import/export and descriptive cohorts with
  explicit person/session linkage, repeat weighting and preserved unavailable
  results. [Cohort contract](methods/IMPLICIT-TASK-COHORT.md) records domain,
  storage, Shiny and actual worker/browser scope.
- Large questionnaire histories now use small native-run input manifests and
  complete typed analysis artifacts with bounded saved-report previews.
  [Worker acceptance](qa/QUESTIONNAIRE-ARTIFACT-WORKER.md): 27 checks and two
  successful publications. A recreated 24,090,330-byte report preserves 200
  final answers and all 400 answer commits; a separate 20,751,147-byte journal
  uses a 1,549-byte input manifest.
- [Large-report browser acceptance](qa/QUESTIONNAIRE-ARTIFACT-RESEARCHER-JOURNEY.md):
  ten checks, seven accessibility scans, exact complete JSON/CSV/artifact
  downloads and reopening. One actual synthesis reads six numeric observations
  beyond the preview and reproduces the independent mean difference of 4
  across three fictional people and visits.
- Questionnaire CSV includes exact typed `response_record_json`. Fifteen export
  and 28 UTF-8 CSV/TSV reader checks cover types, Unicode and source preservation.

These are synthetic software fixtures, not human usability studies or physical
device qualification. Historical execution records and hashes are documented;
large external evidence files are not bundled with the GitHub checkout.

## Exact unfinished checkpoint

**Explore all answers is not connected or available in the UI.** The tested
application currently provides bounded previews and complete downloads.

- `R/platform-questionnaire-index.R` and
  `tests/platform-questionnaire-index.R`: new, **unregistered** pure SQLite
  index/query implementation. The standalone synthetic suite passed 49 checks.
  It has not been exercised through an actual application worker.
- `R/platform-questionnaire-explorer.R`: new, **unregistered** storage,
  queue/publication/opener draft. It parses but has **zero storage or
  integration tests**. Its corresponding storage test file and UI module do
  not exist. No loader or worker hooks enable it.
- Read [Explorer contract](qa/QUESTIONNAIRE-COMPLETE-EXPLORER-CONTRACT.md) and
  [Storage handoff](qa/QUESTIONNAIRE-EXPLORER-STORAGE-HANDOFF.md). Review the
  unexecuted Windows path-prefix escaping and opened-handle/context checks
  before enabling anything. Memory/time supervision, cancellation, native
  publication, exact source authority and browser acceptance remain required.
- Two small participant UX refinements remain: information review should say
  “Review information”, and review progress should describe the questionnaire
  rather than showing a held global protocol cursor. They must not change
  stimulus order, questionnaire boundaries or scored timing.

Recommended next step: qualify the unregistered storage/index boundary, then
connect the complete-answer explorer and run a researcher journey. Do not turn
on the draft files merely because they parse. Broader method/device/hosting and
release gaps remain in the master architecture and build manifest.

## Check a change

After restoring the core library, list checks and run a bounded smoke test:

```powershell
& $rscript --vanilla scripts/run-checks.R --list
& $rscript --vanilla scripts/run-checks.R --test core --output C:/Brohn-QA/core-001
```

`$rscript` and the library environment are configured by the installation guide.
Choose a new external output directory for each run. Full catalog suites and
many historical browser harnesses still use developer paths, reference
libraries, generated fixtures or a prepared QA workspace. Inspect each chosen
script; a fresh clone plus the core R restore does not make every suite portable.
See [Running checks](qa/RUNNING-CHECKS.md) for that boundary.

Packaging verification on 8 September used a separate clean source clone:
the connected loader and all 109 core checks passed with the preinstalled R
library, an explicitly configured Python interpreter and a publication guard
rebuilt from that clone. This verifies source-checkout setup with prepared
dependencies; it is not a full clean-machine installation or full-suite pass.

Keep the loaded source files fixed while scientific jobs run: each published
report records its actual implementation hashes. Update STATUS, the relevant
sprint entry and CHANGELOG when handing work back. Preserve earlier failed
evidence and the distinction between component, worker and browser acceptance.
