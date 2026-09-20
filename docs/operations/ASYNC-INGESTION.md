# Asynchronous source intake

Status: source-preservation module and shared worker dispatch implemented and
tested. Researcher UI integration is being independently checked. Existing
datasets keep their complete-source contract; pending intake is a separate entity.

## Researcher flow

1. Select a file and explicitly choose its data family, collection origin,
   destination project and optional study. Confirm the displayed filename/size.
2. A separate ingestion card represents the pending operation after a short
   metadata-only handoff. It
   reports queued, preserving source, checking preview, ready, cancelled or needs
   attention. No incomplete dataset is made available to scientific analysis.
3. The real `ingest_source` durable job computes the whole-source hash and prepares
   a bounded preview outside the Shiny process and outside SQLite writer locks.
4. One final transaction publishes the verified original object, complete dataset,
   ingestion receipt and exact job completion. The researcher then uses the
   existing explicit mapping/curation flow. Import does not interpret EEG, gaze,
   questionnaire or other signals automatically.

## Public helpers

- `brohn_queue_ingestion(store, upload, title, modality, origin, study_id = NULL,
  project_id = "default", operation_id)` accepts a completed Shiny upload transfer,
  not an arbitrary pathname supplied by a participant. `upload` identifies its
  temporary server path, original filename, exact byte size and stable server
  upload reference. It returns the new ingestion record, including its job ID.
- `brohn_ingestion(store, id)` and `brohn_ingestions(store, project_id, limit)`
  return pending/history cards independently of the dataset library.
- `brohn_cancel_ingestion(store, id, expected_revision)` cancels the exact durable
  job and updates the pending record. It cannot erase source bytes or cancel an
  unrelated job. `brohn_retry_ingestion(store, id, expected_revision, operation_id)`
  preserves predecessor linkage and frozen reviewed metadata. It requires the
  same continuously held source; a restarted server cannot silently bless a
  pre-hash file that no longer has its original guard.
- `brohn_ingestion_input(store, job)` prepares exact isolated worker inputs.
  `brohn_analyse_ingestion(input, scratch)` hashes and previews the source without
  a catalog connection. `brohn_publish_ingestion(...)` performs staged native
  publication and final atomic metadata commit.

The upload object has exactly `path`, `name`, `size` and `reference`. Its stable
reference identifies a completed server transfer; the operation ID identifies the
researcher's import action. Review fields include title, modality, explicit
origin, project, optional study ID/revision/hash, filename, format, size and upload
reference. Repeating an operation with changed review fields conflicts before any
source file is consumed.

## Fast intake and honest integrity boundaries

The selected source may be 512 MiB, so hashing or copying it on the Shiny callback
would still stall the interface even if SQL contention were removed. Intake must
use a quick same-volume move from the completed server upload into a fresh,
workspace-contained private incoming directory. The user's original local file
is unaffected. Only the server's completed temporary upload is consumed.

The source has not yet been hashed at this point. It must not be advertised as a
verified content address. A native read guard in the parent R process retains its
exact file identity while the job waits. The module-owned guard survives browser
disconnects. The registry is retained by the R process option
`brohn.ingestion.source_guards`, including across module re-source into another
environment. Keys combine workspace and ingestion identities, so the same import
operation ID in a second workspace cannot replace the first original's guard.
A worker takes its own matching native guard and checks the exact
original owner PID, creation identity and request binding after handoff. Only then
does it compute the first full-source hash. This guards the interval before a
cryptographic expected hash exists; size, modification time, read-only attributes
or a random private filename alone do not establish immutability.

If R exits before that verified handoff, the pending card becomes needs attention
and the private incoming bytes remain available. It must not automatically bless
possibly modified bytes after restart. A completed worker capture has a full
expected hash, so subsequent copy/publication can reject changes independently.
If the original owner exits after the worker handoff, the worker's own native
guard allows it to finish honestly; owner exit alone does not prove that this
already running attempt failed.

Cross-volume intake needs its own asynchronous transfer helper. The first bounded
implementation must reject it with an actionable explanation rather than silently
performing a blocking large copy. The default prepared Windows upload/workspace
locations are on the same volume; this is an explicit initial limit, not a claim
that every workspace layout is supported.

The metadata helper has a ten-second startup deadline and never reads the source
to compute a hash. It reports a Windows volume/file identity and exact byte count,
holds its read seal while R acquires a matching parent handle, then releases only
after an exact request acknowledgement. Cleanup checks both the owned launcher
and its exact remembered interpreter identity. No bulk copy occurs on this path.

## Durable records and source meaning

An ingestion record keeps its stable ID, reviewed metadata/hash, upload reference,
file size/format, project and optional frozen study revision, source staging
identity, original parent-process identity, job and retry predecessor IDs,
completion/error reason, and final dataset/source object IDs when available.
The pending input must never infer participants, sessions, conditions or shared
clocks from filenames or device labels. Collection origin remains the researcher's
explicit declaration and is frozen into the final dataset.

Zero and missing text remain distinct. CSV/TSV preview follows the existing
character-preserving contract: at most 20 data rows, unique nonempty column names,
and no automatic replacement of literal `NA`, `0`, false or empty strings.
Native binary formats are preserved whole and receive no guessed channels or
units. Header inspection is a separately named operation after intake.

## Publication, cancellation and integration seams

