# Questionnaire revision: browser bridge evidence

This records the connected browser implementation of the source-bound
`within-occurrence-revision/1.0` policy. It does not qualify the separate complete
researcher authoring, analysis and export journey.

The R receiver owns visibility, allowed actions, answer heads, dependency
generations, review hashes and the outer protocol cursor. The browser module
`www/participant/question-revision.js` validates the received packet against the
frozen timeline and builds requests only for server-offered actions. R canonical
hashes are opaque strings: JavaScript does not substitute its own JSON encoding
or hash algorithm. `www/participant/runner.js` connects this module to the real
IndexedDB session and authenticated delivery API.

The first connected release deliberately supports **offline drafts and pending
delivery, with navigation waiting for the durable server acknowledgement**.
This narrows the earlier planning contract's possible offline navigation. It
does not duplicate the scientific/domain reducer in JavaScript. The action,
event identity, sequence and exact body are saved together before transmission.
An acknowledgement and its complete paged canonical answer state are saved in
one browser transaction before the next action. The full state pages retain
their exact packet identity; merged answer rows do not rewrite the first-page
server envelope.

Back keeps the unsent local draft without committing it. The server's exact
occurrence and dependency generation determine whether a draft can be restored.
Review exposes current visible answers only, using authored option labels and
distinct optional omission and information acknowledgement states. An earlier
changed answer clears stale dependent drafts and announces how many previously
committed answers were cleared. The participant still needs to answer any
dependent questions that remain visible. Sealing uses the acknowledged R
projection hash, and only its receipt advances the outer protocol cursor.

Reload first delivers pending exact events and recovers the canonical state.
A new actual page clock creates a resume visit; an ordinary same-page retry
does not invent one. Revised and resumed answers send null initial response
time and retain the current visit's observed active interval. The untimed visit
starts when the question is displayed; controls wait for receipt, so that
interval includes any observed receipt wait. It is not an implicit task latency
or a network-independent measurement. Existing timed-task, stimulus and camera
reload policies are unchanged. Withdrawal stops subsequent navigation even when
an earlier answer acknowledgement arrives late.

The opt-in policy alone selects this route. Original releases without it retain
the old forward-only events, answers and duplicate semantics.

## Evidence

`tests/participant-question-revision.mjs`: **39 pure browser contract checks**.
Original constructed packets cover typed false/zero/close doubles, exact source
members and cursor, unavailable actions, stale drafts, dependency generations,
opaque seal hashes, current/revised/resumed intervals, duplicate commits and
consistent full-page recovery. These constructed packets are not claimed as R
receiver evidence.

`tests/participant-question-revision-delivery.mjs` with the separately owned
`tests/fixtures/participant-question-revision.R` service: **23 checks and two axe
scans** in actual Chrome against the real participant launcher and SQLite
receiver. The source materials are original synthetic sample data. The run
covered a truly committed but deliberately lost acknowledgement, exact batch
retry, unchanged outer cursor, review/edit, edited local draft reload with a new
page visit, final effective values 6 and 4, explicit optional omission,
information acknowledgement, frozen design/protocol hashes, and confirmed
completion. It also aborted a real IndexedDB commit transaction: the input,
saved head, cursor and sequence remained unchanged, and retry retained exactly
one answer with none of the failed candidate IDs. Withdrawal while a committed
answer acknowledgement was held retained one partial answer and no seal or
completed-study job. Desktop question and 390px review scans had zero axe
violations and no horizontal document overflow.

Evidence: `work/test-runs/brohn-question-revision-delivery-cuN66i/` (outside the
repository, including results, exact reopened inspection and screenshots).
The first run exposed optional empty text being treated as an answer. The new
policy now sends an explicit null for a genuinely blank optional value; the
passing run includes this correction. A read-only audit identified a same-page
recovery flag that could request an invalid same-clock resume; navigation now
uses the actual clock instance difference.

`tests/participant-question-revision-legacy.mjs`: **13 checks** running the
existing `tests/participant-logic.mjs` in an isolated actual receiver after the
shared delivery wait change. Two old-style visits retained exact near-one
numeric codes, native numeric/text/boolean collection members, all six typed
branch decisions and completed receipts. Each left one expected job queued.
Evidence: `work/test-runs/brohn-question-revision-delivery-legacy-NZoMgz/evidence/`.

All owned services exited gracefully. These browser transport suites started
**no scientific worker**: automatic analysis was verified as queued, and no
human participant or physical device was used. The independent researcher QA
journey owns the four-occurrence branch/scale/report qualification, while R
receiver tests own direct invalid transitions and canonical scoring evidence.

## Stable participant selectors

- `#content[data-questionnaire-step][data-questionnaire-occurrence]` names the
  current displayed frozen step and occurrence.
- `form#questionnaire-answer` exposes Continue and eligible Back.
- The review heading is `Review your answers`; the ordered numeric/text
  alternative is `#questionnaire-answer-review`.
- Each editable item has a button named `Edit: <exact authored prompt>`.
- `#questionnaire-seal` reads `Continue to the next part` or `Finish study`.
- `#questionnaire-changes` announces cleared prior answers using `role=status`.
- Pending transport exposes `Saving this change` and `#questionnaire-retry`.

Required-answer errors remain in the visible alert region, and Stop study
remains available while normal navigation waits for receipt.
