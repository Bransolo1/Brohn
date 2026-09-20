# Combined participant study acceptance

20 September 2026. One original software fixture passed **11 browser assertions,
four accessibility/reflow scans and two actual supervised jobs**. This is bounded
integration evidence, not release, participant, hardware or timing qualification.

`tests/fixtures/participant-mixed-study.R` authors and freezes one sample study.
`tests/participant-mixed-study.mjs` operates the real participant browser and R
receiver. Retained evidence is in
`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-mixed-study-04`:
`browser-results.json`, `acceptance.json`, four screenshots and the owned server
log. Participant JavaScript hashes were checked before and after the journey.

The same allocated session completes the welcome PNG, consent, required-key and
practice-control checks, camera permission and first acknowledged recording,
four question presentations, two passive PNG exposures, 28 simple reaction-time
trials, four illustrated MaxDiff sets and the saved completion page. Native
browser keyboard/radio actions drive the tasks. All 28 final trial observations
are retained in the actual receiver, among 101 saved events. Equipment practice
is separate from study responses. The camera uses an explicitly synthetic Y4M
fixture, with actual frame callbacks, recording chunks and receiver receipts.

Both `assemble_capture` and `analyse_run` succeed. The decoded camera artifact
and automatic session report retain the same frozen design and run. Camera
analysis is disabled in this fixture; successful capture does not establish
face, gaze or physiological measurement. All four scans have zero reported axe
violations and no document overflow; the equipment and image-choice screenshots
were also inspected visually at 390px. This does not replace human usability
testing. The owned server closes after the run.

Three earlier harness failures remain visible in `brohn-mixed-study-01` through
`-03`: an incorrect participant-label selector; an incorrect start-endpoint URL
predicate; and an assumption that the browser retains its completed outbox after
the receiver acknowledges completion. The last was corrected to inspect saved
receiver events, because clearing that completed browser outbox is intended.
These required harness corrections, with no product change. The successful
fourth run is the accepted evidence; earlier incomplete test workspaces are not
claimed fully processed.

This fixture is programmatically authored. Actual researcher authoring has its
separate welcome, equipment, question and MaxDiff acceptance records. The
combined journey demonstrates their frozen participant behavior together, not
every study mode or physical motor/display timing.
