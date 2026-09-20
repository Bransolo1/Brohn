# Question illustrations and MaxDiff item images

20 September 2026. Read-only integration audit and proposed implementation
contract. No production changes or new test runs were made for this document.
Implement questionnaire illustrations first, after the coordinator's checkpoint;
qualify MaxDiff item images as a separate subsequent slice. These are additions
to enabled participant procedures, not completion of the 50-capability register.

## What the current source requires

| Route | Current behavior and exact integration point |
|---|---|
| Questions | `brohn_validate_question` in `R/platform-core.R` allows twelve types, with strict fields and no image. The compiler copies the whole question into each before/after-each/end occurrence; section assignment also carries the whole question. |
| Participant questions | `www/participant/runner.js` shares `questionFields` for answer controls, but uses separate `showQuestion` and `renderRevision` screens. The latter also builds the answer-review list. Updating only one screen would miss a supported route. |
| Revision integrity | `R/platform-question-revision.R` compares each compiled question against its frozen design, then reconstructs and hashes the occurrence-decorated protocol. Visits, draft generations, invalidations and seals are separate from question content. Keep image transport URLs outside the canonical question object. |
| Release assets | `R/platform-delivery.R` enumerates only passive stimuli, task materials and welcome assets for publication checks and capability-scoped GET. `.brohn_delivery_protocol_urls` currently augments renderer copies of passive/task media only. Both enumeration sites and transport augmentation need explicit question/choice support. |
| Reuse and packages | `brohn_clone_design` copies complete question records and remaps their IDs/rules. `brohn_maxdiff_clone` copies complete items and remaps item/set identities. Their image metadata can survive without a new clone algorithm. `.brohn_port_assets` and `.brohn_port_validate` in `R/platform-portability.R` must include the new references. ZIP extraction verifies manifest hashes and media signatures, but its PNG check is broader than the authoring decoder and does not fully decode pixels. |
| Material authoring | `platform-materials.R` and `platform-material-views.R` now provide explicit attachment, descriptions, exact saved-target authority, local recovery and streamed preview. Extend this mechanism; do not add another automatic-on-transfer observer. |
| MaxDiff | `R/platform-maxdiff.R` items are exactly `{id,label}`. `brohn_maxdiff_steps` carries full items into each offered set. `www/participant/maxdiff.js` independently requires exactly two item fields and renders two labelled radio groups; it has no media preparation. Both validators need the optional image shape. |
| Results/artifacts | Questionnaire summaries contain typed answers, IDs and prompt text, while report provenance retains the exact design. Questionnaire artifact source binding hashes all provenance; its tree storage is lossless and does not need a new answer schema for image metadata. MaxDiff results already retain the complete exercise design, including any newly allowed optional item field. |

## Common immutable image shape

Add optional `illustration` to a question and, in phase two, to a MaxDiff item:

```text
illustration = {
  asset: {hash, size, media_type: "image/png", filename, width, height},
  image_alt: <researcher-authored nonempty text>
}
```

The field is **absent by default**, not automatically `null`, empty or populated
with fallback content. Constructors and unchanged legacy records remain
byte-semantically identical. Removal deletes the field. When present, require
exactly these supported fields, a SHA-256 identity, plain display filename,
positive integer dimensions, the existing PNG limits, and a description of at
most 2,000 UTF-8 bytes. Keep the existing complete `new_png_asset` decoder:
5 MiB, 4,096 pixels per side and 8 million pixels. No SVG, remote URL, HTML or new
format is introduced. Store the original bytes; never derive descriptions from
question answers, category names or MaxDiff preference labels.

The title/prompt and MaxDiff item label remain required safe text. An image
supplements them. It does not replace question type, typed codes, matrix rows,
ranking identities or choice-set membership. Question-option/row images are
outside this first question-level illustration slice, as are image AOIs and
new timing controls.

An explicit image/description edit creates a new design hash, as it should.
Frozen older releases remain unchanged. With no illustration field, canonical
designs, compiled protocols and analysis results must stay identical. With a new
image, preserve actual question/set/item order for the same seed/allocation and
all procedure settings; source-derived hashes, occurrence IDs and MaxDiff trial
IDs legitimately change. Do not assert those IDs remain equal after a source
edit: MaxDiff trial IDs expressly include the exercise design hash.

