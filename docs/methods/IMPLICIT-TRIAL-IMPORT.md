# Original implicit and reaction-time trial import

Brohn accepts trial summaries for its five exact registered IAT, BIAT, keyboard
approach/avoidance, simple reaction-time and choice reaction-time profiles. It
retains the original file and requires the complete original task definition and
realized compiled protocol. Arbitrary vendor exports need a reviewed converter;
matching column names do not establish matching timing or scoring procedures.

## Researcher route

1. Open a completed saved participant session, choose **View assigned protocol**,
   then **Export original task trials**. Select the task and download its trial
   CSV, registry JSON and export notes. The stored protocol supplies the export;
   later study edits do not rewrite its task or participant assignment.
2. Import the CSV through Data using the implicit task family and declare its
   collection origin. After background transfer, review the retained file.
3. Select the exact original study revision and task. Upload the corresponding
   registry JSON and choose **Use this protocol file**. A clone has new identities
   and cannot silently substitute for the source study.
4. Review the collection namespace, source statement, software when known, column
   mapping, target-onset latency definition and terminal response rule. Unknown
   definitions are permitted as retained evidence but withhold affected scores.
5. Choose **Confirm mapping and analyse**. The job pins the source bytes, registry,
   mapping and study version. Review task metrics, unavailable reasons and original
   trial support; download the full report JSON and dedicated task-score CSV.

The machine trial CSV preserves typed codes such as `001`, `NA` and Unicode as
text. It is an interchange file. The separate task-score CSV is intended for
spreadsheet review and protects formula-like text; it is not a trial import file.

## Fixed evidence contract

`brohn-implicit-protocol-registry/1.0` contains the complete original task plus
named complete compiled protocols and their canonical hashes. Brohn validates
the whole deterministic compilation, not just the profile name or trial count.
The registry is stored as an immutable original byte object with byte count,
raw SHA-256, canonical hash and task-definition hash. Mapping and queue gates
check the exact current selection before accepting a source.

CSV/TSV limits are 20,000 original rows, 1,024 unique columns, 1,024 distinct
column names and 20,000 total expected trial positions. The registry is bounded
to 16 MiB and 1,000 compiled protocols. Missing expected rows remain explicitly
derived missing-evidence diagnostics; they are never invented source rows.

Required mapped fields are participant and declared repeat linkage, source
session and attempt, protocol, realized presentation index and trial ID,
presented flag, outcome, first and final codes, first correctness, first-response
and final-correct latency, and missing reason. A named collection namespace
separates identical labels in different sources. Optional task selection retains
excluded rows; a contradictory selected-row origin rejects the mapping.

Latencies are nonnegative decimal millisecond strings, optionally using decimal
scientific notation. Original lexemes remain retained. Parsing rejects malformed
tokens, non-finite values, values above 1e12 and nonzero values that underflow to
zero. Unknown timing semantics do not become known merely because numbers parse.

Outcome consistency checks include actual presentation, valid keys, first/final
correctness and timing, forced correction when required, fixed response deadlines,
stopped attempts and exact compiled positions. Material origin (`synthetic` or
`researcher_supplied`) remains separate from collection origin. Synthetic
demonstrations remain sample/preview evidence.

## Interpretation and automation

Complete compatible evidence runs the existing named scorer. Reaction-time
availability is per metric: one correct response can support a mean or median,
but sample SD needs two. One correct response plus 39 timeouts retains omission
rate 39/40 and error rate 0/1, with SD unavailable. All unavailable reasons and
denominators remain in the saved report and score CSV.

A native export first replays its retained full receiver journal. Reimporting
its summary CSV produces `declared_trial_summary` evidence. Key histories,
onset clocks, frame evidence and original transport replay are absent from that
CSV and are not reconstructed. Neither route establishes physical timing or
hardware qualification. Existing saved reports keep their original recipes.

Per-attempt reports are available. Descriptive task cohorts require separate
frozen membership, explicit person/session mapping and repeat policy; that
connected workflow is still under implementation. Trial counts are never
presented as independent people.

Executed checks and their limits are recorded in
[the implementation contract](../qa/IMPLICIT-IMPORT-COHORT-CONTRACT.md) and
[the integrated checkpoint](../qa/INTEGRATED-CHECKPOINT-20260908.md).
