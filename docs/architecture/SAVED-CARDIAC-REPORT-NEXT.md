# Next saved ECG/PPG report package

28 September 2026. **Read-only implementation proposal, not enabled admission or acceptance.** This refines the cardiac follow-on in [the physiological report plan](SAVED-PHYSIOLOGICAL-REPORT-NEXT.md). All 50 capabilities and 17 work packages remain in scope and retain their existing status. BWP09 owns method meaning; BWP04/BWP06/BWP13/BWP15/BWP17 own the corresponding source, lifecycle, presentation and QA work. No scientific processing, service or production code was changed for this review.

## Exact saved families to qualify

| Existing producer | Saved evidence to preserve | Boundary |
|---|---|---|
| `physiology`, ECG, `ecg-neurokit-detected-rr/1.0` | `analysis.kind="ecg"`, `modality="ecg"`, `schema="brohn-worker-result/1.0"`; complete analysis, effective per-recording parameters, source/engine identities, features, recordings, quality and typed artifacts. | Detected R-peak intervals (RR), not confirmed normal-to-normal HRV. |
| `physiology`, PPG, `ppg-elgendi-detected-prv/1.0` | Same registered worker schema, PPG kind/modality, saved Elgendi output and exact source units. | Pulse-rate variability (PRV), not interchangeable with ECG HRV. |
| `reanalyse_cardiac`, ECG or PPG, `cardiac-source-exclusion/1.0` | Saved child report plus exact parent report, review ref, accepted preview, exclusion ledger, surviving-run artifacts and original detector parameters. | This producer really reruns cleaning/detection. Package preparation must consume its existing result, never call this operation. |

Admission must verify actual operation, schema, modality, recipe, implementation and mandatory collections together. A physiology container or an ECG label is insufficient. Current EDA admission explicitly refuses other physiological families (`platform-eda-display-sources.R:19–21`); keep that behavior until a separately versioned cardiac profile is qualified. Unknown collections and unsupported required parents remain refusals. Study provenance must already exist; do not invent it for standalone imports.

## Complete numerical coverage

`physiology_artifacts.py:324–383` writes `brohn-physiology-tables/1.0` streams of kinds `physiology-series` and `physiology-events`:

- Time tables contain `time_s`, global `source_sample_index`, `raw`, `clean`, and `retained`, plus exact recording/channel/segment identity, source clock, bounds, units and method support. Cardiac `raw` is unit-converted pre-cleaning input, not original CSV/TSV bytes. ECG uses µV; PPG preserves its declared a.u. or converted voltage units. Do not silently standardize either waveform for export.
- Temporal event tables contain type, time, segment-local `sample_index`, original `source_sample_index`, nullable previous interval in ms, and nullable plausibility. The first peak has no preceding interval; an implausible interval is not a missing detection or a confirmed abnormal beat.
- Available interval spectra are **separate frequency tables inside the event artifact**, with all saved Hz and ms²/Hz bins and `brohn-cardiac-interval-spectrum/1.0` support. Total event-artifact rows include spectral bins and cannot be labelled detected-beat counts.
- Retain every saved feature and numerator/denominator, including separate mean-interval-derived rate and mean interval rate, sample SD, successive-pair support, candidate pNN50, and saved LF/HF powers/reasons. Do not recompute them from the illustrated window or substitute a familiar formula. The current pNN50 candidate denominator is retained intervals; rejected intervals do not create successive pairs across a gap.

The current producer writes both table kinds for a computed cardiac run, including an empty temporal event table where applicable; an all-unavailable result can have no artifacts. Validate this against genuine originals before freezing admission rather than fabricating empty streams. Earlier artifacts that lack the `raw` column need an explicit historical coverage policy: show input waveform unavailable while preserving their complete saved evidence, if qualified, or refuse that family precisely. Preparing a report must never trigger reanalysis to fill the missing input.

Typed JSON/NDJSON and all-row CSV companions cover the complete selected and required sources independently of figure choices. Preserve nulls, Boolean plausibility, string identities and lexical/source descriptors; CSV alone is not the lossless oracle. Original input bytes remain separate unless a future raw-bundle profile explicitly includes them.

## Exclusion lineage and unavailable outcomes

The saved `brohn-cardiac-exclusion-ledger/1.0` contains half-open zero-based source spans, individual decisions/reasons/notes, normalized union, surviving runs, edge guards and support counts. `cardiac_review.py:266–284` additionally records curated endpoint identities and a reference to the full CSV/decision crosswalk. Those endpoint records are not the complete acquisition crosswalk.

