# GitHub source checkpoint — 24 September 2026

This checkpoint consolidates the local work in the same
[Bransolo1/Brohn repository](https://github.com/Bransolo1/Brohn). The other
development task used this checkout too; its September 20 implementation was
already included in `aa83ea6`. This follow-up connects the saved-video report
interface and completes further measurement-review checks. It is a development
source handoff, not a finished-platform release.

## Implementation and evidence

| Slice | Current evidence |
| --- | --- |
| [Exact processed values](PROCESSED-VALUES-ACCEPTANCE.md) | 22 connected browser assertions and five clean accessibility/reflow scans. Fourteen new jobs: 13 successful pages/exports and one deliberate cancellation. An independent reader compared all 108,414 rows across six actual CSV downloads with complete original artifacts, including nulls, types and signed zero. |
| [Pupil/blink traces](PUPIL-BLINK-TRACE-ACCEPTANCE.md) | 28 connected browser assertions, five clean accessibility/reflow scans and eight separate SVG-source checks. Includes keyboard scrolling, source/range-bound downloads, cancellation/retry, service restart and unchanged exports without new jobs on reopening. |
| [fNIRS review](FNIRS-VISUAL-ACCEPTANCE.md) | 33 connected assertions/five clean scans, with all 3,580 rows across six selections checked against saved original output. Twelve retained chart renders pass label-intersection/clipping checks. The corrected-browser rerun reused all saved results with zero new jobs; the initial journey's 17 read-only jobs remain separate from eight original jobs. |
| [Saved video explorer](VIDEO-GEOMETRY-RESEARCHER-JOURNEY.md) | 39 retained browser checks/seven clean scans plus 11 separate post-browser inspections. Covers face/pose/hands, exact decoded PNGs/native landmarks, complete selected CSVs, range/stale-link guards, index/frame cancellation and retry, keyboard paging and reopening. Six jobs in the completed traversal: four succeeded and two deliberately cancelled with successful replacements. |
| [Video resource boundary](VIDEO-GEOMETRY-RESOURCE-ACCEPTANCE.md) | Current worker passed three resource and 17 independent exactness checks on an unchanged 2.14 GB synthetic artifact: 36,000 frames and 2,088,000 metric values. Actual build-interpreter peak working set was 30.18 MiB and peak commit 21.76 MiB. This qualifies the declared index-build case, not model inference or every maximum configuration. |

Scientific source files and original reports are preserved. Video values remain
model-native face, body and hand geometry; they are not validated happiness,
attention or calibrated eye-tracking measures. QA media, participant workspaces,
model weights and downloaded runtimes remain outside the repository.

## Regression checks and failures retained

The existing Windows development runtime passed the core suite (109 assertions),
six independent video display regressions and the wire check. Actual Shiny
source/range/stale-command checks passed 12 assertions. Earlier browser failures
remain documented, including corrected landmark disclosure/focus loss, retry
monitoring the cancelled job, and Windows PNG transfer permissions. Compact
fNIRS label collisions were also found and corrected without changing values.
No failed or interrupted attempt is counted as passing.

The completed video traversal ended at a test-inspector typo. A corrected,
separate closed-store/download inspection completes that evidence; the original
failure remains unchanged. This is explicitly a joined continuation, not an
uninterrupted successful harness run. Its receipt has current source identities
and selected-frame worker identities, but no retained browser-start hash snapshot.
Two extra index jobs from an aborted repeat are separately recorded, not added
to the completed traversal's job count.

The bounded publication review checked 38 changed/new source and documentation
files, including five JavaScript syntax checks, one Python parse, three JSON
parses, 11 R parses and 298 relative Markdown links. Candidate files contained
no detected credential patterns or unexpected data/media/binary files; external
runtime and evidence directories remain ignored. Whitespace checks pass. These
checks do not replace the whole-platform test catalog or a clean installation.
The local publication audit is retained under
`make/work/test-runs/brohn-publication-20260924`.

The values journey needed an explicit wait for the Data library to become ready.
Independent timings indicate repeated synchronous context/metadata verification
needs profiling. Passing eventual navigation and export correctness does not
establish a latency target; optimize authority-preserving reads as follow-on work.

## Continue here

Read [current status](../../STATUS.md), [master architecture](../MASTER-ARCHITECTURE.md),
[completion backlog](../PRODUCT-COMPLETION-BACKLOG.md),
[build manifest](../preparation/build-manifest.json) and
[John's handoff](../HANDOFF-JOHN.md). The 50-capability scope and 17-package plan
remain authoritative. Questionnaire/scale distributions, paired multimodal plots,
synchronized replay, wider modality-specific journeys, clean-machine installation,
hosted operation, human comprehension and named-device qualification remain open.

Receipts, independent audit scripts, screenshots and original reference data are
retained at the machine-local paths in each acceptance record. Those paths are
evidence locations, not files a new contributor obtains by cloning. Reproduction
requires the documented reference preparation and optional local runtimes.
