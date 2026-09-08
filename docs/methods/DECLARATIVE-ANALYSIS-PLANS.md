# Reusable consumer-study analysis intentions

The `brohn-analysis-plan/1.0` record belongs to a saved design revision. It
contains a research rationale, an explicit hypothesis family and its error
threshold. It contains no participant records, dataset handles or executable
code. Cloning must remap condition/question/scale/comparison identities; portable
designs must include an integrity-bound copy of the plan in `recipes.json`.

The first registered recipe, `paired-consumer-comparisons/1.0-draft`, supports
numeric after-stimulus questions, saved after-stimulus scale scores,
valid gaze share by AOI label and sampled-gaze
fixation-candidate dwell. An AOI outcome must exist in both selected conditions.
Before/end questions cannot be silently assigned to a stimulus condition, and
categorical codes do not become quantitative scales because they look numeric.
The rating/slider/number declaration still needs the researcher's substantive
scale interpretation.

`questionnaire_scale` selects a declared scale identity. The result must carry
the exact design and scoring keys; the adapter never reuses results from a
different key or pools item rows to repair an incomplete assessment. Each eligible
score enters at its original participant/session/assessment/condition. The scale
comparison retains scored/unavailable assessment counts and hashes alongside the
complete score and item evidence. Scale and individual-item hypotheses share one
questionnaire report and therefore one family correction. See
[scale comparison evidence](QUESTIONNAIRE-SCALES.md#declared-condition-comparisons)
for the original repeated-assessment example and 31 additional scoped checks.

For each chosen outcome, eligible observations are averaged within a person's
condition/session, test-minus-reference differences within person, then people
receive equal weight. Missing responses remain missing. A repeated visit is not
an additional person. With at least two independent people and nondegenerate
between-person variance, the recipe reports the paired Student t result and
unadjusted 95% interval. A constant observed difference retains its descriptive
estimate without claiming a zero-width uncertainty interval.

When all declared hypotheses belong to one saved report, Holm adjusts available
p-values across the full declared family, including unavailable hypotheses.
When the report contains only a subset of the declared modalities, unknown other
p-values prevent a complete joint ordering: conservative Bonferroni bounds use
the full family size. The report records this distinction. A reviewed combined
report can apply Holm across its explicitly selected complete family. Neither
route silently shrinks the family after missing data or outcome selection.

A plan frozen into a participant's protocol predates that participant session.
That evidence does not establish external preregistration, independence from
earlier pilot results or a confirmatory study. For imported recordings, the
relative timing of collection and plan selection is unestablished unless
separate provenance supports it. The report states the evidence it actually has.

An empty declared family requests descriptive output; an older design without
this optional record retains its existing behavior. Unregistered analysis
recipes still require their own validators and workers. This plan does not
replace acquisition settings, calibrated signal mappings or event-window
declarations.

Current evidence: `tests/platform-analysis-plan.R` has 15 independent checks for
repeated-person arithmetic, missing pairs, inference, identity support, family
correction and declarative reference/clone validation. The actual browser journey
in `tests/researcher-analysis-plan.mjs` passes 29 checks and four desktop/narrow
axe scans. It authors a two-measure family, clones and exports/imports the design,
then completes four visits with one repeat participant and one missing pair.
The worker-generated cohort has the independent expected effect of 2, two
eligible people and three paired visits, with the correct full-family Bonferroni
bound and explicit timing provenance in HTML/CSV/JSON. These are synthetic
software checks; they do not establish human usability or scale validity.
