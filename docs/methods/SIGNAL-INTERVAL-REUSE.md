# Reusing named recording intervals

Connected continuation of saved source-bound intervals. This method addresses
repeated baseline/task windows without claiming synchronization between independently
recorded clocks. Executed acceptance is recorded separately in the QA ledger.

Researchers choose an exact saved interval-set version from the same project,
review its labels, categories, notes and source context, and choose a target saved
time-series table. They explicitly declare an anchor in the original recording,
the corresponding anchor in the target recording, and the reason for that mapping.
The displayed preview uses only the translation
`target seconds = original seconds + (target anchor - original anchor)`.
There is no drift correction, inferred event match, interpolation or automatic
clock alignment. Original and target anchors use their own displayed source clocks.
The offset is computed first so equal large anchors preserve original boundaries.
Finite binary64 addition residuals and interval duration are checked against
`max(original duration, 1 second) × 1e-12`; translations that lose more precision
are refused. The renderer and editor preserve round-trip 17-digit boundary values.
This numerical guard does not establish physical timing accuracy.

An explicit Apply action saves a new interval set with new set/window identities.
It binds the exact source annotation ID, revision and hash; both table identities,
clock declarations and origins; both anchors and translation; and the researcher's
mapping rationale. The original set and existing summaries remain unchanged.
No observations, person links, quality decisions, review approval or computed
summary are copied. New summaries read only the target recording's complete data.

The preview must show every translated half-open window and warn where it extends
beyond the target's observed range. Never silently clamp, trim or rescale a window.
The existing summary's exact sample/missing/excluded support determines availability.
Source and target must retain project authority; stale source versions or altered
preview inputs cannot apply a different transformation than the one reviewed.

Acceptance includes positive/negative/fractional translation, unchanged interval
duration and overlap, fresh identities, Unicode labels, preserved null/support,
different target person/session/origin, rejected foreign/mutated sources, stale
preview rejection, preview with no write, exact new-data summary, reopen, exports,
keyboard/narrow layout and actual researcher reuse. Shared source-clock timestamps
or equal recording names alone are not evidence of synchronization. The current
chooser lists at most 100 recent nonempty sets in the project; an explicitly
selected earlier version remains reusable. It does not merge people or combine
their observations. Summaries remain single-target descriptive measurements.
