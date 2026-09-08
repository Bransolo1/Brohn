# Questionnaire option assignment: researcher acceptance

Completed actual-browser acceptance: **32 assertions and six accessibility
scans pass**, with eight completed browser sessions and 32 exact native responses.
The [assignment contract](../methods/QUESTION-OPTION-ASSIGNMENT.md) and its
independent domain oracle retain their separate numerical and compatibility
evidence. This journey examines how a researcher explicitly changes a draft,
releases it, reviews participant assignments and reuses its design.

The original fixture has six labelled refill-pack features with the distinct
codes numeric 0, boolean false, text `"0"`, text `"1"`, numeric 1 and boolean true.
Before-stimulus and after-each questions have the legacy-shaped absent policy
and enabled randomization; the end question is initially fixed. Two original
text concepts, fixed presentation order and 100 ms transport-only exposure keep
the browser exercise bounded. These are synthetic software inputs, not measured
participants, qualified presentation timing or a validated questionnaire.

The executed sequence is:

1. Open and save the existing randomized draft without implicitly migrating it;
   complete one real browser session on its original sample release.
2. Upgrade one question explicitly, reject its stale control, then upgrade the
   second. Enable the formerly fixed end question through its checkbox.
3. Release the saved draft and complete six actual browser allocations, checking
   the displayed option IDs against each received frozen protocol and every
   retained native response. Resume the first session at an untimed question and
   verify its order and draft answer remain unchanged.
4. Complete another session on the original release and compare its full
   assigned protocol with the pre-upgrade expectation. Review/download the
   assigned protocol through the researcher interface, distinguishing planned
   assignments from actual viewed or finished evidence.
5. Export, clone, save/use a template, reimport and reopen the design. Reuse must
   preserve the policy and typed option records under fresh identities; it need
   not reproduce a former study's permutation because identity enters assignment.

The fixture launches isolated Shiny and participant services and no scientific
worker. Completion may enqueue automatic analysis; the harness explicitly
cancels those unstarted jobs in its own workspace. This acceptance therefore
does not claim that a scientific report was generated. Desktop and 390-pixel
accessibility checks complement exact data assertions; neither substitutes for
observing human comprehension.

Both actual researcher downloads are byte-exact matches to the immutable stored
protocol SHA-256. The review table preserves each option's order and distinct
JSON code representation, and explicitly explains that an assignment does not
prove what was viewed or completed. Full downloads exclude access and resume
credentials. The old release's second enrolment retains its original algorithm
after the upgraded draft has already collected six sessions.

Evidence is retained at
`../../work/test-runs/brohn-option-assignment-ui-YSHGe3/evidence/results.json`,
SHA-256 `0fa9bd552da1cd28689be7c69e42b63e6a7bee7343a088bfc00a5d6c7e2adde9`.
All eight automatically queued analyses were explicitly cancelled without a
worker attempt, and no report was created. Owned researcher and receiver
processes stopped after the final checks.

This result includes a narrowly verified continuation. The initial 23 assertions
and four scans covered authoring and all participant sessions. An accessibility
scan began during stage replacement and inspected the dimmed outgoing Plan
subtree; the retained screenshot had already reached Collect. The harness now
waits for the requested stage's bound identity before inspection. A later
assertion also needed to compare labels and code elements separately from HTML
indentation whitespace. Neither retake changed product code. The continuation
independently rechecked all eight retained protocols, the original release and
the upgraded design before performing review, downloads and reuse. The original
scan and both harness failures remain beside the final evidence.

Harness: [researcher-option-assignment.mjs](../../tests/researcher-option-assignment.mjs).
Original source/service fixture:
[researcher-option-assignment.R](../../tests/fixtures/researcher-option-assignment.R).
