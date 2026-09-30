# Stimulus versions and controls — scoped acceptance

1 October 2026. **Add version is implemented and accepted for ordinary study
stimulus authoring.** Open Plan, copy a stimulus into a separate test/control/
neutral/other condition or an existing condition, edit it, and save. The
[researcher guide](../operations/STIMULUS-VERSIONS-AND-CONTROLS.md) explains the
workflow and research consequences.

## Executed evidence

- 36 domain/portable checks: exact source preservation, new stimulus/AOI IDs,
  condition roles and membership, capacity/name boundaries, ordinary compilation,
  actual design ZIP/import, image replacement and historical revisions.
- 28 real Shiny observer/SQLite checks: current Plan/modal identity, stale and
  repeated commands, authorization/head changes, cancellation, transaction
  failure and in-memory recovery after a save callback throws.
- 25 connected browser checks on the exact final source: ordinary full service
  startup; synthetic study opened through Studies/Plan; invalid name and Cancel;
  keyboard-created separate control; explicit existing-condition alternative;
  repeated click; image replacement, Save and reopen. The original study versions,
  materials and other catalog records stay exact. Only the edited copy loses AOIs.
- Six full-page Axe scans at desktop 1280 and phone 390 widths, with zero
  violations. Root inspected seven actual rendered screenshots, including error,
  keyboard focus and saved Plan. Normal dialog buttons fit the tested viewports.
  This is scoped automated/manual review, not a complete accessibility audit.
- Owned researcher, participant, acquisition and worker processes closed
  naturally. No scientific job or participant session was created.

The [source receipt](STIMULUS-VERSIONS-SOURCE.json) records exact tested runtime
and test bytes, phase identities and boundaries. Working-tree BASE bytes are
distinct from earlier Git blobs: pre-existing line-ending differences are
preserved by the distributed Git byte policy. Two fresh checkouts with
`core.autocrlf=false` and `true` are checked before publication; this proves
byte preservation, not a new scientific or operating-system qualification.

## Corrections retained

The first fresh fixture failed because its test ref requested an absent
`body_hash` field. The successor reads that saved field explicitly. The next
browser attempt stopped after an accessibility scan and a keyboard activation;
focus was not reasserted immediately before Enter. Its screenshots also showed
an overlong dialog. Final source shortens four paragraphs without changing
controller behavior; the final harness scans first, then uses real Tab traversal
and verifies focus immediately before Enter. Failed attempts remain retained.

The final source passed the original 36/28 checks again and the actual corrected
researcher journey. No assertion was removed, no timeout enlarged and no failed
attempt is described as passing.

## Practical limits

Every listed ordinary stimulus is scheduled once per run. Different groups do
not yet receive different variant subsets. Existing condition-level gaze summaries
can pool same-condition versions, and a new control does not automatically create
a planned contrast. A control stimulus is separate from a recorded physiological
baseline. Design roles and software checks do not establish scientific validity.

Concept/variant-set allocation, shelf construction, semantic/dynamic AOIs and
other flexibility requirements remain in the [EF02–EF12 queue](../research/EYE-TRACKING-FLEXIBILITY.md).
This release does not activate the unfinished cardiac report or academic-evidence
runtime. All 50 capability and 17 package statuses retain their wider open work.

The loader edit changes new report-preparation implementation fingerprints.
Static review found saved-package opening/downloads still use saved producer
bindings rather than current-loader equality. An unfinished older preparation
may request a new preparation; no historical output is rewritten. This release
does not claim a fresh native report or historical-report browser qualification.

## Reproduce the focused checks

With the documented R dependencies installed, run each of
`tests/stimulus-versions-domain.R` and `tests/stimulus-versions-controller.R` with
three arguments: repository root, the same repository root, and a fresh output
directory outside the checkout. Each creates only its owned synthetic stores;
do not point it at a real research workspace. Test comments retain their original
overlay terminology; the recorded final execution uses this complete checkout.
