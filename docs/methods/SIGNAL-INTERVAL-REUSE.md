# Reusing named recording intervals — next connected contract

Planned continuation of saved source-bound intervals. This contract is not
implementation or acceptance evidence. It addresses repeated baseline/task windows
without claiming synchronization between independently recorded clocks.

Researchers choose an exact saved interval-set version from the same project,
review its labels, categories, notes and source context, and choose a target saved
time-series table. They explicitly declare an anchor in the original recording,
the corresponding anchor in the target recording, and the reason for that mapping.
The displayed preview uses only the translation
`target seconds = original seconds - original anchor + target anchor`.
There is no drift correction, inferred event match, interpolation or automatic
clock alignment. Original and target anchors use their own displayed source clocks.

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

Required checks: positive/negative/fractional translation, unchanged interval
duration and overlap, fresh identities, Unicode labels, preserved null/support,
different target person/session/origin, rejected foreign/mutated sources, stale
preview rejection, preview with no write, exact new-data summary, reopen, exports,
keyboard/narrow layout and actual researcher reuse. Shared source-clock timestamps
or equal recording names alone are not evidence of synchronization.
