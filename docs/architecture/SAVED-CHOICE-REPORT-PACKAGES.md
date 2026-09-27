# Complete saved choice reports

Scoped saved-report checkpoint, 27 September 2026. The connected worker,
researcher, independent complete-export and cold-restart checks have passed.
Read the [source-phased acceptance](../qa/CHOICE-REPORT-PACKAGE-ACCEPTANCE.md)
for the exact tested installation, original synthetic sources and remaining
limits. This checkpoint extends the existing task reports; the platform remains
unfinished.

## Researcher flow

The researcher opens saved findings, chooses **Prepare report**, reviews the
default contents, and prepares one report. Brohn schedules the necessary saved
views automatically. Native questionnaire reports can contain reaction-time
tasks, liking, scales and best-worst exercises together. Each present family
remains available; choosing one does not discard another.

Both best-worst sections initially include every saved exercise. One shows
exposure-adjusted choice counts; the other shows the saved model or its precise
unavailable/not-requested state. An exercise without a fitted model remains
visible. The researcher can choose exact exercises and numerical table pages,
or hide a figure section. The complete selected scientific source remains in
the report's numerical evidence. A shorter table selection does not crop the
complete item chart.

Preparation, progress, cancellation, retry, contents review and historical
downloads use the existing report page. No separate manual preparation workflow
is added for tasks or choices. A completed exact prerequisite can be reused;
an explicitly new implementation requires a new reviewed report version.

## What the figures mean

The count figure uses each saved item's `(best count - worst count) / complete
pair exposures containing that item`. An observed zero remains zero. A missing
denominator remains unavailable. Presented, missing and complete-pair exposure
counts retain their original meanings; they are not participant counts.

The model figure presents the saved aggregate, zero-centred paired logit
utilities in relative logit units. Report preparation does not refit the model,
estimate new uncertainty or infer individual preferences. `estimated`,
`not_requested` and `unavailable` are distinct saved states. A requested section
without utility rows uses an explanatory panel, never a fabricated zero chart.
Original diagnostics, convergence information, declared model parameters,
probabilities and null standard errors stay exactly as saved, where their
original schema includes them.

Task figures use plain labels while retaining canonical metric keys, exact
values, units and support in evidence. A single administration, an individual's
saved combined metric and a cohort mean of individual metrics are distinct.
For example, a mean of individual medians is not labelled a pooled median.

## Versioned source and preparation boundaries

Only renderer `controlled-gaze-explicit-task-choice-paired/0.1` admits complete
choice sources. Its source admission is `task-choice-findings/0.1` and its limits
profile is `controlled-task-choice-report-package/0.1`. Earlier gaze/explicit
and task renderers retain their original closed schemas and historical readers.
They still refuse choice-containing sources, including hidden choice figures.
Historical opening never upgrades a source or preparation under current code.

Supported choice sources are native/packed questionnaire analyses and imported
`explicit_choice` analyses from `brohn-maxdiff-csv-import/1.0`, using the exact
`object-case-paired-maxdiff/1.0` profile. A plotting fixture with another producer
kind is not a supported source. Every selected source and required parent is
validated in full. Unsupported scientific collections refuse complete report
assembly rather than being silently removed.

Source metadata carries an ordered applicable subset of `explicit`, `task` and
`choice`, independently of the existing task-specific source family. A new plan
pins the report renderer, explicit distribution 0.2, task display 0.2 and choice
display 0.1 implementations before any prerequisite is queued. Within each selected
report, dependencies follow explicit distribution, task display, then choice
display. Tasks and choices are mandatory complete-evidence preparations even
when their figures are hidden. Explicit distributions are required for their
selected figure sections.

The new task display 0.2 validates the full mixed source, including its choices.
The original task display 0.1 remains strict. The new tagged distribution request
also carries its explicit source admission and 0.2 implementation; historical
untagged and 0.1 tagged requests keep their old meanings. No historical reader
infers wider admission from the renderer installed today.

## Original native and imported evidence

Choice display preparation retains the original complete result and derives
only presentation rows. It does not replay delivery or rerun scoring/fitting.
For native sources, the parent process snapshots the exact original completed
run membership using the genuine `choice_display` operation and current job
lease. It compares every protocol/journal byte receipt to the scientific
producer's saved receipts and holds the copied files through worker execution
and publication. The worker checks the sealed proof and its exact source scope;
it does not treat a hash string alone as filesystem authority.

Native response timing joins the original exposure by its opaque response ID.
Run identity must agree with the exposure's saved session and provenance.
Resumed timing retains a null uninterrupted duration and its original segment
timing. Imported source-row evidence preserves every original row index/hash,
selection reason and selected mapped cells. Excluded rows do not acquire mapped
cells. Unmapped or excluded raw CSV cells are outside this saved-analysis
profile; the package does not invent a new raw-data sidecar.

Original response IDs remain verbatim. In package-alias mode, person, session,
exposure, step and clock identities are projected consistently using verified
original joins. Questionnaire, task and choice projections compose into the same
complete analysis. Null, absent, false, zero and empty arrays remain distinct.

## Complete numerical companions

The evidence ZIP includes the complete saved scientific analysis and prepared
choice evidence with the selected identifier projection. Choice companion paths
use selected report and original exercise
ordinals, independent of visible figure order:

- `evidence/choices/report-NN.json` contains the complete prepared evidence.
- `data/choices/report-NN-exercise-NNN-*.csv` contains complete saved item,
  exposure, utility, probability and timing collections where applicable.
- Imported observations and source-row evidence retain their complete separate
  companions, including selection and missing-state information.

Canonical JSON preserves optional field absence. An empty applicable collection
can have a header-only CSV; a missing-by-schema collection does not acquire
fabricated records. Coverage distinguishes numerical completeness, original raw
recordings and journal bytes. Task/choice material definitions and hashes remain
included, but their stimulus image bytes/context panels remain unsupported.
The existing optional-image control still applies to supported gaze stimuli.

Packed paired selectors use a fixed source-component rule: a task-bearing source
requires its exact task-display companion; a choice companion is eligible only
without a task component. Job completion order cannot change the selected catalog.
Missing or revoked historical task preparation does not fall back to a newer or
different choice preparation.

## Operational limits and recovery

The profile retains the current eight-source, 100-section/panel report ceiling.
Choice preparation is bounded at 20 exercises per source, 3–60 items per exercise,
and 20,000 exposures per exercise. Numerical tables use 50 rows per page. A selected
unavailable utility costs one explanatory panel. Metadata resolution and complete
worker preflight must agree; a refusal produces no partial successful package.
These are implementation ceilings, not proof of arbitrary workload performance.

Cancellation affects only exclusively owned jobs. A failed but retryable intent
still counts as a consumer of its retained shared dependencies. Explicitly
cancelling that intent releases its claim. The parent stops its child before
releasing source holds or cleaning scratch. A stale generation, cancelled lease,
changed source or expired current authority cannot publish an assembly.

The complete 50-capability/17-package platform remains unfinished. Next is
[saved event and continuous EDA beside liking](SAVED-PHYSIOLOGICAL-REPORT-NEXT.md),
followed by a separate ECG/PPG package. EEG and camera/media report families,
broader workloads, original raw-evidence bundles, task/choice image context and
post-collection restrictions remain separate work. Hardware accuracy, physical
synchronization and broader measurement validity are not established by report
rendering checks.
