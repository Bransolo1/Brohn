# Researcher-authored welcome page and image

Executed 20 September 2026 on Windows with the restored local R library and
Chrome. This acceptance concerns authoring, immutable content delivery, reuse
and browser behavior. The observed response is an explicitly synthetic sample
fixture; there is no human usability, hardware or scientific timing claim.

## Delivered behavior

Plan now offers an optional welcome heading, multiline message and PNG image,
with alternative text. The opening page is separate from participant information
and consent, post-consent instructions and the final debrief. Disabling welcome
returns the draft to the original entry behavior.

Image attachment is an explicit action in a source-bound dialog. Attach is
disabled while a new file is uploading. Invalid bytes or missing alternative text
leave the original draft intact and show an error inside the dialog so the
researcher can correct it. Reopening a dialog cannot silently reuse a previous
upload, and concurrent study changes reject a stale attachment. Replace and
remove affect the current draft; retained study revisions and releases remain
unchanged.

Preview saves pending text and renders the exact saved welcome through the same
participant component, inside a sandboxed iframe with the saved participant
colours. Continue shows the saved study-information text. The preview has no
participant runner, delivery credential, registration or response recording.
Closing returns keyboard focus to its launch button.

Released studies show welcome before consent. A failed welcome-image load blocks
continuation and offers Retry image. Retrying successfully clears the error and
allows the normal consent flow. Welcome and consent navigation alone allocate no
participant session. Existing releases without this optional field continue to
open directly at their original consent screen. Existing post-consent steps and
their original timing/response semantics are unchanged.

## Saved contract and source integrity

`brohn-design/1.0.0` accepts an optional `welcome` object:

```text
schema: brohn-welcome/1.0
title: plain text, up to 240 UTF-8 bytes
text: plain text, up to 20,000 UTF-8 bytes
asset: null or a supported immutable PNG manifest
image_alt: plain text, required when an image is attached
```

The image profile reuses the existing complete PNG decoder: at most 5 MiB,
4096 pixels per side and 8 million pixels in total. The original decoded-valid
PNG bytes are stored without re-encoding, with their hash, size, media type,
plain display filename and pixel dimensions. HTML, SVG, remote image URLs and
executable content are not accepted as welcome artwork. Authored text is rendered
as text, including literal HTML-like strings.

The optional field is absent on existing designs; it is not inserted through a
migration or new default. It freezes inside the released design and the assigned
protocol's design. It adds no timeline step. The entry response preserves that
manifest and supplies an independent image URL tied to the existing release
capability. That capability serves only an image present in its pinned design;
an arbitrary object hash or replacement draft image receives no access.

Clone and template reuse retain exact welcome content in the new design identity.
Portable design packages enumerate the welcome asset along with the existing
stimulus/task assets, so export/import retains its exact bytes and metadata.
No participant observation is copied into a reused design.

## Executed checks

- `tests/platform-welcome.R`: **19 checks** with actual SQLite records, original
  PNG bytes, release routes and a real ZIP export/import roundtrip. Checks include
  unchanged legacy revision and timeline, exact source hashing, release-bound
  asset access, pinned old release after replacement, clone/template reuse,
  invalid media/metadata rejection and safely embedded preview data.
- `tests/platform-welcome-views.R`: **13 Shiny checks** covering pending-text
  capture, local dialog errors and recovery, source-bound attachment, preview
  cleanup, stale upload rejection, invalid replacement retention, concurrent
  edits, cross-study navigation and image removal. Authoring creates no delivery
  tables or sessions.
- Relevant unchanged-contract regressions passed: **109 core**, **90 portability**
  and **56 participant-delivery** checks.
- `tests/researcher-welcome.mjs`: initially **7 actual two-service browser assertions** and
  **3 accessibility/layout scans**. The browser authored welcome text and image,
  recovered from invalid upload, previewed saved content, released a sample study,
  recovered from a failed image request, and completed welcome → consent → saved
  instructions → one synthetic response → authored debrief. It then replaced the
  draft image, checked the old release, reused the template, exported a design
  package and opened a legacy release directly at consent.

The three scans covered the 390-pixel researcher preview and the actual participant
welcome at 1440 and 390 pixels. All had zero axe violations, horizontal overflow
or undersized measured controls. The shared iframe main landmark received a
distinct accessible name after the browser exposed a duplicate unnamed landmark.
Final screenshots were visually inspected. Researcher and participant logs showed
no R or browser exceptions in the passing run.

Retained local evidence:

```text
C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-welcome-20260920-03/
  browser-evidence-1789877783544/results.json
  browser-evidence-1789877783544/*-axe.json
  browser-evidence-1789877783544/participant-welcome-desktop.png
  browser-evidence-1789877783544/participant-welcome-390.png
  browser-evidence-1789877783544/researcher-welcome-preview-390.png
  browser-evidence-1789877783544/original-welcome.brohn-study.zip
  browser-evidence-1789877783544/researcher.log
  browser-evidence-1789877783544/participant.log
```

## Reproduction and limits

```powershell
$env:R_LIBS_USER=(Resolve-Path ../../work/r-library-brohn-restore).Path
$env:LC_ALL='C'
& ../../work/native-r/bin/Rscript.exe --vanilla tests/platform-welcome.R
& ../../work/native-r/bin/Rscript.exe --vanilla tests/platform-welcome-views.R
node tests/researcher-welcome.mjs <fresh-folder-named-brohn-welcome-...>
```

The browser fixture starts isolated local researcher and participant services and
uses original fictional sample packaging. It creates one explicit sample session.
Browser tests use the actual release API, not a mocked participant server.

The completed session was additionally processed by its actual queued analysis
worker: seven assertions passed for guarded publication, the original frozen
welcome image, unchanged frozen design, retained participant response, sample
origin and the welcome validator's code identity. Evidence is
`work/brohn-welcome-20260920-03/welcome-worker-acceptance.json` in the current
20 September task directory. This exposed and corrected a missing welcome-module
load in the child worker. The browser harness now includes this analysis as an
eighth assertion. The full expanded researcher/participant/worker browser journey
then passed **8 assertions and 3 clean accessibility/layout scans** in a fresh
workspace, including successful automatic saved-report publication. Final evidence:
`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-welcome-final-04/browser-evidence-1789881197933/results.json`.
No acquisition hardware was exercised.

The implemented editor is one optional welcome page, plain text and one PNG.
Rich text, arbitrary page builders, other upload formats, an interactive preview
of a complete timed session, and broader browser or assistive-technology profiles
are outside this checkpoint. The source-sequence preview in Overview continues to
describe compiled outer steps; welcome is pre-consent content, inspected with
Plan's dedicated saved welcome preview.
