# Complete questionnaire explorer: implementation contract

Status: proposed next implementation slice. This document changes no runtime,
source data, analysis or participant protocol. Resource settings below are
proposed qualification targets, not measured performance guarantees.

## Researcher outcome

From a saved report, select **Explore all answers** once. Find a question or a
participant/session code, page the complete saved records, read an unabridged
answer, and inspect its acknowledged changes and dependency invalidations. Keep
the report's original design, source origin, scientific status and denominators
visible. Browsing does not recalculate a score or alter the study.

The first release covers questionnaire summaries, response records and retained
questionnaire revision history. Scale, implicit-task and MaxDiff records remain
available through their existing result views/downloads; this explorer must not
pretend questionnaire response rows are those methods' trial evidence.

## Reuse and current constraints

- `platform-signal.R` and `platform-signal-views.R` provide the useful pattern:
  explicit opening, a frozen report/artifact request, a supervised preparation
  job, bounded views, and polling that updates progress without replacing form
  inputs. The new explorer must retain that input stability.
- `platform-gaze-report-views.R` demonstrates composite person/session/exposure
  keys and exact pinned design validation. A question ID or stimulus label alone
  is not a questionnaire assessment identity.
- `platform-questionnaire-artifacts.R` verifies the complete typed NDJSON,
  canonical node sequence, strings, full analysis hash, counts and source
  binding. Its reader reconstructs the entire analysis in R memory. Bounded
  lines do **not** make the current reader an out-of-core query engine.
- `platform-questionnaire-artifact-storage.R` additionally verifies the compact
  preview against that full analysis. Every saved hydration supplies
  `brohn_questionnaire_artifact_source(report)`; an artifact hash by itself is
  not authorization to read a different report or project.
- `platform-question-revision-delivery.R` retains exact effective records,
  event references, full questionnaire events and invalidations. Their hashes
  and IDs support inspection without replaying the protocol in the view.

## Interaction

Keep the existing brief preview and complete downloads. Add one opening action
with the exact report identity. While preparing, show **Preparing saved answers**,
an honest indeterminate progress indicator, Cancel, and the still-usable report.
Do not manufacture a percentage or run scientific processing again.

The ready explorer has two ordinary labelled views:

1. **Questions**: a paged list of the original saved question/condition summaries.
   Find a question by its prompt or code; select a condition. Each row shows the
   recorded response/answered/missing counts and the saved quantitative mean
   only when its original status permits one. Opening a question shows its
   full distribution, paged independently, and **See answers** applies that
   exact question/condition to the Answers view. Person filters do not change a
   saved whole-report summary or create a new filtered mean.
2. **Answers**: question, condition/stimulus, participant code, session and final
   state filters. Start with every available final state, not just answered
   rows. Show **Showing 1–50 of 200 matching records; 200 records in this saved
   source**. Selection opens a detail panel containing the frozen prompt,
   native value type, full value, state, person/session, assessment placement,
   stimulus and source identifiers. **Changes** opens this exact assessment's
   source-linked history within the same panel.

Use **Participant/session code**, not an inferred person name. Unlinked browser
runs remain labelled **Unlinked session**. A supplied alias is explicitly a
researcher/participant code, not verified identity; repeated visits remain
distinct. Imported sources with no revision evidence say **No edit history was
retained for this source**. They must not display a fabricated zero edits count.

Preserve filters, page, selection and scroll when closing detail, returning from
Questions, or receiving an unrelated job update. Search uses a bounded literal
UTF-8 query, not regex or user SQL. For the first qualified profile, matching is
case-sensitive with a visible **Match case** indication; do not silently claim
Unicode case folding that the installed R/SQLite configuration has not proved.
Exact code selectors remain available. Fuzzy matching or multilingual case
folding is a separate, versioned search capability.

At 390 px use a single-column result list with native buttons for each record;
keep full tables available on wider layouts. Do not require horizontal page
scroll or drag gestures. Use real labels, at least 44 px targets, visible focus,
keyboard pagination, an announced matching count and focus restoration to the
opening row. Only the detail content changes when a row is selected; it must
not reset the search form. Text is escaped and may contain HTML-like strings
without being interpreted as markup.