Qualify a recursive reader for exact child → parent → mapped dataset → review/preview/catalog → curated stream/import/raw dataset and retained acquisition/normalization provenance when present. Verify original producer receipts and currently authorized source access without replacing any ref with its latest head. Distinguish zero-based derived CSV rows from original one-based acquisition sequences, and keep original clocks/person/session links. For complete review context, decide and document the derived crosswalk companion; do not claim complete row lineage from endpoints alone. No aliases may be joined solely by matching labels or timestamps.

Keep `completed`, `partial` and `insufficient_support` results and all per-run unavailable reasons. Saved frequency support requires at least ten intervals, all plausible, and the declared minimum peak span (at least 300 s in this recipe). Insufficient support yields no spectral table. Legitimate zero density/power remains zero; zero HF leaves the ratio unavailable with its saved reason. No filtering state, interval, RMSSD or spectrum is pooled across excluded runs. Parent and child figures must state their different support rather than imply an improvement score.

## Same one-Prepare experience

From a saved cardiac report, **Prepare report** selects that exact report and all its applicable cells by default. Existing liking sources can be included in the same contents editor. A durable intent automatically prepares missing descriptive cardiac views and explicit distributions; it never queues `analyse_dataset`, `reanalyse_cardiac`, detector, interpolation or Welch estimation. A spectrum figure reads saved bins. Any new interval view uses saved interval rows only and requires an explicitly defined display contract.

Proposed default: each saved recording/channel/run has a waveform view with separate labelled input and cleaned traces, saved detections, plus its saved interval spectrum or an explanatory unavailable panel. Keep a concise basis/support summary visible. Exclusion reviews also show their saved reasons and run boundaries. Related parent evidence need not add parent figures automatically. Exact cells, waveform component, display window and numerical pages are optional advanced choices; none is a mandatory prerequisite button.

Metadata needed before API freeze: exact report ref and closure hash; modality/recipe; cell key and original record index; recording/channel/run/table identities; saved component availability/units; original time bounds; waveform/detection/spectrum availability with distinct reasons; exact feature/support metadata; artifact/table row counts; prepared-ref binding; requested/resolved figure and marker coverage. Original source windows must be discoverable without a prior successful display so a resource refusal can be recovered. Queue/UI paths remain bounded metadata reads; full validation, hashing, joins and plotting run under supervision.

History pins its original request, prepared models, producer identities and artifact bytes under current-reader checks. Applying edits creates a draft; Prepare saves a new intent. Cancellation, shared prerequisites, retry and code-drift review reuse the existing lifecycle. Complete-data limits must identify source/resource/recovery, rather than advise hiding figures when only fewer source rows would help.

## Concrete implementation gaps and qualification

1. `brohn_queue_signal_view` (`platform-signal.R:52`) starts at the report head. Reuse pure geometry, not this queue, for historical package preparation. `cardiac_review`/preview entities are separate objects, not scientific report refs.
2. Existing cardiac marker overlay stops at 2,000 selected markers with `too_many_markers` and `alignment="not_checked_display_limit_exceeded"` (`platform-signal.R:133–143`). This cannot prove complete default marker membership. Freeze a report policy that validates **all** source joins, then explicitly pages or summarizes markers with honest coverage and panel counts. Never silently show the first 2,000 or borrow EDA's 50-candidate policy without a cardiac decision.
3. Source/ledger schemas and parent closure are not yet registered in the package projection/alias registry. Preserve complete artifacts and unavailable records before enabling metadata choices. Scientific fields cannot be dropped merely to make a figure fit.
4. Qualify the normal 60-second worker lease across source preparation, child execution and full publication validation, including the newly observed EDA lease-starvation boundary. Keep ownership fences, cancellation, source holds and resource limits intact.

Freeze genuine direct ECG/PPG, no-spectrum/zero-power, gap/short-run, all-unavailable and after-exclusion originals before export tests; include a curated acquisition source with nonzero indices and two people. Independently compare every scientific value, typed row, marker-to-waveform join, spectrum bin, ledger span and crosswalk identity. Test focused versus complete evidence, old refs after new review revisions, tampering/permission changes, missing required parents, limit recovery and shared-job cancellation. Then run actual one-Prepare/download/edit/history/cold-restart journeys with unchanged scientific job counts and inspect 390 px, desktop, keyboard, tables, standalone SVG and print output.

Existing cardiac spectrum/input/marker/exclusion suites are prior component evidence, not acceptance of this package. Display “Detected RR” or “Detected PRV”, saved support and qualification flags in plain language. No new cardiac–liking estimate, NN classification, stress interpretation, clinical validity or physical-device/timing qualification is claimed. Other physiology, EEG, media, raw bundles and method validation remain in the full roadmap.
