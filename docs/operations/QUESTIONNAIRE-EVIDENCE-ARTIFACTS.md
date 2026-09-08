# Complete questionnaire evidence beyond inline report limits

Status: connected scoped acceptance. The [retained worker journey](../qa/QUESTIONNAIRE-ARTIFACT-WORKER.md)
passes 27 checks/two publications. The [researcher journey](../qa/QUESTIONNAIRE-ARTIFACT-RESEARCHER-JOURNEY.md)
passes ten browser checks/seven scans and one further actual synthesis.

The original boundary fixture in `tests/platform-question-revision-boundaries.R`
completes 200 long-text questions, each with an original and revised 19,000-byte
answer. All accepted batches fit the participant transport contract. Its worker
input is 8,486,506 bytes; its full report is 24,090,330 bytes, exceeding the
16,777,216-byte worker document limit. All 200 final records page correctly, but
automatic report serialization fails. Historical `sizes.json` is retained in
`../../work/test-runs/brohn-questionnaire-revision-boundary/`. The original R
temporary workspace was automatically removed when that process ended, so its
full source journal is no longer retained. No scientific child was run in that
original reproduction, and its queued job was cancelled. The new explicit
retained receiver recreation in `tests/platform-questionnaire-artifact-worker.R`
reproduces both original sizes exactly. It is a new source and its own cancelled
job retry, never a retry of the vanished historical run. It retains 804 journal
events, 803 questionnaire history events, 400 commits and 200 final answers.

## Input: original run evidence files

`brohn_prepare_run_evidence_input(store, job, scratch)` replaces inline
protocols/journals for native run/cohort jobs with a small, versioned source
manifest. Protocol files retain the original stored JSON bytes. Journal NDJSON
retains each original stored event JSON line, including its legacy encoder;
bounded SQLite reads check original hashes, ordering and final sequence. The
manifest binds workspace, job attempt, original request, exact completed/saved
run membership, project, design and collection origin. It contains no credentials.

`brohn_read_run_evidence_input(input, scratch)` receives its scratch root from the
worker invocation independently of the manifest. It verifies containment, bytes,
whole-file hashes, consumed event sequence/hash chain and source bindings before
using the existing scoring input shape. An edited manifest cannot quietly
substitute a newer study or run. Current scoring still uses in-memory R objects;
removing the JSON envelope limit does not qualify unlimited memory or all ten
million theoretically permitted run events. Lease/cancellation checks must remain
effective while evidence is prepared.

## Output: full analysis with a compact preview

Oversized questionnaire results use
`brohn-questionnaire-analysis-artifact/1.0`, kind `questionnaire-analysis`.
The single typed NDJSON file contains the complete original analysis, including
distributions, observation values, scales/tasks, final questionnaire records and
acknowledged edit history. Deterministic ordered value/object/array nodes preserve
the complete structure; bounded string-part records preserve large escaped text.
The header pins canonical analysis SHA-256, source binding, exact counts and node
count. The initial artifact profile has an explicit 512 MiB read bound; records
are limited to 256 KiB each. Bounds are never satisfied by truncating evidence.

The report catalog uses `brohn-questionnaire-report-preview/1.0`. Its abbreviated
display rows exist only under `preview`, with full counts and artifact references.
They must never appear as the complete scientific `observations` or `features`.
The report remains small enough for existing catalog/publication contracts.
Original smaller inline reports retain their existing representation and bytes.

## Integration and acceptance

The coordinator independently verifies the complete typed artifact, source
binding and exact compact status/quality/counts/display shape, then publishes it
with the report through the existing staged Windows
read-handle/fencing contract. Published references preserve byte/hash/count
metadata and contain no scratch path. Full data readers verify and reconstruct
the original canonical analysis before downstream synthesis or numeric exports.
Browser and offline previews explicitly name their limits; complete data and
history downloads remain available after reopening. A damaged artifact must
produce an integrity failure, never a successful analysis of preview rows.

Required evidence includes the newly retained faithful overflow recreation
producing a saved report; actual input larger than 16 MiB; exact false/zero/null/Unicode and
binary64 round trips; escaped long strings; bad hashes/counts/order/paths;
complete CSV/JSON/NDJSON downloads; downstream synthesis beyond preview rows;
legacy inline report compatibility; and actual researcher desktop/narrow views.
Component checks alone do not complete this acceptance; the separate executed
worker and browser records above cover the retained fixtures and downloads.

Executed components: 57 run-evidence checks (20,748,348-byte original storage
journal to 1,518-byte manifest), 62 codec checks (22,963,103-byte synthetic report
to approximately 21 KiB preview), 24 storage/export/synthesis checks and ten
independent preview/publication integrity probes. The synthesis oracle puts its
six quantitative observations after twelve text rows: the ten-row preview has
none, while the complete source gives differences 2, 4, 6 and equal-person mean
4 across three people. No scientific child is claimed by these components.

Questionnaire observation CSV now includes exact canonical `response_record_json`
alongside readable spreadsheet cells. This keeps numeric zero, false, text,
null, empty answers and formula-like original text distinct. Fifteen export
checks pass. Twenty-eight generic CSV/TSV reader checks cover Unicode headers,
values, BOMs, multiline and no-final-newline files, malformed-byte rejection,
source bounds and actual typed questionnaire export/reimport under Windows C
locale. Non-questionnaire CSV writer behavior is unchanged; the complete JSON
and typed artifact remain lossless alternatives for every analysis field.
