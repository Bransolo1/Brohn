# Proposed design profiles and preflight — under review

These are proposed records and UX gates, not implemented templates or scientific acceptance. They add no jobs, scoring rules or capability status. The evidence IDs refer to [REGISTRY.json](REGISTRY.json); the code audit is [EVIDENCE.md](EVIDENCE.md).

## Minimal profile set

| Proposed profile | Consumer question and estimand | Required design commitments | Implementation/qualification gate |
| --- | --- | --- | --- |
| `consumer-paired-comparison/0.1-proposed` | Mean within-person response to A versus B in a stated exposure context. | Control rationale, matched stimulus properties, identities, order scheme, intended first/repeated exposure, carryover assumptions, questionnaire placement, paired outcome family and participant-level precision. Sources S01–S03, S05–S06, S16–S17, S20–S21, S27–S29. | Build on the existing comparison/paired plan. Validate order and actual usable balance, AOI comparability, timing and method-specific support. Current 5,000/500/0-ms constructor values are not accepted scientific defaults. |
| `consumer-first-exposure-between/0.1-proposed` | Difference between randomized groups each encountering one version, when repeated exposure changes the target experience. | Allocation unit, sequence and concealment, recruitment/eligibility, group balance, stimulus sample, missingness, effect/precision and between-group inference. Sources S01–S02, S16–S17, S20–S22, S25–S26. | Requires a genuine between-participant allocation and analysis path; randomized stimulus order within one participant is insufficient. Not enabled by this packet. |
| `consumer-repeated-stimulus/0.1-proposed` | Condition effect intended to generalise across people and sampled advertisements/packages/items. | Explicit participant × stimulus hierarchy, sufficient stimulus sampling, repeated session/trial structure, constrained order, carryover and model/precision rationale. Sources S03, S16–S19. | Add the supported crossed/hierarchical estimator with convergence/uncertainty handling and independent numerical checks. Do not force either maximal or simplified random effects from a slogan. |
| `physiology-reference-event-recovery/0.1-proposed` | Change in a named physiological quantity relative to an actual supported reference. | Modality/estimator, source units, sensor/context, settling, recorded reference, event/response/recovery windows, artifacts/exclusions and minimum valid support. Sources S07–S12; add the exact modality's independent sources before acceptance. | Per-recipe compatibility checks and actual duration/support, not one universal baseline. ECG RR, confirmed NN-HRV, PPG PRV, EDA and peripheral skin temperature keep distinct records. Evidence here does not supply a skin-temperature protocol or qualify an HRV recipe. |
| `named-behavioural-procedure/0.1-proposed` | The exact contrast supported by a specified RT/implicit task variant. | Published procedure plus adaptation list; practice/pass/retry, stimulus/response mapping, timing/foreperiod, feedback, correction/omission rules, support, scoring and multiplicity. Sources S02, S13–S15, S29–S30 plus each task's original/independent method sources. | Existing vendor-derived drafts need task-specific evidence reconciliation and actual device timing. A short demonstration is not accepted as a stable individual trait measure. |

Questionnaire placement, accessibility accommodations and source/evidence provenance apply to all profiles. Consumer prediction remains a separate planned capability: S31/S32 supply context-specific examples, not permission to add a predictive badge or composite.

## One compact preflight, with conditional requirements

Start with the question, primary estimand, population, manipulation/control rationale and intended claim: group contrast, repeated experience, individual differences or external prediction. Then select the profile and its exact method recipe. Show a short explanation of what that choice can answer and the assumptions that matter, with the source panel expandable. Do not hide a material carryover or baseline assumption in an advanced tab.

The profile supplies applicable fields, never an unqualified universal sample size or duration:

- **Allocation and exposure:** within/between/mixed structure; allocation unit; planned order, randomization and carryover; expected completion/usable balance; practice; observed onset/offset and response clocks.
- **Stimulus and context:** geometry/visual angle, AOI meaning, luminance/background and intended uncontrolled properties; task instructions and language; equipment and input mapping; questionnaire position; accommodation changes with analysis consequences.
- **Physiology when selected:** sensor placement/calibration/context; acclimatisation/settling; actual reference event; recovery; signal support and artifact policy. The exact recipe determines units, required duration and unavailable reasons. A baseline epoch is not automatically a valid baseline measurement.
- **Analysis and useful data:** hierarchy, primary family/direction/error criterion, sample-size or precision rationale, stopping, exclusions, missingness and sensitivity; separation of planned and exploratory analyses; external preregistration URL/status, if any.

Drafts may stay editable with unresolved scientific fields. Before research release, show a concise “ready / unresolved / unsupported for this claim” list grounded in the selected profile's requirements. An unavailable modality/profile must retain the explanation rather than silently changing timing, dropping a measure, or substituting a different estimator. Broad warnings without a specific requirement are not a substitute for this check.

## Proposed versioned design-evidence seam

The future record should contain `profile_id`, `profile_version`, exact recipe and implementation references, `evidence_revision`/hash, `claim_type`, estimand, population/task context, option-to-source claim links, source-review scope, adaptation declarations, controls, timing/support requirements, allocation/hierarchy, planned family, missingness/exclusion/stopping policy, reliability/validity limits, and unresolved gates. A source entry records authors/title/year/type/DOI-or-stable-URL, inspected section, supporting claim, population/task/sensor context, limitations and review date.

Academic support, independent numerical reproduction, software tests, named-device timing, population validity and connected UI/export/history qualification remain separate statuses. At least two distinct suitable academic sources per consequential option are a minimum evidence requirement; neither publication count nor two references to the same dataset/procedure automatically establish independent validation.

Freeze the selected evidence revision alongside new compiled protocols; retain both planned and actual allocation/timing. New analyses record the exact settings, support and changes from the plan. New reports and portable designs retain the deduplicated bibliography and option/claim links. Historical reopening uses the saved evidence snapshot, while presenting later updates separately; it must not rescore or rewrite old methods. This seam is proposed only and must be reconciled with the platform's actual schema/authority rules before implementation.

## Acceptance work still required

Map every actual design option to this record, resolve academic coverage gaps, implement narrowly scoped compatibility checks, verify independent calculations and device timing, and test draft → compiled protocol → collection → analysis → report/export → clone/portable → historical reopen. Check the real phone/desktop flow for clear method distinctions and non-destructive correction of unresolved fields. Preserve 50 capabilities/17 package statuses and planned BWP16 throughout. This packet changes none of them.
