# Remaining work at the paused checkpoint

Updated **8 September 2026**. Development is paused at the owner's request for
the public source handoff. Read [John's handoff](HANDOFF-JOHN.md) and
[current status](../STATUS.md) before resuming. The
[master architecture](MASTER-ARCHITECTURE.md),
[17-package manifest](preparation/build-manifest.json) and
[50-capability register](preparation/capability-register.json) retain the full
intended scope; they are not lists of enabled or qualified features.

The connected application already includes durable study/data/design libraries,
participant delivery on the local computer, historical reports, clone/templates,
portable design import/export, supervised analyses and backup/restore workflows.
The [README](../README.md) describes that current surface. Older preparation
records describing only the 01A–01L prototype are historical.

## Immediate continuation

- **Complete-answer explorer:** the existing report UI has bounded previews and
  complete downloads. `R/platform-questionnaire-index.R` is unregistered and has
  **49 standalone synthetic checks**. `R/platform-questionnaire-explorer.R` is
  an unregistered, parse-only storage draft with **zero storage or integration
  tests**. There is no explorer UI or worker registration. Qualify storage,
  ownership, resource limits, cancellation and publication before connecting it;
  then exercise the complete researcher journey. Review the unexecuted Windows
  path-prefix escaping and opened-handle/context checks recorded in the
  [storage handoff](qa/QUESTIONNAIRE-EXPLORER-STORAGE-HANDOFF.md) and
  [explorer contract](qa/QUESTIONNAIRE-COMPLETE-EXPLORER-CONTRACT.md).
- **Participant review wording:** replace the information row's “Edit answer”
  with “Review information” and make review progress describe the questionnaire.
  Preserve protocol order, assessment boundaries and scored timing.
- **Remaining publication paths:** manager-owned acquisition preservation and
  legacy/direct import callers still need their own qualified ownership paths.
  Continue the [publication transaction plan](operations/PUBLICATION-TRANSACTIONS.md).
  Existing large-file checks have declared limits; they do not establish
  unlimited capacity or every combination of concurrent workloads.

## Broader product and research work

- **Method coverage:** five implicit/reaction-time profiles and their source-bound
  import/cohort workflows are connected. Additional SC-IAT, GNAT, priming, AMP,
  cognitive and movement procedures retain distinct implementation and reference
  requirements. Broader neural, physiology, gaze/AOI, choice and multimodal
  capabilities also retain package-specific acceptance work. MaxDiff does not
  complete every conjoint/choice design, and an installed scientific library does
  not enable every recipe. Use the capability register and
  [method reuse specifications](methods/reuse/README.md) for exact scope.
- **Named devices and timing:** the local LSL route and imported-data workflows
  have software evidence. Supported Tobii/EEG/EDA/response-device configurations
  still require the actual devices, entitled SDKs, calibration, physical onset
  and synchronization measurements, and failure-recovery evidence. Wearable,
  scene/world/VR coordinates and naturalistic extensions remain BWP16 work.
- **Webcam and interpretation:** consented capture and optional local
  face/pose/hand geometry are connected. Entitled facial-expression/AU provider
  integration, calibrated webcam gaze and webcam pulse/respiration each need
  their own implementation and reference evidence. Geometry is not an enabled
  or validated universal emotion/attention score. Model/provider versions and
  redistribution rights remain specific to the chosen route.
- **Hosted collection and collaboration:** local participant links bind to
  loopback. Remote recruitment needs a configured HTTPS host, researcher
  authentication, project isolation, access/expiry/revocation policies,
  invitation/wave handling, monitoring and restore qualification. Controlled
  report sharing and full research-operations journeys remain separate from
  publishing source to GitHub. See the [study lifecycle](product/STUDY-LIFECYCLE.md).
- **Installation and repeatable QA:** the exercised setup is a particular
  Windows environment. A supported clean-machine installer and portable execution
  of the full test catalog remain work. The checkout excludes development tools,
  research workspaces, model weights and large external fixtures. Follow
  [local installation](operations/LOCAL-INSTALLATION.md), including the required
  Windows publication guard, and inspect the chosen suite's dependencies in
  [running checks](qa/RUNNING-CHECKS.md). A core smoke test is not the full catalog.
- **Human usability and accessibility:** automated researcher journeys and
  accessibility scans cover declared application slices. Undergraduate task
  observations, manual assistive-technology testing, comprehension and measured
  action/time targets remain outstanding. Evaluate the
  [unified experience](product/UNIFIED-EXPERIENCE.md) across the complete enabled
  workflow; a successful synthetic journey does not establish human usability.

The [active sprint record](sprints/02-full-platform.md) and
[researcher QA ledger](qa/RESEARCHER-QA.md) distinguish component, worker and
browser evidence. Finish and record each remaining acceptance gate before
changing its support claim. The repository destination and source licence are
now selected: Bransolo1/Brohn and [MIT](../LICENSE); third-party terms remain
documented separately in [the notices](../THIRD-PARTY-NOTICES.md).
