# Control stimuli and presentation design

The user requires control stimuli throughout the platform. The first executable
authoring slice supports one designated control in the existing paired A/B design.
It records intent; it does not automatically make the comparison causal.

## Implemented authoring

- Choose no designated control, A as control, or B as control. Save a rationale.
- Keep stimulus identity separate from order. A remains A even when shown second.
- Plan counterbalanced AB/BA sequences or an explicit fixed order. The preview
  keeps the same viewing duration for both images and places the liking question
  after each image, outside the viewing interval. Duration is an editable preset.
- Preserve B minus A in the draft metric. With A as control it is test minus
  control; with B as control it is control minus test. Report this direction.
- Save roles, rationale and presentation settings with the revision. Existing
  drafts without these optional fields retain their original interpretation.

No participant allocation or timed delivery is active. A sequence preview is not
an achieved counterbalance, observed exposure, randomization log or baseline.
The synthetic analysis uses fixed fictional intervals independent of the plan.

## Method requirements for later implementation

1. Match the control to the research question. Make viewing instructions, image
   display geometry, duration and response opportunity explicit. Record intended
   manipulations and relevant remaining differences; do not assume all visual
   properties must be identical when a property is itself the manipulation.
2. Add neutral/reference stimulus sets and multi-condition contrasts as a schema
   extension. Do not repurpose a missing image, missing response or numeric zero
   as a control condition. Do not require a third stimulus in a two-condition study.
3. Distinguish experimental controls from fixation cues, physiological baseline
   epochs, practice trials, attention checks and washout/rest periods. Give each
   an explicit phase, inclusion rule, timing specification and event identity.
4. Before a runner: implement persistent participant/order assignment, intended
   and observed exposure logs, retries/resumption, browser focus checks, and
   measured timing. Report order counts and exclusions; do not promise balance
   after dropout. Random shuffling alone does not guarantee equal AB/BA allocation.
5. Define method-specific templates and independent reference fixtures: eye AOI
   comparability, EEG/EDA baseline and artifact decisions, AAT response mapping,
   BIAT block/category mapping, and webcam calibration/quality. No universal
   baseline correction or implicit score should be applied across these methods.
6. Preserve pre-analysis choices and later amendments with a reason. Show planned
   versus observed deviations and avoid selecting a favorable control after results.

## Primary references and design interpretation

[PsychoPy's blocks and counterbalancing documentation](https://psychopy.org/builder/blocksCounterbalance.html)
separates stimulus/block identity from explicitly controlled presentation order
and illustrates different orders for participant groups. Its
[randomization workshop](https://workshops.psychopy.org/3days/day3/builder_parallel/customRandomisation.html)
shows fixed and randomized trial positions within a conditions-driven sequence.
Accessed 2026-09-05. These support the ordering model; they do not qualify this
platform's methods or prescribe the five-second starting preset. The requirements
above are implementation decisions for the user's brief, with method qualification
still required before real-data collection and interpretation.
