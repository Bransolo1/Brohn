# One Brohn study, from question to evidence

Build one guided research studio where a first-time psychologist can combine
measures, recover confidently and explain the finished study without assembling
separate device dashboards. This specification applies the
innovation-first-product-psychology review to the
[master architecture](../MASTER-ARCHITECTURE.md). It preserves the full scope in
the [capability register](../preparation/capability-register.json); it is an
implementation and evaluation contract, not a report of achieved usability.

## The flagship experience

The five stages live inside the wider [study lifecycle](STUDY-LIFECYCLE.md).
Home, searchable Studies, Data library and Design library provide creation,
curation and historical access. A study overview links its data, deployments,
reports and revision history. New study offers blank, template, clone and import
design routes. [Save, clone and portable design exchange](DESIGN-PORTABILITY.md)
preserve the study definition with fresh participant/allocation state.

Collect includes lab/hosted delivery, participant entry and enrollment, invitations,
waves, progress and closure; Results includes frozen history and controlled sharing.
Archive, reanalyse and verified backup/restore continue the journey after collection.
These routes reuse the same cards, commands and records; they are not implemented
merely by adding navigation items.

“Compare two creative designs” starts with a prepared recipe and a clear question.
The researcher supplies test/control materials, semantic AOIs and a collection
plan. Eye tracking, EEG and EDA record the **same passive-viewing exposures**;
selected webcam outputs reuse one consented, timestamped camera capture. Linked
liking questions follow their intended exposures. BIAT and physical push/pull AAT
run as **separate sequential task blocks**, with their own instructions, practice,
mapping, trial eligibility and analysis. The recipe specifies block order and
counterbalancing; it does not casually append tasks to create order effects.

The shared timeline contains acclimatization, sensor calibration, physiological
baseline, fixation cues, passive exposure, question/response periods, task practice,
scored task blocks and rest where the selected profiles require them. A control
image remains a comparator; it never substitutes for baseline. Recording may
continue across blocks, while recipe-specific masks determine which signals enter
which analysis. AAT movement and question answering remain visible context rather
than contaminating a “passive response” average.

All outcomes reach one report: AOI allocation, named EEG and EDA features,
association/action contrasts and explicit liking, with independent coverage and
uncertainty. Brohn explains where they agree or differ using the declared model.
The researcher leaves able to say what was compared, what was measured and what
remains uncertain. This earned independence is the product's psychological promise.

## Every measure uses the same interaction contract

Plan presents measure cards grouped by the research question. Each card has:
**what it contributes; capture/import source; selected profile; phases used;
readiness; expected report output; one next action**. Required/optional status
comes from the recipe. “Available through import” and “Choose a supported device”
are actionable states. Adding an extension never creates a blank dashboard.

| Card family | Connected capabilities and setup differences |
| --- | --- |
| Eye movement | Screen/webcam gaze, ocular events, pupil/blinks, AOIs and glasses/VR; calibration, independent validation and coordinate mapping. |
| Brain activity | EEG/ERP/spectrum/time-frequency, frequency tagging, fNIRS and advanced neural recipes; channels, geometry, reference and protocol-specific timing. |
| Skin response | EDA and temperature; placement, units, settling/baseline and ambient context. |
| Heart and circulation | ECG/HRV, PPG/PRV, supported hemodynamics and cardiorespiratory coupling; channel/site, beat quality and compatible time windows. |
| Breathing | Belt/airflow cycles and response summaries; source type and calibrated/proxy units. |
| Muscle and ocular electrical activity | Surface/facial/startle EMG and EOG; electrode map, normalization and probe timing. |
| Movement | IMU/force/location, visible pose and pointer/joystick trajectories; axis/geometry, calibration and supported input profile. |
| Camera observations | Facial/AU outputs and camera physiology extensions; shared camera, capture quality and named model/output profile. |
| Voice | Speech timing/acoustics and selected transcript route; microphone, gain, language/model and voiced support. |
| Association and action | IAT variants, GNAT, priming, AMP, timed association, AAT and relational extensions; profile-specific instructions and practice. |
| Behavioural tasks | Attention, interference/inhibition, learning and decision profiles; task-specific response mapping, timing and outcomes. |
| Explicit responses | Questions, branching, scales, MaxDiff/conjoint; referents, anchors, design and scoring. |
| Shared study services | Protocol, capture/import, multimodal models, reports and research operations; one project/run lifecycle. |

