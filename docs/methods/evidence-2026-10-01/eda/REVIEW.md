# Independent bounded EDA appraisal review

Reviewed 1 October 2026. No blocking factual or qualification claim was found in the frozen, non-active appraisal. This is a static code and supporting-text review, not execution, empirical validation, an exhaustive literature search, or approval to activate an evidence registry.

The reviewed manifest is `89744419fa33eb43a4074df3a3aace5f06381aaa6f040456f3d88cabb1e56c35`. All five manifest members, five source11 code files and eight installed dependency files match their recorded lengths and SHA-256 values. The source11 manifest is exact. `BINDING.json` retains those 18 file comparisons. No application, frozen packet, scientific source or store was changed.

## Code-to-claim checks

- `physiology.py:99–172,353–441`: continuous 1.0/1.1 fix the cutoff at 0.05 Hz, use relative prominence, separate retained peak count from finite supported amplitude denominator, and use samples/fs for retained duration versus measured endpoints for trapezoidal area. Only explicit continuous 1.1 has the exact-constant raw-description branch. The prose states this correctly.
- Installed `eda_phasic.py:152–158`: tonic and phasic use separate low/high-pass filter calls. The appraisal correctly avoids both deconvolution terminology and a necessary raw-minus-phasic identity.
- `eda_events.py:49–89,169–211,254–319`: event settings require explicit windows, absolute onset-to-peak threshold, relative prominence, overlap policy and selection rule. Complete baseline/response support must refer to the same segment. Detector failure, unsupported onset, eligible zero, selected responder and recovery censoring remain distinct. The stated parser ranges are not presented as recommended scientific settings.
- `eda_events.py:35–36,174–182` and installed `eda_phasic.py:164–175,298–305`: cvx defaults are fixed and checked; cleaning occurs before decomposition; the returned phasic signal is `M*q`. The latent driver `A*q` is not returned or subsequently scored. The 10,000-sample bound is a resource rule. Scaling concerns are explicitly unresolved model/code inference, not an observed defect.

## Supporting-text and independence checks

[Greco et al.](https://www.centropiaggio.unipi.it/sites/default/files/greco2015cvxeda.pdf), equations 7/15 and III.D, support the distinction between reconstructed conductance and driver, and between a subject-fitted tau0 in the original study and fixed wrapper defaults. Figure 1 describes normalized experimental input. This pass read the author manuscript; its exact PDF and extracted text are retained. The appraisal does not portray a method-development paper as independent validation of the Brohn adaptation.

[Boucsein et al.](https://onlinelibrary.wiley.com/doi/10.1111/j.1469-8986.2012.01384.x), sections 3.1–3.2 and 6, support explicit response criteria, amplitude/magnitude denominators, recovery and acquisition/context reporting. The threshold discussion is context-dependent. The appraisal does not convert it into endorsement of every admissible software value.

[Kuhn et al.](https://onlinelibrary.wiley.com/doi/full/10.1111/psyp.14058), abstract and sections 4.1–4.2, support the appraisal's limited comparison and reporting conclusions. Its seven approaches and two datasets do not establish one universally superior method or validate cvxEDA/Brohn. The publisher correction explicitly concerns Table 1 orientation. Independence is appropriately limited to this comparison.

[Bach's primary article record](https://pubmed.ncbi.nlm.nih.gov/25148785/) confirms four of five contrasts and the publication metadata; the [primary manuscript's indexed text](https://pmc.ncbi.nlm.nih.gov/articles/PMC4266536/) confirms the developer conflict. This review could not repeat the complete section-level read: UCL timed out/returned 403, and PMC direct reading was challenged. The exact design-matrix filtering detail therefore remains supported by the author's frozen appraisal, not independently reverified here. Nothing retrieved contradicted it. This limitation is not concealed as a fourth independent full-text reread.

The abstract-only scope for [Benedek and Kaernbach](https://pubmed.ncbi.nlm.nih.gov/20451556/) and [Sjouwerman and Lonsdorf](https://onlinelibrary.wiley.com/doi/10.1111/psyp.13307) is appropriate. No unseen section-level numeric claim or independent-author-group claim is added. Multiple links in REVIEW.json mean context coverage, not multiple independent validations of an exact option.

## Nonblocking precision note for future registry work

The machine file groups related decisions rather than defining a recipe-by-option applicability matrix. For example, `eda-constant-and-missing` lists four recipes although `exact_constant_policy` is exclusive to continuous 1.1; `eda-consumer-design` includes prospective design requirements rather than keys accepted by `settings()`. This is consistent with its non-active, non-exhaustive status and the narrower prose. Before reusing it as an executable registry, explicitly separate implemented input/output keys, derived policy, and prospective study requirements, and assign each option to its exact recipe subset. Do not interpret the current family lists as their Cartesian product.

All 12 option families remain `qualified=false`; top-level registry activation and scientific qualification remain false. The appraisal does not endorse a universal five-second EDA protocol, a default algorithm winner, or a liking/emotion/purchase score. No amendment to the frozen packet is required for this bounded appraisal.