The actual job uses the established job lease and fencing token, not a fabricated
analysis task to represent acquisition-manager ownership. The source, preview,
dataset body and frozen final JSON are checked before metadata publication.
Parent-owned native file guards remain held across COMMIT. Final source object,
dataset, ingestion record and successful job receipt must commit together.

Cancellation, stale attempts, changed reviewed metadata, conflicting operation
IDs, failed previews or missing original guards leave no partial dataset. Source
and small diagnostics stay available for inspection/retry. No online orphan sweep
or erasure claim is introduced. Failed work cannot turn a sample declaration into
physical-device evidence.

An initial capture failure is different from a worker failure. The pending record
reports whether private incoming bytes actually exist. If the completed server
upload could not be moved, there is no verified incoming source or queued job;
the interface asks the researcher to select their original local file again.
It never claims to have preserved a source merely because an ingestion ID exists.

Cancelled and failed intake deliberately retains its original native guard for
same-process explicit retry. `brohn_reap_ingestion_guards(store)` releases only a
committed `ready` ingestion whose exact job is `succeeded`; normal R process exit
also closes its OS handles. It never deletes incoming files. The incoming original
and the final content-addressed copy can both consume disk space until an explicit
retention/reconciliation workflow is implemented. Do not describe this as an
automatic purge or deletion policy.

The shared loader sources `platform-ingestion.R` after publication, library and
jobs. The exact `ingest_source` branches call `brohn_ingestion_input`,
`brohn_analyse_ingestion`, then `brohn_publish_ingestion`. The actual scientific
child includes the module and snapshot helper in its frozen implementation
identity; it performs preservation only, with no signal interpretation.

Progress milestones `ingestion-hashing.json`, `ingestion-preview.json` and
`ingestion-verified.json` are small, request-bound, absent-destination atomic
files in that worker's scratch directory. They describe completed stage
transitions, not a durable dataset or promised percentage estimate. Final SQL
publication remains the only successful receipt.

The UI must freeze or explicitly reconfirm the upload destination after a long
transfer; it cannot silently take a different study or origin from whichever
page happens to be open when uploading finishes. Acquisition-manager import
remains a separate ownership model and is not routed through this API implicitly.

## Scoped evidence

All fixtures are original generated data in isolated workspaces.

- `tests/platform-ingestion.R`: thirty-eight checks for source capture, whole-original byte equality,
  zero/empty/literal-NA preview, operation/retry idempotency, cancellation, real
  child processing, reopen, native mutation denial, loader/GC and cross-workspace
  registry retention, pre-handoff owner death, stale/reclaimed fences, changed
  origin rejection, initial capture failure and atomic publication rollback.
- `tests/platform-ingestion-handoff.R`: six actual process checks on a 512 MiB
  original. The original owner exits during worker hashing, the independent
  worker's native guard still denies writes, and the full hash completes. A
  same-size change after that worker closes is rejected during publication.
- `tests/platform-ingestion-integration.R`: eighteen checks through the real
  `brohn_process_job`/shared child. A source becomes a complete dataset, receives
  explicit mapping, then reproduces the existing independently derived gaze
  contrast of 10.833333333333334 percentage points. Frozen study revision,
  full-source download/reopen, real preview failure and explicit retry are checked.
- `tests/platform-ingestion-large.R`: original prototype mode is retained;
  `shared` mode runs the actual shared dispatcher. An independent process sends
  a real participant application-handler receipt while original bytes are being
  copied; full source size/hash, bounded preview and final writer lock are checked.

The initial prototype 512 MiB run passed ten checks: queue 3.432 seconds, final
metadata transaction 0.237 seconds, concurrent participant receipt 0.271 seconds
with HTTP 200. Its exact identity is retained in
`docs/qa/ASYNC-INGESTION-EVIDENCE.json`; it predates process-global registry
hardening, so later evidence must not be represented as that same build. Timings
are local measurements, not guarantees. The participant check invokes the actual
HTTP application handler in another process, not a network round trip. Original
binary transport fixtures are not qualification of EDF scientific interpretation.

The current shared-dispatch 512 MiB run also passed ten checks: queue 3.367
seconds, final source/object/dataset/ingestion/job transaction 0.250 seconds, and
concurrent participant receipt 0.336 seconds with HTTP 200 during copying.
`docs/qa/ASYNC-INGESTION-SHARED-EVIDENCE.json` retains the actual complete worker
implementation identity. Run it with:

```text
Rscript --vanilla tests/platform-ingestion-large.R 512 <absent-evidence-path> shared
```

The file-generation and independent oracle hash occur before the measured
researcher intake callback. This evidence therefore distinguishes completed
upload intake from the browser-to-server transfer itself. It verifies that the
final writer transaction excludes full-source copy/hash and remains separate
from participant receipt writes; it does not guarantee every disk or host will
have these timings.

The cross-volume route is explicitly rejected by the implementation, but no
second physical Windows volume was available for an actual cross-volume test.
Browser transfer/navigation behaviour has its own UI QA scope.

20 September readiness correction: receipt availability is now rechecked after
process-tree observation. A receipt written during a slow observation no longer
fails the subsequent ten-second waiting check. The original nonce, request hash,
process ancestry and native-file identity checks still run before acceptance.
The actual-process ingestion regression passes40 checks; a separate deterministic
race run passes two checks with only the polling clock advanced and a real sealed
helper. Final neural import-to-export acceptance also passed after this correction.
The measured initial metadata queue in that regression was9.290 seconds; this
is a local observation, not a launch-time guarantee.