The [acceptance registry](journey-acceptance.json) assigns all 50 capability IDs to
these surfaces. A device reused by several cards is configured once. Alternative
live/import routes share output contracts but retain their own support status.

Collect consolidates readiness into **“Ready” or “N actions before starting”**.
The next action opens one inline setup panel and returns to the summary. The same
summary names unavailable optional measures and consequences of proceeding.
During collection, one participant timeline aligns stimulus, responses, video and
signals; a keyboard-selectable event table offers the same navigation. Individual
traces are expandable. Colour supplements labels and patterns.

## Five stages, one next action

| Stage | Main action | Automatic work and backend relationship | Essential states and focus |
| --- | --- | --- | --- |
| **Plan** | **Prepare study** | Save draft; validate profile/design; bind assets, controls and semantic targets; propose AOIs; compile revision and allocation plan. | Empty: sample/template route. Loading: named preparation step. Error: linked field summary. Stale: show affected revision. Focus moves to heading after navigation, first linked error after failed submission. |
| **Questions** | **Preview participant flow** | Translate safe canonical question graph; check branch/required rules; preserve item/option IDs and exposure referents; render actual instructions/questions. | Empty optional questionnaire: explain and allow forward progress. Loading: preview status. Error: branch explanation and edit link. Changed answer: show consequent current-answer change while retaining history. Preview exit restores launching control. |
| **Collect** | **Start participant** | Run readiness, reserve allocation transactionally, create run/presentation IDs, preload assets, start approved streams and journal events; ACK durable saves. | Waiting: prerequisites and next fix. Running: phase plus persistence state. Partial: affected sensor only. Interrupted: saved boundary and permitted recovery. Start is enabled only for satisfied required capabilities. Focus remains on operator action; status updates do not steal it. |
| **Review** | **Apply review and continue** when decisions exist; otherwise **View results** | Sealing/import triggers normalization, clock/geometry mapping, masks, events/epochs, AOIs and recipe jobs. Group exceptions by cause; preview the results affected by a decision. | Empty queue: automatically ready to view. Loading: real job phase/count. Error: retry only failed descendants. Partial: usable modalities remain visible. Undo restores prior decision revision; focus returns to the reviewed row or next exception. |
| **Results** | **Download report** | Publish versioned participant/condition features, declared contrasts, coverage and accessible HTML/tables plus reproducible bundle. | Running: retained previous report labelled older. Empty: no eligible result with reasons. Partial: available outcomes plus missing support. Complete: frozen cohort/revision. Export status announces completion without relocating focus. |

Participant finish seals that run and starts its eligible processing. The operator
then sees **Next participant**. **Finish collection** is a separate study-level
action; it freezes the cohort and produces the agreed final analysis. A partial
run can be sealed, preserved and assessed without being labelled completed.

## Automation that makes recovery easy

Observation: unrelated technical failures can feel like a failed study. Mechanism:
an undifferentiated red screen removes agency. Build response: every issue names
the affected measure, preserved observations and one repair. Proof: seed an EDA
disconnect; the operator identifies the loss and keeps valid eye/EEG/liking data.
Optional sensor failure follows the frozen continue policy. Required loss invokes
its declared safe stop/pause boundary. An interrupted timed trial is never
silently resumed or replayed as the original presentation.

Observation: “automatic” can encourage uncritical acceptance. Mechanism: users
mistake polish for certainty. Build response: proposals and processed outputs have
plain status labels, small evidence previews and reversible corrections. Proof:
include one plausible wrong AOI; measure detection, correction time and downstream
metric agreement. Gaze gaps that could hide a first fixation must follow the
recipe's observability policy, rather than becoming misleading nonhits.

