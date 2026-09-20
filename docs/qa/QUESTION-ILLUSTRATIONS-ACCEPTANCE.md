# Optional question illustrations

20 September 2026. Accepted bounded questionnaire slice. The subsequent MaxDiff
extension is recorded in `MAXDIFF-ILLUSTRATIONS-ACCEPTANCE.md` and shares the
contract in `QUESTION-AND-CHOICE-MATERIALS-CONTRACT.md`. This work does
not claim completion of the full 50-capability register.

Every enabled question type can now attach, describe, preview, replace and
remove an optional PNG through the saved-target material editor. The editor
pins the study revision and complete question, including its options and
display logic. Removal deletes only `illustration`. The field is absent by
default; no image or fallback description is inserted into old questions.

Publication and portable import decode the original PNG and verify its exact
hash, byte count and dimensions. Clone/template and ZIP routes retain the
image with its owner-specific description. Release URLs are capability-scoped
transport fields, outside canonical questions and frozen design provenance.
Later draft replacements do not change an existing release's permitted bytes.

The participant renderer prepares unique images before the first new question
visit/onset. Failed preparation offers an untimed retry without allocating a
second run. Forward questions, revision/back/edit screens and answer review use
the same prepared images. Review visibility follows the current branch
projection. Reopening restores the current draft and prepares its images before
continuing; information acknowledgements remain distinct from answers.

The supported engineering bounds are PNG up to 5 MiB, 4096 pixels per side and
8 million pixels per image; authored nonempty descriptions up to 2000 UTF-8
bytes; at most 64 million unique decoded illustration pixels. The subsequent
MaxDiff extension shares that pixel budget with questions. Unique question and
choice illustration bytes plus passive-media bytes together must fit 512 MiB.
Task-image and welcome preloads keep their separate existing bounds. These are
resource limits, not device or timing qualification. Both pure R validation and
the browser enforce the aggregate profile; repeated occurrences do not multiply
it. A malformed image-bearing protocol without a compiled occurrence URL fails
before media fetching.

## Evidence

| Check | Result and coverage |
|---|---|
| `tests/platform-question-materials.R` | **35 passed**: all 12 types; absent-field compatibility; exact removal; six allocations retain shuffled group/option order; individual and aggregate limits; same-byte/different-description owners; after-each reuse; transport isolation; real publish/GET, clone/template and cross-workspace ZIP; truncated PNG rejection; packed report provenance. |
| `tests/platform-question-material-views.R` | **13 passed**: pinned full owner, malformed upload and missing-description recovery, exact preview, forged/stale command rejection, description-only edit, removal, leaving Questions and no preview allocation. |
| `tests/participant-illustrations.mjs` | **21 passed**: matching resource profile, typed metadata, source/capability URL rejection, shared decoding with separate descriptions, missing compiled URL, retry, abort and unchanged input. Fake image class is limited to helper boundaries; real decoding is tested below. |
| `tests/researcher-question-materials.mjs` | **9 connected assertions passed**, actual R/Shiny authoring and receiver. Invalid PNG recovery; exact preview; blocked image request before visit and retry; branch hiding/invalidation; independent-answer retention; draft reload/resume; replacement/removal and frozen capability; all 12 forward renderers; repeated after-each answers; actual reports. |
| Browser accessibility and layout | **6 scans passed** at 1440 and 390 pixels: zero axe violations, no document overflow, no undersized checked editor controls, no uncaught script errors. Researcher preview/recovery and participant matrix/review screenshots were visually inspected. |
| Actual supervised analysis | **3 automatic reports succeeded**, one each for sectioned revision, forward twelve-type and repeated after-each sessions. Exact frozen design provenance matches each run. A subsequent read of final saved reports also verifies revised branch values, the resumed draft, independent numeric value and `information_acknowledged` with no answer value. |
| Existing delivery and portability | **56 delivery and 90 portability checks passed**, including actual ZIP and adversarial package cases, after the separately added equipment module was included in their minimal source lists. |
| Existing core and library | **109 core and 18 library durability checks passed**, including exact legacy snapshots and rollback. |

Final browser evidence:

`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-question-materials-02/browser-evidence-1789886732241`

Its parent contains `fixture.json`, `snapshot.json` and `worker-results.json`.
All owned servers stopped cleanly. The earlier `brohn-question-materials-01`
attempt is retained: its final harness assertion queried IndexedDB after the
application had correctly cleared a completed session. The fixed check uses
durable receiver events. No product behavior was changed for that harness issue.

After the successful full browser run, a small defensive tightening added the
aggregate check to complete R design validation, clarified its question/passive
scope, and rejected missing browser occurrence URLs. The final 35 domain,
13 Shiny and 21 helper checks include that tightening. Accepted image bytes,
rendered screens, study hashes and report source designs were unchanged; the
successful full journey and its screenshots remain applicable.

Fixtures use original synthetic images and scripted sample answers. This is
software qualification of the declared routes, not a study result, usability
study, physiological validation or hardware timing claim.
