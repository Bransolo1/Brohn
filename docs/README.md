# Brohn documentation map

This is the map for John and future contributors, updated for the
[25 September 2026 results and history checkpoint](qa/PUBLICATION-RESULTS-HISTORY-20260925.md).
Development resumed at the owner's request after the September 24 checkpoint; see the
[current workstream and next steps](WORKSTREAM.md). The intended platform is broader than the
working local application. Read current status and evidence alongside the architecture.

| What you need | Start here |
| --- | --- |
| What we are building and why | [Master architecture](MASTER-ARCHITECTURE.md): an accessible R-first research workspace with controlled studies, multimodal data and traceable automated analysis. |
| What works now and where to resume | [Current status](../STATUS.md), [John's handoff](HANDOFF-JOHN.md) and [remaining work](KNOWN-GAPS.md). |
| Implementation order and dependencies | [Build manifest](preparation/build-manifest.json), [delivery guide](ROADMAP.md) and [current sprint checklist](sprints/02-full-platform.md). |
| Complete intended measure coverage | [Holistic scope](preparation/HOLISTIC-CAPABILITIES.md) and [50-capability register](preparation/capability-register.json). |
| One accessible researcher experience | [Unified experience](product/UNIFIED-EXPERIENCE.md), [study lifecycle](product/STUDY-LIFECYCLE.md) and [planned journey acceptance](product/journey-acceptance.json). |
| Historical studies, reuse and design exchange | [Study lifecycle](product/STUDY-LIFECYCLE.md), [cloning/templates/portable designs](product/DESIGN-PORTABILITY.md) and [backup/restore](operations/BACKUP-AND-RESTORE.md). |
| Questionnaire and experimental design | [Question flow](methods/QUESTION-FLOW-BUILDER.md), [sections](methods/QUESTIONNAIRE-SECTIONS.md), [scales](methods/QUESTIONNAIRE-SCALES.md), [controls](methods/CONTROL-DESIGN.md) and [protocol snapshots](methods/PROTOCOL-SNAPSHOTS.md). |
| Scientific methods and reusable implementations | [Method references](methods/reuse/README.md), [analysis plans](methods/DECLARATIVE-ANALYSIS-PLANS.md) and [multimodal reports](methods/MULTIMODAL-REPORTS.md). |
| Design and run the named Brohn Go/No-Go procedure | [GNAT researcher guide](operations/RUN-GNAT.md), [frozen procedure](methods/GNAT-BROHN-PROCEDURE.md) and [connected qualification](qa/GNAT-RESEARCHER-ACCEPTANCE.md). |
| Review saved results and history | [Results, exploration and history guide](operations/REVIEW-SAVED-RESULTS.md), [architecture](architecture/RESULTS-AND-SAVED-HISTORY.md) and [joined checkpoint](qa/PUBLICATION-RESULTS-HISTORY-20260925.md). |
| Inspect the original evidence behind media results | [Saved facial and video/audio review](operations/REVIEW-SAVED-MEDIA.md), including exact frames, full numerical exports and saved reopening. |
| Brand, onboarding and launch | [Brand system](brand/BRAND-SYSTEM.md) and [introduction plan](product/INTRODUCTION-AND-LAUNCH.md). |
| Installation and contribution | [Installation](operations/LOCAL-INSTALLATION.md), [dependencies](../DEPENDENCIES.md), [contribution guide](../CONTRIBUTING.md) and [agent instructions](../AGENTS.md). |
| What has actually been checked | [Researcher QA](qa/RESEARCHER-QA.md), [running checks](qa/RUNNING-CHECKS.md), [configured core subset](qa/PORTABLE-CATALOG-ACCEPTANCE.md), [portable connected smoke](qa/CONNECTED-PORTABLE-SMOKE-ACCEPTANCE.md) and the linked method/journey evidence. |
| Planned alignment across separate recordings | [Reviewed two-event clock mapping](architecture/REVIEWED-CLOCK-ALIGNMENT.md), with exact source/identity/epoch contracts; not an enabled synchronization claim. |
| Original strategy and competitor research | [Planning archive](planning/INDEX.md), including the [strategy](planning/STRATEGY.md), [competitor review](planning/COMPETITOR-REVIEW.md), specialist reviews and [238-ticket backlog](planning/IMPLEMENTATION-BACKLOG.csv). |

The master architecture and current build manifest govern implementation. STATUS,
the current sprint and scoped QA records establish delivered behavior. The
planning archive preserves earlier research and candidate tickets; its older
defaults and completion language do not override the current checkpoint.

Original competitor media and large local test evidence are not redistributed
in this source repository. The planning documents retain source references and
evidence descriptions; the repository includes Brohn's own visual assets.
