# Derived audio in processed signal and interval views

24 September 2026. A saved acoustic report derived from video retains the live
authority of its original video, extraction, decoded audio and camera consent
chain. The generic processed-signal routes now enforce the same rule as source
audio review. Moving or changing the original source does not mutate a retained
report; it makes affected derived views and downloads unavailable until valid
source authority is restored. Ordinary processed reports retain their existing
behavior. No measurement, unit, scoring rule or aggregation arithmetic changes.

`brohn_signal_audio_lineage()` resolves the exact saved dataset revision and
checks its source, mapping, study, original publication and current derived
dataset against the report's retained `derived_audio_lineage`. It then uses
`brohn_audio_extraction_lineage()` to revalidate the original video/camera chain.
Missing or substituted lineage fails for a known derived identity. Historical
mapping revisions remain readable when their original lineage and current
authority remain valid.

Catalog, preview, exact-value page/export and saved-interval inputs include the
complete parent object references in their native read guards. Conditional
worker identity retains the extraction validator. Derived preview and interval
publication recheck parent authority inside the commit transaction; exact-value
publication already reconstructs and checks its complete source input there.
The shared job runner also guards those sources during child reads.

The generic plot controller clears revoked catalog/plot state on its existing
poll and shows an actionable source message. Its JSON/SVG callbacks perform a
fresh authorization check before the next poll can run. Interval JSON/CSV/SVG
callbacks do the same; revocation clears the interval editor/result without
closing the Shiny session. Interval reuse validates both original and target
sources through the common annotation-source resolver.

## Focused executed evidence

`tests/platform-signal-audio-lineage.R` passes 21 checks in
`../../work/test-runs/brohn-signal-audio-lineage-20260924-03/results.json`.
It copies the accepted original video/audio QA workspace into a new external
directory and uses real native signal adapters, guarded test publications and
Shiny controllers. It verifies:

- Valid derived catalog, preview, exact rows and full CSV remain available and
  carry all exact parent references; ordinary reports need no invented lineage.
- Substituting a parent hash, stripping lineage or erasing provenance from a
  known derived report fails.
- Revoked parent ownership blocks queue/input and retained catalog, preview,
  exact-page and export reads. Unrelated ordinary reports remain authorized.
- A deliberate in-process ownership change just before preview commit refuses
  publication and rolls back the catalog change.
- Already-open plot JSON/SVG downloads fail before the next poll. The live
  catalog and plot clear, explain the source issue, and can reopen unchanged
  after authority is restored. Original scientific reports/video stay unchanged.

`tests/platform-signal-audio-intervals.R` passes 14 additional checks in
`../../work/test-runs/brohn-signal-audio-intervals-20260924-01/results.json`.
On another external copy it verifies annotation creation and retained reads,
both directions of source/target interval reuse, exact summary input, guarded
native summary publication, commit-time ownership revocation and rollback,
immediate JSON/CSV/SVG rejection and safe live-state clearing. All prior
scientific reports and the accepted interval result remain unchanged.

Ordinary-path regressions also pass:

| Suite | Checks | Coverage |
| --- | ---: | --- |
| `tests/platform-signal.R` | 32 | Actual workers, provenance, extrema, missing support, fencing, Shiny and downloads |
| `tests/platform-signal-values.R` | 27 | Exact values/full CSV, native publication, pagination, revocation and Shiny |
| `tests/platform-signal-annotations.R` | 21 | Actual worker, independently known interval means/SD, revisions and fencing |
| `tests/platform-signal-annotations-views.R` | 15 | Interval editor, stale forms, retry, history and numerical chart semantics |
| `tests/platform-signal-reuse.R` | 28 | Declared anchor translation, precision, source ownership and interval reuse |

The focused tests do not rescore the acoustic report, run a new full browser
journey, or claim a scientific validity result. The connected camera/video-to-
acoustic browser journey remains separately documented in
[VIDEO-AUDIO-EXTRACTION-ACCEPTANCE.md](VIDEO-AUDIO-EXTRACTION-ACCEPTANCE.md).
General report screens/downloads and derived dataset downloads have separate
shared-app authorization tests; these focused receipts do not substitute for
those checks.

## Reproduction and retained diagnostics

Run the lineage test with the accepted `brohn-audio-extract-browser-*` fixture
directory and a new external `brohn-signal-audio-lineage-*` output directory.
Then run the interval test against that successful output and another new
external `brohn-signal-audio-intervals-*` directory. Each script copies the
workspace, requires terminal input jobs, uses the configured R/native guard and
audio/physiology environments, and preserves its own receipts outside Git.
Neither test edits the original accepted fixture. Temporary ownership faults
affect only the copies and either roll back or are restored explicitly.

Lineage attempts `-01` and `-02` are retained diagnostics. The first placed a
publication scratch file outside the copied workspace, which the existing path
guard refused. The second claimed a job before evaluating a lazily supplied R
queue expression. The harness now uses workspace-local scratch paths and forces
the job argument before claiming it. Production authorization code did not
change between those failures and the successful `-03` run.

The successful lineage receipt pins `platform-signal.R` to
`c8dd455a85964cb271fc8ffd590256e355759ad59d7d160a4d4a2c6adc7e7a22`
and `platform-signal-values.R` to
`a12ed954f96334ecf00dd5e510921a153876564b1ac3cc683a048b0542c8f7f3`.
The interval receipt additionally records the annotation domain/UI identities.
Shared-source changes made later require their own focused verification.
