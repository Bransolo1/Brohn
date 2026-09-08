# SC-IAT implementation contract

Read-only audit, 8 September 2026. No product source or installed package changed. This narrows the SC-IAT branch of [the broader delivery audit](NEXT-PROTOCOL-DELIVERY-AUDIT.md), rather than replacing its questionnaire priorities.

## Decision and evidence status

Keep the prepared **correction-inclusive Millisecond variant** as the first candidate. Its actual current source resolves the previously unspecified category quotas, score inputs, direction and fast-response denominator. It does **not** establish an already qualified Brohn implementation. Vendor-runtime numerical replay and feedback/sampling semantics remain specific acceptance gates. Do not silently switch to the original Karpinski–Steinman procedure or call the existing full-IAT reducer with relabelled blocks.

The current [official manual](https://www.millisecond.com/library/v7/iat/sc_iat/singlecategoryiat/singlecategory/singlecategoryiat.manual), last modified 25 November 2025, distinguishes its required error correction and unrestricted response period from the original response-window/error-penalty procedure. It describes four measured blocks, excludes practice from D, uses E/I and a 250 ms pretrial pause, and defaults the optional speed reminder to off. The original paper is [Karpinski and Steinman, 2006, DOI 10.1037/0022-3514.91.1.16](https://pubmed.ncbi.nlm.nih.gov/16834477/). Its accessible publisher preview did not include the full methods in this audit; later adaptations must not be mistaken for those missing pages.

The [official v7 archive](https://library.millisecond.com/v7/iat/sc_iat/singlecategoryiat/singlecategory/singlecategoryiat.iqzip), linked by the [vendor catalogue](https://www.millisecond.com/library/sc_iat), was fetched and read **in memory only**, without executing or retaining vendor code or materials:

| Evidence | Observed identity |
| --- | --- |
| Archive | `singlecategoryiat.iqzip`, 7,585 bytes |
| Archive SHA-256 | `42dd20fe0ff9260f891253875bbdce3a8dc62ceb58b87ceaf3def860eddf144e` |
| Sole source member | `singlecategoryiat.iqjs`, 37,869 bytes |
| Member SHA-256 | `32f5084e96c7640cabebeda70816d2a6ab842a841d99fee103c55da071db2ed7` |
| Source landmarks | Expressions 460–476; trial definitions 650–742; task blocks 758–819; assignments 846–875 |

The archive is proprietary reference material, not a new Brohn dependency. Implement original code and original/reviewed materials; a downloadable vendor example is not an open-source redistribution licence. A changing v7 URL is insufficient identity: retain the hashes and actual runtime build in any subsequent reference receipt.

## Frozen procedure candidate

Proposed identity: `sciat-ms7-corrected-source/1.0-candidate`; **not registered or selectable today**. Preserve the old `sc-iat-ms-corrected/0.1-draft` as preparation lineage. Activation requires the gates below; timing or scoring changes require another named revision.

Let T be the single target, P the declared positive attribute and N the declared negative attribute. P stays on E; N stays on I. Mapping A joins T with P; mapping B joins T with N. Order is A then B or B then A, assigned once and retained. Do not borrow full-IAT target/attribute alternation or add a dummy second target.

| Mapping phase | Trials | T | P | N | Correct E / I | Scored |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| A practice | 24 | 7 | 7 | 10 | 14 / 10 | No |
| A test | 72 | 21 | 21 | 30 | 42 / 30 | Yes |
| B practice | 24 | 7 | 10 | 7 | 10 / 14 | No |
| B test | 72 | 21 | 30 | 21 | 30 / 42 | Yes |

These are source-derived quotas, not equal-category sampling. The source also inserts instructions before each practice and each test, outside the 192 measured trials. Category selection uses a weighted no-replacement pool; separate exemplar selection must be retained. [Official trial-selection semantics](https://www.millisecond.com/support/docs/current/html/language/attributes/trials.htm) establish weighted block counts. They do not justify forcing each arbitrary 24-trial subsection of a 72-trial block to have identical quotas. The text-item default is no replacement, but pool reset details still need a reference trace: [select](https://www.millisecond.com/support/docs/current/html/language/attributes/select.htm), [resetInterval](https://www.millisecond.com/support/docs/current/html/language/attributes/resetinterval.htm).

The script requests 150 ms error feedback and 150 ms correct feedback. Do not collapse those displays into an intertrial blank. [responseMessage](https://www.millisecond.com/support/docs/current/html/language/attributes/responsemessage.htm) and [correctMessage](https://www.millisecond.com/support/docs/current/html/language/attributes/correctmessage.htm) define their duration, but do not fully answer how correction input during feedback is handled by this runtime. Qualify that sequence before choosing browser acceptance rules. Keep stimulus onset, first key, every correction, terminal correct key, feedback onset/offset and next pretrial/onset distinct. Score latency ends at the correct key; subsequent success feedback is not extra response time.

No scientific response deadline is defined for this variant. Brohn can have an explicitly documented operational abandonment ceiling, but reaching it interrupts the task and retains evidence; it must not manufacture a 1,500 ms omission trial or continue as a valid completed task. Do not silently adopt the existing 30,000 ms constructor value as a source-defined setting. The speed reminder remains off for this candidate. Researcher presentation/review can be accessible; changing the timed task's physical keyboard, feedback or stimulus presentation needs its own procedure evidence.

## Exact scoring separation

The pinned source appends test final-correct latencies of at most 10,000 ms to its mapping lists and combined list. Initial errors remain represented by their correction-inclusive latency; no additional 400 ms is added. There is one contrast, not separate practice/test D scores:

```text
R_A = final-correct test latencies in A, retaining t <= 10000 ms
R_B = final-correct test latencies in B, retaining t <= 10000 ms
D_reference = (mean(R_B) - mean(R_A)) / vendor_SD(R_A concatenated with R_B)
fast_numerator = count(final-correct test latency < 300 ms)
fast_denominator = count(all presented/completed test trials)  # 144 for a complete task
fast_flag = fast_numerator / fast_denominator > 0.10
```

The fast list is populated **outside** the slow-removal branch. Practice contributes to neither count. Corrected errors use final-correct, not first-key, timing for this flag. The source exposes a suggested-exclusion flag while still calculating D; an eventual Brohn eligibility overlay must be named separately, with the reference result/diagnostics retained rather than falsely attributed to vendor automatic exclusion. No vendor verbal preference bands should enter the participant experience.

**Remaining numerical gate:** the source now calls `list.standardDeviation`; its [official documentation](https://www.millisecond.com/support/docs/current/html/language/properties/standarddeviation.htm) does not specify N versus N−1 normalization. It also documents conversion of nonnumeric items to zero and empty-list zero; Brohn must reject malformed measurement input and report insufficient support instead of adopting that missingness behavior. Do not infer a current runtime's denominator from an older forum formula or the name “D”. Require a tiny runtime output receipt that distinguishes both normalizations and includes unequal retained mapping sizes. Then freeze the exact expanded formula. Until that receipt exists, `vendor_SD` above is a resolved function binding, not a verified R formula.

Useful original arithmetic probes, calculated without the vendor engine:

- A = `[400,600]`, B = `[600,1000]`: means 500/800, total centered sum of squares 190,000. N−1 yields SD 251.66114784235833 and D 1.1920791213585393; N yields SD 217.94494717703367 and D 1.3764944032233706. A reference fixture must select one, not tolerate both.
- Fourteen fast plus ten slow among 144 test trials: the specified fast fraction is 14/144, below 0.10. Using the post-removal 134 denominator incorrectly flags the task. Fifteen/144 flags it. Exactly 10,000 ms is retained; a larger finite latency is removed.
- First wrong key at 200 ms and final correct at 500 ms contributes 500 ms and is not a fast trial. Add no second error penalty. Practice-only changes leave test D and the fast counts unchanged.
- Missing pairing, interrupted correction, unknown trial, duplicate trial, nonfinite latency, zero variance or insufficient SD support yields an explicit unavailable result. Do not clamp a score, fill a missing time with zero, or derive a task score from an unfinished run.

The numerical probes are future acceptance oracles, not a new claim of vendor-output replication.

## Existing reuse does not replace that gate

Installed `implicitMeasures` **1.0.0** includes `clean_sciat()` and `compute_sciat()`. Its local namespace and SC-IAT vignette were read with the existing preparation and restored core libraries; nothing was installed or changed. [Versioned upstream source](https://github.com/cran/implicitMeasures/blob/1.0.0/R/compute_sciat.R) is a separate primary software reference.

Code inspection shows a different contract: explicitly named nonresponses and latencies below 350 ms are removed; errors receive 400 ms plus a retained block mean that includes error latencies; SD uses correct retained responses; its sign is mapping A minus B. Accuracy below .75 is flagged, not removed. Slow-latency diagnostics do not themselves remove slow trials. The `cond_ord` comparison uses capitalized names after building lowercase names, so an order label needs an independent check. These are inspection findings, not newly executed package benchmark results. The existing 162-value IAT reference agreement does not qualify this SC-IAT path.

This package could anchor a separately named imported original-style recipe after paper/source/fixture agreement, but cannot score the prepared correction-inclusive vendor protocol. Keep deadlines, error penalties, SD populations and ordering conventions separate. Do not combine a convenient package function with another provider's task presentation and call the result a validated SC-IAT.

## Connected Brohn implementation seams

| Layer inspected | Reusable behavior | Required SC-IAT work |
| --- | --- | --- |
| `R/platform-methods.R` profiles/new/validate | Versioned profiles, immutable materials, explicit origin/rights and control rationale | Exactly three category roles; no target B; source binding; fixed quotas/order/feedback/score settings; explicit operational-abandonment policy. Existing constructor/settings and two-exemplar minimum are Brohn constraints, not evidence of source adequacy. |
| `brohn_task_compile()` | Stable trial IDs, seeded realized sequence and allocation index | Dedicated weighted three-category compiler and four measured blocks; preserve the source's attribute key side and A/B pairing assignment. Existing combined alternation and additional side allocation must not leak into this profile. |
| `R/platform-core.R` | Frozen `design.blocks` task compilation and clone remapping | Keep its task route; validate a candidate fully before release. Clone/export/import must remap identities without changing roles, settings, materials or source binding. |
| `www/participant/tasks.js` | Preload, trusted physical keys, first/corrected response journal, clock instance, held/repeated-key handling, interruption | Add an explicit supported profile and three-category labels; observe pretrial and finite feedback phases. Current wrong feedback remains until correction, correct feedback is absent, and the existing blank interval is not equivalent. Preserve untimed instruction checkpoints; no timed-trial replay on reload. |
| `R/platform-task-delivery.R` | Frozen onset/key/outcome replay and exactly-once outer journal | Validate any added feedback events/durations and their clock/order relationship; terminal RT must agree with the retained key. Reject forged feedback, foreign materials/blocks and continuation after interruption. Do not relax existing profiles. |
| `brohn_task_score()` / jobs | Per-run immutable task result and queued report publication | New scorer and explicit QC counts; do not route through `brohn_iat_d1()`, which requires Ap/At/Bp/Bt and has a different fast denominator. Pin source/runtime/adapter versions in report processing identity. |
| Tasks authoring / result views | Category/material editing, rights, sample origin, saved report shell | One concise “single target + two attributes” editor; visible mapping/count preview, control rationale and settings receipt. Raw timestamps stay out of the routine authoring screen. Result shows direction, paired means/SD/support/errors/flag and access to complete evidence. |
| Data import and cohort analysis | Durable source import, study revision binding and report storage | No dedicated implicit importer currently exists. Add a reviewed full-trial contract; do not reuse the questionnaire/MaxDiff mapping or pool trial rows as people. This is part of a completed commercial slice, not an optional later manual spreadsheet step. |

Proposed task source receipt fields are `procedure_id`, `procedure_source_url`, `procedure_source_sha256`, `reference_runtime_build`, `scorer_binding_id`, `scorer_reference_receipt_hash`, and `material_manifest_hash`. Keep them in the registered profile/provenance contract. Per-study authors choose reviewed category labels/materials, study rationale, language, origin/rights and seed; they do not edit source-defined trial ratios as an ordinary convenience setting. Exact geometry/appearance, exemplars and sampling-reset policy must be explicit before publishing a research template. No new fields are implemented by this audit.

## Minimal import, report and researcher QA

1. **Source qualification:** obtain a licensed/reference-runtime receipt for the pinned source, with original synthetic input values only. Check SD normalization, unequal retained group sizes, both orders, exclusions, feedback/correction timing and exemplar pool reset. Retain raw output and hashes. Reference-implementation agreement and independent arithmetic must be separate assertions.
2. **Author/reuse:** create a one-target consumer task with original fictional product exemplars and an explicit comparison rationale. Review the 192-trial layout and two assignments; save/cancel; clone; save template; export/reimport design; reopen in a fresh session. Verify exact semantic/source identity, valid remapped references and sample-origin preservation. Unknown profiles, extra targets and altered quotas fail before release.
3. **Collect:** two real browser sessions receive opposite initial pairings. Verify all category/key quotas and frozen realized materials. Exercise an initial error and correction, held/repeated keys, an instruction-boundary reload, timed focus loss, withdrawal, offline retry, lost acknowledgment and actual IndexedDB failure. Require durable receipts and one terminal event per trial. Do not shorten the source task to make its acceptance run quicker; small component probes stay separately labelled.
4. **Score:** run real saved jobs on the retained journal. Compare all intermediate counts/means/SD/D with original oracles and the source receipt. Include incomplete and zero-support negatives. Display raw-versus-eligible status, initial-error and correction support, fast numerator/denominator, slow removals, direction and realized assignment; no individual emotion, preference-strength or purchase prediction labels.
5. **Import/export:** export every original trial with study/task/profile/design hashes, participant-linkage declaration, run/session/repeat-task identity, allocation, trial/block/material/category IDs, mapping, practice/test flag, first/final time, accuracy, outcome and origin. A canonical Brohn bundle retains the full key/phase journal. An external CSV/TSV import explicitly maps these identities and timing semantics; a vendor file with only final RT must not acquire invented first RT or key history. Reject mixed hashes/profiles/origins, duplicate exposures, incomplete pairs and wrong counts, preserving the source and row reasons. Reimported scores must match the original saved report exactly; arithmetic tolerances must not hide serialization loss.
6. **Consumer report:** report task administrations and linked people separately. Repeated administrations need an explicit repeat policy and cannot create extra independent participants. An optional explicit liking question remains an independent measure; any correlation/condition contrast requires a reviewed participant/exposure join, compatible procedure/material definitions and prespecified estimand. Test full CSV/JSON/offline HTML downloads, immutable bytes after reopen, narrow-screen numeric access and axe. Keep the main result easy to read and disclose support through expandable detail.

## Research-fit constraints

The opposite attribute pairing supplies the within-task comparison; it does not create a matched control product or a causal experimental control condition. If a researcher is comparing packaging or an intervention, author that condition/randomization separately. Explicit liking order may affect context, so store its sequence relative to the task. Record language, exemplar familiarity/ambiguity, visual properties, response side, target exposure imbalance, practice/order and keyboard/browser timing as possible design or method influences. These are review requirements, not automatically estimated corrections.

A single target still has two attribute reference categories; do not describe the result as an absolute, context-free preference. A correct classification can reflect knowledge of task categories. Reliability, construct fit and predictive usefulness require evidence for the actual materials/population/procedure; scores from trials alone cannot supply that evidence. The safe accessible experience is fewer repeated setup decisions with visible, frozen method choices—not an unlabelled shortened task or a generic emotion score.

## Audit snapshot and remaining gate

Inspected product hashes (SHA-256):

```text
R/platform-methods.R          06f3af8a1157d39105712be768a44da5175f6b718dc50b7ce8de1f71460a476c
R/platform-task-delivery.R    de00579d46c7fe702c3d9ef633b9f9786c940efe57840d4b3c0f19b0b70d5636
www/participant/tasks.js      05b2f810b335f8d677a8884bc8ace5401989064bddddbdf8765e1d22c24e01de
R/platform-core.R             d8d9aa19aa5bd66073771c56a148ab95bce0ab570b231dc8be7bd665250c24a9
R/platform-task-views.R       0cbc36f43e2d7c5bbde81cd5dd179cb28f45953e6da3011dcf1a26e00ab1054a
R/platform-jobs.R             a3a3fe5118474b4fce0730fbdfc3ebd28a11d16119177205432c31bacbb4da7a
```

No SC-IAT implementation, browser execution, vendor runtime, scientific worker or new package regression was run here. The audit closes **source access, quota, source-list membership, contrast sign and fast-denominator ambiguity**. It leaves **runtime SD normalization, feedback/correction acceptance, sampling-reset trace and source-output replay** as concrete qualification work before this candidate can claim analytical compatibility. Authoring, collection, import/reuse and commercial report acceptance above remain implementation work.
