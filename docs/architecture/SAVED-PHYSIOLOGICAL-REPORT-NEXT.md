# Next complete physiological report packages

Planning contract, 27 September 2026. **Not an enabled package profile.** This
continues [the workstream](../WORKSTREAM.md) after the separately gated choice
report checkpoint. All 50 capabilities and 17 work packages remain in scope.

The first cohesive extension is **exact saved event-related and continuous EDA
beside liking**. Follow it with a separately qualified **ECG/PPG** profile,
including saved after-exclusion results. Both consume saved scientific evidence;
opening, preparing or exporting a package must not rerun analysis.

## EDA package

Preserve the complete saved report, original method/parameters, features,
recordings, measured events, segments, source masks, typed processed streams and
verification receipts. Support the registered continuous
`eda-neurokit-highpass/1.0` and event `eda-event-highpass/1.0` /
`eda-event-cvxeda-defaults/1.0` recipes through explicit schema checks. A plot
preview is not the full numerical evidence.

Keep authored baseline/response/latency/recovery windows, overlap policy,
nuisance events, retained/excluded runs and exact source clocks/indices. A
supported nonresponse can have magnitude zero while responder amplitude remains
null. Incomplete support or an unobserved onset is unavailable, not nonresponse.
Continuous peaks have no implied event attribution; relative prominence is not
an absolute conductance threshold. Missing recovery is never invented.

Event and continuous candidate schemas remain distinct. Their table-row,
segment-local peak and original-source sample indices are different identities;
bind them to the exact artifact/report/recording/channel/segment. Preserve the
producer's exact zero/one/two artifact presence when no tables were produced,
with the original unavailable support. Do not require fabricated empty streams.

Complete processed EDA artifacts contain cleaned, tonic and phasic values;
**they omit raw conductance**. Coverage must state that original dataset bytes
remain separate. Preserve every existing processed row rather than reconstructing
raw data from previews. Focused figures/pages must not trim the full evidence.

One durable Prepare report action should resolve exact EDA display prerequisites
automatically. A bounded metadata catalog identifies saved event/channel or
segment/channel choices; a supervised worker builds immutable display models
from sealed complete streams. Default event views show phasic conductance and
the original support window; continuous views show tonic and phasic conductance.
Cleaned traces and focused windows are optional figures. Unavailable cells retain
explanatory panels and their numerical records. Resolve the actual panel budget
before publication rather than silently selecting the first page.

EDA and liking can be presented together without a new association estimator.
The existing multimodal extractor accepts physiology feature scopes `recording`
and `recording_condition`; event EDA uses `event`. This package must not silently
convert that scope or imply a newly available event-level paired comparison.
Any already saved supported contrast needs its exact source closure and complete
original support.

## Reuse and integration boundaries

| Existing implementation | Use in the new package |
| --- | --- |
| `R/platform-eda-review.R` and `scripts/workers/eda_review.py` | Exact event selection, complete source checks, saved feature preservation and display-only window preparation. |
| `R/platform-eda-continuous-review.R` and its Python worker | Decimal source-window membership, continuous candidates, missing endpoints and complete sample/candidate/marker exports. |
| `brohn_eda_review_svg` / `brohn_eda_continuous_review_svg` in the corresponding view files | Reuse pure geometry and support annotations, without installing the explorer controllers. |
| `R/platform-physiology-artifacts.R` and `scripts/workers/physiology_artifacts.py` | Complete typed NDJSON validation, units/nullability, table identities, coordinates and provenance. Stream the evidence; do not load millions of samples into Shiny. |
| `R/platform-signal-values.R` | Exact all-source-row export precedent and immutable source/catalog binding. Numerical pages remain distinct from complete evidence. |
| `R/platform-report-package-sources.R` and prepared-report lifecycle | Add explicit versioned physiological admission, exact prepared refs, current-reader checks and complete recursive parent closure. Older profiles remain strict. |

