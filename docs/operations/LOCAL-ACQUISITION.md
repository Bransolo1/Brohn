# Local LSL acquisition: explicit collection and recoverable evidence

Status: original Brohn adapter `brohn-lsl/1.0`, implemented and exercised on
Windows with Python 3.12.10, pylsl 1.18.2 and liblsl 1.17.7 (API version 117).
This is a local transport adapter, not a qualification of a named eye tracker,
EEG/EDA device, physiological unit, stimulus-onset accuracy or recording throughput.
The [prepared environment](../preparation/ACQUISITION-TOOLING.md) remains optional.

The adapter is [lsl_recorder.py](../../scripts/acquisition/lsl_recorder.py).
It opens only researcher-selected LSL streams. It does not start a camera, vendor
device driver, hardware acquisition application or paid service. Discovery and
recording run as separate, hidden local processes; closing a browser does not
stop the recorder. R integration must retain each process's ownership explicitly.

## Researcher flow and R integration contract

1. Choose the same LSL session as the source application. Explicitly request
   metadata discovery; discovery never calls `open_stream` or `pull_*`. Review
   source UID, source ID, name, type, channel layout, declared units, source origin
   and transport support. A default session is a valid explicit choice.
2. Freeze the selected UID **and** source ID **and** metadata SHA-256. Supply
   participant/session IDs yourself, collection origin and unit provenance.
   Optional study/design/run/deployment references are explicit binding evidence.
   Source IDs, hostnames and matching participant labels are never person linkage.
3. Start one independent process for 1-16 selected streams. Display atomic
   `status.json`: completion status, counts, update time and unqualified quality
   observations. Numeric channels must state a unit; `unknown` is an explicit
   unresolved declaration. It cannot license downstream physiological analysis.
4. Stop writes one exact request-bound control file in that recording's own
   directory. Let the recorder flush and close before processing. Cancel closes
   the handles too, but remains a cancelled recording, not completed observations.
5. After process exit, inspect all committed hashes and counts, preserve the
   canonical recording as the original parent container, and explicitly export
   an interchange bundle. The existing importer then performs ordinary curation.
   No automatic cross-stream merge, clock correction or scientific scoring occurs.

The R controller should use `processx` with `windows_hide_window=TRUE`, a dedicated
recording directory under the workspace, separate stdout/stderr logs and a frozen
request entity. **Do not automatically restart a recording after child exit.** A
new recording creates a new session boundary and must be explicitly started.
Use `status.json`'s `request_sha256` for controls; R and Python canonical JSON
encoders are separate contracts. PID liveness and status timestamps describe the
recorder, not device signal validity. Retry a transient Windows sharing violation
when reading atomic status, retaining the prior snapshot until the next poll.

### CLI

From the repository root, with the pinned acquisition Python:

```powershell
$acquisitionPython = '../../work/tooling/acquisition-venv/Scripts/python.exe'
& $acquisitionPython scripts/acquisition/lsl_recorder.py discover --request discovery.json --output NEW-discovery-result.json
& $acquisitionPython scripts/acquisition/lsl_recorder.py record --request recording.json --output NEW-recording-receipt.json
& $acquisitionPython scripts/acquisition/lsl_recorder.py inspect --recording ABSOLUTE-RECORDING-DIRECTORY --output NEW-inspection.json
& $acquisitionPython scripts/acquisition/lsl_recorder.py export-bundle --recording ABSOLUTE-RECORDING-DIRECTORY --bundle-output NEW-bundle.json --output NEW-export-receipt.json
```

Every CLI receipt path must be absent. Errors return exit code 2 and structured
`error.type` / `error.message`. An interrupted process may have no receipt: inspect
its committed recording. `export-bundle --allow-incomplete` requires an explicit
decision to export a verified subset; it never relabels that subset as complete.
Export is published atomically to an absent destination outside the recording.

Discovery request:

```json
{
  "schema": "brohn-lsl-discovery-request/1.0",
  "lsl_session": "default",
  "source_ids": ["exact-source-id-from-source-application"],
  "timeout_s": 2
}
```

