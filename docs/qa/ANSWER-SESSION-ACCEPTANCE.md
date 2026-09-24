# Saved answer to participant session evidence

Implementation and final acceptance: 24 September 2026. All owned fixture services
and native workers are terminal. Original research stores were not used.

The complete-answer explorer can open a native answer's exact local participant
session. The link binds the saved report revision, immutable answer index and
record hash to the frozen protocol, design and complete received-event hash.
Imported observations without that identity remain inspectable in the existing
explorer, without a guessed local session link.

The connected modal distinguishes received browser events, the originally
assigned sequence, original delivery receipts, any separate researcher resolution
and camera receipt metadata. It preserves the answer explorer and its acknowledged
revision/dependency history on return. It does not replay questionnaire scoring,
add responses, infer presentation from assignment, or qualify physical timing.
Camera receipt metadata does not establish media decoding or scientific eligibility.

## Completed domain evidence

`tests/platform-answer-session.R` passed **30 assertions**, retained at
`work/test-runs/brohn-answer-session-domain-20260924-07/results.json`.
This uses synthetic original questionnaires and the actual receiver, complete
source index and Windows native guarded publication; it is not a supervised-child
or browser claim.

Checks cover exact source authority, idempotent preparation/reopen, different
record/protocol/design/project refusal, unavailable local sessions, active sessions,
ordered paging beyond 25 events, exact selected-step filtering, long Unicode JSON
chunks, independent original full-journal byte hashes, original record preservation
and separate researcher-confirmed completion with a still-missing participant
final acknowledgment. CSV checks preserve every event type/hash and distinguish
ordinary labels beginning with r/t from actual control/formula-leading text.
The existing original response scorer is invoked only to
create the domain fixture report, before the new read-only feature.

Both new modules load under the required Windows `LC_ALL=C` runtime. The root
integration also passed the existing 40-check questionnaire explorer component
suite with the new optional callback hook.

## Resource and authority boundaries

- Preparation is a supervised read-only `answer_session` job. The Shiny callback
  and input resolver read exact metadata; complete event scans run in the child.
  Run/release guards project stored hashes directly without extracting/parsing
  the frozen protocol JSON. The child verifies that complete protocol and design.
- The child opens the local SQLite catalog read-only in one read transaction,
  verifies the immutable answer index and scans received events in ordered batches
  of 25. It independently recreates the full canonical event-array SHA-256 and
  compares every retained questionnaire history reference with its actual event.
- The initial transport profile permits one million events, a 256 MiB canonical
  journal, 4 MiB per event, 20,000 assigned steps, 64 MiB assigned protocol and
  1 MiB request/summary metadata. Oversized sources fail explicitly, without
  truncated session review or changed scientific classification. These bounds
  are safeguards, not empirical maximum-workload qualification.
- Derived SQLite uses one insertion transaction. Researcher pages contain at most
  25 rows and event text chunks contain 4,000 characters. Full received-event JSON,
  timeline CSV, assigned-protocol JSON and review provenance remain available.
- Publication uses the existing native guarded transaction and rechecks exact
  source metadata at commit. UI verification hashes full objects outside Shiny,
  holds native read guards and checks the retained publication envelope.
- Download URLs are token-bound to the active report/index/answer selection.
  Close, navigation, reset or changed source revoke access. The original explorer
  callback authorizes the selected record again for each active action/export.
- CSV protects formula-leading text with an apostrophe. Complete JSON retains the
  original types and values. Credentials are never selected into review evidence.

## Actual researcher/participant journey

Final receipt: `tests/researcher-answer-session.mjs` with
`tests/fixtures/researcher-answer-session.R` on isolated ports 3925/3926. The
original participant changes a typed branch repeatedly, clears dependent answers,
enters a long retained Unicode answer, hides that branch at final review and
finishes with numeric zero on the independent question. The researcher analyses,
opens a saved answer, inspects/exports its actual session, returns, inspects the
finally hidden answer's history and reopens after service restart.

`tests/verify-answer-session.py` independently checks original SQL bytes, complete
downloaded events, CSV rows, assigned protocol, source hashes, publication envelopes,
derived SQL rows, final response semantics and exact job accounting.

- **30 domain assertions** passed; **6 connected journey assertions** passed;
  **32 independent source/export assertions** passed.
- The final UI passed **5 scans** across desktop and 390-pixel layouts: zero axe
  violations, page overflow or visible action targets below 44 pixels. Received
  and assigned rows must actually be visible in their selected section; the
  inactive section must be hidden. Keyboard switching, focused return, expired
  URLs and restart/reopen are exercised. The original participant's separate
  narrow scan passed during the retained collection run.
