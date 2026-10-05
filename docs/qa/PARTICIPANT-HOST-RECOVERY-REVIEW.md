# Participant host recovery review — 5 October 2026

Later follow-up: the [recovery checkpoint](PARTICIPANT-RECOVERY-CHECKPOINT.md)
records scoped successor fixes, real-R questionnaire recovery and ordinary-host
UI06 acceptance. It also preserves the later missing-draft-API integration failure
and corrected component. The original findings below remain historical evidence;
they are not the current source selection. Full actual-R host integration is open.

At the time of this initial review, the assigned participant host was an inactive
local candidate, outside the public snapshot and the released application.
Independent static review found four recovery defects before host qualification:

1. A failed first opening of finish storage cached a rejected promise. Reusing
   that controller made Retry repeat the failure even after storage recovered.
   Close and recreate the failed owner, preserving the original ending intent.
2. A failed or externally closed observation journal could leave an original
   capture waiting for retry, while the host required that capture to drain
   before reopening the journal. Reopen storage through recovery without
   recapturing or reordering the original event, then retry its retained bytes.
   The selected questionnaire controller has the same retry-first limitation.
3. If the first durable save of a terminal intent aborted, normal host close
   could remove its only in-memory copy. A captured ending must have exact durable
   custody before close succeeds, or remain available for explicit retry.
4. After a failed questionnaire event, a later queued visibility event could
   wait behind it indefinitely. Closing waited for that follower while disabling
   Retry. Refuse close promptly on a failed ordered head, keeping recovery
   controls and original captures available.

These findings do not alter earlier, separately scoped passing test results.
Those results did not exercise these combined failure paths. The selected public
controller source remains exact to its recorded version; fixes are being made
in an explicit successor and require fault-injection and joined-flow checks.
Do not promote the public source snapshot based on the prior component passes.

The separate finish-network controller now passes 70 functional Chrome checks
and a two-check real timeout phase against controlled HTTP authority. The two
unchanged 60-second request deadlines took 120,304 ms in the browser; original
pending bytes remained recoverable. Both phases passed their syntax checks and
independent process/listener closure. This is browser/network/storage evidence,
not actual R finalization, a complete participant host or scientific validation.
The finish-network source is not added to this earlier prepared snapshot.

Next acceptance: original capture retry after storage reopening; failed-head
plus follower close refusal; ending-save abort followed by close/retry; cold
recovery across terminal intent/journal/finish boundaries; and the real R-backed
entry, illustrated questionnaire, ordinary/timed screens and finish journey.
Whole-platform, Qualtrics parity, device and scientific gates remain open.
