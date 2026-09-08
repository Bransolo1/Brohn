# Calibrated temperature and acceleration

These are separate versioned imported-channel recipes. They add interpretable recording descriptions and explicitly configured threshold excursions. They do not classify emotion, attention, arousal, core body temperature, energy expenditure or gait. Physical acquisition, sensor accuracy and appropriateness for a research question require their own evidence.

The capability register's temperature and movement families are broader: thermal-image ROIs, event-baseline temperature contrasts, gyroscopes, force, pressure and location are not implemented by this pack. EOG also remains separate. The prepared [other physiology review](reuse/OTHER-PHYSIOLOGY.md) requires an explicit horizontal/vertical montage and reviewed blink evidence; a generic voltage channel cannot establish blink detection or calibrated gaze angle.

## Source contract

`scripts/workers/peripheral.py` runs in the prepared methods environment with NumPy **2.5.3**. It uses original descriptive calculations and the existing full typed artifact writer. No filter, missing-data repair, resampling, implicit baseline or physical state model runs silently.

```text
python scripts/workers/peripheral.py --request request.json --output result.json

schema: brohn-worker-request/1.0
operation: peripheral
modality: temperature | movement
format: csv | tsv
source_path: owned immutable source object
source_hash: full SHA-256
metadata: reviewed mapping below, including immutable origin
parameters: optional normalized settings matching metadata.parameters
artifact_directory: existing owned attempt directory for full output
```

The coordinator verifies the original object; the worker hashes it before and after reading. CSV/TSV accepts UTF-8, ordinary quoted fields and unique column names. Bounds are 128 MiB, one million source rows, 500 contiguous identity groups, 2,000 supported/unavailable segments, 40,000 features and a 16 MiB compact result. Exceeding a bound fails explicitly; rows are not silently truncated. An output path cannot overwrite its source or request.

Common mapping fields are `time_column`, `time_unit`, `sampling_rate`, `value_columns`, `unit`, `origin_statement`, `calibration_source`, `sensor_site` and `acquisition_filters`. Source origin is supplied by the coordinator as `metadata.origin`. Optional participant/session columns must be mapped together; condition, exposure and source segment columns are also explicit, distinct fields. They are retained as source identifiers, with no inferred stimulus or independent-person count.

Temperature also requires `recording_conditions`: ambient conditions, sensor contact, acclimatisation/settling time or an explicit statement that these are unknown. Acceleration requires three distinct signed `axis_labels` in selected-channel X/Y/Z order and `gravity_policy="included"|"removed"`. One source clock, calibrated unit and sampling rate apply to the selected channels. Mixed per-axis scaling/rates must be normalized in a separately reviewed source before this recipe.

Time units are `s`, `ms`, `us`, `ns` or whole `sample` indices. Original timestamp text and one-based data-row indices are preserved, including values beyond binary64's exact-integer range. Relative seconds are computed after decimal subtraction from each contiguous source group's clock origin. Repeated/reversed timestamps within one undeclared segment fail; an explicit segment or identity boundary can start another clock. Rows are never sorted.

Ordinary intervals must agree with the declared cadence, using the recorded tolerance (default 2% of one sample interval, maximum 25%). An interval above 1.5 sample periods is a gap. Missing/nonfinite selected values, gaps and any contiguous identity change break analysis support. Movement uses listwise validity of all three selected axes; still-observed individual axes remain in the full artifact when another axis is missing. Unsupported strings and booleans do not become numeric measurements. Missing values remain null, not zero.

Every valid segment needs at least two samples and the declared minimum observed span. The default is `max(1 second, 1/sampling_rate)`; an explicitly invalid researcher setting is rejected rather than replaced. Span is last observed timestamp minus first, with no extrapolated final sample cell. Failed/short segments remain in the result with reason and source-row bounds. This minimum establishes computational support only, not an empirically validated recording length.

## Temperature profile