## First slice: questionnaire illustrations

1. Extend the current material target adapter with `kind="question"`, stable
   question ID and stage `Questions`. Its owner is the full canonical question;
   its preview adapter may expose prompt/image fields without persisting that
   adapter into the design. Opening the dialog captures current question edits,
   then pins the same saved study/revision/project/design/target identities as
   the accepted material editor. Attach, replace and description-only save use
   the same explicit commands and fresh-transfer checks.
2. Add one compact material control to every question card, including
   `information`. Use “Add illustration”, “Preview illustration”, “Edit image”
   and “Remove illustration”. Removal preserves prompt, typed options, rows,
   logic, scales and placement; it must not invoke the passive/task replacement
   text action or change a question's type. Keep draft text and local recovery
   when bytes, description or authority checks fail.
3. Add a shared participant illustration helper used by forward-only questions,
   revision questions and their visible review rows. Show the saved image after
   its prompt and before answer controls. Review/edit/back/resume show the same
   source and authored alt. Hidden or invalidated-hidden questions remain absent
   from the displayed question/review list. Information pages retain explicit
   acknowledgement rather than becoming an answer input.
4. Add release-scoped transport URLs only to renderer steps, for example
   `step.question_image_url`; never write them into `protocol.design`, the
   canonical `step.question.illustration`, stored run protocol, report or ZIP.
   The renderer must require the same-origin `/api/assets/` capability route and
   bind the URL to that step's retained asset. The server GET still authorizes
   against the release's original design, not an arbitrary requested hash.
5. Prepare unique illustration bytes before any new question visit/onset can be
   recorded. Deduplicate by asset hash, but apply alt per question when cloning
   prepared DOM images: two questions can intentionally describe the same bytes
   differently. Both start and resume need this preparation, and every revision
   entry path must use the same prepared helper. Do not create a visit, answer,
   information acknowledgement or skipped-question record solely by preloading.
6. Image preparation failure is an untimed, recoverable material state: no
   answer controls or Continue/Seal success while a required illustration is
   unavailable. Offer Retry materials and Stop using the same retained run and
   allocation; retain any existing drafts/received answers. On retry, prepare
   the exact original asset, then enter or resume normally. Cancellation must
   prevent a late load callback from reopening a finished run. Preserve the
   existing behavior for failed timed passive/task media; do not replay them.
7. Bound preparation explicitly. Proposed new-illustration profile: at most
   64 million unique declared pixels (about 256 MiB raw RGBA), with their unique
   compressed bytes also counted inside the existing 512 MiB browser media
   budget. Check metadata against decoded natural dimensions. Repeated
   after-each occurrences must not multiply that budget. Enforce the same
   preflight server-side and browser-side, with a smaller-image recovery message.
   This is an engineering resource bound, not a timing/performance qualification;
   settle it with the coordinator before implementation.

The optional image changes the visual material, not branch truth, response
codes, dependency invalidation, visit idempotency or the meaning of omission.
Question response clocks begin only after prepared visual content is inserted;
onset remains a browser observation. Reuse the current controls and preserve
typed values, keyboard focus, required/optional rules and literal text rendering.

## Release, package and result obligations

Use one shared new-illustration collector for publication checks, release asset
authorization, package enumeration and preload-budget calculation, avoiding
different interpretations of the same design. Existing stimuli/task/welcome
collection keeps its existing semantics. Every optional image reference must
resolve to the exact object, matching hash, size and dimensions; a missing or
malformed illustration is not silently treated as an image-free question.

For newly introduced illustrations, verify actual PNG bytes with the existing
bounded complete decoder before accepting a portable import and before release
if the reference has not been trusted through that path. The existing portable
signature check alone is insufficient to claim the 8-million-pixel/full-decode
authoring profile. Do not broaden or retroactively reject unrelated legacy media.
Deduplicate shared files by hash while preserving each owner's alt. A package
with a missing, extra, mismatched or corrupt illustration must fail before its
study is registered. Use the current atomic/quarantine mechanisms.

