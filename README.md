# Brohn

Brohn is an open-source, R-first workspace for consumer and psychology research:
design controlled studies, collect or import data, review traceable analyses,
and reuse study designs. It aims to make these workflows approachable for
undergraduate researchers and useful to commercial research teams.

**Development checkpoint: paused on 8 September 2026.** This repository contains
a working local application and an unfinished broader roadmap. Start with
[John's handoff](docs/HANDOFF-JOHN.md) and [STATUS.md](STATUS.md) for what was
completed, what remains, and where to resume.

## What is connected

| Workflow | Current local application |
| --- | --- |
| Design and reuse | Study/data/design libraries, control stimuli, AOIs, questionnaires with typed branching, participant-specific option assignment, sections, scales, MaxDiff, clone, templates and portable design ZIPs. |
| Collect | A separate participant application serves frozen releases, consent, questionnaires and implemented implicit/reaction-time profiles. Opt-in questionnaire answer review supports Back/Edit within an untimed assessment, dependent-answer invalidation and a final review before continuing. |
| Import and centralize | Reviewed background source import, native recording inspection, preserved multistream archives, reviewed channel preparation, and an explicit local LSL recording route. |
| Analyse | Method-specific gaze, EEG, EDA, ECG/PPG, respiration, EMG, fNIRS, audio, calibrated temperature and movement workflows. Supported inputs and prerequisites differ by profile. |
| Review and export | Pinned signal/gaze views, explicit/physiological comparisons, descriptive task cohorts with reviewed identity and repeat policies, complete artifacts, HTML/CSV/JSON exports, history and backup/restore. |
| Camera and AOIs | Separate camera consent and retention, original recording downloads, optional local face/pose/hand geometry, and assisted AOI proposals that require researcher review. |

R/Shiny provides the researcher interface. A separate browser application runs
participant studies; SQLite and content-addressed files preserve revisions and
original evidence. Supervised processes handle long-running analysis and local
recording. Facial geometry is not presented as a validated emotion or attention
score. Installed libraries do not establish compatibility with a physical device.

## Install and start

The exercised installation is **Windows AMD64 with R 4.6.1** and optional isolated
Python 3.12.10 scientific environments. Follow the
[local installation guide](docs/operations/LOCAL-INSTALLATION.md) from the
repository root. A fresh clone does **not** include the development `../../work`
directories, R libraries, Python environments, model weights or external raw
test evidence.

The guide covers three required setup steps: restore the 46-package R lock into
an explicit application library; configure a 64-bit Python interpreter for the
Windows publication helper; and build the small native publication guard using
the verified TinyCC toolchain. Keep dependencies, caches and research workspaces
outside the repository. Scientific Python profiles and models are installed
separately for the capabilities you need.

After completing those steps, adapt these example paths to your installation:

```powershell
$rscript = 'C:/Program Files/R/R-4.6.1/bin/Rscript.exe'
$applicationLibrary = 'C:/Brohn/r-library'
$env:R_LIBS_USER = $applicationLibrary
$env:BROHN_PYTHON = 'C:/Python312/python.exe'
$env:BROHN_PUBLICATION_PYTHON = 'C:/Python312/python.exe'
$env:BROHN_PUBLICATION_NATIVE_MANIFEST = 'C:/Brohn/tooling/native/publication-guard.json'

& $rscript --vanilla scripts/doctor.R --library $applicationLibrary --profiles none
if ($LASTEXITCODE -ne 0) { throw 'Brohn runtime is not ready; inspect the doctor report.' }
./run-local.ps1 -RscriptPath $rscript -LibraryPath $applicationLibrary `
  -Workspace 'C:/Brohn/workspaces/default' -Port 3838 -ParticipantPort 3840
```

Open [Brohn locally](http://127.0.0.1:3838/). The launcher supervises collection
and processing services; Ctrl+C stops its owned processes. Core study,
questionnaire, task and supported R gaze workflows do not require scientific
Python packages. The doctor can check optional profiles, models and codecs as
described in the installation guide. The historical prototype is available only
through the explicit `-Legacy` option.

This profile binds to **loopback only**. Its participant links cannot recruit
people on other computers. A production or remote deployment still requires
its own authentication, HTTPS, access controls and operational qualification.

## Evidence and current limits

The [researcher QA record](docs/qa/RESEARCHER-QA.md) separates executed journeys
from planned capabilities. Recent completed work includes answer review through
saved scale analysis, and descriptive task cohorts with explicit person/session
linkage and repeat weighting.

Large questionnaire reports retain all final answers and edit history behind
bounded previews. Their [native worker continuation](docs/qa/QUESTIONNAIRE-ARTIFACT-WORKER.md)
passed **27 checks**, with **two successful publications** across the recorded
executions. The later [researcher journey](docs/qa/QUESTIONNAIRE-ARTIFACT-RESEARCHER-JOURNEY.md)
passed **10 browser assertions and seven accessibility scans**, including
complete downloads, reopening and a real synthesis worker reading beyond the
preview. Questionnaire CSV includes exact typed `response_record_json` alongside
display cells; [UTF-8 export/import checks](docs/qa/QUESTIONNAIRE-EXPORT-INTEGRITY.md)
cover Unicode, native false/zero/text/null and malformed-input refusal.

The proposed complete in-app questionnaire explorer is **not a feature of this
checkpoint**. Its new index module is unregistered and has **49 standalone
checks**; storage acceptance is **0**, and no explorer UI is available. See its
[unfinished contract](docs/qa/QUESTIONNAIRE-COMPLETE-EXPLORER-CONTRACT.md).
Complete artifact downloads remain available through the existing report UI.

These are scoped software checks using original fixtures. They do not establish
full-platform production readiness, human usability, physical sensor accuracy,
unlimited dataset capacity or scientific qualification of every method.

## Continue from here

- [Complete documentation map](docs/README.md): product vision, architecture, UX, methods, roadmap and remaining work
- [John's handoff](docs/HANDOFF-JOHN.md), [current status](STATUS.md) and [master architecture](docs/MASTER-ARCHITECTURE.md)
- [Installation and readiness](docs/operations/LOCAL-INSTALLATION.md), [dependencies](DEPENDENCIES.md) and [backup/restore](docs/operations/BACKUP-AND-RESTORE.md)
- [Researcher QA](docs/qa/RESEARCHER-QA.md) and [selected check runner](docs/qa/RUNNING-CHECKS.md)
- [Study lifecycle](docs/product/STUDY-LIFECYCLE.md), [design portability](docs/product/DESIGN-PORTABILITY.md) and [method specifications](docs/methods/reuse/README.md)
- [Contributor workflow](CONTRIBUTING.md), [known gaps](docs/KNOWN-GAPS.md) and [change history](CHANGELOG.md)

Brohn source is provided under the [MIT license](LICENSE). Dependencies and
separately obtained models retain their own licenses. Competitor screenshots,
participant recordings, credentials and proprietary SDKs are not distributed
with this repository.
