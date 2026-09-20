# Saved study material editor

20 September 2026. Implements the bounded passive/exemplar slice identified in
`STUDY-MATERIAL-AUTHORING-AUDIT.md`. Brohn's complete capability register remains
intended scope; this change does not enable new scientific procedures.

## Connected behavior

- Passive stimuli and existing IAT, good-focal BIAT and keyboard AAT exemplars now
  share an explicit Add image / Edit material dialog: preview, PNG attachment or
  replacement, editable participant description, and removal with text recovery.
- An editor pins the saved study, revision, design hash, project, target IDs and
  target hash. Commands also require the current dialog token and form identity.
  Navigation clears the context; concurrent revisions or lost project authority
  reject writes and media access. Invalid uploads keep the draft and typed fields.
- Newly authored images require the researcher's own description, bounded at
  2,000 UTF-8 bytes. Literal text stays text. The optional `image_alt` field is
  absent from unchanged legacy designs; their prior participant fallback stays
  unchanged. Category names are never appended to the authored description.
- PNG validation retains the existing complete decoder and bounds: 5 MiB, 4,096
  pixels per side, 8 million pixels. Original bytes receive immutable SHA-256
  identities. Changing a description preserves image identity and areas;
  replacing different passive image bytes explicitly clears current areas.
- Each preview serves the exact verified saved file through one session-bound
  resource, tied to the current material token. Closed, replaced or stale tokens
  cannot retrieve it. Large permitted media are streamed from the saved file,
  rather than inserted into the page as base64 data.
- Already permitted passive WebP, audio and video select native image/audio/video
  elements. Retained GIF is also previewable; this does not add GIF to the
  portable ZIP format list. Image-area controls are not shown for these media.
- Previewing starts no participant session. Saving a replacement affects the
  draft; an existing release still serves its original material. Clone, template
  reuse and portable design export/import retain descriptions and exact assets.
- Task image changes preserve category membership, trial identities, mappings,
  timing settings and registered scoring procedure. They appropriately change
  the task's design identity. Fixed simple/four-choice RT keep their own cues.

## Executed focused checks

Windows, restored R runtime/library, actual local Shiny researcher app and local
participant receiver, Chrome headless. Fixtures contain only original synthetic
artwork, generated audio/video and automated sample-origin responses.

| Check | Result and scope |
|---|---|
| `tests/platform-materials.R` | 30 passed: legacy design/protocol invariance; malformed bytes and description bounds; exact assets; AOI invalidation; all three exemplar profiles and fixed-RT exclusions; release isolation; actual clone/template/ZIP roundtrip; media dispatch; no session allocation. |
| `tests/platform-material-views.R` | 19 passed: actual Shiny observers; explicit transfer and recovery; reopened-file rejection; exact streamed response; token revocation; description-only save; concurrent revision and archived-project rejection; navigation; passive/task text fallback. |
| `tests/researcher-materials.mjs` | 12 passed connected assertions, including actual authoring/recovery, preview token revocation and keyboard focus, complete passive and IAT participant runs, immutable older release, clone/template/export, all three exemplar editors, text removal recovery, permitted media and two actual supervised saved reports. Six desktop/390-pixel axe/reflow/44-pixel-control scans passed with no script errors. |

Final evidence:
`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-materials-05/browser-evidence-1789884188845`.
`results.json` records all 12 checks and six scans; each scan has its axe JSON and
PNG. The saved `original-materials.brohn-study.zip` is the actual browser download.
`../worker-results.json` records both sample reports and run IDs; the fixture
asserts each report's retained design hash exactly matches that run's frozen
protocol. Researcher/receiver logs are retained and both owned services closed.

Screenshots visually inspected: recovery editor at 390 pixels, passive preview
at desktop, task preview at 390 pixels, and imported video at 390 pixels. Long
literal image descriptions wrap; no horizontal page overflow remains. Native
file inputs retain Shiny's intentional offscreen implementation; their visible
browse control and labelled input remain accessible.

Earlier connected passes exposed and fixed a task exemplar heading-level skip
and narrow overflow from an unbroken authored description. Native media preview,
complete IAT delivery and both actual supervised analysis jobs passed before the
final scan refresh. Test-only setup/order corrections were kept out of production
logic: a portable media fixture needs a valid condition, cloning requires its
visible confirmation, and queue claims follow FIFO rather than list order.

## Boundaries

This is software acceptance using original synthetic data. It does not qualify
physical onset timing, hardware, human usability or every browser/codec pairing.
No arbitrary new audio/video upload, questionnaire inline-image field or
illustrated MaxDiff item was added. Consent/instructions/debrief remain distinct
safe-text stages; the separately accepted welcome image flow remains available.
The editor previews saved content and study colours, not the full timed task.

Implementation: `R/platform-materials.R`, `platform-material-views.R`; scoped
passive/task cards, optional validators, participant alt handling and CSS;
`www/material-preview.js`. Coordinator wiring replaces both legacy automatic
file-upload observers with the new explicit editor installer.
