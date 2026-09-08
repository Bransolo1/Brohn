# Brohn: reusable implicit-method references

Reviewed 2026-09-08. Select **Greenwald–Nosek–Banaji 2003 IAT D1**, implemented through **IATscores 0.2.8**, as the executable scoring reference, using final-correct response latency. This is an evidence-backed named scoring variant, not a claim that arbitrary categories or Brohn's future runner are validated. Full IAT remains a reference experiment; this does not silently move its roadmap milestone.

## Reference recipe manifest

| Field | Frozen reference value / decision |
|---|---|
| Identity/status | `iat-gnb2003-d1-reference/0.1.0`; numerical reference only; production disabled |
| Question/estimand | Relative association of two declared targets with two declared attributes; participant D, then a separately specified group analysis |
| Protocol | Standard seven-block structure: 20/20/20/40/20/20/40 trials; target classification, attribute classification, combined practice/test, reversed target practice, reversed combined practice/test |
| Ordering | Alternate target/attribute trials in combined blocks; balanced initial combined mapping assignment; persist assignment, category-to-key map and stimulus order |
| Acquisition | Desktop two-key categorization; stimulus onset and first response plus all corrections retained; score latency is onset to final correct response, milliseconds |
| Scored population | Completed task; combined blocks 3/4/6/7 only, including combined practice; no deletion of their initial trials |
| Exclusions/order | Select scored blocks; remove latency >10,000 ms; exclude task if exact fraction <300 ms is >0.10; denominator is remaining scored trials, before any transformation; retain exactly 0.10 |
| Errors/transforms | Retain correction-inclusive error trials; no added penalty, logarithm, <400 ms deletion or bounding |
| Score/denominator | Average the practice and test contrasts: `(mean_B - mean_A)/sd(A concatenated with B)`; sample SD with N−1, separately for each pair; this is not pooled within-condition SD |
| Direction/output | Positive means faster under declared mapping A. Export pair means/SDs, D, original/retained counts, exclusion numerator/denominator, assignment, source hashes and package versions |
| Failure/uncertainty | Missing blocks, missing/nonfinite RT or zero pair SD produce no score. Reliability, group interval and applicability require a separate prespecified analysis; no individual preference bands |
| Remaining runner fields | Pin runner revision, actual stimulus/category manifest and rights, instructions, intertrial interval, timeout/abandonment and practice retry rules before participant use |

