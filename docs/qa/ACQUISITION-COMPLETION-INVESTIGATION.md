# Acquisition completion investigation

8 September 2026. Initial read-only investigation, followed by the bounded
corrections described below. The earlier integrated operations failure remains
unattributed because its temporary workspace was removed and the failing log
contains no acquisition state. A passing rerun does not resolve that uncertainty.

## Findings and retained evidence

The [new isolated probe](../../tests/platform-acquisition-completion.R) completed
**58 checks** using an original synthetic, uniquely scoped local LSL outlet and
its own manager/workspace. Eight ordinary explicit stop/archive cycles retained
29, 27, 16, 33, 29, 31, 33 and 39 samples. Every observed revision containing an
original archive also contained completed inspection evidence. Archive manifest
hashes matched the stored inspection receipts and independently recorded both
`complete:true` and `quality_qualified:false` / `signal_quality:not_qualified`.

Retained evidence is under
`work/test-runs/acq-9548769720ac` relative to the outer `make` workspace: complete
workspace, original recording archives, extracted manifests, per-poll observations,
test-owned manager/outlet logs and `evidence.json`. No real-device data was used.

A Windows helper then opened only the final test recording's `status.json` with
an actual exclusive sharing lock. While held:

- `brohn_acquisition()` returned the same stored body and revision but no
  `live_snapshot`.
- The exact earlier combined completion/quality assertion evaluated to false.
- The immutable original remained downloadable with the same SHA-256; its
  manifest still explicitly said complete and not qualified.
- Releasing the lock restored the assertion without any catalog write.

This is a deterministic counterexample to the assertion's assumption that
ephemeral telemetry must be readable after preservation. It is **not evidence
that a sharing lock caused the earlier uninstrumented failure**. No unforced
failure of the target assertion was reproduced in these eight cycles.

## Why the distinction matters

In [platform-acquisition.R](../../R/platform-acquisition.R), the manager first
verifies the closed journal/manifest and original archive. It then writes
`original`, `original_inventory`, `inspection`, `completion_status` and terminal
`status` together in the same entity revision through `.brohn_acq_update()`.
An object catalog registration preceding that revision does not expose a partial
acquisition body.

`brohn_acquisition()` separately reads the mutable small `status.json` using
`.brohn_acq_read()`. That helper returns NULL on any read error. This optional
`live_snapshot` is not the final receipt. The old test's final conjunct,
`identical(record$live_snapshot$quality_qualified, FALSE)`, therefore tests live
file availability as well as scientific qualification.

The Python final manifest already records an explicit quality policy.
`inspect_recording()` verifies that manifest against the committed journal but
does not currently return the quality fields. Consequently the stored inspection
has completion evidence but no direct terminal quality field, despite that field
remaining available in the hash-verified original archive. The current history
UI also places its quality-review copy in the optional live-snapshot paragraph.

Recommended narrow correction: return the actual checked manifest quality
fields in inspection and preserve them through the existing final entity update.
When a crash leaves no final manifest, report that final quality evidence is
unavailable; do not convert NULL to false. Show quality-review status independently
of live sample telemetry. Test completion from the stored atomic receipt, and
quality from the explicit durable field or verified archived manifest. Keep an
independent test for unavailable telemetry so the distinction remains covered.

The manager's retained log contains five optimistic-concurrency retries during
rapid stop commands (`This record changed since it was opened`). The resulting
requests finished correctly; this probe did not identify those retries as a
completion defect.

## Separate reproduced Windows path limit

The first probe used a longer evidence-directory prefix. The original writer
failed its first chunk write at a **266-character Windows path**, with
`FileNotFoundError`; the parent recording and chunks directories already existed.
The recorder wrote an honest incomplete manifest with zero committed samples and
`recorder_error`, and the manager preserved that original. Shortening only the
test directory let collection proceed.

That failed run is retained under
`work/test-runs/brohn-acquisition-completion-a4dc203814e1`, including the actual
writer error receipt, journal, manifest, original ZIP and logs. This is a separate
path-handling defect, not a reproduction of the earlier target assertion: it
failed before receiving ten samples. A bounded follow-up should either support
long paths consistently across writer/inspection/archive APIs or reject an
unsupported destination before collection with actionable copy. Do not discover
the limit only after subscribing to the selected source.

## Scope

No product files, shared runtime, active ports or scientific worker source hashes
were changed during the initial probe. Only original loopback streams and test-owned
processes were started. Cleanup stopped those processes; diagnostics and source
bytes were deliberately retained. This does not qualify named physical devices,
real-world transport loss, signal validity or inter-device synchronization.

## Implemented correction and fresh qualification

The scoped follow-up changes only the acquisition recorder, domain path preflight,
acquisition history copy, acquisition tests and this documentation:

- Checked inspection returns the final manifest's explicit qualification fields
  and their evidence state. Unsupported qualification claims are rejected.
  Missing manifests/legacy quality fields stay null with explicit reasons.
- Existing atomic finalization stores those inspection fields together with the
  original and completion receipt. The assertion and history quality copy use
  this evidence independently of live telemetry. Old catalog rows are unchanged.
- New owned chunks use six-digit sequence filenames. SHA-256 remains in the
  journal and manifest, and full byte verification remains required. Windows path
  preflight checks recording and archive/review paths before collection; an
  unsupported destination fails with a shorter-workspace instruction.

The corrected retained probe passed **75 checks** at
`work/test-runs/brohn-acquisition-completion-55f4a2c28cf`, deliberately using the
same-length directory prefix that failed previously. Eight real recordings
received 17, 16, 29, 15, 29, 16, 25 and 13 samples and were archived. Every cycle's
old hash-bearing filename would exceed 260 characters, while its bounded filename
worked and its checksums were verified. With an actual status-file sharing lock,
the durable completion/quality assertion stayed true, and the legacy
telemetry-dependent assertion remained false as expected. This is a real path
and telemetry regression, not a mocked filesystem test.

The Python recorder suite passed **21 tests**, including actual loopback
collection/crash/cancellation, unsupported destination rejection before
subscription, missing/forged qualification fields, and changed-byte detection
under the shorter filenames. A separate actual inspection of an unchanged
pre-fix 39-sample recording with the original hash-bearing filenames also
succeeded; its receipt is `legacy-inspection.json` in the corrected evidence
directory. The earlier failed source and all original evidence remain intact.
The complete R acquisition lifecycle suite passed **48 checks**, including
stop/archive/download/review, manager crash/recovery, null final quality after a
hard crash, explicit history copy, stale controls and UTF-16 path accounting.

Qualified product SHA-256 for this follow-up:

| File | SHA-256 |
| --- | --- |
| `R/platform-acquisition.R` | `8e9b2b2d2e79716ecb4fab5c5d498836b03fc8ff22729419a2d97e550e7864b9` |
| `R/platform-acquisition-views.R` | `74f48b564e532aeee053186f36dfb64fce28724bb49230d84fe37049385a8941` |
| `scripts/acquisition/lsl_recorder.py` | `3728a6118c1d2d47c681ed78be583a5e7cb2a06e2c5dce3e1d6a6c5f7a6483e9` |

The warning in the forced-lock probe is expected: its actual download call also
tries to read optional telemetry, which is intentionally locked. It did not
prevent verified archive retrieval. This correction does not silently convert
unavailable telemetry into a signal-quality decision.

The original broad-run failure is still unattributed. The deterministic failure
mechanism and path defect are fixed within this scope, but there is no preserved
state proving which, if either, caused that earlier assertion failure.
