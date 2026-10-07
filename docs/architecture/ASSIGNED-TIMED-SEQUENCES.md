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

Advance that existing host clock fence after the arm transaction commits and
before starting the renderer. A frame timestamp can precede a recently completed
transaction even when its callback runs later; it must not be accepted as an onset
before durable prospective intent. This uses an actual clock sample, not a new
participant event or a replacement onset timestamp.

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

## Media evidence implementation boundary — 7 October

The separate [renderer acceptance](../qa/ASSIGNED-TIMED-RENDERER-ACCEPTANCE.md)
passes 58 browser/eight syntax checks. It does not close full-host, server-media
or physical timing gates below.

The proposed `participant-timed-media/0.1` capability uses a closed envelope
containing an actual attachment clock and groups of original records by arm.
A terminal attachment can retain late callbacks from several earlier sequences.
Records keep their original IDs, assigned audio/video steps, page clocks,
current time, playback rate, native readiness/network state and playback/error
flags. A play request and a native `playing` callback are distinct observations.
Missing callbacks remain missing.

Admission belongs to an immutable server release capability bound to the saved
renderer and derivation implementation. Existing releases without that
capability retain their original closed payload grammar. A browser option
cannot enable this route. Record IDs are unique across a run, with deduplication
in the same transaction as received source evidence.

The browser spool snapshots original records synchronously. Its background
writer saves them before appending the containing journal observation, then
links them after that exact journal transaction completes. A crash between
journal commit and linkage recovers the existing event and records. Attachments
are immutable once captured; later callbacks go into subsequent attachments.
These storage waits never run between frame-boundary stimulus transitions.

Ordinary capture and attachment preparation remain unavailable throughout store
recovery, including its complete history audit. A failed audit retains ownership
and originals; reopening a database alone does not restore collection. Concurrent
recovery actions join one operation. An already linked record ID must confirm its
original stored value without allocating another capture order; a conflicting ID
cannot strand later original records. Keep any observation rejected before custody
with its renderer/host owner.

Attachment clocks share the containing event's page domain and are sampled at
or after that event. Earlier-page records preserve their own time origin;
unrelated monotonic clocks must not be compared numerically. Preserve exact
numeric evidence, including signed zero, through copies and exports. Complete
original requests, translated events, assigned source context and capability
identity belong in researcher exports.

Complete operation export includes all five original documents: request,
derivation implementation, model, receipt and result. Verify their source/view/map
bindings, codecs, byte counts and hashes as well as the rederived source events.
Count all operation, derivation, event and native-record rows so orphaned evidence
cannot disappear silently. This is a read under current researcher authority;
it must not manufacture participant credentials or rerun analysis.

This is inactive implementation work, not accepted media delivery. Browser
storage, renderer, R admission/replay, complete exports and the assembled
journey need connected evidence. The existing 4 MiB request ceiling is an
operational limit: overflow must preserve originals and refuse completion.
Larger workloads require an explicit paged receiver path; observations cannot
be dropped to fit a request.

Required verification includes real R event translation/replay, adjacent timing
under delayed HTTP, native text/image/audio/video, exact original recovery across
arm/onset/commit/ACK crash windows, interrupted partial runs, phone/desktop
geometry, keyboard recovery and participant-to-report source linkage. Recorded
or synthetic software evidence must remain separate from physical device/timing
qualification. The [recovery checkpoint](../qa/PARTICIPANT-RECOVERY-CHECKPOINT.md)
records related components that passed; it does not close these timed gates.
