# Frozen multimodal reports

Implemented 2026-09-08 by `R/platform-multimodal.R`. The recipe is
`multimodal-explicit-crosswalk/1.0-draft`. It brings selected, saved scientific
reports into one transparent analysis while keeping each measure's observations,
eligibility and denominator separate. It does not compute a universal composite
or infer synchronized events from nearby timestamps.

## Researcher flow

1. Select saved reports for one study and one declared origin.
2. Review the metric catalog and source support states.
3. Explicitly map each source person/session to the intended shared person/session.
4. Declare the desired conditional comparisons, units and source reports.
5. Freeze the selection and run the report. Reopen the saved result with its
   report revisions, design, crosswalk and source-row hashes.

The study's current draft can have changed since collection. Synthesis uses
the selected reports' original frozen design, checking its hash and study/project
identity. The default `design_policy = 'exact'` refuses different full design
versions. Reports from different origins are always refused.
Existing reports outside the study's project are rejected before returning
their titles or status. An unknown report ID can be recorded as missing.

An explicit `design_policy = 'measurement_compatible_aoi_revision'` supports
the common workflow of correcting AOIs after collection while retaining the
original questionnaire report. `brohn_measurement_design_hash(design)` removes
only top-level `title`, `description`, `tags`, `archived`, `lineage` and each
stimulus's `aois` before hashing. Stimulus content/assets/duration, condition
IDs/roles, questions/scoring, order, seed, timing, methods and blocks remain in
the projection. Stimulus titles are conservatively retained as well.

The compatibility option is available on prepare, catalog and queue helpers;
it is never activated by a failed exact match. Every full source design hash
remains pinned and accompanies its observations. Each gaze definition includes
the complete frozen label-to-AOI geometry map across that report's stimuli.
Two AOI versions therefore cannot be pooled into a single gaze outcome: select
the intended version's report(s) explicitly. Compatibility permits parallel
gaze and rating results from unchanged measurement designs; it does not erase
AOI curation history or allow changed participant stimuli/procedures.

Source report IDs, revisions and body hashes are pinned. If an unavailable
report later appears, or a newer revision is created, the frozen request does
not substitute it. A missing/corrupt pinned revision or result object is an
explicit `integrity_issue` for that source. Other usable source measures remain
available. A source that originally failed or has no usable support is labelled
`unavailable`; an unregistered source kind is `unsupported_measure`.

## APIs and worker integration

```r
catalog <- brohn_multimodal_catalog(store, study_id, report_ids, origin)
request <- brohn_prepare_multimodal(
  store, study_id, report_ids, crosswalk, contrasts, origin,
  multiplicity = list(method = "holm", alpha = .05),
  identity_source = "Reviewed evidence establishing these identity links"
)
input <- brohn_multimodal_input(store, request)
report <- brohn_analyse_multimodal(input)
job <- brohn_queue_multimodal(
  store, study_id, report_ids, crosswalk, contrasts, origin,
  identity_source = "Reviewed evidence establishing these identity links"
)
```

`brohn_queue_multimodal` enqueues `analyse_multimodal` using the frozen request
hash as its idempotency key. The inner worker input has
`schema = 'brohn-multimodal-input/1.0'`, `request` and resolved `sources`.
The job coordinator wraps it in the existing analysis-input envelope with
`operation = 'analyse_multimodal'`, `multimodal = input` and the pinned
`project_id`. Analysis dispatch calls `brohn_analyse_multimodal(input$multimodal)`.
Source this module after the shared domain functions and before the job adapter;
the existing analysis worker handles the fenced result publication.

`catalog$metrics` contains readable labels plus exact `modality`, `metric`,
`outcome_id`, `unit`, `report_ids`, source-row counts and eligible source-row
counts. `catalog$identities` supplies source identities and clearly separate
`proposed_participant_id`, `proposed_session_id`, `confirmed = FALSE` fields.
These proposals are not accepted directly as reviewed crosswalk records.
`catalog$sources` reports each selected source's status and reason.

## Explicit identity and observation mapping

A crosswalk is an array of records with exactly these fields:

```r
list(
  report_id = "report-eye-tracker",
  source_participant_id = "tracker-017",
  source_session_id = "recording-2",
  participant_id = "person-017",
  session_id = "visit-2"
)
```

Every mapping is scoped to one selected report. The evidence/rationale is
stored as `identity_source`. Each source person/session has one assignment;
duplicate assignments are refused. Same-looking labels in different reports
never create an automatic identity link. The researcher must establish that
the shared person/session labels mean what the analysis assumes. Missing
crosswalk entries preserve source observations with
`identity_not_explicitly_linked`, and exclude those observations from linked
comparisons. A device recording without declared source person/session labels
cannot silently become a known person.

The long-form observations retain source report ID/revision/hash, source
container and row number, source-row hash, source person/session/recording/
segment/exposure IDs, shared person/session, stimulus, condition, modality,
metric, outcome, unit, typed value, eligibility, reason and support. Row
numbers are provenance only, never a join key. Actual source exposures are
retained. Physiology without an exposure ID uses its explicit recording/segment
identity as a recording-summary observation; that label does not claim a
measured stimulus onset.

## Supported measures

