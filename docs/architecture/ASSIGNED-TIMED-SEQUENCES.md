# Assigned timed presentation and recovery

Implementation contract, 5 October 2026. Timed delivery remains inactive and
requires joined acceptance. This extends BWP03/05/06/15 and the existing
study-design requirements without changing scientific formulas or saved recipes.

The participant host admits the exact next assigned sequence from fresh
authenticated CURRENT: consecutive baseline, fixation and ordinary stimulus
screens up to the next interactive boundary. It preserves original order,
control/version assignment, material, configured duration, appearance and page
clock. The host owns one event journal and one capture order throughout.

Prepare media before the first baseline. Durably save prospective sequence intent
before presentation. That intent is an arm record, never an invented onset or
outcome. Frame callbacks then present the sequence without awaiting HTTP or a
storage transaction between screens. The previous finish and next start share
the same actual frame timestamp and retain that event order. Initial frame
admission respects earlier captured page clocks by deferring an older frame;
clamping or manufacturing timestamps is prohibited.

Browser `requestAnimationFrame_before_paint` is the explicit reference. It does
not establish physical display or acoustic onset. Preserve actual viewport,
stimulus geometry, assigned versus observed duration and the named frame metrics.
Do not silently redefine historical frame-gap semantics. Study-controlled
appearance takes precedence over the researcher's Brohn theme.

Local event writes drain in the background. An observed failure stops subsequent
presentation and retains original IDs, clocks and ordered retry state. At an
interactive boundary, drain writes and reconcile through the same sender before
offering the next action. Retire an arm only after original stored boundary
events and fresh received state prove the sequence reached that boundary; retain
its history so another ID cannot rearm the same exposure.

A cold page finding an unresolved arm must never automatically replay it.
Recover actual stored events. Missing boundaries remain missing; capture an
actual interrupted ending rather than infer an old onset or completion. Keep
focus, visibility, resize, Escape, withdrawal and recording shutdown in the
ordered terminal path. Normal close must not discard unsaved captures.

Audio/video playback is a separate evidence stream. Invoke playback at its
assigned boundary, preserve native playing/error/current-time observations and
never treat successful preparation as playback. The versioned media-evidence
extension must preserve original callback clocks, durable linkage, strict R
admission and complete exports. A local callback alone does not complete that
backend path. No silent muting, preplaying during baseline or fabricated
audio-visual synchrony is permitted.

Required verification includes real R event translation/replay, adjacent timing
under delayed HTTP, native text/image/audio/video, exact original recovery across
arm/onset/commit/ACK crash windows, interrupted partial runs, phone/desktop
geometry, keyboard recovery and participant-to-report source linkage. Recorded
or synthetic software evidence must remain separate from physical device/timing
qualification. The [recovery checkpoint](../qa/PARTICIPANT-RECOVERY-CHECKPOINT.md)
records related components that passed; it does not close these timed gates.