Observation: a collection of impressive scores can obscure the comparison.
Mechanism: novices substitute a headline for understanding. Build response: each
result answers “Compared with what?”, “How much usable data?” and “What does this
measure mean?”; primary outcomes lead, supporting outcomes expand. Proof: blinded
recipient questions test comparison, baseline, signal/construct distinction and
missingness. No forced composite is needed to make the report feel complete.

Autosave, local buffering and background jobs are visible only through useful
messages: “Saved”, “Saving locally”, “Waiting to synchronize”, or “Saved through
trial 12”. These labels require actual persistence evidence. Job cancellation,
crashes and stale attempts preserve committed artifacts and show retry from the
last valid dependency; progress never invents percentages. Import ambiguity opens
one mapping panel with source units/clocks and affected outputs, preserving files.

## Accessible operation and participant experience

Provide keyboard equivalents for selecting/reordering cards, flow editing,
ranking, AOI geometry and timeline navigation. Modal panels trap focus only while
open, expose a labelled close action and return focus to their launcher. Validation
focuses an error summary whose links target the field; save/progress uses polite
announcements, while a critical acquisition stop has a concise urgent announcement.
No continuous sample-rate speech or automatic focus jumping.

At 320 CSS pixels/400% zoom, the researcher shell becomes one column. Matrices
have item-by-item alternatives; plots have labelled tables; wide scientific tables
may scroll inside a labelled region without forcing whole-page horizontal scroll.
Reduced-motion settings remove decorative transitions and animated status effects.
They must not silently alter a method's stimulus motion, timing or response demands.
If a participant needs a changed timed/input protocol, select its accommodation
profile explicitly, retain that configuration and explain any separate analysis.

Keyboard/screen-reader/zoom access to authoring and reporting is a universal
requirement. Measurement equivalence of a changed participant task is a distinct,
explicit profile decision. Both deserve a clear route through the same interface.

## Targets, evidence and graduation

All targets below are **proposed, unmeasured**. Count clicks/taps/command activations,
including file chooser selections and confirmations. Record typing, focus moves,
setup, consent, sensor fitting, calibration, collection and exceptions separately;
never hide them from total elapsed time. Pair efficiency with unaided completion
and correct interpretation, reporting distributions and raw counts.

| Journey | Initial target |
| --- | --- |
| Prepared fictional sample | At most 5 activations, zero scientific decisions, explained report within 10 minutes. |
| Prepared simple eye-plus-liking study | At most 12 activations and 4 substantive design decisions. |
| Prepared multimodal flagship, saved station profile | At most 18 authoring activations and 6 substantive decisions; active software setup within 15 minutes, separate physical/setup totals. |
| Next participant on ready station | At most 4 operator activations; no repeated device mapping or analysis setup. |
| Recover one optional sensor failure | Operator identifies affected data and a permitted next action within 60 seconds; no unrelated data loss. |
| Report understanding | At least 80% of novices answer all four comparison/measure/coverage/uncertainty questions correctly; also report each question and assistance. |

Build now: shared cards, phase preview, truthful states, accessible controls and
linked reports. Instrument immediately: actions, unaided recovery, misconception
checks and automation correction effort. Graduate named live configurations and
stronger speed/competence claims with observed evidence. The visible destination
stays the full multimodal journey. Reusable recipes, reference fixtures and
recoverable histories make this system harder to copy than its attractive screens.

Evaluation uses the 34 whole-journey scenarios in the acceptance registry;
browser automation supplements observed novice and assistive-technology sessions.
Neither screenshots nor scanner passes alone establish accessible completion.
Context: [earlier UX review](../preparation/UX-READINESS.md),
[archived UX plan](../planning/UX-AND-ROADMAP.md) and
[archived UX team review](../planning/UX-TEAM-REVIEW.md).
