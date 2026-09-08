# Questionnaire sections: researcher acceptance

Completed actual-browser acceptance: **18 assertions and four accessibility
scans pass**, including two completed participant sessions and two successful
automatic analysis jobs. The journey uses an original synthetic consumer
packaging questionnaire and an isolated researcher/participant runtime.
No observed human usability, live device or psychological instrument validation
is implied.

The fixture supplies questions and a scoring key, but the browser must author
the section graph. A boolean-false driver and its conditional numeric follow-up
remain in one ordered group. Two rating items remain in their authored order
while their scoring key deliberately lists the reversed second item first.
The researcher moves that complete scale group from the opening questionnaire
to after each of two original text concepts. Two other sections and two groups
vary among eligible positions; fixed slots and member order remain intact.

Independent checks compare each received assignment with a JavaScript SHA-256
implementation of the published assignment contract. The first participant
selects boolean false and answers the visible follow-up with numeric zero. The
second selects numeric zero and must skip that false-only follow-up. Actual
displayed section labels and durable native response types must match.

Each scale assessment converts the mean of two keyed values on 0–4 to 0–100.
With the second item reverse keyed, original raw pairs `[0,1]` and `[4,0]` must
produce 37.5 and 100 for participant one; `[2,4]` and `[0,0]` must produce 25 and
50 for participant two. Automatic reports must contain exactly two stimulus
assessments per run. Groups cannot create extra assessments or alter item keys.

Acceptance also covers explicit Save and Cancel, stale version rejection,
assigned-protocol and report downloads, clone/template/portable reuse, original
design and report integrity after reopening, and desktop/390-pixel automated
accessibility scans. The 100 ms text exposure is transport-only test input,
not evidence of qualified timing or a recommended research exposure duration.

The initial browser attempt exposed a real immediate type-and-create defect:
the new-section button used a label captured before the current field edit.
It created the previous default name instead of `Shopping context`. The
evidence is retained under
`../../work/test-runs/brohn-question-sections-ui-HkWXDF/evidence/failure.json`.
Cancel and stale-version rejection had passed; no release, worker or report
existed in that attempt. The final fresh run retained that rapid interaction and passed after the editor
captured the current name and destination together with the selected node
identity in one command. No delay was introduced to hide the defect.

Harness: [researcher-question-sections.mjs](../../tests/researcher-question-sections.mjs).
Original fixture: [researcher-question-sections.R](../../tests/fixtures/researcher-question-sections.R).

Final evidence:
`../../work/test-runs/brohn-question-sections-ui-BKOX6s/evidence/results.json`,
SHA-256 `9ecd7bb4e961a2b2dc7e869bc35622c6c672d9356231da41c86bf9f3c16941e5`.
All owned services stopped cleanly. Both immutable report objects verify against
their saved hashes and exact catalog bodies. Full CSV score-record JSON agrees
with all four saved observations. The researcher-assigned protocol download is
byte-exact against the stored SHA-256. Three reused studies have fresh study,
question, scale, section and group identities while retaining the authored
relationships, reversed key order and native false branch value.

The assignment oracle checks exact realized positions against the independently
implemented digest/ranking contract. Two allocations do not establish balanced
position counts, and the product explicitly makes no such guarantee. Reopening
means navigating back to the saved source study and re-exporting its exact
unchanged design after reuse; it is not a crash-recovery test.
