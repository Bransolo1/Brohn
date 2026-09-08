# MaxDiff researcher acceptance

`tests/researcher-maxdiff.mjs` passes **27 assertions and five accessibility
scans** against an isolated actual Shiny app, a separate production participant
launcher and SQLite workspace. Evidence is retained at
`work/test-runs/brohn-maxdiff-researcher-Quiv8b/evidence/results.json`.
The helper is `tests/fixtures/researcher-maxdiff.R`. No scientific worker was
started by this journey.

## Original consumer-research fixture

The researcher starts a blank study and authors an end-of-study five-point
explicit liking item plus two object-case best-worst exercises. Both use four
original labels: Refillable packaging, One-handed opening, Clear ingredient
list and Compact storage. The first asks what matters most/least and requires
a complete pair; the second asks what the participant likes most/least and
permits an omission. Their distinct prompts, best/worst labels, provenance,
required flags and configured model settings survive every reuse operation.

The independent item-position oracle is zero-based. The required exercise's
four saved sets are `[2,1,3]`, `[0,2,3]`, `[0,1,2]`, `[0,1,3]` after actual
Move commands. The optional exercise retains `[1,2,3]`, `[0,2,3]`, `[0,1,3]`,
`[0,1,2]`. Each item appears three times; every pair appears twice. Fixed
order is declared to verify exact transport, with no optimal-design or
field-study recommendation implied.

## Observed acceptance

| Research action | Observed evidence |
| --- | --- |
| Author and review | Both exercises save alongside explicit liking. Coverage describes the connected four-item/four-set design without claiming optimality. |
| Edit membership and order | Item labels preserve identities. Actual set/item Move commands match the independent order oracle. Deleting an item still referenced by a set fails without replacing the draft. |
| Handle stale controls | A prior structure version cannot append a set. Prior-modal Save and Cancel cannot modify or close the currently open modal. |
| Cancel | Edited labels and framing are discarded; the complete exported original design remains identical. |
| Release safely | Synthetic materials fail both Pilot and Live release, with no deployment created. Example walkthrough explicitly creates a sample-origin release without relabelling the materials. |
| Understand and recover from errors | A rejected release's message stays readable through 2.6 seconds of untouched debounce/background activity. The next successful deliberate release clears it. |
| Serve the frozen study | The actual separate participant service starts the pinned design. Its protocol has eight explicit-choice steps before the final liking item and displays the authored prompt and response labels. |
| Withdraw | The actual browser visit stops as withdrawn with sample provenance. There is no processing job or report, and no claim of completed collection. |
| Reuse | Actual template use, clone and ZIP import each create new study, exercise, item, set and question identities. Every internal item/set reference and all framing, origin and settings remain exact. |
| Preserve history | The source design is unchanged after all reuse. Its original withdrawn visit remains attached only to the source; derived designs inherit no visits, reports or participant links. |
| Accessibility | Desktop and 390px editor scans, narrow collection, narrow participant choice and narrow saved Tasks scans have no axe violations or page overflow. No visible Shiny errors or browser exceptions remain. |

Two product gaps were found and fixed: the missing explicit sample walkthrough
release, and background autosave dismissing deliberate-action errors too quickly.
The latter now preserves errors until another deliberate command. Earlier test
attempts also corrected harness assumptions about Selectize's native option
nodes and the store entity's fields; those were not product defects.

## Boundary of this evidence

This is an automated simulated researcher journey using original synthetic
materials and an actual local browser/receiver. It is not observation of a human
researcher or participant, a qualified field study, an optimal-design assessment,
physical timing validation or scientific model qualification. This harness
deliberately withdraws its participant visit and proves **zero jobs and reports**.

Full participant completion, optional omission, reload, exact acknowledgement
retry, withdrawal races and response-transaction rollback are covered separately
by `tests/participant-maxdiff-delivery.mjs` and the method contract in
`docs/methods/MAXDIFF.md`. The separately executed
[completed-study report journey](MAXDIFF-REPORT-JOURNEY.md) passes 24 checks,
four accessibility scans and five scientific worker processes. Its later
collection and reports are additional workspace history after this authoring
checkpoint; they do not change the original authoring-only scope above.
