# Questionnaire sections and safe ordering

Domain and researcher editor implementation, 8 September 2026. Shared compiler
integration has its separate root-owned evidence; actual browser qualification
is still underway at this handoff. This follows
the [delivery audit](../qa/NEXT-PROTOCOL-DELIVERY-AUDIT.md) and preserves the
existing [option-assignment contract](QUESTION-OPTION-ASSIGNMENT.md).

## Design contract

`design.questionnaire_sections` is an optional, versioned layout over the existing
`design.questions` registry. `design.blocks` continues to mean timed implicit/RT
tasks. An absent sections field keeps the original flat order and adds no new
compiled metadata. An explicit null is invalid; an enabled empty sections array
is valid only when there are no questions.

```json
{
  "schema_version": "brohn-questionnaire-sections/1.0",
  "assignment": "participant-sha256/1.0",
  "sections": [
    {
      "id": "section-opinions",
      "label": "Concept opinions",
      "scope": "after_each",
      "placement": "fixed",
      "groups": [
        {
          "id": "group-liking-reason",
          "label": "Liking and follow-up",
          "placement": "shuffle",
          "question_ids": ["q-liking", "q-reason"]
        },
        {
          "id": "group-clarity",
          "label": "Clarity",
          "placement": "shuffle",
          "question_ids": ["q-clarity"]
        }
      ]
    }
  ]
}
```

Every existing question must belong to exactly one nonempty group when enabled.
Sections, groups and questions are each bounded to at most 200 total. Section IDs
are unique; group IDs are unique across the entire questionnaire. Names are bounded
to 240 bytes. All members of a section share its `before`, `after_each` or `end`
scope. No question, group or section is silently dropped. Unsupported fields,
versions, memberships, placements or empty groups fail with actionable names.

Group-internal question order is always the authored `question_ids` order. A
section's `placement` determines whether it can move among the shuffled section
slots of the same scope. A group's `placement` determines whether it can move
among the shuffled group slots of its own section. Fixed slots stay exactly in
place; shuffled items can move across an intervening fixed slot. For example,
`shuffle A, fixed B, shuffle C` may become `C, B, A`. This is explicit slot
randomization, not a promise that a fixed anchor acts as a movement barrier.

There is no subset sampling, general branch jump, section-level skip, Back
navigation, response revision or new participant assessment boundary in this
profile. A hidden conditional question remains an individual display-logic skip;
the offered layout still retains its question ID.

## Dependencies and instruments

Validation examines every referenced question in the nested AND/OR/NOT display
rule, irrespective of whether one sample answer would make a branch visible.
The reference must precede its dependent in **every** permitted permutation:

- Inside one group, the source's question position must be lower.
- In separate groups of one section, the source group's maximum possible slot
  must be below the target group's minimum possible slot.
- In separate same-scope sections, the same maximum/minimum test applies to
  section slots.
- The existing before-scope answers can drive after-each/end questions. An end
  question cannot silently use the last after-each answer. The existing base
  validator retains earlier-question and legal-scope checks as well.

An unsafe layout is rejected before assignment even if one tested seed happens
to produce a safe order. There is no hidden topological sort or biased shuffle
used to repair it. The error names the dependent, its driver and relevant
sections, and asks the researcher to group them together or fix their order.

All items in a declared quantitative scale must remain in one group, with their
relative **existing question presentation order** preserved. The scoring-key
item list can be in another order and does not redefine presentation. This
protects instruments from being fragmented or reordered by section/group
shuffle; it does not establish their validity for a population or translated
wording. Existing scale assessment IDs remain `scope:before`, `scope:end` or the
actual preceding stimulus step. A section/group is not another independent
assessment, participant or physiology exposure.

The explicit constructor first preserves the exact legacy question order within
each scope. It joins each same-scope dependency span, including intervening
questions needed to preserve order. Scale spans are joined likewise; overlapping
spans produce a larger group. Consequently two interleaved instruments may need
one enclosing group. Its generated label identifies that it contains grouped
questions, and review must show its actual members. Enabling sections alone never
reorders the questions or turns on shuffle.

## Assignment and compiled evidence

Hash-ranking is separate at the section and group levels. For each movable item,
SHA-256 covers compact canonical UTF-8 JSON with these exact fields:

```json
{
  "allocation_index": "7",
  "item_id": "group-clarity",
  "level": "group",
  "parent_id": "section-opinions",
  "schema_version": "brohn-questionnaire-order/1.0",
  "scope": "after_each",
  "seed": "104729",
  "stimulus_id": "stimulus-a"
}
```

