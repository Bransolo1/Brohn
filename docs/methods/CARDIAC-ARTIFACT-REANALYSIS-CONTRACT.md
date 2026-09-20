# Source-bound cardiac artifact review and recalculation

Date: 20 September 2026. **Implemented bounded software contract; [executed acceptance](../qa/CARDIAC-EXCLUSION-ACCEPTANCE.md) records the exact tested scope.** Production detector methods remain unchanged. This contract concerns researcher-selected waveform exclusions followed by a new analysis. It does not introduce automatic artifact detection, beat correction, NN classification or physical device qualification.

## Decision and evidence

The bounded first route lets a researcher review one exact ECG/PPG input waveform, mark unwanted sample spans, inspect the resulting support, and calculate a **new report from separately filtered surviving runs**. Preserve the original source, detections, report and every review revision. Never join time or create an interval across an exclusion.

The [recorded PPG evaluation](../qa/PPG-RECORDED-REFERENCE.md) motivates this work. All 5,400 scored pulses outside supplied artifact spans matched within the prespecified strict 50 ms tolerance, but smaller timing errors still changed RMSSD. Whole-record detected RMSSD was 115.16 ms in CapnoBase 0123; independently excluding supplied artifact intervals from endpoint scoring gave 27.88 ms. That evaluation **did not rerun filtering after masking**. Its score must not be presented as the expected output or validation of this proposed preprocessing route. Labels inside artifact are not reliable physiological truth. The eight examined records are now known regression data, not a fresh holdout.

The design distinguishes academic guidance, existing implementation and proposed engineering policy:

