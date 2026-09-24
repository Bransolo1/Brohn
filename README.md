# Brohn - Implicit Research Platform

Brohn is an open-source, R-first workspace for consumer and psychology research:
design controlled studies, collect or import data, review traceable analyses,
and reuse study designs. It aims to make these workflows approachable for
undergraduate researchers and useful to commercial research teams.

**Working local application; active development.** The broader platform remains
unfinished. Start with [current status](STATUS.md), the
[ordered workstream](docs/WORKSTREAM.md), [John's handoff](docs/HANDOFF-JOHN.md)
and the [master architecture](docs/MASTER-ARCHITECTURE.md). The full scope contains
50 registered capabilities across 17 work packages.

The [workflow evidence ledger](docs/qa/INTEGRATED-WORKFLOWS-20260924.md) links the
actual researcher journeys, method checks, exports and restart evidence for
enabled features. Each acceptance record states its tested scope and remaining
limits. For inspecting complete saved observations and original frames, use the
[facial and video/audio review guide](docs/operations/REVIEW-SAVED-MEDIA.md).
The [saved-results guide](docs/operations/REVIEW-SAVED-RESULTS.md) covers
Results/Explore/Evidence, paged histories and reopening original views.

## What is connected

| Workflow | Current local application |
| --- | --- |
| Design and reuse | Study/data/design libraries, control stimuli, AOIs, questionnaires with typed branching, participant-specific option assignment, sections, scales, MaxDiff, clone, templates and portable design ZIPs. |
| Collect | A separate participant application serves frozen releases, consent, questionnaires and seven implicit/reaction-time profiles, including the named Brohn response-window SC-IAT and single-target GNAT. Opt-in questionnaire answer review supports Back/Edit within an untimed assessment, dependent-answer invalidation and a final review before continuing. |
| Import and centralize | Reviewed background source import, native recording inspection, preserved multistream archives, reviewed channel preparation, and an explicit local LSL recording route. |
| Analyse | Method-specific gaze, EEG, EDA, ECG/PPG, respiration, EMG, fNIRS, audio, calibrated temperature and movement workflows. Supported inputs and prerequisites differ by profile. |
| Review and export | Pinned signal/gaze views, explicit/physiological comparisons, descriptive task cohorts with reviewed identity and repeat policies, complete artifacts, HTML/CSV/JSON exports, history and backup/restore. |
| Camera and AOIs | Separate camera consent and retention, original recording downloads, optional local face/pose/hand geometry, source-bound facial AU/native-category analysis, and assisted AOI proposals that require researcher review. |

R/Shiny provides the researcher interface. A separate browser application runs
participant studies; SQLite and content-addressed files preserve revisions and
original evidence. Supervised processes handle long-running analysis and local
recording. Facial geometry is not presented as a validated emotion or attention
score. Installed libraries do not establish compatibility with a physical device.

For Go/No-Go study design, separate deadline results, genuine withholding and
source-preserving imports, use the [GNAT guide](docs/operations/RUN-GNAT.md).
The [current checkpoint](docs/qa/PUBLICATION-GNAT-20260924.md) records this
implementation's acceptance status and scientific limits.

## Install and start

The exercised installation is **Windows AMD64 with R 4.6.1** and optional isolated
Python 3.12.10 scientific environments. Follow the
[local installation guide](docs/operations/LOCAL-INSTALLATION.md) from the
repository root. A fresh clone does **not** include the development `../../work`
directories, R libraries, Python environments, model weights or external raw
test evidence.

After installing R, 64-bit Python and the TinyCC toolchain described in the guide,
one setup command restores the pinned packages, builds protected report storage
and saves a checked configuration. Adapt these paths to your installation:

```powershell
./scripts/setup-local.ps1 -InstallationRoot 'C:/Brohn/local' `
  -RscriptPath 'C:/Program Files/R/R-4.6.1/bin/Rscript.exe' `
  -PythonPath 'C:/Python312/python.exe' `
  -CompilerPath 'C:/Brohn/tooling/tcc/tcc.exe'
./run-local.ps1 -ConfigurationPath 'C:/Brohn/local/local-installation.json'
```

Open [Brohn locally](http://127.0.0.1:3838/). The launcher supervises collection
and processing services; Ctrl+C stops its owned processes. Core study,
questionnaire, task and supported R gaze workflows do not require scientific
Python packages. The doctor can check optional profiles, models and codecs as
described in the installation guide. The historical prototype is available only
through the explicit `-Legacy` option.

Keep dependencies, caches and research workspaces outside the repository.
Scientific Python profiles and models remain separate optional installations.
The [setup evidence](docs/qa/LOCAL-SETUP-ACCEPTANCE.md) covers a fresh separate
library, failure/retry and service restart on the exercised Windows host.

This profile binds to **loopback only**. Its participant links cannot recruit
people on other computers. The separate [protected hosted profile](docs/operations/HOSTED-PROFILE.md)
has local OIDC and access-control evidence for one trusted team. Public
recruitment still needs a configured host, identity tenant and operational checks.

## Evidence and current limits

The [researcher QA record](docs/qa/RESEARCHER-QA.md) separates executed journeys
from planned capabilities. Recent completed work includes answer review through
saved scale analysis, and descriptive task cohorts with explicit person/session
linkage and repeat weighting.

The [current workflow ledger](docs/qa/INTEGRATED-WORKFLOWS-20260924.md) also covers
collection history and recovery, complete response distributions, paired-person
figures, linked signals/events, video-to-audio preparation, audio/EDA/respiration
review and exact answer-to-session navigation. Derived results retain the
original source's access rules. Each linked record states its tested scope;
the broader platform remains in active development.

Large questionnaire reports retain all final answers and edit history behind
bounded previews. Their [native worker continuation](docs/qa/QUESTIONNAIRE-ARTIFACT-WORKER.md)
passed **27 checks**, with **two successful publications** across the recorded
executions. The later [researcher journey](docs/qa/QUESTIONNAIRE-ARTIFACT-RESEARCHER-JOURNEY.md)
passed **10 browser assertions and seven accessibility scans**, including
complete downloads, reopening and a real synthesis worker reading beyond the
preview. Questionnaire CSV includes exact typed `response_record_json` alongside
display cells; [UTF-8 export/import checks](docs/qa/QUESTIONNAIRE-EXPORT-INTEGRITY.md)
cover Unicode, native false/zero/text/null and malformed-input refusal.

The complete in-app questionnaire explorer connects **Explore all answers** to
source-bound background preparation, paged Questions/Answers, complete values,
distributions and retained edit history. Read [its acceptance record](docs/qa/QUESTIONNAIRE-EXPLORER-ACCEPTANCE.md)
for the tested Windows profile, measurements and remaining boundaries. Full
artifact downloads remain available even when interactive preparation fails.

These are scoped software checks using original fixtures. They do not establish
full-platform production readiness, human usability, physical sensor accuracy,
unlimited dataset capacity or scientific qualification of every method.

## Continue from here

- [Complete documentation map](docs/README.md): product vision, architecture, UX, methods, roadmap and remaining work
- [John's handoff](docs/HANDOFF-JOHN.md), [current status](STATUS.md) and [master architecture](docs/MASTER-ARCHITECTURE.md)
- [Installation and readiness](docs/operations/LOCAL-INSTALLATION.md), [dependencies](DEPENDENCIES.md) and [backup/restore](docs/operations/BACKUP-AND-RESTORE.md)
- [Researcher QA](docs/qa/RESEARCHER-QA.md) and [selected check runner](docs/qa/RUNNING-CHECKS.md)
- [Portable connected smoke](docs/qa/CONNECTED-PORTABLE-SMOKE-ACCEPTANCE.md): study creation, participant completion, automatic reporting, exports and restart in an isolated QA workspace
- [Configured core checks](docs/qa/PORTABLE-CATALOG-ACCEPTANCE.md): seven reviewed component checks using a saved installation configuration and separate evidence directory
- [Study lifecycle](docs/product/STUDY-LIFECYCLE.md), [design portability](docs/product/DESIGN-PORTABILITY.md) and [method specifications](docs/methods/reuse/README.md)
- [Contributor workflow](CONTRIBUTING.md), [known gaps](docs/KNOWN-GAPS.md) and [change history](CHANGELOG.md)

Brohn source is provided under the [MIT license](LICENSE). Dependencies and
separately obtained models retain their own licenses. Competitor screenshots,
participant recordings, credentials and proprietary SDKs are not distributed
with this repository.