Whole-number seed and allocation use base-10 strings. `level` is `section` or
`group`; section-level `parent_id` is null. Before/end `stimulus_id` is null;
after-each uses the exact existing stimulus ID. Movable items sort by full
lowercase digest, then ASCII ID as a collision tie-break, and fill only movable
slots. The algorithm does not consume ambient R RNG state. Labels, prompts,
unrelated scope items, instructions, timing settings and stimulus timeline
positions do not enter these ranking hashes.

This is deterministic participant allocation, not guaranteed counterbalancing.
Different allocations may share an order; finite samples need not have equal
position counts. Allocation is a run reservation, not evidence of a distinct
person. Changing question/section/group identities during cloning gives the new
design its own assignments. The original raw source and hashes stay preserved.

The current compiler offers each unique stimulus once. After-each layouts bind to
that stimulus independently of its position. Repeating one stimulus ID would
need a separate versioned occurrence policy; this module does not implement it.

`brohn_question_sections_plan()` returns `entries` and `manifest`. Each entry has
the unchanged `question` record and a sibling `questionnaire` metadata object:
schema, assignment ID, section/group IDs and labels, section/group/question
positions, scope and stimulus ID. It must not add these fields inside the frozen
question, because that would change its scientific/source identity.

The manifest binds the full design hash, section-config hash, assignment version,
seed/allocation, scope/stimulus, and exact realized section/group/question order.
Its `assignment_id` hashes that source context and is scoped to the pinned
protocol; it is not a globally unique participant record. Labels or source edits
change the source identity even when a permutation happens to remain the same.

## Pure APIs and root integration

| API | Result and responsibility |
| --- | --- |
| `brohn_validate_question_sections(config, design)` | Validates exact membership, bounds, dependency safety and scale grouping. No mutation. |
| `brohn_question_sections_new(design)` | Returns an enabled, all-fixed config preserving original scope order; merges dependency/instrument spans. Does not save or enable it on the design. |
| `brohn_question_sections_plan(design, allocation_index, scope, stimulus_id = NULL)` | Returns ordered entries plus source-bound manifest. Absent layout returns the original question entries with null metadata/manifest. |
| `.brohn_question_sections_plan_validated(design, allocation_index, scope, stimulus_id, design_hash, sections_hash)` | Internal compiler-only path after full validation; consumes source hashes computed once so hundreds of stimulus contexts do not repeatedly hash/validate the whole study. Output is byte-identical to the public plan. |
| `brohn_clone_question_sections(config, question_map)` | For a validated source config, creates new section/group IDs and remaps every question through an explicit, unique old-to-new map. The caller validates the completed cloned design. |
| `brohn_question_sections_add(design, question)` | Returns a validated new design. If enabled, appends one fixed group to the final fixed same-scope section; if that last section shuffles or does not exist, creates a fixed tail section. Absent sections remain absent. |
| `brohn_question_sections_remove(design, question_id)` | Returns a validated new design, pruning empty groups/sections. Rejects dangling logic/scale references through the existing base validator. No automatic cascading deletion. |

Load the new module after core; scale/task validators must be available before
validating designs that use those extensions, as they are today. This module
validates the base design with only `questionnaire_sections` removed from a copy,
preventing recursion once core delegates section validation back to it.

Required shared integration hunks, owned by root:

1. Add `questionnaire_sections` to the optional design field list; when the field
   is present, require this module and validate it, including explicit null.
2. In `append_questions`, obtain the plan once for that scope/stimulus. Iterate
   its entries, preserving the existing option-assignment operation and question
   step fields. Attach only non-null sibling metadata. Append only non-null
   manifests to a new optional protocol `questionnaire_assignments` array. An
   absent config must not add empty fields or change old protocol JSON.
3. In full clone, call `brohn_clone_question_sections` after the question map is
   available and before final validation. Portable design import/export retain
   config; they do not copy any participant assignment or response.
4. Use the add/remove lifecycle helpers for ordinary question commands. Changes
   to scope, logic, membership or scale keys must pass full design validation;
   autosave must never silently regroup a saved instrument. UI operations still
   need current draft/study/question identity checks and explicit Save/Cancel.
5. Display named section/group context and realized-order review from frozen
   metadata, while leaving the existing receiver cursor, hidden-step semantics,
   scale assessment IDs and phase boundaries intact. New section labels do not
   require a separate timed or response step.

## Evidence and explicit unfinished work