## Exact source semantics

The index records source locations and hashes, never a new scored projection.

| Collection | Source | Meaning and identity |
|---|---|---|
| Questions | `analysis.features[i]` | Exact saved summary; source row and hash. Distribution entries keep original order and typed values. |
| Final states | `analysis.questionnaire_revision.runs[r].effective_records[i]` | Key includes run/session, occurrence and compiled step ID. This includes not displayed, optional omission and information states. |
| Recorded responses | `analysis.observations[i]` | Separate adapter for sources without revision projections; keep source index/hash and supplied identity. Never infer an assessment from question/stimulus labels. |
| Changes | Revision `history_records` joined to `history_events` | Join exact event ID, sequence and source-event hash within the exact run; do not join across runs by ID or row position. |
| Invalidations | Revision `invalidations[i]` | Exact cause event, previous head event, dependent step, rule/policy hash and generation. |

For revision-backed reports, Answers uses effective records once. Do not append
the overlapping `observations` collection and count the same answer twice.
Retain a source link to the observation when one exists. Information and hidden
states are not scored questionnaire responses and do not change the published
response denominator. If a report contains mixed/unsupported source shapes,
explain which adapter is unavailable rather than silently omitting its records.

History remains append-only evidence. Label a confirmation of the same value
as **Confirmed the same answer**; do not count it as a newly scored answer.
Show replacement and dependent-answer clearing with their exact stored causes.
A hidden or invalidated former answer stays visible in history but never
appears as the current answer. Different before/after-each/end occurrences,
including repeated stimulus labels, remain separate.

Show original response-time fields only with their retained support. Revised
or resumed initial response time stays unavailable when the source says null.
Do not subtract clocks from different page instances, infer time spent reading,
or reinterpret source history as physical timing qualification. Browser clock
strings remain exact strings in the evidence view.

## Proposed APIs and immutable binding

New files should isolate the explorer domain/storage and UI, for example
`R/platform-questionnaire-explorer.R` and
`R/platform-questionnaire-explorer-views.R`. Register only after scoped tests.

```r
brohn_queue_questionnaire_index(store, report_id, report_revision,
                               expected_report_hash)
brohn_questionnaire_index_input(store, job)
brohn_build_questionnaire_index(input, scratch)
brohn_publish_questionnaire_index(store, output, scratch, job, input)

brohn_questionnaire_page(store, index_id, expected_index_hash, query)
brohn_questionnaire_record(store, index_id, expected_index_hash,
                          record_key, record_hash, value_page = NULL)

brohn_questionnaire_explorer_ui(report_record)
brohn_install_questionnaire_explorer(input, output, session, store, state,
                                    attempt, message, prepare_download)
```

The build operation is `questionnaire_index`, recipe
`questionnaire-explorer-index/1.0`, and produces a derived view/index entity,
not a scientific report. Opening an existing matching index reuses it; it does
not enqueue another analysis. The shared job coordinator owns cancellation,
leases, source-code identity, staging and fenced publication.

Freeze at least workspace/project, report ID/revision/body hash, retained result
object hash when present, artifact descriptor hash, artifact SHA/size/schema,
full analysis hash, source binding/hash, original origin, design hash and index
recipe/code identity. An inline report uses its exact retained analysis/body
hash instead of an invented artifact reference. Missing retained-result objects
in historical reports must retain an explicit support category; do not promote
them to supervised publication evidence.

Check project authorization before returning report metadata or opening its
artifact. The coordinator resolves object paths, verifies the pinned source and
hands the child only the bound input. The child verifies full analysis and
compact semantics, then builds an index. On publication, the coordinator
rechecks the same report revision and artifact binding under the existing
publication fence. Never substitute a newer report after review or retry.

A suggested index is one immutable SQLite artifact, opened read-only by the
query adapter. It contains a manifest plus summaries, distribution entries,
final/recorded response metadata, canonical complete source rows, history and
invalidation links. Row keys derive from the full source binding plus original
typed source path; duplicate-looking values do not collapse. Every row retains
its canonical source hash. Validate join completeness and collection counts
against the original artifact before publication. Derived search indexes may
change query speed, not source order, value types or scientific counts.

