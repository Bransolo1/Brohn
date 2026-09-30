# Evidence registry and UI integration recommendation

This is an implementation recommendation from the bounded audit. The published `docs/methods/ACADEMIC-EVIDENCE-CONTRACT.md` governs the product requirement. No runtime changes are made here.

Use a common registry that points to the existing distributed execution registries, rather than renaming or merging their scientific contracts. Link each capability, immutable recipe/profile version, analysis option/default and study-template version. The unit of review is a **specific claim about a specific configuration and context**. A method-family card can collect sources without declaring every child option reviewed.

Recommended record fields:

| Field | Purpose |
|---|---|
| `evidence_record_id`, schema/version, revision/hash | Stable, immutable review identity; historical studies retain their original reference. |
| `capability_id`, `recipe_id/version`, `option_path`, admitted values/default | Exact match to execution and UI. Include fixed internal choices, not only visible controls. Computational bounds and scientific recommendations must have separate types. |
| `implementation_ref` | Code/module/provider/model version and hash; engine identity is a dependency, not the evidence decision. |
| `claim` | Outcome/estimand, units, level of analysis, comparison/direction, intended interpretation and explicit nonclaims. |
| `context` | Population, stimulus/task, sensor/model/device, placement, acquisition conditions, language, setting and available support/duration. State what is unknown. |
| `sources[]` | DOI/stable URL, full citation, document type, publication/version/correction date, access date, exact section/table, evidence role, supported claim and limits. Bibliographic pointer, abstract screening and full-text appraisal are different states. |
| `independence` | Author/laboratory/dataset overlap and whether evidence is genuinely independent. Two URLs for one paper count once. A primary algorithm plus independent validation is more informative than two package manuals. |
| `parameter_rationale` | Why this value/range/threshold/baseline/transform is appropriate; distinguish author recommendation, empirical estimate, protocol-specific choice and operational implementation bound. |
| `review_state`, reviewer/date, unresolved questions | Suggested states: discovered, screened, full-text-reviewed, applicability-reviewed, qualified-for-stated-context, disputed, superseded. Never derive qualification automatically from citation count. |
| `validation_receipts[]` | Separate reference arithmetic, software conformance, labelled-data agreement, physical acquisition/timing, psychometric reliability, construct and consumer/predictive validation. Include exact scope and failures. |
| `template_bindings[]` | Exact frozen template fields, prespecified design rationale, planned-vs-observed checks and amendment history. A saved user design is not promoted to a qualified template by cloning. |
| `limitations`, `required_support`, `fallback_outcome` | Meaningful unavailable/descriptive-only states; no hidden substitution or invented score when conditions fail. |

Record the user requirement for multiple suitable academic sources per analytical approach/option/template as a review gate, with applicability and independence examined. Shared general guidance can be referenced by multiple options only where it actually supports the claim; a second unrelated citation must not be added merely to meet a count. Missing adequate evidence stays explicit and produces an implementation/research task.

The design builder should present the research question and intended inference first. A method card can show what is measured, when it is useful, acquisition/design prerequisites, evidence state and a short limitations statement. An expandable evidence view should show sources with role, applicable settings and reviewer status. Parameter controls should distinguish a scholarly recommended starting value from a computational default, show units/support and explain consequential tradeoffs. Avoid scattering implementation details through participant flows.

At study freeze, retain the exact evidence registry revision, method/profile and option values, template source, rationale and deviations. Freeze does not establish external preregistration or expert scientific approval. A new review should not rewrite old recipes, citations, protocols, source data or outputs; new recommendations become explicit new versions and migration choices.

Reports should preserve each measure's own outcome, denominator, missingness, temporal support and uncertainty. Complete methods/citations/limitations belong in connected HTML, JSON and offline exports. Displaying several measures side by side is a useful holistic view; it must not invent a shared psychological composite. Consumer prediction requires a defined target, held-out validation and evidence beyond simple within-sample correlation. [Bigne et al. 2025](https://onlinelibrary.wiley.com/doi/10.1002/mar.70002) supplies a contemporary organizing framework; [Venkatraman et al. 2015](https://scholarship.miami.edu/esploro/outputs/journalArticle/Predicting-Advertising-success-beyond-Traditional-Measures/991032069208202976) illustrates a scoped comparative consumer study.

## Highest-priority audit work

1. Make the three live structural starters visibly distinct from scientifically reviewed method templates. Trace the 5000 ms/500 ms/zero-baseline and seven-point liking starting values to their actual purpose; do not retrospectively call them academically prescribed.
2. Turn existing one-URL task profiles and free-text `settings_source` fields into exact evidence bindings while preserving original source text. Inspect full scorers/compilers and fixed internal choices before claiming option coverage.
3. Close interpretation-sensitive options first: EEG reference/filter/baseline/bands; EDA event/decomposition/threshold rules; RR-vs-NN/PRV and cardiac spectral support; pupil luminance/blink/baseline; face/model-score inference; AOI comparability and repeated-person statistics.
4. Complete capability discovery for implemented audio/fNIRS and advanced/planned routes. Historical preparation status is not current implementation status. Source-level availability, scientific support and end-to-end readiness remain separate.
5. For each context intended for teaching or consumer research, review independent empirical evidence, reliability, measurement confounds, sample/stimulus design and external applicability. Link to the separate `study-design/` audit. Retain explicit gaps instead of giving every modality the same validation badge.

The packet's initial 121-file index is an efficient discovery aid, not a completion denominator. A later exhaustive audit should enumerate every admission branch and visible/fixed option from code, compare UI defaults with normalized worker requests, then track all those records to reviewed source claims and validation receipts.
