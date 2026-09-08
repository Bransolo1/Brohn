# Reusable questionnaire scale scoring

Brohn's `explicit-questionnaire-scale/1.0` recipe applies a researcher's saved
multi-item numerical scoring key to separate assessments. It supports original
scales and researcher-entered published keys. A name, citation or correct formula
does not establish that the questions, translation, administration or population
match a validated instrument. No questionnaire text is downloaded or supplied by
this module. Reliability coefficients, clinical thresholds, latent-trait models,
normative classifications are outside this recipe. A separate declared comparison
adapter can compare eligible after-stimulus scores using the study's saved
control comparisons and multiple-testing family.

## Saved design contract

`design.scales` is optional. An absent field and an empty list both mean that no
multi-item scoring has been configured. A scale has this portable contract:

```json
{
  "schema": "brohn-questionnaire-scale/1.0",
  "id": "scale-original",
  "label": "Original concept response",
  "version": "1.0",
  "source": "Researcher-defined key; document the construct, source and adaptations here.",
  "scope": "end",
  "items": [
    {"question_id": "question-one", "reverse": false, "min": 0, "max": 4},
    {"question_id": "question-two", "reverse": true, "min": 0, "max": 4}
  ],
  "scoring": {
    "aggregation": "mean",
    "missing": "complete",
    "minimum_answered": 2,
    "prorate": false
  },
  "conversion": null
}
```

At most 32 scales may be saved, with 2-100 unique question references each.
Only quantitative `rating`, `number` and `slider` questions are eligible.
Numeric category codes in a single-choice question are not quantitative scale
items. Matrix rows, allocation responses and other structured responses need a
separately specified item-extraction recipe; they are not flattened implicitly.

Each item pins its exact lower and upper response bounds. Ratings obtain those
bounds from their declared numeric option codes, because generic question range
controls do not constrain rating choices. Number and slider questions use their
frozen `min` and `max`. Every observed value also passes the shared typed answer
validator, including permitted rating codes and number/slider step grids. Zero
is a valid number. Boolean false, numeric-looking text, unsupported values and
out-of-range values are not coerced into numerical answers.

All items in a scale share one `scope`: `before`, `after_each` or `end`.
Changing a referenced question's placement or codes invalidates the old key until
reviewed. Cloning generates a new scale identity and remaps every question
reference; missing mappings fail rather than dropping items. The scoring source,
version, bounds, key and missing rules travel with the design and are frozen into
each analysis report.

## Arithmetic and missingness

For an observed answer `x`, reverse scoring is `min + max - x`. A non-reversed
item retains `x`. Original values, transformed values, bounds and reverse keys
are retained together. Complete scoring sums or averages every keyed item.

`missing:"complete"` requires `minimum_answered` to equal the number of items,
with `prorate:false`. `missing:"minimum_answered"` requires an explicit count.
For a partial mean, the observed keyed items are averaged directly and
`prorate:false`. For a partial sum, `prorate:true` explicitly estimates the full
sum as the observed keyed-item mean multiplied by the full item count. Partial
scoring requires exactly equal lower **and** upper item bounds; equal widths with
different endpoints are insufficient. A hidden or omitted item remains missing,
with its original reason. An invalid or duplicated item makes the assessment
unscoreable even when another item-count threshold would otherwise be met.

`conversion:{"min":0,"max":100}` optionally maps the aggregate's fixed
theoretical lower and upper bounds linearly to a declared range. It does not clip
responses or create percentages, percentiles or population benchmarks. The
original aggregate, theoretical range and converted value are all retained.

