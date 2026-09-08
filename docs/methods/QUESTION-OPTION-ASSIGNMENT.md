# Questionnaire option assignment

Implemented domain slice, 8 September 2026. This fixes the allocation omission
identified in the [protocol delivery audit](../qa/NEXT-PROTOCOL-DELIVERY-AUDIT.md).
It does not introduce question-order randomization, questionnaire sections,
participant Back navigation or statistical counterbalancing.

## Frozen policy and compatibility

Questions retain the existing `randomize_options` boolean. When it is false,
options remain in their exact authored order, irrespective of assignment policy.
The optional `option_assignment` field selects a versioned algorithm when true:

| Value | Meaning |
| --- | --- |
| `participant-sha256/1.0` | Deterministic participant-specific option permutation, scoped to the question and its stimulus assessment. New `brohn_question()` objects explicitly carry this version. |
| `legacy-timeline-r/1.0` | Original timeline-position-seeded R shuffle. It does not include participant allocation. |
| Field absent | Exactly the original legacy algorithm; no automatic migration on validation, compilation, reading or publication. |

An explicit null, unknown version or non-scalar policy is rejected before release.
The field is an optional, self-versioned extension of `brohn-design/1.0.0` question
records; it does not reinterpret the existing boolean. Typed option IDs, labels
and values are preserved as complete records. Numeric zero, boolean false and
text `"0"` remain different answers.

Existing deployments retain their immutable original design JSON and hash. New
participants joining those old releases therefore still receive their historical
policy, even after the current study draft is upgraded. Existing run protocols
retain their already realized options; Start retries and reconnects return that
saved protocol rather than recompiling it. No release, protocol, catalog or hash
is rewritten by this change. The legacy R shuffle remains unchanged; its existing
dependence on R RNG implementation is not newly qualified by this patch.

`brohn_upgrade_option_assignment(design, question_ids = NULL)` is a pure draft
operation. It validates the design and changes only selected questions whose
`randomize_options` is true. `NULL` selects all questions; a character vector
selects exact, unique existing IDs; an empty character vector changes nothing.
It preserves fixed questions and is hash-stable when repeated on migrated items.
The caller must persist an explicitly reviewed new draft revision using the
ordinary stale-study/revision checks. Publishing that revision creates a new
release; the helper never upgrades an old release in place.

## Deterministic assignment contract

For every offered option, construct this canonical JSON object:

```json
{
  "allocation_index": "7",
  "option_id": "choice1",
  "question_id": "q-after",
  "schema_version": "brohn-option-assignment/1.0",
  "scope": "after_each",
  "seed": "104729",
  "stimulus_id": "stimulus-a"
}
```

The seed and allocation index are bounded whole integers encoded as ordinary
base-10 strings without grouping or scientific notation. Before/end assessments
use JSON null for `stimulus_id`. Keys are sorted and compact JSON is UTF-8 encoded
using the existing Brohn canonical serializer. Compute the full SHA-256 digest
for each object. Sort options by ascending lowercase hexadecimal digest, using
ascending ASCII option ID only as a deterministic collision tie-break. Option,
question and stimulus IDs already satisfy the ASCII ID validator.

The resulting permutation depends on seed, allocation, immutable question/scope,
stimulus identity and offered option IDs. It does not depend on title, prompt,
option label/value, unrelated earlier questions, instructions, timing intervals,
global R RNG state/kind or mutable timeline position. Changing a source option's
code or label still changes the design hash; assignment stability does not imply
that its scientific meaning remained the same. Clone/import creates fresh
question/stimulus IDs and may therefore produce different assignments in the new
study. Its policy, source materials, typed values and lineage remain retained.

The current compiler offers each unique stimulus once. `after_each` assignments
are independent question/stimulus contexts: reordering the stimulus timeline does
not change the order assigned to that same participant and stimulus. Different
stimuli may receive different orders; the algorithm does not promise that their
permutations differ. There is currently no repeated occurrence of one stimulus ID.
A future repeated-exposure compiler must define a versioned occurrence identity
or explicitly preserve one order across repetitions before enabling that route;
it must not use timeline length as an unstable substitute.

This is deterministic randomization, **not guaranteed counterbalancing**. Two
participants can receive the same permutation; a finite sample need not have
equal position counts. Allocation index refers to a reserved run within a
release, not proof of a distinct person. Repeat-person linkage remains separate.
The design seed is public protocol metadata and is not an enrollment secret or
an anti-prediction security mechanism.

## Researcher integration contract

Keep the existing Randomize control. A newly authored randomized question can
explain: “Option order varies by participant and is saved for resume.” For an
older randomized question, explain that its old policy uses shared timeline
positions and offer an explicit “Use participant-specific order” action. Bind
that action to current study/draft/question identity and question content hash,
then call the pure helper for that question and save a new draft revision.

Checking Randomize on a previously fixed older question can explicitly opt that
question into the new policy as part of the same authored change. Merely opening
or saving an already randomized old question must not migrate it. Ordered rating
anchors should normally remain ordered according to the instrument: offer no
automatic scale-anchor randomization or claim that shuffle is always preferable.
Existing single-item and multi-item scoring validation continues to use typed
codes, not display positions.

No participant renderer or receiver changes are needed: they consume the exact
ordered `step.question.options` in the frozen protocol. The saved protocol is the
authoritative evidence of the offered order; a design-only portable ZIP contains
policy and source order rather than participant assignments. Reports that expose
offered-order evidence must use each saved run's protocol, not recompile from the
latest draft.

## Executed evidence and remaining review

[The 56-check focused regression](../../tests/platform-question-assignment.R)
passes against real SQLite/catalog operations and the current delivery API. It
includes:

- Four assessment permutations for each of twelve allocations compared exactly
  with a pinned [independent Python standard-library oracle](../../tests/fixtures/question-assignment-oracle.py),
  including mixed typed codes. The prespecified twelve-allocation fixture has
  varied orders; this is not a population balance test.
- Full pre-change legacy protocol JSON snapshots for two allocations; old-release
  new starts after draft upgrade; idempotent Start/client replay; actual store
  close/reopen; no source mutation or silent migration.
- Independence from unrelated questions/instructions/baselines, stimulus display
  order and ambient R RNG kind/state; fixed options remain authored; after-each
  assessments bind to their exact stimulus IDs.
- Rejected null/unknown/malformed policies and invalid/unknown migration targets;
  targeted and no-op migration; real `.brohn-study.zip` export/import preserving
  policy, typed values and valid new identities.

The legacy fixture was captured before the compiler edit and contains the old
compiler SHA-256 and R RNG/version metadata. Its generated original materials
contain no participant data. Expected new permutations were generated with Python
`hashlib`/`json`, independently of the R compiler; the R test reads the pinned
artifact rather than deriving its expected order with the implementation.

The existing core, participant delivery, portable-design and questionnaire-scale
regressions also pass (109, 56, 90 and 74 checks respectively). Actual researcher
UI migration and browser display/reload/
export/reuse are a separate assigned QA journey; do not treat these domain/API
checks as that browser or human-comprehension evidence. Broader questionnaire
flow, repeat-occurrence semantics and scientific suitability of a study's option
randomization remain outside this bounded fix.