| Source | Extraction and eligibility |
|---|---|
| Prepared or raw gaze | `valid_gaze_share` per AOI/exposure, in percentage points. Requires positive valid duration, consistent inside/valid arithmetic, the registered gaze recipe and matching frozen stimulus/AOI/condition identity. The valid off-AOI denominator is preserved. |
| Questionnaire | `explicit_rating` for a frozen question explicitly typed `rating`. The response must be a finite allowed numeric option with no missing reason. Numeric category codes from other question types are not reinterpreted as quantitative ratings. |
| Declared-group EDA, EEG, ECG, PPG, respiration, EMG, fNIRS | Finite, unit-labelled features with recording or recording-condition scope and exactly one matching computed support record. A declared recipe and source person/session mapping are required for linked comparisons. Channel and applicable frequency/band/window/polarity dimensions remain part of the outcome definition. |

Typed missing values remain missing. No no-signal interval, absent response,
failed feature or invalid unit becomes zero. Partial physiology reports can
still supply their computed recording/condition cells. The source's successful
numerical support does not become device or scientific qualification.

Each observation has a definition hash. Gaze denominator/recipe, the frozen
rating question, and physiology recipe/dimensions are retained. A comparison
that would pool different definitions is unavailable with
`source_measure_definitions_disagree`. Duplicate mapped person/session/
condition/observation identities similarly produce
`duplicate_or_ambiguous_observation_identity`; selected reruns cannot count as
extra trials. No source is silently preferred or discarded to resolve ambiguity.

## Declared comparisons and denominators

Each comparison specifies the following selector. Use the catalog's exact
measure fields rather than inventing unit or channel identifiers:

```r
list(
  id = "logo-share",
  report_ids = list("report-eye-tracker"),
  modality = "gaze",
  metric = "valid_gaze_share",
  outcome_id = "Logo",
  unit = "percentage points",
  control_id = "condition-a",
  test_id = "condition-b"
)
```

Both conditions must exist in the frozen design. Duplicate hypotheses or
comparison IDs are refused. A descriptive synthesis may declare no comparisons.
The worker applies the same explicit aggregation to each measure independently:

* Average its eligible source observations equally within person/session/condition.
* Subtract the control mean from the test mean where both exist in that session.
* Average paired session differences within each person.
* Give each person equal weight in the final difference.

Source observations here can be gaze exposures, rating responses or supported
physiology recording summaries. Equal recording-summary weighting is explicit;
it is not time weighting or sample weighting. A protocol needing another
aggregation, raw-signal recalculation or hierarchical model requires its own
tested recipe. Reports retain the source observation counts, session differences,
person differences, paired sessions, unmatched sessions and eligible person N.

Missing EEG does not remove a person's valid gaze. A missing rating removes
only the affected rating pair. There is no global cross-modal complete-case
filter. Each comparison also lists its unavailable selected source reports.
This makes incomplete source availability visible without suppressing unrelated
measures.

## Inference and multiplicity

With at least two people and non-negligible between-person variance, the
estimate uses a two-sided paired-difference t calculation and an unadjusted
95% Student interval at the person level. One person retains a descriptive
estimate with no p-value or interval. Constant/nearly constant person
differences also remain descriptive; they do not generate perfect significance
from a zero estimated standard error. The distribution and independence
assumptions remain properties of the research design and sampling, not of
software execution. [R Student distribution documentation](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/TDist.html)

The implemented policy is **Holm correction across every declared comparison**.
Unavailable hypotheses stay in the family size. Brohn calls `p.adjust` on the
available p-values with `n` equal to the complete declared family. For Holm,
unobserved p-values are thereby treated as larger than observed ones; missing
measures do not quietly reduce the correction denominator. The result reports
family size, available tests, alpha, raw/adjusted p-values and the resulting
decision. Displayed intervals remain unadjusted and do not claim simultaneous
family coverage. [R p.adjust documentation](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/p.adjust.html)

There is no temporal sensor fusion, nearest-time join, multivariate causal
claim, universal emotion/attention index or automatic psychological construct
interpretation. Multilevel/hierarchical models are a separately named future
recipe until their exchangeability, support, convergence and validation are
implemented and tested.

## Bounds and validation

The catalog and request accept 1..100 reports, up to 20,000 reviewed identity
links and up to 100 distinct declared comparisons. Source extraction is capped
at 100,000 observations per report and synthesis at 200,000 total observations.
The catalog supports up to 1,000 distinct measures. Frozen worker input is
limited to 12 MiB; larger selections need smaller report sets. These bounds
avoid silently truncated scientific observations.

Run `tests/platform-multimodal.R` with the Brohn R library. The independent
oracle has gaze person differences 20, 25 and 45 percentage points, so the
equal-person estimate is 30; averaging its raw session differences would
incorrectly give 27.5. Rating and EEG have two eligible people each while gaze
has three, and an entirely missing EDA report remains an unavailable fourth
hypothesis. Closed-form df=1 and df=2 t probabilities and hand-computed Holm
steps check the statistics independently of the implementation's R calls.

Additional checks cover typed omissions, no automatic identity links, changed
or corrupt pinned reports, missing/failed source isolation, confirmed versus
proposed crosswalks, source revisions after selection, historical design
reopening, project/origin/design boundaries, incompatible measure definitions,
duplicate observations, one-person/zero-variance inference limits, idempotent
queueing and restart reproducibility. All fixtures are synthetic. They do not
establish empirical usability, measurement validity or participant reliability.

**45 checks pass**, including compatible post-collection AOI correction with
execution-field protection and refusal to pool different AOI versions. The
full job test uses the actual fenced R child, verifies the independently
expected amended gaze estimate, and reopens the immutable result object with
its receipt and crosswalk hash. This establishes the saved-job path in addition
to in-process numerical checks.