Clone/template/import preserve metadata and exact bytes while remapping only
the existing graph identities. Report provenance retains the frozen image
reference; participant journals continue to record responses, not image bytes.
Questionnaire artifact/index schemas and response CSV columns need no semantic
change. Test a packed report and its provenance binding with the new metadata;
do not weaken existing exact-source checks. Report JSON/design ZIP preserve
the material identity; this slice does not promise that standalone response CSV
or existing HTML exports embed pictures.

## Second slice: MaxDiff item images

Use the same optional `illustration` shape and saved material editor with
`kind="maxdiff_item"`, exercise ID and item ID. Keep item labels, offered
identities/order, prompt, best/worst labels, requiredness and paired-likelihood
analysis unchanged. The R item validator and the JavaScript `validatedChoice`
item-field check both explicitly accept the optional shape; unrelated fields
remain rejected. `brohn_maxdiff_steps` already carries full items into choices.

Keep source canonical: append renderer-only `step.item_image_urls`, and supply
prepared nodes to `BrohnMaxDiff.create` separately from its scientific `choice`
object. Display the exact same item image/alt in both existing choice groups,
in the saved order, before enabling the response. Use native radios and keep
distinct best/worst exclusion, partial drafts, optional skip, lost-receipt retry
and resumed timing unchanged. Media preparation precedes `step_started`; an
image error never fabricates a completed or presented exposure.

The existing MaxDiff modal owns an unsaved exercise draft and review hash.
Do not open the saved-material dialog over that draft or silently commit its
other fields. The minimum safe integration exposes item image controls beside
each **saved** exercise on Tasks, with a clear save/close path from the exercise
editor. Image edits then invalidate the saved design's old review identity in
the usual way. A future inline draft adapter can reuse validation/preview, but
would need an explicit parent token/version, capture and review-reset contract;
it is not necessary for this bounded first implementation.

MaxDiff import rows still require the exact exercise hash. Images do not create
new exposure columns or allow old answers to be relabelled against a changed
exercise. Native results retain full image-bearing design; counts/utilities for
an equivalent response fixture remain numerically identical after deliberately
rebinding that fixture to its new source hash. No new implicit/emotion claim.

## Proposed ownership and acceptance gates

Experience worker: new pure `R/platform-question-materials.R` (metadata validator,
collector and new-image adapters), scoped `platform-materials.R` /
`platform-material-views.R` extension, question card hook in `platform-views.R`,
new `www/participant/illustrations.js`, scoped `runner.js`/CSS/HTML, focused
domain/Shiny/browser fixtures and this acceptance record. After specific approval,
own only the question optional-field validator in `platform-core.R` and the
illustration collection/transport/import-validation additions in
`platform-delivery.R` / `platform-portability.R`. Keep scientific scoring and
revision state-machine files unchanged unless a concrete failing invariant
requires a separately reviewed change.

Coordinator: app/load/worker dependency order and shared registration. A pure
validator referenced by core or worker replay must be available in every source
closure, not only in `brohn_load(ui=TRUE)`. Keep validators store-free. The
existing material installer remains the root hook; a new question card helper
may wrap it, with no parallel automatic upload observer.

Question acceptance must cover: absent-field legacy canonical/protocol fixtures;
all twelve types; sectioned and unsectioned order; repeated after-each images;
same bytes with different alt; invalid/missing/oversized PNG; malformed package;
project/revision/dialog revocation; attach/replace/describe/remove; actual
clone/template/cross-workspace ZIP; an old release after replacement; both real
participant question routes; branching hide/show and transitive invalidation;
information acknowledgement; Back/Edit/Review/Seal and reload; media failure and
retry without extra allocation/visit/answer; source-packed report/explorer
integrity; desktop/390-pixel keyboard, axe, focus and screenshot review; an actual
completed sample run through its supervised saved report.

Phase-two MaxDiff acceptance additionally covers mixed text/image items, both
choice groups and every offered order, exact same-image/different-alt ownership,
partial/invalid pair and optional skip, source replacement, authoring review
invalidation, clone/template/ZIP, browser reload/lost receipt, failure before
onset, current CSV import hash rejection, and unchanged paired numerical outputs.
Reuse existing `participant-question-revision*`, `participant-logic.mjs`,
`participant-maxdiff*`, portability and questionnaire-artifact tests where they
exercise these invariants; add focused fixtures rather than duplicating all
unrelated platform regressions.
