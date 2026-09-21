# GitHub source checkpoint — 21 September 2026

This checkpoint brings [Bransolo1/Brohn](https://github.com/Bransolo1/Brohn)
forward from the September 8 publication. It includes the four subsequent local
commits and the latest measurement-review implementation files. It is a source
handoff with unfinished acceptance work, not a production-readiness sign-off.

## Included work

The earlier resumed commits connect the complete questionnaire answer explorer,
guided study setup, welcome and study images, reusable equipment setups,
participant preflight, saved signal intervals and cardiac input/exclusion review.
Their individual acceptance records remain linked from [STATUS](../../STATUS.md)
and the [completion backlog](../PRODUCT-COMPLETION-BACKLOG.md).

The latest working files add exact processed-value paging and CSV workers,
retained pupil/blink traces and their report interface, fNIRS reference and
visualization fixtures, and saved-video geometry/frame exploration components.
Their qualification boundaries are different:

| Slice | Recorded evidence and remaining acceptance |
| --- | --- |
| [Exact processed values](PROCESSED-VALUES-ACCEPTANCE.md) | Direct worker, native publication and Shiny checks; final connected browser acceptance is unfinished. |
| [Pupil/blink traces](PUPIL-BLINK-TRACE-ACCEPTANCE.md) | Source-retention, saved-worker and initial connected-browser evidence; final SVG export and keyboard-scroll acceptance remain unfinished. |
| [fNIRS visualization](FNIRS-VISUAL-ACCEPTANCE.md) | Independent software phantoms and saved production outputs; connected browser acceptance remains pending. |
| [Saved video geometry](VIDEO-GEOMETRY-SAVED-REFERENCE.md) | Actual saved model output and index reference checks; complete image/overlay/browser/export acceptance remains separate under the [explorer contract](VIDEO-GEOMETRY-EXPLORER-CONTRACT.md). |

Historical wording such as “running” or “in progress” in an acceptance record
describes its last recorded session. It is not proof that its process is still
running, nor proof of completion. Inspect the retained receipt and current
process state before continuing a test.

## Checks repeated for publication

On the existing Windows development runtime, all five selected R catalog
checks passed: `core` (109 assertions), `gaze-traces` (49),
`gaze-trace-server` (10), `signal-values` (27) and
`participant-equipment-races`. The runner retained source identities and
per-check logs at `make/work/test-runs/brohn-push-20260921-105005`.

Six Python worker suites passed 97 tests in total: `signal_values`,
`gaze_trace`, `signal_preview`, `signal_windows`, `vision_explorer` and
`vision_frame`. All 73 repository Python files parsed successfully, and
48 JavaScript files changed since the previous publication passed Node syntax
checks. Python receipts are retained at
`make/work/test-runs/brohn-push-python-20260921-105006`.

The source-publication audit found no real credentials, research databases,
participant recordings, model weights, downloaded dependency trees or oversized
artifacts in its candidates or credential scan of unpublished history. Current
handoff links, manifest JSON and the staged whitespace check passed. These are
bounded publication checks, not a fresh-machine installation, full test-catalog
run or completion of the outstanding browser journeys above.

## Continue development

Start with [remaining work](../KNOWN-GAPS.md), the
[measurement coverage audit](MEASUREMENT-VISUAL-COVERAGE-AUDIT.md),
[master architecture](../MASTER-ARCHITECTURE.md) and
[build manifest](../preparation/build-manifest.json). Complete the outstanding
researcher journeys before upgrading their support claims. Preserve historical
reports, exact source values, missing support and scientific method limitations.

The repository contains source, original fixtures, method notes and QA records.
Developer environments, external reference media, model weights and runtime
research workspaces remain outside it. Installation follows the
[local setup guide](../operations/LOCAL-INSTALLATION.md). Physical hardware,
human usability and hosted deployment retain separate qualification requirements.