The trial structure and D1 distinctions follow the [primary 2003 paper, Tables 1–4](https://faculty.washington.edu/agg/pdf/GN%26B.JPSP.2003.pdf). The selected denominator operationalizes its ordered exclusions explicitly; it is not inferred from rounded package diagnostics.

## Executable reuse and verification

[implicitMeasures 1.0.0](https://CRAN.R-project.org/package=implicitMeasures) offers `clean_iat()` and `compute_iat(Dscore="d1")`, under MIT. Its bundled `raw_data` and `iatdscores` reproduce **162 D1 values exactly**. These expected values are an upstream regression fixture, not independent evidence. The [benchmark](../../../scripts/benchmarks/implicit-reference.R) also compares independent hand calculations for positive/negative contrasts, correction-inclusive errors, slow trials and exact fast-response boundaries. [Machine-readable results](implicit-reference-results.json) record versions and limitations. Package/example data stay outside the repository; no participant rows are exported.

The benchmark reproduces concrete [1.0.0 source](https://github.com/cran/implicitMeasures/blob/1.0.0/R/compute_iat.R) limitations: lines 159–175 calculate `out_fast` without later excluding those tasks; lines 168–171 overwrite flags using successive participant denominators; single-participant slow-trial diagnostics fail at lines 316–317. D4 substitutes errors before calculating SD (250–253, 392–395), unlike original Table 4's ordering. The fixture quantifies that difference; it does not declare every D variant equivalent. A synthetic duplicate bypasses the diagnostics failure only in the benchmark and must never become a production workaround.

[IATscores 0.2.8](https://CRAN.R-project.org/package=IATscores), GPL-2, supplies the preferred independently authored scorer through `RobustScores(P1="none", P2="ignore", P3="dscore", P4="dist", autoremove=FALSE)`. It also matches all 162 reference scores exactly and passes single-participant/error/direction and 10,000 ms boundary fixtures without the duplicate workaround. **29 benchmark assertions pass**, including expected upstream failures. Agreement verifies arithmetic on these inputs, not inferential validity. Explicit `praccrit` and pair mappings are mandatory. Its default automatic exclusion adds a separate minimum-three-correct-responses rule, and it does not implement the required fast-task screen: retain the explicit QC adapter. [API/source](https://github.com/cran/IATscores/blob/0.2.8/R/RobustScores.R).

Both packages and dependencies are installed in `../../work/r-library-implicit-methods`; the app library is unchanged. Run `../../work/native-r/bin/Rscript.exe --vanilla scripts/benchmarks/implicit-reference.R` from the repository root. Deploy only after the adapter enforces the manifest's failure rules, licensing is settled, and runner events satisfy the latency contract.

These are local R function APIs, requiring no paid service or account. [iatgen](https://github.com/iatgen/iatgen) generates Qualtrics surveys rather than running tasks; its CC BY-NC 4.0 code and Qualtrics dependency make it unsuitable as an unrestricted embedded Brohn runtime. A public example is not permission to redistribute its complete task/assets. The 2003 paper also contains a historical commercial-permission notice; package licences alone do not settle that separate question. Record method/material permissions before commercial delivery, without inferring current patent status.

## BIAT denominator resolved at specification level

Freeze `biat-nosek2014-goodfocal-16plus4x20`: one excluded 16-trial warm-up; four 20-trial ABAB/BABA blocks, each beginning with four excluded **target-category-only** trials, followed by 16 alternating target/attribute trials. The earlier preparation wording incorrectly said attribute-only; the implementation review corrected it against Methods and Study 1. Score final-correct latencies. Exclude >10,000 ms, retain errors, then bound 400–2,000 ms; average D from consecutive pairs. **Fast fraction uses original <300 ms latencies among the remaining trials after warm-up/prefix and >10,000 ms removal**: normally 64, not 80 or 96. Study 5 explicitly describes initial removal; Table 8's later recoding must not erase that numerator. Fixture: six fast plus one slow among 64 gives 6/63 before recoding. [Nosek et al. 2014, Methods, Tables 1/2/8 and Studies 1/5](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0110938).

This replaces the vague denominator placeholder with an auditable profile; independent author-data reproduction and stimulus rights remain specific BIAT gates. No examined package exposes this complete BIAT pipeline as a named API.

## Acquisition and AAT reuse

jsPsych is MIT, but the official [`iat-html` source](https://github.com/jspsych/jsPsych/blob/main/packages/plugin-iat-html/src/index.ts) stores **first-response RT** even when forced correction is enabled (lines 221–246). Its correction callback ends the trial without replacing RT. Reuse its presentation/input primitives only after an event adapter proves final-correct timing and preserves first-response accuracy; this is a runner contract test, not new scoring science.

[AATtools 0.0.3](https://CRAN.R-project.org/package=AATtools), GPL-3, exposes `aat_compute()`, `aat_doublemeandiff` and reliability routines. Select one prespecified algorithm and pruning configuration; its menu is not blanket validation. A physical joystick task can distinguish movement initiation, execution and completion; a keyboard response cannot reproduce those physical outcomes. Freeze response relevance, device, zoom/spatial mapping, balanced category×action cells and primary latency separately. [Kahveci et al.'s primary multiverse study](https://pmc.ncbi.nlm.nih.gov/articles/PMC10990989/) demonstrates that preprocessing and latency definitions matter. AATtools can reuse the analysis; it cannot qualify keyboard AAT as physical AAT or supply missing device evidence.
