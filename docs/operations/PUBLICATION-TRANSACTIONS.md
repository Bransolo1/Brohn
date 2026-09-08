# Large artifact publication and participant saves

Status, 8 September 2026: the Windows generic report publisher, including vision
and complete physiology artifacts, now prepares and seals bytes outside SQLite's
writer transaction. Camera assembly, multistream interchange and stream curation
also use staged publication. The parent R process holds native file guards
throughout metadata commit. Acquisition secondary export, direct dataset uploads,
portable design import and legacy migration retain their existing paths; their
writer durations are not covered by this performance result.

## Observed defect and correction

The original isolated experiment called the unchanged artifact promotion helper
inside the general report transaction. An independent R process called the
actual participant event handler while that transaction held `BEGIN IMMEDIATE`.
Connections and a real run were prepared beforehand. No artificial storage delay,
mock hash or modified busy timeout was used.

| Original generated artifact | Writer transaction | Concurrent participant receipt |
| --- | ---: | --- |
| 68,156,855 bytes, original publisher | 1.087 s | 1.267 s, HTTP 200 |
| 1,074,781,175 bytes, original publisher | 13.764 s | 5.604 s, incorrect HTTP 400 |
| 1,073,741,824 bytes, actual staged generic publisher | **0.133 s** | **0.261 s, HTTP 200 during preparation** |

The staged run verified complete artifact SHA/size, native build provenance,
frozen exported JSON, exact participant replay and report/object reopening in ten
checks. It used the actual `brohn_publish_analysis_report()` entry point. Its
valid NDJSON is an original transport fixture, not a claimed model inference.
Timings are local observations, not a general guarantee. Participant calls use the
real app handler without an HTTP network hop.

Evidence:

- [Original contention experiment](../qa/PUBLICATION-CONTENTION-EVIDENCE.json).
- [Actual generic staged publisher](../qa/GENERIC-STAGED-PUBLICATION-EVIDENCE.json).
- [Earlier helper-only experiment](../qa/STAGED-PUBLICATION-EVIDENCE.json), retained
  as historical evidence; it preceded parent-native guards and is not the final
  qualification record.