The [66-check pure regression](../../tests/platform-question-sections.R) passes.
It includes twelve allocations across before, two after-each stimulus contexts
and end, checked against an [independent Python hash/anchor oracle](../../tests/fixtures/question-sections-oracle.py).
It also checks fixed slots, group adjacency, nested dependencies, unsafe
permutations, legal earlier anchors, instrument spans and key-order differences,
malformed/duplicate/missing membership, empty designs, context bounds, source
hashes, typed records, JSON transport, targeted lifecycle operations and section
identity remapping. Original fixtures contain no participant data.

These pure checks are not full compiler, participant, ZIP or browser claims.
The section-clone unit fixture remaps its own nested rules exactly so it can test
the new section mapper in isolation. It also exposed a **separate existing full
clone defect**: core's `rule$rule` lookup partially matches `rule$rules` for an
AND/OR node, adding an unsupported field. The original real
`brohn_clone_design(brohn_sections_fixture())` probe fails with “Logic has
unsupported fields: rule”. Root subsequently fixed the exact lookup and reported
20 passing [connected integration checks](../../tests/platform-question-sections-integration.R),
including full nested clone, real ZIP, receiver and saved worker evidence. That
separate correction was not masked by the section mapper's unit fixture.

## Researcher draft editor

[The editor module](../../R/platform-question-sections-views.R) exposes
`brohn_question_sections_ui(design)` and
`brohn_install_question_sections_ui(input, output, session, current, state, capture, update_study, attempt, message)`.
Root installs it after the normal question capture function. The returned reactive
`context()`/`design()` are available to scoped server tests; persistence remains
the application's existing study revision-CAS function.

Enable opens an all-fixed draft without saving. Edit opens the exact current
config. The ordered list shows section scope, fixed/variable policies, named
groups and every member question. A selected section/group has name and placement
fields and keyboard-operable up/down commands. Whole groups can move to another
same-scope section or become a new named section. Empty source sections are
pruned; individual questions are never split out of a dependent/instrument group.

An explicit whole-group assessment-placement action updates every member question
and any fully contained scale scope, preserving both authored member order and
the original scoring-key list. It moves into a fixed tail at the chosen scope.
Invalid scope crossings show the named group and an explanation to keep its
placement or revise dependent logic/scale design first. Unsupported structural
controls are disabled with visible reasons; direct stale/invalid commands are
also rejected. A failed operation leaves the draft unchanged, including pending
name changes that would otherwise have been applied with that operation.

Names/policies are applied explicitly or included when a bound current form is
saved. Selection and valid structural actions preserve pending valid fields.
Forms rerender only after committed draft transitions. Every command binds editor
token/version; selected fields bind the exact node identity. Save additionally
checks current study ID, revision, full hash and Questions-page identity, then
uses the real revision CAS. Navigation, archive, external revision changes, stale
form fields and late commands cannot overwrite another study/draft.

Cancel explicitly invalidates the editor and can still close the current dialog
after a version changes or its underlying study becomes stale. Old-editor Cancel
cannot close a newly opened editor. Flat opt-out is a draft choice with a visible
explanation that it restores the current question registry's per-scope order;
Save is still required. It does not undo earlier explicit scope changes, rewrite
old participant releases or silently reset option-assignment versions.

[The 37-check Shiny regression](../../tests/platform-question-sections-views.R)
passes with real catalog saves and final CAS failures. It covers Enable/Edit,
unapplied fields on Save, names and variation, keyboard group moves, new-section
creation/transfer cleanup, accepted and rejected scope moves, whole-instrument
scope/key preservation, typed answers, flat opt-out/Cancel, token/version/hash/
navigation/archive/external-CAS guards and visible in-modal `role=alert` errors.
Saved typed-code checks compare exact canonical JSON across R integer/double
storage representations; no numerical tolerance is used.

The actual browser journey exposed a rapid type-then-Create defect: a rendered
command retained the old new-section name before Shiny's text debounce settled.
Create/transfer now capture the visible name, destination, pending node fields
and node identity together on the click in `www/question-sections-ui.js`. The
server validates that snapshot against the current editor, version and selected
group before applying the entire operation. It never substitutes a previous
selection or requires a pause after typing. The regression includes an old
scalar/command name with a current click snapshot, an old destination, mismatched
node identity and a different addressed group. The original rapid browser
sequence remains an independent rerun gate.

Before release, execute actual authored grouping/shuffle Save/Cancel and stale
edits, two participant allocations, hidden required follow-ups and typed answers,
resume/receipts, saved protocol/export/reopen, clone/template/ZIP, scale scoring
with unchanged assessment counts, desktop/narrow accessibility and independent
old-release compatibility. Human comprehension, instrument suitability and
physical timing retain their own evidence. Back/edit, section-level branching,
subsets and repeated-exposure occurrence policies remain separate slices.