For an arithmetic cross-check only, John Brooke's SUS chapter hosted by AHRQ
specifies ten 1-5 responses, alternating item directions and a final 0-100 score.
The usual key subtracts 1 on odd items, subtracts even responses from 5, then
multiplies their total by 2.5. In this generic implementation, reverse-keying the
even items on the 1-5 range and converting the complete sum's 10-50 range to
0-100 is algebraically equivalent. Tests use original placeholder item labels:
favorable endpoints yield 100, adverse endpoints 0 and all midpoints 50.
No SUS item text or validity assertion is attached to those fixtures.
[Primary scoring source: Brooke, SUS chapter, page 5](https://digital.ahrq.gov/sites/default/files/docs/survey/systemusabilityscale%2528sus%2529_comp%255B1%255D.pdf).

## Assessment identity, repeats and source evidence

The unit of scoring is the explicit tuple `participant_id`, `session_id`,
`assessment_id`. Each original question row remains separate inside that tuple.
No answer is borrowed across people, sessions, stimuli, assessments or origins.
Conflicting scope, stimulus/condition, shared exposure or origin in an assessment
makes that assessment unscoreable. Repeated assessments count as assessments,
not additional people. A unique-person count is withheld when person linkage is
not explicitly supported.

For participant runs, `brohn_scale_run_responses()` reads the frozen protocol and
event journal. Before and end questionnaires receive separate scope identities
within the run. After-each items attach to the exact preceding frozen **stimulus
step**, with matching stimulus and condition identities. This matters because the
older questionnaire response row's `exposure_id` names a **question step**; using
it directly would split a multi-item assessment into individual questions. The
adapter retains that original question step and event sequence as item provenance
while keeping the stimulus occurrence as `assessment_exposure_id`.

Imported rows need an explicit shared `assessment_id` from their reviewed source
mapping. The scorer never infers it from row order, session labels, a stimulus
label or per-question exposure IDs. Blank optional stimulus/condition fields stay
missing for whole-study assessments. Imported after-each rows need a recognized
stimulus and its matching condition. An optional `assessment_exposure_id` may
retain a separately established shared occurrence; the original `exposure_id`
always remains item source evidence. Missing assessment IDs appear in the
unassigned-row quality record instead of producing an invented score.

The output includes scale/assessment scores, answered counts, score eligibility
and reasons, item evidence, source hashes, the original referenced questionnaire,
full scale settings and source provenance. Conditionally hidden items remain
distinguishable from optional omissions and unobserved items. Duplicate committed
answers are not averaged, arbitrarily selected or treated as extra items.

## R integration and researcher flow

- `brohn_validate_scales(scales, design)` validates portable settings after the
  design's questions have been validated.
- `brohn_clone_scales(scales, question_map)` remaps a cloned study's item references.
- `brohn_score_scales(responses, design, assessments=NULL, source=list())` scores
  explicit typed response contexts; optional expected assessments expose entirely
  missing assessments instead of silently omitting them.
- `brohn_scale_run_responses(input)` creates frozen run assessment contexts;
  `brohn_score_run_scales(input)` produces `brohn-questionnaire-scale-results/1.0`
  or returns null when no scale is configured.
- `brohn_scale_scores_csv(result, path)` exports every assessment's score, status,
  missingness counts and provenance hashes. Spreadsheet-sensitive text is escaped;
  a canonical JSON score record alongside it preserves exact typed identities.
  Full per-item evidence remains in the complete JSON report.
- `brohn_scales_summary_ui(design)` belongs on Questions;
  `brohn_install_scale_ui(input, output, session, current, state, attempt, capture,
  update_study)` installs its commands. `brohn_scale_results_ui(result)` displays
  stored report results, including incomplete-assessment reasons.

The editor first saves the surrounding question form, then freezes study ID,
revision, design hash and a unique modal identity. Researchers select eligible
items and reverse keys, supply their source and choose the missing rule. Save
validates the complete key and uses the existing study revision check. Cancel
discards the draft. Old modal tokens, study navigation and intervening revision
changes cannot save into another study. Editing an item key never rewrites an
already collected protocol or a frozen report.

Changing or deleting a referenced question is rejected if it would invalidate the
saved key. The error names the scale/item. **Discard unsaved question edits**
restores the saved Questions form without calling the failing capture operation or
writing a catalog revision; the researcher can then edit/remove the key explicitly
before changing its items. There is no silent reverse-key repair.

The current pure-R report bounds are 250,000 source responses, 50,000 explicit
assessment contexts and 100,000 scale scores. Exceeding a bound fails explicitly;
the recipe does not silently truncate scientific results. The UI previews 30
assessment rows and names the total; CSV contains all rows and JSON retains
complete item evidence.

## Scoped evidence

### Declared condition comparisons

In Plan, choose **Questionnaire scale score** and a saved **After-stimulus scale**.
Before/end scales cannot acquire a condition through row order or a supplied
label. Each score first satisfies its complete-item or explicitly prorated key.
Eligible assessments receive equal weight within each condition/session. Paired
session differences are averaged within person, then each person receives equal
weight. Missing scale scores exclude only the affected assessment or unsupported
pair; source assessments and item evidence remain in the report. Unknown repeat
identity withholds the comparison. Mixed recording origins and duplicate
assessment rows are rejected.

Scale and individual numeric-item outcomes share the same declared testing family.
A complete report uses Holm adjustment; a report missing another planned modality
uses conservative Bonferroni bounds over the entire family. Intervals use eligible
person differences and remain unadjusted. Fewer than two people or negligible
between-person variance retains a descriptive estimate without an inferential
interval or probability. No plan adds an automatic scale significance claim.

The comparison pins the exact design, scale keys, scored-assessment hash and source
receipt. Changing a key requires a new analysis. Clone and portable import remap
the hypothesis to the new scale ID as well as remapping its item IDs. The plan
editor invalidates cancelled drafts, late actions, navigation and concurrent
study revisions. [The comparison checks](../../tests/platform-scale-comparisons.R)
pass 31 independent arithmetic, actual worker, ZIP/report/reopen and Shiny checks.
The original repeated-person fixture has differences 4, 8 and 12: mean 8,
three people, four paired visits, and one excluded visit. Its two-sided probability
is independently checked against the closed form `1 - sqrt(6/7)`. Actual browser
comparison authoring and collection remain a separate acceptance journey.

### Scoring and authoring

The scale modal creates its item selectors and reverse controls once. Changing
item membership only shows or hides existing controls in the browser; a delayed
server render cannot erase a reverse choice made in the meantime. Each assessment
placement has a separate picker retained until Save or Cancel. Save reads only
the active placement, then validates every selected item against that scope.
Removing and reselecting an item retains its pending reverse choice in the same
modal. A reopened editor has fresh input identities and the saved key.

`tests/platform-scales.R` passes 74 checks: independent reverse/sum/mean
and linear-conversion arithmetic; missing and partial-sum rules; zero versus false;
typed response/code/grid validation; rating-code bounds and JSON integer restart;
equal-width/different-endpoint rejection; duplicate and repeated assessments;
unknown linkage; explicit import assessment identity; clone references; published
SUS arithmetic using original fixture labels; frozen protocol contexts and hidden
items; and Save/Cancel/stale editor guards. Actual integration tests save a scale
design, reject incompatible question range/scope/deletion while keeping its
revision intact, clone it, reuse a template and export/import a real portable ZIP
with remapped references. A real participant final receipt queues an independently
running, fenced scientific child whose saved score matches the hand calculation.
Additional real jobs verify separate imported repeated assessments and preserve
ordinary item summaries when assessment mapping is absent. Publication hashes,
implementation identity, complete CSV output and immutable reopen behavior are
checked. These are original synthetic fixtures, not a clinical or psychometric
validation study.
