# Behavioural methods review: turn task names into complete research recipes

Build a method library that lets a student choose a research question and receive the appropriate task, practice, scoring and report together. This review is the behavioural-methods workstream within the biovital/implicit team, integrated by the root agent. Date: 5 September2026. It audits the v0.1 package against the user's brief; all fixes below are planning specifications, not implemented or scientifically validated functionality.

## Findings and enabling fixes

| Gap | Priority | What the baseline leaves unresolved | Concrete change | Acceptance evidence |
|---|---|---|---|---|
| IM-G01 | P0 | B006/B007 ask a future team to specify exact BIAT/AAT variants; the app could expose a method name before its protocol is complete. R architecture section5 gives principles rather than a releaseable profile. | Require a signed method manifest with separate protocol, runner and scorer versions. A recipe is draft, implementation-tested or qualified for a named context. Select a paper-anchored BIAT profile; preserve vendor-compatible import profiles separately. | Compiler rejects an absent version, unresolved trial count, category mapping, latency definition or scorer. A hand-calculated fixture passes before a profile becomes implementation-tested. |
| IM-G02 | P0 | A generic D-score or push-minus-pull label can reverse the research conclusion or double-penalise errors. Baseline stores response events but does not give the score-direction contract. | Persist first response and every correction separately; compute final-correct latency only for profiles that require it. Save the explicit numerator and category labels with every result. | Swapping A/B or push/pull reverses the declared contrast exactly. Corrected latency never receives an additional error penalty unless the selected algorithm explicitly calls for one. |
| IM-G03 | P0 | Physical AAT, mouse zoom, touchscreen swipe and VAAST are distinguished conceptually, but one generic selector could still hide changes in response mechanism or measurement versus training. | Separate assessment and training modes; assessment balances stimulus-category × action cells. Create separate input/visual-mapping profiles. Log return-to-neutral, onset, completion, trajectory and errors for physical input. | Missing condition cells prevent the corresponding contrast. A 100% avoidance training schedule cannot publish as a balanced assessment recipe. Switching input creates a new profile revision. |
| IM-G04 | P1 | Agile alternatives are a comparison list and late tickets rather than a usable question-to-method catalogue. | Give each method an outcome, participant burden range measured in pilots, evidence status, supported input, automatic scorer and prerequisite fields. Add dedicated VAAST and timed intuitive association cards, with distinct interpretations. | Every visible method card opens a complete example or visibly states its unavailable dependency. No card implies that a renamed generic go/no-go task is GNAT. |
| IM-G05 | P0 | “Pilot reliability” is mentioned but there is no operational path from desired precision and duration to a recruitment plan or reportable result. | Add a recipe-specific precision planner and psychometric report. Compare candidate durations in pilot fixtures; show retained trials, participant uncertainty and between-participant reliability with its estimator. | Simulation reports assumptions, design, missingness and expected interval width; no universal sample-size recommendation. Halving trials cannot silently inherit the long profile's reliability badge. |
| IM-G06 | P0 | Preflight simulation exists as a principle, but novice practice failure and semantic debugging are not fully specified. | Provide a rehearsal with expected versus actual stimulus, category, key, path and output rows. Participant practice explains the mapping, permits a declared retry rule and records attempts. Errors open the relevant study element. | A reversed category fixture is detected before publication. A failed or abandoned practice is preserved with a reason. Sample/preview events never enter production scores. |
| IM-G07 | P0 | Multimodal linkage could still be treated as one score row per RT trial, despite overlapping physiology and movement. | Store a common task-epoch contract: instruction, practice, stimulus, first response, correction, movement, rating and rest. Analysis declares which windows belong to each outcome. | Delayed EDA and response-locked EEG fixtures retain overlaps. One rating joined to multiple AOIs does not multiply independent observations. |
| IM-G08 | P0 | Plain-language results are promised, but individual/category claims and multi-measure missingness lack a consistent report schema. | Each result declares estimand, unit, level, comparison, direction, denominator, uncertainty and applicability. Keep group inference, participant observations and exploratory association separate. | The same simulated data cannot produce a clinical diagnosis, participant identity label or a universal hidden-preference score. Liking reports can retain people excluded only from eye analysis. |
| IM-G09 | P0 | R-ARCHITECTURE G2 includes full IAT while B189 places it at C:G6; COMPETITOR-REVIEW retains an older five-stage navigation. | Keep BIAT/AAT implementation at G2, physical integration G3 and qualification G4. Full IAT stays C:G6. Use Plan → Questions → Collect → Review → Results everywhere. | Automated document/backlog cross-check finds no conflicting milestone or stage description. |