Existing explorer APIs are not interchangeable with historical package readers.
The generic signal queue begins from the report head; the event UI checks its
current head; EDA prepared readers compare against loaded implementation.
Introduce a pinned historical reader that verifies the original artifact and
producer identity while checking current source permission. Do not regenerate
an older package under current defaults. Queue/catalog work must stay bounded
metadata work; full parsing, hashing and source verification belong behind the
supervised preparation boundary.

Use a new explicit admission profile. A selected report or required parent with
unsupported EEG, ECG/PPG, respiration, EMG, fNIRS, temperature/movement or
camera/media evidence must refuse until that entire family is supported.
Likewise refuse unknown scientific collections. Do not remove unsupported
contents from a mixed report to make an EDA figure fit. Integrate with the
accepted task/choice profiles without loosening their historical
contracts.

## Subsequent ECG/PPG package

Retain all saved pre-cleaning input and cleaned waveforms, detection events,
previous intervals/plausibility, per-segment features, complete spectrum bins,
method settings and support. Cardiac `raw` means unit-converted input values,
**not original file bytes**. ECG remains detected RR; PPG remains PRV. Neither
screening nor manual exclusions establishes normal-to-normal intervals. Preserve
missing first intervals, broken successive-pair support, SD and frequency
availability, and zero-power reasons. Do not pool independent runs or turn LF/HF
into a stress measure.

`brohn_signal_svg`, marker helpers and saved interval-spectrum metadata provide
rendering seams. The `cardiac_review` operation actually reruns the original
cleaner/detector after exclusions; export must read its **saved child report**,
parent and exclusion ledger instead. Preserve half-open sample spans, reasons,
remaining-run support and any curated acquisition crosswalk. Original filter
edges, researcher exclusions and source curation remain distinct.

## Decisions and acceptance before activation

- Start study-bound, matching the existing report workflow, unless standalone
  reports receive their own explicit contract. Do not invent study provenance.
- Keep the current 256 MiB package ceiling; declare smaller per-stream and
  aggregate preparation bounds before implementation. Typed physiology permits
  larger sources, so refusal must explain recovery without silently dropping
  rows. A wider format/workload profile needs separate qualification.
- Pin complete source/curation lineage under native holds before the worker;
  recheck current authority and the job lease at publication. Hold exact prepared
  artifacts during downloads. Declare identity projection paths in typed table
  headers, support metadata, masks and events before aliasing.
  Alias-transformed streams require new derived hashes/bytes/provenance linked
  to original immutable descriptors. Typed JSON/NDJSON is the lossless evidence;
  CSV renders null as blank and protects formula strings, so it cannot establish
  type/string preservation on its own.
- Generate genuine synthetic scientific originals before the export boundary:
  response/nonresponse/overlap/gap/edge event cases, continuous missing-endpoint
  and short-segment cases, plus liking. Freeze an independent all-row/value oracle.
- Test exact history, focused versus complete evidence, unavailable states,
  unsupported mixed parents, payload/panel refusal and recovery, checksum
  refusal, cancellation, current-reader restrictions and child lifetime.
- Run the normal researcher prepare/download/edit/history flow, inspect desktop
  and phone output, compare complete values independently, then cold-restart with
  unchanged original science and no new analysis jobs. Keep earlier classic,
  task and choice packages exact.

Existing EDA review and cardiac spectrum/exclusion tests are useful separate
software evidence; their [EDA event](../qa/EDA-EVENT-REVIEW-ACCEPTANCE.md),
[continuous EDA](../qa/EDA-CONTINUOUS-REVIEW-ACCEPTANCE.md),
[cardiac spectrum](../qa/CARDIAC-SPECTRUM-ACCEPTANCE.md) and
[cardiac exclusion](../qa/CARDIAC-EXCLUSION-ACCEPTANCE.md) records do not constitute
acceptance of these new packages. Physical timing, detector/construct validity,
larger workloads and hosted operations retain their own gates.

BWP09 owns EDA/cardiac methods, with BWP04/BWP06/BWP13/BWP15/BWP17 integration.
PC02/PC05/PC13/PC16 advance; PC07 performance and PC12 timing/annotation meanings
remain constraints. Other report families, task/choice image context, raw
bundles and scoped post-collection restrictions remain in the full roadmap.