`temperature-calibrated-descriptive/1.0` accepts exactly one calibrated channel in `degC`, `K` or `degF`; canonical output is `degC`. Conversion is `K - 273.15` or `(degF - 32)/1.8`. Differences retain Celsius-degree units. These conversion definitions follow the [NIST SI unit guidance](https://www.nist.gov/pml/special-publication-811/nist-guide-si-chapter-4-two-classes-si-units-and-si-prefixes) and [conversion tables](https://pml.nist.gov/cuu/pdf/sp811.pdf). Values below absolute zero are excluded with an explicit reason; a generic physiological plausibility band is not imposed.

Each supported segment returns the arithmetic sample mean, sample standard deviation (`n-1` denominator), minimum, maximum, range, first and last observed values, last-minus-first change and ordinary least-squares slope in `degC/min`. It also returns a trapezoidal time-weighted mean over the actual adjacent sample intervals. Sample and time-weighted means have different denominators and remain distinct. Endpoint change is not relabelled as a protocol baseline comparison.

## Acceleration profile

`acceleration-calibrated-triaxial/1.0` accepts exactly three explicitly ordered calibrated channels in `g` or `m/s2`. The standard-gravity conversion uses **9.80665 m/s2 per g**, a conventional value rather than a measurement of local gravity. [NIST acceleration conversion](https://www.nist.gov/pml/special-publication-811/nist-guide-si-appendix-b-conversion-factors/nist-guide-si-appendix-b9).

For each axis it returns sample mean, sample standard deviation and RMS. It returns vector-magnitude mean, RMS and maximum. The vector-derivative RMS uses `norm((a[i+1]-a[i])/(t[i+1]-t[i]))`, followed by RMS across valid adjacent vector differences. The first sample has no preceding derivative and retains null. This differs from differentiating vector magnitude: rotation of an included gravity vector can produce nonzero vector derivative while magnitude stays constant. No derivative bridges a support boundary, and no displacement is integrated.

ENMO is disabled unless selected. With gravity-included input it computes `norm(a)/9.80665 - 1`, with either retained negative values (`untruncated`) or samplewise flooring at zero before aggregation (`zero_truncated`). Gravity-removed input rejects ENMO to avoid subtracting gravity twice. The original [van Hees et al. study](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0061691) distinguishes norm-based and filter-based gravity handling and examines their limitations during rotation. This recipe implements the declared norm formula and negative-value policy; it does not reproduce that study's complete empirical protocol, wear detection, imputation or energy-expenditure modelling.

## Opt-in protocol-defined excursions

Settings contain `recipe`, `minimum_duration_s`, `threshold` and, for movement, `enmo`. Threshold is null by default. Enabling it requires all of:

```text
metric: temperature_c | vector_magnitude_ms2 | enmo_g
direction: above | below
on: finite canonical-unit start boundary
off: finite canonical-unit return boundary
minimum_duration_s: at least one source sample interval
source: protocol rationale for the operational thresholds
```

The metric must exist in the selected profile; `enmo_g` requires enabled ENMO. An above excursion enters at or above `on` and recovers strictly below `off`; a below excursion enters at or below `on` and recovers strictly above `off`. Hysteresis must point toward the inactive side. No scientific cutoff is prefilled or inferred.

Events preserve the first active observed sample, last active observed sample, separate recovery sample when observed, extreme value, original source start/end rows and left/right censoring. Activity at the first sample is left-censored; continuing activity at the last is right-censored. Observed duration is last-active minus first-active, so a single isolated active sample cannot supply an extrapolated interval. Excursions below the declared observed-duration requirement are not retained. They never bridge missing data or gaps.

With usable support and a requested detector, zero retained excursions is a legitimate operational count. A disabled detector or no usable support yields unavailable/null `quality.event_count`. An empty event artifact alone therefore must not be interpreted as zero physiological activity.

## Full artifacts, reports and integration

The result uses `brohn-worker-result/1.0` with `features`, `events`, `series`, source-group `recordings`, supported/unavailable `segments`, `quality`, `parameters`, `engine`, limitations and full artifact manifests. Features retain original group IDs and a distinct generated `support_segment_id`; this must not be confused with the recorded `group.segment_id` reset label. Summary features consume every eligible sample. Compact rows/events show only the first 2,000 with complete counts and an explicit preview policy.

Full `physiology-series` and `physiology-events` NDJSON artifacts retain every row/event with typed units, source hash, worker/writer hashes, normalized settings, source identities and exact clock origin. Source rows expose `valid_sample`, `analysis_eligible` and the compatible `retained` alias, alongside one-based `source_row` and zero-based `source_sample_index`. Invalid/short support remains visible. Shared cadence metadata lets the signal explorer split gaps, while event tables expose exactly one onset coordinate and use unconnected points. A saved full artifact and verification receipt are required before publication/download; scratch paths must be replaced by immutable object handles.

R APIs, loaded after core, are:

```r
brohn_peripheral_recipe_choices(modality)
brohn_peripheral_defaults(modality)
brohn_validate_peripheral_mapping(metadata, columns = NULL, source_format = NULL, modality)
brohn_peripheral_worker_request(metadata, source_format = NULL, columns = NULL, modality)
```

The request helper returns `operation`, `script`, `python_profile="methods"`, normalized `parameters` and normalized `metadata`. The coordinator uses that metadata, injects immutable `origin` and source hash, then runs the dedicated worker and existing complete artifact verifier. Empty R settings are normalized to a populated JSON object. The Data UI APIs are `brohn_peripheral_settings_ui(metadata, columns, modality)` and `brohn_peripheral_input(input, metadata, modality)`. Controls use `map_unit` and `map_peripheral_*`; existing Data fields own channel order, timing, segment/person/session/condition/exposure and `map_origin` source notes. A separate generic `map_unit` control must be suppressed.

Whole-study or liking comparisons require the separate deliberate peripheral synthesis adapter. Adding a modality name to a generic allowlist does not establish compatible supported-interval identity, recipe definitions or participant-aware aggregation. Shared report and synthesis integration is owned by `R/platform-peripheral-report.R` and `R/platform-peripheral-synthesis.R`.

## Evidence boundaries

`tests/workers/peripheral.py` passes **17 tests**: independent unit/linear-temperature arithmetic, static gravity and vector derivatives, rotation, both ENMO policies, threshold hysteresis/censoring, missing/gap/reset/identity boundaries, full 2,101-row and 2,101-event artifacts despite display caps, malformed values/units/calibration/clock/parameters, source hashes, actual CLI execution and source-overwrite prevention. Error results preserve the requested modality and actionable source error so the shared receiver does not mask them as an incompatible envelope. The full artifact verifier checks canonical schemas, row counts and hashes.

`tests/platform-peripheral.R` passes **42 checks**, including reviewed settings, signed axes/gravity, stale disabled-threshold inputs, empty cutoffs until explicitly entered, low-rate defaults versus rejected explicit invalid settings, source notes, rendered accessible labels and actual R-to-JSON-to-Python temperature/TSV/movement calculations with full artifacts. These are domain/UI-helper and standalone process checks, not physical device qualification or an actual browser journey.

Independent researcher counterexamples in `tests/workers/peripheral-independent.py` pass **19 tests**. Their original oracles exposed a low-rate default mismatch at 0.1 Hz; the correction applies only to omitted defaults, preserving an explicit invalid setting as an error. Their downstream artifact checks separately exercise missing/gap fragments and event plotting. Source hashes and outcomes are retained outside the repository under `work/test-runs/brohn-peripheral-independent/`.

`tests/platform-peripheral-integration.R` passes **26 checks** through the actual saved-job coordinator: two scientific reports, four full-artifact catalog/preview jobs and a deliberately invalid clock-reset job. Independent temperature means, slopes, threshold censoring and static-gravity arithmetic survive immutable publication. The report exactly matches its retained JSON envelope, queued mapping stays frozen after a later review, and complete source/series/events/preview/report downloads preserve their hashes. The signal explorer separates missing samples and clock gaps and renders event observations as unconnected points. Reopening the store preserves the same report and source objects. Processing scratch and unfinished copies are removed; small publication control receipts intentionally remain for audit. These are process/catalog/export checks, not a completed researcher browser journey.
