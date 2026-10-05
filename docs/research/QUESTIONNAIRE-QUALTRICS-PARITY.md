# Questionnaire flow, automation and dashboard requirements

Owner requirement, 1 October 2026: Brohn's questionnaire must match or exceed
Qualtrics for survey-flow changes, automatic analysis and visualization dashboards.
This is an implementation and researcher-acceptance target, not a present parity
claim. It extends the [questionnaire blueprint](../planning/QUESTIONNAIRE-BUILDER.md),
which already records 16 competitor screen snippets. Preserve its distinction
between observed screens, documented behavior and proposed Brohn behavior.

The [assigned-questionnaire delivery contract](../architecture/ASSIGNED-QUESTIONNAIRE-DELIVERY.md)
tracks QF01's active collection/recovery integration and its remaining performance,
storage and complete-journey gates. Component qualification does not activate it.

5 October implementation gap: QF01 must also support genuine questionnaire-only
studies through authoring, compilation, release, participant execution and saved
analysis. Current variant release admission requires stimulus concepts/sets.
Add an explicit supported study mode; do not manufacture dummy exposures or skip
compiled steps. This remains part of Qualtrics parity, not an accepted capability.

## Benchmark and current boundary

Official product documentation was rechecked on 1 October 2026. The benchmark
includes Survey Platform, Results Dashboards, Stats iQ and Text iQ; features and
permissions differ across licenses and project types. Public documentation is
feature evidence, not an executed competitor journey or a measured usability
comparison. New Results Dashboards is the dashboard reference: the official
[migration guide](https://www.qualtrics.com/support/survey-platform/reports-module/results-dashboards/migrating-to-results-dashboards/)
announces the end of Legacy Results-Reports on 1 October 2026. Do not rebuild an
obsolete interface or infer that every tenant has the same rollout state.

| Area | Official benchmark | Brohn evidence and required extension |
|---|---|---|
| Whole survey flow | Ordered blocks, branches, embedded data, randomizers and endings are flow elements. [Survey Flow](https://www.qualtrics.com/support/survey-platform/survey-module/survey-flow/survey-flow-overview/) | Existing before/after-each/end placement and question display rules are partial. Add a structured block-flow editor, conditional routes, explicit endings and readable path preview. Include stimuli, tasks, baseline/rest and equipment stages in the same study sequence. |
| Logic changes | Display, branch and skip logic serve different routing purposes. [Using Logic](https://www.qualtrics.com/support/survey-platform/survey-module/using-logic/) | Existing typed nested AND/OR/NOT display editor is a foundation, not a general branch engine. Add route diagnostics, answer-change invalidation and semantic revision review without changing already released sessions. |
| Experimental allocation | Randomizers can choose flow elements and optionally track even presentation. [Randomizer](https://www.qualtrics.com/support/survey-platform/survey-module/survey-flow/standard-elements/randomizer/) | Preserve option/section order policies. Complete EF02/03 version-set and arm assignment, keeping shared controls explicit. Distinguish order, subset selection, started-run allocation and completed-sample balance. |
| Repeated content | Loop & Merge repeats a question block using row or answer context. [Loop & Merge](https://www.qualtrics.com/support/survey-platform/survey-module/block-options/loop-and-merge/) | After-each-stimulus questions are supported; arbitrary bounded repeats remain open. Each repeat needs an occurrence, exposure referent, independent answer history and recorded realized iteration order. |
| Response reuse | Selected choices can populate a later question. [Carry Forward](https://www.qualtrics.com/support/survey-platform/survey-module/question-options/carry-forward-choices/) | Add typed carry-forward selections, exclusive/other choices and selected/unselected policies. Preserve original option identities and offered sets across edits, review and export. |
| Dynamic wording and variables | Piped text inserts chosen response or metadata representations. [Piped Text](https://www.qualtrics.com/support/survey-platform/survey-module/editing-questions/piped-text/piped-text-overview/) | Add named typed variables and accessible insertion chips, escaping and missing-value fallback. Researcher-only fields must not become participant payloads merely because they exist in a study. |
| Question and instrument authoring | The original blueprint records question formats, validation, reusable content and scoring. [Existing screen inventory](../planning/QUESTIONNAIRE-BUILDER.md) | Retain 12 implemented types, illustrations, exact typed values and scale keys. Reconcile exclusive options, requested versus required answers, choice-level visibility, forms, translations and reusable instruments before declaring coverage. |
| Dashboard construction | Report, blank and private pages support configurable widgets and filters; available widgets depend on field type. [Results Dashboards](https://www.qualtrics.com/support/survey-platform/reports-module/results-dashboards/results-dashboard-overview/) | Complete-answer exploration and saved distributions already exist. Add saved dashboard definitions, chart selection, shared filter context, cross-filtering, audience access and exact filtered exports. A paginated answer table is not dashboard parity. |
| Statistical assistance | Stats iQ provides descriptive, relationship and regression workflows; advanced access adds other tools. [Stats iQ](https://www.qualtrics.com/support/stats-iq/getting-started-with-stats-iq/overview-stats-iq/) | Extend declared scale and comparison recipes into guided design-aware analysis. Explain estimand, eligible sample, assumptions, effect and uncertainty. Do not rank findings solely by smallest p-value or claim a method because an R package is installed. |
| Segments and tables | Crosstabs combines survey and metadata fields; its documentation limits transferring crosstab results into dashboards. [Crosstabs](https://www.qualtrics.com/support/survey-platform/data-and-analysis-module/cross-tabulation/cross-tabulation-overview/) | Build one reusable saved-result model for tables, figures and reports, with explicit response/person denominators and multi-response semantics. Weighting, repeated observations and sparse cells need their own qualified recipes. |
| Open text | Text iQ supports topic and sentiment analysis with tier-specific functionality. [Text iQ](https://www.qualtrics.com/support/survey-platform/data-and-analysis-module/text-iq/text-iq-functionality/) | Retain raw text and build reviewable coding, named language/model/version, corrections and uncertainty. Topic/sentiment output is not a direct measure of emotion or an independently validated psychological construct. |
| Accessibility | Survey accessibility checks identify issues, with behavior depending on survey experience. [Accessibility](https://www.qualtrics.com/support/survey-platform/survey-module/survey-tools/check-survey-accessibility/) | Preserve native keyboard controls and numerical chart alternatives. Test actual author and participant journeys, errors, focus, zoom, narrow layouts and assistive technology; automated scans alone cannot establish accessibility. |

Existing scoped evidence: [display logic](../methods/QUESTION-FLOW-BUILDER.md),
[sections](../methods/QUESTIONNAIRE-SECTIONS.md),
[option assignment](../methods/QUESTION-OPTION-ASSIGNMENT.md),
[answer revision](../qa/QUESTIONNAIRE-ANSWER-REVISION-CONTRACT.md),
[scale scoring](../methods/QUESTIONNAIRE-SCALES.md),
[complete-answer explorer](../qa/QUESTIONNAIRE-EXPLORER-ACCEPTANCE.md) and
[explicit distributions](../qa/EXPLICIT-DISTRIBUTIONS-ACCEPTANCE.md).
Each acceptance applies to its recorded source and workload. Current scale
scoring does not implement reliability, factor models or normative classifications.
An inactive participant-projection or assignment component is not a released
survey capability.

The complete-answer explorer's filters select records; they do not recompute its
saved whole-report summaries. Current categorical distributions preserve complete
structured values, not separate option, matrix-row or rank-position summaries.
QF05/QF06 must add those explicit projections with appropriate denominators:
multi-choice selection rates, matrix-row distributions, rank-position counts and
allocation amounts. Never average category codes or label an unchanged saved
summary as the result of an active filter. Existing declared paired comparisons
remain credited; broad survey modelling is still separate unfinished work.

## Intended researcher experience

Use the existing **Plan → Questions → Collect → Review → Results** navigation.
Questions offers a questionnaire list and a study-flow view over the same draft,
not two incompatible editors. A selected item has **Answer format**, **When it
appears** and **How it is used**. Plain-language rules disclose their source and
show a representative participant path. Keyboard buttons provide every drag
operation. Moving a block updates the path preview and identifies affected
dependencies before saving; it never silently rewrites a scientific instrument.

Guided creation starts with the consumer question and an editable supported
template: packaging/shelf, advertisement, digital UX, sensory/product or brand
association. Controls, versions, explicit liking and modality-specific support
share one study definition. Asking after each assigned material should not require
manually duplicating the questionnaire. Advanced settings remain available with
their consequences visible.

Collect has one readiness summary and direct links to fix the exact issue.
The preview can supply sample answers, explain why a block appeared or was
skipped, and show assignment variants. It must not consume live allocation,
quotas or real participant records. A new published revision applies to new
runs; existing runs and saved findings retain their original definition.

Results initially opens a generated study dashboard: collection/data quality,
explicit answers, declared comparisons and available linked measurements.
Cards show the question being answered, estimate/distribution, uncertainty when
supported, unit, eligible support and a plain-language interpretation. Filters
are visible as removable chips with a reset action. A card opens its exact table,
missing/excluded cases, settings and academic evidence. Unavailable results explain
why and offer a useful next action, without inventing values.

The intended advantage is a single source-preserving path from study design to
explicit and implicit findings: liking beside gaze/AOIs, EDA, EEG, ECG/HRV or PPG
PRV, temperature and other supported measures. Joins require the correct person,
session, exposure and timing support; no synchrony or person identity is inferred
from row position. Missing gaze must not erase a valid liking response. An
interactive dashboard and an exported report use the same retained result and
filter definition, preventing contradictory numbers in separate tools.

## Architecture and automatic analysis contract

1. **Design and compilation:** add versioned typed flow nodes and variable
   declarations to the canonical R domain. Validate reachability, references,
   repeat bounds, permitted paths, instrument order, allocation and endings.
   The UI edits this domain; it does not execute researcher-supplied R or JavaScript.
2. **Participant execution:** compile only the assigned runnable presentation.
   Retain original protocol/source identity privately; opaque presentation keys
   map back to exact source events. Browser and receiver share tested semantics
   for zero, false, null, empty collections, revisions and repeated occurrences.
   Both current and legacy asset routes enforce assigned-material access.
3. **Collection and history:** preserve offered/seen/answered/declined/hidden/
   invalidated states, exact raw answers, append-only revisions, assignment and
   exposure records. Typed analysis values remain distinct from labels. Draft,
   published, preview, pilot and live origins remain explicit.
4. **Analysis:** the saved analysis plan chooses named supported recipes. Sealed
   runs or accepted imports can automatically enqueue eligible dependency jobs;
   retries are idempotent and changed scoring/filter inputs create new saved
   results. Automatically calculate what is justified by the design, and explain
   missing prerequisites instead of selecting convenient tests after seeing data.
5. **Results and dashboards:** store a versioned dashboard definition containing
   source revisions, cohort/filter AST, field definitions, units, estimands, chart
   specifications and access policy. UI queries return bounded projections of
   complete results. Prepared aggregates carry exact provenance; they cannot be
   derived from truncated previews or stale cached permissions.
6. **Sharing and reuse:** clone/portable designs preserve logic, variable and
   instrument references while issuing new structural identities. Reports retain
   original settings, denominators, exclusions, source versions and citations.
   Refreshing data creates an explicit new snapshot; opening history does not
   silently rerun or rescore it. Shared dashboards respect current access, while
   already downloaded copies cannot be revoked.

Automatic analysis coverage must include typed distributions, response/missing
support, instrument scoring, appropriate reliability, declared contrasts and
cross-tabs, repeated-measure models, weighted survey estimates, association/
regression, text coding and available multimodal relationships. This is a
required option inventory, not a statement that these methods are enabled.
Separate descriptive exploration from planned inference and prediction. Retain
participant/stimulus hierarchy, model diagnostics, multiplicity, missingness,
weight source/effective support and held-out validation where applicable.
Follow the [academic evidence contract](../methods/ACADEMIC-EVIDENCE-CONTRACT.md):
multiple suitable academic sources and independent reference cases for each
consequential option. Competitor documentation is not scientific validation.

## Ordered delivery and acceptance queue

These QF items refine existing BWP03/04/05/09/13/14/15/17 and PC02/03/05/06/07/13/16;
they do not create replacement packages or close the existing scope.

| ID | Deliverable | Starting state | Required acceptance |
|---|---|---|---|
| QF01 | Exact participant questions under stimulus-version assignment | Inactive implementation in progress alongside EF02/03 | All 12 types and branches agree across R and browser; typed values, control membership, history, resume, old releases and assigned-only assets remain correct. |
| QF02 | Whole-study flow authoring and route simulation | Existing placement/display editor; broader flow planned | Nested block routes, explicit endings, unreachable/dependency errors, semantic change preview and safe revisions through actual researcher and participant journeys. |
| QF03 | Variables, piping, carry-forward and bounded repeats | Planned beyond fixed after-each behavior | Typed/missing values, translations, escaping, answer revisions and every repeat instance survive collection, clone/import, analysis and cold restart. |
| QF04 | Question/instrument completeness and reuse | Partial | Reconcile the blueprint taxonomy and limits; prove mobile/keyboard inputs, validation, instrument wording/keys, accessible translations, portable reuse and chosen control/version contexts. |
| QF05 | Guided automatic survey analysis | Partial scoring, comparisons and distributions | Supported design-to-recipe mapping, independent numerical checks, option-specific evidence, quality/missingness, rerun history and understandable findings for each enabled family. |
| QF06 | Editable unified dashboards | Existing saved views/explorer; dashboard authoring planned | Generated usable default; configurable pages/charts; global and card filters; exact underlying tables, uncertainty, exports and saved source/permission behavior. |
| QF07 | Advanced segmentation, weighting and text | Planned separate qualified recipes | Appropriate models and denominators, reviewed text/model provenance, no unsupported latent constructs, exact reusable outputs in dashboards and reports. |
| QF08 | Comparative end-to-end researcher QA | Open | Complete the journeys below on the actual integrated build and record feature coverage, task success, errors, accessibility, interactions and timing. |

## Researcher QA and definition of done

Use a synthetic consumer study with a screener, common control, two package
versions, explicit liking, one reusable scale, a conditional follow-up and gaze
input. Extend with a mixed task/physiology study and a repeat-product survey.
Synthetic fixtures test behavior; they are not participant research.

- Create, reorder, preview and publish; explain every realized branch and arm.
  Change an earlier answer and verify dependent answers are retained historically
  but excluded or re-collected according to the saved policy.
- Exercise screen-out, declined consent, partial response, interrupted resume,
  closed recruitment, missing modality and stale draft. Preview and test runs
  must not alter live allocation or published results.
- Clone and portable-export/import the design; verify all structural references,
  material identities, instrument keys and method evidence. Original studies and
  already running sessions remain exact after later edits.
- Automatically produce eligible findings. Independently reconcile each chart,
  filter, crosstab, denominator and missing state with complete saved records.
  Multi-select percentages need an explicit denominator; repeated observations
  are not independent people; numeric-looking categories are not continuous data.
- Change cohort filters, inspect a comparison, save a dashboard and export it.
  Reopen after a cold restart; verify the same source/filter snapshot and numbers,
  current access, failed-job recovery and a separately requested refresh.
- Complete author and participant tasks using keyboard and narrow layouts;
  inspect screen-reader labeling/focus, contrast, zoom, chart tables and error
  recovery. Record actual human usability work separately from automated checks.

Retain the blueprint's low-click targets: at most five activations for the
prepared sample and four design decisions/twelve activations for its defined
prepared real-study path. Measure the whole stated journey, including mandatory
dialogs. Set and test representative dashboard workloads and latency budgets
before launch; the currently slow cardiac saved-open path is an unresolved
integration issue, not acceptable dashboard performance. No blanket "better than
Qualtrics" claim is justified by this requirements document or a component pass.
