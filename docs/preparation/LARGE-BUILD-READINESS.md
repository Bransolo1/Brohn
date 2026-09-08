# Entry point for the large Brohn build

Prepared 2026-09-08. **The holistic implementation plan and local development
toolkit are ready for the next build. Product integration is still to be done.**
The [master architecture](../MASTER-ARCHITECTURE.md) is authoritative; older
architecture prose is background detail where consistent with it.

## Read in this order

1. `STATUS.md` and [master architecture](../MASTER-ARCHITECTURE.md).
2. [Build manifest](build-manifest.json): 17 work packages, dependency graph,
   capability ownership, acceptance criteria and current planned status.
3. [Capability register](capability-register.json) and [human-readable scope](HOLISTIC-CAPABILITIES.md):
   50 capabilities across 28 families. All have an implementation owner.
4. [Astra implementation brief](ASTRA-BUILD-BRIEF.md),
   [unified experience](../product/UNIFIED-EXPERIENCE.md),
   [34 planned journey evaluations](../product/journey-acceptance.json),
   [brand system](../brand/BRAND-SYSTEM.md) and
   [introduction/launch plan](../product/INTRODUCTION-AND-LAUNCH.md).
5. Relevant [method specifications](../methods/reuse/README.md),
   [procedure templates](PROTOCOL-TEMPLATES.md) and tool documents below.
6. Existing code/contracts for that work package, rather than reloading the entire archive.

The 238-ticket research backlog remains unchanged. The machine-readable build
manifest is the execution-level map and must accumulate actual evidence as work
is delivered. Core/extension/device-specific tiers retain the entire scope;
they are not a completion claim or a hidden deletion of advanced capabilities.

## Prepared toolkit and evidence

| Pack | Installed/downloaded | New reference assertions |
|---|---|---:|
| [Acquisition and extended neuroscience](ACQUISITION-TOOLING.md) | 54 Python packages: BrainFlow, LSL, XDF, Arrow/DuckDB, BIDS/SNIRF, MNE-Connectivity/MNE-NIRS | 27 |
| [R platform and statistics](PLATFORM-TOOLING.md) | 66 R packages; all 66 Windows binaries externally cached and hashed; DB/storage, processx/targets/crew, lme4/emmeans/effectsize/psych | 22 |
| [Survey and task execution](PLATFORM-TOOLING.md) | 26 JS packages, SurveyJS 2.5.41 and 15 jsPsych plugins | 29 |
| [Vision and audio](MEDIA-TOOLING.md) | 43 Python packages and six official model artifacts; face/pose/hand, object proposals, optical flow, acoustics/VAD | 17 |
| [Compatible assisted segmentation](SEGMENTATION-TOOLING.md) | Separate 26-package MediaPipe 0.10.21 environment and matching official MagicTouch v1 model | 6 |

**101 new passing assertions**, alongside the earlier **81 method references**.
Counts mix analytic, synthetic, upstream replay, file/contract and model smoke
evidence; they do not represent 182 independently validated methods. The media
result retains the failed v1.0.1 Windows segmentation attempt; the separately
tested legacy route resolves the build dependency. No participant recording,
physical device validation or new production UI was claimed.

Existing R/Shiny app dependencies and the earlier methods environment stayed
unchanged. The new environments live under `../../work`; exact pins and commands
are in the tool documents. Packages/model bytes are downloaded locally; not every
Python wheel is separately mirrored for offline installation on a new machine.
No commercial SDK, paid endpoint or private dataset was fetched.

## Product and visual preparation

The [full study lifecycle](../product/STUDY-LIFECYCLE.md) now specifies historical
study/data/design libraries, actual storage, curation, participant delivery and
enrollment, closure, sharing, archive and recovery. [Design portability](../product/DESIGN-PORTABILITY.md)
adds template save, clone and `.brohn-study.zip` export/import. UX-J19–UX-J34
extend the original 18 cases into **15 operational lifecycle areas**. The existing
17 packages own these routes; the hosted delivery gate records its prerequisites.
Current local persistence is not yet this catalog or deployment service.

The unified UX maps every capability once into **13 shared card families** and
defines **34 planned, unmeasured whole-journey scenarios**. It connects sensor
setup, controls, baselines, implicit task blocks, questionnaire referents,
automatic analysis, partial-data recovery and report comprehension through the
same five stages. BWP15 must turn that contract into observed application evidence.

The [brand preview](../brand/preview.html) and [asset manifest](../../www/brand/asset-manifest.json)
include an original folded-B logo, **32 icons**, soft graphite/mint/lavender
tokens, decorative artwork and a locally bundled licensed font. The
[preview verification](../brand/verification.json) records **31 passing colour
combinations**, zero automated accessibility violations at desktop and narrow
viewports, and reflow/reduced-motion checks. These are design-preview results,
separate from the 101 tool assertions and from full-product accessibility.
The production interface has not been rethemed by this preparation.

The [launch plan](../product/INTRODUCTION-AND-LAUNCH.md) supplies positioning,
preview-stage copy, a sample-to-own-study onboarding path, a demonstration
storyboard and staged release criteria. The [Astra brief](ASTRA-BUILD-BRIEF.md)
supplies the first integration fixtures, focused agent packets and a build
handoff prompt. Neither document represents a published launch or user trial.

## Concrete decisions settled

- Reuse established engines with R-owned recipes; R-to-Python process requests
  preserve large tick strings, explicit nulls and units.
- SQLite/transaction examples, worker execution, cache behavior and typed file
  interchange are exercised. Build the durable lease/fencing/publication layer
  around them; do not mistake these probes for a completed job service.
- SurveyJS Form Library and jsPsych survey share a tested compatible version.
  Build the accessible authoring UI in Brohn; the paid Creator is not bundled.
- MNE-NIRS and SNIRF support are installed. Select short-channel regressors by
  declared wavelength/geometry policy; the default helper needs adapter checks.
- Use the working older MagicTouch worker for assisted masks, with its actual
  0-foreground/255-background encoding. Latest package availability is not a
  sufficient compatibility test.
- Keep condition/baseline/control definitions and method-specific scoring
  explicit; the new protocol catalogue does not invent a single shared score
  for all implicit tasks.
- Keep researcher theming separate from frozen participant appearance, luminance,
  timing and baselines. OS/theme/accessibility preferences cannot silently change
  the experimental task; use explicit accommodation profiles where needed.

## Start and verify the next run

Run `python scripts/readiness/check-plan.py` from the repository root. It checks
the capability-to-work-package map, dependency cycles, required documents,
recorded result states and external tool/model presence. It also checks all
50 capabilities against the shared UX surfaces, the 18 declared/unmeasured
journeys, brand asset inventory and font hash, 31 recorded contrast checks,
two preview viewports and the new document links. It writes a compact readiness
snapshot. These manifest/evidence checks are separate from the 101 new tool
assertions and are not a substitute for rerunning changed numerical or browser code.

Begin BWP01/BWP02 and freeze one shared integration fixture before parallel
changes. Then compile/execute a full controlled study and linked questionnaire,
seal its recordings, run an analysis job and reopen the report after restart.
Expand method packs against that same contract. Use the manifest's acceptance
criteria and retain failure/correction evidence at each checkpoint.

Remaining external inputs are scoped: a named physical rig for live-device
support, entitled provider/model and exact reference response for native AU or
expression scores, source-bound scorer/materials for newly activated task
profiles, observed undergraduate evaluations, and repository/licence choices
before publication. They do not prevent building and testing the shared platform
or the established imported-data/reference workflows.
