# Academic evidence and consumer-research method contract

Owner requirement, 30 September 2026: every analytical approach, meaningful
analysis option and study-design template must follow academic best practice,
cite multiple suitable academic sources, and contribute to a holistic account of
contemporary implicit research for consumer science. This is a build requirement,
not a claim that the existing catalogue has completed this review.

## Unit of evidence

Maintain a versioned, machine-readable method-evidence registry. A family-level
bibliography is an index, not sufficient evidence for every option within that
family. Bind evidence to the exact procedure, recipe version, estimator and
consequential parameter/option: preprocessing, event detection, baseline,
exclusion/correction, window, aggregation, inference and interpretation.

Each research-ready entry needs at least two distinct relevant academic sources,
with independent corroboration where available. Prefer the original method or
measurement standard plus an independent validation/comparison or applicable
consensus statement. A paper and its software documentation are not two
independent academic sources. Store DOI/stable URL, authors, title, year, source
type, relevant section/table, what claim it supports, population/task/sensor
context, known limits and review date. Verify bibliographic metadata and the
supporting text; never manufacture a citation to reach the count.

More citations do not establish validity by themselves. Record disagreement,
negative findings and conditions where the method fails. If independent evidence
is unavailable, record the gap and the narrower supported claim. Library/API
availability, competitor use and successful software tests are separate evidence
types and cannot substitute for the academic record. New Brohn adaptations must
identify their departures from published procedures and the required validation.

## Required method record

The registry must carry:

- Exact method/profile/recipe identifiers, version and implementation references.
- Construct and estimand; directly observed quantities; suitable consumer-science
  questions and the limits of generalising from the cited setting.
- Required design, stimulus controls, acquisition/timing, units, sampling,
  calibration, signal quality and duration/support conditions.
- Algorithm and all consequential options/defaults, with claim-to-source links
  for each. Specify denominators, adjacency, missingness and unavailable outcomes.
- Baseline, correction/exclusion and aggregation rules, including person, session,
  stimulus and trial hierarchy, and which changes require a new recipe version.
- Reliability/agreement and validity evidence; uncertainty and multiplicity;
  limitations on causal, individual-level and predictive interpretation.
- Independent numerical/reference checks, adversarial cases, software evidence,
  scientific evidence and named-device/population evidence as distinct statuses.
- Evidence revision/hash, reviewer scope, unresolved gaps and next review trigger.

A generic modality label must not erase distinctions such as ECG RR versus
confirmed NN-HRV versus PPG PRV, facial action/expression output versus experienced
emotion, gaze allocation versus a general attentional trait, or peripheral skin
temperature versus ambient/core temperature.

## Holistic coverage

The option inventory must cover gaze/fixation/saccade/AOI/transition/pupil/blink;
EDA tonic/phasic/event/recovery; EEG spectral/ERP/time-frequency/connectivity and
supported later modelling; ECG/HRV/PPG PRV; respiration, EMG, peripheral/skin
temperature and other admitted physiological channels; fNIRS and other planned
neural measures; camera/face/head/attention and audio/video-derived measures;
IAT/BIAT/SC-IAT/GNAT, approach-avoidance, priming/AMP and the other behavioural
families in the master catalogue; questionnaires/scales, choice/MaxDiff and other
explicit measures; multimodal synchronisation, contrasts, reliability, fusion
and prediction. Planned methods retain their planned status until implemented
and qualified; the list does not assert that every approach is already enabled.

For each family, enumerate actual user-selectable options from application code
and worker recipes, then reconcile those against the planned catalogue. Track
implemented-but-under-evidenced options separately from absent features. Consumer
use cases include packaging, advertising, digital/physical UX, product experience
and sensory/brand research, but evidence must support the particular use case.

## Study-design layer

Every template needs its own evidence-backed design record. Include the research
question and planned estimand; target population/recruitment; manipulation and
control rationale; matched stimulus properties; within/between/mixed design;
allocation, order and counterbalancing; practice and checks; physiological
acclimatisation and recorded baselines; exposure, recovery and carryover; timing
and synchronisation; planned usable data, sample-size/precision rationale and
stopping rules; prespecified exclusions and missingness; repeated participant/
stimulus hierarchy; multiplicity and confirmatory versus exploratory analyses.

Do not prescribe one universal sample size, cutoff, minimum duration, fixation
algorithm, EDA threshold or baseline for all studies. Offer named supported
profiles, explain their assumptions, and check the actual design/data. A control
stimulus and a recorded physiological baseline are distinct protocol elements.
Accessibility accommodations that alter timing, stimuli or response mechanics
need an explicit protocol version and a documented analysis consequence.

## Application and export integration

Guided mode should retain the low-click journey. Each choice exposes a concise
"Why this method?" explanation, the question it can answer, requirements and an
expandable academic evidence panel. Advanced settings show option-specific
citations and the effect of departing from a supported profile. Preflight checks
method/design compatibility; result views retain support, uncertainty and
interpretation limits alongside the finding. Avoid hiding substantive assumptions
inside an advanced panel alone.

Freeze method-evidence revisions with newly compiled protocols and new analysis
outputs. Reports automatically include the exact methods, settings, exclusions,
software versions and deduplicated bibliography. Portable designs and report
packages retain that evidence snapshot. Later literature updates create a new
evidence revision; changed calculations require a new recipe and explicit rerun.
Saved studies/results must not be silently rescored or relabelled.

## Acceptance and ongoing work

BWP03/BWP09 own option-level scientific coverage and design contracts; BWP06 owns
source/device and quality requirements; BWP13 owns citation-preserving reports;
BWP15 owns understandable guidance; BWP17 owns accurate release claims. Preserve
the existing 50-capability/17-package statuses, including planned BWP16.

Required QA includes complete code-to-registry option coverage; distinct verified
academic sources and claim links; assumptions visible in the actual researcher
flow; method/design incompatibility checks; independent numerical reproduction;
and exact evidence/settings/bibliography through clone, portable design, analysis,
report and historical reopen. Citation-count lint is only a completeness check,
never an automated scientific endorsement.

The [dated portable audit](evidence-2026-09-30/README.md) is retained in this
repository; original local packets are in `work/consumer-methods-evidence-20260930`.
It is bounded source inspection and screened literature, not complete option
appraisal. Existing task
profiles expose single `source` links and more detailed references are dispersed
across method documents; a completed option-level registry/UI/export audit is
still required. The active cardiac integration preserves existing recipes while
this cross-platform evidence work proceeds. The [HRV/temperature inventory](../research/HRV-SKIN-TEMPERATURE.md)
and [control-design contract](CONTROL-DESIGN.md) remain applicable. This document
adds no new analysis or qualification claim.