SQLite WAL permits concurrent readers but only one writer. `BEGIN IMMEDIATE`
reserves that writer before the transaction body. A nested savepoint cannot
release an enclosing writer lock. This follows SQLite's [WAL concurrency
documentation](https://www.sqlite.org/wal.html#concurrency), [transaction
documentation](https://www.sqlite.org/lang_transaction.html) and [busy timeout
documentation](https://www.sqlite.org/c3ref/busy_timeout.html).

### Transient receipt failures

The separately corrected store boundary translates the exact native SQLite
busy/locked messages only around fixed transaction-control DBI statements for an
actual SQLiteConnection. The installed RSQLite exposes no usable native numeric
code for this exception. Arbitrary callback exceptions, even with identical
message text, are not translated.

Delivery returns structured HTTP 503 `workspace_busy`, `Retry-After: 1`, and retry
guidance. It does not acknowledge an unsaved event or disclose native SQL text.
Twelve actual held-lock tests verified retry/replay, malformed JSON still 400,
and unrelated same-text callback errors still 400. Existing 74 store and 56
delivery checks passed. The [classification-only large rerun](../qa/PUBLICATION-BUSY-RETRY-EVIDENCE.json)
retains the observed 32.084-second old publication lock and correct 503 after
5.567 seconds. That variation did not isolate a performance effect; it was prior
to staged publication.

## Implemented publication contract

1. `brohn_prepare_publication(store, job, specifications, timeout_seconds)` refuses
   an enclosing transaction. Each item declares key, kind, exact SHA-256, size,
   media type and contained source path. The private attempt binds workspace ID,
   job, attempt, worker, lease token, nonce and request SHA. One to 1,024 items,
   at most 4 GiB each and 16 GiB total, are accepted by this low-level API;
   scientific artifact manifests retain their narrower existing limits.
2. The owned Python child streams bounded 1 MiB copy blocks to private pending
   files, fsyncs, checks complete expected bytes, and installs an absent final
   hash address with same-volume Windows rename. It never replaces an existing
   address. Matching existing addresses are fully verified. It opens native
   `CreateFileW` handles with read access and **FILE_SHARE_READ only**, hashes
   through those held handles, and writes a bounded exact-owner receipt.
   Before creating any bulk pending file, it waits for a request/nonce-bound
   begin acknowledgement. R records the exact interpreter ownership first;
   even a very early mid-copy crash can then be cleaned without guessing who
   owned a dead PID.
3. While those guards remain held, original `src/publication_guard.c` opens
   compatible handles directly in the parent R process. The `.Call` shim verifies
   exact volume ID, 64-bit file index and byte size; decimal identity strings
   never pass through lossy doubles. It rejects directories and reparse files.
   The helper's exact process creation time, command line, ownership and liveness
   are revalidated after handoff. This rejects a helper death before transfer
   could be established. Parent handles then retain their own protection if the
   helper exits later.
4. `brohn_commit_prepared_objects()` accepts only a registered process-local
   prepared handle inside the final transaction. It verifies current job lease,
   worker, attempt, token, receipt and implementation identities. Parent native
   checks compare held file identity and current path identity. Only object rows
   and audit metadata are inserted. No bulk copy, complete artifact hash, decoder
   or typed row scan runs here.
5. `brohn_publish_analysis_report()` performs typed artifact verification and
   constructs the entire durable result JSON outside the writer lock. Predicted
   immutable descriptors use the existing catalog media type when deduplicating;
   first declaration wins for duplicate new hashes. The final metadata transaction
   demands the same descriptors, registers all objects, writes the report and
   optional AOI proposal, and completes the exact job atomically. A concurrent
   descriptor mismatch rolls back rather than freezing contradictory JSON.
6. `brohn_close_publication()` rejects invocation during an active transaction.
   Parent handles survive until COMMIT or ROLLBACK has returned. They are owned by
   a protected R external pointer with explicit close and finalizer. Close then
   releases the exact owned helper/launcher and native pointers.

Windows sharing behavior is documented by Microsoft for
[CreateFileW](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew).
The read-only filesystem attribute alone is not the protection. Tests first make
the file writable, then attempt same-size write, replacement, deletion and parent
hash-directory rename. The native share modes deny them. A test kills the helper
**after registration inside the real transaction**: R's independent handles still
deny write/replacement, early close fails, and the report commits with exact bytes.
A liveness check just before COMMIT would not establish this invariant.

### Camera, interchange and curation adapters

These adapters stage artifact bytes first. Their existing domain checks then
read the already sealed final paths outside SQL: camera chunks are compared in
original order and the standalone camera manifest is checked; canonical stream
JSONL counts are checked against each frozen stream; curation decision rows must
account for every source row. Bounded read checkpoints poll cancellation and
renew the original lease. Artifact bytes cannot change between these semantic
checks and metadata commit.

Each adapter constructs its complete publication JSON after replacing paths with
predicted immutable descriptors, then stages that small document under a second
parent-owned guard. The final transaction registers both sets and publishes all
related entities plus job completion. Camera publication now retains this full
standalone JSON as well as recording/chunk/frame manifests. Its source decoder
qualification and partial/withdrawn restrictions remain unchanged.

When curation requests immediate analysis, the internal dependent job ID is
allocated before JSON construction. The optional `prepared_id` argument to
`brohn_enqueue_job()` preserves ordinary caller behavior: an exact idempotency
replay returns the existing job, while collisions or changed requests are
rejected. Final curation publication checks the actual queued ID equals its
frozen export. A mismatch rolls back artifacts, dataset, curation and dependent
job writes together. Nine checks include two independent competing R processes;
only one prebuilt ID/export is retained and no dangling linkage is published.

Actual saved journeys passed 63 camera checks, 50 interchange checks and 45
curation checks. The curation journey runs the resulting EEG job and checks the
independent 10/20 Hz and amplitude-squared-over-two oracles. These are functional
and integrity checks, not additional large-file latency measurements.

On non-Windows systems the general publisher explicitly reports
`legacy-transactional-copy` and `native_seal: false`; it keeps its prior complete
checks. No POSIX seal or short-lock qualification is claimed. The direct legacy
`brohn_promote_worker_artifacts()` API is still checked and transactional; callers
must not infer the new timing result applies to that separate entry point.

## Local native build and readiness

Run `Rscript --vanilla scripts/build-publication-guard.R` using the prepared Brohn
library. An optional first argument selects the local compiler executable; the
second selects the build directory. This script neither installs nor downloads
tools. The default workspace-local TinyCC 0.9.27 win64 came from the
[official GNU Savannah distribution](https://download.savannah.gnu.org/releases/tinycc/).
Its original archive SHA-256 is
`34a721949a2583fdff725312da092fa0f5f1f284b702e6f811c6954714faabb2`.
TinyCC's upstream documentation/license remains in its local distribution; no
compiler binaries or R binaries are checked into Brohn's source tree.

The immutable DLL name derives from canonical full build inputs: C source SHA,
R version/architecture/pointer width, R.dll SHA, installed R header inventory,
compiler executable SHA and compiler distribution inventory. Each build has a
separate immutable manifest. Reuse requires exact inputs and DLL SHA. Compilation
runs in a fresh private pending directory; load and all exported symbols must
verify before an absent final filename is promoted. A failed compilation cannot
leave a final named partial DLL. A corrupt or incomplete existing build is never
silently relabelled. The small active manifest pointer is updated only afterward;
interruption of that update produces an actionable readiness failure.

The loader checks source, full build key, runtime ABI, DLL SHA and required
symbols. Scientific jobs retain the C/R/Python source hashes and the complete
native build identity in exported provenance. TinyCC's parser predates the R
headers' C23 enum spelling: the shim uses an int enum with a compile-time width
assertion and the legacy declaration for unused complex types. It never accesses
R internals, numerical array storage or complex values.

`brohn_publication_readiness()` probes the native build and launches a bounded,
standard-library-only Python check with a ten-second deadline and process-tree
cleanup. It requires 64-bit Windows Python 3.10+ in the Python 3 series and returns
the actual version. An existing non-executable file does not pass. Failures
separately identify native rebuild versus `BROHN_PUBLICATION_PYTHON` configuration.
The readiness check does not discover devices or start acquisition.

## Failure, fencing and retained originals

- Preparation renews the original 60-second lease in separate short transactions
  every 15 seconds and polls cancellation while the child performs bulk work.
  Cancelled, expired or superseded attempts cannot enter final publication.
- Two publishers may independently hold compatible guards on identical bytes.
  Closing one does not release the other. They produce one object catalog row.
- Any enclosing transaction failure rolls back all new object rows, report and
  job completion. Fully installed unregistered content-addressed bytes remain
  safe orphans and can be reverified by a later authorized attempt.
- No online sweeping of shared hash-addressed orphans is implemented. An
  unregistered file may belong to another pending commit. Object erasure is a
  separate, unimplemented lifecycle and is not implied by these changes.
- Known Windows venv launcher and actual interpreter identities are tracked
  separately by PID, creation time and exact frozen arguments. Cleanup requires
  both to be proved stopped. Unknown ownership retains the attempt and reports
  failure; it never kills a process based only on its name.
- After proven shutdown, only UUID-named `.object-pending` files in that exact
  contained attempt directory are removed. Whole originals and small request,
  status, receipt and log documents remain. No other attempt or shared object is
  deleted. Real cancellation and a forced crash with a partial copy test this.

## Reproduction and limits

The actual general job suite passed 30 assertions, real nested R/Python vision
passed 30, and event-related EDA with full preserved artifacts passed 65 through
the new route. Forty native guard/fence checks cover cancellation, expired/reclaimed
leases, cross-workspace use, receipt tampering, duplicate publishers, rollback,
helper death before and after registration, early close and exact reopening.
Native build/readiness tests cover ten actual build, corruption and probe cases.

```text
Rscript --vanilla tests/platform-publication-build.R
Rscript --vanilla tests/platform-publication.R
Rscript --vanilla tests/platform-prepared-jobs.R
Rscript --vanilla tests/platform-capture.R
Rscript --vanilla tests/platform-interchange.R
Rscript --vanilla tests/platform-stream-curation.R
Rscript --vanilla tests/platform-publication-report.R 1024 NEW-EVIDENCE.json
```

The GiB experiment is opt-in and requires an absent evidence destination. Its
original fixture and private workspace are removed after success or failure.
Named hardware, psychological interpretations, POSIX file sealing, power-loss
durability and the remaining non-generic publishers are not qualified by it.