This is a source-linked view artifact. It remains distinct from the original
questionnaire NDJSON, and deleting/rebuilding the view must never remove or
rewrite that original. Published indexes follow the existing object-store and
backup integrity rules; do not add an untracked copy of response data to a
general OS temporary cache. A corrupt index is unavailable and may be rebuilt
from its exact retained source, with an explicit action.

## Paging, large values and cache

Queries allow only named collections, declared filter fields, bounded literal
search and fixed sort choices. Use bound SQL parameters. Default sort is the
original saved source order; optional session/question sorts include the source
ordinal as a deterministic tie-break. Keyset cursors bind index hash, query hash,
sort version and last ordered key. Reject a cursor from another filter or
report. A new filter starts at the first page, preserving the prior selection
only when it is still an exact member of the new result.

Default page size is 50, allowed 25/50/100. Facets are paged/searchable too;
never send every person or question to a browser select control. Return full
source count, exact matching count, returned count, next/previous cursor and
source identity. No-match is distinct from missing/corrupt evidence. List
values may be abbreviated with an explicit indicator; counts always describe
the complete matching source, not the preview window.

Each response is at most 512 KiB. Detail returns small values whole. Larger
text or canonical JSON is read in contiguous UTF-8-safe chunks, up to 64 KiB
raw text and the final encoded response budget. Return start/next character
positions, total characters/UTF-8 bytes and full value hash. Navigation never
drops text: every chunk is reachable, boundaries preserve code points, and
rejoining chunks must exactly reproduce the canonical/source value. Distinguish
a native text display from a structured value's canonical JSON display.

The index is the persistent reuse layer. In-memory cache contains only bounded
page/detail responses, keyed by the complete source/index/query identity. A
proposed first profile is at most 8 MiB per session and 64 MiB per process, with
LRU eviction and a 15-minute idle lifetime. No full analysis object remains in
a Shiny reactive value or a global cache. Invalidate session cache on workspace
switch or access loss. Recheck the report/index descriptor and authorization on
each action. Verify immutable index bytes on open; cached handles must remain
read-only and source-bound. Do not hash a large artifact on every keystroke.

The first implementation can use the current full reader **only in the
supervised index-build child**, then release the full R object after indexing.
Retain the current 512 MiB artifact/256 KiB line/one-million-node bounds. Add an
explicit worker resource profile, provisionally 1 GiB monitored resident memory,
1 GiB derived-index disk budget and a 300-second build deadline, with one such
build per workspace. Polling resident memory is a termination guard, not a hard
guarantee against transient allocation spikes. Qualify these settings with real
fixtures before enabling the feature.

Encoded input bytes are not a reliable estimate of R heap size. Exceeding the
profile must stop without publishing a partial index, retain the report and
downloads, and explain **This saved result exceeds this installation's
interactive-view limit**. Never retain only the first N records to fit. A fully
streaming canonical verifier/index builder is a later implementation if the
largest allowed artifacts exceed this bounded full-reader profile; the current
codec must not be advertised as providing that behavior.

## UI identity, concurrency and source links

Use a fixed, bound form context: report ID/revision/hash, index ID/hash, tab,
query generation and request ID. Apply actions atomically to the current form
values; do not bake recently typed text into stale server-rendered button
payloads. Debounce search requests, but accept an immediate Enter/apply action
using those same current values. Ignore late results for a different context.
Changing reports clears visible source content immediately, even if an old
build finishes later. Cancelling an index build cannot publish it through a
late callback. Poll only status leaves; stable completed controls must not be
re-rendered during unrelated jobs or a table page request.

Each detail includes a concise **Source** disclosure with report/analysis hash,
source path/ordinal, row hash and applicable event IDs. **Open saved session**
is offered only when that run exists in the same authorized workspace and its
frozen protocol/event identity matches the report. Otherwise the complete
retained event payload remains inspectable and the unavailable session link
is explained. Do not expose server filesystem paths or participant access
tokens in the browser or exports.

## Acceptance before release

1. An original source with more than ten questions and more than fifty records
   has a known answer beyond both preview boundaries. Find it by question and
   participant/session, page every result exactly once, and read its full text.
   Filtered counts and source hashes match independently enumerated source rows.