For a researcher-requested local inventory, omit `source_ids` and set
`allow_machine_discovery:true`. Discovery returns `brohn-lsl-discovery/1.0`,
`metadata_only:true`, `streams[]` and `engine`. Each stream includes UID/source
identity, full original XML and its hash, nominal rate, channel format/layout,
source-origin declaration, `supported` and actionable `support_reason`.
No available stream is automatically selected.

Recording request (the UID and metadata hash must come from actual discovery):

```json
{
  "schema": "brohn-lsl-record-request/1.0",
  "recording_id": "recording-unique-id",
  "output_root": "C:/absolute/existing/workspace/acquisitions",
  "lsl_session": "default",
  "origin": "pilot",
  "origin_statement": "Pilot recording for the selected study protocol.",
  "identity": {"participant_id": "P01", "session_id": "P01-S01"},
  "references": {"study_id": "study-id", "design_hash": "actual-frozen-design-hash", "run_id": "optional-explicit-run-id"},
  "streams": [{
    "id": "eda-source",
    "uid": "actual-discovered-outlet-uid",
    "source_id": "actual-discovered-source-id",
    "metadata_sha256": "actual-discovered-64-character-sha256",
    "clock_id": "eda-source-clock",
    "clock_kind": "monotonic",
    "kind": "signal",
    "unit_provenance": "Explicit device export declaration reviewed for this configuration.",
    "gap_threshold_s": 0.2,
    "channels": [{"id": "eda", "label": "EDA", "type": "EDA", "unit": "uS", "value_type": "float32"}]
  }],
  "limits": {"max_duration_s": 600, "max_samples": 100000, "max_bytes": 67108864, "chunk_samples": 256, "inlet_buffer": 5}
}
```

`identity` requires participant and session; optional condition/exposure may be
supplied when valid for the whole recording. `references` optionally accepts
study_id, design_hash, run_id and deployment_id. No reference changes sample
identity or clock mapping. Keep continuous recordings' changing condition and
exposure assignments in separately measured marker/event evidence.

Streams declare `kind:signal|markers|unclassified` and the **entire original**
channel layout with exact transport value types. Calibration is never applied.
Declare `clock_kind:monotonic|unix|device|unspecified_epoch` for source timestamps;
the LSL wire encoding is float64 seconds. Transport alone does not establish
which epoch a particular source actually used.
Source-origin declarations remain distinct evidence. A source explicitly labelled
sample/synthetic, pilot or live cannot be recorded under a conflicting collection
origin. An absent or nonstandard source-origin declaration is preserved as such.

After start, atomically write this to `RECORDING-DIRECTORY/control.json`:

```json
{"recording_id":"recording-unique-id","request_sha256":"exact-status-request-sha256","operation":"stop"}
```

`operation` accepts `stop` or `cancel`. A mismatching recording/hash is rejected
and produces an incomplete recording; no other recording is touched. The control
file is limited to 4 KiB and must be a regular file in the exact recording root.
SIGINT/SIGTERM are cancellation where the OS delivers them normally. A Windows
hard process kill is an interrupted recording, covered separately by recovery.

## Durable recording contract

The new, absent `output_root/recording_id` contains:

| Member | Meaning |
| --- | --- |
| `request.json` | Frozen explicit design/identity/limits/origin/selection request |
| `streams.json` | Full source XML, observed metadata and separate researcher declarations; actual engine/code identity |
| `chunks/NNNNNN-SHA256.jsonl` | Original typed sample chunks, fsynced before journal commitment |
| `journal.jsonl` | Fsynced sequence and SHA-256 chain of open, chunk, clock, stop, error and close observations |
| `status.json` | Small atomic polling snapshot; advisory, not completion authority |
| `manifest.json` | Final immutable inventory only after orderly handle closure |

