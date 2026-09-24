# Closed collection to saved history

24 September 2026. **Scoped connected acceptance passed:** 19 direct lifecycle
checks, 10 grouped full-browser assertions, four clean accessibility/layout scans,
one actual automatic response-analysis job and actual researcher/participant
service restart. This closes the participant-release inventory/history route;
it does not close PC02, PC06, PC13 or whole-platform completion.

## Product contract

Closing recruitment keeps existing sessions active under the existing participant
policy. **Review collection closure** appears for closed releases in Collect and
History. It lists unresolved participant receipts and linked processing and offers
the existing participant Review and Activity recovery routes. An active session,
unreceived final transfer, open camera recording, unassembled received recording,
missing completed-session automatic report or unresolved processing attempt
prevents finalization. A cancelled or failed attempt is resolved only by a
successful attempt with the same frozen request.

**Finalize collection** rechecks the reviewed inventory under one transaction and
refuses a changed review. It saves a single immutable collection record containing
the released design identity, all started sessions and their distinct terminal
outcomes, protocol hashes, linked job states, camera-receipt identities and exact
successful report references. It counts sessions; completion is separate from
scientific quality or participant independence. An empty closed release can be
finalized as an explicitly zero-start inventory.

This profile freezes the participant release and linked processing. It does not
silently attach separate device acquisitions, imported datasets or unrelated
cohort analyses. It does not calculate a new aggregate scientific result.
Finalized collection history opens its exact saved reports, downloads the manifest
and clones the released design revision without copying observations. Later draft
edits, new releases, reanalysis, archive and restart do not rewrite this record.
Existing terminal session outcomes remain immutable. Further collection uses a
new release; unarchive alone never resumes the old one.

The current finalization profile supports at most 2,000 sessions per release and
pages displayed session rows by 40 and closed releases by 20. A larger release is
refused with its existing Review/Results evidence retained; it is not truncated.
Shared or hosted collection, cross-release enrollment waves, operator-forced
resolution of abandoned browsers, participant withdrawal/purge reconciliation,
and whole-platform scientific qualification remain separate work.

## Direct evidence

`tests/platform-collection-history.R` passed 19 checks in
`make/work/test-runs/brohn-collection-domain-20260924-01/results.json`.
Receipt SHA-256:
`cbd6bb6cd8eafe6352fe4b2d2ae9b2e1bdd59cba7efc7b2d70e562eba5f2383e`.
The suite uses original isolated real start/withdrawal receipts and an empty
finalized release. It checks open/foreign release refusal, active-session and job
blockers, closed-link refusal, stale review, cancellation, idempotence, absence of
access credentials, historical design cloning, new release isolation, pagination
and actual local backup/restore. Restore preserved the manifest and closed later
recruitment while keeping the restored workspace paused.

These direct tests do not establish successful participant completion or automatic
scientific analysis; those belong to the connected browser test.

The later browser source also deduplicates repeated identical report references
from successful linked processing. The direct suite preceded that small addition;
the browser receipt pins the actual resulting source and shared entry points.

## Connected journey harness

`tests/researcher-collection-history.mjs` starts an isolated real researcher app
and participant service with `tests/fixtures/researcher-collection-history.R`.
The researcher authors an original control/candidate liking study, then uses
automated sample participants, actual durable receiver receipts and the supervised
R analysis path. The fixture helper does not inject studies, responses or reports.
It retains per-attempt source hashes, downloads, failure records, screenshots,
accessibility scans, worker result and the final saved workspace outside Git.

The browser scope includes one completed and one withdrawn session, analysis
cancellation/retry, closure blockers, keyboard finalization, exact manifest/report
exports, a new release, archive, historical cloning, and actual researcher and
participant service restart. It is not natural-human usability, hardware timing,
population performance or scientific-accuracy qualification.

## Executed connected evidence

The first browser run passed without a product or harness correction:

`make/work/test-runs/brohn-collection-browser-20260924-01/browser-1790217769241/results.json`

Receipt SHA-256:
`740efd9c5b6e25c647a5634a303cbd491c7547b850aa3d1f4c8ab2afee1bb889`.

The researcher authored a two-condition comparison, explicitly retained control
and test roles, set stimulus text/durations, separate consent and debrief, and a
liking question. One automated sample participant completed with exact answers
1 and 7; another started, remained active when recruitment closed, then withdrew
through its actual participant browser. A fresh browser could not start from the
closed link. The release retained its original design identity throughout.

Closure showed both the unfinished participant and the queued report, with no
Finalize action. Its actions led to actual session review and Activity. Cancelling
and retrying the automatically queued report created exactly two jobs: the
original was cancelled and its replacement succeeded through the supervised R
worker. The saved report contained the exact observed sample values; no report
was fabricated or preloaded by the fixture.

Keyboard finalization saved two started sessions, one completed and one withdrawn,
and the exact original report/protocol references. The manifest omitted aliases
and access credentials. Its download SHA-256 was
`db581ca19ccf490b25739b0f4ec284192a9b052df90c9dc584466421defed4ad`.
The collection opened that report with unchanged downloadable provenance.

Editing the draft and publishing a separate release did not change the original
closed release or manifest. Cloning from History retained the original released
question and control roles with zero sessions or reports copied. After archiving
and stopping/restarting both actual services, History reopened the same manifest.
Original report, received event journal and assigned protocol were unchanged.
There were no duplicate jobs, browser exceptions or changes to the five pinned
collection/entry-point source files between the start and end of the journey.

Four axe/reflow/target-size scans covered blocked desktop, finalized desktop,
finalized 390px and reopened 390px views. Each had zero automated violations,
zero horizontal page overflow and no targeted modal actions under 44px. All four
screenshots were visually inspected: status distinctions and actions were legible,
the session table fit the narrow viewport, and content wrapped without clipping.
Narrow modal content extends vertically and remains scrollable. These observations
are not comprehensive accessibility certification or human usability testing.

The local fixture and downloads remain outside Git. All owned browser and service
processes finished. For a fresh isolated run, from the repository root with the
prepared local runtimes:

```text
node tests/researcher-collection-history.mjs ../../work/test-runs/brohn-collection-browser-<unique-name>
```

The fixture uses researcher port 3891 and participant port 3892. It requires a new
fixture directory and must never point at a real research workspace. The included
domain suite has separate backup/restore and history-list pagination evidence;
this two-session browser run does not prove 40-row session navigation or the
2,000-session capacity boundary. Camera-specific closure and larger-volume
acceptance still require their own connected journeys.
