# Native task evidence export and reimport

This bounded journey uses an original synthetic 48-trial choice-reaction-time
journal. The full journal goes through the production R receiver and completes
its frozen study. Eight practice trials and one scored trial have correct 500 ms
responses; the other 39 scored trials time out. This is deliberately generated
software evidence, not observed browser task participation or qualified physical
timing. The original automatic run-analysis job is cancelled before it starts.

The researcher then uses the actual local browser interface to open the assigned
protocol and download the complete trial CSV, frozen registry and export notes.
The CSV is transferred back through the explicit filename, family, origin and
destination review. A real background intake retains its exact bytes. The
researcher selects the saved study revision, original task, collection namespace,
registry and source definitions before launching an actual analysis worker.

The independent scoring expectations are:

| Source declaration | Expected result |
| --- | --- |
| Response-time or terminal-response definition unknown | Retain all 48 source rows and the administration, but make scoring explicitly unavailable. |
| Both exact native definitions declared | Mean and median 500 ms; sample SD unavailable because only one correct scored response remains. |
| Omissions | 39 of 40 scored test trials: 0.975. |
| First-response errors | Zero of one answered scored test trial: 0. |
| Identity and provenance | Participant text `001`, explicit repeated-session linkage and collection namespace; original source and registry hashes remain exact. |
| Imported evidence level | `declared_trial_summary`; journal replay and physical timing qualification remain false. |

The import must not inherit the stronger native export's replay status. Empty
timeout latencies remain empty rather than becoming zero. A malformed protocol
file must not replace the dataset, mapping or object catalog. A later corrected
mapping must create a new report while preserving the earlier unavailable one.

The complete task-score CSV keeps separate task and metric eligibility, source
attempt identity and evidence level. JSON and saved publication envelopes must
match exactly, and the original CSV must remain byte-identical after reopening.
Desktop and 390-pixel checks cover mapping, original-protocol export and saved
report presentation; standalone HTML is checked separately.

The complete retained-source continuation passes **19 browser assertions and
five accessibility scans**. One actual intake job and two actual scientific
import jobs succeed; the original run-analysis job remains cancelled at attempt
zero. Both report publication envelopes match the catalog exactly. The two
analyses record the same 34 executed source-file hashes, with the native
publication DLL and its build inputs retained in their processing provenance.
All owned services stop cleanly.

The initial run in the same workspace already observed the complete-file review,
its explicit action and successful immutable intake. Its harness then waited on
the normal Shiny input cache for a file upload that had actually completed.
The continuation uses the visible upload-complete receipt and reopens the exact
retained source; it does not regenerate or relabel it. Earlier fresh runs also
corrected test selector assumptions about selectize label fields, study-ID
suffixes and saved-revision labels. No product fix was needed for this journey.

Final evidence:
`../../work/test-runs/brohn-native-task-import-SqroKv/evidence-resume-1788861347657/results.json`,
SHA-256 `15582505be802f74b50e03adabe4854b35cf2ea7bd7963332a1ebf2b6875020e`.
The earlier actual intake observations remain in that workspace's
`evidence/failure.json`. `executed-source-identities.json` and
`source-verification.json` retain both publication identities and the independent
exact-envelope check. The source identity export has SHA-256
`0935cc3f98a0bb1c053b0f84837d04aa0a58c12992b70fdfb73cff06319a9fe6`.

The checked UI still calls this family "Implicit task (retain source)" despite
now offering source-bound scoring. Renaming that option would improve discovery;
it does not affect this preserved analysis evidence. These checks do not
establish arbitrary vendor compatibility, observed human comprehension or
physical timing qualification.

Harness: [researcher-task-import.mjs](../../tests/researcher-task-import.mjs).
Fixture: [researcher-task-import.R](../../tests/fixtures/researcher-task-import.R).