| Primary basis | What it supports here | What it does not establish |
| --- | --- | --- |
| [ESC/NASPE Task Force, 1996](https://www.escardio.org/static-file/Escardio/Guidelines/Scientific-Statements/guidelines-Heart-Rate-Variability-FT-1996.pdf) | NN requires successive sinus-origin complexes; recording duration and adjacency matter for HRV statistics. | Plausible interval lengths or manually excluded waveform spans are not a sinus-beat classification. |
| [Quigley et al., 2024 publication guidelines](https://doi.org/10.1111/psyp.14604) | Report the original electrical/pulsatile signal, sensor configuration, sampling and filtering; acknowledge the precision limits of PPG and reduced sampling rates. | A software sample-rate gate is not broad measurement qualification. |
| [GRAPH reporting guidance, 2016](https://pmc.ncbi.nlm.nih.gov/articles/PMC5070064/) | Preserve the preparation and calculation decisions needed to interpret and reproduce a study. | One acceptance rule cannot cover all research questions. |
| [Stapelberg et al., 2018, experimental addition of artifacts](https://pmc.ncbi.nlm.nih.gov/articles/PMC7313264/) | Different endpoints respond differently to contaminated intervals; assess variability endpoints as well as detection counts. | A universal allowable artifact percentage or a physiological endorsement of robust-looking metrics. |
| [Lipponen and Tarvainen, 2019](https://pubmed.ncbi.nlm.nih.gov/31314618/) | Beat classification and correction constitute a distinct algorithm with its own empirical evaluation. | Exclusion-only processing does not inherit its validation or become equivalent to corrected NN analysis. |
| [Gil et al., 2010 paired PRV/HRV experiment](https://pubmed.ncbi.nlm.nih.gov/20702919/) | PRV/HRV agreement is conditional on the signal, protocol and endpoint tested. | Pulse intervals cannot be silently relabelled ECG RR or NN intervals. |
| [NeuroKit PPG cleaning source](https://neuropsychology.github.io/NeuroKit/_modules/neurokit2/ppg/ppg_clean.html), [SciPy forward/backward filter documentation](https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.filtfilt.html) | Cleaning changes samples and has boundary behavior; NeuroKit's PPG convenience path fills missing inputs. Partition runs before invoking it. | No universally sufficient two-second filter guard follows from these sources. |

Access scope: the original article abstracts, accessible guidance/source text and locally installed NeuroKit implementation were inspected. The ESC PDF's relevant definition/duration text was available through the search index; direct PDF retrieval returned 403. The online NeuroKit documentation is a development build; the installed package and frozen code identities, not a moving documentation page, govern execution.

## Existing contracts to preserve

Implementation anchors at this review date:

- `scripts/workers/physiology.py:170` reads mapped CSV/TSV values and groups, retains the exact decimal clock origin, and converts to canonical amplitude units. A source sample index denotes an analysis-input data row, excluding its CSV header. For native recordings it has a different declared sample origin; these conventions must not be mixed.
- `physiology.py:306` splits finite, regularly sampled channel runs at missing samples and timestamp gaps before filtering. `:489` calls the named ECG/PPG detector with automatic correction disabled. `:426` preserves original interval adjacency when screening interval lengths.
- `scripts/workers/stream_extract.py:249` separates acquisition source/clock/identity boundaries and removed rows. Its complete decisions and derived CSV retain the source sequence/clock crosswalk. Its selected-channel missingness rule is listwise; a later single-channel review cannot recover rows already omitted during that preparation.
- `R/platform-stream-curation.R` pins original stream/import/dataset revisions, canonical artifacts, source bytes and the declared selection. [Stream curation](STREAM-CURATION.md) is a preparation operation, not a cardiac artifact classifier.
- `R/platform-signal-annotations.R:25` binds named windows to one complete **processed** table. [Saved interval summaries](SIGNAL-INTERVALS.md) and [interval reuse](SIGNAL-INTERVAL-REUSE.md) select and summarize saved values; they do not change preprocessing. An existing category named “artifact” must never silently acquire exclusion semantics.
- `scripts/workers/physiology_artifacts.py:286` writes complete provenance-bound series/events. The accompanying ECG/PPG writer change retains `raw`, defined as **unit-converted preprocessing input**, alongside `clean`. The original file bytes remain authoritative. Earlier reports have only cleaned series. This document does not certify the accompanying change's tests.

## Bounded first release

Implemented scope: one exact ECG/PPG source table, channel and original continuous input range per review set. Start with direct or curated CSV/TSV whose original input mapping and row association can be verified. A new result describes only that selected range; it must not appear to replace all channels, recordings or participants in its parent report. Native-format adapters require their own exact sample-origin/calibration tests before being admitted.

Keep the parent detector and its complete numerical settings unchanged. The separately named `cardiac-source-exclusion/1.0` policy is frozen with each request. A mask change, detector change, mapping change or guard change produces a different request identity and new report. Do not change the meaning of existing `/1.0` reports or quietly replay them under the new method.

The initial route requires the complete saved input column plus the authoritative analysis-input object and mapping. For an older clean-only report, offer a new analysis that preserves input samples; keep the old report readable. Do not pretend its cleaned trace is unfiltered evidence or backfill its artifact in place. A chart preview is never a numerical source.

The current input-waveform display still honors the saved analysis `retained` flag, so filter-edge samples are stored but omitted from its plotted trace. The artifact-review preview now makes those input samples inspectable and distinguishes original filter edges from researcher exclusions; the ordinary waveform view retains its prior eligibility policy.

### Researcher interaction

1. From the selected recording, open **Review artifacts**. Show input/cleaned waveforms with exact saved detections, modality, channel, person/session and original time reference. Markers remain detections made on the cleaned waveform even when drawn at the input sample's amplitude.
2. Select a span graphically or enter exact boundaries. Show the actual first/last excluded samples, exclusive sample endpoint, timestamps and sample count. A coarse chart brush proposes a span; the complete source resolves it.
3. Supply a short reason: signal loss, clipping, movement/other distortion, or researcher exclusion with a note. A suspected irregular beat can be noted, but the product does not diagnose it or certify the remaining beats as normal. Store reviewer identity only if it is actually available; otherwise a declared reviewer label is not an authenticated signature.
4. **Preview recalculation** shows the union of excluded samples, resulting separate runs, edge exclusions and insufficient-support runs. Show expected support, not predicted cardiac scores. Editing any relevant visible control invalidates this preview; native click/keyboard actions must submit current visible values before the action, including debounced numeric inputs.
5. **Save and recalculate** freezes that exact version and queues one supervised job. Present the new report beside its parent with excluded support and per-run results. Undo creates a new review revision; the old report and mask history remain available.

Keep the ordinary display compact: excluded duration/count, retained runs, and “Detected RR” or “Detected PRV; beats remain unreviewed.” Put exact associations, numerical methods and source identities in a closed details panel and complete downloads. No green physiological-quality state follows from successful calculation or manual masking.

## Source and boundary identity

Each review revision must bind the following, without public filesystem paths:

| Binding | Required contents |
| --- | --- |
| Authority | Project; current authorized source/report existence; exact parent report ID, revision and body hash. |
| Analysis input | Dataset ID/revision/body hash; original analysis-input object SHA-256 and bytes; exact source format, mapping and calibration/unit conversion; source clock origin text/unit and sampling-rate declaration. |
| Review evidence | Complete series manifest SHA-256/counts/provenance; catalog ID/revision/hash; table ID and full table-identity hash; input/clean column names and units. If detections are shown, also the same report's complete event manifest and exact event-to-series association. |
| Recording target | Source row range, recording/channel/segment, and all explicit participant/session/condition/exposure identities, preserving absence rather than inventing codes. |
| Curated lineage | Curation revision/hash, derived CSV hash and decisions artifact hash; original stream/import/dataset hashes. Join derived row → stored source sequence/segment/clock/timestamp, with original index convention stated. Never assume the derived row index equals an acquisition sequence. |
| Review decision | Review schema, revision/hash, per-span stable ID, reason/note, creation/update provenance, canonical sample spans, requested time text when supplied, and the exact resolution receipt. |
| Method | Parent detection/cleaning settings; exclusion policy version; guard policy; worker/package/code identities and resource bounds. |

Canonical bounds are zero-based source-row/sample half-open intervals `[start, end)`, within the single pinned table's input range. `end` may equal that range's exclusive end; this is an index boundary, not evidence that a sample exists there. Distinguish source indices, table row offsets, local run indices and curated acquisition sequences in names and exports.

For typed times, preserve the user's decimal text and the table's clock origin/reference. Resolve membership by actual source timestamps under the declared `[start_time, end_time)` rule; do not multiply a large floating absolute time by sampling rate or apply an inferred clock offset. Display the resolved source samples before applying. If the entered interval selects no samples, exceeds the supported source range, crosses a clock/group boundary or cannot be represented unambiguously, reject it with an actionable message. A final-sample selection can use the explicit exclusive sample-index bound instead of inventing a final timestamp.

Implemented engineering bounds are 1–64 spans per review set and one channel/table. Merge overlapping/adjacent spans for processing, but retain all original span IDs, reasons and their associations to the union; count each excluded sample once. Reject excessive spans/segments before execution. The current worker's global row/value/segment and artifact-size bounds remain in force. These caps are resource/UI policies, not scientific thresholds.

Save uses optimistic revision checking. Preview identity includes the entire form, target and source context. Queue/read/publication recheck project authority and exact frozen hashes; changed bytes, mapping, person, table or manifest fail closed. A specifically requested historical revision can run while it remains authorized and byte-identical; a new latest review revision must not silently replace it. Retries use the original frozen input. Stale or cancelled attempts cannot publish.

## Processing and interval rules

1. Re-read and verify the original analysis-input bytes and mapping; resolve the selected source range and channel. Verify the saved input column against that mapping's converted samples and coordinates. Do not run the new filter over the old `clean` column, or convert the canonical input twice. For curated sources, verify the complete row crosswalk and original lineage as well.
2. Intersect validity with the explicit exclusion union **before any cleaning, detector threshold estimation or stateful processing**. Split at every exclusion, original missing sample, clock gap/reset and identity boundary. Passing a NaN-masked entire array to a filling library is prohibited. Do not zero-fill, bridge, interpolate or concatenate surviving pieces.
3. Invoke the unchanged cleaner/detector independently on each surviving finite run. Reset filter and detector state for every run. Preserve its original source sample/time coordinates; a local array offset does not reset the report clock. Extending a neighboring run or changing any excluded values must not influence this run's computed values.
4. Apply the declared filter-edge guard independently at both ends of every run, including new mask boundaries. Save the guard's seconds and exact rounded sample counts. The existing two-second default and ten retained seconds are computational choices, **not** proof of transient removal or scientifically sufficient HRV duration. An inadequate/short run produces an explicit unavailable reason, not a zero feature. Filter padding must not read across a mask.
5. The first retained detected peak in each run has null previous interval. Every interval requires consecutive detections in the same run; every successive interval difference requires three consecutive eligible detections there. No interval crosses a removed sample even if its apparent length would pass the 300–2000 ms plausibility screen. Invalid intervals must not create new adjacent pairs.
6. Keep per-run counts, mean interval, sample SD, RMSSD and rate definitions/units. Never pool runs by deleting time, average per-run RMSSDs as a whole-record RMSSD, or count runs as participants. The first version has no aggregate across disconnected runs. ECG output remains detected RR; PPG remains detected systolic-pulse PRV. `normal_to_normal_confirmed` remains false. A future event-editing or NN route requires a separate method and validation.
7. Spectral estimates require the unchanged profile's complete plausible intervals and minimum continuous detected-peak span **within one run** (currently at least 300 seconds). Ten 30-second runs are not a five-minute spectrum. Existing declared within-run interval interpolation for Welch remains distinct from forbidden interpolation across exclusions; preserve its bins, units, settings and support. Shorter runs report unavailable spectra. No inference of stationarity or stress follows from eligibility.

A run with zero detections differs from a run that could not be processed. If all support is excluded or too short, preserve the decision/support result with no invented cardiac values. Count excluded input samples, edge samples, other invalid samples, analyzable samples, peaks, intervals and successive pairs separately. A source-sample count is exact; `count / fs` is declared nominal sample support, not proof of physical elapsed coverage. Store first/last observed timestamps and any nominal end convention separately. Overlapping exclusion reasons may have overlapping counters; the union totals must reconcile.

## Complete outputs and comparison

The new report and complete artifacts must bind the review revision and canonical union hash as well as original source/mapping and detector identities. Save an exclusion ledger with every submitted span, normalized union, source association, resulting runs, edge guards, counts and unavailable reasons. Verify exact union/processing counts before publication.

Keep separate time tables for surviving runs with input, clean, retained support and original source indices. Excluded values remain in the authoritative original and pinned review source; do not fabricate clean rows inside the gap. The ledger references them explicitly. Charts break paths at masks and distinguish excluded spans from filter-edge support. New markers come only from the new report's matching complete events and series; do not attach old event rows to new waveform artifacts even when timestamps coincide.

A comparison labels parent and new report versions, method differences and denominators. A whole-record parent endpoint and a shorter new-run endpoint have different support; show this prominently rather than interpreting their difference as improvement. Both reports' full artifacts remain downloadable. Any named study-window summary must be newly bound to the new source tables; the old summary stays attached to its old source. No automatic copying across participants or clock domains.

## Required acceptance before release

| Independent/adversarial case | Required observable outcome |
| --- | --- |
| Fixed source grid and independently enumerated `[start, end)` membership; final sample; decimal epoch clocks; millisecond source units | Exact excluded samples, original times and counts; unchanged edit/save round trip; no floating epoch/index drift. |
| One-sample exclusion between plausible adjacent beats; longer exclusions; adjacent/overlapping masks | No bridging RR/PRV or successive difference; unique union counts; all original reasons retained. Use hand-specified peak sequences for the interval oracle, not the production helper. |
| Change only samples inside a fixed excluded span to extreme values | Identical surviving-run processed arrays, detections and endpoints, demonstrating no filter/threshold/state leakage. Compare numeric outputs rather than provenance bytes, which should change with the source hash. |
| Independently process each surviving run as a standalone input | Same numerical result after the explicitly tested source-coordinate translation; comparison is a boundary/isolation test, not detector accuracy qualification. |
| Missing data and manual masks together; identical group labels separated in the file | Original discontinuities stay separate; no library filling; identity labels do not merge noncontiguous recordings. |
| Same timestamps on another channel/person/session; curated rows removed before analysis | Mask affects only the bound channel/range; exact acquisition crosswalk; no inferred cross-stream clock relation. |
| Edge exclusions and short/all-excluded runs; several individually short runs totaling over five minutes | Explicit support and unavailable values; no pooled spectrum or fabricated zero metrics. |
| Source/mapping/manifest/table/clock tampering, mixed report event artifacts, changed project, stale preview, altered mask revision | Save/queue/read/publication refusal; no partial report or stale publication. Test full bytes and mid-read replacement, not only a stored hash field. |
| Real supervised ECG and PPG jobs, failed attempt, cancel/retry, restart | Complete source-bound artifacts reconcile with independent rows and endpoint arithmetic; old reports and downloads stay unchanged. |
| Actual browser visible input immediately followed by Preview/Apply, undo/history, report switch, keyboard and narrow layout | Frozen selection equals what the researcher saw; editing clears stale previews; clear run/support plot and exact downloadable decisions. |

For scientific evaluation, freeze a new protocol before inspecting outcomes: records, waveform exclusion source, endpoints, exact location tolerances, mask-boundary guard/sensitivity analyses and intended-use limits. CapnoBase's deposited expert artifact intervals may be supplied as **external validation input**, with their provenance and original inclusive-index convention converted explicitly. They are not an implemented detector, not user-supplied product labels, and not evidence that Brohn can discover the same artifacts automatically. The [dataset's original terms](https://doi.org/10.5683/SP2/NLB8IT) prohibit using this benchmark for training/tuning; retain that separation.

Keep the eight already inspected PPG records as disclosed regression cases. Use separately frozen uninspected records for new comparisons, with no outcome-driven guard/detector adjustment. Score detection timing and interval/endpoint errors separately, show lost coverage and boundary effects, and retain failures. Compare like-for-like source support. Expert masks evaluate the conditional reanalysis path; a separate blinded reviewer study is needed to assess whether intended users find and bound artifacts consistently. Neither establishes NN classification, motion robustness across devices/populations, clinical validity or hardware timing.

## Open implementation decisions

1. **Initial source scope:** accept the recommended one-table direct/curated CSV/TSV route, or qualify native sample-origin/calibration adapters before including them. Multiple tables/channels should require independent source-bound review sets.
2. **Guard policy:** freeze the actual seconds, rounding and padding behavior for the new profile. Reusing two seconds requires explicit limited-support wording and boundary sensitivity evidence; increasing it merely by intuition is not academic validation. The user may widen the excluded source span after inspecting residual artifact, creating a new recorded decision.
3. **Method identity and UI entry:** finalize the new policy/operation names and whether clean-only historical reports require an explicit fresh parent analysis. Never mutate the historical report or reinterpret existing generic intervals automatically.
4. **Coverage and future aggregation:** first release should keep per-run endpoints. A later pooled estimator, task-window RR recalculation or reviewed-NN workflow needs its own mathematical definition, adjacency rules and independent evidence.
5. **Review attribution:** use the application's actual identity model; if it lacks authenticated reviewer identity, label a declared name accordingly. Record reasons and source evidence without inventing expertise or a clinical sign-off.

No new source code, detector settings or scientific jobs were changed/run to create this contract. The listed acceptance work is outstanding implementation work, not a claim of completed qualification.