These findings refine the existing direction. The baseline already contains raw-data preservation, immutable versions, task-specific scoring, quality checks and qualification gates; the changes make those intentions concrete at the interface and service boundary.

## A concrete BIAT profile decision

Use a **Nosek et al.2014 procedure/scoring profile** as the paper-anchored implementation target, with the exact category/stimulus package and operating context qualified separately. The evaluated structure has a16-trial warm-up followed by four20-trial blocks; the first four trials of response blocks are prefatory. Its reported scoring removes latencies above10,000ms, retains correction-inclusive error trials, bounds remaining latencies to400–2,000ms, computes a D contrast within each consecutive block pair and averages the pair scores. The fast-response screen uses a pre-recoding count of responses below300ms and a10% criterion. The detailed eligible-trial denominator must be frozen in the scorer fixture. These are characteristics of that profile, not defaults for all implicit tasks. [Primary study, Tables1,2,8 and Study5](https://faculty.washington.edu/agg/pdf/Nosek%26al.BIAT%20scoring%20algorith.PLoS%20ONE.2014.pdf)

The current Inquisit BIAT documentation describes a different practice/extended-block arrangement and exports initial accuracy alongside final corrected latency. Give imported vendor data a named compatibility profile; do not relabel a vendor export as the paper profile merely because both produce D. The online manual also contains visibly malformed interpretation thresholds; this reinforces the need for reviewed typed specifications and numerical fixtures rather than automatic copying of prose. [Inquisit BIAT manual, modified25November2025](https://www.millisecond.com/library/v7/iat/briefiat/briefiat/briefiat/briefiat.manual)

Proposed internal manifest fragment; exact production values are deliberately versioned, and `qualification` is not yet passed:

```json
{
  "method_profile_id": "biat-nosek2014-v1",
  "status": "draft_specification",
  "protocol_id": "biat-16plus4x20-v1",
  "runner_contract_id": "correct-until-accepted-v1",
  "scorer_id": "biat-d-bounded-pairs-v1",
  "focal_attribute_id": "declared-good-category",
  "counterbalance": "ABAB_or_BABA_persisted_assignment",
  "latency_field": "final_correct_minus_stimulus_onset_ms",
  "first_response_field": "first_response_event_id",
  "correction_events": "retained_in_order",
  "fast_rate_source": "original_latency_before_recoding",
  "fast_rate_denominator_id": "required_reviewed_fixture_definition",
  "contrast": {"numerator": "mean_B_minus_mean_A", "positive_label": "required"},
  "raw_data_mutation": false,
  "publish_blockers": ["unresolved_denominator", "unverified_stimulus_rights", "unpassed_independent_score_fixture"]
}
```

The unresolved denominator is an explicit scientific decision, not a silent implementation assumption. Resolve it against the article's analysis specification/reference data before publishing the profile; until then the compiler permits only synthetic demonstrations. This is a bounded gate with an observable completion test.

## AAT assessment specification

Build the first physical assessment with balanced category × movement cells and a declared response-relevant feature. Record the mapping from physical direction to approach/avoidance separately from screen zoom. Produce both reaction time (stimulus to movement onset) and movement time (onset to threshold/completion), with one chosen primary outcome. Report per-category push-minus-pull contrasts and, when the research question specifies it, the difference of those category contrasts. Preserve correct-trial counts in every cell, plus the predeclared trimming and aggregation rule.

Do not transfer a BIAT correction penalty to AAT. A primary simulation/multiverse study found that AAT preprocessing choices materially affected reliability and validity; qualify the chosen AAT treatment against a relevant reference dataset. [Kahveci et al.,2023](https://pubmed.ncbi.nlm.nih.gov/37221345/)

Inquisit provides distinct gamepad, joystick, keyboard and mouse variants. Its supplied assessment example uses practice and balanced movement requirements, illustrating why “push/pull supported” is insufficient to describe a method. [Inquisit AAT](https://www.millisecond.com/library/aat)

## Agile method catalogue to build

| Research question | Method card | Automatic result contract | Delivery |
|---|---|---|---|
| Which of two concepts is more strongly paired with a declared attribute? | Specified BIAT | Named D profile; counterbalance; error/fast-response audit; group estimate and uncertainty | G2 implementation, G4 qualification |
| Is approach faster than avoidance for a category relative to a comparator? | Physical AAT assessment | Prespecified onset/completion contrast; balanced cells; movement QC | G2 simulated/imported, G3 physical, G4 qualification |
| How do self-directed approach/avoidance responses vary across categories online? | VAAST | Separate spatial-action and visual-motion contract, latency/accuracy summaries | C:G6 method pack |
| How readily is a target associated with an attribute without a second target category? | SC-IAT or GNAT, chosen by the actual protocol | Distinct association/deadline and error model; named scoring, not a generic IAT reducer | C:G6 |
| How does a prime shift evaluation of an ambiguous target? | AMP | Trial sequence, response proportion/contrast, prime visibility/timing requirements | C:G6 |
| Which association is endorsed quickly? | Timed intuitive association | Endorsement and conditional latency reported separately; timeout/censoring explicit | C:G6 |

This is a proposed product taxonomy. The existing competitor review supplies primary sources for SC-IAT, GNAT and AMP. PsyToolkit's VAAST example includes a method-specific manual and R analysis materials, making it a useful open-workflow reference. It is not evidence that VAAST is interchangeable with joystick AAT. [PsyToolkit VAAST](https://www.psytoolkit.org/experiment-library/vaast_images.html)

## Frontend-to-backend behaviour

**Plan:** a recipe card selects a `method_profile_id`; the R service resolves immutable protocol/scorer references and returns a capability check. Changing a category or input invalidates compilation and leaves prior sessions pinned to their old version. **Questions:** explicit questions receive declared referents; the questionnaire compiler validates their availability along each realised task path. **Collect:** the runner receives a signed, self-contained run bundle and logs response/correction events locally; the acquisition coordinator owns live-stream readiness. **Review:** a quality decision creates a revision and invalidates dependent score/model/report jobs. **Results:** a deterministic R result object, not the UI's current selections, supplies numbers and direction labels.

Proposed event envelope:

```json
{
  "run_id": "run-demo-01",
  "study_version": "study-v7",
  "method_profile_id": "biat-nosek2014-v1",
  "trial_instance_id": "block2-trial8",
  "event_id": "device-stream-seq1024",
  "type": "response_corrected",
  "clock_id": "runner-monotonic",
  "source_time_ns": "38425590100",
  "sequence": 1024,
  "payload": {"response": "right", "is_correct": true, "response_ordinal": 2}
}
```

The schema keeps physical onset evidence and browser callback time distinguishable. A replayed event ID cannot create another trial; a missing first response stays missing rather than being inferred from the final correction. Run-bundle hashes and clock-mapping revisions travel with the resulting score.

## New visual evidence and its use

Eleven stills extend the library with Inquisit, OpenSesame and PsyToolkit. Source UI is studied for interaction structure, not adopted as the premium visual style.

| Evidence | Visible state | Gap informed |
|---|---|---|
| IM-V2-IQ7, IQ10 | Script/structure workspace and debugger properties | IM-G01/06: recipe trace and exact state inspection |
| IM-V2-OS1/OS2/OS3 | Live variable inspector, source-linked error and process failure | IM-G06: semantic rehearsal and recoverable errors |
| IM-V2-OS4/OS5/OS6 | Template selection, category/response table and stimulus editor | IM-G01/02: complete templates and inspectable mapping |
| IM-V2-PT1 | VAAST participant introduction | IM-G03/04: method-specific spatial instructions |
| IM-V2-PT2/PT3 | Live IAT instructions and a category-sorting trial | IM-G02/06: preview-to-participant continuity |

The Inquisit screenshots come from its copyright2022 manual. OpenSesame sources are version4.0 documentation; embedded screenshots may be older. PsyToolkit demo captures are live public UI observed on the review date; no full study was completed. The manifest records source URLs, image hashes and gap IDs. No videos or animations were downloaded. Screenshots resolve reference gaps; timing, psychometrics and accessibility still require implementation and appropriate tests.

Sources for the visual lessons: [Inquisit programmer manual](https://www.millisecond.com/support/Inquisit%20Programmer%27s%20Manual.pdf), [OpenSesame debugging](https://osdoc.cogsci.nl/4.0/manual/debugging/), [OpenSesame IAT tutorial](https://osdoc.cogsci.nl/4.0/tutorials/iat/), [PsyToolkit IAT demo](https://www.psytoolkit.org/experiment-library/experiment_iat.html).
