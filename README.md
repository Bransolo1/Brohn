# Brohn — Implicit Research Platform

Brohn is an open-source, R-first workspace for consumer and psychology research: design controlled studies, collect or import data, review traceable analyses, and reuse study designs. It aims to make these workflows approachable for undergraduate researchers and useful to commercial research teams.

**Working local application; active development.** The intended platform remains unfinished, with 50 registered capabilities across 17 work packages. Implemented software, an accepted research workflow and a scientifically qualified measurement are different milestones.

- Get running: [installation below](#install-and-start) and [local installation guide](docs/operations/LOCAL-INSTALLATION.md).
- See what passed: [source and workflow evidence map](docs/qa/SOURCE-EVIDENCE-MAP-20261009.md).
- Continue development: [status](STATUS.md), [John's handoff](docs/HANDOFF-JOHN.md), [workstream](docs/WORKSTREAM.md) and [master architecture](docs/MASTER-ARCHITECTURE.md).

## Current checkpoint

**9 October 2026: assigned study delivery is connected in the normal application.** Design version groups and shared controls, release the study, collect supported participant responses, process the completed session automatically and review the saved report. The final relocated Git checkout passed the real launcher/Release-button/participant/worker/report journey, 38 document-access checks and independent complete-data inspection. Separate researcher checks cover reuse, manual analysis/recovery and desktop/phone report cards. See the [evidence map](docs/qa/SOURCE-EVIDENCE-MAP-20261009.md) for source-specific limits.

The [assigned-study guide](docs/operations/ASSIGNED-STUDY-WORKFLOW.md) explains **Who sees each version?**, shared controls, participant setup, answer review, **Analyse saved run**, **Analyse release**, clone/templates and design exchange. This scoped route uses supported text/PNG stimuli and questionnaires. Assigned A/V delivery, camera/equipment collection and other study formats retain separate gates. The older ordinary authoring route schedules each listed stimulus; do not infer between-group assignment from a version label alone.

**Saved cardiac packaging is implemented with native qualification.** It assembles supported saved ECG detected-RR and PPG PRV findings, including required parent/exclusion evidence, without repeating scientific processing. Complete included analytical evidence is distinct from original raw recordings. The final cardiac researcher-browser/cold-reopen journey and performance remain open: a measured saved-history open took about 80 seconds. Read the [researcher guide](docs/operations/SHARE-SAVED-CARDIAC-FINDINGS.md), [contract](docs/architecture/SAVED-CARDIAC-REPORT-PACKAGES.md) and [scoped acceptance](docs/qa/CARDIAC-EVIDENCE-ACCEPTANCE.md).

**Current method guidance is screened, not scientific approval.** The selected registry contains 24 bounded claims and 31 scholarly source records. Its Tasks/Data panels show assumptions and limits; they do not automatically freeze citations into every study or result. See [references inside Brohn](docs/research/METHOD-EVIDENCE-RUNTIME.md).

## Implemented workflows

Support depends on the selected profile, inputs and prerequisites; the [documentation map](docs/README.md) links their contracts and evidence.

| Area | Available implementation and guides |
| --- | --- |
| Design and reuse | Study/data/design libraries, control stimuli, AOIs, typed questionnaire branching, sections, scales, MaxDiff, clones, templates and portable design ZIPs. [Study lifecycle](docs/product/STUDY-LIFECYCLE.md). |
| Collect | Separate participant application with frozen releases, consent, questionnaires and seven implicit/reaction-time profiles. Opt-in answer review supports Back/Edit within an untimed assessment. [Named Brohn GNAT guide](docs/operations/RUN-GNAT.md). |
| Import and centralize | Reviewed background imports, preserved multistream archives, channel preparation and an explicit local LSL recording route. [Installation and optional profiles](docs/operations/LOCAL-INSTALLATION.md). |
| Analyse | Method-specific gaze, EEG, EDA, ECG/PPG, respiration, EMG, fNIRS, audio, calibrated temperature and movement workflows. [Methods and limits](docs/methods/reuse/README.md). |
| Review and share | Saved results/history, complete artifacts, HTML/CSV/JSON exports and supported saved-findings packages. [Review results](docs/operations/REVIEW-SAVED-RESULTS.md) and [share findings](docs/operations/SHARE-SAVED-FINDINGS.md). |
| Camera and AOIs | Separate consent/retention, original recordings, optional local geometry, source-bound facial analysis and assisted AOI proposals requiring review. [Saved-media guide](docs/operations/REVIEW-SAVED-MEDIA.md). |

R/Shiny provides the researcher interface. Browser studies, supervised analysis/recording processes, SQLite revisions and content-addressed files preserve original evidence. Facial geometry is not a validated emotion/attention score. Detected ECG RR is not confirmed NN-HRV, and PPG PRV is not interchangeable with HRV. Installed libraries do not establish physical-device compatibility or synchronization.

Earlier [EDA](docs/qa/EDA-REPORT-PACKAGE-ACCEPTANCE.md), [exact-constant EDA](docs/qa/EDA-CONSTANT-SIGNAL-ACCEPTANCE.md), [task](docs/qa/TASK-REPORT-PACKAGE-ACCEPTANCE.md) and [choice](docs/qa/CHOICE-REPORT-PACKAGE-ACCEPTANCE.md) package acceptances retain their own tested scope. Complete questionnaire exports preserve typed responses and history behind bounded previews; see [questionnaire export integrity](docs/qa/QUESTIONNAIRE-EXPORT-INTEGRITY.md).

## Install and start

The exercised installation is **Windows AMD64 with R 4.6.1**, with optional isolated Python 3.12.10 scientific environments. Follow the [local installation guide](docs/operations/LOCAL-INSTALLATION.md) from the repository root. A clone excludes development workspaces, installed libraries, model weights and external raw test evidence.

After installing R, 64-bit Python and the documented TinyCC toolchain, adapt these paths:

```powershell
./scripts/setup-local.ps1 -InstallationRoot 'C:/Brohn/local' `
  -RscriptPath 'C:/Program Files/R/R-4.6.1/bin/Rscript.exe' `
  -PythonPath 'C:/Python312/python.exe' `
  -CompilerPath 'C:/Brohn/tooling/tcc/tcc.exe'
./run-local.ps1 -ConfigurationPath 'C:/Brohn/local/local-installation.json'
```

Open [Brohn locally](http://127.0.0.1:3838/). The launcher supervises collection and processing; Ctrl+C stops its owned services. Keep dependencies, caches and research workspaces outside the repository. Scientific Python profiles/models are separate optional installations; use the installation guide's doctor checks. The historical prototype requires the explicit `-Legacy` option.

This profile binds to **loopback only**: its participant links cannot recruit people on other computers. The [protected hosted profile](docs/operations/HOSTED-PROFILE.md) has separate local access-control evidence; public recruitment still requires configured hosting, identity and operational checks.

## Develop and qualify

Use [John's handoff](docs/HANDOFF-JOHN.md) and the [ordered workstream](docs/WORKSTREAM.md). Start with [running checks](docs/qa/RUNNING-CHECKS.md), the [contributor guide](CONTRIBUTING.md) and the [evidence map](docs/qa/SOURCE-EVIDENCE-MAP-20261009.md). The qualified repository-owned connected test is documented in [tests/connected](tests/connected/README.md); run it with your own explicit installation paths and a fresh disposable workspace.

Full questionnaire parity, broader study formats, responsive large-data workflows, A/V integration, physical-device agreement, scientific appraisal and production hosting remain open. Automated accessibility scans and scoped original-data checks do not establish whole-platform readiness or usability for every researcher.

Source is provided under the [MIT license](LICENSE). Dependencies and separately obtained models retain their own licenses. Competitor screenshots, participant recordings, credentials and proprietary SDKs are not distributed with this repository.
