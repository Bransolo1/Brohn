# Large questionnaire history: retained worker qualification

The historical counterexample recorded 200 questions, 400 entered answers,
200 final records, an 8,486,506-byte worker input and a 24,090,330-byte output
against a 16,777,216-byte single-document transport limit. Its measurements remain
at `work/test-runs/brohn-questionnaire-revision-boundary/sizes.json` under the outer
workspace. That JSON points to an R temporary directory which no longer exists.
The original completed run and cancelled job were therefore not retained after
the original R process. No later test should claim to recover or retry them.

The new `tests/fixtures/original-questionnaire-boundary.R` faithfully reproduces
the original receiver sequence in an explicitly retained workspace. It creates
200 long-text questions, visits and commits every question twice, checks paged
recovery of all 200 records, seals the occurrence and finishes the actual receiver
run. Each answer contains 19,000 `a` characters followed by its pass and question
number. This source is original synthetic software evidence, not human responses
or independently qualified timing. The recreated run's own automatic job is
cancelled at attempt zero and later explicitly retried; its source is preserved.

`tests/platform-questionnaire-artifact-worker.R` has separate preparation and
worker phases. `prepare` captures the actual receiver source, independent text
oracles, event-row/run hashes and complete current-code report into a fresh
`work/test-runs/brohn-questionnaire-artifact-worker-*` directory. It does not start
a scientific child. `run <that directory>` is the scientific qualification and
must run with shared product sources held stable.

The scientific phase is designed to verify the complete typed reconstruction,
all 200 final answers and 400 acknowledged answer versions, both exact original
text passes, revision/RT support, compact catalog and publication object equality,
full JSON/CSV/artifact downloads, source-scope rejection and reopen. Full exports
are deliberately separate from the bounded worker/catalog envelope. The test
also preserves the original historical size-evidence hash.

The exact source contains 804 journal events: 803 questionnaire-history events
(402 visits, 400 answer commits, one seal) plus `run_finished`. The answer-version
count must filter commit events; it is not the length of the complete history.
An initial preparation assertion used 400 as that total and stopped after the
receiver had completed and the baseline had been written. Preparation metadata
was then resumed from those same retained records, without generating replacement
source. The database-row fingerprint is an explicit list of row records, rather
than an unsupported data-frame value passed to the canonical JSON hash helper.

A second, separately labelled source seeds a 40-event journal directly into its
own run catalog: 36 original synthetic visibility payloads plus an optional
question's start, explicit null response, finish and completed-run ending.
The full sequence must pass the actual delivery replay reducer before storage.
Its total source journal exceeds 16 MiB while individual rows remain below 4 MiB.
This checks actual worker transport and exact source preservation. It does not
claim receiver acceptance of these directly seeded events or treat their text
as questionnaire answers. The expected scientific report retains one explicit
unanswered item and the visibility count, without inventing an answer value.

The first scientific execution saved the large revised-questionnaire report and
passed its complete reconstruction and export checks. Its second fixture then
correctly failed release validation because the test had created an empty design.
A separate test teardown ordering defect prevented writing that attempt's final
evidence document. Both failures are recorded in the retained execution note;
neither required a product change. The `continue` mode reuses that single saved
main report, reruns read-only evidence checks, and executes only the corrected
second fixture. It must not launch a replacement main report or relabel the first
execution as wholly passing. Evidence capture now precedes store close.

The completed continuation passed **27 checks** on 8 September 2026, with two
actual successful scientific publications in total: the first execution's saved
main report, and the continuation's large-input report. The first execution's
overall test failure remains recorded; the successful main publication was not
repeated. Its own original automatic job remains cancelled at attempt zero.
Final reopen checks found no queued or running jobs and unchanged original run,
journal rows and historical size-evidence hashes.

Retained evidence is at
`work/test-runs/brohn-questionnaire-artifact-worker-20260908-184203-a80ab4d8`
under the outer workspace. `fixture.json` contains the original text oracles,
`evidence.json` records the 27-check continuation, `continuation.log` is its
actual redirected process output, and `first-run-failure-note.txt` is explicitly
labelled as a transcription of the earlier tool output, not a raw execution log.
The prepared current-code output envelope is exactly 24,090,330 bytes, matching
the historical measured boundary. Main report
`report-job_46fd985e3f6b341cc11c16fd7cd217d7` has a 153,222-byte retained result
envelope and a complete 24,405,317-byte typed artifact. Its full JSON export is
24,110,326 bytes and its 200-row complete observation CSV is 7,871,502 bytes.
Canonical response-record JSON in that CSV retains exact typed source rows.

The second report, `report-job_ff57b264a9de6bbf4f0f7c7e3a067cb0`, consumes a
20,751,147-byte journal through a 1,549-byte input manifest. The independent
manifest and full original journal are retained. Exact source hashes, all 36
visibility payloads, the explicit null answer and completed replay were checked.
This is storage transport and actual worker evidence, separately labelled from
the main fixture's actual receiver path.

Preparation, continuation, worker and subsequent browser results are separate
evidence scopes. Complete reconstruction still holds analysis in R memory;
the bounded artifact profile is not an unlimited-memory or unrestricted
study-size performance claim.
