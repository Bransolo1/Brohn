# Reviewed alignment between two recordings

24 September 2026. **Implementation contract for the next PC12 slice; not an
enabled feature.** This extends `centralization.recordings` without changing
the existing same-import linked-review or one-anchor interval-reuse contracts.
Complete saved-review discovery is the preceding workstream.

## Researcher outcome

A researcher opens two recordings from the same project, identifies the same
two recorded events in both, reviews the proposed mapping, then saves a new
versioned alignment. A linked view shows selected original channels on the
reference recording's timeline. Original times, units, values, gaps and source
identities remain available beside every mapped value and in complete exports.
Reopening this view must not rerun the underlying scientific analyses.

The flow is **choose recordings → match two events → inspect mapping → save
and review**. Advanced details disclose exact anchors and arithmetic. Unsupported
inputs explain the missing evidence rather than offering an apparently aligned
plot. Existing shared-clock review remains the simpler route when appropriate.

## Basis and scope

The official [LSL time-synchronization documentation](https://labstreaminglayer.readthedocs.io/info/time_synchronization.html)
describes preserving sample timestamps and measured clock offsets, and building
an explicit mapping for other clocks. It distinguishes clock correction from
timestamp jitter and system delay. This supports keeping original observations
and mapping evidence separate; it does not validate a particular Brohn mapping
or the accuracy of manually matched events. Reviewed 24 September 2026.

Brohn's first proposed profile is
`reviewed-two-event-affine/0.1.0-draft`: exactly two reviewed correspondences
define a positive affine map within one unambiguous epoch on each recording.
Additional selected events may check the map but do not silently refit it.
One-anchor translation, regression/robust fits, reset-spanning piecewise maps,
continuous playback, automatic cross-correlation and scientific resampling
remain separate profiles. The current interval-reuse translation retains its
existing semantics.

## Source and identity contract

- Pin both original dataset/import revisions, body hashes, complete sample and
  clock-evidence objects, origin, stream/channel identities and clock units.
  Use original observed timestamps with explicit epoch/segment evidence.
- Each anchor selects a precise original marker row, including sequence,
  source timestamp token, clock/segment identity and retained event value.
  Matching text alone cannot select an event when that label occurs repeatedly.
  User-entered approximate times are not original marker evidence.
- A signal channel may use its recording's marker clock only when their
  retained clock and epoch support establishes that common domain. Names or
  similar numeric timestamps do not establish it.
- Both sides must belong to the selected project and retain current access.
  Source changes invalidate pending previews; old maps retain their exact
original references. Opening, exporting and background publication repeat
  the appropriate current-source and permission checks.
- Keep sample, pilot, live and imported origins explicit. First implementation
  requires a consistent origin and an explicit researcher declaration of the
  relationship between the recordings. It also requires the same nonempty,
  reviewed participant and session identifiers across every selected stream's
  complete source rows, preserving the existing linked-reader rule. Missing,
  conflicting or differently encoded identities require supported source
  curation before this view; a free-text declaration cannot bypass that check.
  A future different-ID linkage route must pin a specific reviewed linkage
  record/version. Mapping clocks never merges people, visits or conditions.
- Pin timestamp processing stage as well as clock identity. This first profile
  consumes the importer's preserved coordinates with its explicit
  `clock_correction_applied=FALSE` and `dejitter_applied=FALSE` policy. Record any
  declared upstream processing separately; preserved imported time is not
  necessarily an unprocessed hardware clock. Do not consume a previously mapped
  coordinate as raw input or silently apply retained LSL offsets again. Future
  corrected-coordinate inputs need a distinct explicit stage contract.

To reduce setup work, the UI may propose pairs when an event label occurs
exactly once in each selected epoch. Show the original rows and times for
review; matching labels are suggestions, not automatic evidence of the same
event. Repeated labels require explicit row selection. A single confirmation
can accept the two displayed pairs and rationale before the mapping preview.

## Mapping and support

Convert each original timestamp to seconds using its exact declared scale.
For source anchors `x0 < x1` and reference anchors `y0 < y1`, define:

```text
scale = (y1 - y0) / (x1 - x0)
mapped(x) = y0 + (x - x0) * scale
```

Evaluate source subtraction and ratios using exact rational representations of
the bounded decimal tokens; do not subtract large absolute binary64 epochs.
Preserve the original tokens and reduced numerator/denominator pairs. Rounded
display seconds are a separately labelled projection, never replacement source
coordinates. The first arithmetic component has the following frozen resource
bounds; these bounds do not establish scientific validity or acceptable drift:

- ASCII decimal tokens use the existing stream-reader envelope: at most 120
  bytes and adjusted decimal exponent between -100 and 100. Explicit exponent
  tokens have at most three digits and lie between -220 and 220; check these
  limits before constructing powers. Reject binary numbers and booleans.
- Units are exactly `s`, `ms`, `us`, `ns`, or `ticks` with an explicit positive
  decimal `seconds_per_tick`. No implicit unit aliases or inferred sampling rate.
- Both anchor spans must be positive and at most 86,400 exact seconds. There is
  no invented minimum span or maximum scientifically acceptable drift.
- Reduced numerator and denominator strings each have at most 2,048 digits.
  A serialized point/check is limited to 64 KiB and a map to 128 KiB.
- Display strings use 34 significant digits with round-half-even. Also expose
  an approximate position relative to the reference anchor, so large absolute
  epochs do not conceal small differences. Neither approximation determines
  support, equality or exported exact coordinates.

The reusable arithmetic object is validated once, then maps one position at a
time. Its serialized manifest is separate. The component does not itself prove
recording identity, source authority, clock epochs or timestamp-processing stage;
those checks remain mandatory at the R and original-artifact boundaries below.

The usable mapping domain is the closed anchor span. A displayed data window
keeps the platform's start-inclusive/end-exclusive selection convention; the
end anchor remains mapping evidence even when outside a selected window.
No default extrapolation, clamping, inferred sample, interpolation or gap filling
is allowed. Duplicate/reversed anchors, nonpositive scale, undeclared clock
units, reconstructed timestamps or ambiguous clock epochs refuse the map.
Clock-reset boundaries require another map, rather than extending this one.

Keep missing and unplaced observations distinct. Plot breaks follow original
gaps/segments and retain their causes. Different sample rates remain different
sample positions on the mapped axis; a shared cursor does not imply paired
observations. Export every selected actual row with original and mapped time,
source sequence, value state, unit and map identity.

For optional check events, show the signed mapped-minus-reference residual for
each original correspondence, with complete support and units. The two defining
anchors have zero residual by construction. Zero fit residual does not establish
physical synchronization, event detection accuracy or uncertainty. Record
uncertainty as unknown unless separately supplied source evidence supports it;
do not invent an error bound from the fit.

## R, worker and UI responsibilities

R owns the named profile, source/project/epoch validation, reviewed anchor
selection, immutable mapping request, current authority and publication rules.
A bounded supervised worker reads complete pinned artifacts and calculates
exact rational mapped coordinates; it may use Python's standard-library
arithmetic without introducing another model dependency. R validates returned
source identities, complete counts, selection and mapping schema before ordinary
guarded publication. Independent arithmetic checks remain outside that worker.

The researcher UI offers only supported original recordings/channels/events,
shows both anchor pairs and affected span, and requires an explicit save after
preview. Editing creates a new revision. Historical views pin the exact map and
source versions. Metadata history and existing explorers reuse their respective
authority checks. No existing report is rescored or silently relabelled aligned.
Scientific recipes must explicitly opt into a later qualified mapping contract
before consuming these coordinates for ERP, event response or cross-signal
inference; this first profile supports auditable review/export only.

## Required connected acceptance

1. Independently calculate offset and non-unit drift examples, different units,
   large epochs with sub-millisecond differences, reversed/duplicate anchors,
   reset/gap cases and exact boundary selection. Include a held-out event whose
   residual is nonzero, so an incorrect zero-error display cannot pass.
2. Import two original synthetic recordings with unequal rates and explicit
   markers. Author the mapping through the actual UI, inspect exact rows and
   the figure, and compare every selected exported value/time to the independent
   complete-source oracle. No seeded aligned result counts as this journey.
3. Reopen a historical map, save a different version, and prove the previous
   view/export remains source-bound. Exercise cancel/retry, stale preview,
   foreign-project and revoked-source refusal and explicit unsupported epochs.
4. Restart the services and reopen identical maps, original objects, reports
   and exports with no new scientific analysis. Count review preparation jobs
   separately. Inspect desktop/narrow/keyboard layouts and accessible numerical
   alternatives; retain failed attempts and exact source phases.

Passing this slice would establish the specified software mapping/review route.
Physical-device timing, inferred event equivalence, empirical uncertainty and
general multimodal validity remain distinct evidence requirements.