Each source has its own receipt sequence, clock ID, reset segment and chunk
inventory. Each row stores original source timestamp as a roundtrip decimal
string plus little-endian IEEE-754 bytes, original typed channel values, explicit
nonfinite states, and raw IEEE bytes for floating channels. Int64 is a decimal
string at JSON boundaries, never a double. Zero, negative zero and empty marker
strings are retained. Nonfinite floats have JSON null plus `nan`,
`positive_infinity` or `negative_infinity`; no null becomes zero.

`receive_before_s` and `receive_after_s` bracket the actual `pull_chunk` call in
the recorder's LSL clock. They are chunk-receipt observations, not per-sample
network-arrival or hardware capture timestamps. The source timestamps are passed
through unchanged using `proc_none`, with `recover=False`. The adapter records
available `time_correction` offsets, observation time and query start, with
`applied:false`. pylsl's public method does not expose the extended uncertainty/
remote-time pair here, so those fields remain null. A query timeout is explicitly
logged. No nanosecond resolution, UTC epoch, synchronization or accuracy claim is
inferred. [pylsl inlet API](https://github.com/labstreaminglayer/pylsl/blob/v1.18.2/src/pylsl/inlet.py),
[LSL clock guidance](https://labstreaminglayer.readthedocs.io/info/time_synchronization.html).

Timestamp reversals and reported clock resets create new segments. Equal clocks
are retained and labelled; marker coincidence can be valid. Gap flags require a
declared threshold and retain the actual gap, without interpolation. Sequence
numbers count receipts; they cannot detect every upstream drop without a source
packet counter. Native buffer overflow is not silently presented as measurable
zero loss. Every resulting physiological analysis still requires its mapping,
validity masks and method recipe.

Manual stop drains only immediately available samples, bounded at 4096 samples
and 0.25 seconds plus the current chunk's synchronous disk commit. Samples may
arrive after the control receipt during this tail; the journal states that fact.
Each pulled chunk has already been written and fsynced, so there is no separate
application buffer to discard. Cancel and configured sample/duration limits stop
reading directly. Before each `close_stream`, the observed remaining queue count
is logged. Closing discards any remaining native/in-flight tail, as documented by
[the upstream inlet API](https://labstreaminglayer.readthedocs.io/projects/liblsl/ref/inlet.html).

`completion_status` is `completed`, `cancelled`, `incomplete`, or inspection-only
`interrupted`; the final manifest's `complete` is true only for completed orderly
recordings. Completion means that the bounded collection interval was closed and
its received samples committed. It is **separate from signal quality**: even a
zero-sample interval may close normally, while `signal_quality:not_qualified`,
`quality_qualified:false` and counts remain explicit. An acquisition UI must show
empty intervals and configured-limit stop reasons, rather than call them valid
research data.

The checked inspection now retains `quality_qualified`, `signal_quality` and
`quality_evidence:verified_final_manifest` from that final manifest. Those fields
are stored atomically with the final acquisition receipt. History shows this
durable quality status even when optional live telemetry is unreadable. A crash
without a final manifest yields null quality fields and
`quality_evidence:missing_final_manifest`; an older manifest without explicit
quality fields yields `missing_quality_fields`. Neither case means qualified or
unqualified data by inference. Older stored inspection records are not rewritten;
the UI says that final quality evidence is unavailable in that receipt.

## Bounds, recovery and original-container preservation

New chunk files use bounded sequence names such as `chunks/000001.jsonl`. The
full SHA-256, byte count and row/sequence bounds remain in both the chained
journal and final manifest; inspection still rejects changed or missing bytes.
Existing recordings with hash-bearing chunk filenames remain readable.

The Windows local profile preflights destination lengths before discovery and
recording, including room for archive/review scratch and atomic-write suffixes.
The standalone recorder independently checks its full owned layout before
subscribing. Unsupported destinations require a shorter workspace path; this
does not claim universal extended-path support across Python, R and ZIP readers.
The bounds follow the ordinary Windows API path and directory limits; enabling
long paths for one executable does not enable every consumer.
[Microsoft path limits](https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation)

Request JSON is limited to 2 MiB. Discovery is at most 64 descriptors and recording
at most 16 streams / 128 channels per stream, 2 million received samples and
20 million potential channel values. Chunk pulls are 1-512 samples. Duration is
0.1 seconds to 24 hours. `max_bytes` limits committed sample-chunk bytes, 64 KiB to
512 MiB; journal and manifest overhead are separately bounded (journal 64 MiB,
JSON manifests/receipts 16 MiB). There is a 100,000-chunk safety cap. Exceeding a
serialization/disk bound produces incomplete/interrupted evidence, never a
successful truncated stream. Reserve additional disk space for manifests and any
explicit secondary export.

`inlet_buffer` is 1-60 seconds for regularly sampled streams or multiples of
100 samples for irregular streams, with an additional declared four-million-value
gate. Nominal rates must be finite and at most 100 kHz. LSL receives source strings
before Brohn can check their 32 KiB/channel text limit; native memory limits and
high-rate/drop behavior still require device/configuration-specific qualification.
This local trusted-source adapter is not an arbitrary-network ingestion boundary.

Each sample file is immutable after publication, and the journal commits only
after its file flush. Crash before journal commitment leaves an orphan chunk,
which inspection counts but never trusts. Crash after commitment preserves a
verifiable prefix. A trailing incomplete journal line is reported and ignored;
corruption of a full committed record is rejected. Missing/tampered chunks,
sequence/count/hash mismatch, traversal and forged completion are rejected. A
missing final manifest remains interrupted, even if a close record was written.
There is no in-place resume, rewriting history, or automatic source replacement.
Full inspection/export is intended after the owned recorder exits; while active,
poll the bounded status snapshot instead.

The hashes detect mismatch; they are not signatures/authentication. The R catalog
must pin the original request, manifest, journal and canonical chunks together.
Keep all verified raw members as the parent recording container before promoting
the secondary bundle. The bundle's metadata includes recording ID, frozen request
and final-manifest hashes, journal tip, completion status, original chunk inventory,
references and source-origin evidence. It intentionally does not repeat all raw
receive/IEEE/nonfinite-state evidence; **retaining only the bundle loses evidence**.

`export-bundle` streams a `brohn-stream-bundle/1.0` file up to 64 MiB. The current
interchange worker accepts it using `format:"brohn_stream_bundle"`, the exact
export SHA and `metadata.clock_policy:"preserve_only"`. It produces separate
curatable datasets, preserving original typed values and explicit identities.
Larger canonical recordings remain valid, but need the separately named future
streaming-import route rather than an silently truncated bundle.

## Transport qualification and checks

Tests use only original synthetic outlets, random source IDs and an isolated
LSL session. No broad discovery, physical device or remote address is used.
Machine scope alone missed additional local outlets in this Windows environment;
the documented `KnownPeers={127.0.0.1}` fallback resolves those local sources.
All tests continue to resolve only their exact original source IDs. This is a
local-only profile; it does not certify a remote-LSL network deployment.
[Official configuration guidance](https://labstreaminglayer.readthedocs.io/info/lslapicfg.html).

Installed pylsl 1.18.2 explicitly disables int64 transport on Windows and 32-bit
platforms. Discovery reports unsupported status, and recording rejects that
format before subscription. Exact int64 disk serialization has independent
arithmetic tests; it is not presented as Windows live-int64 evidence.
[Pinned upstream type bindings](https://github.com/labstreaminglayer/pylsl/blob/v1.18.2/src/pylsl/lib/__init__.py).

Run `tests/acquisition/lsl_recorder.py` with the acquisition Python. **17 scoped
tests passed** on the pinned Windows environment. Evidence
includes real separate-process discovery without subscription; float64 zeros,
nonfinite values, gaps, coincident clocks and reversals; float32 cancellation;
simultaneous int32/string markers through the existing interchange importer;
unapplied correction observations; sample/duration bounds; frozen UID/metadata
rejection; exact control binding; forced-process-kill recovery; torn/orphan data;
independent int64 and size arithmetic; missing/corrupt chunks; forged completion;
and destination/identity/path rejection. Device calibration, sustained throughput,
native buffer overflow, physical disconnect timing and stimulus-onset alignment
remain separate acceptance evidence.

## R workspace and independent manager

`R/platform-acquisition.R` stores metadata discovery and recording requests in
immutable, revisioned catalog entities. These requests have their own manager;
they do not occupy the scientific analysis worker. The integrated launcher starts
`Rscript --vanilla scripts/run-acquisition.R --root WORKSPACE` as its third child.
Shiny browser disconnection does not terminate that process or its recording.
There is one concurrent recording per workspace in this first local profile.

The researcher flow is Collect > Find local sources > select exact discovered
UIDs > review every channel unit, source clock, participant/session and collection
origin > Start reviewed recording. A missing participant or session is rejected;
source IDs never become people. Native synthetic origin cannot become live.
The request pins the current study revision and design, plus any explicitly
selected participant-run reference. A stale study/discovery form must be reviewed
again. Controls require the current study's Collect page and matching hidden form
identity, so delayed browser input cannot act on a subsequently selected study.

Public integration APIs:

- `brohn_queue_lsl_discovery()` and `brohn_lsl_discoveries()` persist bounded
  metadata-only results with the source script and result hashes.
- `brohn_retry_lsl_discovery()` requires an explicit interrupted/failed request
  revision and creates a separate request with the same source scope and retry
  lineage. It pins the current study and recorder versions; it never replaces
  the original discovery or runs automatically.
- `brohn_lsl_selection()` freezes the exact reviewed source/units/clock mapping;
  `brohn_queue_acquisition()` requires explicit review and the study revision.
- `brohn_acquisition()` returns the immutable entity plus a separate
  `live_snapshot` from the small atomic status file. Counts do not create catalog
  revisions on each poll. `brohn_acquisitions()` lists history.
- `brohn_stop_acquisition()` stores a revision-checked, request-bound stop/cancel.
  The manager forwards that exact request's control; no arbitrary PID is killed.
- `brohn_acquisition_download()` resolves the verified immutable original ZIP.
  The UI uses a writable, hash-checked transfer copy for Windows HTTP download.
- `brohn_review_acquisition()` explicitly accepts a completed recording, or an
  incomplete subset with separate confirmation, for secondary dataset preparation.
  It queues the existing multistream normalization job with `preserve_only`
  clocks and the original archive as parent provenance. It never auto-aligns clocks.

After the writer exits, the manager checks the request, source code, committed
journal and completion state. It archives the entire canonical recording, hashes
every file, extracts a verification copy, checks all members, and rechecks the
original files before publication. The immutable ZIP retains raw timestamps,
receipt brackets, channel bytes, nonfinite states, controls, status and orphan
evidence as well as the valid committed prefix. Keeping a secondary stream bundle
does not replace this original. Archives are private local data containing the
researcher's explicit identity labels. The short temporary extraction directory
avoids Windows path-length failures; cleanup is restricted to that verified fresh
temporary directory. Larger sources that exceed the secondary bundle bound stay
preserved and need a future streaming importer; they are not partially imported.

`brohn_acquisition_ready(root, workspace_id)` requires the service's exact root,
workspace identity and a live process matching creation time, executable, working
directory and complete command. This is liveness/ownership evidence, not a
signal-quality check or a hung-process watchdog. A singleton catalog fence prevents
two live managers. The UI polls status every second, while discovery results only
invalidate their form when the durable result changes; typing units must survive
status refreshes.

`brohn_acquisition_service_status()` additionally exposes distinct ready, stopped,
missing, unavailable, invalid, foreign-workspace and unverified-process states.
Only the atomic `service.json` read retries transient open failures: ten attempts
with 20ms between them. Captured I/O warnings remain in the final unavailable
diagnostic instead of spilling a warning for each Windows sharing conflict.
Malformed JSON, excessive size and invalid ownership fields are rejected without
retry; they do not become missing files or proof that a process exited. Stop
authorization uses one verified status snapshot. Scientific artifacts and raw
recording reads retain their existing validation paths.

`tests/platform-acquisition-service.R` passes 22 checks, including actual exclusive
Windows file-sharing locks against a fresh test-owned service file, short-lock
recovery, bounded persistent refusal, corruption/schema/size rejection, original
byte preservation, exact stop binding and duplicate-manager refusal while the
state file is unreadable. The original Python fixture opens an existing file with
zero sharing flags and closes its own handle; it changes no system policy or
permissions. [Microsoft's documented sharing behavior](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew).

`brohn_request_acquisition_manager_stop(root, expected_pid)` atomically creates
`acquisitions/stop-MANAGER-ID.json` only after verifying the runtime-owned manager.
The control binds manager/workspace/creation time; creation times use the same
1ms comparison tolerance as process verification because JSON epoch doubles can
move one ULP, while manager/workspace identities must match exactly.
`brohn_stop_acquisition_manager()` sends exact recording stop intent and allows
up to 15 seconds to drain and preserve before terminating only its own remaining
process children. The runtime provides a 20-second outer bound. A deadline,
forced kill or power loss leaves interrupted evidence for the next manager; it
does not invent successful completion. The catalog is closed after this cleanup.

Unexpected manager exit is restarted by the supervisor with its existing bounded
backoff. A new manager checks the old writer identity before doing anything: a
known dead writer is inspected and preserved, a known alive writer is tracked,
and an uncertain launch/process identity becomes `attention_required` and blocks
another recording. The narrow crash gap between spawn intent and persisted child
identity deliberately requires local ownership review; there is no automatic
second writer. Compatible externally started managers remain externally owned:
the integrated launcher neither adopts nor stops them. There is no in-place
recording resume, physical-device reconnection guarantee, remote acquisition
service or automatic restarting of data collection.

`tests/platform-acquisition.R` currently passes **43 scoped checks**, including
actual independent-manager collection, exact-source discovery, source origin and
revision gates, complete original ZIP verification, explicit secondary import,
duplicate-manager refusal, forced-kill recovery, interrupted-subset consent,
restart byte identity and stale Collect-form rejection. These supplement the
Python transport checks; they do not qualify any named physical device.

`tests/platform-runtime.R` passes **74 actual process checks** across the three
services. It restarts a killed analysis worker and completes a saved scientific
job, restarts killed participant/acquisition services, preserves a real recording
after manager crash, exercises retry backoff and separate generation logs, and
proves that compatible external participant and acquisition managers are neither
adopted nor killed. A real Shiny launcher shutdown while receiving an original
synthetic LSL stream saves the completed original and stops all owned children;
restarting the workspace retains that byte identity without starting collection.
Tests use isolated temporary workspaces and dynamically selected loopback ports.
This is a bounded small-recording shutdown proof, not a large-disk, power-loss or
physical-device timing qualification. A metadata discovery interrupted while its
manager is killed is reconciled at the next manager startup. Running discovery
records include a unique execution ID, workspace/manager process, start time,
request path/hash and receipt path before the child starts. Immutable service
history must prove that the previous same-workspace manager is absent before the
request becomes `interrupted`; conflicting or unverifiable ownership becomes
`attention_required`, with no claim that a foreign process exited. The request,
prior revisions and source files remain intact. The UI offers **Retry these
sources** for a verified interrupted/failed request or the existing **Find local
sources** action to review a new scope. No recovery step rescans, pulls signals,
creates a participant recording, or promotes a partial discovery receipt.

`tests/platform-acquisition-recovery.R` passes **22 scoped checks** and exercises real exact-source discovery
against an original loopback outlet, kills its isolated manager and child during
the request, and verifies restart, preserved source bytes/history, no automatic
rescan, explicit retry with lineage, completed-result integrity, and safe legacy
or conflicting-workspace handling. It uses no physical hardware or broad scan.