- The original participant produced **30 acknowledged events**, one genuine
  completion and one final receipt. Its two final observations retain numeric
  zero and exclude the finally hidden dependent answer. The earlier long Unicode
  answer remains available in the original 8,422-character event and does not
  become another scored response.
- **7 jobs**, all succeeded on attempt one: one original scoring job, one answer
  index, three explicitly retained earlier reader versions and two current
  readers. No new scoring or reader jobs were created by final reopening/restart.

Final evidence directory (relative to the parent `make` workspace):
`work/test-runs/brohn-answer-session-browser-20260924-01/browser-1790227837229`.
The preserved original participant evidence is
`work/test-runs/brohn-answer-session-browser-20260924-01/browser-1790225678768`.
The final `results.json` names both, every job ID and all unchanged source hashes,
including the global researcher UI assets. The preceding corrected-worker run
`browser-1790227131459` also passed the independent export oracle; final UI
acceptance is the later receipt above.

Manually inspected final PNGs cover the desktop event table, both sides of the
narrow event table, assigned sequence and retained long-event text. Their
`*-evidence.png` captures target actual content regions, because Shiny output
wrappers themselves have no layout box. Horizontal table scrolling preserves
complete columns without creating page overflow. These screenshots and axe checks
are bounded visual evidence, not a claim of universal assistive-technology testing.

| Receipt | SHA-256 |
| --- | --- |
| Domain `-07/results.json` | `1ba6633f2ed44978dde10e6b2551c425e27f8564b112629ea14e9e55d148ed03` |
| Final browser `results.json` | `3d35c6d1679509cc1191220841e6f0509dcd0bbe1a0aee6eb02172035e477ce8` |
| Final `independent-source-audit.json` | `747845364194d542e212132374d394301b2a76094f312ca044828449f6b9ec95` |

## Reproduction

Run from the repository root with the R library, publication Python and native
publication manifest configured as in `RUNNING-CHECKS.md`. The domain test accepts
optional `BROHN_ANSWER_SESSION_TEST_ROOT`; by default it retains a fresh temporary
workspace. It does not touch an existing research store.

Create a fresh external directory named `brohn-answer-session-browser-*`, then run
the fixture's `setup` mode, the browser harness with that directory, and the Python
verifier with the fixture directory and final browser evidence subdirectory.
Coordinate source freezing with other live workers first. The harness stops only
its own two services and verifies that the source fingerprints remain unchanged.

Initial test-fixture corrections: index publication scratch was moved inside its
owned workspace; exact R list lookup replaced a partial-match title access. The
first browser attempt stopped before collection because the harness assumed a Plan
landing while the current app opens Overview; the harness now checks the actual
study heading before selecting its stage. The next real browser run produced the
original participant journal, original report, source index and one derived view,
then exposed low contrast on the dynamically inserted modal tab. A scoped view fix
corrected the active-tab palette. Later runs corrected harness waits for updated
filter generations, and found missing tab semantics in Shiny's dynamic modal;
the view now supplies explicit ARIA relationships, selected state and standard
keyboard navigation. The final renderer uses local native buttons and explicit
panel visibility; acceptance requires visible rows in each selected section and
hides the inactive section. The visual diagnostic also found that scrolling a
zero-height Shiny output wrapper did not scroll its visible child table. The
harness now scrolls the actual child region and captures its viewport, including
both sides of the narrow horizontal table. Earlier DOM-only journey receipts are
preliminary UI evidence, not final visible-flow acceptance. Original participant
and scoring work were retained.

The metadata guard was subsequently hardened to avoid repeated protocol JSON
extraction. Its new implementation identity requires new derived views; the
earlier successful reader result stays retained and is counted explicitly.
The independent CSV oracle subsequently found an overbroad base-R escape pattern
that prefixed ordinary r/t labels. Exact first-character comparison replaced it;
complete source JSON/SQL were unchanged. The oracle now passes against corrected
current readers. Three earlier derived readers remain retained and are explicitly
counted alongside two current readers. Together with the one original scoring job
and one immutable answer-index job, there are seven successful attempt-one jobs.
No participant/scoring/index rerun was needed. Final visible-panel reopening,
screenshots and exact source/export verification passed with the same seven jobs.
The harness also supports `--visual-only` for a read-only retained-store layout
diagnostic; it does not collect participants or run workers.
