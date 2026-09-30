# Continuous EDA: exact-constant recordings

Updated 30 September 2026. Explicit recipe `eda-neurokit-highpass/1.1` adds a descriptive
branch for exactly constant, eligible recordings. It does not establish a new
physiological response threshold. The [acceptance record](../qa/EDA-CONSTANT-SIGNAL-ACCEPTANCE.md)
separates component, native source, review, export and researcher evidence.

## What the researcher receives

A constant recording retains its measured raw conductance level, original units,
sample rate, segment bounds, edge exclusions and source identities. Brohn explains
that response measurements are unavailable. It does not present a zero SCR count,
zero response rate or an invented tonic/phasic line. The recording may reflect an
absence of observed variation or an equipment/contact problem; this policy alone
cannot distinguish those explanations.

Select the new continuous method explicitly when mapping a new analysis. Existing
mappings, defaults, stream curation and saved recipe 1.0 results keep their original
behavior. A report preparation cannot silently rerun or repair an old analysis.
New report packages use the versioned 0.2 display/export profile; old packages
reopen their original files. See the [report guide](../operations/SHARE-SAVED-EDA-FINDINGS.md).

## Exact method boundary

1. Apply the existing source-unit conversion, physical admissibility, time/gap
   segmentation, minimum duration and edge-support checks.
2. Compare every finite converted segment value directly with its first value.
   There is no epsilon, range subtraction, rounding or amplitude threshold.
   Signed zeros may compare equal; original source bytes remain retained.
3. For an eligible exact constant, bypass cleaning, decomposition and detection.
   The raw mean is the first converted value. This avoids summation noise and
   overflow without claiming a filtered physiological component.
4. Preserve the existing exclusion mask and valid-duration definition, even
   though this branch does not filter. Short or otherwise ineligible segments
   retain their original unavailable reasons; the branch does not rescue them.
5. Ordinary and near-constant inputs use the unchanged numerical processing path.

The effective parameters record
`exact_constant_policy="raw_description_only/1.0"`. This is a fixed recipe rule,
not an adjustable researcher threshold. Recipe 1.0 is unchanged.

## Output and source preservation

| Output | Exact-constant behavior |
|---|---|
| Segment status | `descriptive_only`; descriptive status computed, response status unavailable. |
| Raw conductance mean | Original finite converted level; eligible descriptive value. |
| Tonic mean, median and slope | Null with `exact_constant_signal`. |
| SCR count and rate | Null with `exact_constant_signal`, never an inferred physiological zero. |
| SCR amplitude mean and median | Null values and explicit null denominators. |
| Signed and positive phasic area | Null with `exact_constant_signal`. |
| Stored numerical candidates | Zero structural records, distinct from an SCR measurement. |
| Full sample table | Original time, source index and retained flag; clean/tonic/phasic cells explicitly null. |
| Candidate stream | A complete valid zero-row table, not a missing artifact. |
| Preview and source | Original bounded raw preview and source retained; no full raw waveform duplicated in report evidence. |

All ten feature rows keep their names, units, order and scope. Typed evidence
preserves nulls; CSV processed cells are empty under the existing headers.
Mixed recordings retain both ordinary computed and constant descriptive segments.
Quality totals distinguish computed, descriptive-only and unavailable segments.
Usability of a raw description does not imply usability of a response estimate.
The existing research-review and unqualified-method flags remain explicit.

Synthesis may retain the eligible raw mean under its exact method definition.
The nine unavailable observations remain present with their source reason.
Different recipes do not silently pool, and matching participant text alone is
not a cross-source identity proof. No new EDA–liking estimator is introduced.

## Views, reports and history

A saved constant review has a non-null model with an explanatory state, no
processed points/components/markers, and separate coordinate counts. It uses the
whole original segment and offers no response-window controls. The 500,000-row
coordinate-view limit remains; narrowing a response window is not a remedy.
Reports retain all original numerical evidence even if their figures are hidden.
See the [versioned report contract](../architecture/SAVED-EDA-REPORT-PACKAGES.md).

Old standalone reviews verify the original successful producer and saved source
under current reader authority. New execution still pins the current code.
Historical recipe 1.0 models and CSVs, and package 0.1 HTML/ZIP/manifest files,
remain exact; current readers do not regenerate them.

## Work that remains

- **Near-constant numerical behavior:** adjacent representable values, ramps and
  quantized signals are deliberately unchanged. A future correction needs its own
  reviewed version and independent conditioning/error evidence.
- **Scientific response criteria:** relative peak prominence is not an absolute
  conductance-amplitude criterion. Define the measured quantity, stage, onset
  support, noise context and denominators before adding an absolute criterion.
- **Device quality:** calibration, resolution, clipping, contact and motion need
  device/protocol evidence. A software constant branch does not qualify hardware.
- **Reference recordings and constructs:** independent reviewed labels and protocol
  evidence remain necessary for physiological or consumer-research interpretation.
- **Event-related EDA:** remains a separate method; this branch does not change its
  baseline windows, exclusions, response definition or nonresponse policy.

The [retained recipe 1.0 counterexamples](../qa/EDA-CONSTANT-SIGNAL-FINDING.md)
document the numerical fault and its reproducible original results. The SPR
[publication recommendations](https://doi.org/10.1111/j.1469-8986.2012.01384.x)
discuss amplitude criteria in relation to equipment and protocol; those values
have not been adopted as new Brohn defaults.
