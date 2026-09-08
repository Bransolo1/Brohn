# Questionnaire display logic authoring

The visual builder edits Brohn's existing `show_if` rule structure. Researchers
can combine **all** (AND), **any** (OR) and **not** groups with earlier-answer
conditions. A readable preview and an ordered tree show the same saved rule.
Native buttons move, select and remove conditions without dragging.

Conditions support answered, scalar equality/inequality, numeric thresholds and
membership in multi-answer responses. Choice selectors use actual option IDs to
retrieve their typed stored values. Numeric `1`, text `"1"`, boolean `false` and
numeric `0` remain distinct. Ranking membership uses recorded option identities,
not their separate reporting codes. Matrix membership means any row has that
answer; allocation membership means any allocated amount equals the number.
This rule format does not provide matrix-row-specific, rank-position-specific,
or allocation-option-specific predicates.

Unanswered responses do not satisfy equality, inequality, membership or numeric
comparisons. NOT reverses its child's entire result, including missing-answer
outcomes; the editor explains this and offers an explicit Has an answer condition.
Numeric equality is exact in both R and the participant renderer.

Available questions follow the compiler's earlier-question and placement rules:

| Target placement | Earlier answers available to its rule |
| --- | --- |
| Before stimuli | Earlier before-stimuli questions |
| After each stimulus | Earlier before-stimuli questions plus earlier after-each questions for that same stimulus |
| End of study | Earlier before-stimuli and end-of-study questions |

Information screens have no response and are excluded from new answer-condition
choices. Imported rules are retained. A saved operation incompatible with its
current answer type remains visible and unchanged until deliberately repaired;
opening or navigating the editor does not silently substitute another operation.

## Draft and publication behaviour

Opening the modal first captures the current valid study draft. Rule edits stay
inside the modal until **Save display logic**. Saving also applies the current
condition's field values, then creates one study revision. Cancel discards the
draft and disables late Save messages. Tree actions carry editor and draft
identities; old controls cannot address a reordered tree. A changed study or
archived study prevents stale publication. Existing participant releases retain
their frozen rules.

The visual editor accepts at most 200 rule nodes. The existing compiler limits
still apply: fewer than 12 nesting levels and 1 to 20 children in AND/OR groups.
An oversized imported rule remains saved and produces an explicit editor limit
message; its nodes are not silently omitted.

## Integration

- Source `R/platform-question-flow.R` with platform helpers.
- Source `R/platform-question-flow-views.R` with UI helpers.
- Use `brohn_question_logic_summary_ui(design, question)` in each question card.
- Install `brohn_install_question_flow_server(input, output, session, current,
  state, capture, update_study, attempt, message)` after the parent capture helper
  exists.
- Remove the former `q_logic_*` / `q_equals_*` capture branch, so stale controls
  cannot overwrite a saved compound rule.

## Evidence

`tests/platform-question-flow.R` passes 36 checks covering typed comparisons,
scope availability, compiler preservation, imported rule preservation, tree
mutations, actual Shiny draft/save/reorder/cancel commands, stale controls,
concurrent edits and archived studies. The core's exact typed comparison change
also passes all 109 core and 56 participant-delivery checks.

The separate actual-browser regression `tests/participant-logic.mjs` passes 11
checks: two completed saved runs verify near-equal numbers and mixed
number/text/boolean membership against recorded participant step/skip events.
These generated fixtures exercise execution and authoring behaviour rather than
participant research outcomes.
