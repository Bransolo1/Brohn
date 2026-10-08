# Controlled versions, collection and saved analysis

This guide describes the assigned-study workflow enabled in the normal application
at the 9 October checkpoint. Read [STATUS](../../STATUS.md) for current limits.
The tested route uses text/PNG stimuli and supported questionnaires. Other
collection routes keep their own capability requirements.

## Design the comparison

Create a comparison study and describe the research question. Add the original
material, then use **Add version** to create an editable copy. Choose a separate
condition when the difference is the comparison you intend to estimate. A
control/test label records that intention; it does not establish control quality
or automatically add a statistical contrast.

In Plan, **Who sees each version?** makes exposure explicit:

- Leave a stimulus outside a version group to show it to everyone. This is useful
  for a shared control, provided it suits the research design.
- Group alternatives and choose **Show all versions** for exposure to every
  member, or **Show one version** to allocate one member to each participant.
- For show-one groups, choose balanced shuffled enrollment blocks or independent
  random assignment. Complete enrollment blocks balance the complete assignments;
  incomplete blocks and dropout can leave completed groups unequal. Independent
  assignment does not promise equal group sizes.
- Review the complete assignments when combining groups. A paired comparison
  needs both relevant conditions within each assignment; a between-group design
  needs an appropriate analysis rather than treating it as paired.

Use **Save version group** and review the saved Plan before release. Shared
stimuli, group membership and allocated versions are retained with the original
protocol. Editing the draft later does not change an existing release.

Stimulus order, baseline and fixation remain separate decisions. A control is
material the person sees. A baseline is a protocol interval whose usefulness
depends on the recorded signal and the method. Neither starts a sensor by
itself. Follow the [control-design contract](../methods/CONTROL-DESIGN.md) and
the selected method's requirements; starter durations are not universal
scientific recommendations.

## Prepare participants and release

Review consent, instructions, question wording, response options, display rules
and the answer-review setting. Use Preview to check the sequence and Review to
resolve design problems before Collect. Preview does not establish hardware
timing, device compatibility or accessibility for every participant.

Assigned studies currently refuse camera collection and participant equipment
checks. Plan displays **Review participant setup** when these requirements are
saved. Open **Participant checks and recording** and explicitly turn off only
features this particular study does not need. If a check is required by the
research design, retain it and use a supported route. Brohn must not silently
discard it to make publishing succeed.

Start Brohn through the configured local launcher so the researcher interface,
participant service and processing worker are available. In Collect, release
the saved study, then open the generated participant link. The local profile
uses loopback addresses: the link is for this computer. Remote recruitment
requires the separate hosted deployment work; changing a URL alone is not that
deployment.

The participant reads consent and instructions, completes the assigned sequence
and finishes the study. Enabled answer review applies within the supported
untimed questionnaire. Changing an answer can clear dependent responses; review
and re-answer them before continuing. Controlled timed exposures must not be
replayed through questionnaire editing.

## Review the saved result

Finish retains the original completion request and queues the appropriate named
analysis. The normal worker processes it; Results opens the saved report. Review
the assigned materials, answers, timing availability and exclusions alongside
the numbers. A completed report is not proof that a device was connected or that
the research design identifies the intended construct.

Complete JSON, CSV and offline HTML downloads preserve their supported saved
content. Downloading an existing report does not rerun its calculations. Recorded
IDs may identify sessions or people; their count alone does not establish a
unique participant count. Missing timing remains missing rather than becoming a
zero-duration observation.

## Analyse saved sessions and releases

Use **Analyse saved run** from the saved session or **Analyse release** from
Results/History. The **Saved analysis** dialog shows the actual queue state and
job identity. Repeating the same action can return an existing queued or complete
analysis; the dialog explains when no new attempt was created. **Open Activity**
takes you to processing status.

For the historical failure caused by an assigned session being sent to the old
reader, **Analyse saved run** can create the correctly named analysis from the
original saved session. No participant recollection is needed. **Analysis
history** retains both job identities and the earlier failed request. The old
**Retry saved inputs** action retains its original request and method; it does
not silently upgrade that failure to a different analysis.

The saved protocol determines the analysis route. Editing today's study draft
does not change the interpretation of yesterday's collected session. Damaged,
unsupported or incompatible saved inputs must be resolved explicitly.

## Reuse and continue

Clone a study or save a template to reuse its design. **Export design** creates a
portable `.brohn-study.zip`; import it through the Studies library to create a
separate study. Controls, groups, compatible materials and evidence travel with
the design while live identities are renewed. This does not copy participants,
analysis results or the complete workspace. Use
[backup and restore](BACKUP-AND-RESTORE.md) for workspace preservation.

This checkpoint does not establish full questionnaire parity, A/V assigned
delivery, live-device qualification, scientific validity or production hosting.
The [workstream](../WORKSTREAM.md) and [master architecture](../MASTER-ARCHITECTURE.md)
retain those requirements.
