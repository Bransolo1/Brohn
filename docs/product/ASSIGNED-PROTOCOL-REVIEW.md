# Review a participant's assigned protocol

In a study's Collect or Review stage, open **View assigned protocol** beside a
participant session. The review shows its origin, current completion/transfer
state, assigned step sequence and exact typed answer codes in offered order.
Forty steps appear per page; every assigned step remains available by paging.

**Download assigned protocol JSON** returns the original stored JSON bytes and
SHA-256 identity, including its complete frozen design, realized stimulus order,
question option order and compiled task/choice definitions. It never recompiles
from the current draft. Media objects are referenced, not bundled into this JSON.
Participant access credentials and deployment tokens are not exported.

Assignment does not prove that a question was displayed or answered: conditional
visibility, interruption and missing responses belong to the event journal.
This review is labelled accordingly. Completion/transfer state shown in the modal
is a current read, while the assigned protocol is immutable. A closed review or
navigation to another study invalidates the selected download context.

The stored protocol service checks exact run/study/project ownership and source
integrity. The UI binds its selected session/hash before paging or downloading.
Sixteen scoped checks in `tests/platform-run-review.R` exercise the actual Start
API, byte-exact downloads, distinct numeric/text/boolean codes, later draft edits,
study/project boundaries and real Shiny stale/close/navigation behavior. The
connected questionnaire researcher/participant journey passes32 assertions and
six accessibility scans, including eight completed sessions, old/new protocol
downloads, actual untimed resume and design reuse. See
[the researcher journey](../qa/QUESTION-ASSIGNMENT-RESEARCHER-JOURNEY.md).
