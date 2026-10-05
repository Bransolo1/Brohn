# Participant recovery checkpoint — 5 October 2026

Brohn remains unfinished. The inactive development snapshot now contains 72
source files, including the ordinary participant host, finish networking and
stimulus preparation. No production loader, route or renderer is activated.
The exact sources and local receipt identities are in the
[source index](ASSIGNED-QUESTIONNAIRE-COMPONENT-SOURCES.json) and
[snapshot manifest](../../development/assigned-questionnaire/SOURCES.json).

## Real R questionnaire recovery

The first integration attempt exposed a real composition defect: the image-alert
component lacked `flushDraft()`, which the controller calls before navigation,
refresh and close. Earlier component and controller tests used different source
combinations. The failure is preserved; its new recovery cases did not run.

The corrected component combines the original draft-draining guards with the
image-alert fix. It waits for captured revisions without inventing a new value,
revision or clock. The same tests, R authority, controller and timeouts then
passed: 19 browser, 30 R and 33 wrapper checks, plus two mobile Axe scans with
zero violations. The receiver independently replayed the received public events
against the original source reducer.

Both an aborted observation write with a queued follower and a real database
versionchange recovered their exact original events. Close refused promptly
before and during recovery; duplicate Retry calls joined one operation. Fresh
received state, draft restart, lost-reply recovery, conditional branching,
review, sealing and released handoff also passed. All owned processes/listener
closed naturally and the retained source files remained exact.

Selected controller: `3d947a1d…`; component: `3bd8a4d1…`; acceptance:
`5870f1a95ed15fa756884591191c034f01622b3f5120dd89c3b2349f2058a2f9`.
This remains a held conditional-questionnaire fixture with a test-only image
adapter. It does not prove entry, the production assigned-image provider, timed
exposures and finish ran together.

## Ordinary host and finish

The earlier host candidate passed 22 terminal-custody and 32 ordinary-host
browser checks. Visual inspection still found a stale Finish action after a
failed ending save; its supposed phone recovery screenshot was actually desktop.

The explicit UI06 successor passes 24 focused browser checks, 27 syntax checks
and four zero-violation Axe scans. Actual 390×844 screenshots and keyboard checks
cover instructions, finishing, failed-save recovery and confirmation. Healthy
screens offer one primary action. A captured ending removes Finish immediately;
Retry saving retains the same ending ID, clock, document and finish request.
Busy state prevents duplicate actions. The original protocol text/colors remain.
Source-identical cleanup was independently confirmed. A technical error message
still needs plain participant wording in the next host integration.

UI06 acceptance: `3e4201756528d29fe1b0120797c5d199670093143f97c70cd2ce4b45beed9cb0`.
These tests use explicit controlled Node authority and do not exercise the
questionnaire. UI06's tested dependency included the older component; the selected
combined component has the separate real-R recovery acceptance above.

Finish networking independently passes 70 functional and two real-timeout browser
checks, with 13 syntax checks per phase. Assigned ordinary stimulus preparation
passes 63 functional and two real-timeout browser checks, with eight syntax checks
per phase. Those are controlled-authority/native-browser checks, not actual R
resource delivery, a complete host or physical media-onset qualification.

## Remaining integration

Join the exact host, entry, assigned illustrations, corrected question component,
timed/material renderers, ending and automatic worker/report pipeline against real
R. Keep all task, MaxDiff, equipment/camera and withdrawal/restart requirements.
Complete the researcher author-to-report journey, performance fixes and portable
server/test packaging before enabling the profile.

The [timed-sequence contract](../architecture/ASSIGNED-TIMED-SEQUENCES.md) prevents
network/storage waits inside exposures and silent replay after a crash. Its arm
ledger and renderer are separate implementation work; their proposed behavior is
not established by the passes above. Survey-only release admission also remains
open: the current variant design requires stimulus concepts/sets and cannot
honestly claim questionnaire-only publication by deleting compiled screens.

All 17 packages, all 50 capabilities and QF01–QF08 retain their individual
unfinished gates. These counts overlap scoped cases and are not a product
completion percentage, scientific validation or a Qualtrics-parity score.