2. An independently specified distribution has a distinctive value beyond the
   first five count entries. The full distribution shows it with its saved
   count; searching a person never changes the published mean/denominator.
3. Native false, numeric zero, text zero, null omission, empty text, structured
   values, Unicode, HTML-like text and formula-like text display safely and
   remain distinct. Rejoined long-value chunks reproduce the exact original
   value/hash, including newlines and multibyte boundary cases.
4. Two sessions sharing a supplied alias, two unlinked sessions, and repeated
   stimulus labels produce separate assessments. No unique-person count or
   verified identity is manufactured.
5. Use the existing false/zero driver, transitive and still-visible dependent
   invalidation fixture. The final answer remains authoritative, prior answers
   remain only in history, confirmation does not increment scored versions,
   and the final two-item 6+4 scale result remains 5 without rerunning scoring.
6. Sources without revision evidence and information-only states are labelled
   honestly. The explorer neither invents history nor duplicates overlapping
   observation/effective rows. Missing source joins fail visibly.
7. Exact report/index/query cursors reject foreign projects, swapped artifacts,
   altered compact status/counts, corrupt index bytes and stale form actions.
   Late search/build responses cannot replace a newly selected report. Reopen
   and restart recover the same complete source without rerunning analysis.
8. Immediate type-then-search, filter-then-next, close/reopen detail, cancellation
   and unrelated job completion preserve correct selections and keyboard focus.
   Desktop and 390 px browser journeys pass accessibility scans and manual
   keyboard reading/pagination with no page overflow or hidden modal errors.
9. Resource-limit and cancellation fixtures publish no partial index; complete
   source reports remain downloadable. Measured memory, build duration, index
   size and page latency are retained with fixture size/code identity, without
   converting target limits into unsupported performance claims.

Implementation should land in three connected checkpoints: source-bound index
and pure query evidence; guarded UI and detail/history browsing; then the actual
researcher journey above. Each checkpoint keeps existing full downloads usable.

## Development handoff at the requested stop

On 8 September 2026, feature development stopped at the user's request. The new
`R/platform-questionnaire-index.R` module and
`tests/platform-questionnaire-index.R` are **unregistered**: their presence does
not enable the explorer in the application. The latest completed standalone run
passed **49 checks** using original synthetic fixtures; both files also passed
the final parse check. No scientific workers or browser services were launched
for those checks, and no owned process remained at handoff.

The pure module builds a complete, source-bound SQLite index and provides
`brohn_questionnaire_index_open`, `brohn_questionnaire_index_close`,
`brohn_questionnaire_index_page`, `brohn_questionnaire_index_record`, and
`brohn_questionnaire_index_value`. The tests cover the 50-row page boundary,
exact typed and Unicode values, full value chunks, saved summaries and
distributions, revision/history/invalidation source links, compact-source
verification, source/hash failures, read-only handles and failure cleanup.

Authorization, supervised build limits, native immutable-file guards, job
registration, publication, session caching, UI integration and the connected
browser acceptance above remain unfinished integration work. Separate adapter
and UI files may exist as drafts; no connected explorer qualification is claimed
here. The builder hydrates the complete analysis in R memory, so its byte and
row bounds are not measured peak-memory or execution-time guarantees. A saved
read handle relies on the coordinator's held native file guard in addition to
the pure module's whole-file hash at open and file-identity checks.

## Deferred participant review refinements

These remain follow-up work and are not implemented by this document:

- An information-only review row should say **Review information**, with its
  corresponding accessible label, instead of **Edit answer**. It has no scored
  answer. Existing acknowledgement and revision semantics must remain intact.
- The participant header currently derives **Part 2 of 19** from the outer
  delivery cursor, which deliberately stays at occurrence entry until sealing.
  Use **Answer review** or **Final review** for review screens, and an explicit
  within-part question count based on the actual displayed frozen step and
  current canonical visible-step list. If overall progress remains visible,
  name it separately. Never mutate the transport cursor to repair presentation,
  count hidden questions as viewed, or imply back-navigation across timed
  stimuli. Test conditional branches, resumed review, adjacent occurrences and
  the final review at 390 px against unchanged durable events/receipts.
